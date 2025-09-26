import 'dart:convert';
import '../models/api_response.dart';
import '../models/playlist.dart';
import 'base_api_service.dart';

/// API service for playlist management operations
class PlaylistApiService extends BaseApiService {
  
  /// Get all playlists with optional search and pagination
  static Future<ApiResponse<PlaylistListResponse>> getPlaylists({
    int page = 1,
    int perPage = 20,
    String? search,
  }) async {
    try {
      final params = <String, String>{
        'page': page.toString(),
        'per_page': perPage.toString(),
      };
      if (search != null && search.isNotEmpty) {
        params['search'] = search;
      }

      final apiBaseUrl = await BaseApiService.baseUrl;
      final headers = await BaseApiService.getAuthHeaders();
      print('PlaylistApiService: baseUrl = $apiBaseUrl');
      print('PlaylistApiService: Making request with params: $params');
      print('PlaylistApiService: Headers: $headers');
      
      final response = await BaseApiService.get(
        '/v2/playlists',
        queryParams: params,
      );
      
      print('PlaylistApiService: Response status: ${response.statusCode}');
      print('PlaylistApiService: Response body: ${response.body}');

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        return ApiResponse<PlaylistListResponse>.fromJson(
          json,
          (data) => PlaylistListResponse.fromJson(data as Map<String, dynamic>),
        );
      } else {
        final json = jsonDecode(response.body);
        return ApiResponse<PlaylistListResponse>(
          success: false,
          message: json['message'] ?? 'Failed to get playlists',
        );
      }
    } catch (e) {
      return ApiResponse<PlaylistListResponse>(
        success: false,
        message: 'Network error: $e',
      );
    }
  }

  /// Create a new playlist
  static Future<ApiResponse<Playlist>> createPlaylist(CreatePlaylistRequest request) async {
    try {
      final response = await BaseApiService.post(
        '/v2/playlists',
        body: request.toJson(),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final json = jsonDecode(response.body);
        return ApiResponse<Playlist>.fromJson(
          json,
          (data) => Playlist.fromJson(data as Map<String, dynamic>),
        );
      } else {
        final json = jsonDecode(response.body);
        return ApiResponse<Playlist>(
          success: false,
          message: json['message'] ?? 'Failed to create playlist',
        );
      }
    } catch (e) {
      return ApiResponse<Playlist>(
        success: false,
        message: 'Network error: $e',
      );
    }
  }

  /// Get a specific playlist by ID
  static Future<ApiResponse<Playlist>> getPlaylist(String playlistId) async {
    try {
      final response = await BaseApiService.get('/v2/playlists/$playlistId');

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        return ApiResponse<Playlist>.fromJson(
          json,
          (data) => Playlist.fromJson(data as Map<String, dynamic>),
        );
      } else {
        final json = jsonDecode(response.body);
        return ApiResponse<Playlist>(
          success: false,
          message: json['message'] ?? 'Failed to get playlist',
        );
      }
    } catch (e) {
      return ApiResponse<Playlist>(
        success: false,
        message: 'Network error: $e',
      );
    }
  }

  /// Update an existing playlist
  static Future<ApiResponse<Playlist>> updatePlaylist(
    String playlistId,
    UpdatePlaylistRequest request,
  ) async {
    try {
      final response = await BaseApiService.put(
        '/v2/playlists/$playlistId',
        body: request.toJson(),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        return ApiResponse<Playlist>.fromJson(
          json,
          (data) => Playlist.fromJson(data as Map<String, dynamic>),
        );
      } else {
        final json = jsonDecode(response.body);
        return ApiResponse<Playlist>(
          success: false,
          message: json['message'] ?? 'Failed to update playlist',
        );
      }
    } catch (e) {
      return ApiResponse<Playlist>(
        success: false,
        message: 'Network error: $e',
      );
    }
  }

  /// Delete a playlist
  static Future<ApiResponse<bool>> deletePlaylist(String playlistId) async {
    try {
      final response = await BaseApiService.delete('/v2/playlists/$playlistId');

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        return ApiResponse<bool>.fromJson(
          json,
          (data) => data as bool,
        );
      } else {
        final json = jsonDecode(response.body);
        return ApiResponse<bool>(
          success: false,
          message: json['message'] ?? 'Failed to delete playlist',
        );
      }
    } catch (e) {
      return ApiResponse<bool>(
        success: false,
        message: 'Network error: $e',
      );
    }
  }

  /// Get items from a playlist
  static Future<ApiResponse<List<PlaylistItem>>> getPlaylistItems(String playlistId) async {
    try {
      final response = await BaseApiService.get('/v2/playlists/$playlistId/items');

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        return ApiResponse<List<PlaylistItem>>.fromJson(
          json,
          (data) => (data as List)
              .map((item) => PlaylistItem.fromJson(item as Map<String, dynamic>))
              .toList(),
        );
      } else {
        final json = jsonDecode(response.body);
        return ApiResponse<List<PlaylistItem>>(
          success: false,
          message: json['message'] ?? 'Failed to get playlist items',
        );
      }
    } catch (e) {
      return ApiResponse<List<PlaylistItem>>(
        success: false,
        message: 'Network error: $e',
      );
    }
  }

  /// Add an item to a playlist
  static Future<ApiResponse<PlaylistItem>> addPlaylistItem(
    String playlistId,
    AddPlaylistItemRequest request,
  ) async {
    try {
      final response = await BaseApiService.post(
        '/v2/playlists/$playlistId/items',
        body: request.toJson(),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final json = jsonDecode(response.body);
        return ApiResponse<PlaylistItem>.fromJson(
          json,
          (data) => PlaylistItem.fromJson(data as Map<String, dynamic>),
        );
      } else {
        final json = jsonDecode(response.body);
        return ApiResponse<PlaylistItem>(
          success: false,
          message: json['message'] ?? 'Failed to add item to playlist',
        );
      }
    } catch (e) {
      return ApiResponse<PlaylistItem>(
        success: false,
        message: 'Network error: $e',
      );
    }
  }

  /// Remove an item from a playlist
  static Future<ApiResponse<bool>> removePlaylistItem(
    String playlistId,
    String itemId,
  ) async {
    try {
      final response = await BaseApiService.delete('/v2/playlists/$playlistId/items/$itemId');

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        return ApiResponse<bool>.fromJson(
          json,
          (data) => data as bool,
        );
      } else {
        final json = jsonDecode(response.body);
        return ApiResponse<bool>(
          success: false,
          message: json['message'] ?? 'Failed to remove item from playlist',
        );
      }
    } catch (e) {
      return ApiResponse<bool>(
        success: false,
        message: 'Network error: $e',
      );
    }
  }

  /// Reorder an item in a playlist
  static Future<ApiResponse<bool>> reorderPlaylistItem(
    String playlistId,
    String itemId,
    ReorderPlaylistItemRequest request,
  ) async {
    try {
      final response = await BaseApiService.put(
        '/v2/playlists/$playlistId/items/$itemId/reorder',
        body: request.toJson(),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        return ApiResponse<bool>.fromJson(
          json,
          (data) => data as bool,
        );
      } else {
        final json = jsonDecode(response.body);
        return ApiResponse<bool>(
          success: false,
          message: json['message'] ?? 'Failed to reorder playlist item',
        );
      }
    } catch (e) {
      return ApiResponse<bool>(
        success: false,
        message: 'Network error: $e',
      );
    }
  }
}
