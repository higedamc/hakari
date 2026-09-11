/// Design tokens shared by every presentation-layer leaf.
///
/// This file is the **contract** between the UI leaves (home, settings,
/// entry, onboarding/scale). Screens and widgets read radii, spacing and
/// surface roles from here instead of hard-coding numbers, so the whole app
/// moves together when a value changes.
///
/// Usage:
///
/// ```dart
/// Padding(padding: const EdgeInsets.all(HakariSpacing.lg), ...)
/// ClipRRect(borderRadius: HakariRadii.cardBorder, ...)
/// Container(color: HakariSurfaces.nested(scheme), ...)
/// final chart = HakariChartColors.of(context);
/// ```
///
/// Rules of thumb:
/// * Prefer the component themes in `hakari_theme.dart` (Card, ListTile,
///   BottomSheet, FAB, ...) over styling by hand. Reach for these tokens only
///   when a widget has no component theme.
/// * Do not introduce new literal radii or paddings in screens. Add a token
///   here instead, in its own PR, if a genuinely new size is needed.
library;

import 'package:flutter/material.dart';

/// Corner radii in logical pixels.
///
/// Cards and list tiles are generously rounded; sheets and dialogs are
/// rounder still so layered surfaces read as a stack.
abstract final class HakariRadii {
  /// Cards on a page (chart card, wellness card, grouped settings cards).
  static const double card = 20;

  /// Standalone list tiles and rows inside a card.
  static const double tile = 16;

  /// Modal bottom sheets (top corners).
  static const double sheet = 28;

  /// Dialogs.
  static const double dialog = 28;

  /// Chips and small inline badges.
  static const double chip = 8;

  /// Text fields.
  static const double field = 12;

  /// Small inner elements (progress bars, inset thumbnails).
  static const double inner = 8;

  static const BorderRadius cardBorder = BorderRadius.all(
    Radius.circular(card),
  );
  static const BorderRadius tileBorder = BorderRadius.all(
    Radius.circular(tile),
  );
  static const BorderRadius sheetBorder = BorderRadius.vertical(
    top: Radius.circular(sheet),
  );
  static const BorderRadius dialogBorder = BorderRadius.all(
    Radius.circular(dialog),
  );
  static const BorderRadius chipBorder = BorderRadius.all(
    Radius.circular(chip),
  );
  static const BorderRadius fieldBorder = BorderRadius.all(
    Radius.circular(field),
  );
  static const BorderRadius innerBorder = BorderRadius.all(
    Radius.circular(inner),
  );

  static const OutlinedBorder cardShape = RoundedRectangleBorder(
    borderRadius: cardBorder,
  );
  static const OutlinedBorder tileShape = RoundedRectangleBorder(
    borderRadius: tileBorder,
  );
  static const OutlinedBorder sheetShape = RoundedRectangleBorder(
    borderRadius: sheetBorder,
  );
  static const OutlinedBorder dialogShape = RoundedRectangleBorder(
    borderRadius: dialogBorder,
  );
  static const OutlinedBorder chipShape = RoundedRectangleBorder(
    borderRadius: chipBorder,
  );

  /// Pill shape for buttons, segmented controls and status badges.
  static const OutlinedBorder pillShape = StadiumBorder();
}

/// Spacing scale in logical pixels (4-pt grid).
abstract final class HakariSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;

  /// Horizontal inset of page content from the screen edge.
  static const double page = lg;

  /// Inner padding of a card.
  static const double card = lg;

  /// Vertical gap between stacked cards / list rows.
  static const double listGap = md;

  /// Gap between a section header and its first item.
  static const double sectionGap = sm;

  /// Bottom padding on scrolling lists so the FAB never covers the last row.
  static const double fabClearance = 120;

  static const EdgeInsets pageInsets = EdgeInsets.symmetric(horizontal: page);
  static const EdgeInsets cardInsets = EdgeInsets.all(card);
  static const EdgeInsets listInsets = EdgeInsets.fromLTRB(
    page,
    lg,
    page,
    fabClearance,
  );
}

/// Fixed control sizes in logical pixels.
abstract final class HakariSizes {
  /// Minimum height of filled / outlined buttons (comfortable touch target).
  static const double buttonHeight = 48;

  /// Height of the Material 3 [NavigationBar].
  static const double navBarHeight = 80;
}

/// Tonal surface ladder.
///
/// Material 3 layers surfaces by tone rather than by shadow. Each level here
/// names a *role*; call it with the current [ColorScheme] so light and dark
/// resolve correctly. Levels only go up as content nests deeper:
///
/// | role      | scheme slot                 | used for                        |
/// |-----------|-----------------------------|---------------------------------|
/// | page      | surface                     | Scaffold background             |
/// | bar       | surfaceContainer            | NavigationBar / bottom app bar  |
/// | card      | surfaceContainerLow         | cards sitting on the page       |
/// | sheet     | surfaceContainerLow         | modal bottom sheets             |
/// | raised    | surfaceContainerHigh        | dialogs, menus, popovers        |
/// | nested    | surfaceContainerHighest     | chips / insets inside a card    |
abstract final class HakariSurfaces {
  static Color page(ColorScheme s) => s.surface;
  static Color bar(ColorScheme s) => s.surfaceContainer;
  static Color card(ColorScheme s) => s.surfaceContainerLow;
  static Color sheet(ColorScheme s) => s.surfaceContainerLow;
  static Color raised(ColorScheme s) => s.surfaceContainerHigh;
  static Color nested(ColorScheme s) => s.surfaceContainerHighest;
}

/// Chart colours, exposed as a [ThemeExtension] so `fl_chart` widgets read
/// them from `Theme.of(context)` and stay in sync with light / dark.
///
/// Read with [HakariChartColors.of]; `hakari_theme.dart` installs one built
/// from the active [ColorScheme].
@immutable
class HakariChartColors extends ThemeExtension<HakariChartColors> {
  const HakariChartColors({
    required this.line,
    required this.secondaryLine,
    required this.fillTop,
    required this.fillBottom,
    required this.grid,
    required this.axisLabel,
    required this.marker,
    required this.tooltipBackground,
    required this.tooltipForeground,
  });

  /// Derives the palette from a [ColorScheme].
  factory HakariChartColors.fromScheme(ColorScheme s) => HakariChartColors(
    line: s.primary,
    secondaryLine: s.tertiary,
    fillTop: s.primary.withValues(alpha: 0.28),
    fillBottom: s.primary.withValues(alpha: 0.0),
    grid: s.outlineVariant.withValues(alpha: 0.4),
    axisLabel: s.onSurfaceVariant,
    marker: s.tertiary,
    tooltipBackground: s.inverseSurface,
    tooltipForeground: s.onInverseSurface,
  );

  /// Primary series (weight).
  final Color line;

  /// Secondary series (body fat).
  final Color secondaryLine;

  /// Gradient under the primary line, top stop.
  final Color fillTop;

  /// Gradient under the primary line, bottom stop (transparent).
  final Color fillBottom;

  /// Horizontal grid lines. Keep them faint; trale-style charts are minimal.
  final Color grid;

  /// Axis tick labels.
  final Color axisLabel;

  /// "Today" / selected-point marker.
  final Color marker;

  final Color tooltipBackground;
  final Color tooltipForeground;

  /// Vertical fill gradient for the area under the primary line.
  LinearGradient get fillGradient => LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [fillTop, fillBottom],
  );

  /// Shorthand for `Theme.of(context).extension<HakariChartColors>()`.
  ///
  /// Falls back to deriving from the current scheme so widget tests that
  /// build a bare [MaterialApp] still work.
  static HakariChartColors of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<HakariChartColors>() ??
        HakariChartColors.fromScheme(theme.colorScheme);
  }

  @override
  HakariChartColors copyWith({
    Color? line,
    Color? secondaryLine,
    Color? fillTop,
    Color? fillBottom,
    Color? grid,
    Color? axisLabel,
    Color? marker,
    Color? tooltipBackground,
    Color? tooltipForeground,
  }) => HakariChartColors(
    line: line ?? this.line,
    secondaryLine: secondaryLine ?? this.secondaryLine,
    fillTop: fillTop ?? this.fillTop,
    fillBottom: fillBottom ?? this.fillBottom,
    grid: grid ?? this.grid,
    axisLabel: axisLabel ?? this.axisLabel,
    marker: marker ?? this.marker,
    tooltipBackground: tooltipBackground ?? this.tooltipBackground,
    tooltipForeground: tooltipForeground ?? this.tooltipForeground,
  );

  @override
  HakariChartColors lerp(ThemeExtension<HakariChartColors>? other, double t) {
    if (other is! HakariChartColors) return this;
    return HakariChartColors(
      line: Color.lerp(line, other.line, t)!,
      secondaryLine: Color.lerp(secondaryLine, other.secondaryLine, t)!,
      fillTop: Color.lerp(fillTop, other.fillTop, t)!,
      fillBottom: Color.lerp(fillBottom, other.fillBottom, t)!,
      grid: Color.lerp(grid, other.grid, t)!,
      axisLabel: Color.lerp(axisLabel, other.axisLabel, t)!,
      marker: Color.lerp(marker, other.marker, t)!,
      tooltipBackground: Color.lerp(
        tooltipBackground,
        other.tooltipBackground,
        t,
      )!,
      tooltipForeground: Color.lerp(
        tooltipForeground,
        other.tooltipForeground,
        t,
      )!,
    );
  }
}
