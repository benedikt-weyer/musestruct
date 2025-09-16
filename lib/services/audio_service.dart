import 'package:audioplayers/audioplayers.dart';
import 'package:http/http.dart' as http;
import '../models/music.dart';
import 'dart:async';

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
  AudioOutputInfo _audioOutputInfo = AudioOutputInfo();

  AudioPlayer get player => _player;
  Track? get currentTrack => _currentTrack;
  bool get isInitialized => _isInitialized;
  bool get isPlaying => _isPlaying;
  Duration get position => _position;
  Duration get duration => _duration;
  AudioOutputInfo get audioOutputInfo => _audioOutputInfo;

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
      
      // Analyze audio stream for real-time info (with delay to ensure playback started)
      Timer(const Duration(seconds: 2), () {
        _analyzeAudioStream(streamUrl);
      });
    } catch (e) {
      print('Error playing track: $e');
      rethrow;
    }
  }

  Future<void> _analyzeAudioStream(String streamUrl) async {
    try {
      // Try to get basic info from HTTP headers
      final response = await http.head(Uri.parse(streamUrl));
      
      String? contentType = response.headers['content-type'];
      String? contentLength = response.headers['content-length'];
      
      // Determine format from content type
      String? format;
      if (contentType?.contains('audio/mpeg') == true) {
        format = 'MP3';
      } else if (contentType?.contains('audio/flac') == true) {
        format = 'FLAC';
      } else if (contentType?.contains('audio/wav') == true) {
        format = 'WAV';
      } else if (contentType?.contains('audio/aac') == true) {
        format = 'AAC';
      }
      
      // Estimate bitrate if we have duration and file size
      int? estimatedBitrate;
      if (_currentTrack?.duration != null && contentLength != null) {
        try {
          final fileSizeBytes = int.parse(contentLength);
          final durationSeconds = _currentTrack!.duration!;
          // Bitrate = (file size in bits) / duration in seconds / 1000 for kbps
          estimatedBitrate = ((fileSizeBytes * 8) / durationSeconds / 1000).round();
        } catch (e) {
          // Ignore parsing errors
        }
      }
      
      _audioOutputInfo = AudioOutputInfo(
        outputBitrate: estimatedBitrate ?? _currentTrack?.bitrate,
        outputSampleRate: _currentTrack?.sampleRate,
        outputBitDepth: _currentTrack?.bitDepth,
        format: format ?? _currentTrack?.quality,
        codec: format,
      );
      
      print('Audio Output Info: ${_audioOutputInfo.formattedOutputQuality}');
    } catch (e) {
      print('Could not analyze audio stream: $e');
      // Fallback to track metadata if available
      if (_currentTrack != null) {
        _audioOutputInfo = AudioOutputInfo(
          outputBitrate: _currentTrack!.bitrate,
          outputSampleRate: _currentTrack!.sampleRate,
          outputBitDepth: _currentTrack!.bitDepth,
          format: _currentTrack!.quality,
        );
      }
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
    _audioOutputInfo = AudioOutputInfo();
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