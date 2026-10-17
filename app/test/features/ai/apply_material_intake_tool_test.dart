/// `apply_material_intake` 工具的测试（roadmap §2-C ① 的后半段）。
///
/// `ingest_material` 只读、只摆提案；用户点头之后由这个工具落库。这里钉的是"写"这条
/// 路上最容易出事的几件事：**不是只读**（审批引擎得看得见）、信封不合规时**一行都不写**、
/// 同一份信封确认两次**不会建出两个知识点或两条边**、参数里的 `proposal_ids` 越界要拒绝
/// 而不是悄悄少写、以及选中的连接**真的落成线索边**（`knowledge_edges`，严格有向、`ls`
/// 带未标定标记）—— 端点不齐的才如实报 `deferred`。
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

/// 与 `ingest_tools_test.dart` / 纯逻辑测试同一份三行材料。
Map<String, Object?> envelopeJson({String batchId = 'b-apply'}) =>
    <String, Object?>{
      'protocol': 'mindnet.material/1',
      'batch_id': batchId,
      'source': <String, Object?>{
        'kind': 'book',
        'refs': <String>['词汇书 p12'],
        'material': '词汇书',
        'captured_at': '2026-10-16T05:00:00.000Z',
      },
      'topic': 'travel',
      'language': 'en',
      'items': <Map<String, Object?>>[
        <String, Object?>{
          'id': 'm1',
          'mark': '句',
          'text': 'I relied on him.',
          'page': 12,
          'line': 3,
          'contains': <String>['m2'],
          'margin_note': '整句要能说出来',
        },
        <String, Object?>{
          'id': 'm2',
          'mark': '词',
          'text': 'rely on',
          'page': 12,
          'line': 3,
          'context': 'I relied on him.',
          'meaning': '依靠',
          'meaning_source': 'user',
          'margin_note': '搭配',
          'produce': true,
        },
        <String, Object?>{
          'id': 'm3',
          'mark': '问',
          'text': 'rely on 和 depend on 的区别？',
          'page': 12,
          'line': 4,
          'margin_note': '先别建点',
        },
      ],
    };

void main() {
  late AppDatabase db;
  late AnkiRepository anki;
  late MaterialIntakeRepository repository;
  late ApplyMaterialIntakeTool tool;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    anki = AnkiRepository(db);
    repository = MaterialIntakeRepository(
      db,
      ankiRepository: anki,
      clock: () => DateTime.fromMillisecondsSinceEpoch(1789000000000),
    );
    tool = ApplyMaterialIntakeTool(
      repository: repository,
      clock: () => DateTime.fromMillisecondsSinceEpoch(1789000000000),
    );
  });

  tearDown(() async {
    await db.close();
  });

  ToolInvocation invocationOf(
    Object? material, {
    List<String>? proposalIds,
    Map<String, String>? renames,
  }) =>
      ToolInvocation(
        toolName: 'apply_material_intake',
        action: 'apply_material_intake',
        arguments: <String, Object?>{
          'material': material,
          if (proposalIds != null) 'proposal_ids': proposalIds,
          if (renames != null) 'renames': renames,
        },
      );

  Map<String, Object?> payloadOf(ToolResult result) =>
      result.modelResult! as Map<String, Object?>;

  test('是写工具（审批看得见），且注册表里拿得到', () {
    expect(tool.name, 'apply_material_intake');
    expect(tool.readOnly, isFalse);
    expect(tool.riskFor('apply_material_intake'), ToolRisk.write);
    expect(tool.reversibleFor('apply_material_intake'), isTrue);

    final registry = ToolRegistry.forApp(
      db: db,
      tasks: TaskRepository(db),
      blocks: TimeBlockRepository(db),
      anki: anki,
      tags: TagRepository(db),
    );
    expect(registry.byName('apply_material_intake'), isNotNull);
  });

  test('没有要动的东西 ⇒ 一行都不写，也不留批次', () async {
    final onlyQuestion = envelopeJson()
      ..['items'] = <Map<String, Object?>>[
        <String, Object?>{
          'id': 'm3',
          'mark': '问',
          'text': 'rely on 和 depend on 的区别？',
          'page': 12,
          'line': 4,
          'margin_note': '先别建点',
        },
      ];

    final result = await tool.run(invocationOf(onlyQuestion));

    expect(result.ok, isTrue);
    expect(result.summary, contains('没有要动的东西'));
    expect(await db.select(db.knowledgePoints).get(), isEmpty);
    expect(await repository.batches(), isEmpty);
  });

  test('信封不合规 ⇒ 整份拒绝，一行都不写', () async {
    final bad = envelopeJson()..['protocol'] = 'mindnet.material/0';
    final result = await tool.run(invocationOf(bad));

    expect(result.ok, isFalse);
    expect(result.summary, contains('整份拒绝'));
    expect(await db.select(db.knowledgePoints).get(), isEmpty);
    expect(await repository.batches(), isEmpty);
  });

  test('好信封 ⇒ 知识点与线索边落库、afterJson 带两类 id', () async {
    final result = await tool.run(invocationOf(envelopeJson()));

    expect(result.ok, isTrue);
    expect(result.summary, contains('新建 2 个知识点'));
    expect(result.summary, contains('新建 2 条连接'));
    expect(result.summary, contains('「rely on」'));
    expect(result.summary, contains('en::w::rely-on'));
    expect(result.summary, contains('未标定'));

    final outcome = payloadOf(result)['outcome']! as Map<String, Object?>;
    expect(outcome['batch_id'], 'b-apply');
    expect(outcome['created'], hasLength(2));
    expect(outcome['created_edges'], hasLength(2));
    expect(outcome['deferred'], isEmpty);
    expect(outcome['remaining'], 0);

    final batch = payloadOf(result)['batch']! as Map<String, Object?>;
    expect(batch['summary'], contains('批次 b-apply'));
    expect(batch['proposal_count'], 4);
    expect(batch['unapplied_count'], 0);

    final rows = await db.select(db.knowledgePoints).get();
    expect(rows, hasLength(2));
    expect(
      rows.singleWhere((row) => row.externalId == 'en::w::rely-on').source,
      '材料：词汇书（第 12 页）',
    );

    final edges = await db.select(db.knowledgeEdges).get();
    expect(edges, hasLength(2));
    expect(edges.first.lsCalibrated, isFalse);
    expect(edges.first.batchId, 'b-apply');

    final after = jsonDecode(result.afterJson!) as Map<String, Object?>;
    expect(after['batch_id'], 'b-apply');
    expect(after['knowledge_point_ids'], hasLength(2));
    expect(after['edge_ids'], hasLength(2));
  });

  test('确认两次是幂等的：第二次不建新点新边，也不报错', () async {
    await tool.run(invocationOf(envelopeJson()));
    final again = await tool.run(invocationOf(envelopeJson()));

    expect(again.ok, isTrue);
    final outcome = payloadOf(again)['outcome']! as Map<String, Object?>;
    expect(outcome['created'], isEmpty);
    expect(outcome['created_edges'], isEmpty);
    expect(outcome['remaining'], 0);
    expect(await db.select(db.knowledgePoints).get(), hasLength(2));
    expect(await db.select(db.knowledgeEdges).get(), hasLength(2));
  });

  test('proposal_ids 只确认选中那几条', () async {
    final result = await tool.run(
      invocationOf(
        envelopeJson(),
        // 词那条的提案 id 是稳定的（节点 id 用 slug）；句那条是 `kp:en::s::<hash8>`。
        proposalIds: <String>['kp:en::w::rely-on'],
      ),
    );

    expect(result.ok, isTrue);
    final outcome = payloadOf(result)['outcome']! as Map<String, Object?>;
    expect(outcome['created'], hasLength(1));
    expect(outcome['remaining'], 3);
    expect(await db.select(db.knowledgePoints).get(), hasLength(1));
  });

  test('proposal_ids 里有这一批之外的 id ⇒ 拒绝，并说清这一批有什么', () async {
    final result = await tool.run(
      invocationOf(
        envelopeJson(),
        proposalIds: <String>['kp:en::w::not-here'],
      ),
    );

    expect(result.ok, isFalse);
    expect(result.summary, contains('不在这一批里'));
    expect(await db.select(db.knowledgePoints).get(), isEmpty);
  });

  test('material 给 JSON 文本时也能确认', () async {
    final result = await tool.run(invocationOf(jsonEncode(envelopeJson())));

    expect(result.ok, isTrue);
    expect(await db.select(db.knowledgePoints).get(), hasLength(2));
  });

  test('renames：点头之前先改一改标题，建出来的就是改过的那个', () async {
    final result = await tool.run(
      invocationOf(
        envelopeJson(),
        renames: <String, String>{'kp:en::w::rely-on': '  rely on（依靠）  '},
      ),
    );

    expect(result.ok, isTrue, reason: result.summary);
    expect(result.summary, contains('先改过 1 条知识点提案的标题'));
    expect(result.summary, contains('rely on（依靠）'));
    final payload = payloadOf(result);
    expect(payload['renamed'], hasLength(1));
    final renamed =
        (payload['renamed']! as List).single as Map<String, Object?>;
    expect(renamed['proposal_id'], 'kp:en::w::rely-on');
    expect(renamed['title'], 'rely on（依靠）', reason: '首尾空白要剪掉');

    // 库里那个知识点的标题就是改过的（不是材料里原来那个）。
    final points = await anki.getKnowledgePoints();
    expect(
      points.map((point) => point.title),
      containsAll(<String>['rely on（依靠）', 'I relied on him.']),
    );
    expect(points.map((point) => point.title), isNot(contains('rely on')));
  });

  test('renames 指到一条连接 ⇒ 失败，说清只有知识点的标题能改', () async {
    // 先确认一条知识点：连接还留在待确认里，正好拿它来试"连接的标题不给改"。
    await tool.run(
      invocationOf(
        envelopeJson(),
        proposalIds: <String>['kp:en::w::rely-on'],
      ),
    );
    final batch = (await repository.batches()).single;
    final connection = (await repository.pendingProposals(batch.batchId))
        .firstWhere((proposal) => proposal.id.startsWith('edge:'));

    final result = await tool.run(
      invocationOf(
        envelopeJson(),
        renames: <String, String>{connection.id: '随便改个名字'},
      ),
    );

    expect(result.ok, isFalse);
    expect(result.summary, contains('只有知识点的标题能改'));
    // 第一次那条已经点过头了；这次失败没多建任何东西。
    expect(await db.select(db.knowledgePoints).get(), hasLength(1));
  });

  test('renames 给空标题 ⇒ 失败，理由是人话', () async {
    final result = await tool.run(
      invocationOf(
        envelopeJson(),
        renames: <String, String>{'kp:en::w::rely-on': '   '},
      ),
    );

    expect(result.ok, isFalse);
    expect(result.summary, contains('标题不能是空的'));
    expect(await db.select(db.knowledgePoints).get(), isEmpty);
  });

  test('renames 有这一批之外的 id ⇒ 失败，说清这一批里没有它', () async {
    final result = await tool.run(
      invocationOf(
        envelopeJson(),
        renames: <String, String>{'kp:en::w::not-here': '改'},
      ),
    );

    expect(result.ok, isFalse);
    expect(result.summary, contains('没有这条提案'));
    expect(await db.select(db.knowledgePoints).get(), isEmpty);
  });

  test('renames 不是对象 ⇒ 参数错，不装作改了', () async {
    final result = await tool.run(ToolInvocation(
      toolName: 'apply_material_intake',
      action: 'apply_material_intake',
      arguments: <String, Object?>{
        'material': envelopeJson(),
        'renames': <String>['不是对象'],
      },
    ));

    expect(result.ok, isFalse);
    expect(result.summary, contains('应该是一个对象'));
    expect(await db.select(db.knowledgePoints).get(), isEmpty);
  });
}
