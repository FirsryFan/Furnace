/// 组卷页「学科配额」的界面契约：配额区只改 spec，分布/被挡/缺口只排版 PaperPlan。
///
/// 三条纪律：
/// 1. 配额状态只认 `paperSpecProvider`（setSubjectMax / setSubjectMin /
///    clearSubjectQuota），页面不自己存一份配额；
/// 2. 生成后的分布/被挡/缺口全部来自 `PaperPlan`，这里断言的是域层算出来的数字，
///    页面改文案时这些断言应该跟着红，而不是被页面顺手改好；
/// 3. 非法输入不提交：输入框标红，spec 保持原样。
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
import 'package:furnace/domain/services/paper/subject_quota.dart';
import 'package:furnace/features/cognitive/presentation/cognitive_model_page.dart';
import 'package:furnace/features/questions/application/paper_plan_provider.dart';
import 'package:furnace/features/questions/presentation/paper_subject_quota_view.dart';
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

  group('纯函数：配额输入解析', () {
    test('空输入 = 这一条不设限', () {
      final parsed = parsePaperSubjectQuotaInput('   ');
      expect(parsed.isEmpty, isTrue);
      expect(parsed.isInvalid, isFalse);
      expect(parsed.value, isNull);
    });

    test('非负整数是合法输入（上限 0 也合法）', () {
      expect(parsePaperSubjectQuotaInput('3').value, 3);
      expect(parsePaperSubjectQuotaInput(' 12 ').value, 12);
      final zero = parsePaperSubjectQuotaInput('0');
      expect(zero.value, 0);
      expect(zero.isInvalid, isFalse);
    });

    test('负数/小数/文字都不提交', () {
      for (final raw in <String>['-2', '3.5', 'abc', '2 道']) {
        final parsed = parsePaperSubjectQuotaInput(raw);
        expect(parsed.isInvalid, isTrue, reason: raw);
        expect(parsed.value, isNull, reason: raw);
      }
    });
  });

  group('纯函数：学科顺序与分布排序', () {
    test('题库顺序优先，再补只在已选里的学科（字典序）', () {
      expect(
        paperSubjectQuotaSubjects(
          selectedSubjects: <String>{'math', 'physics'},
          bankSubjects: <String>['physics', 'chemistry'],
        ),
        <String>['physics', 'math'],
      );
    });

    test('空白学科键一律丢掉', () {
      expect(
        paperSubjectQuotaSubjects(
          selectedSubjects: <String>{'  ', 'math'},
          bankSubjects: <String>[''],
        ),
        <String>['math'],
      );
    });

    test('分布按数量倒序、同量按学科键升序，0 道不列', () {
      final sorted = paperSubjectDistributionSorted(<String, int>{
        'math': 2,
        'physics': 3,
        'chemistry': 0,
        ' ': 5,
      });
      expect(sorted.map((entry) => entry.key).toList(), <String>[
        'physics',
        'math',
      ]);
      expect(sorted.first.value, 3);
      final tie = paperSubjectDistributionSorted(<String, int>{
        'physics': 2,
        'math': 2,
      });
      expect(
          tie.map((entry) => entry.key).toList(), <String>['math', 'physics']);
    });
  });

  group('纯函数：被挡预览与题干预览', () {
    QuotaBlockedQuestion blockedAt(int index) => QuotaBlockedQuestion(
          questionId: 'q-$index',
          subjectKey: 'math',
          subjectLimit: 2,
        );

    test('最多列 3 条，其余换成「还有几条」', () {
      final blocked = <QuotaBlockedQuestion>[
        for (var index = 0; index < 5; index++) blockedAt(index),
      ];
      expect(paperSubjectQuotaBlockedPreview(blocked), hasLength(3));
      expect(paperSubjectQuotaBlockedHidden(blocked), 2);
      expect(paperSubjectQuotaBlockedHidden(blocked.take(3).toList()), 0);
      expect(paperSubjectQuotaBlockedHidden(blocked.take(1).toList()), 0);
    });

    test('题干预览折空白、超长截断、空题干给空串', () {
      expect(paperSubjectQuotaStemPreview('  已知  函数\n最小值  '), '已知 函数 最小值');
      expect(paperSubjectQuotaStemPreview(''), isEmpty);
      expect(paperSubjectQuotaStemPreview('一二三四五六', maxChars: 4), '一二三四…');
    });

    test('学科显示名走组卷页同一份词表，未知键原样，空键说不限', () {
      expect(paperSubjectLabelOf(zh, 'math'), '数学');
      expect(paperSubjectLabelOf(zh, 'astronomy'), 'astronomy');
      expect(paperSubjectLabelOf(zh, ' '), zh.questionPaperSubjectNone);
    });
  });

  group('widget：配额编辑区', () {
    testWidgets('未选学科时只说明作用范围，选中数学后才出现该科输入框', (tester) async {
      await _seedQuestion(db, id: 'q-math', stem: '数学题', subjectKey: 'math');
      await _seedQuestion(db,
          id: 'q-physics', stem: '物理题', subjectKey: 'physics');

      await _pumpPaperPage(tester, db: db);

      expect(find.byKey(paperSubjectQuotaSectionKey), findsOneWidget);
      expect(find.text(zh.paperSubjectQuotaNoSubjects), findsOneWidget);
      expect(find.byKey(paperSubjectQuotaMaxKey('math')), findsNothing);

      await tester.tap(find.widgetWithText(FilterChip, '数学'));
      await _settle(tester);

      expect(find.text(zh.paperSubjectQuotaNoSubjects), findsNothing);
      expect(find.byKey(paperSubjectQuotaMaxKey('math')), findsOneWidget);
      expect(find.byKey(paperSubjectQuotaMinKey('math')), findsOneWidget);
      expect(
        find.byKey(paperSubjectQuotaMaxKey('physics')),
        findsNothing,
        reason: '没选的学科不摆配额行',
      );
    });

    testWidgets('上限/保底写进 spec；清空配额后输入框清空、按钮回到禁用', (tester) async {
      await _seedQuestion(db, id: 'q-math', stem: '数学题', subjectKey: 'math');
      final container = await _pumpPaperPage(tester, db: db);
      await tester.tap(find.widgetWithText(FilterChip, '数学'));
      await _settle(tester);

      final clearButton = find.byKey(paperSubjectQuotaClearKey);
      expect(
        tester.widget<TextButton>(clearButton).onPressed,
        isNull,
        reason: '没配额时「清空配额」不可点',
      );

      await tester.enterText(_quotaField(paperSubjectQuotaMaxKey('math')), '2');
      await _settle(tester);
      var quota = container.read(paperSpecProvider).subjectQuota;
      expect(quota, isNotNull);
      expect(quota!.maxPerSubject['math'], 2);

      await tester.enterText(_quotaField(paperSubjectQuotaMinKey('math')), '1');
      await _settle(tester);
      quota = container.read(paperSpecProvider).subjectQuota;
      expect(quota!.maxPerSubject['math'], 2, reason: '设保底不能清掉上限');
      expect(quota.minPerSubject['math'], 1);

      await tester.tap(clearButton);
      await _settle(tester);

      expect(container.read(paperSpecProvider).subjectQuota, isNull);
      expect(_quotaText(tester, paperSubjectQuotaMaxKey('math')), isEmpty);
      expect(_quotaText(tester, paperSubjectQuotaMinKey('math')), isEmpty);
      expect(tester.widget<TextButton>(clearButton).onPressed, isNull);
    });

    testWidgets('非法输入不提交、输入框标红；改好后正常提交', (tester) async {
      await _seedQuestion(db, id: 'q-math', stem: '数学题', subjectKey: 'math');
      final container = await _pumpPaperPage(tester, db: db);
      await tester.tap(find.widgetWithText(FilterChip, '数学'));
      await _settle(tester);

      final maxField = _quotaField(paperSubjectQuotaMaxKey('math'));
      await tester.enterText(maxField, '-2');
      await _settle(tester);

      expect(
        container.read(paperSpecProvider).subjectQuota,
        isNull,
        reason: '负数不许写进 spec',
      );
      expect(find.text(zh.paperSubjectQuotaInvalid), findsOneWidget);

      await tester.enterText(maxField, '3.5');
      await _settle(tester);
      expect(
        container.read(paperSpecProvider).subjectQuota,
        isNull,
        reason: '小数同样不许提交',
      );
      expect(find.text(zh.paperSubjectQuotaInvalid), findsOneWidget);

      await tester.enterText(maxField, '4');
      await _settle(tester);
      expect(
        container.read(paperSpecProvider).subjectQuota!.maxPerSubject['math'],
        4,
      );
      expect(find.text(zh.paperSubjectQuotaInvalid), findsNothing);
    });
  });

  group('widget：生成后的分布/被挡/缺口', () {
    testWidgets('没配配额时不摆结果卡片', (tester) async {
      await _seedQuestion(db, id: 'q-math', stem: '数学题', subjectKey: 'math');
      await _pumpPaperPage(tester, db: db);
      expect(find.byKey(paperSubjectQuotaOutcomeKey), findsNothing);
    });

    testWidgets('学科分布 + 被上限挡下的题：数字来自 PaperPlan', (tester) async {
      await _seedQuestion(db, id: 'q-math-1', stem: '数学题一', subjectKey: 'math');
      await _seedQuestion(db, id: 'q-math-2', stem: '数学题二', subjectKey: 'math');
      await _seedQuestion(db, id: 'q-math-3', stem: '数学题三', subjectKey: 'math');
      await _seedQuestion(
        db,
        id: 'q-physics-1',
        stem: '物理题一',
        subjectKey: 'physics',
      );
      await _seedQuestion(
        db,
        id: 'q-physics-2',
        stem: '物理题二',
        subjectKey: 'physics',
      );

      final container = await _pumpPaperPage(tester, db: db);
      container.read(paperSpecProvider.notifier).setSubjectMax('math', 2);
      await _settle(tester);

      final plan = _readPlan(container);
      expect(plan.bySubject, <String, int>{'math': 2, 'physics': 2});
      expect(plan.quotaBlockedQuestions, hasLength(1));
      expect(plan.quotaBlockedQuestions.single.subjectKey, 'math');
      expect(plan.quotaBlockedQuestions.single.subjectLimit, 2);

      expect(find.byKey(paperSubjectQuotaOutcomeKey), findsOneWidget);
      expect(
        find.text(
          '${paperSubjectLabelOf(zh, 'math')} · '
          '${zh.questionPaperCountOption(2)}',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          '${paperSubjectLabelOf(zh, 'physics')} · '
          '${zh.questionPaperCountOption(2)}',
        ),
        findsOneWidget,
      );
      expect(find.text(zh.paperSubjectQuotaBlocked(1)), findsOneWidget);
      expect(
        find.textContaining(
          zh.paperSubjectQuotaBlockedItem(
              paperSubjectLabelOf(zh, 'math'), 2, ''),
        ),
        findsOneWidget,
      );
    });

    testWidgets('保底缺口区分「题库没题」与「候选不足」', (tester) async {
      await _seedQuestion(db, id: 'q-1', stem: '数学题一', subjectKey: 'math');
      await _seedQuestion(db, id: 'q-2', stem: '数学题二', subjectKey: 'math');
      await _seedQuestion(db, id: 'q-3', stem: '数学题三', subjectKey: 'math');

      final container = await _pumpPaperPage(tester, db: db);
      final notifier = container.read(paperSpecProvider.notifier);
      notifier.setSubjectMin('math', 4);
      notifier.setSubjectMin('chemistry', 2);
      await _settle(tester);

      final plan = _readPlan(container);
      final mathShortfall = plan.subjectShortfalls
          .singleWhere((shortfall) => shortfall.subjectKey == 'math');
      expect(mathShortfall.minimumCount, 4);
      expect(mathShortfall.selectedCount, 3);
      expect(mathShortfall.availableCount, 3);
      final chemistryShortfall = plan.subjectShortfalls
          .singleWhere((shortfall) => shortfall.subjectKey == 'chemistry');
      expect(chemistryShortfall.isUncovered, isTrue);

      expect(find.text(zh.paperSubjectQuotaShortfallTitle), findsOneWidget);
      expect(
        find.text(
          zh.paperSubjectQuotaShortfall(
            paperSubjectLabelOf(zh, 'math'),
            mathShortfall.minimumCount - mathShortfall.selectedCount,
            mathShortfall.availableCount,
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          zh.paperSubjectQuotaShortfallEmpty(
            paperSubjectLabelOf(zh, 'chemistry'),
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('空题库：配额缺口仍如实展示，空态文案不变', (tester) async {
      final container = await _pumpPaperPage(tester, db: db);
      container.read(paperSpecProvider.notifier).setSubjectMin('chemistry', 2);
      await _settle(tester);

      expect(find.text(zh.questionPaperEmptyBank), findsOneWidget);
      expect(find.byKey(paperSubjectQuotaOutcomeKey), findsOneWidget);
      expect(
        find.text(
          zh.paperSubjectQuotaShortfallEmpty(
            paperSubjectLabelOf(zh, 'chemistry'),
          ),
        ),
        findsOneWidget,
      );
    });
  });
}

/// 某个配额输入框里的文字（上限/保底各一个 TextField）。
String _quotaText(WidgetTester tester, Key key) {
  final field = tester.widget<TextField>(_quotaField(key));
  return field.controller?.text ?? '';
}

/// 配额输入框本体：key 在外层 _QuotaNumberField 上，TextField 在它下面。
Finder _quotaField(Key key) => find.descendant(
      of: find.byKey(key),
      matching: find.byType(TextField),
    );

/// 读当前组卷结果：结果卡片渲染时 provider 应该已经落到 data。
PaperPlan _readPlan(ProviderContainer container) {
  final asyncPlan = container.read(paperPlanProvider);
  expect(asyncPlan.hasValue, isTrue, reason: '组卷结果还没落定时不断言界面');
  return asyncPlan.value!;
}

Future<ProviderContainer> _pumpPaperPage(
  WidgetTester tester, {
  required AppDatabase db,
  LibraryDiagnosis diagnosis = LibraryDiagnosis.notRun,
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
            .overrideWith((ref) async => diagnosis),
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
/// 不能用 `pumpAndSettle`——数据还没到时页面上是无限动画的进度条，会超时。
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
  String subjectKey = '',
  String sourceLevel = 'unknown',
  String? trapNote,
  double? difficulty,
  String? answer,
}) {
  return db.into(db.questions).insert(
        QuestionsCompanion.insert(
          id: id,
          stem: stem,
          createdAt: _ts,
          updatedAt: _ts,
          subjectKey: Value(subjectKey),
          sourceLevel: Value(sourceLevel),
          trapNote: Value(trapNote),
          difficulty: Value(difficulty),
          answer: Value(answer),
        ),
      );
}
