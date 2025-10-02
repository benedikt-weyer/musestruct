import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

class AppConfigService {
  static const String _backendUrlKey = 'backend_url';
  static const String _defaultBackendUrl = 'http://127.0.0.1:8080';
  
  static AppConfigService? _instance;
  static AppConfigService get instance => _instance ??= AppConfigService._internal();
  
  AppConfigService._internal();
  
  SharedPreferences? _prefs;
  
  Future<void> _initPrefs() async {
    _prefs ??= await SharedPreferences.getInstance();
  }
  
  /// Get the currently configured backend URL
  Future<String> getBackendUrl() async {
    await _initPrefs();
    return _prefs!.getString(_backendUrlKey) ?? _defaultBackendUrl;
  }
  
  /// Set the backend URL
  Future<void> setBackendUrl(String url) async {
    await _initPrefs();
    // Ensure URL doesn't end with slash
    final cleanUrl = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
    await _prefs!.setString(_backendUrlKey, cleanUrl);
  }
  
  /// Get the API base URL (backend URL + /api)
  Future<String> getApiBaseUrl() async {
    final backendUrl = await getBackendUrl();
    return '$backendUrl/api';
  }
  
  /// Get the health check endpoint URL
  Future<String> getHealthEndpoint() async {
    final backendUrl = await getBackendUrl();
    return '$backendUrl/health';
  }
  
  /// Reset backend URL to default
  Future<void> resetBackendUrl() async {
    await _initPrefs();
    await _prefs!.remove(_backendUrlKey);
  }
  
  /// Validate if the provided URL is a valid backend URL format
  static bool isValidBackendUrl(String url) {
    if (url.isEmpty) return false;
    
    try {
      final uri = Uri.parse(url);
      return uri.hasScheme && (uri.scheme == 'http' || uri.scheme == 'https') && uri.hasAuthority;
    } catch (e) {
      return false;
    }
  }
  
  /// Get default backend URL
  static String get defaultBackendUrl => _defaultBackendUrl;
  
  /// Test connection to the backend server
  static Future<bool> testConnection(String url) async {
    try {
      // Ensure URL doesn't end with slash
      final cleanUrl = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
      final healthUrl = '$cleanUrl/health';
      
      final response = await http.get(
        Uri.parse(healthUrl),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));
      
      return response.statusCode == 200 && response.body.trim() == 'OK';
    } catch (e) {
      return false;
    }
  }
}
