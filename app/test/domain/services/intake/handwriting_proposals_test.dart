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

import 'dart:convert';

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

    test('多图：3 张照片 → 2 条消息、3 个 image part 按顺序、逐页标注', () {
      final messages = handwritingProposalMessagesForPhotos(
        photos: const <HandwritingPhotoInput>[
          HandwritingPhotoInput(
            fileName: 'hw-9/page-1.png',
            mime: 'image/png',
            base64: 'PAGE1',
          ),
          HandwritingPhotoInput(
            fileName: 'hw-9/page-2.jpg',
            mime: 'image/jpeg',
            base64: 'PAGE2',
          ),
          HandwritingPhotoInput(
            fileName: 'hw-9/page-3.png',
            mime: 'image/png',
            base64: 'PAGE3',
          ),
        ],
      );

      expect(messages, hasLength(2));
      expect(messages.first.role, 'system');
      expect(messages.last.role, 'user');

      final system = messages.first.content ?? '';
      expect(system, contains('3 张照片'));
      expect(system, contains('第 1 页到第 3 页'));
      expect(system, contains('同一道题跨页时合并成**一条** question 提案'));
      expect(system, contains('第几页'));
      expect(system, contains(handwritingProposalJsonContract));

      final user = messages.last;
      final userText = user.content ?? '';
      expect(userText, contains('第 1 页：hw-9/page-1.png'));
      expect(userText, contains('第 2 页：hw-9/page-2.jpg'));
      expect(userText, contains('第 3 页：hw-9/page-3.png'));
      expect(userText, isNot(contains('第 4 页')));
      expect(user.images, hasLength(3));
      expect(
        user.images.map((image) => image.base64).toList(),
        const <String>['PAGE1', 'PAGE2', 'PAGE3'],
      );
      expect(
        user.images.map((image) => image.mime).toList(),
        const <String>['image/png', 'image/jpeg', 'image/png'],
      );
    });

    test('多图：2 张是下限，仍然逐页标注', () {
      final messages = handwritingProposalMessagesForPhotos(
        photos: const <HandwritingPhotoInput>[
          HandwritingPhotoInput(
            fileName: 'a.png',
            mime: 'image/png',
            base64: 'QQ==',
          ),
          HandwritingPhotoInput(
            fileName: 'b.png',
            mime: 'image/png',
            base64: 'Qg==',
          ),
        ],
      );

      expect(messages, hasLength(2));
      expect(messages.last.images, hasLength(2));
      final system = messages.first.content ?? '';
      expect(system, contains('2 张照片'));
      expect(system, contains('第 1 页到第 2 页'));
      final user = messages.last.content ?? '';
      expect(user, contains('第 1 页：a.png'));
      expect(user, contains('第 2 页：b.png'));
      expect(user, isNot(contains('第 3 页')));
    });

    test('多图不足 2 张：assert 暴露调用方 bug，不悄悄降级成单图', () {
      expect(
        () => handwritingProposalMessagesForPhotos(
          photos: const <HandwritingPhotoInput>[],
        ),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => handwritingProposalMessagesForPhotos(
          photos: const <HandwritingPhotoInput>[
            HandwritingPhotoInput(
              fileName: 'only.png',
              mime: 'image/png',
              base64: 'QQ==',
            ),
          ],
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('多图的 JSON 契约与六条铁律和单图逐字一致，只多出页规则', () {
      final single = handwritingProposalMessages(
        fileName: 'hw-9/page-1.png',
        mime: 'image/png',
        base64: 'PAGE1',
        existingTagPaths: const ['文化课/物理/力学'],
        existingKnowledgePointTitles: const ['动量守恒的条件'],
      );
      final multi = handwritingProposalMessagesForPhotos(
        photos: const <HandwritingPhotoInput>[
          HandwritingPhotoInput(
            fileName: 'hw-9/page-1.png',
            mime: 'image/png',
            base64: 'PAGE1',
          ),
          HandwritingPhotoInput(
            fileName: 'hw-9/page-2.png',
            mime: 'image/png',
            base64: 'PAGE2',
          ),
        ],
        existingTagPaths: const ['文化课/物理/力学'],
        existingKnowledgePointTitles: const ['动量守恒的条件'],
      );

      final singleSystem = single.first.content ?? '';
      final multiSystem = multi.first.content ?? '';

      // 单图开头逐字没变（这次只是把提示词抽成了一份共用的）。
      expect(
        singleSystem,
        startsWith(
          '你是一个「手写/纸质材料整理员」。用户给你一张照片，'
          '你要把它整理成**待确认的产物提案**，\n交回一份 JSON。',
        ),
      );

      // 契约段及其后内容逐字节相同：多图只在前面多一段页说明和几条页规则。
      final singleTail =
          singleSystem.substring(singleSystem.indexOf('只输出 JSON'));
      final multiTail = multiSystem.substring(multiSystem.indexOf('只输出 JSON'));
      expect(multiTail, singleTail);
      expect(singleTail, endsWith(handwritingProposalJsonContract));

      // 铁律 1-6 与标签/知识点清单原样在；页规则 7-9 追加在它们后面。
      final sharedRules = singleSystem.substring(
        singleSystem.indexOf('1. 只整理'),
        singleSystem.indexOf('\n\n已有的标签路径'),
      );
      expect(sharedRules, contains('6. 题目提案（kind=question）只做誊写'));
      expect(multiSystem, contains(sharedRules));
      final pageRulesAt = multiSystem.indexOf('7. 按第 1 页到第 2 页的顺序读这些照片');
      expect(pageRulesAt, greaterThan(multiSystem.indexOf(sharedRules)));
      expect(multiSystem, contains('8. 同一道题跨页时合并成**一条** question 提案'));
      expect(multiSystem, contains('9. 看不清、拍漏或不确定时'));
    });

    test('多图也如实带上已有标签路径与知识点标题', () {
      final messages = handwritingProposalMessagesForPhotos(
        photos: const <HandwritingPhotoInput>[
          HandwritingPhotoInput(
            fileName: 'p1.png',
            mime: 'image/png',
            base64: 'QQ==',
          ),
          HandwritingPhotoInput(
            fileName: 'p2.png',
            mime: 'image/png',
            base64: 'Qg==',
          ),
        ],
        existingTagPaths: const ['文化课/物理/力学', '文化课/物理/电磁学'],
        existingKnowledgePointTitles: const ['动量守恒的条件'],
      );
      final system = messages.first.content ?? '';
      expect(system, contains('- 文化课/物理/力学'));
      expect(system, contains('- 文化课/物理/电磁学'));
      expect(system, contains('- 动量守恒的条件'));
      expect(system, isNot(contains('标签树现在还是空的')));
      expect(system, isNot(contains('还没有知识点')));
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
          '{"proposals": [{"kind": "mindmap", "title": "x"}]}',
          'tag / knowledge_point / flashcard / question',
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
            <String, Object?>{'id': 'tag-0', 'kind': 'mindmap', 'title': 'T'},
          ],
        },
        'tag / knowledge_point / flashcard / question',
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

  group('题目提案（第四类产物）', () {
    void expectQuestionThrows(String raw, Object messagePart) {
      expect(
        () => parseHandwritingProposals(raw, sourceRef: 'hw/qx.png'),
        throwsA(
          isA<HandwritingProposalParseException>().having(
            (error) => error.message,
            'message',
            contains(messagePart.toString()),
          ),
        ),
      );
    }

    test('纯题干：kind=question、stem 进 fields、无 options', () {
      const raw = '{"proposals": [{"kind": "question", "title": "第 3 题", '
          '"rationale": "照片里是一道纯文字题", "confidence": 0.7, '
          '"fields": {"stem": "照片里的题干原文"}}]}';
      final set = parseHandwritingProposals(raw, sourceRef: 'hw/q1.png');
      final proposal = set.proposals.single;
      expect(proposal.kind, HandwritingProposalKind.question);
      expect(proposal.id, 'question-0');
      expect(proposal.fields['stem'], '照片里的题干原文');
      expect(proposal.options, isEmpty);
      expect(proposal.cards, isEmpty);
      expect(set.countOf(HandwritingProposalKind.question), 1);
      expect(proposal.toJson().containsKey('options'), isFalse);
    });

    test('带选项：label 归一大写、内容 trim、toJson 输出 options', () {
      const raw = '{"proposals": [{"kind": "question", "title": "选择题", '
          '"fields": {"stem": "题干"}, "options": ['
          '{"label": " a ", "content": " 甲 "}, '
          '{"label": "B", "content": "乙"}, '
          '{"label": "C", "content": "丙"}, '
          '{"label": "D", "content": "丁"}]}]}';
      final proposal = parseHandwritingProposals(raw, sourceRef: 'hw/q2.png')
          .proposals
          .single;
      expect(proposal.options, hasLength(4));
      expect(
        proposal.options.map((option) => option.label).toList(),
        const <String>['A', 'B', 'C', 'D'],
      );
      expect(proposal.options.first.content, '甲');
      final options = proposal.toJson()['options'] as List<Object?>;
      expect(options, hasLength(4));
      expect((options.first as Map<String, Object?>)['label'], 'A');
    });

    test('带答案与解析：fields 里 stem/answer/solution 都在', () {
      final proposal = parseHandwritingProposals(
        '{"proposals": [{"kind": "question", "title": "T", '
        '"fields": {"stem": "题干", "answer": "B", "solution": "因为加速度恒定"}, '
        '"options": [{"label": "A", "content": "甲"}, {"label": "B", "content": "乙"}]}]}',
        sourceRef: 'hw/q3.png',
      ).proposals.single;
      expect(proposal.fields['stem'], '题干');
      expect(proposal.fields['answer'], 'B');
      expect(proposal.fields['solution'], '因为加速度恒定');
    });

    test('题目缺 fields.stem 报错（题面必须来自照片）', () {
      expectQuestionThrows(
        '{"proposals": [{"kind": "question", "title": "T"}]}',
        '缺少 fields.stem',
      );
    });

    test('question 带 cards 报错', () {
      expectQuestionThrows(
        '{"proposals": [{"kind": "question", "title": "T", "fields": {"stem": "题干"}, '
            '"cards": [{"question": "Q", "answer": "A"}]}]}',
        '不该有 cards',
      );
    });

    test('options 不是数组报错', () {
      expectQuestionThrows(
        '{"proposals": [{"kind": "question", "title": "T", "fields": {"stem": "题干"}, '
            '"options": {}}]}',
        '不是数组',
      );
    });

    test('options 是空数组报错（有选项才写，没有就省略）', () {
      expectQuestionThrows(
        '{"proposals": [{"kind": "question", "title": "T", "fields": {"stem": "题干"}, '
            '"options": []}]}',
        '空数组',
      );
    });

    test('options 超过 26 条报错', () {
      final raw = jsonEncode(<String, Object?>{
        'proposals': <Object?>[
          <String, Object?>{
            'kind': 'question',
            'title': 'T',
            'fields': <String, Object?>{'stem': '题干'},
            'options': <Object?>[
              for (var index = 0; index < 27; index += 1)
                <String, Object?>{'label': 'A', 'content': '内容'},
            ],
          },
        ],
      });
      expectQuestionThrows(raw, '最多 26 条');
    });

    test('options 条目不是对象报错', () {
      expectQuestionThrows(
        '{"proposals": [{"kind": "question", "title": "T", "fields": {"stem": "题干"}, '
            '"options": [7]}]}',
        '不是对象',
      );
    });

    test('选项 label 非法报错', () {
      expectQuestionThrows(
        '{"proposals": [{"kind": "question", "title": "T", "fields": {"stem": "题干"}, '
            '"options": [{"label": "AB", "content": "甲"}]}]}',
        '必须是单个大写字母 A-Z',
      );
    });

    test('选项 label 重复报错', () {
      expectQuestionThrows(
        '{"proposals": [{"kind": "question", "title": "T", "fields": {"stem": "题干"}, '
            '"options": [{"label": "A", "content": "甲"}, {"label": "A", "content": "乙"}]}]}',
        '重复',
      );
    });

    test('选项 label 必须从 A 起连续', () {
      const suffix = '（选项要按 A、B、C… 连续）';
      expectQuestionThrows(
        '{"proposals": [{"kind": "question", "title": "T", "fields": {"stem": "题干"}, '
        '"options": [{"label": "A", "content": "甲"}, {"label": "C", "content": "丙"}]}]}',
        suffix,
      );
      expectQuestionThrows(
        '{"proposals": [{"kind": "question", "title": "T", "fields": {"stem": "题干"}, '
        '"options": [{"label": "B", "content": "乙"}, {"label": "C", "content": "丙"}]}]}',
        suffix,
      );
    });

    test('选项内容不能为空', () {
      expectQuestionThrows(
        '{"proposals": [{"kind": "question", "title": "T", "fields": {"stem": "题干"}, '
            '"options": [{"label": "A", "content": "   "}]}]}',
        '为空',
      );
    });

    test('非题目 kind 带 options 直接拒绝', () {
      const samples = <String>[
        '{"proposals": [{"kind": "tag", "title": "T", "fields": {"parent_path": "A/B"}, '
            '"options": [{"label": "A", "content": "甲"}]}]}',
        '{"proposals": [{"kind": "knowledge_point", "title": "K", "fields": {"content": "C"}, '
            '"options": [{"label": "A", "content": "甲"}]}]}',
        '{"proposals": [{"kind": "flashcard", "title": "F", "fields": {"content": "C"}, '
            '"cards": [{"question": "Q", "answer": "A"}], '
            '"options": [{"label": "A", "content": "甲"}]}]}',
      ];
      for (final raw in samples) {
        expectQuestionThrows(raw, '不该有 options');
      }
    });

    test('options 经 toJson/fromJson 往返不丢内容', () {
      const raw =
          '{"proposals": [{"kind": "question", "title": "T", "fields": {"stem": "题干"}, '
          '"options": [{"label": "A", "content": "甲"}, {"label": "B", "content": "乙"}]}]}';
      final set = parseHandwritingProposals(raw, sourceRef: 'hw/q5.png');
      final restored = HandwritingProposalSet.fromJson(set.toJson());
      expect(restored.toJson(), set.toJson());
      expect(
        restored.proposals.single.options
            .map((option) => option.content)
            .toList(),
        const <String>['甲', '乙'],
      );
    });

    test('HandwritingOptionDraft.fromJson 归一 label 并校验', () {
      final draft = HandwritingOptionDraft.fromJson(
        <String, Object?>{'label': ' b ', 'content': ' 乙 '},
      );
      expect(draft.label, 'B');
      expect(draft.content, '乙');
      expect(draft.toJson()['label'], 'B');
      expect(
        () => HandwritingOptionDraft.fromJson(
          <String, Object?>{'label': 'AB', 'content': 'x'},
        ),
        throwsA(isA<HandwritingProposalParseException>()),
      );
      expect(
        () => HandwritingOptionDraft.fromJson(
          <String, Object?>{'label': 'A', 'content': '   '},
        ),
        throwsA(
          isA<HandwritingProposalParseException>().having(
            (error) => error.message,
            'message',
            contains('content'),
          ),
        ),
      );
    });

    test('JSON 契约仍是合法 JSON，且题目示例选项 A-D 齐全', () {
      final decoded =
          jsonDecode(handwritingProposalJsonContract) as Map<String, Object?>;
      final proposals =
          (decoded['proposals'] as List<Object?>).cast<Map<String, Object?>>();
      expect(
        proposals.map((proposal) => proposal['kind']).toList(),
        const <String>['tag', 'knowledge_point', 'flashcard', 'question'],
      );
      final fields = proposals.last['fields'] as Map<String, Object?>;
      expect((fields['stem'] as String).trim(), isNotEmpty);
      final options = (proposals.last['options'] as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(
        options.map((option) => option['label']).toList(),
        const <String>['A', 'B', 'C', 'D'],
      );
      expect(
        options
            .every((option) => (option['content'] as String).trim().isNotEmpty),
        isTrue,
      );
    });

    test('提示词讲明四类产物与题目只誊写', () {
      final messages = handwritingProposalMessages(
        fileName: 'hw-3/page.png',
        mime: 'image/png',
        base64: 'QUJD',
      );
      final system = messages.first.content ?? '';
      expect(
        system,
        contains('四种 kind 只允许：tag / knowledge_point / flashcard / question'),
      );
      expect(system, contains('只做誊写'));
      expect(system, contains('不改写题意'));
      expect(system, contains('不补全缺失选项'));
      expect(system, contains('不做题'));
      final user = messages.last.content ?? '';
      expect(user, contains('四类待确认产物'));
      expect(user, contains('题目'));
    });

    test('旧三类 JSON 照常解析，且不凭空多出 options', () {
      const raw = '{"proposals": ['
          '{"kind": "tag", "title": "T", "fields": {"parent_path": "文化课/物理"}}, '
          '{"kind": "knowledge_point", "title": "K", "fields": {"content": "动量守恒"}}, '
          '{"kind": "flashcard", "title": "F", "fields": {"content": "条件"}, '
          '"cards": [{"question": "Q", "answer": "A"}]}'
          ']}';
      final set = parseHandwritingProposals(raw, sourceRef: 'hw/old.png');
      expect(
        set.proposals.map((proposal) => proposal.kind).toList(),
        const <HandwritingProposalKind>[
          HandwritingProposalKind.tag,
          HandwritingProposalKind.knowledgePoint,
          HandwritingProposalKind.flashcard,
        ],
      );
      expect(
        set.proposals.map((proposal) => proposal.id).toList(),
        const <String>['tag-0', 'knowledge_point-1', 'flashcard-2'],
      );
      expect(set.countOf(HandwritingProposalKind.question), 0);
      for (final proposal in set.proposals) {
        expect(proposal.toJson().containsKey('options'), isFalse);
      }
    });

    test('题目没有选项时 toJson 不带 options，且解析结果确定', () {
      const raw = '{"proposals": [{"kind": "question", "title": "T", '
          '"fields": {"stem": "题干"}}]}';
      final once = parseHandwritingProposals(raw, sourceRef: 'hw/q6.png');
      final twice = parseHandwritingProposals(raw, sourceRef: 'hw/q6.png');
      expect(once.proposals.single.toJson().containsKey('options'), isFalse);
      expect(twice.toJson(), once.toJson());
    });
  });

  group('题干内联选项抽取', () {
    InlineOptionExtraction extract(String raw) => extractInlineOptions(raw);

    List<String> labelsOf(InlineOptionExtraction extraction) =>
        extraction.options.map((option) => option.label).toList();

    List<String> contentsOf(InlineOptionExtraction extraction) =>
        extraction.options.map((option) => option.content).toList();

    List<String> proposalLabels(HandwritingProposal proposal) =>
        proposal.options.map((option) => option.label).toList();

    test('选项各占一行：题干与 A-D 分开', () {
      final extraction = extract('题干（  ）\nA．甲\nB．乙\nC．丙\nD．丁');
      expect(extraction.succeeded, isTrue);
      expect(extraction.failureReason, isNull);
      expect(extraction.stem, '题干（  ）');
      expect(labelsOf(extraction), const <String>['A', 'B', 'C', 'D']);
      expect(contentsOf(extraction), const <String>['甲', '乙', '丙', '丁']);
    });

    test('全角字母与全角句点也认', () {
      final extraction = extract('下列正确的是\nＡ．甲\nＢ．乙');
      expect(extraction.stem, '下列正确的是');
      expect(labelsOf(extraction), const <String>['A', 'B']);
      expect(contentsOf(extraction), const <String>['甲', '乙']);
    });

    test('同一行内联多个选项可以拆开', () {
      final extraction = extract('下列正确的是\nA．甲 B．乙 C．丙 D．丁');
      expect(labelsOf(extraction), const <String>['A', 'B', 'C', 'D']);
      expect(contentsOf(extraction), const <String>['甲', '乙', '丙', '丁']);
    });

    test('四种分隔符混用', () {
      final extraction = extract('题干\nA、甲\nB. 乙\nC) 丙\nD：丁');
      expect(labelsOf(extraction), const <String>['A', 'B', 'C', 'D']);
      expect(contentsOf(extraction), const <String>['甲', '乙', '丙', '丁']);
    });

    test('选项行首允许缩进', () {
      final extraction = extract('题干\n   A．甲\n   B．乙');
      expect(extraction.stem, '题干');
      expect(contentsOf(extraction), const <String>['甲', '乙']);
    });

    test('选项内容可以跨行，换行原样保留', () {
      final extraction = extract('题干\nA．第一行\n第二行\nB．乙');
      expect(contentsOf(extraction).first, '第一行\n第二行');
      expect(contentsOf(extraction)[1], '乙');
    });

    test('选项内容里的 LaTeX 原样保留', () {
      const raw = r'''题干
A．$\frac{1}{2}$
B．$\sqrt{2}$''';
      final extraction = extract(raw);
      expect(labelsOf(extraction), const <String>['A', 'B']);
      expect(contentsOf(extraction).first, r'$\frac{1}{2}$');
      expect(contentsOf(extraction)[1], r'$\sqrt{2}$');
      expect(extraction.stem, '题干');
    });

    test('行内公式里的 A．B 不参与识别', () {
      const raw = r'''已知 $x=A．B$，则
A．1
B．2''';
      final extraction = extract(raw);
      expect(extraction.succeeded, isTrue);
      expect(extraction.stem, r'已知 $x=A．B$，则');
      expect(contentsOf(extraction), const <String>['1', '2']);
    });

    test('行间公式里的字母不参与识别', () {
      const raw = r'''已知 \[A．B\]，则
A．1
B．2''';
      final extraction = extract(raw);
      expect(extraction.succeeded, isTrue);
      expect(extraction.stem, r'已知 \[A．B\]，则');
      expect(contentsOf(extraction), const <String>['1', '2']);
    });

    test('行间公式（双美元符号）里的字母不参与识别', () {
      const raw = r'''求 $$\frac{A．B}{2}$$ 的值
A．1
B．2''';
      final extraction = extract(raw);
      expect(extraction.succeeded, isTrue);
      expect(extraction.stem, r'求 $$\frac{A．B}{2}$$ 的值');
      expect(contentsOf(extraction), const <String>['1', '2']);
    });

    test('【答案】【解析】行整行不参与识别，也不并入选项内容', () {
      const raw = r'''题干
A．甲
B．乙
【答案】A
【解析】先算 A．1，再算 B．2''';
      final extraction = extract(raw);
      expect(extraction.succeeded, isTrue);
      expect(labelsOf(extraction), const <String>['A', 'B']);
      expect(contentsOf(extraction), const <String>['甲', '乙']);
      expect(extraction.stem, '题干');
    });

    test('答案：/解析：前缀行同样不参与识别', () {
      final extraction = extract('题干\nA．甲\nB．乙\n答案：B\n解析：选 B．乙');
      expect(labelsOf(extraction), const <String>['A', 'B']);
      expect(contentsOf(extraction), const <String>['甲', '乙']);
    });

    test('题干里行首枚举 A、B两点 不会被误当选项', () {
      final extraction = extract('A、B两点确定一条直线（  ）\nA．1\nB．2');
      expect(extraction.succeeded, isTrue);
      expect(extraction.stem, 'A、B两点确定一条直线（  ）');
      expect(contentsOf(extraction), const <String>['1', '2']);
    });

    test('A=1、B点、选项 A 说法正确 都不算选项标记', () {
      final extraction = extract('令 A=1，B=2，则 A、B 两点之间的距离为（  ）\n选项 A 说法正确');
      expect(extraction.succeeded, isFalse);
      expect(extraction.options, isEmpty);
      expect(
        extraction.stem,
        '令 A=1，B=2，则 A、B 两点之间的距离为（  ）\n选项 A 说法正确',
      );
      expect(extraction.failureReason, '没找到行首或段首的选项标记');
    });

    test('括号样式（A）不是选项标记', () {
      final extraction = extract('题干\n（A）甲\n（B）乙');
      expect(extraction.succeeded, isFalse);
      expect(extraction.failureReason, '没找到行首或段首的选项标记');
    });

    test('只有一个 A 时失败并说明原因', () {
      final extraction = extract('题干\nA．甲');
      expect(extraction.succeeded, isFalse);
      expect(extraction.failureReason, '至少需要 2 个选项（现在只有 1 个「A」）');
    });

    test('不从 A 起时失败，并指出第一个标记', () {
      final extraction = extract('题干\nB．甲\nC．乙');
      expect(extraction.succeeded, isFalse);
      expect(
        extraction.failureReason,
        '选项必须从 A 开始，第一个标记是「B」（选项要按 A、B、C… 连续）',
      );
    });

    test('跳号时失败，列出缺少的字母', () {
      final extraction = extract('题干\nA．甲\nD．丁');
      expect(extraction.succeeded, isFalse);
      expect(
        extraction.failureReason,
        '选项字母不连续：「A」之后直接是「D」，缺少「B」、「C」（选项要按 A、B、C… 连续）',
      );
    });

    test('重复字母时失败（A、B 之后又出现 A）', () {
      final extraction = extract('题干\nA．甲\nB．乙\nA．丙');
      expect(extraction.succeeded, isFalse);
      expect(extraction.failureReason, '选项字母重复：「A」出现了不止一次');
    });

    test('选项内容为空时失败', () {
      final extraction = extract('题干\nA．甲\nB．\nC．丙');
      expect(extraction.succeeded, isFalse);
      expect(extraction.failureReason, '选项「B」的内容为空：标记后面没有文字');
    });

    test('选项标记前面没有题干时失败', () {
      final extraction = extract('A．甲\nB．乙');
      expect(extraction.succeeded, isFalse);
      expect(extraction.failureReason, '选项标记前面没有题干：抽出的选项不能没有题面');
    });

    test('空输入与纯空白输入：不抛异常，给出空原因', () {
      final empty = extract('');
      expect(empty.stem, '');
      expect(empty.succeeded, isFalse);
      expect(empty.failureReason, '题面是空的，没有可抽取的内容');
      final spaces = extract('   ');
      expect(spaces.stem, '   ');
      expect(spaces.failureReason, '题面是空的，没有可抽取的内容');
    });

    test('纯文字题没有选项标记：原样返回，不猜选项', () {
      final extraction = extract('已知函数在区间上单调递增，求参数的取值范围。');
      expect(extraction.succeeded, isFalse);
      expect(extraction.stem, '已知函数在区间上单调递增，求参数的取值范围。');
      expect(extraction.options, isEmpty);
      expect(extraction.failureReason, '没找到行首或段首的选项标记');
    });

    test('任何奇怪输入都不抛异常，成功/失败状态自洽', () {
      const inputs = <String>[
        '',
        ' ',
        '\n',
        '\u3000',
        'A',
        'B．',
        'A．\n',
        'A．\nB．',
        '题干\nA．甲\nB．',
        r'$',
        r'\(',
        r'$\(A．B',
        'A．甲\nB．乙\nC．',
      ];
      for (final input in inputs) {
        late InlineOptionExtraction extraction;
        expect(
          () {
            extraction = extract(input);
          },
          returnsNormally,
        );
        if (extraction.succeeded) {
          expect(extraction.failureReason, isNull);
          expect(extraction.options.length, greaterThanOrEqualTo(2));
          expect(extraction.stem, isNotEmpty);
        } else {
          expect(extraction.failureReason, isNotNull);
          expect(extraction.options, isEmpty);
        }
      }
    });

    test('同一输入永远同一结果', () {
      const raw = '题干（  ）\nA．甲 B．乙 C．丙';
      final first = extract(raw);
      final second = extract(raw);
      expect(second.stem, first.stem);
      expect(second.failureReason, first.failureReason);
      expect(labelsOf(second), labelsOf(first));
      expect(contentsOf(second), contentsOf(first));
    });

    test('题面与选项同一行、选项不在行首时不抽（已知限制）', () {
      final extraction = extract('题干（  ） A．甲 B．乙');
      expect(extraction.succeeded, isFalse);
      expect(extraction.failureReason, '没找到行首或段首的选项标记');
    });

    test('全角空格会从选项内容首尾去掉', () {
      final extraction = extract('题干\nA．\u3000甲\u3000\nB．乙');
      expect(contentsOf(extraction).first, '甲');
    });

    test('CRLF 换行的题面也能抽', () {
      final extraction = extract('题干\r\nA．甲\r\nB．乙');
      expect(extraction.stem, '题干');
      expect(contentsOf(extraction), const <String>['甲', '乙']);
    });

    test('超长题干不截断', () {
      final longStem = List<String>.filled(2000, '题').join();
      final raw = <String>[longStem, 'A．甲', 'B．乙'].join('\n');
      final extraction = extract(raw);
      expect(extraction.succeeded, isTrue);
      expect(extraction.stem.length, 2000);
      expect(extraction.stem, longStem);
    });

    test('A-E 五个选项都认', () {
      final extraction = extract('题干\nA．1\nB．2\nC．3\nD．4\nE．5');
      expect(labelsOf(extraction), const <String>['A', 'B', 'C', 'D', 'E']);
      expect(contentsOf(extraction), const <String>['1', '2', '3', '4', '5']);
    });

    test('选项之间的空行不影响抽取', () {
      final extraction = extract('题干\nA．甲\n\nB．乙');
      expect(contentsOf(extraction), const <String>['甲', '乙']);
    });

    test('解析接线：模型没给 options 时从 fields.stem 抽，并保留原题面', () {
      final raw = jsonEncode(<String, Object?>{
        'proposals': <Object?>[
          <String, Object?>{
            'kind': 'question',
            'title': '第 3 题',
            'fields': <String, Object?>{'stem': '题干（  ）\nA．甲\nB．乙'},
          },
        ],
      });
      final proposal =
          parseHandwritingProposals(raw, sourceRef: 'hw/inline.png')
              .proposals
              .single;
      expect(proposal.kind, HandwritingProposalKind.question);
      expect(proposal.fields['stem'], '题干（  ）');
      expect(proposal.fields['stem_original'], '题干（  ）\nA．甲\nB．乙');
      expect(proposalLabels(proposal), const <String>['A', 'B']);
      expect(
        proposal.options.map((option) => option.content).toList(),
        const <String>['甲', '乙'],
      );
      final json = proposal.toJson();
      expect(json['fields'], <String, Object?>{
        'stem': '题干（  ）',
        'stem_original': '题干（  ）\nA．甲\nB．乙',
      });
      expect((json['options']! as List<Object?>), hasLength(2));
    });

    test('模型给了 options 就不再从题面抽，题面保持原样', () {
      final raw = jsonEncode(<String, Object?>{
        'proposals': <Object?>[
          <String, Object?>{
            'kind': 'question',
            'title': '第 4 题',
            'fields': <String, Object?>{'stem': '题干\nA．甲\nB．乙'},
            'options': <Object?>[
              <String, Object?>{'label': 'A', 'content': '原选项甲'},
              <String, Object?>{'label': 'B', 'content': '原选项乙'},
            ],
          },
        ],
      });
      final proposal = parseHandwritingProposals(raw, sourceRef: 'hw/given.png')
          .proposals
          .single;
      expect(proposal.fields['stem'], '题干\nA．甲\nB．乙');
      expect(proposal.fields.containsKey('stem_original'), isFalse);
      expect(
        proposal.options.map((option) => option.content).toList(),
        const <String>['原选项甲', '原选项乙'],
      );
    });

    test('纯文字题目不受影响：不新增字段、不带 options', () {
      final raw = jsonEncode(<String, Object?>{
        'proposals': <Object?>[
          <String, Object?>{
            'kind': 'question',
            'title': '第 5 题',
            'fields': <String, Object?>{'stem': '纯文字题干（  ）'},
          },
        ],
      });
      final proposal = parseHandwritingProposals(raw, sourceRef: 'hw/plain.png')
          .proposals
          .single;
      expect(proposal.fields, <String, String>{'stem': '纯文字题干（  ）'});
      expect(proposal.options, isEmpty);
      expect(proposal.toJson().containsKey('options'), isFalse);
    });

    test('库里读回的存量题目：题干里有内联选项也会被确定性补抽', () {
      final restored = HandwritingProposalSet.fromJson(<String, Object?>{
        'source_ref': 'handwriting_intake/hw-legacy',
        'proposals': <Object?>[
          <String, Object?>{
            'id': 'question-0',
            'kind': 'question',
            'title': '存量题',
            'fields': <String, Object?>{'stem': '旧题干（  ）\nA．甲\nB．乙'},
          },
        ],
      }).proposals.single;
      expect(restored.fields['stem'], '旧题干（  ）');
      expect(restored.fields['stem_original'], '旧题干（  ）\nA．甲\nB．乙');
      expect(proposalLabels(restored), const <String>['A', 'B']);
    });

    test('toJson → fromJson 往返一字不差，且不会重复剥离', () {
      final raw = jsonEncode(<String, Object?>{
        'proposals': <Object?>[
          <String, Object?>{
            'kind': 'question',
            'title': '往返题',
            'fields': <String, Object?>{'stem': '题干\nA．甲\nB．乙'},
          },
        ],
      });
      final once = parseHandwritingProposals(raw, sourceRef: 'hw/roundtrip.png')
          .proposals
          .single;
      final restored = HandwritingProposal.fromJson(once.toJson());
      expect(jsonEncode(restored.toJson()), jsonEncode(once.toJson()));
      expect(restored.fields['stem'], '题干');
      expect(restored.fields['stem_original'], '题干\nA．甲\nB．乙');
      expect(proposalLabels(restored), const <String>['A', 'B']);
    });

    test('旧三类产物里的 A．B． 文本不受影响', () {
      final raw = jsonEncode(<String, Object?>{
        'proposals': <Object?>[
          <String, Object?>{
            'kind': 'tag',
            'title': 'T',
            'fields': <String, Object?>{
              'parent_path': '文化课/物理',
              'description': 'A．第一点\nB．第二点',
            },
          },
          <String, Object?>{
            'kind': 'knowledge_point',
            'title': 'K',
            'fields': <String, Object?>{
              'content': 'A．内容',
              'tag_path': '文化课/物理'
            },
          },
        ],
      });
      final set = parseHandwritingProposals(raw, sourceRef: 'hw/old.png');
      final tag = set.proposals[0];
      expect(tag.fields['description'], 'A．第一点\nB．第二点');
      expect(tag.fields.containsKey('stem_original'), isFalse);
      expect(tag.options, isEmpty);
      expect(set.proposals[1].fields['content'], 'A．内容');
    });

    test('多题里只有带内联选项的那题被抽', () {
      final raw = jsonEncode(<String, Object?>{
        'proposals': <Object?>[
          <String, Object?>{
            'kind': 'question',
            'title': '第 1 题',
            'fields': <String, Object?>{'stem': '题干一\nA．甲\nB．乙'},
          },
          <String, Object?>{
            'kind': 'question',
            'title': '第 2 题',
            'fields': <String, Object?>{'stem': '纯文字题干二'},
          },
        ],
      });
      final set = parseHandwritingProposals(raw, sourceRef: 'hw/two.png');
      expect(set.proposals[0].fields['stem'], '题干一');
      expect(proposalLabels(set.proposals[0]), const <String>['A', 'B']);
      expect(set.proposals[1].fields, <String, String>{'stem': '纯文字题干二'});
      expect(set.proposals[1].options, isEmpty);
    });

    test('抽不出选项时解析不抛异常，题面原样保留', () {
      final raw = jsonEncode(<String, Object?>{
        'proposals': <Object?>[
          <String, Object?>{
            'kind': 'question',
            'title': '第 6 题',
            'fields': <String, Object?>{'stem': '令 A=1，B=2，则距离为（  ）'},
          },
        ],
      });
      final proposal =
          parseHandwritingProposals(raw, sourceRef: 'hw/no-extract.png')
              .proposals
              .single;
      expect(proposal.fields, <String, String>{'stem': '令 A=1，B=2，则距离为（  ）'});
      expect(proposal.options, isEmpty);
    });

    test('题面只有选项没有题干时解析不抛异常', () {
      final raw = jsonEncode(<String, Object?>{
        'proposals': <Object?>[
          <String, Object?>{
            'kind': 'question',
            'title': '第 7 题',
            'fields': <String, Object?>{'stem': 'A．甲\nB．乙'},
          },
        ],
      });
      final proposal =
          parseHandwritingProposals(raw, sourceRef: 'hw/only-options.png')
              .proposals
              .single;
      expect(proposal.fields['stem'], 'A．甲\nB．乙');
      expect(proposal.options, isEmpty);
    });

    test('解析结果确定：两次 toJson 相同', () {
      final raw = jsonEncode(<String, Object?>{
        'proposals': <Object?>[
          <String, Object?>{
            'kind': 'question',
            'title': '确定题',
            'fields': <String, Object?>{'stem': '题干\nA．甲\nB．乙'},
          },
        ],
      });
      final once = parseHandwritingProposals(raw, sourceRef: 'hw/det.png');
      final twice = parseHandwritingProposals(raw, sourceRef: 'hw/det.png');
      expect(jsonEncode(twice.toJson()), jsonEncode(once.toJson()));
    });

    test('题干抽出选项后，答案与解析字段原样保留', () {
      final raw = jsonEncode(<String, Object?>{
        'proposals': <Object?>[
          <String, Object?>{
            'kind': 'question',
            'title': '第 8 题',
            'fields': <String, Object?>{
              'stem': '题干\nA．甲\nB．乙',
              'answer': 'B',
              'solution': '因为 A、B 两点对称',
            },
          },
        ],
      });
      final proposal =
          parseHandwritingProposals(raw, sourceRef: 'hw/answer.png')
              .proposals
              .single;
      expect(proposal.fields['stem'], '题干');
      expect(proposal.fields['answer'], 'B');
      expect(proposal.fields['solution'], '因为 A、B 两点对称');
      expect(proposalLabels(proposal), const <String>['A', 'B']);
    });
  });
}
