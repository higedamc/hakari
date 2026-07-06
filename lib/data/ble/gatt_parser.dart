/// Pure-Dart parsers for the Bluetooth SIG GATT scale characteristics:
///
/// * Weight Measurement (0x2A9D, Weight Scale Service 0x181D)
/// * Body Composition Measurement (0x2A9C, Body Composition Service 0x181B)
///
/// All multi-byte fields are little-endian. Malformed / truncated payloads
/// throw [FormatException]; callers are expected to wrap or skip.
library;

/// Exact conversion factor defined by the Bluetooth SIG (and NIST).
const double poundsToKilograms = 0.45359237;

/// Exact conversion factor: 1 inch = 0.0254 m.
const double inchesToMeters = 0.0254;

/// Thermochemical calorie: 1 kcal = 4.184 kJ.
const double kilojoulesPerKilocalorie = 4.184;

/// Sentinel for the mandatory Body Fat Percentage field of 0x2A9C meaning
/// "measurement unsuccessful".
const int bodyFatUnsuccessful = 0xFFFF;

/// Parsed Weight Measurement (characteristic 0x2A9D).
class WeightMeasurement {
  /// Weight converted to kilograms (imperial payloads are converted).
  final double weightKg;

  /// True when the scale reported imperial units (lb / inch).
  final bool isImperial;

  /// Measurement timestamp, when the scale included one.
  final DateTime? timestamp;

  /// User index (null when absent or 255 = "unknown user").
  final int? userId;

  /// Body Mass Index (kg/m^2), when present.
  final double? bmi;

  /// Height in meters (imperial payloads are converted), when present.
  final double? heightMeters;

  const WeightMeasurement({
    required this.weightKg,
    required this.isImperial,
    this.timestamp,
    this.userId,
    this.bmi,
    this.heightMeters,
  });
}

/// Parsed Body Composition Measurement (characteristic 0x2A9C).
class BodyCompositionMeasurement {
  /// True when the scale reported imperial units (lb / inch).
  final bool isImperial;

  /// Mandatory field. Null when the scale sent 0xFFFF
  /// ("measurement unsuccessful") — see [measurementUnsuccessful].
  final double? bodyFatPercent;

  /// True when the mandatory body-fat field was 0xFFFF.
  final bool measurementUnsuccessful;

  final DateTime? timestamp;

  /// User index (null when absent or 255 = "unknown user").
  final int? userId;

  /// Basal metabolism converted from kilojoules to kilocalories (rounded).
  final int? basalMetabolismKcal;

  /// Muscle percentage (%).
  final double? musclePercent;

  /// Muscle mass in kilograms (imperial payloads are converted).
  final double? muscleMassKg;

  /// Fat-free mass in kilograms.
  final double? fatFreeMassKg;

  /// Soft lean mass in kilograms.
  final double? softLeanMassKg;

  /// Body water *mass* in kilograms (not a percentage — divide by total
  /// weight to obtain a body-water percentage).
  final double? bodyWaterMassKg;

  /// Impedance in ohms.
  final double? impedanceOhms;

  /// Weight in kilograms, when the scale included it in this packet.
  final double? weightKg;

  /// Height in meters, when present.
  final double? heightMeters;

  /// True when this measurement is split across multiple packets.
  final bool isPartOfMultiplePacket;

  const BodyCompositionMeasurement({
    required this.isImperial,
    this.bodyFatPercent,
    this.measurementUnsuccessful = false,
    this.timestamp,
    this.userId,
    this.basalMetabolismKcal,
    this.musclePercent,
    this.muscleMassKg,
    this.fatFreeMassKg,
    this.softLeanMassKg,
    this.bodyWaterMassKg,
    this.impedanceOhms,
    this.weightKg,
    this.heightMeters,
    this.isPartOfMultiplePacket = false,
  });
}

/// Parses a Weight Measurement (0x2A9D) payload.
///
/// Flags (uint8):
/// * bit 0 — units: 0 = SI (kg / m), 1 = imperial (lb / inch)
/// * bit 1 — timestamp present (7-byte date_time)
/// * bit 2 — user id present (uint8, 255 = unknown)
/// * bit 3 — BMI (uint16 x0.1) and height (uint16 x0.001 m / x0.1 inch)
///
/// Weight: uint16, x0.005 kg (SI) or x0.01 lb (imperial).
WeightMeasurement parseWeightMeasurement(List<int> data) {
  final reader = _ByteReader(data, characteristic: '0x2A9D');
  final flags = reader.readUint8();
  final isImperial = flags & 0x01 != 0;

  final rawWeight = reader.readUint16();
  final weightKg = isImperial
      ? rawWeight * 0.01 * poundsToKilograms
      : rawWeight * 0.005;

  DateTime? timestamp;
  if (flags & 0x02 != 0) {
    timestamp = reader.readDateTime();
  }

  int? userId;
  if (flags & 0x04 != 0) {
    final raw = reader.readUint8();
    userId = raw == 0xFF ? null : raw;
  }

  double? bmi;
  double? heightMeters;
  if (flags & 0x08 != 0) {
    bmi = reader.readUint16() * 0.1;
    final rawHeight = reader.readUint16();
    heightMeters =
        isImperial ? rawHeight * 0.1 * inchesToMeters : rawHeight * 0.001;
  }

  return WeightMeasurement(
    weightKg: weightKg,
    isImperial: isImperial,
    timestamp: timestamp,
    userId: userId,
    bmi: bmi,
    heightMeters: heightMeters,
  );
}

/// Parses a Body Composition Measurement (0x2A9C) payload.
///
/// Flags (uint16, little-endian):
/// * bit 0 — units: 0 = SI, 1 = imperial
/// * bit 1 — timestamp present
/// * bit 2 — user id present
/// * bit 3 — basal metabolism present (uint16, kilojoule)
/// * bit 4 — muscle percentage present (uint16 x0.1 %)
/// * bit 5 — muscle mass present (uint16 x0.005 kg / x0.01 lb)
/// * bit 6 — fat free mass present (same resolution)
/// * bit 7 — soft lean mass present (same resolution)
/// * bit 8 — body water mass present (same resolution; a mass, not a %)
/// * bit 9 — impedance present (uint16 x0.1 ohm)
/// * bit 10 — weight present (uint16 x0.005 kg / x0.01 lb)
/// * bit 11 — height present (uint16 x0.001 m / x0.1 inch)
/// * bit 12 — multiple packet measurement
///
/// The mandatory Body Fat Percentage (uint16 x0.1 %) directly follows the
/// flags; 0xFFFF means the measurement was unsuccessful.
BodyCompositionMeasurement parseBodyComposition(List<int> data) {
  final reader = _ByteReader(data, characteristic: '0x2A9C');
  final flags = reader.readUint16();
  final isImperial = flags & 0x0001 != 0;

  final rawBodyFat = reader.readUint16();
  final unsuccessful = rawBodyFat == bodyFatUnsuccessful;
  final bodyFatPercent = unsuccessful ? null : rawBodyFat * 0.1;

  DateTime? timestamp;
  if (flags & 0x0002 != 0) {
    timestamp = reader.readDateTime();
  }

  int? userId;
  if (flags & 0x0004 != 0) {
    final raw = reader.readUint8();
    userId = raw == 0xFF ? null : raw;
  }

  int? basalMetabolismKcal;
  if (flags & 0x0008 != 0) {
    final kilojoules = reader.readUint16();
    basalMetabolismKcal = (kilojoules / kilojoulesPerKilocalorie).round();
  }

  double? musclePercent;
  if (flags & 0x0010 != 0) {
    musclePercent = reader.readUint16() * 0.1;
  }

  double? muscleMassKg;
  if (flags & 0x0020 != 0) {
    muscleMassKg = _massToKg(reader.readUint16(), isImperial);
  }

  double? fatFreeMassKg;
  if (flags & 0x0040 != 0) {
    fatFreeMassKg = _massToKg(reader.readUint16(), isImperial);
  }

  double? softLeanMassKg;
  if (flags & 0x0080 != 0) {
    softLeanMassKg = _massToKg(reader.readUint16(), isImperial);
  }

  double? bodyWaterMassKg;
  if (flags & 0x0100 != 0) {
    bodyWaterMassKg = _massToKg(reader.readUint16(), isImperial);
  }

  double? impedanceOhms;
  if (flags & 0x0200 != 0) {
    impedanceOhms = reader.readUint16() * 0.1;
  }

  double? weightKg;
  if (flags & 0x0400 != 0) {
    weightKg = _massToKg(reader.readUint16(), isImperial);
  }

  double? heightMeters;
  if (flags & 0x0800 != 0) {
    final rawHeight = reader.readUint16();
    heightMeters =
        isImperial ? rawHeight * 0.1 * inchesToMeters : rawHeight * 0.001;
  }

  return BodyCompositionMeasurement(
    isImperial: isImperial,
    bodyFatPercent: bodyFatPercent,
    measurementUnsuccessful: unsuccessful,
    timestamp: timestamp,
    userId: userId,
    basalMetabolismKcal: basalMetabolismKcal,
    musclePercent: musclePercent,
    muscleMassKg: muscleMassKg,
    fatFreeMassKg: fatFreeMassKg,
    softLeanMassKg: softLeanMassKg,
    bodyWaterMassKg: bodyWaterMassKg,
    impedanceOhms: impedanceOhms,
    weightKg: weightKg,
    heightMeters: heightMeters,
    isPartOfMultiplePacket: flags & 0x1000 != 0,
  );
}

/// Mass field: uint16, x0.005 kg (SI) or x0.01 lb (imperial), converted
/// to kilograms.
double _massToKg(int raw, bool isImperial) =>
    isImperial ? raw * 0.01 * poundsToKilograms : raw * 0.005;

/// Sequential little-endian reader with bounds checks.
class _ByteReader {
  final List<int> data;
  final String characteristic;
  int _offset = 0;

  _ByteReader(this.data, {required this.characteristic});

  int readUint8() {
    if (_offset + 1 > data.length) {
      throw FormatException(
          'Truncated $characteristic payload: needed 1 byte at offset '
          '$_offset, total length ${data.length}');
    }
    return data[_offset++] & 0xFF;
  }

  int readUint16() {
    if (_offset + 2 > data.length) {
      throw FormatException(
          'Truncated $characteristic payload: needed 2 bytes at offset '
          '$_offset, total length ${data.length}');
    }
    final value = (data[_offset] & 0xFF) | ((data[_offset + 1] & 0xFF) << 8);
    _offset += 2;
    return value;
  }

  /// GATT date_time: year uint16 LE, month, day, hours, minutes, seconds.
  DateTime readDateTime() {
    final year = readUint16();
    final month = readUint8();
    final day = readUint8();
    final hours = readUint8();
    final minutes = readUint8();
    final seconds = readUint8();
    if (month > 12 || day > 31 || hours > 23 || minutes > 59 || seconds > 59) {
      throw FormatException(
          'Invalid $characteristic date_time: '
          '$year-$month-$day $hours:$minutes:$seconds');
    }
    // Per the spec, 0 means "unknown" for year/month/day; clamp to a valid
    // DateTime rather than failing the whole measurement.
    return DateTime(
      year == 0 ? 1970 : year,
      month == 0 ? 1 : month,
      day == 0 ? 1 : day,
      hours,
      minutes,
      seconds,
    );
  }
}
