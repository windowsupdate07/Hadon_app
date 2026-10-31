import 'package:flutter/foundation.dart';

import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/storage/token_storage.dart';
import '../../core/utils/json.dart';
import 'employee.dart';

enum AuthStatus { unknown, authenticated, unauthenticated }

class AuthProvider extends ChangeNotifier {
  AuthProvider(this._api, this._storage) {
    _api.onUnauthorized = _onUnauthorized;
  }

  final ApiClient _api;
  final TokenStorage _storage;

  AuthStatus _status = AuthStatus.unknown;
  Employee? _employee;
  String? _sessionMessage;

  AuthStatus get status => _status;
  Employee? get employee => _employee;
  bool get isLoggedIn => _status == AuthStatus.authenticated;

  /// Message to show on the login page after a forced logout.
  String? takeSessionMessage() {
    final m = _sessionMessage;
    _sessionMessage = null;
    return m;
  }

  /// Restores the session on app start.
  Future<void> restore() async {
    final token = await _storage.loadToken();
    if (token == null) {
      _set(AuthStatus.unauthenticated);
      return;
    }
    // Show the cached user immediately, then validate with the server.
    final cached = await _storage.loadEmployee();
    if (cached != null) {
      _employee = Employee.fromJson(cached);
    }
    try {
      final data = await _api.get('/auth/restorelogin');
      final json = asMap(data is Map ? data['employeeData'] : null);
      if (json != null) {
        _employee = Employee.fromJson(json);
        await _storage.saveEmployee(json);
      }
      _set(AuthStatus.authenticated);
    } on ApiException catch (e) {
      if (e.isUnauthorized || e.statusCode == 404) {
        await _storage.clear();
        _employee = null;
        _set(AuthStatus.unauthenticated);
      } else if (_employee != null) {
        // Offline / server down: keep the cached session.
        _set(AuthStatus.authenticated);
      } else {
        _set(AuthStatus.unauthenticated);
      }
    }
  }

  /// Throws [ApiException] with the server message on failure.
  Future<void> login(String username, String password) async {
    final dynamic data;
    try {
      data = await _api.post(
        '/auth/login',
        data: {'Username': username, 'Password': password},
      );
    } on ApiException catch (e) {
      throw ApiException(_loginMessage(e.message), statusCode: e.statusCode);
    }
    final token = data is Map ? asString(data['accessToken']) : null;
    final json = asMap(data is Map ? data['employeeData'] : null);
    if (token == null || json == null) {
      throw ApiException(
        _loginMessage(data is Map ? asString(data['message']) : null),
      );
    }
    await _storage.saveToken(token);
    await _storage.saveEmployee(json);
    _employee = Employee.fromJson(json);
    _set(AuthStatus.authenticated);
  }

  Future<void> logout() async {
    await _api.logout();
    await _storage.clear();
    _employee = null;
    _set(AuthStatus.unauthenticated);
  }

  Future<void> changePassword(String oldPassword, String newPassword) async {
    await _api.post(
      '/auth/change-password',
      data: {
        'oldPassword': oldPassword,
        'newPassword': newPassword,
        'confirmNewPassword': newPassword,
      },
    );
  }

  void _onUnauthorized() {
    if (_status != AuthStatus.authenticated) {
      return;
    }
    _sessionMessage = 'เซสชันหมดอายุ กรุณาเข้าสู่ระบบใหม่';
    logout();
  }

  void _set(AuthStatus s) {
    _status = s;
    notifyListeners();
  }

  String _loginMessage(String? msg) {
    switch (msg) {
      case 'Employee not found.':
        return 'ไม่พบชื่อผู้ใช้งานนี้';
      case 'Invalid Password!':
        return 'รหัสผ่านไม่ถูกต้อง';
      default:
        return msg ?? 'เข้าสู่ระบบไม่สำเร็จ';
    }
  }
}
