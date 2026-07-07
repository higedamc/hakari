import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers/nostr_sync_provider.dart';
import 'screens/home_screen.dart';
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
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      home: const HomeScreen(),
    );
  }

  ThemeData _buildTheme(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: Colors.teal,
      brightness: brightness,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLow,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
