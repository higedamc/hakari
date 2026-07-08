import '../entities/daily_wellness.dart';

/// Result of the workout-readiness / diet-efficiency heuristic.
class ReadinessResult {
  /// 0–100: how good a day today is for training.
  final int readinessPercent;

  /// Estimated share of weight loss that comes from fat (vs lean mass)
  /// at the current sleep pattern, in percent. See [computeReadiness].
  final int dietEfficiencyPercent;

  final String headline;

  /// Human-readable factors behind the numbers, most important first.
  final List<String> reasons;

  const ReadinessResult({
    required this.readinessPercent,
    required this.dietEfficiencyPercent,
    required this.headline,
    required this.reasons,
  });
}

/// Heuristic readiness score from recent sleep + active energy.
///
/// The numbers are transparent estimates, not medical advice. The diet
/// efficiency mapping follows Nedeltcheva et al. 2010 (Ann Intern Med):
/// under identical caloric deficits, 8.5 h sleepers lost ~55 % of weight
/// as fat vs ~25 % for 5.5 h sleepers. Readiness additionally penalizes
/// acute short sleep and unusually heavy activity the previous day
/// (recovery), a pattern used by consumer training-readiness features.
///
/// Returns null when there is no sleep data at all (nothing meaningful
/// to score).
ReadinessResult? computeReadiness(List<DailyWellness> history) {
  if (history.isEmpty) return null;
  final byDay = List<DailyWellness>.of(history)
    ..sort((a, b) => b.day.compareTo(a.day));

  final today = byDay.first;
  final lastNight = today.sleepHours;
  final sleepSamples = byDay
      .map((d) => d.sleepHours)
      .whereType<double>()
      .toList();
  if (sleepSamples.isEmpty) return null;

  final avgSleep = sleepSamples.reduce((a, b) => a + b) / sleepSamples.length;
  final reasons = <String>[];

  // --- readiness ---------------------------------------------------
  final acuteSleep = lastNight ?? avgSleep;
  var readiness = 100.0 * _sleepFactor(acuteSleep);
  reasons.add(
    lastNight != null
        ? 'Slept ${_fmtHours(lastNight)} last night'
        : 'No sleep record for last night '
              '(using ${_fmtHours(avgSleep)} average)',
  );

  if (sleepSamples.length >= 3 && avgSleep < 6.5) {
    readiness -= 10;
    reasons.add(
      'Sleep debt: ${_fmtHours(avgSleep)} average over '
      '${sleepSamples.length} nights',
    );
  }

  final yesterday = byDay.length > 1 ? byDay[1].activeEnergyKcal : null;
  final energySamples = byDay
      .skip(1)
      .map((d) => d.activeEnergyKcal)
      .whereType<double>()
      .toList();
  if (yesterday != null && energySamples.length >= 3) {
    final avgEnergy =
        energySamples.reduce((a, b) => a + b) / energySamples.length;
    if (avgEnergy > 0) {
      final ratio = yesterday / avgEnergy;
      if (ratio > 1.5) {
        readiness -= 15;
        reasons.add(
          'Heavy activity yesterday '
          '(${yesterday.round()} kcal vs ${avgEnergy.round()} avg) — '
          'consider a lighter session',
        );
      } else if (ratio < 0.5) {
        readiness += 5;
        reasons.add('Light day yesterday — good recovery');
      }
    }
  }
  final readinessPercent = readiness.clamp(5, 100).round();

  // --- diet efficiency ---------------------------------------------
  // Chronic pattern matters here, so use the multi-night average.
  // Linear between the two study arms: 5.5 h → 25 %, 8.5 h → 55 %.
  final efficiency = (25 + (avgSleep - 5.5) / 3.0 * 30).clamp(20, 60);
  final dietEfficiencyPercent = efficiency.round();

  return ReadinessResult(
    readinessPercent: readinessPercent,
    dietEfficiencyPercent: dietEfficiencyPercent,
    headline: switch (readinessPercent) {
      >= 85 => 'Great day to train',
      >= 65 => 'Good day to train',
      >= 45 => 'Take it moderate',
      _ => 'Recovery day',
    },
    reasons: reasons,
  );
}

/// 0.25–1.0 factor for one night of sleep. 7–9 h is optimal; short
/// sleep degrades steeply, very long sleep slightly.
double _sleepFactor(double hours) {
  if (hours >= 7 && hours <= 9) return 1.0;
  if (hours > 9) {
    if (hours >= 11) return 0.85;
    return 1.0 - (hours - 9) * 0.075;
  }
  if (hours <= 4) return 0.25;
  // 4 h → 0.25 rising linearly to 7 h → 1.0
  return 0.25 + (hours - 4) / 3.0 * 0.75;
}

String _fmtHours(double hours) {
  final h = hours.floor();
  final m = ((hours - h) * 60).round();
  return m == 0 ? '${h}h' : '${h}h ${m.toString().padLeft(2, '0')}m';
}
