import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hakari/core/di/providers.dart';
import 'package:hakari/domain/entities/app_settings.dart';
import 'package:hakari/domain/entities/weight_entry.dart';
import 'package:hakari/domain/repositories/settings_repository.dart';
import 'package:hakari/domain/repositories/weight_repository.dart';
import 'package:hakari/domain/services/health_planet_service.dart';
import 'package:hakari/domain/services/health_service.dart';
import 'package:hakari/domain/services/nostr_service.dart';
import 'package:hakari/domain/services/scale_service.dart';
import 'package:hakari/presentation/screens/add_entry_sheet.dart';
import 'package:hakari/presentation/screens/home_screen.dart';
import 'package:hakari/presentation/screens/onboarding_screen.dart';
import 'package:hakari/presentation/screens/scale_screen.dart';
import 'package:hakari/presentation/screens/settings_screen.dart';
import 'package:hakari/presentation/theme/hakari_theme.dart';

/// Phase 0 acceptance: every existing screen still builds and lays out
/// under the extracted theme, in both brightnesses, without throwing.
///
/// Fakes implement only what the screens touch at build / init time; any
/// other call surfaces as an [UnimplementedError] so the test fails loudly
/// instead of silently rendering less than the real app.
void main() {
  final sample = [
    WeightEntry(
      id: 'a',
      recordedAt: DateTime(2026, 9, 1, 8),
      weightKg: 72.4,
      bodyFatPercent: 18.1,
      source: MeasurementSource.manual,
    ),
    WeightEntry(
      id: 'b',
      recordedAt: DateTime(2026, 9, 5, 8),
      weightKg: 71.9,
      source: MeasurementSource.bleScale,
    ),
    WeightEntry(
      id: 'c',
      recordedAt: DateTime(2026, 9, 10, 8),
      weightKg: 71.2,
      bodyFatPercent: 17.6,
      source: MeasurementSource.manual,
    ),
  ];

  Widget host(
    Widget home,
    Brightness brightness, {
    List<WeightEntry>? entries,
  }) => ProviderScope(
    overrides: [
      weightRepositoryProvider.overrideWithValue(
        _FakeWeightRepository(entries ?? sample),
      ),
      settingsRepositoryProvider.overrideWithValue(_FakeSettingsRepository()),
      healthServiceProvider.overrideWithValue(_FakeHealthService()),
      nostrServiceProvider.overrideWithValue(_FakeNostrService()),
      healthPlanetServiceProvider.overrideWithValue(_FakeHealthPlanetService()),
      scaleServiceProvider.overrideWithValue(_FakeScaleService()),
    ],
    child: MaterialApp(
      theme: HakariTheme.light(),
      darkTheme: HakariTheme.dark(),
      themeMode: brightness == Brightness.dark
          ? ThemeMode.dark
          : ThemeMode.light,
      home: home,
    ),
  );

  for (final brightness in Brightness.values) {
    group('renders in ${brightness.name}', () {
      testWidgets('HomeScreen with entries', (tester) async {
        await tester.pumpWidget(host(const HomeScreen(), brightness));
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull);
        expect(find.text('Hakari'), findsOneWidget);
        expect(find.text('Weight trend'), findsOneWidget);
        expect(find.byType(Card), findsWidgets);
        expect(find.byType(FloatingActionButton), findsNWidgets(2));
      });

      testWidgets('HomeScreen empty state', (tester) async {
        await tester.pumpWidget(
          host(const HomeScreen(), brightness, entries: const []),
        );
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull);
        expect(find.text('No measurements yet'), findsOneWidget);
      });

      testWidgets('SettingsScreen', (tester) async {
        await tester.pumpWidget(host(const SettingsScreen(), brightness));
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull);
        expect(find.byType(ListTile), findsWidgets);
        expect(find.byType(SwitchListTile), findsWidgets);
      });

      testWidgets('AddEntrySheet body', (tester) async {
        await tester.pumpWidget(
          host(const Scaffold(body: AddEntrySheet()), brightness),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.byType(TextFormField), findsWidgets);
        expect(find.byType(FilledButton), findsWidgets);
      });

      testWidgets('OnboardingScreen', (tester) async {
        await tester.pumpWidget(host(const OnboardingScreen(), brightness));
        await tester.pump();
        expect(tester.takeException(), isNull);
        // Welcome splash auto-advances; let it settle before teardown.
        await tester.pump(const Duration(seconds: 3));
        expect(tester.takeException(), isNull);
      });

      testWidgets('ScaleScreen', (tester) async {
        await tester.pumpWidget(host(const ScaleScreen(), brightness));
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull);
      });
    });
  }
}

// ---------------------------------------------------------------------------
// Fakes: explicit for what the screens call, loud for everything else.

class _FakeWeightRepository implements WeightRepository {
  _FakeWeightRepository(this.entries);
  final List<WeightEntry> entries;

  @override
  Future<List<WeightEntry>> getAll() async => entries;

  @override
  Stream<List<WeightEntry>> watchAll() => Stream.value(entries);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _FakeSettingsRepository implements SettingsRepository {
  @override
  Future<AppSettings> load() async => const AppSettings();

  @override
  Stream<AppSettings> watch() => Stream.value(const AppSettings());

  @override
  Future<void> save(AppSettings settings) async {}
}

class _FakeHealthService implements HealthService {
  @override
  Future<bool> isAvailable() async => false;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _FakeNostrService implements NostrService {
  @override
  Future<List<RelayStatus>> relayStatuses() async => const [
    RelayStatus('wss://relay.example', RelayState.connected),
    RelayStatus('wss://relay2.example', RelayState.disconnected),
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _FakeHealthPlanetService implements HealthPlanetService {
  @override
  Future<bool> isLinked() async => false;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _FakeScaleService implements ScaleService {
  final _state = StreamController<ScaleConnectionState>.broadcast();

  @override
  Stream<ScaleConnectionState> get connectionState => _state.stream;

  @override
  Stream<DiscoveredScale> scan({Duration? timeout}) => const Stream.empty();

  @override
  Future<void> stopScan() async {}

  @override
  Future<void> disconnect() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}
