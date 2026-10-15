/// `apply_material_intake` 工具的测试（roadmap §2-C ① 的后半段）。
///
/// `ingest_material` 只读、只摆提案；用户点头之后由这个工具落库。这里钉的是"写"这条
/// 路上最容易出事的几件事：**不是只读**（审批引擎得看得见）、信封不合规时**一行都不写**、
/// 同一份信封确认两次**不会建出两个知识点**、参数里的 `proposal_ids` 越界要拒绝而不是
/// 悄悄少写、以及**连接现在不写**（落点未定，§2-C ④）—— 它必须如实报成 `deferred`。
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
  }) =>
      ToolInvocation(
        toolName: 'apply_material_intake',
        action: 'apply_material_intake',
        arguments: <String, Object?>{
          'material': material,
          if (proposalIds != null) 'proposal_ids': proposalIds,
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

  test('好信封 ⇒ 知识点落库、连接 deferred、afterJson 带 id', () async {
    final result = await tool.run(invocationOf(envelopeJson()));

    expect(result.ok, isTrue);
    expect(result.summary, contains('新建 2 个知识点'));
    expect(result.summary, contains('「rely on」'));
    expect(result.summary, contains('en::w::rely-on'));
    expect(result.summary, contains('连接先不动'));

    final outcome = payloadOf(result)['outcome']! as Map<String, Object?>;
    expect(outcome['batch_id'], 'b-apply');
    expect(outcome['created'], hasLength(2));
    expect(outcome['deferred'], hasLength(2));
    expect(outcome['remaining'], 2);

    final batch = payloadOf(result)['batch']! as Map<String, Object?>;
    expect(batch['summary'], contains('批次 b-apply'));
    expect(batch['proposal_count'], 4);
    expect(batch['unapplied_count'], 2);

    final rows = await db.select(db.knowledgePoints).get();
    expect(rows, hasLength(2));
    expect(
      rows.singleWhere((row) => row.externalId == 'en::w::rely-on').source,
      '材料：词汇书（第 12 页）',
    );

    final after = jsonDecode(result.afterJson!) as Map<String, Object?>;
    expect(after['batch_id'], 'b-apply');
    expect(after['knowledge_point_ids'], hasLength(2));
  });

  test('确认两次是幂等的：第二次不建新点，也不报错', () async {
    await tool.run(invocationOf(envelopeJson()));
    final again = await tool.run(invocationOf(envelopeJson()));

    expect(again.ok, isTrue);
    final outcome = payloadOf(again)['outcome']! as Map<String, Object?>;
    expect(outcome['created'], isEmpty);
    expect(outcome['remaining'], 2);
    expect(await db.select(db.knowledgePoints).get(), hasLength(2));
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
}
