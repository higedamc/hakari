import 'package:flutter_test/flutter_test.dart';
import 'package:hakari/data/health/health_kit_connect_service.dart';
import 'package:hakari/domain/entities/weight_entry.dart';

void main() {
  final t0 = DateTime(2026, 7, 1, 7, 30);

  String Function() sequentialIds() {
    var n = 0;
    return () => 'gen-${n++}';
  }

  HealthSample weight(DateTime at, double kg, {String uuid = ''}) =>
      HealthSample(uuid: uuid, timestamp: at, value: kg);

  HealthSample fat(DateTime at, double percent, {String uuid = ''}) =>
      HealthSample(uuid: uuid, timestamp: at, value: percent);

  group('mergeSamples', () {
    test('returns empty list for no samples', () {
      final entries = HealthKitConnectService.mergeSamples(
        weightSamples: [],
        bodyFatSamples: [],
        generateId: sequentialIds(),
      );
      expect(entries, isEmpty);
    });

    test('weight without body fat maps to entry with null bodyFatPercent', () {
      final entries = HealthKitConnectService.mergeSamples(
        weightSamples: [weight(t0, 72.4, uuid: 'w-1')],
        bodyFatSamples: [],
        generateId: sequentialIds(),
      );
      expect(entries, hasLength(1));
      final entry = entries.single;
      expect(entry.id, 'w-1');
      expect(entry.recordedAt, t0);
      expect(entry.weightKg, 72.4);
      expect(entry.bodyFatPercent, isNull);
      expect(entry.source, MeasurementSource.healthSync);
      expect(entry.syncedToHealth, isTrue);
    });

    test('body fat with identical timestamp is merged', () {
      final entries = HealthKitConnectService.mergeSamples(
        weightSamples: [weight(t0, 72.4, uuid: 'w-1')],
        bodyFatSamples: [fat(t0, 23.5)],
        generateId: sequentialIds(),
      );
      expect(entries.single.bodyFatPercent, 23.5);
    });

    test('body fat within +-60s is merged', () {
      final entries = HealthKitConnectService.mergeSamples(
        weightSamples: [
          weight(t0, 72.4, uuid: 'w-1'),
          weight(t0.add(const Duration(hours: 2)), 72.0, uuid: 'w-2'),
        ],
        bodyFatSamples: [
          fat(t0.add(const Duration(seconds: 59)), 23.5),
          fat(t0.add(const Duration(hours: 2, seconds: -60)), 22.9),
        ],
        generateId: sequentialIds(),
      );
      expect(entries, hasLength(2));
      expect(entries[0].bodyFatPercent, 23.5);
      expect(entries[1].bodyFatPercent, 22.9);
    });

    test('body fat outside 60s window is not merged', () {
      final entries = HealthKitConnectService.mergeSamples(
        weightSamples: [weight(t0, 72.4, uuid: 'w-1')],
        bodyFatSamples: [fat(t0.add(const Duration(seconds: 61)), 23.5)],
        generateId: sequentialIds(),
      );
      expect(entries.single.bodyFatPercent, isNull);
    });

    test('closest body fat sample wins when several are in the window', () {
      final entries = HealthKitConnectService.mergeSamples(
        weightSamples: [weight(t0, 72.4, uuid: 'w-1')],
        bodyFatSamples: [
          fat(t0.add(const Duration(seconds: 40)), 30.0),
          fat(t0.add(const Duration(seconds: 5)), 23.5),
          fat(t0.subtract(const Duration(seconds: 20)), 25.0),
        ],
        generateId: sequentialIds(),
      );
      expect(entries.single.bodyFatPercent, 23.5);
    });

    test('each body fat sample is consumed at most once', () {
      final entries = HealthKitConnectService.mergeSamples(
        weightSamples: [
          weight(t0, 72.4, uuid: 'w-1'),
          weight(t0.add(const Duration(seconds: 30)), 72.5, uuid: 'w-2'),
        ],
        bodyFatSamples: [fat(t0, 23.5)],
        generateId: sequentialIds(),
      );
      expect(entries, hasLength(2));
      expect(entries[0].bodyFatPercent, 23.5);
      expect(entries[1].bodyFatPercent, isNull);
    });

    test('unmatched body fat samples never create entries', () {
      final entries = HealthKitConnectService.mergeSamples(
        weightSamples: [],
        bodyFatSamples: [fat(t0, 23.5)],
        generateId: sequentialIds(),
      );
      expect(entries, isEmpty);
    });

    test('uses platform uuid when present, generated id otherwise', () {
      final entries = HealthKitConnectService.mergeSamples(
        weightSamples: [
          weight(t0, 72.4, uuid: 'hk-uuid-1'),
          weight(t0.add(const Duration(days: 1)), 72.0),
        ],
        bodyFatSamples: [],
        generateId: sequentialIds(),
      );
      expect(entries[0].id, 'hk-uuid-1');
      expect(entries[1].id, 'gen-0');
    });

    test('results are sorted by timestamp ascending', () {
      final entries = HealthKitConnectService.mergeSamples(
        weightSamples: [
          weight(t0.add(const Duration(days: 2)), 71.0, uuid: 'w-3'),
          weight(t0, 72.4, uuid: 'w-1'),
          weight(t0.add(const Duration(days: 1)), 72.0, uuid: 'w-2'),
        ],
        bodyFatSamples: [],
        generateId: sequentialIds(),
      );
      expect(entries.map((e) => e.id).toList(), ['w-1', 'w-2', 'w-3']);
    });

    test('custom match window is honored', () {
      final entries = HealthKitConnectService.mergeSamples(
        weightSamples: [weight(t0, 72.4, uuid: 'w-1')],
        bodyFatSamples: [fat(t0.add(const Duration(minutes: 5)), 23.5)],
        generateId: sequentialIds(),
        matchWindow: const Duration(minutes: 10),
      );
      expect(entries.single.bodyFatPercent, 23.5);
    });
  });

  group('body fat platform value conversion', () {
    test('to platform: iOS uses 0-1 fraction, Android uses 0-100', () {
      expect(
        HealthKitConnectService.bodyFatToPlatformValue(23.5, isIOS: true),
        closeTo(0.235, 1e-9),
      );
      expect(
        HealthKitConnectService.bodyFatToPlatformValue(23.5, isIOS: false),
        23.5,
      );
    });

    test('from platform: iOS fraction is scaled back to percent', () {
      expect(
        HealthKitConnectService.bodyFatFromPlatformValue(0.235, isIOS: true),
        closeTo(23.5, 1e-9),
      );
      expect(
        HealthKitConnectService.bodyFatFromPlatformValue(23.5, isIOS: false),
        23.5,
      );
    });

    test('round-trips on both platforms', () {
      for (final isIOS in [true, false]) {
        final raw = HealthKitConnectService.bodyFatToPlatformValue(
          31.7,
          isIOS: isIOS,
        );
        expect(
          HealthKitConnectService.bodyFatFromPlatformValue(raw, isIOS: isIOS),
          closeTo(31.7, 1e-9),
        );
      }
    });
  });
}
