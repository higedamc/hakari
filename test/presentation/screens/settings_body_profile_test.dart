import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hakari/core/di/providers.dart';
import 'package:hakari/domain/entities/app_settings.dart';
import 'package:hakari/domain/entities/weight_entry.dart';
import 'package:hakari/presentation/screens/settings_screen.dart';
import 'package:hakari/presentation/theme/hakari_theme.dart';

import '../screen_fakes.dart';

/// Records every save so a test can tell "the controller persisted X"
/// apart from "the row happens to display X".
class RecordingSettingsRepository extends FakeSettingsRepository {
  RecordingSettingsRepository(super.settings);
  final saved = <AppSettings>[];

  @override
  Future<void> save(AppSettings settings) async => saved.add(settings);
}

/// A linked Health Planet account whose import returns no entries but
/// reports a profile height, which is all the adoption path needs.
class LinkedHealthPlanetService extends FakeHealthPlanetService {
  LinkedHealthPlanetService({required this.heightCm});
  final double? heightCm;
  var fetches = 0;

  @override
  Future<bool> isLinked() async => true;

  @override
  Future<List<WeightEntry>> fetchEntries(DateTime from, DateTime to) async {
    fetches++;
    return const [];
  }

  @override
  double? get lastFetchedHeightCm => fetches == 0 ? null : heightCm;
}

void main() {
  late RecordingSettingsRepository repo;
  late LinkedHealthPlanetService healthPlanet;

  Future<void> pumpSettings(
    WidgetTester tester, {
    AppSettings settings = const AppSettings(),
    double? fetchedHeightCm,
    Brightness brightness = Brightness.light,
  }) async {
    tester.view.physicalSize = const Size(400, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    repo = RecordingSettingsRepository(settings);
    healthPlanet = LinkedHealthPlanetService(heightCm: fetchedHeightCm);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          weightRepositoryProvider.overrideWithValue(
            FakeWeightRepository(const []),
          ),
          settingsRepositoryProvider.overrideWithValue(repo),
          healthServiceProvider.overrideWithValue(FakeHealthService()),
          nostrServiceProvider.overrideWithValue(FakeNostrService()),
          healthPlanetServiceProvider.overrideWithValue(healthPlanet),
          scaleServiceProvider.overrideWithValue(FakeScaleService()),
        ],
        child: MaterialApp(
          theme: HakariTheme.light(),
          darkTheme: HakariTheme.dark(),
          themeMode: brightness == Brightness.dark
              ? ThemeMode.dark
              : ThemeMode.light,
          home: const SettingsScreen(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> submitDialog(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
  }

  Future<void> importFromHealthPlanet(WidgetTester tester) async {
    final row = find.text('Import from Health Planet (90 days)');
    await tester.scrollUntilVisible(
      row,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    await tester.tap(row);
    await tester.pump(const Duration(milliseconds: 300));
  }

  for (final brightness in Brightness.values) {
    group('Body profile ($brightness)', () {
      testWidgets('both rows render unset with an invitation', (tester) async {
        await pumpSettings(tester, brightness: brightness);
        expect(tester.takeException(), isNull);
        expect(find.text('Height'), findsOneWidget);
        expect(find.text('Goal weight'), findsOneWidget);
        expect(find.textContaining('Not set.'), findsNWidgets(2));
        expect(find.byTooltip('Clear height'), findsNothing);
        expect(find.byTooltip('Clear goal weight'), findsNothing);
      });

      testWidgets('a valid height is persisted and shown', (tester) async {
        await pumpSettings(tester, brightness: brightness);
        await tester.tap(find.text('Height'));
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byType(AlertDialog), findsOneWidget);
        await submitDialog(tester, '175.5');

        expect(find.byType(AlertDialog), findsNothing);
        expect(repo.saved.last.heightCm, 175.5);
        expect(find.textContaining('175.5 cm.'), findsOneWidget);
        expect(find.byTooltip('Clear height'), findsOneWidget);
      });

      testWidgets('an out-of-range height shows an error and is not saved', (
        tester,
      ) async {
        await pumpSettings(tester, brightness: brightness);
        await tester.tap(find.text('Height'));
        await tester.pump(const Duration(milliseconds: 300));
        await submitDialog(tester, '30');

        expect(find.byType(AlertDialog), findsOneWidget);
        expect(
          find.text('Enter a value between 50 and 250 cm'),
          findsOneWidget,
        );
        expect(repo.saved, isEmpty);

        await submitDialog(tester, 'abc');
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(repo.saved, isEmpty);
      });
    });
  }

  group('Body profile', () {
    testWidgets('clearing a stored height resets it to null', (tester) async {
      await pumpSettings(tester, settings: const AppSettings(heightCm: 180));
      expect(find.textContaining('180 cm.'), findsOneWidget);
      await tester.tap(find.byTooltip('Clear height'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(repo.saved.last.heightCm, isNull);
      expect(find.textContaining('180 cm.'), findsNothing);
      expect(find.byTooltip('Clear height'), findsNothing);
    });

    testWidgets('goal weight validates, persists and clears', (tester) async {
      await pumpSettings(tester);
      await tester.tap(find.text('Goal weight'));
      await tester.pump(const Duration(milliseconds: 300));
      await submitDialog(tester, '0.5');
      expect(find.text('Enter a value between 1 and 500 kg'), findsOneWidget);
      expect(repo.saved, isEmpty);

      await submitDialog(tester, '72');
      expect(find.byType(AlertDialog), findsNothing);
      expect(repo.saved.last.goalWeightKg, 72);
      expect(find.textContaining('72 kg.'), findsOneWidget);

      await tester.tap(find.byTooltip('Clear goal weight'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(repo.saved.last.goalWeightKg, isNull);
    });

    testWidgets('a Health Planet import fills an empty height', (tester) async {
      await pumpSettings(tester, fetchedHeightCm: 170);
      await importFromHealthPlanet(tester);

      expect(healthPlanet.fetches, 1);
      expect(repo.saved.last.heightCm, 170);
      await tester.scrollUntilVisible(
        find.text('Height'),
        -200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.textContaining('170 cm.'), findsOneWidget);
    });

    testWidgets('a Health Planet import leaves a typed height untouched', (
      tester,
    ) async {
      await pumpSettings(
        tester,
        settings: const AppSettings(heightCm: 180),
        fetchedHeightCm: 170,
      );
      await importFromHealthPlanet(tester);

      expect(healthPlanet.fetches, 1);
      expect(repo.saved, isEmpty);
      await tester.scrollUntilVisible(
        find.text('Height'),
        -200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.textContaining('180 cm.'), findsOneWidget);
    });

    testWidgets('an import without a height leaves the slot empty', (
      tester,
    ) async {
      await pumpSettings(tester, fetchedHeightCm: null);
      await importFromHealthPlanet(tester);
      expect(healthPlanet.fetches, 1);
      expect(repo.saved, isEmpty);
    });
  });
}
