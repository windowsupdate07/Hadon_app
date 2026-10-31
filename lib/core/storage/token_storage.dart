import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists the access token and the logged-in employee in secure storage.
class TokenStorage {
  TokenStorage([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  static const _tokenKey = 'access_token';
  static const _employeeKey = 'employee';

  final FlutterSecureStorage _storage;

  // In-memory copy so every request does not hit the keychain.
  String? _token;

  String? get token => _token;

  Future<String?> loadToken() async {
    _token = await _storage.read(key: _tokenKey);
    return _token;
  }

  Future<void> saveToken(String token) async {
    _token = token;
    await _storage.write(key: _tokenKey, value: token);
  }

  Future<Map<String, dynamic>?> loadEmployee() async {
    final raw = await _storage.read(key: _employeeKey);
    if (raw == null) {
      return null;
    }
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<void> saveEmployee(Map<String, dynamic> json) =>
      _storage.write(key: _employeeKey, value: jsonEncode(json));

  Future<void> clear() async {
    _token = null;
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _employeeKey);
  }
}
