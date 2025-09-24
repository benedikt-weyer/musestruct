import 'dart:async';
import 'package:http/http.dart' as http;
import 'app_config_service.dart';

enum BackendStatus {
  online,
  offline,
  checking,
}

class ConnectivityService {
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

  /// Force an immediate health check
  void forceCheck() {
    _checkBackendHealth();
  }

  Future<void> _checkBackendHealth() async {
    try {
      final healthEndpoint = await AppConfigService.instance.getHealthEndpoint();
      final response = await http.get(
        Uri.parse(healthEndpoint),
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
