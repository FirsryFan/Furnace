import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/export/paper_docx.dart';
import 'package:furnace/domain/services/paper/paper_composer.dart';
import 'package:furnace/domain/services/paper/paper_quality_report.dart';
import 'package:furnace/domain/services/paper/subject_quota.dart';

/// 题目卷「组卷说明」里的组卷质量节：开关、总览、四类分布、命中判据与
/// 版面上限，以及默认不传报告时卷面与旧版逐字节一致。
void main() {
  group('质量节：开关与默认输出', () {
    test('不传报告与显式 null 逐字节一致，且没有质量节', () {
      final plan = _plan(items: <PaperItem>[_item('q1'), _item('q2')]);
      final questions = _questions(<String>['q1', 'q2']);
      final withDefault = buildPaperDocx(
        plan: plan,
        questions: questions,
        knowledgePointNames: const <String, String>{},
        generatedAt: DateTime(2026, 10, 18, 22, 5),
      );
      final withNull = buildPaperDocx(
        plan: plan,
        questions: questions,
        knowledgePointNames: const <String, String>{},
        generatedAt: DateTime(2026, 10, 18, 22, 5),
        qualityReport: null,
      );
      final document = _documentXml(withNull);
      expect(withDefault.bytes, orderedEquals(withNull.bytes));
      expect(document, isNot(contains('组卷质量')));
      expect(document, isNot(contains('组卷说明')));
    });

    test('关掉组卷说明时质量报告不渲染', () {
      final plan = _plan(
        items: <PaperItem>[_item('q1')],
        bySubject: const <String, int>{'math': 1},
      );
      final questions = _questions(<String>['q1']);
      const labels = PaperDocxLabels();
      final withoutReport = buildPaperDocx(
        plan: plan,
        questions: questions,
        knowledgePointNames: const <String, String>{},
        labels: labels,
        includeCompositionNotes: false,
      );
      final withReport = buildPaperDocx(
        plan: plan,
        questions: questions,
        knowledgePointNames: const <String, String>{},
        labels: labels,
        includeCompositionNotes: false,
        qualityReport: _report(plan),
      );
      expect(withReport.bytes, orderedEquals(withoutReport.bytes));
      expect(_documentXml(withReport), isNot(contains('组卷质量')));
    });

    test('plan 没有组卷说明数据、只有质量报告时也渲染组卷说明', () {
      final plan = _plan(items: <PaperItem>[_item('q1')]);
      final document = _documentXml(
        buildPaperDocx(
          plan: plan,
          questions: _questions(<String>['q1']),
          knowledgePointNames: const <String, String>{},
          qualityReport: _report(plan),
        ),
      );
      expect(document, contains('组卷说明'));
      expect(document, contains('组卷质量'));
    });

    test('质量节排在组卷说明末尾，整卷分页仍只有一次', () {
      final plan = _plan(
        items: <PaperItem>[_item('q1')],
        shortfalls: <SubjectQuotaShortfall>[
          const SubjectQuotaShortfall(
            subjectKey: 'math',
            minimumCount: 2,
            selectedCount: 1,
            availableCount: 1,
          ),
        ],
      );
      final document = _documentXml(
        buildPaperDocx(
          plan: plan,
          questions: _questions(<String>['q1']),
          knowledgePointNames: const <String, String>{},
          qualityReport: _report(plan),
        ),
      );
      final heading = document.indexOf('组卷质量');
      expect(heading, greaterThan(document.indexOf('保底缺口')));
      expect('<w:pageBreakBefore/>'.allMatches(document).length, 1);
    });

    test('同一输入两次导出字节相等', () {
      final plan = _plan(items: <PaperItem>[_item('q1')]);
      final report = _report(plan);
      Uint8List run() => buildPaperDocx(
            plan: plan,
            questions: _questions(<String>['q1']),
            knowledgePointNames: const <String, String>{},
            qualityReport: report,
            generatedAt: DateTime(2026, 10, 18, 22, 5),
          ).bytes;
      expect(run(), orderedEquals(run()));
    });
  });

  group('质量节：总览与分布', () {
    test('总览写题数、目标、填充率与三档判据计数', () {
      final plan = _plan(items: _pairItems(), requestedCount: 3);
      final document = _documentXml(
        buildPaperDocx(
          plan: plan,
          questions: _questions(<String>['q1', 'q2']),
          knowledgePointNames: const <String, String>{},
          qualityReport: _report(plan),
        ),
      );
      expect(document, contains('卷面：2 / 目标 3 道，填充率 66.7%'));
      expect(document, contains('判据：错误 0 条、警告 1 条、提示 1 条'));
    });

    test('学科、来源、区域分布按报告顺序写出，空分布不写空行', () {
      final plan = _plan(items: _pairItems());
      final document = _documentXml(
        buildPaperDocx(
          plan: plan,
          questions: _questions(<String>['q1', 'q2']),
          knowledgePointNames: const <String, String>{},
          qualityReport: _report(
            plan,
            subjectNames: const <String, String>{'math': '数学', 'physics': '物理'},
          ),
        ),
      );
      expect(document, contains('学科分布：数学 1 道（50.0%）、物理 1 道（50.0%）'));
      expect(document, contains('来源分布：高考 1 道（50.0%）、校考 1 道（50.0%）'));
      expect(document, contains('区域分布：危险区 1 道（50.0%）、发展区 1 道（50.0%）'));
      expect(document, isNot(contains('难度分布：')));
    });

    test('难度分布用展示名写档位', () {
      final plan = _plan(items: _pairItems());
      final document = _documentXml(
        buildPaperDocx(
          plan: plan,
          questions: _questions(<String>['q1', 'q2']),
          knowledgePointNames: const <String, String>{},
          qualityReport: _report(
            plan,
            difficulties: const <String, double>{'q1': 3.0, 'q2': 5.0},
            difficultyLabels: const <String, String>{'3.0': '容易', '5.0': '中档'},
          ),
        ),
      );
      expect(document, contains('难度分布：容易 1 道（50.0%）、中档 1 道（50.0%）'));
      expect(document, contains('没有命中任何判据'));
    });

    test('分布超过上限折叠成「其余 N 项」，不静默丢题', () {
      final items = <PaperItem>[
        for (var i = 1; i <= 8; i++) _item('q$i', subject: 's$i', kp: 'kp$i'),
      ];
      final plan = _plan(items: items);
      final document = _documentXml(
        buildPaperDocx(
          plan: plan,
          questions: _questions(
              <String>['q1', 'q2', 'q3', 'q4', 'q5', 'q6', 'q7', 'q8']),
          knowledgePointNames: const <String, String>{},
          qualityReport: _report(plan),
        ),
      );
      expect(document, contains('s6 1 道（12.5%）、其余 2 项'));
      expect(document, isNot(contains('s7 1 道')));
      expect(document, isNot(contains('s8 1 道')));
    });

    test('空卷只写一条错误判据，填充率记 0', () {
      final plan = _plan(items: const <PaperItem>[], requestedCount: 2);
      final document = _documentXml(
        buildPaperDocx(
          plan: plan,
          questions: const <String, PaperDocxQuestion>{},
          knowledgePointNames: const <String, String>{},
          qualityReport: _report(plan),
        ),
      );
      expect(document, contains('卷面：0 / 目标 2 道，填充率 0.0%'));
      expect(document, contains('判据：错误 1 条、警告 0 条、提示 0 条'));
      expect(document, contains('[错误] 卷面是空的：没有排进任何题（目标 2 道）。'));
    });

    test('英文 labels 可覆盖质量节文案', () {
      final plan = _plan(items: _pairItems());
      final document = _documentXml(
        buildPaperDocx(
          plan: plan,
          questions: _questions(<String>['q1', 'q2']),
          knowledgePointNames: const <String, String>{},
          labels: const PaperDocxLabels(
            qualityHeading: 'Paper Quality',
            qualityOverview: 'Filled',
            qualitySeverityPrefix: 'Findings',
            qualitySeverityError: 'E',
            qualitySeverityWarning: 'W',
            qualitySeverityInfo: 'I',
            qualityDistributionSubject: 'By subject',
            qualityNoWarnings: 'No findings',
          ),
          qualityReport: _report(plan),
        ),
      );
      expect(document, contains('Paper Quality'));
      expect(document, contains('Filled：2 / 目标 2 道'));
      expect(document, contains('Findings：E 0 条、W 0 条、I 1 条'));
      expect(document, contains('By subject：'));
    });
  });

  group('质量节：命中判据与截断', () {
    test('报告没有任何命中判据时写占位句', () {
      final plan = _plan(items: <PaperItem>[_item('q1')]);
      final document = _documentXml(
        buildPaperDocx(
          plan: plan,
          questions: _questions(<String>['q1']),
          knowledgePointNames: const <String, String>{},
          qualityReport: _manualReport(warnings: const <PaperQualityWarning>[]),
        ),
      );
      expect(document, contains('没有命中任何判据'));
      expect(document, contains('判据：错误 0 条、警告 0 条、提示 0 条'));
      expect(document, isNot(contains('报告侧截断')));
    });

    test('同一判据多条只列前 3 条并写同类总数', () {
      final warnings = <PaperQualityWarning>[
        for (var i = 1; i <= 5; i++)
          PaperQualityWarning(
            code: 'subject_min_shortfall',
            severity: PaperQualitySeverity.warning,
            messageZh: '第 $i 条判据。',
          ),
      ];
      final document = _documentXml(
        buildPaperDocx(
          plan: _plan(items: <PaperItem>[_item('q1')]),
          questions: _questions(<String>['q1']),
          knowledgePointNames: const <String, String>{},
          qualityReport: _manualReport(warnings: warnings),
        ),
      );
      expect('· [警告]'.allMatches(document).length, 3);
      expect(document, contains('第 3 条判据。'));
      expect(document, isNot(contains('第 5 条判据。')));
      expect(document, contains('同类共 5 条，已显示前 3 条'));
    });

    test('不同判据各自折叠计数', () {
      final warnings = <PaperQualityWarning>[
        for (var i = 1; i <= 4; i++)
          PaperQualityWarning(
            code: 'fill_short',
            severity: PaperQualitySeverity.warning,
            messageZh: '填充判据 $i。',
          ),
        for (var i = 1; i <= 5; i++)
          PaperQualityWarning(
            code: 'quota_blocked',
            severity: PaperQualitySeverity.info,
            messageZh: '配额判据 $i。',
          ),
      ];
      final document = _documentXml(
        buildPaperDocx(
          plan: _plan(items: <PaperItem>[_item('q1')]),
          questions: _questions(<String>['q1']),
          knowledgePointNames: const <String, String>{},
          qualityReport: _manualReport(warnings: warnings),
        ),
      );
      expect(document, contains('同类共 4 条，已显示前 3 条'));
      expect(document, contains('同类共 5 条，已显示前 3 条'));
      expect('· [提示]'.allMatches(document).length, 3);
    });

    test('报告侧按 code 截断时如实写未展开条数', () {
      final document = _documentXml(
        buildPaperDocx(
          plan: _plan(items: <PaperItem>[_item('q1')]),
          questions: _questions(<String>['q1']),
          knowledgePointNames: const <String, String>{},
          qualityReport: _manualReport(
            warnings: const <PaperQualityWarning>[
              PaperQualityWarning(
                code: 'fill_short',
                severity: PaperQualitySeverity.warning,
                messageZh: '题数不够。',
              ),
            ],
            truncatedWarningCount: 4,
          ),
        ),
      );
      expect(document, contains('报告侧截断：另有 4 条同类判据未展开'));
    });

    test('真实报告的每条命中判据文案都进卷面', () {
      final plan = _plan(
        items: _pairItems(),
        requestedCount: 5,
        uncovered: const <String>['kp-missing'],
      );
      final report = _report(plan);
      final document = _documentXml(
        buildPaperDocx(
          plan: plan,
          questions: _questions(<String>['q1', 'q2']),
          knowledgePointNames: const <String, String>{},
          qualityReport: report,
        ),
      );
      expect(report.warnings, isNotEmpty);
      for (final warning in report.warnings) {
        expect(document, contains(warning.messageZh));
      }
    });
  });
}

// ---------------------------------------------------------------------------
// 测试夹具
// ---------------------------------------------------------------------------

PaperItem _item(
  String id, {
  String subject = 'math',
  String source = 'gaokao',
  String kp = 'kp1',
  PaperZone zone = PaperZone.danger,
}) =>
    PaperItem(
      questionId: id,
      subjectKey: subject,
      sourceLevel: source,
      questionType: 'solution',
      knowledgePointId: kp,
      matchedKnowledgePointIds: <String>[kp],
      zone: zone,
      need: 0.5,
      quality: 0.8,
      score: 0.7,
      reasonZh: '理由。',
      improvementNote: '提升点。',
      backgroundZh: '背景。',
    );

List<PaperItem> _pairItems() => <PaperItem>[
      _item('q1'),
      _item('q2',
          subject: 'physics', source: 'school', zone: PaperZone.development),
    ];

PaperPlan _plan({
  required List<PaperItem> items,
  int? requestedCount,
  List<String> uncovered = const <String>[],
  List<SubjectQuotaShortfall> shortfalls = const <SubjectQuotaShortfall>[],
  Map<String, int> bySubject = const <String, int>{},
}) =>
    PaperPlan(
      items: items,
      uncoveredKnowledgePointIds: uncovered,
      deferredKnowledgePointIds: const <String>[],
      byKnowledgePoint: const <String, int>{},
      candidateCount: items.length,
      requestedCount: requestedCount ?? items.length,
      overallNeed: 0.5,
      weights: const PaperWeights(),
      bySubject: bySubject,
      subjectShortfalls: shortfalls,
    );

Map<String, PaperDocxQuestion> _questions(Iterable<String> ids) =>
    <String, PaperDocxQuestion>{
      for (final id in ids)
        id: PaperDocxQuestion(
            questionId: id, serialNo: 'TR-$id', stem: '题干 $id。'),
    };

PaperQualityReport _report(
  PaperPlan plan, {
  Map<String, String> subjectNames = const <String, String>{},
  Map<String, double> difficulties = const <String, double>{},
  Map<String, String> difficultyLabels = const <String, String>{},
}) =>
    PaperQualityReport.build(
      plan: plan,
      subjectNames: subjectNames,
      difficultyByQuestionId: difficulties,
      difficultyLabels: difficultyLabels,
    );

PaperQualityReport _manualReport({
  List<PaperQualityWarning> warnings = const <PaperQualityWarning>[],
  int truncatedWarningCount = 0,
}) =>
    PaperQualityReport(
      questionCount: 1,
      requestedCount: 1,
      fillRatio: 1.0,
      subjectDistribution: const <PaperQualityBucket>[],
      domainDistribution: const <PaperQualityBucket>[],
      difficultyDistribution: const <PaperQualityBucket>[],
      sourceLevelDistribution: const <PaperQualityBucket>[],
      zoneDistribution: const <PaperQualityBucket>[],
      coveredKnowledgePointCount: 1,
      knowledgePointCoverage: 1.0,
      uncoveredKnowledgePointIds: const <String>[],
      quotaSatisfied: true,
      warnings: warnings,
      truncatedWarningCount: truncatedWarningCount,
    );

Map<String, String> unzipText(Uint8List bytes) {
  final archive = ZipDecoder().decodeBytes(bytes);
  final result = <String, String>{};
  for (final file in archive) {
    if (!file.isFile) continue;
    result[file.name] = utf8.decode(file.content as List<int>);
  }
  return result;
}

String _documentXml(PaperDocxBuildResult result) =>
    unzipText(result.bytes)['word/document.xml']!;
