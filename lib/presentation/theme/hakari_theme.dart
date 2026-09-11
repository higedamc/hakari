import 'package:flutter/material.dart';

import 'hakari_tokens.dart';

/// Builds the app [ThemeData] for one [Brightness].
///
/// Everything visual that can live in a component theme lives here, so
/// screens compose stock Material widgets and inherit the look. Values come
/// from `hakari_tokens.dart`; do not add literals in this file that are not
/// already a token.
///
/// `NavigationBarTheme` is configured even though no screen uses a
/// `NavigationBar` yet. Bottom navigation is a structure change that is
/// decided separately; when it lands, it inherits this theme unchanged.
abstract final class HakariTheme {
  /// Seed colour. Kept from the original theme so dynamic-colour work later
  /// only has to replace this one value.
  static const Color seed = Colors.teal;

  static ThemeData light() => build(Brightness.light);
  static ThemeData dark() => build(Brightness.dark);

  static ThemeData build(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
    );
    final chart = HakariChartColors.fromScheme(scheme);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: HakariSurfaces.page(scheme),
      extensions: <ThemeExtension<dynamic>>[chart],

      appBarTheme: AppBarTheme(
        backgroundColor: HakariSurfaces.page(scheme),
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),

      cardTheme: CardThemeData(
        elevation: 0,
        color: HakariSurfaces.card(scheme),
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: HakariRadii.cardShape,
      ),

      listTileTheme: ListTileThemeData(
        shape: HakariRadii.tileShape,
        iconColor: scheme.onSurfaceVariant,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: HakariSpacing.lg,
        ),
      ),

      navigationBarTheme: NavigationBarThemeData(
        elevation: 0,
        height: HakariSizes.navBarHeight,
        backgroundColor: HakariSurfaces.bar(scheme),
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.secondaryContainer,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),

      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        backgroundColor: scheme.primaryContainer,
        foregroundColor: scheme.onPrimaryContainer,
        shape: HakariRadii.tileShape,
        extendedPadding: const EdgeInsets.symmetric(
          horizontal: HakariSpacing.xl,
        ),
        extendedIconLabelSpacing: HakariSpacing.md,
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: HakariRadii.pillShape,
          minimumSize: const Size(0, HakariSizes.buttonHeight),
          padding: const EdgeInsets.symmetric(horizontal: HakariSpacing.xl),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: HakariRadii.pillShape,
          minimumSize: const Size(0, HakariSizes.buttonHeight),
          padding: const EdgeInsets.symmetric(horizontal: HakariSpacing.xl),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(shape: HakariRadii.pillShape),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(shape: HakariRadii.pillShape),
      ),

      chipTheme: ChipThemeData(
        shape: HakariRadii.chipShape,
        side: BorderSide.none,
        backgroundColor: HakariSurfaces.nested(scheme),
        labelPadding: const EdgeInsets.symmetric(horizontal: HakariSpacing.xs),
      ),

      inputDecorationTheme: InputDecorationTheme(
        border: const OutlineInputBorder(borderRadius: HakariRadii.fieldBorder),
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: HakariSurfaces.sheet(scheme),
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: HakariSurfaces.sheet(scheme),
        shape: HakariRadii.sheetShape,
        clipBehavior: Clip.antiAlias,
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: HakariSurfaces.raised(scheme),
        surfaceTintColor: Colors.transparent,
        shape: HakariRadii.dialogShape,
      ),

      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        space: HakariSpacing.lg,
      ),

      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
