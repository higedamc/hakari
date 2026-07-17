import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/providers.dart';
import '../../domain/services/workout_readiness.dart';

/// Today's workout-readiness estimate, or null when there is no usable
/// sleep data (card hides itself). Errors (no permission, no Health
/// Connect) also resolve to null — the card is strictly best-effort.
///
/// Side effect: every read persists the fetched days into the wellness
/// repository (fill-missing merge), so the history accumulates in
/// Hakari beyond Health Connect's retention and can be backed up.
// autoDispose: re-reads after navigating away and back, so the card
// appears right after permissions are granted in Settings.
final readinessProvider = FutureProvider.autoDispose<ReadinessResult?>((
  ref,
) async {
  try {
    final health = ref.read(healthServiceProvider);
    if (!await health.isAvailable()) return null;
    final fetched = await health.readWellness(8);

    final repo = ref.read(wellnessRepositoryProvider);
    for (final day in fetched) {
      if (day.sleepHours == null && day.activeEnergyKcal == null) continue;
      await repo.upsertDay(day);
    }

    // Score from the stored history so days Health Connect has already
    // dropped still count.
    final now = DateTime.now();
    final history = await repo.getRange(
      now.subtract(const Duration(days: 7)),
      now,
    );
    return computeReadiness(history.isEmpty ? fetched : history);
  } catch (_) {
    return null;
  }
});
