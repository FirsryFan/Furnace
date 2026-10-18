import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/paper/domain_quota.dart';
import 'package:furnace/domain/services/paper/paper_composer.dart';
import 'package:furnace/domain/services/paper/paper_quality_report.dart';
import 'package:furnace/domain/services/paper/subject_quota.dart';

PaperItem _item({
  required String id,
  String subject = '数学',
  String source = 'gaokao',
  String? point = 'kp-1',
  List<String> matched = const <String>[],
  PaperZone zone = PaperZone.healthy,
}) {
  return PaperItem(
    questionId: id,
    subjectKey: subject,
    sourceLevel: source,
    questionType: 'solution',
    knowledgePointId: point,
    matchedKnowledgePointIds: matched,
    zone: zone,
    need: 0.5,
    quality: 0.8,
    score: 0.7,
    reasonZh: 'r',
    improvementNote: 'i',
    backgroundZh: 'b',
  );
}

PaperPlan _plan({
  List<PaperItem> items = const <PaperItem>[],
  int? requested,
  List<String> uncovered = const <String>[],
  Map<String, int> byDomain = const <String, int>{},
  List<QuotaBlockedQuestion> blocked = const <QuotaBlockedQuestion>[],
  List<SubjectQuotaShortfall> shortfalls = const <SubjectQuotaShortfall>[],
  List<DomainQuotaBlockedQuestion> domainBlocked =
      const <DomainQuotaBlockedQuestion>[],
  List<DomainQuotaShortfall> domainShortfalls = const <DomainQuotaShortfall>[],
  bool manual = false,
  List<String> manualMissing = const <String>[],
  List<String> manualSkipped = const <String>[],
  List<String> manualConflict = const <String>[],
}) {
  return PaperPlan(
    items: items,
    uncoveredKnowledgePointIds: uncovered,
    deferredKnowledgePointIds: const <String>[],
    byKnowledgePoint: const <String, int>{},
    candidateCount: items.length,
    requestedCount: requested ?? items.length,
    overallNeed: 0.5,
    weights: const PaperWeights(),
    quotaBlockedQuestions: blocked,
    subjectShortfalls: shortfalls,
    byDomain: byDomain,
    quotaBlockedByDomain: domainBlocked,
    domainShortfalls: domainShortfalls,
    manualSelectionEnabled: manual,
    manualIncludedCount: manual ? 1 : 0,
    manualMissingQuestionIds: manualMissing,
    manualSkippedQuestionIds: manualSkipped,
    manualConflictQuestionIds: manualConflict,
  );
}

PaperQualityReport _build(
  PaperPlan plan, {
  Map<String, String> subjectNames = const <String, String>{},
  Map<String, String> knowledgePointNames = const <String, String>{},
  Map<String, String> difficultyLabels = const <String, String>{},
  Map<String, String> sourceLevelNames = const <String, String>{},
  Map<String, double> difficulties = const <String, double>{},
  double? target,
  double tolerance = 1.0,
  int maxPerCode = 20,
}) {
  return PaperQualityReport.build(
    plan: plan,
    subjectNames: subjectNames,
    knowledgePointNames: knowledgePointNames,
    difficultyLabels: difficultyLabels,
    sourceLevelNames: sourceLevelNames,
    difficultyByQuestionId: difficulties,
    targetDifficulty: target,
    difficultyTolerance: tolerance,
    maxWarningsPerCode: maxPerCode,
  );
}

List<String> _codes(PaperQualityReport report) {
  return <String>[for (final warning in report.warnings) warning.code];
}

List<String> _warningCodes(PaperQualityReport report) {
  return <String>[
    for (final warning in report.warnings)
      if (warning.severity == PaperQualitySeverity.warning) warning.code,
  ];
}

PaperQualityWarning? _find(PaperQualityReport report, String code) {
  for (final warning in report.warnings) {
    if (warning.code == code) return warning;
  }
  return null;
}

PaperQualityBucket? _bucket(List<PaperQualityBucket> buckets, String key) {
  for (final bucket in buckets) {
    if (bucket.key == key) return bucket;
  }
  return null;
}

void main() {
  group('PaperQualityReport 空卷与填充率', () {
    test('空计划：error empty_plan，isEmpty，fillRatio 0，不抛异常', () {
      final report = _build(_plan());
      expect(report.isEmpty, isTrue);
      expect(report.questionCount, 0);
      expect(report.requestedCount, 0);
      expect(report.fillRatio, 0);
      expect(report.warnings.length, 1);
      expect(report.warnings.single.code, PaperQualityCodes.emptyPlan);
      expect(report.warnings.single.severity, PaperQualitySeverity.error);
      expect(report.hasWarnings, isTrue);
      expect(report.countsBySeverity[PaperQualitySeverity.error], 1);
      expect(report.severityCount(PaperQualitySeverity.info), 0);
    });

    test('空计划 + 目标 5 道：只报 empty_plan，不报 fill_short', () {
      final report = _build(_plan(requested: 5));
      expect(report.requestedCount, 5);
      expect(report.fillRatio, 0);
      expect(_codes(report), <String>[PaperQualityCodes.emptyPlan]);
    });

    test('有题但目标 0：fillRatio 记 0 且不报题数不够（目标负数按 0）', () {
      final report =
          _build(_plan(items: <PaperItem>[_item(id: 'q1')], requested: -3));
      expect(report.questionCount, 1);
      expect(report.requestedCount, 0);
      expect(report.fillRatio, 0);
      expect(_codes(report), isNot(contains(PaperQualityCodes.fillShort)));
    });

    test('题数不够：fill_short 带 missing_count 与两位小数填充率', () {
      final items = <PaperItem>[
        _item(id: 'q1', source: 'gaokao'),
        _item(id: 'q2', source: 'personal'),
        _item(id: 'q3', source: 'gaokao'),
      ];
      final report = _build(_plan(items: items, requested: 5));
      final warning = _find(report, PaperQualityCodes.fillShort);
      expect(warning, isNotNull);
      expect(warning!.severity, PaperQualitySeverity.warning);
      expect(warning.evidence['requested_count'], '5');
      expect(warning.evidence['question_count'], '3');
      expect(warning.evidence['missing_count'], '2');
      expect(warning.evidence['fill_ratio'], '0.60');
      expect(warning.messageZh, contains('差 2 道'));
      expect(report.fillRatio, closeTo(0.6, 0.000001));
    });

    test('题数刚好够：不报 fill_short', () {
      final items = <PaperItem>[_item(id: 'q1'), _item(id: 'q2')];
      final report = _build(_plan(items: items, requested: 2));
      expect(_codes(report), isNot(contains(PaperQualityCodes.fillShort)));
    });
  });

  group('PaperQualityReport 分布口径', () {
    test('学科分布按键升序、ratio 按题数、标签可覆盖', () {
      final items = <PaperItem>[
        _item(id: 'q1', subject: '数学'),
        _item(id: 'q2', subject: '数学'),
        _item(id: 'q3', subject: '物理'),
      ];
      final report = _build(_plan(items: items),
          subjectNames: <String, String>{'数学': '数学(自定义)'});
      expect(
        report.subjectDistribution.map((bucket) => bucket.key),
        <String>['数学', '物理'],
      );
      final math = _bucket(report.subjectDistribution, '数学')!;
      expect(math.labelZh, '数学(自定义)');
      expect(math.count, 2);
      expect(math.ratio, closeTo(2 / 3, 0.000001));
      expect(_bucket(report.subjectDistribution, '物理')!.labelZh, '物理');
    });

    test('空学科键进入未标注学科桶', () {
      final report =
          _build(_plan(items: <PaperItem>[_item(id: 'q1', subject: '  ')]));
      final bucket = report.subjectDistribution.single;
      expect(bucket.key, '');
      expect(bucket.labelZh, kPaperQualityUnknownSubjectLabel);
      expect(bucket.count, 1);
      expect(bucket.ratio, 1);
    });

    test('领域分布来自 byDomain，多领域可让 ratio 之和大于 1', () {
      final report = _build(_plan(
        items: <PaperItem>[_item(id: 'q1')],
        byDomain: <String, int>{'物理': 1, '数学': 3, '化学': 0},
      ));
      expect(
        report.domainDistribution.map((bucket) => bucket.key),
        <String>['数学', '物理'],
      );
      expect(_bucket(report.domainDistribution, '数学')!.ratio, 3);
      expect(_bucket(report.domainDistribution, '物理')!.ratio, 1);
      expect(_bucket(report.domainDistribution, '数学')!.labelZh, '数学');
    });

    test('难度分布按数值升序，key 保留一位小数，标签可覆盖', () {
      final items = <PaperItem>[
        _item(id: 'q1', source: 'personal'),
        _item(id: 'q2', source: 'personal'),
        _item(id: 'q3', source: 'personal'),
      ];
      final report = _build(
        _plan(items: items),
        difficulties: <String, double>{'q1': 5.0, 'q2': 3.0, 'q3': 4.0},
        difficultyLabels: <String, String>{'3.0': '易'},
      );
      expect(
        report.difficultyDistribution.map((bucket) => bucket.key),
        <String>['3.0', '4.0', '5.0'],
      );
      expect(_bucket(report.difficultyDistribution, '3.0')!.labelZh, '易');
      expect(_bucket(report.difficultyDistribution, '4.0')!.labelZh, '难度 4.0');
      expect(_codes(report),
          isNot(contains(PaperQualityCodes.difficultyDataPartial)));
    });

    test('只有部分题有难度：difficulty_data_partial info', () {
      final items = <PaperItem>[_item(id: 'q1'), _item(id: 'q2')];
      final report = _build(_plan(items: items),
          difficulties: <String, double>{'q1': 4.0});
      final warning = _find(report, PaperQualityCodes.difficultyDataPartial);
      expect(warning, isNotNull);
      expect(warning!.severity, PaperQualitySeverity.info);
      expect(warning.evidence['known_count'], '1');
      expect(warning.evidence['missing_count'], '1');
      expect(report.difficultyDistribution.length, 1);
    });

    test('完全没有难度读数：difficulty_data_unavailable info', () {
      final report = _build(_plan(items: <PaperItem>[_item(id: 'q1')]));
      final warning =
          _find(report, PaperQualityCodes.difficultyDataUnavailable);
      expect(warning, isNotNull);
      expect(warning!.severity, PaperQualitySeverity.info);
      expect(report.difficultyDistribution, isEmpty);
    });

    test('来源分布：空来源记 unknown，展示名可覆盖', () {
      final items = <PaperItem>[
        _item(id: 'q1', source: 'gaokao'),
        _item(id: 'q2', source: '  '),
        _item(id: 'q3', source: 'gaokao'),
      ];
      final report = _build(
        _plan(items: items),
        sourceLevelNames: <String, String>{'gaokao': '高考(覆盖)'},
      );
      expect(
        report.sourceLevelDistribution.map((bucket) => bucket.key),
        <String>['gaokao', 'unknown'],
      );
      expect(
          _bucket(report.sourceLevelDistribution, 'gaokao')!.labelZh, '高考(覆盖)');
      expect(_bucket(report.sourceLevelDistribution, 'unknown')!.labelZh, '未知');
    });

    test('zone 分布按 PaperZone 声明顺序、带中文标签', () {
      final items = <PaperItem>[
        _item(id: 'q1', zone: PaperZone.healthy),
        _item(id: 'q2', zone: PaperZone.danger),
        _item(id: 'q3', zone: PaperZone.healthy),
      ];
      final report = _build(_plan(items: items));
      expect(
        report.zoneDistribution.map((bucket) => bucket.key),
        <String>['danger', 'healthy'],
      );
      expect(_bucket(report.zoneDistribution, 'danger')!.labelZh, '危险区');
      expect(_bucket(report.zoneDistribution, 'healthy')!.labelZh, '健康');
      expect(_bucket(report.zoneDistribution, 'healthy')!.ratio,
          closeTo(2 / 3, 0.000001));
    });
  });

  group('PaperQualityReport 知识点覆盖', () {
    test('覆盖 = 主知识点 ∪ 匹配知识点，未覆盖按字典序', () {
      final items = <PaperItem>[
        _item(id: 'q1', point: 'kp-a', matched: <String>['kp-b', ' kp-b ']),
      ];
      final report = _build(
        _plan(items: items, uncovered: <String>['kp-c', ' kp-a ', '']),
        knowledgePointNames: <String, String>{'kp-c': '函数单调性'},
      );
      expect(report.coveredKnowledgePointCount, 2);
      expect(report.uncoveredKnowledgePointIds, <String>['kp-a', 'kp-c']);
      expect(report.knowledgePointCoverage, closeTo(2 / 3, 0.000001));
      final warning = _find(report, PaperQualityCodes.knowledgePointGap);
      expect(warning, isNotNull);
      expect(warning!.evidence['uncovered_count'], '2');
      expect(warning.evidence['covered_count'], '2');
      expect(warning.evidence['knowledge_point_ids'], 'kp-a, kp-c');
      expect(warning.evidence['knowledge_point_labels'], 'kp-a, 函数单调性');
    });

    test('一道题都没挂知识点：no_knowledge_points，且覆盖率记 0 不除零', () {
      final report =
          _build(_plan(items: <PaperItem>[_item(id: 'q1', point: null)]));
      expect(report.coveredKnowledgePointCount, 0);
      expect(report.knowledgePointCoverage, 0);
      expect(report.uncoveredKnowledgePointIds, isEmpty);
      expect(_codes(report), contains(PaperQualityCodes.noKnowledgePoints));
      expect(
          _codes(report), isNot(contains(PaperQualityCodes.knowledgePointGap)));
    });

    test('知识点 id 超过证据上限时截断并写总数', () {
      final uncovered = <String>[for (var i = 0; i < 12; i++) 'kp-00$i'];
      final report = _build(
        _plan(items: <PaperItem>[_item(id: 'q1')], uncovered: uncovered),
      );
      final warning = _find(report, PaperQualityCodes.knowledgePointGap)!;
      expect(warning.evidence['knowledge_point_ids'], endsWith('（共 12 个）'));
      expect(warning.evidence['knowledge_point_ids'], startsWith('kp-000'));
    });
  });

  group('PaperQualityReport 集中度 / 来源 / 难度 / zone 判据', () {
    test('单学科 3/4 超过阈值：subject_concentrated', () {
      final items = <PaperItem>[
        _item(id: 'q1', subject: '数学', source: 'gaokao'),
        _item(id: 'q2', subject: '数学', source: 'personal'),
        _item(id: 'q3', subject: '数学', source: 'school'),
        _item(id: 'q4', subject: '物理', source: 'elite_school'),
      ];
      final report = _build(_plan(items: items));
      final warning = _find(report, PaperQualityCodes.subjectConcentrated);
      expect(warning, isNotNull);
      expect(warning!.evidence['subject_key'], '数学');
      expect(warning.evidence['count'], '3');
      expect(warning.evidence['ratio'], '0.75');
      expect(warning.evidence['threshold'], '0.60');
    });

    test('单学科恰好 0.60 不算过于集中（严格大于阈值）', () {
      final items = <PaperItem>[
        _item(id: 'q1', subject: '数学', source: 'gaokao'),
        _item(id: 'q2', subject: '数学', source: 'personal'),
        _item(id: 'q3', subject: '数学', source: 'school'),
        _item(id: 'q4', subject: '物理', source: 'elite_school'),
        _item(id: 'q5', subject: '物理', source: 'personal'),
      ];
      final report = _build(_plan(items: items));
      expect(_codes(report),
          isNot(contains(PaperQualityCodes.subjectConcentrated)));
    });

    test('只有 1 道题时不报学科集中（低于最小题数）', () {
      final report = _build(_plan(items: <PaperItem>[_item(id: 'q1')]));
      expect(_codes(report),
          isNot(contains(PaperQualityCodes.subjectConcentrated)));
    });

    test('来源单一：3 道同源命中，2 道同源不命中', () {
      final three = <PaperItem>[
        _item(id: 'q1', source: 'school'),
        _item(id: 'q2', subject: '物理', source: 'school'),
        _item(id: 'q3', source: 'school'),
      ];
      final hit = _build(_plan(items: three));
      final warning = _find(hit, PaperQualityCodes.sourceNarrow);
      expect(warning, isNotNull);
      expect(warning!.evidence['source_level'], 'school');
      expect(warning.messageZh, contains('来自 校考'));

      final two = <PaperItem>[
        _item(id: 'q1', source: 'school'),
        _item(id: 'q2', subject: '物理', source: 'school'),
      ];
      expect(_codes(_build(_plan(items: two))),
          isNot(contains(PaperQualityCodes.sourceNarrow)));
    });

    test('难度过平：3 道题极差 0.4 小于阈值', () {
      final items = <PaperItem>[
        _item(id: 'q1', source: 'school'),
        _item(id: 'q2', subject: '物理', source: 'school'),
        _item(id: 'q3', source: 'school'),
      ];
      final report = _build(
        _plan(items: items),
        difficulties: <String, double>{'q1': 3.0, 'q2': 3.2, 'q3': 3.4},
      );
      final warning = _find(report, PaperQualityCodes.difficultyFlat);
      expect(warning, isNotNull);
      expect(warning!.evidence['item_count'], '3');
      expect(warning.evidence['spread'], '0.40');
      expect(warning.evidence['threshold'], '1.00');
    });

    test('难度极差 2.0 不算过平', () {
      final items = <PaperItem>[
        _item(id: 'q1', source: 'school'),
        _item(id: 'q2', subject: '物理', source: 'school'),
        _item(id: 'q3', source: 'school'),
      ];
      final report = _build(
        _plan(items: items),
        difficulties: <String, double>{'q1': 3.0, 'q2': 5.0, 'q3': 3.5},
      );
      expect(_codes(report), isNot(contains(PaperQualityCodes.difficultyFlat)));
    });

    test('难度偏离目标；偏差恰好等于容差时不报', () {
      final items = <PaperItem>[
        _item(id: 'q1', source: 'school'),
        _item(id: 'q2', subject: '物理', source: 'school'),
      ];
      final hit = _build(
        _plan(items: items),
        difficulties: <String, double>{'q1': 8.0, 'q2': 8.0},
        target: 5.0,
      );
      final warning = _find(hit, PaperQualityCodes.difficultyFarFromTarget);
      expect(warning, isNotNull);
      expect(warning!.evidence['mean'], '8.00');
      expect(warning.evidence['target'], '5.00');
      expect(warning.evidence['deviation'], '3.00');

      final same = _build(
        _plan(items: items),
        difficulties: <String, double>{'q1': 6.0, 'q2': 6.0},
        target: 5.0,
      );
      expect(_codes(same),
          isNot(contains(PaperQualityCodes.difficultyFarFromTarget)));
    });

    test('zone 失衡：3 道全危险区命中，全健康区不命中，2 道不算', () {
      final danger = <PaperItem>[
        _item(id: 'q1', zone: PaperZone.danger),
        _item(id: 'q2', subject: '物理', zone: PaperZone.danger),
        _item(id: 'q3', zone: PaperZone.danger),
      ];
      final hit = _build(_plan(items: danger));
      final warning = _find(hit, PaperQualityCodes.zoneImbalanced);
      expect(warning, isNotNull);
      expect(warning!.evidence['zone'], 'danger');
      expect(warning.evidence['count'], '3');

      final healthy = <PaperItem>[
        _item(id: 'q1'),
        _item(id: 'q2', subject: '物理'),
        _item(id: 'q3'),
      ];
      expect(_codes(_build(_plan(items: healthy))),
          isNot(contains(PaperQualityCodes.zoneImbalanced)));

      final twoDanger = <PaperItem>[
        _item(id: 'q1', zone: PaperZone.danger),
        _item(id: 'q2', subject: '物理', zone: PaperZone.danger),
      ];
      expect(_codes(_build(_plan(items: twoDanger))),
          isNot(contains(PaperQualityCodes.zoneImbalanced)));
    });
  });

  group('PaperQualityReport 配额与手工名单', () {
    test('学科保底没达成：subject_min_shortfall 带差几道与可用候选', () {
      final report = _build(_plan(
        items: <PaperItem>[_item(id: 'q1')],
        shortfalls: const <SubjectQuotaShortfall>[
          SubjectQuotaShortfall(
            subjectKey: '物理',
            minimumCount: 3,
            selectedCount: 1,
            availableCount: 4,
          ),
        ],
      ));
      final warning = _find(report, PaperQualityCodes.subjectMinShortfall);
      expect(warning, isNotNull);
      expect(warning!.evidence['subject_key'], '物理');
      expect(warning.evidence['minimum_count'], '3');
      expect(warning.evidence['selected_count'], '1');
      expect(warning.evidence['available_count'], '4');
      expect(warning.messageZh, contains('差 2 道'));
      expect(report.quotaSatisfied, isFalse);
    });

    test('学科保底没有可用题：uncovered_subject，不重复报 min_shortfall', () {
      final report = _build(_plan(
        items: <PaperItem>[_item(id: 'q1')],
        shortfalls: const <SubjectQuotaShortfall>[
          SubjectQuotaShortfall(
            subjectKey: '化学',
            minimumCount: 2,
            selectedCount: 0,
            availableCount: 0,
          ),
        ],
      ));
      final warning = _find(report, PaperQualityCodes.uncoveredSubject);
      expect(warning, isNotNull);
      expect(warning!.messageZh, contains('题库里 0 道候选'));
      expect(_codes(report),
          isNot(contains(PaperQualityCodes.subjectMinShortfall)));
    });

    test('领域保底缺口与领域无题分别报两条', () {
      final report = _build(_plan(
        items: <PaperItem>[_item(id: 'q1')],
        domainShortfalls: const <DomainQuotaShortfall>[
          DomainQuotaShortfall(
            domain: '物理',
            minimumCount: 2,
            selectedCount: 0,
            availableCount: 3,
          ),
          DomainQuotaShortfall(
            domain: '化学',
            minimumCount: 1,
            selectedCount: 0,
            availableCount: 0,
          ),
        ],
      ));
      final shortfall = _find(report, PaperQualityCodes.domainMinShortfall);
      expect(shortfall, isNotNull);
      expect(shortfall!.evidence['domain'], '物理');
      expect(shortfall.messageZh, contains('差 2 道'));
      final uncovered = _find(report, PaperQualityCodes.uncoveredDomain);
      expect(uncovered, isNotNull);
      expect(uncovered!.evidence['domain'], '化学');
      expect(report.quotaSatisfied, isFalse);
    });

    test('配额上限挡下：quota_blocked info 汇总学科与领域计数', () {
      final report = _build(_plan(
        items: <PaperItem>[_item(id: 'q1')],
        blocked: const <QuotaBlockedQuestion>[
          QuotaBlockedQuestion(
              questionId: 'q8', subjectKey: '数学', subjectLimit: 1),
          QuotaBlockedQuestion(
              questionId: 'q9', subjectKey: '数学', subjectLimit: 1),
        ],
        domainBlocked: const <DomainQuotaBlockedQuestion>[
          DomainQuotaBlockedQuestion(
              questionId: 'q10', domain: '物理', domainLimit: 1),
        ],
      ));
      final warning = _find(report, PaperQualityCodes.quotaBlocked);
      expect(warning, isNotNull);
      expect(warning!.severity, PaperQualitySeverity.info);
      expect(warning.evidence['subject_blocked_count'], '2');
      expect(warning.evidence['domain_blocked_count'], '1');
      expect(warning.evidence['subject_counts'], '数学 2 道');
      expect(warning.evidence['domain_counts'], '物理 1 道');
      expect(report.quotaSatisfied, isTrue);
    });

    test('手工名单有问题：manual_selection_issues info', () {
      final report = _build(_plan(
        items: <PaperItem>[_item(id: 'q1')],
        manual: true,
        manualMissing: const <String>['q-x'],
        manualSkipped: const <String>['q-y', 'q-z'],
      ));
      final warning = _find(report, PaperQualityCodes.manualSelectionIssues);
      expect(warning, isNotNull);
      expect(warning!.severity, PaperQualitySeverity.info);
      expect(warning.evidence['missing_ids'], '1');
      expect(warning.evidence['skipped_ids'], '2');
      expect(warning.evidence['conflict_ids'], '0');
      expect(warning.evidence['missing_preview'], 'q-x');
      expect(warning.evidence['skipped_preview'], 'q-y, q-z');
    });

    test('没启用手工名单且姓名都齐：不报 manual_selection_issues', () {
      final report = _build(_plan(items: <PaperItem>[_item(id: 'q1')]));
      expect(_codes(report),
          isNot(contains(PaperQualityCodes.manualSelectionIssues)));
      expect(report.quotaSatisfied, isTrue);
    });
  });

  group('PaperQualityReport 排序 / 截断 / toJson / 常量', () {
    test('warnings 先按严重度、同严重度按 code 升序', () {
      final items = <PaperItem>[
        _item(id: 'q1', source: 'school', point: null),
        _item(id: 'q2', subject: '物理', source: 'school', point: null),
        _item(id: 'q3', source: 'school', point: null),
      ];
      final report = _build(
        _plan(items: items, requested: 5, uncovered: <String>['kp-z']),
      );
      expect(
        _warningCodes(report),
        <String>[
          PaperQualityCodes.fillShort,
          PaperQualityCodes.knowledgePointGap,
          PaperQualityCodes.noKnowledgePoints,
          PaperQualityCodes.sourceNarrow,
          PaperQualityCodes.subjectConcentrated,
        ],
      );
      expect(report.warnings.last.severity, PaperQualitySeverity.info);
    });

    test('maxWarningsPerCode 截断：显式计数标记 + truncatedWarningCount', () {
      final report = _build(
        _plan(
          items: <PaperItem>[_item(id: 'q1')],
          shortfalls: <SubjectQuotaShortfall>[
            for (var i = 0; i < 5; i++)
              SubjectQuotaShortfall(
                subjectKey: '学科0$i',
                minimumCount: 2,
                selectedCount: 0,
                availableCount: 3,
              ),
          ],
        ),
        maxPerCode: 2,
      );
      expect(report.truncatedWarningCount, 3);
      final keptShortfalls = <PaperQualityWarning>[
        for (final warning in report.warnings)
          if (warning.code == PaperQualityCodes.subjectMinShortfall) warning,
      ];
      expect(keptShortfalls.length, 2);
      final last = keptShortfalls.last;
      expect(last.messageZh, endsWith('（同类共 5 条，已显示前 2 条）'));
      expect(last.evidence['truncated'], 'true');
      expect(last.evidence['total_for_code'], '5');
      expect(last.evidence['shown_for_code'], '2');
    });

    test('maxWarningsPerCode 小于等于 0 表示不截断', () {
      final report = _build(
        _plan(
          items: <PaperItem>[_item(id: 'q1')],
          shortfalls: <SubjectQuotaShortfall>[
            for (var i = 0; i < 5; i++)
              SubjectQuotaShortfall(
                subjectKey: '学科0$i',
                minimumCount: 2,
                selectedCount: 0,
                availableCount: 3,
              ),
          ],
        ),
        maxPerCode: 0,
      );
      expect(report.truncatedWarningCount, 0);
      expect(
        _codes(report)
            .where((code) => code == PaperQualityCodes.subjectMinShortfall)
            .length,
        5,
      );
      expect(
          report.warnings.any((warning) => warning.messageZh.contains('同类共')),
          isFalse);
    });

    test('两次 build 的 toJson 逐字节相等（确定性）', () {
      final items = <PaperItem>[
        _item(id: 'q1'),
        _item(id: 'q2', subject: '物理')
      ];
      final plan =
          _plan(items: items, requested: 3, uncovered: <String>['kp-9']);
      final first = jsonEncode(_build(plan).toJson());
      final second = jsonEncode(_build(plan).toJson());
      expect(first, second);
    });

    test('toJson 键序与 schema 固定，分布桶键名 snake_case', () {
      final report = _build(_plan(items: <PaperItem>[_item(id: 'q1')]));
      final json = report.toJson();
      expect(json.keys.toList(), <String>[
        'schema',
        'question_count',
        'requested_count',
        'fill_ratio',
        'subject_distribution',
        'domain_distribution',
        'difficulty_distribution',
        'source_level_distribution',
        'zone_distribution',
        'covered_knowledge_point_count',
        'knowledge_point_coverage',
        'uncovered_knowledge_point_ids',
        'quota_satisfied',
        'counts_by_severity',
        'truncated_warning_count',
        'warnings',
      ]);
      expect(json['schema'], kPaperQualitySchema);
      final counts = json['counts_by_severity']! as Map<String, int>;
      expect(counts.keys.toSet(), <String>{'error', 'warning', 'info'});
      final subject = (json['subject_distribution']! as List<Object?>).single!
          as Map<String, Object?>;
      expect(
          subject.keys.toList(), <String>['key', 'label_zh', 'count', 'ratio']);
      expect(subject['ratio'], 1.0);
    });

    test('纸面数字四舍五入到 6 位小数', () {
      final items = <PaperItem>[
        _item(id: 'q1', subject: '数学'),
        _item(id: 'q2', subject: '物理'),
        _item(id: 'q3', subject: '化学'),
      ];
      final report = _build(_plan(items: items));
      expect(report.fillRatio, 1);
      expect(report.toJson()['fill_ratio'], 1.0);
      expect(_bucket(report.subjectDistribution, '数学')!.ratio,
          closeTo(1 / 3, 0.000001));
    });

    test('code 清单与中文说明键集一致、顺序稳定且唯一', () {
      expect(PaperQualityCodes.all.length, 17);
      expect(
          PaperQualityCodes.all.toSet().length, PaperQualityCodes.all.length);
      expect(PaperQualityCodes.descriptions.keys.toSet(),
          PaperQualityCodes.all.toSet());
      expect(
          PaperQualityCodes.all.contains(PaperQualityCodes.emptyPlan), isTrue);
      expect(PaperQualityCodes.descriptions[PaperQualityCodes.quotaBlocked],
          isNotEmpty);
      expect(PaperQualitySeverity.values.map((value) => value.name).toList(),
          <String>['error', 'warning', 'info']);
      expect(PaperQualitySeverity.warning.labelZh, '警告');
    });
  });
}
