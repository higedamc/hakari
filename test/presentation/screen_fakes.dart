import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hakari/core/di/providers.dart';
import 'package:hakari/domain/entities/app_settings.dart';
import 'package:hakari/domain/entities/weight_entry.dart';
import 'package:hakari/domain/repositories/settings_repository.dart';
import 'package:hakari/domain/repositories/weight_repository.dart';
import 'package:hakari/domain/services/health_planet_service.dart';
import 'package:hakari/domain/services/health_service.dart';
import 'package:hakari/domain/services/nostr_service.dart';
import 'package:hakari/domain/services/scale_service.dart';
import 'package:hakari/presentation/theme/hakari_theme.dart';

/// Test doubles shared by presentation-layer widget tests.
///
/// Fakes implement only what the screens touch at build / init time; any
/// other call surfaces as an [UnimplementedError] so a test fails loudly
/// instead of silently rendering less than the real app.

/// Wraps [child] in a [ProviderScope] whose overrides let every screen build
/// without real I/O.
Widget scopedForScreens(
  Widget child, {
  List<WeightEntry> entries = const [],
  AppSettings settings = const AppSettings(),
}) => ProviderScope(
  overrides: [
    weightRepositoryProvider.overrideWithValue(FakeWeightRepository(entries)),
    settingsRepositoryProvider.overrideWithValue(
      FakeSettingsRepository(settings),
    ),
    healthServiceProvider.overrideWithValue(FakeHealthService()),
    nostrServiceProvider.overrideWithValue(FakeNostrService()),
    healthPlanetServiceProvider.overrideWithValue(FakeHealthPlanetService()),
    scaleServiceProvider.overrideWithValue(FakeScaleService()),
  ],
  child: child,
);

/// [home] inside a themed [MaterialApp], scoped with [scopedForScreens].
Widget screenHost(
  Widget home,
  Brightness brightness, {
  List<WeightEntry> entries = const [],
  AppSettings settings = const AppSettings(),
}) => scopedForScreens(
  MaterialApp(
    theme: HakariTheme.light(),
    darkTheme: HakariTheme.dark(),
    themeMode: brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
    home: home,
  ),
  entries: entries,
  settings: settings,
);

class FakeWeightRepository implements WeightRepository {
  FakeWeightRepository(this.entries);
  final List<WeightEntry> entries;

  @override
  Future<List<WeightEntry>> getAll() async => entries;

  @override
  Stream<List<WeightEntry>> watchAll() => Stream.value(entries);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class FakeSettingsRepository implements SettingsRepository {
  FakeSettingsRepository([this.settings = const AppSettings()]);
  final AppSettings settings;

  @override
  Future<AppSettings> load() async => settings;

  @override
  Stream<AppSettings> watch() => Stream.value(settings);

  @override
  Future<void> save(AppSettings settings) async {}
}

class FakeHealthService implements HealthService {
  @override
  Future<bool> isAvailable() async => false;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class FakeNostrService implements NostrService {
  @override
  Future<List<RelayStatus>> relayStatuses() async => const [
    RelayStatus('wss://relay.example', RelayState.connected),
    RelayStatus('wss://relay2.example', RelayState.disconnected),
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class FakeHealthPlanetService implements HealthPlanetService {
  @override
  Future<bool> isLinked() async => false;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class FakeScaleService implements ScaleService {
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
