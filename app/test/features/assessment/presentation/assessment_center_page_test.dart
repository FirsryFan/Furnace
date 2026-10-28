import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/features/assessment/application/assessment_providers.dart';
import 'package:furnace/features/assessment/domain/assessment_models.dart';
import 'package:furnace/features/assessment/presentation/assessment_center_page.dart';
import 'package:furnace/features/assessment/presentation/assessment_profile_page.dart';
import 'package:furnace/l10n/app_localizations.dart';

void main() {
  late AppLocalizations zh;

  setUpAll(() async {
    zh = await AppLocalizations.delegate.load(const Locale('zh'));
  });

  AssessmentTaskConfig task(
    String taskId, {
    bool enabled = true,
    bool provisional = false,
    int seconds = 120,
  }) =>
      AssessmentTaskConfig(
        taskId: taskId,
        displayName: '任务 $taskId',
        taskType: AssessmentTaskType.goNogo,
        estimatedDurationSeconds: seconds,
        enabled: enabled,
        provisional: provisional,
      );

  AbilityEstimate ability(
    String abilityId, {
    double mean = 0.1,
    String source = EstimateSources.assessment,
  }) =>
      AbilityEstimate(
        abilityId: abilityId,
        mean: mean,
        uncertainty: 0.5,
        nMeasurements: 2,
        source: source,
      );

  ParamEstimate param(String paramId, {double value = 0.5}) => ParamEstimate(
        paramId: paramId,
        value: value,
        uncertainty: 0.6,
        source: EstimateSources.derived,
      );

  AssessmentSessionSummary session(
    String sessionId, {
    String taskId = 'go_nogo',
    String status = 'completed',
  }) =>
      AssessmentSessionSummary(
        sessionId: sessionId,
        taskId: taskId,
        designVersion: kAssessmentDesignVersion,
        device: AssessmentDevices.windowsMouse,
        startedAt: DateTime(2026, 10, 1, 9),
        completedAt: DateTime(2026, 10, 1, 9, 5),
        status: status,
      );

  AssessmentProfileSnapshot snapshot({
    List<AbilityEstimate> abilities = const [],
    List<ParamEstimate> params = const [],
    List<AssessmentSessionSummary> sessions = const [],
  }) =>
      AssessmentProfileSnapshot(
        abilities: abilities,
        params: params,
        sessions: sessions,
      );

  Future<void> settle(WidgetTester tester, {int rounds = 40}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  Future<void> pumpCenter(
    WidgetTester tester, {
    required Future<List<AssessmentTaskConfig>> Function() loadTasks,
    required AssessmentProfileSnapshot profile,
    required List<AssessmentTaskConfig> started,
    Object? startError,
    bool wait = true,
  }) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          assessmentTasksProvider.overrideWith((ref) => loadTasks()),
          assessmentProfileProvider.overrideWith((ref) async => profile),
          assessmentStartTaskProvider.overrideWithValue((
            context,
            task,
          ) async {
            started.add(task);
            if (startError != null) throw startError;
          }),
        ],
        child: const MaterialApp(
          locale: Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: AssessmentCenterPage(),
        ),
      ),
    );
    if (wait) await settle(tester);
  }

  testWidgets('任务清单只显示启用的任务，并带时长、次数与开始按钮', (tester) async {
    await pumpCenter(
      tester,
      loadTasks: () async => [
        task('go_nogo', seconds: 240),
        task('disabled_task', enabled: false),
        task('decision_fatigue', provisional: true, seconds: 180),
      ],
      profile: snapshot(),
      started: [],
    );

    expect(find.text(zh.assessmentCenterTitle), findsOneWidget);
    expect(find.text(zh.assessmentCenterTasksTitle), findsOneWidget);
    expect(
      find.byKey(assessmentCenterTaskCardKey('go_nogo')),
      findsOneWidget,
    );
    expect(
      find.byKey(assessmentCenterTaskCardKey('disabled_task')),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byKey(assessmentCenterTaskCardKey('go_nogo')),
        matching: find.text(zh.taskGoNogo),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(assessmentCenterTaskCardKey('go_nogo')),
        matching: find.text(zh.assessmentCenterDurationMinutes(4)),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(assessmentCenterTaskCardKey('go_nogo')),
        matching: find.text(zh.assessmentCenterMeasuredCount(0)),
      ),
      findsOneWidget,
    );
    expect(find.text(zh.assessmentCenterProvisional), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(assessmentCenterStartButtonKey('go_nogo')),
        matching: find.text(zh.assessmentCenterStart),
      ),
      findsOneWidget,
    );
  });

  testWidgets('已测任务显示测量次数与「再测一次」', (tester) async {
    await pumpCenter(
      tester,
      loadTasks: () async => [task('go_nogo')],
      profile: snapshot(
        sessions: [
          session('s1'),
          session('s2'),
          session('s3', taskId: 'n_back_2', status: 'incomplete'),
        ],
      ),
      started: [],
    );

    expect(
      find.descendant(
        of: find.byKey(assessmentCenterTaskCardKey('go_nogo')),
        matching: find.text(zh.assessmentCenterMeasuredCount(2)),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(assessmentCenterStartButtonKey('go_nogo')),
        matching: find.text(zh.assessmentCenterRedo),
      ),
      findsOneWidget,
    );
  });

  testWidgets('点开始调用启动器，返回后重读任务与档案', (tester) async {
    final started = <AssessmentTaskConfig>[];
    var taskLoads = 0;
    await pumpCenter(
      tester,
      loadTasks: () async {
        taskLoads++;
        return [task('go_nogo')];
      },
      profile: snapshot(),
      started: started,
    );
    expect(taskLoads, 1);

    await tester.tap(find.byKey(assessmentCenterStartButtonKey('go_nogo')));
    await settle(tester);

    expect(started.single.taskId, 'go_nogo');
    expect(taskLoads, greaterThan(1));
  });

  testWidgets('启动失败时用 SnackBar 报错', (tester) async {
    await pumpCenter(
      tester,
      loadTasks: () async => [task('go_nogo')],
      profile: snapshot(),
      started: [],
      startError: Exception('boom'),
    );

    await tester.tap(find.byKey(assessmentCenterStartButtonKey('go_nogo')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      find.text(zh.assessmentCenterStartFailed('Exception: boom')),
      findsOneWidget,
    );
  });

  testWidgets('档案入口：没有测量时显示先验提示', (tester) async {
    await pumpCenter(
      tester,
      loadTasks: () async => [task('go_nogo')],
      profile: snapshot(),
      started: [],
    );
    expect(
      find.text(zh.assessmentCenterNoMeasurements),
      findsOneWidget,
    );
    expect(
      find.byKey(assessmentCenterNoMeasurementsKey),
      findsOneWidget,
    );
  });

  testWidgets('档案入口：有测量时显示次数', (tester) async {
    await pumpCenter(
      tester,
      loadTasks: () async => [task('go_nogo')],
      profile: snapshot(
        params: [param(CognitiveParamIds.taskDurationEstimate)],
        sessions: [session('s1'), session('s2')],
      ),
      started: [],
    );
    expect(
      find.byKey(assessmentCenterProfileSummaryKey),
      findsOneWidget,
    );
    expect(find.text(zh.assessmentCenterMeasuredCount(2)), findsWidgets);
  });

  testWidgets('点档案入口打开认知档案页', (tester) async {
    await pumpCenter(
      tester,
      loadTasks: () async => [task('go_nogo')],
      profile: snapshot(abilities: [ability(AbilityIds.processingSpeed)]),
      started: [],
    );

    await tester.tap(find.byKey(assessmentCenterProfileEntryKey));
    await settle(tester);

    expect(find.byType(AssessmentProfilePage), findsOneWidget);
  });

  testWidgets('任务列表读取失败显示错误并支持重试', (tester) async {
    var calls = 0;
    await pumpCenter(
      tester,
      loadTasks: () async {
        calls++;
        if (calls == 1) throw Exception('boom');
        return [task('go_nogo')];
      },
      profile: snapshot(),
      started: [],
    );

    expect(
      find.text(zh.assessmentCenterLoadFailed('Exception: boom')),
      findsOneWidget,
    );
    expect(find.byKey(assessmentCenterRetryKey), findsOneWidget);

    await tester.tap(find.byKey(assessmentCenterRetryKey));
    await settle(tester);

    expect(find.byKey(assessmentCenterTasksKey), findsOneWidget);
    expect(find.byKey(assessmentCenterRetryKey), findsNothing);
  });
}
