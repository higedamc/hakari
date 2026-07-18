import '../entities/weight_entry.dart';

/// TANITA Health Planet cloud integration (OAuth 2 + innerscan API).
///
/// Modern TANITA consumer scales speak a proprietary, account-bound BLE
/// protocol, so measurements reach Hakari indirectly: scale → TANITA app
/// → Health Planet cloud → this service. See README "TANITA
/// compatibility".
abstract class HealthPlanetService {
  /// Where the user grants access (opened in an external browser). After
  /// approval Health Planet's success page displays an authorization
  /// code which the user pastes back into the app. Async because the
  /// client id may come from on-device storage.
  Future<Uri> authorizationUrl();

  /// Exchanges a pasted authorization code (valid 10 minutes) for tokens
  /// and persists them securely.
  Future<void> linkWithCode(String code);

  /// Whether an OAuth client secret is available (baked into the build
  /// or previously stored on this device).
  Future<bool> hasClientSecret();

  /// Stores the OAuth client secret on-device (Keystore-backed). Lets
  /// the user paste it once instead of embedding it in the APK.
  Future<void> setClientSecret(String secret);

  /// Stores the user's own Health Planet client id (from their developer
  /// registration). Empty/blank keeps the built-in default.
  Future<void> setClientId(String clientId);

  /// The effective client id (stored override or built-in default).
  Future<String> clientId();

  /// Whether tokens are stored (does not guarantee they are still valid;
  /// [fetchEntries] refreshes or fails with [HealthPlanetFailure]).
  Future<bool> isLinked();

  /// Removes stored tokens.
  Future<void> unlink();

  /// Fetches innerscan measurements in `[from, to]` (measurement dates,
  /// max 3 months per Health Planet request) mapped to [WeightEntry].
  Future<List<WeightEntry>> fetchEntries(DateTime from, DateTime to);

  /// Fetches the entire innerscan history by paging 90-day windows
  /// backwards from now. Stops after two consecutive empty windows (or a
  /// hard cap of ~12 years) so it terminates on any realistic account.
  /// [onProgress] reports the running entry count per fetched window.
  Future<List<WeightEntry>> fetchAllEntries({
    void Function(int fetchedSoFar)? onProgress,
  });
}
