import 'dart:convert';
import '../models/api_response.dart';
import '../models/music.dart';
import 'base_api_service.dart';

/// API service for music streaming operations
class MusicApiService extends BaseApiService {
  
  /// Search for music tracks across streaming services
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

      final response = await BaseApiService.get(
        '/streaming/search',
        queryParams: params,
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

  /// Search for playlists across streaming services
  static Future<ApiResponse<SearchResults>> searchPlaylists(
    String query, {
    int? limit,
    int? offset,
    String? service,
    List<String>? services,
  }) async {
    try {
      final params = <String, String>{
        'q': query,
        'type': 'playlist',
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

      final response = await BaseApiService.get(
        '/streaming/search',
        queryParams: params,
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        print('MusicApiService: Playlist search response: $json');
        print('MusicApiService: Playlists field in response: ${json['playlists']}');
        
        try {
          return ApiResponse<SearchResults>.fromJson(
            json,
            (data) => SearchResults.fromJson(data as Map<String, dynamic>),
          );
        } catch (e) {
          print('MusicApiService: Error parsing SearchResults: $e');
          // Return a safe empty SearchResults
          return ApiResponse<SearchResults>.success(
            SearchResults(
              tracks: [],
              albums: [],
              playlists: [],
              total: 0,
              offset: 0,
              limit: 20,
            ),
          );
        }
      } else {
        final json = jsonDecode(response.body);
        return ApiResponse<SearchResults>(
          success: false,
          message: json['message'] ?? 'Playlist search failed',
        );
      }
    } catch (e) {
      return ApiResponse<SearchResults>(
        success: false,
        message: 'Network error: $e',
      );
    }
  }

  /// Get stream URL for a track
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

      final response = await BaseApiService.get(
        '/streaming/stream-url',
        queryParams: params,
        timeout: BaseApiService.streamingTimeout,
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

  /// Get backend stream URL for a track
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

      final response = await BaseApiService.get(
        '/streaming/backend-stream-url',
        queryParams: params,
        timeout: BaseApiService.streamingTimeout,
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

  /// Get available streaming services
  static Future<ApiResponse<List<ServiceInfo>>> getAvailableServices() async {
    try {
      final response = await BaseApiService.get('/streaming/services');

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

  /// Connect to Qobuz streaming service
  static Future<ApiResponse<String>> connectQobuz(
    String username,
    String password,
  ) async {
    try {
      final response = await BaseApiService.post(
        '/streaming/connect/qobuz',
        body: {
          'username': username,
          'password': password,
        },
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

  /// Get service connection status
  static Future<ApiResponse<ServiceStatusResponse>> getServiceStatus() async {
    try {
      final response = await BaseApiService.get('/streaming/status');

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

  /// Disconnect from a streaming service
  static Future<ApiResponse<String>> disconnectService(String serviceName) async {
    try {
      final response = await BaseApiService.post(
        '/streaming/disconnect',
        body: {'service_name': serviceName},
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

  /// Get tracks from a streaming service playlist
  static Future<ApiResponse<List<Track>>> getPlaylistTracks(
    String playlistId, {
    String? service,
    int? limit,
    int? offset,
  }) async {
    try {
      final queryParams = <String, String>{
        if (service != null) 'service': service,
        if (limit != null) 'limit': limit.toString(),
        if (offset != null) 'offset': offset.toString(),
      };

      final response = await BaseApiService.get(
        '/streaming/playlist/$playlistId/tracks',
        queryParams: queryParams,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return ApiResponse<List<Track>>.fromJson(data, (json) {
          final tracksJson = json as List<dynamic>;
          return tracksJson.map((trackJson) => Track.fromJson(trackJson as Map<String, dynamic>)).toList();
        });
      } else {
        return ApiResponse<List<Track>>.error('Failed to get playlist tracks: ${response.statusCode}');
      }
    } catch (e) {
      return ApiResponse<List<Track>>.error('Error getting playlist tracks: $e');
    }
  }
}

/// Service information model
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

/// Service status response model
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

/// Connected service information model
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
