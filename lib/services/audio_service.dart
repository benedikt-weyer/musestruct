import 'package:audioplayers/audioplayers.dart';
import '../models/music.dart';

class AudioService {
  static final AudioService _instance = AudioService._internal();
  factory AudioService() => _instance;
  AudioService._internal();

  final AudioPlayer _player = AudioPlayer();
  Track? _currentTrack;
  bool _isInitialized = false;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  AudioPlayer get player => _player;
  Track? get currentTrack => _currentTrack;
  bool get isInitialized => _isInitialized;
  bool get isPlaying => _isPlaying;
  Duration get position => _position;
  Duration get duration => _duration;

  // Stream controllers for state management
  Stream<bool> get playingStream => _player.onPlayerStateChanged.map((state) => state == PlayerState.playing);
  Stream<Duration> get positionStream => _player.onPositionChanged;
  Stream<Duration> get durationStream => _player.onDurationChanged;

  Future<void> initialize() async {
    if (!_isInitialized) {
      // Set up listeners
      _player.onPlayerStateChanged.listen((PlayerState state) {
        _isPlaying = state == PlayerState.playing;
      });

      _player.onPositionChanged.listen((Duration position) {
        _position = position;
      });

      _player.onDurationChanged.listen((Duration duration) {
        _duration = duration;
      });

      _isInitialized = true;
    }
  }

  Future<void> playTrack(Track track, String streamUrl) async {
    try {
      _currentTrack = track;
      await _player.play(UrlSource(streamUrl));
    } catch (e) {
      print('Error playing track: $e');
      rethrow;
    }
  }

  Future<void> play() async {
    await _player.resume();
  }

  Future<void> pause() async {
    await _player.pause();
  }

  Future<void> stop() async {
    await _player.stop();
    _currentTrack = null;
  }

  Future<void> seek(Duration position) async {
    await _player.seek(position);
  }

  Future<void> setVolume(double volume) async {
    await _player.setVolume(volume);
  }

  void dispose() {
    _player.dispose();
  }
}