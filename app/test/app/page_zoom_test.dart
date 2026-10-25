import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/app/page_zoom.dart';

/// The page scale is a real browser-style zoom, not a text scaler: the child is
/// laid out in a window/scale sized logical area and painted scaled. These tests
/// pin that contract — logical size, insets, hit testing and the promise that
/// the platform text scaler is not multiplied twice.
void main() {
  Widget harness({
    required double scale,
    required Widget child,
    EdgeInsets padding = const EdgeInsets.all(10),
    EdgeInsets viewInsets = EdgeInsets.zero,
    TextScaler textScaler = TextScaler.noScaling,
  }) {
    return MediaQuery(
      data: MediaQueryData(
        size: const Size(800, 600),
        padding: padding,
        viewInsets: viewInsets,
        textScaler: textScaler,
      ),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: PageZoom(scale: scale, child: child),
      ),
    );
  }

  testWidgets('scale 1.0 leaves the layout untouched', (tester) async {
    final seen = <MediaQueryData>[];
    await tester.pumpWidget(harness(
      scale: 1.0,
      child: Builder(
        builder: (context) {
          seen.add(MediaQuery.of(context));
          return const SizedBox.expand();
        },
      ),
    ));

    expect(seen.single.size, const Size(800, 600));
    expect(seen.single.padding, const EdgeInsets.all(10));
    expect(find.byType(Transform), findsNothing);
    expect(find.byType(ClipRect), findsNothing);
  });

  testWidgets('scale 1.5 lays the app out in a larger logical area',
      (tester) async {
    final seen = <MediaQueryData>[];
    await tester.pumpWidget(harness(
      scale: 1.5,
      padding: const EdgeInsets.fromLTRB(10, 20, 30, 40),
      viewInsets: const EdgeInsets.only(bottom: 60),
      child: Builder(
        builder: (context) {
          seen.add(MediaQuery.of(context));
          return const SizedBox.expand();
        },
      ),
    ));

    expect(seen.single.size.width, closeTo(800 / 1.5, 1e-9));
    expect(seen.single.size.height, closeTo(600 / 1.5, 1e-9));
    expect(seen.single.padding.left, closeTo(10 / 1.5, 1e-9));
    expect(seen.single.padding.top, closeTo(20 / 1.5, 1e-9));
    expect(seen.single.padding.right, closeTo(30 / 1.5, 1e-9));
    expect(seen.single.padding.bottom, closeTo(40 / 1.5, 1e-9));
    expect(seen.single.viewInsets.bottom, closeTo(60 / 1.5, 1e-9));
  });

  testWidgets('scale 0.8 grows the logical area (more content fits)',
      (tester) async {
    final seen = <MediaQueryData>[];
    await tester.pumpWidget(harness(
      scale: 0.8,
      child: Builder(
        builder: (context) {
          seen.add(MediaQuery.of(context));
          return const SizedBox.expand();
        },
      ),
    ));

    expect(seen.single.size.width, closeTo(1000, 1e-9));
    expect(seen.single.size.height, closeTo(750, 1e-9));
  });

  testWidgets('paints the child through a scale transform inside a ClipRect',
      (tester) async {
    await tester
        .pumpWidget(harness(scale: 1.25, child: const SizedBox.expand()));

    final transforms = tester.widgetList<Transform>(find.byType(Transform));
    expect(transforms, isNotEmpty);
    expect(
      transforms
          .any((t) => (t.transform.getMaxScaleOnAxis() - 1.25).abs() < 1e-9),
      isTrue,
    );
    expect(find.byType(ClipRect), findsOneWidget);
  });

  testWidgets('hit testing follows the zoom', (tester) async {
    var taps = 0;
    await tester.pumpWidget(harness(
      scale: 2.0,
      child: Align(
        alignment: Alignment.topLeft,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => taps++,
          child: const SizedBox(width: 40, height: 40),
        ),
      ),
    ));

    // Physical (30,30) is logical (20,20) at 2x: inside the 40x40 box.
    await tester.tapAt(const Offset(30, 30));
    await tester.pump();
    expect(taps, 1);

    // Physical (100,100) is logical (50,50): outside the box, must not hit.
    await tester.tapAt(const Offset(100, 100));
    await tester.pump();
    expect(taps, 1);
  });

  testWidgets('keeps the platform text scaler instead of scaling twice',
      (tester) async {
    final seen = <MediaQueryData>[];
    await tester.pumpWidget(harness(
      scale: 1.5,
      textScaler: const TextScaler.linear(1.2),
      child: Builder(
        builder: (context) {
          seen.add(MediaQuery.of(context));
          return const SizedBox.expand();
        },
      ),
    ));

    expect(seen.single.textScaler.scale(10), closeTo(12, 1e-9));
  });

  testWidgets('non-positive or non-finite scales are ignored', (tester) async {
    for (final scale in <double>[0, -1, double.nan, double.infinity]) {
      await tester
          .pumpWidget(harness(scale: scale, child: const SizedBox.expand()));
      expect(find.byType(Transform), findsNothing, reason: 'scale=$scale');
    }
  });
}
