/// One calendar day of recovery-relevant health data read from
/// Health Connect / HealthKit.
class DailyWellness {
  /// Calendar date (time component zeroed, local).
  final DateTime day;

  /// Main sleep ending on the morning of [day], in hours. Null = no data.
  final double? sleepHours;

  /// Active energy burned during [day], kcal. Null = no data.
  final double? activeEnergyKcal;

  /// Nostr event id (hex) of this day's encrypted backup; null = not
  /// yet backed up (or changed since — publishing resets it).
  final String? nostrEventId;

  const DailyWellness({
    required this.day,
    this.sleepHours,
    this.activeEnergyKcal,
    this.nostrEventId,
  });

  DailyWellness copyWith({
    double? sleepHours,
    double? activeEnergyKcal,
    String? nostrEventId,
  }) {
    return DailyWellness(
      day: day,
      sleepHours: sleepHours ?? this.sleepHours,
      activeEnergyKcal: activeEnergyKcal ?? this.activeEnergyKcal,
      nostrEventId: nostrEventId ?? this.nostrEventId,
    );
  }

  /// Hive box key: `yyyy-MM-dd`.
  String get dayKey =>
      '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';

  Map<String, dynamic> toMap() => {
    'day': dayKey,
    'sleepHours': sleepHours,
    'activeEnergyKcal': activeEnergyKcal,
    'nostrEventId': nostrEventId,
  };

  factory DailyWellness.fromMap(Map<dynamic, dynamic> map) {
    final raw = map['day'] as String;
    return DailyWellness(
      day: DateTime(
        int.parse(raw.substring(0, 4)),
        int.parse(raw.substring(5, 7)),
        int.parse(raw.substring(8, 10)),
      ),
      sleepHours: (map['sleepHours'] as num?)?.toDouble(),
      activeEnergyKcal: (map['activeEnergyKcal'] as num?)?.toDouble(),
      nostrEventId: map['nostrEventId'] as String?,
    );
  }
}
