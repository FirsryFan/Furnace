/// 题目详情页的界面级测试：把「AI 解题」这条通路的两头都钉住。
///
/// 三件事必须一直成立：
///
///  1. **成功时链会落库**：`reasoning_chains` / `reasoning_steps` 里真有一行，
///     页面上每一步的目标、能力动作、模型风险都看得见。
///  2. **失败时不吞**：离线（没有适配器）、模型报错、回复不合契约，三种原因与
///     已经收到的原始回复都要显示出来，并且一行都不写库。
///  3. **"没有你的读数"看得见**：卡点评估里 `unmatchedHints` 是"本地没有读
///     数"，不是"这一步没问题"；界面上必须能区分这两件事。
///
/// 数据库用内存库（不装 `instrumentWrites`——这里断言的是"写进去了没有"，
/// 不是"界面自己刷新了吗"）；模型用 `FakeModelAdapter`。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/question_repository.dart';
import 'package:furnace/features/questions/data/question_media_store.dart';
import 'package:furnace/domain/services/paper/similar_questions.dart';
import 'package:furnace/domain/services/questions/question_source.dart';
import 'package:furnace/domain/services/zujuan/zujuan_link.dart';
import 'package:furnace/features/ai/application/ai_providers.dart';
import 'package:furnace/features/ai/domain/model_adapter.dart';
import 'package:furnace/features/ai/infrastructure/fake_model_adapter.dart';
import 'package:furnace/features/questions/application/question_media_providers.dart';
import 'package:furnace/features/questions/application/similar_question_provider.dart';
import 'package:furnace/features/questions/presentation/question_detail_page.dart';
import 'package:furnace/features/questions/presentation/question_media_view.dart';
import 'package:furnace/features/questions/presentation/question_title_dialog.dart';
import 'package:furnace/features/questions/presentation/question_source_edit_dialog.dart';
import 'package:furnace/features/questions/presentation/question_intake_page.dart';
import 'package:furnace/features/questions/presentation/question_intake_providers.dart';
import 'package:furnace/features/questions/presentation/question_zujuan_search.dart';
import 'package:furnace/l10n/app_localizations.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

import '../support/picked_file_fakes.dart';
import 'support/question_media_fakes.dart';

const String _stem = '已知 x^2-5x+6=0，求两根之和。';
const String _chainSummary = '先把系数看清楚，再用韦达定理，最后回代检验。';
const String _missingQuestionId = 'q-does-not-exist';

late AppLocalizations _zh;

void main() {
  setUpAll(() async {
    _zh = await AppLocalizations.delegate.load(const Locale('zh'));
  });

  testWidgets('解题成功：步骤逐条展示，链真的落进库里', (WidgetTester tester) async {
    final database = _newDatabase();
    final question = await _seedQuestion(database);
    final adapter = FakeModelAdapter(<List<ModelEvent>>[
      FakeModelAdapter.answer(_replyJson()),
    ]);

    await _pumpDetail(tester, database, question.id, adapter: adapter);
    await tester.tap(find.text(_zh.questionDetailSolveButton));
    await _waitForText(tester, _zh.questionDetailStepTitle(1));

    expect(find.text(_zh.questionDetailStepTitle(2)), findsOneWidget);
    expect(find.text('确认方程的标准形式'), findsOneWidget);
    expect(find.text('从定义出发'), findsOneWidget);
    expect(find.text('回代检验'), findsOneWidget);
    expect(find.text(_zh.questionDetailModelRisk(80)), findsOneWidget);
    expect(find.text(_zh.questionDetailModelRisk(20)), findsOneWidget);
    expect(find.text(_zh.questionDetailOverallRisk(80)), findsOneWidget);
    expect(adapter.requests, hasLength(1));

    final repository = QuestionRepository(database);
    final chains = await repository.chainsOf(question.id);
    expect(chains, hasLength(1));
    expect(chains.single.summary, _chainSummary);
    expect(chains.single.stepCount, 2);

    final steps = await repository.stepsOf(chains.single.id);
    expect(steps.map((step) => step.idx).toList(), <int>[0, 1]);
    expect(steps.first.goal, '确认方程的标准形式');
    expect(steps.first.actionType, 'first_principles');
    expect(jsonDecode(steps.first.knowledgeHints), <String>['kp-1']);
    // `saveChain` 顺带把题目推进到 processed。
    expect((await repository.byId(question.id))!.state, 'processed');
  });

  testWidgets('离线：说清没有适配器，一行都不写库', (WidgetTester tester) async {
    final database = _newDatabase();
    final question = await _seedQuestion(database);

    await _pumpDetail(tester, database, question.id, adapter: null);
    await tester.tap(find.text(_zh.questionDetailSolveButton));
    await _waitForText(tester, _zh.questionDetailRunFailedTitle);

    expect(find.text('没有可用的模型适配器（离线或未配置）'), findsOneWidget);
    expect(find.text(_zh.questionDetailRawReplyMissing), findsOneWidget);
    expect(find.text(_zh.questionDetailNoChainYet), findsOneWidget);
    expect(await QuestionRepository(database).chainsOf(question.id), isEmpty);
  });

  testWidgets('模型报错：原因与已经收到的原文都摊出来，不写库', (WidgetTester tester) async {
    final database = _newDatabase();
    final question = await _seedQuestion(database);
    final adapter = FakeModelAdapter(<List<ModelEvent>>[
      const <ModelEvent>[
        ModelTextDelta('半截回复：先看系数'),
        ModelFailure('网络断了'),
      ],
    ]);

    await _pumpDetail(tester, database, question.id, adapter: adapter);
    await tester.tap(find.text(_zh.questionDetailSolveButton));
    await _waitForText(tester, _zh.questionDetailRunFailedTitle);

    expect(find.text('模型调用失败：网络断了'), findsOneWidget);
    expect(find.text('半截回复：先看系数'), findsOneWidget);
    expect(find.text(_zh.questionDetailRawReplyMissing), findsNothing);
    expect(await QuestionRepository(database).chainsOf(question.id), isEmpty);
  });

  testWidgets('回复不合契约：说清是契约问题，原文照显，不写库', (WidgetTester tester) async {
    final database = _newDatabase();
    final question = await _seedQuestion(database);
    final adapter = FakeModelAdapter(<List<ModelEvent>>[
      FakeModelAdapter.answer('这道题我不会，抱歉。'),
    ]);

    await _pumpDetail(tester, database, question.id, adapter: adapter);
    await tester.tap(find.text(_zh.questionDetailSolveButton));
    await _waitForText(tester, _zh.questionDetailRunFailedTitle);

    expect(find.textContaining('模型回复不符合契约'), findsOneWidget);
    expect(find.text('这道题我不会，抱歉。'), findsOneWidget);
    expect(await QuestionRepository(database).chainsOf(question.id), isEmpty);
  });

  testWidgets('有状态读数：融合风险出现、覆盖率报满，不再说"暂无数据"', (WidgetTester tester) async {
    final database = _newDatabase();
    final question = await _seedQuestion(database);
    await database.into(database.cardStates).insert(
          CardStatesCompanion.insert(
            id: 'cs-1',
            knowledgePointId: const Value('kp-1'),
            stability: const Value(1.0),
            difficulty: const Value(9.0),
            encodingStrength: const Value(1.0),
            savings: const Value(0.8),
            repetitions: const Value(3),
            createdAt: 1,
            updatedAt: 2,
          ),
        );
    final adapter = FakeModelAdapter(<List<ModelEvent>>[
      FakeModelAdapter.answer(_replyJson()),
    ]);

    await _pumpDetail(tester, database, question.id, adapter: adapter);
    await tester.tap(find.text(_zh.questionDetailSolveButton));
    await _waitForText(tester, _zh.questionDetailStepTitle(1));

    expect(find.text(_zh.questionDetailEvidenceCoverage(2, 2)), findsOneWidget);
    expect(find.textContaining('合上你的状态读数'), findsNWidgets(2));
    expect(find.textContaining('（暂无你的状态数据）'), findsNothing);
    expect(find.text(_zh.questionDetailUnmatchedHintsTitle), findsNothing);
  });

  testWidgets('没有读数：明说"暂无你的状态数据"，并列出未匹配的知识点', (WidgetTester tester) async {
    final database = _newDatabase();
    final question = await _seedQuestion(database);
    final adapter = FakeModelAdapter(<List<ModelEvent>>[
      FakeModelAdapter.answer(_replyJson()),
    ]);

    await _pumpDetail(tester, database, question.id, adapter: adapter);
    await tester.tap(find.text(_zh.questionDetailSolveButton));
    await _waitForText(tester, _zh.questionDetailStepTitle(1));

    expect(find.text(_zh.questionDetailEvidenceCoverage(0, 2)), findsOneWidget);
    expect(find.textContaining('（暂无你的状态数据）'), findsNWidgets(2));
    expect(find.text(_zh.questionDetailUnmatchedHintsTitle), findsOneWidget);
    expect(find.text(_zh.questionDetailUnmatchedHintsBody), findsOneWidget);
    expect(find.text('kp-1'), findsWidgets);
    expect(find.textContaining('合上你的状态读数'), findsNothing);
  });

  testWidgets('题目不存在：说清缺失，且不让解题', (WidgetTester tester) async {
    final database = _newDatabase();
    final adapter = FakeModelAdapter(<List<ModelEvent>>[
      FakeModelAdapter.answer(_replyJson()),
    ]);

    await _pumpDetail(tester, database, _missingQuestionId, adapter: adapter);

    expect(find.text(_zh.questionDetailQuestionMissing), findsOneWidget);
    await tester.tap(find.text(_zh.questionDetailSolveButton),
        warnIfMissed: false);
    await _settle(tester);
    expect(adapter.requests, isEmpty);
  });

  testWidgets('模型给了词表里没有的动作：如实说出来，不假装认识', (WidgetTester tester) async {
    final database = _newDatabase();
    final question = await _seedQuestion(database);
    final adapter = FakeModelAdapter(<List<ModelEvent>>[
      FakeModelAdapter.answer(_replyJson(secondActionType: 'mystery_move')),
    ]);

    await _pumpDetail(tester, database, question.id, adapter: adapter);
    await tester.tap(find.text(_zh.questionDetailSolveButton));
    await _waitForText(tester, _zh.questionDetailUnknownAction('mystery_move'));

    expect(
      find.text(_zh.questionDetailUnknownAction('mystery_move')),
      findsOneWidget,
    );
    // 词表里的另一步照旧显示中文名，两件事不互相掩盖。
    expect(find.text('从定义出发'), findsOneWidget);
    expect(find.text('回代检验'), findsNothing);
  });

  testWidgets('进入页面时显示库里已有的链，而不是"还没有"', (WidgetTester tester) async {
    final database = _newDatabase();
    final question = await _seedQuestion(database);
    await QuestionRepository(database).saveChain(
      question.id,
      const ReasoningChainDraft(
        summary: '库里那条链',
        steps: <ReasoningStepDraft>[
          ReasoningStepDraft(
            goal: '第一步：读题',
            actionType: 'first_principles',
            justification: '先把条件抄下来',
            checkMethod: '复述一遍',
            stuckRisk: 0.4,
          ),
          ReasoningStepDraft(
            goal: '第二步：求解',
            actionType: 'sanity_check',
            justification: '回代检验',
            checkMethod: '',
            stuckRisk: 0.1,
          ),
        ],
      ),
    );
    final adapter = FakeModelAdapter(<List<ModelEvent>>[
      FakeModelAdapter.answer(_replyJson()),
    ]);

    await _pumpDetail(tester, database, question.id, adapter: adapter);
    await _waitForText(tester, _zh.questionDetailStepTitle(1));

    expect(find.text(_zh.questionDetailChainFromLibrary), findsOneWidget);
    expect(find.text('库里那条链'), findsOneWidget);
    expect(find.text('第一步：读题'), findsOneWidget);
    expect(find.text('第二步：求解'), findsOneWidget);
    expect(find.text(_zh.questionDetailResolveButton), findsOneWidget);
    expect(adapter.requests, isEmpty);
  });

  testWidgets('收题页点一行能进详情页', (WidgetTester tester) async {
    final database = _newDatabase();
    final question = await _seedQuestion(database);
    final root = Directory.systemTemp.createTempSync('furnace_detail_entry_');
    addTearDown(() {
      if (root.existsSync()) {
        root.deleteSync(recursive: true);
      }
    });

    await _pumpIntake(tester, database, root);
    await _waitForText(tester, question.stem);

    await tester.tap(find.text(question.stem));
    await tester.pump();
    await _waitForType(tester, QuestionDetailPage);

    expect(find.byType(QuestionDetailPage), findsOneWidget);
  });

  testWidgets('改来源：分级/年份/地区存得住，题干一个字不动', (WidgetTester tester) async {
    final database = _newDatabase();
    final repository = QuestionRepository(database);
    final seeded = await repository.ingest(
      const QuestionDraft(
        stem: '不确定来源的一道题',
        answer: '42',
        subjectKey: 'math',
        questionType: 'solution',
        sourceLevel: 'unknown',
      ),
    );

    await _pumpDetail(tester, database, seeded.question.id, adapter: null);
    await _waitForText(tester, '不确定来源的一道题');

    expect(find.text(_zh.questionDetailEditSource), findsOneWidget);
    await tester.tap(find.text(_zh.questionDetailEditSource));
    await tester.pumpAndSettle();
    expect(find.text(_zh.questionDetailEditSourceTitle), findsOneWidget);

    // 分级从"未标注"改成"高考真题"。
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_zh.questionIntakeSourceGaokao).last);
    await tester.pumpAndSettle();

    // 年份与地区。来源说明也一起补上。
    final fields = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    await tester.enterText(fields.at(0), '2024 湖南师大附中月考');
    await tester.enterText(fields.at(1), '2024');
    await tester.enterText(fields.at(2), '湖南');
    await tester.tap(find.text(_zh.commonSave));
    await tester.pumpAndSettle();

    // 页面自己刷新：来源行变成"高考真题"，年份也在。
    await tester.pumpAndSettle();
    expect(find.textContaining(_zh.questionIntakeSourceGaokao), findsWidgets);
    expect(find.textContaining(_zh.questionDetailYear(2024)), findsWidgets);

    // 库里的四列变了，题干/答案没动。
    final after = (await repository.byId(seeded.question.id))!;
    expect(after.sourceLevel, 'gaokao');
    expect(after.sourceLabel, '2024 湖南师大附中月考');
    expect(after.year, 2024);
    expect(after.region, '湖南');
    expect(after.stem, seeded.question.stem);
    expect(after.answer, '42');
  });

  testWidgets('改来源时年份写错：停在对话框里说清楚，一行都不写库', (
    WidgetTester tester,
  ) async {
    final database = _newDatabase();
    final repository = QuestionRepository(database);
    final seeded = await repository.ingest(
      const QuestionDraft(
        stem: '年份写错的那道题',
        sourceLevel: 'unknown',
        questionType: 'solution',
      ),
    );

    await _pumpDetail(tester, database, seeded.question.id, adapter: null);
    await _waitForText(tester, '年份写错的那道题');
    await tester.tap(find.text(_zh.questionDetailEditSource));
    await tester.pumpAndSettle();

    final fields = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    await tester.enterText(fields.at(1), '20x4');
    await tester.tap(find.text(_zh.commonSave));
    await tester.pumpAndSettle();

    expect(find.text(_zh.questionDetailEditSourceYearBad), findsOneWidget);
    final after = (await repository.byId(seeded.question.id))!;
    expect(after.year, isNull, reason: '写错就是没写进去');
    expect(after.sourceLevel, 'unknown');
  });

  testWidgets('题号：详情页显示 TR-00001，点一下复制到剪贴板', (WidgetTester tester) async {
    final database = _newDatabase();
    final question = await _seedQuestion(database);

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

    await _pumpDetail(tester, database, question.id, adapter: null);
    await _waitForText(tester, 'TR-00001');

    await tester.tap(find.text('TR-00001'));
    await tester.pump(const Duration(milliseconds: 300));

    final copies = calls
        .where((call) => call.method == 'Clipboard.setData')
        .toList(growable: false);
    expect(copies, hasLength(1));
    expect(
      (copies.single.arguments as Map<Object?, Object?>)['text'],
      'TR-00001',
    );
    expect(find.text(_zh.questionSerialCopied('TR-00001')), findsOneWidget);
  });

  testWidgets('配图：详情页是大图，点开可缩放', (WidgetTester tester) async {
    final database = _newDatabase();
    final question = await _seedQuestion(database);
    final mediaStore = FakeQuestionMediaStore(database: database)
      ..seed(
        questionId: question.id,
        fileName: 'page-1.png',
        bytes: tinyPngBytes,
      );

    await _pumpDetail(
      tester,
      database,
      question.id,
      adapter: null,
      mediaStore: mediaStore,
    );
    await _waitForText(tester, _zh.questionImageCount(1));
    await _waitForType(tester, Image);

    expect(find.text(_zh.questionImageCount(1)), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
    // 没有「题目配图」这种独占区块标题：图直接跟在题干文字里。
    expect(find.text(_zh.questionDetailImagesSection), findsNothing);

    // 图片解码完成前只占位 180 高，先让占位排版落定再点（点的是图本身，
    // 占位和真图都在 InkWell 里，都能打开大图）。
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(Image)).height, greaterThan(0));
    await tester.tap(find.byType(Image));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('题干图文混排：按［图N］占位插进文字，公式渲染成数学', (WidgetTester tester) async {
    final database = _newDatabase();
    final question = await _seedQuestion(
      database,
      stem: r'已知 $x^2-5x+6=0$，求两根之和。［图1］再检验。',
    );
    final mediaStore = FakeQuestionMediaStore(database: database)
      ..seed(
        questionId: question.id,
        fileName: 'graph-1.png',
        bytes: tinyPngBytes,
      )
      ..seed(
        questionId: question.id,
        fileName: 'graph-2.png',
        bytes: tinyPngBytes,
      );

    await _pumpDetail(
      tester,
      database,
      question.id,
      adapter: null,
      mediaStore: mediaStore,
    );
    final inlineImages = find.descendant(
      of: find.byKey(questionStemImagesKey),
      matching: find.byType(QuestionInlineImage),
    );
    await _waitForCount(tester, inlineImages, 2);

    // 公式被排成数学：页面上没有任何字面的 $ 符号。
    expect(find.byType(GptMarkdown), findsWidgets);
    final plainTexts = tester
        .widgetList<Text>(find.byType(Text))
        .map((text) => text.data ?? text.textSpan?.toPlainText() ?? '')
        .toList(growable: false);
    expect(
      plainTexts.where((text) => text.contains(r'$')),
      isEmpty,
      reason: '公式应被渲染，不能留下字面 \$ 定界符',
    );

    // 顺序：文字 → 图1（占位处）→ 后段文字 → 图2（没被引用的图接在末尾）。
    final firstText = tester.getTopLeft(find.textContaining('已知').first).dy;
    final firstImage = tester.getTopLeft(inlineImages.at(0)).dy;
    final tailText = tester.getTopLeft(find.text('再检验。')).dy;
    final secondImage = tester.getTopLeft(inlineImages.at(1)).dy;
    expect(firstImage, greaterThan(firstText));
    expect(tailText, greaterThan(firstImage));
    expect(secondImage, greaterThan(tailText));
  });

  testWidgets('题干没有占位：配图接在题干文字末尾，仍是大图', (WidgetTester tester) async {
    final database = _newDatabase();
    final question = await _seedQuestion(database);
    final mediaStore = FakeQuestionMediaStore(database: database)
      ..seed(
        questionId: question.id,
        fileName: 'page-1.png',
        bytes: tinyPngBytes,
      );

    await _pumpDetail(
      tester,
      database,
      question.id,
      adapter: null,
      mediaStore: mediaStore,
    );
    final inlineImages = find.descendant(
      of: find.byKey(questionStemImagesKey),
      matching: find.byType(QuestionInlineImage),
    );
    await _waitForCount(tester, inlineImages, 1);

    final stemBottom = tester.getBottomLeft(find.text(_stem)).dy;
    final imageTop = tester.getTopLeft(inlineImages.first).dy;
    expect(imageTop, greaterThanOrEqualTo(stemBottom));
  });

  testWidgets('答案截图显示在答案段之后', (WidgetTester tester) async {
    final database = _newDatabase();
    final question = await _seedQuestion(database);
    final mediaStore = FakeQuestionMediaStore(database: database)
      ..seed(
        questionId: question.id,
        fileName: 'answer-1.png',
        bytes: tinyPngBytes,
        role: QuestionImageRole.answer,
      );

    await _pumpDetail(
      tester,
      database,
      question.id,
      adapter: null,
      mediaStore: mediaStore,
    );
    final answerImages = find.descendant(
      of: find.byKey(questionAnswerImagesSectionKey),
      matching: find.byType(QuestionInlineImage),
    );
    await _waitForCount(tester, answerImages, 1);

    final answerLabel =
        tester.getTopLeft(find.text(_zh.questionIntakeAnswerLabel).first).dy;
    final answerImage = tester.getTopLeft(answerImages.first).dy;
    expect(answerImage, greaterThan(answerLabel));
    expect(find.text(_zh.questionAnswerImageTitle), findsNothing);
  });

  testWidgets('没有配图：配图区块整个不出现，不留空相框', (WidgetTester tester) async {
    final database = _newDatabase();
    final question = await _seedQuestion(database);

    await _pumpDetail(tester, database, question.id, adapter: null);
    await _waitForText(tester, _stem);

    expect(find.text(_zh.questionDetailImagesSection), findsNothing);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('配图读不出来：给一个坏图标记，不崩', (WidgetTester tester) async {
    final database = _newDatabase();
    final question = await _seedQuestion(database);
    final mediaStore = FakeQuestionMediaStore(database: database);
    final image = mediaStore.seed(
      questionId: question.id,
      fileName: 'lost.png',
      bytes: tinyPngBytes,
    );
    mediaStore.removeBytes(image);

    await _pumpDetail(
      tester,
      database,
      question.id,
      adapter: null,
      mediaStore: mediaStore,
    );
    await _waitForText(tester, _zh.questionImageCount(1));

    expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('整卡快照：正文占位变省略号，图只放末尾并带「原题整图」', (WidgetTester tester) async {
    final database = _newDatabase();
    final placeholders = List<String>.generate(
      12,
      (index) => '［图${index + 1}］',
    ).join();
    final question = await _seedQuestion(
      database,
      stem: '整题截图：$placeholders完。',
    );
    final mediaStore = FakeQuestionMediaStore(database: database)
      ..seed(
        questionId: question.id,
        fileName: 'full-page.png',
        bytes: _pngHeader(width: 1640, height: 808),
      );

    await _pumpDetail(
      tester,
      database,
      question.id,
      adapter: null,
      mediaStore: mediaStore,
    );
    final stemImages = find.descendant(
      of: find.byKey(questionStemImagesKey),
      matching: find.byType(QuestionInlineImage),
    );
    await _waitForText(tester, _zh.questionDetailOriginalCardImage);
    await _waitForCount(tester, stemImages, 1);

    // 题干正文在 SelectableText 里，用 find.textContaining 才能扫到。
    expect(
      find.textContaining('［图'),
      findsNothing,
      reason: '快照模式下正文不能再露出［图N］占位',
    );
    expect(
      find.textContaining('…'),
      findsWidgets,
      reason: '占位应被替换成省略号',
    );

    final headingTop =
        tester.getTopLeft(find.text(_zh.questionDetailOriginalCardImage)).dy;
    final imageTop = tester.getTopLeft(stemImages.first).dy;
    expect(imageTop, greaterThan(headingTop));
  });

  testWidgets('正常包：两张小图按占位内联，没有整卡标题', (WidgetTester tester) async {
    final database = _newDatabase();
    final question = await _seedQuestion(
      database,
      stem: '前段文字［图1］中间文字［图2］后段文字。',
    );
    final mediaStore = FakeQuestionMediaStore(database: database)
      ..seed(
        questionId: question.id,
        fileName: 'small-1.png',
        bytes: _pngHeader(width: 400, height: 300),
      )
      ..seed(
        questionId: question.id,
        fileName: 'small-2.png',
        bytes: _pngHeader(width: 400, height: 300),
      );

    await _pumpDetail(
      tester,
      database,
      question.id,
      adapter: null,
      mediaStore: mediaStore,
    );
    final stemImages = find.descendant(
      of: find.byKey(questionStemImagesKey),
      matching: find.byType(QuestionInlineImage),
    );
    await _waitForCount(tester, stemImages, 2);

    expect(find.text(_zh.questionDetailOriginalCardImage), findsNothing);
    expect(find.textContaining('［图'), findsNothing);

    final firstText = tester.getTopLeft(find.text('前段文字')).dy;
    final firstImage = tester.getTopLeft(stemImages.at(0)).dy;
    final middleText = tester.getTopLeft(find.text('中间文字')).dy;
    final secondImage = tester.getTopLeft(stemImages.at(1)).dy;
    expect(firstImage, greaterThan(firstText));
    expect(middleText, greaterThan(firstImage));
    expect(secondImage, greaterThan(middleText));
  });

  testWidgets('单张小图 + 单个占位：仍按占位内联', (WidgetTester tester) async {
    final database = _newDatabase();
    final question = await _seedQuestion(
      database,
      stem: '看图［图1］作答。',
    );
    final mediaStore = FakeQuestionMediaStore(database: database)
      ..seed(
        questionId: question.id,
        fileName: 'one.png',
        bytes: _pngHeader(width: 400, height: 300),
      );

    await _pumpDetail(
      tester,
      database,
      question.id,
      adapter: null,
      mediaStore: mediaStore,
    );
    final stemImages = find.descendant(
      of: find.byKey(questionStemImagesKey),
      matching: find.byType(QuestionInlineImage),
    );
    await _waitForCount(tester, stemImages, 1);

    expect(find.text(_zh.questionDetailOriginalCardImage), findsNothing);
    expect(find.textContaining('［图'), findsNothing);
    final imageTop = tester.getTopLeft(stemImages.first).dy;
    final afterText = tester.getTopLeft(find.text('作答。')).dy;
    expect(afterText, greaterThan(imageTop));
  });

  testWidgets('单张大图（>=1000x400）：按整卡快照放到正文末尾', (WidgetTester tester) async {
    final database = _newDatabase();
    final question = await _seedQuestion(database, stem: '见［图1］。');
    final mediaStore = FakeQuestionMediaStore(database: database)
      ..seed(
        questionId: question.id,
        fileName: 'snapshot.png',
        bytes: _pngHeader(width: 1640, height: 808),
      );

    await _pumpDetail(
      tester,
      database,
      question.id,
      adapter: null,
      mediaStore: mediaStore,
    );
    final stemImages = find.descendant(
      of: find.byKey(questionStemImagesKey),
      matching: find.byType(QuestionInlineImage),
    );
    await _waitForText(tester, _zh.questionDetailOriginalCardImage);
    await _waitForCount(tester, stemImages, 1);

    expect(find.text('见…。'), findsOneWidget);
    expect(find.textContaining('［图'), findsNothing);
    final headingTop =
        tester.getTopLeft(find.text(_zh.questionDetailOriginalCardImage)).dy;
    final imageTop = tester.getTopLeft(stemImages.first).dy;
    expect(imageTop, greaterThan(headingTop));
  });

  testWidgets('有占位但没配图：不崩，占位原样保留', (WidgetTester tester) async {
    final database = _newDatabase();
    final question = await _seedQuestion(
      database,
      stem: '这道题没有配图［图1］。',
    );

    await _pumpDetail(tester, database, question.id, adapter: null);
    await _waitForText(tester, '这道题没有配图［图1］。');

    final stemImages = find.descendant(
      of: find.byKey(questionStemImagesKey),
      matching: find.byType(QuestionInlineImage),
    );
    expect(stemImages, findsNothing);
    expect(find.text(_zh.questionDetailOriginalCardImage), findsNothing);
    expect(find.textContaining('［图1］'), findsOneWidget);
  });
  test('组卷网候选 provider：空白题干为空，正常题干每条候选都带搜索链接', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(questionZujuanCandidatesProvider('')), isEmpty);
    expect(container.read(questionZujuanCandidatesProvider('   ')), isEmpty);

    final candidates = container.read(
      questionZujuanCandidatesProvider('细胞膜上的载体蛋白参与物质运输，实验测得浓度梯度。'),
    );
    expect(candidates, isNotEmpty);
    for (final candidate in candidates) {
      expect(candidate.url, zujuanSearchUrl(candidate.keyword));
    }
  });

  testWidgets('组卷网入口：没有可用检索词时整个入口不渲染', (WidgetTester tester) async {
    final database = _newDatabase();
    final question = await _seedQuestion(database);

    await _pumpDetail(
      tester,
      database,
      question.id,
      adapter: null,
      zujuanCandidates: const <ZujuanSearchCandidate>[],
    );
    await _waitForText(tester, _stem);

    expect(find.byKey(questionZujuanSearchButtonKey), findsNothing);
  });

  testWidgets('组卷网入口：点开列出检索词候选与两种操作', (WidgetTester tester) async {
    final database = _newDatabase();
    final question = await _seedQuestion(database);
    final candidates = <ZujuanSearchCandidate>[
      ZujuanSearchCandidate(
        keyword: '细胞膜上的载体蛋白',
        url: zujuanSearchUrl('细胞膜上的载体蛋白'),
      ),
      ZujuanSearchCandidate(
        keyword: '实验测得浓度梯度',
        url: zujuanSearchUrl('实验测得浓度梯度'),
      ),
    ];

    await _pumpDetail(
      tester,
      database,
      question.id,
      adapter: null,
      zujuanCandidates: candidates,
    );
    await _waitForText(tester, _stem);

    expect(find.byKey(questionZujuanSearchButtonKey), findsOneWidget);
    await tester.tap(find.byKey(questionZujuanSearchButtonKey));
    await tester.pumpAndSettle();

    expect(find.text('细胞膜上的载体蛋白'), findsOneWidget);
    expect(find.text('实验测得浓度梯度'), findsOneWidget);
    expect(find.text(_zh.questionZujuanBankHint), findsOneWidget);
    expect(find.text(_zh.questionZujuanCopyKeyword), findsNWidgets(2));
    expect(find.text(_zh.questionZujuanOpenUrl), findsNWidgets(2));
    expect(find.byKey(const Key('question-zujuan-copy-0')), findsOneWidget);
    expect(find.byKey(const Key('question-zujuan-open-1')), findsOneWidget);
  });

  testWidgets('组卷网入口：候选最多只显示前 5 条', (WidgetTester tester) async {
    final database = _newDatabase();
    final question = await _seedQuestion(database);
    final candidates = List<ZujuanSearchCandidate>.generate(8, (index) {
      final keyword = '候选检索词$index';
      return ZujuanSearchCandidate(
          keyword: keyword, url: zujuanSearchUrl(keyword));
    });

    await _pumpDetail(
      tester,
      database,
      question.id,
      adapter: null,
      zujuanCandidates: candidates,
    );
    await _waitForText(tester, _stem);
    await tester.tap(find.byKey(questionZujuanSearchButtonKey));
    await tester.pumpAndSettle();

    for (var index = 0; index < questionZujuanVisibleCandidateLimit; index++) {
      expect(find.text('候选检索词$index'), findsOneWidget);
      expect(find.byKey(Key('question-zujuan-copy-$index')), findsOneWidget);
    }
    expect(find.text('候选检索词5'), findsNothing);
    expect(find.byKey(const Key('question-zujuan-copy-5')), findsNothing);
  });

  testWidgets('组卷网入口：复制检索词写进剪贴板并提示', (WidgetTester tester) async {
    final database = _newDatabase();
    final question = await _seedQuestion(database);
    const keyword = '细胞膜上的载体蛋白';
    final candidates = <ZujuanSearchCandidate>[
      ZujuanSearchCandidate(keyword: keyword, url: zujuanSearchUrl(keyword)),
    ];

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

    await _pumpDetail(
      tester,
      database,
      question.id,
      adapter: null,
      zujuanCandidates: candidates,
    );
    await _waitForText(tester, _stem);
    await tester.tap(find.byKey(questionZujuanSearchButtonKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('question-zujuan-copy-0')));
    await tester.pumpAndSettle();

    final copies = calls
        .where((call) => call.method == 'Clipboard.setData')
        .toList(growable: false);
    expect(copies, hasLength(1));
    expect((copies.single.arguments as Map<Object?, Object?>)['text'], keyword);
    expect(find.text(_zh.questionZujuanCopied(keyword)), findsOneWidget);
    expect(find.byKey(const Key('question-zujuan-copy-0')), findsNothing);
  });

  testWidgets('组卷网入口：打开搜索页复制链接并提示去浏览器粘贴', (WidgetTester tester) async {
    final database = _newDatabase();
    final question = await _seedQuestion(database);
    const keyword = '实验测得浓度梯度';
    final url = zujuanSearchUrl(keyword);
    final candidates = <ZujuanSearchCandidate>[
      ZujuanSearchCandidate(keyword: keyword, url: url),
    ];

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

    await _pumpDetail(
      tester,
      database,
      question.id,
      adapter: null,
      zujuanCandidates: candidates,
    );
    await _waitForText(tester, _stem);
    await tester.tap(find.byKey(questionZujuanSearchButtonKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('question-zujuan-open-0')));
    await tester.pumpAndSettle();

    final copies = calls
        .where((call) => call.method == 'Clipboard.setData')
        .toList(growable: false);
    expect(copies, hasLength(1));
    expect((copies.single.arguments as Map<Object?, Object?>)['text'], url);
    expect(find.text(_zh.questionZujuanUrlCopied), findsOneWidget);
  });

  testWidgets('题目来源：没有可信链接时整块不出现', (WidgetTester tester) async {
    final database = _newDatabase();
    final question = await _seedQuestion(database);

    await _pumpDetail(tester, database, question.id, adapter: null);
    await _waitForText(tester, _stem);

    expect(find.byKey(questionSourceCopyButtonKey), findsNothing);
    expect(find.text(_zh.questionSourceCopyLink), findsNothing);
  });

  testWidgets('题目来源：普通站 sourceUrl 显示 host，复制规范化链接',
      (WidgetTester tester) async {
    final database = _newDatabase();
    const rawUrl = 'https://Example.com:443/p/1?x=1#frag';
    final question = await _seedQuestion(database, sourceUrl: rawUrl);
    final expected = questionSourceFor(sourceUrl: rawUrl)!;

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

    await _pumpDetail(tester, database, question.id, adapter: null);
    await _waitForText(tester, _stem);

    expect(find.byKey(questionSourceCopyButtonKey), findsOneWidget);
    expect(find.text(expected.host), findsOneWidget);
    expect(find.text(_zh.questionSourceZujuan), findsNothing);

    await tester.tap(find.byKey(questionSourceCopyButtonKey));
    await tester.pump(const Duration(milliseconds: 300));

    final copies = calls
        .where((call) => call.method == 'Clipboard.setData')
        .toList(growable: false);
    expect(copies, hasLength(1));
    expect(
      (copies.single.arguments as Map<Object?, Object?>)['text'],
      expected.url,
    );
    expect(find.text(_zh.questionSourceCopyDone), findsOneWidget);
  });

  testWidgets('题目来源：只有组卷网 id 时重建详情页链接', (WidgetTester tester) async {
    final database = _newDatabase();
    final question = await _seedQuestion(
      database,
      zujuanQuestionId: '35583902',
      zujuanBankId: '10',
    );
    const expectedUrl = 'https://zujuan.xkw.com/10q35583902.html';

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

    await _pumpDetail(tester, database, question.id, adapter: null);
    await _waitForText(tester, _stem);

    expect(find.byKey(questionSourceCopyButtonKey), findsOneWidget);
    expect(find.text(_zh.questionSourceZujuan), findsOneWidget);

    await tester.tap(find.byKey(questionSourceCopyButtonKey));
    await tester.pump(const Duration(milliseconds: 300));

    final copies = calls
        .where((call) => call.method == 'Clipboard.setData')
        .toList(growable: false);
    expect(copies, hasLength(1));
    expect(
      (copies.single.arguments as Map<Object?, Object?>)['text'],
      expectedUrl,
    );
  });

  testWidgets('题目来源：组卷网 sourceUrl 显示「组卷网原题」而不是 host',
      (WidgetTester tester) async {
    final database = _newDatabase();
    final question = await _seedQuestion(
      database,
      sourceUrl: 'https://zujuan.xkw.com/10q35583902.html',
    );

    await _pumpDetail(tester, database, question.id, adapter: null);
    await _waitForText(tester, _stem);

    expect(find.byKey(questionSourceCopyButtonKey), findsOneWidget);
    expect(find.text(_zh.questionSourceZujuan), findsOneWidget);
    expect(find.text('zujuan.xkw.com'), findsNothing);
  });

  testWidgets('没有原题链接：详情页留「添加原题链接」入口，点开是空的编辑框', (WidgetTester tester) async {
    final database = _newDatabase();
    final question = await _seedQuestion(database);

    await _pumpDetail(tester, database, question.id, adapter: null);
    await _waitForText(tester, _stem);

    expect(find.byKey(questionSourceCopyButtonKey), findsNothing);
    expect(find.byKey(questionSourceEditButtonKey), findsOneWidget);
    expect(find.text(_zh.questionSourceAdd), findsOneWidget);

    await tester.tap(find.byKey(questionSourceEditButtonKey));
    await tester.pumpAndSettle();

    expect(find.byKey(questionSourceEditDialogKey), findsOneWidget);
    final field = tester.widget<TextField>(
      find.byKey(questionSourceEditInputKey),
    );
    expect(field.controller!.text, isEmpty);
  });

  testWidgets('有原题链接：来源行复制按钮旁有编辑入口，编辑框带出现有链接', (WidgetTester tester) async {
    final database = _newDatabase();
    const url = 'https://old.example.com/a';
    final question = await _seedQuestion(database, sourceUrl: url);

    await _pumpDetail(tester, database, question.id, adapter: null);
    await _waitForText(tester, _stem);

    expect(find.byKey(questionSourceCopyButtonKey), findsOneWidget);
    expect(find.byKey(questionSourceEditButtonKey), findsOneWidget);

    await tester.tap(find.byKey(questionSourceEditButtonKey));
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(
      find.byKey(questionSourceEditInputKey),
    );
    expect(field.controller!.text, url);
  });

  testWidgets('改完链接保存：详情页立刻换成新的来源行', (WidgetTester tester) async {
    final database = _newDatabase();
    final question = await _seedQuestion(database);

    await _pumpDetail(tester, database, question.id, adapter: null);
    await _waitForText(tester, _stem);

    await tester.tap(find.byKey(questionSourceEditButtonKey));
    await tester.pumpAndSettle();
    expect(find.byKey(questionSourceEditDialogKey), findsOneWidget);

    await tester.enterText(
      find.byKey(questionSourceEditInputKey),
      'https://zujuan.xkw.com/10q35583902.html',
    );
    await tester.pump();
    await tester.tap(find.byKey(questionSourceEditSaveKey));
    await _waitForText(tester, _zh.questionSourceZujuan);
    // 来源行在新数据回来时就重建了，对话框退场动画可能还没走完。
    await tester.pumpAndSettle();

    expect(find.byKey(questionSourceEditDialogKey), findsNothing);
    expect(find.byKey(questionSourceCopyButtonKey), findsOneWidget);
    final row = await QuestionRepository(database).byId(question.id);
    expect(row!.sourceUrl, 'https://zujuan.xkw.com/10q35583902.html');
    expect(row.zujuanQuestionId, '35583902');
    expect(row.zujuanBankId, '10');
  });

  testWidgets('详情页顶部显示题名与改名入口', (WidgetTester tester) async {
    final database = _newDatabase();
    final question = await _seedQuestion(database, title: '二次函数最值题型');

    await _pumpDetail(tester, database, question.id, adapter: null);
    await _waitForText(tester, '二次函数最值题型');

    expect(find.text('二次函数最值题型'), findsOneWidget);
    expect(find.byKey(questionTitleEditButtonKey), findsOneWidget);
    expect(find.text(_zh.questionTitleUntitled), findsNothing);
  });

  testWidgets('没题名时标题位置给弱化占位，而不是空白', (WidgetTester tester) async {
    final database = _newDatabase();
    final question = await _seedQuestion(database);

    await _pumpDetail(tester, database, question.id, adapter: null);
    await _waitForText(tester, _zh.questionTitleUntitled);

    expect(find.byKey(questionTitleEditButtonKey), findsOneWidget);
  });

  testWidgets('改题名保存：详情页立刻显示新名字，库里也写进去了', (WidgetTester tester) async {
    final database = _newDatabase();
    final question = await _seedQuestion(database, title: '旧名字');

    await _pumpDetail(tester, database, question.id, adapter: null);
    await _waitForText(tester, '旧名字');

    await tester.tap(find.byKey(questionTitleEditButtonKey));
    await tester.pumpAndSettle();
    expect(find.byKey(questionTitleFieldKey), findsOneWidget);

    await tester.enterText(find.byKey(questionTitleFieldKey), '新题名');
    await tester.tap(find.byKey(questionTitleSaveButtonKey));
    await _waitForText(tester, _zh.questionTitleSaved);
    await tester.pumpAndSettle();

    expect(find.byKey(questionTitleFieldKey), findsNothing);
    expect(find.text('新题名'), findsOneWidget);
    final row = await QuestionRepository(database).byId(question.id);
    expect(row!.title, '新题名');
  });

  testWidgets('相似题是整卡快照：显示可读摘录并带「整题截图」徽标', (WidgetTester tester) async {
    final database = _newDatabase();
    final focus = await _seedQuestion(database);
    final placeholders =
        List<String>.generate(12, (index) => '［图${index + 1}］').join();
    final stem = '已知函数 \$f(x)=x^2\$，求最小值。$placeholders';
    final snapshot = await _seedQuestion(database, stem: stem);
    await _addStemImage(database, questionId: snapshot.id);

    await _pumpDetail(
      tester,
      database,
      focus.id,
      adapter: null,
      overrides: <Override>[
        similarQuestionsProvider.overrideWith(
          (ref, questionId) => <SimilarQuestion>[
            SimilarQuestion(
              questionId: snapshot.id,
              score: 0.8,
              components: const <String, double>{'knowledge_point': 0.8},
              reasonZh: '共用知识点「二次函数」',
            ),
          ],
        ),
      ],
    );
    await _waitForText(tester, r'已知函数 $f(x)=x^2$，求最小值');

    expect(find.text(r'已知函数 $f(x)=x^2$，求最小值'), findsOneWidget);
    expect(find.text(_zh.questionBankSnapshotBadge), findsOneWidget);
    expect(find.textContaining('［图'), findsNothing);
  });

  testWidgets('相似题是整卡快照但没有正文摘录：显示整题截图标签，不摆徽标', (WidgetTester tester) async {
    final database = _newDatabase();
    final focus = await _seedQuestion(database);
    final stem =
        '，。${List<String>.generate(12, (index) => '［图${index + 1}］').join()}';
    final snapshot = await _seedQuestion(database, stem: stem);
    await _addStemImage(database, questionId: snapshot.id);

    await _pumpDetail(
      tester,
      database,
      focus.id,
      adapter: null,
      overrides: <Override>[
        similarQuestionsProvider.overrideWith(
          (ref, questionId) => <SimilarQuestion>[
            SimilarQuestion(
              questionId: snapshot.id,
              score: 0.7,
              components: const <String, double>{'knowledge_point': 0.7},
              reasonZh: '共用知识点「二次函数」',
            ),
          ],
        ),
      ],
    );
    await _waitForText(tester, '整题截图 · 12 处公式/图');

    expect(find.text('整题截图 · 12 处公式/图'), findsOneWidget);
    expect(find.text(_zh.questionBankSnapshotBadge), findsNothing);
  });

  testWidgets('相似题是普通题：显示原文，不摆整题截图徽标', (WidgetTester tester) async {
    final database = _newDatabase();
    final focus = await _seedQuestion(database);
    final similar = await _seedQuestion(database, stem: '普通相似题：求导。');

    await _pumpDetail(
      tester,
      database,
      focus.id,
      adapter: null,
      overrides: <Override>[
        similarQuestionsProvider.overrideWith(
          (ref, questionId) => <SimilarQuestion>[
            SimilarQuestion(
              questionId: similar.id,
              score: 0.5,
              components: const <String, double>{},
              reasonZh: '题面相近',
            ),
          ],
        ),
      ],
    );
    await _waitForText(tester, '普通相似题：求导。');

    expect(find.text('普通相似题：求导。'), findsOneWidget);
    expect(find.text(_zh.questionBankSnapshotBadge), findsNothing);
  });
}

/// 一个干净的内存库；每个用例自己关。
AppDatabase _newDatabase() {
  final database = AppDatabase.forTesting(NativeDatabase.memory());
  addTearDown(database.close);
  return database;
}

Future<Question> _seedQuestion(
  AppDatabase database, {
  String? sourceUrl,
  String? zujuanQuestionId,
  String? zujuanBankId,
  String stem = _stem,
  String? title,
}) async {
  final result = await QuestionRepository(database).ingest(
    QuestionDraft(
      stem: stem,
      answer: '5',
      solution: '韦达定理：两根之和等于 -b/a。',
      subjectKey: 'math',
      questionType: 'single_choice',
      sourceLevel: 'gaokao',
      year: 2024,
      region: '江苏',
      difficulty: 4,
      sourceUrl: sourceUrl,
      zujuanQuestionId: zujuanQuestionId,
      zujuanBankId: zujuanBankId,
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
  if (title != null) {
    await QuestionRepository(database).setQuestionTitle(
      result.question.id,
      title,
    );
  }
  return result.question;
}

/// 给某道题插一行「题干图」附件：列表/相似题的显示文本只读 attachments 计数，
/// 不读图片字节，所以不需要真的落盘一个文件。
Future<void> _addStemImage(
  AppDatabase database, {
  required String questionId,
  String fileName = 'page.png',
}) async {
  await database.into(database.attachments).insert(
        AttachmentsCompanion.insert(
          id: 'attachment-$questionId',
          ownerType: 'question',
          ownerId: questionId,
          relPath: 'media/$questionId/$fileName',
          mime: const Value('image/png'),
          sortOrder: const Value(0),
          role: const Value('stem'),
          createdAt: 1,
        ),
      );
}

/// 一份合规的模型回复：两步，都带同一个知识提示 [hint]。
///
/// 两步的风险刻意一个高（0.8）一个低（0.2），这样"整条链最高风险"和"这一步
/// 的风险"在断言里能分开看。第二步的动作 key 可以换成词表里没有的值，用来测
/// 「不假装认识这个动作」那条通路。
String _replyJson({
  String hint = 'kp-1',
  String secondActionType = 'sanity_check',
}) =>
    jsonEncode(<String, Object?>{
      'summary': _chainSummary,
      'steps': <Object?>[
        <String, Object?>{
          'index': 1,
          'goal': '确认方程的标准形式',
          'actionType': 'first_principles',
          'justification': '先把系数看清楚',
          'checkMethod': '检查 a、b、c 是否抄对',
          'stuckRisk': 0.8,
          'knowledgeHints': <String>[hint],
        },
        <String, Object?>{
          'index': 2,
          'goal': '用韦达定理求和',
          'actionType': secondActionType,
          'justification': '两根之和等于 -b/a',
          'checkMethod': '代回原方程检查',
          'stuckRisk': 0.2,
          'knowledgeHints': <String>[hint],
        },
      ],
    });

Future<void> _pumpDetail(
  WidgetTester tester,
  AppDatabase database,
  String questionId, {
  required ModelAdapter? adapter,
  FakeQuestionMediaStore? mediaStore,
  List<ZujuanSearchCandidate>? zujuanCandidates,
  List<Override> overrides = const <Override>[],
}) async {
  _bigSurface(tester);
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        appDatabaseProvider.overrideWithValue(database),
        modelAdapterProvider.overrideWithValue(adapter),
        questionMediaStoreProvider.overrideWithValue(
          mediaStore ?? FakeQuestionMediaStore(database: database),
        ),
        // 只替换「题干 → 候选」这一步，别的通路照真实 provider 走。
        if (zujuanCandidates != null)
          questionZujuanCandidatesProvider.overrideWith(
            (ref, stem) => zujuanCandidates,
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
  await _settle(tester);
}

Future<void> _pumpIntake(
  WidgetTester tester,
  AppDatabase database,
  Directory root,
) async {
  _bigSurface(tester);
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        appDatabaseProvider.overrideWithValue(database),
        handwritingIntakeStoreProvider.overrideWithValue(
          FakeIntakeStore(database: database, root: root),
        ),
        questionMediaStoreProvider
            .overrideWithValue(FakeQuestionMediaStore(database: database)),
      ],
      child: const MaterialApp(
        locale: Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: QuestionIntakePage(),
      ),
    ),
  );
}

/// 页面很长，默认 800×600 视口里 `ListView` 只建可见的那几行。
void _bigSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// 推进几帧直到没有转圈的进度条。
///
/// 不能用 `pumpAndSettle`：进度指示器是无限动画，会直接超时；而链上的风险条是
/// **定值**进度条，会一直在，所以循环到上限也要正常返回。
Future<void> _settle(WidgetTester tester, {int rounds = 40}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.pump(const Duration(milliseconds: 20));
    final spinning =
        find.byType(LinearProgressIndicator).evaluate().isNotEmpty ||
            find.byType(CircularProgressIndicator).evaluate().isNotEmpty;
    if (!spinning) {
      return;
    }
  }
}

/// 等一段文字出现（异步管道 + 数据库回写需要的帧数不确定，所以轮询）。
Future<void> _waitForText(
  WidgetTester tester,
  String text, {
  int rounds = 120,
}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (find.text(text).evaluate().isNotEmpty) {
      return;
    }
  }
  fail('等了 12 秒也没等到这段文字：$text');
}

Future<void> _waitForType(WidgetTester tester, Type type,
    {int rounds = 120}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (find.byType(type).evaluate().isNotEmpty) {
      return;
    }
  }
  fail('等了 12 秒也没等到这个控件：$type');
}

/// 等某个 finder 命中指定数量（图片字节异步读回来，widget 才会出现）。
Future<void> _waitForCount(
  WidgetTester tester,
  Finder finder,
  int count, {
  int rounds = 120,
}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().length == count) {
      return;
    }
  }
  fail('等了 12 秒也没等到 $count 个 $finder');
}

/// 24 字节的 PNG 文件头（签名 + IHDR + 宽高）：`readImageSize` 只读文件头，
/// 不需要真的像素数据；`Image.memory` 解码失败会走 errorBuilder 占位。
Uint8List _pngHeader({required int width, required int height}) {
  final builder = BytesBuilder();
  builder.add(<int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  builder.add(<int>[0, 0, 0, 13]);
  builder.add('IHDR'.codeUnits);
  for (final value in <int>[width, height]) {
    builder.add(<int>[
      (value >> 24) & 0xFF,
      (value >> 16) & 0xFF,
      (value >> 8) & 0xFF,
      value & 0xFF,
    ]);
  }
  return builder.toBytes();
}
