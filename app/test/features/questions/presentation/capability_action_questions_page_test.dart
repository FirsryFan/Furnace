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
}
