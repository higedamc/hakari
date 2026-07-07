/// Core measurement entity. Mirrors the field set TANITA scales emit
/// (weight + body composition) as used by WeightLogger's SQLite schema.
class WeightEntry {
  final String id;
  final DateTime recordedAt;
  final double weightKg;
  final double? bodyFatPercent;
  final double? bodyWaterPercent;
  final double? muscleMassKg;
  final int? visceralFatRating;
  final double? boneMassKg;
  final int? basalMetabolicRateKcal;
  final int? metabolicAge;
  final MeasurementSource source;

  /// Nostr event id (hex) once published; null = not yet synced.
  final String? nostrEventId;

  /// Whether this entry was written to Health Connect / HealthKit.
  final bool syncedToHealth;

  const WeightEntry({
    required this.id,
    required this.recordedAt,
    required this.weightKg,
    this.bodyFatPercent,
    this.bodyWaterPercent,
    this.muscleMassKg,
    this.visceralFatRating,
    this.boneMassKg,
    this.basalMetabolicRateKcal,
    this.metabolicAge,
    this.source = MeasurementSource.manual,
    this.nostrEventId,
    this.syncedToHealth = false,
  });

  WeightEntry copyWith({
    DateTime? recordedAt,
    double? weightKg,
    double? bodyFatPercent,
    double? bodyWaterPercent,
    double? muscleMassKg,
    int? visceralFatRating,
    double? boneMassKg,
    int? basalMetabolicRateKcal,
    int? metabolicAge,
    MeasurementSource? source,
    String? nostrEventId,
    bool? syncedToHealth,
  }) {
    return WeightEntry(
      id: id,
      recordedAt: recordedAt ?? this.recordedAt,
      weightKg: weightKg ?? this.weightKg,
      bodyFatPercent: bodyFatPercent ?? this.bodyFatPercent,
      bodyWaterPercent: bodyWaterPercent ?? this.bodyWaterPercent,
      muscleMassKg: muscleMassKg ?? this.muscleMassKg,
      visceralFatRating: visceralFatRating ?? this.visceralFatRating,
      boneMassKg: boneMassKg ?? this.boneMassKg,
      basalMetabolicRateKcal:
          basalMetabolicRateKcal ?? this.basalMetabolicRateKcal,
      metabolicAge: metabolicAge ?? this.metabolicAge,
      source: source ?? this.source,
      nostrEventId: nostrEventId ?? this.nostrEventId,
      syncedToHealth: syncedToHealth ?? this.syncedToHealth,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'recordedAt': recordedAt.millisecondsSinceEpoch,
    'weightKg': weightKg,
    'bodyFatPercent': bodyFatPercent,
    'bodyWaterPercent': bodyWaterPercent,
    'muscleMassKg': muscleMassKg,
    'visceralFatRating': visceralFatRating,
    'boneMassKg': boneMassKg,
    'basalMetabolicRateKcal': basalMetabolicRateKcal,
    'metabolicAge': metabolicAge,
    'source': source.name,
    'nostrEventId': nostrEventId,
    'syncedToHealth': syncedToHealth,
  };

  factory WeightEntry.fromMap(Map<dynamic, dynamic> map) => WeightEntry(
    id: map['id'] as String,
    recordedAt: DateTime.fromMillisecondsSinceEpoch(map['recordedAt'] as int),
    weightKg: (map['weightKg'] as num).toDouble(),
    bodyFatPercent: (map['bodyFatPercent'] as num?)?.toDouble(),
    bodyWaterPercent: (map['bodyWaterPercent'] as num?)?.toDouble(),
    muscleMassKg: (map['muscleMassKg'] as num?)?.toDouble(),
    visceralFatRating: map['visceralFatRating'] as int?,
    boneMassKg: (map['boneMassKg'] as num?)?.toDouble(),
    basalMetabolicRateKcal: map['basalMetabolicRateKcal'] as int?,
    metabolicAge: map['metabolicAge'] as int?,
    source: MeasurementSource.values.firstWhere(
      (s) => s.name == map['source'],
      orElse: () => MeasurementSource.manual,
    ),
    nostrEventId: map['nostrEventId'] as String?,
    syncedToHealth: (map['syncedToHealth'] as bool?) ?? false,
  );
}

enum MeasurementSource { manual, bleScale, healthSync, imported }
