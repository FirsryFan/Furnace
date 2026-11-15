// task-64：4 档预设 + 3 题小样的选择页。
//
// 这里钉五件事：
// 1) `assets/preset_scoring.json` 存在、是精简 asset（< 30 KB）、4 档齐全；
// 2) 每档的 `x.xx/18`、期望率、90% 区间与 PRESET-SCORING-2026-11-15.json 一致；
// 3) 页面明显标「3 题小样 / 预设估计 / 非高考分」，且**不**把 18 分小样映射成
//    任何高考分（用户明确禁止"预计高考 120/130"这类显示）；
// 4) 选择生效：点选后横幅显示"已选预设（可随时改）"，改选会更新；状态只在内层；
// 5) 选择生效：点选后横幅显示"已选预设（可随时改）"，改选会更新；状态只在内层。
//
// 设置页入口的断言在 settings_preset_entry_test.dart（那个文件要编译 DB 层，
// 与页面测试分开，避免一个模块的临时编译错误把整组 asset/页面测试拖下水）。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/features/student_preset/application/preset_selection.dart';
import 'package:furnace/features/student_preset/data/preset_scoring_source.dart';
import 'package:furnace/features/student_preset/domain/preset_scoring.dart';
import 'package:furnace/features/student_preset/presentation/preset_select_page.dart';

class _FakeSource implements PresetScoringSource {
  _FakeSource(this.data);

  final PresetScoringData data;

  @override
  Future<PresetScoringData> load() async => data;
}

Future<PresetScoringData> _loadAsset() async {
  final file = File('assets/preset_scoring.json');
  expect(
    await file.exists(),
    isTrue,
    reason: '本地 asset 必须存在：assets/preset_scoring.json',
  );
  return PresetScoringData.decode(await file.readAsString());
}

/// 收集页面上所有 Text 文本，用于"不出现高考分映射"的负向断言。
String _visibleText(WidgetTester tester) {
  final buffer = StringBuffer();
  for (final widget in tester.widgetList<Text>(find.byType(Text))) {
    buffer.writeln(widget.data ?? widget.textSpan?.toPlainText() ?? '');
  }
  return buffer.toString();
}

void main() {
  // 真实文件 IO 不在 fake-async 区里做（与 design_board 测试同一做法）。
  late PresetScoringData assetData;

  setUpAll(() async {
    assetData = await _loadAsset();
  });

  group('preset_scoring.json asset', () {
    test('精简 asset：4 档齐全、顺序与 id 固定', () async {
      final file = File('assets/preset_scoring.json');
      final bytes = await file.length();
      expect(
        bytes,
        lessThan(30 * 1024),
        reason: '紧凑 asset：不能把整份报告搬进 app（实际 $bytes bytes）',
      );

      expect(assetData.schema, 'furnace.preset-select/0.1');
      expect(assetData.sourceDocument, 'PRESET-SCORING-2026-11-15.json');
      expect(assetData.sourceStatus, 'prototype_uncalibrated');

      expect(assetData.presets.map((p) => p.id).toList(), <String>[
        'preset-weak',
        'preset-medium',
        'preset-above',
        'preset-top',
      ]);
      expect(assetData.presets.map((p) => p.name).toList(), <String>[
        '基础薄弱',
        '中等',
        '中上',
        '拔尖',
      ]);
    });

    test('三题小样分值/期望率/区间与 PRESET-SCORING JSON 一致', () {
      // 期望值逐条来自 PRESET-SCORING-2026-11-15.json
      // sample_summary.per_preset（JSON 精确值，不是报告里四舍五入后的显示）。
      const expected = <String, (double, double, double, double)>{
        'preset-weak': (4.584, 0.2547, 3.678, 5.41),
        'preset-medium': (7.491, 0.4162, 6.255, 8.508),
        'preset-above': (9.988, 0.5549, 8.603, 11.088),
        'preset-top': (13.2, 0.7333, 11.757, 14.218),
      };

      for (final preset in assetData.presets) {
        final want = expected[preset.id]!;
        expect(preset.expectedPoints, closeTo(want.$1, 1e-9), reason: preset.id);
        expect(preset.rate, closeTo(want.$2, 1e-9), reason: preset.id);
        expect(preset.intervalLow, closeTo(want.$3, 1e-9), reason: preset.id);
        expect(preset.intervalHigh, closeTo(want.$4, 1e-9), reason: preset.id);
        expect(preset.pointsTotal, 18.0);
        // 卡片上的分数显示（4.58/18 这类）与 JSON 数值一致。
        expect(
          preset.pointsLabel,
          '${want.$1.toStringAsFixed(2)}/18',
          reason: preset.id,
        );
        expect(
          preset.rateLabel,
          '${(want.$2 * 100).toStringAsFixed(1)}%',
          reason: preset.id,
        );
      }

      expect(
        assetData.presets.map((p) => p.pointsLabel).toList(),
        <String>['4.58/18', '7.49/18', '9.99/18', '13.20/18'],
      );
      expect(
        assetData.presets.map((p) => p.rateLabel).toList(),
        <String>['25.5%', '41.6%', '55.5%', '73.3%'],
      );
    });

    test('每档三题分项之和 = 该档总期望分（JSON 内部一致）', () {
      for (final preset in assetData.presets) {
        final sum = preset.questionLines.fold<double>(
          0,
          (total, line) => total + line.expectedPoints,
        );
        expect(sum, closeTo(preset.expectedPoints, 0.002), reason: preset.id);
        expect(preset.questionLines.length, 3, reason: preset.id);
        expect(preset.questionLines.map((l) => l.subjectLabel).toList(), <String>[
          '物理',
          '数学',
          '语文',
        ]);
      }
    });

    test('18 分是原型尺度：不是完整真题、不是测量', () {
      expect(assetData.sample.questionCount, 3);
      expect(assetData.sample.pointsTotal, 18.0);
      expect(assetData.sample.pointsPerQuestion, 6.0);
      expect(assetData.sample.isFullExam, isFalse);
      expect(assetData.sample.isMeasurement, isFalse);
      expect(assetData.sample.scaleNote, contains('不能'));
      expect(assetData.sample.questions.length, 3);
      expect(assetData.sample.questions.first.id, 'Q-PH0001');
      expect(assetData.sample.questions.last.id, 'Q-CH0001');
    });

    test('标记文字明确：3 题小样 / 预设估计 / 不是高考分', () {
      expect(presetDisclaimerBadges, <String>['3 题小样', '预设估计', '非高考分']);
      final all = assetData.disclaimers.join('\n');
      expect(all, contains('3 题小样'));
      expect(all, contains('预设估计'));
      expect(all, contains('不是高考分'));
      expect(all, contains('不是真实成绩'));
      expect(assetData.oneLine, contains('不是真实成绩'));
    });
  });

  group('PresetSelectPage', () {
    Future<ProviderContainer> pumpPage(
      WidgetTester tester, {
      PresetSelection? selection,
    }) async {
      tester.view.physicalSize = const Size(1200, 3600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final container = ProviderContainer();
      addTearDown(container.dispose);
      if (selection != null) {
        container.read(presetSelectionProvider.notifier).state = selection;
      }
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: PresetSelectPage(source: _FakeSource(assetData)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return container;
    }

    testWidgets('4 档卡片都在，分数/18 与标记可见', (tester) async {
      await pumpPage(tester);

      for (final name in <String>['基础薄弱', '中等', '中上', '拔尖']) {
        expect(find.text(name), findsOneWidget, reason: name);
      }
      expect(find.text('4.58/18'), findsOneWidget);
      expect(find.text('7.49/18'), findsOneWidget);
      expect(find.text('9.99/18'), findsOneWidget);
      expect(find.text('13.20/18'), findsOneWidget);

      // 顶部边界卡 + 每张卡上的三个标记（4 卡 × 3 标记 + 顶部 3 标记）。
      expect(find.text('3 题小样'), findsNWidgets(5));
      expect(find.text('预设估计'), findsNWidgets(5));
      expect(find.text('非高考分'), findsNWidgets(5));
      expect(find.text('这是 3 题小样诊断，不是高考分'), findsOneWidget);
      expect(find.textContaining('90% 模型区间'), findsWidgets);
      expect(find.textContaining('预计卡点'), findsWidgets);
      expect(find.textContaining('强项：'), findsNWidgets(4));
      expect(find.textContaining('弱项：'), findsNWidgets(4));
    });

    testWidgets('不把 18 分小样映射成任何高考分（无 150/预计高考/预估分）', (tester) async {
      await pumpPage(tester);

      final text = _visibleText(tester);
      expect(RegExp(r'预计高考').hasMatch(text), isFalse);
      expect(RegExp(r'预估高考').hasMatch(text), isFalse);
      expect(RegExp(r'预估分').hasMatch(text), isFalse);
      expect(RegExp(r'150').hasMatch(text), isFalse);
      // 任何"高考 + 数字 + 分"的疑似分数承诺都不许出现。
      expect(RegExp(r'高考\s*\d+\s*分').hasMatch(text), isFalse);
      expect(RegExp(r'\d+\s*/\s*150').hasMatch(text), isFalse);
      // 但反过来的边界说明必须在。
      expect(RegExp(r'不是高考分').hasMatch(text), isTrue);
    });

    testWidgets('选择生效：横幅显示已选预设（可随时改），改选后更新', (tester) async {
      final container = await pumpPage(tester);

      await tester.tap(find.byKey(presetSelectButtonKey('preset-medium')));
      await tester.pumpAndSettle();

      expect(find.byKey(presetSelectedBannerKey), findsOneWidget);
      // SnackBar 也带同一句前缀，所以只在横幅子树里断言。
      expect(
        find.descendant(
          of: find.byKey(presetSelectedBannerKey),
          matching: find.textContaining('已选预设：中等'),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('可随时改'), findsWidgets);
      expect(
        container.read(presetSelectionProvider),
        const PresetSelection(presetId: 'preset-medium', presetName: '中等'),
      );

      await tester.tap(find.byKey(presetSelectButtonKey('preset-top')));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byKey(presetSelectedBannerKey),
          matching: find.textContaining('已选预设：拔尖'),
        ),
        findsOneWidget,
      );
      expect(
        container.read(presetSelectionProvider),
        const PresetSelection(presetId: 'preset-top', presetName: '拔尖'),
      );
      // 选中卡换高亮/按钮文案，原来那档回到"选这一档"。
      expect(find.text('已选（可改选其他档）'), findsOneWidget);
    });
  });
}
