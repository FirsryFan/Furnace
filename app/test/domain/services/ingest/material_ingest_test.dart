import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/ingest/material_ingest.dart';

/// INGEST 第 ③ 步（确定性转化）的测试。
///
/// 这一层是 MindNet `src/ingest.js` 的 Dart 版，所以这里的期望值分两种：
///  * **对拍值**：用 `node` 真跑参考实现拿到的输出（节点 id、7 条边、14 条动作、告警）。
///    它们不是从文档抄的，改这一层时这些数字必须逐位一样；
///  * **本位自己的约定**：四处与 JS 有意不同的地方（见 library doc），各有用例钉住。
///
/// 这一层不 import Flutter/drift，也不需要数据库与时钟：材料信封 → 三样正产品是纯函数。
void main() {
  /// 模型时间基（Unix 纪元小时数）；对拍时用的就是 497321.25。
  const nowHours = 497321.25;
  const batchId = 'en-listen-2026-09-25-a';

  /// INGEST.md §3 的示例信封（对拍用的那一份）。
  Map<String, Object?> exampleJson() => (jsonDecode(r'''
{
  "protocol": "mindnet.material/1",
  "batch_id": "en-listen-2026-09-25-a",
  "source": {
    "kind": "photo",
    "refs": ["dsc_0101.jpg"],
    "material": "BBC 6 Minute English · 第 3 段",
    "captured_at": "2026-09-25T10:00:00Z"
  },
  "topic": "travel",
  "language": "en",
  "marks": { "法": { "role": "method", "means": "听力方法/套路" } },
  "items": [
    { "id": "m1", "mark": "词", "text": "resilient",
      "margin_note": "resilient", "meaning": "有韧性的", "meaning_source": "ai",
      "ipa": "/rɪˈzɪliənt/", "context": "…she was remarkably resilient…",
      "page": 1, "line": 12, "modified": ["star"] },
    { "id": "m2", "mark": "词", "text": "get the hang of",
      "margin_note": "get the hang of",
      "context": "It took me a while to get the hang of it.",
      "page": 1, "line": 15, "modified": ["star", "produce"] },
    { "id": "m3", "mark": "句", "text": "It took me a while to get the hang of it.",
      "page": 1, "lines": [15, 16], "contains": ["m2"] },
    { "id": "m4", "mark": "段", "text": "（整段文字，逐字给出）…", "page": 1, "lines": [18, 24] },
    { "id": "m5", "mark": "问", "text": "没听清 introduced 后面那个词",
      "marked_by": "dot", "dot_position": "第 20 行 introduced 后", "page": 1, "line": 20 },
    { "id": "m6", "mark": "法", "text": "先抓连接词，再补细节", "page": 1, "line": 22 }
  ]
}
''') as Map).cast<String, Object?>();

  MaterialEnvelope exampleEnvelope() =>
      MaterialEnvelope.fromJson(exampleJson());

  /// 造小信封：只给 items，其它键按需覆盖。
  MaterialEnvelope envelopeOf(
    String itemsJson, {
    Object? protocol = 'mindnet.material/1',
    String batch = batchId,
    String? topic,
    Map<String, Object?>? marks,
    Map<String, Object?>? source,
  }) =>
      MaterialEnvelope.fromJson(<String, Object?>{
        'protocol': protocol,
        'batch_id': batch,
        if (source != null) 'source': source,
        if (topic != null) 'topic': topic,
        if (marks != null) 'marks': marks,
        'items': jsonDecode(itemsJson),
      });

  /// 一条能过所有必填规则的词条目（改一个字段就得到一条针对性用例）。
  String item({
    String id = 'm1',
    String mark = '"词"',
    String text = '"resilient"',
    String extra = '',
  }) =>
      '{"id":"$id","mark":$mark,"text":$text,"margin_note":"x","context":"c",'
      '"page":1,"line":1$extra}';

  Matcher throwsIngest(String substring) => throwsA(
        isA<MaterialIngestException>().having(
          (error) => error.message,
          'message',
          contains(substring),
        ),
      );

  group('文本与 id（对拍 JS）', () {
    test('hash8 是 32 位 FNV-1a，与参考实现逐位相同', () {
      expect(MaterialIngest.hash8('resilient'), 'f40f2384');
      expect(
        MaterialIngest.hash8('It took me a while to get the hang of it.'),
        '9ef4708d',
      );
      expect(MaterialIngest.hash8('（整段文字，逐字给出）…'), '9c90edeb');
      // 大小写与多余空白不影响（都先规范化）。
      expect(MaterialIngest.hash8('  The Hang  '),
          MaterialIngest.hash8('the hang'));
    });

    test('slug 只留字母数字与中日韩字', () {
      expect(MaterialIngest.slug('get the hang of'), 'get-the-hang-of');
      expect(MaterialIngest.slug('先抓连接词，再补细节'), '先抓连接词-再补细节');
      expect(MaterialIngest.slug("It's fine!"), 'its-fine');
      expect(MaterialIngest.slug('…'), '');
    });

    test('记号规范化：词/搭/字母/数字等价，认不出的原样留下', () {
      expect(MaterialIngest.canonMark('词'), 'W');
      expect(MaterialIngest.canonMark('搭'), 'W');
      expect(MaterialIngest.canonMark('w'), 'W');
      expect(MaterialIngest.canonMark('3'), 'S');
      expect(MaterialIngest.canonMark('法'), '法');
      expect(MaterialIngest.canonMark(null), isNull);
      expect(MaterialIngest.writtenMark('词'), '词');
      expect(MaterialIngest.writtenMark('法'), '法');
      expect(MaterialIngest.isCustomMark('词'), isFalse);
      expect(MaterialIngest.isCustomMark('法'), isTrue);
    });

    test('节点 id：内容确定，写「词」还是 W 得到同一个 id', () {
      expect(
        MaterialIngest.nodeId(mark: '词', text: 'resilient'),
        'en::w::resilient',
      );
      expect(
        MaterialIngest.nodeId(mark: 'W', text: 'resilient'),
        'en::w::resilient',
      );
      expect(
        MaterialIngest.nodeId(
          mark: '句',
          text: 'It took me a while to get the hang of it.',
        ),
        'en::s::9ef4708d',
      );
      // 「段」按记号归类（t），不按角色（passage）。
      expect(
        MaterialIngest.nodeId(mark: '段', text: '（整段文字，逐字给出）…'),
        'en::t::9c90edeb',
      );
      // 自定义记号按角色归类：两个不同的自定义记号只要角色与内容一样，只建一个节点。
      expect(
        MaterialIngest.nodeId(mark: '法', text: '先抓连接词，再补细节', role: 'method'),
        'en::method::先抓连接词-再补细节',
      );
      // 自定义记号又没有角色 → x（照样收下，只是 id 空间在别的桶里）。
      expect(MaterialIngest.nodeId(mark: '法', text: 'abc'), 'en::x::abc');
      // 语言前缀来自信封。
      expect(
        MaterialIngest.nodeId(language: 'ZH', mark: '词', text: 'Alpha'),
        'zh::w::alpha',
      );
      expect(MaterialIngest.topicId(topic: 'travel'), 'en::topic::travel');
    });
  });

  group('validate（对拍：示例信封只有一条 dot-mark 告警）', () {
    test('示例信封合法，唯一告警是 m5 的点子通道', () {
      final validation = MaterialIngest.validate(exampleEnvelope());
      expect(validation.warnings, hasLength(1));
      final warning = validation.warnings.single;
      expect(warning.item, 'm5');
      expect(warning.kind, 'dot-mark');
      expect(warning.message, '按你标的点子取的正文内容：第 20 行 introduced 后');
      expect(warning.toString(), contains('[dot-mark] m5'));
    });
  });

  group('graphPatch（对拍：6 节点 / 7 边 / 1 条不进图）', () {
    test('节点 id、类型、名字、modifiers 与参考实现一致', () {
      final patch = MaterialIngest.graphPatch(exampleEnvelope());
      expect(
        <String>[for (final node in patch.nodes) node.id],
        <String>[
          'en::w::resilient',
          'en::w::get-the-hang-of',
          'en::s::9ef4708d',
          'en::t::9c90edeb',
          'en::method::先抓连接词-再补细节',
          'en::topic::travel',
        ],
      );
      expect(
        <String>[for (final node in patch.nodes) node.type],
        <String>[
          'knowledge',
          'knowledge',
          'logic',
          'logic',
          'technique',
          'knowledge',
        ],
      );
      expect(patch.nodes[0].name, 'resilient');
      expect(patch.nodes[1].name, 'get the hang of');
      expect(patch.nodes[2].name, 'It took me a while to get the hang of it.');
      expect(patch.nodes[5].name, '#travel');
      expect(patch.nodes[1].meta['modifiers'], <String>['star', 'produce']);
      expect(patch.nodes[0].meta['modifiers'], <String>['star']);
      expect(patch.nodes[0].meta['meaning'], '有韧性的');
      expect(patch.nodes[0].meta['meaning_source'], 'ai');
      expect(patch.nodes[0].meta['page'], 1.0);
      expect(patch.nodes[0].meta['source'], 'BBC 6 Minute English · 第 3 段');
      expect(patch.nodes[4].meta['mark_means'], '听力方法/套路');
      expect(patch.nodes[5].meta['mark'], 'TOPIC');
    });

    test('7 条边的顺序、端点与 why 与参考实现一致', () {
      final patch = MaterialIngest.graphPatch(exampleEnvelope());
      expect(
        <String>[for (final edge in patch.edges) edge.why],
        <String>[
          'contains',
          'produce',
          'topic',
          'topic',
          'topic',
          'topic',
          'topic',
        ],
      );
      expect(patch.edges[0].id, 'e_en::s::9ef4708d__en::w::get-the-hang-of');
      expect(patch.edges[0].from, 'en::s::9ef4708d');
      expect(patch.edges[0].to, 'en::w::get-the-hang-of');
      expect(patch.edges[0].ls, MaterialIngest.lsSentenceToChunk);
      expect(patch.edges[1].from, 'en::w::get-the-hang-of');
      expect(patch.edges[1].to, 'en::s::9ef4708d');
      expect(patch.edges[1].ls, MaterialIngest.lsChunkToSentence);
      expect(
        <String>[for (final edge in patch.edges.skip(2)) edge.from],
        List<String>.filled(5, 'en::topic::travel'),
      );
      expect(
        <String>[for (final edge in patch.edges.skip(2)) edge.to],
        <String>[
          'en::w::resilient',
          'en::w::get-the-hang-of',
          'en::s::9ef4708d',
          'en::t::9c90edeb',
          'en::method::先抓连接词-再补细节',
        ],
      );
      expect(patch.edges[2].ls, MaterialIngest.lsTopicToItem);
    });

    test('不进图的条目带原因（疑问先答复再决定要不要建节点）', () {
      final patch = MaterialIngest.graphPatch(exampleEnvelope());
      expect(patch.skipped, hasLength(1));
      final skipped = patch.skipped.single;
      expect(skipped.item, 'm5');
      expect(skipped.mark, 'N');
      expect(skipped.role, 'question');
      expect(skipped.reason, '疑问不进图（先答复，再决定是否建节点）');
    });

    test('toJson 的节点/边/跳过三块都在', () {
      final json = MaterialIngest.graphPatch(exampleEnvelope()).toJson();
      expect(json.keys, <String>['nodes', 'edges', 'skipped']);
      expect(json['nodes'], hasLength(6));
      expect(json['edges'], hasLength(7));
      final firstEdge = (json['edges']! as List).first as Map<String, Object?>;
      expect(firstEdge['ls'], 0.6);
      expect(firstEdge['why'], 'contains');
    });
  });

  group('standardItems（对拍：标准清单字段）', () {
    test('句条目：contains / lines / scope', () {
      final items = MaterialIngest.standardItems(exampleEnvelope());
      final sentence = items.firstWhere((item) => item.id == 'm3');
      expect(sentence.mark, 'S');
      expect(sentence.markWritten, '句');
      expect(sentence.role, 'passage');
      expect(sentence.roleKnown, isTrue);
      expect(sentence.inGraph, isTrue);
      expect(sentence.nodeId, 'en::s::9ef4708d');
      expect(sentence.contains, <String>['m2']);
      expect(sentence.line, 15);
      expect(sentence.lines, <double>[15, 16]);
      expect(sentence.scope, 'margin');
    });

    test('段条目：line 取 lines[0]', () {
      final items = MaterialIngest.standardItems(exampleEnvelope());
      final passage = items.firstWhere((item) => item.id == 'm4');
      expect(passage.line, 18);
      expect(passage.inGraph, isTrue);
      expect(passage.nodeId, 'en::t::9c90edeb');
    });

    test('疑问不进图：node_id 为 null，scope 记下"点子通道"', () {
      final items = MaterialIngest.standardItems(exampleEnvelope());
      final question = items.firstWhere((item) => item.id == 'm5');
      expect(question.inGraph, isFalse);
      expect(question.nodeId, isNull);
      expect(question.scope, 'dot');
      expect(question.roleKnown, isTrue);
      expect(question.markWritten, '问');
    });

    test('自定义记号：custom_mark 与 marks 块里的 means 都带出来', () {
      final items = MaterialIngest.standardItems(exampleEnvelope());
      final custom = items.firstWhere((item) => item.id == 'm6');
      expect(custom.customMark, isTrue);
      expect(custom.markWritten, '法');
      expect(custom.markMeans, '听力方法/套路');
      expect(custom.role, 'method');
      expect(custom.nodeId, 'en::method::先抓连接词-再补细节');
    });

    test('toJson 字段名是下划线风格（给 AI/工具读的那份）', () {
      final json =
          MaterialIngest.standardItems(exampleEnvelope()).first.toJson();
      expect(json['mark_written'], '词');
      expect(json['custom_mark'], isFalse);
      expect(json['in_graph'], isTrue);
      expect(json['node_id'], 'en::w::resilient');
      expect(json['meaning_source'], 'ai');
      expect(json['scope'], 'margin');
      expect(json['duplicate_of'], isNull);
    });
  });

  group('runRequest（对拍：14 条动作 + evidence）', () {
    test('请求头：协议、幂等键、时间基、摘要', () {
      final request = MaterialIngest.runRequest(
        exampleEnvelope(),
        nowHours: nowHours,
      );
      expect(request.protocol, MaterialIngest.runProtocol);
      expect(request.runId, 'ingest-$batchId');
      expect(request.time.modelHours, nowHours);
      expect(request.time.wall, '2026-09-25T10:00:00Z');
      expect(request.meta['source'], 'ingest');
      expect(request.meta['note'], '材料批次 $batchId：6 节点 / 7 边');
      expect(request.toJson().keys, <String>[
        'protocol',
        'run_id',
        'time',
        'actions',
        'meta',
      ]);
    });

    test('动作顺序：先全部节点、再全部边、最后 ★ 的 goal', () {
      final request = MaterialIngest.runRequest(
        exampleEnvelope(),
        nowHours: nowHours,
      );
      expect(request.actions, hasLength(14));
      expect(
        <String>[for (final action in request.actions) action.kind],
        <String>[
          'knowledge',
          'knowledge',
          'knowledge',
          'knowledge',
          'knowledge',
          'knowledge',
          'knowledge',
          'knowledge',
          'knowledge',
          'knowledge',
          'knowledge',
          'knowledge',
          'knowledge',
          'goal',
        ],
      );
    });

    test('节点动作带出处：哪一页、哪一行、哪一批', () {
      final request = MaterialIngest.runRequest(
        exampleEnvelope(),
        nowHours: nowHours,
      );
      final first = request.actions.first;
      expect(first.node, <String, Object?>{
        'id': 'en::w::resilient',
        'name': 'resilient',
        'type': 'knowledge',
      });
      expect(first.modelHours, nowHours);
      expect(first.confidence, 0.9);
      expect(first.evidence!['source'], 'dsc_0101.jpg');
      expect(first.evidence!['region'], '第 1 页');
      expect(first.evidence!['batch_id'], batchId);
      // 有意差异之一：这一层真的把页边那一行带进 evidence.quote（JS 恒为 null）。
      expect(first.evidence!['quote'], 'resilient');
    });

    test('hub 的出处写「第 ? 页」（有意差异之二）', () {
      final request = MaterialIngest.runRequest(
        exampleEnvelope(),
        nowHours: nowHours,
      );
      final hub = request.actions.firstWhere(
        (action) => action.node?['id'] == 'en::topic::travel',
      );
      expect(hub.evidence!['region'], '第 ? 页');
      expect(hub.evidence!['quote'], isNull);
      expect(hub.confidence, 0.9);
    });

    test('边动作：端点、权重、why 进 region，且没有 quote 字段', () {
      final request = MaterialIngest.runRequest(
        exampleEnvelope(),
        nowHours: nowHours,
      );
      final contains = request.actions.firstWhere(
        (action) =>
            action.edge?['id'] == 'e_en::s::9ef4708d__en::w::get-the-hang-of',
      );
      expect(contains.edge!['from'], 'en::s::9ef4708d');
      expect(contains.edge!['to'], 'en::w::get-the-hang-of');
      expect(contains.edge!['ls'], 0.6);
      // 动作里的边只有契约那四个键（`why` 只进 region）——对拍时抓出来的差异，钉住。
      expect(contains.edge!.keys, <String>['id', 'from', 'to', 'ls']);
      expect(contains.confidence, 0.8);
      expect(contains.evidence!['region'], '边：contains');
      expect(contains.evidence!.containsKey('quote'), isFalse);
    });

    test('goal 动作：目标只有 ★ 的两个，没有 confidence', () {
      final request = MaterialIngest.runRequest(
        exampleEnvelope(),
        nowHours: nowHours,
      );
      final goal = request.actions.last;
      expect(goal.kind, 'goal');
      expect(goal.targets, <String>[
        'en::w::resilient',
        'en::w::get-the-hang-of',
      ]);
      expect(goal.starts, isNull);
      expect(goal.confidence, isNull);
      expect(goal.evidence!['region'], '★ 高优先级条目');
      expect(goal.evidence!['batch_id'], batchId);
      final json = goal.toJson();
      expect(json.containsKey('starts'), isFalse);
      expect(json.containsKey('confidence'), isFalse);
      expect(json['at'], <String, Object?>{'model_hours': nowHours});
    });

    test('goal 的起点只有显式传了才出现', () {
      final request = MaterialIngest.runRequest(
        exampleEnvelope(),
        nowHours: nowHours,
        starts: <String>['en::topic::travel'],
      );
      expect(request.actions.last.starts, <String>['en::topic::travel']);
      expect(request.actions.last.toJson()['starts'], hasLength(1));
    });

    test('没有 ★ 就不加 goal（只有节点与边）', () {
      final request = MaterialIngest.runRequest(
        envelopeOf('[${item()}]'),
        nowHours: nowHours,
      );
      expect(request.actions, hasLength(1));
      expect(request.actions.single.kind, 'knowledge');
    });

    test('时间基必须显式给：NaN 一律拒绝', () {
      expect(
        () => MaterialIngest.runRequest(
          exampleEnvelope(),
          nowHours: double.nan,
        ),
        throwsIngest('toRunRequest 需要 now_hours'),
      );
    });

    test('同一份信封跑两次逐字节相同（幂等）', () {
      final first =
          MaterialIngest.convert(exampleEnvelope(), nowHours: nowHours);
      final second =
          MaterialIngest.convert(exampleEnvelope(), nowHours: nowHours);
      expect(
        jsonEncode(first.runRequest.toJson()),
        jsonEncode(second.runRequest.toJson()),
      );
      expect(
        jsonEncode(<Object?>[
          for (final entry in first.standardItems) entry.toJson(),
        ]),
        jsonEncode(<Object?>[
          for (final entry in second.standardItems) entry.toJson(),
        ]),
      );
      expect(
        jsonEncode(first.graphPatch.toJson()),
        jsonEncode(second.graphPatch.toJson()),
      );
    });

    test('toJson → fromJson 往返之后仍然自洽', () {
      final request = MaterialIngest.runRequest(
        exampleEnvelope(),
        nowHours: nowHours,
      );
      final restored = MaterialRunRequest.fromJson(request.toJson());
      expect(restored.protocol, MaterialIngest.runProtocol);
      expect(restored.runId, request.runId);
      expect(restored.time.modelHours, nowHours);
      expect(restored.actions, hasLength(14));
      expect(MaterialIngest.checkRunRequest(restored).ok, isTrue);
    });

    test('convert 汇总：6 条 → 6 节点 / 7 边 · 14 动作 · 1 告警', () {
      final conversion =
          MaterialIngest.convert(exampleEnvelope(), nowHours: nowHours);
      expect(conversion.summary.items, 6);
      expect(conversion.summary.nodes, 6);
      expect(conversion.summary.edges, 7);
      expect(conversion.summary.actions, 14);
      expect(conversion.summary.skipped, 1);
      expect(conversion.summary.warnings, 1);
      expect(conversion.summary.batchId, batchId);
      expect(
        conversion.summary.text,
        '批次 $batchId：6 条 → 6 节点 / 7 边 · 14 条动作 · 1 条告警',
      );
      expect(conversion.standardItems, hasLength(6));
      expect(conversion.warnings, hasLength(1));
    });
  });

  group('validate 报错族（整份拒绝，绝不半途生效）', () {
    test('协议不对', () {
      expect(
        () =>
            MaterialIngest.validate(envelopeOf('[${item()}]', protocol: 'x/1')),
        throwsIngest('protocol 必须是 "mindnet.material/1"'),
      );
    });

    test('缺 batch_id', () {
      expect(
        () => MaterialIngest.validate(envelopeOf('[${item()}]', batch: '')),
        throwsIngest('缺少 batch_id（幂等键）'),
      );
    });

    test('items 空数组', () {
      expect(
        () => MaterialIngest.validate(envelopeOf('[]')),
        throwsIngest('items 必须是非空数组'),
      );
    });

    test('第 N 条不是对象', () {
      expect(
        () => MaterialIngest.validate(envelopeOf('[1]')),
        throwsIngest('第 1 条 item 不是对象'),
      );
    });

    test('缺 id / id 重复', () {
      expect(
        () => MaterialIngest.validate(
          envelopeOf('[{"mark":"词","text":"t","page":1,"line":1}]'),
        ),
        throwsIngest('第 1 条 item 缺少 id'),
      );
      expect(
        () => MaterialIngest.validate(envelopeOf('[${item()},${item()}]')),
        throwsIngest('的 id "m1" 与前面的重复'),
      );
    });

    test('缺 mark（记号可以自己发明，但不能空着）', () {
      expect(
        () => MaterialIngest.validate(
          envelopeOf('[{"id":"m1","text":"t","page":1,"line":1}]'),
        ),
        throwsIngest('缺少 mark（你写的那个记号）'),
      );
    });

    test('缺 text', () {
      expect(
        () => MaterialIngest.validate(
          envelopeOf('[{"id":"m1","mark":"词","page":1,"line":1}]'),
        ),
        throwsIngest('缺少 text'),
      );
    });

    test('缺 page / 缺 line：缺席与显式 null 不是一回事', () {
      expect(
        () => MaterialIngest.validate(
          envelopeOf(
            '[{"id":"m1","mark":"词","text":"t","margin_note":"x","context":"c",'
            '"line":1}]',
          ),
        ),
        throwsIngest('缺少 page'),
      );
      expect(
        () => MaterialIngest.validate(
          envelopeOf(
            '[{"id":"m1","mark":"词","text":"t","margin_note":"x","context":"c",'
            '"page":1}]',
          ),
        ),
        throwsIngest('缺少 line 或 lines'),
      );
      expect(
        () => MaterialIngest.validate(
          envelopeOf(
            '[{"id":"m1","mark":"词","text":"t","margin_note":"x","context":"c",'
            '"page":1,"lines":[3]}]',
          ),
        ),
        throwsIngest('缺少 line 或 lines'),
      );
    });

    test('显式 page:null 按 JS 的 Number(null)=0 收下（钉住这个怪癖）', () {
      final envelope = envelopeOf(
        '[{"id":"m1","mark":"词","text":"t","margin_note":"x","context":"c",'
        '"page":null,"line":1}]',
      );
      expect(MaterialIngest.validate(envelope).warnings, isEmpty);
      expect(
        MaterialIngest.standardItems(envelope).single.page,
        0,
      );
    });

    test('页边三通道：不抄又不说清 → 报错；说明白就收', () {
      expect(
        () => MaterialIngest.validate(
          envelopeOf(
            '[{"id":"m1","mark":"词","text":"t","context":"c","page":1,"line":1}]',
          ),
        ),
        throwsIngest('缺少 margin_note'),
      );
      for (final channel in <String>[
        '"inferred_from_line":true',
        '"marked_by":"dot","dot_position":"第 3 行"',
      ]) {
        final envelope = envelopeOf(
          '[{"id":"m1","mark":"词","text":"t","context":"c","page":1,"line":1,'
          '$channel}]',
        );
        expect(MaterialIngest.validate(envelope).warnings, hasLength(1));
      }
    });

    test('词条目缺 context（例句来源）', () {
      expect(
        () => MaterialIngest.validate(
          envelopeOf(
            '[{"id":"m1","mark":"词","text":"t","margin_note":"x","page":1,"line":1}]',
          ),
        ),
        throwsIngest('缺少 context'),
      );
    });

    test('contains 非数组 / 指向批次外', () {
      expect(
        () => MaterialIngest.validate(
          envelopeOf(
            '[{"id":"m1","mark":"句","text":"s","page":1,"line":1,'
            '"contains":"m2"}]',
          ),
        ),
        throwsIngest('的 contains 必须是数组'),
      );
      expect(
        () => MaterialIngest.validate(
          envelopeOf(
            '[{"id":"m1","mark":"句","text":"s","page":1,"line":1,'
            '"contains":["nope"]}]',
          ),
        ),
        throwsIngest('contains 指向不存在的 id "nope"'),
      );
    });

    test('modified 非数组', () {
      expect(
        () => MaterialIngest.validate(
          envelopeOf('[${item(extra: ',"modified":"star"')}]'),
        ),
        throwsIngest('的 modified 必须是数组'),
      );
    });
  });

  group('告警族（只是记录，不阻止入库）', () {
    MaterialWarning only(MaterialEnvelope envelope) =>
        MaterialIngest.validate(envelope).warnings.single;

    test('unknown-mark：不认识的记号先按"未分类"收下', () {
      final warning = only(
        envelopeOf(
          '[{"id":"m1","mark":"坑","text":"t","page":1,"line":1}]',
        ),
      );
      expect(warning.kind, 'unknown-mark');
      expect(warning.message, contains('记号「坑」不在内置表里'));
      // 收下了，只是不进图。
      final patch = MaterialIngest.graphPatch(
        envelopeOf('[{"id":"m1","mark":"坑","text":"t","page":1,"line":1}]'),
      );
      expect(patch.nodes, isEmpty);
      expect(patch.skipped.single.role, 'other');
      expect(patch.skipped.single.reason, startsWith('角色「other」不进图'));
    });

    test('custom-role：声明了契约不认识的角色', () {
      final warning = only(
        envelopeOf(
          '[{"id":"m1","mark":"法","text":"t","page":1,"line":1}]',
          marks: <String, Object?>{
            '法': <String, Object?>{'role': 'mystery', 'means': '说不清'},
          },
        ),
      );
      expect(warning.kind, 'custom-role');
      expect(warning.message, contains('自定义角色「mystery」'));
    });

    test('custom-modifier：修饰符也开放，原样保留', () {
      final warning = only(
        envelopeOf('[${item(extra: ',"modified":["star","mystery"]')}]'),
      );
      expect(warning.kind, 'custom-modifier');
      expect(warning.message, contains('自定义修饰符「mystery」'));
    });

    test('duplicate-text：同一条文字出现两次（没标 duplicate_of）', () {
      final envelope = envelopeOf(
        '[${item()},${item(id: 'm2', extra: ',"page":2,"line":9')}]',
      );
      expect(MaterialIngest.validate(envelope).warnings, hasLength(1));
      expect(
        MaterialIngest.validate(envelope).warnings.single.kind,
        'duplicate-text',
      );
    });

    test('uncertain / conflict：上游标的不确定与冲突都带位置', () {
      final uncertain = only(
        envelopeOf('[${item(extra: ',"uncertain":true,"region":"第 7 行"')}]'),
      );
      expect(uncertain.kind, 'uncertain');
      expect(uncertain.message, contains('第 7 行'));
      final conflict = only(
        envelopeOf(
          '[${item(extra: ',"conflict":true,"conflict_detail":"页边写的是别的词"')}]',
        ),
      );
      expect(conflict.kind, 'conflict');
      expect(conflict.message, contains('页边写的是别的词'));
    });

    test('inferred-scope：省力通道要被记录下来', () {
      final warning = only(
        envelopeOf(
          '[{"id":"m1","mark":"词","text":"t","context":"c","page":1,"line":1,'
          '"inferred_from_line":true}]',
        ),
      );
      expect(warning.kind, 'inferred-scope');
    });
  });

  group('角色优先级与 duplicate_of', () {
    test('条目级 role 覆盖内置记号（去向跟着 role，节点 id 还是按记号桶）', () {
      final envelope = envelopeOf(
        '[{"id":"m1","mark":"问","role":"item","text":"t","margin_note":"x",'
        '"context":"c","page":1,"line":1}]',
      );
      final standard = MaterialIngest.standardItems(envelope).single;
      expect(standard.role, 'item');
      expect(standard.inGraph, isTrue);
      expect(standard.nodeId, 'en::n::t');
      final node = MaterialIngest.graphPatch(envelope).nodes.single;
      expect(node.type, 'knowledge');
    });

    test('marks 声明决定自定义记号去哪', () {
      final method = MaterialIngest.graphPatch(
        envelopeOf(
          '[{"id":"m1","mark":"法","text":"先抓连接词","page":1,"line":1}]',
          marks: <String, Object?>{
            '法': <String, Object?>{'role': 'method'},
          },
        ),
      );
      expect(method.nodes.single.type, 'technique');
      expect(method.nodes.single.id, 'en::method::先抓连接词');
      expect(
        method.nodes.single.meta['mark_means'],
        isNull,
      );
    });

    test('duplicate_of：复用被指向的节点 id，并且后续边能穿过它', () {
      final envelope = envelopeOf(r'''
[
  {"id":"m1","mark":"词","text":"alpha","margin_note":"alpha","context":"c","page":1,"line":1},
  {"id":"m2","mark":"句","text":"A sentence.","page":1,"line":2,"contains":["m1"]},
  {"id":"m3","mark":"词","text":"alpha","margin_note":"alpha","context":"c","page":1,"line":3,"duplicate_of":"m1"},
  {"id":"m4","mark":"句","text":"Another one.","page":1,"line":4,"contains":["m3"]}
]
''');
      final patch = MaterialIngest.graphPatch(envelope);
      expect(<String>[for (final node in patch.nodes) node.id], hasLength(3));
      expect(patch.skipped.single.item, 'm3');
      expect(patch.skipped.single.reason, '与 m1 重复');
      // m4 的 contains 指向 m3，而 m3 复用 m1 的节点 ⇒ 边落到 m1 的节点上。
      expect(
        <String>[for (final edge in patch.edges) '${edge.from}->${edge.to}'],
        <String>[
          'en::s::${MaterialIngest.hash8('A sentence.')}->en::w::alpha',
          'en::s::${MaterialIngest.hash8('Another one.')}->en::w::alpha',
        ],
      );
      expect(MaterialIngest.validate(envelope).warnings, isEmpty);
    });
  });

  group('checkRunRequest（io_check 类校验：只校验不执行）', () {
    test('材料批次自己的请求合法：影子图让"先建节点再建边"成立', () {
      final request = MaterialIngest.runRequest(
        exampleEnvelope(),
        nowHours: nowHours,
      );
      final check = MaterialIngest.checkRunRequest(request);
      expect(check.ok, isTrue);
      expect(check.errors, isEmpty);
      expect(check.previews, hasLength(14));
      expect(check.evidenceCount, 14);
      expect(check.summary, contains('请求合法'));
      expect(check.previews.first, contains('新增节点 en::w::resilient'));
      expect(
        check.previews.firstWhere((line) => line.contains('[goal]')),
        contains('en::w::resilient、en::w::get-the-hang-of'),
      );
    });

    test('要建的节点已经存在 → 报错（材料入库应当幂等）', () {
      final request = MaterialIngest.runRequest(
        exampleEnvelope(),
        nowHours: nowHours,
      );
      final check = MaterialIngest.checkRunRequest(
        request,
        existingNodeIds: const <String>{'en::w::resilient'},
      );
      expect(check.ok, isFalse);
      expect(check.errors.single, contains('已经存在'));
      expect(check.errors.single, contains('en::w::resilient'));
    });

    test('边的端点必须在图里（含本批次新建的）', () {
      const request = MaterialRunRequest(
        runId: 'r1',
        time: MaterialRunTime(modelHours: 100),
        actions: <MaterialRunAction>[
          MaterialRunAction(
            kind: 'knowledge',
            node: <String, Object?>{
              'id': 'a',
              'name': 'A',
              'type': 'knowledge'
            },
            modelHours: 100,
          ),
          MaterialRunAction(
            kind: 'knowledge',
            edge: <String, Object?>{
              'id': 'e1',
              'from': 'a',
              'to': 'b',
              'ls': 0.6
            },
            modelHours: 100,
          ),
        ],
      );
      final check = MaterialIngest.checkRunRequest(request);
      expect(check.ok, isFalse);
      expect(check.errors.single, contains('边终点 "b" 不在图里'));
    });

    test('goal 必须给非空 targets，且目标都在图里', () {
      const empty = MaterialRunRequest(
        runId: 'r1',
        time: MaterialRunTime(modelHours: 100),
        actions: <MaterialRunAction>[
          MaterialRunAction(
            kind: 'goal',
            targets: <String>[],
            modelHours: 100,
          ),
        ],
      );
      expect(
        MaterialIngest.checkRunRequest(empty).errors.single,
        contains('必须给非空的 targets 数组'),
      );
      const missing = MaterialRunRequest(
        runId: 'r1',
        time: MaterialRunTime(modelHours: 100),
        actions: <MaterialRunAction>[
          MaterialRunAction(
            kind: 'goal',
            targets: <String>['nope'],
            modelHours: 100,
          ),
        ],
      );
      expect(
        MaterialIngest.checkRunRequest(missing).errors.single,
        contains('目标 "nope" 不在图里'),
      );
    });

    test('协议 / 幂等键 / 时间基三样缺一不可', () {
      expect(
        MaterialIngest.checkRunRequest(
          const MaterialRunRequest(
            protocol: 'mindnet.run/0',
            runId: 'r1',
            time: MaterialRunTime(modelHours: 100),
            actions: <MaterialRunAction>[],
          ),
        ).errors.single,
        contains('protocol 必须是 "mindnet.run/1"'),
      );
      expect(
        MaterialIngest.checkRunRequest(
          const MaterialRunRequest(
            runId: '',
            time: MaterialRunTime(modelHours: 100),
            actions: <MaterialRunAction>[],
          ),
        ).errors.single,
        contains('缺少 run_id'),
      );
      expect(
        MaterialIngest.checkRunRequest(
          const MaterialRunRequest(
            runId: 'r1',
            time: MaterialRunTime(modelHours: double.nan),
            actions: <MaterialRunAction>[],
          ),
        ).errors.single,
        contains('time.model_hours 必须是数字'),
      );
    });

    test('knowledge 要么给节点要么给边；动作必须有时基与已知 kind', () {
      expect(
        MaterialIngest.checkRunRequest(
          const MaterialRunRequest(
            runId: 'r1',
            time: MaterialRunTime(modelHours: 100),
            actions: <MaterialRunAction>[
              MaterialRunAction(kind: 'knowledge', modelHours: 100),
            ],
          ),
        ).errors.single,
        contains('要么给 node（新知识点）要么给 edge（新连接）'),
      );
      expect(
        MaterialIngest.checkRunRequest(
          const MaterialRunRequest(
            runId: 'r1',
            time: MaterialRunTime(modelHours: 100),
            actions: <MaterialRunAction>[
              MaterialRunAction(kind: 'nonsense', modelHours: 100),
            ],
          ),
        ).errors.single,
        contains('kind 必须是'),
      );
      expect(
        MaterialIngest.checkRunRequest(
          const MaterialRunRequest(
            runId: 'r1',
            time: MaterialRunTime(modelHours: 100),
            actions: <MaterialRunAction>[
              MaterialRunAction(
                kind: 'goal',
                targets: <String>['a'],
              ),
            ],
          ),
        ).errors,
        containsAll(<String>[
          '第 1 条 action（goal）缺少时间基：至少要 at.model_hours'
              '（time 动作也可以用 elapsed_hours）',
          '第 1 条 action（goal）的目标 "a" 不在图里',
        ]),
      );
    });

    test('空 actions 结构上合法（与 io_check 一致）', () {
      final check = MaterialIngest.checkRunRequest(
        const MaterialRunRequest(
          runId: 'r1',
          time: MaterialRunTime(modelHours: 100),
          actions: <MaterialRunAction>[],
        ),
      );
      expect(check.ok, isTrue);
      expect(check.previews, isEmpty);
      expect(check.evidenceCount, 0);
    });

    test('要建的边已经存在 → 报错；没有 id 的边允许（引擎会自动编号）', () {
      const request = MaterialRunRequest(
        runId: 'r1',
        time: MaterialRunTime(modelHours: 100),
        actions: <MaterialRunAction>[
          MaterialRunAction(
            kind: 'knowledge',
            node: <String, Object?>{
              'id': 'a',
              'name': 'A',
              'type': 'knowledge'
            },
            modelHours: 100,
          ),
          MaterialRunAction(
            kind: 'knowledge',
            node: <String, Object?>{
              'id': 'b',
              'name': 'B',
              'type': 'knowledge'
            },
            modelHours: 100,
          ),
        ],
      );
      expect(MaterialIngest.checkRunRequest(request).ok, isTrue);
      final duplicate = MaterialIngest.checkRunRequest(
        request,
        existingEdgeIds: const <String>{'e_a__b'},
      );
      // 这份请求里的节点动作没有边，所以 existingEdgeIds 不会误报。
      expect(duplicate.ok, isTrue);
    });
  });
}
