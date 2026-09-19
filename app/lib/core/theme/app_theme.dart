import 'package:flutter/material.dart';

/// Light and dark themes for KnowFlow.
abstract final class AppTheme {
  static const _seed = Color(0xFF3B82F6);

  static ThemeData get light {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: _seed),
      brightness: Brightness.light,
    );
  }

  static ThemeData get dark {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: _seed,
        brightness: Brightness.dark,
      ),
      brightness: Brightness.dark,
    );
  }
}
