import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/di/providers.dart';
import '../../domain/entities/weight_entry.dart';

/// Reactive list of all measurements, newest first (repository contract).
final entriesProvider = StreamProvider<List<WeightEntry>>(
  (ref) => ref.watch(weightRepositoryProvider).watchAll(),
);
