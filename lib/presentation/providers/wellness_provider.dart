import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/providers.dart';
import '../../domain/services/workout_readiness.dart';

/// Today's workout-readiness estimate, or null when there is no usable
/// sleep data (card hides itself). Errors (no permission, no Health
/// Connect) also resolve to null — the card is strictly best-effort.
// autoDispose: re-reads after navigating away and back, so the card
// appears right after permissions are granted in Settings.
final readinessProvider = FutureProvider.autoDispose<ReadinessResult?>((
  ref,
) async {
  try {
    final health = ref.read(healthServiceProvider);
    if (!await health.isAvailable()) return null;
    final history = await health.readWellness(8);
    return computeReadiness(history);
  } catch (_) {
    return null;
  }
});
