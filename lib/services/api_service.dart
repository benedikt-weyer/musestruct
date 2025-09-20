import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/user.dart';
import '../models/music.dart';
import '../models/playlist.dart';
import '../models/api_response.dart';
import '../providers/queue_provider.dart';

class ApiService {
  static const String baseUrl = 'http://127.0.0.1:8080/api';
  static const _storage = FlutterSecureStorage();
  
  static const String _sessionTokenKey = 'session_token';

  // Authentication methods
  static Future<String?> getSessionToken() async {
    return await _storage.read(key: _sessionTokenKey);
  }

  static Future<void> saveSessionToken(String token) async {
    await _storage.write(key: _sessionTokenKey, value: token);
  }

  static Future<void> clearSessionToken() async {
    await _storage.delete(key: _sessionTokenKey);
  }

  static Map<String, String> _getHeaders() {
    final headers = {
      'Content-Type': 'application/json',
    };
    
    return headers;
  }

  static Future<Map<String, String>> _getAuthHeaders() async {
    final token = await getSessionToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  // User Authentication
  static Future<ApiResponse<LoginResponse>> login(LoginRequest request) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/login'),
        headers: _getHeaders(),
        body: jsonEncode(request.toJson()),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        final apiResponse = ApiResponse<LoginResponse>.fromJson(
          json,
          (data) => LoginResponse.fromJson(data as Map<String, dynamic>),
        );
        
        if (apiResponse.success && apiResponse.data != null) {
          await saveSessionToken(apiResponse.data!.sessionToken);
        }
        
        return apiResponse;
      } else {
        final json = jsonDecode(response.body);
        return ApiResponse<LoginResponse>(
          success: false,
          message: json['message'] ?? 'Login failed',
        );
      }
    } catch (e) {
      return ApiResponse<LoginResponse>(
        success: false,
        message: 'Network error: $e',
      );
    }
  }

  static Future<ApiResponse<User>> register(RegisterRequest request) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/register'),
        headers: _getHeaders(),
        body: jsonEncode(request.toJson()),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        return ApiResponse<User>.fromJson(
          json,
          (data) => User.fromJson(data as Map<String, dynamic>),
        );
      } else {
        final json = jsonDecode(response.body);
        return ApiResponse<User>(
          success: false,
          message: json['message'] ?? 'Registration failed',
        );
      }
    } catch (e) {
      return ApiResponse<User>(
        success: false,
        message: 'Network error: $e',
      );
    }
  }

  static Future<ApiResponse<User>> getCurrentUser() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/auth/me'),
        headers: await _getAuthHeaders(),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        return ApiResponse<User>.fromJson(
          json,
          (data) => User.fromJson(data as Map<String, dynamic>),
        );
      } else {
        return ApiResponse<User>(
          success: false,
          message: 'Failed to get user info',
        );
      }
    } catch (e) {
      return ApiResponse<User>(
        success: false,
        message: 'Network error: $e',
      );
    }
  }

  static Future<ApiResponse<void>> logout() async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/logout'),
        headers: await _getAuthHeaders(),
      );

      await clearSessionToken();
      
      return ApiResponse<void>(
        success: response.statusCode == 200,
        message: response.statusCode == 200 ? null : 'Logout failed',
      );
    } catch (e) {
      await clearSessionToken(); // Clear local token anyway
      return ApiResponse<void>(
        success: false,
        message: 'Network error: $e',
      );
    }
  }

  // Music streaming methods
  static Future<ApiResponse<SearchResults>> searchMusic(
    String query, {
    int? limit,
    int? offset,
    String? service,
    List<String>? services,
  }) async {
    try {
      final params = <String, String>{
        'q': query,
        if (limit != null) 'limit': limit.toString(),
        if (offset != null) 'offset': offset.toString(),
        if (service != null) 'service': service,
      };

      // Add services parameter if provided
      if (services != null && services.isNotEmpty) {
        for (int i = 0; i < services.length; i++) {
          params['services[$i]'] = services[i];
        }
      }

      final uri = Uri.parse('$baseUrl/streaming/search').replace(
        queryParameters: params,
      );

      final response = await http.get(
        uri,
        headers: await _getAuthHeaders(),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        return ApiResponse<SearchResults>.fromJson(
          json,
          (data) => SearchResults.fromJson(data as Map<String, dynamic>),
        );
      } else {
        final json = jsonDecode(response.body);
        return ApiResponse<SearchResults>(
          success: false,
          message: json['message'] ?? 'Search failed',
        );
      }
    } catch (e) {
      return ApiResponse<SearchResults>(
        success: false,
        message: 'Network error: $e',
      );
    }
  }

  static Future<ApiResponse<String>> getStreamUrl(
    String trackId, {
    String? quality,
    String? service,
  }) async {
    try {
      final params = {
        'track_id': trackId,
        if (quality != null) 'quality': quality,
        if (service != null) 'service': service,
      };

      final uri = Uri.parse('$baseUrl/streaming/stream-url').replace(
        queryParameters: params,
      );

      final response = await http.get(
        uri,
        headers: await _getAuthHeaders(),
      );

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
          message: json['message'] ?? 'Failed to get stream URL',
        );
      }
    } catch (e) {
      return ApiResponse<String>(
        success: false,
        message: 'Network error: $e',
      );
    }
  }

  static Future<ApiResponse<BackendStreamUrlResponse>> getBackendStreamUrl(
    String trackId,
    String source,
    String originalUrl,
  ) async {
    try {
      final params = {
        'track_id': trackId,
        'source': source,
        'url': originalUrl,
      };

      final uri = Uri.parse('$baseUrl/streaming/backend-stream-url').replace(
        queryParameters: params,
      );

      final response = await http.get(
        uri,
        headers: await _getAuthHeaders(),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        return ApiResponse<BackendStreamUrlResponse>.fromJson(
          json,
          (data) => BackendStreamUrlResponse.fromJson(data as Map<String, dynamic>),
        );
      } else {
        final json = jsonDecode(response.body);
        return ApiResponse<BackendStreamUrlResponse>(
          success: false,
          message: json['message'] ?? 'Failed to get backend stream URL',
        );
      }
    } catch (e) {
      return ApiResponse<BackendStreamUrlResponse>(
        success: false,
        message: 'Network error: $e',
      );
    }
  }

  static Future<ApiResponse<List<ServiceInfo>>> getAvailableServices() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/streaming/services'),
        headers: await _getAuthHeaders(),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        return ApiResponse<List<ServiceInfo>>.fromJson(
          json,
          (data) => (data as List)
              .map((item) => ServiceInfo.fromJson(item as Map<String, dynamic>))
              .toList(),
        );
      } else {
        final json = jsonDecode(response.body);
        return ApiResponse<List<ServiceInfo>>(
          success: false,
          message: json['message'] ?? 'Failed to get available services',
        );
      }
    } catch (e) {
      return ApiResponse<List<ServiceInfo>>(
        success: false,
        message: 'Network error: $e',
      );
    }
  }

  static Future<ApiResponse<String>> connectQobuz(
    String username,
    String password,
  ) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/streaming/connect/qobuz'),
        headers: await _getAuthHeaders(),
        body: jsonEncode({
          'username': username,
          'password': password,
        }),
      );

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
          message: json['message'] ?? 'Failed to connect to Qobuz',
        );
      }
    } catch (e) {
      return ApiResponse<String>(
        success: false,
        message: 'Network error: $e',
      );
    }
  }

  static Future<ApiResponse<String>> connectSpotify(
    String accessToken,
    String? refreshToken,
  ) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/streaming/connect/spotify'),
        headers: await _getAuthHeaders(),
        body: jsonEncode({
          'access_token': accessToken,
          'refresh_token': refreshToken,
        }),
      );

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
          message: json['message'] ?? 'Failed to connect to Spotify',
        );
      }
    } catch (e) {
      return ApiResponse<String>(
        success: false,
        message: 'Network error: $e',
      );
    }
  }

  static Future<ApiResponse<ServiceStatusResponse>> getServiceStatus() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/streaming/status'),
        headers: await _getAuthHeaders(),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        return ApiResponse<ServiceStatusResponse>.fromJson(
          json,
          (data) => ServiceStatusResponse.fromJson(data as Map<String, dynamic>),
        );
      } else {
        final json = jsonDecode(response.body);
        return ApiResponse<ServiceStatusResponse>(
          success: false,
          message: json['message'] ?? 'Failed to get service status',
        );
      }
    } catch (e) {
      return ApiResponse<ServiceStatusResponse>(
        success: false,
        message: 'Network error: $e',
      );
    }
  }

  static Future<ApiResponse<String>> disconnectService(String serviceName) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/streaming/disconnect'),
        headers: await _getAuthHeaders(),
        body: jsonEncode({
          'service_name': serviceName,
        }),
      );

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
          message: json['message'] ?? 'Failed to disconnect service',
        );
      }
    } catch (e) {
      return ApiResponse<String>(
        success: false,
        message: 'Network error: $e',
      );
    }
  }

  // Spotify OAuth2 methods
  static Future<ApiResponse<SpotifyAuthUrlResponse>> getSpotifyAuthUrl() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/streaming/spotify/auth-url'),
        headers: await _getAuthHeaders(),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        return ApiResponse<SpotifyAuthUrlResponse>.fromJson(
          json,
          (data) => SpotifyAuthUrlResponse.fromJson(data as Map<String, dynamic>),
        );
      } else {
        final json = jsonDecode(response.body);
        return ApiResponse<SpotifyAuthUrlResponse>.fromJson(
          json,
          (data) => SpotifyAuthUrlResponse.fromJson(data as Map<String, dynamic>),
        );
      }
    } catch (e) {
      return ApiResponse<SpotifyAuthUrlResponse>.error('Network error: $e');
    }
  }

  static Future<ApiResponse<String>> spotifyCallback(String code, String state) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/streaming/spotify/callback?code=$code&state=$state'),
        headers: await _getAuthHeaders(),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        return ApiResponse<String>.fromJson(json, (data) => data as String);
      } else {
        final json = jsonDecode(response.body);
        return ApiResponse<String>.fromJson(json, (data) => data as String);
      }
    } catch (e) {
      return ApiResponse<String>.error('Network error: $e');
    }
  }

  static Future<ApiResponse<String>> transferSpotifyPlayback(String deviceId) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/streaming/spotify/transfer'),
        headers: await _getAuthHeaders(),
        body: jsonEncode({'device_id': deviceId}),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        return ApiResponse<String>.fromJson(json, (data) => data as String);
      } else {
        final json = jsonDecode(response.body);
        return ApiResponse<String>.fromJson(json, (data) => data as String);
      }
    } catch (e) {
      return ApiResponse<String>.error('Network error: $e');
    }
  }

  static Future<ApiResponse<String>> getSpotifyAccessToken() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/streaming/spotify/token'),
        headers: await _getAuthHeaders(),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        return ApiResponse<String>.fromJson(json, (data) => data as String);
      } else {
        final json = jsonDecode(response.body);
        return ApiResponse<String>.fromJson(json, (data) => data as String);
      }
    } catch (e) {
      return ApiResponse<String>.error('Network error: $e');
    }
  }

  // Saved tracks methods
  static Future<ApiResponse<SavedTrack>> saveTrack(SaveTrackRequest request) async {
    try {
      print('Saving track: ${request.toJson()}');
      final headers = await _getAuthHeaders();
      print('Headers: $headers');
      final response = await http.post(
        Uri.parse('$baseUrl/saved-tracks'),
        headers: headers,
        body: jsonEncode(request.toJson()),
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

  static Future<ApiResponse<List<SavedTrack>>> getSavedTracks({int page = 1, int limit = 50}) async {
    try {
      final headers = await _getAuthHeaders();
      print('Headers: $headers');
      final response = await http.get(
        Uri.parse('$baseUrl/saved-tracks?page=$page&limit=$limit'),
        headers: headers,
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

  static Future<ApiResponse<void>> removeSavedTrack(String trackId) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/saved-tracks/$trackId'),
        headers: await _getAuthHeaders(),
      );

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

  static Future<ApiResponse<bool>> isTrackSaved(String trackId, String source) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/saved-tracks/check?track_id=$trackId&source=$source'),
        headers: await _getAuthHeaders(),
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

  // Queue management methods
  static Future<ApiResponse<List<QueueItem>>> getQueue() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/queue'),
        headers: await _getAuthHeaders(),
      );

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

  static Future<ApiResponse<bool>> addToQueue(Track track) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/queue'),
        headers: await _getAuthHeaders(),
        body: jsonEncode({
          'track_id': track.id,
          'title': track.title,
          'artist': track.artist,
          'album': track.album,
          'duration': track.duration ?? 0,
          'source': track.source,
          'cover_url': track.coverUrl,
        }),
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

  static Future<ApiResponse<bool>> removeFromQueue(String queueItemId) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/queue/$queueItemId'),
        headers: await _getAuthHeaders(),
      );

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

  static Future<ApiResponse<bool>> reorderQueue(String queueItemId, int newPosition) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/queue/$queueItemId/reorder'),
        headers: await _getAuthHeaders(),
        body: jsonEncode({
          'new_position': newPosition,
        }),
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

  static Future<ApiResponse<bool>> clearQueue() async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/queue'),
        headers: await _getAuthHeaders(),
      );

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

class ServiceInfo {
  final String name;
  final String displayName;
  final bool supportsFullTracks;
  final bool requiresPremium;

  ServiceInfo({
    required this.name,
    required this.displayName,
    required this.supportsFullTracks,
    required this.requiresPremium,
  });

  factory ServiceInfo.fromJson(Map<String, dynamic> json) {
    return ServiceInfo(
      name: json['name'] as String,
      displayName: json['display_name'] as String,
      supportsFullTracks: json['supports_full_tracks'] as bool,
      requiresPremium: json['requires_premium'] as bool,
    );
  }
}

class ServiceStatusResponse {
  final List<ConnectedServiceInfo> services;

  ServiceStatusResponse({
    required this.services,
  });

  factory ServiceStatusResponse.fromJson(Map<String, dynamic> json) {
    return ServiceStatusResponse(
      services: (json['services'] as List<dynamic>)
          .map((item) => ConnectedServiceInfo.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }
}

class ConnectedServiceInfo {
  final String name;
  final String displayName;
  final bool isConnected;
  final String? connectedAt;
  final String? accountUsername;

  ConnectedServiceInfo({
    required this.name,
    required this.displayName,
    required this.isConnected,
    this.connectedAt,
    this.accountUsername,
  });

  factory ConnectedServiceInfo.fromJson(Map<String, dynamic> json) {
    return ConnectedServiceInfo(
      name: json['name'] as String,
      displayName: json['display_name'] as String,
      isConnected: json['is_connected'] as bool,
      connectedAt: json['connected_at'] as String?,
      accountUsername: json['account_username'] as String?,
    );
  }
}

class SpotifyAuthUrlResponse {
  final String authUrl;
  final String state;

  SpotifyAuthUrlResponse({
    required this.authUrl,
    required this.state,
  });

  factory SpotifyAuthUrlResponse.fromJson(Map<String, dynamic> json) {
    return SpotifyAuthUrlResponse(
      authUrl: json['auth_url'] as String,
      state: json['state'] as String,
    );
  }
}

// Playlist API methods
class PlaylistApiService {
  static const String baseUrl = 'http://127.0.0.1:8080/api';

  static Future<Map<String, String>> _getAuthHeaders() async {
    final token = await ApiService.getSessionToken();
    print('PlaylistApiService: Retrieved token: ${token != null ? "present" : "null"}');
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  // Get all playlists
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

      final uri = Uri.parse('$baseUrl/v2/playlists').replace(queryParameters: params);
      print('PlaylistApiService: baseUrl = $baseUrl');
      print('PlaylistApiService: constructed uri = $uri');
      final headers = await _getAuthHeaders();
      print('PlaylistApiService: Making request to $uri');
      print('PlaylistApiService: Headers: $headers');
      
      final response = await http.get(uri, headers: headers);
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

  // Create playlist
  static Future<ApiResponse<Playlist>> createPlaylist(CreatePlaylistRequest request) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/v2/playlists'),
        headers: await _getAuthHeaders(),
        body: jsonEncode(request.toJson()),
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

  // Get playlist by ID
  static Future<ApiResponse<Playlist>> getPlaylist(String playlistId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/v2/playlists/$playlistId'),
        headers: await _getAuthHeaders(),
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

  // Update playlist
  static Future<ApiResponse<Playlist>> updatePlaylist(
    String playlistId,
    UpdatePlaylistRequest request,
  ) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/v2/playlists/$playlistId'),
        headers: await _getAuthHeaders(),
        body: jsonEncode(request.toJson()),
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

  // Delete playlist
  static Future<ApiResponse<bool>> deletePlaylist(String playlistId) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/v2/playlists/$playlistId'),
        headers: await _getAuthHeaders(),
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

  // Get playlist items
  static Future<ApiResponse<List<PlaylistItem>>> getPlaylistItems(String playlistId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/v2/playlists/$playlistId/items'),
        headers: await _getAuthHeaders(),
      );

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

  // Add item to playlist
  static Future<ApiResponse<PlaylistItem>> addPlaylistItem(
    String playlistId,
    AddPlaylistItemRequest request,
  ) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/v2/playlists/$playlistId/items'),
        headers: await _getAuthHeaders(),
        body: jsonEncode(request.toJson()),
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

  // Remove item from playlist
  static Future<ApiResponse<bool>> removePlaylistItem(
    String playlistId,
    String itemId,
  ) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/v2/playlists/$playlistId/items/$itemId'),
        headers: await _getAuthHeaders(),
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

  // Reorder playlist item
  static Future<ApiResponse<bool>> reorderPlaylistItem(
    String playlistId,
    String itemId,
    ReorderPlaylistItemRequest request,
  ) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/v2/playlists/$playlistId/items/$itemId/reorder'),
        headers: await _getAuthHeaders(),
        body: jsonEncode(request.toJson()),
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
