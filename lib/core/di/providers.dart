import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/repositories/settings_repository.dart';
import '../../domain/repositories/weight_repository.dart';
import '../../domain/repositories/wellness_repository.dart';
import '../../domain/services/export_service.dart';
import '../../domain/services/health_planet_service.dart';
import '../../domain/services/health_service.dart';
import '../../domain/services/nostr_service.dart';
import '../../domain/services/scale_service.dart';
import '../../domain/services/signer_service.dart';

/// DI seams. All are overridden in main.dart with concrete
/// implementations (Phase 4); presentation code depends only on these.
final weightRepositoryProvider = Provider<WeightRepository>(
  (ref) => throw UnimplementedError('override in main'),
);

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => throw UnimplementedError('override in main'),
);

final scaleServiceProvider = Provider<ScaleService>(
  (ref) => throw UnimplementedError('override in main'),
);

final healthServiceProvider = Provider<HealthService>(
  (ref) => throw UnimplementedError('override in main'),
);

final nostrServiceProvider = Provider<NostrService>(
  (ref) => throw UnimplementedError('override in main'),
);

final signerServiceProvider = Provider<SignerService>(
  (ref) => throw UnimplementedError('override in main'),
);

final exportServiceProvider = Provider<ExportService>(
  (ref) => throw UnimplementedError('override in main'),
);

final healthPlanetServiceProvider = Provider<HealthPlanetService>(
  (ref) => throw UnimplementedError('override in main'),
);

final wellnessRepositoryProvider = Provider<WellnessRepository>(
  (ref) => throw UnimplementedError('override in main'),
);
