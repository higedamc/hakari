import '../entities/daily_wellness.dart';

/// Persistence for daily wellness data (sleep / active energy) so the
/// history outlives Health Connect's retention and can be backed up to
/// Nostr like weight entries. Implementations throw [StorageFailure].
abstract interface class WellnessRepository {
  /// Inserts or merges one day. Merging fills only fields the stored
  /// day lacks — existing values are never overwritten. When a merge
  /// changes data, the day's [DailyWellness.nostrEventId] is cleared so
  /// it is backed up again.
  Future<void> upsertDay(DailyWellness day);

  /// All stored days, newest first.
  Future<List<DailyWellness>> getAll();

  /// Days in `[from, to]` (inclusive, by calendar day), newest first.
  Future<List<DailyWellness>> getRange(DateTime from, DateTime to);

  /// Days that have data but no Nostr backup event yet, oldest first.
  Future<List<DailyWellness>> getUnpublished();

  /// Records [eventId] as the backup event for [day].
  Future<void> markBackedUp(DailyWellness day, String eventId);
}
