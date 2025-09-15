import 'package:flutter/foundation.dart';
import '../services/connectivity_service.dart';

class ConnectivityProvider with ChangeNotifier {
  final ConnectivityService _connectivityService = ConnectivityService();
  
  BackendStatus _status = BackendStatus.checking;
  DateTime? _lastOnline;
  DateTime? _lastChecked;

  BackendStatus get status => _status;
  DateTime? get lastOnline => _lastOnline;
  DateTime? get lastChecked => _lastChecked;

  bool get isOnline => _status == BackendStatus.online;
  bool get isOffline => _status == BackendStatus.offline;
  bool get isChecking => _status == BackendStatus.checking;

  String get statusText {
    switch (_status) {
      case BackendStatus.online:
        return 'Backend Online';
      case BackendStatus.offline:
        return 'Backend Offline';
      case BackendStatus.checking:
        return 'Checking...';
    }
  }

  ConnectivityProvider() {
    _connectivityService.statusStream.listen((status) {
      _status = status;
      _lastChecked = DateTime.now();
      
      if (status == BackendStatus.online) {
        _lastOnline = DateTime.now();
      }
      
      notifyListeners();
    });
    
    _connectivityService.startMonitoring();
  }

  @override
  void dispose() {
    _connectivityService.dispose();
    super.dispose();
  }
}
