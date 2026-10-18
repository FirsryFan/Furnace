import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
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

void main() {
  group('SubjectQuota', () {
    test('an empty quota object is disabled and resolves to empty maps', () {
      const quota = SubjectQuota();
      expect(quota.isEnabled, isFalse);
      final resolved = quota.resolve();
      expect(resolved.isEnabled, isFalse);
      expect(resolved.maxPerSubject, isEmpty);
      expect(resolved.minPerSubject, isEmpty);
      expect(resolved.toJson(), {
        'max_per_subject': <String, int>{},
        'min_per_subject': <String, int>{},
      });
    });

    test('resolve trims subject keys and sorts them', () {
      const quota = SubjectQuota(
        maxPerSubject: {' 物理 ': 3, '数学': 2},
        minPerSubject: {' 数学 ': 1},
      );
      final resolved = quota.resolve();
      expect(resolved.maxPerSubject.keys.toList(), ['数学', '物理']);
      expect(resolved.maxFor(' 数学 '), 2);
      expect(resolved.maxFor('物理'), 3);
      expect(resolved.minFor('数学'), 1);
      expect(resolved.minFor(' 物理 '), 0);
    });

    test('a minimum above the maximum raises the effective maximum', () {
      final resolved = const SubjectQuota(
        maxPerSubject: {'数学': 1},
        minPerSubject: {'数学': 2},
      ).resolve();
      expect(resolved.maxFor('数学'), 2);
      expect(resolved.minFor('数学'), 2);
      expect(resolved.toJson(), {
        'max_per_subject': {'数学': 2},
        'min_per_subject': {'数学': 2},
      });
    });

    test('a subject with only a minimum has no upper limit', () {
      final resolved = const SubjectQuota(minPerSubject: {'物理': 1}).resolve();
      expect(resolved.maxFor('物理'), isNull);
      expect(resolved.minFor('物理'), 1);
      expect(resolved.maxPerSubject, isEmpty);
    });

    test('negative quotas are configuration errors', () {
      expect(
        () => const SubjectQuota(maxPerSubject: {'数学': -1}).resolve(),
        throwsArgumentError,
      );
      expect(
        () => const SubjectQuota(minPerSubject: {'数学': -2}).resolve(),
        throwsArgumentError,
      );
    });

    test('blank subject keys are configuration errors', () {
      expect(
        () => const SubjectQuota(maxPerSubject: {'   ': 1}).resolve(),
        throwsArgumentError,
      );
    });

    test('duplicate keys after trim are configuration errors', () {
      expect(
        () => const SubjectQuota(maxPerSubject: {'数学': 1, ' 数学': 2}).resolve(),
        throwsArgumentError,
      );
    });

    test('a zero maximum is allowed and means no questions of that subject',
        () {
      final resolved = const SubjectQuota(maxPerSubject: {'数学': 0}).resolve();
      expect(resolved.isEnabled, isTrue);
      expect(resolved.maxFor('数学'), 0);
    });
  });

  group('PaperComposer subject quota', () {
    test('without a quota the output is byte-identical to the old plan', () {
      final plan = PaperComposer.compose(
        candidates: [
          _candidate(id: 'q-1'),
          _candidate(id: 'q-2', source: 'school'),
        ],
        spec: const PaperSpec(targetCount: 2),
      );
      expect(plan.bySubject, isEmpty);
      expect(plan.quotaBlockedQuestions, isEmpty);
      expect(plan.subjectShortfalls, isEmpty);
      expect(plan.subjectQuota, isNull);
      expect(plan.toJson().keys.toList(), const [
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
      ]);
      final explicitNull = PaperComposer.compose(
        candidates: [
          _candidate(id: 'q-1'),
          _candidate(id: 'q-2', source: 'school'),
        ],
        spec: const PaperSpec(targetCount: 2, subjectQuota: null),
      );
      expect(jsonEncode(explicitNull.toJson()), jsonEncode(plan.toJson()));
    });

    test('an empty quota object behaves exactly like null', () {
      final candidates = [
        _candidate(id: 'q-1'),
        _candidate(id: 'q-2', source: 'school'),
      ];
      final readings = [_reading('kp-1', danger: true)];
      final plain = PaperComposer.compose(
        candidates: candidates,
        spec: const PaperSpec(targetCount: 2),
        readings: readings,
      );
      final withEmptyQuota = PaperComposer.compose(
        candidates: candidates,
        spec: const PaperSpec(targetCount: 2, subjectQuota: SubjectQuota()),
        readings: readings,
      );
      expect(withEmptyQuota.subjectQuota, isNull);
      expect(jsonEncode(withEmptyQuota.toJson()), jsonEncode(plain.toJson()));
    });

    test('the disabled plan still pins the historical field values', () {
      final plan = PaperComposer.compose(
        candidates: [_candidate(id: 'q-1')],
        spec: const PaperSpec(targetCount: 1),
        readings: [_reading('kp-1', danger: true)],
      );
      final json = plan.toJson();
      final item =
          (json['items'] as List<Object?>).single as Map<String, Object?>;
      expect(item['zone'], 'danger');
      expect(item['need'], closeTo(1.0, 1e-9));
      expect(item['quality'], closeTo(0.7, 1e-9));
      expect(item['score'], closeTo(0.925, 1e-9));
      expect(item['matched_knowledge_point_ids'], ['kp-1']);
      expect(json['overall_need'], closeTo(1.0, 1e-9));
      expect(json['weights'], {
        'need': 0.55,
        'quality': 0.25,
        'difficulty_fit': 0.2,
      });
      expect(json.containsKey('by_subject'), isFalse);
    });

    // ---- 上限 ----
    test('per-subject maximum caps how many questions a subject contributes',
        () {
      final plan = PaperComposer.compose(
        candidates: [
          _candidate(id: 'q-1'),
          _candidate(id: 'q-2'),
          _candidate(id: 'q-3'),
        ],
        spec: const PaperSpec(
          targetCount: 3,
          subjectQuota: SubjectQuota(maxPerSubject: {'数学': 2}),
        ),
        readings: [_reading('kp-1', danger: true)],
      );
      expect(_ids(plan), ['q-1', 'q-2']);
      expect(plan.isShort, isTrue);
      expect(plan.quotaBlockedQuestions, hasLength(1));
      final blocked = plan.quotaBlockedQuestions.single;
      expect(blocked.questionId, 'q-3');
      expect(blocked.subjectKey, '数学');
      expect(blocked.subjectLimit, 2);
      expect(plan.bySubject, {'数学': 2});
    });

    test('subjects not listed in the quota are unlimited', () {
      final plan = PaperComposer.compose(
        candidates: [
          _candidate(id: 'q-m1'),
          _candidate(id: 'q-p1', subject: '物理', points: const ['kp-p1']),
          _candidate(id: 'q-p2', subject: '物理', points: const ['kp-p2']),
        ],
        spec: const PaperSpec(
          targetCount: 3,
          subjectQuota: SubjectQuota(maxPerSubject: {'数学': 1}),
        ),
        readings: [
          _reading('kp-1', danger: true),
          _reading('kp-p1', danger: true),
          _reading('kp-p2', danger: true),
        ],
      );
      expect(plan.items, hasLength(3));
      expect(plan.bySubject, {'数学': 1, '物理': 2});
    });

    test('a zero maximum excludes a subject and records why', () {
      final plan = PaperComposer.compose(
        candidates: [
          _candidate(id: 'q-m1'),
          _candidate(
            id: 'q-p1',
            subject: '物理',
            source: 'school',
            points: const ['kp-p1'],
          ),
          _candidate(
            id: 'q-p2',
            subject: '物理',
            source: 'school',
            points: const ['kp-p2'],
          ),
        ],
        spec: const PaperSpec(
          targetCount: 2,
          subjectQuota: SubjectQuota(maxPerSubject: {'数学': 0}),
        ),
        readings: [_reading('kp-1', danger: true)],
      );
      expect(_ids(plan), ['q-p1', 'q-p2']);
      expect(
        plan.quotaBlockedQuestions
            .map((blocked) => blocked.questionId)
            .toList(),
        ['q-m1'],
      );
      expect(plan.bySubject, {'物理': 2});
    });

    test('the blocked list follows score order while slots remain', () {
      final plan = PaperComposer.compose(
        candidates: [
          _candidate(id: 'q-1', source: 'personal'),
          _candidate(id: 'q-2', source: 'school'),
          _candidate(id: 'q-3', source: 'gaokao'),
        ],
        spec: const PaperSpec(
          targetCount: 2,
          subjectQuota: SubjectQuota(maxPerSubject: {'数学': 1}),
        ),
        readings: [_reading('kp-1', danger: true)],
      );
      expect(_ids(plan), ['q-3']);
      expect(
        plan.quotaBlockedQuestions
            .map((blocked) => blocked.questionId)
            .toList(),
        ['q-2', 'q-1'],
      );
    });

    test('no blocked entries are recorded after the target is full', () {
      final plan = PaperComposer.compose(
        candidates: [
          _candidate(id: 'q-1'),
          _candidate(id: 'q-2', source: 'school'),
        ],
        spec: const PaperSpec(
          targetCount: 1,
          subjectQuota: SubjectQuota(maxPerSubject: {'数学': 1}),
        ),
        readings: [_reading('kp-1', danger: true)],
      );
      expect(_ids(plan), ['q-1']);
      expect(plan.quotaBlockedQuestions, isEmpty);
      expect(plan.isShort, isFalse);
    });

    test('bySubject trims subject keys and counts selections', () {
      final plan = PaperComposer.compose(
        candidates: [
          _candidate(id: 'q-1', subject: ' 数学 ', points: const ['kp-1']),
          _candidate(id: 'q-2', subject: ' 数学 ', points: const ['kp-2']),
        ],
        spec: const PaperSpec(
          targetCount: 2,
          subjectQuota: SubjectQuota(maxPerSubject: {'数学': 5}),
        ),
        readings: [
          _reading('kp-1', danger: true),
          _reading('kp-2', danger: true),
        ],
      );
      expect(plan.bySubject, {'数学': 2});
      expect(plan.items.first.subjectKey, ' 数学 ');
    });

    test('quota selection is independent of the candidate input order', () {
      final candidates = [
        _candidate(id: 'q-1', source: 'personal'),
        _candidate(id: 'q-2', source: 'gaokao'),
        _candidate(id: 'q-3', subject: '物理', points: const ['kp-p1']),
      ];
      const spec = PaperSpec(
        targetCount: 2,
        subjectQuota: SubjectQuota(maxPerSubject: {'数学': 1}),
      );
      final readings = [
        _reading('kp-1', danger: true),
        _reading('kp-p1', danger: true),
      ];
      final forward = PaperComposer.compose(
        candidates: candidates,
        spec: spec,
        readings: readings,
      );
      final reversed = PaperComposer.compose(
        candidates: candidates.reversed.toList(),
        spec: spec,
        readings: readings,
      );
      expect(jsonEncode(reversed.toJson()), jsonEncode(forward.toJson()));
    });

    test('quotas and score order coexist across subjects', () {
      final plan = PaperComposer.compose(
        candidates: [
          _candidate(id: 'q-m1', points: const ['kp-m1']),
          _candidate(
            id: 'q-p1',
            subject: '物理',
            source: 'school',
            points: const ['kp-p1'],
          ),
          _candidate(id: 'q-p2', subject: '物理', points: const ['kp-p2']),
        ],
        spec: const PaperSpec(
          targetCount: 2,
          subjectQuota: SubjectQuota(maxPerSubject: {'物理': 1}),
        ),
        readings: [
          _reading('kp-m1', danger: true),
          _reading('kp-p1', danger: true),
          _reading('kp-p2', danger: true),
        ],
      );
      expect(_ids(plan), ['q-m1', 'q-p2']);
      expect(plan.bySubject, {'数学': 1, '物理': 1});
    });

    // ---- 保底 ----
    test('a subject minimum pulls in a lower-scored question', () {
      final plan = PaperComposer.compose(
        candidates: [
          _candidate(id: 'q-m1', points: const ['kp-m1']),
          _candidate(id: 'q-m2', points: const ['kp-m2']),
          _candidate(
            id: 'q-p1',
            subject: '物理',
            source: 'school',
            points: const ['kp-p1'],
          ),
        ],
        spec: const PaperSpec(
          targetCount: 2,
          subjectQuota: SubjectQuota(minPerSubject: {'物理': 1}),
        ),
        readings: [
          _reading('kp-m1', danger: true),
          _reading('kp-m2', danger: true),
          _reading('kp-p1', danger: true),
        ],
      );
      expect(_ids(plan), ['q-p1', 'q-m1']);
      expect(plan.bySubject, {'数学': 1, '物理': 1});
    });

    test('a minimum of two fills two slots', () {
      final plan = PaperComposer.compose(
        candidates: [
          _candidate(id: 'q-m1', points: const ['kp-m1']),
          _candidate(
            id: 'q-p1',
            subject: '物理',
            source: 'school',
            points: const ['kp-p1'],
          ),
          _candidate(
            id: 'q-p2',
            subject: '物理',
            source: 'school',
            points: const ['kp-p2'],
          ),
        ],
        spec: const PaperSpec(
          targetCount: 3,
          subjectQuota: SubjectQuota(minPerSubject: {'物理': 2}),
        ),
        readings: [
          _reading('kp-m1', danger: true),
          _reading('kp-p1', danger: true),
          _reading('kp-p2', danger: true),
        ],
      );
      expect(plan.items, hasLength(3));
      expect(plan.bySubject, {'数学': 1, '物理': 2});
      expect(plan.subjectShortfalls, isEmpty);
    });

    test('a subject with no candidates reports an uncovered shortfall', () {
      final plan = PaperComposer.compose(
        candidates: [
          _candidate(id: 'q-m1', points: const ['kp-m1']),
          _candidate(id: 'q-m2', points: const ['kp-m2']),
        ],
        spec: const PaperSpec(
          targetCount: 2,
          subjectQuota: SubjectQuota(minPerSubject: {'物理': 1}),
        ),
        readings: [
          _reading('kp-m1', danger: true),
          _reading('kp-m2', danger: true),
        ],
      );
      expect(_ids(plan), ['q-m1', 'q-m2']);
      final shortfall = plan.subjectShortfalls.single;
      expect(shortfall.subjectKey, '物理');
      expect(shortfall.minimumCount, 1);
      expect(shortfall.selectedCount, 0);
      expect(shortfall.availableCount, 0);
      expect(shortfall.isUncovered, isTrue);
      expect(plan.uncoveredSubjectKeys, ['物理']);
    });

    test('a per-knowledge-point cap can starve a subject minimum', () {
      final plan = PaperComposer.compose(
        candidates: [
          _candidate(id: 'q-p1', subject: '物理', points: const ['kp-1']),
          _candidate(id: 'q-p2', subject: '物理', points: const ['kp-1']),
        ],
        spec: const PaperSpec(
          targetCount: 2,
          perKnowledgePointCap: 1,
          subjectQuota: SubjectQuota(minPerSubject: {'物理': 2}),
        ),
        readings: [_reading('kp-1', danger: true)],
      );
      expect(_ids(plan), ['q-p1']);
      final shortfall = plan.subjectShortfalls.single;
      expect(shortfall.selectedCount, 1);
      expect(shortfall.availableCount, 2);
      expect(shortfall.isUncovered, isFalse);
    });

    test('minimums beyond the target count are served in subject-key order',
        () {
      final plan = PaperComposer.compose(
        candidates: [
          _candidate(id: 'q-p1', subject: '物理', points: const ['kp-p1']),
          _candidate(id: 'q-m1', points: const ['kp-m1']),
        ],
        spec: const PaperSpec(
          targetCount: 1,
          subjectQuota: SubjectQuota(
            minPerSubject: {'物理': 1, '数学': 1},
          ),
        ),
        readings: [
          _reading('kp-p1', danger: true),
          _reading('kp-m1', danger: true),
        ],
      );
      expect(_ids(plan), ['q-m1']);
      final shortfall = plan.subjectShortfalls.single;
      expect(shortfall.subjectKey, '物理');
      expect(shortfall.selectedCount, 0);
      expect(shortfall.availableCount, 1);
    });

    test('filling continues with other subjects after the minimums are met',
        () {
      final plan = PaperComposer.compose(
        candidates: [
          _candidate(
            id: 'q-p1',
            subject: '物理',
            source: 'school',
            points: const ['kp-p1'],
          ),
          _candidate(id: 'q-m1', points: const ['kp-m1']),
          _candidate(id: 'q-m2', points: const ['kp-m2']),
        ],
        spec: const PaperSpec(
          targetCount: 3,
          subjectQuota: SubjectQuota(minPerSubject: {'物理': 1}),
        ),
        readings: [
          _reading('kp-p1', danger: true),
          _reading('kp-m1', danger: true),
          _reading('kp-m2', danger: true),
        ],
      );
      expect(plan.items, hasLength(3));
      expect(plan.items.first.subjectKey, '物理');
      expect(plan.bySubject, {'数学': 2, '物理': 1});
    });

    test('a minimum above a maximum still selects the minimum', () {
      final plan = PaperComposer.compose(
        candidates: [
          _candidate(id: 'q-1'),
          _candidate(id: 'q-2'),
          _candidate(id: 'q-3'),
        ],
        spec: const PaperSpec(
          targetCount: 3,
          subjectQuota: SubjectQuota(
            maxPerSubject: {'数学': 1},
            minPerSubject: {'数学': 2},
          ),
        ),
        readings: [_reading('kp-1', danger: true)],
      );
      expect(_ids(plan), ['q-1', 'q-2']);
      expect(plan.subjectQuota?.maxFor('数学'), 2);
      expect(plan.quotaBlockedQuestions.single.questionId, 'q-3');
      expect(plan.subjectShortfalls, isEmpty);
    });

    test('a zero minimum is ignored', () {
      final plan = PaperComposer.compose(
        candidates: [
          _candidate(id: 'q-1'),
          _candidate(id: 'q-2'),
        ],
        spec: const PaperSpec(
          targetCount: 2,
          subjectQuota: SubjectQuota(
            maxPerSubject: {'数学': 1},
            minPerSubject: {'数学': 0},
          ),
        ),
        readings: [_reading('kp-1', danger: true)],
      );
      expect(_ids(plan), ['q-1']);
      expect(plan.subjectShortfalls, isEmpty);
      expect(plan.quotaBlockedQuestions.single.questionId, 'q-2');
    });

    test('empty candidates still report minimum shortfalls', () {
      final plan = PaperComposer.compose(
        candidates: const [],
        spec: const PaperSpec(
          targetCount: 3,
          subjectQuota: SubjectQuota(minPerSubject: {'数学': 2}),
        ),
      );
      expect(plan.isEmpty, isTrue);
      expect(plan.subjectShortfalls.single.toJson(), {
        'subject_key': '数学',
        'minimum_count': 2,
        'selected_count': 0,
        'available_count': 0,
        'is_uncovered': true,
      });
      final json = plan.toJson();
      expect(json['by_subject'], isEmpty);
      expect(json['quota_blocked_questions'], isEmpty);
      expect(json['subject_shortfalls'] as List<Object?>, hasLength(1));
      expect(json['subject_quota'], {
        'max_per_subject': <String, int>{},
        'min_per_subject': {'数学': 2},
      });
    });

    // ---- 输出契约 ----
    test('quota JSON keys appear only when the quota is enabled', () {
      final enabled = PaperComposer.compose(
        candidates: [_candidate(id: 'q-1')],
        spec: const PaperSpec(
          targetCount: 1,
          subjectQuota: SubjectQuota(minPerSubject: {'数学': 1}),
        ),
      );
      final json = enabled.toJson();
      expect(json.containsKey('by_subject'), isTrue);
      expect(json.containsKey('quota_blocked_questions'), isTrue);
      expect(json.containsKey('subject_shortfalls'), isTrue);
      expect(json.containsKey('subject_quota'), isTrue);
      expect(json['by_subject'], {'数学': 1});
      expect(json['subject_quota'], {
        'max_per_subject': <String, int>{},
        'min_per_subject': {'数学': 1},
      });
    });

    test('blocked questions and shortfalls serialise in snake_case', () {
      const blocked = QuotaBlockedQuestion(
        questionId: 'q-1',
        subjectKey: '数学',
        subjectLimit: 2,
      );
      expect(blocked.toJson(), {
        'question_id': 'q-1',
        'subject_key': '数学',
        'subject_limit': 2,
      });
      const shortfall = SubjectQuotaShortfall(
        subjectKey: '物理',
        minimumCount: 2,
        selectedCount: 1,
        availableCount: 3,
      );
      expect(shortfall.toJson(), {
        'subject_key': '物理',
        'minimum_count': 2,
        'selected_count': 1,
        'available_count': 3,
        'is_uncovered': false,
      });
    });

    test('uncovered and deferred knowledge points still behave with a quota',
        () {
      final plan = PaperComposer.compose(
        candidates: [
          _candidate(id: 'q-a', points: const ['kp-a'])
        ],
        spec: const PaperSpec(
          targetCount: 2,
          subjectQuota: SubjectQuota(maxPerSubject: {'数学': 2}),
        ),
        readings: [
          _reading('kp-a', danger: true),
          _reading('kp-b', danger: true),
          _reading('kp-c', development: true),
        ],
      );
      expect(plan.uncoveredKnowledgePointIds, ['kp-b', 'kp-c']);
      expect(plan.deferredKnowledgePointIds, isEmpty);
      expect(plan.byKnowledgePoint, {'kp-a': 1});
    });

    test(
        'shared knowledge points are still counted when the minimum picks first',
        () {
      final plan = PaperComposer.compose(
        candidates: [
          const PaperCandidate(
            questionId: 'q-phy',
            subjectKey: '物理',
            sourceLevel: 'school',
            matchedKnowledgePointIds: ['kp-2', 'kp-1'],
          ),
        ],
        spec: const PaperSpec(
          targetCount: 1,
          subjectQuota: SubjectQuota(minPerSubject: {'物理': 1}),
        ),
        readings: [
          _reading('kp-1', danger: true),
          _reading('kp-2', danger: true),
        ],
      );
      expect(_ids(plan), ['q-phy']);
      expect(plan.byKnowledgePoint, {'kp-1': 1, 'kp-2': 1});
      expect(plan.items.single.matchedKnowledgePointIds, ['kp-1', 'kp-2']);
    });

    test('quota plans serialise deterministically', () {
      PaperPlan build() => PaperComposer.compose(
            candidates: [
              _candidate(id: 'q-m1', points: const ['kp-m1']),
              _candidate(
                id: 'q-p1',
                subject: '物理',
                source: 'school',
                points: const ['kp-p1'],
              ),
            ],
            spec: const PaperSpec(
              targetCount: 2,
              subjectQuota: SubjectQuota(
                maxPerSubject: {'物理': 3, '数学': 3},
                minPerSubject: {'物理': 1},
              ),
            ),
            readings: [
              _reading('kp-m1', danger: true),
              _reading('kp-p1', danger: true),
            ],
          );
      expect(jsonEncode(build().toJson()), jsonEncode(build().toJson()));
    });
  });
}
