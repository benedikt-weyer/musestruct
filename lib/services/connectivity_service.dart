import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

enum BackendStatus {
  online,
  offline,
  checking,
}

class ConnectivityService {
  static const String _healthEndpoint = 'http://127.0.0.1:8080/health';
  static const Duration _checkInterval = Duration(seconds: 5);
  static const Duration _timeout = Duration(seconds: 3);

  static final ConnectivityService _instance = ConnectivityService._internal();
  factory ConnectivityService() => _instance;
  ConnectivityService._internal();

  Timer? _timer;
  BackendStatus _status = BackendStatus.checking;
  final StreamController<BackendStatus> _statusController = 
      StreamController<BackendStatus>.broadcast();

  BackendStatus get status => _status;
  Stream<BackendStatus> get statusStream => _statusController.stream;

  void startMonitoring() {
    // Initial check
    _checkBackendHealth();
    
    // Start periodic checks
    _timer = Timer.periodic(_checkInterval, (_) => _checkBackendHealth());
  }

  void stopMonitoring() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _checkBackendHealth() async {
    try {
      final response = await http.get(
        Uri.parse(_healthEndpoint),
      ).timeout(_timeout);

      if (response.statusCode == 200 && response.body.trim() == 'OK') {
        _updateStatus(BackendStatus.online);
      } else {
        _updateStatus(BackendStatus.offline);
      }
    } catch (e) {
      _updateStatus(BackendStatus.offline);
    }
  }

  void _updateStatus(BackendStatus newStatus) {
    if (_status != newStatus) {
      _status = newStatus;
      _statusController.add(_status);
    }
  }

  void dispose() {
    stopMonitoring();
    _statusController.close();
  }
}
