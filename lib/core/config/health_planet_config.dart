/// Health Planet OAuth client credentials.
///
/// The client id is public by nature (it appears in the browser URL).
/// The client secret is injected at build time:
///   flutter build apk --release --dart-define=HP_CLIENT_SECRET=...
/// An APK built without it can still browse to the consent page, but the
/// token exchange fails with a clear configuration error.
class HealthPlanetConfig {
  HealthPlanetConfig._();

  /// No built-in client id: each user registers their own Health Planet
  /// application and enters its credentials in the link dialog. Personal
  /// builds may inject one with --dart-define=HP_CLIENT_ID=...
  static const String clientId = String.fromEnvironment('HP_CLIENT_ID');

  static const String clientSecret = String.fromEnvironment('HP_CLIENT_SECRET');

  /// Health Planet's own landing page; after approval it displays the
  /// authorization code on the page for the user to copy (OOB-style).
  static const String redirectUri = 'https://www.healthplanet.jp/success.html';

  static bool get isConfigured => clientSecret.isNotEmpty;
}
