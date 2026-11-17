/// 题目详情页「版块清单」的界面级回归测试（2026-11-17）。
///
/// 三条产品口径：
///  1. 一道题在一页里看全：题干 → 答案 → 思维 DAG → 元数据 → 相似题目推荐 →
///     来源文件/来源包 → 页底「AI 解题 / MindNet 认知评价」完整版块；
///  2. 缺数据时版块照样在，写「暂无」，不留只有标题的空卡；
///  3. 「去组卷网搜这道题」只对组卷网有列表页的学科出现：算法竞赛/信息学这类
///     OI 题不摆这个入口（`zujuanSubjectFor` 认不出学科即不渲染）。
library;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/content_ref_repository.dart';
import 'package:furnace/data/repositories/question_repository.dart';
import 'package:furnace/domain/services/zujuan/zujuan_link.dart';
import 'package:furnace/features/ai/application/ai_providers.dart';
import 'package:furnace/features/questions/application/question_media_providers.dart';
import 'package:furnace/features/questions/presentation/question_detail_page.dart';
import 'package:furnace/features/questions/presentation/question_zujuan_search.dart';
import 'package:furnace/l10n/app_localizations.dart';

import 'support/question_media_fakes.dart';

const String _stem = '已知 x^2-5x+6=0，求两根之和。';

late AppLocalizations _zh;

void main() {
  setUpAll(() async {
    _zh = await AppLocalizations.delegate.load(const Locale('zh'));
  });

  testWidgets('版块齐全且顺序是：题干→答案→思维 DAG→元数据→相似→来源→AI 解题/认知评价',
      (WidgetTester tester) async {
    final database = _newDatabase();
    await _insertTag(database);
    final question = await _seedQuestion(
      database,
      answer: '(1) 5',
      solution: '韦达定理：两根之和等于 -b/a。',
      sourceLabel: '2025 高考全国一卷',
      year: 2025,
      region: '全国一卷',
      difficulty: 6,
      capability: const <String>['A2'],
      tagIds: const <String>{'tag-1'},
    );
    await ContentRefRepository(database).upsert(
      contentId: '2025-math-national1#Q3',
      objectType: 'question',
      objectId: question.id,
      role: 'source_package',
      metadata: <String, Object?>{
        'paper_title': '2025 全国一卷',
        'figures': <Object?>[
          <String, Object?>{'path': 'figures/q3.png'},
        ],
      },
    );

    await _pumpDetail(tester, database, question.id);

    final stemTitle = find.text(_zh.questionIntakeStemLabel);
    final answerTitle = find.text(_zh.questionDetailAnswerSection);
    final dagSection = find.byKey(questionDetailDagSectionKey);
    final metadataSection = find.byKey(questionDetailMetadataSectionKey);
    final similarSection = find.byKey(questionDetailSimilarSectionKey);
    final sourceSection = find.byKey(questionDetailSourceSectionKey);
    final aiSection = find.byKey(questionDetailAiCognitiveSectionKey);
    final reasoningSection = find.byKey(questionDetailReasoningSectionKey);
    final cognitiveSection = find.byKey(questionCognitiveSectionKey);

    for (final section in <String, Finder>{
      '题干': stemTitle,
      '答案与解析': answerTitle,
      '思维 DAG': dagSection,
      '元数据': metadataSection,
      '相似题目推荐': similarSection,
      '来源文件与来源包': sourceSection,
      'AI 解题 / MindNet 版块': aiSection,
      'AI 解题卡片': reasoningSection,
      'MindNet 认知评价卡片': cognitiveSection,
    }.entries) {
      expect(section.value, findsOneWidget, reason: '缺少版块：${section.key}');
    }

    final ordered = <String, double>{
      '题干': tester.getTopLeft(stemTitle).dy,
      '答案与解析': tester.getTopLeft(answerTitle).dy,
      '思维 DAG': tester.getTopLeft(dagSection).dy,
      '元数据': tester.getTopLeft(metadataSection).dy,
      '相似题目推荐': tester.getTopLeft(similarSection).dy,
      '来源文件与来源包': tester.getTopLeft(sourceSection).dy,
      'AI 解题 / MindNet 版块': tester.getTopLeft(aiSection).dy,
      'MindNet 认知评价卡片': tester.getTopLeft(cognitiveSection).dy,
    };
    final names = ordered.keys.toList(growable: false);
    for (var i = 1; i < names.length; i++) {
      expect(
        ordered[names[i]]!,
        greaterThan(ordered[names[i - 1]]!),
        reason: '版块顺序不对：${names[i - 1]} 应该在 ${names[i]} 上面',
      );
    }
  });

  testWidgets('缺数据：答案/思维 DAG/元数据/来源都写「暂无」，版块不消失', (WidgetTester tester) async {
    final database = _newDatabase();
    final question = await _seedQuestion(database, answer: null, solution: null);

    await _pumpDetail(tester, database, question.id);

    // 版块根节点都在（不是空占位：每个版块有标题 + 一句「暂无」）。
    expect(find.byKey(questionDetailDagSectionKey), findsOneWidget);
    expect(find.byKey(questionDetailMetadataSectionKey), findsOneWidget);
    expect(find.byKey(questionDetailSourceSectionKey), findsOneWidget);
    expect(find.text(_zh.questionDetailDagSection), findsOneWidget);
    expect(find.text(_zh.questionDetailMetadataSection), findsOneWidget);
    expect(find.text(_zh.questionDetailSourceSection), findsOneWidget);

    // 缺答案/链/来源包时是「暂无」而不是空白。
    expect(find.text(_zh.questionDetailAnswerEmpty), findsOneWidget);
    expect(find.text(_zh.questionDetailNoChainYet), findsOneWidget);
    expect(find.text(_zh.questionDetailSourceEmpty), findsOneWidget);
    // 元数据里年份/地区/能力点/标签都没有：至少出现 4 行「暂无」。
    expect(
      find.text(_zh.questionDetailMetadataNone),
      findsAtLeastNWidgets(4),
    );
  });

  testWidgets('来源包有数据：显示内容 id、整卷标题与来源图文件路径', (WidgetTester tester) async {
    final database = _newDatabase();
    final question = await _seedQuestion(database);
    await ContentRefRepository(database).upsert(
      contentId: '2025-math-national1#Q3',
      objectType: 'question',
      objectId: question.id,
      role: 'source_package',
      metadata: <String, Object?>{
        'paper_title': '2025 全国一卷',
        'figures': <Object?>[
          <String, Object?>{'path': 'figures/q3.png'},
        ],
      },
    );

    await _pumpDetail(tester, database, question.id);

    expect(find.text('2025-math-national1#Q3'), findsOneWidget);
    expect(find.textContaining('2025 全国一卷'), findsOneWidget);
    expect(
      find.textContaining('figures/q3.png'),
      findsOneWidget,
      reason: '来源图文件路径应该出现在「来源文件」一行',
    );
    expect(find.text(_zh.questionDetailSourceEmpty), findsNothing);
  });

  testWidgets('原题链接：复制按钮写剪贴板并提示', (WidgetTester tester) async {
    final database = _newDatabase();
    const url = 'https://example.com/p/1';
    final question = await _seedQuestion(database, sourceUrl: url);

    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall call) async {
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

    await _pumpDetail(tester, database, question.id);
    await tester.tap(find.byKey(questionDetailSourceCopyKey));
    await tester.pumpAndSettle();

    final copies = calls
        .where((call) => call.method == 'Clipboard.setData')
        .toList(growable: false);
    expect(copies, hasLength(1));
    expect((copies.single.arguments as Map<Object?, Object?>)['text'], url);
    expect(find.text(_zh.questionSourceCopyDone), findsOneWidget);
  });

  testWidgets('OI（算法竞赛）题：即使能算出检索词，也不摆组卷网搜索入口', (WidgetTester tester) async {
    final database = _newDatabase();
    final question = await _seedQuestion(
      database,
      subjectKey: 'algorithm',
      stem: '给定一个整数序列，求区间最大子段和。',
    );

    await _pumpDetail(
      tester,
      database,
      question.id,
      zujuanCandidates: const <ZujuanSearchCandidate>[
        ZujuanSearchCandidate(
          keyword: '给定一个整数序列，求区间最大子段和',
          url: 'https://zujuan.xkw.com/1q1.html',
        ),
      ],
    );

    expect(find.byKey(questionZujuanSearchButtonKey), findsNothing);
    // 版块本身照常，不是把整页藏起来。
    expect(find.byKey(questionDetailSourceSectionKey), findsOneWidget);
  });

  testWidgets('普通学科题（数学）仍出现组卷网搜索入口', (WidgetTester tester) async {
    final database = _newDatabase();
    final question = await _seedQuestion(database);

    await _pumpDetail(
      tester,
      database,
      question.id,
      zujuanCandidates: const <ZujuanSearchCandidate>[
        ZujuanSearchCandidate(
          keyword: '已知方程求两根之和',
          url: 'https://zujuan.xkw.com/1q1.html',
        ),
      ],
    );

    expect(find.byKey(questionZujuanSearchButtonKey), findsOneWidget);
  });
}

AppDatabase _newDatabase() {
  final database = AppDatabase.forTesting(NativeDatabase.memory());
  addTearDown(database.close);
  return database;
}

Future<void> _insertTag(AppDatabase database) async {
  await database.into(database.tags).insert(
        TagsCompanion.insert(
          id: 'tag-1',
          name: '数学',
          path: const Value<String>('文化课/学科/数学'),
          createdAt: 1,
          updatedAt: 1,
        ),
      );
}

Future<Question> _seedQuestion(
  AppDatabase database, {
  String? answer = '5',
  String? solution = '韦达定理：两根之和等于 -b/a。',
  String subjectKey = 'math',
  String? sourceUrl,
  String sourceLabel = '',
  int? year,
  String? region,
  double? difficulty,
  List<String> capability = const <String>[],
  Set<String> tagIds = const <String>{},
  String stem = _stem,
}) async {
  final result = await QuestionRepository(database).ingest(
    QuestionDraft(
      stem: stem,
      answer: answer,
      solution: solution,
      subjectKey: subjectKey,
      questionType: 'solution',
      sourceLevel: 'gaokao',
      sourceLabel: sourceLabel,
      year: year,
      region: region,
      difficulty: difficulty,
      capability: capability,
      tagIds: tagIds,
      sourceUrl: sourceUrl,
      options: const <QuestionOptionDraft>[
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
  return result.question;
}

Future<void> _pumpDetail(
  WidgetTester tester,
  AppDatabase database,
  String questionId, {
  List<ZujuanSearchCandidate>? zujuanCandidates,
}) async {
  tester.view.physicalSize = const Size(1200, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        appDatabaseProvider.overrideWithValue(database),
        modelAdapterProvider.overrideWithValue(null),
        questionMediaStoreProvider.overrideWithValue(
          FakeQuestionMediaStore(database: database),
        ),
        if (zujuanCandidates != null)
          questionZujuanCandidatesProvider.overrideWith(
            (ref, query) => zujuanCandidates,
          ),
      ],
      child: MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: QuestionDetailPage(questionId: questionId),
      ),
    ),
  );
  // 推进固定帧数，让题库/相似题/认知读数这些异步 provider 都读完。
  // 不用 pumpAndSettle：链上的风险条是定值进度条，页面永远"不静止"。
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}
