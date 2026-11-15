import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/anki_repository.dart';
import 'package:furnace/data/repositories/content_ref_repository.dart';
import 'package:furnace/domain/services/content/dag_flashcard_generator.dart';
import 'package:furnace/domain/services/content/content_ref_vocab.dart';

/// `DagFlashcardGenerator`（task-79，2026-11-15）：DAG 节点 / 错因 → 闪存卡。
///
/// 要锁的行为（每条都能单独失败）：
///
///  * dry run 是默认：不传参只返回计划（wouldCreate 预览），库里 0 行；
///  * apply 才写 `card_templates`：公式卡 `fill_blank`，判断/决策/结论/错因卡
///    `essay`；`external_id = content:<content-id>#<seed-id>`；
///  * 五类卡（formula/check/decision/conclusion/error_cause）各自的卡面规则：
///    公式卡答案 = formulas，判断/决策/结论答案 = result（body 只截断作依据），
///    错因卡 answer = 根因+改法、hint = 诊断问题；
///  * 跳过：纯爆算、审题、非自测节点、变式/失败支类节点、空内容、无 result/
///    无公式、缺 KP（missing/unknown）、错因不完整；
///  * 阻断：非法 content_id / 非法种子 id / 同批重复种子；
///  * 幂等：同 `external_id` 第二次 apply 为 already_exists，不新增模板/引用；
///  * **不复制 FSRS**：生成器不建 `card_states`/`review_logs`，也不动既有卡状态；
///  * 回溯：`content_refs(object_type=card_template, role=card_seed)` 带节点/错因
///    摘要，`metadata_json` 里没有题干/答案正文。
void main() {
  late AppDatabase db;
  late AnkiRepository anki;
  late ContentRefRepository contentRefs;
  late DagFlashcardGenerator generator;
  late String kpId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    anki = AnkiRepository(db);
    contentRefs = ContentRefRepository(db);
    generator = DagFlashcardGenerator(
      db,
      ankiRepository: anki,
      contentRefs: contentRefs,
    );
    kpId = (await anki.createKnowledgePoint(
      title: '平抛运动与运动的分解',
      content: '平抛运动的水平/竖直分运动与不变量。',
    ))
        .id;
  });

  tearDown(() async {
    await db.close();
  });

  // ---------------------------------------------------------------------------
  // fixtures
  // ---------------------------------------------------------------------------

  DagFlashcardNode node({
    required String id,
    required String kind,
    String role = '',
    String label = '',
    String body = '',
    List<String> formulas = const <String>[],
    List<String> keyQuantities = const <String>[],
    String result = '',
  }) =>
      DagFlashcardNode(
        id: id,
        kind: kind,
        role: role,
        label: label,
        body: body,
        formulas: formulas,
        keyQuantities: keyQuantities,
        result: result,
      );

  DagFlashcardNode formulaNode({String id = 'N-Q1-02'}) => node(
        id: id,
        kind: 'formula_or_model',
        role: 'construct',
        label: '建模：平抛 = 水平匀速 + 竖直自由落体',
        body: '平抛就是「初速度水平、只受重力」。水平方向不受力，vx=v0 全程不变；'
            '竖直方向只受重力、初速度为 0，vy=gt 线性增大。',
        formulas: const <String>['v_x=v_0', 'v_y=gt'],
        keyQuantities: const <String>['vx=v0：水平分速度（不变）'],
        result: 'vx=v0、vy=gt、a=g',
      );

  DagFlashcardNode checkNode({String id = 'N-Q1-03'}) => node(
        id: id,
        kind: 'check',
        role: 'judge',
        label: '判 B：合力恒为重力 ⇒ a=g 不变（B 成立）',
        body: '只受重力，合力 F=mg 是恒矢量；由牛顿第二定律 a=F/m=g，'
            '大小和方向都不随时间改变，所以「加速度保持不变」成立。',
        formulas: const <String>['\\vec a=\\vec g=\\text{const}'],
        keyQuantities: const <String>['a=g：恒矢量'],
        result: 'B 真',
      );

  DagFlashcardNode decisionNode({String id = 'N-Q1-07'}) => node(
        id: id,
        kind: 'decision',
        role: 'judge',
        label: '决策：选平抛模型直接判四项，还是转能量法硬算',
        body: '四个选项都是定性判断，平抛模型一写出就能逐项代入；能量法要额外列式，'
            '对这道题没有信息增量。',
        result: '选平抛模型（逐项代入判定）',
      );

  DagFlashcardNode conclusionNode({String id = 'N-Q1-06'}) => node(
        id: id,
        kind: 'conclusion',
        role: 'conclude',
        label: '收口：唯一成立项是 B',
        body: 'A 假、B 真、C 假、D 假，只有 B 与平抛模型相容。',
        formulas: const <String>['A\\ \\text{假}\\Rightarrow B'],
        result: '答案 B',
      );

  DagFlashcardErrorCause errorCause({
    String code = 'EC-Q1-01',
    String category = 'knowledge_gap',
    String symptom = '混淆「水平分速度不变」与「速度大小不变」，错选 C。',
    String rootCause = '平抛速度分解只记住「水平匀速」，没有把合速度矢量式写出来。',
    String diagnosticQuestion = '速度是矢量还是标量？水平分速度不变是否意味着合速度不变？',
    String remediation = '写 v(t) 并在 t=0、t=1 s 比较合速度大小与方向。',
    String? locateNode = 'N-Q1-02',
  }) =>
      DagFlashcardErrorCause(
        code: code,
        category: category,
        symptom: symptom,
        rootCause: rootCause,
        diagnosticQuestion: diagnosticQuestion,
        remediation: remediation,
        locateNode: locateNode,
      );

  DagFlashcardInput inputOf({
    String contentId = 'Q-PH0001',
    String questionTitle = '平抛运动的不变量与变化量',
    String? knowledgePointId,
    List<DagFlashcardNode> nodes = const <DagFlashcardNode>[],
    List<DagFlashcardErrorCause> errorCauses = const <DagFlashcardErrorCause>[],
  }) =>
      DagFlashcardInput(
        contentId: contentId,
        questionTitle: questionTitle,
        knowledgePointId: knowledgePointId,
        nodes: nodes,
        errorCauses: errorCauses,
      );

  Future<List<CardTemplate>> templates() => db.select(db.cardTemplates).get();

  Future<List<CardState>> states() => db.select(db.cardStates).get();

  Future<List<ReviewLog>> reviewLogs() => db.select(db.reviewLogs).get();

  Future<List<ContentRefRow>> refs() => db.select(db.contentRefs).get();

  group('dry run 默认：只计划不写库', () {
    test('不传 dryRun 时 dryRun=true、wouldCreate 有内容、库里 0 行', () async {
      final plan = await generator.generate(
        inputOf(
            knowledgePointId: kpId, nodes: <DagFlashcardNode>[formulaNode()]),
      );

      expect(plan.dryRun, isTrue);
      expect(plan.wouldCreate, 1);
      expect(plan.created, 0);
      expect(plan.skipped, 0);
      expect(plan.blocked, 0);
      expect(plan.items.single.status, DagCardStatus.wouldCreate);
      expect(plan.items.single.question, contains('______'));
      expect(plan.items.single.answer, 'v_x=v_0；v_y=gt');

      expect(await templates(), isEmpty);
      expect(await refs(), isEmpty);
      expect(await states(), isEmpty);
    });

    test('计划 JSON 带 wouldCreate/skipped/blocked 与逐项原因', () async {
      final plan = await generator.generate(
        inputOf(
          knowledgePointId: kpId,
          nodes: <DagFlashcardNode>[
            formulaNode(),
            node(id: 'N-Q1-05', kind: 'computation', role: 'compute'),
          ],
        ),
      );
      final json = plan.toJson();

      expect(json['dry_run'], isTrue);
      expect(json['would_create'], 1);
      expect(json['created'], 0);
      expect(json['skipped'], 1);
      expect(json['blocked'], 0);
      expect(
        json['skipped_reasons'],
        <String, int>{DagCardSkipReason.pureComputation: 1},
      );
      expect(
        json['cards_by_kind'],
        <String, int>{'formula': 1},
      );
    });
  });

  group('apply：五类卡与卡面规则', () {
    test('公式卡：fill_blank，答案 = formulas，external_id 可回溯', () async {
      final plan = await generator.generate(
        inputOf(
            knowledgePointId: kpId, nodes: <DagFlashcardNode>[formulaNode()]),
        dryRun: false,
      );

      expect(plan.created, 1);
      final created = plan.items.single;
      expect(created.status, DagCardStatus.created);
      expect(created.kind, DagCardKind.formula);
      expect(created.cardType, 'fill_blank');
      expect(created.externalId, 'content:Q-PH0001#N-Q1-02');
      expect(
        DagFlashcardGenerator.externalIdOf('Q-PH0001', 'N-Q1-02'),
        'content:Q-PH0001#N-Q1-02',
      );

      final row = (await templates()).single;
      expect(row.id, created.templateId);
      expect(row.type, 'fill_blank');
      expect(row.knowledgePointId, kpId);
      expect(row.externalId, 'content:Q-PH0001#N-Q1-02');
      expect(row.question, contains('______'));
      expect(row.clozeTemplate, row.question);
      expect(row.answer, 'v_x=v_0；v_y=gt');
      expect(row.options, isNull);
      expect(row.hint, startsWith('【AI】'));
      expect(row.hint, contains('关键量：vx=v0：水平分速度（不变）'));
    });

    test('五类卡各生成一张，类型映射与卡面内容正确', () async {
      final plan = await generator.generate(
        inputOf(
          knowledgePointId: kpId,
          nodes: <DagFlashcardNode>[
            formulaNode(),
            checkNode(),
            decisionNode(),
            conclusionNode(),
          ],
          errorCauses: <DagFlashcardErrorCause>[errorCause()],
        ),
        dryRun: false,
      );

      expect(plan.created, 5);
      expect(plan.skipped, 0);
      expect(plan.blocked, 0);
      expect(
        plan.cardsByKind,
        <DagCardKind, int>{
          DagCardKind.formula: 1,
          DagCardKind.check: 1,
          DagCardKind.decision: 1,
          DagCardKind.conclusion: 1,
          DagCardKind.errorCause: 1,
        },
      );

      final bySeed = <String, DagFlashcardPlanItem>{
        for (final item in plan.items) item.seedId: item,
      };
      expect(bySeed['N-Q1-02']!.cardType, 'fill_blank');
      expect(bySeed['N-Q1-03']!.cardType, 'essay');
      expect(bySeed['N-Q1-07']!.cardType, 'essay');
      expect(bySeed['N-Q1-06']!.cardType, 'essay');
      expect(bySeed['EC-Q1-01']!.cardType, 'essay');

      // 判断卡：label 末尾的判定括号被去掉（否则题面自带答案），答案从 result 起。
      final checkQuestion = bySeed['N-Q1-03']!.question!;
      expect(checkQuestion, contains('判 B：合力恒为重力'));
      expect(checkQuestion, isNot(contains('（B 成立）')));
      expect(bySeed['N-Q1-03']!.answer, startsWith('B 真'));
      expect(bySeed['N-Q1-03']!.answer, contains('依据：'));

      // 决策卡：答案 = result + 依据。
      expect(bySeed['N-Q1-07']!.answer, startsWith('选平抛模型'));

      // 结论卡：题干不复制节点 label（label 往往就是答案本身），用题目短标题补上下文。
      expect(bySeed['N-Q1-06']!.question, contains('《平抛运动的不变量与变化量》'));
      expect(bySeed['N-Q1-06']!.question, isNot(contains('唯一成立项')));
      expect(bySeed['N-Q1-06']!.answer, '答案 B');

      // 错因卡：题干 = symptom，答案 = 根因 + 改法，提示 = 诊断问题 + 对应步骤。
      expect(bySeed['EC-Q1-01']!.question, contains('易错点：'));
      expect(bySeed['EC-Q1-01']!.question, contains('错选 C'));
      expect(bySeed['EC-Q1-01']!.answer, contains('根因：'));
      expect(bySeed['EC-Q1-01']!.answer, contains('改法：'));
      expect(bySeed['EC-Q1-01']!.hint, contains('先自问：'));
      expect(bySeed['EC-Q1-01']!.hint, contains('对应步骤：建模：平抛'));

      // 所有卡的 hint 都带【AI】标记（契约 §6.2：未经人工审核的生成卡）。
      for (final row in await templates()) {
        expect(row.hint, startsWith('【AI】'),
            reason: '${row.externalId} 缺 AI 标记');
      }
      expect(await templates(), hasLength(5));
    });

    test('节点 body 不整段进 answer：摘要 120 字并截断', () async {
      final longBody = '推导过程。' * 100; // 500 字
      final plan = await generator.generate(
        inputOf(
          knowledgePointId: kpId,
          nodes: <DagFlashcardNode>[
            node(
              id: 'N-Q1-04',
              kind: 'check',
              role: 'exclude',
              label: '判 A：只有重力做功 ⇒ 机械能守恒（A 假）',
              body: longBody,
              result: 'A 假：机械能守恒',
            ),
          ],
        ),
        dryRun: false,
      );

      expect(plan.created, 1);
      final answer = plan.items.single.answer!;
      expect(answer, contains('依据：'));
      expect(answer, contains('…'));
      expect(answer.length, lessThan(longBody.length));
    });
  });

  group('跳过：不生成不可成卡的内容', () {
    test('纯爆算节点：pure_computation，不写库', () async {
      final plan = await generator.generate(
        inputOf(
          knowledgePointId: kpId,
          nodes: <DagFlashcardNode>[
            node(
              id: 'N-Q1-05',
              kind: 'computation',
              role: 'compute',
              label: '算 C、D',
              body: '把 t 代入求值。',
              result: 'C 假、D 假',
            ),
          ],
        ),
        dryRun: false,
      );

      expect(plan.skipped, 1);
      expect(plan.items.single.reason, DagCardSkipReason.pureComputation);
      expect(await templates(), isEmpty);
    });

    test('审题 role 与非自测节点类型：read_question_role / not_cardable_kind', () async {
      final plan = await generator.generate(
        inputOf(
          knowledgePointId: kpId,
          nodes: <DagFlashcardNode>[
            node(
              id: 'N-Q1-01',
              kind: 'conclusion',
              role: 'read_question',
              label: '审题',
              result: '待判 A/B/C/D',
            ),
            node(id: 'N-Q1-08', kind: 'condition', label: '题干条件'),
            node(id: 'N-Q1-09', kind: 'branch_try', label: '尝试另一条路'),
            node(id: 'N-Q1-10', kind: 'dead_end', label: '此路不通'),
            node(id: 'N-Q1-11', kind: 'insight', label: '一点洞察'),
          ],
        ),
        dryRun: false,
      );

      expect(plan.skipped, 5);
      expect(plan.items[0].reason, DagCardSkipReason.readQuestionRole);
      for (final item in plan.items.skip(1)) {
        expect(item.reason, DagCardSkipReason.notCardableKind);
      }
      expect(await templates(), isEmpty);
    });

    test('内容空 / 无公式 / 无 result：各自的原因，不硬生成', () async {
      final plan = await generator.generate(
        inputOf(
          knowledgePointId: kpId,
          nodes: <DagFlashcardNode>[
            node(id: 'N-E1', kind: 'formula_or_model'), // 全空
            node(
              id: 'N-E2',
              kind: 'formula_or_model',
              label: '只有模型没有公式',
              body: '模型描述',
            ),
            node(id: 'N-E3', kind: 'check', label: '判 B', body: '依据'),
            node(id: 'N-E4', kind: 'decision'),
            node(
              id: 'N-E5',
              kind: 'check',
              label: '',
              body: '',
              result: 'B 真',
            ),
          ],
        ),
        dryRun: false,
      );

      expect(plan.skipped, 5);
      expect(plan.items[0].reason, DagCardSkipReason.noFormula);
      expect(plan.items[1].reason, DagCardSkipReason.noFormula);
      expect(plan.items[2].reason, DagCardSkipReason.noResult);
      expect(plan.items[3].reason, DagCardSkipReason.noResult);
      expect(plan.items[4].reason, DagCardSkipReason.noCardableContent);
      expect(await templates(), isEmpty);
    });

    test('错因不完整：缺 symptom 或缺根因+改法 → error_cause_incomplete', () async {
      final plan = await generator.generate(
        inputOf(
          knowledgePointId: kpId,
          errorCauses: <DagFlashcardErrorCause>[
            errorCause(code: 'EC-E1', symptom: ''),
            errorCause(code: 'EC-E2', rootCause: '', remediation: ''),
          ],
        ),
        dryRun: false,
      );

      expect(plan.skipped, 2);
      for (final item in plan.items) {
        expect(item.reason, DagCardSkipReason.errorCauseIncomplete);
      }
      expect(await templates(), isEmpty);
    });
  });

  group('知识点：缺 KP / KP 不存在都跳过（不伪造）', () {
    test('没给 knowledgePointId：missing_knowledge_point', () async {
      final plan = await generator.generate(
        inputOf(nodes: <DagFlashcardNode>[formulaNode()]),
        dryRun: false,
      );

      expect(plan.skipped, 1);
      expect(plan.items.single.reason, DagCardSkipReason.missingKnowledgePoint);
      expect(await templates(), isEmpty);
    });

    test('给空白 KP 字符串也按缺 KP 处理', () async {
      final plan = await generator.generate(
        inputOf(
            knowledgePointId: '  ', nodes: <DagFlashcardNode>[formulaNode()]),
        dryRun: false,
      );

      expect(plan.items.single.reason, DagCardSkipReason.missingKnowledgePoint);
      expect(await templates(), isEmpty);
    });

    test('KP 在库里不存在：unknown_knowledge_point，不建悬空外键', () async {
      final plan = await generator.generate(
        inputOf(
          knowledgePointId: 'kp-does-not-exist',
          nodes: <DagFlashcardNode>[formulaNode()],
        ),
        dryRun: false,
      );

      expect(plan.skipped, 1);
      expect(plan.items.single.reason, DagCardSkipReason.unknownKnowledgePoint);
      expect(await templates(), isEmpty);
    });
  });

  group('阻断：非法输入不写库', () {
    test('非法 content_id（空 / 含空格 / 含 #）：blocked invalid_content_id', () async {
      for (final contentId in <String>['  ', 'Q PH1', 'Q#PH1']) {
        final plan = await generator.generate(
          inputOf(
            contentId: contentId,
            knowledgePointId: kpId,
            nodes: <DagFlashcardNode>[formulaNode()],
          ),
          dryRun: false,
        );
        expect(plan.blocked, 1, reason: contentId);
        expect(plan.items.single.reason, DagCardBlockReason.invalidContentId);
      }
      expect(await templates(), isEmpty);
    });

    test('非法种子 id（节点 id 含 # / 错因 code 为空）：blocked invalid_seed_id', () async {
      final plan = await generator.generate(
        inputOf(
          knowledgePointId: kpId,
          nodes: <DagFlashcardNode>[formulaNode(id: 'N#1')],
          errorCauses: <DagFlashcardErrorCause>[errorCause(code: '')],
        ),
        dryRun: false,
      );

      expect(plan.blocked, 2);
      for (final item in plan.items) {
        expect(item.reason, DagCardBlockReason.invalidSeedId);
      }
      expect(await templates(), isEmpty);
    });

    test('同批两个种子算出同一 external_id：第二个 blocked duplicate_seed_id', () async {
      final plan = await generator.generate(
        inputOf(
          knowledgePointId: kpId,
          nodes: <DagFlashcardNode>[formulaNode(), formulaNode()],
        ),
        dryRun: false,
      );

      expect(plan.created, 1);
      expect(plan.blocked, 1);
      expect(plan.items[0].status, DagCardStatus.created);
      expect(plan.items[1].reason, DagCardBlockReason.duplicateSeedId);
      expect(await templates(), hasLength(1));
    });
  });

  group('幂等：同 external_id 不重复建卡', () {
    test('apply 两次：第二次全部 already_exists，模板与引用都不新增', () async {
      final input = inputOf(
        knowledgePointId: kpId,
        nodes: <DagFlashcardNode>[formulaNode()],
        errorCauses: <DagFlashcardErrorCause>[errorCause()],
      );
      final first = await generator.generate(input, dryRun: false);
      expect(first.created, 2);
      final refsAfterFirst = await refs();
      expect(refsAfterFirst, hasLength(2));

      final second = await generator.generate(input, dryRun: false);

      expect(second.created, 0);
      expect(second.skipped, 2);
      for (final item in second.items) {
        expect(item.reason, DagCardSkipReason.alreadyExists);
        expect(item.templateId, isNotNull);
      }
      expect(await templates(), hasLength(2));
      expect(await refs(), hasLength(2));
      expect(await states(), isEmpty);
    });

    test('apply 之后 dry run 也报 already_exists（wouldCreate=0）', () async {
      final input = inputOf(
        knowledgePointId: kpId,
        nodes: <DagFlashcardNode>[formulaNode()],
      );
      await generator.generate(input, dryRun: false);

      final plan = await generator.generate(input);

      expect(plan.wouldCreate, 0);
      expect(plan.skipped, 1);
      expect(plan.items.single.reason, DagCardSkipReason.alreadyExists);
    });

    test('按 external_id 可查回模板（仓库查询）', () async {
      await generator.generate(
        inputOf(
            knowledgePointId: kpId, nodes: <DagFlashcardNode>[formulaNode()]),
        dryRun: false,
      );

      final found =
          await anki.getTemplatesByExternalId('content:Q-PH0001#N-Q1-02');
      expect(found, hasLength(1));
      expect(found.single.externalId, 'content:Q-PH0001#N-Q1-02');
    });
  });

  group('不复制 FSRS：生成器只写模板与引用', () {
    test('apply 不创建任何 CardState / ReviewLog', () async {
      await generator.generate(
        inputOf(
          knowledgePointId: kpId,
          nodes: <DagFlashcardNode>[formulaNode(), checkNode()],
          errorCauses: <DagFlashcardErrorCause>[errorCause()],
        ),
        dryRun: false,
      );

      expect(await templates(), hasLength(3));
      expect(await states(), isEmpty);
      expect(await reviewLogs(), isEmpty);
    });

    test('既有卡的 FSRS 状态与复习记录原样保留，不被复制/覆盖', () async {
      // 先有一张与本次生成无关的卡，并把它推进到 FSRS review 状态。
      final existingTemplate = await anki.createTemplate(
        knowledgePointId: kpId,
        type: 'essay',
        question: '既有卡：机械能守恒条件是什么？',
        answer: '只有重力/弹力做功。',
        externalId: 'content:Q-OTHER#N-9',
      );
      final existingState =
          await anki.getOrCreateCardState(existingTemplate.id);
      await anki.updateUnitCardState(
        existingState.id,
        dueAt: 1700000009999,
        state: 'review',
        stability: 5.5,
        difficulty: 4.25,
        intervalDays: 7.5,
        repetitions: 3,
        lapses: 1,
        forced: 1,
        forcedStreak: 1,
        lastReviewedAt: 1690000000000,
      );
      await anki.addReviewLog(
        cardStateId: existingState.id,
        cardTemplateId: existingTemplate.id,
        rating: 2,
        reviewedAt: 1690000000000,
        correct: 1,
      );
      final before = (await anki.cardStateById(existingState.id))!;

      final plan = await generator.generate(
        inputOf(
          knowledgePointId: kpId,
          nodes: <DagFlashcardNode>[formulaNode(), conclusionNode()],
        ),
        dryRun: false,
      );
      expect(plan.created, 2);

      final after = (await anki.cardStateById(existingState.id))!;
      expect(after.stability, before.stability);
      expect(after.difficulty, before.difficulty);
      expect(after.intervalDays, before.intervalDays);
      expect(after.repetitions, before.repetitions);
      expect(after.lapses, before.lapses);
      expect(after.forced, before.forced);
      expect(after.forcedStreak, before.forcedStreak);
      expect(after.dueAt, before.dueAt);
      expect(after.state, before.state);
      expect(after.lastReviewedAt, before.lastReviewedAt);
      expect(after.updatedAt, before.updatedAt, reason: '生成不该改 FSRS 状态');

      // 生成的两张新卡没有状态行：卡状态是复习事件产生的，不是生成器产生的。
      expect(await states(), hasLength(1));
      expect(await reviewLogs(), hasLength(1));
      expect(await templates(), hasLength(3));
    });
  });

  group('回溯：content_refs(card_seed) 只存引用摘要', () {
    test('每张新卡一条 card_template/card_seed 引用，metadata 带节点摘要且无正文', () async {
      final plan = await generator.generate(
        inputOf(
          knowledgePointId: kpId,
          nodes: <DagFlashcardNode>[formulaNode()],
          errorCauses: <DagFlashcardErrorCause>[errorCause()],
        ),
        dryRun: false,
      );
      final templateId = plan.items
          .firstWhere((i) => i.kind == DagCardKind.formula)
          .templateId;

      final byContent = await contentRefs.listByContentId('Q-PH0001');
      expect(byContent, hasLength(2));
      final formulaRef = byContent.firstWhere(
        (ref) => ref.objectId == templateId,
      );
      expect(formulaRef.objectType, ContentObjectType.cardTemplate);
      expect(formulaRef.role, ContentRefRole.cardSeed);
      expect(formulaRef.contentVersion, isNull);
      expect(formulaRef.contentHash, isNull);

      final metadata =
          jsonDecode(formulaRef.metadataJson!) as Map<String, Object?>;
      expect(metadata['seed_id'], 'N-Q1-02');
      expect(metadata['card_kind'], 'formula');
      expect(metadata['card_type'], 'fill_blank');
      expect(metadata['source_mode'], 'ai_derived');
      expect(metadata['node_kind'], 'formula_or_model');
      expect(metadata['node_role'], 'construct');
      expect(metadata['external_id'], 'content:Q-PH0001#N-Q1-02');

      // 契约 §2.4：引用摘要不是正文副本——不得出现题干/答案/解析字段。
      for (final forbidden in <String>[
        'question',
        'answer',
        'body',
        'solution',
        'stem',
      ]) {
        expect(metadata.containsKey(forbidden), isFalse, reason: forbidden);
      }
    });

    test('错因引用带 error_category / locate_node，答案正文不进引用', () async {
      final plan = await generator.generate(
        inputOf(
          knowledgePointId: kpId,
          errorCauses: <DagFlashcardErrorCause>[errorCause()],
        ),
        dryRun: false,
      );
      final templateId = plan.items.single.templateId;
      final ref = (await refs()).single;
      expect(ref.objectId, templateId);
      final metadata = jsonDecode(ref.metadataJson!) as Map<String, Object?>;
      expect(metadata['card_kind'], 'error_cause');
      expect(metadata['error_category'], 'knowledge_gap');
      expect(metadata['locate_node'], 'N-Q1-02');
      expect(metadata['external_id'], 'content:Q-PH0001#EC-Q1-01');
    });
  });
}
