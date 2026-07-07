import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/providers.dart';
import '../../domain/entities/app_settings.dart';
import '../../domain/entities/weight_entry.dart';
import '../../domain/failures/failures.dart';
import '../../domain/repositories/weight_repository.dart';
import '../../domain/services/nostr_service.dart';
import 'settings_provider.dart';

enum SyncPhase { idle, syncing, success, error }

/// Current state of Nostr publish / fetch operations.
class SyncStatus {
  const SyncStatus(this.phase, [this.message]);

  final SyncPhase phase;
  final String? message;

  static const idle = SyncStatus(SyncPhase.idle);

  bool get isSyncing => phase == SyncPhase.syncing;
}

/// Publishes entries to relays (NIP-101h) and imports our own events back.
class NostrSyncController extends Notifier<SyncStatus> {
  @override
  SyncStatus build() => SyncStatus.idle;

  NostrService get _nostr => ref.read(nostrServiceProvider);
  WeightRepository get _repo => ref.read(weightRepositoryProvider);

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

  /// Publishes every entry that has no Nostr event id yet.
  Future<void> publishAllUnpublished() async {
    state = const SyncStatus(
      SyncPhase.syncing,
      'Publishing unpublished entries...',
    );
    try {
      final settings = await _settings();
      final pending = await _repo.getUnpublished();
      if (pending.isEmpty) {
        state = const SyncStatus(
          SyncPhase.success,
          'Everything is already published.',
        );
        return;
      }
      var published = 0;
      var failed = 0;
      for (final entry in pending) {
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
        } on Failure {
          failed++;
        }
      }
      state = failed == 0
          ? SyncStatus(
              SyncPhase.success,
              'Published $published ${published == 1 ? 'entry' : 'entries'}.',
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

  /// Fetches our own events from relays and imports the ones we don't
  /// have yet (deduped by entry id and by Nostr event id).
  Future<void> fetchFromNostr({DateTime? since}) async {
    state = const SyncStatus(SyncPhase.syncing, 'Fetching from relays...');
    try {
      final fetched = await _nostr.fetchOwnEntries(since: since);
      final existing = await _repo.getAll();
      final knownIds = existing.map((e) => e.id).toSet();
      final knownEventIds =
          existing.map((e) => e.nostrEventId).whereType<String>().toSet();
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
      state = SyncStatus(
        SyncPhase.success,
        imported == 0
            ? 'Already up to date.'
            : 'Imported $imported ${imported == 1 ? 'entry' : 'entries'} '
                'from relays.',
      );
    } on Failure catch (f) {
      state = SyncStatus(SyncPhase.error, f.message);
    } catch (e) {
      state = SyncStatus(SyncPhase.error, 'Fetch failed: $e');
    }
  }
}

final nostrSyncProvider = NotifierProvider<NostrSyncController, SyncStatus>(
  NostrSyncController.new,
);
