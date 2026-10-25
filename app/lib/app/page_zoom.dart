import 'package:flutter/material.dart';

/// Zooms the whole page — text, controls, spacing and images — by [scale].
///
/// The theme editor's "页面缩放" is specified as *overall* zoom
/// (docs/FURNACE_SPEC.md §4.1: 80%–150%; docs/APPEARANCE_DESIGN.md). Until this
/// widget existed the scale was only fed into MediaQuery.textScaler, so the
/// slider moved font sizes alone while buttons, paddings and images kept their
/// size — the hint says "影响正文与控件尺寸", which was not true.
///
/// How the zoom works: the child is laid out in a *larger* logical area
/// (window size / [scale]) with a matching [MediaQuery] (size, padding,
/// view insets), then painted through a [Transform.scale]. Widgets therefore
/// reflow exactly as if the window were that many logical pixels wide, and the
/// transform maps the result back onto the physical screen. This is the same
/// model a browser uses for page zoom, so no widget has to know about it.
///
/// The incoming MediaQuery.textScaler (the platform's text accessibility
/// setting) is preserved untouched — scaling it here as well would multiply the
/// font size twice and defeat system text scaling.
class PageZoom extends StatelessWidget {
  const PageZoom({super.key, required this.scale, required this.child});

  /// 1.0 means "no zoom"; values are clamped by ThemeScale.clamp before use.
  final double scale;
  final Widget child;

  static const double _epsilon = 0.001;

  @override
  Widget build(BuildContext context) {
    if (!scale.isFinite || scale <= 0 || (scale - 1).abs() < _epsilon) {
      return child;
    }
    final media = MediaQuery.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        var base = constraints.biggest;
        if (!base.isFinite) {
          base = media.size;
        }
        if (!base.isFinite || base.isEmpty) {
          return child;
        }
        final zoomed = Size(base.width / scale, base.height / scale);
        return MediaQuery(
          data: media.copyWith(
            size: zoomed,
            padding: media.padding / scale,
            viewPadding: media.viewPadding / scale,
            viewInsets: media.viewInsets / scale,
            systemGestureInsets: media.systemGestureInsets / scale,
          ),
          child: ClipRect(
            child: OverflowBox(
              // The zoomed layout is deliberately sized by the child itself
              // (SizedBox below); the box only fills the window.
              alignment: Alignment.topLeft,
              minWidth: 0,
              maxWidth: double.infinity,
              minHeight: 0,
              maxHeight: double.infinity,
              child: Transform.scale(
                scale: scale,
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: zoomed.width,
                  height: zoomed.height,
                  child: child,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
