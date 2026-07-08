import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/services/workout_readiness.dart';
import '../providers/wellness_provider.dart';

/// Home-screen card with today's workout readiness and estimated diet
/// (fat-loss) efficiency, derived from Health Connect sleep + active
/// energy. Renders nothing while loading or when there is no data.
class WellnessCard extends ConsumerWidget {
  const WellnessCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final readiness = ref.watch(readinessProvider).valueOrNull;
    if (readiness == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 56,
                  height: 56,
                  child: Stack(
                    fit: StackFit.expand,
                    alignment: Alignment.center,
                    children: [
                      CircularProgressIndicator(
                        value: readiness.readinessPercent / 100,
                        strokeWidth: 5,
                        backgroundColor: scheme.surfaceContainerHighest,
                      ),
                      Center(
                        child: Text(
                          '${readiness.readinessPercent}',
                          style: text.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(readiness.headline, style: text.titleMedium),
                      const SizedBox(height: 2),
                      Text(
                        'Workout readiness today',
                        style: text.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.info_outline, size: 20),
                  tooltip: 'How this is calculated',
                  onPressed: () => _showInfo(context, readiness),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Est. fat-loss efficiency '
                        '${readiness.dietEfficiencyPercent}%',
                        style: text.bodyMedium,
                      ),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: readiness.dietEfficiencyPercent / 100,
                          minHeight: 6,
                          backgroundColor: scheme.surfaceContainerHighest,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (readiness.reasons.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                readiness.reasons.first,
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showInfo(BuildContext context, ReadinessResult readiness) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('About these scores'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Workout readiness combines last night\'s sleep, your '
                '7-day sleep pattern and yesterday\'s activity load from '
                'Health Connect.\n\n'
                'Fat-loss efficiency estimates how much of a caloric '
                'deficit is lost as fat rather than lean mass at your '
                'current sleep pattern, interpolating the sleep-'
                'restriction findings of Nedeltcheva et al. 2010 '
                '(Annals of Internal Medicine): ~55% at 8.5h of sleep '
                'vs ~25% at 5.5h.\n\n'
                'These are transparent heuristics for motivation, not '
                'medical advice.',
              ),
              const SizedBox(height: 12),
              for (final reason in readiness.reasons)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('• $reason'),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
