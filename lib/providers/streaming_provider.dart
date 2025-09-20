import 'package:flutter/foundation.dart';
import '../services/api_service.dart';

class StreamingProvider with ChangeNotifier {
  List<ConnectedServiceInfo> _services = [];
  bool _isLoading = false;
  String? _error;

  List<ConnectedServiceInfo> get services => _services;
  bool get isLoading => _isLoading;
  String? get error => _error;

  bool isServiceConnected(String serviceName) {
    return _services.any((service) => 
        service.name == serviceName && service.isConnected);
  }

  ConnectedServiceInfo? getService(String serviceName) {
    try {
      return _services.firstWhere((service) => service.name == serviceName);
    } catch (e) {
      return null;
    }
  }

  Future<void> loadServiceStatus() async {
    _setLoading(true);
    _clearError();

    try {
      final response = await ApiService.getServiceStatus();
      
      if (response.success && response.data != null) {
        _services = response.data!.services;
      } else {
        _setError(response.message ?? 'Failed to load service status');
      }
    } catch (e) {
      _setError('Network error: $e');
    } finally {
      _setLoading(false);
    }
  }

  Future<bool> disconnectService(String serviceName) async {
    _setLoading(true);
    _clearError();

    try {
      final response = await ApiService.disconnectService(serviceName);
      
      if (response.success) {
        // Update local state
        await loadServiceStatus();
        return true;
      } else {
        _setError(response.message ?? 'Failed to disconnect service');
        return false;
      }
    } catch (e) {
      _setError('Network error: $e');
      return false;
    } finally {
      _setLoading(false);
    }
  }

  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  void _setError(String error) {
    _error = error;
    notifyListeners();
  }

  void _clearError() {
    _error = null;
    notifyListeners();
  }
}
