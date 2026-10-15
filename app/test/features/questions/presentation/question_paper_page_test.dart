/// 组卷页（Q10a）的界面契约：页面只排版，不另写措辞。
///
/// 三条纪律：
/// 1. 理由 / 提升点 / 知识背景与档位标签**原样**来自领域层（`PaperPlan` →
///    `PaperItem` / `PaperZone.labelZh`）。这里断言的就是领域层那几句原文——
///    改域层文案时这些断言应该跟着红，而不是被页面"顺手改好"。
/// 2. 缺口不是错误：没有候选（去收题）与这轮被挤掉（调大题数）是两句话；
///    空题库与条件太窄也是两句话。
/// 3. `cognitiveLibraryDiagnosisProvider` 一律注入：真实实现即使在空库上也会先读
///    `cognitiveModelProvider`。"快层没跑"用 `LibraryDiagnosis.notRun` 表示，
///    它和"跑过但没报告"不是一回事。
library;

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart' show NativeDatabase;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/domain/services/cognitive/fast_diagnosis.dart';
import 'package:furnace/domain/services/cognitive/library_diagnosis.dart';
import 'package:furnace/features/cognitive/presentation/cognitive_model_page.dart';
import 'package:furnace/features/questions/application/paper_plan_provider.dart';
import 'package:furnace/features/questions/presentation/question_intake_page.dart';
import 'package:furnace/features/questions/presentation/question_intake_providers.dart';
import 'package:furnace/features/questions/presentation/question_paper_page.dart';
import 'package:furnace/l10n/app_localizations.dart';

import '../support/picked_file_fakes.dart';

/// 固定时间戳：让"最近"这种排序在测试里也是确定的。
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

  testWidgets('题库为空时给出可读空态，而不是错误', (tester) async {
    await _pumpPaperPage(tester, db: db);

    expect(find.text(zh.questionPaperEmptyBank), findsOneWidget);
    expect(find.text(zh.questionPaperEmptyPlan), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    // 控制区也在，学科没有可选项时说"不限学科"。
    expect(find.text(zh.questionPaperSubjectAny), findsOneWidget);
    expect(find.text(zh.questionPaperTargetCountLabel), findsOneWidget);
  });

  testWidgets('有候选时展示序号、档位 chip 与领域层给的三段原文', (tester) async {
    await _seedKnowledgePoint(
      db,
      id: 'kp-quadratic',
      title: '二次函数',
      tagId: 'tag-quadratic',
    );
    await _seedQuestion(
      db,
      id: 'q-1',
      stem: '求二次函数的最小值',
      subjectKey: 'math',
      sourceLevel: 'gaokao',
      trapNote: '别忘了定义域',
    );
    await _linkQuestionToTag(db, questionId: 'q-1', tagId: 'tag-quadratic');

    await _pumpPaperPage(tester, db: db);

    expect(find.text(zh.questionPaperItemIndex(1)), findsOneWidget);
    // 没有读数 = zone unknown，chip 文案来自 PaperZone.labelZh。
    expect(find.text('没有读数'), findsOneWidget);
    expect(find.text('${zh.questionPaperKnowledgePointLabel}：二次函数'),
        findsOneWidget);
    // reasonZh 原文（未知档那一句）。
    expect(
      find.text('知识点「二次函数」还没有你的读数，按未知处理（未知不当作健康）。'),
      findsOneWidget,
    );
    // improvementNote 原文 + trapNote 附在末尾。
    expect(
      find.text('先做一遍并把结果记进系统，下一轮才知道它属于哪一档。 这题的已知坑：别忘了定义域'),
      findsOneWidget,
    );
    // 三个标签都在（背景那段也渲染出来了）。
    expect(find.text(zh.questionPaperItemReasonLabel), findsOneWidget);
    expect(find.text(zh.questionPaperItemImprovementLabel), findsOneWidget);
    expect(find.text(zh.questionPaperItemBackgroundLabel), findsOneWidget);
    expect(find.text('二次函数'), findsWidgets);
  });

  testWidgets('凑不够时头部说明"题库不够"，并给出两位小数的整体该练程度', (tester) async {
    await _seedQuestion(db, id: 'q-1', stem: '第一题', subjectKey: 'math');
    await _seedQuestion(db, id: 'q-2', stem: '第二题', subjectKey: 'math');

    await _pumpPaperPage(tester, db: db);

    expect(find.text(zh.questionPaperHeadline(2, 10)), findsOneWidget);
    expect(
      find.text(
        '${zh.questionPaperCandidateCount(2)} · ${zh.questionPaperOverallNeed('0.35')}',
      ),
      findsOneWidget,
    );
    expect(find.text(zh.questionPaperShortNotice), findsOneWidget);
    expect(find.text(zh.questionPaperEmptyBank), findsNothing);
  });

  testWidgets('切换目标题数后卷子题数跟着变', (tester) async {
    for (var i = 1; i <= 6; i++) {
      await _seedQuestion(db, id: 'q-$i', stem: '第 $i 题', subjectKey: 'math');
    }

    await _pumpPaperPage(tester, db: db);
    expect(find.text(zh.questionPaperHeadline(6, 10)), findsOneWidget);

    // 真实交互：打开目标题数下拉，选 5 道。
    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text(zh.questionPaperCountOption(5)).last);
    await _settle(tester);

    expect(find.text(zh.questionPaperHeadline(5, 5)), findsOneWidget);
    expect(find.text(zh.questionPaperShortNotice), findsNothing);
    expect(find.text(zh.questionPaperItemIndex(6)), findsNothing);
  });

  testWidgets('来源下限把低来源的候选挡在外面', (tester) async {
    await _seedQuestion(
      db,
      id: 'q-g1',
      stem: '高考题一',
      subjectKey: 'math',
      sourceLevel: 'gaokao',
    );
    await _seedQuestion(
      db,
      id: 'q-g2',
      stem: '高考题二',
      subjectKey: 'math',
      sourceLevel: 'gaokao',
    );
    await _seedQuestion(
      db,
      id: 'q-p1',
      stem: '自建题一',
      subjectKey: 'math',
      sourceLevel: 'personal',
    );
    await _seedQuestion(
      db,
      id: 'q-p2',
      stem: '自建题二',
      subjectKey: 'math',
      sourceLevel: 'personal',
    );

    await _pumpPaperPage(tester, db: db);
    expect(find.text(zh.questionPaperHeadline(4, 10)), findsOneWidget);

    final container = _container(tester);
    container.read(paperSpecProvider.notifier).setMinSourceLevel('gaokao');
    await _settle(tester);

    expect(find.text(zh.questionPaperHeadline(2, 10)), findsOneWidget);
    expect(find.text(zh.questionPaperShortNotice), findsOneWidget);
  });

  testWidgets('学科 chip 只留下选中的学科', (tester) async {
    await _seedQuestion(db, id: 'q-m', stem: '数学题', subjectKey: 'math');
    await _seedQuestion(db, id: 'q-p', stem: '物理题', subjectKey: 'physics');

    await _pumpPaperPage(tester, db: db);
    expect(find.text(zh.questionPaperHeadline(2, 10)), findsOneWidget);
    expect(find.widgetWithText(FilterChip, '数学'), findsOneWidget);
    expect(find.widgetWithText(FilterChip, '物理'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilterChip, '数学'));
    await _settle(tester);

    expect(find.text(zh.questionPaperHeadline(1, 10)), findsOneWidget);
  });

  testWidgets('注入的危险区/发展区结论决定档位 chip 与理由原文', (tester) async {
    await _seedKnowledgePoint(db, id: 'kp-a', title: 'Alpha', tagId: 'tag-a');
    await _seedKnowledgePoint(db, id: 'kp-b', title: 'Beta', tagId: 'tag-b');
    await _seedQuestion(db, id: 'q-a', stem: 'Alpha 题', subjectKey: 'math');
    await _seedQuestion(db, id: 'q-b', stem: 'Beta 题', subjectKey: 'math');
    await _linkQuestionToTag(db, questionId: 'q-a', tagId: 'tag-a');
    await _linkQuestionToTag(db, questionId: 'q-b', tagId: 'tag-b');

    await _pumpPaperPage(
      tester,
      db: db,
      diagnosis: const LibraryDiagnosis(
        byKnowledgePoint: {
          'kp-a': BottleneckType.danger,
          'kp-b': BottleneckType.weak
        },
        fastLayerRan: true,
        rounds: 3,
      ),
    );

    expect(find.text('危险区'), findsOneWidget);
    expect(find.text('发展区'), findsOneWidget);
    expect(find.text('没有读数'), findsNothing);
    expect(
      find.text('知识点「Alpha」在危险区（自信高、实际提取不出来），这份卷先练它。'),
      findsOneWidget,
    );
    expect(
      find.text('知识点「Beta」在发展区（有读数但还偏弱），现在练收益最大。'),
      findsOneWidget,
    );
    // 危险区的提升点原文也来自域层。
    expect(find.text('别整套刷：只把关键那一步慢速重做一遍，并写出每一步的依据。'), findsOneWidget);
  });

  testWidgets('危险区但题库里没有候选 → 如实列出"去收题"，不当成没问题', (tester) async {
    await _seedKnowledgePoint(db, id: 'kp-a', title: 'Alpha', tagId: 'tag-a');
    await _seedKnowledgePoint(db, id: 'kp-e', title: 'Epsilon', tagId: 'tag-e');
    await _seedQuestion(
      db,
      id: 'q-a',
      stem: 'Alpha 高考题',
      subjectKey: 'math',
      sourceLevel: 'gaokao',
    );
    await _seedQuestion(
      db,
      id: 'q-e',
      stem: 'Epsilon 自建题',
      subjectKey: 'math',
      sourceLevel: 'personal',
    );
    await _linkQuestionToTag(db, questionId: 'q-a', tagId: 'tag-a');
    await _linkQuestionToTag(db, questionId: 'q-e', tagId: 'tag-e');

    await _pumpPaperPage(
      tester,
      db: db,
      diagnosis: const LibraryDiagnosis(
        byKnowledgePoint: {
          'kp-a': BottleneckType.danger,
          'kp-e': BottleneckType.danger
        },
        fastLayerRan: true,
        rounds: 3,
      ),
    );

    // 把来源下限提到高考真题：Epsilon 只剩自建题 → 一道候选都没有。
    _container(tester)
        .read(paperSpecProvider.notifier)
        .setMinSourceLevel('gaokao');
    await _settle(tester);

    expect(find.text(zh.questionPaperUncoveredTitle), findsOneWidget);
    expect(find.text(zh.questionPaperUncoveredBody), findsOneWidget);
    expect(find.text('• Epsilon'), findsOneWidget);
    expect(find.text(zh.questionPaperDeferredTitle), findsNothing);
    expect(find.text(zh.questionPaperHeadline(1, 10)), findsOneWidget);
  });

  testWidgets('有候选但被配额挤掉 → 列进"这轮被挤掉"，不是"没有候选"', (tester) async {
    for (final point in ['a', 'b', 'c', 'd']) {
      await _seedKnowledgePoint(
        db,
        id: 'kp-$point',
        title: point.toUpperCase(),
        tagId: 'tag-$point',
      );
    }
    for (final point in ['a', 'b', 'c']) {
      for (var i = 1; i <= 2; i++) {
        final id = 'q-$point$i';
        await _seedQuestion(
          db,
          id: id,
          stem: '$point$i',
          subjectKey: 'math',
          sourceLevel: 'gaokao',
        );
        await _linkQuestionToTag(db, questionId: id, tagId: 'tag-$point');
      }
    }
    for (var i = 1; i <= 2; i++) {
      final id = 'q-d$i';
      await _seedQuestion(
        db,
        id: id,
        stem: 'd$i',
        subjectKey: 'math',
        sourceLevel: 'personal',
      );
      await _linkQuestionToTag(db, questionId: id, tagId: 'tag-d');
    }

    await _pumpPaperPage(
      tester,
      db: db,
      diagnosis: const LibraryDiagnosis(
        byKnowledgePoint: {
          'kp-a': BottleneckType.danger,
          'kp-b': BottleneckType.danger,
          'kp-c': BottleneckType.danger,
          'kp-d': BottleneckType.danger,
        },
        fastLayerRan: true,
        rounds: 3,
      ),
    );

    // 目标 5 道、4 个知识点 → 每个点默认上限 ceil(5/4)=2 → 只有三个点进得来。
    _container(tester).read(paperSpecProvider.notifier).setTargetCount(5);
    await _settle(tester);

    expect(find.text(zh.questionPaperHeadline(5, 5)), findsOneWidget);
    expect(find.text(zh.questionPaperDeferredTitle), findsOneWidget);
    expect(find.text(zh.questionPaperDeferredBody), findsOneWidget);
    expect(find.text('• D'), findsOneWidget);
    expect(find.text(zh.questionPaperUncoveredTitle), findsNothing);
  });

  testWidgets('收题页 AppBar 有进组卷页的入口', (tester) async {
    final supportRoot =
        Directory.systemTemp.createTempSync('furnace_paper_entry_');
    addTearDown(() {
      if (supportRoot.existsSync()) {
        supportRoot.deleteSync(recursive: true);
      }
    });

    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          handwritingIntakeStoreProvider.overrideWithValue(
            FakeIntakeStore(database: db, root: supportRoot),
          ),
          cognitiveLibraryDiagnosisProvider.overrideWith(
            (ref) async => LibraryDiagnosis.notRun,
          ),
        ],
        child: const MaterialApp(
          locale: Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: QuestionIntakePage(),
        ),
      ),
    );
    await _settle(tester);

    expect(find.byIcon(Icons.playlist_add_check), findsOneWidget);
    await tester.tap(find.byTooltip(zh.questionPaperTitle));
    await _settle(tester);

    expect(find.byType(QuestionPaperPage), findsOneWidget);
    expect(find.text(zh.questionPaperSubtitle), findsOneWidget);
  });
}

// ---------------------------------------------------------------------------
// 装置
// ---------------------------------------------------------------------------

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
  return _container(tester);
}

ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(QuestionPaperPage)));

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
        ),
      );
}

Future<void> _seedKnowledgePoint(
  AppDatabase db, {
  required String id,
  required String title,
  required String tagId,
}) async {
  await db.into(db.knowledgePoints).insert(
        KnowledgePointsCompanion.insert(
          id: id,
          title: title,
          content: '',
          createdAt: _ts,
          updatedAt: _ts,
        ),
      );
  await db.into(db.tags).insert(
        TagsCompanion.insert(
          id: tagId,
          name: title,
          createdAt: _ts,
          updatedAt: _ts,
        ),
      );
  await db.into(db.objectTags).insert(
        ObjectTagsCompanion.insert(
          id: 'ot-$tagId-$id',
          tagId: tagId,
          objectType: 'knowledge_point',
          objectId: id,
          createdAt: _ts,
        ),
      );
}

/// 题目与知识点共享同一个标签 → 组卷器才认得出这道题挂在哪。
Future<void> _linkQuestionToTag(
  AppDatabase db, {
  required String questionId,
  required String tagId,
}) {
  return db.into(db.objectTags).insert(
        ObjectTagsCompanion.insert(
          id: 'ot-$tagId-$questionId',
          tagId: tagId,
          objectType: 'question',
          objectId: questionId,
          createdAt: _ts,
        ),
      );
}
