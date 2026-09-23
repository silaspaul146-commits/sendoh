/// Compile-time configuration for the Sendoh mobile applications.
///
/// The staging endpoint is the safe default for release builds. Override it
/// without editing source code with:
///   flutter build apk --dart-define=API_URL=https://api.example.com
abstract final class SendohConfig {
  static const String apiBaseUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'https://sendoh-api-staging.onrender.com',
  );
}
