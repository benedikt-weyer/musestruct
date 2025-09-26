import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../services/app_config_service.dart';

/// Base API service with shared functionality for all API services
abstract class BaseApiService {
  static const _storage = FlutterSecureStorage();
  static const String _sessionTokenKey = 'session_token';
  
  // Timeout configurations
  static const Duration defaultTimeout = Duration(seconds: 30);
  static const Duration streamingTimeout = Duration(minutes: 3);
  
  /// Get the base URL for API calls
  static Future<String> get baseUrl async {
    return await AppConfigService.instance.getApiBaseUrl();
  }

  /// Get session token from secure storage
  static Future<String?> getSessionToken() async {
    return await _storage.read(key: _sessionTokenKey);
  }

  /// Save session token to secure storage
  static Future<void> saveSessionToken(String token) async {
    await _storage.write(key: _sessionTokenKey, value: token);
  }

  /// Clear session token from secure storage
  static Future<void> clearSessionToken() async {
    await _storage.delete(key: _sessionTokenKey);
  }

  /// Get basic headers for API requests
  static Map<String, String> getHeaders() {
    return {
      'Content-Type': 'application/json',
    };
  }

  /// Get headers with authentication token
  static Future<Map<String, String>> getAuthHeaders() async {
    final token = await getSessionToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// Make a GET request with automatic error handling
  static Future<http.Response> get(
    String endpoint, {
    Map<String, String>? queryParams,
    bool requiresAuth = true,
    Duration? timeout,
  }) async {
    final apiBaseUrl = await baseUrl;
    final uri = Uri.parse('$apiBaseUrl$endpoint').replace(
      queryParameters: queryParams,
    );
    
    final headers = requiresAuth ? await getAuthHeaders() : getHeaders();
    
    return await http.get(uri, headers: headers).timeout(
      timeout ?? defaultTimeout,
    );
  }

  /// Make a POST request with automatic error handling
  static Future<http.Response> post(
    String endpoint, {
    Map<String, dynamic>? body,
    bool requiresAuth = true,
    Duration? timeout,
  }) async {
    final apiBaseUrl = await baseUrl;
    final uri = Uri.parse('$apiBaseUrl$endpoint');
    
    final headers = requiresAuth ? await getAuthHeaders() : getHeaders();
    
    return await http.post(
      uri,
      headers: headers,
      body: body != null ? jsonEncode(body) : null,
    ).timeout(timeout ?? defaultTimeout);
  }

  /// Make a PUT request with automatic error handling
  static Future<http.Response> put(
    String endpoint, {
    Map<String, dynamic>? body,
    bool requiresAuth = true,
    Duration? timeout,
  }) async {
    final apiBaseUrl = await baseUrl;
    final uri = Uri.parse('$apiBaseUrl$endpoint');
    
    final headers = requiresAuth ? await getAuthHeaders() : getHeaders();
    
    return await http.put(
      uri,
      headers: headers,
      body: body != null ? jsonEncode(body) : null,
    ).timeout(timeout ?? defaultTimeout);
  }

  /// Make a DELETE request with automatic error handling
  static Future<http.Response> delete(
    String endpoint, {
    bool requiresAuth = true,
    Duration? timeout,
  }) async {
    final apiBaseUrl = await baseUrl;
    final uri = Uri.parse('$apiBaseUrl$endpoint');
    
    final headers = requiresAuth ? await getAuthHeaders() : getHeaders();
    
    return await http.delete(uri, headers: headers).timeout(
      timeout ?? defaultTimeout,
    );
  }
}
