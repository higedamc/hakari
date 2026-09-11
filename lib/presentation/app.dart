import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/entities/app_settings.dart';
import 'providers/nostr_sync_provider.dart';
import 'providers/settings_provider.dart';
import 'screens/onboarding_screen.dart';
import 'screens/root_shell.dart';
import 'theme/hakari_theme.dart';
import 'widgets/app_messenger.dart';

/// Root widget. main.dart wraps this in a [ProviderScope] whose overrides
/// supply the concrete repository / service implementations.
class HakariApp extends ConsumerWidget {
  const HakariApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Surface Nostr sync results app-wide as SnackBars.
    ref.listen<SyncStatus>(nostrSyncProvider, (previous, next) {
      if ((next.phase == SyncPhase.success || next.phase == SyncPhase.error) &&
          next.message != null) {
        showAppSnackBar(next.message!);
      }
    });

    return MaterialApp(
      title: 'Hakari',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: appMessengerKey,
      theme: HakariTheme.light(),
      darkTheme: HakariTheme.dark(),
      home: const _RootGate(),
    );
  }
}

/// Routes first launches into onboarding, everyone else into the tab shell.
///
/// Users who logged in before this flag existed skip onboarding via the
/// signer check. A storage error falls through to the shell so the app stays
/// usable.
class _RootGate extends ConsumerWidget {
  const _RootGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final child = switch (settings) {
      AsyncData(:final value)
          when !value.onboardingComplete &&
              value.signerMode == SignerMode.none =>
        const OnboardingScreen(),
      AsyncLoading() => const Scaffold(body: SizedBox.shrink()),
      _ => const RootShell(),
    };
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: child,
    );
  }
}
