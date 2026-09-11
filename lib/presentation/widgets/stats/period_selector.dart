import 'package:flutter/material.dart';

import 'stats_period.dart';

/// 1M / 3M / 6M / 1Y / All segmented control.
class PeriodSelector extends StatelessWidget {
  const PeriodSelector({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final StatsPeriod selected;
  final ValueChanged<StatsPeriod> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<StatsPeriod>(
        showSelectedIcon: false,
        segments: [
          for (final p in StatsPeriod.values)
            ButtonSegment(value: p, label: Text(p.label)),
        ],
        selected: {selected},
        onSelectionChanged: (s) => onChanged(s.single),
      ),
    );
  }
}
