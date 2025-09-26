import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../models/music.dart';

class SpotifyWebPlayer {
  static final SpotifyWebPlayer _instance = SpotifyWebPlayer._internal();
  factory SpotifyWebPlayer() => _instance;
  SpotifyWebPlayer._internal();

  bool _isInitialized = false;
  bool _isPlaying = false;
  Track? _currentTrack;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  
  // Stream controllers for state management
  final StreamController<bool> _playingController = StreamController<bool>.broadcast();
  final StreamController<Duration> _positionController = StreamController<Duration>.broadcast();
  final StreamController<Duration> _durationController = StreamController<Duration>.broadcast();
  final StreamController<Track?> _trackController = StreamController<Track?>.broadcast();

  Stream<bool> get playingStream => _playingController.stream;
  Stream<Duration> get positionStream => _positionController.stream;
  Stream<Duration> get durationStream => _durationController.stream;
  Stream<Track?> get trackStream => _trackController.stream;

  bool get isInitialized => _isInitialized;
  bool get isPlaying => _isPlaying;
  Track? get currentTrack => _currentTrack;
  Duration get position => _position;
  Duration get duration => _duration;

  Future<void> initialize(String accessToken) async {
    // Spotify Web Playback SDK is only available on web platforms
    if (kIsWeb) {
      throw UnsupportedError(
        'Spotify Web Playback SDK is only available on web platforms. '
        'Please use the web version of the app for full Spotify playback support.'
      );
    } else {
      throw UnsupportedError(
        'Spotify Web Playback SDK is not available on this platform. '
        'Please use the web version of the app or try Qobuz tracks instead.'
      );
    }
  }


  Future<void> playTrack(Track track) async {
    throw UnsupportedError(
      'Spotify Web Playback SDK is not available on this platform. '
      'Please use the web version of the app for full Spotify playback support.'
    );
  }

  Future<void> play() async {
    throw UnsupportedError(
      'Spotify Web Playback SDK is not available on this platform. '
      'Please use the web version of the app for full Spotify playback support.'
    );
  }

  Future<void> pause() async {
    throw UnsupportedError(
      'Spotify Web Playback SDK is not available on this platform. '
      'Please use the web version of the app for full Spotify playback support.'
    );
  }

  Future<void> stop() async {
    _currentTrack = null;
    _trackController.add(null);
  }

  Future<void> seek(Duration position) async {
    throw UnsupportedError(
      'Spotify Web Playback SDK is not available on this platform. '
      'Please use the web version of the app for full Spotify playback support.'
    );
  }

  Future<void> setVolume(double volume) async {
    throw UnsupportedError(
      'Spotify Web Playback SDK is not available on this platform. '
      'Please use the web version of the app for full Spotify playback support.'
    );
  }

  void dispose() {
    _playingController.close();
    _positionController.close();
    _durationController.close();
    _trackController.close();
  }
}
