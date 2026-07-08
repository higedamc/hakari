import '../entities/daily_wellness.dart';
import '../entities/weight_entry.dart';

/// Health Connect (Android) / HealthKit (iOS) integration.
/// Implementations throw [HealthFailure] / [HealthPermissionFailure].
abstract interface class HealthService {
  /// Whether the platform health store is available on this device.
  Future<bool> isAvailable();

  /// Request read+write permission for weight and body fat.
  /// Returns true when granted.
  Future<bool> requestPermissions();

  /// Write one entry (weight, and body fat % when present).
  Future<void> writeEntry(WeightEntry entry);

  /// Read weight records between [from] and [to] as entries
  /// (source = healthSync). Used for import.
  Future<List<WeightEntry>> readEntries(DateTime from, DateTime to);

  /// Sleep + active energy for the [days] calendar days ending today
  /// (oldest first, one element per day; missing data yields nulls).
  /// Requires the sleep / active-energy read permissions from
  /// [requestPermissions].
  Future<List<DailyWellness>> readWellness(int days);
}
