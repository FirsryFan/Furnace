import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/paper/paper_composer.dart';
import 'package:furnace/domain/services/paper/similar_questions.dart';
import 'package:furnace/domain/services/paper/source_level_labels.dart';
import 'package:furnace/domain/services/scheduling/domain_balance.dart'
    show KnowledgePointReading;

/// 文案打磨（task-61）的验收点：
///
///  * 相似题理由只在 `detailedReasons: true` 时追加「可核实依据」，且只写输入里
///    真有的数据（共用知识点个数、同型动作命中数、来源档位对比）；
///  * 信息缺失时一个字的废话都不追加；quality 权重为 0 时绝不提 MindNet；
///  * 组卷理由在 `detailedNotes: true` 时写清「本卷第几题、需求/质量/得分/权重」，
///    改进建议点名知识点并给下一步，背景列出本题还覆盖的知识点；
///  * 缺口解释句只解释真实缺口（题库里没有 vs 被题数/配额挤掉），并给可执行动作；
///  * 两个开关默认关闭：既有分数、排序、JSON 逐字节不变。
void main() {
  SimilarityFocus focus({
    List<String> points = const ['kp-a', 'kp-b'],
    List<String> actions = const ['first_principles', 'sanity_check'],
    String subject = '数学',
    String source = 'unknown',
  }) =>
      SimilarityFocus(
        questionId: 'q-focus',
        knowledgePointIds: points,
        subjectKey: subject,
        difficulty: 5,
        actionTypes: actions,
        sourceLevel: source,
      );

  SimilarityCandidate candidate(
    String id, {
    List<String> points = const ['kp-a'],
    List<String> actions = const [],
    String subject = '数学',
    String source = 'unknown',
    double? difficulty = 5,
  }) =>
      SimilarityCandidate(
        questionId: id,
        knowledgePointIds: points,
        subjectKey: subject,
        sourceLevel: source,
        difficulty: difficulty,
        actionTypes: actions,
      );

  PaperCandidate paperCandidate({
    required String id,
    String subject = '数学',
    String source = 'gaokao',
    double? difficulty,
    double? quality,
    List<String> points = const ['kp-1'],
  }) =>
      PaperCandidate(
        questionId: id,
        subjectKey: subject,
        sourceLevel: source,
        difficulty: difficulty,
        aiQuality: quality,
        matchedKnowledgePointIds: points,
      );

  KnowledgePointReading reading(
    String id, {
    bool danger = false,
    bool development = false,
  }) =>
      KnowledgePointReading(
        knowledgePointId: id,
        inDangerZone: danger,
        inDevelopmentZone: development,
      );

  group('相似题理由：可核实依据（detailedReasons）', () {
    test('默认关闭：理由与显式 false 完全一致，且没有可核实依据', () {
      final f = focus(points: ['kp-a']);
      final cands = [
        candidate('c1', points: ['kp-a'])
      ];
      final plain =
          SimilarQuestionFinder.rank(focus: f, candidates: cands).single;
      final explicit = SimilarQuestionFinder.rank(
        focus: f,
        candidates: cands,
        detailedReasons: false,
      ).single;
      expect(plain.reasonZh, isNot(contains('可核实依据')));
      expect(plain.reasonZh, explicit.reasonZh);
    });

    test('点名共用知识点的个数（聚焦题侧是分母）', () {
      final f = focus(points: ['kp-a', 'kp-b']);
      final one = SimilarQuestionFinder.rank(
        focus: f,
        candidates: [
          candidate('c1', points: ['kp-a'])
        ],
        detailedReasons: true,
      ).single;
      expect(one.reasonZh, contains('共用知识点 1/2 个'));
      final both = SimilarQuestionFinder.rank(
        focus: f,
        candidates: [
          candidate('c1', points: ['kp-a', 'kp-b'])
        ],
        detailedReasons: true,
      ).single;
      expect(both.reasonZh, contains('共用知识点 2/2 个'));
    });

    test('点名同型动作命中几个（对比聚焦题的步骤数）', () {
      final f = focus(
          points: ['kp-a'], actions: ['first_principles', 'sanity_check']);
      final ranked = SimilarQuestionFinder.rank(
        focus: f,
        candidates: [
          candidate('c1', points: ['kp-a'], actions: ['first_principles']),
        ],
        detailedReasons: true,
      ).single;
      expect(ranked.reasonZh, contains('同型动作命中 1 个（聚焦题 2 步）'));
    });

    test('来源档位对比：候选高于/低于/同档都说清楚', () {
      final higher = SimilarQuestionFinder.rank(
        focus: focus(points: ['kp-a'], source: 'school'),
        candidates: [
          candidate('c1', points: ['kp-a'], source: 'gaokao')
        ],
        detailedReasons: true,
      ).single;
      expect(higher.reasonZh, contains('候选题「高考真题」高于聚焦题「校内题」'));
      final lower = SimilarQuestionFinder.rank(
        focus: focus(points: ['kp-a'], source: 'gaokao'),
        candidates: [
          candidate('c1', points: ['kp-a'], source: 'school')
        ],
        detailedReasons: true,
      ).single;
      expect(lower.reasonZh, contains('候选题「校内题」低于聚焦题「高考真题」'));
      final same = SimilarQuestionFinder.rank(
        focus: focus(points: ['kp-a'], source: 'gaokao'),
        candidates: [
          candidate('c1', points: ['kp-a'], source: 'gaokao')
        ],
        detailedReasons: true,
      ).single;
      expect(same.reasonZh, contains('与聚焦题「高考真题」同档'));
    });

    test('来源不知道就不做档位对比（不猜）', () {
      final ranked = SimilarQuestionFinder.rank(
        focus: focus(points: ['kp-a']),
        candidates: [
          candidate('c1', points: ['kp-a'], source: 'gaokao')
        ],
        detailedReasons: true,
      ).single;
      expect(ranked.reasonZh, isNot(contains('来源档位')));
    });

    test('没有共用知识点也没有同型动作：不追加可核实依据', () {
      final f = focus(points: ['kp-a']);
      final cands = [
        candidate('c1', points: ['kp-x'], difficulty: null)
      ];
      final plain = SimilarQuestionFinder.rank(
        focus: f,
        candidates: cands,
        minScore: 0,
      ).single;
      final detailed = SimilarQuestionFinder.rank(
        focus: f,
        candidates: cands,
        minScore: 0,
        detailedReasons: true,
      ).single;
      expect(detailed.reasonZh, isNot(contains('可核实依据')));
      expect(detailed.reasonZh, plain.reasonZh);
    });

    test('detailedReasons 不改分数、分量与排序', () {
      final f = focus(points: ['kp-a', 'kp-b']);
      final cands = [
        candidate('c1',
            points: ['kp-a'], source: 'gaokao', actions: ['first_principles']),
        candidate('c2', points: ['kp-a', 'kp-b'], source: 'school'),
      ];
      final plain = SimilarQuestionFinder.rank(focus: f, candidates: cands);
      final detailed = SimilarQuestionFinder.rank(
        focus: f,
        candidates: cands,
        detailedReasons: true,
      );
      expect(
        [for (final item in detailed) item.questionId],
        [for (final item in plain) item.questionId],
      );
      for (var i = 0; i < plain.length; i++) {
        expect(detailed[i].score, plain[i].score);
        expect(jsonEncode(detailed[i].components),
            jsonEncode(plain[i].components));
      }
    });

    test('quality 权重为 0：即使有危险区读数也不提 MindNet', () {
      final ranked = SimilarQuestionFinder.rank(
        focus: focus(points: ['kp-a']),
        candidates: [
          candidate('c1', points: ['kp-a'])
        ],
        knowledgePointReadings: {'kp-a': reading('kp-a', danger: true)},
        detailedReasons: true,
      ).single;
      expect(ranked.reasonZh, isNot(contains('MindNet')));
    });

    test('quality 权重开启：MindNet 有效性读数仍进理由', () {
      final ranked = SimilarQuestionFinder.rank(
        focus: focus(points: ['kp-a']),
        candidates: [
          candidate('c1', points: ['kp-a'])
        ],
        weights: const SimilarityWeights(quality: 1.0),
        knowledgePointReadings: {'kp-a': reading('kp-a', danger: true)},
        detailedReasons: true,
      ).single;
      expect(ranked.reasonZh, contains('MindNet 有效性 0.85'));
    });

    test('同一输入两次调用理由相同（确定性）', () {
      final f = focus(points: ['kp-a', 'kp-b'], source: 'school');
      final cands = [
        candidate('c1', points: ['kp-a'], source: 'gaokao'),
        candidate('c2', points: ['kp-a', 'kp-b'], source: 'school'),
      ];
      final a = SimilarQuestionFinder.rank(
        focus: f,
        candidates: cands,
        detailedReasons: true,
      );
      final b = SimilarQuestionFinder.rank(
        focus: f,
        candidates: cands,
        detailedReasons: true,
      );
      expect(
        [for (final item in a) item.reasonZh],
        [for (final item in b) item.reasonZh],
      );
    });
  });

  group('组卷文案：详细理由与缺口解释（detailedNotes）', () {
    test('默认关闭：JSON 与显式 false 逐字节一致，也不出缺口解释键', () {
      final cands = [paperCandidate(id: 'c1')];
      final readings = [reading('kp-1', danger: true)];
      final plain = PaperComposer.compose(
        candidates: cands,
        spec: const PaperSpec(targetCount: 1),
        readings: readings,
      );
      final explicit = PaperComposer.compose(
        candidates: cands,
        spec: const PaperSpec(targetCount: 1),
        readings: readings,
        detailedNotes: false,
      );
      expect(jsonEncode(plain.toJson()), jsonEncode(explicit.toJson()));
      expect(plain.toJson().containsKey('uncovered_knowledge_point_notes'),
          isFalse);
      expect(plain.toJson().containsKey('deferred_knowledge_point_notes'),
          isFalse);
      expect(plain.items.single.reasonZh, isNot(contains('本卷第')));
    });

    test('详细理由写清第几题、需求、质量分、综合得分与权重', () {
      final plan = PaperComposer.compose(
        candidates: [paperCandidate(id: 'c1')],
        spec: const PaperSpec(targetCount: 1),
        readings: [reading('kp-1', danger: true)],
        knowledgePointTagPaths: {
          'kp-1': ['数学', '函数', '函数单调性'],
        },
        detailedNotes: true,
      );
      final reason = plan.items.single.reasonZh;
      expect(reason, startsWith('本卷第 1 题。'));
      expect(reason, contains('危险区'));
      expect(reason, contains('需求 1.00（危险区）'));
      expect(reason, contains('质量分 0.70（来源 高考真题）'));
      expect(reason, contains('综合得分'));
      expect(reason, contains('排序权重 需求 0.55 / 质量 0.25 / 难度贴合 0.20'));
    });

    test('低分题不吹好：只报真实需求分与综合得分', () {
      final plan = PaperComposer.compose(
        candidates: [
          paperCandidate(id: 'c1', points: ['kp-x'])
        ],
        spec: const PaperSpec(targetCount: 1),
        weights: const PaperWeights(need: 1, quality: 0, difficultyFit: 0),
        detailedNotes: true,
      );
      final item = plan.items.single;
      expect(item.zone, PaperZone.unknown);
      expect(item.reasonZh, contains('需求 0.35（没有读数）'));
      expect(item.reasonZh, contains('综合得分 0.35'));
    });

    test('改进建议点名知识点并给下一步动作', () {
      final plan = PaperComposer.compose(
        candidates: [paperCandidate(id: 'c1')],
        spec: const PaperSpec(targetCount: 1),
        readings: [reading('kp-1', danger: true)],
        knowledgePointTagPaths: {
          'kp-1': ['数学', '函数', '函数单调性'],
        },
        detailedNotes: true,
      );
      final note = plan.items.single.improvementNote;
      expect(note, contains('为知识点「函数单调性」：'));
      expect(note, contains('下一步：做完把这题的结果记进系统'));
    });

    test('背景列出本题还覆盖的其他知识点', () {
      final plan = PaperComposer.compose(
        candidates: [
          paperCandidate(id: 'c1', points: ['kp-1', 'kp-2']),
        ],
        spec: const PaperSpec(targetCount: 1),
        knowledgePointTagPaths: {
          'kp-1': ['数学', '函数', '函数单调性'],
          'kp-2': ['数学', '函数', '定义域'],
        },
        detailedNotes: true,
      );
      final item = plan.items.single;
      expect(item.knowledgePointId, 'kp-1');
      expect(item.backgroundZh, startsWith('数学 / 函数 / 函数单调性'));
      expect(item.backgroundZh, contains('本题还覆盖：定义域'));
    });

    test('未覆盖知识点：说清题库里没有，并禁止模型生成', () {
      final plan = PaperComposer.compose(
        candidates: [paperCandidate(id: 'c1')],
        spec: const PaperSpec(targetCount: 1),
        readings: [
          reading('kp-1', danger: true),
          reading('kp-2', danger: true),
        ],
        knowledgePointNames: {'kp-2': '函数的零点'},
        detailedNotes: true,
      );
      expect(plan.uncoveredKnowledgePointIds, ['kp-2']);
      final note = plan.uncoveredKnowledgePointNotes.single;
      expect(note.knowledgePointId, 'kp-2');
      expect(note.labelZh, '函数的零点');
      expect(note.messageZh, contains('危险区'));
      expect(note.messageZh, contains('题库里一道候选都没有'));
      expect(note.messageZh, contains('不要用模型生成'));
    });

    test('被挤掉的知识点：报真实可用候选数并给可执行的调整动作', () {
      final plan = PaperComposer.compose(
        candidates: [
          paperCandidate(id: 'c1', points: ['kp-1']),
          paperCandidate(id: 'c2', points: ['kp-2']),
        ],
        spec: const PaperSpec(targetCount: 1),
        readings: [
          reading('kp-1', danger: true),
          reading('kp-2', danger: true),
        ],
        detailedNotes: true,
      );
      expect(plan.deferredKnowledgePointIds, ['kp-2']);
      final note = plan.deferredKnowledgePointNotes.single;
      expect(note.knowledgePointId, 'kp-2');
      expect(note.messageZh, contains('1 道可用候选'));
      expect(note.messageZh, contains('把目标题数调大'));
    });

    test('缺口解释键插在 deferred_knowledge_points 之后（toJson 顺序）', () {
      final plan = PaperComposer.compose(
        candidates: [
          paperCandidate(id: 'c1', points: ['kp-1']),
          paperCandidate(id: 'c2', points: ['kp-2']),
        ],
        spec: const PaperSpec(targetCount: 1),
        readings: [
          reading('kp-1', danger: true),
          reading('kp-2', danger: true),
          reading('kp-3', danger: true),
        ],
        detailedNotes: true,
      );
      final keys = plan.toJson().keys.toList();
      final uncoveredIndex = keys.indexOf('uncovered_knowledge_point_notes');
      final deferredIndex = keys.indexOf('deferred_knowledge_point_notes');
      expect(uncoveredIndex,
          greaterThan(keys.indexOf('deferred_knowledge_points')));
      expect(deferredIndex, greaterThan(uncoveredIndex));
      expect(deferredIndex, lessThan(keys.indexOf('by_knowledge_point')));
      expect(plan.uncoveredKnowledgePointIds, ['kp-3']);
      expect(plan.deferredKnowledgePointIds, ['kp-2']);
      final json = plan.toJson();
      final uncoveredJson =
          (json['uncovered_knowledge_point_notes'] as List).single;
      expect(uncoveredJson, isA<Map<String, Object?>>());
      expect((uncoveredJson as Map<String, Object?>)['knowledge_point_id'],
          'kp-3');
    });

    test('detailedNotes 不改题量、分数与顺序', () {
      final cands = [
        paperCandidate(id: 'c1', points: ['kp-1']),
        paperCandidate(id: 'c2', points: ['kp-2']),
      ];
      final readings = [
        reading('kp-1', danger: true),
        reading('kp-2', development: true),
      ];
      final plain = PaperComposer.compose(
        candidates: cands,
        spec: const PaperSpec(targetCount: 2),
        readings: readings,
      );
      final detailed = PaperComposer.compose(
        candidates: cands,
        spec: const PaperSpec(targetCount: 2),
        readings: readings,
        detailedNotes: true,
      );
      expect(
        [for (final item in detailed.items) item.questionId],
        [for (final item in plain.items) item.questionId],
      );
      for (var i = 0; i < plain.items.length; i++) {
        expect(detailed.items[i].score, plain.items[i].score);
        expect(detailed.items[i].zone, plain.items[i].zone);
      }
      expect(detailed.byKnowledgePoint, plain.byKnowledgePoint);
    });

    test('空库不抛异常，也不产出缺口解释句', () {
      final plan = PaperComposer.compose(
        candidates: const [],
        spec: const PaperSpec(targetCount: 0),
        detailedNotes: true,
      );
      expect(plan.isEmpty, isTrue);
      expect(plan.uncoveredKnowledgePointNotes, isEmpty);
      expect(plan.deferredKnowledgePointNotes, isEmpty);
    });

    test('同一输入两次详细卷的 JSON 相同（确定性）', () {
      final cands = [paperCandidate(id: 'c1')];
      final readings = [reading('kp-1', danger: true)];
      final first = PaperComposer.compose(
        candidates: cands,
        spec: const PaperSpec(targetCount: 1),
        readings: readings,
        detailedNotes: true,
      );
      final second = PaperComposer.compose(
        candidates: cands,
        spec: const PaperSpec(targetCount: 1),
        readings: readings,
        detailedNotes: true,
      );
      expect(jsonEncode(first.toJson()), jsonEncode(second.toJson()));
    });
  });

  group('PaperGapNote 与来源档位名字表', () {
    test('PaperGapNote.toJson 只用 snake_case 三个键', () {
      const note = PaperGapNote(
        knowledgePointId: 'kp-1',
        labelZh: '函数单调性',
        messageZh: '先收题。',
      );
      expect(note.toJson(), {
        'knowledge_point_id': 'kp-1',
        'label_zh': '函数单调性',
        'message': '先收题。',
      });
    });

    test('sourceLevelLabel 覆盖六档，未知 key 原样返回', () {
      expect(sourceLevelLabel('gaokao'), '高考真题');
      expect(sourceLevelLabel(' provincial_diagnostic '), '省市诊断');
      expect(sourceLevelLabel('elite_school'), '名校测试');
      expect(sourceLevelLabel('school'), '校内题');
      expect(sourceLevelLabel('personal'), '自建题');
      expect(sourceLevelLabel('unknown'), 'unknown');
      expect(sourceLevelLabel('made_up'), 'made_up');
    });
  });
}
