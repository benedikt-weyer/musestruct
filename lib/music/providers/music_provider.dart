import 'package:flutter/foundation.dart';
import 'dart:async';
import '../models/music.dart';
import '../../core/models/api_response.dart';
import '../services/music_api_service.dart';
import '../../core/services/audio_service.dart';
import '../../core/services/audio_service_handler.dart';
import '../../core/services/app_config_service.dart';
import '../../queue/providers/queue_provider.dart';
import '../../playlists/services/playlist_api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'saved_tracks_provider.dart';
// import '../../core/services/spotify_webview_player.dart'; // Disabled
// import '../../core/widgets/spotify_webview_widget.dart'; // Disabled

class MusicProvider with ChangeNotifier {
  final AudioService _audioService = AudioService();
  // final SpotifyWebViewPlayer _spotifyPlayer = SpotifyWebViewPlayer(); // Disabled
  QueueProvider? _queueProvider;
  MusestructAudioHandler? _audioServiceHandler;
  SavedTracksProvider? _savedTracksProvider;
  
  SearchResults? _searchResults;
  bool _isSearching = false;
  String? _searchError;
  
  // Pagination state
  int _currentPage = 1;
  int _itemsPerPage = 20;
  String _lastSearchQuery = '';
  SearchType _lastSearchType = SearchType.tracks;
  bool _lastSearchWasLibrary = false; // Track if last search was library search
  
  // Available page sizes
  static const List<int> _availablePageSizes = [10, 20, 50, 100];
  
  List<ServiceInfo> _availableServices = [];
  String _selectedService = 'server'; // Default to server since it's always available
  List<String> _selectedServices = ['server']; // For multi-service search
  bool _useMultiServiceSearch = false;
  
  Track? _currentTrack;
  bool _isPlaying = false;
  bool _isLoading = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  AudioOutputInfo _audioOutputInfo = AudioOutputInfo();
  Timer? _audioInfoTimer;
  Timer? _backgroundUpdateTimer;
  bool _isUIUpdatesPaused = false;
  
  // Playlist queue support
  PlaylistQueueItem? _currentPlaylistQueueItem;
  bool _isPlayingFromPlaylist = false;

  // Getters
  SearchResults? get searchResults => _searchResults;
  bool get isSearching => _isSearching;
  String? get searchError => _searchError;
  
  // Pagination getters
  int get currentPage => _currentPage;
  int get itemsPerPage => _itemsPerPage;
  List<int> get availablePageSizes => MusicProvider._availablePageSizes;
  int get totalPages => _searchResults != null 
      ? ((_searchResults!.total / _itemsPerPage).ceil()).clamp(1, double.infinity).toInt()
      : 1;
  bool get hasNextPage => _currentPage < totalPages;
  bool get hasPreviousPage => _currentPage > 1;
  
  List<ServiceInfo> get availableServices => _availableServices;
  String get selectedService => _selectedService;
  List<String> get selectedServices => _selectedServices;
  bool get useMultiServiceSearch => _useMultiServiceSearch;
  
  Track? get currentTrack => _currentTrack;
  bool get isPlaying => _isPlaying;
  bool get isLoading => _isLoading;
  Duration get position => _position;
  Duration get duration => _duration;
  AudioOutputInfo get audioOutputInfo => _audioOutputInfo;
  
  // Playlist queue getters
  PlaylistQueueItem? get currentPlaylistQueueItem => _currentPlaylistQueueItem;
  bool get isPlayingFromPlaylist => _isPlayingFromPlaylist;
  
  AudioService get audioService => _audioService;
  bool get isUIUpdatesPaused => _isUIUpdatesPaused;

  void setQueueProvider(QueueProvider queueProvider) {
    _queueProvider = queueProvider;
  }

  void setSavedTracksProvider(SavedTracksProvider savedTracksProvider) {
    _savedTracksProvider = savedTracksProvider;
  }

  Future<void> playNextTrack() async {
    if (_queueProvider == null) return;

    // Check if we're playing from a playlist queue
    if (_isPlayingFromPlaylist) {
      await playNextTrackFromPlaylist();
      return;
    }

    // Check if there are playlist queue items available
    final currentPlaylist = _queueProvider!.getCurrentPlaylistQueueItem();
    if (currentPlaylist != null) {
      await playPlaylistQueueItem(currentPlaylist);
      return;
    }

    final nextTrack = _queueProvider!.getNextTrack();
    if (nextTrack != null) {
      // Remove current track from queue and play next
      await _queueProvider!.moveToNext();
      await playTrack(nextTrack.toTrack(), clearQueue: false);
    }
  }

  Future<void> seekTo(Duration position) async {
    if (_currentTrack == null) return;
    
    // Check if seeking is supported for this track
    if (!_audioService.isSeekSupported) {
      print('Seeking not supported for ${_currentTrack!.source} tracks on this platform');
      throw UnsupportedError('Seeking not supported for this audio format');
    }
    
    try {
      // Check if the position is valid
      if (position < Duration.zero || position > _duration) {
        print('Invalid seek position: $position (duration: $_duration)');
        return;
      }
      
      await _audioService.seek(position);
      _position = position;
      notifyListeners();
      print('Successfully seeked to: ${position.inSeconds}s');
    } catch (e) {
      print('Error seeking to position: $e');
      
      // Show user-friendly error message
      if (e.toString().contains('GStreamer') || e.toString().contains('LinuxAudioError')) {
        print('Seek failed due to GStreamer/Linux audio limitations. This is a known issue with certain streaming formats on Linux.');
        // Don't update position if seek failed
        return;
      }
      
      // For other errors, still try to update position locally as fallback
      _position = position;
      notifyListeners();
    }
  }

  MusicProvider() {
    _initializeAudioService();
    _loadAvailableServices();
    _loadPageSizePreference();
  }

  void _initializeAudioService() async {
    await _audioService.initialize();
    
    // Listen to player state changes
    _audioService.playingStream.listen((isPlaying) {
      _isPlaying = isPlaying;
      if (!_isUIUpdatesPaused) {
        notifyListeners();
      }
      // Update audio service handler
      _updateAudioServiceHandlerState();
    });

    // Listen to position changes
    _audioService.positionStream.listen((position) {
      _position = position;
      if (!_isUIUpdatesPaused) {
        notifyListeners();
      }
      
      // Update audio service handler periodically (every second)
      if (position.inSeconds != (_position.inSeconds)) {
        _updateAudioServiceHandlerState();
      }
      
      // Fallback completion detection based on position
      _checkForTrackCompletion();
    });

    // Listen to duration changes
    _audioService.durationStream.listen((duration) {
      _duration = duration;
      if (!_isUIUpdatesPaused) {
        notifyListeners();
      }
      // Update audio service handler
      _updateAudioServiceHandlerState();
    });
    
    // Listen to track completion events
    _audioService.completionStream.listen((isCompleted) {
      if (isCompleted && _currentTrack != null && _queueProvider != null) {
        print('Track completed via PlayerState.completed, playing next track...');
        _playNextTrackAfterCompletion();
      }
    });
  }
  
  /// Set the audio service handler for media controls
  void setAudioServiceHandler(MusestructAudioHandler handler) {
    _audioServiceHandler = handler;
    _audioService.setAudioServiceHandler(handler);
    print('MusicProvider: Audio service handler set');
  }
  
  /// Update the audio service handler with current playback state
  void _updateAudioServiceHandlerState() {
    if (_audioServiceHandler == null) return;
    
    final bool hasNext = _queueProvider?.hasNextTrack() ?? false;
    final bool hasPrevious = _isPlayingFromPlaylist && ((_currentPlaylistQueueItem?.currentTrackIndex ?? 0) > 0);
    
    // Check if current track is favorited
    final bool isFavorite = _currentTrack != null && _savedTracksProvider != null
        ? _savedTracksProvider!.isTrackSaved(_currentTrack!.id, _currentTrack!.source)
        : false;
    
    print('MusicProvider: Updating audio service state - HasNext: $hasNext, HasPrevious: $hasPrevious, IsFavorite: $isFavorite');
    
    _audioServiceHandler!.updatePlaybackState(
      playing: _isPlaying,
      position: _position,
      duration: _duration,
      hasNext: hasNext,
      hasPrevious: hasPrevious,
      isFavorite: isFavorite,
    );
  }

  /// Toggle favorite status of current track
  Future<void> toggleFavorite() async {
    if (_currentTrack == null || _savedTracksProvider == null) {
      print('MusicProvider: Cannot toggle favorite - no current track or saved tracks provider');
      return;
    }
    
    final isSaved = _savedTracksProvider!.isTrackSaved(_currentTrack!.id, _currentTrack!.source);
    
    if (isSaved) {
      // Find the saved track to get its ID
      final savedTrack = _savedTracksProvider!.savedTracks.firstWhere(
        (st) => st.trackId == _currentTrack!.id && st.source == _currentTrack!.source,
        orElse: () => throw Exception('Saved track not found'),
      );
      await _savedTracksProvider!.removeSavedTrack(savedTrack.id, _currentTrack!.id, _currentTrack!.source);
      print('MusicProvider: Track removed from favorites: ${_currentTrack!.title}');
    } else {
      await _savedTracksProvider!.saveTrack(_currentTrack!);
      print('MusicProvider: Track added to favorites: ${_currentTrack!.title}');
    }
    
    // Update audio service handler to reflect new favorite status
    _updateAudioServiceHandlerState();
  }

  Future<void> _loadAvailableServices() async {
    try {
      final response = await MusicApiService.getAvailableServices();
      if (response.success && response.data != null) {
        _availableServices = response.data!;
        
        // Update selected services to include server if available
        if (_availableServices.any((s) => s.name == 'server')) {
          if (!_selectedServices.contains('server')) {
            _selectedServices.add('server');
          }
          // If current selected service is not available, default to server
          if (!_availableServices.any((s) => s.name == _selectedService)) {
            _selectedService = 'server';
          }
        }
        
        notifyListeners();
      }
    } catch (e) {
      print('Failed to load available services: $e');
    }
  }

  void selectService(String serviceName) {
    if (_selectedService != serviceName) {
      _selectedService = serviceName;
      // Clear current search results when switching services
      _searchResults = null;
      notifyListeners();
    }
  }

  void toggleMultiServiceSearch() {
    _useMultiServiceSearch = !_useMultiServiceSearch;
    _searchResults = null; // Clear search results when switching modes
    notifyListeners();
  }

  void toggleServiceSelection(String serviceName) {
    if (_selectedServices.contains(serviceName)) {
      _selectedServices.remove(serviceName);
    } else {
      _selectedServices.add(serviceName);
    }
    _searchResults = null; // Clear search results when changing selection
    notifyListeners();
  }

  void selectAllServices() {
    _selectedServices = _availableServices.map((s) => s.name).toList();
    _searchResults = null;
    notifyListeners();
  }

  void clearServiceSelection() {
    _selectedServices.clear();
    _searchResults = null;
    notifyListeners();
  }

  Future<void> searchMusic(String query) async {
    if (query.trim().isEmpty) return;

    _isSearching = true;
    _searchError = null;
    notifyListeners();

    try {
      ApiResponse<SearchResults> response;
      
      if (_useMultiServiceSearch && _selectedServices.isNotEmpty) {
        // Multi-service search
        response = await MusicApiService.searchMusic(
          query, 
          limit: 20,
          services: _selectedServices,
        );
      } else {
        // Single service search
        response = await MusicApiService.searchMusic(
          query, 
          limit: 20,
          service: _selectedService,
        );
      }
      
      if (response.success && response.data != null) {
        _searchResults = response.data;
      } else {
        _searchError = response.message ?? 'Search failed';
      }
    } catch (e) {
      _searchError = 'Search failed: $e';
    } finally {
      _isSearching = false;
      notifyListeners();
    }
  }

  Future<void> searchPlaylists(String query) async {
    if (query.trim().isEmpty) return;

    _isSearching = true;
    _searchError = null;
    notifyListeners();

    try {
      ApiResponse<SearchResults> response;
      
      if (_useMultiServiceSearch && _selectedServices.isNotEmpty) {
        // Multi-service search
        print('MusicProvider: Using multi-service playlist search with: $_selectedServices');
        response = await MusicApiService.searchPlaylists(
          query, 
          limit: 20,
          services: _selectedServices,
        );
      } else {
        // Single service search
        print('MusicProvider: Using single-service playlist search with: $_selectedService');
        response = await MusicApiService.searchPlaylists(
          query, 
          limit: 20,
          service: _selectedService,
        );
      }
      
      if (response.success && response.data != null) {
        print('MusicProvider: Playlist search response data: ${response.data}');
        print('MusicProvider: Playlists in response: ${response.data!.playlists ?? "null"}');
        _searchResults = response.data;
      } else {
        _searchError = response.message ?? 'Playlist search failed';
        // If playlist search fails, create an empty SearchResults with empty playlists
        _searchResults = SearchResults(
          tracks: [],
          albums: [],
          playlists: [],
          total: 0,
          offset: 0,
          limit: 20,
        );
      }
    } catch (e) {
      _searchError = 'Playlist search failed: $e';
      // If playlist search fails, create an empty SearchResults with empty playlists
      _searchResults = SearchResults(
        tracks: [],
        albums: [],
        playlists: [],
        total: 0,
        offset: 0,
        limit: 20,
      );
    } finally {
      _isSearching = false;
      notifyListeners();
    }
  }

  Future<void> searchAlbums(String query) async {
    if (query.trim().isEmpty) return;

    _isSearching = true;
    _searchError = null;
    notifyListeners();

    try {
      ApiResponse<SearchResults> response;
      
      if (_useMultiServiceSearch && _selectedServices.isNotEmpty) {
        // Multi-service search
        print('MusicProvider: Using multi-service album search with: $_selectedServices');
        response = await MusicApiService.searchAlbums(
          query, 
          limit: 20,
          services: _selectedServices,
        );
      } else {
        // Single service search
        print('MusicProvider: Using single-service album search with: $_selectedService');
        response = await MusicApiService.searchAlbums(
          query, 
          limit: 20,
          service: _selectedService,
        );
      }
      
      if (response.success && response.data != null) {
        print('MusicProvider: Album search response data: ${response.data}');
        print('MusicProvider: Albums in response: ${response.data!.albums}');
        _searchResults = response.data;
      } else {
        _searchError = response.message ?? 'Album search failed';
        // If album search fails, create an empty SearchResults with empty albums
        _searchResults = SearchResults(
          tracks: [],
          albums: [],
          playlists: [],
          total: 0,
          offset: 0,
          limit: 20,
        );
      }
    } catch (e) {
      _searchError = 'Album search failed: $e';
      // If album search fails, create an empty SearchResults with empty albums
      _searchResults = SearchResults(
        tracks: [],
        albums: [],
        playlists: [],
        total: 0,
        offset: 0,
        limit: 20,
      );
    } finally {
      _isSearching = false;
      notifyListeners();
    }
  }

  Future<void> searchAll() async {
    // Search all music from server with empty query
    // Reset pagination for new search
    _currentPage = 1;
    _lastSearchQuery = '';
    _lastSearchType = SearchType.tracks;
    _lastSearchWasLibrary = false;

    _isSearching = true;
    _searchError = null;
    notifyListeners();

    try {
      // Use empty query to get all results from server
      final offset = (_currentPage - 1) * _itemsPerPage;
      
      final futures = await Future.wait([
        MusicApiService.searchMusic(
          '', // Empty query for all results
          limit: _itemsPerPage,
          offset: offset,
          service: 'server',
        ),
        MusicApiService.searchAlbums(
          '', // Empty query for all results
          limit: _itemsPerPage,
          offset: offset,
          service: 'server',
        ),
        MusicApiService.searchPlaylists(
          '', // Empty query for all results
          limit: _itemsPerPage,
          offset: offset,
          service: 'server',
        ),
      ]);
      
      final musicResponse = futures[0];
      final albumResponse = futures[1];
      final playlistResponse = futures[2];
      
      // Combine the results
      List<Track> tracks = [];
      List<Album> albums = [];
      List<PlaylistSearchResult> playlists = [];
      
      if (musicResponse.success && musicResponse.data != null) {
        tracks = musicResponse.data!.tracks;
      }
      
      if (albumResponse.success && albumResponse.data != null) {
        albums = albumResponse.data!.albums;
      }
      
      if (playlistResponse.success && playlistResponse.data != null) {
        playlists = playlistResponse.data!.playlists ?? [];
      }
      
      // Use the total from the first successful response, or calculate from results
      int total = 0;
      if (musicResponse.success && musicResponse.data != null) {
        total = musicResponse.data!.total;
      } else if (albumResponse.success && albumResponse.data != null) {
        total = albumResponse.data!.total;
      } else if (playlistResponse.success && playlistResponse.data != null) {
        total = playlistResponse.data!.total;
      } else {
        total = tracks.length + albums.length + playlists.length;
      }

      _searchResults = SearchResults(
        tracks: tracks,
        albums: albums,
        playlists: playlists,
        total: total,
        offset: offset,
        limit: _itemsPerPage,
      );
      
      _searchError = null;
    } catch (e) {
      _searchError = 'Failed to search all music: $e';
      _searchResults = null;
    } finally {
      _isSearching = false;
      notifyListeners();
    }
  }

  Future<void> searchLibrary(String query, {SearchType? searchType}) async {
    if (query.trim().isEmpty) return;

    // Reset pagination for new search
    _currentPage = 1;
    _lastSearchQuery = query;
    _lastSearchType = searchType ?? SearchType.tracks;
    _lastSearchWasLibrary = true;

    _isSearching = true;
    _searchError = null;
    notifyListeners();

    try {
      ApiResponse<SearchResults> response;
      
      // Convert SearchType to string
      String typeString = _lastSearchType == SearchType.tracks ? 'track' 
                        : _lastSearchType == SearchType.albums ? 'album' 
                        : 'playlist';
      
      if (_useMultiServiceSearch && _selectedServices.isNotEmpty) {
        // Multi-service library search
        response = await MusicApiService.searchLibrary(
          query, 
          limit: _itemsPerPage,
          services: _selectedServices,
          type: typeString,
        );
      } else {
        // Single service library search
        response = await MusicApiService.searchLibrary(
          query, 
          limit: _itemsPerPage,
          service: _selectedService,
          type: typeString,
        );
      }
      
      if (response.success && response.data != null) {
        _searchResults = response.data;
      } else {
        _searchError = response.message ?? 'Library search failed';
      }
    } catch (e) {
      _searchError = 'Library search failed: $e';
    } finally {
      _isSearching = false;
      notifyListeners();
    }
  }

  Future<void> searchAllLibrary({SearchType? searchType}) async {
    // Search all library items with empty query
    // Reset pagination for new search
    _currentPage = 1;
    _lastSearchQuery = '';
    _lastSearchType = searchType ?? SearchType.tracks;
    _lastSearchWasLibrary = true;

    _isSearching = true;
    _searchError = null;
    notifyListeners();

    try {
      final offset = (_currentPage - 1) * _itemsPerPage;
      ApiResponse<SearchResults> response;
      
      // Convert SearchType to string
      String typeString = _lastSearchType == SearchType.tracks ? 'track' 
                        : _lastSearchType == SearchType.albums ? 'album' 
                        : 'playlist';
      
      if (_useMultiServiceSearch && _selectedServices.isNotEmpty) {
        // Multi-service library search all
        response = await MusicApiService.searchAllLibrary(
          limit: _itemsPerPage,
          offset: offset,
          services: _selectedServices,
          type: typeString,
        );
      } else {
        // Single service library search all
        response = await MusicApiService.searchAllLibrary(
          limit: _itemsPerPage,
          offset: offset,
          service: _selectedService,
          type: typeString,
        );
      }
      
      if (response.success && response.data != null) {
        _searchResults = response.data;
      } else {
        _searchError = response.message ?? 'Library search all failed';
      }
    } catch (e) {
      _searchError = 'Library search all failed: $e';
    } finally {
      _isSearching = false;
      notifyListeners();
    }
  }

  Future<void> searchBoth(String query) async {
    if (query.trim().isEmpty) return;

    // Reset pagination for new search
    _currentPage = 1;
    _lastSearchQuery = query;
    _lastSearchType = SearchType.tracks; // Default to tracks for combined search
    _lastSearchWasLibrary = false;

    _isSearching = true;
    _searchError = null;
    notifyListeners();

    try {
      // Perform all three searches simultaneously
      late ApiResponse<SearchResults> musicResponse;
      late ApiResponse<SearchResults> albumResponse;
      late ApiResponse<SearchResults> playlistResponse;
      
      if (_useMultiServiceSearch && _selectedServices.isNotEmpty) {
        // Multi-service search
        final futures = await Future.wait([
          MusicApiService.searchMusic(
            query, 
            limit: 20,
            services: _selectedServices,
          ),
          MusicApiService.searchAlbums(
            query, 
            limit: 20,
            services: _selectedServices,
          ),
          MusicApiService.searchPlaylists(
            query, 
            limit: 20,
            services: _selectedServices,
          ),
        ]);
        musicResponse = futures[0];
        albumResponse = futures[1];
        playlistResponse = futures[2];
      } else {
        // Single service search
        final futures = await Future.wait([
          MusicApiService.searchMusic(
            query, 
            limit: 20,
            service: _selectedService,
          ),
          MusicApiService.searchAlbums(
            query, 
            limit: 20,
            service: _selectedService,
          ),
          MusicApiService.searchPlaylists(
            query, 
            limit: 20,
            service: _selectedService,
          ),
        ]);
        musicResponse = futures[0];
        albumResponse = futures[1];
        playlistResponse = futures[2];
      }
      
      // Combine the results
      List<Track> tracks = [];
      List<Album> albums = [];
      List<PlaylistSearchResult> playlists = [];
      
      if (musicResponse.success && musicResponse.data != null) {
        tracks = musicResponse.data!.tracks;
      }
      
      if (albumResponse.success && albumResponse.data != null) {
        albums = albumResponse.data!.albums;
      }
      
      if (playlistResponse.success && playlistResponse.data != null) {
        playlists = playlistResponse.data!.playlists ?? [];
      }
      
      // Create combined search results
      _searchResults = SearchResults(
        tracks: tracks,
        albums: albums,
        playlists: playlists,
        total: tracks.length + albums.length + playlists.length,
        offset: 0,
        limit: 20,
      );
      
      print('MusicProvider: Combined search results - ${tracks.length} tracks, ${albums.length} albums, ${playlists.length} playlists');
      
    } catch (e) {
      _searchError = 'Combined search failed: $e';
      _searchResults = SearchResults(
        tracks: [],
        albums: [],
        playlists: [],
        total: 0,
        offset: 0,
        limit: 20,
      );
    } finally {
      _isSearching = false;
      notifyListeners();
    }
  }

  Future<void> playTrack(Track track, {bool clearQueue = true}) async {
    try {
      _isLoading = true;
      _currentTrack = track;
      notifyListeners();

      // Clear queue if requested (default behavior)
      if (clearQueue && _queueProvider != null) {
        await _queueProvider!.clearQueue();
        _queueProvider!.clearPlaylistQueue();
      }

      // Get stream URL
      
      if (track.source == 'spotify') {
        // For now, show a message that Spotify playback is not available
        throw Exception('Spotify playback is currently disabled. Please use Qobuz tracks for playback.');
      } else {
        // Use regular audio service for other sources (Qobuz, etc.)
        await _playRegularTrack(track);
      }
    } catch (e) {
      _searchError = 'Failed to play track: $e';
      _currentTrack = null;
      notifyListeners();
    } finally {
      _isLoading = false;
    }
  }

  // _playSpotifyTrack method removed - Spotify WebView playback disabled

  Future<void> _playRegularTrack(Track track) async {
    try {
      _currentTrack = track;
      print('MusicProvider: Getting stream URL for ${track.title}...');
      
      // First get the original stream URL
      final originalResponse = await MusicApiService.getStreamUrl(
        track.id,
        service: track.source,
      );
      
      if (!originalResponse.success || originalResponse.data == null) {
        throw Exception(originalResponse.message ?? 'Failed to get original stream URL');
      }
      
      print('MusicProvider: Original stream URL obtained, preparing backend cache...');
      
      // Now get the backend stream URL (this may take time for caching)
      final backendResponse = await MusicApiService.getBackendStreamUrl(
        track.id,
        track.source,
        originalResponse.data!,
        title: track.title,
        artist: track.artist,
      );
      
      if (backendResponse.success && backendResponse.data != null) {
        // Use the backend stream URL for playback
        final configuredBackendUrl = await AppConfigService.instance.getBackendUrl();
        final backendUrl = '$configuredBackendUrl${backendResponse.data!.streamUrl}';
        
        // Convert coverUrl to absolute URL if it's a relative path
        String? absoluteCoverUrl;
        if (track.coverUrl != null) {
          if (track.coverUrl!.startsWith('http://') || track.coverUrl!.startsWith('https://')) {
            // Already an absolute URL
            absoluteCoverUrl = track.coverUrl;
          } else {
            // Relative path - prepend backend URL
            absoluteCoverUrl = '$configuredBackendUrl${track.coverUrl}';
          }
        }
        
        print('MusicProvider: Backend stream URL ready: $backendUrl');
        
        // Update the current track with the backend stream URL and absolute cover URL
        _currentTrack = Track(
          id: track.id,
          title: track.title,
          artist: track.artist,
          album: track.album,
          duration: track.duration,
          streamUrl: backendUrl,
          coverUrl: absoluteCoverUrl,
          source: track.source,
          quality: track.quality,
          bitrate: track.bitrate,
          sampleRate: track.sampleRate,
          bitDepth: track.bitDepth,
          bpm: track.bpm, // Preserve BPM from original track
        );
        
        print('MusicProvider: Starting audio playback...');
        await _audioService.playTrack(_currentTrack!, backendUrl);
        
        // Update local state for UI and media controls
        _isPlaying = true;
        _position = Duration.zero;
        _duration = _currentTrack!.duration != null ? Duration(seconds: _currentTrack!.duration!) : Duration.zero;
        
        // Immediately update audio service handler state for MPRIS/media controls
        _updateAudioServiceHandlerState();
        notifyListeners();
        
        _startAudioInfoUpdates();
      } else {
        throw Exception(backendResponse.message ?? 'Failed to get backend stream URL');
      }
    } catch (e) {
      print('MusicProvider: Error in _playRegularTrack: $e');
      
      // Provide more user-friendly error messages
      if (e.toString().contains('timeout') || e.toString().contains('Timeout')) {
        throw Exception('The track is taking too long to load. This may be due to a slow internet connection or the file being very large. Please try again.');
      } else if (e.toString().contains('AndroidAudioError')) {
        throw Exception('Unable to play this audio format. Please try a different track.');
      } else {
        rethrow;
      }
    }
  }

  void _startAudioInfoUpdates() {
    _audioInfoTimer?.cancel();
    _audioInfoTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      final newAudioInfo = _audioService.audioOutputInfo;
      if (newAudioInfo.hasInfo && 
          (newAudioInfo.outputBitrate != _audioOutputInfo.outputBitrate ||
           newAudioInfo.outputSampleRate != _audioOutputInfo.outputSampleRate ||
           newAudioInfo.format != _audioOutputInfo.format)) {
        _audioOutputInfo = newAudioInfo;
        notifyListeners();
      }
    });
  }

  void _stopAudioInfoUpdates() {
    _audioInfoTimer?.cancel();
    _audioInfoTimer = null;
    _audioOutputInfo = AudioOutputInfo();
  }

  Future<void> togglePlayPause() async {
    if (_isPlaying) {
      await _audioService.pause();
    } else {
      await _audioService.play();
    }
  }

  Future<void> stopPlayback() async {
    await _audioService.stop();
    _stopAudioInfoUpdates();
    _currentTrack = null;
    _position = Duration.zero;
    _duration = Duration.zero;
    notifyListeners();
  }

  Future<void> seek(Duration position) async {
    await _audioService.seek(position);
  }

  Future<void> setVolume(double volume) async {
    await _audioService.setVolume(volume);
  }

  void clearSearch() {
    _searchResults = null;
    _searchError = null;
    _currentPage = 1;
    _lastSearchQuery = '';
    _lastSearchWasLibrary = false;
    notifyListeners();
  }

  // Pagination methods
  void nextPage() {
    if (hasNextPage) {
      _currentPage++;
      notifyListeners(); // Notify immediately to update UI
      _performPaginatedSearch();
    }
  }

  void previousPage() {
    if (hasPreviousPage) {
      _currentPage--;
      notifyListeners(); // Notify immediately to update UI
      _performPaginatedSearch();
    }
  }

  void goToPage(int page) {
    if (page >= 1 && page <= totalPages && page != _currentPage) {
      _currentPage = page;
      notifyListeners(); // Notify immediately to update UI
      _performPaginatedSearch();
    }
  }

  void changePageSize(int newPageSize) {
    if (availablePageSizes.contains(newPageSize) && newPageSize != _itemsPerPage) {
      _itemsPerPage = newPageSize;
      _currentPage = 1; // Reset to first page when changing page size
      
      // Save preference
      _savePageSizePreference(newPageSize);
      
      // Refresh search results with new page size
      _performPaginatedSearch();
    }
  }

  Future<void> _loadPageSizePreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedPageSize = prefs.getInt('search_page_size') ?? 20;
      
      if (_availablePageSizes.contains(savedPageSize)) {
        _itemsPerPage = savedPageSize;
      }
    } catch (e) {
      print('Failed to load page size preference: $e');
    }
  }

  Future<void> _savePageSizePreference(int pageSize) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('search_page_size', pageSize);
    } catch (e) {
      print('Failed to save page size preference: $e');
    }
  }

  void _performPaginatedSearch() {
    if (_lastSearchQuery.isEmpty) {
      // For "search all" with pagination, we need to call the search methods with current pagination
      if (_lastSearchWasLibrary) {
        _searchAllLibraryWithPagination();
      } else {
        _searchAllWithPagination();
      }
      return;
    }

    // Perform search with current pagination
    if (_lastSearchWasLibrary) {
      _searchLibraryWithPagination(_lastSearchQuery);
    } else {
      switch (_lastSearchType) {
        case SearchType.tracks:
          _searchWithPagination(_lastSearchQuery, 'track');
          break;
        case SearchType.albums:
          _searchWithPagination(_lastSearchQuery, 'album');
          break;
        case SearchType.playlists:
          _searchWithPagination(_lastSearchQuery, 'playlist');
          break;
      }
    }
  }

  Future<void> _searchWithPagination(String query, String type) async {
    _isSearching = true;
    _searchError = null;
    notifyListeners();

    try {
      final offset = (_currentPage - 1) * _itemsPerPage;
      
      ApiResponse<SearchResults> response;
      
      if (type == 'track') {
        if (_useMultiServiceSearch && _selectedServices.isNotEmpty) {
          response = await MusicApiService.searchMusic(
            query,
            limit: _itemsPerPage,
            offset: offset,
            services: _selectedServices,
          );
        } else {
          response = await MusicApiService.searchMusic(
            query,
            limit: _itemsPerPage,
            offset: offset,
            service: _selectedService,
          );
        }
      } else if (type == 'album') {
        if (_useMultiServiceSearch && _selectedServices.isNotEmpty) {
          response = await MusicApiService.searchAlbums(
            query,
            limit: _itemsPerPage,
            offset: offset,
            services: _selectedServices,
          );
        } else {
          response = await MusicApiService.searchAlbums(
            query,
            limit: _itemsPerPage,
            offset: offset,
            service: _selectedService,
          );
        }
      } else {
        if (_useMultiServiceSearch && _selectedServices.isNotEmpty) {
          response = await MusicApiService.searchPlaylists(
            query,
            limit: _itemsPerPage,
            offset: offset,
            services: _selectedServices,
          );
        } else {
          response = await MusicApiService.searchPlaylists(
            query,
            limit: _itemsPerPage,
            offset: offset,
            service: _selectedService,
          );
        }
      }
      
      if (response.success && response.data != null) {
        _searchResults = response.data;
        _searchError = null;
      } else {
        _searchError = response.message ?? 'Search failed';
      }
    } catch (e) {
      _searchError = 'Search failed: $e';
    } finally {
      _isSearching = false;
      notifyListeners();
    }
  }

  /// Update the BPM of a track
  void updateTrackBpm(String trackId, double bpm) {
    // Update current track if it matches
    if (_currentTrack != null && _currentTrack!.id == trackId) {
      _currentTrack = Track(
        id: _currentTrack!.id,
        title: _currentTrack!.title,
        artist: _currentTrack!.artist,
        album: _currentTrack!.album,
        duration: _currentTrack!.duration,
        streamUrl: _currentTrack!.streamUrl,
        coverUrl: _currentTrack!.coverUrl,
        source: _currentTrack!.source,
        quality: _currentTrack!.quality,
        bitrate: _currentTrack!.bitrate,
        sampleRate: _currentTrack!.sampleRate,
        bitDepth: _currentTrack!.bitDepth,
        bpm: bpm,
        keyName: _currentTrack!.keyName,
        camelot: _currentTrack!.camelot,
        keyConfidence: _currentTrack!.keyConfidence,
      );
      notifyListeners();
    }

    // Update search results if they exist
    if (_searchResults != null) {
      final updatedTracks = _searchResults!.tracks.map((track) {
        if (track.id == trackId) {
          return Track(
            id: track.id,
            title: track.title,
            artist: track.artist,
            album: track.album,
            duration: track.duration,
            streamUrl: track.streamUrl,
            coverUrl: track.coverUrl,
            source: track.source,
            quality: track.quality,
            bitrate: track.bitrate,
            sampleRate: track.sampleRate,
            bitDepth: track.bitDepth,
            bpm: bpm,
            keyName: track.keyName,
            camelot: track.camelot,
            keyConfidence: track.keyConfidence,
          );
        }
        return track;
      }).toList();

      _searchResults = SearchResults(
        tracks: updatedTracks,
        albums: _searchResults!.albums,
        playlists: _searchResults!.playlists,
        total: _searchResults!.total,
        offset: _searchResults!.offset,
        limit: _searchResults!.limit,
      );
      notifyListeners();
    }
  }

  /// Update the key of a track
  void updateTrackKey(String trackId, String keyName, String camelot, double confidence) {
    // Update current track if it matches
    if (_currentTrack != null && _currentTrack!.id == trackId) {
      _currentTrack = Track(
        id: _currentTrack!.id,
        title: _currentTrack!.title,
        artist: _currentTrack!.artist,
        album: _currentTrack!.album,
        duration: _currentTrack!.duration,
        streamUrl: _currentTrack!.streamUrl,
        coverUrl: _currentTrack!.coverUrl,
        source: _currentTrack!.source,
        quality: _currentTrack!.quality,
        bitrate: _currentTrack!.bitrate,
        sampleRate: _currentTrack!.sampleRate,
        bitDepth: _currentTrack!.bitDepth,
        bpm: _currentTrack!.bpm,
        keyName: keyName,
        camelot: camelot,
        keyConfidence: confidence,
      );
      notifyListeners();
    }

    // Update search results if they exist
    if (_searchResults != null) {
      final updatedTracks = _searchResults!.tracks.map((track) {
        if (track.id == trackId) {
          return Track(
            id: track.id,
            title: track.title,
            artist: track.artist,
            album: track.album,
            duration: track.duration,
            streamUrl: track.streamUrl,
            coverUrl: track.coverUrl,
            source: track.source,
            quality: track.quality,
            bitrate: track.bitrate,
            sampleRate: track.sampleRate,
            bitDepth: track.bitDepth,
            bpm: track.bpm,
            keyName: keyName,
            camelot: camelot,
            keyConfidence: confidence,
          );
        }
        return track;
      }).toList();

      _searchResults = SearchResults(
        tracks: updatedTracks,
        albums: _searchResults!.albums,
        playlists: _searchResults!.playlists,
        total: _searchResults!.total,
        offset: _searchResults!.offset,
        limit: _searchResults!.limit,
      );
      notifyListeners();
    }
  }

  void pauseUIUpdates() {
    if (!_isUIUpdatesPaused) {
      _isUIUpdatesPaused = true;
      _startBackgroundUpdates();
    }
  }

  void resumeUIUpdates() {
    if (_isUIUpdatesPaused) {
      _isUIUpdatesPaused = false;
      _stopBackgroundUpdates();
      // Force update UI with current state
      notifyListeners();
    }
  }

  void _startBackgroundUpdates() {
    if (_backgroundUpdateTimer != null || _currentTrack == null) return;
    
    // Start background timer for periodic updates
    _backgroundUpdateTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (_isPlaying && _isUIUpdatesPaused) {
        // Update position from audio service
        _position = _audioService.position;
        _duration = _audioService.duration;
        
        // Force UI update even when paused
        notifyListeners();
      }
    });
  }

  void _stopBackgroundUpdates() {
    _backgroundUpdateTimer?.cancel();
    _backgroundUpdateTimer = null;
  }

  Future<void> _checkAndPlayNextTrack() async {
    if (_queueProvider == null) return;
    
    // Check if we're playing from a playlist queue
    if (_isPlayingFromPlaylist) {
      await _checkAndPlayNextTrackFromPlaylist();
      return;
    }
    
    // Check if current track is at the end (within 1 second of duration)
    if (_duration.inSeconds > 0 && _position.inSeconds >= _duration.inSeconds - 1) {
      final nextTrack = _queueProvider!.getNextTrack();
      if (nextTrack != null) {
        // Remove current track from queue and play next
        await _queueProvider!.moveToNext();
        await playTrack(nextTrack.toTrack(), clearQueue: false);
      }
    }
  }

  // Playlist Queue Methods
  Future<void> playPlaylistQueueItem(PlaylistQueueItem playlistQueueItem) async {
    _currentPlaylistQueueItem = playlistQueueItem;
    _isPlayingFromPlaylist = true;
    
    // Use the stored track details from the playlist queue item
    final track = Track(
      id: playlistQueueItem.currentTrackId ?? playlistQueueItem.trackOrder[playlistQueueItem.currentTrackIndex],
      title: playlistQueueItem.currentTrackTitle ?? 'Track ${playlistQueueItem.currentTrackIndex + 1}',
      artist: playlistQueueItem.currentTrackArtist ?? 'From ${playlistQueueItem.playlistName}',
      album: playlistQueueItem.currentTrackAlbum ?? playlistQueueItem.playlistName,
      duration: playlistQueueItem.currentTrackDuration,
      coverUrl: playlistQueueItem.currentTrackCoverUrl,
      source: playlistQueueItem.currentTrackSource ?? 'qobuz',
    );
    
    await playTrack(track, clearQueue: false);
  }

  Future<void> playNextTrackFromPlaylist() async {
    if (_currentPlaylistQueueItem == null || _queueProvider == null) return;
    
    // Move to next track in playlist
    final success = await _queueProvider!.moveToNextTrack();
    if (success) {
      // Get updated playlist queue item
      final updatedItem = _queueProvider!.getCurrentPlaylistQueueItem();
      if (updatedItem != null) {
        // Fetch the actual track details for the new track
        await _playTrackFromPlaylistAtIndex(updatedItem, updatedItem.currentTrackIndex);
      } else {
        // Playlist finished, check regular queue
        await _checkAndPlayNextTrack();
      }
    }
  }

  Future<void> playPreviousTrackFromPlaylist() async {
    if (_currentPlaylistQueueItem == null || _queueProvider == null) return;
    
    // Move to previous track in playlist
    final success = await _queueProvider!.moveToPreviousTrack();
    if (success) {
      // Get updated playlist queue item
      final updatedItem = _queueProvider!.getCurrentPlaylistQueueItem();
      if (updatedItem != null) {
        // Fetch the actual track details for the new track
        await _playTrackFromPlaylistAtIndex(updatedItem, updatedItem.currentTrackIndex);
      }
    }
  }

  Future<void> _checkAndPlayNextTrackFromPlaylist() async {
    if (!_isPlayingFromPlaylist || _currentPlaylistQueueItem == null) {
      await _checkAndPlayNextTrack();
      return;
    }
    
    // Check if current track is at the end (within 1 second of duration)
    if (_duration.inSeconds > 0 && _position.inSeconds >= _duration.inSeconds - 1) {
      await playNextTrackFromPlaylist();
    }
  }

  void _checkForTrackCompletion() {
    // Fallback completion detection based on position being very close to duration
    // and the track not being actively playing
    if (_duration.inSeconds > 0 && 
        _position.inSeconds >= _duration.inSeconds - 1 &&
        !_isPlaying &&
        _currentTrack != null &&
        _queueProvider != null) {
      
      // Use a small delay to ensure the position has truly reached the end
      Timer(const Duration(milliseconds: 500), () {
        if (_position.inSeconds >= _duration.inSeconds - 1 && !_isPlaying) {
          print('Track completed via position detection, playing next track...');
          _playNextTrackAfterCompletion();
        }
      });
    }
  }

  Future<void> _playTrackFromPlaylistAtIndex(PlaylistQueueItem playlistItem, int trackIndex) async {
    if (trackIndex >= playlistItem.trackOrder.length) return;
    
    try {
      _isLoading = true;
      notifyListeners();
      
      final trackId = playlistItem.trackOrder[trackIndex];
      
      // Fetch track details from the backend
      final response = await PlaylistApiService.getPlaylistItems(playlistItem.playlistId);
      
      if (response.success && response.data != null) {
        final playlistItems = response.data!;
        
        // Find the track in the playlist items
        final trackItem = playlistItems.firstWhere(
          (item) => item.itemId == trackId,
          orElse: () => throw Exception('Track not found in playlist'),
        );
        
        // Create track from the fetched details
        final track = Track(
          id: trackItem.itemId,
          title: trackItem.title ?? 'Unknown Title',
          artist: trackItem.artist ?? 'Unknown Artist',
          album: trackItem.album ?? 'Unknown Album',
          duration: trackItem.duration,
          coverUrl: trackItem.coverUrl,
          source: trackItem.source ?? 'qobuz',
        );
        
        // Update the current playlist queue item
        _currentPlaylistQueueItem = playlistItem;
        _isPlayingFromPlaylist = true;
        
        await playTrack(track, clearQueue: false);
      } else {
        throw Exception('Failed to fetch playlist details');
      }
    } catch (e) {
      print('Error playing track from playlist at index $trackIndex: $e');
      // Fallback to using the track ID directly if we can't fetch details
      final trackId = playlistItem.trackOrder[trackIndex];
      final track = Track(
        id: trackId,
        title: 'Track ${trackIndex + 1}',
        artist: 'From ${playlistItem.playlistName}',
        album: playlistItem.playlistName,
        duration: null,
        coverUrl: null,
        source: 'qobuz',
      );
      
      _currentPlaylistQueueItem = playlistItem;
      _isPlayingFromPlaylist = true;
      
      await playTrack(track, clearQueue: false);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _playNextTrackAfterCompletion() async {
    if (_queueProvider == null) return;
    
    try {
      // Check if we're playing from a playlist queue
      if (_isPlayingFromPlaylist) {
        await playNextTrackFromPlaylist();
        return;
      }

      // Check if there are playlist queue items available
      final currentPlaylist = _queueProvider!.getCurrentPlaylistQueueItem();
      if (currentPlaylist != null) {
        await playPlaylistQueueItem(currentPlaylist);
        return;
      }

      // Get the next track from the regular queue
      final nextTrack = _queueProvider!.getNextTrack();
      if (nextTrack != null) {
        // Remove current track from queue and play next
        await _queueProvider!.moveToNext();
        await playTrack(nextTrack.toTrack(), clearQueue: false);
      } else {
        print('No next track available in queue');
      }
    } catch (e) {
      print('Error playing next track after completion: $e');
    }
  }

  Future<void> _searchAllWithPagination() async {
    // Search all music from server with current pagination (don't reset page)
    _isSearching = true;
    _searchError = null;
    notifyListeners();

    try {
      // Use empty query to get all results from server
      final offset = (_currentPage - 1) * _itemsPerPage;
      
      final futures = await Future.wait([
        MusicApiService.searchMusic(
          '', // Empty query for all results
          limit: _itemsPerPage,
          offset: offset,
          service: 'server',
        ),
        MusicApiService.searchAlbums(
          '', // Empty query for all results
          limit: _itemsPerPage,
          offset: offset,
          service: 'server',
        ),
        MusicApiService.searchPlaylists(
          '', // Empty query for all results
          limit: _itemsPerPage,
          offset: offset,
          service: 'server',
        ),
      ]);
      
      final musicResponse = futures[0];
      final albumResponse = futures[1];
      final playlistResponse = futures[2];
      
      // Combine the results
      List<Track> tracks = [];
      List<Album> albums = [];
      List<PlaylistSearchResult> playlists = [];
      
      if (musicResponse.success && musicResponse.data != null) {
        tracks = musicResponse.data!.tracks;
      }
      
      if (albumResponse.success && albumResponse.data != null) {
        albums = albumResponse.data!.albums;
      }
      
      if (playlistResponse.success && playlistResponse.data != null) {
        playlists = playlistResponse.data!.playlists ?? [];
      }
      
      // Use the total from the first successful response, or calculate from results
      int total = 0;
      if (musicResponse.success && musicResponse.data != null) {
        total = musicResponse.data!.total;
      } else if (albumResponse.success && albumResponse.data != null) {
        total = albumResponse.data!.total;
      } else if (playlistResponse.success && playlistResponse.data != null) {
        total = playlistResponse.data!.total;
      } else {
        total = tracks.length + albums.length + playlists.length;
      }

      _searchResults = SearchResults(
        tracks: tracks,
        albums: albums,
        playlists: playlists,
        total: total,
        offset: offset,
        limit: _itemsPerPage,
      );
      
      _searchError = null;
    } catch (e) {
      _searchError = 'Failed to search all music: $e';
      _searchResults = null;
    } finally {
      _isSearching = false;
      notifyListeners();
    }
  }

  Future<void> _searchAllLibraryWithPagination() async {
    // Search all library items with current pagination (don't reset page)
    _isSearching = true;
    _searchError = null;
    notifyListeners();

    try {
      final offset = (_currentPage - 1) * _itemsPerPage;
      
      // Convert SearchType to string
      String typeString = _lastSearchType == SearchType.tracks ? 'track' 
                        : _lastSearchType == SearchType.albums ? 'album' 
                        : 'playlist';
      
      ApiResponse<SearchResults> response;
      
      if (_useMultiServiceSearch && _selectedServices.isNotEmpty) {
        // Multi-service library search all
        response = await MusicApiService.searchAllLibrary(
          limit: _itemsPerPage,
          offset: offset,
          services: _selectedServices,
          type: typeString,
        );
      } else {
        // Single service library search all
        response = await MusicApiService.searchAllLibrary(
          limit: _itemsPerPage,
          offset: offset,
          service: _selectedService,
          type: typeString,
        );
      }
      
      if (response.success && response.data != null) {
        _searchResults = response.data;
      } else {
        _searchError = response.message ?? 'Library search all failed';
      }
    } catch (e) {
      _searchError = 'Library search all failed: $e';
    } finally {
      _isSearching = false;
      notifyListeners();
    }
  }

  Future<void> _searchLibraryWithPagination(String query) async {
    _isSearching = true;
    _searchError = null;
    notifyListeners();

    try {
      final offset = (_currentPage - 1) * _itemsPerPage;
      
      // Convert SearchType to string
      String typeString = _lastSearchType == SearchType.tracks ? 'track' 
                        : _lastSearchType == SearchType.albums ? 'album' 
                        : 'playlist';
      
      ApiResponse<SearchResults> response;
      
      if (_useMultiServiceSearch && _selectedServices.isNotEmpty) {
        response = await MusicApiService.searchLibrary(
          query,
          limit: _itemsPerPage,
          offset: offset,
          services: _selectedServices,
          type: typeString,
        );
      } else {
        response = await MusicApiService.searchLibrary(
          query,
          limit: _itemsPerPage,
          offset: offset,
          service: _selectedService,
          type: typeString,
        );
      }
      
      if (response.success && response.data != null) {
        _searchResults = response.data;
        _searchError = null;
      } else {
        _searchError = response.message ?? 'Library search failed';
      }
    } catch (e) {
      _searchError = 'Library search failed: $e';
    } finally {
      _isSearching = false;
      notifyListeners();
    }
  }

  void dispose() {
    _audioInfoTimer?.cancel();
    _stopBackgroundUpdates();
    _audioService.dispose();
    super.dispose();
  }
}
