/// 题目详情页「MindNet 认知评价」卡片的界面级测试：
///
///  * 空态（没有知识点/没有记忆行）时卡片在、显示「还读不到」，不编数字；
///  * 有读数时卡片把区域/判词/理由/建议/先验/未标定声明逐项摆出来；
///  * 读数读失败时整块零高度，不挡住详情页其它部分。
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/question_repository.dart';
import 'package:furnace/domain/services/cognitive/problem_evaluator.dart'
    show ProblemVerdict;
import 'package:furnace/features/ai/application/ai_providers.dart';
import 'package:furnace/features/anki/application/review_advisory.dart'
    show ReviewZone;
import 'package:furnace/features/questions/application/question_cognitive_provider.dart';
import 'package:furnace/features/questions/application/question_media_providers.dart';
import 'package:furnace/features/questions/presentation/question_detail_page.dart';
import 'package:furnace/l10n/app_localizations.dart';

import 'support/question_media_fakes.dart';

const String _stem = '已知 x^2-5x+6=0，求两根之和。';

late AppLocalizations _zh;

void main() {
  setUpAll(() async {
    _zh = await AppLocalizations.delegate.load(const Locale('zh'));
  });

  testWidgets('空态：题目没挂知识点 ⇒ 卡片在，显示「还读不到」', (tester) async {
    final database = _newDatabase();
    final question = await _seedQuestion(database);

    await _pumpDetail(tester, database, question.id);
    await _waitFor(tester, find.byKey(questionCognitiveSectionKey));

    expect(find.byKey(questionCognitiveSectionKey), findsOneWidget);
    expect(find.text(_zh.questionCognitiveTitle), findsOneWidget);
    expect(find.text(_zh.questionCognitiveEmpty), findsOneWidget);
    expect(find.text(_zh.questionCognitiveUncalibrated), findsOneWidget);
  });

  testWidgets('有读数：区域/判词/理由/建议/先验/未标定逐项显示', (tester) async {
    final database = _newDatabase();
    final question = await _seedQuestion(database);

    await _pumpDetail(
      tester,
      database,
      question.id,
      overrides: <Override>[
        questionCognitiveReadingProvider.overrideWith(
          (ref, questionId) => _reading(questionId),
        ),
      ],
    );
    await _waitFor(tester, find.byKey(questionCognitiveSectionKey));

    expect(find.byKey(questionCognitiveSectionKey), findsOneWidget);
    expect(find.text(_zh.questionCognitiveTitle), findsOneWidget);
    expect(
      find.text(_zh.questionCognitiveZone(_zh.cognitiveZoneDanger)),
      findsOneWidget,
    );
    expect(
      find.text(_zh.questionCognitiveFit('值得现在做')),
      findsOneWidget,
    );
    expect(find.text('平均可提取度 62%，模型增益 1.30'), findsOneWidget);
    expect(find.text('先补先验（危险区，先复习/先测评）'), findsOneWidget);
    expect(find.text(_zh.cognitiveEncodingPrior('0.72')), findsOneWidget);
    expect(find.text(_zh.questionCognitiveUncalibrated), findsOneWidget);
    expect(find.text(_zh.questionCognitiveEmpty), findsNothing);
  });

  testWidgets('读数读失败 ⇒ 卡片零高度，题目本身照常显示', (tester) async {
    final database = _newDatabase();
    final question = await _seedQuestion(database);

    await _pumpDetail(
      tester,
      database,
      question.id,
      overrides: <Override>[
        questionCognitiveReadingProvider.overrideWith(
          (ref, questionId) => Future<QuestionCognitiveReading>.error(
            StateError('boom'),
          ),
        ),
      ],
    );
    await _waitFor(tester, find.text(_stem));

    expect(find.text(_stem), findsOneWidget);
    expect(find.byKey(questionCognitiveSectionKey), findsNothing);
  });
}

QuestionCognitiveReading _reading(String questionId) =>
    QuestionCognitiveReading(
      questionId: questionId,
      knowledgePointIds: const <String>['kp-1'],
      judgedKnowledgePointIds: const <String>['kp-1'],
      zone: ReviewZone.danger,
      verdict: ProblemVerdict.highValue,
      reason: '平均可提取度 62%，模型增益 1.30',
      suggestion: QuestionCognitiveSuggestion.buildPrior,
      priorR0: 0.72,
      priorConfidence: 0.625,
      priorSamples: 5,
      fastLayerRan: true,
    );

AppDatabase _newDatabase() {
  final database = AppDatabase.forTesting(NativeDatabase.memory());
  addTearDown(database.close);
  return database;
}

Future<Question> _seedQuestion(AppDatabase database) async {
  final ingested = await QuestionRepository(database).ingest(
    const QuestionDraft(
      stem: _stem,
      answer: '5',
      solution: '韦达定理：两根之和等于 -b/a。',
      subjectKey: 'math',
      questionType: 'single_choice',
      sourceLevel: 'gaokao',
      difficulty: 4,
      options: <QuestionOptionDraft>[
        QuestionOptionDraft(label: 'A', content: '3', sortOrder: 0),
        QuestionOptionDraft(
          label: 'B',
          content: '5',
          isCorrect: true,
          sortOrder: 1,
        ),
      ],
    ),
  );
  return ingested.question;
}

Future<void> _pumpDetail(
  WidgetTester tester,
  AppDatabase database,
  String questionId, {
  List<Override> overrides = const <Override>[],
}) async {
  _bigSurface(tester);
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        appDatabaseProvider.overrideWithValue(database),
        modelAdapterProvider.overrideWithValue(null),
        questionMediaStoreProvider.overrideWithValue(
          FakeQuestionMediaStore(database: database),
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
  await tester.pump();
}

/// 页面很长，默认 800×600 视口里 ListView 只建可见的那几行。
void _bigSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// 轮询推进直到 finder 出现（异步 provider + 数据库回读需要的帧数不确定）。
Future<void> _waitFor(
  WidgetTester tester,
  Finder finder, {
  int rounds = 150,
}) async {
  for (var i = 0; i < rounds; i += 1) {
    await tester.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().isNotEmpty) {
      return;
    }
  }
  fail('等了 15 秒也没等到目标 widget');
}
