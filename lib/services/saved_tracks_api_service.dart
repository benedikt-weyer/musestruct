import 'dart:convert';
import '../models/api_response.dart';
import '../models/music.dart';
import 'base_api_service.dart';

/// API service for saved tracks operations
class SavedTracksApiService extends BaseApiService {
  
  /// Save a track to user's saved tracks
  static Future<ApiResponse<SavedTrack>> saveTrack(SaveTrackRequest request) async {
    try {
      print('Saving track: ${request.toJson()}');
      final headers = await BaseApiService.getAuthHeaders();
      print('Headers: $headers');
      
      final response = await BaseApiService.post(
        '/saved-tracks',
        body: request.toJson(),
      );

      print('Save track response status: ${response.statusCode}');
      print('Save track response body: ${response.body}');

      if (response.statusCode == 200) {
        if (response.body.isEmpty) {
          return ApiResponse<SavedTrack>.error('Empty response from server');
        }
        
        final json = jsonDecode(response.body);
        return ApiResponse<SavedTrack>.fromJson(json, (data) => SavedTrack.fromJson(data as Map<String, dynamic>));
      } else {
        if (response.body.isEmpty) {
          return ApiResponse<SavedTrack>.error('Server error: ${response.statusCode} - Empty response');
        }
        
        final json = jsonDecode(response.body);
        return ApiResponse<SavedTrack>.fromJson(json, (data) => SavedTrack.fromJson(data as Map<String, dynamic>));
      }
    } catch (e) {
      print('Error in saveTrack: $e');
      return ApiResponse<SavedTrack>.error('Network error: $e');
    }
  }

  /// Get user's saved tracks with pagination
  static Future<ApiResponse<List<SavedTrack>>> getSavedTracks({int page = 1, int limit = 50}) async {
    try {
      final headers = await BaseApiService.getAuthHeaders();
      print('Headers: $headers');
      
      final response = await BaseApiService.get(
        '/saved-tracks',
        queryParams: {
          'page': page.toString(),
          'limit': limit.toString(),
        },
      );

      print('Saved tracks response status: ${response.statusCode}');
      print('Saved tracks response body: ${response.body}');

      if (response.statusCode == 200) {
        if (response.body.isEmpty) {
          return ApiResponse<List<SavedTrack>>.error('Empty response from server');
        }
        
        final json = jsonDecode(response.body);
        return ApiResponse<List<SavedTrack>>.fromJson(
          json, 
          (data) => (data as List).map((item) => SavedTrack.fromJson(item as Map<String, dynamic>)).toList()
        );
      } else {
        if (response.body.isEmpty) {
          return ApiResponse<List<SavedTrack>>.error('Server error: ${response.statusCode} - Empty response');
        }
        
        final json = jsonDecode(response.body);
        return ApiResponse<List<SavedTrack>>.fromJson(
          json, 
          (data) => (data as List).map((item) => SavedTrack.fromJson(item as Map<String, dynamic>)).toList()
        );
      }
    } catch (e) {
      print('Error in getSavedTracks: $e');
      return ApiResponse<List<SavedTrack>>.error('Network error: $e');
    }
  }

  /// Remove a saved track
  static Future<ApiResponse<void>> removeSavedTrack(String trackId) async {
    try {
      final response = await BaseApiService.delete('/saved-tracks/$trackId');

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        return ApiResponse<void>.fromJson(json, (data) => null);
      } else {
        final json = jsonDecode(response.body);
        return ApiResponse<void>.fromJson(json, (data) => null);
      }
    } catch (e) {
      return ApiResponse<void>.error('Network error: $e');
    }
  }

  /// Check if a track is saved
  static Future<ApiResponse<bool>> isTrackSaved(String trackId, String source) async {
    try {
      final response = await BaseApiService.get(
        '/saved-tracks/check',
        queryParams: {
          'track_id': trackId,
          'source': source,
        },
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        return ApiResponse<bool>.fromJson(json, (data) => data as bool);
      } else {
        final json = jsonDecode(response.body);
        return ApiResponse<bool>.fromJson(json, (data) => data as bool);
      }
    } catch (e) {
      return ApiResponse<bool>.error('Network error: $e');
    }
  }
}
