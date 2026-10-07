abstract final class ApiConfig {
  /// Backend base URL. Override per target:
  ///   Linux desktop / tests: default (http://localhost:8080)
  ///   Android emulator:      --dart-define=API_BASE_URL=http://10.0.2.2:8080
  ///   Real device:           --dart-define=API_BASE_URL=http://VPS_IP:8080
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8080',
  );
}
