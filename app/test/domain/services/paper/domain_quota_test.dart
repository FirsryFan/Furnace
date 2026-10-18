import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/paper/domain_quota.dart';
import 'package:furnace/domain/services/paper/paper_composer.dart';
import 'package:furnace/domain/services/paper/subject_quota.dart';

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

List<String> _ids(PaperPlan plan) => [
      for (final item in plan.items) item.questionId,
    ];

void main() {
  group('DomainQuota 配置', () {
    test('空配置不启用：两张表都空、maxFor 为 null、minFor 为 0', () {
      const quota = DomainQuota();
      expect(quota.isEnabled, isFalse);
      final resolved = quota.resolve();
      expect(resolved.isEnabled, isFalse);
      expect(resolved.maxPerDomain, isEmpty);
      expect(resolved.minPerDomain, isEmpty);
      expect(resolved.maxFor('数学'), isNull);
      expect(resolved.minFor('数学'), 0);
    });

    test('只有上限时启用、领域键按字典序排序', () {
      const quota = DomainQuota(maxPerDomain: {'物理': 1, '数学': 2});
      final resolved = quota.resolve();
      expect(resolved.isEnabled, isTrue);
      expect(resolved.maxPerDomain.keys.toList(), ['数学', '物理']);
      expect(resolved.minPerDomain, isEmpty);
    });

    test('领域键 trim 后归一化，查询也 trim', () {
      const quota = DomainQuota(maxPerDomain: {' 数学 ': 2});
      final resolved = quota.resolve();
      expect(resolved.maxPerDomain.keys.toList(), ['数学']);
      expect(resolved.maxFor('数学'), 2);
      expect(resolved.maxFor(' 数学 '), 2);
    });

    test('负上限抛 ArgumentError', () {
      const quota = DomainQuota(maxPerDomain: {'数学': -1});
      expect(quota.resolve, throwsArgumentError);
    });

    test('负下限抛 ArgumentError', () {
      const quota = DomainQuota(minPerDomain: {'数学': -2});
      expect(quota.resolve, throwsArgumentError);
    });

    test('空白领域键抛 ArgumentError', () {
      const quota = DomainQuota(maxPerDomain: {'   ': 1});
      expect(quota.resolve, throwsArgumentError);
    });

    test('trim 后重复的领域键抛 ArgumentError', () {
      const quota = DomainQuota(maxPerDomain: {'数学': 1, ' 数学 ': 2});
      expect(quota.resolve, throwsArgumentError);
    });

    test('只有保底时启用：上限缺省为 null', () {
      final resolved = const DomainQuota(minPerDomain: {'物理': 2}).resolve();
      expect(resolved.isEnabled, isTrue);
      expect(resolved.maxFor('物理'), isNull);
      expect(resolved.minFor('物理'), 2);
      expect(resolved.maxPerDomain, isEmpty);
    });

    test('同域 min > max 时上限抬到 min（保底优先）', () {
      final resolved = const DomainQuota(
        maxPerDomain: {'数学': 1},
        minPerDomain: {'数学': 3},
      ).resolve();
      expect(resolved.maxFor('数学'), 3);
      expect(resolved.minFor('数学'), 3);
    });

    test('同域 min <= max 时上限保持不变', () {
      final resolved = const DomainQuota(
        maxPerDomain: {'数学': 5},
        minPerDomain: {'数学': 2},
      ).resolve();
      expect(resolved.maxFor('数学'), 5);
    });

    test('resolve 是确定性的：同配置两次解析相等', () {
      const quota = DomainQuota(
        maxPerDomain: {'数学': 2, '物理': 1},
        minPerDomain: {'语文': 1},
      );
      final first = quota.resolve();
      final second = quota.resolve();
      expect(first, second);
      expect(first.hashCode, second.hashCode);
    });

    test('DomainQuotaResolved.toJson 用 snake_case 键回显', () {
      final resolved = const DomainQuota(
        maxPerDomain: {'数学': 2},
        minPerDomain: {'物理': 1},
      ).resolve();
      expect(resolved.toJson(), {
        'max_per_domain': {'数学': 2},
        'min_per_domain': {'物理': 1},
      });
      expect(resolved.toString(), contains('数学'));
    });

    test('不同配置解析结果不相等', () {
      final a = const DomainQuota(maxPerDomain: {'数学': 1}).resolve();
      final b = const DomainQuota(maxPerDomain: {'数学': 2}).resolve();
      expect(a == b, isFalse);
    });
  });

  group('DomainQuotaResolver 标签路径解析', () {
    test('domainOfTagPath 取标签路径第一段', () {
      expect(
        DomainQuotaResolver.domainOfTagPath('数学/函数/函数单调性'),
        '数学',
      );
    });

    test('domainOfTagPath 跳过前导空段并 trim', () {
      expect(DomainQuotaResolver.domainOfTagPath('//数学/函数'), '数学');
      expect(DomainQuotaResolver.domainOfTagPath(' / 物理 /力学 '), '物理');
    });

    test('domainOfTagPath 空白路径返回 null', () {
      expect(DomainQuotaResolver.domainOfTagPath(''), isNull);
      expect(DomainQuotaResolver.domainOfTagPath('   '), isNull);
      expect(DomainQuotaResolver.domainOfTagPath('/ / '), isNull);
    });

    test('domainOfTagPath 单段路径', () {
      expect(DomainQuotaResolver.domainOfTagPath('数学'), '数学');
    });

    test('domainsByKnowledgePoint 汇总多个标签路径并排序去重', () {
      final result = DomainQuotaResolver.domainsByKnowledgePoint({
        'kp-a': ['数学/函数', '数学/函数/单调性', ' 语文/阅读 '],
        'kp-b': ['物理/力学'],
      });
      expect(result, {
        'kp-a': ['数学', '语文'],
        'kp-b': ['物理'],
      });
      expect(result.keys.toList(), ['kp-a', 'kp-b']);
    });

    test('domainsByKnowledgePoint trim 键、跳过空键与无领域知识点', () {
      final result = DomainQuotaResolver.domainsByKnowledgePoint({
        ' kp-a ': ['数学/函数'],
        '  ': ['物理/力学'],
        'kp-b': ['', '   '],
        'kp-c': ['/ /'],
      });
      expect(result.keys.toList(), ['kp-a']);
      expect(result['kp-a'], ['数学']);
    });

    test('domainsByKnowledgePoint 返回不可变集合', () {
      final result = DomainQuotaResolver.domainsByKnowledgePoint({
        'kp-a': ['数学/函数'],
      });
      expect(() => result['kp-b'] = const ['物理'], throwsUnsupportedError);
      expect(() => result['kp-a']!.add('物理'), throwsUnsupportedError);
    });

    test('questionDomains 单领域：主领域就是它、无附加领域', () {
      final domains = DomainQuotaResolver.domainsByKnowledgePoint({
        'kp-math': ['数学/函数'],
      });
      final assignment =
          DomainQuotaResolver.questionDomains(domains, ['kp-math']);
      expect(assignment.hasDomain, isTrue);
      expect(assignment.primaryDomain, '数学');
      expect(assignment.additionalDomains, isEmpty);
      expect(assignment.allDomains, ['数学']);
    });

    test('questionDomains 多领域按字典序取主领域，其余进附加领域', () {
      final domains = DomainQuotaResolver.domainsByKnowledgePoint({
        'kp-multi': ['物理/力学', '数学/函数'],
      });
      final assignment =
          DomainQuotaResolver.questionDomains(domains, ['kp-multi']);
      expect(assignment.primaryDomain, '数学');
      expect(assignment.additionalDomains, ['物理']);
      expect(assignment.allDomains, ['数学', '物理']);
    });

    test('questionDomains 多个知识点取并集并去重', () {
      final domains = DomainQuotaResolver.domainsByKnowledgePoint({
        'kp-a': ['数学/函数', '语文/阅读'],
        'kp-b': ['数学/几何'],
      });
      final assignment = DomainQuotaResolver.questionDomains(
        domains,
        [' kp-a ', 'kp-b', 'kp-a', '  '],
      );
      expect(assignment.primaryDomain, '数学');
      expect(assignment.additionalDomains, ['语文']);
    });

    test('questionDomains 空知识点/未知知识点返回 none', () {
      final domains = DomainQuotaResolver.domainsByKnowledgePoint({
        'kp-math': ['数学/函数'],
      });
      expect(
        DomainQuotaResolver.questionDomains(domains, const []),
        QuestionDomains.none,
      );
      final unknown =
          DomainQuotaResolver.questionDomains(domains, ['  ', 'kp-unknown']);
      expect(unknown, QuestionDomains.none);
      expect(unknown.hasDomain, isFalse);
      expect(unknown.allDomains, isEmpty);
    });

    test('QuestionDomains 值语义与 toJson', () {
      const a = QuestionDomains(
        primaryDomain: '数学',
        additionalDomains: ['物理'],
      );
      const b = QuestionDomains(
        primaryDomain: '数学',
        additionalDomains: ['物理'],
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a.toJson(), {
        'primary_domain': '数学',
        'additional_domains': ['物理'],
      });
      expect(QuestionDomains.none.toJson(), {
        'primary_domain': null,
        'additional_domains': [],
      });
    });
  });

  group('PaperComposer 领域配额', () {
    const mathPaths = {
      'kp-math': ['数学/函数']
    };

    test('默认不启用：plan 没有领域字段、toJson 没有领域键', () {
      final plan = PaperComposer.compose(
        candidates: [
          _candidate(id: 'm1', points: ['kp-math'])
        ],
        spec: const PaperSpec(targetCount: 2),
        knowledgePointTagPaths: mathPaths,
      );
      expect(plan.domainQuota, isNull);
      expect(plan.byDomain, isEmpty);
      expect(plan.quotaBlockedByDomain, isEmpty);
      expect(plan.domainShortfalls, isEmpty);
      expect(plan.uncoveredDomains, isEmpty);
      final json = plan.toJson();
      for (final key in const [
        'by_domain',
        'quota_blocked_by_domain',
        'domain_shortfalls',
        'domain_quota',
      ]) {
        expect(json.containsKey(key), isFalse, reason: key);
      }
      expect(json['schema'], 'mindnet.paper_plan/1');
    });

    test('空 DomainQuota 视为不启用（输出与默认一致）', () {
      final plan = PaperComposer.compose(
        candidates: [
          _candidate(id: 'm1', points: ['kp-math'])
        ],
        spec: const PaperSpec(targetCount: 2, domainQuota: DomainQuota()),
        knowledgePointTagPaths: mathPaths,
      );
      expect(plan.domainQuota, isNull);
      expect(plan.toJson().containsKey('by_domain'), isFalse);
    });

    test('领域上限挡下的候选记进 quotaBlockedByDomain，不静默丢', () {
      final plan = PaperComposer.compose(
        candidates: [
          _candidate(id: 'm1', points: ['kp-math']),
          _candidate(id: 'm2', points: ['kp-math']),
          _candidate(id: 'm3', points: ['kp-math']),
        ],
        spec: const PaperSpec(
          targetCount: 3,
          domainQuota: DomainQuota(maxPerDomain: {'数学': 2}),
        ),
        knowledgePointTagPaths: mathPaths,
      );
      expect(_ids(plan), ['m1', 'm2']);
      expect(plan.byDomain, {'数学': 2});
      expect(plan.quotaBlockedByDomain, hasLength(1));
      final blocked = plan.quotaBlockedByDomain.single;
      expect(blocked.questionId, 'm3');
      expect(blocked.domain, '数学');
      expect(blocked.domainLimit, 2);
      expect(plan.domainQuota!.maxFor('数学'), 2);
    });

    test('没配置的领域不限', () {
      final plan = PaperComposer.compose(
        candidates: [
          _candidate(id: 'p1', subject: '物理', points: ['kp-physics']),
          _candidate(id: 'p2', subject: '物理', points: ['kp-physics']),
        ],
        spec: const PaperSpec(
          targetCount: 2,
          domainQuota: DomainQuota(maxPerDomain: {'数学': 1}),
        ),
        knowledgePointTagPaths: const {
          'kp-physics': ['物理/力学'],
        },
      );
      expect(_ids(plan), ['p1', 'p2']);
      expect(plan.byDomain, {'物理': 2});
      expect(plan.quotaBlockedByDomain, isEmpty);
    });

    test('上限为 0 的领域一道都不取，全部记 blocked', () {
      final plan = PaperComposer.compose(
        candidates: [
          _candidate(id: 'm1', points: ['kp-math']),
          _candidate(id: 'm2', points: ['kp-math']),
        ],
        spec: const PaperSpec(
          targetCount: 2,
          domainQuota: DomainQuota(maxPerDomain: {'数学': 0}),
        ),
        knowledgePointTagPaths: mathPaths,
      );
      expect(plan.items, isEmpty);
      expect(plan.byDomain, isEmpty);
      expect(plan.quotaBlockedByDomain, hasLength(2));
      expect(
        [for (final blocked in plan.quotaBlockedByDomain) blocked.domainLimit],
        [0, 0],
      );
    });

    test('领域保底：低分题也先补保底', () {
      final plan = PaperComposer.compose(
        candidates: [
          _candidate(
              id: 'p1',
              subject: '物理',
              source: 'school',
              points: ['kp-physics']),
          _candidate(id: 'm1', points: ['kp-math']),
        ],
        spec: const PaperSpec(
          targetCount: 2,
          domainQuota: DomainQuota(minPerDomain: {'物理': 1}),
        ),
        knowledgePointTagPaths: const {
          'kp-math': ['数学/函数'],
          'kp-physics': ['物理/力学'],
        },
      );
      expect(_ids(plan), ['p1', 'm1']);
      expect(plan.byDomain, {'数学': 1, '物理': 1});
    });

    test('领域保底受 targetCount 硬上限', () {
      final plan = PaperComposer.compose(
        candidates: [
          _candidate(id: 'm1', points: ['kp-math']),
          _candidate(
              id: 'p1',
              subject: '物理',
              source: 'school',
              points: ['kp-physics']),
        ],
        spec: const PaperSpec(
          targetCount: 1,
          domainQuota: DomainQuota(minPerDomain: {'物理': 1}),
        ),
        knowledgePointTagPaths: const {
          'kp-math': ['数学/函数'],
          'kp-physics': ['物理/力学'],
        },
      );
      expect(_ids(plan), ['p1']);
    });

    test('领域保底阶段受每知识点上限约束（保底也补不满）', () {
      final plan = PaperComposer.compose(
        candidates: [
          _candidate(id: 'p1', subject: '物理', points: ['kp-physics']),
          _candidate(id: 'p2', subject: '物理', points: ['kp-physics']),
        ],
        spec: const PaperSpec(
          targetCount: 3,
          perKnowledgePointCap: 1,
          domainQuota: DomainQuota(minPerDomain: {'物理': 2}),
        ),
        knowledgePointTagPaths: const {
          'kp-physics': ['物理/力学'],
        },
      );
      expect(_ids(plan), ['p1']);
      expect(plan.byKnowledgePoint, {'kp-physics': 1});
      final shortfall = plan.domainShortfalls.single;
      expect(shortfall.domain, '物理');
      expect(shortfall.minimumCount, 2);
      expect(shortfall.selectedCount, 1);
      expect(shortfall.availableCount, 2);
      expect(shortfall.isUncovered, isFalse);
      expect(plan.uncoveredDomains, isEmpty);
    });

    test('学科保底先于领域保底（同分竞争时学科保底先拿）', () {
      final plan = PaperComposer.compose(
        candidates: [
          _candidate(
            id: 'p1',
            subject: '物理',
            points: ['kp-physics'],
          ),
          _candidate(id: 'm1', source: 'school', points: ['kp-math']),
        ],
        spec: const PaperSpec(
          targetCount: 2,
          subjectQuota: SubjectQuota(minPerSubject: {'数学': 1}),
          domainQuota: DomainQuota(minPerDomain: {'物理': 1}),
        ),
        knowledgePointTagPaths: const {
          'kp-math': ['数学/函数'],
          'kp-physics': ['物理/力学'],
        },
      );
      expect(_ids(plan), ['m1', 'p1']);
    });

    test('领域保底不得突破学科上限（学科上限更硬）', () {
      final plan = PaperComposer.compose(
        candidates: [
          _candidate(id: 'p1', subject: '物理', points: ['kp-physics']),
          _candidate(id: 'm1', points: ['kp-math']),
        ],
        spec: const PaperSpec(
          targetCount: 2,
          subjectQuota: SubjectQuota(maxPerSubject: {'物理': 0}),
          domainQuota: DomainQuota(minPerDomain: {'物理': 1}),
        ),
        knowledgePointTagPaths: const {
          'kp-math': ['数学/函数'],
          'kp-physics': ['物理/力学'],
        },
      );
      expect(_ids(plan), ['m1']);
      expect(plan.quotaBlockedQuestions, hasLength(1));
      expect(plan.quotaBlockedQuestions.single.subjectKey, '物理');
      expect(plan.quotaBlockedByDomain, isEmpty);
      expect(plan.uncoveredDomains, isEmpty);
      expect(plan.domainShortfalls, hasLength(1));
      final shortfall = plan.domainShortfalls.single;
      expect(shortfall.domain, '物理');
      expect(shortfall.minimumCount, 1);
      expect(shortfall.selectedCount, 0);
      expect(shortfall.availableCount, 1);
      expect(shortfall.isUncovered, isFalse);
    });

    test('学科上限先于领域上限判定（不重复记领域 blocked）', () {
      final plan = PaperComposer.compose(
        candidates: [
          _candidate(id: 'm1', points: ['kp-math']),
          _candidate(id: 'm2', points: ['kp-math']),
        ],
        spec: const PaperSpec(
          targetCount: 3,
          subjectQuota: SubjectQuota(maxPerSubject: {'数学': 1}),
          domainQuota: DomainQuota(maxPerDomain: {'数学': 5}),
        ),
        knowledgePointTagPaths: mathPaths,
      );
      expect(_ids(plan), ['m1']);
      expect(plan.quotaBlockedQuestions, hasLength(1));
      expect(plan.quotaBlockedByDomain, isEmpty);
    });

    test('无知识点或没标签路径的题按无领域处理（不占上限、不报领域）', () {
      final plan = PaperComposer.compose(
        candidates: [
          _candidate(id: 'n1', points: const []),
          _candidate(id: 'n2', points: ['kp-nolabel']),
        ],
        spec: const PaperSpec(
          targetCount: 2,
          domainQuota: DomainQuota(
            maxPerDomain: {'数学': 1},
            minPerDomain: {'物理': 1},
          ),
        ),
        knowledgePointTagPaths: mathPaths,
      );
      expect(_ids(plan), ['n1', 'n2']);
      expect(plan.byDomain, isEmpty);
      expect(plan.quotaBlockedByDomain, isEmpty);
      expect(plan.domainShortfalls, hasLength(1));
      expect(plan.uncoveredDomains, ['物理']);
      expect(plan.domainShortfalls.single.isUncovered, isTrue);
    });

    test('附加领域只回报、不参与上限判定', () {
      final plan = PaperComposer.compose(
        candidates: [
          _candidate(id: 'x1', points: ['kp-multi'])
        ],
        spec: const PaperSpec(
          targetCount: 1,
          domainQuota: DomainQuota(maxPerDomain: {'物理': 0}),
        ),
        knowledgePointTagPaths: const {
          'kp-multi': ['物理/力学', '数学/函数'],
        },
      );
      expect(_ids(plan), ['x1']);
      expect(plan.quotaBlockedByDomain, isEmpty);
      expect(plan.byDomain, {'数学': 1, '物理': 1});
    });

    test('byDomain 统计主领域与附加领域（条目数可大于题数）', () {
      final plan = PaperComposer.compose(
        candidates: [
          _candidate(id: 'x1', points: ['kp-multi'])
        ],
        spec: const PaperSpec(
          targetCount: 1,
          domainQuota: DomainQuota(maxPerDomain: {'数学': 1}),
        ),
        knowledgePointTagPaths: const {
          'kp-multi': ['物理/力学', '数学/函数'],
        },
      );
      expect(plan.items, hasLength(1));
      expect(plan.byDomain.values.fold<int>(0, (sum, count) => sum + count), 2);
    });

    test('缺口：题库没有该领域题时 isUncovered=true', () {
      final plan = PaperComposer.compose(
        candidates: const [],
        spec: const PaperSpec(
          targetCount: 2,
          domainQuota: DomainQuota(minPerDomain: {'语文': 1}),
        ),
      );
      expect(plan.items, isEmpty);
      expect(plan.domainShortfalls, hasLength(1));
      final shortfall = plan.domainShortfalls.single;
      expect(shortfall.availableCount, 0);
      expect(shortfall.isUncovered, isTrue);
      expect(plan.uncoveredDomains, ['语文']);
    });

    test('缺口：有题但不够保底时 isUncovered=false', () {
      final plan = PaperComposer.compose(
        candidates: [
          _candidate(id: 'p1', subject: '物理', points: ['kp-physics']),
        ],
        spec: const PaperSpec(
          targetCount: 3,
          domainQuota: DomainQuota(minPerDomain: {'物理': 2}),
        ),
        knowledgePointTagPaths: const {
          'kp-physics': ['物理/力学'],
        },
      );
      expect(_ids(plan), ['p1']);
      final shortfall = plan.domainShortfalls.single;
      expect(shortfall.selectedCount, 1);
      expect(shortfall.availableCount, 1);
      expect(shortfall.isUncovered, isFalse);
      expect(plan.uncoveredDomains, isEmpty);
    });

    test('启用时 toJson 追加四个 snake_case 键', () {
      final plan = PaperComposer.compose(
        candidates: [
          _candidate(id: 'm1', points: ['kp-math']),
          _candidate(id: 'm2', points: ['kp-math']),
          _candidate(id: 'm3', points: ['kp-math']),
        ],
        spec: const PaperSpec(
          targetCount: 3,
          domainQuota: DomainQuota(maxPerDomain: {'数学': 2}),
        ),
        knowledgePointTagPaths: mathPaths,
      );
      final json = plan.toJson();
      expect(json['by_domain'], {'数学': 2});
      expect(json['domain_quota'], {
        'max_per_domain': {'数学': 2},
        'min_per_domain': {},
      });
      expect(json['quota_blocked_by_domain'], [
        {'question_id': 'm3', 'domain': '数学', 'domain_limit': 2},
      ]);
      expect(json['domain_shortfalls'], isEmpty);
      expect(json['schema'], 'mindnet.paper_plan/1');
    });

    test('默认关闭时输出与历史逐字节一致（候选顺序无关）', () {
      final forward = PaperComposer.compose(
        candidates: [
          _candidate(id: 'm1', points: ['kp-math']),
          _candidate(id: 'm2', points: ['kp-math']),
        ],
        spec: const PaperSpec(targetCount: 2),
      );
      final reversed = PaperComposer.compose(
        candidates: [
          _candidate(id: 'm2', points: ['kp-math']),
          _candidate(id: 'm1', points: ['kp-math']),
        ],
        spec: const PaperSpec(targetCount: 2),
      );
      final encoded = jsonEncode(forward.toJson());
      expect(encoded, jsonEncode(reversed.toJson()));
      expect(encoded.contains('by_domain'), isFalse);
    });

    test('启用领域配额时整体确定性（候选顺序无关）', () {
      List<PaperCandidate> candidates() => [
            _candidate(
                id: 'p1',
                subject: '物理',
                source: 'school',
                points: ['kp-physics']),
            _candidate(id: 'm2', points: ['kp-math']),
            _candidate(id: 'm1', points: ['kp-math']),
          ];
      const spec = PaperSpec(
        targetCount: 3,
        domainQuota: DomainQuota(
          maxPerDomain: {'数学': 1},
          minPerDomain: {'物理': 1},
        ),
      );
      const paths = {
        'kp-math': ['数学/函数'],
        'kp-physics': ['物理/力学'],
      };
      final forward = PaperComposer.compose(
        candidates: candidates(),
        spec: spec,
        knowledgePointTagPaths: paths,
      );
      final reversed = PaperComposer.compose(
        candidates: candidates().reversed.toList(),
        spec: spec,
        knowledgePointTagPaths: paths,
      );
      expect(_ids(forward), ['p1', 'm1']);
      expect(jsonEncode(forward.toJson()), jsonEncode(reversed.toJson()));
    });
  });
}
