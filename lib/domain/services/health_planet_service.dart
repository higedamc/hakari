import '../entities/weight_entry.dart';

/// TANITA Health Planet cloud integration (OAuth 2 + innerscan API).
///
/// Modern TANITA consumer scales speak a proprietary, account-bound BLE
/// protocol, so measurements reach Hakari indirectly: scale → TANITA app
/// → Health Planet cloud → this service. See README "TANITA
/// compatibility".
abstract class HealthPlanetService {
  /// Where the user grants access (opened in an external browser). After
  /// approval Health Planet redirects to its success page with
  /// `?code=...` which the user pastes back into the app.
  Uri authorizationUrl();

  /// Exchanges a pasted authorization code (valid 10 minutes) for tokens
  /// and persists them securely.
  Future<void> linkWithCode(String code);

  /// Whether tokens are stored (does not guarantee they are still valid;
  /// [fetchEntries] refreshes or fails with [HealthPlanetFailure]).
  Future<bool> isLinked();

  /// Removes stored tokens.
  Future<void> unlink();

  /// Fetches innerscan measurements in `[from, to]` (measurement dates,
  /// max 3 months per Health Planet request) mapped to [WeightEntry].
  Future<List<WeightEntry>> fetchEntries(DateTime from, DateTime to);
}
