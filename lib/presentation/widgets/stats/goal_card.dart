import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../domain/services/body_metrics.dart';
import '../../theme/hakari_tokens.dart';
import 'stat_card.dart';
import 'stats_period.dart';

final NumberFormat _oneDecimal = NumberFormat('0.0');
final DateFormat _startDateFormat = DateFormat.yMMMd();

/// Distance to the goal weight (absolute) and progress over the selected
/// window (relative to the window's first entry).
///
/// The two figures answer different questions, so the bar is labelled
/// with the window it measures, and with fewer than two entries in the
/// window no bar is shown at all: `start == current` would read as 0 %
/// beside a "x kg to go" that says otherwise.
class GoalCard extends StatelessWidget {
  const GoalCard({
    super.key,
    required this.summary,
    required this.period,
    required this.goalWeightKg,
  });

  final WeightSummary summary;
  final StatsPeriod period;
  final double? goalWeightKg;

  static const String missingGoalMessage =
      'Set a goal weight in Settings to track your progress.';
  static const String insufficientDataMessage =
      'Not enough measurements in this period to measure progress. '
      'Two or more are needed.';
  static const String goalReachedMessage = 'Goal reached';

  @override
  Widget build(BuildContext context) {
    final remaining = goalRemainingKg(
      currentKg: summary.current.weightKg,
      goalKg: goalWeightKg,
    );
    if (goalWeightKg == null || remaining == null) {
      return const StatCard(
        title: 'Goal',
        child: StatInvitation(
          icon: Icons.flag_outlined,
          message: missingGoalMessage,
        ),
      );
    }

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final goal = goalWeightKg!;
    final reached = isGoalReached(
      startKg: summary.canMeasureProgress ? summary.start.weightKg : null,
      currentKg: summary.current.weightKg,
      goalKg: goal,
      toleranceKg: 0.05,
    );
    final progress = summary.canMeasureProgress
        ? goalProgress(
            startKg: summary.start.weightKg,
            currentKg: summary.current.weightKg,
            goalKg: goal,
          )
        : null;

    final String headline;
    final String? unit;
    final String direction;
    if (reached) {
      headline = goalReachedMessage;
      unit = null;
      direction = 'Goal ${_oneDecimal.format(goal)} kg';
    } else {
      headline = _oneDecimal.format(remaining.abs());
      unit = 'kg to go';
      direction = remaining < 0
          ? 'Down to ${_oneDecimal.format(goal)} kg'
          : 'Up to ${_oneDecimal.format(goal)} kg';
    }

    return StatCard(
      title: 'Goal',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StatFigure(value: headline, unit: unit, caption: direction),
          const SizedBox(height: HakariSpacing.lg),
          if (progress != null) ...[
            ClipRRect(
              borderRadius: HakariRadii.innerBorder,
              child: LinearProgressIndicator(
                value: progress,
                minHeight: HakariSpacing.sm,
                backgroundColor: HakariSurfaces.nested(scheme),
              ),
            ),
            const SizedBox(height: HakariSpacing.sm),
            Text(
              '${(progress * 100).round()} % of the way since '
              '${_startDateFormat.format(summary.start.recordedAt)} '
              '(${period.label}: ${_oneDecimal.format(summary.start.weightKg)} kg '
              '→ ${_oneDecimal.format(summary.current.weightKg)} kg)',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ] else if (!summary.canMeasureProgress)
            Text(
              insufficientDataMessage,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            )
          else
            Text(
              'This period started at the goal weight, so there is no '
              'progress to measure.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}
