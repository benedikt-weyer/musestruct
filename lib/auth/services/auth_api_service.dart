import 'dart:convert';
import '../../models/api_response.dart';
import '../../models/user.dart';
import '../../core/services/base_api_service.dart';

/// API service for user authentication operations
class AuthApiService extends BaseApiService {
  
  /// Get session token from secure storage
  static Future<String?> getSessionToken() => BaseApiService.getSessionToken();
  
  /// Save session token to secure storage
  static Future<void> saveSessionToken(String token) => BaseApiService.saveSessionToken(token);
  
  /// Clear session token from secure storage
  static Future<void> clearSessionToken() => BaseApiService.clearSessionToken();
  
  /// Authenticate user with login credentials
  static Future<ApiResponse<LoginResponse>> login(LoginRequest request) async {
    try {
      final response = await BaseApiService.post(
        '/auth/login',
        body: request.toJson(),
        requiresAuth: false,
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        final apiResponse = ApiResponse<LoginResponse>.fromJson(
          json,
          (data) => LoginResponse.fromJson(data as Map<String, dynamic>),
        );
        
        if (apiResponse.success && apiResponse.data != null) {
          await BaseApiService.saveSessionToken(apiResponse.data!.sessionToken);
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

  /// Register a new user account
  static Future<ApiResponse<User>> register(RegisterRequest request) async {
    try {
      final response = await BaseApiService.post(
        '/auth/register',
        body: request.toJson(),
        requiresAuth: false,
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

  /// Get current authenticated user information
  static Future<ApiResponse<User>> getCurrentUser() async {
    try {
      final response = await BaseApiService.get('/auth/me');

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

  /// Log out the current user
  static Future<ApiResponse<void>> logout() async {
    try {
      final response = await BaseApiService.post('/auth/logout');

      await BaseApiService.clearSessionToken();
      
      return ApiResponse<void>(
        success: response.statusCode == 200,
        message: response.statusCode == 200 ? null : 'Logout failed',
      );
    } catch (e) {
      await BaseApiService.clearSessionToken(); // Clear local token anyway
      return ApiResponse<void>(
        success: false,
        message: 'Network error: $e',
      );
    }
  }
}
