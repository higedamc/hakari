import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../theme/hakari_tokens.dart';
import 'stat_card.dart';
import 'stats_period.dart';

final NumberFormat _oneDecimal = NumberFormat('0.0');
final NumberFormat _signedOneDecimal = NumberFormat('+0.0;-0.0');

/// Current weight, change over the window, average, min / max and count.
class WeightSummaryCard extends StatelessWidget {
  const WeightSummaryCard({
    super.key,
    required this.summary,
    required this.period,
  });

  final WeightSummary summary;
  final StatsPeriod period;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final change = summary.changeKg;
    final changeText = summary.count < 2
        ? 'Single measurement in this period'
        : '${_signedOneDecimal.format(change)} kg over ${period.label}';

    return StatCard(
      title: 'Weight',
      trailing: Chip(
        label: Text('${summary.count} measurements'),
        labelStyle: theme.textTheme.labelSmall?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
        visualDensity: VisualDensity.compact,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StatFigure(
            value: _oneDecimal.format(summary.current.weightKg),
            unit: 'kg',
            caption: changeText,
          ),
          const SizedBox(height: HakariSpacing.lg),
          Row(
            children: [
              Expanded(
                child: StatPair(
                  label: 'Average',
                  value: '${_oneDecimal.format(summary.averageKg)} kg',
                ),
              ),
              Expanded(
                child: StatPair(
                  label: 'Lowest',
                  value: '${_oneDecimal.format(summary.minKg)} kg',
                ),
              ),
              Expanded(
                child: StatPair(
                  label: 'Highest',
                  value: '${_oneDecimal.format(summary.maxKg)} kg',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
