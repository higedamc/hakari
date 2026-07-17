import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/providers.dart';
import '../../domain/entities/app_settings.dart';
import '../../domain/entities/daily_wellness.dart';
import '../../domain/entities/weight_entry.dart';
import '../../domain/failures/failures.dart';
import '../../domain/repositories/weight_repository.dart';
import '../../domain/repositories/wellness_repository.dart';
import '../../domain/services/nostr_service.dart';
import 'settings_provider.dart';

enum SyncPhase { idle, syncing, success, error }

/// Current state of Nostr publish / fetch operations.
class SyncStatus {
  const SyncStatus(this.phase, [this.message, this.done, this.total]);

  final SyncPhase phase;
  final String? message;

  /// Batch progress (entries finished / batch size); null outside a
  /// batch publish.
  final int? done;
  final int? total;

  static const idle = SyncStatus(SyncPhase.idle);

  bool get isSyncing => phase == SyncPhase.syncing;

  bool get hasProgress => isSyncing && total != null && total! > 0;
}

/// Publishes entries to relays (NIP-101h) and imports our own events back.
class NostrSyncController extends Notifier<SyncStatus> {
  @override
  SyncStatus build() => SyncStatus.idle;

  NostrService get _nostr => ref.read(nostrServiceProvider);
  WeightRepository get _repo => ref.read(weightRepositoryProvider);
  WellnessRepository get _wellnessRepo => ref.read(wellnessRepositoryProvider);

  Future<AppSettings> _settings() async {
    try {
      return await ref.read(settingsProvider.future);
    } catch (_) {
      return const AppSettings();
    }
  }

  /// Publishes a single [entry]; records its event id on success.
  /// Returns true when at least one relay accepted the event.
  Future<bool> publishEntry(WeightEntry entry) async {
    state = const SyncStatus(SyncPhase.syncing, 'Publishing to Nostr...');
    try {
      final settings = await _settings();
      final result = await _nostr.publishEntry(
        entry,
        encrypt: settings.encryptHealthEvents,
      );
      if (!result.success) {
        state = const SyncStatus(
          SyncPhase.error,
          'No relay accepted the event.',
        );
        return false;
      }
      await _repo.upsert(entry.copyWith(nostrEventId: result.eventId));
      state = SyncStatus(
        SyncPhase.success,
        'Published to ${result.successfulRelays} '
        '${result.successfulRelays == 1 ? 'relay' : 'relays'}.',
      );
      return true;
    } on Failure catch (f) {
      state = SyncStatus(SyncPhase.error, f.message);
      return false;
    } catch (e) {
      state = SyncStatus(SyncPhase.error, 'Publish failed: $e');
      return false;
    }
  }

  bool _cancelRequested = false;

  /// Stops a running [publishAllUnpublished] batch after the entry
  /// currently in flight completes.
  void cancelBatch() => _cancelRequested = true;

  /// Publishes every entry that has no Nostr event id yet.
  ///
  /// Aborts immediately on a signer rejection or timeout — continuing
  /// would re-prompt Amber for every remaining entry.
  Future<void> publishAllUnpublished() async {
    _cancelRequested = false;
    state = const SyncStatus(
      SyncPhase.syncing,
      'Publishing unpublished entries...',
    );
    try {
      final settings = await _settings();
      final pending = await _repo.getUnpublished();
      final pendingWellness = await _getUnpublishedWellness();
      final total = pending.length + pendingWellness.length;
      if (total == 0) {
        state = const SyncStatus(
          SyncPhase.success,
          'Everything is already published.',
        );
        return;
      }
      var published = 0;
      var failed = 0;
      String? abortReason;

      SyncStatus progress() => SyncStatus(
        SyncPhase.syncing,
        'Publishing ${published + failed + 1}/$total...',
        published + failed,
        total,
      );

      for (final entry in pending) {
        if (_cancelRequested) {
          abortReason = 'Cancelled';
          break;
        }
        state = progress();
        try {
          final result = await _nostr.publishEntry(
            entry,
            encrypt: settings.encryptHealthEvents,
          );
          if (result.success) {
            await _repo.upsert(entry.copyWith(nostrEventId: result.eventId));
            published++;
          } else {
            failed++;
          }
        } on SignerRejectedFailure {
          abortReason = 'Stopped: rejected in Amber';
          break;
        } on SignerTimeoutFailure {
          abortReason = 'Stopped: Amber did not respond';
          break;
        } on SignerUnavailableFailure catch (f) {
          abortReason = 'Stopped: ${f.message}';
          break;
        } on Failure {
          failed++;
        }
      }

      // Wellness days (sleep / active energy) ride the same batch with
      // the same abort semantics.
      if (abortReason == null) {
        for (final day in pendingWellness) {
          if (_cancelRequested) {
            abortReason = 'Cancelled';
            break;
          }
          state = progress();
          try {
            final result = await _nostr.publishWellnessDay(day);
            if (result.success) {
              await _wellnessRepo.markBackedUp(day, result.eventId);
              published++;
            } else {
              failed++;
            }
          } on SignerRejectedFailure {
            abortReason = 'Stopped: rejected in Amber';
            break;
          } on SignerTimeoutFailure {
            abortReason = 'Stopped: Amber did not respond';
            break;
          } on SignerUnavailableFailure catch (f) {
            abortReason = 'Stopped: ${f.message}';
            break;
          } on Failure {
            failed++;
          }
        }
      }

      if (abortReason != null) {
        state = SyncStatus(
          SyncPhase.error,
          '$abortReason. Published $published of $total.',
        );
        return;
      }
      state = failed == 0
          ? SyncStatus(
              SyncPhase.success,
              'Published $published ${published == 1 ? 'item' : 'items'}.',
            )
          : SyncStatus(
              SyncPhase.error,
              'Published $published, failed $failed.',
            );
    } on Failure catch (f) {
      state = SyncStatus(SyncPhase.error, f.message);
    } catch (e) {
      state = SyncStatus(SyncPhase.error, 'Sync failed: $e');
    }
  }

  /// Unpublished wellness days; an unwired repo (tests) yields none.
  Future<List<DailyWellness>> _getUnpublishedWellness() async {
    try {
      return await _wellnessRepo.getUnpublished();
    } catch (_) {
      return const [];
    }
  }

  /// Fetches our own events from relays and imports the ones we don't
  /// have yet (deduped by entry id and by Nostr event id).
  Future<void> fetchFromNostr({DateTime? since}) async {
    state = const SyncStatus(SyncPhase.syncing, 'Fetching from relays...');
    try {
      final fetched = await _nostr.fetchOwnEntries(since: since);
      final existing = await _repo.getAll();
      final knownIds = existing.map((e) => e.id).toSet();
      final knownEventIds = existing
          .map((e) => e.nostrEventId)
          .whereType<String>()
          .toSet();
      var imported = 0;
      for (final entry in fetched) {
        if (knownIds.contains(entry.id)) continue;
        final eventId = entry.nostrEventId;
        if (eventId != null && knownEventIds.contains(eventId)) continue;
        await _repo.upsert(entry);
        knownIds.add(entry.id);
        if (eventId != null) knownEventIds.add(eventId);
        imported++;
      }
      final importedWellness = await _restoreWellness(since: since);
      final restored = imported + importedWellness;
      state = SyncStatus(
        SyncPhase.success,
        restored == 0
            ? 'Already up to date.'
            : 'Imported $restored ${restored == 1 ? 'item' : 'items'} '
                  'from relays.',
      );
    } on Failure catch (f) {
      state = SyncStatus(SyncPhase.error, f.message);
    } catch (e) {
      state = SyncStatus(SyncPhase.error, 'Fetch failed: $e');
    }
  }

  /// Restores wellness backups. Merged days that exactly match the
  /// backup keep its event id (not re-published); a local day holding
  /// more data than the backup stays unpublished so the fuller version
  /// is backed up on the next publish run.
  Future<int> _restoreWellness({DateTime? since}) async {
    final List<DailyWellness> fetched;
    try {
      fetched = await _nostr.fetchOwnWellness(since: since);
    } on Failure {
      return 0; // Best-effort: weight restore already succeeded.
    }
    var imported = 0;
    for (final day in fetched) {
      try {
        final before = await _wellnessRepo.getRange(day.day, day.day);
        await _wellnessRepo.upsertDay(day);
        final stored = (await _wellnessRepo.getRange(
          day.day,
          day.day,
        )).firstOrNull;
        if (stored == null) continue;
        final matchesBackup =
            stored.sleepHours == day.sleepHours &&
            stored.activeEnergyKcal == day.activeEnergyKcal;
        final eventId = day.nostrEventId;
        if (matchesBackup && stored.nostrEventId == null && eventId != null) {
          await _wellnessRepo.markBackedUp(stored, eventId);
        }
        if (before.isEmpty) imported++;
      } on Failure {
        // Skip storage failures per-day rather than failing the fetch.
      }
    }
    return imported;
  }
}

final nostrSyncProvider = NotifierProvider<NostrSyncController, SyncStatus>(
  NostrSyncController.new,
);
