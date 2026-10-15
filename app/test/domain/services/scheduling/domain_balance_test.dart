import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/scheduling/domain_balance.dart';
import 'package:furnace/domain/services/scheduling/thread_ranker.dart';

void main() {
  final now = DateTime(2026, 9, 7, 20); // Monday evening

  RankContext context() => RankContext(now: now);

  RankEvent task(
    String id, {
    List<String> tagPaths = const [],
    int? estimateMinutes = 30,
    DateTime? dueAt,
  }) =>
      RankEvent(
        id: id,
        title: id,
        tagPaths: tagPaths,
        estimateMinutes: estimateMinutes,
        dueAt: dueAt,
      );

  group('segment A boundary (hard constraints stay in the plain algorithm)',
      () {
    test('red-listed task is excluded even when it is in the danger zone', () {
      final output = DomainBalanceRanker.rank(
        events: [
          task('hard',
              tagPaths: ['数学/函数'],
              dueAt: now.add(const Duration(hours: 1)),
              estimateMinutes: 120),
          task('easy',
              tagPaths: ['数学/函数'], dueAt: now.add(const Duration(hours: 1))),
        ],
        context: context(),
        taskKnowledgePoints: {
          'hard': ['kp-danger'],
        },
        readings: [
          const KnowledgePointReading(
              knowledgePointId: 'kp-danger', inDangerZone: true),
        ],
      );

      expect(output.taskIds, isNot(contains('hard')));
      expect(output.insufficient.map((e) => e.event.id), contains('hard'));
      expect(output.insufficient.single.neededMinutes, 120);
      expect(output.insufficient.single.availableMinutes, 60);
      expect(output.taskIds, ['easy']);
    });

    test('overdue task lands in the overdue bucket, not in the ranking', () {
      final output = DomainBalanceRanker.rank(
        events: [
          task('late',
              tagPaths: ['语文/阅读'],
              dueAt: now.subtract(const Duration(minutes: 1))),
          task('ok', tagPaths: ['语文/阅读']),
        ],
        context: context(),
      );
      expect(output.overdue.map((e) => e.event.id), ['late']);
      expect(output.taskIds, ['ok']);
    });

    test('feasible() is exactly ThreadRanker.rank() (segment A untouched)', () {
      final events = [
        task('a',
            tagPaths: ['语文/阅读'], dueAt: now.add(const Duration(hours: 3))),
        task('b',
            tagPaths: ['数学/函数'],
            dueAt: now.add(const Duration(hours: 1)),
            estimateMinutes: 120),
      ];
      final a =
          DomainBalanceRanker.feasible(events: events, context: context());
      final b = ThreadRanker.rank(events: events, context: context());
      expect(a.ready.map((e) => e.event.id), b.ready.map((e) => e.event.id));
      expect(a.insufficient.map((e) => e.event.id),
          b.insufficient.map((e) => e.event.id));
      expect(
          a.overdue.map((e) => e.event.id), b.overdue.map((e) => e.event.id));
    });
  });

  group('domain quota disperses tasks across subjects', () {
    test('a single subject cannot eat the whole window', () {
      final output = DomainBalanceRanker.rank(
        events: [
          task('cn-danger', tagPaths: ['语文/阅读']),
          task('cn-1', tagPaths: ['语文/阅读']),
          task('cn-2', tagPaths: ['语文/阅读']),
          task('math-1', tagPaths: ['数学/函数']),
        ],
        context: context(),
        taskKnowledgePoints: {
          'cn-danger': ['kp-danger'],
        },
        readings: [
          const KnowledgePointReading(
            knowledgePointId: 'kp-danger',
            inDangerZone: true,
          ),
        ],
        windowSlots: 2, // 2 slots / 2 subjects -> quota 1 each
      );

      expect(output.domainQuota, {'语文': 1, '数学': 1});
      // Most effective task first, then the OTHER subject gets the slot.
      expect(output.taskIds.first, 'cn-danger');
      expect(output.ranked[1].taskId, 'math-1');
      expect(output.ranked[1].domainKey, '数学');
      expect(output.ranked[1].overQuota, isFalse);
      // Everything after the quota is flagged as an over-quota filler.
      expect(output.ranked[2].overQuota, isTrue);
      expect(output.ranked[2].overQuotaPenaltyApplied, 1.0);
      expect(output.ranked[2].balanceNote, contains('配额'));
    });

    test('quota is per subject and never zero', () {
      expect(DomainBalanceRanker.quotaFor(6, 2), 3);
      expect(DomainBalanceRanker.quotaFor(6, 3), 2);
      expect(DomainBalanceRanker.quotaFor(1, 5), 1);
      expect(DomainBalanceRanker.quotaFor(0, 3), 1);
      expect(DomainBalanceRanker.quotaFor(4, 0), 4);
    });

    test('explicitQuotas override the automatic quota', () {
      final output = DomainBalanceRanker.rank(
        events: [
          task('cn-1', tagPaths: ['语文/阅读']),
          task('cn-2', tagPaths: ['语文/阅读']),
          task('math-1', tagPaths: ['数学/函数']),
        ],
        context: context(),
        windowSlots: 3,
        explicitQuotas: const {'语文': 2},
      );
      expect(output.domainQuota['语文'], 2);
      expect(output.domainQuota['数学'], 2); // ceil(3/2)
      expect(output.taskIds.length, 3);
    });
  });

  group('cognitive effectiveness term', () {
    test('danger zone ranks above a neutral task of the same subject', () {
      final output = DomainBalanceRanker.rank(
        events: [
          task('plain', tagPaths: ['语文/阅读']),
          task('danger', tagPaths: ['语文/阅读']),
        ],
        context: context(),
        taskKnowledgePoints: {
          'danger': ['kp-danger'],
        },
        readings: [
          const KnowledgePointReading(
            knowledgePointId: 'kp-danger',
            inDangerZone: true,
          ),
        ],
      );
      expect(output.taskIds, ['danger', 'plain']);
      expect(output.ranked.first.inDangerZone, isTrue);
      expect(output.ranked.first.effectiveness, closeTo(0.85, 1e-9));
      expect(output.ranked.first.effectiveness,
          greaterThan(output.ranked.last.effectiveness));
      expect(output.ranked.first.reasonZh, contains('危险区'));
      expect(output.ranked.last.reasonZh, isNotEmpty);
    });

    test('danger > development > neutral', () {
      final output = DomainBalanceRanker.rank(
        events: [
          task('neutral', tagPaths: ['语文/阅读']),
          task('dev', tagPaths: ['语文/阅读']),
          task('danger', tagPaths: ['语文/阅读']),
        ],
        context: context(),
        taskKnowledgePoints: {
          'dev': ['kp-dev'],
          'danger': ['kp-danger'],
        },
        readings: [
          const KnowledgePointReading(
            knowledgePointId: 'kp-dev',
            inDevelopmentZone: true,
          ),
          const KnowledgePointReading(
            knowledgePointId: 'kp-danger',
            inDangerZone: true,
          ),
        ],
      );
      expect(output.taskIds, ['danger', 'dev', 'neutral']);
      expect(output.ranked[1].reasonZh, contains('发展区'));
    });

    test('assessment prior lifts a weakly encoded knowledge point', () {
      final output = DomainBalanceRanker.rank(
        events: [
          task('strong', tagPaths: ['语文/阅读']),
          task('weak', tagPaths: ['语文/阅读']),
        ],
        context: context(),
        taskKnowledgePoints: {
          'strong': ['kp-strong'],
          'weak': ['kp-weak'],
        },
        readings: const [
          KnowledgePointReading(
            knowledgePointId: 'kp-strong',
            priorR0: 0.95,
            priorConfidence: 1,
          ),
          KnowledgePointReading(
            knowledgePointId: 'kp-weak',
            priorR0: 0.05,
            priorConfidence: 1,
          ),
        ],
      );
      expect(output.taskIds, ['weak', 'strong']);
      expect(output.ranked.first.effectiveness, closeTo(0.785, 1e-9));
      expect(output.ranked.first.reasonZh, contains('R0='));
    });

    test('a task with several knowledge points takes the most effective one',
        () {
      final output = DomainBalanceRanker.rank(
        events: [
          task('multi', tagPaths: ['语文/阅读'])
        ],
        context: context(),
        taskKnowledgePoints: {
          'multi': ['kp-plain', 'kp-danger'],
        },
        readings: const [
          KnowledgePointReading(knowledgePointId: 'kp-plain'),
          KnowledgePointReading(
            knowledgePointId: 'kp-danger',
            inDangerZone: true,
          ),
        ],
      );
      expect(output.ranked.single.matchedKnowledgePointId, 'kp-danger');
      expect(output.ranked.single.effectiveness, closeTo(0.85, 1e-9));
    });
  });

  group('determinism and degenerate input', () {
    test(
        'single-subject list ranks deterministically regardless of input order',
        () {
      final forward = DomainBalanceRanker.rank(
        events: [
          task('a', tagPaths: ['数学/函数']),
          task('b', tagPaths: ['数学/函数']),
          task('c', tagPaths: ['数学/函数']),
        ],
        context: context(),
      );
      final reversed = DomainBalanceRanker.rank(
        events: [
          task('c', tagPaths: ['数学/函数']),
          task('b', tagPaths: ['数学/函数']),
          task('a', tagPaths: ['数学/函数']),
        ],
        context: context(),
      );
      expect(forward.taskIds, ['a', 'b', 'c']);
      expect(reversed.taskIds, ['a', 'b', 'c']);
      expect(forward.domainQuota, {'数学': 3});
    });

    test('exact ties break on taskId, not on the unstable sort order', () {
      final first = DomainBalanceRanker.rank(
        events: [
          task('z', tagPaths: ['语文/阅读']),
          task('y', tagPaths: ['语文/阅读']),
          task('x', tagPaths: ['语文/阅读']),
        ],
        context: context(),
      );
      expect(first.taskIds, ['x', 'y', 'z']);
      expect(first.ranked.map((t) => t.balanceBonus).toList(),
          [1.0, closeTo(2 / 3, 1e-9), closeTo(1 / 3, 1e-9)]);
    });

    test('empty input returns an empty result and does not throw', () {
      final output = DomainBalanceRanker.rank(
        events: const [],
        context: context(),
      );
      expect(output.isEmpty, isTrue);
      expect(output.taskIds, isEmpty);
      expect(output.insufficient, isEmpty);
      expect(output.overdue, isEmpty);
      expect(output.domainQuota, isEmpty);
    });

    test('degenerate readings and slots do not throw', () {
      final output = DomainBalanceRanker.rank(
        events: [
          task('a', tagPaths: const ['语文/阅读'])
        ],
        context: context(),
        taskKnowledgePoints: const {
          'a': ['', 'kp-unknown'],
        },
        readings: const [
          KnowledgePointReading(knowledgePointId: ''),
          KnowledgePointReading(
            knowledgePointId: 'kp-unknown',
            priorR0: 42, // out of range on purpose
            priorConfidence: 3,
          ),
        ],
        windowSlots: -5,
        explicitQuotas: const {'语文': 0},
      );
      expect(output.taskIds, ['a']);
      expect(output.ranked.single.effectiveness, inInclusiveRange(0.0, 1.0));
      expect(output.domainQuota['语文'], 1);
    });

    test('a task without any tag becomes 未分类', () {
      final output = DomainBalanceRanker.rank(
        events: [task('a')],
        context: context(),
      );
      expect(output.ranked.single.domainKey, kUnclassifiedDomain);
      expect(output.ranked.single.isUnclassified, isTrue);
      expect(output.ranked.single.balanceNote, contains('无学科标签'));
    });

    test('weights are exposed and normalize to 1.0', () {
      const weights = DomainBalanceWeights();
      expect(weights.sum, closeTo(1.0, 1e-9));
      final scaled = const DomainBalanceWeights(
        effectiveness: 0.5,
        urgency: 0.25,
        goal: 0.25,
        balance: 0.5,
      ).normalized();
      expect(scaled.sum, closeTo(1.0, 1e-9));
      expect(scaled.effectiveness, closeTo(1 / 3, 1e-9));
      expect(scaled.overQuotaPenalty, 1.0);
      expect(
        const DomainBalanceWeights(
          effectiveness: 0,
          urgency: 0,
          goal: 0,
          balance: 0,
        ).normalized().sum,
        0,
      ); // a non-positive sum is returned unchanged
      expect(
          const DomainBalanceWeights().toMap().keys,
          containsAll(
              <String>['effectiveness', 'balance', 'overQuotaPenalty']));
    });
  });

  group('DomainKeyResolver', () {
    test('domain key is the top-level ancestor', () {
      expect(DomainKeyResolver.domainOfPath('语文/阅读/文言文'), '语文');
      expect(DomainKeyResolver.domainOfPath('语文'), '语文');
      expect(DomainKeyResolver.domainOfPath('   '), kUnclassifiedDomain);
      expect(DomainKeyResolver.domainOfPath(''), kUnclassifiedDomain);
    });

    test('shortest path wins, then lexicographic', () {
      expect(
        DomainKeyResolver.domainOfPaths(['语文/阅读/文言文', '数学']),
        '数学',
      );
      expect(
        DomainKeyResolver.domainOfPaths(['语文/阅读', '数学/函数']),
        '数学',
      );
      expect(DomainKeyResolver.domainOfPaths(const []), kUnclassifiedDomain);
    });

    test('tag tree fallback walks parents and ignores non-task links', () {
      final domains = DomainKeyResolver.resolveFromTagTree(
        tags: const [
          DomainTag(id: 'root-cn', name: '语文'),
          DomainTag(id: 'leaf-read', parentId: 'root-cn', name: '阅读'),
          DomainTag(id: 'root-math', name: '数学'),
        ],
        links: const [
          TaskTagLink(taskId: 't1', tagId: 'leaf-read'),
          TaskTagLink(taskId: 't2', tagId: 'root-math'),
          TaskTagLink(taskId: 't3', tagId: 'root-math', objectType: 'note'),
          TaskTagLink(taskId: 't4', tagId: 'missing'),
        ],
      );
      expect(domains['t1'], '语文');
      expect(domains['t2'], '数学');
      expect(domains['t3'], isNull); // objectType != 'task'
      expect(domains['t4'], kUnclassifiedDomain);
    });

    test('a parent cycle terminates instead of hanging', () {
      final domains = DomainKeyResolver.resolveFromTagTree(
        tags: const [
          DomainTag(id: 'a', parentId: 'b', name: 'A'),
          DomainTag(id: 'b', parentId: 'a', name: 'B'),
        ],
        links: const [TaskTagLink(taskId: 't', tagId: 'a')],
      );
      expect(domains['t'], anyOf('A', 'B'));
    });

    test('tree fallback is used when RankEvent.tagPaths is empty', () {
      final output = DomainBalanceRanker.rank(
        events: [task('t1')],
        context: context(),
        tags: const [
          DomainTag(id: 'root-cn', name: '语文'),
          DomainTag(id: 'leaf-read', parentId: 'root-cn', name: '阅读'),
        ],
        taskTagLinks: const [TaskTagLink(taskId: 't1', tagId: 'leaf-read')],
      );
      expect(output.ranked.single.domainKey, '语文');
    });
  });
}
