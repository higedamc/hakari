import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hakari/domain/entities/weight_entry.dart';
import 'package:hakari/presentation/screens/add_entry_sheet.dart';
import 'package:hakari/presentation/screens/home_screen.dart';
import 'package:hakari/presentation/screens/onboarding_screen.dart';
import 'package:hakari/presentation/screens/scale_screen.dart';
import 'package:hakari/presentation/screens/settings_screen.dart';

import '../screen_fakes.dart';

/// Phase 0 acceptance: every existing screen still builds and lays out
/// under the extracted theme, in both brightnesses, without throwing.
///
/// Fakes live in `test/presentation/screen_fakes.dart`.
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
  }) => screenHost(home, brightness, entries: entries ?? sample);

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
