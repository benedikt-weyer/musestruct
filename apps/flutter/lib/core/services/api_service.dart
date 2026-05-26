import 'dart:convert';
import 'package:http/http.dart' as http;
import 'base_api_service.dart';

class ApiService extends BaseApiService {
  /// Make a GET request
  Future<http.Response> get(
    String endpoint, {
    Map<String, String>? queryParameters,
    bool requiresAuth = true,
    Duration? timeout,
  }) async {
    return BaseApiService.get(
      endpoint,
      queryParams: queryParameters,
      requiresAuth: requiresAuth,
      timeout: timeout,
    );
  }

  /// Make a POST request
  Future<http.Response> post(
    String endpoint, {
    Map<String, dynamic>? body,
    Map<String, String>? queryParameters,
    bool requiresAuth = true,
    Duration? timeout,
  }) async {
    // Handle query parameters by appending them to the endpoint
    String finalEndpoint = endpoint;
    if (queryParameters != null && queryParameters.isNotEmpty) {
      final uri = Uri.parse(endpoint).replace(queryParameters: queryParameters);
      finalEndpoint = uri.toString();
    }
    
    return BaseApiService.post(
      finalEndpoint,
      body: body,
      requiresAuth: requiresAuth,
      timeout: timeout,
    );
  }

  /// Make a PUT request
  Future<http.Response> put(
    String endpoint, {
    Map<String, dynamic>? body,
    Map<String, String>? queryParameters,
    bool requiresAuth = true,
    Duration? timeout,
  }) async {
    // Handle query parameters by appending them to the endpoint
    String finalEndpoint = endpoint;
    if (queryParameters != null && queryParameters.isNotEmpty) {
      final uri = Uri.parse(endpoint).replace(queryParameters: queryParameters);
      finalEndpoint = uri.toString();
    }
    
    return BaseApiService.put(
      finalEndpoint,
      body: body,
      requiresAuth: requiresAuth,
      timeout: timeout,
    );
  }

  /// Make a DELETE request
  Future<http.Response> delete(
    String endpoint, {
    Map<String, String>? queryParameters,
    bool requiresAuth = true,
    Duration? timeout,
  }) async {
    // Handle query parameters by appending them to the endpoint
    String finalEndpoint = endpoint;
    if (queryParameters != null && queryParameters.isNotEmpty) {
      final uri = Uri.parse(endpoint).replace(queryParameters: queryParameters);
      finalEndpoint = uri.toString();
    }
    
    return BaseApiService.delete(
      finalEndpoint,
      requiresAuth: requiresAuth,
      timeout: timeout,
    );
  }
}
