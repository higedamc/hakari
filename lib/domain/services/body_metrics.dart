/// Pure body-profile arithmetic: BMI and goal-weight progress.
///
/// This is the contract the Stats UI codes against. No I/O, no Flutter,
/// no dependency on settings or repositories: callers pass the numbers
/// they have and get `null` back whenever an input is missing or
/// implausible, so screens can decide what to hide instead of guarding
/// every formula themselves.
library;

/// Plausibility bounds shared by the codec, the settings layer and the
/// formulas below. Anything outside is treated as absent.
abstract final class BodyProfileLimits {
  static const double minHeightCm = 50;
  static const double maxHeightCm = 250;
  static const double minWeightKg = 1;
  static const double maxWeightKg = 500;

  static bool isPlausibleHeightCm(double? cm) =>
      cm != null && cm.isFinite && cm >= minHeightCm && cm <= maxHeightCm;

  static bool isPlausibleWeightKg(double? kg) =>
      kg != null && kg.isFinite && kg >= minWeightKg && kg <= maxWeightKg;
}

/// WHO adult BMI classes.
enum BmiCategory { underweight, normal, overweight, obese }

/// Body mass index (kg / m²), or `null` when either input is missing or
/// implausible.
double? computeBmi({required double? weightKg, required double? heightCm}) {
  if (!BodyProfileLimits.isPlausibleWeightKg(weightKg) ||
      !BodyProfileLimits.isPlausibleHeightCm(heightCm)) {
    return null;
  }
  final metres = heightCm! / 100;
  return weightKg! / (metres * metres);
}

/// WHO adult cut-offs: < 18.5 underweight, < 25 normal, < 30 overweight,
/// otherwise obese. `null` for a missing or non-finite BMI.
BmiCategory? classifyBmi(double? bmi) {
  if (bmi == null || !bmi.isFinite || bmi <= 0) return null;
  if (bmi < 18.5) return BmiCategory.underweight;
  if (bmi < 25) return BmiCategory.normal;
  if (bmi < 30) return BmiCategory.overweight;
  return BmiCategory.obese;
}

/// Signed distance still to travel: `goalKg - currentKg`. Negative means
/// weight still has to come off, positive means it has to go on, zero
/// means the goal is met. `null` when either value is missing.
double? goalRemainingKg({required double? currentKg, required double? goalKg}) {
  if (!BodyProfileLimits.isPlausibleWeightKg(currentKg) ||
      !BodyProfileLimits.isPlausibleWeightKg(goalKg)) {
    return null;
  }
  return goalKg! - currentKg!;
}

/// Share of the way from [startKg] to [goalKg] that [currentKg] has
/// covered, clamped to `0.0 … 1.0`. Works in both directions (losing or
/// gaining). `null` when any value is missing or when start equals goal,
/// because progress is undefined then.
double? goalProgress({
  required double? startKg,
  required double? currentKg,
  required double? goalKg,
}) {
  if (!BodyProfileLimits.isPlausibleWeightKg(startKg) ||
      !BodyProfileLimits.isPlausibleWeightKg(currentKg) ||
      !BodyProfileLimits.isPlausibleWeightKg(goalKg)) {
    return null;
  }
  final total = startKg! - goalKg!;
  if (total == 0) return null;
  final covered = startKg - currentKg!;
  return (covered / total).clamp(0.0, 1.0);
}

/// Whether [currentKg] has reached [goalKg], allowing [toleranceKg] of
/// slack in the direction of travel from [startKg]. With no start weight
/// the check is symmetric.
bool isGoalReached({
  required double? startKg,
  required double? currentKg,
  required double? goalKg,
  double toleranceKg = 0.0,
}) {
  final remaining = goalRemainingKg(currentKg: currentKg, goalKg: goalKg);
  if (remaining == null) return false;
  if (remaining.abs() <= toleranceKg) return true;
  if (!BodyProfileLimits.isPlausibleWeightKg(startKg)) return false;
  // Overshooting past the goal in the direction of travel still counts.
  final losing = startKg! > goalKg!;
  return losing ? currentKg! <= goalKg : currentKg! >= goalKg;
}
