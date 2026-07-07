import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../domain/entities/weight_entry.dart';

final DateFormat _axisDateFormat = DateFormat('M/d');

/// Card showing the last 90 days of weight as a line chart, with a
/// secondary body-fat line when composition data exists.
class WeightChartCard extends StatelessWidget {
  const WeightChartCard({super.key, required this.entries});

  final List<WeightEntry> entries;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final cutoff = DateTime.now().subtract(const Duration(days: 90));
    final points = entries.where((e) => e.recordedAt.isAfter(cutoff)).toList()
      ..sort((a, b) => a.recordedAt.compareTo(b.recordedAt));
    final hasBodyFat = points.any((p) => p.bodyFatPercent != null);

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Last 90 days', style: theme.textTheme.titleMedium),
            const SizedBox(height: 16),
            SizedBox(
              height: 220,
              child: points.length < 2
                  ? const _EmptyChart()
                  : _TrendChart(points: points),
            ),
            if (points.length >= 2) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  _LegendDot(color: scheme.primary, label: 'Weight (kg)'),
                  if (hasBodyFat) ...[
                    const SizedBox(width: 16),
                    _LegendDot(color: scheme.tertiary, label: 'Body fat (%)'),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TrendChart extends StatelessWidget {
  const _TrendChart({required this.points});

  final List<WeightEntry> points;

  static double _dayX(DateTime t) =>
      t.millisecondsSinceEpoch / Duration.millisecondsPerDay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final weightSpots = [
      for (final p in points) FlSpot(_dayX(p.recordedAt), p.weightKg),
    ];
    final fatSpots = [
      for (final p in points)
        if (p.bodyFatPercent != null)
          FlSpot(_dayX(p.recordedAt), p.bodyFatPercent!),
    ];

    var minX = weightSpots.first.x;
    var maxX = weightSpots.last.x;
    if (maxX - minX < 1) {
      minX -= 0.5;
      maxX += 0.5;
    }

    final allY = [
      for (final s in weightSpots) s.y,
      for (final s in fatSpots) s.y,
    ];
    final minY = (allY.reduce(math.min) - 2).floorToDouble();
    final maxY = (allY.reduce(math.max) + 2).ceilToDouble();

    final labelStyle = theme.textTheme.labelSmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );

    return LineChart(
      LineChartData(
        minX: minX,
        maxX: maxX,
        minY: minY,
        maxY: maxY,
        gridData: FlGridData(
          drawVerticalLine: false,
          getDrawingHorizontalLine: (value) => FlLine(
            color: scheme.outlineVariant.withValues(alpha: 0.4),
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 36,
              getTitlesWidget: (value, meta) => SideTitleWidget(
                meta: meta,
                child: Text(value.toStringAsFixed(0), style: labelStyle),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              interval: math.max(1, (maxX - minX) / 4),
              getTitlesWidget: (value, meta) {
                final date = DateTime.fromMillisecondsSinceEpoch(
                  (value * Duration.millisecondsPerDay).round(),
                );
                return SideTitleWidget(
                  meta: meta,
                  child: Text(_axisDateFormat.format(date), style: labelStyle),
                );
              },
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => scheme.inverseSurface,
            getTooltipItems: (touchedSpots) => [
              for (final spot in touchedSpots)
                LineTooltipItem(
                  spot.y.toStringAsFixed(1),
                  theme.textTheme.labelMedium!.copyWith(
                    color: scheme.onInverseSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: weightSpots,
            isCurved: true,
            preventCurveOverShooting: true,
            color: scheme.primary,
            barWidth: 3,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: scheme.primary.withValues(alpha: 0.08),
            ),
          ),
          if (fatSpots.length >= 2)
            LineChartBarData(
              spots: fatSpots,
              isCurved: true,
              preventCurveOverShooting: true,
              color: scheme.tertiary,
              barWidth: 2,
              isStrokeCapRound: true,
              dashArray: [6, 4],
              dotData: const FlDotData(show: false),
            ),
        ],
      ),
    );
  }
}

class _EmptyChart extends StatelessWidget {
  const _EmptyChart();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.show_chart, size: 40, color: scheme.outline),
          const SizedBox(height: 8),
          Text('Not enough data yet', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            'Add at least two measurements to see your trend.',
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

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
