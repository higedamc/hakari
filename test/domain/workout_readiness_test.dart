import 'package:flutter_test/flutter_test.dart';
import 'package:hakari/domain/entities/daily_wellness.dart';
import 'package:hakari/domain/services/workout_readiness.dart';

DailyWellness day(int daysAgo, {double? sleep, double? energy}) =>
    DailyWellness(
      day: DateTime(2026, 7, 8).subtract(Duration(days: daysAgo)),
      sleepHours: sleep,
      activeEnergyKcal: energy,
    );

void main() {
  group('computeReadiness', () {
    test('returns null without any sleep data', () {
      expect(computeReadiness(const []), isNull);
      expect(computeReadiness([day(0, energy: 300)]), isNull);
    });

    test('optimal sleep scores 100 and headline says train', () {
      final result = computeReadiness([
        for (var i = 7; i >= 0; i--) day(i, sleep: 8, energy: 400),
      ]);
      expect(result!.readinessPercent, 100);
      expect(result.headline, 'Great day to train');
    });

    test('short last night drops readiness steeply', () {
      final result = computeReadiness([
        for (var i = 7; i >= 1; i--) day(i, sleep: 8, energy: 400),
        day(0, sleep: 5),
      ]);
      // 5h → factor 0.5 → 50%.
      expect(result!.readinessPercent, 50);
      expect(result.headline, 'Take it moderate');
    });

    test('chronic short sleep adds a debt penalty', () {
      final result = computeReadiness([
        for (var i = 7; i >= 0; i--) day(i, sleep: 5.5, energy: 400),
      ]);
      // 5.5h → 62.5 minus 10 debt = 52.5 → 53.
      expect(result!.readinessPercent, lessThan(56));
      expect(result.reasons.any((r) => r.contains('Sleep debt')), isTrue);
    });

    test('heavy yesterday subtracts recovery penalty', () {
      final rested = computeReadiness([
        for (var i = 7; i >= 2; i--) day(i, sleep: 8, energy: 400),
        day(1, sleep: 8, energy: 400),
        day(0, sleep: 8),
      ]);
      final smashed = computeReadiness([
        for (var i = 7; i >= 2; i--) day(i, sleep: 8, energy: 400),
        day(1, sleep: 8, energy: 900),
        day(0, sleep: 8),
      ]);
      expect(smashed!.readinessPercent, lessThan(rested!.readinessPercent));
      expect(smashed.reasons.any((r) => r.contains('Heavy activity')), isTrue);
    });

    test('diet efficiency maps the Nedeltcheva endpoints', () {
      final short = computeReadiness([
        for (var i = 7; i >= 0; i--) day(i, sleep: 5.5),
      ]);
      final long = computeReadiness([
        for (var i = 7; i >= 0; i--) day(i, sleep: 8.5),
      ]);
      expect(short!.dietEfficiencyPercent, 25);
      expect(long!.dietEfficiencyPercent, 55);
    });

    test('efficiency is clamped for extreme sleep values', () {
      final tiny = computeReadiness([day(0, sleep: 2)]);
      final huge = computeReadiness([day(0, sleep: 12)]);
      expect(tiny!.dietEfficiencyPercent, 20);
      expect(huge!.dietEfficiencyPercent, 60);
    });

    test('missing last night falls back to the average', () {
      final result = computeReadiness([
        for (var i = 7; i >= 1; i--) day(i, sleep: 8, energy: 400),
        day(0), // today: no sleep record yet
      ]);
      expect(result!.readinessPercent, 100);
      expect(result.reasons.first, contains('No sleep record'));
    });
  });
}
