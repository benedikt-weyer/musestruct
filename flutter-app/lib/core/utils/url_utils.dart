import '../services/app_config_service.dart';

class UrlUtils {
  /// Convert a relative URL to a full URL using the configured backend URL
  static Future<String> getFullUrl(String? relativeUrl) async {
    if (relativeUrl == null || relativeUrl.isEmpty) {
      return '';
    }
    
    // If it's already a full URL, return as is
    if (relativeUrl.startsWith('http://') || relativeUrl.startsWith('https://')) {
      return relativeUrl;
    }
    
    // Get the backend URL and prepend it to the relative URL
    final backendUrl = await AppConfigService.instance.getBackendUrl();
    
    // Ensure the relative URL starts with /
    final cleanRelativeUrl = relativeUrl.startsWith('/') ? relativeUrl : '/$relativeUrl';
    
    return '$backendUrl$cleanRelativeUrl';
  }
  
  /// Get a full cover image URL from a relative cover URL
  static Future<String?> getCoverImageUrl(String? coverUrl) async {
    if (coverUrl == null || coverUrl.isEmpty) {
      return null;
    }
    
    return await getFullUrl(coverUrl);
  }
}
