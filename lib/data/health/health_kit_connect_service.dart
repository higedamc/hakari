import 'dart:io';

import 'package:health/health.dart';
import 'package:uuid/uuid.dart';

import '../../domain/entities/weight_entry.dart';
import '../../domain/failures/failures.dart';
import '../../domain/services/health_service.dart';

/// Lightweight, plugin-independent snapshot of a single numeric health
/// sample. Used so the merge logic below stays pure and unit-testable.
class HealthSample {
  final String uuid;
  final DateTime timestamp;
  final double value;

  const HealthSample({
    required this.uuid,
    required this.timestamp,
    required this.value,
  });
}

/// [HealthService] backed by the `health` plugin — Google Health Connect
/// on Android, Apple HealthKit on iOS.
class HealthKitConnectService implements HealthService {
  HealthKitConnectService({Health? health, Uuid? uuid})
      : _health = health ?? Health(),
        _uuid = uuid ?? const Uuid();

  final Health _health;
  final Uuid _uuid;
  bool _configured = false;

  /// How far apart a weight and a body-fat sample may be recorded and
  /// still be considered one measurement.
  static const Duration defaultMatchWindow = Duration(seconds: 60);

  static const List<HealthDataType> _types = [
    HealthDataType.WEIGHT,
    HealthDataType.BODY_FAT_PERCENTAGE,
  ];

  static const List<HealthDataAccess> _permissions = [
    HealthDataAccess.READ_WRITE,
    HealthDataAccess.READ_WRITE,
  ];

  bool get _isSupportedPlatform => Platform.isAndroid || Platform.isIOS;

  /// `Health.configure()` must run once before any other plugin call.
  Future<void> _ensureConfigured() async {
    if (_configured) return;
    await _health.configure();
    _configured = true;
  }

  @override
  Future<bool> isAvailable() async {
    try {
      if (!_isSupportedPlatform) return false;
      if (Platform.isIOS) return true;
      // Android: Health Connect SDK must be present and up to date.
      await _ensureConfigured();
      final status = await _health.getHealthConnectSdkStatus();
      return status == HealthConnectSdkStatus.sdkAvailable;
    } catch (_) {
      // Contract: isAvailable never throws.
      return false;
    }
  }

  @override
  Future<bool> requestPermissions() async {
    try {
      if (!_isSupportedPlatform) {
        throw const HealthFailure(
            'Health store is not supported on this platform');
      }
      await _ensureConfigured();
      // requestAuthorization may block when permissions are already
      // granted, so check first (may return null on iOS for READ).
      final has =
          await _health.hasPermissions(_types, permissions: _permissions);
      if (has == true) return true;
      return await _health.requestAuthorization(_types,
          permissions: _permissions);
    } on HealthFailure {
      rethrow;
    } catch (e) {
      throw HealthPermissionFailure(
          'Failed to request health permissions', e);
    }
  }

  @override
  Future<void> writeEntry(WeightEntry entry) async {
    try {
      await _ensureConfigured();
      final wroteWeight = await _health.writeHealthData(
        value: entry.weightKg,
        type: HealthDataType.WEIGHT,
        unit: HealthDataUnit.KILOGRAM,
        startTime: entry.recordedAt,
        endTime: entry.recordedAt,
        recordingMethod: RecordingMethod.manual,
      );
      if (!wroteWeight) {
        throw const HealthPermissionFailure(
            'Health store rejected the weight write '
            '(permission not granted?)');
      }
      final bodyFat = entry.bodyFatPercent;
      if (bodyFat != null) {
        final wroteFat = await _health.writeHealthData(
          value: bodyFatToPlatformValue(bodyFat, isIOS: Platform.isIOS),
          type: HealthDataType.BODY_FAT_PERCENTAGE,
          unit: HealthDataUnit.PERCENT,
          startTime: entry.recordedAt,
          endTime: entry.recordedAt,
          recordingMethod: RecordingMethod.manual,
        );
        if (!wroteFat) {
          throw const HealthPermissionFailure(
              'Health store rejected the body fat write '
              '(permission not granted?)');
        }
      }
    } on HealthFailure {
      rethrow;
    } catch (e) {
      throw HealthFailure('Failed to write entry to health store', e);
    }
  }

  @override
  Future<List<WeightEntry>> readEntries(DateTime from, DateTime to) async {
    try {
      await _ensureConfigured();
      final points = await _health.getHealthDataFromTypes(
        types: _types,
        startTime: from,
        endTime: to,
      );

      final isIOS = Platform.isIOS;
      final weightSamples = <HealthSample>[];
      final bodyFatSamples = <HealthSample>[];
      for (final point in points) {
        final value = point.value;
        if (value is! NumericHealthValue) continue;
        final sample = HealthSample(
          uuid: point.uuid,
          timestamp: point.dateFrom,
          value: point.type == HealthDataType.BODY_FAT_PERCENTAGE
              ? bodyFatFromPlatformValue(value.numericValue, isIOS: isIOS)
              : value.numericValue.toDouble(),
        );
        switch (point.type) {
          case HealthDataType.WEIGHT:
            weightSamples.add(sample);
          case HealthDataType.BODY_FAT_PERCENTAGE:
            bodyFatSamples.add(sample);
          default:
            break;
        }
      }

      return mergeSamples(
        weightSamples: weightSamples,
        bodyFatSamples: bodyFatSamples,
        generateId: _uuid.v4,
      );
    } on HealthFailure {
      rethrow;
    } catch (e) {
      throw HealthFailure('Failed to read entries from health store', e);
    }
  }

  // ---------------------------------------------------------------------
  // Pure mapping logic (unit-tested in
  // test/data/health_service_mapping_test.dart).
  // ---------------------------------------------------------------------

  /// Converts a human body fat percentage (e.g. `23.5`) to the value the
  /// `health` plugin expects: HealthKit's `HKUnit.percent()` is a 0–1
  /// fraction, Health Connect's `Percentage` is 0–100.
  static double bodyFatToPlatformValue(double percent,
          {required bool isIOS}) =>
      isIOS ? percent / 100.0 : percent;

  /// Inverse of [bodyFatToPlatformValue]: normalizes a raw plugin value
  /// back to a 0–100 percentage.
  static double bodyFatFromPlatformValue(num raw, {required bool isIOS}) =>
      isIOS ? raw.toDouble() * 100.0 : raw.toDouble();

  /// Merges weight samples with body-fat samples recorded at (nearly) the
  /// same instant into [WeightEntry]s.
  ///
  /// For each weight sample the closest body-fat sample within
  /// [matchWindow] (default ±60 s) is attached; each body-fat sample is
  /// consumed at most once. Body-fat samples with no matching weight are
  /// dropped (an entry cannot exist without a weight).
  ///
  /// Entry ids use the weight data point's platform uuid when present,
  /// falling back to [generateId]. Results are sorted by [WeightEntry]
  /// timestamp ascending.
  static List<WeightEntry> mergeSamples({
    required List<HealthSample> weightSamples,
    required List<HealthSample> bodyFatSamples,
    required String Function() generateId,
    Duration matchWindow = defaultMatchWindow,
  }) {
    final sortedWeights = List<HealthSample>.of(weightSamples)
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final remainingFat = List<HealthSample>.of(bodyFatSamples);

    final entries = <WeightEntry>[];
    for (final weight in sortedWeights) {
      HealthSample? bestFat;
      Duration bestDistance = matchWindow;
      for (final fat in remainingFat) {
        final distance = (fat.timestamp.difference(weight.timestamp)).abs();
        if (distance <= bestDistance) {
          bestFat = fat;
          bestDistance = distance;
        }
      }
      if (bestFat != null) remainingFat.remove(bestFat);

      entries.add(WeightEntry(
        id: weight.uuid.isNotEmpty ? weight.uuid : generateId(),
        recordedAt: weight.timestamp,
        weightKg: weight.value,
        bodyFatPercent: bestFat?.value,
        source: MeasurementSource.healthSync,
        syncedToHealth: true,
      ));
    }
    return entries;
  }
}
