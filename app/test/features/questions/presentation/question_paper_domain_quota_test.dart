/// 组卷页「领域配额」的界面契约：配额区只改 spec，分布/被挡/缺口只排版 PaperPlan。
///
/// 与学科配额同一套纪律（见 question_paper_quota_test.dart）：
/// 1. 配额状态只认 `paperSpecProvider`（setDomainMax / setDomainMin /
///    clearDomainQuota），页面不自己存一份配额；
/// 2. 生成后的分布/被挡/缺口全部来自 `PaperPlan`，这里断言的是域层算出来的数字，
///    页面改文案时这些断言应该跟着红；
/// 3. 领域键 = 知识点标签路径第一段（如「数学」），学科键 = subjectKey（如 math），
///    两套命名空间互不影响。
library;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart' show NativeDatabase;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/domain/services/cognitive/library_diagnosis.dart';
import 'package:furnace/domain/services/paper/domain_quota.dart';
import 'package:furnace/domain/services/paper/paper_composer.dart';
import 'package:furnace/features/cognitive/presentation/cognitive_model_page.dart';
import 'package:furnace/features/questions/application/paper_plan_provider.dart';
import 'package:furnace/features/questions/presentation/paper_domain_quota_view.dart';
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
      final parsed = parsePaperDomainQuotaInput('   ');
      expect(parsed.isEmpty, isTrue);
      expect(parsed.isInvalid, isFalse);
      expect(parsed.value, isNull);
    });

    test('非负整数是合法输入（上限 0 也合法）', () {
      expect(parsePaperDomainQuotaInput('3').value, 3);
      expect(parsePaperDomainQuotaInput(' 12 ').value, 12);
      final zero = parsePaperDomainQuotaInput('0');
      expect(zero.value, 0);
      expect(zero.isInvalid, isFalse);
    });

    test('负数、小数、文字都判非法（不当成清空）', () {
      for (final raw in ['-1', '1.5', '数学', '12a']) {
        final parsed = parsePaperDomainQuotaInput(raw);
        expect(parsed.isInvalid, isTrue, reason: raw);
        expect(parsed.value, isNull, reason: raw);
      }
    });
  });

  group('纯函数：题库领域键与列行顺序', () {
    test('领域键取标签路径第一段，去重并排序', () {
      final domains = paperDomainQuotaBankDomains(<String, List<String>>{
        'kp-1': <String>['数学/函数', ' 数学/集合 '],
        'kp-2': <String>['物理/力学', '   '],
        'kp-3': const <String>[],
      });
      expect(domains, <String>['数学', '物理']);
    });

    test('配额里有、题库暂时没有的领域也要列出来（否则清不掉）', () {
      final domains = paperDomainQuotaDomains(
        configuredDomains: <String>['物理', ' 化学 ', '化学'],
        bankDomains: <String>['数学', '物理', ''],
      );
      expect(domains, <String>['数学', '物理', '化学']);
    });
  });

  group('纯函数：领域分布与被挡预览', () {
    test('分布：数量倒序、同量按领域键升序；0 道与空白键不列', () {
      final sorted = paperDomainQuotaDistributionSorted(<String, int>{
        '物理': 2,
        '数学': 2,
        '化学': 1,
        '生物': 1,
        '历史': 0,
        '   ': 3,
      });
      expect(
        sorted.map((entry) => entry.key).toList(),
        <String>['数学', '物理', '化学', '生物'],
      );
      expect(sorted.map((entry) => entry.value).toList(), <int>[2, 2, 1, 1]);
    });

    test('被挡题只预览前 3 条，剩下的报数量', () {
      final blocked = <DomainQuotaBlockedQuestion>[
        for (var i = 0; i < 5; i++)
          DomainQuotaBlockedQuestion(
            questionId: 'q-$i',
            domain: '数学',
            domainLimit: 1,
          ),
      ];
      expect(paperDomainQuotaBlockedPreview(blocked), hasLength(3));
      expect(paperDomainQuotaBlockedHidden(blocked), 2);
      expect(paperDomainQuotaBlockedHidden(blocked.take(2).toList()), 0);
    });

    test('题干预览：折掉换行与连续空白，超长截断', () {
      expect(paperDomainQuotaStemPreview('  a\n\n  b  '), 'a b');
      expect(paperDomainQuotaStemPreview('   '), '');
      expect(paperDomainQuotaStemPreview('一二三四五', maxChars: 3), '一二三…');
    });
  });

  group('widget：配额区与生成结果', () {
    testWidgets('题库空、未启用配额：不摆区块也不摆结果卡', (tester) async {
      await _pumpPaperPage(tester, db: db);

      expect(find.byKey(paperDomainQuotaSectionKey), findsNothing);
      expect(find.byKey(paperDomainQuotaOutcomeKey), findsNothing);
      expect(find.text(zh.paperDomainQuotaTitle), findsNothing);
    });

    testWidgets('题库有领域但未启用：只摆可编辑行，不摆结果卡', (tester) async {
      await _seedTaggedQuestion(
        db,
        questionId: 'q-math',
        stem: '求函数单调区间',
        knowledgePointId: 'kp-math',
        tagId: 'tag-math',
        tagName: '函数',
        tagPath: '数学/函数',
        subjectKey: 'math',
      );
      await _pumpPaperPage(tester, db: db);

      expect(find.byKey(paperDomainQuotaSectionKey), findsOneWidget);
      expect(find.byKey(paperDomainQuotaMaxKey('数学')), findsOneWidget);
      expect(find.byKey(paperDomainQuotaMaxKey('物理')), findsNothing);
      expect(find.byKey(paperDomainQuotaOutcomeKey), findsNothing);
    });

    testWidgets('输入上限后 spec 与 plan 都反映出来，并展示被挡的题', (tester) async {
      await _seedTaggedQuestion(
        db,
        questionId: 'q-math-1',
        stem: '求函数单调区间',
        knowledgePointId: 'kp-math-1',
        tagId: 'tag-math-1',
        tagName: '函数',
        tagPath: '数学/函数',
        subjectKey: 'math',
      );
      await _seedTaggedQuestion(
        db,
        questionId: 'q-math-2',
        stem: '求集合交集',
        knowledgePointId: 'kp-math-2',
        tagId: 'tag-math-2',
        tagName: '集合',
        tagPath: '数学/集合',
        subjectKey: 'math',
      );
      final container = await _pumpPaperPage(tester, db: db);

      await tester.enterText(_quotaField(paperDomainQuotaMaxKey('数学')), '1');
      await _settle(tester);

      final spec = container.read(paperSpecProvider);
      expect(spec.domainQuota?.maxPerDomain['数学'], 1);

      final plan = _readPlan(container);
      expect(plan.byDomain['数学'], 1);
      expect(plan.quotaBlockedByDomain, hasLength(1));
      expect(plan.quotaBlockedByDomain.single.domain, '数学');
      expect(plan.quotaBlockedByDomain.single.domainLimit, 1);

      expect(find.byKey(paperDomainQuotaOutcomeKey), findsOneWidget);
      expect(find.text(zh.paperDomainQuotaBlocked(1)), findsOneWidget);
      expect(
        find.textContaining(zh.questionPaperCountOption(1)),
        findsWidgets,
      );
    });

    testWidgets('非法输入标红且不写进 spec', (tester) async {
      await _seedTaggedQuestion(
        db,
        questionId: 'q-math',
        stem: '求函数单调区间',
        knowledgePointId: 'kp-math',
        tagId: 'tag-math',
        tagName: '函数',
        tagPath: '数学/函数',
        subjectKey: 'math',
      );
      final container = await _pumpPaperPage(tester, db: db);

      await tester.enterText(_quotaField(paperDomainQuotaMaxKey('数学')), '-1');
      await _settle(tester);

      expect(find.text(zh.paperDomainQuotaInvalid), findsOneWidget);
      expect(container.read(paperSpecProvider).domainQuota, isNull);
    });

    testWidgets('清空配额：spec 归零、输入框清空、结果卡消失', (tester) async {
      await _seedTaggedQuestion(
        db,
        questionId: 'q-math',
        stem: '求函数单调区间',
        knowledgePointId: 'kp-math',
        tagId: 'tag-math',
        tagName: '函数',
        tagPath: '数学/函数',
        subjectKey: 'math',
      );
      final container = await _pumpPaperPage(tester, db: db);
      container.read(paperSpecProvider.notifier).setDomainMax('数学', 1);
      await _settle(tester);
      expect(find.byKey(paperDomainQuotaOutcomeKey), findsOneWidget);

      await tester.tap(find.byKey(paperDomainQuotaClearKey));
      await _settle(tester);

      expect(container.read(paperSpecProvider).domainQuota, isNull);
      expect(_quotaText(tester, paperDomainQuotaMaxKey('数学')), '');
      expect(find.byKey(paperDomainQuotaOutcomeKey), findsNothing);
    });

    testWidgets('保底缺口：候选不足与题库无题两种都如实展示', (tester) async {
      await _seedTaggedQuestion(
        db,
        questionId: 'q-physics',
        stem: '求小车加速度',
        knowledgePointId: 'kp-physics',
        tagId: 'tag-physics',
        tagName: '力学',
        tagPath: '物理/力学',
        subjectKey: 'physics',
      );
      final container = await _pumpPaperPage(tester, db: db);
      final notifier = container.read(paperSpecProvider.notifier);
      notifier.setDomainMin('物理', 2);
      await _settle(tester);
      notifier.setDomainMin('化学', 2);
      await _settle(tester);

      final plan = _readPlan(container);
      expect(plan.domainShortfalls, hasLength(2));
      expect(find.text(zh.paperDomainQuotaShortfallTitle), findsOneWidget);
      expect(
          find.text(zh.paperDomainQuotaShortfall('物理', 1, 1)), findsOneWidget);
      expect(
          find.text(zh.paperDomainQuotaShortfallEmpty('化学')), findsOneWidget);
      expect(plan.uncoveredDomains, contains('化学'));
      expect(
        find.text(zh.paperDomainQuotaUncovered('化学')),
        findsOneWidget,
      );
    });

    testWidgets('被挡下的快照题：那一行用摘录，并补「整题截图」小标签', (tester) async {
      await _seedTaggedQuestion(
        db,
        questionId: 'q-math-1',
        stem: '求函数单调区间',
        knowledgePointId: 'kp-math-1',
        tagId: 'tag-math-1',
        tagName: '函数',
        tagPath: '数学/函数',
        subjectKey: 'math',
      );
      await _seedTaggedQuestion(
        db,
        questionId: 'q-math-2',
        stem: '求集合交集［图1］［图2］',
        knowledgePointId: 'kp-math-2',
        tagId: 'tag-math-2',
        tagName: '集合',
        tagPath: '数学/集合',
        subjectKey: 'math',
      );
      await _seedStemAttachment(db, questionId: 'q-math-2');
      final container = await _pumpPaperPage(tester, db: db);
      container.read(paperSpecProvider.notifier).setDomainMax('数学', 1);
      await _settle(tester);

      final plan = _readPlan(container);
      expect(plan.quotaBlockedByDomain.single.questionId, 'q-math-2');
      final outcome = find.byKey(paperDomainQuotaOutcomeKey);
      expect(
        find.descendant(
          of: outcome,
          matching: find.text(zh.paperDomainQuotaBlockedItem('数学', 1, '求集合交集')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: outcome,
          matching: find.text(zh.questionBankSnapshotBadge),
        ),
        findsOneWidget,
      );
    });

    testWidgets('被挡的快照题没有正文摘录：显示标签本身，不再叠一个小徽标', (tester) async {
      await _seedTaggedQuestion(
        db,
        questionId: 'q-math-1',
        stem: '求函数单调区间',
        knowledgePointId: 'kp-math-1',
        tagId: 'tag-math-1',
        tagName: '函数',
        tagPath: '数学/函数',
        subjectKey: 'math',
      );
      await _seedTaggedQuestion(
        db,
        questionId: 'q-math-2',
        stem: '［图1］［图2］',
        knowledgePointId: 'kp-math-2',
        tagId: 'tag-math-2',
        tagName: '集合',
        tagPath: '数学/集合',
        subjectKey: 'math',
      );
      await _seedStemAttachment(db, questionId: 'q-math-2');
      final container = await _pumpPaperPage(tester, db: db);
      container.read(paperSpecProvider.notifier).setDomainMax('数学', 1);
      await _settle(tester);

      final plan = _readPlan(container);
      expect(plan.quotaBlockedByDomain.single.questionId, 'q-math-2');
      final outcome = find.byKey(paperDomainQuotaOutcomeKey);
      expect(
        find.descendant(
          of: outcome,
          matching: find.textContaining('整题截图'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: outcome,
          matching: find.text(zh.questionBankSnapshotBadge),
        ),
        findsNothing,
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
}) {
  return db.into(db.questions).insert(
        QuestionsCompanion.insert(
          id: id,
          stem: stem,
          createdAt: _ts,
          updatedAt: _ts,
          subjectKey: Value(subjectKey),
        ),
      );
}

/// 一题一个知识点 + 一条带 path 的标签：题目与知识点共享同一标签，
/// 组卷器据此把题归到「标签路径第一段」那个领域。
Future<void> _seedTaggedQuestion(
  AppDatabase db, {
  required String questionId,
  required String stem,
  required String knowledgePointId,
  required String tagId,
  required String tagName,
  required String tagPath,
  String subjectKey = '',
}) async {
  await _seedQuestion(db, id: questionId, stem: stem, subjectKey: subjectKey);
  await db.into(db.knowledgePoints).insert(
        KnowledgePointsCompanion.insert(
          id: knowledgePointId,
          title: tagName,
          content: '',
          createdAt: _ts,
          updatedAt: _ts,
        ),
      );
  await db.into(db.tags).insert(
        TagsCompanion.insert(
          id: tagId,
          name: tagName,
          path: Value(tagPath),
          createdAt: _ts,
          updatedAt: _ts,
        ),
      );
  await db.into(db.objectTags).insert(
        ObjectTagsCompanion.insert(
          id: 'ot-$tagId-$knowledgePointId',
          tagId: tagId,
          objectType: 'knowledge_point',
          objectId: knowledgePointId,
          createdAt: _ts,
        ),
      );
  await db.into(db.objectTags).insert(
        ObjectTagsCompanion.insert(
          id: 'ot-$tagId-$questionId',
          tagId: tagId,
          objectType: 'question',
          objectId: questionId,
          createdAt: _ts,
        ),
      );
}

/// 一张题干图：role 为 NULL 或 'stem' 都按题干图算（v27 旧行是 NULL）。
Future<void> _seedStemAttachment(
  AppDatabase db, {
  required String questionId,
  String? role = 'stem',
}) {
  return db.into(db.attachments).insert(
        AttachmentsCompanion.insert(
          id: 'att-$questionId',
          ownerType: 'question',
          ownerId: questionId,
          relPath: 'question_images/$questionId/att-$questionId/photo.png',
          mime: const Value<String>('image/png'),
          role: Value<String?>(role),
          createdAt: _ts,
        ),
      );
}
