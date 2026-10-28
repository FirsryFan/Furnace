import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/features/assessment/application/assessment_providers.dart';
import 'package:furnace/features/assessment/application/assessment_session_service.dart';
import 'package:furnace/features/assessment/application/task_registry.dart';
import 'package:furnace/features/assessment/domain/assessment_estimates.dart';
import 'package:furnace/features/assessment/domain/assessment_models.dart';
import 'package:furnace/features/assessment/presentation/assessment_display.dart';
import 'package:furnace/features/assessment/presentation/assessment_result_page.dart';
import 'package:furnace/features/assessment/presentation/assessment_run_page.dart';
import 'package:furnace/l10n/app_localizations.dart';

void main() {
  late AppLocalizations zh;

  setUpAll(() async {
    zh = await AppLocalizations.delegate.load(const Locale('zh'));
  });

  AssessmentTaskConfig choiceTask({
    int trials = 2,
    int practiceTrials = 0,
    int responseWindowMs = 5000,
    List<String> qualityChecks = const <String>[],
  }) =>
      AssessmentTaskConfig(
        taskId: AssessmentTaskIds.fastSimpleI,
        displayName: '快速分类（图形）',
        taskType: AssessmentTaskType.choiceReaction,
        estimatedDurationSeconds: 120,
        config: <String, Object?>{
          'trials': trials,
          'practice_trials': practiceTrials,
          'isi_min_ms': 20,
          'isi_max_ms': 20,
          'response_window_ms': responseWindowMs,
        },
        qualityChecks: qualityChecks,
      );

  AssessmentTaskConfig goNogoTask({
    int trials = 1,
    int responseWindowMs = 5000,
  }) =>
      AssessmentTaskConfig(
        taskId: AssessmentTaskIds.goNogo,
        displayName: 'Go / No-Go',
        taskType: AssessmentTaskType.goNogo,
        estimatedDurationSeconds: 240,
        config: <String, Object?>{
          'trials': trials,
          'practice_trials': 0,
          'isi_min_ms': 20,
          'isi_max_ms': 20,
          'response_window_ms': responseWindowMs,
        },
      );

  AssessmentTaskConfig digitSpanTask() => const AssessmentTaskConfig(
        taskId: AssessmentTaskIds.digitSpanBackward,
        displayName: '倒序数字广度',
        taskType: AssessmentTaskType.digitSpan,
        estimatedDurationSeconds: 180,
        config: <String, Object?>{
          'lengths': <int>[3],
          'failures_to_stop': 2,
          'display_ms': 100,
          'gap_ms': 20,
          'isi_min_ms': 20,
          'isi_max_ms': 20,
        },
      );

  Future<void> pumpRun(
    WidgetTester tester, {
    required AssessmentTaskConfig task,
    required _FakeSessionService service,
  }) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          assessmentSessionServiceProvider.overrideWithValue(service),
        ],
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: _RunHost(task: task),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> openRun(WidgetTester tester) async {
    await tester.tap(find.byKey(_RunHost.openKey));
    await tester.pumpAndSettle();
  }

  Future<void> startRun(WidgetTester tester) async {
    await tester.tap(find.byKey(assessmentRunStartKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
  }

  testWidgets('说明页显示任务名、指导语与开始按钮，不显示进度', (tester) async {
    final service = _FakeSessionService();
    final task = choiceTask();
    await pumpRun(tester, task: task, service: service);
    await openRun(tester);

    expect(find.text(assessmentTaskName(zh, task)), findsOneWidget);
    expect(find.text('这个图形是圆还是方？'), findsOneWidget);
    expect(find.byKey(assessmentRunStartKey), findsOneWidget);
    expect(find.byKey(assessmentRunProgressKey), findsNothing);
    expect(find.byKey(assessmentRunQuitButtonKey), findsOneWidget);
  });

  testWidgets('二选一任务：作答逐题推进，收满后跳结果页并保存', (tester) async {
    final service = _FakeSessionService();
    await pumpRun(tester, task: choiceTask(), service: service);
    await openRun(tester);
    await startRun(tester);

    expect(find.byKey(assessmentRunOptionKey('circle')), findsOneWidget);
    expect(find.byKey(assessmentRunOptionKey('square')), findsOneWidget);
    expect(find.text(zh.assessmentRunProgress(1, 2)), findsOneWidget);

    await tester.tap(find.byKey(assessmentRunOptionKey('circle')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
    expect(find.text(zh.assessmentRunProgress(2, 2)), findsOneWidget);

    await tester.tap(find.byKey(assessmentRunOptionKey('square')));
    await tester.pumpAndSettle();

    expect(find.byType(AssessmentResultPage), findsOneWidget);
    expect(service.completeCalls, 1);
    expect(service.lastTrials, hasLength(2));
    expect(service.lastTrials.first.response['choice'], 'circle');
    expect(service.lastTrials.last.response['choice'], 'square');
  });

  testWidgets('Go / No-Go：点击目标记录按下反应', (tester) async {
    final service = _FakeSessionService();
    await pumpRun(tester, task: goNogoTask(), service: service);
    await openRun(tester);
    await startRun(tester);

    expect(find.byKey(assessmentRunTapTargetKey), findsOneWidget);
    expect(find.text(zh.assessmentRunTapPrompt), findsOneWidget);

    await tester.tap(find.byKey(assessmentRunTapTargetKey));
    await tester.pumpAndSettle();

    expect(find.byType(AssessmentResultPage), findsOneWidget);
    expect(service.lastTrials, hasLength(1));
    expect(service.lastTrials.single.response['pressed'], isTrue);
    expect(service.lastTrials.single.rtMs, isNotNull);
  });

  testWidgets('响应窗口超时：记 0 反应并显示超时提示', (tester) async {
    final service = _FakeSessionService();
    await pumpRun(
      tester,
      task: goNogoTask(trials: 2, responseWindowMs: 100),
      service: service,
    );
    await openRun(tester);
    await startRun(tester);

    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(assessmentRunTimeoutKey), findsOneWidget);
    expect(find.text(zh.assessmentRunTimeout), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 30));
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pumpAndSettle();

    expect(find.byType(AssessmentResultPage), findsOneWidget);
    expect(service.lastTrials, hasLength(2));
    expect(
      service.lastTrials.every((trial) => trial.rtMs == null),
      isTrue,
    );
  });

  testWidgets('倒序数字广度：展示数字、输入倒序并判对', (tester) async {
    final service = _FakeSessionService();
    await pumpRun(tester, task: digitSpanTask(), service: service);
    await openRun(tester);
    await startRun(tester);

    final expectedResponses = <String>[];
    for (var trial = 0; trial < 2; trial++) {
      expect(find.byKey(assessmentRunDigitDisplayKey), findsOneWidget);
      final shown =
          tester.widget<Text>(find.byKey(assessmentRunDigitDisplayKey)).data!;
      final digits = RegExp(r'[0-9]')
          .allMatches(shown)
          .map((match) => match.group(0)!)
          .join();
      final reversed = digits.split('').reversed.join();
      expectedResponses.add(reversed);

      await tester.pump(const Duration(milliseconds: 120));
      expect(find.byKey(assessmentRunDigitInputKey), findsOneWidget);
      expect(find.text(zh.assessmentRunDigitPrompt), findsOneWidget);

      await tester.enterText(find.byKey(assessmentRunDigitInputKey), reversed);
      await tester.tap(find.byKey(assessmentRunDigitSubmitKey));
      await tester.pump();
      if (trial == 0) {
        await tester.pump(const Duration(milliseconds: 30));
      }
    }
    await tester.pumpAndSettle();

    expect(find.byType(AssessmentResultPage), findsOneWidget);
    expect(service.lastTrials, hasLength(2));
    expect(
      [for (final trial in service.lastTrials) trial.response['choice']],
      expectedResponses,
    );
    expect(
      service.lastTrials.every((trial) => trial.correct == true),
      isTrue,
    );
  });

  testWidgets('练习块带徽标，练习记录标记为 isPractice', (tester) async {
    final service = _FakeSessionService();
    await pumpRun(
      tester,
      task: choiceTask(trials: 1, practiceTrials: 1),
      service: service,
    );
    await openRun(tester);
    await startRun(tester);

    expect(find.byKey(assessmentRunPracticeBadgeKey), findsOneWidget);
    expect(find.text(zh.assessmentRunProgress(1, 2)), findsOneWidget);

    await tester.tap(find.byKey(assessmentRunOptionKey('circle')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));

    expect(find.byKey(assessmentRunPracticeBadgeKey), findsNothing);
    expect(find.text(zh.assessmentRunProgress(2, 2)), findsOneWidget);

    await tester.tap(find.byKey(assessmentRunOptionKey('circle')));
    await tester.pumpAndSettle();

    expect(service.lastTrials, hasLength(2));
    expect(service.lastTrials.first.isPractice, isTrue);
    expect(service.lastTrials.last.isPractice, isFalse);
  });

  testWidgets('中途退出需确认，确认后落一条 aborted 会话并返回', (tester) async {
    final service = _FakeSessionService();
    await pumpRun(tester, task: choiceTask(), service: service);
    await openRun(tester);
    await startRun(tester);

    await tester.tap(find.byKey(assessmentRunQuitButtonKey));
    await tester.pumpAndSettle();
    expect(find.text(zh.assessmentRunQuitConfirmTitle), findsOneWidget);
    expect(find.text(zh.assessmentRunQuitConfirmBody), findsOneWidget);

    await tester.tap(find.byKey(assessmentRunQuitCancelKey));
    await tester.pumpAndSettle();
    expect(find.text(zh.assessmentRunQuitConfirmTitle), findsNothing);
    expect(find.byType(AssessmentRunPage), findsOneWidget);

    await tester.tap(find.byKey(assessmentRunQuitButtonKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(assessmentRunQuitConfirmKey));
    await tester.pumpAndSettle();

    expect(find.byType(AssessmentRunPage), findsNothing);
    expect(find.byKey(_RunHost.openKey), findsOneWidget);
    expect(service.incompleteCalls, 1);
    expect(
      service.lastIncompleteStatus,
      AssessmentSessionStatuses.aborted,
    );
  });

  testWidgets('保存失败显示错误与重试，重试成功后跳结果页', (tester) async {
    final service = _FakeSessionService()..failComplete = true;
    await pumpRun(tester, task: choiceTask(trials: 1), service: service);
    await openRun(tester);
    await startRun(tester);

    await tester.tap(find.byKey(assessmentRunOptionKey('circle')));
    await tester.pumpAndSettle();

    expect(find.byKey(assessmentRunSaveRetryKey), findsOneWidget);
    expect(
      find.text(zh.assessmentRunSaveFailed('Bad state: 写库失败')),
      findsWidgets,
    );
    expect(service.completeCalls, 1);
    expect(find.byType(AssessmentResultPage), findsNothing);

    service.failComplete = false;
    await tester.tap(find.byKey(assessmentRunSaveRetryKey));
    await tester.pumpAndSettle();

    expect(find.byType(AssessmentResultPage), findsOneWidget);
    expect(service.completeCalls, 2);
  });

  testWidgets('切后台在声明了该检查的任务上补 background_switch 质量标记', (tester) async {
    final service = _FakeSessionService();
    final task = choiceTask(
      trials: 1,
      qualityChecks: const <String>[QualityFlags.backgroundSwitch],
    );
    await pumpRun(tester, task: task, service: service);
    await openRun(tester);
    await startRun(tester);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    await tester.tap(find.byKey(assessmentRunOptionKey('circle')));
    await tester.pumpAndSettle();

    expect(find.byType(AssessmentResultPage), findsOneWidget);
    expect(service.lastTrials, hasLength(1));
    expect(
        service.lastExtraQualityFlags, contains(QualityFlags.backgroundSwitch));
    expect(find.byType(AssessmentResultPage), findsOneWidget);
    expect(
      find.text(
        assessmentQualityFlagsText(zh, const <String>[
          QualityFlags.backgroundSwitch,
        ]),
      ),
      findsOneWidget,
    );
  });
}

class _RunHost extends StatelessWidget {
  const _RunHost({required this.task});

  static const Key openKey = Key('assessment-run-test-open');

  final AssessmentTaskConfig task;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Builder(
          builder: (context) => FilledButton(
            key: openKey,
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => AssessmentRunPage(task: task),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
  }
}

class _FakeSessionService implements AssessmentSessionService {
  int completeCalls = 0;
  int incompleteCalls = 0;
  List<TrialResult> lastTrials = const <TrialResult>[];
  Set<String> lastExtraQualityFlags = const <String>{};
  String? lastIncompleteStatus;
  bool failComplete = false;

  @override
  Future<AssessmentSessionResult> completeSession({
    required AssessmentTaskConfig task,
    required List<TrialResult> trials,
    required DateTime startedAt,
    required DateTime completedAt,
    required String device,
    Set<String> extraQualityFlags = const <String>{},
  }) async {
    completeCalls += 1;
    lastTrials = List<TrialResult>.unmodifiable(trials);
    lastExtraQualityFlags = Set<String>.unmodifiable(extraQualityFlags);
    if (failComplete) {
      throw StateError('写库失败');
    }
    final flags = <String>[
      for (final flag in QualityFlags.all)
        if (extraQualityFlags.contains(flag)) flag,
    ];
    return AssessmentSessionResult(
      summary: AssessmentSessionSummary(
        sessionId: 'session-1',
        taskId: task.taskId,
        designVersion: task.designVersion,
        device: device,
        startedAt: startedAt,
        completedAt: completedAt,
        status: AssessmentSessionStatuses.completed,
        qualityFlags: flags,
      ),
      metrics: const <MetricSample>[],
      abilities: const <AbilityEstimate>[],
      params: const <ParamEstimate>[],
      qualityFlags: flags,
      measurements: const <AbilityMeasurement>[],
    );
  }

  @override
  Future<AssessmentSessionSummary> recordIncompleteSession({
    required AssessmentTaskConfig task,
    required List<TrialResult> trials,
    required DateTime startedAt,
    required DateTime endedAt,
    required String device,
    String status = AssessmentSessionStatuses.aborted,
  }) async {
    incompleteCalls += 1;
    lastTrials = List<TrialResult>.unmodifiable(trials);
    lastIncompleteStatus = status;
    return AssessmentSessionSummary(
      sessionId: 'session-incomplete',
      taskId: task.taskId,
      designVersion: task.designVersion,
      device: device,
      startedAt: startedAt,
      completedAt: endedAt,
      status: status,
    );
  }
}
