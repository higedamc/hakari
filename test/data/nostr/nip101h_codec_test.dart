import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hakari/data/nostr/nip101h_codec.dart';
import 'package:hakari/domain/entities/weight_entry.dart';

void main() {
  final fullEntry = WeightEntry(
    id: 'entry-123',
    recordedAt: DateTime.fromMillisecondsSinceEpoch(1752000000 * 1000),
    weightKg: 72.5,
    bodyFatPercent: 21.3,
    bodyWaterPercent: 55.0,
    muscleMassKg: 54.2,
    visceralFatRating: 7,
    boneMassKg: 2.9,
    basalMetabolicRateKcal: 1620,
    metabolicAge: 30,
    source: MeasurementSource.bleScale,
  );

  group('backupPlaintext (kind 30078 content)', () {
    test('serializes the full entry with the wire field names', () {
      final json = jsonDecode(
        backupPlaintext(fullEntry, weightEventId: 'abc123'),
      ) as Map<String, dynamic>;

      expect(json['id'], 'entry-123');
      expect(json['recorded_at'], 1752000000);
      expect(json['weight_kg'], 72.5);
      expect(json['body_fat_percent'], 21.3);
      expect(json['body_water_percent'], 55.0);
      expect(json['muscle_mass_kg'], 54.2);
      expect(json['visceral_fat_rating'], 7);
      expect(json['bone_mass_kg'], 2.9);
      expect(json['basal_metabolic_rate_kcal'], 1620);
      expect(json['metabolic_age'], 30);
      expect(json['source'], 'bleScale');
      expect(json['weight_event_id'], 'abc123');
    });

    test('omits null optionals (matches Rust skip_serializing_if)', () {
      final sparse = WeightEntry(
        id: 'entry-9',
        recordedAt: DateTime.fromMillisecondsSinceEpoch(1752000000 * 1000),
        weightKg: 81.0,
      );
      final json =
          jsonDecode(backupPlaintext(sparse)) as Map<String, dynamic>;

      expect(json.containsKey('body_fat_percent'), isFalse);
      expect(json.containsKey('weight_event_id'), isFalse);
      expect(json['weight_kg'], 81.0);
    });
  });

  group('entryFromBackupMap (30078 JSON -> WeightEntry)', () {
    test('roundtrips through backupPlaintext', () {
      final map = jsonDecode(
        backupPlaintext(fullEntry, weightEventId: 'abc123'),
      ) as Map<String, dynamic>;
      final entry = entryFromBackupMap(map, backupEventId: 'backup-event-id');

      expect(entry.id, fullEntry.id);
      expect(entry.recordedAt, fullEntry.recordedAt);
      expect(entry.weightKg, fullEntry.weightKg);
      expect(entry.bodyFatPercent, fullEntry.bodyFatPercent);
      expect(entry.bodyWaterPercent, fullEntry.bodyWaterPercent);
      expect(entry.muscleMassKg, fullEntry.muscleMassKg);
      expect(entry.visceralFatRating, fullEntry.visceralFatRating);
      expect(entry.boneMassKg, fullEntry.boneMassKg);
      expect(entry.basalMetabolicRateKcal, fullEntry.basalMetabolicRateKcal);
      expect(entry.metabolicAge, fullEntry.metabolicAge);
      // Entries fetched from relays are marked as imported.
      expect(entry.source, MeasurementSource.imported);
      // nostrEventId prefers the referenced 1351 event id.
      expect(entry.nostrEventId, 'abc123');
    });

    test('falls back to the 30078 event id without weight_event_id', () {
      final map =
          jsonDecode(backupPlaintext(fullEntry)) as Map<String, dynamic>;
      final entry = entryFromBackupMap(map, backupEventId: 'backup-event-id');
      expect(entry.nostrEventId, 'backup-event-id');
      expect(weightEventIdOfBackup(map), isNull);
    });
  });

  group('entryFromWeightEvent (stand-alone kind 1351)', () {
    test('parses weight content and timestamp tag', () {
      final entry = entryFromWeightEvent(
        eventId: 'weight-event-id',
        createdAtUnix: 1752000000,
        content: '72.5',
        tags: [
          ['unit', 'kg'],
          ['t', 'health'],
          ['t', 'weight'],
          ['timestamp', '2025-07-01T10:30:00Z'],
        ],
      );

      expect(entry, isNotNull);
      expect(entry!.weightKg, 72.5);
      expect(entry.recordedAt, DateTime.parse('2025-07-01T10:30:00Z'));
      expect(entry.nostrEventId, 'weight-event-id');
      expect(entry.id, 'weight-event-id');
      expect(entry.source, MeasurementSource.imported);
    });

    test('uses created_at when timestamp tag is missing', () {
      final entry = entryFromWeightEvent(
        eventId: 'e1',
        createdAtUnix: 1752000000,
        content: '81.0',
        tags: [
          ['unit', 'kg'],
        ],
      );
      expect(
        entry!.recordedAt,
        DateTime.fromMillisecondsSinceEpoch(1752000000 * 1000),
      );
    });

    test('returns null for non-numeric (still-encrypted) content', () {
      final entry = entryFromWeightEvent(
        eventId: 'e2',
        createdAtUnix: 1752000000,
        content: 'AqTBz...ciphertext',
        tags: const [],
      );
      expect(entry, isNull);
    });
  });

  group('tag helpers', () {
    test('tagValue and isEncryptedWeightEvent', () {
      final tags = [
        ['unit', 'kg'],
        ['encrypted', 'true'],
        ['encryption_algo', 'nip44'],
        ['p', 'deadbeef'],
      ];
      expect(tagValue(tags, 'unit'), 'kg');
      expect(tagValue(tags, 'missing'), isNull);
      expect(isEncryptedWeightEvent(tags), isTrue);
      expect(
        isEncryptedWeightEvent([
          ['unit', 'kg'],
        ]),
        isFalse,
      );
    });
  });

  test('weightContent matches the Rust formatter', () {
    expect(weightContent(72.5), '72.5');
    expect(weightContent(72.0), '72.0');
    expect(weightContent(103.25), '103.25');
  });
}
