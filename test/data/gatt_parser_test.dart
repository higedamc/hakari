import 'package:flutter_test/flutter_test.dart';
import 'package:hakari/data/ble/gatt_parser.dart';

/// Little-endian uint16 helper.
List<int> u16(int value) => [value & 0xFF, (value >> 8) & 0xFF];

/// GATT date_time: year uint16 LE, month, day, hours, minutes, seconds.
List<int> dateTimeBytes(DateTime dt) => [
      ...u16(dt.year),
      dt.month,
      dt.day,
      dt.hour,
      dt.minute,
      dt.second,
    ];

void main() {
  group('parseWeightMeasurement (0x2A9D)', () {
    test('SI weight only', () {
      // flags = 0x00 (SI, no optional fields); weight 15000 * 0.005 = 75 kg
      final m = parseWeightMeasurement([0x00, ...u16(15000)]);

      expect(m.weightKg, closeTo(75.0, 1e-9));
      expect(m.isImperial, isFalse);
      expect(m.timestamp, isNull);
      expect(m.userId, isNull);
      expect(m.bmi, isNull);
      expect(m.heightMeters, isNull);
    });

    test('imperial weight is converted to kg', () {
      // flags = 0x01 (imperial); weight 16534 * 0.01 = 165.34 lb
      final m = parseWeightMeasurement([0x01, ...u16(16534)]);

      expect(m.isImperial, isTrue);
      expect(m.weightKg, closeTo(165.34 * 0.45359237, 1e-9));
    });

    test('weight + timestamp + user id + BMI/height (SI)', () {
      final ts = DateTime(2026, 7, 7, 8, 30, 15);
      // flags = bit1|bit2|bit3 = 0x0E
      final data = [
        0x0E,
        ...u16(14100), // 70.5 kg
        ...dateTimeBytes(ts),
        3, // user id
        ...u16(231), // BMI 23.1
        ...u16(1750), // height 1.750 m
      ];

      final m = parseWeightMeasurement(data);

      expect(m.weightKg, closeTo(70.5, 1e-9));
      expect(m.timestamp, ts);
      expect(m.userId, 3);
      expect(m.bmi, closeTo(23.1, 1e-9));
      expect(m.heightMeters, closeTo(1.75, 1e-9));
    });

    test('imperial height uses 0.1 inch resolution', () {
      // flags = imperial | BMI+height = 0x09
      final data = [
        0x09,
        ...u16(16534), // 165.34 lb
        ...u16(231), // BMI 23.1
        ...u16(689), // 68.9 inch
      ];

      final m = parseWeightMeasurement(data);

      expect(m.heightMeters, closeTo(68.9 * 0.0254, 1e-9));
    });

    test('user id 255 maps to null (unknown user)', () {
      final m = parseWeightMeasurement([0x04, ...u16(15000), 0xFF]);
      expect(m.userId, isNull);
    });

    test('throws FormatException on empty payload', () {
      expect(() => parseWeightMeasurement([]), throwsFormatException);
    });

    test('throws FormatException when weight is truncated', () {
      expect(() => parseWeightMeasurement([0x00, 0x98]), throwsFormatException);
    });

    test('throws FormatException when flagged timestamp is missing', () {
      // flags claim a timestamp but the payload ends after the weight
      expect(() => parseWeightMeasurement([0x02, ...u16(15000), 0xEA]),
          throwsFormatException);
    });
  });

  group('parseBodyComposition (0x2A9C)', () {
    test('body fat only', () {
      // flags = 0x0000; body fat 285 * 0.1 = 28.5 %
      final m = parseBodyComposition([...u16(0x0000), ...u16(285)]);

      expect(m.bodyFatPercent, closeTo(28.5, 1e-9));
      expect(m.measurementUnsuccessful, isFalse);
      expect(m.isImperial, isFalse);
      expect(m.timestamp, isNull);
      expect(m.basalMetabolismKcal, isNull);
      expect(m.musclePercent, isNull);
      expect(m.muscleMassKg, isNull);
      expect(m.fatFreeMassKg, isNull);
      expect(m.softLeanMassKg, isNull);
      expect(m.bodyWaterMassKg, isNull);
      expect(m.impedanceOhms, isNull);
      expect(m.weightKg, isNull);
      expect(m.heightMeters, isNull);
      expect(m.isPartOfMultiplePacket, isFalse);
    });

    test('full SI packet: timestamp, BMR, muscle, water, impedance, weight',
        () {
      final ts = DateTime(2026, 7, 7, 8, 30, 15);
      // bits: 1 (timestamp) | 3 (BMR) | 4 (muscle %) | 5 (muscle mass)
      //     | 8 (water mass) | 9 (impedance) | 10 (weight) = 0x073A
      final data = [
        ...u16(0x073A),
        ...u16(250), // body fat 25.0 %
        ...dateTimeBytes(ts),
        ...u16(7000), // BMR 7000 kJ
        ...u16(405), // muscle 40.5 %
        ...u16(6100), // muscle mass 30.5 kg
        ...u16(8400), // water mass 42.0 kg
        ...u16(5023), // impedance 502.3 ohm
        ...u16(15000), // weight 75.0 kg
      ];

      final m = parseBodyComposition(data);

      expect(m.bodyFatPercent, closeTo(25.0, 1e-9));
      expect(m.timestamp, ts);
      // 7000 kJ / 4.184 = 1673.04... -> 1673 kcal
      expect(m.basalMetabolismKcal, 1673);
      expect(m.musclePercent, closeTo(40.5, 1e-9));
      expect(m.muscleMassKg, closeTo(30.5, 1e-9));
      expect(m.bodyWaterMassKg, closeTo(42.0, 1e-9));
      expect(m.impedanceOhms, closeTo(502.3, 1e-9));
      expect(m.weightKg, closeTo(75.0, 1e-9));
      expect(m.fatFreeMassKg, isNull);
      expect(m.softLeanMassKg, isNull);
      expect(m.isPartOfMultiplePacket, isFalse);
    });

    test('BMR kJ to kcal rounds correctly', () {
      // 6276 kJ / 4.184 = exactly 1500 kcal
      final m = parseBodyComposition(
          [...u16(0x0008), ...u16(250), ...u16(6276)]);
      expect(m.basalMetabolismKcal, 1500);

      // 6278 kJ / 4.184 = 1500.478... -> 1500
      final m2 = parseBodyComposition(
          [...u16(0x0008), ...u16(250), ...u16(6278)]);
      expect(m2.basalMetabolismKcal, 1500);

      // 6281 kJ / 4.184 = 1501.195... -> 1501
      final m3 = parseBodyComposition(
          [...u16(0x0008), ...u16(250), ...u16(6281)]);
      expect(m3.basalMetabolismKcal, 1501);
    });

    test('imperial masses are converted to kg', () {
      // bits: 0 (imperial) | 5 (muscle mass) | 10 (weight) = 0x0421
      final data = [
        ...u16(0x0421),
        ...u16(300), // body fat 30.0 %
        ...u16(6000), // muscle mass 60.00 lb
        ...u16(16534), // weight 165.34 lb
      ];

      final m = parseBodyComposition(data);

      expect(m.isImperial, isTrue);
      expect(m.muscleMassKg, closeTo(60.00 * 0.45359237, 1e-9));
      expect(m.weightKg, closeTo(165.34 * 0.45359237, 1e-9));
    });

    test('fat free mass, soft lean mass, height, user id, multi-packet', () {
      // bits: 2 (user id) | 6 (fat free) | 7 (soft lean) | 11 (height)
      //     | 12 (multi packet) = 0x18C4
      final data = [
        ...u16(0x18C4),
        ...u16(220), // body fat 22.0 %
        7, // user id
        ...u16(11000), // fat free mass 55.0 kg
        ...u16(10400), // soft lean mass 52.0 kg
        ...u16(1680), // height 1.680 m
      ];

      final m = parseBodyComposition(data);

      expect(m.userId, 7);
      expect(m.fatFreeMassKg, closeTo(55.0, 1e-9));
      expect(m.softLeanMassKg, closeTo(52.0, 1e-9));
      expect(m.heightMeters, closeTo(1.68, 1e-9));
      expect(m.isPartOfMultiplePacket, isTrue);
    });

    test('0xFFFF body fat means measurement unsuccessful', () {
      final m = parseBodyComposition([...u16(0x0000), 0xFF, 0xFF]);

      expect(m.bodyFatPercent, isNull);
      expect(m.measurementUnsuccessful, isTrue);
    });

    test('unsuccessful body fat can still carry a weight', () {
      final m = parseBodyComposition(
          [...u16(0x0400), 0xFF, 0xFF, ...u16(15000)]);

      expect(m.bodyFatPercent, isNull);
      expect(m.measurementUnsuccessful, isTrue);
      expect(m.weightKg, closeTo(75.0, 1e-9));
    });

    test('throws FormatException on empty payload', () {
      expect(() => parseBodyComposition([]), throwsFormatException);
    });

    test('throws FormatException when flags are truncated', () {
      expect(() => parseBodyComposition([0x3A]), throwsFormatException);
    });

    test('throws FormatException when mandatory body fat is missing', () {
      expect(
          () => parseBodyComposition([...u16(0x0000)]), throwsFormatException);
    });

    test('throws FormatException when a flagged field is truncated', () {
      // weight flagged (bit 10) but only one byte of it present
      expect(
          () => parseBodyComposition(
              [...u16(0x0400), ...u16(250), 0x98]),
          throwsFormatException);
    });
  });

  group('GATT date_time parsing', () {
    test('parses via 0x2A9D timestamp field', () {
      final ts = DateTime(1999, 12, 31, 23, 59, 59);
      final m = parseWeightMeasurement(
          [0x02, ...u16(15000), ...dateTimeBytes(ts)]);
      expect(m.timestamp, ts);
    });

    test('rejects out-of-range date_time fields', () {
      // month = 13 is invalid
      expect(
          () => parseWeightMeasurement(
              [0x02, ...u16(15000), ...u16(2026), 13, 1, 0, 0, 0]),
          throwsFormatException);
    });

    test('year 0 (unknown) clamps instead of throwing', () {
      final m = parseWeightMeasurement(
          [0x02, ...u16(15000), ...u16(0), 0, 0, 12, 0, 0]);
      expect(m.timestamp, DateTime(1970, 1, 1, 12, 0, 0));
    });
  });
}
