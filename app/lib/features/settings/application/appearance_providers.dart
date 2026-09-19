import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/theme_profile.dart';
import '../../../data/database/database.dart';
import '../../../data/repositories/repository_providers.dart';

/// All stored themes, built-ins first.
final themesProvider = FutureProvider<List<ThemeProfile>>((ref) {
  return ref.watch(themeRepositoryProvider).getAll();
});

/// The active theme plus the resolved model.
///
/// `row == null` means "follow the system": the app then uses its own light or
/// dark default depending on the platform brightness. This keeps the old
/// system/light/dark behaviour available next to the JSON themes, which the
/// spec's appearance section implies (built-in official light and dark themes).
class ActiveAppearance {
  const ActiveAppearance({
    required this.row,
    required this.data,
    required this.followSystem,
    required this.legacyMode,
  });

  final ThemeProfile? row;
  final ThemeProfileData? data;

  /// True when no theme is selected and the legacy light/dark/system setting
  /// decides the brightness.
  final bool followSystem;

  /// The legacy `theme_mode` value (`system` | `light` | `dark`).
  final String legacyMode;

  /// Builds the ThemeData for a given platform brightness.
  ThemeData themeFor(Brightness platformBrightness) {
    final profile = data;
    if (profile != null) {
      return profile.toThemeData();
    }
    final wantDark = switch (legacyMode) {
      'light' => false,
      'dark' => true,
      _ => platformBrightness == Brightness.dark,
    };
    return (wantDark
            ? ThemeProfileData.builtinDark
            : ThemeProfileData.builtinLight)
        .toThemeData();
  }

  /// The profile currently in effect, for reading scale/animations.
  ThemeProfileData effectiveFor(Brightness platformBrightness) {
    final profile = data;
    if (profile != null) {
      return profile;
    }
    final wantDark = switch (legacyMode) {
      'light' => false,
      'dark' => true,
      _ => platformBrightness == Brightness.dark,
    };
    return wantDark
        ? ThemeProfileData.builtinDark
        : ThemeProfileData.builtinLight;
  }
}

final activeAppearanceProvider = FutureProvider<ActiveAppearance>((ref) async {
  final repo = ref.watch(themeRepositoryProvider);
  await repo.ensureBuiltins();
  final active = await repo.active();
  final settings =
      await ref.watch(settingsRepositoryProvider).getSettings();
  return ActiveAppearance(
    row: active?.row,
    data: active?.data,
    followSystem: active == null,
    legacyMode: settings?.themeMode ?? 'system',
  );
});

/// Selects a theme, or null to follow the legacy system/light/dark setting.
Future<void> selectTheme(WidgetRef ref, String? id) async {
  await ref.read(themeRepositoryProvider).setActive(id);
  ref.invalidate(activeAppearanceProvider);
  ref.invalidate(themesProvider);
}

/// Saves edits to a theme and refreshes the dependents.
Future<ThemeProfile> saveTheme(
  WidgetRef ref, {
  String? id,
  required ThemeProfileData data,
  bool makeActive = false,
}) async {
  final saved = await ref.read(themeRepositoryProvider).save(
        id: id,
        data: data,
        makeActive: makeActive,
      );
  ref.invalidate(activeAppearanceProvider);
  ref.invalidate(themesProvider);
  return saved;
}

/// Imports a theme document.
Future<ThemeProfile> importTheme(
  WidgetRef ref,
  String json, {
  bool makeActive = true,
}) async {
  final imported = await ref
      .read(themeRepositoryProvider)
      .importJson(json, makeActive: makeActive);
  ref.invalidate(activeAppearanceProvider);
  ref.invalidate(themesProvider);
  return imported;
}

/// Deletes a user theme. Returns false for built-ins.
Future<bool> deleteTheme(WidgetRef ref, String id) async {
  final removed = await ref.read(themeRepositoryProvider).delete(id);
  ref.invalidate(activeAppearanceProvider);
  ref.invalidate(themesProvider);
  return removed;
}
