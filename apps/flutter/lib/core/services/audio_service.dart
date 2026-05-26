import 'package:audioplayers/audioplayers.dart';
import 'package:http/http.dart' as http;
import '../../music/models/music.dart';
import 'dart:async';
import 'audio_service_handler.dart';

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
  
  // Audio service handler for media controls (MPRIS on Linux, notifications on Android/iOS, etc.)
  MusestructAudioHandler? _audioServiceHandler;

  AudioPlayer get player => _player;
  Track? get currentTrack => _currentTrack;
  bool get isInitialized => _isInitialized;
  bool get isPlaying => _isPlaying;
  Duration get position => _position;
  Duration get duration => _duration;
  AudioOutputInfo get audioOutputInfo => _audioOutputInfo;
  
  // Set the audio service handler
  void setAudioServiceHandler(MusestructAudioHandler handler) {
    _audioServiceHandler = handler;
    print('AudioService: Audio service handler set for media controls');
  }

  // Stream controllers for state management
  Stream<bool> get playingStream => _player.onPlayerStateChanged.map((state) => state == PlayerState.playing);
  Stream<Duration> get positionStream => _player.onPositionChanged;
  Stream<Duration> get durationStream => _player.onDurationChanged;
  
  // Stream for completion detection
  Stream<bool> get completionStream => _player.onPlayerStateChanged.map((state) => state == PlayerState.completed);

  Future<void> initialize() async {
    if (!_isInitialized) {
      try {
        // Configure player for background processing
        await _player.setReleaseMode(ReleaseMode.stop);
        
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
        print('AudioService initialized successfully');
      } catch (e) {
        print('Error initializing AudioService: $e');
        rethrow;
      }
    }
  }

  Future<void> playTrack(Track track, String streamUrl) async {
    try {
      _currentTrack = track;
      _duration = track.duration != null ? Duration(seconds: track.duration!) : Duration.zero;
      _position = Duration.zero;
      print('AudioService: Starting playback for ${track.title} from $streamUrl');
      
      // Update audio service handler with track info
      _audioServiceHandler?.updateTrackInfo(track);
      
      // Set a longer timeout for the play operation
      await _player.play(UrlSource(streamUrl)).timeout(
        const Duration(seconds: 45),
        onTimeout: () {
          throw TimeoutException('Audio playback timed out after 45 seconds. The audio file may be too large or the network connection is slow.', const Duration(seconds: 45));
        },
      );
      
      // Mark as playing immediately after starting playback
      _isPlaying = true;
      
      // Analyze audio stream for real-time info (with delay to ensure playback started)
      Timer(const Duration(seconds: 2), () {
        _analyzeAudioStream(streamUrl);
      });
    } catch (e) {
      print('Error playing track: $e');
      
      // Provide more user-friendly error messages
      if (e is TimeoutException) {
        throw Exception('Playback timed out: ${e.message}');
      } else if (e.toString().contains('AndroidAudioError')) {
        throw Exception('Audio playback failed. Please check your internet connection and try again.');
      } else {
        throw Exception('Failed to play track: ${e.toString()}');
      }
    }
  }

  Future<void> _analyzeAudioStream(String streamUrl) async {
    try {
      // Try to get basic info from HTTP headers with timeout
      final response = await http.head(Uri.parse(streamUrl)).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          print('AudioService: HTTP HEAD request timed out for $streamUrl');
          throw TimeoutException('HTTP HEAD request timed out', const Duration(seconds: 10));
        },
      );
      
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
    // Audio service handler will be notified via the playing stream listener
  }

  Future<void> pause() async {
    await _player.pause();
    // Audio service handler will be notified via the playing stream listener
  }

  Future<void> stop() async {
    await _player.stop();
    _currentTrack = null;
    _audioOutputInfo = AudioOutputInfo();
    _audioServiceHandler?.clearMediaItem();
  }

  Future<void> seek(Duration position) async {
    try {
      // Validate position
      if (position < Duration.zero) {
        throw ArgumentError('Seek position cannot be negative');
      }
      
      if (_duration > Duration.zero && position > _duration) {
        throw ArgumentError('Seek position cannot exceed track duration');
      }
      
      await _player.seek(position);
      _position = position;
      print('AudioService: Successfully seeked to ${position.inSeconds}s');
    } catch (e) {
      print('AudioService: Seek error: $e');
      rethrow;
    }
  }

  Future<void> setVolume(double volume) async {
    await _player.setVolume(volume);
  }

  // Check if seeking is supported for the current track
  bool get isSeekSupported {
    if (_currentTrack == null) return false;
    
    // Check if this is a backend stream URL (cached file)
    if (_currentTrack!.streamUrl != null && 
        _currentTrack!.streamUrl!.contains('/api/stream/')) {
      // Backend streams are cached local files, so seeking is supported
      return true;
    }
    
    // Some streaming formats don't support seeking on Linux
    final source = _currentTrack!.source.toLowerCase();
    if (source == 'qobuz' || source == 'tidal') {
      // These services often use streaming formats that don't support seeking on Linux
      return false;
    }
    
    return true;
  }

  // Get current state for background updates
  Map<String, dynamic> getCurrentState() {
    return {
      'isPlaying': _isPlaying,
      'position': _position.inMilliseconds,
      'duration': _duration.inMilliseconds,
      'trackTitle': _currentTrack?.title ?? '',
      'trackArtist': _currentTrack?.artist ?? '',
      'isSeekSupported': isSeekSupported,
    };
  }

  void dispose() {
    _player.dispose();
  }
}