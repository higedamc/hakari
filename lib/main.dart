import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'core/di/providers.dart';
import 'core/di/switching_signer_service.dart';
import 'data/ble/blue_plus_scale_service.dart';
import 'data/export/file_export_service.dart';
import 'data/health/health_kit_connect_service.dart';
import 'data/local/hive_settings_repository.dart';
import 'data/local/hive_weight_repository.dart';
import 'data/nostr/local_key_signer_service.dart';
import 'data/nostr/nsec_store.dart';
import 'data/nostr/rust_nostr_service.dart';
import 'data/signer/amber_signer_service.dart';
import 'domain/entities/app_settings.dart';
import 'presentation/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Hive.initFlutter();
  final weightBox = await HiveWeightRepository.openBox();
  final settingsBox = await HiveSettingsRepository.openBox();

  await RustNostrService.initRustLib();

  final weightRepository = HiveWeightRepository(weightBox);
  final settingsRepository = HiveSettingsRepository(settingsBox);

  final nsecStore = NsecStore();
  final signerService = SwitchingSignerService(
    settingsRepository,
    localSigner: LocalKeySignerService(nsecStore),
    amberSigner: const AmberSignerService(),
  );
  final nostrService = RustNostrService(
    signer: signerService,
    nsecStore: nsecStore,
  );

  // Best-effort relay client startup; a first launch with SignerMode.none
  // is a no-op and failures surface later through the UI actions.
  try {
    final settings = await settingsRepository.load();
    if (settings.signerMode != SignerMode.none) {
      await nostrService.initialize(settings);
    }
  } catch (_) {
    // Non-fatal: relays can be (re)connected from the settings screen.
  }

  runApp(
    ProviderScope(
      overrides: [
        weightRepositoryProvider.overrideWithValue(weightRepository),
        settingsRepositoryProvider.overrideWithValue(settingsRepository),
        scaleServiceProvider.overrideWithValue(BluePlusScaleService()),
        healthServiceProvider.overrideWithValue(HealthKitConnectService()),
        nostrServiceProvider.overrideWithValue(nostrService),
        signerServiceProvider.overrideWithValue(signerService),
        exportServiceProvider.overrideWithValue(FileExportService()),
      ],
      child: const HakariApp(),
    ),
  );
}
