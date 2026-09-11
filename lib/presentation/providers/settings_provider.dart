import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/providers.dart';
import '../../domain/entities/app_settings.dart';
import '../../domain/repositories/settings_repository.dart';
import '../../domain/services/body_metrics.dart';

/// Loads, exposes and persists [AppSettings].
///
/// Every mutator saves through the repository, updates local state and
/// returns the new settings so callers can re-initialize services
/// (e.g. `nostrService.initialize`) with the fresh value.
class SettingsController extends AsyncNotifier<AppSettings> {
  SettingsRepository get _repo => ref.read(settingsRepositoryProvider);

  @override
  Future<AppSettings> build() => _repo.load();

  Future<AppSettings> _update(
    AppSettings Function(AppSettings current) change,
  ) async {
    final current = state.value ?? await _repo.load();
    final next = change(current);
    await _repo.save(next);
    state = AsyncData(next);
    return next;
  }

  // Relays -------------------------------------------------------------

  Future<AppSettings> setRelays(List<String> relays) =>
      _update((s) => s.copyWith(relays: relays.toList()));

  Future<AppSettings> addRelay(String url) => _update(
    (s) => s.relays.contains(url) ? s : s.copyWith(relays: [...s.relays, url]),
  );

  Future<AppSettings> removeRelay(String url) => _update(
    (s) => s.copyWith(relays: s.relays.where((r) => r != url).toList()),
  );

  Future<AppSettings> resetRelaysToDefaults() =>
      _update((s) => s.copyWith(relays: AppSettings.defaultRelays.toList()));

  // Tor / proxy --------------------------------------------------------

  Future<AppSettings> setTorMode(TorMode mode) =>
      _update((s) => s.copyWith(torMode: mode));

  Future<AppSettings> setProxyUrl(String url) =>
      _update((s) => s.copyWith(proxyUrl: url));

  // Signer / identity ---------------------------------------------------

  Future<AppSettings> setSignerMode(SignerMode mode, {String? pubkeyHex}) =>
      _update((s) => s.copyWith(signerMode: mode, pubkeyHex: pubkeyHex));

  Future<AppSettings> logout() => _update(
    (s) => s.copyWith(signerMode: SignerMode.none, clearPubkey: true),
  );

  /// Marks first-run onboarding as finished (logged in or skipped).
  Future<AppSettings> completeOnboarding() =>
      _update((s) => s.copyWith(onboardingComplete: true));

  // Toggles --------------------------------------------------------------

  Future<AppSettings> setEncryptHealthEvents(bool value) =>
      _update((s) => s.copyWith(encryptHealthEvents: value));

  Future<AppSettings> setAutoSyncToHealth(bool value) =>
      _update((s) => s.copyWith(autoSyncToHealth: value));

  Future<AppSettings> setAutoPublishToNostr(bool value) =>
      _update((s) => s.copyWith(autoPublishToNostr: value));

  Future<AppSettings> setUseMetricUnits(bool value) =>
      _update((s) => s.copyWith(useMetricUnits: value));

  // Body profile ---------------------------------------------------------

  /// Sets the height the user typed; `null` clears it (and lets the next
  /// Health Planet sync fill it again). Implausible values are ignored
  /// without a save.
  Future<AppSettings> setHeightCm(double? cm) async {
    if (cm == null) return _update((s) => s.copyWith(clearHeightCm: true));
    if (!BodyProfileLimits.isPlausibleHeightCm(cm)) {
      return state.value ?? await _repo.load();
    }
    return _update((s) => s.copyWith(heightCm: cm));
  }

  /// Sets the goal weight; `null` clears it. Implausible values are
  /// ignored without a save.
  Future<AppSettings> setGoalWeightKg(double? kg) async {
    if (kg == null) {
      return _update((s) => s.copyWith(clearGoalWeightKg: true));
    }
    if (!BodyProfileLimits.isPlausibleWeightKg(kg)) {
      return state.value ?? await _repo.load();
    }
    return _update((s) => s.copyWith(goalWeightKg: kg));
  }

  /// Adopts a height reported by a Health Planet sync, but **only when no
  /// height is stored yet**. A value the user entered always wins and is
  /// never overwritten by sync. Returns the (possibly unchanged) settings.
  Future<AppSettings> adoptFetchedHeightCm(double? cm) async {
    final current = state.value ?? await _repo.load();
    if (current.heightCm != null ||
        !BodyProfileLimits.isPlausibleHeightCm(cm)) {
      return current;
    }
    return _update((s) => s.heightCm != null ? s : s.copyWith(heightCm: cm));
  }
}

final settingsProvider = AsyncNotifierProvider<SettingsController, AppSettings>(
  SettingsController.new,
);
