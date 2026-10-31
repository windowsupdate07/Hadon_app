import 'dart:io';

/// Runtime configuration.
///
/// Override the API URL at build time:
/// `flutter run --dart-define=API_BASE_URL=http://192.168.1.10:8080/ntp-api`
class Env {
  Env._();

  static const String _apiBaseUrl = String.fromEnvironment('API_BASE_URL');

  static String get apiBaseUrl {
    if (_apiBaseUrl.isNotEmpty) {
      return _apiBaseUrl;
    }
    // Android emulator reaches the host machine via 10.0.2.2.
    if (Platform.isAndroid) {
      return 'http://10.0.2.2:8080/ntp-api';
    }
    return 'http://127.0.0.1:8080/ntp-api';
  }
}
