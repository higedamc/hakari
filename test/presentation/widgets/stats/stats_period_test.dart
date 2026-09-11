import 'package:flutter_test/flutter_test.dart';
import 'package:hakari/domain/entities/weight_entry.dart';
import 'package:hakari/presentation/widgets/stats/stats_period.dart';

WeightEntry _e(String id, DateTime at, double kg, {double? fat}) =>
    WeightEntry(id: id, recordedAt: at, weightKg: kg, bodyFatPercent: fat);

void main() {
  final now = DateTime(2026, 9, 12, 12);
  final entries = [
    _e('a', now.subtract(const Duration(days: 400)), 80, fat: 25),
    _e('b', now.subtract(const Duration(days: 200)), 78),
    _e('c', now.subtract(const Duration(days: 60)), 76, fat: 22),
    _e('d', now.subtract(const Duration(days: 10)), 75, fat: 21),
    _e('e', now.subtract(const Duration(days: 1)), 74.5),
  ];

  group('StatsPeriod.select', () {
    test('keeps entries inside the window, newest first', () {
      final oneMonth = StatsPeriod.oneMonth.select(
        entries.reversed.toList(),
        now: now,
      );
      expect(oneMonth.map((e) => e.id), ['e', 'd']);
      expect(
        StatsPeriod.threeMonths.select(entries, now: now).map((e) => e.id),
        ['e', 'd', 'c'],
      );
      expect(StatsPeriod.oneYear.select(entries, now: now).map((e) => e.id), [
        'e',
        'd',
        'c',
        'b',
      ]);
      expect(StatsPeriod.all.select(entries, now: now), hasLength(5));
    });

    test('window start is inclusive', () {
      final onEdge = _e('x', now.subtract(const Duration(days: 30)), 70);
      expect(StatsPeriod.oneMonth.select([onEdge], now: now), [onEdge]);
    });

    test('default period is 3M', () {
      expect(StatsPeriod.initial, StatsPeriod.threeMonths);
    });
  });

  group('WeightSummary', () {
    test('null for an empty window', () {
      expect(WeightSummary.of(const []), isNull);
    });

    test('start is the oldest entry in the window, so it moves with the '
        'period; All starts at the first entry ever', () {
      final oneMonth = WeightSummary.of(
        StatsPeriod.oneMonth.select(entries, now: now),
      )!;
      final all = WeightSummary.of(StatsPeriod.all.select(entries, now: now))!;
      expect(oneMonth.start.id, 'd');
      expect(all.start.id, 'a');
      expect(oneMonth.current.id, 'e');
      expect(all.current.id, 'e');
      expect(oneMonth.changeKg, closeTo(-0.5, 1e-9));
      expect(all.changeKg, closeTo(-5.5, 1e-9));
    });

    test('average, min, max, count', () {
      final s = WeightSummary.of(
        StatsPeriod.threeMonths.select(entries, now: now),
      )!;
      expect(s.count, 3);
      expect(s.averageKg, closeTo((76 + 75 + 74.5) / 3, 1e-9));
      expect(s.minKg, 74.5);
      expect(s.maxKg, 76);
    });

    test('a single entry cannot measure progress', () {
      final s = WeightSummary.of([entries.last])!;
      expect(s.count, 1);
      expect(s.canMeasureProgress, isFalse);
      expect(s.changeKg, 0);
      expect(WeightSummary.of(entries)!.canMeasureProgress, isTrue);
    });
  });

  group('BodyMetric', () {
    test('entriesWithValue keeps only entries carrying the metric', () {
      final withFat = BodyMetric.bodyFat.entriesWithValue(
        StatsPeriod.all.select(entries, now: now),
      );
      expect(withFat.map((e) => e.id), ['d', 'c', 'a']);
      expect(BodyMetric.muscleMass.entriesWithValue(entries), isEmpty);
    });

    test('format respects unit and decimals', () {
      expect(BodyMetric.bodyFat.format(21.26), '21.3 %');
      expect(BodyMetric.visceralFat.format(7), '7');
      expect(BodyMetric.basalMetabolicRate.format(1560), '1560 kcal');
    });
  });
}
