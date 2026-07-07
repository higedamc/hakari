import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/providers.dart';
import '../../domain/entities/app_settings.dart';
import '../../domain/entities/weight_entry.dart';
import '../../domain/failures/failures.dart';
import 'nostr_sync_provider.dart';
import 'settings_provider.dart';

/// Persists a new entry and runs the configured auto-sync hooks
/// (Health Connect write, Nostr publish). Shared by the manual add
/// sheet and the BLE scale flow.
class EntrySaver {
  EntrySaver(this._ref);

  final Ref _ref;

  /// Upserts [entry], then applies auto-sync side effects.
  ///
  /// Storage errors are rethrown ([StorageFailure]); side-effect errors
  /// are non-fatal and returned as warning messages for SnackBars.
  /// Nostr publish results are surfaced separately through
  /// [nostrSyncProvider]'s status.
  Future<List<String>> save(WeightEntry entry) async {
    final warnings = <String>[];
    final repo = _ref.read(weightRepositoryProvider);
    var current = entry;
    await repo.upsert(current);

    AppSettings settings;
    try {
      settings = await _ref.read(settingsProvider.future);
    } catch (_) {
      settings = const AppSettings();
    }

    if (settings.autoSyncToHealth) {
      try {
        await _ref.read(healthServiceProvider).writeEntry(current);
        current = current.copyWith(syncedToHealth: true);
        await repo.upsert(current);
      } on Failure catch (f) {
        warnings.add('Health sync failed: ${f.message}');
      } catch (e) {
        warnings.add('Health sync failed: $e');
      }
    }

    if (settings.autoPublishToNostr) {
      // Success / failure is reported via the global sync status listener.
      await _ref.read(nostrSyncProvider.notifier).publishEntry(current);
    }

    return warnings;
  }
}

final entrySaverProvider = Provider<EntrySaver>(EntrySaver.new);
