import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hakari/data/local/hive_weight_repository.dart';
import 'package:hakari/domain/entities/weight_entry.dart';
import 'package:hive/hive.dart';

WeightEntry _entry({
  required String id,
  required DateTime recordedAt,
  double weightKg = 70.0,
  String? nostrEventId,
}) {
  return WeightEntry(
    id: id,
    recordedAt: recordedAt,
    weightKg: weightKg,
    bodyFatPercent: 21.5,
    source: MeasurementSource.bleScale,
    nostrEventId: nostrEventId,
  );
}

void main() {
  late Directory tempDir;
  late Box box;
  late HiveWeightRepository repo;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('hakari_hive_test_');
    Hive.init(tempDir.path);
    box = await HiveWeightRepository.openBox();
    repo = HiveWeightRepository(box);
  });

  tearDown(() async {
    await box.deleteFromDisk();
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  test('getAll returns empty list for empty box', () async {
    expect(await repo.getAll(), isEmpty);
  });

  test('upsert then getAll round-trips all fields', () async {
    final entry = WeightEntry(
      id: 'a',
      recordedAt: DateTime(2026, 7, 1, 8, 30),
      weightKg: 72.4,
      bodyFatPercent: 20.1,
      bodyWaterPercent: 55.2,
      muscleMassKg: 54.3,
      visceralFatRating: 7,
      boneMassKg: 3.1,
      basalMetabolicRateKcal: 1650,
      metabolicAge: 33,
      source: MeasurementSource.bleScale,
      nostrEventId: 'deadbeef',
      syncedToHealth: true,
    );
    await repo.upsert(entry);

    final all = await repo.getAll();
    expect(all, hasLength(1));
    final read = all.single;
    expect(read.id, entry.id);
    expect(read.recordedAt, entry.recordedAt);
    expect(read.weightKg, entry.weightKg);
    expect(read.bodyFatPercent, entry.bodyFatPercent);
    expect(read.bodyWaterPercent, entry.bodyWaterPercent);
    expect(read.muscleMassKg, entry.muscleMassKg);
    expect(read.visceralFatRating, entry.visceralFatRating);
    expect(read.boneMassKg, entry.boneMassKg);
    expect(read.basalMetabolicRateKcal, entry.basalMetabolicRateKcal);
    expect(read.metabolicAge, entry.metabolicAge);
    expect(read.source, entry.source);
    expect(read.nostrEventId, entry.nostrEventId);
    expect(read.syncedToHealth, entry.syncedToHealth);
  });

  test('getAll sorts by recordedAt descending', () async {
    await repo.upsert(_entry(id: 'old', recordedAt: DateTime(2026, 7, 1)));
    await repo.upsert(_entry(id: 'new', recordedAt: DateTime(2026, 7, 5)));
    await repo.upsert(_entry(id: 'mid', recordedAt: DateTime(2026, 7, 3)));

    final all = await repo.getAll();
    expect(all.map((e) => e.id).toList(), ['new', 'mid', 'old']);
  });

  test('upsert with existing id updates the entry', () async {
    await repo.upsert(
      _entry(id: 'a', recordedAt: DateTime(2026, 7, 1), weightKg: 70.0),
    );
    await repo.upsert(
      _entry(id: 'a', recordedAt: DateTime(2026, 7, 1), weightKg: 71.5),
    );

    final all = await repo.getAll();
    expect(all, hasLength(1));
    expect(all.single.weightKg, 71.5);
  });

  test('getById returns entry or null', () async {
    await repo.upsert(_entry(id: 'a', recordedAt: DateTime(2026, 7, 1)));

    expect((await repo.getById('a'))?.id, 'a');
    expect(await repo.getById('missing'), isNull);
  });

  test('delete removes the entry', () async {
    await repo.upsert(_entry(id: 'a', recordedAt: DateTime(2026, 7, 1)));
    await repo.delete('a');

    expect(await repo.getAll(), isEmpty);
  });

  test('getUnpublished returns only entries without nostrEventId', () async {
    await repo.upsert(_entry(
      id: 'published',
      recordedAt: DateTime(2026, 7, 1),
      nostrEventId: 'abc123',
    ));
    await repo.upsert(_entry(id: 'draft1', recordedAt: DateTime(2026, 7, 2)));
    await repo.upsert(_entry(id: 'draft2', recordedAt: DateTime(2026, 7, 4)));

    final unpublished = await repo.getUnpublished();
    expect(unpublished.map((e) => e.id).toList(), ['draft2', 'draft1']);
  });

  test('watchAll emits current list immediately, then on every change',
      () async {
    await repo.upsert(_entry(id: 'a', recordedAt: DateTime(2026, 7, 1)));

    final events = <List<WeightEntry>>[];
    final sub = repo.watchAll().listen(events.add);
    addTearDown(sub.cancel);

    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(events, hasLength(1));
    expect(events.first.single.id, 'a');

    await repo.upsert(_entry(id: 'b', recordedAt: DateTime(2026, 7, 2)));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(events, hasLength(2));
    expect(events.last.map((e) => e.id).toList(), ['b', 'a']);

    await repo.delete('a');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(events, hasLength(3));
    expect(events.last.map((e) => e.id).toList(), ['b']);
  });
}
