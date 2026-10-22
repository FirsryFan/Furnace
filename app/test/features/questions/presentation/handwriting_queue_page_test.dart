/// 拍照整理队列页的界面验收（`docs/QUESTION_BANK_DESIGN.md` §7.3–§7.4）。
///
/// 这一组测试盯着的是用户口径里最容易做错的三件事：
///
///  1. **确认前不写库**：整理（analyze）只出提案，标签/知识点/闪存卡要等用户点
///     确认才落库；已确认的条目显示"已确认"且按钮禁用，点第二次不会写第二份。
///  2. **失败如实**：整理失败时显示失败原因，并且**不显示旧提案**（旧提案会让人
///     以为这次成功了）；整批确认里一条失败不影响其它条，逐条结果照实渲染。
///  3. **领域层文案原样**：`rationaleZh` 与 `kind.labelZh` 直接显示，页面不重写；
///     `confidence` 折成三档，不显示成百分比。
///
/// 装置照抄 Lead 的 `application/handwriting_proposal_service_test.dart`：真内存库 +
/// `FakeIntakeStore`（同步落盘，见 `../support/picked_file_fakes.dart`）+ `FakeModelAdapter`。
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/anki_repository.dart';
import 'package:furnace/data/repositories/question_repository.dart';
import 'package:furnace/data/repositories/tag_repository.dart';
import 'package:furnace/domain/services/intake/handwriting_proposals.dart';
import 'package:furnace/domain/services/questions/question_number.dart';
import 'package:furnace/features/ai/domain/model_adapter.dart';
import 'package:furnace/features/ai/infrastructure/fake_model_adapter.dart';
import 'package:furnace/features/questions/application/handwriting_proposal_service.dart';
import 'package:furnace/features/questions/presentation/handwriting_queue_page.dart';
import 'package:furnace/features/questions/presentation/question_intake_page.dart';
import 'package:furnace/l10n/app_localizations.dart';

import '../support/picked_file_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppLocalizations zh;
  late AppDatabase db;
  late TagRepository tags;
  late AnkiRepository anki;
  late QuestionRepository questions;
  late Directory root;
  late FakeIntakeStore store;

  setUpAll(() async {
    zh = await AppLocalizations.delegate.load(const Locale('zh'));
  });

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    tags = TagRepository(db);
    anki = AnkiRepository(db);
    questions = QuestionRepository(db);
    root = Directory.systemTemp.createTempSync('furnace_hw_queue_');
    store = FakeIntakeStore(database: db, root: root);
  });

  tearDown(() async {
    await db.close();
    if (root.existsSync()) {
      root.deleteSync(recursive: true);
    }
  });

  HandwritingProposalService serviceWith(ModelAdapter? adapter) =>
      HandwritingProposalService(
        store: store,
        tags: tags,
        anki: anki,
        questions: questions,
        adapter: adapter,
      );

  /// 落一张假照片（真 `attachments` 行 + 同步落盘），返回相对路径。
  Future<String> seedPhoto([String name = 'page.png']) async {
    final image = await store.save(
      FakePickedFile(name, Uint8List.fromList(<int>[1, 2, 3, 4])),
    );
    return image.relPath;
  }

  /// 逐层建出一条标签路径（提案里的 `parent_path` 必须已经存在）。
  Future<void> seedParentPath(String path) async {
    Tag? parent;
    for (final segment in path.split('/')) {
      parent = parent == null
          ? await tags.createTag(name: segment)
          : await tags.createTag(name: segment, parentId: parent.id);
    }
  }

  String reply(List<String> proposals) =>
      '{"proposals": [${proposals.join(',')}]}';

  const tagProposal = '{"kind": "tag", "title": "动量守恒", '
      '"rationale": "照片里反复出现这个词", "confidence": 0.8, '
      '"fields": {"parent_path": "文化课/物理/力学"}}';

  const pointProposal = '{"kind": "knowledge_point", "title": "动量守恒的条件", '
      '"rationale": "照片第 3 段在讲这个点", "confidence": 0.6, '
      '"fields": {"content": "合外力为零", "tag_path": "文化课/物理/力学"}}';

  const cardProposal = '{"kind": "flashcard", "title": "动量守恒三件套", '
      '"rationale": "这一页值得做成背诵卡片", "confidence": 0.55, '
      '"fields": {"content": "正文"}, '
      '"cards": ['
      '{"question": "条件是什么？", "answer": "合外力为零。"},'
      '{"question": "公式？", "answer": "m1v1 + m2v2 = 常量", "type": "fill_blank"}'
      ']}';

  /// 循环 pump 到没有转圈为止；固定值进度条会一直在，所以有上限、不 fail。
  Future<void> settle(WidgetTester tester, {int rounds = 40}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.pump(const Duration(milliseconds: 20));
      if (i >= 2 &&
          find.byType(LinearProgressIndicator).evaluate().isEmpty &&
          find.byType(CircularProgressIndicator).evaluate().isEmpty) {
        return;
      }
    }
  }

  /// 轮询等到某段文字出现（不能 pumpAndSettle：页面里有无限动画的进度条）。
  Future<void> waitForText(
    WidgetTester tester,
    String text, {
    int rounds = 60,
  }) async {
    for (var i = 0; i < rounds; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.text(text).evaluate().isNotEmpty) {
        return;
      }
    }
    fail('等了 ${rounds * 50} 毫秒也没等到这段文字：$text');
  }

  Future<void> pumpQueue(
    WidgetTester tester, {
    ModelAdapter? adapter,
    String? initialRelPath,
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
          handwritingIntakeStoreProvider.overrideWithValue(store),
          handwritingProposalServiceProvider.overrideWithValue(
            serviceWith(adapter),
          ),
          ...overrides,
        ],
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: HandwritingQueuePage(initialRelPath: initialRelPath),
        ),
      ),
    );
    await settle(tester);
  }

  testWidgets('空队列：空态 + 去收题页的入口', (tester) async {
    await pumpQueue(tester);

    expect(find.text(zh.handwritingQueueEmpty), findsOneWidget);
    expect(find.text(zh.handwritingQueueGoIntake), findsOneWidget);
    expect(find.text(zh.handwritingQueueApplyAll), findsNothing);

    await tester.tap(find.text(zh.handwritingQueueGoIntake));
    await settle(tester);
    expect(find.byType(QuestionIntakePage), findsOneWidget);
  });

  testWidgets('整理中：显示进度，整理完才出提案', (tester) async {
    await seedPhoto();
    final adapter = _HangingAdapter();
    await pumpQueue(tester, adapter: adapter);

    expect(find.text(zh.handwritingQueueNotAnalyzed), findsOneWidget);

    await tester.tap(find.text(zh.handwritingQueueAnalyze));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(find.text(zh.handwritingQueueAnalyzing), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsWidgets);
    expect(find.text(zh.handwritingProposalApply), findsNothing);

    adapter.finish(reply(<String>[tagProposal]));
    await waitForText(tester, '动量守恒');
    expect(find.text(zh.handwritingQueueAnalyzing), findsNothing);
  });

  testWidgets('整理失败：如实显示原因，且不显示旧提案', (tester) async {
    await seedPhoto();
    final adapter = FakeModelAdapter(<List<ModelEvent>>[
      FakeModelAdapter.failure('网络断了'),
    ]);
    await pumpQueue(tester, adapter: adapter);

    await tester.tap(find.text(zh.handwritingQueueAnalyze));
    await waitForText(tester, zh.handwritingQueueFailureTitle);

    expect(find.textContaining('模型调用失败：网络断了'), findsOneWidget);
    expect(find.text(zh.handwritingProposalApply), findsNothing);
    // 失败不是"还没整理"：两种状态不能混着说。
    expect(find.text(zh.handwritingQueueNotAnalyzed), findsNothing);
  });

  testWidgets('三类提案都渲染：kind 中文名、rationale 原文、卡片张数与置信度档位', (tester) async {
    await seedPhoto();
    await seedParentPath('文化课/物理/力学');
    final adapter = FakeModelAdapter(<List<ModelEvent>>[
      FakeModelAdapter.answer(
        reply(<String>[tagProposal, pointProposal, cardProposal]),
      ),
    ]);
    await pumpQueue(tester, adapter: adapter);

    await tester.tap(find.text(zh.handwritingQueueAnalyze));
    await waitForText(tester, '动量守恒三件套');

    // 三类产物的名字来自领域层词表。
    expect(find.text('标签'), findsOneWidget);
    expect(find.text('知识点'), findsOneWidget);
    expect(find.text('闪存卡'), findsOneWidget);
    // rationaleZh 原样显示。
    expect(find.text('照片里反复出现这个词'), findsOneWidget);
    // 闪存卡额外给张数和每张卡的问题。
    expect(find.text(zh.handwritingProposalCardCount(2)), findsOneWidget);
    expect(find.textContaining('条件是什么？'), findsOneWidget);
    // 置信度折成档位：0.8 → 较确定；0.6 与 0.55 → 拿不准。
    expect(
      find.text(
        zh.handwritingProposalConfidence(zh.handwritingProposalConfidenceHigh),
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        zh.handwritingProposalConfidence(
          zh.handwritingProposalConfidenceMedium,
        ),
      ),
      findsNWidgets(2),
    );
  });

  testWidgets('逐条确认：变"已确认"、按钮禁用，再点不写第二份', (tester) async {
    await seedPhoto();
    await seedParentPath('文化课/物理/力学');
    final adapter = FakeModelAdapter(<List<ModelEvent>>[
      FakeModelAdapter.answer(reply(<String>[tagProposal])),
    ]);
    await pumpQueue(tester, adapter: adapter);

    await tester.tap(find.text(zh.handwritingQueueAnalyze));
    await waitForText(tester, zh.handwritingProposalApply);

    // 确认之前库里没有「动量守恒」这个叶子。
    expect(await tags.getTagByPath('文化课/物理/力学/动量守恒'), isNull);

    await tester.tap(find.text(zh.handwritingProposalApply));
    await waitForText(tester, zh.handwritingProposalApplied);

    expect(await tags.getTagByPath('文化课/物理/力学/动量守恒'), isNotNull);
    final confirmedButton = find.ancestor(
      of: find.text(zh.handwritingProposalApplied),
      matching: find.byWidgetPredicate((widget) => widget is FilledButton),
    );
    expect(confirmedButton, findsOneWidget);
    expect((tester.widget(confirmedButton) as FilledButton).onPressed, isNull);

    // 再点一次：按钮是禁用的，库里还是那 4 条（3 层父路径 + 1 个新叶子）。
    await tester.tap(confirmedButton, warnIfMissed: false);
    await settle(tester);
    expect(await tags.getAllTags(), hasLength(4));
  });

  testWidgets('整批确认：成功/失败逐条报出来，汇总给出成功与失败数', (tester) async {
    await seedPhoto();
    await seedParentPath('文化课/物理/力学');
    final adapter = FakeModelAdapter(<List<ModelEvent>>[
      FakeModelAdapter.answer(
        reply(<String>[
          tagProposal,
          '{"kind": "tag", "title": "量子纠缠", '
              '"fields": {"parent_path": "不存在的/路径"}}',
        ]),
      ),
    ]);
    await pumpQueue(tester, adapter: adapter);

    await tester.tap(find.text(zh.handwritingQueueAnalyze));
    await waitForText(tester, zh.handwritingQueueApplyAll);

    await tester.tap(find.text(zh.handwritingQueueApplyAll));
    await waitForText(tester, zh.handwritingQueueReportSummary(1, 1));

    // 成功的那条给出人话说明；失败的那条如实说标签树里没有父路径。
    // 预检区也会提到这两件事，所以这里用精确文案，不跟预检的提示混在一起。
    expect(find.text('新建标签「文化课/物理/力学/动量守恒」'), findsOneWidget);
    expect(
      find.text('标签树里没有 `不存在的/路径`，先建这一层（或改挂别处）再确认'),
      findsOneWidget,
    );
    // 失败的条目没有被记成"已确认"，还能再试。
    expect(find.text(zh.handwritingProposalApplied), findsOneWidget);
    expect(find.text(zh.handwritingProposalApply), findsOneWidget);
    expect(await tags.getAllTags(), hasLength(4));
  });

  testWidgets('丢弃整理结果：回到未整理态，提案不见', (tester) async {
    await seedPhoto();
    final adapter = FakeModelAdapter(<List<ModelEvent>>[
      FakeModelAdapter.answer(reply(<String>[tagProposal])),
    ]);
    await pumpQueue(tester, adapter: adapter);

    await tester.tap(find.text(zh.handwritingQueueAnalyze));
    await waitForText(tester, '动量守恒');

    await tester.tap(find.text(zh.handwritingQueueForget));
    await waitForText(tester, zh.handwritingQueueNotAnalyzed);

    expect(find.text(zh.handwritingProposalApply), findsNothing);
    expect(find.text('动量守恒'), findsNothing);
  });

  testWidgets('从收题页进来：选中的就是那张照片，也能切到别的', (tester) async {
    await seedPhoto('first.png');
    final second = await seedPhoto('second.png');
    await pumpQueue(tester, initialRelPath: second);

    ChoiceChip chipOf(String label) =>
        tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, label));

    expect(chipOf('second.png').selected, isTrue);
    expect(chipOf('first.png').selected, isFalse);
    // 清单里的 chip + 面板标题各一次。
    expect(find.text('second.png'), findsNWidgets(2));

    await tester.tap(find.widgetWithText(ChoiceChip, 'first.png'));
    await settle(tester);
    expect(chipOf('first.png').selected, isTrue);
    expect(chipOf('second.png').selected, isFalse);
  });

  // ── 题目提案：从照片到题库 ────────────────────────────────────────────────
  //
  // 题目是四类产物里唯一不能"确认即入库"的一种：确认只代表模型读对了，
  // 真要建题得带着草稿去收题页校对，用户按「入库」才写库。这组测试盯三件事：
  //  1. 卡片把模型读到的题干/选项/答案/解析原样显示（解析只做单行摘要）；
  //  2. 点「编辑后保存」把草稿预填进收题页表单（不写库）；
  //  3. 收题页入库成功后，题库有这道题、题号出现在提示里，拍照整理那条提案
  //     被标成已确认（只标记，不重复写库）。

  const stem = '质量 1 kg 的小球以 2 m/s 撞墙，以 1 m/s 反弹，求动量变化大小。';
  const answer = '3 kg·m/s（方向与原速度相反）';
  const solution = '取原方向为正：Δp = m(v2 - v1) = 1 × (-1 - 2) = -3，大小 3 kg·m/s。';
  const questionProposal = '{"kind": "question", "title": "动量变化题", '
      '"rationale": "照片里的第 2 题", "confidence": 0.7, '
      '"fields": {"stem": "$stem", "answer": "$answer", '
      '"solution": "$solution"}, '
      '"options": [{"label": "A", "content": "3 kg·m/s"}, '
      '{"label": "B", "content": "1 kg·m/s"}]}';

  FakeModelAdapter questionAdapter() => FakeModelAdapter(<List<ModelEvent>>[
        FakeModelAdapter.answer(reply(<String>[questionProposal])),
      ]);

  testWidgets('题目卡片：题干、选项、答案、解析摘要都显示', (tester) async {
    await seedPhoto();
    await seedParentPath('文化课/物理/力学');
    await pumpQueue(tester, adapter: questionAdapter());

    await tester.tap(find.text(zh.handwritingQueueAnalyze));
    await waitForText(tester, zh.handwritingQuestionEditForIntake);

    expect(find.text('题目'), findsOneWidget);
    final stemWidget = tester.widget<SelectableText>(
      find.byType(SelectableText),
    );
    expect(stemWidget.data, stem);
    expect(find.text(zh.handwritingQuestionOptions(2)), findsOneWidget);
    expect(find.text('A. 3 kg·m/s'), findsOneWidget);
    expect(find.text('B. 1 kg·m/s'), findsOneWidget);
    expect(find.text(zh.handwritingQuestionAnswer(answer)), findsOneWidget);
    expect(find.text(zh.handwritingQuestionSolution(solution)), findsOneWidget);
  });

  testWidgets('点「编辑后保存」：草稿预填到收题页，但还没写库', (tester) async {
    await seedPhoto();
    await seedParentPath('文化课/物理/力学');
    await pumpQueue(tester, adapter: questionAdapter());

    await tester.tap(find.text(zh.handwritingQueueAnalyze));
    await waitForText(tester, zh.handwritingQuestionEditForIntake);

    await tester.tap(find.text(zh.handwritingQuestionEditForIntake));
    await waitForText(tester, zh.questionIntakePasteSection);

    expect(find.byType(QuestionIntakePage), findsOneWidget);
    expect(find.widgetWithText(TextField, stem), findsOneWidget);
    expect(find.widgetWithText(TextField, answer), findsOneWidget);
    expect(find.widgetWithText(TextField, solution), findsOneWidget);
    expect(find.widgetWithText(TextField, '3 kg·m/s'), findsOneWidget);
    expect(find.widgetWithText(TextField, '1 kg·m/s'), findsOneWidget);
    expect(find.widgetWithText(TextField, '拍照整理'), findsOneWidget);
    // 预填只是表单内容：不按「入库」就什么都不写。
    expect(await db.select(db.questions).get(), isEmpty);
  });

  testWidgets('入库后：题库有这道题、题号进提示、拍照整理卡片变已确认', (tester) async {
    await seedPhoto();
    await seedParentPath('文化课/物理/力学');
    await pumpQueue(tester, adapter: questionAdapter());

    await tester.tap(find.text(zh.handwritingQueueAnalyze));
    await waitForText(tester, zh.handwritingQuestionEditForIntake);
    await tester.tap(find.text(zh.handwritingQuestionEditForIntake));
    await waitForText(tester, zh.questionIntakePasteSection);

    await tester.ensureVisible(find.text(zh.questionIntakeSubmit));
    await settle(tester);
    await tester.tap(find.text(zh.questionIntakeSubmit));
    await waitForText(
      tester,
      zh.handwritingQuestionSaved(formatQuestionSerial(1)),
    );

    final rows = await db.select(db.questions).get();
    expect(rows, hasLength(1));
    expect(rows.single.stem, stem);
    expect(rows.single.serialNo, 1);

    // 中文界面下 `tester.pageBack()` 找不到 tooltip「Back」，直接点 AppBar 的返回键。
    await tester.tap(find.byType(BackButton));
    await waitForText(tester, zh.handwritingProposalApplied);
    expect(find.text(zh.handwritingProposalApplied), findsOneWidget);
    // 已确认之后不能再从卡片进收题页（那是第二遍入库）。
    final editButton = tester.widget<TextButton>(
      find.widgetWithText(TextButton, zh.handwritingQuestionEditForIntake),
    );
    expect(editButton.onPressed, isNull);
  });

  testWidgets('题干为空：只提示重拍或手填，不给编辑入口', (tester) async {
    final relPath = await seedPhoto();
    final images = await store.pending();
    final seeded = HandwritingQueueState(
      images: images,
      sets: <String, HandwritingProposalSet>{
        relPath: HandwritingProposalSet(
          sourceRef: relPath,
          proposals: const <HandwritingProposal>[
            HandwritingProposal(
              id: 'question-empty',
              kind: HandwritingProposalKind.question,
              titleZh: '读不出题干',
              fields: <String, String>{'answer': '42'},
            ),
          ],
        ),
      },
    );
    await pumpQueue(
      tester,
      initialRelPath: relPath,
      overrides: <Override>[
        handwritingQueueProvider
            .overrideWith(() => _SeededQueueNotifier(seeded)),
      ],
    );

    expect(find.text('题目'), findsOneWidget);
    expect(find.text(zh.handwritingQuestionMissingStem), findsOneWidget);
    expect(find.text(zh.handwritingQuestionEditForIntake), findsNothing);
  });

  testWidgets('预检三种结论：ready 不提示、needsReview 高亮、blocked 禁止确认且整批不能全确认',
      (tester) async {
    final relPath = await seedPhoto();
    await seedParentPath('文化课/物理/力学');
    final images = await store.pending();
    final seeded = HandwritingQueueState(
      images: images,
      sets: <String, HandwritingProposalSet>{
        relPath: HandwritingProposalSet(
          sourceRef: relPath,
          proposals: const <HandwritingProposal>[
            HandwritingProposal(
              id: 'tag-ready',
              kind: HandwritingProposalKind.tag,
              titleZh: '动量守恒',
              fields: <String, String>{'parent_path': '文化课/物理/力学'},
            ),
            HandwritingProposal(
              id: 'point-review',
              kind: HandwritingProposalKind.knowledgePoint,
              titleZh: '动量守恒的条件',
              fields: <String, String>{'content': ''},
            ),
            HandwritingProposal(
              id: 'tag-blocked',
              kind: HandwritingProposalKind.tag,
              titleZh: '量子纠缠',
              fields: <String, String>{'parent_path': '不存在的/路径'},
            ),
          ],
        ),
      },
    );
    await pumpQueue(
      tester,
      initialRelPath: relPath,
      overrides: <Override>[
        handwritingQueueProvider
            .overrideWith(() => _SeededQueueNotifier(seeded)),
      ],
    );

    await waitForText(tester, '会新建标签「动量守恒」');
    // ready：只给目标路径，没有额外高亮提示。
    expect(find.text('目标路径：文化课/物理/力学/动量守恒'), findsOneWidget);
    // needsReview：结论 + 具体 warning。
    expect(find.text(zh.handwritingQueuePreviewNeedsReview), findsOneWidget);
    expect(find.textContaining('知识点正文为空'), findsOneWidget);
    // blocked：结论 + 具体 blocker + 整批总说明。
    expect(find.text(zh.handwritingQueuePreviewBlocked), findsOneWidget);
    expect(find.textContaining('标签树里没有'), findsOneWidget);
    expect(
      find.text(zh.handwritingQueuePreviewBlockedSummary(1, 1, 1)),
      findsOneWidget,
    );
    expect(
      find.byKey(handwritingProposalPreviewKey('tag-blocked')),
      findsOneWidget,
    );

    // 整批有 blocked → 全部确认禁用；单条 blocked 禁用，ready 仍可确认。
    final applyAll = tester.widget<FilledButton>(
      find.byKey(handwritingQueueApplyAllKey),
    );
    expect(applyAll.onPressed, isNull);
    final blockedApply = tester.widget<FilledButton>(
      find.byKey(handwritingProposalApplyKey('tag-blocked')),
    );
    expect(blockedApply.onPressed, isNull);
    final readyApply = tester.widget<FilledButton>(
      find.byKey(handwritingProposalApplyKey('tag-ready')),
    );
    expect(readyApply.onPressed, isNotNull);

    // 点不能确认的那条：什么都不写（标签只有父路径那 3 个）。
    await tester.tap(
      find.byKey(handwritingProposalApplyKey('tag-blocked')),
      warnIfMissed: false,
    );
    await settle(tester);
    expect(await tags.getAllTags(), hasLength(3));
    expect(await anki.getKnowledgePoints(), isEmpty);
  });

  testWidgets('没有不能确认的条目：全部确认可用并能一次写入', (tester) async {
    final relPath = await seedPhoto();
    await seedParentPath('文化课/物理/力学');
    final images = await store.pending();
    final seeded = HandwritingQueueState(
      images: images,
      sets: <String, HandwritingProposalSet>{
        relPath: HandwritingProposalSet(
          sourceRef: relPath,
          proposals: const <HandwritingProposal>[
            HandwritingProposal(
              id: 'tag-ready',
              kind: HandwritingProposalKind.tag,
              titleZh: '动量守恒',
              fields: <String, String>{'parent_path': '文化课/物理/力学'},
            ),
            HandwritingProposal(
              id: 'point-review',
              kind: HandwritingProposalKind.knowledgePoint,
              titleZh: '动量守恒的条件',
              fields: <String, String>{'content': ''},
            ),
          ],
        ),
      },
    );
    await pumpQueue(
      tester,
      initialRelPath: relPath,
      overrides: <Override>[
        handwritingQueueProvider
            .overrideWith(() => _SeededQueueNotifier(seeded)),
      ],
    );

    await waitForText(tester, '会新建标签「动量守恒」');
    expect(find.text(zh.handwritingQueuePreviewBlocked), findsNothing);
    expect(find.textContaining('条不能确认'), findsNothing);
    final applyAll = tester.widget<FilledButton>(
      find.byKey(handwritingQueueApplyAllKey),
    );
    expect(applyAll.onPressed, isNotNull);

    await tester.tap(find.byKey(handwritingQueueApplyAllKey));
    await waitForText(tester, zh.handwritingQueueReportSummary(2, 0));
    expect(await tags.getAllTags(), hasLength(4));
    expect(await anki.getKnowledgePoints(), hasLength(1));
  });

  testWidgets('切换照片后重算预检：上一张的结论不再显示', (tester) async {
    final first = await seedPhoto('first.png');
    final second = await seedPhoto('second.png');
    await seedParentPath('文化课/物理/力学');
    final images = await store.pending();
    final seeded = HandwritingQueueState(
      images: images,
      sets: <String, HandwritingProposalSet>{
        first: HandwritingProposalSet(
          sourceRef: first,
          proposals: const <HandwritingProposal>[
            HandwritingProposal(
              id: 'tag-first',
              kind: HandwritingProposalKind.tag,
              titleZh: '动量守恒',
              fields: <String, String>{'parent_path': '文化课/物理/力学'},
            ),
          ],
        ),
        second: HandwritingProposalSet(
          sourceRef: second,
          proposals: const <HandwritingProposal>[
            HandwritingProposal(
              id: 'tag-second',
              kind: HandwritingProposalKind.tag,
              titleZh: '机械能守恒',
              fields: <String, String>{'parent_path': '文化课/物理/力学'},
            ),
          ],
        ),
      },
    );
    await pumpQueue(
      tester,
      initialRelPath: first,
      overrides: <Override>[
        handwritingQueueProvider
            .overrideWith(() => _SeededQueueNotifier(seeded)),
      ],
    );

    await waitForText(tester, '会新建标签「动量守恒」');
    await tester.tap(find.widgetWithText(ChoiceChip, 'second.png'));
    await waitForText(tester, '会新建标签「机械能守恒」');
    expect(find.text('会新建标签「动量守恒」'), findsNothing);
  });

  testWidgets('整理全部：按钮显示待整理张数，跑完显示汇总并禁用', (tester) async {
    await seedPhoto('first.png');
    await seedPhoto('second.png');
    await seedParentPath('文化课/物理/力学');
    final adapter = FakeModelAdapter(<List<ModelEvent>>[
      FakeModelAdapter.answer(reply(<String>[tagProposal])),
      FakeModelAdapter.answer(reply(<String>[tagProposal])),
    ]);
    await pumpQueue(tester, adapter: adapter);

    expect(find.text('整理全部（2 张待整理）'), findsOneWidget);
    await tester.tap(find.byKey(handwritingBatchAnalyzeAllKey));
    await waitForText(tester, '成功 2 张、失败 0 张、跳过 0 张');

    expect(find.byKey(handwritingBatchSummaryKey), findsOneWidget);
    expect(find.text(zh.handwritingQueueBatchStopped), findsNothing);
    expect(adapter.requests, hasLength(2));
    final button = tester.widget<FilledButton>(
      find.byKey(handwritingBatchAnalyzeAllKey),
    );
    expect(button.onPressed, isNull);
    expect(find.text('整理全部（0 张待整理）'), findsOneWidget);
  });

  testWidgets('整理全部：运行中显示进度与停止，停止只停后面的照片', (tester) async {
    await seedPhoto('first.png');
    await seedPhoto('second.png');
    await seedParentPath('文化课/物理/力学');
    final adapter = _BatchSteppedAdapter();
    await pumpQueue(tester, adapter: adapter);

    await tester.tap(find.byKey(handwritingBatchAnalyzeAllKey));
    for (var attempt = 0; attempt < 100 && adapter.callCount < 1; attempt++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(adapter.callCount, 1);
    expect(find.text('正在整理 1/2'), findsOneWidget);
    expect(find.byKey(handwritingBatchStopKey), findsOneWidget);
    final running = tester.widget<FilledButton>(
      find.byKey(handwritingBatchAnalyzeAllKey),
    );
    expect(running.onPressed, isNull);

    await tester.tap(find.byKey(handwritingBatchStopKey));
    await tester.pump();
    expect(find.text(zh.handwritingQueueBatchStopping), findsOneWidget);

    adapter.finish(0, reply(<String>[tagProposal]));
    await waitForText(tester, '成功 1 张、失败 0 张、跳过 0 张');
    expect(find.text('已停止，剩下的照片没有整理'), findsOneWidget);
    expect(adapter.callCount, 1);
    expect(find.text('整理全部（1 张待整理）'), findsOneWidget);
  });
}

/// 一个"永远不回答"的适配器：用来把「整理中」那一帧定住（`FakeModelAdapter`
/// 的回合是立刻结束的，看不到进行中的状态）。
final class _HangingAdapter implements ModelAdapter {
  final StreamController<ModelEvent> _controller =
      StreamController<ModelEvent>();

  @override
  Stream<ModelEvent> runTurn({
    required List<ChatMessage> messages,
    required List<ModelToolSpec> tools,
  }) =>
      _controller.stream;

  void finish(String text) {
    _controller.add(ModelTextDelta(text));
    _controller.add(const ModelTurnDone(finishReason: 'stop'));
    _controller.close();
  }
}

/// 用固定队列状态起页面的替身：正常 `refresh()` 会把状态换成磁盘与库里的真实
/// 内容，而这条用例要的是一条"库里读不回来"的空题干提案（严格解析会拒绝空题干，
/// 所以只能直接构造）。
final class _SeededQueueNotifier extends HandwritingQueueNotifier {
  _SeededQueueNotifier(this.seeded);

  final HandwritingQueueState seeded;

  @override
  HandwritingQueueState build() => seeded;

  @override
  Future<void> refresh() async {}
}

/// 逐张返回的假模型：把「正在整理 i/N」这一帧定住，好在批次进行中按停止。
final class _BatchSteppedAdapter implements ModelAdapter {
  final List<StreamController<ModelEvent>> _controllers =
      <StreamController<ModelEvent>>[];

  int get callCount => _controllers.length;

  @override
  Stream<ModelEvent> runTurn({
    required List<ChatMessage> messages,
    required List<ModelToolSpec> tools,
  }) {
    final controller = StreamController<ModelEvent>();
    _controllers.add(controller);
    return controller.stream;
  }

  void finish(int index, String text) {
    final controller = _controllers[index];
    controller.add(ModelTextDelta(text));
    controller.add(const ModelTurnDone(finishReason: 'stop'));
    controller.close();
  }
}
