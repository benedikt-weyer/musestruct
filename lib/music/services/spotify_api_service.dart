import 'dart:convert';
import '../../models/api_response.dart';
import '../../core/services/base_api_service.dart';

/// API service for Spotify-specific operations
class SpotifyApiService extends BaseApiService {
  
  /// Connect to Spotify with access token
  static Future<ApiResponse<String>> connectSpotify(
    String accessToken,
    String? refreshToken,
  ) async {
    try {
      final response = await BaseApiService.post(
        '/streaming/connect/spotify',
        body: {
          'access_token': accessToken,
          'refresh_token': refreshToken,
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

  /// Get Spotify OAuth2 authorization URL
  static Future<ApiResponse<SpotifyAuthUrlResponse>> getSpotifyAuthUrl() async {
    try {
      final response = await BaseApiService.get('/streaming/spotify/auth-url');

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

  /// Handle Spotify OAuth2 callback
  static Future<ApiResponse<String>> spotifyCallback(String code, String state) async {
    try {
      final response = await BaseApiService.get(
        '/streaming/spotify/callback',
        queryParams: {
          'code': code,
          'state': state,
        },
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

  /// Transfer Spotify playback to a specific device
  static Future<ApiResponse<String>> transferSpotifyPlayback(String deviceId) async {
    try {
      final response = await BaseApiService.post(
        '/streaming/spotify/transfer',
        body: {'device_id': deviceId},
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

  /// Get Spotify access token
  static Future<ApiResponse<String>> getSpotifyAccessToken() async {
    try {
      final response = await BaseApiService.get('/streaming/spotify/token');

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
}

/// Spotify authorization URL response model
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
