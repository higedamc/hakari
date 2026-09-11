import 'package:flutter/material.dart';

import '../theme/hakari_tokens.dart';

/// Stats tab.
///
/// Placeholder only. The navigation shell needs a third destination; the
/// `ui-stats` leaf replaces this file with the real statistics page (period
/// selector, weight summary, body-composition trend cards).
class StatsScreen extends StatelessWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Stats')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(HakariSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.insights_outlined,
                size: HakariSpacing.xxxl,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(height: HakariSpacing.lg),
              Text(
                'Statistics coming soon',
                style: text.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: HakariSpacing.sm),
              Text(
                'Trends and summaries of your measurements will appear here.',
                style: text.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
