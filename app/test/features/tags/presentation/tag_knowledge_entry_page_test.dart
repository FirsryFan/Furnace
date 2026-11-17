/// 标签知识入口页：三块（题 / 卡 / 任务）的数量、空态、导航、范围开关与切换。
///
/// 钉住的用户可见行为：
///  * 空标签三块都写「暂无」并显示 0，不造假行；
///  * 有链接时每块数量 = 真实行数，行可点进题目详情 / 任务详情；
///  * 卡打开只读详情弹窗；卡属于已配置卡组时能直接进复习；
///  * 「含子标签」开关改变统计范围；
///  * 从标签树可以进入：叶子点击、父行菜单都行，切换标签后内容跟着换。
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/anki_repository.dart';
import 'package:furnace/data/repositories/question_repository.dart';
import 'package:furnace/data/repositories/review_plan_repository.dart';
import 'package:furnace/data/repositories/tag_repository.dart';
import 'package:furnace/data/repositories/task_repository.dart';
import 'package:furnace/features/anki/presentation/review_page.dart';
import 'package:furnace/features/questions/application/question_media_providers.dart';
import 'package:furnace/features/questions/presentation/question_detail_page.dart';
import 'package:furnace/features/tags/presentation/tag_graph_view.dart';
import 'package:furnace/features/tags/presentation/tag_knowledge_entry_page.dart';
import 'package:furnace/features/tags/presentation/tag_tree_page.dart';
import 'package:furnace/features/tasks/presentation/task_detail_page.dart';
import 'package:furnace/l10n/app_localizations.dart';

import '../../questions/presentation/support/question_media_fakes.dart';

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

  /// 一个标签。
  Future<Tag> seedTag(String name, {String? parentId}) =>
      TagRepository(db).createTag(name: name, parentId: parentId);

  /// 一道挂到 [tagId] 的题。
  Future<Question> seedQuestion(
    String tagId,
    String stem, {
    String? title,
  }) async {
    final repository = QuestionRepository(db);
    final question = (await repository.ingest(
      QuestionDraft(stem: stem, tagIds: <String>{tagId}),
    ))
        .question;
    if (title != null) {
      await repository.setQuestionTitle(question.id, title);
    }
    return (await repository.byId(question.id))!;
  }

  /// 一张挂到 [tagId] 的卡（经知识点）。
  Future<CardTemplate> seedCard(
    String tagId, {
    required String front,
    required String answer,
    String hint = '',
    String knowledgePointTitle = '受力分析',
  }) async {
    final tags = TagRepository(db);
    final anki = AnkiRepository(db);
    final point = await anki.createKnowledgePoint(
      title: knowledgePointTitle,
      content: '内容',
    );
    await tags.addTagToObject(
      tagId: tagId,
      objectType: 'knowledge_point',
      objectId: point.id,
    );
    return anki.createTemplate(
      knowledgePointId: point.id,
      type: 'fill_blank',
      question: front,
      answer: answer,
      hint: hint.isEmpty ? null : hint,
    );
  }

  /// 一条挂到 [tagId] 的任务。
  Future<Task> seedTask(String tagId, String title) async {
    final task = await TaskRepository(db).createTask(title: title);
    await TagRepository(db).addTagToObject(
      tagId: tagId,
      objectType: 'task',
      objectId: task.id,
    );
    return task;
  }

  /// 等待页面显式内容出现（不依赖 indeterminate 进度圈的动画收敛）。
  Future<void> settle(WidgetTester tester) async {
    for (var index = 0; index < 80; index++) {
      await tester.pump(const Duration(milliseconds: 20));
      if (find.byType(CircularProgressIndicator).evaluate().isEmpty) {
        return;
      }
    }
    fail('页面在 80 次 pump 后仍停在加载态');
  }

  Future<void> pumpEntry(
    WidgetTester tester, {
    required String tagId,
    required String tagLabel,
  }) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          appDatabaseProvider.overrideWithValue(db),
          questionMediaStoreProvider.overrideWithValue(
            FakeQuestionMediaStore(database: db),
          ),
        ],
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: TagKnowledgeEntryPage(tagId: tagId, tagLabel: tagLabel),
        ),
      ),
    );
    await settle(tester);
  }

  Finder countBadge(String block, int count) => find.descendant(
        of: find.byKey(tagKnowledgeCountKey(block)),
        matching: find.text('$count'),
      );

  testWidgets('空标签：三块各显示 0 与「暂无」，没有任何行', (tester) async {
    final tag = await seedTag('空标签');
    await pumpEntry(tester, tagId: tag.id, tagLabel: tag.name);

    expect(find.text(zh.tagKnowledgeQuestions), findsOneWidget);
    expect(find.text(zh.tagKnowledgeFlashcards), findsOneWidget);
    expect(find.text(zh.tagKnowledgeTasks), findsOneWidget);

    expect(countBadge('questions', 0), findsOneWidget);
    expect(countBadge('cards', 0), findsOneWidget);
    expect(countBadge('tasks', 0), findsOneWidget);

    expect(find.text(zh.tagKnowledgeEmptyQuestions), findsOneWidget);
    expect(find.text(zh.tagKnowledgeEmptyFlashcards), findsOneWidget);
    expect(find.text(zh.tagKnowledgeEmptyTasks), findsOneWidget);

    // 空态不是用假行凑出来的：没有题/卡/任务行。
    for (final prefix in <String>[
      'tag-knowledge-question-',
      'tag-knowledge-card-',
      'tag-knowledge-task-',
    ]) {
      expect(
        find.byWidgetPredicate((widget) =>
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>).value.startsWith(prefix)),
        findsNothing,
      );
    }
    expect(find.byKey(tagKnowledgeEmptyKey('questions')), findsOneWidget);
    expect(find.byKey(tagKnowledgeEmptyKey('cards')), findsOneWidget);
    expect(find.byKey(tagKnowledgeEmptyKey('tasks')), findsOneWidget);
  });

  testWidgets('有链接：三块数量与行都真实出现', (tester) async {
    final tag = await seedTag('物理');
    final question = await seedQuestion(tag.id, '求小球的加速度', title: '牛顿第二定律');
    final card = await seedCard(
      tag.id,
      front: '重力的方向是？',
      answer: '竖直向下',
    );
    final task = await seedTask(tag.id, '完成力学练习');

    await pumpEntry(tester, tagId: tag.id, tagLabel: tag.name);

    expect(countBadge('questions', 1), findsOneWidget);
    expect(countBadge('cards', 1), findsOneWidget);
    expect(countBadge('tasks', 1), findsOneWidget);

    expect(
      find.byKey(ValueKey<String>('tag-knowledge-question-${question.id}')),
      findsOneWidget,
    );
    expect(find.text('牛顿第二定律'), findsOneWidget);
    expect(find.textContaining('TR-'), findsWidgets);

    expect(
      find.byKey(ValueKey<String>('tag-knowledge-card-${card.id}')),
      findsOneWidget,
    );
    expect(find.text('重力的方向是？'), findsOneWidget);
    expect(find.textContaining('填空题'), findsOneWidget);

    expect(
      find.byKey(ValueKey<String>('tag-knowledge-task-${task.id}')),
      findsOneWidget,
    );
    expect(find.text('完成力学练习'), findsOneWidget);
    expect(find.text(zh.tasksStatusTodo), findsOneWidget);

    expect(find.text(zh.tagKnowledgeEmptyQuestions), findsNothing);
  });

  testWidgets('点题目行进入题目详情页', (tester) async {
    final tag = await seedTag('数学');
    final question = await seedQuestion(tag.id, '求二次函数最小值', title: '二次函数最值');

    await pumpEntry(tester, tagId: tag.id, tagLabel: tag.name);
    await tester.tap(
      find.byKey(ValueKey<String>('tag-knowledge-question-${question.id}')),
    );
    await tester.pumpAndSettle();

    expect(find.byType(QuestionDetailPage), findsOneWidget);
  });

  testWidgets('点任务行进入任务详情页', (tester) async {
    final tag = await seedTag('任务');
    final task = await seedTask(tag.id, '整理错题');

    await pumpEntry(tester, tagId: tag.id, tagLabel: tag.name);
    await tester.tap(
      find.byKey(ValueKey<String>('tag-knowledge-task-${task.id}')),
    );
    await tester.pumpAndSettle();

    expect(find.byType(TaskDetailPage), findsOneWidget);
  });

  testWidgets('点卡行打开只读卡详情：正面/答案/提示都在，没有卡组时如实说明', (tester) async {
    final tag = await seedTag('生物');
    final card = await seedCard(
      tag.id,
      front: '细胞壁的成分是？',
      answer: '纤维素和果胶',
      hint: '植物细胞',
      knowledgePointTitle: '细胞结构',
    );

    await pumpEntry(tester, tagId: tag.id, tagLabel: tag.name);
    await tester.tap(
      find.byKey(ValueKey<String>('tag-knowledge-card-${card.id}')),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text(zh.tagKnowledgeCardFront), findsOneWidget);
    expect(find.text('细胞壁的成分是？'), findsWidgets);
    expect(find.text(zh.tagKnowledgeCardAnswer), findsOneWidget);
    expect(find.text('纤维素和果胶'), findsOneWidget);
    expect(find.text(zh.tagKnowledgeCardHint), findsOneWidget);
    expect(find.text('植物细胞'), findsOneWidget);
    expect(
      find.text(zh.tagKnowledgeCardKnowledgePoint('细胞结构')),
      findsOneWidget,
    );
    expect(find.text(zh.tagKnowledgeNoReviewGroup), findsOneWidget);
    expect(find.textContaining('去复习'), findsNothing);
  });

  testWidgets('卡属于已配置卡组：详情弹窗可直接进复习，且带对卡组 id', (tester) async {
    final root = await seedTag('化学');
    final child = await seedTag('平衡', parentId: root.id);
    final card = await seedCard(
      child.id,
      front: '勒夏特列原理？',
      answer: '改变条件平衡向减弱方向移动',
    );
    await ReviewPlanRepository(db, AnkiRepository(db)).setGroupPlan(
      tagId: root.id,
      newCardsPerDay: 5,
      reviewCardsPerDay: 20,
    );

    await pumpEntry(tester, tagId: child.id, tagLabel: child.name);
    await tester.tap(
      find.byKey(ValueKey<String>('tag-knowledge-card-${card.id}')),
    );
    await tester.pumpAndSettle();

    final reviewButton = find.text(zh.tagKnowledgeCardReview('化学'));
    expect(reviewButton, findsOneWidget);

    await tester.tap(reviewButton);
    for (var index = 0; index < 40; index++) {
      await tester.pump(const Duration(milliseconds: 20));
      if (find.byType(ReviewPage).evaluate().isNotEmpty) {
        break;
      }
    }
    expect(find.byType(ReviewPage), findsOneWidget);
    expect(
      tester.widget<ReviewPage>(find.byType(ReviewPage)).scopeTagId,
      root.id,
    );
  });

  testWidgets('「含子标签」开关：直挂为空时打开才出现子树内容', (tester) async {
    final root = await seedTag('物理');
    final child = await seedTag('力学', parentId: root.id);
    await seedQuestion(child.id, '求加速度', title: '加速度题');

    await pumpEntry(tester, tagId: root.id, tagLabel: root.name);
    expect(countBadge('questions', 0), findsOneWidget);
    expect(find.text(zh.tagKnowledgeEmptyQuestions), findsOneWidget);

    await tester.tap(find.byKey(tagKnowledgeScopeSwitchKey));
    await settle(tester);

    expect(countBadge('questions', 1), findsOneWidget);
    expect(find.text('加速度题'), findsOneWidget);
    expect(find.text(zh.tagKnowledgeEmptyQuestions), findsNothing);

    // 再关掉：回到只统计直挂，内容随之消失。
    await tester.tap(find.byKey(tagKnowledgeScopeSwitchKey));
    await settle(tester);
    expect(countBadge('questions', 0), findsOneWidget);
  });

  testWidgets('标签已被删除：页面如实说「已不存在」，不显示三块', (tester) async {
    await pumpEntry(tester, tagId: 'tag-gone', tagLabel: '已删标签');

    expect(find.text(zh.tagKnowledgeTagMissing), findsOneWidget);
    expect(find.text(zh.tagKnowledgeQuestions), findsNothing);
  });

  testWidgets('悬空链接：给出诚实提示，但不补假行', (tester) async {
    final tag = await seedTag('语文');
    await TagRepository(db).addTagToObject(
      tagId: tag.id,
      objectType: 'question',
      objectId: 'q-deleted',
    );

    await pumpEntry(tester, tagId: tag.id, tagLabel: tag.name);

    expect(countBadge('questions', 0), findsOneWidget);
    expect(find.text(zh.tagKnowledgeMissingTargets(1)), findsOneWidget);
    expect(find.text(zh.tagKnowledgeEmptyQuestions), findsOneWidget);
  });

  group('从标签树进入（选中标签 → 三块；切换标签）', () {
    Future<void> pumpTree(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            appDatabaseProvider.overrideWithValue(db),
            questionMediaStoreProvider.overrideWithValue(
              FakeQuestionMediaStore(database: db),
            ),
          ],
          child: const MaterialApp(
            locale: Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: TagTreePage(),
          ),
        ),
      );
      await settle(tester);
      // v48：标签树默认全折叠，要点「力学」这类子标签得先「全部打开」。
      await tester.tap(
        find.byKey(const ValueKey<String>('tag-tree-expand-all')),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('叶子标签点击进入；返回后再选另一个标签，三块内容随之切换', (tester) async {
      final subject = await seedTag('科目');
      final mechanics = await seedTag('力学', parentId: subject.id);
      final physics = await seedTag('物理');
      final question =
          await seedQuestion(mechanics.id, '求小球加速度', title: '力学入口题');
      final task = await seedTask(physics.id, '物理任务入口');

      await pumpTree(tester);
      // 2026-11-15：标签树改成图后，单击节点先开设置浮窗，再从浮窗进「关联内容」。
      await tester.tap(find.text('力学'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(tagNodeSettingsKnowledgeKey));
      await tester.pump();
      await settle(tester);
      expect(find.byType(TagKnowledgeEntryPage), findsOneWidget);
      expect(
        find.byKey(ValueKey<String>('tag-knowledge-question-${question.id}')),
        findsOneWidget,
      );

      // 返回标签树：AppBar 的返回键在中文 locale 下 tooltip 不是 "Back"，
      // `tester.pageBack()` 找不到；直接弹当前路由，语义相同。
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();

      await tester.tap(find.text('物理'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(tagNodeSettingsKnowledgeKey));
      await tester.pump();
      await settle(tester);
      expect(find.byType(TagKnowledgeEntryPage), findsOneWidget);
      expect(
        find.byKey(ValueKey<String>('tag-knowledge-task-${task.id}')),
        findsOneWidget,
      );
      expect(
        find.byKey(ValueKey<String>('tag-knowledge-question-${question.id}')),
        findsNothing,
      );
    });

    testWidgets('父标签节点设置浮窗也有「关联内容」入口', (tester) async {
      final root = await seedTag('根标签');
      await seedTag('子标签', parentId: root.id);

      await pumpTree(tester);
      await tester.tap(find.text('根标签'));
      await tester.pumpAndSettle();
      expect(find.text(zh.tagsKnowledgeEntry), findsOneWidget);

      await tester.tap(find.byKey(tagNodeSettingsKnowledgeKey));
      await tester.pump();
      await settle(tester);

      expect(find.byType(TagKnowledgeEntryPage), findsOneWidget);
    });
  });
}
