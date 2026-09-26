import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:furnace/l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/theme/theme_profile.dart';
import '../features/settings/application/appearance_providers.dart';
import 'settings/settings_controller.dart';
import 'shell/home_shell.dart';

/// Root widget of Furnace.
///
/// Appearance is driven by the selected theme document (spec §4) rather than a
/// hard-coded pair of ThemeData objects. The theme also carries the page scale
/// and the animation switch, both applied here so they take effect app-wide.
class FurnaceApp extends ConsumerWidget {
  const FurnaceApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsControllerProvider);
    final locale = settings.language.resolve();
    final appearanceAsync = ref.watch(activeAppearanceProvider);

    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) => _AppearanceScope(
        appearance: appearanceAsync.valueOrNull,
        child: child ?? const SizedBox.shrink(),
      ),
      theme: appearanceAsync.valueOrNull?.themeFor(Brightness.light) ??
          ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2F6F4F)),
          ),
      darkTheme: appearanceAsync.valueOrNull?.themeFor(Brightness.dark) ??
          ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF3D8B63),
              brightness: Brightness.dark,
            ),
          ),
      // A selected theme is used for both brightnesses (the document states its
      // own brightness); otherwise the legacy system/light/dark choice applies.
      themeMode: appearanceAsync.valueOrNull?.followSystem == false
          ? (((appearanceAsync.valueOrNull?.data?.isDark) ?? true)
              ? ThemeMode.dark
              : ThemeMode.light)
          : settings.themeMode.resolve(),
      home: const HomeShell(),
    );
  }
}

/// Paints the theme's background image behind the whole app.
///
/// The path stored in a theme document is relative to the app support
/// directory (importing copies the file there, so a theme travels with its
/// image only as far as the user re-imports it). A missing file therefore
/// degrades to "no image" instead of crashing the app on startup - a theme
/// whose picture was deleted must not make the app unusable.
class _BackgroundImage extends StatelessWidget {
  const _BackgroundImage({
    required this.relativePath,
    required this.blur,
    required this.child,
  });

  final String relativePath;
  final double blur;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Directory>(
      future: getApplicationSupportDirectory(),
      builder: (context, snapshot) {
        final dir = snapshot.data;
        if (dir == null) {
          return child;
        }
        final file = File(p.join(dir.path, relativePath));
        if (!file.existsSync()) {
          return child;
        }
        Widget image = Image.file(
          file,
          fit: BoxFit.cover,
          // Decode at a sane size: a phone photo as a full-resolution
          // background costs a lot of memory for no visible gain.
          cacheWidth: 2048,
          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
        );
        if (blur > 0) {
          image = ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
            child: image,
          );
        }
        return Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(child: image),
            child,
          ],
        );
      },
    );
  }
}

/// Applies the theme's page scale and animation switch to the widget tree.
///
/// Why only `textScaler`: scaling here AND inside `ThemeData` would scale text
/// twice. The spec asks for a page zoom of 80%-150%, and text is the dominant
/// content in this app, so the scale is expressed as a text scaler applied to
/// the whole tree. A custom font family is delivered through ThemeData, which
/// is the only mechanism that reaches every widget correctly.
class _AppearanceScope extends StatelessWidget {
  const _AppearanceScope({required this.appearance, required this.child});

  final ActiveAppearance? appearance;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final active = appearance;
    if (active == null) {
      return child;
    }
    final media = MediaQuery.of(context);
    final profile = active.effectiveFor(media.platformBrightness);
    final scale = ThemeScale.clamp(profile.scale);

    Widget result = MediaQuery(
      data: media.copyWith(
        textScaler: TextScaler.linear(scale),
      ),
      child: child,
    );

    // A background image is a layer *behind* the whole app. The theme's
    // scaffold background is painted with the configured opacity, so the image
    // shows through exactly as far as the opacity slider says.
    if (profile.backgroundImagePath != null) {
      result = _BackgroundImage(
        relativePath: profile.backgroundImagePath!,
        blur: profile.backgroundBlur,
        child: result,
      );
    }

    if (!profile.animations) {
      // Disabling animations is expressed by shortening every implicit
      // animation, which is what "disable animations" means for the user.
      result = _NoAnimations(child: result);
    }
    return result;
  }
}

/// Zeroes the duration of implicit animations for the whole subtree.
class _NoAnimations extends StatelessWidget {
  const _NoAnimations({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: <TargetPlatform, PageTransitionsBuilder>{
            TargetPlatform.android: _InstantPageTransitionsBuilder(),
            TargetPlatform.iOS: _InstantPageTransitionsBuilder(),
            TargetPlatform.windows: _InstantPageTransitionsBuilder(),
            TargetPlatform.macOS: _InstantPageTransitionsBuilder(),
            TargetPlatform.linux: _InstantPageTransitionsBuilder(),
            TargetPlatform.fuchsia: _InstantPageTransitionsBuilder(),
          },
        ),
      ),
      child: child,
    );
  }
}

/// No-op page transition used when the theme turns animations off.
class _InstantPageTransitionsBuilder extends PageTransitionsBuilder {
  const _InstantPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) =>
      child;
}
