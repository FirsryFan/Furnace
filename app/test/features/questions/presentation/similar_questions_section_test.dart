/// 题目详情页「找相似题」区块（Q12 UI）的验收点：
///
///  * 有相似题：显示**领域层给的**理由行（不重写措辞、不显示裸分数），
///    `crossSubjectTransfer` 给「跨学科迁移」角标；
///  * 空列表：只给空态（指向内置 agent 收题），**不拿别的题凑数**（用户口径）；
///  * provider 抛错 / 还在算：区块如实说，页面其余部分照常，不崩。
///
/// 数据一律走真仓储写进内存库（`ingest` / `createKnowledgePoint` / `createTag` /
/// `saveChain`），这样喂给 `similarQuestionsProvider` 的就是生产同款输入。
library;

import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/anki_repository.dart';
import 'package:furnace/data/repositories/question_repository.dart';
import 'package:furnace/data/repositories/tag_repository.dart';
import 'package:furnace/domain/services/paper/similar_questions.dart';
import 'package:furnace/features/questions/application/similar_question_provider.dart';
import 'package:furnace/features/questions/data/handwriting_intake_store.dart';
import 'package:furnace/features/questions/presentation/question_detail_page.dart';
import 'package:furnace/features/questions/presentation/question_intake_providers.dart';
import 'package:furnace/l10n/app_localizations.dart';

void main() {
  late AppLocalizations zh;
  late AppDatabase db;
  late QuestionRepository questions;
  late TagRepository tags;
  late AnkiRepository anki;

  setUpAll(() async {
    zh = await AppLocalizations.delegate.load(const Locale('zh'));
  });

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    questions = QuestionRepository(db);
    tags = TagRepository(db);
    anki = AnkiRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<String> seedQuestion({
    required String stem,
    String subjectKey = 'math',
    String sourceLevel = 'gaokao',
  }) async {
    final ingested = await questions.ingest(
      QuestionDraft(
        stem: stem,
        subjectKey: subjectKey,
        sourceLevel: sourceLevel,
      ),
    );
    return ingested.question.id;
  }

  Future<String> seedKnowledgePoint(String title) async =>
      (await anki.createKnowledgePoint(title: title, content: '')).id;

  /// 题目覆盖知识点的方式：题目与知识点挂**同一个**标签（`TaskKnowledgePointResolver`）。
  Future<void> link({
    required String questionId,
    required String pointId,
    required String tagName,
  }) async {
    final tagId = (await tags.createTag(name: tagName)).id;
    await tags.addTagToObject(
      tagId: tagId,
      objectType: 'knowledge_point',
      objectId: pointId,
    );
    await tags.addTagToObject(
      tagId: tagId,
      objectType: 'question',
      objectId: questionId,
    );
  }

  /// 库里已有的思维链才是「同型动作」那条信号的来源（没链 = 没信号）。
  Future<void> seedChain({
    required String questionId,
    required List<String> actionTypes,
  }) async {
    await questions.saveChain(
      questionId,
      ReasoningChainDraft(
        model: 'test-model',
        summary: '测试链',
        steps: [
          for (var index = 0; index < actionTypes.length; index++)
            ReasoningStepDraft(
              goal: '第 ${index + 1} 步',
              actionType: actionTypes[index],
            ),
        ],
      ),
    );
  }

  /// 循环 pump：`pumpAndSettle` 会被无限动画（进度条）拖到超时，这里只等到进度条消失。
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 20));
      if (find.byType(CircularProgressIndicator).evaluate().isEmpty &&
          find.byType(LinearProgressIndicator).evaluate().isEmpty) {
        return;
      }
    }
  }

  Future<void> waitForText(WidgetTester tester, String text) async {
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.text(text).evaluate().isNotEmpty) {
        return;
      }
    }
    fail('等了 3 秒也没等到这段文字：$text');
  }

  Future<void> pumpDetail(
    WidgetTester tester, {
    required String questionId,
    List<Override> overrides = const <Override>[],
  }) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          appDatabaseProvider.overrideWithValue(db),
          // 空态里的「去收题」会打开收题页；它的待整理清单不该真去碰平台目录。
          pendingHandwritingImagesProvider.overrideWith(
            (ref) => const <PendingHandwritingImage>[],
          ),
          ...overrides,
        ],
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: QuestionDetailPage(questionId: questionId),
        ),
      ),
    );
    await settle(tester);
    await waitForText(tester, zh.questionSimilarTitle);
  }

  testWidgets('有相似题：显示理由行原文，跨学科同型动作给「跨学科迁移」角标', (tester) async {
    final pointId = await seedKnowledgePoint('动量守恒');
    final focusId = await seedQuestion(stem: '碰撞后两球速度各是多少？');
    final sharedPointId = await seedQuestion(stem: '另一道动量题：子弹打木块。');
    await link(questionId: focusId, pointId: pointId, tagName: '力学');
    await link(questionId: sharedPointId, pointId: pointId, tagName: '力学');

    // 跨学科迁移：学科不同，但库里的思维链动作同型。
    final transferId = await seedQuestion(
      stem: '跨学科的题：电路里的等效变换。',
      subjectKey: 'physics',
    );
    await seedChain(
      questionId: focusId,
      actionTypes: ['first_principles', 'sanity_check'],
    );
    await seedChain(
      questionId: transferId,
      actionTypes: ['first_principles', 'sanity_check'],
    );

    await pumpDetail(tester, questionId: focusId);
    await waitForText(tester, '另一道动量题：子弹打木块。');
    await waitForText(tester, '跨学科的题：电路里的等效变换。');

    // 候选行带题号：按 questionId 异步读，读到才显示；页头自己的号仍是唯一那个。
    await waitForText(tester, 'TR-00002');
    await waitForText(tester, 'TR-00003');
    expect(find.text('TR-00001'), findsOneWidget);

    // 理由行是领域层写的，界面只原样显示（含知识点名）。
    expect(find.textContaining('共用知识点「动量守恒」'), findsOneWidget);
    expect(find.textContaining('跨学科迁移：学科不同，但解题动作同型'), findsOneWidget);
    // 角标只挂在迁移候选那一条上（理由行里的「跨学科迁移：…」是长句，不会被算成角标）。
    expect(find.text(zh.questionSimilarCrossSubject), findsOneWidget);
    expect(find.text(zh.questionSimilarCount(2)), findsOneWidget);

    // 题干摘要 + 可点进详情：两条候选都有 onTap。
    final tiles = tester.widgetList<ListTile>(find.byType(ListTile)).toList();
    expect(tiles.length, 2);
    expect(tiles.every((tile) => tile.onTap != null), isTrue);

    // 不展示裸分数：界面上不出现分数百分比/分量表。
    expect(find.textContaining('score'), findsNothing);
    expect(find.textContaining('knowledge_point'), findsNothing);
  });

  testWidgets('库里没有相似题：只给空态（指向内置 agent 收题），不凑数', (tester) async {
    final focusId = await seedQuestion(stem: '库里唯一的一道题。');

    await pumpDetail(tester, questionId: focusId);

    expect(find.text(zh.questionSimilarEmpty), findsOneWidget);
    // 收题入口已并进内置 agent：相似题空态不再给「去收题」入口。
    expect(find.textContaining('去收题'), findsNothing);
    // 一条候选都没有：不拿"看着像"的题凑数。
    expect(find.byType(ListTile), findsNothing);
  });

  testWidgets('找相似题抛错：如实显示失败行，页面其余部分照常', (tester) async {
    final focusId = await seedQuestion(stem: '会出错的题。');

    await pumpDetail(
      tester,
      questionId: focusId,
      overrides: <Override>[
        similarQuestionsProvider.overrideWith(
          (ref, questionId) =>
              Future<List<SimilarQuestion>>.error(StateError('boom')),
        ),
      ],
    );

    expect(find.textContaining('boom'), findsOneWidget);
    expect(
      find.text(zh.questionSimilarFailed('Bad state: boom')),
      findsOneWidget,
      reason: '失败行必须带上真实错误，不能只剩前缀',
    );
    // 页面没崩：推理区块照常。
    expect(find.text(zh.questionDetailReasoningSection), findsOneWidget);
  });

  testWidgets('找相似题还在算：显示加载行，页面不崩', (tester) async {
    final focusId = await seedQuestion(stem: '还在算的题。');
    final pending = Completer<List<SimilarQuestion>>();

    await pumpDetail(
      tester,
      questionId: focusId,
      overrides: <Override>[
        similarQuestionsProvider
            .overrideWith((ref, questionId) => pending.future),
      ],
    );

    expect(find.text(zh.questionSimilarLoading), findsOneWidget);
    expect(find.text(zh.questionDetailReasoningSection), findsOneWidget);
  });
}
