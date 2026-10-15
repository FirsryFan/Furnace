import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/paper/similar_questions.dart';

/// 找相似题（Q12）纯逻辑的验收点：
///
///  * 共用知识点 / 同型动作序列 / 同学科 / 难度接近四个信号按权重合成；
///  * 动作序列按**顺序**比对（LCS），不是集合；
///  * 跨学科但动作同型 → 明确标成迁移候选；
///  * "不知道"（缺学科、缺难度）取中性，不冒充"很像"；
///  * 弱信号（只是同学科同难度）不过阈值；
///  * tie-break 与输入顺序无关（同一输入永远同一输出）。
void main() {
  const focus = SimilarityFocus(
    questionId: 'q-focus',
    knowledgePointIds: ['kp-a', 'kp-b'],
    subjectKey: '数学',
    difficulty: 5,
    actionTypes: ['first_principles', 'sanity_check'],
  );

  SimilarityCandidate candidate(
    String id, {
    List<String> knowledgePointIds = const [],
    String subjectKey = '数学',
    String sourceLevel = 'unknown',
    double? difficulty = 5,
    List<String> actionTypes = const [],
  }) =>
      SimilarityCandidate(
        questionId: id,
        knowledgePointIds: knowledgePointIds,
        subjectKey: subjectKey,
        sourceLevel: sourceLevel,
        difficulty: difficulty,
        actionTypes: actionTypes,
      );

  test('共用知识点越多越像：排序与分量都对', () {
    final ranked = SimilarQuestionFinder.rank(
      focus: focus,
      candidates: [
        candidate('q-one', knowledgePointIds: ['kp-a']),
        candidate('q-both', knowledgePointIds: ['kp-a', 'kp-b']),
      ],
    );

    expect(ranked.map((r) => r.questionId).toList(), ['q-both', 'q-one']);
    expect(ranked.first.components['knowledge_point'], closeTo(1.0, 1e-9));
    expect(ranked.last.components['knowledge_point'], closeTo(0.5, 1e-9));
    expect(ranked.first.sharedKnowledgePointIds, ['kp-a', 'kp-b']);
    expect(ranked.first.score, greaterThan(ranked.last.score));
  });

  test('自己不推荐自己', () {
    final ranked = SimilarQuestionFinder.rank(
      focus: focus,
      candidates: [
        candidate('q-focus', knowledgePointIds: ['kp-a', 'kp-b']),
        candidate(' q-focus ', knowledgePointIds: ['kp-a']),
        candidate('q-other', knowledgePointIds: ['kp-a']),
      ],
    );

    expect(ranked.map((r) => r.questionId).toList(), ['q-other']);
  });

  test('跨学科但动作同型 → 入榜并标成迁移候选', () {
    final ranked = SimilarQuestionFinder.rank(
      focus: focus,
      candidates: [
        candidate(
          'q-language',
          subjectKey: '语文',
          actionTypes: ['first_principles', 'sanity_check'],
        ),
      ],
    );

    final only = ranked.single;
    expect(only.questionId, 'q-language');
    expect(only.crossSubjectTransfer, isTrue);
    expect(only.sharedActionTypes, ['first_principles', 'sanity_check']);
    expect(only.components['action_type'], closeTo(1.0, 1e-9));
    expect(only.components['subject'], 0.0);
    expect(only.reasonZh, contains('跨学科迁移'));
  });

  test('动作序列按顺序比对（LCS），顺序反了分更低', () {
    const sequenceFocus = SimilarityFocus(
      questionId: 'q-focus',
      subjectKey: '数学',
      actionTypes: ['induction', 'case_split', 'sanity_check'],
    );
    final ranked = SimilarQuestionFinder.rank(
      focus: sequenceFocus,
      candidates: [
        candidate(
          'q-reversed',
          actionTypes: ['sanity_check', 'case_split', 'induction'],
        ),
        candidate(
          'q-same',
          actionTypes: ['induction', 'case_split', 'sanity_check'],
        ),
      ],
    );

    expect(ranked.map((r) => r.questionId).toList(), ['q-same', 'q-reversed']);
    expect(ranked.first.components['action_type'], closeTo(1.0, 1e-9));
    // 逆序的 LCS 只有 1 步（`case_split`），3 步里的 1/3。
    expect(ranked.last.components['action_type'], closeTo(1 / 3, 1e-9));
    expect(
      SimilarQuestionFinder.actionSequenceOverlap(
        const ['induction', 'case_split'],
        const ['induction', 'case_split'],
      ),
      closeTo(1.0, 1e-9),
    );
    expect(
      SimilarQuestionFinder.actionSequenceOverlap(
        const [],
        const ['induction'],
      ),
      0,
    );
  });

  test('缺学科 / 缺难度取中性，不惩罚"不知道"', () {
    const unknownFocus = SimilarityFocus(
      questionId: 'q-focus',
      knowledgePointIds: ['kp-a'],
      actionTypes: ['induction'],
    );
    final ranked = SimilarQuestionFinder.rank(
      focus: unknownFocus,
      candidates: [
        candidate(
          'q-quiet',
          knowledgePointIds: ['kp-a'],
          subjectKey: '',
          difficulty: null,
          actionTypes: ['induction'],
        ),
      ],
    );

    final components = ranked.single.components;
    expect(components['subject'], closeTo(0.5, 1e-9));
    expect(components['difficulty'], closeTo(0.5, 1e-9));
    expect(components['knowledge_point'], closeTo(1.0, 1e-9));
  });

  test('难度差越大分量越低', () {
    final ranked = SimilarQuestionFinder.rank(
      focus: focus,
      candidates: [
        candidate('q-close', knowledgePointIds: ['kp-a'], difficulty: 3),
        candidate('q-far', knowledgePointIds: ['kp-a'], difficulty: 9),
      ],
    );

    final byId = {for (final r in ranked) r.questionId: r};
    expect(
      byId['q-close']!.components['difficulty']!,
      greaterThan(byId['q-far']!.components['difficulty']!),
    );
    expect(byId['q-close']!.score, greaterThan(byId['q-far']!.score));
  });

  test('弱信号不过阈值：只是同学科 + 同难度不进榜', () {
    final ranked = SimilarQuestionFinder.rank(
      focus: focus,
      candidates: [candidate('q-stranger')],
    );

    expect(ranked, isEmpty);
    // 阈值可以调低，但那就不是"相似"而是"随便给一道"了。
    expect(
      SimilarQuestionFinder.rank(
        focus: focus,
        candidates: [candidate('q-stranger')],
        minScore: 0,
      ),
      hasLength(1),
    );
  });

  test('limit 取前 N；limit <= 0 视为不限', () {
    final candidates = [
      for (var i = 0; i < 4; i++)
        candidate('q-$i', knowledgePointIds: ['kp-a']),
    ];
    expect(
      SimilarQuestionFinder.rank(
          focus: focus, candidates: candidates, limit: 2),
      hasLength(2),
    );
    expect(
      SimilarQuestionFinder.rank(
          focus: focus, candidates: candidates, limit: 0),
      hasLength(4),
    );
  });

  test('调权能改变排序：动作权重拉高后跨学科同型排在同学科有点之前', () {
    final candidates = [
      // 同学科、共用一半知识点，但思维链不同型。
      candidate('q-same-subject',
          knowledgePointIds: ['kp-a'], actionTypes: ['extreme_case']),
      // 跨学科、但动作完全同型。
      candidate(
        'q-cross-subject',
        subjectKey: '语文',
        actionTypes: ['first_principles', 'sanity_check'],
      ),
    ];

    final byDefault =
        SimilarQuestionFinder.rank(focus: focus, candidates: candidates);
    expect(byDefault.first.questionId, 'q-same-subject');

    final actionLed = SimilarQuestionFinder.rank(
      focus: focus,
      candidates: candidates,
      minScore: 0,
      weights: const SimilarityWeights(
        knowledgePoint: 0.1,
        actionType: 1.0,
        subject: 0,
        difficulty: 0,
      ),
    );
    expect(actionLed.first.questionId, 'q-cross-subject');
  });

  test('tie-break：同分比来源分级，再比题目 id；与输入顺序无关', () {
    final candidates = [
      candidate('q-personal',
          knowledgePointIds: ['kp-a'], sourceLevel: 'personal'),
      candidate('q-gaokao', knowledgePointIds: ['kp-a'], sourceLevel: 'gaokao'),
    ];

    final forward =
        SimilarQuestionFinder.rank(focus: focus, candidates: candidates);
    expect(
        forward.map((r) => r.questionId).toList(), ['q-gaokao', 'q-personal']);

    final reversed = SimilarQuestionFinder.rank(
      focus: focus,
      candidates: candidates.reversed.toList(),
    );
    expect(reversed.map((r) => r.questionId).toList(),
        forward.map((r) => r.questionId).toList());

    // 完全同分、同来源时按题目 id 升序，仍然是确定性的。
    final sameScore = SimilarQuestionFinder.rank(
      focus: focus,
      candidates: [
        candidate('q-b', knowledgePointIds: ['kp-a']),
        candidate('q-a', knowledgePointIds: ['kp-a']),
      ],
    );
    expect(sameScore.map((r) => r.questionId).toList(), ['q-a', 'q-b']);
  });

  test('reasonZh 说清楚为什么像，并能列出"没有可对照信号"的兜底', () {
    // 未知动作要**两侧都有**才会进"同型步骤"（理由只讲重合上的动作）。
    const richFocus = SimilarityFocus(
      questionId: 'q-focus',
      knowledgePointIds: ['kp-a'],
      subjectKey: '数学',
      difficulty: 5,
      actionTypes: ['first_principles', 'made_up_action'],
    );
    final ranked = SimilarQuestionFinder.rank(
      focus: richFocus,
      candidates: [
        candidate(
          'q-rich',
          knowledgePointIds: ['kp-a'],
          sourceLevel: 'gaokao',
          difficulty: 6,
          actionTypes: ['first_principles', 'made_up_action'],
        ),
      ],
      knowledgePointNames: const {'kp-a': '二次函数最值'},
      minScore: 0,
    );

    final reason = ranked.single.reasonZh;
    expect(reason, contains('共用知识点「二次函数最值」'));
    expect(reason, contains('同型步骤'));
    // 词表里查不到的动作原样显示 key，不隐藏未知。
    expect(reason, contains('made_up_action'));
    expect(reason, contains('难度 5.00 vs 6.00'));
    expect(reason, contains('来源：高考真题'));

    // 兜底：只有弱信号且阈值被调低时，理由不能说"共用知识点"。
    final weak = SimilarQuestionFinder.rank(
      focus: focus,
      candidates: [candidate('q-stranger')],
      minScore: 0,
      weights: const SimilarityWeights(
        knowledgePoint: 0,
        actionType: 0,
        subject: 1,
        difficulty: 0,
      ),
    );
    expect(weak.single.reasonZh, contains('还没有可对照的知识点或思维链'));
  });

  test('输入清洗：空白 id / 空动作被丢掉，重复知识点只算一次', () {
    final ranked = SimilarQuestionFinder.rank(
      focus: const SimilarityFocus(
        questionId: 'q-focus',
        knowledgePointIds: [' kp-a ', 'kp-a', '', '  '],
        actionTypes: ['induction', ' ', 'induction'],
      ),
      candidates: [
        candidate('q-x', knowledgePointIds: ['kp-a', 'kp-a']),
      ],
    );

    expect(ranked.single.components['knowledge_point'], closeTo(1.0, 1e-9));
    expect(
      SimilarQuestionFinder.knowledgePointOverlap(
        focus: const ['kp-a', 'kp-a'],
        candidate: const [' kp-a '],
      ),
      closeTo(1.0, 1e-9),
    );
    expect(
        SimilarQuestionFinder.knowledgePointOverlap(
            focus: const [], candidate: const ['kp-a']),
        0);
  });

  test('toJson 带分量、同型动作与跨学科标记', () {
    final ranked = SimilarQuestionFinder.rank(
      focus: focus,
      candidates: [
        candidate('q-language',
            subjectKey: '语文',
            actionTypes: ['first_principles', 'sanity_check']),
      ],
    );

    final json = ranked.single.toJson();
    expect(json['question_id'], 'q-language');
    expect(json['cross_subject_transfer'], isTrue);
    expect(json['shared_action_types'], ['first_principles', 'sanity_check']);
    expect((json['components']! as Map<String, double>).keys,
        contains('knowledge_point'));
    expect(json['reason_zh'], isA<String>());
  });

  test('空候选列表不抛', () {
    expect(
      SimilarQuestionFinder.rank(focus: focus, candidates: const []),
      isEmpty,
    );
  });
}
