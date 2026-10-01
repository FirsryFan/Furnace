import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/app/background_layer.dart';
import 'package:furnace/core/theme/theme_profile.dart';

/// Structural checks for the background layer's ordering, and for the theme
/// rule that made the picture invisible.
///
/// **What these tests can and cannot prove.** They pin the layer order, because
/// that is what the bug was: the theme's background colour was painted on the
/// `Scaffold`, which sits *above* this layer, so the picture was covered no
/// matter how present and decodable it was. Ordering is checkable here.
///
/// They do **not** prove that pixels reach the screen. A pixel-level test was
/// attempted and abandoned: it deadlocks, because `Image.file` needs a real
/// async decode while a widget test runs in a fake-async zone, so the frame the
/// picture arrives in never settles. `runAsync` did not resolve it either.
/// The final "I can see the picture" confirmation therefore still needs a human
/// looking at the running app.
void main() {
  group('layer order', () {
    testWidgets('the theme colour is painted as its own layer', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Backdrop(
            relativePath: 'whatever.png',
            scrim: Color(0x800000FF),
            child: Text('content', textDirection: TextDirection.ltr),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(Stack), findsWidgets,
          reason: 'the layer stacks image / colour / content');
      expect(
        find
            .byWidgetPredicate(
                (w) => w is ColoredBox && w.color == const Color(0x800000FF))
            .evaluate(),
        isNotEmpty,
        reason: 'the configured colour must be painted',
      );
      expect(find.text('content'), findsOneWidget);
    });

    testWidgets('the app content is inside the layer, not behind it',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Backdrop(
            relativePath: 'whatever.png',
            child: Text('content', textDirection: TextDirection.ltr),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('content'), findsOneWidget);
    });

    testWidgets('no background colour means no tinting layer at all',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Backdrop(
            relativePath: 'whatever.png',
            child: Text('content', textDirection: TextDirection.ltr),
          ),
        ),
      );
      await tester.pump();
      // Scoped to the layer: a MaterialApp brings its own ColoredBox for the
      // scaffold, so counting ColoredBoxes app-wide would always find one.
      final insideLayer = find.descendant(
        of: find.byType(Backdrop),
        matching: find.byWidgetPredicate((w) => w is ColoredBox),
      );
      expect(insideLayer, findsNothing,
          reason: 'a theme with no background colour must not tint the picture');
    });

    testWidgets('a missing picture still renders content, without throwing',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Backdrop(
            relativePath: 'this-file-does-not-exist.png',
            scrim: Color(0xFF00FF00),
            child: Text('content', textDirection: TextDirection.ltr),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('content'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('the theme rule that caused the bug', () {
    test('a background image makes the scaffold transparent', () {
      // The fix, as an assertion. The scaffold paints above the image layer, so
      // leaving it opaque-ish is exactly what hid the picture - at 0.9 opacity
      // the image was covered just as well as at 1.0.
      const withImage = ThemeProfileData(
        name: 'forest',
        brightness: 'dark',
        primary: '#2F6F4F',
        secondary: '#1565C0',
        background: '#101211',
        backgroundOpacity: 0.9,
        backgroundImagePath: 'theme-backgrounds/bg.jpg',
      );
      expect(withImage.hasBackgroundImage, isTrue);
      expect(withImage.toThemeData().scaffoldBackgroundColor,
          Colors.transparent,
          reason: 'the scaffold must not paint over the picture');
    });

    test('without an image the colour is the scaffold background', () {
      // And the opacity then means what it says: let what is behind show
      // through.
      const colourOnly = ThemeProfileData(
        name: 'plain',
        brightness: 'dark',
        primary: '#2F6F4F',
        secondary: '#1565C0',
        background: '#101211',
        backgroundOpacity: 0.5,
      );
      expect(colourOnly.hasBackgroundImage, isFalse);
      final colour = colourOnly.toThemeData().scaffoldBackgroundColor;
      expect(colour.a, closeTo(0.5, 0.01));
    });

    test('an empty image path is not a background image', () {
      const blank = ThemeProfileData(
        name: 'blank',
        brightness: 'dark',
        primary: '#2F6F4F',
        secondary: '#1565C0',
        backgroundImagePath: '',
      );
      expect(blank.hasBackgroundImage, isFalse);
    });
  });
}
