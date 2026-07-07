import 'package:flutter_test/flutter_test.dart';
import 'package:hakari/domain/entities/weight_entry.dart';

void main() {
  test('WeightEntry map round-trip preserves all fields', () {
    final entry = WeightEntry(
      id: 'abc',
      recordedAt: DateTime.fromMillisecondsSinceEpoch(1751846400000),
      weightKg: 72.5,
      bodyFatPercent: 18.2,
      bodyWaterPercent: 55.1,
      muscleMassKg: 30.4,
      visceralFatRating: 7,
      boneMassKg: 2.9,
      basalMetabolicRateKcal: 1650,
      metabolicAge: 32,
      source: MeasurementSource.bleScale,
      nostrEventId: 'deadbeef',
      syncedToHealth: true,
    );

    final restored = WeightEntry.fromMap(entry.toMap());

    expect(restored.toMap(), entry.toMap());
    expect(restored.source, MeasurementSource.bleScale);
  });
}
