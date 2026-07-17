import 'package:hive/hive.dart';

import '../../domain/entities/daily_wellness.dart';
import '../../domain/failures/failures.dart';
import '../../domain/repositories/wellness_repository.dart';

/// [WellnessRepository] backed by a Hive box (encrypted, like weights).
///
/// Days are stored keyed by `yyyy-MM-dd` as the plain map produced by
/// [DailyWellness.toMap], so no Hive TypeAdapter is required.
class HiveWellnessRepository implements WellnessRepository {
  static const String boxName = 'wellness_days';

  final Box _box;

  HiveWellnessRepository(this._box);

  List<DailyWellness> _readAllSorted() {
    final days =
        _box.values.map((raw) => DailyWellness.fromMap(raw as Map)).toList()
          ..sort((a, b) => b.day.compareTo(a.day));
    return days;
  }

  @override
  Future<void> upsertDay(DailyWellness day) async {
    try {
      final raw = _box.get(day.dayKey);
      if (raw == null) {
        await _box.put(day.dayKey, day.toMap());
        return;
      }
      final current = DailyWellness.fromMap(raw as Map);
      // Fill only missing fields; never overwrite recorded data.
      final merged = current.copyWith(
        sleepHours: current.sleepHours ?? day.sleepHours,
        activeEnergyKcal: current.activeEnergyKcal ?? day.activeEnergyKcal,
      );
      final changed =
          merged.sleepHours != current.sleepHours ||
          merged.activeEnergyKcal != current.activeEnergyKcal;
      if (!changed) return;
      // Data changed: the old backup event no longer matches.
      await _box.put(day.dayKey, {...merged.toMap(), 'nostrEventId': null});
    } catch (e) {
      throw StorageFailure('Failed to save wellness day "${day.dayKey}"', e);
    }
  }

  @override
  Future<List<DailyWellness>> getAll() async {
    try {
      return _readAllSorted();
    } catch (e) {
      throw StorageFailure('Failed to read wellness days', e);
    }
  }

  @override
  Future<List<DailyWellness>> getRange(DateTime from, DateTime to) async {
    try {
      final fromDay = DateTime(from.year, from.month, from.day);
      final toDay = DateTime(to.year, to.month, to.day);
      return _readAllSorted()
          .where((d) => !d.day.isBefore(fromDay) && !d.day.isAfter(toDay))
          .toList();
    } catch (e) {
      throw StorageFailure('Failed to read wellness days', e);
    }
  }

  @override
  Future<List<DailyWellness>> getUnpublished() async {
    try {
      return _readAllSorted().reversed
          .where(
            (d) =>
                d.nostrEventId == null &&
                (d.sleepHours != null || d.activeEnergyKcal != null),
          )
          .toList();
    } catch (e) {
      throw StorageFailure('Failed to read unpublished wellness days', e);
    }
  }

  @override
  Future<void> markBackedUp(DailyWellness day, String eventId) async {
    try {
      await _box.put(day.dayKey, {...day.toMap(), 'nostrEventId': eventId});
    } catch (e) {
      throw StorageFailure('Failed to mark wellness day backed up', e);
    }
  }
}
