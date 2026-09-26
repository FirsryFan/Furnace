import 'dart:convert';

import 'package:flutter/material.dart';

/// Appearance theme as a portable JSON document (spec §4 / GAP D13).
///
/// The spec asks for: separate UI and editor fonts, page scale 80%-150%
/// (themed via [scale]), primary/secondary colours, background colour with
/// opacity and an optional background image, an animation switch, built-in
/// light/dark themes, and import/export as a single JSON file.
///
/// Everything lives in this one model so a theme file can be validated,
/// exported and imported without touching the database shape.
@immutable
class ThemeProfileData {
  const ThemeProfileData({
    this.schemaVersion = 1,
    required this.name,
    this.brightness = 'dark',
    this.primary = '#2F6F4F',
    this.secondary = '#4F7FA8',
    this.surface,
    this.background,
    this.backgroundOpacity = 1.0,
    this.backgroundImagePath,
    this.backgroundBlur = 0,
    this.uiFont,
    this.editorFont,
    this.scale = 1.0,
    this.animations = true,
  });

  final int schemaVersion;
  final String name;

  /// `light` | `dark`.
  final String brightness;

  /// Hex strings (`#RRGGBB`), parsed leniently by [colorOf].
  final String primary;
  final String secondary;
  final String? surface;
  final String? background;

  /// 0.0-1.0 applied to the background layer.
  final double backgroundOpacity;

  /// Relative path inside the app directory (import copies the file there).
  final String? backgroundImagePath;
  final double backgroundBlur;

  /// Font family names; null = the platform default.
  final String? uiFont;
  final String? editorFont;

  /// Page scale, clamped to [ThemeScale.min]..[ThemeScale.max].
  final double scale;

  /// When false, implicit animations are removed.
  final bool animations;

  bool get isDark => brightness == 'dark';

  ThemeProfileData copyWith({
    String? name,
    String? brightness,
    String? primary,
    String? secondary,
    String? surface,
    String? background,
    double? backgroundOpacity,
    String? backgroundImagePath,
    bool clearBackgroundImage = false,
    double? backgroundBlur,
    String? uiFont,
    String? editorFont,
    double? scale,
    bool? animations,
  }) =>
      ThemeProfileData(
        schemaVersion: schemaVersion,
        name: name ?? this.name,
        brightness: brightness ?? this.brightness,
        primary: primary ?? this.primary,
        secondary: secondary ?? this.secondary,
        surface: surface ?? this.surface,
        background: background ?? this.background,
        backgroundOpacity: backgroundOpacity ?? this.backgroundOpacity,
        backgroundImagePath: clearBackgroundImage
            ? null
            : (backgroundImagePath ?? this.backgroundImagePath),
        backgroundBlur: backgroundBlur ?? this.backgroundBlur,
        uiFont: uiFont ?? this.uiFont,
        editorFont: editorFont ?? this.editorFont,
        scale: scale ?? this.scale,
        animations: animations ?? this.animations,
      );

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'name': name,
        'brightness': brightness,
        'colors': {
          'primary': primary,
          'secondary': secondary,
          if (surface != null) 'surface': surface,
        },
        'background': {
          if (background != null) 'color': background,
          'opacity': backgroundOpacity,
          if (backgroundImagePath != null) 'imagePath': backgroundImagePath,
          'blur': backgroundBlur,
        },
        'fonts': {
          if (uiFont != null) 'ui': uiFont,
          if (editorFont != null) 'editor': editorFont,
        },
        'scale': scale,
        'animations': animations,
      };

  /// Parses a theme document. Unknown keys are ignored on purpose so a file
  /// written by a newer version still loads (spec: import must not fail on
  /// extra fields).
  factory ThemeProfileData.fromJson(Map<String, dynamic> json) {
    final colors = (json['colors'] as Map<String, dynamic>?) ?? const {};
    final background = (json['background'] as Map<String, dynamic>?) ?? const {};
    final fonts = (json['fonts'] as Map<String, dynamic>?) ?? const {};
    return ThemeProfileData(
      schemaVersion: (json['schemaVersion'] as num?)?.toInt() ?? 1,
      name: json['name'] as String? ?? 'Custom',
      brightness: json['brightness'] as String? ?? 'dark',
      primary: colors['primary'] as String? ?? '#2F6F4F',
      secondary: colors['secondary'] as String? ?? '#4F7FA8',
      surface: colors['surface'] as String?,
      background: background['color'] as String?,
      backgroundOpacity:
          (background['opacity'] as num?)?.toDouble().clamp(0.0, 1.0) ?? 1.0,
      backgroundImagePath: background['imagePath'] as String?,
      backgroundBlur: (background['blur'] as num?)?.toDouble() ?? 0,
      uiFont: fonts['ui'] as String?,
      editorFont: fonts['editor'] as String?,
      scale: (json['scale'] as num?)?.toDouble().clamp(
                ThemeScale.min,
                ThemeScale.max,
              ) ??
          1.0,
      animations: json['animations'] as bool? ?? true,
    );
  }

  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());

  /// Parses a theme file body. Throws [FormatException] on invalid JSON.
  static ThemeProfileData decode(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('主题文件必须是一个 JSON 对象');
    }
    return ThemeProfileData.fromJson(decoded);
  }

  /// Parses `#RRGGBB` / `#AARRGGBB` / `RRGGBB`; returns [fallback] when the
  /// string is not a colour, so a hand-edited theme degrades instead of
  /// crashing.
  static Color colorOf(String? value, {required Color fallback}) {
    if (value == null) {
      return fallback;
    }
    var hex = value.trim();
    if (hex.startsWith('#')) {
      hex = hex.substring(1);
    }
    if (hex.length == 6) {
      hex = 'FF$hex';
    }
    if (hex.length != 8) {
      return fallback;
    }
    final parsed = int.tryParse(hex, radix: 16);
    return parsed == null ? fallback : Color(parsed);
  }

  /// The shipped dark theme.
  static const ThemeProfileData builtinDark = ThemeProfileData(
    name: '内置深色',
    brightness: 'dark',
    primary: '#3D8B63',
    secondary: '#5B8FC7',
    surface: '#1B1D1C',
    background: '#101211',
  );

  /// The shipped light theme.
  static const ThemeProfileData builtinLight = ThemeProfileData(
    name: '内置浅色',
    brightness: 'light',
    primary: '#2F6F4F',
    secondary: '#3B6FA0',
    surface: '#F6F7F5',
    background: '#FFFFFF',
  );

  /// Builds the Flutter theme for this profile.
  ///
  /// Every field of this document is meant to be *visible*. Three of them were
  /// not: `background`, `backgroundOpacity` and `editorFont` were editable in
  /// the theme editor and parsed from files, but never reached the widget tree,
  /// so changing them did nothing. That is worse than not offering them - the
  /// user believes the setting took effect. They are applied here.
  ThemeData toThemeData() {
    final scheme = ColorScheme.fromSeed(
      seedColor: colorOf(primary, fallback: const Color(0xFF2F6F4F)),
      brightness: isDark ? Brightness.dark : Brightness.light,
    );

    // The configured background colour, at the configured opacity, is the
    // scaffold background. Opacity below 1 lets whatever is painted behind the
    // scaffold show through, which is what the slider promises.
    final backgroundColour = background == null
        ? null
        : colorOf(background!, fallback: scheme.surface)
            .withValues(alpha: backgroundOpacity.clamp(0.0, 1.0));

    final surfaceOverride = surface == null
        ? null
        : colorOf(surface!, fallback: scheme.surface);

    final base = ThemeData(
      colorScheme: surfaceOverride == null
          ? scheme
          : scheme.copyWith(surface: surfaceOverride),
      useMaterial3: true,
      fontFamily: uiFont,
      visualDensity: VisualDensity.standard,
      scaffoldBackgroundColor: backgroundColour,
    );

    if (editorFont == null) {
      return base;
    }

    // A body/editor font is a different thing from the UI font: it applies to
    // what the user *reads and writes* (descriptions, notes, card answers,
    // message bodies) while buttons, tabs and titles keep the UI font. Applying
    // it to the whole text theme would silently defeat the second setting, so
    // only the body styles are overridden.
    final body = base.textTheme;
    return base.copyWith(
      textTheme: body.copyWith(
        bodyLarge: body.bodyLarge?.copyWith(fontFamily: editorFont),
        bodyMedium: body.bodyMedium?.copyWith(fontFamily: editorFont),
        bodySmall: body.bodySmall?.copyWith(fontFamily: editorFont),
      ),
      inputDecorationTheme: InputDecorationTheme(
        hintStyle: TextStyle(fontFamily: editorFont),
        labelStyle: TextStyle(fontFamily: editorFont),
      ),
    );
  }
}

/// Page-scale bounds (spec §4: 80%-150%).
abstract final class ThemeScale {
  static const double min = 0.8;
  static const double max = 1.5;

  static double clamp(double value) =>
      value < min ? min : (value > max ? max : value);
}
