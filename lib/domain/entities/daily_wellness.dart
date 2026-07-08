/// One calendar day of recovery-relevant health data read from
/// Health Connect / HealthKit.
class DailyWellness {
  /// Calendar date (time component zeroed, local).
  final DateTime day;

  /// Main sleep ending on the morning of [day], in hours. Null = no data.
  final double? sleepHours;

  /// Active energy burned during [day], kcal. Null = no data.
  final double? activeEnergyKcal;

  const DailyWellness({
    required this.day,
    this.sleepHours,
    this.activeEnergyKcal,
  });
}
