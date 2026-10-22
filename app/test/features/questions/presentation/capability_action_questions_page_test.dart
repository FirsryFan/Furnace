import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/features/questions/presentation/capability_action_questions_page.dart';
import 'package:furnace/features/questions/presentation/question_detail_page.dart';
import 'package:furnace/l10n/app_localizations.dart';

/// 「按能力动作找题」页：从画像点进来之后看到的是"哪些题练到这个动作"。
///
/// 这一页是只读的；它回答的是画像的下一个问题（"那练哪几道？"），
/// 所以测试钉三件事：动作名说人话、每行是题（题干 + 学科/来源/链上动作）、点得进详情页。
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

  Future<void> seedQuestion({
    required String id,
    required String stem,
    String subjectKey = 'math',
    String sourceLevel = 'gaokao',
  }) async {
    await db.into(db.questions).insert(
          QuestionsCompanion.insert(
            id: id,
            stem: stem,
            createdAt: 1,
            updatedAt: 1,
            subjectKey: Value(subjectKey),
            sourceLevel: Value(sourceLevel),
          ),
        );
  }

  Future<void> seedChain({
    required String questionId,
    required List<String> actions,
  }) async {
    final chainId = 'chain-$questionId';
    await db.into(db.reasoningChains).insert(
          ReasoningChainsCompanion.insert(
            id: chainId,
            questionId: questionId,
            createdAt: 10,
            summary: const Value(''),
            stepCount: Value(actions.length),
          ),
        );
    for (var i = 0; i < actions.length; i++) {
      await db.into(db.reasoningSteps).insert(
            ReasoningStepsCompanion.insert(
              id: '$chainId-step-$i',
              chainId: chainId,
              idx: i,
              goal: '第 $i 步',
              actionType: Value(actions[i]),
              createdAt: 10,
            ),
          );
    }
  }

  /// 给某道题插一行「题干图」附件：列表的题干显示文本只读 attachments 计数，
  /// 不读图片字节，所以不需要真的落盘一个文件。
  Future<void> seedStemImage({required String questionId}) async {
    await db.into(db.attachments).insert(
          AttachmentsCompanion.insert(
            id: 'attachment-$questionId',
            ownerType: 'question',
            ownerId: questionId,
            relPath: 'media/$questionId/page.png',
            mime: const Value('image/png'),
            sortOrder: const Value(0),
            role: const Value('stem'),
            createdAt: 1,
          ),
        );
  }

  /// 等显示文本从原文换成快照摘录（provider 解析是异步的）。
  Future<void> waitForText(WidgetTester tester, String text) async {
    for (var i = 0; i < 120; i++) {
      await tester.pump(const Duration(milliseconds: 20));
      if (find.text(text).evaluate().isNotEmpty) {
        return;
      }
    }
    fail('等了 2.4 秒也没等到这段文字：$text');
  }

  Future<void> pumpPage(WidgetTester tester, String actionType) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: CapabilityActionQuestionsPage(actionType: actionType),
        ),
      ),
    );
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 20));
      if (find.byType(LinearProgressIndicator).evaluate().isEmpty) {
        return;
      }
    }
  }

  testWidgets('列出的题带题干与"学科/来源/链上动作"，点一行进详情页', (tester) async {
    await seedQuestion(id: 'q-1', stem: '抽取两次，求条件概率。');
    await seedChain(
      questionId: 'q-1',
      actions: const <String>['case_split', 'sanity_check'],
    );

    await pumpPage(tester, 'case_split');

    // 标题用词表里的中文名，不摆 key。
    expect(
      find.text(zh.capabilityActionQuestionsTitle('分类讨论')),
      findsOneWidget,
    );
    expect(find.text(zh.capabilityActionQuestionsNote), findsOneWidget);
    expect(find.text('抽取两次，求条件概率。'), findsOneWidget);
    // 行副标题：学科 · 来源 · 链上动作（词表外的 key 原样显示）。
    expect(
      find.text(zh.capabilityActionQuestionsMeta('数学', '高考真题', '分类讨论、回代检验')),
      findsOneWidget,
    );

    await tester.tap(find.text('抽取两次，求条件概率。'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(QuestionDetailPage), findsOneWidget);
  });

  testWidgets('没有解过含这个动作的题：说清"还没有"，并指去解题', (tester) async {
    await pumpPage(tester, 'induction');

    expect(
      find.text(zh.capabilityActionQuestionsEmpty('归纳')),
      findsOneWidget,
    );
    expect(find.byType(Card), findsNothing);
  });

  testWidgets('学科筛选：走读表（组合查询），选中后只剩该学科的题，能切回全部', (tester) async {
    await seedQuestion(id: 'q-math', stem: '数学的分类讨论题。', subjectKey: 'math');
    await seedQuestion(
      id: 'q-phys',
      stem: '物理的分类讨论题。',
      subjectKey: 'physics',
      sourceLevel: 'school',
    );
    await seedChain(
      questionId: 'q-math',
      actions: const <String>['case_split'],
    );
    await seedChain(
      questionId: 'q-phys',
      actions: const <String>['case_split'],
    );

    await pumpPage(tester, 'case_split');

    // 两个学科都真实出现过 → 至少两个学科 chip + 「全部学科」。
    expect(find.text(zh.capabilityActionQuestionsAllSubjects), findsOneWidget);
    expect(find.text('数学'), findsWidgets);
    expect(find.text('物理'), findsWidgets);
    expect(find.text('数学的分类讨论题。'), findsOneWidget);
    expect(find.text('物理的分类讨论题。'), findsOneWidget);

    // 点「物理」：只剩物理那道（筛选走读表，不是在已加载结果里过滤）。
    await tester.tap(find.widgetWithText(ChoiceChip, '物理'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('物理的分类讨论题。'), findsOneWidget);
    expect(find.text('数学的分类讨论题。'), findsNothing);

    // 切回「全部学科」：两道都回来。
    await tester.tap(
      find.widgetWithText(ChoiceChip, zh.capabilityActionQuestionsAllSubjects),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('数学的分类讨论题。'), findsOneWidget);
    expect(find.text('物理的分类讨论题。'), findsOneWidget);
  });

  testWidgets('叠加第二个动作 + 「都要出现」：列表收窄；清掉后恢复并收起开关', (tester) async {
    await seedQuestion(id: 'q-both', stem: '两个动作都用上的题。');
    await seedQuestion(id: 'q-split', stem: '只用分类讨论的题。');
    await seedChain(
      questionId: 'q-both',
      actions: const <String>['case_split', 'sanity_check'],
    );
    await seedChain(
      questionId: 'q-split',
      actions: const <String>['case_split'],
    );

    await pumpPage(tester, 'case_split');
    expect(find.text('两个动作都用上的题。'), findsOneWidget);
    expect(find.text('只用分类讨论的题。'), findsOneWidget);
    // 没叠加第二个动作时不该有「都要出现」开关。
    expect(find.byType(Switch), findsNothing);

    // 选第二个动作：sanity_check（回代检验）。
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('回代检验（sanity_check）').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // 默认 any：只看"链上含分类讨论或回代检验"——两道都还在。
    expect(find.text('两个动作都用上的题。'), findsOneWidget);
    expect(find.text('只用分类讨论的题。'), findsOneWidget);
    expect(find.byType(Switch), findsOneWidget);

    // 打开「两个动作都得出现在同一条链里」：只剩两个动作都有的那道。
    await tester.tap(find.byType(Switch));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('两个动作都用上的题。'), findsOneWidget);
    expect(find.text('只用分类讨论的题。'), findsNothing);

    // 清掉第二个动作（选「不叠加」）：开关收起、列表回到两道。
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester
        .tap(find.text(zh.capabilityActionQuestionsSecondActionNone).last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byType(Switch), findsNothing);
    expect(find.text('两个动作都用上的题。'), findsOneWidget);
    expect(find.text('只用分类讨论的题。'), findsOneWidget);
  });

  testWidgets('整卡快照题：一行显示可读摘录，不露［图N］', (tester) async {
    final placeholders =
        List<String>.generate(12, (index) => '［图${index + 1}］').join();
    final stem = '已知函数 \$f(x)=x^2\$，求最小值。$placeholders';
    await seedQuestion(id: 'q-snapshot', stem: stem);
    await seedStemImage(questionId: 'q-snapshot');
    await seedChain(
      questionId: 'q-snapshot',
      actions: const <String>['case_split'],
    );

    await pumpPage(tester, 'case_split');
    await waitForText(tester, r'已知函数 $f(x)=x^2$，求最小值');

    expect(find.text(r'已知函数 $f(x)=x^2$，求最小值'), findsOneWidget);
    expect(find.textContaining('［图'), findsNothing);
  });

  testWidgets('快照题没有正文摘录：一行退成「整题截图 · N 处公式/图」', (tester) async {
    final stem =
        '，。${List<String>.generate(12, (index) => '［图${index + 1}］').join()}';
    await seedQuestion(id: 'q-snapshot-bare', stem: stem);
    await seedStemImage(questionId: 'q-snapshot-bare');
    await seedChain(
      questionId: 'q-snapshot-bare',
      actions: const <String>['case_split'],
    );

    await pumpPage(tester, 'case_split');
    await waitForText(tester, '整题截图 · 12 处公式/图');

    expect(find.text('整题截图 · 12 处公式/图'), findsOneWidget);
    expect(find.textContaining('［图'), findsNothing);
  });
}
