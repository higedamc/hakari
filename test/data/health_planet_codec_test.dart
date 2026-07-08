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

  test('formatRequestDate emits yyyyMMddHHmmss', () {
    expect(
      HealthPlanetCodec.formatRequestDate(DateTime(2026, 7, 7, 9, 5, 3)),
      '20260707090503',
    );
  });
}
