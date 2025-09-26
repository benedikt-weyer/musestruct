import 'package:flutter/foundation.dart';
import 'dart:async';
import '../../models/music.dart';
import '../services/queue_api_service.dart';

class QueueProvider with ChangeNotifier {
  List<QueueItem> _queue = [];
  List<PlaylistQueueItem> _playlistQueue = [];
  bool _isLoading = false;
  String? _error;

  List<QueueItem> get queue => _queue;
  List<PlaylistQueueItem> get playlistQueue => _playlistQueue;
  bool get isLoading => _isLoading;
  String? get error => _error;
  int get queueLength => _queue.length + _playlistQueue.length;

  QueueProvider() {
    // Don't load queue immediately - wait for authentication
  }

  Future<void> _loadQueue() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await QueueApiService.getQueue();
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

      final response = await QueueApiService.addToQueue(track);
      if (response.success) {
        // Reload queue to get updated positions
        try {
          await _loadQueue();
        } catch (e) {
          print('Error reloading queue: $e');
        }
        return true;
      } else {
        _error = response.message ?? 'Failed to add track to queue';
        notifyListeners();
        return false;
      }
    } catch (e) {
      _error = 'Failed to add track to queue: $e';
      notifyListeners();
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

      final response = await QueueApiService.removeFromQueue(queueItemId);
      if (response.success) {
        // Reload queue to get updated positions
        try {
          await _loadQueue();
        } catch (e) {
          print('Error reloading queue: $e');
        }
        return true;
      } else {
        _error = response.message ?? 'Failed to remove track from queue';
        notifyListeners();
        return false;
      }
    } catch (e) {
      _error = 'Failed to remove track from queue: $e';
      notifyListeners();
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

      final response = await QueueApiService.reorderQueue(queueItemId, newPosition);
      if (response.success) {
        // Reload queue to get updated positions
        try {
          await _loadQueue();
        } catch (e) {
          print('Error reloading queue: $e');
        }
        return true;
      } else {
        _error = response.message ?? 'Failed to reorder queue';
        notifyListeners();
        return false;
      }
    } catch (e) {
      _error = 'Failed to reorder queue: $e';
      notifyListeners();
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

      final response = await QueueApiService.clearQueue();
      if (response.success) {
        _queue.clear();
        notifyListeners();
        return true;
      } else {
        _error = response.message ?? 'Failed to clear queue';
        notifyListeners();
        return false;
      }
    } catch (e) {
      _error = 'Failed to clear queue: $e';
      notifyListeners();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> refreshQueue() async {
    await _loadQueue();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  QueueItem? getNextTrack() {
    if (_queue.isEmpty) return null;
    return _queue.first;
  }

  Future<void> moveToNext() async {
    if (_queue.isNotEmpty) {
      await removeFromQueue(_queue.first.id);
    }
  }

  Future<void> initialize() async {
    await _loadQueue();
  }

  // Playlist Queue Methods
  Future<bool> addPlaylistToQueue({
    required String playlistId,
    required String playlistName,
    String? playlistDescription,
    String? coverUrl,
    PlayMode playMode = PlayMode.normal,
    LoopMode loopMode = LoopMode.once,
    required List<String> trackOrder,
    String? currentTrackId,
    String? currentTrackTitle,
    String? currentTrackArtist,
    String? currentTrackAlbum,
    int? currentTrackDuration,
    String? currentTrackSource,
    String? currentTrackCoverUrl,
  }) async {
    try {
      _isLoading = true;
      notifyListeners();

      // Create playlist queue item
      final playlistQueueItem = PlaylistQueueItem(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        playlistId: playlistId,
        playlistName: playlistName,
        playlistDescription: playlistDescription,
        coverUrl: coverUrl,
        playMode: playMode,
        loopMode: loopMode,
        trackOrder: trackOrder,
        currentTrackIndex: 0,
        addedAt: DateTime.now(),
        currentTrackId: currentTrackId,
        currentTrackTitle: currentTrackTitle,
        currentTrackArtist: currentTrackArtist,
        currentTrackAlbum: currentTrackAlbum,
        currentTrackDuration: currentTrackDuration,
        currentTrackSource: currentTrackSource,
        currentTrackCoverUrl: currentTrackCoverUrl,
      );

      // Add to playlist queue
      _playlistQueue.add(playlistQueueItem);
      notifyListeners();

      return true;
    } catch (e) {
      _error = 'Failed to add playlist to queue: $e';
      notifyListeners();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> removePlaylistFromQueue(String playlistQueueItemId) async {
    try {
      _isLoading = true;
      notifyListeners();

      _playlistQueue.removeWhere((item) => item.id == playlistQueueItemId);
      notifyListeners();

      return true;
    } catch (e) {
      _error = 'Failed to remove playlist from queue: $e';
      notifyListeners();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> updatePlaylistQueueItem(PlaylistQueueItem updatedItem) async {
    try {
      _isLoading = true;
      notifyListeners();

      final index = _playlistQueue.indexWhere((item) => item.id == updatedItem.id);
      if (index != -1) {
        _playlistQueue[index] = updatedItem;
        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      _error = 'Failed to update playlist queue item: $e';
      notifyListeners();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  PlaylistQueueItem? getCurrentPlaylistQueueItem() {
    if (_playlistQueue.isEmpty) return null;
    return _playlistQueue.first;
  }

  String? getCurrentTrackId() {
    final currentPlaylist = getCurrentPlaylistQueueItem();
    if (currentPlaylist == null) return null;
    
    if (currentPlaylist.currentTrackIndex >= currentPlaylist.trackOrder.length) {
      return null;
    }
    
    return currentPlaylist.trackOrder[currentPlaylist.currentTrackIndex];
  }

  Future<bool> moveToNextTrack() async {
    final currentPlaylist = getCurrentPlaylistQueueItem();
    if (currentPlaylist == null) return false;

    final nextIndex = currentPlaylist.currentTrackIndex + 1;
    
    // Check if we've reached the end of the playlist
    if (nextIndex >= currentPlaylist.trackOrder.length) {
      // Handle loop modes
      switch (currentPlaylist.loopMode) {
        case LoopMode.once:
          // Remove playlist from queue
          return await removePlaylistFromQueue(currentPlaylist.id);
        case LoopMode.twice:
          // Check if we've played twice
          if (currentPlaylist.currentTrackIndex >= currentPlaylist.trackOrder.length * 2) {
            return await removePlaylistFromQueue(currentPlaylist.id);
          }
          // Reset to beginning for second play
          final updatedItem = currentPlaylist.copyWith(
            currentTrackIndex: 0,
          );
          return await updatePlaylistQueueItem(updatedItem);
        case LoopMode.infinite:
          // Reset to beginning
          final updatedItem = currentPlaylist.copyWith(
            currentTrackIndex: 0,
          );
          return await updatePlaylistQueueItem(updatedItem);
      }
    }

    // Move to next track
    final updatedItem = currentPlaylist.copyWith(
      currentTrackIndex: nextIndex,
    );
    return await updatePlaylistQueueItem(updatedItem);
  }

  Future<bool> moveToPreviousTrack() async {
    final currentPlaylist = getCurrentPlaylistQueueItem();
    if (currentPlaylist == null) return false;

    final prevIndex = currentPlaylist.currentTrackIndex - 1;
    
    if (prevIndex < 0) {
      // Handle loop modes for going backwards
      switch (currentPlaylist.loopMode) {
        case LoopMode.once:
          return false; // Can't go back from first track
        case LoopMode.twice:
        case LoopMode.infinite:
          // Go to last track
          final updatedItem = currentPlaylist.copyWith(
            currentTrackIndex: currentPlaylist.trackOrder.length - 1,
          );
          return await updatePlaylistQueueItem(updatedItem);
      }
    }

    // Move to previous track
    final updatedItem = currentPlaylist.copyWith(
      currentTrackIndex: prevIndex,
    );
    return await updatePlaylistQueueItem(updatedItem);
  }

  void clearPlaylistQueue() {
    _playlistQueue.clear();
    notifyListeners();
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