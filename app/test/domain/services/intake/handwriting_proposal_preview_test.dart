import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/intake/handwriting_proposal_preview.dart';
import 'package:furnace/domain/services/intake/handwriting_proposals.dart';

const Set<String> _existingTags = <String>{
  '文化课',
  '文化课/物理',
  '文化课/物理/力学',
};

const Set<String> _existingKnowledgePoints = <String>{'动量'};

HandwritingProposalSet _setOf(List<HandwritingProposal> proposals) =>
    HandwritingProposalSet(
      sourceRef: 'handwriting_intake/hw-1',
      proposals: proposals,
    );

HandwritingIntakePreview _previewSet(HandwritingProposalSet set) =>
    previewHandwritingProposals(
      set,
      existingTagPaths: _existingTags,
      existingKnowledgePointTitles: _existingKnowledgePoints,
    );

HandwritingProposalPreview _previewOf(HandwritingProposal proposal) =>
    _previewSet(_setOf(<HandwritingProposal>[proposal])).previews.single;

HandwritingProposal _tagProposal({
  String id = 'tag-0',
  String title = '动量守恒',
  String parentPath = '文化课/物理/力学',
}) =>
    HandwritingProposal(
      id: id,
      kind: HandwritingProposalKind.tag,
      titleZh: title,
      fields: <String, String>{'parent_path': parentPath},
    );

HandwritingProposal _knowledgePointProposal({
  String id = 'knowledge_point-1',
  String title = '动量守恒的条件',
  String content = '系统所受合外力为零时动量守恒。',
  String? tagPath = '文化课/物理/力学',
}) =>
    HandwritingProposal(
      id: id,
      kind: HandwritingProposalKind.knowledgePoint,
      titleZh: title,
      fields: <String, String>{
        'content': content,
        if (tagPath != null) 'tag_path': tagPath,
      },
    );

HandwritingProposal _flashcardProposal({
  String id = 'flashcard-2',
  String title = '动量守恒',
  List<HandwritingCardDraft> cards = const <HandwritingCardDraft>[
    HandwritingCardDraft(
      question: '动量守恒的条件是什么？',
      answer: '系统所受合外力为零。',
    ),
  ],
  String? tagPath,
}) =>
    HandwritingProposal(
      id: id,
      kind: HandwritingProposalKind.flashcard,
      titleZh: title,
      fields: <String, String>{
        'content': '整理后的正文',
        if (tagPath != null) 'tag_path': tagPath,
      },
      cards: cards,
    );

HandwritingProposal _questionProposal({
  String id = 'question-3',
  String title = '第 3 题（动量守恒）',
  String stem = '质量 m 的物体以速度 v 运动，动量多大？',
  String? answer = 'B',
  String? solution = '由 p = mv 得 p = 3 kg·m/s。',
  List<HandwritingOptionDraft> options = const <HandwritingOptionDraft>[
    HandwritingOptionDraft(label: 'A', content: '1 kg·m/s'),
    HandwritingOptionDraft(label: 'B', content: '3 kg·m/s'),
    HandwritingOptionDraft(label: 'C', content: '5 kg·m/s'),
    HandwritingOptionDraft(label: 'D', content: '9 kg·m/s'),
  ],
  String? tagPath,
}) =>
    HandwritingProposal(
      id: id,
      kind: HandwritingProposalKind.question,
      titleZh: title,
      fields: <String, String>{
        'stem': stem,
        if (answer != null) 'answer': answer,
        if (solution != null) 'solution': solution,
        if (tagPath != null) 'tag_path': tagPath,
      },
      options: options,
    );

bool _hasChinese(String line) => RegExp(r'[\u4e00-\u9fff]').hasMatch(line);

void main() {
  group('空输入与整体结果', () {
    test('空 set：没有预览、计数为 0、可以整批确认', () {
      final preview = _previewSet(
        const HandwritingProposalSet(
          sourceRef: 'handwriting_intake/hw-empty',
          proposals: <HandwritingProposal>[],
        ),
      );
      expect(preview.sourceRef, 'handwriting_intake/hw-empty');
      expect(preview.previews, isEmpty);
      expect(preview.readyCount, 0);
      expect(preview.needsReviewCount, 0);
      expect(preview.blockedCount, 0);
      expect(preview.hasBlocked, isFalse);
      expect(preview.canApplyAll, isTrue);
    });

    test('单条 ready 提案：计数 1、canApplyAll 为真', () {
      final preview =
          _previewSet(_setOf(<HandwritingProposal>[_tagProposal()]));
      expect(preview.previews, hasLength(1));
      expect(preview.readyCount, 1);
      expect(preview.hasBlocked, isFalse);
      expect(preview.canApplyAll, isTrue);
    });

    test('有一条 blocked：hasBlocked 为真、整批不能应用', () {
      final preview = _previewSet(
        _setOf(<HandwritingProposal>[
          _tagProposal(),
          _tagProposal(id: 'tag-1', title: '动量'),
        ]),
      );
      // 第二条缺父层（parent_path 指向不存在的层）。
      final broken = previewHandwritingProposals(
        _setOf(<HandwritingProposal>[
          _tagProposal(id: 'tag-0', parentPath: '文化课/数学'),
        ]),
        existingTagPaths: _existingTags,
        existingKnowledgePointTitles: _existingKnowledgePoints,
      );
      expect(broken.blockedCount, 1);
      expect(broken.hasBlocked, isTrue);
      expect(broken.canApplyAll, isFalse);
      expect(preview.readyCount, 2);
    });

    test('三类结论混合时计数正确', () {
      final preview = _previewSet(
        _setOf(<HandwritingProposal>[
          _tagProposal(),
          _questionProposal(answer: null),
          _flashcardProposal(cards: const <HandwritingCardDraft>[]),
        ]),
      );
      expect(preview.readyCount, 1);
      expect(preview.needsReviewCount, 1);
      expect(preview.blockedCount, 1);
      expect(
          preview.previews.map((item) => item.verdict).toList(),
          <HandwritingPreviewVerdict>[
            HandwritingPreviewVerdict.ready,
            HandwritingPreviewVerdict.needsReview,
            HandwritingPreviewVerdict.blocked,
          ]);
    });

    test('同一输入两次预检结果完全相同（确定性）', () {
      final set = _setOf(<HandwritingProposal>[
        _tagProposal(),
        _knowledgePointProposal(tagPath: '文化课/化学'),
        _questionProposal(answer: null, solution: null),
      ]);
      expect(_previewSet(set).toJson(), _previewSet(set).toJson());
    });

    test('不修改传入的提案 set 与两个已有集合', () {
      final proposals = <HandwritingProposal>[_tagProposal()];
      final set = _setOf(proposals);
      final beforeSet = set.toJson();
      final tags = <String>{'文化课', '文化课/物理', '文化课/物理/力学', '文化课/化学'};
      final points = <String>{'动量'};
      previewHandwritingProposals(
        set,
        existingTagPaths: tags,
        existingKnowledgePointTitles: points,
      );
      expect(set.toJson(), beforeSet);
      expect(proposals, hasLength(1));
      expect(tags, containsAll(<String>['文化课/化学', '文化课/物理/力学']));
      expect(points, <String>{'动量'});
    });

    test('每条预览 2–5 行中文，不出现空行', () {
      final preview = _previewSet(
        _setOf(<HandwritingProposal>[
          _tagProposal(),
          _knowledgePointProposal(),
          _flashcardProposal(),
          _questionProposal(),
        ]),
      );
      for (final item in preview.previews) {
        expect(item.previewLines.length, inInclusiveRange(2, 5));
        for (final line in item.previewLines) {
          expect(line.trim(), isNotEmpty);
          expect(_hasChinese(line), isTrue);
        }
      }
    });
  });

  group('标签提案', () {
    test('父层存在、完整路径不存在：会新建标签', () {
      final preview = _previewOf(_tagProposal());
      expect(preview.verdict, HandwritingPreviewVerdict.ready);
      expect(preview.willCreate, isTrue);
      expect(preview.willReuse, isFalse);
      expect(preview.targetPath, '文化课/物理/力学/动量守恒');
      expect(preview.previewLines, contains('会新建标签「动量守恒」'));
      expect(preview.previewLines, contains('目标路径：文化课/物理/力学/动量守恒'));
      expect(preview.blockers, isEmpty);
      expect(preview.warnings, isEmpty);
    });

    test('完整路径已存在：复用已有标签', () {
      final preview = previewHandwritingProposals(
        _setOf(<HandwritingProposal>[_tagProposal()]),
        existingTagPaths: <String>{'文化课/物理/力学/动量守恒'},
        existingKnowledgePointTitles: _existingKnowledgePoints,
      ).previews.single;
      expect(preview.verdict, HandwritingPreviewVerdict.ready);
      expect(preview.willReuse, isTrue);
      expect(preview.willCreate, isFalse);
      expect(preview.previewLines, contains('会复用已有标签「动量守恒」'));
    });

    test('parent_path 为空：不能确认', () {
      final preview = _previewOf(_tagProposal(parentPath: ''));
      expect(preview.verdict, HandwritingPreviewVerdict.blocked);
      expect(preview.targetPath, isNull);
      expect(preview.willCreate, isFalse);
      expect(preview.willReuse, isFalse);
      expect(preview.blockers.single, contains('parent_path 为空'));
      expect(preview.previewLines, hasLength(2));
    });

    test('父层不在标签树：不能确认（提示先建父层或改挂别处）', () {
      final preview = _previewOf(_tagProposal(parentPath: '文化课/数学'));
      expect(preview.verdict, HandwritingPreviewVerdict.blocked);
      expect(preview.blockers.single, contains('文化课/数学'));
      expect(preview.blockers.single, contains('先建父层或改挂别处'));
      expect(preview.targetPath, '文化课/数学/动量守恒');
    });

    test('标签标题为空：不能确认', () {
      final preview = _previewOf(_tagProposal(title: '   '));
      expect(preview.verdict, HandwritingPreviewVerdict.blocked);
      expect(preview.blockers.single, contains('标签名为空'));
      expect(preview.targetPath, isNull);
    });

    test('父层路径带首尾斜杠也能归一后匹配', () {
      final preview = _previewOf(_tagProposal(parentPath: '/文化课/物理/力学/'));
      expect(preview.verdict, HandwritingPreviewVerdict.ready);
      expect(preview.targetPath, '文化课/物理/力学/动量守恒');
    });
  });

  group('知识点提案', () {
    test('标题不存在：会新建知识点并挂到已有标签', () {
      final preview = _previewOf(_knowledgePointProposal());
      expect(preview.verdict, HandwritingPreviewVerdict.ready);
      expect(preview.willCreate, isTrue);
      expect(preview.willReuse, isFalse);
      expect(preview.targetPath, '文化课/物理/力学');
      expect(preview.previewLines, contains('会新建知识点「动量守恒的条件」'));
      expect(preview.warnings, isEmpty);
    });

    test('标题已存在：复用已有知识点', () {
      final preview = _previewOf(_knowledgePointProposal(title: '动量'));
      expect(preview.verdict, HandwritingPreviewVerdict.ready);
      expect(preview.willReuse, isTrue);
      expect(preview.willCreate, isFalse);
      expect(preview.previewLines, contains('会复用已有知识点「动量」'));
    });

    test('标题为空：不能确认', () {
      final preview = _previewOf(_knowledgePointProposal(title: '  '));
      expect(preview.verdict, HandwritingPreviewVerdict.blocked);
      expect(preview.blockers.single, contains('标题为空'));
      expect(preview.previewLines, hasLength(2));
    });

    test('正文为空：可以确认前先看一眼', () {
      final preview = _previewOf(_knowledgePointProposal(content: '   '));
      expect(preview.verdict, HandwritingPreviewVerdict.needsReview);
      expect(preview.warnings.single, contains('正文为空'));
      expect(preview.blockers, isEmpty);
    });

    test('tag_path 不在标签树：警告但不阻断', () {
      final preview = _previewOf(_knowledgePointProposal(tagPath: '文化课/化学'));
      expect(preview.verdict, HandwritingPreviewVerdict.needsReview);
      expect(preview.warnings.single, contains('文化课/化学'));
      expect(preview.warnings.single, contains('先不挂到标签'));
      expect(preview.willCreate, isTrue);
    });

    test('没有 tag_path：目标路径为空，预览行写明不挂标签', () {
      final preview = _previewOf(_knowledgePointProposal(tagPath: null));
      expect(preview.targetPath, isNull);
      expect(preview.previewLines, contains('目标路径：不挂标签'));
      expect(preview.verdict, HandwritingPreviewVerdict.ready);
    });
  });

  group('闪存卡提案', () {
    test('多张卡片：会新建闪存卡并列出题型', () {
      final preview = _previewOf(
        _flashcardProposal(
          cards: const <HandwritingCardDraft>[
            HandwritingCardDraft(question: '条件？', answer: '合外力为零。'),
            HandwritingCardDraft(
              question: '动量单位？',
              answer: 'kg·m/s。',
              type: 'mcq',
            ),
          ],
        ),
      );
      expect(preview.verdict, HandwritingPreviewVerdict.ready);
      expect(preview.willCreate, isTrue);
      expect(preview.previewLines, contains('卡片 2 张（题型：essay、mcq）'));
      expect(preview.warnings, isEmpty);
    });

    test('没有卡片：不能确认', () {
      final preview = _previewOf(
        _flashcardProposal(cards: const <HandwritingCardDraft>[]),
      );
      expect(preview.verdict, HandwritingPreviewVerdict.blocked);
      expect(preview.blockers.single, contains('没有卡片'));
      expect(preview.previewLines, contains('卡片数量：0 张'));
    });

    test('卡片缺题干或答案：可以确认前先看一眼', () {
      final preview = _previewOf(
        _flashcardProposal(
          cards: const <HandwritingCardDraft>[
            HandwritingCardDraft(question: '条件？', answer: '   '),
          ],
        ),
      );
      expect(preview.verdict, HandwritingPreviewVerdict.needsReview);
      expect(preview.warnings.single, contains('1 张卡片缺题干或答案'));
    });

    test('标题是已有知识点：标记复用知识点', () {
      final preview = _previewOf(_flashcardProposal(title: '动量'));
      expect(preview.willReuse, isTrue);
      expect(preview.willCreate, isTrue);
      expect(preview.previewLines, contains('会复用已有知识点「动量」'));
      expect(preview.verdict, HandwritingPreviewVerdict.ready);
    });

    test('tag_path 不在标签树：警告但不阻断', () {
      final preview = _previewOf(_flashcardProposal(tagPath: '文化课/化学'));
      expect(preview.verdict, HandwritingPreviewVerdict.needsReview);
      expect(preview.warnings.single, contains('文化课/化学'));
      expect(preview.targetPath, '文化课/化学');
    });
  });

  group('题目提案', () {
    test('选择题有答案有解析：ready，预览行给出选项与答案', () {
      final preview = _previewOf(_questionProposal());
      expect(preview.verdict, HandwritingPreviewVerdict.ready);
      expect(preview.willCreate, isTrue);
      expect(preview.previewLines, contains('选项 4 个、答案 B'));
      expect(preview.warnings, isEmpty);
    });

    test('没有答案：needsReview', () {
      final preview = _previewOf(_questionProposal(answer: null));
      expect(preview.verdict, HandwritingPreviewVerdict.needsReview);
      expect(preview.warnings.single, contains('没有答案'));
    });

    test('没有解析：needsReview', () {
      final preview = _previewOf(_questionProposal(solution: null));
      expect(preview.verdict, HandwritingPreviewVerdict.needsReview);
      expect(preview.warnings.single, contains('没有解析'));
    });

    test('答案与解析都没有：两条 warning', () {
      final preview =
          _previewOf(_questionProposal(answer: null, solution: null));
      expect(preview.verdict, HandwritingPreviewVerdict.needsReview);
      expect(preview.warnings, hasLength(2));
    });

    test('题面为空：不能确认', () {
      final preview = _previewOf(_questionProposal(stem: '   '));
      expect(preview.verdict, HandwritingPreviewVerdict.blocked);
      expect(preview.blockers.single, contains('题面为空'));
      expect(preview.willCreate, isFalse);
      expect(preview.previewLines, hasLength(2));
    });

    test('纯文字题（无选项）有答案：ready 并写明无选项', () {
      final preview = _previewOf(
        _questionProposal(
          options: const <HandwritingOptionDraft>[],
          answer: 'p = 3 kg·m/s',
        ),
      );
      expect(preview.verdict, HandwritingPreviewVerdict.ready);
      expect(preview.previewLines, contains('无选项（纯文字题）'));
      expect(preview.previewLines, contains('答案：p = 3 kg·m/s'));
    });

    test('tag_path 存在：ready 且写目标路径', () {
      final preview = _previewOf(
        _questionProposal(tagPath: '文化课/物理/力学'),
      );
      expect(preview.verdict, HandwritingPreviewVerdict.ready);
      expect(preview.targetPath, '文化课/物理/力学');
      expect(preview.previewLines, contains('目标路径：文化课/物理/力学'));
    });

    test('tag_path 不在标签树：警告但不阻断', () {
      final preview = _previewOf(_questionProposal(tagPath: '文化课/化学'));
      expect(preview.verdict, HandwritingPreviewVerdict.needsReview);
      expect(preview.warnings.single, contains('文化课/化学'));
      expect(preview.warnings.single, contains('先不挂标签'));
    });

    test('长答案在预览行里截断，加省略号', () {
      final preview = _previewOf(
        _questionProposal(answer: 'A' * 60),
      );
      expect(preview.verdict, HandwritingPreviewVerdict.ready);
      expect(
        preview.previewLines.any((line) => line.contains('…')),
        isTrue,
      );
    });
  });

  group('同一批里重复出现', () {
    test('后出现的同 kind+title：needsReview 并指回第一条 id', () {
      final preview = _previewSet(
        _setOf(<HandwritingProposal>[
          _knowledgePointProposal(id: 'knowledge_point-0'),
          _knowledgePointProposal(id: 'knowledge_point-1'),
        ]),
      );
      expect(preview.previews[0].verdict, HandwritingPreviewVerdict.ready);
      expect(preview.previews[0].duplicateOfProposalId, isNull);
      expect(
          preview.previews[1].verdict, HandwritingPreviewVerdict.needsReview);
      expect(preview.previews[1].duplicateOfProposalId, 'knowledge_point-0');
      expect(preview.previews[1].warnings.single, contains('重复出现'));
      expect(preview.previews[1].warnings.single, contains('第 1 条'));
    });

    test('重复且自带 blocker：仍然是 blocked（blocker 优先）', () {
      final preview = _previewSet(
        _setOf(<HandwritingProposal>[
          _tagProposal(id: 'tag-0', title: '动量', parentPath: '文化课/数学'),
          _tagProposal(id: 'tag-1', title: '动量', parentPath: '文化课/数学'),
        ]),
      );
      expect(preview.previews[0].verdict, HandwritingPreviewVerdict.blocked);
      expect(preview.previews[1].verdict, HandwritingPreviewVerdict.blocked);
      expect(preview.previews[1].warnings.single, contains('重复出现'));
      expect(preview.previews[1].duplicateOfProposalId, 'tag-0');
    });

    test('同标题但不同 kind：不算重复', () {
      final preview = _previewSet(
        _setOf(<HandwritingProposal>[
          _tagProposal(title: '动量'),
          _flashcardProposal(title: '动量'),
        ]),
      );
      for (final item in preview.previews) {
        expect(item.duplicateOfProposalId, isNull);
        expect(
          item.warnings.any((warning) => warning.contains('重复出现')),
          isFalse,
        );
      }
    });

    test('三条同标题：后两条都指回第一条', () {
      final preview = _previewSet(
        _setOf(<HandwritingProposal>[
          _knowledgePointProposal(id: 'kp-0'),
          _knowledgePointProposal(id: 'kp-1'),
          _knowledgePointProposal(id: 'kp-2'),
        ]),
      );
      expect(preview.previews[1].duplicateOfProposalId, 'kp-0');
      expect(preview.previews[2].duplicateOfProposalId, 'kp-0');
      expect(preview.previews[2].warnings.single, contains('第 1 条'));
    });
  });

  group('结论标签与 JSON', () {
    test('三个结论的中文名与稳定键', () {
      expect(HandwritingPreviewVerdict.ready.storageKey, 'ready');
      expect(HandwritingPreviewVerdict.ready.labelZh, '可以确认');
      expect(HandwritingPreviewVerdict.needsReview.storageKey, 'needs_review');
      expect(HandwritingPreviewVerdict.needsReview.labelZh, '确认前看一眼');
      expect(HandwritingPreviewVerdict.blocked.storageKey, 'blocked');
      expect(HandwritingPreviewVerdict.blocked.labelZh, '不能确认');
    });

    test('单条预览 toJson 的键与值', () {
      final json = _previewOf(_tagProposal()).toJson();
      expect(json.keys.toList(), <String>[
        'proposal_id',
        'kind',
        'verdict',
        'target_path',
        'will_create',
        'will_reuse',
        'preview_lines',
        'warnings',
        'blockers',
        'duplicate_of_proposal_id',
      ]);
      expect(json['proposal_id'], 'tag-0');
      expect(json['kind'], 'tag');
      expect(json['verdict'], 'ready');
      expect(json['will_create'], isTrue);
      expect(json['duplicate_of_proposal_id'], isNull);
    });

    test('整批预览 toJson 的键与计数', () {
      final json = _previewSet(
        _setOf(<HandwritingProposal>[
          _tagProposal(),
          _tagProposal(id: 'tag-1', title: '冲量')
        ]),
      ).toJson();
      expect(json.keys.toList(), <String>[
        'source_ref',
        'previews',
        'ready_count',
        'needs_review_count',
        'blocked_count',
        'has_blocked',
        'can_apply_all',
      ]);
      expect(json['ready_count'], 2);
      expect(json['has_blocked'], isFalse);
      expect(json['can_apply_all'], isTrue);
    });

    test('预览顺序与输入提案顺序一致', () {
      final preview = _previewSet(
        _setOf(<HandwritingProposal>[
          _questionProposal(id: 'q-0'),
          _tagProposal(id: 't-1', title: '冲量'),
          _knowledgePointProposal(id: 'kp-2', title: '冲量定理'),
        ]),
      );
      expect(
        preview.previews.map((item) => item.proposalId).toList(),
        <String>['q-0', 't-1', 'kp-2'],
      );
    });

    test('isBlocked 与 blockers 一致', () {
      final preview = _previewOf(_questionProposal(stem: ''));
      expect(preview.isBlocked, isTrue);
      expect(preview.blockers, isNotEmpty);
    });
  });
}
