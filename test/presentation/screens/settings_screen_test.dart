import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hakari/domain/entities/app_settings.dart';
import 'package:hakari/presentation/screens/settings_screen.dart';
import 'package:hakari/presentation/widgets/section_header.dart';

import '../screen_fakes.dart';

/// ui-settings acceptance, light and dark: every group renders as a card
/// under its header, the logged-in / logged-out identity rows, the empty
/// relay list, and two switches that must still reach the controller.
void main() {
  const groups = [
    'Identity',
    'Relays',
    'Privacy',
    'Publishing',
    'TANITA Health Planet',
    'Export',
  ];

  Future<void> pumpSettings(
    WidgetTester tester,
    Brightness brightness, {
    AppSettings settings = const AppSettings(),
  }) async {
    // Phone-sized surface so the cards lay out at a realistic width.
    tester.view.physicalSize = const Size(400, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      screenHost(const SettingsScreen(), brightness, settings: settings),
    );
    await tester.pump(const Duration(milliseconds: 300));
  }

  for (final brightness in Brightness.values) {
    group('SettingsScreen ($brightness)', () {
      testWidgets('renders every group as a header over a card', (
        tester,
      ) async {
        await pumpSettings(tester, brightness);
        expect(tester.takeException(), isNull);

        // A plain ListView builds children lazily, so each group is
        // scrolled into view before it is asserted on.
        final list = find.byType(Scrollable).first;
        for (final title in groups) {
          await tester.scrollUntilVisible(
            find.text(title),
            200,
            scrollable: list,
          );
          expect(
            find.descendant(
              of: find.byType(SectionHeader),
              matching: find.text(title),
            ),
            findsOneWidget,
            reason: 'header "$title"',
          );
          expect(tester.takeException(), isNull, reason: 'group "$title"');
        }
        // Every built row lives inside a card, none directly on the page.
        final tiles = find.byType(ListTile).evaluate().toList();
        expect(tiles, isNotEmpty);
        for (final tile in tiles) {
          expect(
            find.ancestor(
              of: find.byWidget(tile.widget),
              matching: find.byType(Card),
            ),
            findsOneWidget,
          );
        }
      });

      testWidgets('logged out shows the Amber login action', (tester) async {
        await pumpSettings(tester, brightness);
        expect(find.text('Not logged in'), findsOneWidget);
        expect(
          find.widgetWithText(FilledButton, 'Login with Amber'),
          findsOneWidget,
        );
        expect(find.text('Log out'), findsNothing);
      });

      testWidgets('logged in shows the truncated key and log out', (
        tester,
      ) async {
        const pubkey =
            'abcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcd';
        await pumpSettings(
          tester,
          brightness,
          settings: const AppSettings(
            pubkeyHex: pubkey,
            signerMode: SignerMode.amber,
          ),
        );
        expect(find.text('abcdefabcd...abcdefabcd'), findsOneWidget);
        expect(find.text('Signing with Amber'), findsOneWidget);
        expect(find.widgetWithText(TextButton, 'Log out'), findsOneWidget);
        expect(find.text('Login with Amber'), findsNothing);
      });

      testWidgets('lists every relay with a remove action', (tester) async {
        await pumpSettings(tester, brightness);
        for (final relay in AppSettings.defaultRelays) {
          expect(find.text(relay), findsOneWidget);
        }
        expect(
          find.byTooltip('Remove relay'),
          findsNWidgets(AppSettings.defaultRelays.length),
        );
        expect(find.text('No relays configured'), findsNothing);
      });

      testWidgets('empty relay list shows the empty state', (tester) async {
        await pumpSettings(
          tester,
          brightness,
          settings: const AppSettings(relays: []),
        );
        expect(find.text('No relays configured'), findsOneWidget);
        expect(find.byTooltip('Remove relay'), findsNothing);
        expect(find.widgetWithText(FilledButton, 'Add relay'), findsOneWidget);
        expect(
          find.widgetWithText(OutlinedButton, 'Reset to defaults'),
          findsOneWidget,
        );
      });

      testWidgets('encrypt switch still reaches the controller', (
        tester,
      ) async {
        await pumpSettings(tester, brightness);
        SwitchListTile encrypt() => tester.widget<SwitchListTile>(
          find.widgetWithText(SwitchListTile, 'Encrypt health data (NIP-44)'),
        );
        expect(encrypt().value, isTrue);
        await tester.tap(find.text('Encrypt health data (NIP-44)'));
        await tester.pump(const Duration(milliseconds: 300));
        expect(encrypt().value, isFalse);
      });

      testWidgets('Orbot switch reveals the proxy field', (tester) async {
        await pumpSettings(tester, brightness);
        expect(find.text('SOCKS5 proxy URL'), findsNothing);
        await tester.tap(find.text('Route through Orbot (SOCKS5)'));
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull);
        expect(find.text('SOCKS5 proxy URL'), findsOneWidget);
        expect(
          tester
              .widget<SwitchListTile>(
                find.widgetWithText(
                  SwitchListTile,
                  'Route through Orbot (SOCKS5)',
                ),
              )
              .value,
          isTrue,
        );
      });

      testWidgets('export rows are tiles inside the Export card', (
        tester,
      ) async {
        await pumpSettings(tester, brightness);
        await tester.scrollUntilVisible(
          find.text('Export JSON'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.widgetWithText(ListTile, 'Export CSV'), findsOneWidget);
        expect(find.widgetWithText(ListTile, 'Export JSON'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    });
  }
}
