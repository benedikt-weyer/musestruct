import 'package:just_audio/just_audio.dart';
import '../models/music.dart';

class AudioService {
  static final AudioService _instance = AudioService._internal();
  factory AudioService() => _instance;
  AudioService._internal();

  final AudioPlayer _player = AudioPlayer();
  Track? _currentTrack;
  bool _isInitialized = false;

  AudioPlayer get player => _player;
  Track? get currentTrack => _currentTrack;
  bool get isInitialized => _isInitialized;

  Stream<PlayerState> get playerStateStream => _player.playerStateStream;
  Stream<Duration?> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;

  Future<void> initialize() async {
    if (!_isInitialized) {
      _isInitialized = true;
    }
  }

  Future<void> playTrack(Track track, String streamUrl) async {
    try {
      _currentTrack = track;
      await _player.setUrl(streamUrl);
      await _player.play();
    } catch (e) {
      print('Error playing track: $e');
      rethrow;
    }
  }

  Future<void> play() async {
    await _player.play();
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
