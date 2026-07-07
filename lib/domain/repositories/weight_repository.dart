import '../entities/weight_entry.dart';

/// Local persistence contract for measurements.
/// Implementations throw [StorageFailure] on error.
abstract interface class WeightRepository {
  /// All entries sorted by recordedAt descending.
  Future<List<WeightEntry>> getAll();

  Future<WeightEntry?> getById(String id);

  Future<void> upsert(WeightEntry entry);

  Future<void> delete(String id);

  /// Entries not yet published to Nostr.
  Future<List<WeightEntry>> getUnpublished();

  /// Reactive stream emitting the full sorted list on every change.
  Stream<List<WeightEntry>> watchAll();
}
