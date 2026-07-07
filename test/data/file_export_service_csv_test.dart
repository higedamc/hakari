import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hakari/data/export/file_export_service.dart';
import 'package:hakari/domain/entities/weight_entry.dart';

void main() {
  group('escapeCsvField', () {
    test('leaves plain fields untouched', () {
      expect(FileExportService.escapeCsvField('72.4'), '72.4');
      expect(FileExportService.escapeCsvField(''), '');
    });

    test('quotes fields containing commas', () {
      expect(FileExportService.escapeCsvField('a,b'), '"a,b"');
    });

    test('quotes and doubles inner double quotes', () {
      expect(FileExportService.escapeCsvField('say "hi"'), '"say ""hi"""');
    });

    test('quotes fields containing newlines', () {
      expect(FileExportService.escapeCsvField('a\nb'), '"a\nb"');
      expect(FileExportService.escapeCsvField('a\r\nb'), '"a\r\nb"');
    });

    test('neutralizes spreadsheet formula triggers in non-numeric fields', () {
      expect(
        FileExportService.escapeCsvField('=HYPERLINK("http://evil")'),
        '"\'=HYPERLINK(""http://evil"")"',
      );
      expect(FileExportService.escapeCsvField('@cmd'), "'@cmd");
      expect(FileExportService.escapeCsvField('+SUM(1)'), "'+SUM(1)");
      expect(FileExportService.escapeCsvField('-2+3'), "'-2+3");
    });

    test('keeps negative numbers as numbers', () {
      expect(FileExportService.escapeCsvField('-2.5'), '-2.5');
      expect(FileExportService.escapeCsvField('+7'), '+7');
    });
  });

  group('buildCsv', () {
    test('emits WeightLogger-compatible header for empty list', () {
      expect(
        FileExportService.buildCsv(const []),
        'recorded_at,weight_kg,body_fat_percent,body_water_percent,'
        'muscle_mass_kg,visceral_fat_rating,bone_mass_kg,'
        'basal_metabolic_rate_kcal,metabolic_age,source',
      );
    });

    test('renders a full entry with ISO8601 timestamp and all columns', () {
      final entry = WeightEntry(
        id: 'a',
        recordedAt: DateTime(2026, 7, 1, 8, 30, 15),
        weightKg: 72.4,
        bodyFatPercent: 20.1,
        bodyWaterPercent: 55.2,
        muscleMassKg: 54.3,
        visceralFatRating: 7,
        boneMassKg: 3.1,
        basalMetabolicRateKcal: 1650,
        metabolicAge: 33,
        source: MeasurementSource.bleScale,
      );

      final csv = FileExportService.buildCsv([entry]);
      final lines = csv.split('\n');
      expect(lines, hasLength(2));
      expect(
        lines[1],
        '2026-07-01T08:30:15.000,72.4,20.1,55.2,54.3,7,3.1,1650,33,bleScale',
      );
    });

    test('renders null optional fields as empty columns', () {
      final entry = WeightEntry(
        id: 'a',
        recordedAt: DateTime(2026, 7, 1),
        weightKg: 70.0,
      );

      final row = FileExportService.buildCsvRow(entry);
      expect(row, '2026-07-01T00:00:00.000,70.0,,,,,,,,manual');
      expect(row.split(','), hasLength(10));
    });

    test('emits one row per entry in given order', () {
      final entries = [
        WeightEntry(id: 'a', recordedAt: DateTime(2026, 7, 2), weightKg: 71),
        WeightEntry(id: 'b', recordedAt: DateTime(2026, 7, 1), weightKg: 70),
      ];

      final lines = FileExportService.buildCsv(entries).split('\n');
      expect(lines, hasLength(3));
      expect(lines[1], startsWith('2026-07-02'));
      expect(lines[2], startsWith('2026-07-01'));
    });
  });

  group('buildJson', () {
    test('wraps entries in versioned envelope', () {
      final entry = WeightEntry(
        id: 'a',
        recordedAt: DateTime(2026, 7, 1),
        weightKg: 70.0,
        nostrEventId: 'abc',
      );

      final decoded =
          jsonDecode(FileExportService.buildJson([entry]))
              as Map<String, dynamic>;
      expect(decoded['app'], 'hakari');
      expect(decoded['version'], 1);
      final entries = decoded['entries'] as List;
      expect(entries, hasLength(1));
      final map = entries.single as Map<String, dynamic>;
      expect(map['id'], 'a');
      expect(map['weightKg'], 70.0);
      expect(map['nostrEventId'], 'abc');
      expect(map['recordedAt'], DateTime(2026, 7, 1).millisecondsSinceEpoch);
    });
  });
}
