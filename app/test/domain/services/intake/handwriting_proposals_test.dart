/// 拍照整理的领域层验收：`docs/QUESTION_BANK_DESIGN.md` §7.3–§7.4。
///
/// 这一组测试盯着三件读代码时最容易"看着对、其实不对"的事：
///
///  1. **只整理、不编造**——提示词里必须带上"照片里没有的不许写"这条铁律，
///     以及"现在有什么"（已有标签路径、已有知识点标题），否则模型会造新树。
///  2. **解析是严格的**——结构性错误一律抛异常，不静默丢条（少写一条而用户以为
///     整理完了，比直接报错更糟）。
///  3. **缺省的 confidence 是 0.5（不知道）**，不是 1.0（很确定）。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/intake/handwriting_proposals.dart';

void main() {
  group('提示词', () {
    test('两条消息：system 讲铁律与契约，user 带图', () {
      final messages = handwritingProposalMessages(
        fileName: 'hw-1/page.png',
        mime: 'image/png',
        base64: 'QUJD',
        existingTagPaths: const ['文化课/物理/力学'],
        existingKnowledgePointTitles: const ['动量守恒的条件'],
      );

      expect(messages, hasLength(2));
      expect(messages.first.role, isNot('user'));

      final system = messages.first.content ?? '';
      expect(system, isNotEmpty);
      expect(system, contains('只整理照片里'));
      expect(system, contains('不许'));
      expect(system, contains('文化课/物理/力学'));
      expect(system, contains('动量守恒的条件'));
      expect(system, contains(handwritingProposalJsonContract));
      for (final kind in HandwritingProposalKind.values) {
        expect(system, contains(kind.storageKey));
      }

      final user = messages.last;
      expect(user.content ?? '', contains('hw-1/page.png'));
      expect(user.images, hasLength(1));
      expect(user.images.single.mime, 'image/png');
      expect(user.images.single.base64, 'QUJD');
    });

    test('库里还没有标签/知识点时，提示词如实说"还没有"', () {
      final messages = handwritingProposalMessages(
        fileName: 'x.jpg',
        mime: 'image/jpeg',
        base64: 'QQ==',
      );
      final system = messages.first.content;
      expect(system, contains('标签树现在还是空的'));
      expect(system, contains('还没有知识点'));
    });
  });

  group('解析', () {
    const threeKinds = '''
寒暄一句：这是我的整理结果。
```json
{
  "proposals": [
    {"kind": "tag", "title": "动量守恒", "rationale": "照片里反复出现",
     "confidence": 0.8, "fields": {"parent_path": "文化课/物理/力学", "description": "定义"}},
    {"kind": "knowledge_point", "title": "动量守恒的条件",
     "fields": {"content": "合外力为零", "tag_path": "文化课/物理/力学/动量守恒"}},
    {"kind": "flashcard", "title": "动量守恒", "confidence": 0.9,
     "fields": {"content": "正文"},
     "cards": [{"question": "条件是什么？", "answer": "合外力为零。", "type": "fill_blank"}]}
  ]
}
```
''';

    test('三类产物都能解析，id 确定性、字段与卡片齐全', () {
      final set = parseHandwritingProposals(threeKinds, sourceRef: 'hw/1.png');

      expect(set.sourceRef, 'hw/1.png');
      expect(set.isEmpty, isFalse);
      expect(set.proposals, hasLength(3));
      expect(
        set.proposals.map((p) => p.kind),
        [
          HandwritingProposalKind.tag,
          HandwritingProposalKind.knowledgePoint,
          HandwritingProposalKind.flashcard,
        ],
      );
      expect(
        set.proposals.map((p) => p.id),
        ['tag-0', 'knowledge_point-1', 'flashcard-2'],
      );
      expect(set.countOf(HandwritingProposalKind.tag), 1);
      expect(set.countOf(HandwritingProposalKind.flashcard), 1);

      final tag = set.proposals[0];
      expect(tag.titleZh, '动量守恒');
      expect(tag.rationaleZh, '照片里反复出现');
      expect(tag.confidence, 0.8);
      expect(tag.fields['parent_path'], '文化课/物理/力学');

      final point = set.proposals[1];
      expect(point.fields['content'], '合外力为零');
      // 没写 confidence = 不知道，而不是"很确定"。
      expect(point.confidence, defaultProposalConfidence);
      expect(point.confidence, 0.5);

      final card = set.proposals[2];
      expect(card.cards, hasLength(1));
      expect(card.cards.single.question, '条件是什么？');
      expect(card.cards.single.answer, '合外力为零。');
      expect(card.cards.single.type, 'fill_blank');

      // 两次解析必须得到同样的 id（同一张照片重跑不会漂移）。
      final again =
          parseHandwritingProposals(threeKinds, sourceRef: 'hw/1.png');
      expect(
        again.proposals.map((p) => p.id).toList(),
        set.proposals.map((p) => p.id).toList(),
      );

      final json = set.toJson();
      expect(json['source_ref'], 'hw/1.png');
      expect(
        (json['proposals'] as List).cast<Map<String, Object?>>().first['kind'],
        'tag',
      );
    });

    test('空数组是合法结果：照片里没有可整理的东西', () {
      final set = parseHandwritingProposals(
        '{"proposals": []}',
        sourceRef: 'hw/2.png',
      );
      expect(set.isEmpty, isTrue);
      expect(set.proposals, isEmpty);
    });

    test('卡片默认题型是 essay（与知识模块默认一致）', () {
      final set = parseHandwritingProposals('''
{"proposals": [{"kind": "flashcard", "title": "T",
 "fields": {"content": "C"},
 "cards": [{"question": "Q", "answer": "A"}]}]}
''', sourceRef: 'hw/3.png');
      expect(set.proposals.single.cards.single.type, 'essay');
    });

    test('confidence 是字符串数字也认；越界钳到 0..1', () {
      final set = parseHandwritingProposals('''
{"proposals": [
 {"kind": "tag", "title": "A", "confidence": "0.25"},
 {"kind": "tag", "title": "B", "confidence": 7},
 {"kind": "tag", "title": "C", "confidence": -3}
]}
''', sourceRef: 'hw/4.png');
      expect(
        set.proposals.map((p) => p.confidence),
        [0.25, 1.0, 0.0],
      );
    });

    group('结构性错误一律报错，不静默降级', () {
      void expectThrows(String raw, Object messagePart) {
        expect(
          () => parseHandwritingProposals(raw, sourceRef: 'hw/x.png'),
          throwsA(
            isA<HandwritingProposalParseException>().having(
              (error) => error.message,
              'message',
              contains(messagePart.toString()),
            ),
          ),
        );
      }

      test('找不到 JSON / 顶层不是对象 / 缺 proposals', () {
        expectThrows('模型今天不想说话', '找不到 JSON 对象');
        expectThrows('最后只有一个 } 收尾 {', '找不到 JSON 对象');
        expectThrows('{"foo": 1}', 'proposals');
        expectThrows('{"proposals": {"kind": "tag"}}', 'proposals');
        expectThrows('{"proposals": [1]}', 'proposals[0]` 不是对象');
        expectThrows(
          '{"proposals": [{"kind": "tag", "title": "T", "fields": 7}]}',
          'fields',
        );
      });

      test('kind 未知要列出可用取值；title 不能空', () {
        expectThrows(
          '{"proposals": [{"kind": "question", "title": "x"}]}',
          'tag / knowledge_point / flashcard',
        );
        expectThrows(
          '{"proposals": [{"kind": "tag", "title": "  "}]}',
          '缺少 title',
        );
      });

      test('知识点必须有 content（正文来自照片）', () {
        expectThrows(
          '{"proposals": [{"kind": "knowledge_point", "title": "T"}]}',
          'fields.content',
        );
      });

      test('闪存卡必须有卡片、卡片必须完整、题型必须在册', () {
        expectThrows(
          '{"proposals": [{"kind": "flashcard", "title": "T", "fields": {"content": "C"}}]}',
          '复习队列',
        );
        expectThrows(
          '{"proposals": [{"kind": "flashcard", "title": "T", "fields": {"content": "C"}, "cards": []}]}',
          'cards',
        );
        expectThrows(
          '{"proposals": [{"kind": "flashcard", "title": "T", "fields": {"content": "C"}, '
              '"cards": [{"question": "Q"}]}]}',
          'question 或 answer',
        );
        expectThrows(
          '{"proposals": [{"kind": "flashcard", "title": "T", "fields": {"content": "C"}, '
              '"cards": [{"question": "Q", "answer": "A", "type": "true_false"}]}]}',
          'fill_blank / mcq / essay',
        );
      });

      test('confidence 不是数字要报错；非闪存卡不许带 cards', () {
        expectThrows(
          '{"proposals": [{"kind": "tag", "title": "T", "confidence": "高"}]}',
          'confidence',
        );
        expectThrows(
          '{"proposals": [{"kind": "tag", "title": "T", "cards": [{"question": "Q", "answer": "A"}]}]}',
          '不该有 cards',
        );
      });
    });
  });

  group('从库里读回（fromJson）', () {
    HandwritingProposalSet sampleSet() => const HandwritingProposalSet(
          sourceRef: 'handwriting_intake/hw-1',
          proposals: <HandwritingProposal>[
            HandwritingProposal(
              id: 'tag-0',
              kind: HandwritingProposalKind.tag,
              titleZh: '动量守恒',
              rationaleZh: '照片里反复出现',
              confidence: 0.8,
              fields: <String, String>{
                'parent_path': '文化课/物理/力学',
                'description': '定义',
              },
              sourceRef: 'handwriting_intake/hw-1',
            ),
            HandwritingProposal(
              id: 'knowledge_point-1',
              kind: HandwritingProposalKind.knowledgePoint,
              titleZh: '动量守恒的条件',
              fields: <String, String>{
                'content': '合外力为零',
                'tag_path': '文化课/物理/力学/动量守恒',
              },
              sourceRef: 'handwriting_intake/hw-1',
            ),
            HandwritingProposal(
              id: 'flashcard-2',
              kind: HandwritingProposalKind.flashcard,
              titleZh: '动量守恒',
              confidence: 0.9,
              fields: <String, String>{'content': '正文'},
              cards: <HandwritingCardDraft>[
                HandwritingCardDraft(
                  question: '条件是什么？',
                  answer: '合外力为零。',
                  type: 'fill_blank',
                ),
                HandwritingCardDraft(question: 'Q2', answer: 'A2'),
              ],
              sourceRef: 'handwriting_intake/hw-1',
            ),
          ],
        );

    test('toJson → fromJson 往返一字不差（三类产物、字段、卡片都在）', () {
      final original = sampleSet();
      final restored = HandwritingProposalSet.fromJson(original.toJson());

      expect(restored.sourceRef, original.sourceRef);
      expect(
        restored.proposals.map((proposal) => proposal.id),
        original.proposals.map((proposal) => proposal.id),
      );
      expect(
        restored.proposals.map((proposal) => proposal.kind),
        original.proposals.map((proposal) => proposal.kind),
      );
      expect(restored.toJson(), original.toJson());

      final card = restored.proposals[2];
      expect(card.cards, hasLength(2));
      expect(card.cards.first.type, 'fill_blank');
      expect(card.cards[1].type, 'essay');
      expect(card.confidence, 0.9);
      expect(restored.countOf(HandwritingProposalKind.tag), 1);
    });

    test('库里的坏行要报错，不静默跳过（kind / id / fields / cards）', () {
      void expectThrows(Map<String, Object?> json, Object messagePart) {
        expect(
          () => HandwritingProposalSet.fromJson(json),
          throwsA(
            isA<HandwritingProposalParseException>().having(
              (error) => error.message,
              'message',
              contains(messagePart.toString()),
            ),
          ),
        );
      }

      expectThrows(<String, Object?>{'proposals': 1}, 'proposals');
      expectThrows(
        <String, Object?>{
          'proposals': <Object?>[
            <String, Object?>{'kind': 'tag', 'title': 'T'},
          ],
        },
        '缺少 id',
      );
      expectThrows(
        <String, Object?>{
          'proposals': <Object?>[
            <String, Object?>{'id': 'tag-0', 'kind': 'question', 'title': 'T'},
          ],
        },
        'tag / knowledge_point / flashcard',
      );
      expectThrows(
        <String, Object?>{
          'proposals': <Object?>[
            <String, Object?>{
              'id': 'kp-0',
              'kind': 'knowledge_point',
              'title': 'T'
            },
          ],
        },
        'fields.content',
      );
      expectThrows(
        <String, Object?>{
          'proposals': <Object?>[
            <String, Object?>{
              'id': 'fc-0',
              'kind': 'flashcard',
              'title': 'T',
              'fields': <String, Object?>{'content': 'C'},
            },
          ],
        },
        '复习队列',
      );
      expectThrows(
        <String, Object?>{
          'proposals': <Object?>[
            <String, Object?>{
              'id': 'tag-0',
              'kind': 'tag',
              'title': 'T',
              'confidence': '高',
            },
          ],
        },
        'confidence',
      );
    });

    test('卡片缺 answer / 题型不在册 → 报错；题型缺省是 essay', () {
      expect(
        () => HandwritingCardDraft.fromJson(<String, Object?>{
          'question': 'Q',
        }),
        throwsA(isA<HandwritingProposalParseException>()),
      );
      expect(
        () => HandwritingCardDraft.fromJson(<String, Object?>{
          'question': 'Q',
          'answer': 'A',
          'type': 'true_false',
        }),
        throwsA(
          isA<HandwritingProposalParseException>().having(
            (error) => error.message,
            'message',
            contains('fill_blank / mcq / essay'),
          ),
        ),
      );
      expect(
        HandwritingCardDraft.fromJson(<String, Object?>{
          'question': 'Q',
          'answer': 'A',
        }).type,
        'essay',
      );
    });

    test('空提案集合往返仍然合法（照片里没有可整理的东西）', () {
      const empty = HandwritingProposalSet(
        sourceRef: 'handwriting_intake/hw-9',
        proposals: <HandwritingProposal>[],
      );
      final restored = HandwritingProposalSet.fromJson(empty.toJson());
      expect(restored.isEmpty, isTrue);
      expect(restored.sourceRef, 'handwriting_intake/hw-9');
    });
  });
}
