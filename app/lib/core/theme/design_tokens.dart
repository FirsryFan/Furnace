import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

/// Design tokens for the whole app (review feedback item 3: 「UI 风格不自然」).
///
/// Why tokens at all: before this file, one grep over `lib/` found 125 distinct
/// `EdgeInsets` literals, 11 distinct `BorderRadius.circular` values (2, 3, 4,
/// 6, 8, 10, 12, 18, 999, height/2, width/2) and only five explicit font sizes
/// (9, 10, 11, 12, 13). Nothing was wrong on any single page; the pages simply
/// disagreed with each other, and that is what reads as "not natural".
///
/// The tokens live in a [ThemeExtension] instead of global constants so that
/// other themes (and tests) can answer `AppTokens.of(context)` without an
/// import of this file, and so a page can be migrated one at a time without a
/// big-bang rewrite. Nothing here forces a page to use them.
abstract final class AppSpacing {
  /// 4pt grid, with a 2pt half-step for optical alignment only.
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;

  static const List<double> scale = <double>[
    xxs,
    xs,
    sm,
    md,
    lg,
    xl,
    xxl,
    xxxl,
  ];

  /// Snaps an arbitrary value to the nearest grid step, for migrating a page
  /// that used an off-grid literal (e.g. 14 -> 12, 18 -> 16).
  static double snap(double value) {
    var best = scale.first;
    var bestDistance = (value - best).abs();
    for (final step in scale.skip(1)) {
      final distance = (value - step).abs();
      if (distance < bestDistance) {
        best = step;
        bestDistance = distance;
      }
    }
    return best;
  }
}

/// Four corner radii: controls, cards, sheets, and "fully round".
abstract final class AppRadius {
  static const double control = 6;
  static const double card = 10;
  static const double sheet = 14;
  static const double pill = 999;

  static const BorderRadius controlBorder =
      BorderRadius.all(Radius.circular(control));
  static const BorderRadius cardBorder =
      BorderRadius.all(Radius.circular(card));
  static const BorderRadius sheetBorder =
      BorderRadius.all(Radius.circular(sheet));
  static const BorderRadius pillBorder =
      BorderRadius.all(Radius.circular(pill));
}

/// The resolved tokens for one theme.
///
/// Text styles are derived from the theme's [TextTheme] (so the UI font and the
/// global text scale still apply) and only pin the size/weight/tracking parts
/// that the semantic name promises.
@immutable
class AppTokens extends ThemeExtension<AppTokens> {
  const AppTokens({
    this.spaceXxs = AppSpacing.xxs,
    this.spaceXs = AppSpacing.xs,
    this.spaceSm = AppSpacing.sm,
    this.spaceMd = AppSpacing.md,
    this.spaceLg = AppSpacing.lg,
    this.spaceXl = AppSpacing.xl,
    this.spaceXxl = AppSpacing.xxl,
    this.spaceXxxl = AppSpacing.xxxl,
    this.controlRadius = AppRadius.control,
    this.cardRadius = AppRadius.card,
    this.sheetRadius = AppRadius.sheet,
    this.pageTitle = const TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.w600,
      height: 1.3,
    ),
    this.sectionTitle = const TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w600,
      height: 1.35,
    ),
    this.body = const TextStyle(fontSize: 14, height: 1.4),
    this.caption = const TextStyle(fontSize: 12, height: 1.35),
  });

  final double spaceXxs;
  final double spaceXs;
  final double spaceSm;
  final double spaceMd;
  final double spaceLg;
  final double spaceXl;
  final double spaceXxl;
  final double spaceXxxl;

  final double controlRadius;
  final double cardRadius;
  final double sheetRadius;

  /// Page-level heading (one per page).
  final TextStyle pageTitle;

  /// Card / section heading.
  final TextStyle sectionTitle;

  /// Reading text.
  final TextStyle body;

  /// Secondary labels, counts, timestamps.
  final TextStyle caption;

  BorderRadius get controlBorder =>
      BorderRadius.all(Radius.circular(controlRadius));
  BorderRadius get cardBorder => BorderRadius.all(Radius.circular(cardRadius));
  BorderRadius get sheetBorder =>
      BorderRadius.all(Radius.circular(sheetRadius));

  /// The fallback used when a page is shown without [ThemeProfileData.toThemeData]
  /// (an old test harness, a bare `MaterialApp`): tokens never become null.
  static const AppTokens standard = AppTokens();

  /// Derives the text styles from [theme]'s own [TextTheme].
  ///
  /// Only the semantic size/weight/height are pinned; family, letter spacing and
  /// decoration come from the theme, which is what keeps the editor font
  /// (`ThemeProfileData.editorFont`) effective on reading text.
  factory AppTokens.fromTheme(ThemeData theme) {
    final text = theme.textTheme;
    return const AppTokens().copyWith(
      pageTitle: (text.headlineSmall ?? const TextStyle()).copyWith(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        height: 1.3,
      ),
      sectionTitle: (text.titleMedium ?? const TextStyle()).copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        height: 1.35,
      ),
      body: (text.bodyMedium ?? const TextStyle()).copyWith(
        fontSize: 14,
        height: 1.4,
      ),
      caption: (text.bodySmall ?? const TextStyle()).copyWith(
        fontSize: 12,
        height: 1.35,
      ),
    );
  }

  /// The tokens of the current theme, or [standard] when none were installed.
  static AppTokens of(BuildContext context) =>
      Theme.of(context).extension<AppTokens>() ?? standard;

  @override
  AppTokens copyWith({
    double? spaceXxs,
    double? spaceXs,
    double? spaceSm,
    double? spaceMd,
    double? spaceLg,
    double? spaceXl,
    double? spaceXxl,
    double? spaceXxxl,
    double? controlRadius,
    double? cardRadius,
    double? sheetRadius,
    TextStyle? pageTitle,
    TextStyle? sectionTitle,
    TextStyle? body,
    TextStyle? caption,
  }) {
    return AppTokens(
      spaceXxs: spaceXxs ?? this.spaceXxs,
      spaceXs: spaceXs ?? this.spaceXs,
      spaceSm: spaceSm ?? this.spaceSm,
      spaceMd: spaceMd ?? this.spaceMd,
      spaceLg: spaceLg ?? this.spaceLg,
      spaceXl: spaceXl ?? this.spaceXl,
      spaceXxl: spaceXxl ?? this.spaceXxl,
      spaceXxxl: spaceXxxl ?? this.spaceXxxl,
      controlRadius: controlRadius ?? this.controlRadius,
      cardRadius: cardRadius ?? this.cardRadius,
      sheetRadius: sheetRadius ?? this.sheetRadius,
      pageTitle: pageTitle ?? this.pageTitle,
      sectionTitle: sectionTitle ?? this.sectionTitle,
      body: body ?? this.body,
      caption: caption ?? this.caption,
    );
  }

  @override
  AppTokens lerp(ThemeExtension<AppTokens>? other, double t) {
    if (other is! AppTokens) {
      return this;
    }
    return AppTokens(
      spaceXxs: lerpDouble(spaceXxs, other.spaceXxs, t)!,
      spaceXs: lerpDouble(spaceXs, other.spaceXs, t)!,
      spaceSm: lerpDouble(spaceSm, other.spaceSm, t)!,
      spaceMd: lerpDouble(spaceMd, other.spaceMd, t)!,
      spaceLg: lerpDouble(spaceLg, other.spaceLg, t)!,
      spaceXl: lerpDouble(spaceXl, other.spaceXl, t)!,
      spaceXxl: lerpDouble(spaceXxl, other.spaceXxl, t)!,
      spaceXxxl: lerpDouble(spaceXxxl, other.spaceXxxl, t)!,
      controlRadius: lerpDouble(controlRadius, other.controlRadius, t)!,
      cardRadius: lerpDouble(cardRadius, other.cardRadius, t)!,
      sheetRadius: lerpDouble(sheetRadius, other.sheetRadius, t)!,
      pageTitle: TextStyle.lerp(pageTitle, other.pageTitle, t)!,
      sectionTitle: TextStyle.lerp(sectionTitle, other.sectionTitle, t)!,
      body: TextStyle.lerp(body, other.body, t)!,
      caption: TextStyle.lerp(caption, other.caption, t)!,
    );
  }
}
