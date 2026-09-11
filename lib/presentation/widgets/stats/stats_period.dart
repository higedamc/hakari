import '../../../domain/entities/weight_entry.dart';

/// Time window the Stats tab summarises.
enum StatsPeriod {
  oneMonth('1M', Duration(days: 30)),
  threeMonths('3M', Duration(days: 91)),
  sixMonths('6M', Duration(days: 182)),
  oneYear('1Y', Duration(days: 365)),
  all('All', null);

  const StatsPeriod(this.label, this.span);

  /// Short label shown in the period selector.
  final String label;

  /// Length of the window, or `null` for the whole history.
  final Duration? span;

  /// Default window when the tab opens.
  static const StatsPeriod initial = StatsPeriod.threeMonths;

  /// Entries recorded inside the window ending at [now], newest first.
  /// Order of [entries] does not matter.
  List<WeightEntry> select(List<WeightEntry> entries, {DateTime? now}) {
    final cutoff = span == null
        ? null
        : (now ?? DateTime.now()).subtract(span!);
    final inWindow = [
      for (final e in entries)
        if (cutoff == null || !e.recordedAt.isBefore(cutoff)) e,
    ]..sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
    return inWindow;
  }
}

/// Weight figures for one window. Built from the entries [StatsPeriod.select]
/// returned; `null` when the window is empty.
class WeightSummary {
  const WeightSummary._({
    required this.current,
    required this.start,
    required this.averageKg,
    required this.minKg,
    required this.maxKg,
    required this.count,
  });

  /// Newest entry in the window.
  final WeightEntry current;

  /// Oldest entry in the window. Its weight is the `startKg` every
  /// goal-progress figure on the Stats tab is measured from, so the bar
  /// answers "how am I doing over this window". Switching the period
  /// therefore moves the start; on `All` it is the first entry ever.
  final WeightEntry start;

  final double averageKg;
  final double minKg;
  final double maxKg;
  final int count;

  /// `current - start`; zero when the window holds a single entry.
  double get changeKg => current.weightKg - start.weightKg;

  /// Goal progress is only meaningful with two distinct points in the
  /// window. With one entry `start == current`, which would render as a
  /// 0 % bar next to an absolute "x kg to go" figure that says otherwise.
  bool get canMeasureProgress => count >= 2;

  static WeightSummary? of(List<WeightEntry> inWindow) {
    if (inWindow.isEmpty) return null;
    final sorted = List<WeightEntry>.of(inWindow)
      ..sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
    var sum = 0.0;
    var min = double.infinity;
    var max = double.negativeInfinity;
    for (final e in sorted) {
      sum += e.weightKg;
      if (e.weightKg < min) min = e.weightKg;
      if (e.weightKg > max) max = e.weightKg;
    }
    return WeightSummary._(
      current: sorted.first,
      start: sorted.last,
      averageKg: sum / sorted.length,
      minKg: min,
      maxKg: max,
      count: sorted.length,
    );
  }
}

/// Body-composition metrics that get their own trend card. Every one is
/// nullable on [WeightEntry]; a card is shown only when the window holds
/// at least one value.
enum BodyMetric {
  bodyFat('Body fat', '%', 1),
  muscleMass('Muscle mass', 'kg', 1),
  visceralFat('Visceral fat', '', 0),
  basalMetabolicRate('Basal metabolic rate', 'kcal', 0),
  metabolicAge('Metabolic age', 'yrs', 0);

  const BodyMetric(this.label, this.unit, this.decimals);

  final String label;
  final String unit;
  final int decimals;

  double? valueOf(WeightEntry e) => switch (this) {
    BodyMetric.bodyFat => e.bodyFatPercent,
    BodyMetric.muscleMass => e.muscleMassKg,
    BodyMetric.visceralFat => e.visceralFatRating?.toDouble(),
    BodyMetric.basalMetabolicRate => e.basalMetabolicRateKcal?.toDouble(),
    BodyMetric.metabolicAge => e.metabolicAge?.toDouble(),
  };

  /// Entries in the window that carry this metric, newest first.
  List<WeightEntry> entriesWithValue(List<WeightEntry> inWindow) => [
    for (final e in inWindow)
      if (valueOf(e) != null) e,
  ];

  String format(double value) => unit.isEmpty
      ? value.toStringAsFixed(decimals)
      : '${value.toStringAsFixed(decimals)} $unit';
}
