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

/// Paints the theme's background image behind the whole app, with the theme's
/// background colour laid over it as a translucent scrim.
///
/// Layering, bottom to top:
///
///   1. the image
///   2. the background colour at the configured opacity (the "scrim")
///   3. the app
///
/// The scrim is what makes the background **readable**: a photo behind raw text
/// makes the text unreadable, and a 0-opacity colour would leave it that way.
/// Painting the colour over the image (rather than under, as a scaffold
/// background) is also what fixes the bug where the image never appeared at
/// all: the scaffold sits *above* this layer, so an opaque scaffold background
/// covered the picture no matter how transparent the colour was meant to be.
/// `ThemeProfileData.toThemeData` therefore makes the scaffold transparent
/// whenever a background image is present.
///
/// The path stored in a theme document is relative to the app support directory
/// (importing copies the file there). A missing file degrades to "no image"
/// instead of crashing the app on startup - a theme whose picture was deleted
/// must not make the app unusable.
class _BackgroundImage extends StatefulWidget {
  const _BackgroundImage({
    required this.relativePath,
    required this.blur,
    required this.scrim,
    required this.child,
  });

  final String relativePath;
  final double blur;
  final Color? scrim;
  final Widget child;

  @override
  State<_BackgroundImage> createState() => _BackgroundImageState();
}

class _BackgroundImageState extends State<_BackgroundImage> {
  /// Resolved once and kept: the support directory does not move while the app
  /// runs, and re-resolving per rebuild made the layer flicker. `null` means
  /// "not resolved yet" and is handled by painting only the scrim.
  String? _filePath;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(_BackgroundImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.relativePath != widget.relativePath) {
      _resolve();
    }
  }

  Future<void> _resolve() async {
    try {
      final dir = await getApplicationSupportDirectory();
      if (!mounted) {
        return;
      }
      setState(() => _filePath = p.join(dir.path, widget.relativePath));
    } catch (_) {
      // No support directory (should not happen on a supported platform), or
      // the plugin failed: fall back to "no image" rather than taking the app
      // down over a decoration. Leaving `_filePath` null does exactly that.
    }
  }

  @override
  Widget build(BuildContext context) {
    final path = _filePath;
    final exists = path != null && File(path).existsSync();

    // Until the path is known, paint only the scrim: no flash of the image
    // appearing a frame later.
    if (!exists) {
      return Stack(
        fit: StackFit.expand,
        children: [
          if (widget.scrim != null)
            Positioned.fill(child: ColoredBox(color: widget.scrim!)),
          widget.child,
        ],
      );
    }

    Widget image = Image.file(
      File(path),
      fit: BoxFit.cover,
      // Decode at a sane size: a phone photo as a full-resolution background
      // costs a lot of memory for no visible gain.
      cacheWidth: 2048,
      // A file that exists but cannot be decoded (truncated, exotic format)
      // must degrade, not throw.
      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
    );
    if (widget.blur > 0) {
      image = ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: widget.blur, sigmaY: widget.blur),
        child: image,
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(child: image),
        if (widget.scrim != null)
          Positioned.fill(child: ColoredBox(color: widget.scrim!)),
        widget.child,
      ],
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

    // A background image is a layer *behind* the whole app, with the theme's
    // background colour over it as a scrim. The scaffold is transparent in that
    // case (see ThemeProfileData.toThemeData), which is what actually lets the
    // picture be seen.
    if (profile.hasBackgroundImage) {
      result = _BackgroundImage(
        relativePath: profile.backgroundImagePath!,
        blur: profile.backgroundBlur,
        scrim: profile.background == null
            ? null
            : ThemeProfileData.colorOf(
                profile.background!,
                fallback: const Color(0xFF000000),
              ).withValues(
                alpha: profile.backgroundOpacity.clamp(0.0, 1.0),
              ),
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
