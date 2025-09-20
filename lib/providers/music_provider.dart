import 'package:flutter/foundation.dart';
import 'dart:async';
import '../models/music.dart';
import '../models/api_response.dart';
import '../services/api_service.dart';
import '../services/audio_service.dart';
// import '../services/spotify_webview_player.dart'; // Disabled
// import '../widgets/spotify_webview_widget.dart'; // Disabled

class MusicProvider with ChangeNotifier {
  final AudioService _audioService = AudioService();
  // final SpotifyWebViewPlayer _spotifyPlayer = SpotifyWebViewPlayer(); // Disabled
  
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
  
  AudioService get audioService => _audioService;

  MusicProvider() {
    _initializeAudioService();
    _loadAvailableServices();
  }

  void _initializeAudioService() async {
    await _audioService.initialize();
    
    // Listen to player state changes
    _audioService.playingStream.listen((isPlaying) {
      _isPlaying = isPlaying;
      notifyListeners();
    });

    // Listen to position changes
    _audioService.positionStream.listen((position) {
      _position = position;
      notifyListeners();
    });

    // Listen to duration changes
    _audioService.durationStream.listen((duration) {
      _duration = duration;
      notifyListeners();
    });
  }

  Future<void> _loadAvailableServices() async {
    try {
      final response = await ApiService.getAvailableServices();
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
        response = await ApiService.searchMusic(
          query, 
          limit: 20,
          services: _selectedServices,
        );
      } else {
        // Single service search
        response = await ApiService.searchMusic(
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
    // Get stream URL for non-Spotify tracks
    final response = await ApiService.getStreamUrl(
      track.id,
      service: track.source,
    );
    
    if (response.success && response.data != null) {
      await _audioService.playTrack(track, response.data!);
      _startAudioInfoUpdates();
    } else {
      throw Exception(response.message ?? 'Failed to get stream URL');
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

  @override
  void dispose() {
    _audioInfoTimer?.cancel();
    _audioService.dispose();
    super.dispose();
  }
}
