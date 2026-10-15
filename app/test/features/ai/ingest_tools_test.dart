/// `ingest_material` 工具的测试（roadmap §2-C ① / §3 第 6 行）。
///
/// 工具是接线不是逻辑：确定性转化与提案的判断在
/// `domain/services/ingest/{material_ingest,material_intake_plan}.dart` 里各有测试，
/// 这里只钉它自己那几件事 —— 只读、注册表里拿得到、参数错要能读懂、信封不合规整份拒绝
/// 且说清原因、同名知识点标"不重复建"、JSON 文本与对象两种给法等价。
library;

import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/anki_repository.dart';
import 'package:furnace/data/repositories/tag_repository.dart';
import 'package:furnace/data/repositories/task_repository.dart';
import 'package:furnace/data/repositories/time_block_repository.dart';
import 'package:furnace/features/ai/domain/ai_tool.dart';
import 'package:furnace/features/ai/domain/tool_registry.dart';
import 'package:furnace/features/ai/tools/ingest_tools.dart';

/// 与纯逻辑测试同一份三行材料（句子 / 搭配 / 不进图的疑问）。
Map<String, Object?> envelopeJson() => <String, Object?>{
      'protocol': 'mindnet.material/1',
      'batch_id': 'b-tool',
      'source': <String, Object?>{
        'kind': 'book',
        'refs': <String>['词汇书 p12'],
        'material': '词汇书',
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
          // 上游生成反向边（词 → 句）的条件：`produce: true`（或 `modified: ['produce']`）。
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
  late IngestMaterialTool tool;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    anki = AnkiRepository(db);
    tool = IngestMaterialTool(
      ankiRepository: anki,
      // 钉住时刻：材料入库要一个模型时间基，测试里不让它跟着墙钟跑。
      clock: () => DateTime.fromMillisecondsSinceEpoch(1789000000000),
    );
  });

  tearDown(() async {
    await db.close();
  });

  ToolInvocation invocationOf(
    Object? material, {
    bool? includeTopicHubs,
  }) =>
      ToolInvocation(
        toolName: 'ingest_material',
        action: 'ingest_material',
        arguments: <String, Object?>{
          'material': material,
          if (includeTopicHubs != null) 'include_topic_hubs': includeTopicHubs,
        },
      );

  Map<String, Object?> planOf(ToolResult result) =>
      (result.modelResult! as Map<String, Object?>)['plan']!
          as Map<String, Object?>;

  test('只读，且注册表里拿得到', () {
    expect(tool.name, 'ingest_material');
    expect(tool.readOnly, isTrue);
    expect(tool.reversibleFor('ingest_material'), isTrue);

    final registry = ToolRegistry.forApp(
      db: db,
      tasks: TaskRepository(db),
      blocks: TimeBlockRepository(db),
      anki: anki,
      tags: TagRepository(db),
    );
    expect(registry.byName('ingest_material'), isNotNull);
  });

  test('缺少 material ⇒ ToolArgError（模型能读懂的那种错）', () async {
    await expectLater(
      tool.run(invocationOf(null)),
      throwsA(
        isA<ToolArgError>().having(
          (error) => error.message,
          'message',
          contains('mindnet.material/1'),
        ),
      ),
    );
  });

  test('信封不合规 ⇒ 整份拒绝，并说清哪一条错', () async {
    final bad = envelopeJson()..['protocol'] = 'mindnet.material/0';
    final result = await tool.run(invocationOf(bad));

    expect(result.ok, isFalse);
    expect(result.summary, contains('整份拒绝'));
    expect(result.summary, contains('protocol'));
    expect(result.modelResult, isNull);
  });

  test('好信封 ⇒ 提案清单 + 只读声明，plan 计数对得上', () async {
    final result = await tool.run(invocationOf(envelopeJson()));

    expect(result.ok, isTrue);
    expect(result.summary, contains('批次 b-tool：要建 2 个知识点'));
    expect(result.summary, contains('2 条连接'));
    expect(result.summary, contains('[知识点] rely on'));
    expect(result.summary, contains('只读：上面是提案，还没有写库'));

    final plan = planOf(result);
    expect(plan['new_points'], 2);
    expect(plan['connections'], 2);
    expect(plan['skipped_count'], 3);
    expect(plan['proposals'], hasLength(4));
  });

  test('material 给 JSON 文本时与给对象等价', () async {
    final asObject = await tool.run(invocationOf(envelopeJson()));
    final asText = await tool.run(
      invocationOf(jsonEncode(envelopeJson())),
    );

    expect(asText.ok, isTrue);
    expect(planOf(asText)['new_points'], planOf(asObject)['new_points']);
    expect(planOf(asText)['connections'], planOf(asObject)['connections']);
  });

  test('库里已有同名知识点 ⇒ 明说"不重复建"', () async {
    await anki.createKnowledgePoint(title: 'rely on', content: '先有的点');

    final result = await tool.run(invocationOf(envelopeJson()));

    expect(result.ok, isTrue);
    expect(result.summary, contains('同名已存在，不重复建'));
    expect(planOf(result)['existing_points'], 1);
    expect(planOf(result)['new_points'], 1);
  });

  test('include_topic_hubs: true ⇒ 主题也进提案', () async {
    final result =
        await tool.run(invocationOf(envelopeJson(), includeTopicHubs: true));

    expect(planOf(result)['new_points'], 3);
    expect(planOf(result)['connections'], 4);
  });

  test('payload 带材料摘要、告警与 run/1 自检（只校验不执行）', () async {
    final result = await tool.run(invocationOf(envelopeJson()));
    final payload = result.modelResult! as Map<String, Object?>;

    final material = payload['material']! as Map<String, Object?>;
    expect(material['batch_id'], 'b-tool');
    expect(material['nodes'], 3);

    final check = payload['run_check']! as Map<String, Object?>;
    expect(check['ok'], isTrue);
    expect(check['summary'], contains('请求合法'));
    expect(payload['run_request'], isNotNull);
    expect(payload['warnings'], isA<List<Object?>>());
  });
}
