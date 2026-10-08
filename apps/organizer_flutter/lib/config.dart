/// Compile-time configuration for the Sendoh mobile applications.
///
/// The hosted staging endpoint is the safe default for release builds.
/// Local development can override it without editing source code:
///   flutter run --dart-define=API_URL=http://192.168.1.118:8000
abstract final class SendohConfig {
  static const String apiBaseUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'https://sendoh.onrender.com',
  );
}
