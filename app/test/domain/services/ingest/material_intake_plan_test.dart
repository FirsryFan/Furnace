/// 材料摄取应用侧计划的测试（`docs/MINDNET_ROADMAP.md` §2-C ① / §3 第 6 行）。
///
/// 上游（`material_ingest.dart`）的输出值已经被别处逐字段钉住（56 例 + 与 MindNet
/// 参考实现的对拍），所以这里不重复钉 hash/节点 id 的**具体值**，只钉这一层新加的判断：
/// 进图的条目变成知识点提案、边变成连接提案、主题分组默认只报不建、同名标"不重复建"、
/// 不进图的条目留在清单外并带原因、同一份信封两次得到同一份 JSON。
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/ingest/material_ingest.dart';
import 'package:furnace/domain/services/ingest/material_intake_plan.dart';

/// 一份三行材料：一个句子、它里面要记的搭配、一个不进图的疑问。
List<Map<String, Object?>> threeItems() => <Map<String, Object?>>[
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
        'modified': <String>['star'],
        // `produce: true` 是上游生成反向边（词 → 句）的条件（与 `modified: ['produce']` 同义）。
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
    ];

Map<String, Object?> envelopeJson({
  String batch = 'b-1',
  String? topic = 'travel',
  List<Map<String, Object?>>? items,
}) =>
    <String, Object?>{
      'protocol': 'mindnet.material/1',
      'batch_id': batch,
      'source': <String, Object?>{
        'kind': 'book',
        'refs': <String>['词汇书 p12'],
        'material': '词汇书',
      },
      if (topic != null) 'topic': topic,
      'language': 'en',
      'items': items ?? threeItems(),
    };

MaterialIntakePlan planOf(
  Map<String, Object?> json, {
  Set<String> existingTitles = const <String>{},
  bool includeTopicHubs = false,
}) {
  final envelope = MaterialEnvelope.fromJson(json);
  final conversion = MaterialIngest.convert(envelope, nowHours: 497321.25);
  return MaterialIntakePlanner.plan(
    conversion,
    envelope: envelope,
    existingTitles: existingTitles,
    includeTopicHubs: includeTopicHubs,
  );
}

MaterialIntakeProposal proposalOf(MaterialIntakePlan plan, String id) =>
    plan.proposals.firstWhere((p) => p.id == id);

void main() {
  group('知识点提案（进图的条目）', () {
    test('进图的条目变成知识点提案，不进图的留清单外', () {
      final plan = planOf(envelopeJson());

      // 句子 + 搭配两个知识点；contains / produce 两条连接；主题边与疑问留在外面。
      expect(plan.newPoints, 2);
      expect(plan.connections, 2);
      expect(plan.skippedCount, 3);
      expect(plan.isEmpty, isFalse);
      expect(plan.text, contains('批次 b-1：要建 2 个知识点'));
      expect(plan.text, contains('2 条连接'));
      expect(plan.text, contains('3 条留在清单外'));

      final ids = plan.proposals.map((p) => p.id).toList();
      expect(ids, contains('kp:en::w::rely-on'));
      expect(
        ids.where((id) => id.startsWith('kp:en::s::')).length,
        1,
        reason: '句子进图，节点 id 用 en::s::<hash>',
      );
      expect(ids.where((id) => id.startsWith('edge:e_')).length, 2);
    });

    test('词提案：标题、正文（释义/原文/出处）、理由与出处都带全', () {
      final plan = planOf(envelopeJson());
      final proposal = proposalOf(plan, 'kp:en::w::rely-on');

      expect(proposal.kind, MaterialIntakeKind.knowledgePoint);
      expect(proposal.title, 'rely on');
      expect(proposal.nodeId, 'en::w::rely-on');
      expect(proposal.exists, isFalse);
      expect(proposal.body, contains('释义：依靠'));
      expect(proposal.body, contains('原文：I relied on him.'));
      expect(proposal.body, contains('出处：词汇书，第 12 页，页边：搭配'));
      expect(proposal.why, contains('材料里标了「词」（要能复习的单元）'));
      expect(proposal.why, contains('★ 高优先级'));

      expect(proposal.evidence.source, '词汇书');
      expect(proposal.evidence.page, 12);
      expect(proposal.evidence.region, '第 12 页');
      expect(proposal.evidence.quote, '搭配');
      expect(proposal.evidence.batchId, 'b-1');
    });

    test('句提案：标题是整句，理由说"整句/整段"', () {
      final plan = planOf(envelopeJson());
      final sentence = plan.proposals.firstWhere(
        (p) =>
            p.kind == MaterialIntakeKind.knowledgePoint &&
            p.id.startsWith('kp:en::s::'),
      );

      expect(sentence.title, 'I relied on him.');
      expect(sentence.why, contains('「句」（整句/整段）'));
      expect(sentence.body, contains('出处：词汇书，第 12 页，页边：整句要能说出来'));
    });

    test('AI 给的释义标"待核对"', () {
      final items = threeItems();
      items[1]['meaning_source'] = 'ai';
      final plan = planOf(envelopeJson(items: items));

      expect(
        proposalOf(plan, 'kp:en::w::rely-on').body,
        contains('释义：依靠（待核对）'),
      );
    });

    test('同名知识点已存在 ⇒ 标 exists，不算进"要建"', () {
      // 调用方给的是库里原样的标题（大小写/空白不该骗过去）。
      final plan = planOf(
        envelopeJson(),
        existingTitles: <String>{'  Rely   ON '},
      );

      expect(proposalOf(plan, 'kp:en::w::rely-on').exists, isTrue);
      expect(plan.existingPoints, 1);
      expect(plan.newPoints, 1);
      expect(plan.text, contains('其中 1 个已存在，不重复建'));
    });
  });

  group('连接提案（边）', () {
    test('contains / produce 各一条，带强度与两端节点 id', () {
      final plan = planOf(envelopeJson());
      final connections = plan.proposals
          .where((p) => p.kind == MaterialIntakeKind.connection)
          .toList();

      final containsEdge =
          connections.firstWhere((c) => c.why.contains('句子里包含它'));
      expect(containsEdge.id, startsWith('edge:e_'));
      expect(containsEdge.title, 'I relied on him. → rely on');
      expect(containsEdge.from, startsWith('en::s::'));
      expect(containsEdge.to, 'en::w::rely-on');
      expect(containsEdge.ls, 0.6);
      expect(containsEdge.exists, isFalse);
      expect(containsEdge.evidence.region, '边：contains');

      final produceEdge =
          connections.firstWhere((c) => c.why.contains('用它造出这句话'));
      expect(produceEdge.from, 'en::w::rely-on');
      expect(produceEdge.to, startsWith('en::s::'));
      expect(produceEdge.evidence.region, '边：produce');
    });

    test('主题边默认只报不建，原因写明关联类型未定', () {
      final plan = planOf(envelopeJson());
      final topicSkips =
          plan.skipped.where((s) => s.reason.contains('关联类型未定')).toList();

      expect(topicSkips.length, 2, reason: 'hub → 句子、hub → 词，两条主题边');
      expect(topicSkips.first.reason, contains('roadmap §2-C ④'));
      expect(
        plan.proposals.any((p) =>
            p.kind == MaterialIntakeKind.connection && p.why.contains('主题分组')),
        isFalse,
      );
    });

    test('includeTopicHubs: true 时主题也当知识点、主题边也变成连接', () {
      final plan = planOf(envelopeJson(), includeTopicHubs: true);

      expect(plan.newPoints, 3);
      expect(plan.connections, 4);
      expect(plan.skippedCount, 1, reason: '只剩那条疑问');
      expect(
        plan.proposals.map((p) => p.id),
        contains('kp:en::topic::travel'),
      );
    });
  });

  group('留在清单外的条目', () {
    test('疑问不进图，但留在清单外并带原因（不是丢掉）', () {
      final plan = planOf(envelopeJson());
      final question = plan.skipped.firstWhere((s) => s.ref == 'm3');

      expect(question.reason, contains('疑问不进图'));
      expect(plan.proposals.any((p) => p.title.contains('depend on')), isFalse);
    });

    test('只有一条疑问 ⇒ 计划是空的，但说清楚为什么', () {
      final plan = planOf(envelopeJson(items: <Map<String, Object?>>[
        <String, Object?>{
          'id': 'm1',
          'mark': '问',
          'text': '为什么？',
          'page': 1,
          'line': 1,
          'margin_note': '先别建点',
        },
      ]));

      expect(plan.isEmpty, isTrue);
      expect(plan.proposals, isEmpty);
      expect(plan.skippedCount, 1);
      expect(plan.text, contains('没有要动的东西'));
    });

    test('没有主题的分组边时不会多出 skipped', () {
      final plan = planOf(envelopeJson(topic: null));

      expect(plan.connections, 2);
      expect(plan.skippedCount, 1, reason: '只剩那条疑问');
    });
  });

  group('归一与序列化', () {
    test('normalizeTitle：去首尾空白、压空白、转小写', () {
      expect(MaterialIntakePlanner.normalizeTitle('  Rely   ON '), 'rely on');
      expect(MaterialIntakePlanner.normalizeTitle('A\nB'), 'a b');
      expect(MaterialIntakePlanner.normalizeTitle('rely on'), 'rely on');
    });

    test('toJson 带计数、人话与明细；同一份信封两次逐字节相同', () {
      final first = planOf(envelopeJson());
      final second = planOf(envelopeJson());
      final json = first.toJson();

      expect(jsonEncode(json), jsonEncode(second.toJson()));
      expect(json['batch_id'], 'b-1');
      expect(json['topic'], 'travel');
      expect(json['source'], '词汇书');
      expect(json['new_points'], 2);
      expect(json['existing_points'], 0);
      expect(json['connections'], 2);
      expect(json['skipped_count'], 3);
      expect(json['text'], isA<String>());
      expect((json['proposals'] as List).length, 4);
      expect((json['skipped'] as List).length, 3);

      final proposal =
          (json['proposals'] as List).cast<Map<String, Object?>>().firstWhere(
                (p) => p['id'] == 'kp:en::w::rely-on',
              );
      expect(proposal['kind'], 'knowledge_point');
      expect(proposal['node_id'], 'en::w::rely-on');
      expect(proposal['exists'], isFalse);
      expect((proposal['evidence'] as Map)['page'], 12);
      expect((proposal['evidence'] as Map)['quote'], '搭配');
    });
  });
}
