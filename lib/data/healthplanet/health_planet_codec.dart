import 'dart:convert';

import '../../domain/entities/weight_entry.dart';
import '../../domain/failures/failures.dart';
import '../../domain/services/body_metrics.dart';

/// Everything a single innerscan response yields: the measurements plus
/// the profile height the API returns next to them.
class InnerscanPayload {
  const InnerscanPayload({required this.entries, required this.heightCm});

  /// Measurements, newest first.
  final List<WeightEntry> entries;

  /// Top-level `height` (cm) when present and plausible, else `null`.
  final double? heightCm;
}

/// Pure parsing/mapping for the Health Planet innerscan API.
/// Kept free of I/O so it is unit-testable.
///
/// Innerscan tags (https://www.healthplanet.jp/apis/api.html):
///   6021 weight kg, 6022 body fat %, 6023 muscle mass kg,
///   6024 muscle score, 6025 visceral fat level 2,
///   6026 visceral fat level, 6027 basal metabolism kcal,
///   6028 body age, 6029 estimated bone mass kg.
class HealthPlanetCodec {
  HealthPlanetCodec._();

  static const String tagWeight = '6021';
  static const String tagBodyFat = '6022';
  static const String tagMuscleMass = '6023';
  static const String tagMuscleScore = '6024';
  static const String tagVisceralFatLevel2 = '6025';
  static const String tagVisceralFat = '6026';
  static const String tagBasalMetabolism = '6027';
  static const String tagBodyAge = '6028';
  static const String tagBoneMass = '6029';

  /// Tags requested from the API (everything WeightEntry can hold).
  static const String requestTags =
      '$tagWeight,$tagBodyFat,$tagMuscleMass,$tagMuscleScore,'
      '$tagVisceralFatLevel2,$tagVisceralFat,'
      '$tagBasalMetabolism,$tagBodyAge,$tagBoneMass';

  /// Parses an oauth/token response, returning (accessToken, refreshToken).
  static (String, String?) parseTokenResponse(String body) {
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } catch (e) {
      throw HealthPlanetFailure('Health Planet returned malformed JSON', e);
    }
    if (decoded is! Map<String, dynamic>) {
      throw const HealthPlanetFailure(
        'Health Planet returned an unexpected token response',
      );
    }
    final error = decoded['error'];
    if (error != null) {
      throw HealthPlanetFailure('Health Planet rejected the request: $error');
    }
    final access = decoded['access_token'];
    if (access is! String || access.isEmpty) {
      throw const HealthPlanetFailure(
        'Health Planet response contained no access token',
      );
    }
    final refresh = decoded['refresh_token'];
    return (access, refresh is String && refresh.isNotEmpty ? refresh : null);
  }

  /// Parses an innerscan.json response into entries, one per measurement
  /// timestamp. Groups the flat tag/keydata rows by their `date` value.
  /// Rows with unparseable values are skipped rather than failing the
  /// whole sync (the response is remote input — treat it as hostile).
  static List<WeightEntry> parseInnerscan(
    String body, {
    required String Function() generateId,
  }) => parseInnerscanPayload(body, generateId: generateId).entries;

  /// Like [parseInnerscan] but also returns the profile `height` the API
  /// sends at the top level next to `birth_date` and `sex`. A missing or
  /// implausible height never fails the entry parse.
  static InnerscanPayload parseInnerscanPayload(
    String body, {
    required String Function() generateId,
  }) {
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } catch (e) {
      throw HealthPlanetFailure('Health Planet returned malformed JSON', e);
    }
    if (decoded is! Map<String, dynamic>) {
      throw const HealthPlanetFailure(
        'Health Planet returned an unexpected innerscan response',
      );
    }
    final heightCm = parseHeightCm(decoded['height']);
    final data = decoded['data'];
    if (data is! List) {
      return InnerscanPayload(entries: const [], heightCm: heightCm);
    }

    // date string (yyyyMMddHHmm) -> tag -> value
    final grouped = <String, Map<String, double>>{};
    for (final row in data) {
      if (row is! Map) continue;
      final date = row['date'];
      final tag = row['tag'];
      final keydata = row['keydata'];
      if (date is! String || tag is! String || keydata is! String) continue;
      final value = double.tryParse(keydata);
      if (value == null || !value.isFinite) continue;
      (grouped[date] ??= {})[tag] = value;
    }

    final entries = <WeightEntry>[];
    for (final entry in grouped.entries) {
      final recordedAt = _parseDate(entry.key);
      if (recordedAt == null) continue;
      final tags = entry.value;
      final weight = tags[tagWeight];
      // A measurement without weight cannot become a WeightEntry.
      if (weight == null || weight <= 0 || weight > 500) continue;
      entries.add(
        WeightEntry(
          id: generateId(),
          recordedAt: recordedAt,
          weightKg: weight,
          bodyFatPercent: tags[tagBodyFat],
          muscleMassKg: tags[tagMuscleMass],
          muscleScore: tags[tagMuscleScore]?.round(),
          visceralFatRating: tags[tagVisceralFat]?.round(),
          visceralFatLevel2: tags[tagVisceralFatLevel2],
          basalMetabolicRateKcal: tags[tagBasalMetabolism]?.round(),
          metabolicAge: tags[tagBodyAge]?.round(),
          boneMassKg: tags[tagBoneMass],
          source: MeasurementSource.imported,
        ),
      );
    }
    entries.sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
    return InnerscanPayload(entries: entries, heightCm: heightCm);
  }

  /// Top-level `height` field → centimetres, or `null`.
  ///
  /// The API documents it as a string (`"177.5"`) but the value is remote
  /// input, so a number is accepted too and anything non-finite or outside
  /// [BodyProfileLimits] is dropped rather than thrown.
  static double? parseHeightCm(Object? raw) {
    final double? value = switch (raw) {
      final num n => n.toDouble(),
      final String s => double.tryParse(s.trim()),
      _ => null,
    };
    return BodyProfileLimits.isPlausibleHeightCm(value) ? value : null;
  }

  /// Health Planet timestamps are local `yyyyMMddHHmm`.
  static DateTime? _parseDate(String raw) {
    if (raw.length != 12) return null;
    final year = int.tryParse(raw.substring(0, 4));
    final month = int.tryParse(raw.substring(4, 6));
    final day = int.tryParse(raw.substring(6, 8));
    final hour = int.tryParse(raw.substring(8, 10));
    final minute = int.tryParse(raw.substring(10, 12));
    if (year == null ||
        month == null ||
        day == null ||
        hour == null ||
        minute == null) {
      return null;
    }
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    if (hour > 23 || minute > 59) return null;
    return DateTime(year, month, day, hour, minute);
  }

  /// `yyyyMMddHHmmss` request-parameter form.
  static String formatRequestDate(DateTime value) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${value.year.toString().padLeft(4, '0')}${two(value.month)}'
        '${two(value.day)}${two(value.hour)}${two(value.minute)}'
        '${two(value.second)}';
  }
}
