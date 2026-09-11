import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hakari/domain/entities/app_settings.dart';
import 'package:hakari/domain/entities/weight_entry.dart';
import 'package:hakari/presentation/screens/stats_screen.dart';
import 'package:hakari/presentation/widgets/stats/bmi_card.dart';
import 'package:hakari/presentation/widgets/stats/goal_card.dart';
import 'package:hakari/presentation/widgets/stats/metric_trend_card.dart';
import 'package:hakari/presentation/widgets/stats/stats_period.dart';

import '../screen_fakes.dart';

/// ui-stats acceptance, light and dark: populated period, empty period,
/// height unset, goal unset, a metric with no data, and the single-entry
/// window that must not render a 0 % bar.
void main() {
  final now = DateTime.now();
  WeightEntry entry(
    String id,
    int daysAgo,
    double kg, {
    double? fat,
    int? bmr,
  }) => WeightEntry(
    id: id,
    recordedAt: now.subtract(Duration(days: daysAgo)),
    weightKg: kg,
    bodyFatPercent: fat,
    basalMetabolicRateKcal: bmr,
  );

  // Three in the default 3M window, one older; body fat on two, BMR on
  // one, no muscle mass anywhere.
  final populated = [
    entry('old', 200, 80, fat: 25),
    entry('c', 60, 76, fat: 22, bmr: 1550),
    entry('b', 10, 75, fat: 21),
    entry('a', 1, 74.5),
  ];
  const profile = AppSettings(heightCm: 175, goalWeightKg: 70);

  Future<void> pumpStats(
    WidgetTester tester,
    Brightness brightness, {
    required List<WeightEntry> entries,
    AppSettings settings = profile,
  }) async {
    tester.view.physicalSize = const Size(400, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      screenHost(
        const StatsScreen(),
        brightness,
        entries: entries,
        settings: settings,
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
  }

  Finder metricCard(BodyMetric m) =>
      find.byWidgetPredicate((w) => w is MetricTrendCard && w.metric == m);

  for (final brightness in Brightness.values) {
    group(brightness.name, () {
      testWidgets('populated period shows summary, BMI, goal bar and only '
          'metrics with data', (tester) async {
        await pumpStats(tester, brightness, entries: populated);
        expect(tester.takeException(), isNull);

        expect(find.text('Stats'), findsOneWidget);
        expect(find.byType(SegmentedButton<StatsPeriod>), findsOneWidget);

        // Weight summary: current, change over 3M (74.5 - 76), count.
        expect(find.text('74.5'), findsOneWidget);
        expect(find.text('-1.5 kg over 3M'), findsOneWidget);
        expect(find.text('3 measurements'), findsOneWidget);

        // BMI = 74.5 / 1.75² = 24.3, Normal.
        expect(find.text('24.3'), findsOneWidget);
        expect(find.text('kg/m²'), findsOneWidget);
        expect(find.text('Normal'), findsOneWidget);
        expect(find.text(BmiCard.missingHeightMessage), findsNothing);

        // Goal: 4.5 kg to go, bar = (76 - 74.5) / (76 - 70) = 25 %.
        expect(find.text('4.5'), findsOneWidget);
        expect(find.text('kg to go'), findsOneWidget);
        expect(find.byType(LinearProgressIndicator), findsOneWidget);
        final bar = tester.widget<LinearProgressIndicator>(
          find.byType(LinearProgressIndicator),
        );
        expect(bar.value, closeTo(0.25, 1e-9));
        expect(find.textContaining('25 % of the way since'), findsOneWidget);
        expect(find.textContaining('(3M: 76.0 kg → 74.5 kg)'), findsOneWidget);
        expect(find.text(GoalCard.insufficientDataMessage), findsNothing);

        // Metric cards: body fat (2 values) and BMR (1 value) present,
        // muscle mass / visceral fat / metabolic age absent.
        expect(metricCard(BodyMetric.bodyFat), findsOneWidget);
        expect(metricCard(BodyMetric.basalMetabolicRate), findsOneWidget);
        expect(metricCard(BodyMetric.muscleMass), findsNothing);
        expect(metricCard(BodyMetric.visceralFat), findsNothing);
        expect(metricCard(BodyMetric.metabolicAge), findsNothing);
        expect(find.text('-1.0 % over 3M'), findsOneWidget);
        expect(find.text('One value in this period'), findsOneWidget);
      });

      testWidgets('empty period shows the empty state; a longer period '
          'reveals older data and moves the start', (tester) async {
        await pumpStats(
          tester,
          brightness,
          entries: [entry('old', 200, 80, fat: 25), entry('older', 300, 82)],
        );
        expect(find.text('No measurements in the last 3M'), findsOneWidget);
        expect(find.byType(LinearProgressIndicator), findsNothing);
        expect(metricCard(BodyMetric.bodyFat), findsNothing);

        await tester.tap(find.text('All'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('No measurements in the last 3M'), findsNothing);
        expect(find.text('80.0'), findsOneWidget);
        expect(find.text('-2.0 kg over All'), findsOneWidget);
        // Start is the first entry ever (82 kg), goal 70: 2/12 = 17 %.
        expect(find.textContaining('(All: 82.0 kg → 80.0 kg)'), findsOneWidget);
        expect(metricCard(BodyMetric.bodyFat), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('no entries at all shows the first-run empty state', (
        tester,
      ) async {
        await pumpStats(tester, brightness, entries: const []);
        expect(find.text('No measurements yet'), findsOneWidget);
        expect(find.byType(BmiCard), findsNothing);
        expect(find.byType(GoalCard), findsNothing);
      });

      testWidgets('height unset: BMI invites, never renders a number', (
        tester,
      ) async {
        await pumpStats(
          tester,
          brightness,
          entries: populated,
          settings: const AppSettings(goalWeightKg: 70),
        );
        expect(find.text(BmiCard.missingHeightMessage), findsOneWidget);
        expect(find.text('kg/m²'), findsNothing);
        expect(find.text('24.3'), findsNothing);
        expect(find.text('0.0'), findsNothing);
        // The rest of the page still renders.
        expect(find.text('4.5'), findsOneWidget);
        expect(find.text('kg to go'), findsOneWidget);
        expect(find.byType(LinearProgressIndicator), findsOneWidget);
      });

      testWidgets('goal unset: goal card invites, BMI still shows', (
        tester,
      ) async {
        await pumpStats(
          tester,
          brightness,
          entries: populated,
          settings: const AppSettings(heightCm: 175),
        );
        expect(find.text(GoalCard.missingGoalMessage), findsOneWidget);
        expect(find.byType(LinearProgressIndicator), findsNothing);
        expect(find.text('kg to go'), findsNothing);
        expect(find.text('24.3'), findsOneWidget);
      });

      testWidgets('single entry in the default period: remaining distance, '
          'no bar (first launch after one Health Planet measurement)', (
        tester,
      ) async {
        await pumpStats(tester, brightness, entries: [entry('only', 2, 70.2)]);
        expect(find.text('0.2'), findsOneWidget);
        expect(find.text('kg to go'), findsOneWidget);
        expect(find.byType(LinearProgressIndicator), findsNothing);
        expect(find.textContaining('% of the way'), findsNothing);
        expect(find.text(GoalCard.insufficientDataMessage), findsOneWidget);
        expect(find.text('Single measurement in this period'), findsOneWidget);
        expect(find.text('1 measurements'), findsOneWidget);
      });

      testWidgets('goal reached', (tester) async {
        await pumpStats(
          tester,
          brightness,
          entries: [entry('b', 20, 72), entry('a', 1, 70)],
        );
        expect(find.text(GoalCard.goalReachedMessage), findsOneWidget);
        expect(find.text('kg to go'), findsNothing);
        final bar = tester.widget<LinearProgressIndicator>(
          find.byType(LinearProgressIndicator),
        );
        expect(bar.value, 1);
      });
    });
  }
}
