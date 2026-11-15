import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/anki_repository.dart';
import 'package:furnace/data/repositories/content_ref_repository.dart';
import 'package:furnace/domain/services/content/dag_flashcard_generator.dart';

/// 真实内容包冒烟（2026-11-15，task-79）：Q-PH0001 的 DAG 节点 + 错因走一遍
/// 闪存卡生成器，锁住「真实内容 → 卡」的规则与数量（dry run 与 apply 各一遍）。
///
/// 这是**实验/验收**测试，不是纯单元测试：它直接读工作区内容包的绝对路径，
/// 文件不在本机时整组 skip（与 `test/experiments/` 其它用例同口径）。纯规则
/// 单测在 `test/domain/services/content/dag_flashcard_generator_test.dart`。
///
/// 期望（2026-11-15 的 Q-PH0001，board v3 / 6 节点 / 2 错因）：
///  * 生成 6 张：公式 1（N-Q1-02）、判断 2（N-Q1-03/04）、结论 1（N-Q1-06）、
///    错因 2（EC-Q1-01/02）；
///  * 跳过 2 张：审题节点 N-Q1-01（role=read_question）、纯爆算 N-Q1-05
///    （kind=computation）；
///  * 缺 KP / KO 不存在 / 重复 external_id 等规则由纯单测覆盖。
void main() {
  const boardPath =
      r'E:\Workspaces\agent-control\10-projects\agent-control-plane'
      r'\content-store\physics\Q-PH0001\boards\physics-board.json';
  final boardFile = File(boardPath);
  if (!boardFile.existsSync()) {
    test('Q-PH0001 内容包不在本机，跳过真实内容冒烟', () {}, skip: 'not found: $boardPath');
    return;
  }
  final board =
      jsonDecode(boardFile.readAsStringSync()) as Map<String, Object?>;

  DagFlashcardNode nodeFromJson(Map<String, Object?> json) => DagFlashcardNode(
        id: (json['id'] as String?) ?? '',
        kind: (json['kind'] as String?) ?? '',
        role: (json['role'] as String?) ?? '',
        label: (json['label'] as String?) ?? '',
        body: (json['body'] as String?) ?? '',
        formulas: <String>[
          for (final formula
              in (json['formulas'] as List<Object?>?) ?? <Object?>[])
            formula.toString(),
        ],
        keyQuantities: <String>[
          for (final quantity
              in (json['key_quantities'] as List<Object?>?) ?? <Object?>[])
            quantity.toString(),
        ],
        result: (json['result'] as String?) ?? '',
      );

  final dag = board['thinking_dag'] as Map<String, Object?>;
  final nodes = <DagFlashcardNode>[
    for (final raw in (dag['nodes'] as List<Object?>))
      nodeFromJson((raw as Map<Object?, Object?>).cast<String, Object?>()),
  ];
  final causeBoard = board['error_causes'] as Map<String, Object?>?;
  final causes = <DagFlashcardErrorCause>[
    for (final raw in (causeBoard?['items'] as List<Object?>?) ?? <Object?>[])
      _causeFromJson((raw as Map<Object?, Object?>).cast<String, Object?>()),
  ];

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
      content: '真实内容包冒烟用的产品知识点（不是内容正文）。',
    ))
        .id;
  });

  tearDown(() async {
    await db.close();
  });

  DagFlashcardInput input() => DagFlashcardInput(
        contentId: 'Q-PH0001',
        questionTitle: '平抛运动的不变量与变化量',
        knowledgePointId: kpId,
        nodes: nodes,
        errorCauses: causes,
      );

  test('dry run：真实 DAG/错因 → 6 张 wouldCreate、2 张 skipped', () async {
    final plan = await generator.generate(input());

    expect(plan.dryRun, isTrue);
    expect(plan.wouldCreate, 6, reason: '1 公式 + 2 判断 + 1 结论 + 2 错因');
    expect(plan.skipped, 2, reason: '审题 N-Q1-01 + 纯爆算 N-Q1-05');
    expect(plan.blocked, 0);
    expect(
      plan.cardsByKind,
      <DagCardKind, int>{
        DagCardKind.formula: 1,
        DagCardKind.check: 2,
        DagCardKind.conclusion: 1,
        DagCardKind.errorCause: 2,
      },
    );
    final bySeed = <String, DagFlashcardPlanItem>{
      for (final item in plan.items) item.seedId: item,
    };
    expect(bySeed['N-Q1-01']!.reason, DagCardSkipReason.readQuestionRole);
    expect(bySeed['N-Q1-05']!.reason, DagCardSkipReason.pureComputation);
    expect(bySeed['N-Q1-02']!.kind, DagCardKind.formula);
    expect(bySeed['N-Q1-02']!.answer, contains('v_x=v_0'));
    expect(bySeed['N-Q1-03']!.kind, DagCardKind.check);
    expect(bySeed['N-Q1-03']!.question, contains('这一步的判断是什么？依据是什么？'));
    expect(bySeed['N-Q1-03']!.answer, startsWith('B 真'));
    expect(bySeed['N-Q1-04']!.answer, startsWith('A 假'));
    expect(bySeed['N-Q1-06']!.kind, DagCardKind.conclusion);
    expect(bySeed['N-Q1-06']!.answer, '答案 B');
    expect(bySeed['EC-Q1-01']!.kind, DagCardKind.errorCause);
    expect(bySeed['EC-Q1-01']!.question, contains('易错点：'));
    expect(bySeed['EC-Q1-02']!.kind, DagCardKind.errorCause);

    // dry run 不写库。
    expect(await anki.getAllTemplates(), isEmpty);
    expect((await contentRefs.listByContentId('Q-PH0001')), isEmpty);
    expect(await db.select(db.cardStates).get(), isEmpty);
  });

  test('apply：真实内容落 6 张模板 + 6 条 card_seed 引用，不动 FSRS', () async {
    final plan = await generator.generate(input(), dryRun: false);

    expect(plan.created, 6);
    final templates = await anki.getAllTemplates();
    expect(templates, hasLength(6));
    for (final template in templates) {
      expect(template.externalId, startsWith('content:Q-PH0001#'));
      expect(template.knowledgePointId, kpId);
      expect(template.hint, startsWith('【AI】'));
    }
    expect(
      <String>{
        for (final template in templates) template.externalId!,
      },
      <String>{
        'content:Q-PH0001#N-Q1-02',
        'content:Q-PH0001#N-Q1-03',
        'content:Q-PH0001#N-Q1-04',
        'content:Q-PH0001#N-Q1-06',
        'content:Q-PH0001#EC-Q1-01',
        'content:Q-PH0001#EC-Q1-02',
      },
    );
    expect(await contentRefs.listByContentId('Q-PH0001'), hasLength(6));
    expect(await db.select(db.cardStates).get(), isEmpty);
    expect(await db.select(db.reviewLogs).get(), isEmpty);

    // 再跑一次是幂等的：不新增模板/引用。
    final again = await generator.generate(input(), dryRun: false);
    expect(again.created, 0);
    expect(
      again.skipped,
      8,
      reason: '6 张 already_exists + 审题/爆算 2 个类型跳过',
    );
    expect(
      again.skippedReasons,
      <String, int>{
        DagCardSkipReason.alreadyExists: 6,
        DagCardSkipReason.readQuestionRole: 1,
        DagCardSkipReason.pureComputation: 1,
      },
    );
    expect(await anki.getAllTemplates(), hasLength(6));
    expect(await contentRefs.listByContentId('Q-PH0001'), hasLength(6));
  });
}

DagFlashcardErrorCause _causeFromJson(Map<String, Object?> json) =>
    DagFlashcardErrorCause(
      code: (json['code'] as String?) ?? '',
      category: (json['category'] as String?) ?? '',
      symptom: (json['symptom'] as String?) ?? '',
      rootCause: (json['root_cause'] as String?) ?? '',
      diagnosticQuestion: (json['diagnostic_question'] as String?) ?? '',
      remediation: (json['remediation'] as String?) ?? '',
      locateNode: json['locate_node'] as String?,
    );
