/// 定点找题面板的纯逻辑与交互测试（不联网：链接只是字符串）。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/zujuan/zujuan_query.dart';
import 'package:furnace/features/questions/presentation/zujuan_pick_panel.dart';
import 'package:furnace/l10n/app_localizations.dart';

void main() {
  group('链接构造（纯逻辑）', () {
    test('表单学科 → 面板默认学科：认不出回退数学', () {
      expect(zujuanPickDefaultSubject(null), ZujuanSubject.math);
      expect(zujuanPickDefaultSubject(''), ZujuanSubject.math);
      expect(zujuanPickDefaultSubject('physics'), ZujuanSubject.physics);
      expect(zujuanPickDefaultSubject('gzwl'), ZujuanSubject.physics);
      expect(zujuanPickDefaultSubject('history'), ZujuanSubject.math);
      expect(zujuanPickDefaultSubject('informatics'), ZujuanSubject.math);
    });

    test('年份候选从今年 +1 往回数', () {
      expect(
        zujuanPickYearOptions(currentYear: 2026),
        <int>[2027, 2026, 2025, 2024, 2023, 2022, 2021, 2020],
      );
      expect(
        zujuanPickYearOptions(currentYear: 2026, count: 3),
        <int>[2027, 2026, 2025],
      );
    });

    test('省份名 → 行政区码：认不出回退 null', () {
      expect(zujuanPickProvinceCode('浙江'), '330000');
      expect(zujuanPickProvinceCode(' 北京 '), '110000');
      expect(zujuanPickProvinceCode(null), isNull);
      expect(zujuanPickProvinceCode(''), isNull);
      expect(zujuanPickProvinceCode('不存在的省'), isNull);
    });

    test('空条件只到学科根节点；非法知识点 id 由域层忽略', () {
      final base = zujuanPickUrlFor(
        zujuanPickSpec(subject: ZujuanSubject.math),
      );
      expect(base, 'https://zujuan.xkw.com/gzsx/zsd27925/');
      final invalid = zujuanPickUrlFor(
        zujuanPickSpec(
          subject: ZujuanSubject.math,
          knowledgePointId: 'abc',
        ),
      );
      expect(invalid, base);
    });

    test('条件齐全时链接按域层段序拼好', () {
      final url = zujuanPickUrlFor(
        zujuanPickSpec(
          subject: ZujuanSubject.physics,
          knowledgePointId: '999',
          difficulty: ZujuanDifficulty.hard,
          year: 2024,
          provinceName: '浙江',
          grade: 12,
          sort: ZujuanSort.latest,
        ),
      );
      expect(url, startsWith('https://zujuan.xkw.com/gzwl/zsd999/'));
      expect(url, contains('d3'));
      expect(url, contains('y2024'));
      expect(url, contains('a330000'));
      expect(url, contains('g12'));
      expect(url, contains('o2'));
    });

    test('「更早」用 -1 段', () {
      final url = zujuanPickUrlFor(
        zujuanPickSpec(subject: ZujuanSubject.math, year: -1),
      );
      expect(url, contains('y-1'));
    });
  });

  group('面板交互', () {
    testWidgets('默认学科跟表单走，URL 实时显示', (tester) async {
      final strings = await _pumpPanel(tester, initialSubjectKey: 'physics');
      expect(find.text(strings.zujuanPickTitle), findsOneWidget);
      expect(_url(tester), contains('/gzwl/'));
      expect(_url(tester), contains('zsd41934'));
    });

    testWidgets('切学科 / 难度 / 年份 / 年级 / 排序都会改 URL', (tester) async {
      await _pumpPanel(tester, initialSubjectKey: 'math');
      expect(_url(tester), contains('/gzsx/'));

      await _select(tester, zujuanPickSubjectFieldKey, '物理');
      expect(_url(tester), contains('/gzwl/'));

      await _select(tester, zujuanPickDifficultyFieldKey, '困难');
      expect(_url(tester), contains('d3'));

      await _select(tester, zujuanPickYearFieldKey, '更早');
      expect(_url(tester), contains('y-1'));

      await _select(tester, zujuanPickGradeFieldKey, '高三');
      expect(_url(tester), contains('g12'));

      await _select(tester, zujuanPickSortFieldKey, '最新');
      expect(_url(tester), contains('o2'));
    });

    testWidgets('知识点 id：填了换节点，清空回学科根节点', (tester) async {
      await _pumpPanel(tester, initialSubjectKey: 'math');
      await tester.enterText(
        find.byKey(zujuanPickKnowledgePointFieldKey),
        '123456',
      );
      await tester.pumpAndSettle();
      expect(_url(tester), contains('/zsd123456/'));

      await tester.enterText(find.byKey(zujuanPickKnowledgePointFieldKey), '');
      await tester.pumpAndSettle();
      expect(_url(tester), contains('/zsd27925/'));
    });

    testWidgets('复制链接：先写剪贴板，再关面板，再提示', (tester) async {
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          calls.add(call);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final strings = await _pumpPanel(tester, initialSubjectKey: 'math');
      final expected = _url(tester);

      await tester.tap(find.byKey(zujuanPickCopyKey));
      await tester.pumpAndSettle();

      final setData =
          calls.where((call) => call.method == 'Clipboard.setData').toList();
      expect(setData, hasLength(1));
      expect((setData.single.arguments as Map)['text'], expected);
      expect(find.text(strings.zujuanPickCopied), findsOneWidget);
      expect(find.byKey(zujuanPickSheetKey), findsNothing);
    });

    testWidgets('关闭按钮只关面板，不写剪贴板', (tester) async {
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          calls.add(call);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final strings = await _pumpPanel(tester, initialSubjectKey: 'math');

      await tester.tap(find.text(strings.commonClose));
      await tester.pumpAndSettle();

      expect(find.byKey(zujuanPickSheetKey), findsNothing);
      expect(
        calls.where((call) => call.method == 'Clipboard.setData'),
        isEmpty,
      );
    });
  });
}

String _url(WidgetTester tester) =>
    tester.widget<SelectableText>(find.byKey(zujuanPickUrlKey)).data ?? '';

Future<void> _select(WidgetTester tester, Key fieldKey, String label) async {
  await tester.tap(find.byKey(fieldKey));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

Future<AppLocalizations> _pumpPanel(
  WidgetTester tester, {
  String? initialSubjectKey,
}) async {
  tester.view.physicalSize = const Size(1200, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              key: const Key('open-pick'),
              onPressed: () => showZujuanPickPanel(
                context,
                l10n: AppLocalizations.of(context),
                initialSubjectKey: initialSubjectKey,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const Key('open-pick')));
  await tester.pumpAndSettle();
  return AppLocalizations.of(
      tester.element(find.byKey(const Key('open-pick'))));
}
