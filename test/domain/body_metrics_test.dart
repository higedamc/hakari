import 'package:flutter_test/flutter_test.dart';
import 'package:hakari/domain/services/body_metrics.dart';

void main() {
  group('BodyProfileLimits', () {
    test('height bounds are inclusive and reject null / non-finite', () {
      expect(BodyProfileLimits.isPlausibleHeightCm(50), isTrue);
      expect(BodyProfileLimits.isPlausibleHeightCm(250), isTrue);
      expect(BodyProfileLimits.isPlausibleHeightCm(49.9), isFalse);
      expect(BodyProfileLimits.isPlausibleHeightCm(250.1), isFalse);
      expect(BodyProfileLimits.isPlausibleHeightCm(null), isFalse);
      expect(BodyProfileLimits.isPlausibleHeightCm(double.nan), isFalse);
      expect(BodyProfileLimits.isPlausibleHeightCm(double.infinity), isFalse);
    });

    test('weight bounds are inclusive and reject null / non-finite', () {
      expect(BodyProfileLimits.isPlausibleWeightKg(1), isTrue);
      expect(BodyProfileLimits.isPlausibleWeightKg(500), isTrue);
      expect(BodyProfileLimits.isPlausibleWeightKg(0), isFalse);
      expect(BodyProfileLimits.isPlausibleWeightKg(500.5), isFalse);
      expect(BodyProfileLimits.isPlausibleWeightKg(null), isFalse);
      expect(BodyProfileLimits.isPlausibleWeightKg(-double.infinity), isFalse);
    });
  });

  group('computeBmi', () {
    test('kg over metres squared', () {
      expect(computeBmi(weightKg: 72, heightCm: 180), closeTo(22.22, 0.01));
      expect(computeBmi(weightKg: 60, heightCm: 150), closeTo(26.67, 0.01));
    });

    test('null on missing or implausible input', () {
      expect(computeBmi(weightKg: null, heightCm: 180), isNull);
      expect(computeBmi(weightKg: 72, heightCm: null), isNull);
      expect(computeBmi(weightKg: 0, heightCm: 180), isNull);
      expect(computeBmi(weightKg: 72, heightCm: 0), isNull);
      expect(computeBmi(weightKg: 72, heightCm: 300), isNull);
      expect(computeBmi(weightKg: double.nan, heightCm: 180), isNull);
    });
  });

  group('classifyBmi', () {
    test('WHO cut-offs, lower bound inclusive', () {
      expect(classifyBmi(18.49), BmiCategory.underweight);
      expect(classifyBmi(18.5), BmiCategory.normal);
      expect(classifyBmi(24.99), BmiCategory.normal);
      expect(classifyBmi(25), BmiCategory.overweight);
      expect(classifyBmi(29.99), BmiCategory.overweight);
      expect(classifyBmi(30), BmiCategory.obese);
      expect(classifyBmi(45), BmiCategory.obese);
    });

    test('null on missing, zero, negative or non-finite', () {
      expect(classifyBmi(null), isNull);
      expect(classifyBmi(0), isNull);
      expect(classifyBmi(-1), isNull);
      expect(classifyBmi(double.nan), isNull);
      expect(classifyBmi(double.infinity), isNull);
    });
  });

  group('goalRemainingKg', () {
    test('signed goal minus current', () {
      expect(goalRemainingKg(currentKg: 72, goalKg: 68), closeTo(-4, 1e-9));
      expect(goalRemainingKg(currentKg: 60, goalKg: 65), closeTo(5, 1e-9));
      expect(goalRemainingKg(currentKg: 70, goalKg: 70), 0);
    });

    test('null on missing or implausible input', () {
      expect(goalRemainingKg(currentKg: null, goalKg: 68), isNull);
      expect(goalRemainingKg(currentKg: 72, goalKg: null), isNull);
      expect(goalRemainingKg(currentKg: 72, goalKg: 0), isNull);
      expect(goalRemainingKg(currentKg: 999, goalKg: 68), isNull);
    });
  });

  group('goalProgress', () {
    test('fraction of the way, losing', () {
      expect(
        goalProgress(startKg: 80, currentKg: 76, goalKg: 70),
        closeTo(0.4, 1e-9),
      );
      expect(goalProgress(startKg: 80, currentKg: 80, goalKg: 70), 0);
      expect(goalProgress(startKg: 80, currentKg: 70, goalKg: 70), 1);
    });

    test('fraction of the way, gaining', () {
      expect(
        goalProgress(startKg: 55, currentKg: 58, goalKg: 60),
        closeTo(0.6, 1e-9),
      );
    });

    test('clamped to 0..1 when off the start or past the goal', () {
      expect(goalProgress(startKg: 80, currentKg: 82, goalKg: 70), 0);
      expect(goalProgress(startKg: 80, currentKg: 68, goalKg: 70), 1);
      expect(goalProgress(startKg: 55, currentKg: 61, goalKg: 60), 1);
      expect(goalProgress(startKg: 55, currentKg: 54, goalKg: 60), 0);
    });

    test('null when undefined: start equals goal, or any input missing', () {
      expect(goalProgress(startKg: 70, currentKg: 70, goalKg: 70), isNull);
      expect(goalProgress(startKg: null, currentKg: 76, goalKg: 70), isNull);
      expect(goalProgress(startKg: 80, currentKg: null, goalKg: 70), isNull);
      expect(goalProgress(startKg: 80, currentKg: 76, goalKg: null), isNull);
      expect(goalProgress(startKg: 80, currentKg: 76, goalKg: 0), isNull);
    });
  });

  group('isGoalReached', () {
    test('exact or within tolerance', () {
      expect(isGoalReached(startKg: 80, currentKg: 70, goalKg: 70), isTrue);
      expect(
        isGoalReached(
          startKg: 80,
          currentKg: 70.3,
          goalKg: 70,
          toleranceKg: 0.5,
        ),
        isTrue,
      );
      expect(isGoalReached(startKg: 80, currentKg: 70.3, goalKg: 70), isFalse);
    });

    test('overshoot in the direction of travel counts', () {
      expect(isGoalReached(startKg: 80, currentKg: 69, goalKg: 70), isTrue);
      expect(isGoalReached(startKg: 55, currentKg: 61, goalKg: 60), isTrue);
      expect(isGoalReached(startKg: 55, currentKg: 59, goalKg: 60), isFalse);
    });

    test('without a start weight only proximity counts', () {
      expect(isGoalReached(startKg: null, currentKg: 70, goalKg: 70), isTrue);
      expect(isGoalReached(startKg: null, currentKg: 69, goalKg: 70), isFalse);
    });

    test('false on missing input', () {
      expect(isGoalReached(startKg: 80, currentKg: null, goalKg: 70), isFalse);
      expect(isGoalReached(startKg: 80, currentKg: 70, goalKg: null), isFalse);
    });
  });
}
