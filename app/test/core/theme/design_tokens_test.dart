import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/core/theme/design_tokens.dart';
import 'package:furnace/core/theme/theme_profile.dart';

void main() {
  group('AppSpacing', () {
    test('除 2pt 视觉半步外都在 4pt 栅格上', () {
      for (final step in AppSpacing.scale) {
        expect(step > 0, isTrue, reason: 'step $step');
        if (step != AppSpacing.xxs) {
          expect(step % 4, 0, reason: 'step $step 不在 4pt 栅格上');
        }
      }
      expect(
          AppSpacing.scale,
          orderedEquals(<double>[
            2,
            4,
            8,
            12,
            16,
            24,
            32,
            48,
          ]));
    });

    test('snap 把离栅格值吸附到最近的档', () {
      expect(AppSpacing.snap(14), AppSpacing.md); // 12
      expect(AppSpacing.snap(15), AppSpacing.lg); // 16
      expect(AppSpacing.snap(18), AppSpacing.lg); // 16
      expect(AppSpacing.snap(100), AppSpacing.xxxl);
      expect(AppSpacing.snap(0), AppSpacing.xxs);
    });
  });

  group('AppRadius', () {
    test('四档半径与 BorderRadius 常量一致', () {
      expect(AppRadius.controlBorder.topLeft.x, 6);
      expect(AppRadius.cardBorder.topLeft.x, 10);
      expect(AppRadius.sheetBorder.topLeft.x, 14);
      expect(AppRadius.pillBorder.topLeft.x, 999);
    });
  });

  group('AppTokens', () {
    testWidgets('未安装扩展时 of 返回 standard，而不是 null', (tester) async {
      late AppTokens read;
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: Builder(
          builder: (context) {
            read = AppTokens.of(context);
            return const SizedBox.shrink();
          },
        ),
      ));
      expect(read.spaceMd, AppSpacing.md);
      expect(read.pageTitle.fontSize, 20);
      expect(identical(read, AppTokens.standard), isTrue);
    });

    test('toThemeData 安装了 tokens，字号与圆角来自语义档', () {
      final theme = ThemeProfileData.builtinLight.toThemeData();
      final tokens = theme.extension<AppTokens>();
      expect(tokens, isNotNull);
      expect(tokens!.pageTitle.fontSize, 20);
      expect(tokens.sectionTitle.fontSize, 16);
      expect(tokens.body.fontSize, 14);
      expect(tokens.caption.fontSize, 12);
      expect(tokens.cardRadius, AppRadius.card);
      expect(tokens.sheetBorder.topLeft.x, AppRadius.sheet);
    });

    test('编辑器字体只进正文 token，不进标题 token', () {
      final theme = const ThemeProfileData(
        name: '测试主题',
        editorFont: 'Noto Serif',
      ).toThemeData();
      final tokens = theme.extension<AppTokens>()!;
      expect(tokens.body.fontFamily, 'Noto Serif');
      expect(tokens.caption.fontFamily, 'Noto Serif');
      expect(tokens.pageTitle.fontFamily, isNot('Noto Serif'));
      expect(tokens.sectionTitle.fontFamily, isNot('Noto Serif'));
    });

    test('copyWith 只改传入字段', () {
      const tokens = AppTokens.standard;
      final wider = tokens.copyWith(spaceMd: 20);
      expect(wider.spaceMd, 20);
      expect(wider.spaceLg, tokens.spaceLg);
      expect(wider.cardRadius, tokens.cardRadius);
    });

    test('lerp 在两端之间插值', () {
      const a = AppTokens(spaceMd: 8);
      const b = AppTokens(spaceMd: 16);
      expect(a.lerp(b, 0.5).spaceMd, 12);
      expect(a.lerp(null, 0.5).spaceMd, 8);
    });
  });
}
