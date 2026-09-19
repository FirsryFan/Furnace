import 'dart:convert';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:knowflow/core/theme/theme_profile.dart';

/// Theme JSON document (spec §4 / GAP D13): import/export round trip, lenient
/// parsing, and the documented 80%-150% scale bounds.
void main() {
  group('round trip', () {
    test('encode then decode preserves every field', () {
      const original = ThemeProfileData(
        name: '深潜',
        brightness: 'dark',
        primary: '#123456',
        secondary: '#654321',
        surface: '#101010',
        background: '#000000',
        backgroundOpacity: 0.72,
        backgroundImagePath: 'themes/bg.webp',
        backgroundBlur: 4,
        uiFont: 'System',
        editorFont: 'LXGW WenKai',
        scale: 1.25,
        animations: false,
      );

      final restored = ThemeProfileData.decode(original.encode());
      expect(restored.name, original.name);
      expect(restored.brightness, original.brightness);
      expect(restored.primary, original.primary);
      expect(restored.secondary, original.secondary);
      expect(restored.surface, original.surface);
      expect(restored.background, original.background);
      expect(restored.backgroundOpacity, original.backgroundOpacity);
      expect(restored.backgroundImagePath, original.backgroundImagePath);
      expect(restored.backgroundBlur, original.backgroundBlur);
      expect(restored.uiFont, original.uiFont);
      expect(restored.editorFont, original.editorFont);
      expect(restored.scale, original.scale);
      expect(restored.animations, original.animations);
    });

    test('the encoded document keeps the documented shape', () {
      final json = jsonDecode(ThemeProfileData.builtinDark.encode())
          as Map<String, dynamic>;
      expect(json['schemaVersion'], 1);
      expect(json['colors'], isA<Map<String, dynamic>>());
      expect(json['background'], isA<Map<String, dynamic>>());
      expect(json['fonts'], isA<Map<String, dynamic>>());
    });
  });

  group('lenient parsing (a hand-edited or newer file must still load)', () {
    test('unknown keys are ignored', () {
      final profile = ThemeProfileData.decode('''
{"name":"x","brightness":"light","futureField":123,
 "colors":{"primary":"#FF0000","brandNew":"#00FF00"}}
''');
      expect(profile.name, 'x');
      expect(profile.primary, '#FF0000');
    });

    test('missing keys fall back to documented defaults', () {
      final profile = ThemeProfileData.decode('{}');
      expect(profile.brightness, 'dark');
      expect(profile.scale, 1.0);
      expect(profile.animations, isTrue);
      expect(profile.backgroundOpacity, 1.0);
    });

    test('scale is clamped into 0.8..1.5', () {
      expect(ThemeProfileData.decode('{"scale":5}').scale, ThemeScale.max);
      expect(ThemeProfileData.decode('{"scale":0.1}').scale, ThemeScale.min);
      expect(ThemeScale.clamp(1.2), 1.2);
    });

    test('background opacity is clamped into 0..1', () {
      expect(
        ThemeProfileData.decode('{"background":{"opacity":3}}')
            .backgroundOpacity,
        1.0,
      );
      expect(
        ThemeProfileData.decode('{"background":{"opacity":-1}}')
            .backgroundOpacity,
        0.0,
      );
    });

    test('a non-object document is rejected', () {
      expect(() => ThemeProfileData.decode('[]'), throwsFormatException);
    });

    test('malformed JSON throws instead of returning a broken theme', () {
      expect(() => ThemeProfileData.decode('{not json'), throwsFormatException);
    });
  });

  group('colour parsing', () {
    const fallback = Color(0xFF010203);

    test('accepts #RRGGBB, RRGGBB and #AARRGGBB', () {
      expect(ThemeProfileData.colorOf('#FF0000', fallback: fallback),
          const Color(0xFFFF0000));
      expect(ThemeProfileData.colorOf('00FF00', fallback: fallback),
          const Color(0xFF00FF00));
      expect(ThemeProfileData.colorOf('#8000FF00', fallback: fallback),
          const Color(0x8000FF00));
    });

    test('falls back on junk instead of crashing', () {
      expect(ThemeProfileData.colorOf('not-a-colour', fallback: fallback),
          fallback);
      expect(ThemeProfileData.colorOf('#12345', fallback: fallback), fallback);
      expect(ThemeProfileData.colorOf(null, fallback: fallback), fallback);
    });
  });

  group('built-in themes', () {
    test('both built-ins exist and differ', () {
      expect(ThemeProfileData.builtinDark.isDark, isTrue);
      expect(ThemeProfileData.builtinLight.isDark, isFalse);
      expect(ThemeProfileData.builtinLight.background,
          isNot(ThemeProfileData.builtinDark.background));
    });

    test('they build usable ThemeData', () {
      final dark = ThemeProfileData.builtinDark.toThemeData();
      final light = ThemeProfileData.builtinLight.toThemeData();
      expect(dark.brightness, Brightness.dark);
      expect(light.brightness, Brightness.light);
      // The explicit surface override must survive into the scheme.
      expect(dark.colorScheme.surface,
          ThemeProfileData.colorOf(ThemeProfileData.builtinDark.surface,
              fallback: dark.colorScheme.surface));
    });
  });

  group('copyWith', () {
    test('changes only what is passed', () {
      const base = ThemeProfileData.builtinDark;
      final changed = base.copyWith(scale: 1.4, animations: false);
      expect(changed.scale, 1.4);
      expect(changed.animations, isFalse);
      expect(changed.name, base.name);
      expect(changed.primary, base.primary);
    });

    test('a background image can be cleared explicitly', () {
      const withImage = ThemeProfileData(
        name: 'x',
        backgroundImagePath: 'themes/a.png',
      );
      expect(withImage.copyWith().backgroundImagePath, 'themes/a.png');
      expect(withImage.copyWith(clearBackgroundImage: true).backgroundImagePath,
          isNull);
    });
  });
}
