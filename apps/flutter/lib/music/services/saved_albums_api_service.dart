import 'dart:convert';
import '../../core/models/api_response.dart';
import '../models/music.dart';
import '../../core/services/base_api_service.dart';

/// API service for saved albums operations
class SavedAlbumsApiService extends BaseApiService {
  
  /// Save an album to the user's collection
  static Future<ApiResponse<SavedAlbum>> saveAlbum(SaveAlbumRequest request) async {
    try {
      final response = await BaseApiService.post(
        '/albums/save',
        body: request.toJson(),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        return ApiResponse<SavedAlbum>.fromJson(
          json,
          (data) => SavedAlbum.fromJson(data as Map<String, dynamic>),
        );
      } else {
        final json = jsonDecode(response.body);
        return ApiResponse<SavedAlbum>(
          success: false,
          message: json['message'] ?? 'Failed to save album',
        );
      }
    } catch (e) {
      return ApiResponse<SavedAlbum>(
        success: false,
        message: 'Network error: $e',
      );
    }
  }

  /// Get all saved albums for the current user
  static Future<ApiResponse<List<SavedAlbum>>> getSavedAlbums({
    int page = 1,
    int limit = 50,
  }) async {
    try {
      final response = await BaseApiService.get(
        '/albums/saved',
        queryParams: {
          'page': page.toString(),
          'limit': limit.toString(),
        },
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        return ApiResponse<List<SavedAlbum>>.fromJson(
          json,
          (data) => (data as List)
              .map((item) => SavedAlbum.fromJson(item as Map<String, dynamic>))
              .toList(),
        );
      } else {
        final json = jsonDecode(response.body);
        return ApiResponse<List<SavedAlbum>>(
          success: false,
          message: json['message'] ?? 'Failed to load saved albums',
        );
      }
    } catch (e) {
      return ApiResponse<List<SavedAlbum>>(
        success: false,
        message: 'Network error: $e',
      );
    }
  }

  /// Remove an album from the user's collection
  static Future<ApiResponse<String>> removeSavedAlbum(String albumId) async {
    try {
      final response = await BaseApiService.delete('/albums/saved/$albumId');

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        return ApiResponse<String>.fromJson(
          json,
          (data) => data as String,
        );
      } else {
        final json = jsonDecode(response.body);
        return ApiResponse<String>(
          success: false,
          message: json['message'] ?? 'Failed to remove album',
        );
      }
    } catch (e) {
      return ApiResponse<String>(
        success: false,
        message: 'Network error: $e',
      );
    }
  }

  /// Check if an album is saved
  static Future<ApiResponse<bool>> isAlbumSaved(String albumId, String source) async {
    try {
      final response = await BaseApiService.get(
        '/albums/saved/check',
        queryParams: {
          'album_id': albumId,
          'source': source,
        },
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        return ApiResponse<bool>.fromJson(
          json,
          (data) => data as bool,
        );
      } else {
        return ApiResponse<bool>(
          success: false,
          data: false,
          message: 'Failed to check album status',
        );
      }
    } catch (e) {
      return ApiResponse<bool>(
        success: false,
        data: false,
        message: 'Network error: $e',
      );
    }
  }

  /// Get album tracks for a saved album
  static Future<ApiResponse<List<Track>>> getAlbumTracks(String albumId, String source) async {
    try {
      final response = await BaseApiService.get(
        '/albums/$albumId/tracks',
        queryParams: {
          'source': source,
        },
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        return ApiResponse<List<Track>>.fromJson(
          json,
          (data) => (data as List)
              .map((item) => Track.fromJson(item as Map<String, dynamic>))
              .toList(),
        );
      } else {
        final json = jsonDecode(response.body);
        return ApiResponse<List<Track>>(
          success: false,
          message: json['message'] ?? 'Failed to load album tracks',
        );
      }
    } catch (e) {
      return ApiResponse<List<Track>>(
        success: false,
        message: 'Network error: $e',
      );
    }
  }
}
