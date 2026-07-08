import 'package:flutter_test/flutter_test.dart';
import 'package:hakari/data/health/health_kit_connect_service.dart';

void main() {
  final today = DateTime(2026, 7, 8);

  group('buildDailyWellness', () {
    test('assigns a night to the morning it ends on and sums energy', () {
      final result = HealthKitConnectService.buildDailyWellness(
        sleep: [
          SleepSpan(
            start: DateTime(2026, 7, 7, 23, 0),
            end: DateTime(2026, 7, 8, 6, 30),
          ),
        ],
        energy: [
          HealthSample(
            uuid: 'a',
            timestamp: DateTime(2026, 7, 7, 10),
            value: 250,
          ),
          HealthSample(
            uuid: 'b',
            timestamp: DateTime(2026, 7, 7, 18),
            value: 150,
          ),
        ],
        today: today,
        days: 2,
      );

      expect(result, hasLength(2));
      expect(result[0].day, DateTime(2026, 7, 7));
      expect(result[0].sleepHours, isNull);
      expect(result[0].activeEnergyKcal, 400);
      expect(result[1].day, today);
      expect(result[1].sleepHours, closeTo(7.5, 0.01));
      expect(result[1].activeEnergyKcal, isNull);
    });

    test('collapses duplicate spans and sums split segments', () {
      final result = HealthKitConnectService.buildDailyWellness(
        sleep: [
          // Session and an identical duplicate.
          SleepSpan(
            start: DateTime(2026, 7, 7, 23),
            end: DateTime(2026, 7, 8, 3),
          ),
          SleepSpan(
            start: DateTime(2026, 7, 7, 23),
            end: DateTime(2026, 7, 8, 3),
          ),
          // A second segment after a wake gap.
          SleepSpan(
            start: DateTime(2026, 7, 8, 3, 30),
            end: DateTime(2026, 7, 8, 6, 30),
          ),
        ],
        energy: const [],
        today: today,
        days: 1,
      );

      expect(result.single.sleepHours, closeTo(7.0, 0.01));
    });

    test('ignores zero/negative spans and out-of-window samples', () {
      final result = HealthKitConnectService.buildDailyWellness(
        sleep: [
          SleepSpan(
            start: DateTime(2026, 7, 8, 6),
            end: DateTime(2026, 7, 8, 6),
          ),
        ],
        energy: [
          HealthSample(uuid: 'x', timestamp: DateTime(2026, 6, 1), value: 500),
        ],
        today: today,
        days: 2,
      );

      expect(result[0].sleepHours, isNull);
      expect(result[0].activeEnergyKcal, isNull);
      expect(result[1].sleepHours, isNull);
    });
  });
}
