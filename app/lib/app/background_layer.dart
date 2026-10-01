import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Paints a theme's background image behind the app, with the theme's
/// background colour laid over it as a translucent scrim.
///
/// Layering, bottom to top:
///
///   1. the image
///   2. the background colour at the configured opacity (the "scrim")
///   3. the app
///
/// Why this is its own widget, and why it is public: the first attempt at this
/// feature put the colour on the `Scaffold`'s background instead, which sits
/// *above* the image - so an opaque colour (even at 0.9 opacity) covered the
/// picture completely, and the user reported "the background image never
/// loads" while the file was present and being read. The layer order is the
/// whole behaviour, so it is isolated here and pinned by a widget test that
/// renders it and inspects the resulting pixels.
///
/// The scrim is also what keeps the background *readable*: a photo behind raw
/// text makes the text unreadable, so the colour is painted over the image
/// rather than under it, and the opacity slider decides how strong it is.
///
/// The path is relative to the app support directory (importing a picture
/// copies it there). A missing or undecodable file degrades to "no image"
/// instead of crashing the app on startup - a theme whose picture was deleted
/// must not make the app unusable.
class Backdrop extends StatefulWidget {
  const Backdrop({
    super.key,
    required this.relativePath,
    this.blur = 0,
    this.scrim,
    required this.child,
  });

  /// Path relative to the app support directory.
  final String relativePath;
  final double blur;

  /// Colour painted over the image; null paints nothing.
  final Color? scrim;

  final Widget child;

  @override
  State<Backdrop> createState() => _BackdropState();
}

class _BackdropState extends State<Backdrop> {
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
  void didUpdateWidget(Backdrop oldWidget) {
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
      // No support directory, or the plugin failed: fall back to "no image"
      // rather than taking the app down over a decoration. Leaving `_filePath`
      // null does exactly that.
    }
  }

  @override
  Widget build(BuildContext context) {
    final path = _filePath;
    final exists = path != null && File(path).existsSync();

    if (!exists) {
      return _withScrim(widget.child);
    }

    Widget image = Image.file(
      File(path),
      fit: BoxFit.cover,
      // Decode at a sane size: a phone photo as a full-resolution background
      // costs a lot of memory for no visible gain. `cacheWidth` must be an
      // int > 0, so 0 means "no downscale".
      cacheWidth: widget.blur > 0 ? 2048 : 1600,
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

  Widget _withScrim(Widget child) {
    if (widget.scrim == null) {
      return child;
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(child: ColoredBox(color: widget.scrim!)),
        child,
      ],
    );
  }
}
