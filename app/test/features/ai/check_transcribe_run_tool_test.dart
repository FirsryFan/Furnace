/// `check_transcribe_run` 工具的测试（roadmap §2-C ③）。
///
/// 与 MindNet 的 `tools/io_check.js` 是同一件事：**只校验、不执行**。这里钉的是接线上最
/// 容易出事的几件事：工具是**只读**的（审批引擎直接执行，不打扰用户）、缺 `request` 要报
/// 参数错、不合规的请求要整份拒绝（不"挑能跑的先跑"）、图清单来自库里的 `external_id`
/// （所以 `review` 指向真实存在的知识点就能过），以及提示词与图清单能一起要出来。
///
/// `execute: true` 之后的**演练**（Q56）也在这里钉两件事：真的把动作 apply 进引擎而
/// **库一个字不动**；以及"校验说合法"≠"引擎真能跑"——仿真图是从库里摆出来的，库里没有
/// 的节点会让演练如实停在第一条。它也是 `run_executor.dart` 的第一个调用者。
library;

import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/anki_repository.dart';
import 'package:furnace/data/repositories/material_intake_repository.dart';
import 'package:furnace/data/repositories/tag_repository.dart';
import 'package:furnace/data/repositories/task_repository.dart';
import 'package:furnace/data/repositories/time_block_repository.dart';
import 'package:furnace/features/ai/domain/ai_tool.dart';
import 'package:furnace/features/ai/domain/tool_registry.dart';
import 'package:furnace/features/ai/tools/ingest_tools.dart';

/// 一条 `review` 动作（`at` / evidence / confidence 都带齐）。
Map<String, Object?> reviewAction(String nodeId) => <String, Object?>{
      'kind': 'review',
      'node': nodeId,
      'outcome': 'wrong',
      'reviewed_solution': true,
      'at': <String, Object?>{'model_hours': 497321.25},
      'evidence': <String, Object?>{
        'source': 'page-3.jpg',
        'region': '第 2 题',
        'quote': '我写成了 rely in',
      },
      'confidence': 0.7,
    };

Map<String, Object?> runJson({
  Object? protocol = 'mindnet.run/1',
  Object? runId = 'run-2026-10-16-0007',
  List<Map<String, Object?>>? actions,
}) =>
    <String, Object?>{
      'protocol': protocol,
      'run_id': runId,
      'time': <String, Object?>{'model_hours': 497321.25},
      'actions':
          actions ?? <Map<String, Object?>>[reviewAction('en::w::rely-on')],
    };

void main() {
  late AppDatabase db;
  late AnkiRepository anki;
  late CheckTranscribeRunTool tool;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    anki = AnkiRepository(db);
    tool = CheckTranscribeRunTool(
      repository: MaterialIntakeRepository(db, ankiRepository: anki),
      database: db,
    );
  });

  tearDown(() async {
    await db.close();
  });

  ToolInvocation invocationOf(
    Object? request, {
    List<String>? existingNodeIds,
    bool includePrompt = false,
    bool execute = false,
  }) =>
      ToolInvocation(
        toolName: 'check_transcribe_run',
        action: 'check_transcribe_run',
        arguments: <String, Object?>{
          'request': request,
          if (existingNodeIds != null) 'existing_node_ids': existingNodeIds,
          if (includePrompt) 'include_prompt': true,
          if (execute) 'execute': true,
        },
      );

  Map<String, Object?> reportOf(ToolResult result) =>
      (result.modelResult! as Map<String, Object?>)['report']!
          as Map<String, Object?>;

  test('是只读工具（审批直接执行），且注册表里拿得到', () {
    expect(tool.name, 'check_transcribe_run');
    expect(tool.readOnly, isTrue);
    expect(tool.availableOnCurrentPlatform, isTrue);

    final registry = ToolRegistry.forApp(
      db: db,
      tasks: TaskRepository(db),
      blocks: TimeBlockRepository(db),
      anki: anki,
      tags: TagRepository(db),
    );
    expect(registry.byName('check_transcribe_run'), isNotNull);
  });

  test('缺 `request` ⇒ 参数错（不是"请求不合法"）', () async {
    await expectLater(
      tool.run(invocationOf(null)),
      throwsA(
        isA<ToolArgError>().having(
          (error) => error.message,
          'message',
          contains('缺少 `request`'),
        ),
      ),
    );
  });

  test('不是 JSON 文本 ⇒ 参数错', () async {
    await expectLater(
      tool.run(invocationOf('{不是 json')),
      throwsA(isA<ToolArgError>()),
    );
  });

  test('好请求 ⇒ 合法 + 机制路径 + 出处统计', () async {
    final result = await tool.run(
      invocationOf(runJson(), existingNodeIds: <String>['en::w::rely-on']),
    );

    expect(result.ok, isTrue);
    expect(result.summary, contains('✓ 请求合法：run-2026-10-16-0007'));
    expect(result.summary, contains('retrieval_failure_feedback'));
    expect(result.summary, contains('出处：1/1 条带 evidence'));
    expect(result.summary, contains('只读：这份请求还没有被执行'));
    expect(result.summary, contains('图清单来自库里的 1 个节点'));

    final report = reportOf(result);
    expect(report['ok'], isTrue);
    expect(report['actions'], 1);
    expect(report['evidence_count'], 1);
    expect(report['warnings'], isEmpty);
    expect(report['previews'], hasLength(1));
  });

  test('节点不在图 ⇒ ok false，整份拒绝', () async {
    final result = await tool.run(
      invocationOf(runJson(), existingNodeIds: <String>[]),
    );

    expect(result.ok, isFalse);
    expect(result.summary, contains('✗ 请求不合法'));
    expect(result.summary, contains('整份拒绝'));
    expect(result.error, contains('图里不存在'));
    expect(reportOf(result)['ok'], isFalse);
  });

  test('图清单默认来自库里知识点的 external_id', () async {
    final point = await anki.createKnowledgePoint(
      title: 'rely on',
      content: '依靠',
      externalId: 'en::w::rely-on',
    );
    expect(point.title, 'rely on');

    final withPrompt = await tool.run(
      invocationOf(runJson(), includePrompt: true),
    );

    expect(withPrompt.ok, isTrue, reason: withPrompt.summary);
    expect(withPrompt.summary, contains('图清单来自库里的 1 个节点'));
    final payload = withPrompt.modelResult! as Map<String, Object?>;
    expect(payload['graph_nodes'], 1);
    expect(payload['prompt'], contains('en::w::rely-on → rely on'));
    expect(payload['prompt'], contains('【图清单】'));
  });

  test('JSON 文本与对象等价', () async {
    final fromText = await tool.run(
      invocationOf(jsonEncode(runJson()),
          existingNodeIds: <String>['en::w::rely-on']),
    );
    final fromObject = await tool.run(
      invocationOf(runJson(), existingNodeIds: <String>['en::w::rely-on']),
    );

    expect(fromText.ok, isTrue);
    expect(reportOf(fromText)['run_id'], reportOf(fromObject)['run_id']);
    expect(reportOf(fromText)['previews'], reportOf(fromObject)['previews']);
  });

  test('协议不对 ⇒ 整份拒绝（但预览照给，便于定位）', () async {
    final result = await tool.run(
      invocationOf(
        runJson(protocol: 'mindnet.run/0'),
        existingNodeIds: <String>['en::w::rely-on'],
      ),
    );

    expect(result.ok, isFalse);
    expect(result.error, contains('protocol 必须是 "mindnet.run/1"'));
    expect(reportOf(result)['previews'], hasLength(1));
  });

  test('不写 `execute` ⇒ 校验完就停，payload 里没有演练', () async {
    await anki.createKnowledgePoint(
      title: 'rely on',
      content: '依靠',
      externalId: 'en::w::rely-on',
    );

    final result = await tool.run(invocationOf(runJson()));

    expect(result.ok, isTrue);
    final payload = result.modelResult! as Map<String, Object?>;
    expect(payload.containsKey('rehearsal'), isFalse);
    expect(result.summary, contains('还没有被执行'));
  });

  test('`execute: true` ⇒ 真的跑进引擎：图摆好、动作应用、库一个字没动', () async {
    await anki.createKnowledgePoint(
      title: 'rely on',
      content: '依靠',
      externalId: 'en::w::rely-on',
    );

    final result = await tool.run(invocationOf(runJson(), execute: true));

    expect(result.ok, isTrue, reason: result.summary);
    expect(result.summary, contains('演练（只跑不落库）'));
    expect(result.summary, contains('全部跑完'));
    expect(result.summary, contains('真的动了机制'));
    // 这条知识点还没有卡片，所以读不出 ms —— 演练如实说出来，不替它编数字。
    expect(result.summary, contains('1 个节点没有 ms'));

    final payload = result.modelResult! as Map<String, Object?>;
    final rehearsal = payload['rehearsal']! as Map<String, Object?>;
    expect(rehearsal['seed_node_ids'], <String>['en::w::rely-on']);
    expect(rehearsal['seed_edge_ids'], isEmpty);
    expect(rehearsal['nodes_without_ms'], <String>['en::w::rely-on']);
    expect(rehearsal['unknown_node_ids'], isEmpty);

    final report = rehearsal['report']! as Map<String, Object?>;
    expect(report['ok'], isTrue);
    final traces = report['traces']! as List<Object?>;
    expect(traces, hasLength(1));
    final delta = (traces.first! as Map<String, Object?>)['delta']!
        as Map<String, Object?>;
    // 装了 `memory.dsr`，所以一次 wrong + 对答案真的动了袋子。
    expect(delta['mechanism'], 'memory.dsr');
    expect(delta['R_after'], isA<num>());

    // 只跑不落库：知识点还是一行，卡片与记忆态没有任何新行。
    expect(await anki.getKnowledgePoints(), hasLength(1));
    expect(await db.select(db.cardStates).get(), isEmpty);
    expect(await db.select(db.cardTemplates).get(), isEmpty);
    expect(await db.select(db.materialIntakeProposals).get(), isEmpty);
  });

  test('校验说合法，演练也可能真的跑不动：库里没有那个节点 ⇒ 停在第一条', () async {
    // 显式给了图清单 ⇒ 校验过；但库里一个字都没有 ⇒ 仿真图是空的。
    final result = await tool.run(
      invocationOf(
        runJson(),
        existingNodeIds: <String>['en::w::rely-on'],
        execute: true,
      ),
    );

    expect(result.ok, isFalse);
    expect(result.error, isNotNull);
    expect(result.summary, contains('演练（只跑不落库）'));
    expect(result.summary, contains('停在'));

    final payload = result.modelResult! as Map<String, Object?>;
    final rehearsal = payload['rehearsal']! as Map<String, Object?>;
    expect(rehearsal['seed_node_ids'], isEmpty);
    expect(rehearsal['unknown_node_ids'], <String>['en::w::rely-on']);
  });
}
