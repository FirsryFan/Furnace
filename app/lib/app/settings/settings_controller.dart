import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/repository_providers.dart';

/// UI language preference.
enum AppLanguage {
  system,
  zh,
  en;

  Locale? resolve() {
    return switch (this) {
      AppLanguage.system => null,
      AppLanguage.zh => const Locale('zh'),
      AppLanguage.en => const Locale('en'),
    };
  }
}

/// Theme preference.
enum AppThemeMode {
  system,
  light,
  dark;

  ThemeMode resolve() {
    return switch (this) {
      AppThemeMode.system => ThemeMode.system,
      AppThemeMode.light => ThemeMode.light,
      AppThemeMode.dark => ThemeMode.dark,
    };
  }
}

/// Settings state backed by the local database when available.
class SettingsState {
  const SettingsState({
    this.language = AppLanguage.system,
    this.themeMode = AppThemeMode.system,
  });

  final AppLanguage language;
  final AppThemeMode themeMode;

  SettingsState copyWith({
    AppLanguage? language,
    AppThemeMode? themeMode,
  }) {
    return SettingsState(
      language: language ?? this.language,
      themeMode: themeMode ?? this.themeMode,
    );
  }
}

class SettingsController extends Notifier<SettingsState> {
  @override
  SettingsState build() {
    return const SettingsState();
  }

  /// Loads persisted settings and ensures a local profile exists.
  Future<void> loadFromDatabase() async {
    final repo = ref.read(settingsRepositoryProvider);
    var profile = await repo.getProfile();
    if (profile == null) {
      profile = await repo.ensureProfile(displayName: 'User');
    }
    final settings = await repo.ensureSettings(profileId: profile.id);
    state = SettingsState(
      language: _parseLanguage(settings.language),
      themeMode: _parseTheme(settings.themeMode),
    );
  }

  void setLanguage(AppLanguage language) {
    state = state.copyWith(language: language);
    ref.read(settingsRepositoryProvider).updateLanguage(_languageName(language));
  }

  void setThemeMode(AppThemeMode themeMode) {
    state = state.copyWith(themeMode: themeMode);
    ref.read(settingsRepositoryProvider).updateThemeMode(_themeName(themeMode));
  }

  AppLanguage _parseLanguage(String value) {
    return switch (value) {
      'zh' => AppLanguage.zh,
      'en' => AppLanguage.en,
      _ => AppLanguage.system,
    };
  }

  AppThemeMode _parseTheme(String value) {
    return switch (value) {
      'light' => AppThemeMode.light,
      'dark' => AppThemeMode.dark,
      _ => AppThemeMode.system,
    };
  }

  String _languageName(AppLanguage language) {
    return switch (language) {
      AppLanguage.system => 'system',
      AppLanguage.zh => 'zh',
      AppLanguage.en => 'en',
    };
  }

  String _themeName(AppThemeMode themeMode) {
    return switch (themeMode) {
      AppThemeMode.system => 'system',
      AppThemeMode.light => 'light',
      AppThemeMode.dark => 'dark',
    };
  }
}

final settingsControllerProvider =
    NotifierProvider<SettingsController, SettingsState>(
  SettingsController.new,
);
