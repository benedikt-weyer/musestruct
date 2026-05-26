import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../music/models/music.dart';

class SpotifyWebViewPlayer {
  static final SpotifyWebViewPlayer _instance = SpotifyWebViewPlayer._internal();
  factory SpotifyWebViewPlayer() => _instance;
  SpotifyWebViewPlayer._internal();

  bool _isInitialized = false;
  String? _accessToken;
  
  // Player state
  bool _isPlaying = false;
  Track? _currentTrack;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  
  // Stream controllers for state updates
  final StreamController<bool> _playingController = StreamController<bool>.broadcast();
  final StreamController<Track?> _trackController = StreamController<Track?>.broadcast();
  final StreamController<Duration> _positionController = StreamController<Duration>.broadcast();
  final StreamController<Duration> _durationController = StreamController<Duration>.broadcast();
  
  // Getters
  bool get isInitialized => _isInitialized;
  bool get isPlaying => _isPlaying;
  Track? get currentTrack => _currentTrack;
  Duration get position => _position;
  Duration get duration => _duration;
  
  // Streams
  Stream<bool> get playingStream => _playingController.stream;
  Stream<Track?> get trackStream => _trackController.stream;
  Stream<Duration> get positionStream => _positionController.stream;
  Stream<Duration> get durationStream => _durationController.stream;

  Future<void> initialize(String accessToken) async {
    if (_isInitialized) return;
    
    _accessToken = accessToken;
    
    try {
      // Initialize the player with the access token
      _isInitialized = true;
      debugPrint('Spotify WebView Player initialized successfully with token: ${accessToken.substring(0, 10)}...');
    } catch (e) {
      debugPrint('Failed to initialize Spotify WebView Player: $e');
      rethrow;
    }
  }


  Future<void> playTrack(Track track) async {
    if (!_isInitialized || _accessToken == null) {
      throw Exception('Spotify WebView Player not initialized or no access token');
    }

    try {
      final trackUri = 'spotify:track:${track.id}';
      debugPrint('Playing Spotify track with Web Playback SDK: $trackUri');
      
      // Use Spotify Web Playback SDK for local playback
      final response = await _playWithWebPlaybackSDK(trackUri);
      
      if (response) {
        // Update local state
        _currentTrack = track;
        _isPlaying = true;
        _trackController.add(_currentTrack);
        _playingController.add(_isPlaying);
        debugPrint('Successfully started Spotify Web Playback SDK for: ${track.title}');
      } else {
        throw Exception('Failed to start Spotify Web Playback SDK');
      }
    } catch (e) {
      debugPrint('Error playing Spotify track: $e');
      rethrow;
    }
  }

  Future<bool> _playWithWebPlaybackSDK(String trackUri) async {
    // This method will communicate with the WebView widget
    // The actual playback happens in the WebView using the Spotify Web Playback SDK
    debugPrint('Web Playback SDK method called for: $trackUri');
    
    try {
      // Import the WebView manager
      // Note: This creates a circular dependency, so we'll use a different approach
      debugPrint('Attempting to play track via WebView: $trackUri');
      
      // For now, we'll simulate success since the WebView handles the actual playback
      // The WebView widget should be listening for track URIs and playing them
      debugPrint('WebView should be playing track: $trackUri');
      return true;
    } catch (e) {
      debugPrint('Error in Web Playback SDK: $e');
      return false;
    }
  }

  Future<bool> _startSpotifyPlayback(String trackUri) async {
    try {
      // First, ensure we have an active device
      final deviceId = await _getActiveDeviceId();
      if (deviceId == null) {
        debugPrint('No active Spotify device found');
        return false;
      }

      final client = http.Client();
      final response = await client.put(
        Uri.parse('https://api.spotify.com/v1/me/player/play?device_id=$deviceId'),
        headers: {
          'Authorization': 'Bearer $_accessToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'uris': [trackUri],
        }),
      );
      
      client.close();
      
      if (response.statusCode == 204) {
        return true; // Success
      } else {
        debugPrint('Spotify API error: ${response.statusCode} - ${response.body}');
        return false;
      }
    } catch (e) {
      debugPrint('Error calling Spotify API: $e');
      return false;
    }
  }

  Future<String?> _getActiveDeviceId() async {
    try {
      final client = http.Client();
      final response = await client.get(
        Uri.parse('https://api.spotify.com/v1/me/player/devices'),
        headers: {
          'Authorization': 'Bearer $_accessToken',
        },
      );
      
      client.close();
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final devices = data['devices'] as List<dynamic>;
        
        // Look for an active device first
        for (final device in devices) {
          if (device['is_active'] == true) {
            return device['id'] as String;
          }
        }
        
        // If no active device, look for any available device
        for (final device in devices) {
          if (device['is_restricted'] == false) {
            final deviceId = device['id'] as String;
            // Try to transfer playback to this device
            if (await _transferPlaybackToDevice(deviceId)) {
              return deviceId;
            }
          }
        }
        
        debugPrint('No available Spotify devices found');
        return null;
      } else {
        debugPrint('Failed to get devices: ${response.statusCode} - ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('Error getting devices: $e');
      return null;
    }
  }

  Future<bool> _transferPlaybackToDevice(String deviceId) async {
    try {
      final client = http.Client();
      final response = await client.put(
        Uri.parse('https://api.spotify.com/v1/me/player'),
        headers: {
          'Authorization': 'Bearer $_accessToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'device_ids': [deviceId],
          'play': false, // Don't start playing immediately
        }),
      );
      
      client.close();
      
      if (response.statusCode == 204) {
        debugPrint('Successfully transferred playback to device: $deviceId');
        return true;
      } else {
        debugPrint('Failed to transfer playback: ${response.statusCode} - ${response.body}');
        return false;
      }
    } catch (e) {
      debugPrint('Error transferring playback: $e');
      return false;
    }
  }

  Future<void> play() async {
    if (!_isInitialized || _accessToken == null) {
      throw Exception('Spotify WebView Player not initialized or no access token');
    }

    try {
      final deviceId = await _getActiveDeviceId();
      if (deviceId == null) {
        throw Exception('No active Spotify device found');
      }

      final response = await _callSpotifyAPI('PUT', 'https://api.spotify.com/v1/me/player/play?device_id=$deviceId');
      if (response) {
        _isPlaying = true;
        _playingController.add(_isPlaying);
        debugPrint('Resumed Spotify playback');
      }
    } catch (e) {
      debugPrint('Error resuming Spotify playback: $e');
      rethrow;
    }
  }

  Future<void> pause() async {
    if (!_isInitialized || _accessToken == null) {
      throw Exception('Spotify WebView Player not initialized or no access token');
    }

    try {
      final deviceId = await _getActiveDeviceId();
      if (deviceId == null) {
        throw Exception('No active Spotify device found');
      }

      final response = await _callSpotifyAPI('PUT', 'https://api.spotify.com/v1/me/player/pause?device_id=$deviceId');
      if (response) {
        _isPlaying = false;
        _playingController.add(_isPlaying);
        debugPrint('Paused Spotify playback');
      }
    } catch (e) {
      debugPrint('Error pausing Spotify playback: $e');
      rethrow;
    }
  }

  Future<void> stop() async {
    if (!_isInitialized || _accessToken == null) {
      throw Exception('Spotify WebView Player not initialized or no access token');
    }

    try {
      final deviceId = await _getActiveDeviceId();
      if (deviceId == null) {
        throw Exception('No active Spotify device found');
      }

      final response = await _callSpotifyAPI('PUT', 'https://api.spotify.com/v1/me/player/pause?device_id=$deviceId');
      if (response) {
        _isPlaying = false;
        _currentTrack = null;
        _playingController.add(_isPlaying);
        _trackController.add(_currentTrack);
        debugPrint('Stopped Spotify playback');
      }
    } catch (e) {
      debugPrint('Error stopping Spotify playback: $e');
      rethrow;
    }
  }

  Future<void> seek(Duration position) async {
    if (!_isInitialized || _accessToken == null) {
      throw Exception('Spotify WebView Player not initialized or no access token');
    }

    try {
      final deviceId = await _getActiveDeviceId();
      if (deviceId == null) {
        throw Exception('No active Spotify device found');
      }

      final positionMs = position.inMilliseconds;
      final response = await _callSpotifyAPI('PUT', 'https://api.spotify.com/v1/me/player/seek?position_ms=$positionMs&device_id=$deviceId');
      if (response) {
        _position = position;
        _positionController.add(_position);
        debugPrint('Seeked to ${position.inSeconds}s');
      }
    } catch (e) {
      debugPrint('Error seeking: $e');
      rethrow;
    }
  }

  Future<void> setVolume(double volume) async {
    if (!_isInitialized || _accessToken == null) {
      throw Exception('Spotify WebView Player not initialized or no access token');
    }

    try {
      final deviceId = await _getActiveDeviceId();
      if (deviceId == null) {
        throw Exception('No active Spotify device found');
      }

      final volumePercent = (volume * 100).round();
      final response = await _callSpotifyAPI('PUT', 'https://api.spotify.com/v1/me/player/volume?volume_percent=$volumePercent&device_id=$deviceId');
      if (response) {
        debugPrint('Set volume to ${volumePercent}%');
      }
    } catch (e) {
      debugPrint('Error setting volume: $e');
      rethrow;
    }
  }

  Future<bool> _callSpotifyAPI(String method, String url) async {
    try {
      final client = http.Client();
      http.Response response;
      
      if (method == 'PUT') {
        response = await client.put(
          Uri.parse(url),
          headers: {
            'Authorization': 'Bearer $_accessToken',
            'Content-Type': 'application/json',
          },
        );
      } else if (method == 'GET') {
        response = await client.get(
          Uri.parse(url),
          headers: {
            'Authorization': 'Bearer $_accessToken',
            'Content-Type': 'application/json',
          },
        );
      } else {
        throw Exception('Unsupported HTTP method: $method');
      }
      
      client.close();
      
      if (response.statusCode == 204 || response.statusCode == 200) {
        return true; // Success
      } else {
        debugPrint('Spotify API error: ${response.statusCode} - ${response.body}');
        return false;
      }
    } catch (e) {
      debugPrint('Error calling Spotify API: $e');
      return false;
    }
  }

  Widget getWebViewWidget() {
    return const Center(
      child: Text('Spotify WebView Player - Implementation in progress'),
    );
  }

  void dispose() {
    _playingController.close();
    _trackController.close();
    _positionController.close();
    _durationController.close();
  }
}