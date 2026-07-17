import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hakari/data/local/hive_wellness_repository.dart';
import 'package:hakari/domain/entities/daily_wellness.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory tempDir;
  late Box box;
  late HiveWellnessRepository repo;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('wellness_test');
    Hive.init(tempDir.path);
    box = await Hive.openBox<dynamic>('wellness_test');
    repo = HiveWellnessRepository(box);
  });

  tearDown(() async {
    await box.deleteFromDisk();
    await tempDir.delete(recursive: true);
  });

  DailyWellness day(int d, {double? sleep, double? energy, String? eventId}) =>
      DailyWellness(
        day: DateTime(2026, 7, d),
        sleepHours: sleep,
        activeEnergyKcal: energy,
        nostrEventId: eventId,
      );

  test('round-trips a day through the map codec', () async {
    await repo.upsertDay(day(8, sleep: 7.5, energy: 420));
    final all = await repo.getAll();
    expect(all, hasLength(1));
    expect(all.single.day, DateTime(2026, 7, 8));
    expect(all.single.sleepHours, 7.5);
    expect(all.single.activeEnergyKcal, 420);
    expect(all.single.nostrEventId, isNull);
  });

  test('merge fills missing fields without overwriting', () async {
    await repo.upsertDay(day(8, sleep: 7.5));
    await repo.upsertDay(day(8, sleep: 6.0, energy: 400));
    final stored = (await repo.getAll()).single;
    expect(stored.sleepHours, 7.5); // kept, not overwritten
    expect(stored.activeEnergyKcal, 400); // filled
  });

  test('merge that changes data clears the backup event id', () async {
    await repo.upsertDay(day(8, sleep: 7.5));
    await repo.markBackedUp((await repo.getAll()).single, 'event123');
    expect((await repo.getUnpublished()), isEmpty);

    // New data arrives for the same day: needs re-backup.
    await repo.upsertDay(day(8, energy: 400));
    final unpublished = await repo.getUnpublished();
    expect(unpublished, hasLength(1));
    expect(unpublished.single.nostrEventId, isNull);
  });

  test('no-op merge keeps the backup event id', () async {
    await repo.upsertDay(day(8, sleep: 7.5, energy: 400));
    await repo.markBackedUp((await repo.getAll()).single, 'event123');
    await repo.upsertDay(day(8, sleep: 7.0, energy: 300)); // nothing missing
    expect(await repo.getUnpublished(), isEmpty);
    expect((await repo.getAll()).single.sleepHours, 7.5);
  });

  test('getRange filters by calendar day inclusive', () async {
    for (var d = 1; d <= 10; d++) {
      await repo.upsertDay(day(d, sleep: 7));
    }
    final range = await repo.getRange(
      DateTime(2026, 7, 3, 14, 30),
      DateTime(2026, 7, 6, 2, 0),
    );
    expect(range.map((d) => d.day.day), [6, 5, 4, 3]);
  });

  test('getUnpublished skips empty days and orders oldest first', () async {
    await repo.upsertDay(day(3, sleep: 7));
    await repo.upsertDay(day(1, energy: 300));
    await repo.upsertDay(day(2)); // no data — never published
    final unpublished = await repo.getUnpublished();
    expect(unpublished.map((d) => d.day.day), [1, 3]);
  });
}
