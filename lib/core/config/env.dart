/// Runtime configuration.
///
/// Defaults to the hosted API. Override at build time, e.g. for a local
/// backend:
/// `flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8080/ntp-api`
class Env {
  Env._();

  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://notabug.dev/ntp-api',
  );
}
