import 'package:flutter/foundation.dart';
import '../models/music.dart';
import '../services/api_service.dart';
import '../services/audio_service.dart';

class MusicProvider with ChangeNotifier {
  final AudioService _audioService = AudioService();
  
  SearchResults? _searchResults;
  bool _isSearching = false;
  String? _searchError;
  
  List<ServiceInfo> _availableServices = [];
  String _selectedService = 'qobuz';
  
  Track? _currentTrack;
  bool _isPlaying = false;
  bool _isLoading = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  // Getters
  SearchResults? get searchResults => _searchResults;
  bool get isSearching => _isSearching;
  String? get searchError => _searchError;
  
  List<ServiceInfo> get availableServices => _availableServices;
  String get selectedService => _selectedService;
  
  Track? get currentTrack => _currentTrack;
  bool get isPlaying => _isPlaying;
  bool get isLoading => _isLoading;
  Duration get position => _position;
  Duration get duration => _duration;
  
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

  Future<void> searchMusic(String query) async {
    if (query.trim().isEmpty) return;

    _isSearching = true;
    _searchError = null;
    notifyListeners();

    try {
      final response = await ApiService.searchMusic(
        query, 
        limit: 20,
        service: _selectedService,
      );
      
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
      final response = await ApiService.getStreamUrl(track.id);
      
      if (response.success && response.data != null) {
        await _audioService.playTrack(track, response.data!);
      } else {
        throw Exception(response.message ?? 'Failed to get stream URL');
      }
    } catch (e) {
      _searchError = 'Failed to play track: $e';
      _currentTrack = null;
      notifyListeners();
    } finally {
      _isLoading = false;
    }
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
    _audioService.dispose();
    super.dispose();
  }
}
