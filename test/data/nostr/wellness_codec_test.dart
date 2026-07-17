import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hakari/data/nostr/nip101h_codec.dart';
import 'package:hakari/domain/entities/daily_wellness.dart';

void main() {
  group('wellnessPlaintext', () {
    test('serializes day key and only present fields', () {
      final json =
          jsonDecode(
                wellnessPlaintext(
                  DailyWellness(day: DateTime(2026, 7, 8), sleepHours: 7.5),
                ),
              )
              as Map<String, dynamic>;
      expect(json, {'day': '2026-07-08', 'sleep_hours': 7.5});
    });
  });

  group('isWellnessEvent', () {
    test('detects the wellness d-tag prefix', () {
      expect(
        isWellnessEvent([
          ['d', 'hakari:wellness:2026-07-08'],
        ]),
        isTrue,
      );
      expect(
        isWellnessEvent([
          ['d', 'hakari:entry:some-uuid'],
        ]),
        isFalse,
      );
      expect(isWellnessEvent([]), isFalse);
    });
  });

  group('wellnessFromBackupMap', () {
    test('round-trips through the plaintext codec', () {
      final original = DailyWellness(
        day: DateTime(2026, 7, 8),
        sleepHours: 7.5,
        activeEnergyKcal: 420,
      );
      final map =
          jsonDecode(wellnessPlaintext(original)) as Map<String, dynamic>;
      final restored = wellnessFromBackupMap(map, backupEventId: 'ev1');
      expect(restored, isNotNull);
      expect(restored!.day, original.day);
      expect(restored.sleepHours, 7.5);
      expect(restored.activeEnergyKcal, 420);
      expect(restored.nostrEventId, 'ev1');
    });

    test('rejects hostile payloads', () {
      DailyWellness? parse(Map<String, dynamic> map) =>
          wellnessFromBackupMap(map, backupEventId: 'ev');
      expect(parse({}), isNull);
      expect(parse({'day': 'not-a-date', 'sleep_hours': 7}), isNull);
      expect(parse({'day': '2026-07-08'}), isNull); // no data
      expect(parse({'day': '2026-07-08', 'sleep_hours': 99}), isNull);
      expect(parse({'day': '2026-07-08', 'active_energy_kcal': -5}), isNull);
      expect(parse({'day': '2026-99-08', 'sleep_hours': 7}), isNull);
    });
  });
}
