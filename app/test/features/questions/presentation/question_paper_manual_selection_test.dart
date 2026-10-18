/// 组卷页「手工指定 / 排除」的界面契约：状态只写 paperSpecProvider，结果只读 PaperPlan。
///
/// 三条纪律（与学科/领域配额同一套）：
/// 1. 名单状态只认 PaperSpecNotifier（toggleManualInclude / toggleManualExclude /
///    clearManualSelection / setManualIncludeIds / setManualExcludeIds）；
/// 2. 生成后的缺失 / 被挤掉 / 冲突三类名单全部来自 PaperPlan，界面只排版不改数字；
/// 3. 找不到的 id（缺失名单）直接显示原始 id，不摆「未编号」冒充一道题。
library;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart' show NativeDatabase;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/domain/services/cognitive/library_diagnosis.dart';
import 'package:furnace/domain/services/paper/paper_composer.dart';
import 'package:furnace/features/cognitive/presentation/cognitive_model_page.dart';
import 'package:furnace/features/questions/application/paper_plan_provider.dart';
import 'package:furnace/features/questions/presentation/paper_manual_selection_view.dart';
import 'package:furnace/features/questions/presentation/question_paper_page.dart';
import 'package:furnace/l10n/app_localizations.dart';

/// 固定时间戳：让排序在测试里也是确定的。
const int _ts = 1700000000000;

void main() {
  late AppDatabase db;
  late AppLocalizations zh;

  setUpAll(() async {
    zh = await AppLocalizations.delegate.load(const Locale('zh'));
  });

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  group('纯函数：名单排序与题干预览', () {
    test('题目 id 去空、去重、字典序', () {
      expect(
        paperManualSortedIds(<String>['q-b', ' q-a ', 'q-b', '', '   ']),
        <String>['q-a', 'q-b'],
      );
      expect(paperManualSortedIds(null), isEmpty);
    });

    test('题干预览：折掉换行与连续空白，超长截断', () {
      expect(paperManualStemPreview('  a\n\n  b  '), 'a b');
      expect(paperManualStemPreview('   '), '');
      expect(paperManualStemPreview('一二三四五', maxChars: 3), '一二三…');
      expect(paperManualStemPreview('短题干'), '短题干');
    });
  });

  group('纯函数：候选过滤', () {
    test('题干或 id 包含查询（不区分大小写），空查询全留', () {
      const candidates = <PaperCandidate>[
        PaperCandidate(questionId: 'q-func', subjectKey: 'math'),
        PaperCandidate(questionId: 'q-set', subjectKey: 'math'),
        PaperCandidate(questionId: 'ID-ABC', subjectKey: 'math'),
      ];
      const stems = <String, String>{
        'q-func': '求函数单调区间',
        'q-set': '求集合交集',
        'ID-ABC': '证明三角形全等',
      };

      expect(paperManualFilterCandidates(candidates, stems, ''), candidates);
      expect(
        paperManualFilterCandidates(candidates, stems, '集合')
            .map((c) => c.questionId)
            .toList(),
        <String>['q-set'],
      );
      expect(
        paperManualFilterCandidates(candidates, stems, 'id-ab')
            .map((c) => c.questionId)
            .toList(),
        <String>['ID-ABC'],
      );
      expect(paperManualFilterCandidates(candidates, stems, '不存在'), isEmpty);
    });
  });

  group('纯函数：三类名单聚合与结果卡可见性', () {
    test('顺序 缺失 -> 挤掉 -> 冲突，每类只留前 N 条并报总数', () {
      final plan = _plan(
        included: 2,
        missing: <String>['m-1', 'm-2', 'm-3'],
        skipped: <String>['s-1', 's-2'],
        conflict: <String>['c-1'],
      );
      final groups = paperManualIssueGroups(plan, maxPerGroup: 2);

      expect(
        groups.map((g) => g.kind).toList(),
        <PaperManualIssueKind>[
          PaperManualIssueKind.missing,
          PaperManualIssueKind.skipped,
          PaperManualIssueKind.conflict,
        ],
      );
      expect(groups[0].visibleIds, <String>['m-1', 'm-2']);
      expect(groups[0].totalCount, 3);
      expect(groups[0].hiddenCount, 1);
      expect(groups[0].hasHidden, isTrue);
      expect(groups[1].visibleIds, <String>['s-1', 's-2']);
      expect(groups[1].hasHidden, isFalse);
      expect(groups[2].visibleIds, <String>['c-1']);
    });

    test('没有任何名单时不产生分组', () {
      final plan = _plan();
      expect(paperManualIssueGroups(plan), isEmpty);
      expect(paperManualOutcomeVisible(plan), isFalse);
    });

    test('结果卡只在启用且确实收下/有问题名单时出现', () {
      expect(paperManualOutcomeVisible(_plan(enabled: false, included: 1)),
          isFalse);
      expect(paperManualOutcomeVisible(_plan(included: 1)), isTrue);
      expect(
          paperManualOutcomeVisible(_plan(missing: <String>['ghost'])), isTrue);
      expect(paperManualOutcomeVisible(_plan(enabled: true)), isFalse);
    });
  });

  group('widget：入口、对话框与名单展示', () {
    testWidgets('默认没有名单：摆「选择题」入口，不摆名单卡与结果卡', (tester) async {
      await _seedQuestion(db, id: 'q-1', stem: '求函数单调区间');
      await _pumpPaperPage(tester, db: db);

      expect(find.byKey(paperManualSelectionAddKey), findsOneWidget);
      expect(find.byKey(paperManualSelectionSectionKey), findsNothing);
      expect(find.byKey(paperManualSelectionOutcomeKey), findsNothing);
    });

    testWidgets('从对话框设为必收：spec 写入、名单卡出现、结果卡报收下 1 道', (tester) async {
      await _seedQuestion(db, id: 'q-1', stem: '求函数单调区间');
      final container = await _pumpPaperPage(tester, db: db);

      await _openPicker(tester);
      expect(find.byKey(paperManualSelectionPickerKey), findsOneWidget);
      await tester.tap(find.byKey(paperManualPickerIncludeKey('q-1')));
      await tester.pump();
      expect(
        container.read(paperSpecProvider).manualIncludeQuestionIds,
        <String>{'q-1'},
      );

      await _closePicker(tester, zh);
      expect(find.byKey(paperManualSelectionSectionKey), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(paperManualSelectionIncludeRowKey('q-1')),
          matching: find.text('求函数单调区间'),
        ),
        findsOneWidget,
      );
      expect(find.text(zh.paperManualSelectionIncludeTitle(1)), findsOneWidget);

      final plan = _readPlan(container);
      expect(plan.manualSelectionEnabled, isTrue);
      expect(plan.manualIncludedCount, 1);
      expect(plan.items.single.questionId, 'q-1');
      expect(find.byKey(paperManualSelectionOutcomeKey), findsOneWidget);
      expect(
        find.text(zh.paperManualSelectionOutcomeIncluded(1)),
        findsOneWidget,
      );
    });

    testWidgets('从对话框设为排除：卷面不再有这道题，排除优先名单不摆结果卡', (tester) async {
      await _seedQuestion(db, id: 'q-1', stem: '求函数单调区间');
      await _seedQuestion(db, id: 'q-2', stem: '求集合交集');
      final container = await _pumpPaperPage(tester, db: db);

      await _openPicker(tester);
      await tester.tap(find.byKey(paperManualPickerExcludeKey('q-2')));
      await tester.pump();
      expect(
        container.read(paperSpecProvider).manualExcludeQuestionIds,
        <String>{'q-2'},
      );

      await _closePicker(tester, zh);
      expect(find.byKey(paperManualSelectionSectionKey), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(paperManualSelectionExcludeRowKey('q-2')),
          matching: find.text('求集合交集'),
        ),
        findsOneWidget,
      );

      final plan = _readPlan(container);
      expect(
          plan.items.map((item) => item.questionId).toList(), <String>['q-1']);
      expect(find.byKey(paperManualSelectionOutcomeKey), findsNothing);
    });

    testWidgets('行内移除：名单回到不启用，名单卡消失', (tester) async {
      await _seedQuestion(db, id: 'q-1', stem: '求函数单调区间');
      final container = await _pumpPaperPage(tester, db: db);
      container.read(paperSpecProvider.notifier).setManualIncludeIds(
        <String>{'q-1'},
      );
      await _settle(tester);
      expect(find.byKey(paperManualSelectionSectionKey), findsOneWidget);

      await tester.tap(find.byKey(paperManualSelectionIncludeRemoveKey('q-1')));
      await _settle(tester);

      expect(
        container.read(paperSpecProvider).manualIncludeQuestionIds,
        isNull,
      );
      expect(find.byKey(paperManualSelectionSectionKey), findsNothing);
      expect(find.byKey(paperManualSelectionOutcomeKey), findsNothing);
    });

    testWidgets('一键清空：必收与排除两个名单一起回到不启用', (tester) async {
      await _seedQuestion(db, id: 'q-1', stem: '求函数单调区间');
      await _seedQuestion(db, id: 'q-2', stem: '求集合交集');
      final container = await _pumpPaperPage(tester, db: db);
      final notifier = container.read(paperSpecProvider.notifier);
      notifier.setManualIncludeIds(<String>{'q-1'});
      notifier.setManualExcludeIds(<String>{'q-2'});
      await _settle(tester);
      expect(find.byKey(paperManualSelectionSectionKey), findsOneWidget);

      await tester.tap(find.byKey(paperManualSelectionClearKey));
      await _settle(tester);

      final spec = container.read(paperSpecProvider);
      expect(spec.manualIncludeQuestionIds, isNull);
      expect(spec.manualExcludeQuestionIds, isNull);
      expect(find.byKey(paperManualSelectionSectionKey), findsNothing);
    });

    testWidgets('候选过滤框按题干筛选对话框里的行', (tester) async {
      await _seedQuestion(db, id: 'q-1', stem: '求函数单调区间');
      await _seedQuestion(db, id: 'q-2', stem: '求集合交集');
      await _pumpPaperPage(tester, db: db);

      await _openPicker(tester);
      expect(find.byKey(paperManualPickerIncludeKey('q-1')), findsOneWidget);
      expect(find.byKey(paperManualPickerIncludeKey('q-2')), findsOneWidget);

      await tester.enterText(
        find.byKey(paperManualSelectionPickerFilterKey),
        '集合',
      );
      await tester.pump();

      expect(find.byKey(paperManualPickerIncludeKey('q-1')), findsNothing);
      expect(find.byKey(paperManualPickerIncludeKey('q-2')), findsOneWidget);
    });
  });

  group('widget：生成后的三类名单如实展示', () {
    testWidgets('缺失：题库里没有的 id 直接显示原始 id', (tester) async {
      await _seedQuestion(db, id: 'q-1', stem: '求函数单调区间');
      final container = await _pumpPaperPage(tester, db: db);
      container
          .read(paperSpecProvider.notifier)
          .setManualIncludeIds(<String>{'ghost-q'});
      await _settle(tester);

      final plan = _readPlan(container);
      expect(plan.manualMissingQuestionIds, <String>['ghost-q']);
      expect(plan.manualIncludedCount, 0);
      expect(find.byKey(paperManualSelectionOutcomeKey), findsOneWidget);
      expect(find.text(zh.paperManualSelectionMissingTitle(1)), findsOneWidget);
      // 名单卡里也会显示这个 id（必收栏）；结果卡里那条才是「缺失」的原始 id。
      expect(
        find.descendant(
          of: find.byKey(paperManualSelectionOutcomeKey),
          matching: find.text('ghost-q'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('被目标题数挤掉：报数量与被挤掉的 id', (tester) async {
      await _seedQuestion(db, id: 'q-1', stem: '求函数单调区间');
      await _seedQuestion(db, id: 'q-2', stem: '求集合交集');
      final container = await _pumpPaperPage(tester, db: db);
      final notifier = container.read(paperSpecProvider.notifier);
      notifier.setTargetCount(1);
      notifier.setManualIncludeIds(<String>{'q-1', 'q-2'});
      await _settle(tester);

      final plan = _readPlan(container);
      expect(plan.manualIncludedCount, 1);
      expect(plan.manualSkippedQuestionIds, <String>['q-2']);
      expect(find.text(zh.paperManualSelectionSkippedTitle(1)), findsOneWidget);
    });

    testWidgets('冲突：同一题既必收又排除时排除生效，并如实报冲突', (tester) async {
      await _seedQuestion(db, id: 'q-1', stem: '求函数单调区间');
      final container = await _pumpPaperPage(tester, db: db);
      final notifier = container.read(paperSpecProvider.notifier);
      notifier.setManualIncludeIds(<String>{'q-1'});
      notifier.setManualExcludeIds(<String>{'q-1'});
      await _settle(tester);

      final plan = _readPlan(container);
      expect(plan.manualConflictQuestionIds, <String>['q-1']);
      expect(plan.manualIncludedCount, 0);
      expect(plan.items, isEmpty);
      expect(find.byKey(paperManualSelectionOutcomeKey), findsOneWidget);
      expect(
          find.text(zh.paperManualSelectionConflictTitle(1)), findsOneWidget);
    });
  });
}

/// 纯函数用例的 PaperPlan：只有手工名单相关字段有意义。
PaperPlan _plan({
  bool enabled = true,
  int included = 0,
  List<String> missing = const <String>[],
  List<String> skipped = const <String>[],
  List<String> conflict = const <String>[],
}) {
  return PaperPlan(
    items: const <PaperItem>[],
    uncoveredKnowledgePointIds: const <String>[],
    deferredKnowledgePointIds: const <String>[],
    byKnowledgePoint: const <String, int>{},
    candidateCount: 0,
    requestedCount: 0,
    overallNeed: 0,
    weights: const PaperWeights(),
    manualSelectionEnabled: enabled,
    manualIncludedCount: included,
    manualMissingQuestionIds: missing,
    manualSkippedQuestionIds: skipped,
    manualConflictQuestionIds: conflict,
  );
}

/// 读当前组卷结果：结果卡片渲染时 provider 应该已经落到 data。
PaperPlan _readPlan(ProviderContainer container) {
  final asyncPlan = container.read(paperPlanProvider);
  expect(asyncPlan.hasValue, isTrue, reason: '组卷结果还没落定时不断言界面');
  return asyncPlan.value!;
}

Future<void> _openPicker(WidgetTester tester) async {
  await tester.tap(find.byKey(paperManualSelectionAddKey));
  // 对话框入场动画 + 题库/题干 future：等动画走完再等进度条消失。
  await tester.pump(const Duration(milliseconds: 400));
  await _settle(tester);
}

Future<void> _closePicker(WidgetTester tester, AppLocalizations l10n) async {
  await tester.tap(find.text(l10n.commonClose));
  await tester.pump(const Duration(milliseconds: 400));
  await _settle(tester);
}

Future<ProviderContainer> _pumpPaperPage(
  WidgetTester tester, {
  required AppDatabase db,
}) async {
  tester.view.physicalSize = const Size(1200, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        cognitiveLibraryDiagnosisProvider
            .overrideWith((ref) async => LibraryDiagnosis.notRun),
      ],
      child: const MaterialApp(
        locale: Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: QuestionPaperPage(),
      ),
    ),
  );
  await _settle(tester);
  return ProviderScope.containerOf(
    tester.element(find.byType(QuestionPaperPage)),
  );
}

/// 等 provider 落定：进度条消失后再多推两帧。
///
/// 不能用 pumpAndSettle：数据还没到时页面上是无限动画的进度条，会超时。
Future<void> _settle(WidgetTester tester, {int rounds = 80}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.pump(const Duration(milliseconds: 20));
    final busy = find.byType(LinearProgressIndicator).evaluate().isNotEmpty ||
        find.byType(CircularProgressIndicator).evaluate().isNotEmpty;
    if (!busy && i >= 2) {
      return;
    }
  }
}

Future<void> _seedQuestion(
  AppDatabase db, {
  required String id,
  required String stem,
}) {
  return db.into(db.questions).insert(
        QuestionsCompanion.insert(
          id: id,
          stem: stem,
          createdAt: _ts,
          updatedAt: _ts,
          subjectKey: const Value<String>('math'),
        ),
      );
}
