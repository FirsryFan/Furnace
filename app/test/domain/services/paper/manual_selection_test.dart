import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/paper/domain_quota.dart';
import 'package:furnace/domain/services/paper/paper_composer.dart';
import 'package:furnace/domain/services/paper/subject_quota.dart';
import 'package:furnace/domain/services/scheduling/domain_balance.dart'
    show KnowledgePointReading;

PaperCandidate _candidate({
  required String id,
  String subject = '数学',
  String source = 'gaokao',
  List<String> points = const ['kp-1'],
}) =>
    PaperCandidate(
      questionId: id,
      subjectKey: subject,
      sourceLevel: source,
      matchedKnowledgePointIds: points,
    );

KnowledgePointReading _reading(
  String knowledgePointId, {
  bool danger = false,
  bool development = false,
}) =>
    KnowledgePointReading(
      knowledgePointId: knowledgePointId,
      inDangerZone: danger,
      inDevelopmentZone: development,
    );

List<String> _ids(PaperPlan plan) => [
      for (final item in plan.items) item.questionId,
    ];

Map<String, List<String>> _paths(Map<String, String> domainByPoint) => {
      for (final entry in domainByPoint.entries)
        entry.key: ['${entry.value}/章节'],
    };

const List<String> _baseKeys = [
  'schema',
  'items',
  'uncovered_knowledge_points',
  'deferred_knowledge_points',
  'by_knowledge_point',
  'candidate_count',
  'requested_count',
  'is_short',
  'overall_need',
  'weights',
];

const List<String> _manualKeys = [
  'manual_included_count',
  'manual_missing_question_ids',
  'manual_skipped_question_ids',
  'manual_conflict_question_ids',
];

void main() {
  group('PaperComposer 手工指定/排除（默认关闭）', () {
    test('默认 null 时开关关闭、字段取默认值', () {
      final plan = PaperComposer.compose(
        candidates: [_candidate(id: 'q-1'), _candidate(id: 'q-2')],
        spec: const PaperSpec(targetCount: 2),
      );
      expect(plan.manualSelectionEnabled, isFalse);
      expect(plan.manualIncludedCount, 0);
      expect(plan.manualMissingQuestionIds, isEmpty);
      expect(plan.manualSkippedQuestionIds, isEmpty);
      expect(plan.manualConflictQuestionIds, isEmpty);
      expect(_ids(plan), ['q-1', 'q-2']);
      expect(plan.toJson().keys.toList(), _baseKeys);
    });

    test('默认 null 与显式 null 的输出逐字节一致', () {
      PaperPlan build({bool explicitNull = false}) => PaperComposer.compose(
            candidates: [
              _candidate(id: 'q-1'),
              _candidate(id: 'q-2', source: 'school'),
            ],
            spec: explicitNull
                ? const PaperSpec(
                    targetCount: 2,
                    manualIncludeQuestionIds: null,
                    manualExcludeQuestionIds: null,
                  )
                : const PaperSpec(targetCount: 2),
            readings: [_reading('kp-1', danger: true)],
          );
      expect(jsonEncode(build().toJson()),
          jsonEncode(build(explicitNull: true).toJson()));
    });

    test('启用后 toJson 追加手工四键，位置在旧十键之后', () {
      final plan = PaperComposer.compose(
        candidates: [_candidate(id: 'q-1')],
        spec: const PaperSpec(
          targetCount: 1,
          manualIncludeQuestionIds: {'q-1'},
        ),
      );
      expect(plan.toJson().keys.toList(), [..._baseKeys, ..._manualKeys]);
    });

    test('空 include 集也算启用：开关为 true，但没有必收题', () {
      final plan = PaperComposer.compose(
        candidates: [_candidate(id: 'q-1')],
        spec: const PaperSpec(
          targetCount: 1,
          manualIncludeQuestionIds: <String>{},
        ),
      );
      expect(plan.manualSelectionEnabled, isTrue);
      expect(plan.manualIncludedCount, 0);
      expect(plan.manualMissingQuestionIds, isEmpty);
      expect(plan.manualSkippedQuestionIds, isEmpty);
      expect(plan.manualConflictQuestionIds, isEmpty);
      expect(_ids(plan), ['q-1']);
      final json = plan.toJson();
      for (final key in _manualKeys) {
        expect(json.containsKey(key), isTrue, reason: key);
      }
      expect(json['manual_missing_question_ids'], isEmpty);
    });

    test('只给排除集也算启用', () {
      final plan = PaperComposer.compose(
        candidates: [_candidate(id: 'q-1'), _candidate(id: 'q-2')],
        spec: const PaperSpec(
          targetCount: 2,
          manualExcludeQuestionIds: {'q-2'},
        ),
      );
      expect(plan.manualSelectionEnabled, isTrue);
      expect(_ids(plan), ['q-1']);
      expect(plan.manualIncludedCount, 0);
      final json = plan.toJson();
      for (final key in _manualKeys) {
        expect(json.containsKey(key), isTrue, reason: key);
      }
    });

    test('领域配额与手工同时启用时，toJson 键顺序 = 旧十键 + 领域四键 + 手工四键', () {
      final plan = PaperComposer.compose(
        candidates: [_candidate(id: 'q-1')],
        spec: const PaperSpec(
          targetCount: 1,
          domainQuota: DomainQuota(maxPerDomain: {'数学': 5}),
          manualIncludeQuestionIds: {'q-1'},
        ),
        knowledgePointTagPaths: _paths({'kp-1': '数学'}),
      );
      expect(plan.toJson().keys.toList(), [
        ..._baseKeys,
        'by_domain',
        'quota_blocked_by_domain',
        'domain_shortfalls',
        'domain_quota',
        ..._manualKeys,
      ]);
    });
  });

  group('PaperComposer 手工必收', () {
    test('必收题绕过学科过滤', () {
      final plan = PaperComposer.compose(
        candidates: [
          _candidate(id: 'q-math', points: const ['kp-m']),
          _candidate(id: 'q-phy', subject: '物理', points: const ['kp-p']),
        ],
        spec: const PaperSpec(
          targetCount: 2,
          subjectKeys: {'物理'},
          manualIncludeQuestionIds: {'q-math'},
        ),
        readings: [
          _reading('kp-m', danger: true),
          _reading('kp-p', danger: true)
        ],
      );
      expect(_ids(plan), ['q-math', 'q-phy']);
      expect(plan.manualIncludedCount, 1);
    });

    test('必收题绕过来源下限过滤', () {
      final plan = PaperComposer.compose(
        candidates: [
          _candidate(id: 'q-gaokao', points: const ['kp-1']),
          _candidate(id: 'q-school', source: 'school', points: const ['kp-2']),
        ],
        spec: const PaperSpec(
          targetCount: 2,
          minSourceLevel: 'gaokao',
          manualIncludeQuestionIds: {'q-school'},
        ),
        readings: [
          _reading('kp-1', danger: true),
          _reading('kp-2', danger: true)
        ],
      );
      expect(_ids(plan), ['q-school', 'q-gaokao']);
      expect(plan.items.first.sourceLevel, 'school');
      expect(plan.manualIncludedCount, 1);
    });

    test('必收题不受每知识点上限限制', () {
      final plan = PaperComposer.compose(
        candidates: [
          _candidate(id: 'q-1', points: const ['kp-1']),
          _candidate(id: 'q-2', points: const ['kp-1']),
          _candidate(id: 'q-3', points: const ['kp-2']),
        ],
        spec: const PaperSpec(
          targetCount: 3,
          perKnowledgePointCap: 1,
          manualIncludeQuestionIds: {'q-2', 'q-1'},
        ),
        readings: [
          _reading('kp-1', danger: true),
          _reading('kp-2', danger: true)
        ],
      );
      expect(_ids(plan), ['q-1', 'q-2', 'q-3']);
      expect(plan.byKnowledgePoint, {'kp-1': 2, 'kp-2': 1});
      expect(plan.manualIncludedCount, 2);
    });

    test('必收题不受学科上限限制', () {
      final plan = PaperComposer.compose(
        candidates: [
          _candidate(id: 'q-1', points: const ['kp-1']),
          _candidate(id: 'q-2', points: const ['kp-2']),
        ],
        spec: const PaperSpec(
          targetCount: 2,
          subjectQuota: SubjectQuota(maxPerSubject: {'数学': 1}),
          manualIncludeQuestionIds: {'q-1', 'q-2'},
        ),
        readings: [
          _reading('kp-1', danger: true),
          _reading('kp-2', danger: true)
        ],
      );
      expect(_ids(plan), ['q-1', 'q-2']);
      expect(plan.bySubject, {'数学': 2});
      expect(plan.quotaBlockedQuestions, isEmpty);
      expect(plan.manualIncludedCount, 2);
    });

    test('必收题不受领域上限限制', () {
      final plan = PaperComposer.compose(
        candidates: [
          _candidate(id: 'q-1', subject: '物理', points: const ['kp-1']),
          _candidate(id: 'q-2', subject: '物理', points: const ['kp-2']),
        ],
        spec: const PaperSpec(
          targetCount: 2,
          domainQuota: DomainQuota(maxPerDomain: {'物理': 1}),
          manualIncludeQuestionIds: {'q-1', 'q-2'},
        ),
        readings: [
          _reading('kp-1', danger: true),
          _reading('kp-2', danger: true)
        ],
        knowledgePointTagPaths: _paths({'kp-1': '物理', 'kp-2': '物理'}),
      );
      expect(_ids(plan), ['q-1', 'q-2']);
      expect(plan.byDomain, {'物理': 2});
      expect(plan.quotaBlockedByDomain, isEmpty);
      expect(plan.manualIncludedCount, 2);
    });

    test('必收题排在学科保底之前', () {
      final plan = PaperComposer.compose(
        candidates: [
          _candidate(id: 'q-math', points: const ['kp-m']),
          _candidate(id: 'q-phy', subject: '物理', points: const ['kp-p']),
        ],
        spec: const PaperSpec(
          targetCount: 2,
          subjectQuota: SubjectQuota(minPerSubject: {'物理': 1}),
          manualIncludeQuestionIds: {'q-math'},
        ),
        readings: [
          _reading('kp-m', danger: true),
          _reading('kp-p', danger: true)
        ],
      );
      expect(_ids(plan), ['q-math', 'q-phy']);
      expect(plan.manualIncludedCount, 1);
      expect(plan.subjectShortfalls, isEmpty);
    });

    test('必收题照常打分：zone/need/score/reason 都可解释', () {
      final plan = PaperComposer.compose(
        candidates: [
          _candidate(id: 'q-math', points: const ['kp-1'])
        ],
        spec: const PaperSpec(
          targetCount: 1,
          subjectKeys: {'物理'},
          manualIncludeQuestionIds: {'q-math'},
        ),
        readings: [_reading('kp-1', danger: true)],
      );
      final item = plan.items.single;
      expect(item.zone, PaperZone.danger);
      expect(item.need, closeTo(1.0, 1e-9));
      expect(item.score, closeTo(0.925, 1e-9));
      expect(item.reasonZh, contains('危险区'));
      expect(plan.candidateCount, 1);
    });
  });

  group('PaperComposer 手工排除', () {
    test('排除题在任何阶段都不选（哪怕分数最高）', () {
      final plan = PaperComposer.compose(
        candidates: [
          _candidate(id: 'q-1', points: const ['kp-1']),
          _candidate(id: 'q-2', source: 'school', points: const ['kp-2']),
        ],
        spec: const PaperSpec(
          targetCount: 2,
          manualExcludeQuestionIds: {'q-1'},
        ),
        readings: [
          _reading('kp-1', danger: true),
          _reading('kp-2', danger: true)
        ],
      );
      expect(_ids(plan), ['q-2']);
      expect(plan.isShort, isTrue);
    });

    test('排除题从 candidateCount 里去掉', () {
      final plan = PaperComposer.compose(
        candidates: [
          _candidate(id: 'q-1'),
          _candidate(id: 'q-2'),
          _candidate(id: 'q-3'),
        ],
        spec: const PaperSpec(
          targetCount: 2,
          manualExcludeQuestionIds: {'q-3'},
        ),
      );
      expect(plan.candidateCount, 2);
      expect(_ids(plan), ['q-1', 'q-2']);
    });

    test('排除不影响未列出的题', () {
      final plan = PaperComposer.compose(
        candidates: [
          _candidate(id: 'q-1'),
          _candidate(id: 'q-2'),
          _candidate(id: 'q-3'),
        ],
        spec: const PaperSpec(
          targetCount: 3,
          manualExcludeQuestionIds: {'q-3'},
        ),
      );
      expect(_ids(plan), ['q-1', 'q-2']);
    });

    test('学科保底不会把被排除的题补回来', () {
      final plan = PaperComposer.compose(
        candidates: [
          _candidate(id: 'q-phy', subject: '物理', points: const ['kp-p']),
          _candidate(id: 'q-math', points: const ['kp-m']),
        ],
        spec: const PaperSpec(
          targetCount: 2,
          subjectQuota: SubjectQuota(minPerSubject: {'物理': 1}),
          manualExcludeQuestionIds: {'q-phy'},
        ),
        readings: [
          _reading('kp-p', danger: true),
          _reading('kp-m', danger: true)
        ],
      );
      expect(_ids(plan), ['q-math']);
      final shortfall = plan.subjectShortfalls.single;
      expect(shortfall.subjectKey, '物理');
      expect(shortfall.selectedCount, 0);
      expect(shortfall.availableCount, 0);
      expect(shortfall.isUncovered, isTrue);
    });
  });

  group('PaperComposer 必收题与 targetCount 硬上限', () {
    test('必收题超过 targetCount 时按 id 字典序取前 k，其余记 skipped', () {
      final plan = PaperComposer.compose(
        candidates: [
          _candidate(id: 'q-1'),
          _candidate(id: 'q-2'),
          _candidate(id: 'q-3'),
        ],
        spec: const PaperSpec(
          targetCount: 2,
          manualIncludeQuestionIds: {'q-3', 'q-1', 'q-2'},
        ),
      );
      expect(_ids(plan), ['q-1', 'q-2']);
      expect(plan.manualIncludedCount, 2);
      expect(plan.manualSkippedQuestionIds, ['q-3']);
      final json = plan.toJson();
      expect(json['manual_skipped_question_ids'], ['q-3']);
      expect(json['manual_included_count'], 2);
    });

    test('必收题占满 targetCount 后不再填充', () {
      final plan = PaperComposer.compose(
        candidates: [_candidate(id: 'q-1'), _candidate(id: 'q-2')],
        spec: const PaperSpec(
          targetCount: 1,
          manualIncludeQuestionIds: {'q-1'},
        ),
      );
      expect(_ids(plan), ['q-1']);
      expect(plan.isShort, isFalse);
      expect(plan.manualSkippedQuestionIds, isEmpty);
    });

    test('必收题占满 targetCount 时学科保底被挤掉', () {
      final plan = PaperComposer.compose(
        candidates: [
          _candidate(id: 'q-math', points: const ['kp-m']),
          _candidate(id: 'q-phy', subject: '物理', points: const ['kp-p']),
        ],
        spec: const PaperSpec(
          targetCount: 1,
          subjectQuota: SubjectQuota(minPerSubject: {'物理': 1}),
          manualIncludeQuestionIds: {'q-math'},
        ),
        readings: [
          _reading('kp-m', danger: true),
          _reading('kp-p', danger: true)
        ],
      );
      expect(_ids(plan), ['q-math']);
      final shortfall = plan.subjectShortfalls.single;
      expect(shortfall.subjectKey, '物理');
      expect(shortfall.selectedCount, 0);
      expect(shortfall.availableCount, 1);
      expect(shortfall.isUncovered, isFalse);
    });

    test('targetCount = 0 时必收题全部记 skipped', () {
      final plan = PaperComposer.compose(
        candidates: [_candidate(id: 'q-1'), _candidate(id: 'q-2')],
        spec: const PaperSpec(
          targetCount: 0,
          manualIncludeQuestionIds: {'q-2', 'q-1'},
        ),
      );
      expect(plan.items, isEmpty);
      expect(plan.manualIncludedCount, 0);
      expect(plan.manualSkippedQuestionIds, ['q-1', 'q-2']);
    });
  });

  group('PaperComposer 必收缺失与冲突', () {
    test('候选池没有的必收 id 记 missing', () {
      final plan = PaperComposer.compose(
        candidates: [_candidate(id: 'q-1')],
        spec: const PaperSpec(
          targetCount: 2,
          manualIncludeQuestionIds: {'q-1', 'q-ghost'},
        ),
      );
      expect(_ids(plan), ['q-1']);
      expect(plan.manualMissingQuestionIds, ['q-ghost']);
      expect(plan.manualIncludedCount, 1);
      expect(plan.manualSkippedQuestionIds, isEmpty);
    });

    test('多个缺失 id 按字典序回报', () {
      final plan = PaperComposer.compose(
        candidates: [_candidate(id: 'q-1')],
        spec: const PaperSpec(
          targetCount: 1,
          manualIncludeQuestionIds: {'q-z', 'q-a', 'q-1'},
        ),
      );
      expect(plan.manualMissingQuestionIds, ['q-a', 'q-z']);
    });

    test('必收与排除冲突时排除生效并记 conflict', () {
      final plan = PaperComposer.compose(
        candidates: [_candidate(id: 'q-1'), _candidate(id: 'q-2')],
        spec: const PaperSpec(
          targetCount: 2,
          manualIncludeQuestionIds: {'q-2'},
          manualExcludeQuestionIds: {'q-2'},
        ),
      );
      expect(_ids(plan), ['q-1']);
      expect(plan.manualConflictQuestionIds, ['q-2']);
      expect(plan.manualIncludedCount, 0);
      expect(plan.manualMissingQuestionIds, isEmpty);
      expect(plan.manualSkippedQuestionIds, isEmpty);
      expect(plan.candidateCount, 1);
    });

    test('冲突 id 即使候选池里没有也只记冲突，不记缺失', () {
      final plan = PaperComposer.compose(
        candidates: const [],
        spec: const PaperSpec(
          targetCount: 1,
          manualIncludeQuestionIds: {'q-ghost'},
          manualExcludeQuestionIds: {'q-ghost'},
        ),
      );
      expect(plan.items, isEmpty);
      expect(plan.manualConflictQuestionIds, ['q-ghost']);
      expect(plan.manualMissingQuestionIds, isEmpty);
    });

    test('必收 id 归一化：trim、丢空串、去重', () {
      final plan = PaperComposer.compose(
        candidates: [_candidate(id: 'q-1')],
        spec: const PaperSpec(
          targetCount: 1,
          manualIncludeQuestionIds: {' q-1 ', '', 'q-1'},
        ),
      );
      expect(_ids(plan), ['q-1']);
      expect(plan.manualIncludedCount, 1);
      expect(plan.manualMissingQuestionIds, isEmpty);
    });
  });

  group('PaperComposer 手工题计入汇总', () {
    test('必收题计入 bySubject', () {
      final plan = PaperComposer.compose(
        candidates: [
          _candidate(id: 'q-1', points: const ['kp-1']),
          _candidate(id: 'q-2', points: const ['kp-2']),
        ],
        spec: const PaperSpec(
          targetCount: 2,
          subjectQuota: SubjectQuota(maxPerSubject: {'数学': 5}),
          manualIncludeQuestionIds: {'q-1'},
        ),
        readings: [
          _reading('kp-1', danger: true),
          _reading('kp-2', danger: true)
        ],
      );
      expect(_ids(plan), ['q-1', 'q-2']);
      expect(plan.bySubject, {'数学': 2});
      expect(plan.manualIncludedCount, 1);
    });

    test('必收题计入 byDomain（主领域 + 附加领域）', () {
      final plan = PaperComposer.compose(
        candidates: [
          _candidate(id: 'q-1', subject: '物理', points: const ['kp-1']),
          _candidate(id: 'q-2', subject: '化学', points: const ['kp-2']),
        ],
        spec: const PaperSpec(
          targetCount: 2,
          domainQuota: DomainQuota(maxPerDomain: {'数学': 5, '物理': 5, '化学': 5}),
          manualIncludeQuestionIds: {'q-1'},
        ),
        readings: [
          _reading('kp-1', danger: true),
          _reading('kp-2', danger: true)
        ],
        // kp-1 同时挂两条标签路径 → 主领域取字典序第一个（数学），物理只作附加领域回报。
        knowledgePointTagPaths: {
          'kp-1': ['物理/力学', '数学/函数'],
          'kp-2': ['化学/有机'],
        },
      );
      expect(_ids(plan), ['q-1', 'q-2']);
      expect(plan.byDomain, {'化学': 1, '数学': 1, '物理': 1});
      expect(plan.manualIncludedCount, 1);
    });

    test('必收题占用学科名额，保底不会为它重复补题', () {
      final plan = PaperComposer.compose(
        candidates: [
          _candidate(id: 'q-1', points: const ['kp-1']),
          _candidate(id: 'q-2', points: const ['kp-2']),
        ],
        spec: const PaperSpec(
          targetCount: 2,
          subjectQuota: SubjectQuota(minPerSubject: {'数学': 1}),
          manualIncludeQuestionIds: {'q-1'},
        ),
        readings: [
          _reading('kp-1', danger: true),
          _reading('kp-2', danger: true)
        ],
      );
      expect(_ids(plan), ['q-1', 'q-2']);
      expect(plan.bySubject, {'数学': 2});
      expect(plan.subjectShortfalls, isEmpty);
    });

    test('manualIncludedCount 只数真正进卷的必收题', () {
      final plan = PaperComposer.compose(
        candidates: [_candidate(id: 'q-1')],
        spec: const PaperSpec(
          targetCount: 1,
          manualIncludeQuestionIds: {'q-1', 'q-ghost'},
        ),
      );
      expect(plan.manualIncludedCount, 1);
      expect(plan.manualMissingQuestionIds, ['q-ghost']);
    });
  });

  group('PaperComposer 手工选择的确定性', () {
    PaperPlan build(
            {required Set<String> include, required Set<String> exclude}) =>
        PaperComposer.compose(
          candidates: [
            _candidate(id: 'q-1', points: const ['kp-1']),
            _candidate(id: 'q-2', points: const ['kp-2']),
            _candidate(id: 'q-3', points: const ['kp-3']),
          ],
          spec: PaperSpec(
            targetCount: 2,
            manualIncludeQuestionIds: include,
            manualExcludeQuestionIds: exclude,
          ),
          readings: [
            _reading('kp-1', danger: true),
            _reading('kp-2', danger: true),
            _reading('kp-3', danger: true),
          ],
        );

    test('include Set 乱序结果一致', () {
      final forward = build(include: {'q-2', 'q-1'}, exclude: const {});
      final reversed = build(include: {'q-1', 'q-2'}, exclude: const {});
      expect(jsonEncode(forward.toJson()), jsonEncode(reversed.toJson()));
    });

    test('exclude Set 乱序结果一致', () {
      final forward = build(include: const {'q-1'}, exclude: {'q-3', 'q-2'});
      final reversed = build(include: const {'q-1'}, exclude: {'q-2', 'q-3'});
      expect(jsonEncode(forward.toJson()), jsonEncode(reversed.toJson()));
    });

    test('候选顺序不同结果一致', () {
      final candidates = [
        _candidate(id: 'q-1', points: const ['kp-1']),
        _candidate(id: 'q-2', points: const ['kp-2']),
        _candidate(id: 'q-3', points: const ['kp-3']),
      ];
      final readings = [
        _reading('kp-1', danger: true),
        _reading('kp-2', danger: true),
        _reading('kp-3', danger: true),
      ];
      PaperPlan compose(List<PaperCandidate> list) => PaperComposer.compose(
            candidates: list,
            spec: const PaperSpec(
              targetCount: 2,
              manualIncludeQuestionIds: {'q-3'},
              manualExcludeQuestionIds: {'q-2'},
            ),
            readings: readings,
          );
      expect(
        jsonEncode(compose(candidates).toJson()),
        jsonEncode(compose(candidates.reversed.toList()).toJson()),
      );
    });

    test('同一 id 的重复候选按分数/tie-break 取最优一条', () {
      final plan = PaperComposer.compose(
        candidates: [
          _candidate(id: 'q-1', points: const ['kp-1']),
          _candidate(id: 'q-1', source: 'school', points: const ['kp-1']),
        ],
        spec: const PaperSpec(
          targetCount: 1,
          manualIncludeQuestionIds: {'q-1'},
        ),
        readings: [_reading('kp-1', danger: true)],
      );
      expect(plan.items, hasLength(1));
      expect(plan.items.single.sourceLevel, 'gaokao');
    });
  });

  group('PaperComposer 手工选择的边界与组合', () {
    test('空候选池 + 必收 id：全部记缺失、卷为空', () {
      final plan = PaperComposer.compose(
        candidates: const [],
        spec: const PaperSpec(
          targetCount: 3,
          manualIncludeQuestionIds: {'q-1'},
        ),
      );
      expect(plan.isEmpty, isTrue);
      expect(plan.isShort, isTrue);
      expect(plan.candidateCount, 0);
      expect(plan.manualIncludedCount, 0);
      expect(plan.manualMissingQuestionIds, ['q-1']);
    });

    test('手工开关与学科/领域两套配额同时启用', () {
      final plan = PaperComposer.compose(
        candidates: [
          _candidate(id: 'q-1', points: const ['kp-1']),
          _candidate(id: 'q-2', subject: '物理', points: const ['kp-2']),
          _candidate(id: 'q-3', points: const ['kp-3']),
        ],
        spec: const PaperSpec(
          targetCount: 2,
          subjectQuota: SubjectQuota(
            maxPerSubject: {'数学': 5, '物理': 5},
            minPerSubject: {'物理': 1},
          ),
          domainQuota: DomainQuota(maxPerDomain: {'数学': 2, '物理': 2}),
          manualIncludeQuestionIds: {'q-1'},
          manualExcludeQuestionIds: {'q-3'},
        ),
        readings: [
          _reading('kp-1', danger: true),
          _reading('kp-2', danger: true),
          _reading('kp-3', danger: true),
        ],
        knowledgePointTagPaths: _paths({
          'kp-1': '数学',
          'kp-2': '物理',
          'kp-3': '数学',
        }),
      );
      expect(_ids(plan), ['q-1', 'q-2']);
      expect(plan.bySubject, {'数学': 1, '物理': 1});
      expect(plan.byDomain, {'数学': 1, '物理': 1});
      expect(plan.manualIncludedCount, 1);
      expect(plan.manualConflictQuestionIds, isEmpty);
      expect(plan.manualMissingQuestionIds, isEmpty);
      expect(plan.manualSkippedQuestionIds, isEmpty);
      expect(plan.quotaBlockedQuestions, isEmpty);
      expect(plan.quotaBlockedByDomain, isEmpty);
      expect(plan.subjectShortfalls, isEmpty);
      expect(plan.domainShortfalls, isEmpty);
      expect(plan.candidateCount, 2);
    });
  });
}
