import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hakari/presentation/screens/home_screen.dart';
import 'package:hakari/presentation/screens/root_shell.dart';
import 'package:hakari/presentation/screens/settings_screen.dart';
import 'package:hakari/presentation/screens/stats_screen.dart';
import 'package:hakari/presentation/theme/hakari_tokens.dart';

import '../screen_fakes.dart';

/// Phase 0.5 acceptance: the tab shell reaches all three tabs, keeps tab
/// state across switches, and keeps every tab body above the bar.
void main() {
  Finder nestedScaffoldOf(Type tab) => find.descendant(
    of: find.byType(tab, skipOffstage: false),
    matching: find.byType(Scaffold, skipOffstage: false),
    skipOffstage: false,
  );

  for (final brightness in Brightness.values) {
    group(brightness.name, () {
      testWidgets('starts on Home and reaches every tab', (tester) async {
        await tester.pumpWidget(screenHost(const RootShell(), brightness));
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull);

        expect(find.byType(NavigationBar), findsOneWidget);
        expect(find.byType(NavigationDestination), findsNWidgets(3));
        expect(find.byType(HomeScreen), findsOneWidget);
        expect(find.text('Hakari'), findsOneWidget);

        await tester.tap(find.text('Stats'));
        await tester.pumpAndSettle();
        expect(find.byType(StatsScreen), findsOneWidget);
        expect(find.text('Statistics coming soon'), findsOneWidget);
        expect(find.byIcon(Icons.insights), findsOneWidget);

        await tester.tap(find.text('Settings'));
        await tester.pumpAndSettle();
        expect(find.byType(SettingsScreen), findsOneWidget);
        expect(find.widgetWithText(AppBar, 'Settings'), findsOneWidget);
        expect(find.byIcon(Icons.settings), findsOneWidget);

        await tester.tap(find.text('Home'));
        await tester.pumpAndSettle();
        expect(find.byType(HomeScreen), findsOneWidget);
        expect(find.byIcon(Icons.home), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('tabs stay mounted and keep state across switches', (
        tester,
      ) async {
        await tester.pumpWidget(screenHost(const RootShell(), brightness));
        await tester.pump(const Duration(milliseconds: 300));

        final homeBefore = tester.element(find.byType(HomeScreen));

        await tester.tap(find.text('Settings'));
        await tester.pumpAndSettle();
        final settingsState = tester.state(find.byType(SettingsScreen));

        // Home is offstage, not disposed.
        expect(find.byType(HomeScreen), findsNothing);
        expect(find.byType(HomeScreen, skipOffstage: false), findsOneWidget);
        expect(find.byType(IndexedStack), findsOneWidget);

        await tester.tap(find.text('Stats'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Settings'));
        await tester.pumpAndSettle();
        expect(
          identical(tester.state(find.byType(SettingsScreen)), settingsState),
          isTrue,
        );

        await tester.tap(find.text('Home'));
        await tester.pumpAndSettle();
        expect(
          identical(tester.element(find.byType(HomeScreen)), homeBefore),
          isTrue,
        );
      });

      testWidgets('system back from a secondary tab returns to Home; '
          'from Home it pops', (tester) async {
        await tester.pumpWidget(screenHost(const RootShell(), brightness));
        await tester.pump(const Duration(milliseconds: 300));

        for (final tab in ['Stats', 'Settings']) {
          await tester.tap(find.text(tab));
          await tester.pumpAndSettle();
          expect(find.byType(HomeScreen), findsNothing);

          final handled = await tester.binding.handlePopRoute();
          await tester.pumpAndSettle();
          expect(handled, isTrue, reason: 'back from $tab must be consumed');
          expect(find.byType(RootShell), findsOneWidget);
          expect(find.byType(HomeScreen), findsOneWidget);
          expect(find.byIcon(Icons.home), findsOneWidget);
        }

        // On Home the pop bubbles up to the system (app exit).
        final handled = await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(handled, isFalse, reason: 'back from Home must leave the app');
        expect(tester.takeException(), isNull);
      });

      testWidgets('body sits above the bar: extendBody false, no bottom '
          'inset', (tester) async {
        // 800px tall view with a 34px bottom safe area (iPhone home bar).
        tester.view.physicalSize = const Size(400, 800);
        tester.view.devicePixelRatio = 1;
        tester.view.padding = const FakeViewPadding(bottom: 34);
        addTearDown(tester.view.reset);

        await tester.pumpWidget(screenHost(const RootShell(), brightness));
        await tester.pump(const Duration(milliseconds: 300));

        final shellScaffold = tester.widget<Scaffold>(
          find
              .descendant(
                of: find.byType(RootShell),
                matching: find.byType(Scaffold),
              )
              .first,
        );
        expect(shellScaffold.extendBody, isFalse);

        final barTop = tester.getRect(find.byType(NavigationBar)).top;
        expect(barTop, lessThan(800));
        expect(
          800 - barTop,
          HakariSizes.navBarHeight + 34,
          reason: 'NavigationBar absorbs the safe area itself',
        );

        for (final tab in [HomeScreen, StatsScreen, SettingsScreen]) {
          final nested = nestedScaffoldOf(tab).first;
          expect(
            MediaQuery.paddingOf(tester.element(nested)).bottom,
            0,
            reason: '$tab must not see the bottom safe area',
          );
          expect(
            tester.getRect(nested).bottom,
            barTop,
            reason: '$tab body must end exactly where the bar starts',
          );
        }
      });
    });
  }

  testWidgets('initialIndex selects the starting tab', (tester) async {
    await tester.pumpWidget(
      screenHost(const RootShell(initialIndex: 2), Brightness.light),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
  });
}
