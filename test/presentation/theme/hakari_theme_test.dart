import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hakari/presentation/theme/hakari_theme.dart';
import 'package:hakari/presentation/theme/hakari_tokens.dart';

/// Pins the Phase 0 design contract so other UI leaves can rely on it.
void main() {
  group('HakariTheme', () {
    for (final brightness in Brightness.values) {
      group(brightness.name, () {
        final theme = HakariTheme.build(brightness);
        final scheme = theme.colorScheme;

        test('uses Material 3 with the requested brightness', () {
          expect(theme.useMaterial3, isTrue);
          expect(scheme.brightness, brightness);
        });

        test('installs chart colours derived from the scheme', () {
          final chart = theme.extension<HakariChartColors>();
          expect(chart, isNotNull);
          expect(chart!.line, scheme.primary);
          expect(chart.secondaryLine, scheme.tertiary);
          expect(chart.fillBottom.a, 0);
        });

        test('cards are flat, tonal and use the card radius', () {
          final card = theme.cardTheme;
          expect(card.elevation, 0);
          expect(card.color, HakariSurfaces.card(scheme));
          expect(card.shape, HakariRadii.cardShape);
          expect(card.margin, EdgeInsets.zero);
        });

        test('sheets and dialogs use the token radii', () {
          expect(theme.bottomSheetTheme.shape, HakariRadii.sheetShape);
          expect(theme.dialogTheme.shape, HakariRadii.dialogShape);
        });

        test('navigation bar: tonal bar, pill indicator, labels always', () {
          final nav = theme.navigationBarTheme;
          expect(nav.elevation, 0);
          expect(nav.height, HakariSizes.navBarHeight);
          expect(nav.backgroundColor, HakariSurfaces.bar(scheme));
          expect(nav.indicatorColor, scheme.secondaryContainer);
          expect(nav.indicatorShape, HakariRadii.pillShape);
          expect(
            nav.labelBehavior,
            NavigationDestinationLabelBehavior.alwaysShow,
          );
        });

        test('navigation bar: selected vs unselected icon and label', () {
          final nav = theme.navigationBarTheme;
          const selected = {WidgetState.selected};
          const unselected = <WidgetState>{};

          final selIcon = nav.iconTheme!.resolve(selected)!;
          final unselIcon = nav.iconTheme!.resolve(unselected)!;
          expect(selIcon.color, scheme.onSecondaryContainer);
          expect(unselIcon.color, scheme.onSurfaceVariant);
          expect(selIcon.size, HakariSizes.navIconSize);
          expect(unselIcon.size, HakariSizes.navIconSize);

          final selLabel = nav.labelTextStyle!.resolve(selected)!;
          final unselLabel = nav.labelTextStyle!.resolve(unselected)!;
          expect(selLabel.color, scheme.onSurface);
          expect(selLabel.fontWeight, FontWeight.w600);
          expect(unselLabel.color, scheme.onSurfaceVariant);
          expect(unselLabel.fontSize, selLabel.fontSize);

          expect(
            nav.overlayColor!.resolve(const {WidgetState.pressed})!.a,
            greaterThan(0),
          );
          expect(nav.overlayColor!.resolve(unselected), Colors.transparent);
        });

        testWidgets('app bar changes its rendered colour once the body '
            'has scrolled under it', (tester) async {
          await tester.pumpWidget(
            MaterialApp(
              theme: theme,
              home: Scaffold(
                appBar: AppBar(title: const Text('Scroll')),
                body: ListView.builder(
                  itemCount: 100,
                  itemBuilder: (_, i) => ListTile(title: Text('Row $i')),
                ),
              ),
            ),
          );

          // The Material the AppBar paints itself with, not the theme
          // field: this is the colour on screen after the bar has resolved
          // its scrolled-under state.
          Color paintedBarColor() => tester
              .widget<Material>(
                find
                    .descendant(
                      of: find.byType(AppBar),
                      matching: find.byType(Material),
                    )
                    .first,
              )
              .color!;

          final atRest = paintedBarColor();
          expect(atRest, HakariSurfaces.page(scheme));

          await tester.drag(find.byType(ListView), const Offset(0, -400));
          await tester.pumpAndSettle();

          final scrolled = paintedBarColor();
          expect(scrolled, isNot(equals(atRest)));
          expect(scrolled, HakariSurfaces.bar(scheme));

          // Scrolling back to the top restores the page colour.
          await tester.drag(find.byType(ListView), const Offset(0, 400));
          await tester.pumpAndSettle();
          expect(paintedBarColor(), atRest);
        });

        testWidgets('a stock NavigationBar renders under the theme', (
          tester,
        ) async {
          var index = 0;
          await tester.pumpWidget(
            MaterialApp(
              theme: theme,
              home: StatefulBuilder(
                builder: (context, setState) => Scaffold(
                  bottomNavigationBar: NavigationBar(
                    selectedIndex: index,
                    onDestinationSelected: (i) => setState(() => index = i),
                    destinations: const [
                      NavigationDestination(
                        icon: Icon(Icons.home_outlined),
                        selectedIcon: Icon(Icons.home),
                        label: 'Home',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.insights_outlined),
                        selectedIcon: Icon(Icons.insights),
                        label: 'Stats',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.settings_outlined),
                        selectedIcon: Icon(Icons.settings),
                        label: 'Settings',
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
          // Labels are visible for every destination, not just the selected.
          expect(find.text('Home'), findsOneWidget);
          expect(find.text('Stats'), findsOneWidget);
          expect(find.text('Settings'), findsOneWidget);

          await tester.tap(find.text('Stats'));
          await tester.pumpAndSettle();
          expect(index, 1);
          expect(find.byIcon(Icons.insights), findsOneWidget);
          expect(find.byIcon(Icons.home_outlined), findsOneWidget);
        });

        test('extended FAB is tonal and rounded', () {
          final fab = theme.floatingActionButtonTheme;
          expect(fab.backgroundColor, scheme.primaryContainer);
          expect(fab.shape, HakariRadii.tileShape);
        });

        test('inputs use the field radius', () {
          final border = theme.inputDecorationTheme.border;
          expect(border, isA<OutlineInputBorder>());
          expect(
            (border! as OutlineInputBorder).borderRadius,
            HakariRadii.fieldBorder,
          );
        });
      });
    }

    test('light and dark share the seed and differ only by brightness', () {
      final light = HakariTheme.light();
      final dark = HakariTheme.dark();
      expect(light.colorScheme.brightness, Brightness.light);
      expect(dark.colorScheme.brightness, Brightness.dark);
      expect(light.cardTheme.shape, dark.cardTheme.shape);
    });
  });

  group('HakariChartColors', () {
    testWidgets('of(context) reads the installed extension', (tester) async {
      late HakariChartColors seen;
      await tester.pumpWidget(
        MaterialApp(
          theme: HakariTheme.light(),
          home: Builder(
            builder: (context) {
              seen = HakariChartColors.of(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(seen.line, HakariTheme.light().colorScheme.primary);
    });

    test('lerp at t=1 yields the other palette', () {
      final a = HakariChartColors.fromScheme(
        ColorScheme.fromSeed(seedColor: Colors.teal),
      );
      final b = HakariChartColors.fromScheme(
        ColorScheme.fromSeed(seedColor: Colors.deepOrange),
      );
      expect(a.lerp(b, 1).line, b.line);
      expect(a.lerp(b, 0).line, a.line);
    });
  });

  group('tokens', () {
    test('radii ladder is monotone from chip to sheet', () {
      expect(HakariRadii.chip, lessThan(HakariRadii.field));
      expect(HakariRadii.field, lessThan(HakariRadii.tile));
      expect(HakariRadii.tile, lessThan(HakariRadii.card));
      expect(HakariRadii.card, lessThan(HakariRadii.sheet));
      expect(HakariRadii.sheet, HakariRadii.dialog);
    });

    test('spacing scale sits on a 4-pt grid', () {
      for (final v in [
        HakariSpacing.xs,
        HakariSpacing.sm,
        HakariSpacing.md,
        HakariSpacing.lg,
        HakariSpacing.xl,
        HakariSpacing.xxl,
        HakariSpacing.xxxl,
        HakariSpacing.fabClearance,
      ]) {
        expect(v % 4, 0, reason: '$v is not on the 4-pt grid');
      }
    });
  });
}
