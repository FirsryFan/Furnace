import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/features/assessment/domain/assessment_models.dart';
import 'package:furnace/features/assessment/presentation/assessment_result_page.dart';
import 'package:furnace/l10n/app_localizations.dart';

void main() {
  late AppLocalizations zh;

  setUpAll(() async {
    zh = await AppLocalizations.delegate.load(const Locale('zh'));
  });

  final startedAt = DateTime(2026, 10, 27, 9, 0);

  AssessmentSessionSummary summary({
    String taskId = 'go_nogo',
    String status = 'completed',
    bool withCompletedAt = true,
  }) {
    return AssessmentSessionSummary(
      sessionId: 'session-1',
      taskId: taskId,
      designVersion: kAssessmentDesignVersion,
      device: AssessmentDevices.windowsMouse,
      startedAt: startedAt,
      completedAt:
          withCompletedAt ? startedAt.add(const Duration(minutes: 3)) : null,
      status: status,
    );
  }

  MetricSample metric(String name, double value) =>
      MetricSample(name: name, value: value, nTrials: 20);

  AbilityEstimate ability(
    String abilityId,
    double mean, {
    String source = EstimateSources.assessment,
    bool stale = false,
  }) {
    return AbilityEstimate(
      abilityId: abilityId,
      mean: mean,
      uncertainty: 0.3,
      nMeasurements: 2,
      source: source,
      stale: stale,
    );
  }

  ParamEstimate param(String paramId, double value) => ParamEstimate(
        paramId: paramId,
        value: value,
        uncertainty: 0.3,
        source: EstimateSources.derived,
      );

  Future<void> pumpResult(
    WidgetTester tester, {
    required AssessmentSessionSummary session,
    List<MetricSample> metrics = const <MetricSample>[],
    List<AbilityEstimate> abilities = const <AbilityEstimate>[],
    List<ParamEstimate> params = const <ParamEstimate>[],
    List<String> qualityFlags = const <String>[],
    VoidCallback? onDone,
  }) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: AssessmentResultPage(
          summary: session,
          metrics: metrics,
          abilities: abilities,
          params: params,
          qualityFlags: qualityFlags,
          onDone: onDone,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('标题、保存横幅、任务名与用时都上屏', (tester) async {
    await pumpResult(
      tester,
      session: summary(),
      metrics: [metric(MetricNames.accuracy, 0.85)],
      params: [param(CognitiveParamIds.taskDurationEstimate, 0.6)],
    );

    expect(find.text(zh.assessmentResultPageTitle), findsOneWidget);
    expect(find.byKey(assessmentResultSavedKey), findsOneWidget);
    expect(find.text(zh.assessmentResultSaved), findsOneWidget);
    expect(find.text(zh.taskGoNogo), findsOneWidget);
    expect(
      find.text(zh.assessmentResultDuration('03:00')),
      findsOneWidget,
    );
  });

  testWidgets('统计指标按任务产出的 metrics 渲染', (tester) async {
    await pumpResult(
      tester,
      session: summary(),
      metrics: [
        metric(MetricNames.accuracy, 0.85),
        metric(MetricNames.rtMedian, 512.6),
      ],
    );

    expect(find.byKey(assessmentResultMetricsKey), findsOneWidget);
    expect(
      find.byKey(assessmentResultMetricRowKey(MetricNames.accuracy)),
      findsOneWidget,
    );
    expect(
      find.byKey(assessmentResultMetricRowKey(MetricNames.rtMedian)),
      findsOneWidget,
    );
    expect(find.text(zh.metricAccuracy), findsOneWidget);
    expect(find.text('85.0%'), findsOneWidget);
    expect(find.text(zh.metricRtMedian), findsOneWidget);
    expect(find.text('513 ms'), findsOneWidget);
  });

  testWidgets('能力估计按稳定顺序排列，显示数值、来源与 stale', (tester) async {
    await pumpResult(
      tester,
      session: summary(),
      abilities: [
        ability(
          AbilityIds.inhibitoryControl,
          -0.5,
          source: EstimateSources.defaultPrior,
          stale: true,
        ),
        ability(AbilityIds.processingSpeed, 0.25),
      ],
    );

    expect(find.byKey(assessmentResultAbilitiesKey), findsOneWidget);
    expect(
      find.byKey(assessmentResultAbilityRowKey(AbilityIds.processingSpeed)),
      findsOneWidget,
    );
    expect(
      find.byKey(assessmentResultAbilityRowKey(AbilityIds.inhibitoryControl)),
      findsOneWidget,
    );
    expect(find.text(zh.abilityProcessingSpeed), findsOneWidget);
    expect(find.text('0.25'), findsOneWidget);
    expect(find.text(zh.assessmentProfileSourceAssessment), findsOneWidget);
    expect(find.text('-0.50'), findsOneWidget);
    expect(find.text(zh.assessmentProfileSourceDefault), findsOneWidget);
    expect(find.text(zh.assessmentProfileStale), findsOneWidget);

    final processing = tester.getTopLeft(
      find.byKey(assessmentResultAbilityRowKey(AbilityIds.processingSpeed)),
    );
    final inhibition = tester.getTopLeft(
      find.byKey(assessmentResultAbilityRowKey(AbilityIds.inhibitoryControl)),
    );
    expect(processing.dy, lessThan(inhibition.dy));
  });

  testWidgets('质量标记：有标记显示标记，无标记显示「无」', (tester) async {
    await pumpResult(
      tester,
      session: summary(),
      qualityFlags: ['too_fast', 'high_lapse'],
    );
    expect(find.byKey(assessmentResultQualityKey), findsOneWidget);
    expect(find.text('too_fast · high_lapse'), findsOneWidget);

    await pumpResult(tester, session: summary());
    expect(find.text(zh.assessmentResultQualityNone), findsOneWidget);
  });

  testWidgets('没有指标与能力时不出现空区块，也不崩', (tester) async {
    await pumpResult(
      tester,
      session: summary(withCompletedAt: false, status: 'aborted'),
    );

    expect(find.byKey(assessmentResultMetricsKey), findsNothing);
    expect(find.byKey(assessmentResultAbilitiesKey), findsNothing);
    expect(find.byKey(assessmentResultQualityKey), findsOneWidget);
    expect(find.byKey(assessmentResultSavedKey), findsOneWidget);
  });

  testWidgets('点完成触发回调', (tester) async {
    var doneCalls = 0;
    await pumpResult(tester, session: summary(), onDone: () => doneCalls++);

    await tester.tap(find.byKey(assessmentResultDoneKey));
    await tester.pumpAndSettle();
    expect(doneCalls, 1);
  });

  testWidgets('没有 onDone 时点完成关闭当前页', (tester) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => AssessmentResultPage(
                      summary: summary(),
                      metrics: const <MetricSample>[],
                      abilities: const <AbilityEstimate>[],
                      params: const <ParamEstimate>[],
                      qualityFlags: const <String>[],
                    ),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(AssessmentResultPage), findsOneWidget);

    await tester.tap(find.byKey(assessmentResultDoneKey));
    await tester.pumpAndSettle();
    expect(find.byType(AssessmentResultPage), findsNothing);
  });
}
