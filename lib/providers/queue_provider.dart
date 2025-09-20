import 'package:flutter/foundation.dart';
import 'dart:async';
import '../models/music.dart';
import '../services/api_service.dart';

class QueueProvider with ChangeNotifier {
  List<QueueItem> _queue = [];
  bool _isLoading = false;
  String? _error;

  List<QueueItem> get queue => _queue;
  bool get isLoading => _isLoading;
  String? get error => _error;
  int get queueLength => _queue.length;

  QueueProvider() {
    // Don't load queue immediately - wait for authentication
  }

  Future<void> _loadQueue() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await ApiService.getQueue();
      if (response.success && response.data != null) {
        _queue = response.data!;
      } else {
        _error = response.message ?? 'Failed to load queue';
      }
    } catch (e) {
      _error = 'Failed to load queue: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> addToQueue(Track track) async {
    try {
      _isLoading = true;
      notifyListeners();

      final response = await ApiService.addToQueue(track);
      if (response.success) {
        // Reload queue to get updated positions
        try {
          await _loadQueue();
        } catch (e) {
          // If reload fails, just clear the error and continue
          print('Warning: Failed to reload queue after adding track: $e');
        }
        return true;
      } else {
        _error = response.message ?? 'Failed to add track to queue';
        return false;
      }
    } catch (e) {
      _error = 'Failed to add track to queue: $e';
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> removeFromQueue(String queueItemId) async {
    try {
      _isLoading = true;
      notifyListeners();

      final response = await ApiService.removeFromQueue(queueItemId);
      if (response.success) {
        await _loadQueue(); // Reload queue to get updated positions
        return true;
      } else {
        _error = response.message ?? 'Failed to remove track from queue';
        return false;
      }
    } catch (e) {
      _error = 'Failed to remove track from queue: $e';
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> reorderQueue(String queueItemId, int newPosition) async {
    try {
      _isLoading = true;
      notifyListeners();

      final response = await ApiService.reorderQueue(queueItemId, newPosition);
      if (response.success) {
        await _loadQueue(); // Reload queue to get updated positions
        return true;
      } else {
        _error = response.message ?? 'Failed to reorder queue';
        return false;
      }
    } catch (e) {
      _error = 'Failed to reorder queue: $e';
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> clearQueue() async {
    try {
      _isLoading = true;
      notifyListeners();

      final response = await ApiService.clearQueue();
      if (response.success) {
        _queue.clear();
        return true;
      } else {
        _error = response.message ?? 'Failed to clear queue';
        return false;
      }
    } catch (e) {
      _error = 'Failed to clear queue: $e';
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> refreshQueue() async {
    await _loadQueue();
  }

  // Get next track in queue
  QueueItem? getNextTrack() {
    if (_queue.isEmpty) return null;
    return _queue.first;
  }

  // Get track at specific position
  QueueItem? getTrackAt(int position) {
    if (position < 0 || position >= _queue.length) return null;
    return _queue[position];
  }

  // Move to next track (remove current track from queue)
  Future<bool> moveToNext() async {
    if (_queue.isEmpty) return false;
    
    final firstItem = _queue.first;
    return await removeFromQueue(firstItem.id);
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  // Initialize queue after authentication
  Future<void> initialize() async {
    await _loadQueue();
  }
}

class QueueItem {
  final String id;
  final String trackId;
  final String title;
  final String artist;
  final String album;
  final int duration;
  final String source;
  final String? coverUrl;
  final int position;
  final DateTime addedAt;

  QueueItem({
    required this.id,
    required this.trackId,
    required this.title,
    required this.artist,
    required this.album,
    required this.duration,
    required this.source,
    this.coverUrl,
    required this.position,
    required this.addedAt,
  });

  factory QueueItem.fromJson(Map<String, dynamic> json) {
    return QueueItem(
      id: json['id'] as String,
      trackId: json['track_id'] as String,
      title: json['title'] as String,
      artist: json['artist'] as String,
      album: json['album'] as String,
      duration: json['duration'] as int,
      source: json['source'] as String,
      coverUrl: json['cover_url'] as String?,
      position: json['position'] as int,
      addedAt: DateTime.parse(json['added_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'track_id': trackId,
      'title': title,
      'artist': artist,
      'album': album,
      'duration': duration,
      'source': source,
      'cover_url': coverUrl,
      'position': position,
      'added_at': addedAt.toIso8601String(),
    };
  }

  // Convert QueueItem to Track for playback
  Track toTrack() {
    return Track(
      id: trackId,
      title: title,
      artist: artist,
      album: album,
      duration: duration,
      streamUrl: null, // Will be fetched when playing
      coverUrl: coverUrl,
      source: source,
      quality: null,
      bitrate: null,
      sampleRate: null,
      bitDepth: null,
    );
  }

  String get formattedDuration {
    final minutes = duration ~/ 60;
    final seconds = duration % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  String get formattedSource {
    switch (source.toLowerCase()) {
      case 'qobuz':
        return 'Qobuz';
      case 'spotify':
        return 'Spotify';
      case 'tidal':
        return 'Tidal';
      case 'apple_music':
        return 'Apple Music';
      case 'youtube_music':
        return 'YouTube Music';
      case 'deezer':
        return 'Deezer';
      default:
        return source.isNotEmpty ? source.toUpperCase() : 'Streaming';
    }
  }
}
