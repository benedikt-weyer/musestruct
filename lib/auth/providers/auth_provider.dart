import 'package:flutter/foundation.dart';
import '../models/user.dart';
import '../services/auth_api_service.dart';

class AuthProvider with ChangeNotifier {
  User? _user;
  bool _isLoading = false;
  String? _error;

  User? get user => _user;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isAuthenticated => _user != null;

  Future<bool> login(String email, String password) async {
    _setLoading(true);
    _clearError();

    try {
      final request = LoginRequest(email: email, password: password);
      final response = await AuthApiService.login(request);

      if (response.success && response.data != null) {
        _user = response.data!.user;
        notifyListeners();
        return true;
      } else {
        _setError(response.message ?? 'Login failed');
        return false;
      }
    } catch (e) {
      _setError('Login failed: $e');
      return false;
    } finally {
      _setLoading(false);
    }
  }

  Future<bool> register(String email, String username, String password) async {
    _setLoading(true);
    _clearError();

    try {
      final request = RegisterRequest(
        email: email,
        username: username,
        password: password,
      );
      final response = await AuthApiService.register(request);

      if (response.success) {
        // After successful registration, login automatically
        return await login(email, password);
      } else {
        _setError(response.message ?? 'Registration failed');
        return false;
      }
    } catch (e) {
      _setError('Registration failed: $e');
      return false;
    } finally {
      _setLoading(false);
    }
  }

  Future<void> logout() async {
    _setLoading(true);

    try {
      await AuthApiService.logout();
    } catch (e) {
      print('Logout error: $e');
    } finally {
      _user = null;
      _setLoading(false);
      notifyListeners();
    }
  }

  Future<void> checkAuthStatus() async {
    final token = await AuthApiService.getSessionToken();
    if (token != null) {
      _setLoading(true);
      try {
        final response = await AuthApiService.getCurrentUser();
        if (response.success && response.data != null) {
          _user = response.data;
        } else {
          // Token is invalid, clear it
          await AuthApiService.clearSessionToken();
        }
      } catch (e) {
        await AuthApiService.clearSessionToken();
      } finally {
        _setLoading(false);
      }
    }
    notifyListeners();
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
