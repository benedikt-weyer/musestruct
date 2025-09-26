import 'dart:convert';
import '../../models/api_response.dart';
import '../../models/music.dart';
import '../providers/queue_provider.dart';
import '../../core/services/base_api_service.dart';

/// API service for queue management operations
class QueueApiService extends BaseApiService {
  
  /// Get the current user's queue
  static Future<ApiResponse<List<QueueItem>>> getQueue() async {
    try {
      final response = await BaseApiService.get('/queue');

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        final List<dynamic> queueData = json['data'] ?? [];
        final queueItems = queueData.map((item) => QueueItem.fromJson(item)).toList();
        return ApiResponse<List<QueueItem>>.success(queueItems);
      } else {
        final json = jsonDecode(response.body);
        return ApiResponse<List<QueueItem>>.error(json['message'] ?? 'Failed to get queue');
      }
    } catch (e) {
      return ApiResponse<List<QueueItem>>.error('Network error: $e');
    }
  }

  /// Add a track to the queue
  static Future<ApiResponse<bool>> addToQueue(Track track) async {
    try {
      final response = await BaseApiService.post(
        '/queue',
        body: {
          'track_id': track.id,
          'title': track.title,
          'artist': track.artist,
          'album': track.album,
          'duration': track.duration ?? 0,
          'source': track.source,
          'cover_url': track.coverUrl,
        },
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final json = jsonDecode(response.body);
        if (json['success'] == true) {
          return ApiResponse<bool>.success(true);
        } else {
          return ApiResponse<bool>.error(json['message'] ?? 'Failed to add track to queue');
        }
      } else {
        final json = jsonDecode(response.body);
        return ApiResponse<bool>.error(json['message'] ?? 'Failed to add track to queue');
      }
    } catch (e) {
      return ApiResponse<bool>.error('Network error: $e');
    }
  }

  /// Remove a track from the queue
  static Future<ApiResponse<bool>> removeFromQueue(String queueItemId) async {
    try {
      final response = await BaseApiService.delete('/queue/$queueItemId');

      if (response.statusCode == 200 || response.statusCode == 204) {
        final json = jsonDecode(response.body);
        if (json['success'] == true) {
          return ApiResponse<bool>.success(true);
        } else {
          return ApiResponse<bool>.error(json['message'] ?? 'Failed to remove track from queue');
        }
      } else {
        final json = jsonDecode(response.body);
        return ApiResponse<bool>.error(json['message'] ?? 'Failed to remove track from queue');
      }
    } catch (e) {
      return ApiResponse<bool>.error('Network error: $e');
    }
  }

  /// Reorder a track in the queue
  static Future<ApiResponse<bool>> reorderQueue(String queueItemId, int newPosition) async {
    try {
      final response = await BaseApiService.put(
        '/queue/$queueItemId/reorder',
        body: {'new_position': newPosition},
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        if (json['success'] == true) {
          return ApiResponse<bool>.success(true);
        } else {
          return ApiResponse<bool>.error(json['message'] ?? 'Failed to reorder queue');
        }
      } else {
        final json = jsonDecode(response.body);
        return ApiResponse<bool>.error(json['message'] ?? 'Failed to reorder queue');
      }
    } catch (e) {
      return ApiResponse<bool>.error('Network error: $e');
    }
  }

  /// Clear all tracks from the queue
  static Future<ApiResponse<bool>> clearQueue() async {
    try {
      final response = await BaseApiService.delete('/queue');

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        if (json['success'] == true) {
          return ApiResponse<bool>.success(true);
        } else {
          return ApiResponse<bool>.error(json['message'] ?? 'Failed to clear queue');
        }
      } else {
        final json = jsonDecode(response.body);
        return ApiResponse<bool>.error(json['message'] ?? 'Failed to clear queue');
      }
    } catch (e) {
      return ApiResponse<bool>.error('Network error: $e');
    }
  }
}
