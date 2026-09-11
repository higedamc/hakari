import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../domain/services/body_metrics.dart';
import 'stat_card.dart';

final NumberFormat _oneDecimal = NumberFormat('0.0');

/// BMI from the newest weight in the window and the stored height.
///
/// With no height the card invites the user to set one and shows no
/// number at all; a wrong or zero BMI is never rendered.
class BmiCard extends StatelessWidget {
  const BmiCard({super.key, required this.weightKg, required this.heightCm});

  final double weightKg;
  final double? heightCm;

  static const String missingHeightMessage =
      'Set your height in Settings to see your BMI.';

  @override
  Widget build(BuildContext context) {
    final bmi = computeBmi(weightKg: weightKg, heightCm: heightCm);
    final category = classifyBmi(bmi);
    if (bmi == null || category == null) {
      return const StatCard(
        title: 'BMI',
        child: StatInvitation(
          icon: Icons.height,
          message: missingHeightMessage,
        ),
      );
    }
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return StatCard(
      title: 'BMI',
      trailing: Chip(
        label: Text(_categoryLabel(category)),
        labelStyle: theme.textTheme.labelSmall?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
        visualDensity: VisualDensity.compact,
      ),
      child: StatFigure(
        value: _oneDecimal.format(bmi),
        unit: 'kg/m²',
        caption:
            'Height ${_oneDecimal.format(heightCm!)} cm · '
            'weight ${_oneDecimal.format(weightKg)} kg',
      ),
    );
  }

  static String _categoryLabel(BmiCategory c) => switch (c) {
    BmiCategory.underweight => 'Underweight',
    BmiCategory.normal => 'Normal',
    BmiCategory.overweight => 'Overweight',
    BmiCategory.obese => 'Obese',
  };
}
