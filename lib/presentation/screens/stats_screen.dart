import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/weight_entry.dart';
import '../../domain/failures/failures.dart';
import '../providers/entries_provider.dart';
import '../providers/settings_provider.dart';
import '../theme/hakari_tokens.dart';
import '../widgets/stats/bmi_card.dart';
import '../widgets/stats/goal_card.dart';
import '../widgets/stats/metric_trend_card.dart';
import '../widgets/stats/period_selector.dart';
import '../widgets/stats/stats_period.dart';
import '../widgets/stats/weight_summary_card.dart';

/// Stats tab: period selector, weight summary, BMI, goal progress and one
/// trend card per body-composition metric that has data in the window.
///
/// Read-only: it never writes entries or settings. Height and goal weight
/// come from [AppSettings]; when either is missing the matching card
/// invites the user to set it and shows no number.
class StatsScreen extends ConsumerStatefulWidget {
  const StatsScreen({super.key});

  @override
  ConsumerState<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends ConsumerState<StatsScreen> {
  StatsPeriod _period = StatsPeriod.initial;

  @override
  Widget build(BuildContext context) {
    final entriesAsync = ref.watch(entriesProvider);
    final settingsAsync = ref.watch(settingsProvider);
    // Until settings have loaded, height and goal are unknown, not absent.
    // The BMI and Goal cards wait rather than inviting a user who has
    // already set both to go and set them.
    final settingsKnown = settingsAsync.hasValue || settingsAsync.hasError;
    final settings = settingsAsync.value;

    return Scaffold(
      appBar: AppBar(title: const Text('Stats')),
      body: entriesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(HakariSpacing.xl),
            child: Text(
              error is Failure
                  ? error.message
                  : 'Failed to load entries: $error',
              textAlign: TextAlign.center,
            ),
          ),
        ),
        data: (entries) => _StatsBody(
          allEntries: entries,
          period: _period,
          settingsKnown: settingsKnown,
          heightCm: settings?.heightCm,
          goalWeightKg: settings?.goalWeightKg,
          onPeriodChanged: (p) => setState(() => _period = p),
        ),
      ),
    );
  }
}

class _StatsBody extends StatelessWidget {
  const _StatsBody({
    required this.allEntries,
    required this.period,
    required this.settingsKnown,
    required this.heightCm,
    required this.goalWeightKg,
    required this.onPeriodChanged,
  });

  final List<WeightEntry> allEntries;
  final StatsPeriod period;

  /// False while [AppSettings] are still loading; the cards that depend
  /// on them are omitted instead of rendering a misleading invitation.
  final bool settingsKnown;
  final double? heightCm;
  final double? goalWeightKg;
  final ValueChanged<StatsPeriod> onPeriodChanged;

  @override
  Widget build(BuildContext context) {
    final inWindow = period.select(allEntries);
    final summary = WeightSummary.of(inWindow);

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        HakariSpacing.page,
        HakariSpacing.lg,
        HakariSpacing.page,
        HakariSpacing.xl,
      ),
      children: [
        PeriodSelector(selected: period, onChanged: onPeriodChanged),
        const SizedBox(height: HakariSpacing.lg),
        if (summary == null)
          _EmptyPeriod(period: period, hasAnyEntries: allEntries.isNotEmpty)
        else ...[
          WeightSummaryCard(summary: summary, period: period),
          if (settingsKnown) ...[
            const SizedBox(height: HakariSpacing.listGap),
            BmiCard(weightKg: summary.current.weightKg, heightCm: heightCm),
            const SizedBox(height: HakariSpacing.listGap),
            GoalCard(
              summary: summary,
              period: period,
              goalWeightKg: goalWeightKg,
            ),
          ],
          for (final metric in BodyMetric.values)
            if (metric.entriesWithValue(inWindow) case final withValue
                when withValue.isNotEmpty) ...[
              const SizedBox(height: HakariSpacing.listGap),
              MetricTrendCard(
                metric: metric,
                entriesWithValue: withValue,
                period: period,
              ),
            ],
        ],
      ],
    );
  }
}

/// Case 1 of the empty states: nothing recorded in the window.
class _EmptyPeriod extends StatelessWidget {
  const _EmptyPeriod({required this.period, required this.hasAnyEntries});

  final StatsPeriod period;
  final bool hasAnyEntries;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: HakariSpacing.xxxl),
      child: Column(
        children: [
          Icon(
            Icons.insights_outlined,
            size: HakariSpacing.xxxl,
            color: scheme.outline,
          ),
          const SizedBox(height: HakariSpacing.md),
          Text(
            hasAnyEntries
                ? 'No measurements in the last ${period.label}'
                : 'No measurements yet',
            style: theme.textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: HakariSpacing.xs),
          Text(
            hasAnyEntries
                ? 'Pick a longer period to see older data.'
                : 'Add a measurement on the Home tab to see your stats.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
