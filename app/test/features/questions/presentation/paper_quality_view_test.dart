/// 组卷质量体检卡的界面契约（task-46）。
///
/// 断言四件事：
/// 1. 报告没算完/算错时安静降级（不占高度 / 只说算不出来，别抛给页面）；
/// 2. 干净报告与命中判据的两种态都说人话，判据按错误→警告→提示分组；
/// 3. evidence 可展开/收起，键与取值按领域层口径中文化，未收录键原样显示；
/// 4. 空卷报告也渲染（领域层给了 empty_plan 的 error，不能折叠成不占高度）。
///
/// 判据本身是否正确由 domain/services/paper/paper_quality_report.dart 的测试负责。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/paper/paper_quality_report.dart';
import 'package:furnace/features/questions/application/paper_quality_provider.dart';
import 'package:furnace/features/questions/presentation/paper_quality_view.dart';
import 'package:furnace/l10n/app_localizations.dart';

void main() {
  late AppLocalizations zh;

  setUpAll(() async {
    zh = await AppLocalizations.delegate.load(const Locale('zh'));
  });

  group('纯逻辑', () {
    test('percent：有限非负数转百分比，坏数据记 —', () {
      expect(paperQualityPercent(0.5), '50%');
      expect(paperQualityPercent(0), '0%');
      expect(paperQualityPercent(1), '100%');
      expect(paperQualityPercent(2.0 / 3.0), '67%');
      expect(paperQualityPercent(-0.1), '—');
      expect(paperQualityPercent(double.nan), '—');
      expect(paperQualityPercent(double.infinity), '—');
    });

    test('evidence 键与取值都按领域层口径中文化', () {
      expect(paperQualityEvidenceLabel('fill_ratio'), '填充率');
      expect(paperQualityEvidenceLabel('no_such_key'), 'no_such_key');
      expect(paperQualityEvidenceValue('fill_ratio', '0.5'), '50%');
      expect(paperQualityEvidenceValue('coverage', '0'), '0%');
      expect(paperQualityEvidenceValue('subject_key', 'math'), '数学');
      expect(
        paperQualityEvidenceValue('subject_key', ' '),
        kPaperQualityUnknownSubjectLabel,
      );
      expect(paperQualityEvidenceValue('source_level', 'gaokao'), '高考');
      expect(paperQualityEvidenceValue('zone', 'danger'), '危险区');
      expect(paperQualityEvidenceValue('truncated', 'true'), '是');
      expect(paperQualityEvidenceValue('truncated', 'false'), '否');
      expect(paperQualityEvidenceValue('no_such_key', 'raw'), 'raw');
    });

    test('evidence 行保持原顺序', () {
      final rows = paperQualityEvidenceRows(const {
        'requested_count': '2',
        'fill_ratio': '0.5',
        'subject_key': 'physics',
      });
      expect(rows.map((row) => row.label).toList(), [
        '想要几道',
        '填充率',
        '学科',
      ]);
      expect(rows.map((row) => row.value).toList(), ['2', '50%', '物理']);
    });

    test('warningsOf 只留指定严重度', () {
      final report = _report(
        warnings: [
          _warning(PaperQualitySeverity.error, '错误一'),
          _warning(PaperQualitySeverity.warning, '警告一'),
          _warning(PaperQualitySeverity.info, '提示一'),
        ],
      );
      expect(
        paperQualityWarningsOf(report, PaperQualitySeverity.error)
            .map((warning) => warning.messageZh)
            .toList(),
        ['错误一'],
      );
      expect(
        paperQualityWarningsOf(report, PaperQualitySeverity.warning)
            .map((warning) => warning.messageZh)
            .toList(),
        ['警告一'],
      );
      expect(
        paperQualityWarningsOf(report, PaperQualitySeverity.info)
            .map((warning) => warning.messageZh)
            .toList(),
        ['提示一'],
      );
    });

    test('严重度图标互不相同，zone 键能翻中文', () {
      final icons = <IconData>{
        for (final severity in PaperQualitySeverity.values)
          paperQualitySeverityIcon(severity),
      };
      expect(icons, hasLength(3));
      expect(paperQualityZoneLabel('danger'), '危险区');
      expect(paperQualityZoneLabel('healthy'), '健康');
      expect(paperQualityZoneLabel('nope'), isNull);
    });
  });

  group('体检卡', () {
    testWidgets('报告未算完：安静地不占高度', (tester) async {
      final gate = Completer<PaperQualityReport>();
      await _pumpSection(tester, load: () => gate.future);

      expect(find.byKey(paperQualitySectionKey), findsNothing);
      expect(find.text(zh.paperQualityTitle), findsNothing);
    });

    testWidgets('报告算错：只说算不出来，不把异常抛给页面', (tester) async {
      await _pumpSection(
        tester,
        load: () async => throw StateError('quality boom'),
      );

      expect(find.byKey(paperQualitySectionKey), findsOneWidget);
      expect(find.text(zh.paperQualityFailed), findsOneWidget);
    });

    testWidgets('干净报告：摘要 + 覆盖率 + 没有命中判据', (tester) async {
      await _pumpSection(
        tester,
        load: () async => _report(
          questionCount: 2,
          requestedCount: 2,
          fillRatio: 1,
          knowledgePointCoverage: 0.5,
        ),
      );

      expect(find.text(zh.paperQualityTitle), findsOneWidget);
      expect(find.text(zh.paperQualitySummary(2, 2, '100%')), findsOneWidget);
      expect(find.text(zh.paperQualityCoverage('50%')), findsOneWidget);
      expect(find.text(zh.paperQualityClean), findsOneWidget);
      for (final severity in PaperQualitySeverity.values) {
        expect(find.byKey(paperQualityGroupKey(severity)), findsNothing);
      }
    });

    testWidgets('有判据：按错误/警告/提示分组，详情原文可见', (tester) async {
      await _pumpSection(
        tester,
        load: () async => _report(
          warnings: [
            _warning(PaperQualitySeverity.error, '卷面空：一道题都没排进来'),
            _warning(PaperQualitySeverity.warning, '题数不够：实际题数少于目标题数'),
            _warning(PaperQualitySeverity.info, '没有逐题难度读数，难度判据未评估'),
          ],
        ),
      );

      expect(find.text(zh.paperQualityClean), findsNothing);
      for (final severity in PaperQualitySeverity.values) {
        expect(find.byKey(paperQualityGroupKey(severity)), findsOneWidget);
      }
      expect(find.text('卷面空：一道题都没排进来'), findsOneWidget);
      expect(find.text(zh.paperQualityGroupHeader('错误', 1)), findsOneWidget);

      final errorY = tester
          .getTopLeft(
              find.byKey(paperQualityGroupKey(PaperQualitySeverity.error)))
          .dy;
      final warningY = tester
          .getTopLeft(
            find.byKey(paperQualityGroupKey(PaperQualitySeverity.warning)),
          )
          .dy;
      final infoY = tester
          .getTopLeft(
              find.byKey(paperQualityGroupKey(PaperQualitySeverity.info)))
          .dy;
      expect(errorY, lessThan(warningY));
      expect(warningY, lessThan(infoY));
    });

    testWidgets('evidence 可展开收起，取值按证据口径格式化', (tester) async {
      await _pumpSection(
        tester,
        load: () async => _report(
          warnings: [
            _warning(
              PaperQualitySeverity.warning,
              '学科过于集中：单学科占比超过阈值',
              evidence: const {
                'subject_key': 'math',
                'ratio': '0.75',
                'no_such_key': 'raw',
              },
            ),
          ],
        ),
      );

      expect(find.text(zh.paperQualityEvidenceTitle), findsNothing);
      await tester.tap(find.byKey(paperQualityEvidenceToggleKey(0)));
      await tester.pumpAndSettle();

      expect(find.text(zh.paperQualityEvidenceTitle), findsOneWidget);
      expect(find.text('学科：数学'), findsOneWidget);
      expect(find.text('占比：75%'), findsOneWidget);
      expect(find.text('no_such_key：raw'), findsOneWidget);
      expect(find.text(zh.paperQualityEvidenceCollapse), findsOneWidget);

      await tester.tap(find.byKey(paperQualityEvidenceToggleKey(0)));
      await tester.pumpAndSettle();

      expect(find.text(zh.paperQualityEvidenceTitle), findsNothing);
      expect(find.text('学科：数学'), findsNothing);
      expect(find.text(zh.paperQualityEvidenceToggle), findsOneWidget);
    });

    testWidgets('保底没满足与截断提示都如实显示', (tester) async {
      await _pumpSection(
        tester,
        load: () async => _report(
          quotaSatisfied: false,
          truncatedWarningCount: 3,
          warnings: [_warning(PaperQualitySeverity.error, '学科保底没达成')],
        ),
      );

      expect(find.text(zh.paperQualityQuotaUnsatisfied), findsOneWidget);
      expect(find.text(zh.paperQualityTruncated(3)), findsOneWidget);
    });

    testWidgets('空卷报告也渲染：不折叠成不占高度', (tester) async {
      await _pumpSection(
        tester,
        load: () async => _report(
          questionCount: 0,
          requestedCount: 5,
          fillRatio: 0,
          knowledgePointCoverage: 0,
          warnings: [_warning(PaperQualitySeverity.error, '卷面空：一道题都没排进来')],
        ),
      );

      expect(find.byKey(paperQualitySectionKey), findsOneWidget);
      expect(find.text(zh.paperQualitySummary(0, 5, '0%')), findsOneWidget);
      expect(find.text('卷面空：一道题都没排进来'), findsOneWidget);
    });
  });
}

// ---------------------------------------------------------------------------
// 装置
// ---------------------------------------------------------------------------

Future<void> _pumpSection(
  WidgetTester tester, {
  required Future<PaperQualityReport> Function() load,
}) async {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        paperQualityReportProvider.overrideWith((ref) => load()),
      ],
      child: const MaterialApp(
        locale: Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            padding: EdgeInsets.all(16),
            child: PaperQualitySection(),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

PaperQualityReport _report({
  int questionCount = 1,
  int requestedCount = 2,
  double fillRatio = 0.5,
  double knowledgePointCoverage = 0.25,
  bool quotaSatisfied = true,
  List<PaperQualityWarning> warnings = const [],
  int truncatedWarningCount = 0,
}) {
  return PaperQualityReport(
    questionCount: questionCount,
    requestedCount: requestedCount,
    fillRatio: fillRatio,
    subjectDistribution: const [],
    domainDistribution: const [],
    difficultyDistribution: const [],
    sourceLevelDistribution: const [],
    zoneDistribution: const [],
    coveredKnowledgePointCount: 1,
    knowledgePointCoverage: knowledgePointCoverage,
    uncoveredKnowledgePointIds: const [],
    quotaSatisfied: quotaSatisfied,
    warnings: warnings,
    truncatedWarningCount: truncatedWarningCount,
  );
}

PaperQualityWarning _warning(
  PaperQualitySeverity severity,
  String messageZh, {
  Map<String, String> evidence = const {},
}) {
  return PaperQualityWarning(
    code: 'test_code',
    severity: severity,
    messageZh: messageZh,
    evidence: evidence,
  );
}
