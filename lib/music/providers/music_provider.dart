import 'package:flutter/foundation.dart';
import 'dart:async';
import '../models/music.dart';
import '../../core/models/api_response.dart';
import '../services/music_api_service.dart';
import '../../core/services/audio_service.dart';
import '../../core/services/app_config_service.dart';
import '../../queue/providers/queue_provider.dart';
// import '../../core/services/spotify_webview_player.dart'; // Disabled
// import '../../core/widgets/spotify_webview_widget.dart'; // Disabled

class MusicProvider with ChangeNotifier {
  final AudioService _audioService = AudioService();
  // final SpotifyWebViewPlayer _spotifyPlayer = SpotifyWebViewPlayer(); // Disabled
  QueueProvider? _queueProvider;
  
  SearchResults? _searchResults;
  bool _isSearching = false;
  String? _searchError;
  
  List<ServiceInfo> _availableServices = [];
  String _selectedService = 'qobuz';
  List<String> _selectedServices = ['qobuz']; // For multi-service search
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
      await playTrack(nextTrack.toTrack());
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
  }

  void _initializeAudioService() async {
    await _audioService.initialize();
    
    // Listen to player state changes
    _audioService.playingStream.listen((isPlaying) {
      _isPlaying = isPlaying;
      if (!_isUIUpdatesPaused) {
        notifyListeners();
      }
      
      // Check if track finished and we should play next from queue
      if (!isPlaying && _currentTrack != null && _queueProvider != null) {
        _checkAndPlayNextTrack();
      }
    });

    // Listen to position changes
    _audioService.positionStream.listen((position) {
      _position = position;
      if (!_isUIUpdatesPaused) {
        notifyListeners();
      }
    });

    // Listen to duration changes
    _audioService.durationStream.listen((duration) {
      _duration = duration;
      if (!_isUIUpdatesPaused) {
        notifyListeners();
      }
    });
  }

  Future<void> _loadAvailableServices() async {
    try {
      final response = await MusicApiService.getAvailableServices();
      if (response.success && response.data != null) {
        _availableServices = response.data!;
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

  Future<void> searchBoth(String query) async {
    if (query.trim().isEmpty) return;

    _isSearching = true;
    _searchError = null;
    notifyListeners();

    try {
      // Perform both searches simultaneously
      late ApiResponse<SearchResults> musicResponse;
      late ApiResponse<SearchResults> playlistResponse;
      
      if (_useMultiServiceSearch && _selectedServices.isNotEmpty) {
        // Multi-service search
        final futures = await Future.wait([
          MusicApiService.searchMusic(
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
        playlistResponse = futures[1];
      } else {
        // Single service search
        final futures = await Future.wait([
          MusicApiService.searchMusic(
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
        playlistResponse = futures[1];
      }
      
      // Combine the results
      List<Track> tracks = [];
      List<PlaylistSearchResult> playlists = [];
      
      if (musicResponse.success && musicResponse.data != null) {
        tracks = musicResponse.data!.tracks;
      }
      
      if (playlistResponse.success && playlistResponse.data != null) {
        playlists = playlistResponse.data!.playlists ?? [];
      }
      
      // Create combined search results
      _searchResults = SearchResults(
        tracks: tracks,
        albums: [], // Not used in current implementation
        playlists: playlists,
        total: tracks.length + playlists.length,
        offset: 0,
        limit: 20,
      );
      
      print('MusicProvider: Combined search results - ${tracks.length} tracks, ${playlists.length} playlists');
      
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

  Future<void> playTrack(Track track) async {
    try {
      _isLoading = true;
      _currentTrack = track;
      notifyListeners();

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
      );
      
      if (backendResponse.success && backendResponse.data != null) {
        // Use the backend stream URL for playback
        final configuredBackendUrl = await AppConfigService.instance.getBackendUrl();
        final backendUrl = '$configuredBackendUrl${backendResponse.data!.streamUrl}';
        
        print('MusicProvider: Backend stream URL ready: $backendUrl');
        
        // Update the current track with the backend stream URL
        _currentTrack = Track(
          id: track.id,
          title: track.title,
          artist: track.artist,
          album: track.album,
          duration: track.duration,
          streamUrl: backendUrl, // This is the key change!
          coverUrl: track.coverUrl,
          source: track.source,
          quality: track.quality,
          bitrate: track.bitrate,
          sampleRate: track.sampleRate,
          bitDepth: track.bitDepth,
        );
        
        print('MusicProvider: Starting audio playback...');
        await _audioService.playTrack(_currentTrack!, backendUrl);
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
    notifyListeners();
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
        await playTrack(nextTrack.toTrack());
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
    
    await playTrack(track);
  }

  Future<void> playNextTrackFromPlaylist() async {
    if (_currentPlaylistQueueItem == null || _queueProvider == null) return;
    
    // Move to next track in playlist
    final success = await _queueProvider!.moveToNextTrack();
    if (success) {
      // Get updated playlist queue item
      final updatedItem = _queueProvider!.getCurrentPlaylistQueueItem();
      if (updatedItem != null) {
        await playPlaylistQueueItem(updatedItem);
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
        await playPlaylistQueueItem(updatedItem);
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

  @override
  void dispose() {
    _audioInfoTimer?.cancel();
    _stopBackgroundUpdates();
    _audioService.dispose();
    super.dispose();
  }
}
