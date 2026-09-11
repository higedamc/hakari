import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../domain/entities/weight_entry.dart';
import '../../theme/hakari_tokens.dart';
import 'stat_card.dart';
import 'stats_period.dart';

final NumberFormat _signedOneDecimal = NumberFormat('+0.0;-0.0');
final NumberFormat _signedInteger = NumberFormat('+0;-0');

/// One body-composition metric over the window: latest value, change since
/// the window's first value, and a sparkline when there are two or more.
///
/// Callers only build this for metrics that have data in the window
/// (see [BodyMetric.entriesWithValue]); it asserts that contract.
class MetricTrendCard extends StatelessWidget {
  MetricTrendCard({
    super.key,
    required this.metric,
    required List<WeightEntry> entriesWithValue,
    required this.period,
  }) : entries = List<WeightEntry>.of(entriesWithValue)
         ..sort((a, b) => a.recordedAt.compareTo(b.recordedAt)),
       assert(
         entriesWithValue.isNotEmpty,
         'MetricTrendCard needs at least one entry with a value',
       );

  final BodyMetric metric;

  /// Oldest first, every one carrying [metric].
  final List<WeightEntry> entries;
  final StatsPeriod period;

  static const double sparklineWidth = 120;
  static const double sparklineHeight = 72;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final latest = metric.valueOf(entries.last)!;
    final first = metric.valueOf(entries.first)!;
    final delta = latest - first;
    final caption = entries.length < 2
        ? 'One value in this period'
        : '${metric.decimals == 0 ? _signedInteger.format(delta) : _signedOneDecimal.format(delta)}'
              '${metric.unit.isEmpty ? '' : ' ${metric.unit}'} over ${period.label}';

    return StatCard(
      title: metric.label,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: StatFigure(
              value: latest.toStringAsFixed(metric.decimals),
              unit: metric.unit.isEmpty ? null : metric.unit,
              caption: caption,
            ),
          ),
          if (entries.length >= 2) ...[
            const SizedBox(width: HakariSpacing.lg),
            SizedBox(
              width: sparklineWidth,
              height: sparklineHeight,
              child: _Sparkline(
                values: [for (final e in entries) metric.valueOf(e)!],
                color: scheme.primary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Sparkline extends StatelessWidget {
  const _Sparkline({required this.values, required this.color});

  final List<double> values;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final chart = HakariChartColors.of(context);
    final minY = values.reduce(math.min);
    final maxY = values.reduce(math.max);
    final pad = maxY == minY ? 1.0 : (maxY - minY) * 0.15;
    return LineChart(
      LineChartData(
        minX: 0,
        maxX: (values.length - 1).toDouble(),
        minY: minY - pad,
        maxY: maxY + pad,
        gridData: const FlGridData(show: false),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        lineTouchData: const LineTouchData(enabled: false),
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (var i = 0; i < values.length; i++)
                FlSpot(i.toDouble(), values[i]),
            ],
            isCurved: true,
            preventCurveOverShooting: true,
            color: chart.line,
            barWidth: 2,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(show: true, gradient: chart.fillGradient),
          ),
        ],
      ),
      duration: Duration.zero,
    );
  }
}
