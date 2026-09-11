import 'package:flutter_test/flutter_test.dart';
import 'package:hakari/data/healthplanet/health_planet_codec.dart';
import 'package:hakari/domain/entities/weight_entry.dart';
import 'package:hakari/domain/failures/failures.dart';

void main() {
  group('parseTokenResponse', () {
    test('extracts access and refresh tokens', () {
      final (access, refresh) = HealthPlanetCodec.parseTokenResponse(
        '{"access_token":"abc","expires_in":2592000,'
        '"refresh_token":"def"}',
      );
      expect(access, 'abc');
      expect(refresh, 'def');
    });

    test('throws on error payloads and malformed JSON', () {
      expect(
        () => HealthPlanetCodec.parseTokenResponse('{"error":"invalid_grant"}'),
        throwsA(isA<HealthPlanetFailure>()),
      );
      expect(
        () => HealthPlanetCodec.parseTokenResponse('not json'),
        throwsA(isA<HealthPlanetFailure>()),
      );
      expect(
        () => HealthPlanetCodec.parseTokenResponse('{"access_token":""}'),
        throwsA(isA<HealthPlanetFailure>()),
      );
    });
  });

  group('parseInnerscan', () {
    var counter = 0;
    String nextId() => 'id-${counter++}';

    setUp(() => counter = 0);

    test('groups tag rows by measurement date into one entry', () {
      const body = '''
      {"birth_date":"19900101","height":"170","sex":"male","data":[
        {"date":"202607070900","keydata":"71.90","model":"01000144","tag":"6021"},
        {"date":"202607070900","keydata":"18.40","model":"01000144","tag":"6022"},
        {"date":"202607070900","keydata":"30.10","model":"01000144","tag":"6023"},
        {"date":"202607070900","keydata":"2","model":"01000144","tag":"6024"},
        {"date":"202607070900","keydata":"7.5","model":"01000144","tag":"6025"},
        {"date":"202607070900","keydata":"7","model":"01000144","tag":"6026"},
        {"date":"202607070900","keydata":"1560","model":"01000144","tag":"6027"},
        {"date":"202607070900","keydata":"28","model":"01000144","tag":"6028"},
        {"date":"202607070900","keydata":"2.90","model":"01000144","tag":"6029"},
        {"date":"202607060830","keydata":"72.40","model":"01000144","tag":"6021"}
      ]}''';

      final entries = HealthPlanetCodec.parseInnerscan(
        body,
        generateId: nextId,
      );

      expect(entries, hasLength(2));
      // Sorted newest first.
      final full = entries.first;
      expect(full.recordedAt, DateTime(2026, 7, 7, 9, 0));
      expect(full.weightKg, 71.9);
      expect(full.bodyFatPercent, 18.4);
      expect(full.muscleMassKg, 30.1);
      expect(full.muscleScore, 2);
      expect(full.visceralFatRating, 7);
      expect(full.visceralFatLevel2, 7.5);
      expect(full.basalMetabolicRateKcal, 1560);
      expect(full.metabolicAge, 28);
      expect(full.boneMassKg, 2.9);
      expect(full.source, MeasurementSource.imported);
      expect(entries[1].weightKg, 72.4);
      expect(entries[1].bodyFatPercent, isNull);
    });

    test('skips hostile rows without failing the sync', () {
      const body = '''
      {"data":[
        {"date":"202607070900","keydata":"NaN","model":"m","tag":"6021"},
        {"date":"202607070901","keydata":"9999","model":"m","tag":"6021"},
        {"date":"bogus","keydata":"70.0","model":"m","tag":"6021"},
        {"date":"202607070902","keydata":"70.0","model":"m","tag":"6022"},
        {"date":"202607070903","keydata":"70.5","model":"m","tag":"6021"}
      ]}''';

      final entries = HealthPlanetCodec.parseInnerscan(
        body,
        generateId: nextId,
      );

      // Only the last row is a valid weight measurement; the fat-only
      // group has no weight and is dropped.
      expect(entries, hasLength(1));
      expect(entries.single.weightKg, 70.5);
    });

    test('returns empty list when data is missing', () {
      expect(
        HealthPlanetCodec.parseInnerscan('{}', generateId: nextId),
        isEmpty,
      );
    });

    test('throws on malformed JSON', () {
      expect(
        () => HealthPlanetCodec.parseInnerscan('<html>', generateId: nextId),
        throwsA(isA<HealthPlanetFailure>()),
      );
    });
  });

  group('parseInnerscanPayload height', () {
    var counter = 0;
    String nextId() => 'id-${counter++}';

    test('extracts the top-level height next to the entries', () {
      const body = '''
      {"birth_date":"19900101","height":"177.5","sex":"male","data":[
        {"date":"202607070900","keydata":"71.90","model":"01000144","tag":"6021"}
      ]}''';
      final payload = HealthPlanetCodec.parseInnerscanPayload(
        body,
        generateId: nextId,
      );
      expect(payload.heightCm, 177.5);
      expect(payload.entries, hasLength(1));
      expect(payload.entries.single.weightKg, 71.9);
    });

    test('accepts a numeric height and trims whitespace', () {
      expect(
        HealthPlanetCodec.parseInnerscanPayload(
          '{"height":170,"data":[]}',
          generateId: nextId,
        ).heightCm,
        170.0,
      );
      expect(
        HealthPlanetCodec.parseInnerscanPayload(
          '{"height":" 165.0 ","data":[]}',
          generateId: nextId,
        ).heightCm,
        165.0,
      );
    });

    test('height is present even when data is missing', () {
      final payload = HealthPlanetCodec.parseInnerscanPayload(
        '{"height":"170"}',
        generateId: nextId,
      );
      expect(payload.heightCm, 170.0);
      expect(payload.entries, isEmpty);
    });

    test('missing / empty / non-numeric / out-of-range height reads as null '
        'without failing the entry parse', () {
      const row =
          '{"date":"202607070900","keydata":"71.90","model":"m","tag":"6021"}';
      for (final height in [
        null,
        '""',
        '"abc"',
        '"NaN"',
        '"Infinity"',
        '"0"',
        '"49.9"',
        '"250.1"',
        '"9999"',
        '"-170"',
        'true',
        '[170]',
        '{"cm":170}',
      ]) {
        final body = height == null
            ? '{"data":[$row]}'
            : '{"height":$height,"data":[$row]}';
        final payload = HealthPlanetCodec.parseInnerscanPayload(
          body,
          generateId: nextId,
        );
        expect(payload.heightCm, isNull, reason: 'height=$height');
        expect(payload.entries, hasLength(1), reason: 'height=$height');
      }
    });

    test('parseInnerscan still returns just the entries', () {
      final entries = HealthPlanetCodec.parseInnerscan(
        '{"height":"177.5","data":[]}',
        generateId: nextId,
      );
      expect(entries, isEmpty);
    });
  });

  test('formatRequestDate emits yyyyMMddHHmmss', () {
    expect(
      HealthPlanetCodec.formatRequestDate(DateTime(2026, 7, 7, 9, 5, 3)),
      '20260707090503',
    );
  });
}
