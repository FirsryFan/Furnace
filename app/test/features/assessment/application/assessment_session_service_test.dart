// 评测会话服务的编排测试：用内存 store 替掉 Drift，验证
// 指标 → 质量标记 → 能力合并 → 参数推导这一整条链（设计文档 v1.0 §7/§8/§9）。
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/features/assessment/application/assessment_engine.dart';
import 'package:furnace/features/assessment/application/assessment_session_service.dart';
import 'package:furnace/features/assessment/application/task_registry.dart';
import 'package:furnace/features/assessment/domain/assessment_models.dart';

void main() {
  const startedAt = '2026-10-29T09:00:00';

  AssessmentTaskConfig taskById(String taskId) =>
      kDefaultAssessmentTasks.firstWhere((task) => task.taskId == taskId);

  /// 用引擎把一张任务「全部答对、每 trial 固定 RT」跑完，返回全部 trial。
  List<TrialResult> runPerfect({
    required AssessmentTaskConfig task,
    int rtMs = 400,
  }) {
    final start = DateTime.parse(startedAt);
    final engine = AssessmentRunEngine(task: task, seed: 7, startedAt: start);
    while (!engine.isFinished) {
      final shown = start.add(Duration(milliseconds: rtMs * engine.trialIndex));
      engine.markShown(shown);
      final expected = engine.trials[engine.trialIndex].expectedResponse;
      engine.submit(
        response: expected,
        at: shown.add(Duration(milliseconds: rtMs)),
      );
    }
    return engine.recorded;
  }

  group('computeSessionMetrics', () {
    test('go_nogo 全对时产出 4 个指标且 d′ 很高', () {
      final task = taskById(AssessmentTaskIds.goNogo);
      final trials = runPerfect(task: task);
      final metrics = computeSessionMetrics(task: task, trials: trials);
      final names = metrics.map((m) => m.name).toList();
      expect(names, containsAll(task.producedMetrics));
      final dPrime =
          metrics.firstWhere((m) => m.name == MetricNames.dPrime).value;
      expect(dPrime, greaterThan(2));
      final hit =
          metrics.firstWhere((m) => m.name == MetricNames.hitRate).value;
      expect(hit, 1.0);
    });

    test('stroop 一致/冲突 RT 相同时冲突代价为 0，钓鱼正确率 1', () {
      final task = taskById(AssessmentTaskIds.stroopCrosslang);
      final trials = runPerfect(task: task);
      final metrics = computeSessionMetrics(task: task, trials: trials);
      final conflict =
          metrics.firstWhere((m) => m.name == MetricNames.conflictCost).value;
      expect(conflict, 0.0);
      final fish = metrics
          .firstWhere((m) => m.name == MetricNames.fishTrialAccuracy)
          .value;
      expect(fish, 1.0);
    });

    test('task_switching 的切换/重复 RT 都产出', () {
      final task = taskById(AssessmentTaskIds.taskSwitching);
      final trials = runPerfect(task: task);
      final metrics = computeSessionMetrics(task: task, trials: trials);
      final names = metrics.map((m) => m.name).toList();
      expect(names, containsAll(task.producedMetrics));
    });

    test('digit_span 全对时稳定跨度与最高跨度都是 9', () {
      final task = taskById(AssessmentTaskIds.digitSpanBackward);
      final trials = runPerfect(task: task);
      final metrics = computeSessionMetrics(task: task, trials: trials);
      final stable =
          metrics.firstWhere((m) => m.name == MetricNames.stableSpan).value;
      final max =
          metrics.firstWhere((m) => m.name == MetricNames.maxSpan).value;
      expect(stable, 9.0);
      expect(max, 9.0);
    });
  });

  group('evaluateQualityFlags', () {
    test('不满 20 个有效 trial 标 low_trial_count', () {
      const task = AssessmentTaskConfig(
        taskId: 'short_task',
        displayName: '短任务',
        taskType: AssessmentTaskType.choiceReaction,
        estimatedDurationSeconds: 30,
        producedMetrics: <String>[MetricNames.rtMedian],
        qualityChecks: <String>[QualityFlags.lowTrialCount],
      );
      final start = DateTime.parse(startedAt);
      final trials = <TrialResult>[
        for (var index = 0; index < 5; index++)
          TrialResult(
            trialIndex: index,
            blockIndex: 0,
            stimulus: const <String, Object?>{
              'options': <String>['a', 'b']
            },
            response: const <String, Object?>{'choice': 'a'},
            rtMs: 400,
            correct: true,
            isPractice: false,
            timestamp: start.add(Duration(milliseconds: 400 * index)),
          ),
      ];
      final metrics = computeSessionMetrics(task: task, trials: trials);
      final flags = evaluateQualityFlags(
        task: task,
        trials: trials,
        metricSamples: metrics,
        status: AssessmentSessionStatuses.completed,
        device: AssessmentDevices.windowsMouse,
      );
      expect(flags, contains(QualityFlags.lowTrialCount));
    });

    test('反应太快标 too_fast，换设备标 device_mismatch', () {
      final task = taskById(AssessmentTaskIds.fastSimpleI);
      final trials = runPerfect(task: task, rtMs: 50);
      final metrics = computeSessionMetrics(task: task, trials: trials);
      final flags = evaluateQualityFlags(
        task: task,
        trials: trials,
        metricSamples: metrics,
        status: AssessmentSessionStatuses.completed,
        device: AssessmentDevices.androidTouch,
        previousDevice: AssessmentDevices.windowsMouse,
      );
      expect(flags, contains(QualityFlags.tooFast));
      expect(flags, contains(QualityFlags.deviceMismatch));
    });

    test('没完成时标 incomplete', () {
      final task = taskById(AssessmentTaskIds.fastSimpleI);
      final trials = runPerfect(task: task);
      final metrics = computeSessionMetrics(task: task, trials: trials);
      final flags = evaluateQualityFlags(
        task: task,
        trials: trials,
        metricSamples: metrics,
        status: AssessmentSessionStatuses.incomplete,
        device: AssessmentDevices.windowsMouse,
      );
      expect(flags, contains(QualityFlags.incomplete));
    });
  });

  group('AssessmentSessionService.completeSession', () {
    test('第一次测评写入能力测量并降低不确定性，参数被推导', () async {
      final store = _FakeStore();
      final service = AssessmentSessionService(store: store);
      final task = taskById(AssessmentTaskIds.goNogo);
      final trials = runPerfect(task: task);
      final start = DateTime.parse(startedAt);
      final result = await service.completeSession(
        task: task,
        trials: trials,
        startedAt: start,
        completedAt: start.add(const Duration(minutes: 4)),
        device: AssessmentDevices.windowsMouse,
      );
      expect(result.measurements, isNotEmpty);
      expect(result.abilities.length, AbilityIds.all.length);
      final inhibitory = result.abilities.firstWhere(
        (ability) => ability.abilityId == AbilityIds.inhibitoryControl,
      );
      expect(inhibitory.nMeasurements, 1);
      expect(inhibitory.source, EstimateSources.assessment);
      // 首次测量按 1/sqrt(n+1)=1/sqrt(2)≈0.707；最低 0.15。
      expect(inhibitory.uncertainty, closeTo(0.7071, 0.001));
      expect(result.params.length, CognitiveParamIds.all.length);
      final interruption = result.params.firstWhere(
        (param) => param.paramId == CognitiveParamIds.interruptionCost,
      );
      expect(interruption.source, EstimateSources.derived);
      expect(store.sessions, hasLength(1));
      expect(store.metrics, isNotEmpty);
    });

    test('第二次测评合并后测量数变 2', () async {
      final store = _FakeStore();
      final service = AssessmentSessionService(store: store);
      final task = taskById(AssessmentTaskIds.goNogo);
      final start = DateTime.parse(startedAt);
      for (var round = 0; round < 2; round++) {
        await service.completeSession(
          task: task,
          trials: runPerfect(task: task),
          startedAt: start.add(Duration(hours: round)),
          completedAt: start.add(Duration(hours: round, minutes: 4)),
          device: AssessmentDevices.windowsMouse,
        );
      }
      final inhibitory = store.abilities.values.firstWhere(
        (ability) => ability.abilityId == AbilityIds.inhibitoryControl,
      );
      expect(inhibitory.nMeasurements, 2);
      expect(inhibitory.uncertainty, lessThan(0.6));
    });
    test('调用方补充的 background_switch 进会话标记并上调不确定性', () async {
      final store = _FakeStore();
      final service = AssessmentSessionService(store: store);
      final task = taskById(AssessmentTaskIds.goNogo);
      final start = DateTime.parse(startedAt);
      final result = await service.completeSession(
        task: task,
        trials: runPerfect(task: task),
        startedAt: start,
        completedAt: start.add(const Duration(minutes: 4)),
        device: AssessmentDevices.windowsMouse,
        extraQualityFlags: const <String>{
          QualityFlags.backgroundSwitch,
          'bogus_flag',
        },
      );
      expect(result.qualityFlags, contains(QualityFlags.backgroundSwitch));
      expect(result.qualityFlags, isNot(contains('bogus_flag')));
      expect(store.sessions.single.qualityFlags,
          contains(QualityFlags.backgroundSwitch));
      expect(
        store.metrics.every(
          (metric) =>
              metric.qualityFlags.contains(QualityFlags.backgroundSwitch),
        ),
        isTrue,
      );
      final inhibitory = result.abilities.firstWhere(
        (ability) => ability.abilityId == AbilityIds.inhibitoryControl,
      );
      // 1/sqrt(2)≈0.7071，再加一个已知质量标记 0.1。
      expect(inhibitory.uncertainty, closeTo(0.8071, 0.001));
    });

    test('user_override 的能力不再被自动覆盖', () async {
      final store = _FakeStore();
      final service = AssessmentSessionService(store: store);
      store.abilities['processing_speed'] = const AbilityEstimate(
        abilityId: 'processing_speed',
        mean: 2.5,
        uncertainty: 0.3,
        nMeasurements: 1,
        source: EstimateSources.userOverride,
      );
      final task = taskById(AssessmentTaskIds.fastSimpleI);
      final start = DateTime.parse(startedAt);
      await service.completeSession(
        task: task,
        trials: runPerfect(task: task),
        startedAt: start,
        completedAt: start.add(const Duration(minutes: 2)),
        device: AssessmentDevices.windowsMouse,
      );
      final speed = store.abilities['processing_speed']!;
      expect(speed.source, EstimateSources.userOverride);
      expect(speed.mean, 2.5);
    });

    test('中途退出只落会话，不写能力估计', () async {
      final store = _FakeStore();
      final service = AssessmentSessionService(store: store);
      final task = taskById(AssessmentTaskIds.goNogo);
      final start = DateTime.parse(startedAt);
      final summary = await service.recordIncompleteSession(
        task: task,
        trials: runPerfect(task: task),
        startedAt: start,
        endedAt: start.add(const Duration(minutes: 1)),
        device: AssessmentDevices.windowsMouse,
      );
      expect(summary.status, AssessmentSessionStatuses.aborted);
      expect(store.sessions, hasLength(1));
      expect(store.abilities, isEmpty);
      expect(store.params, isEmpty);
    });
  });
}

/// 内存版 AssessmentStore：只实现服务用到的行为，不碰数据库。
class _FakeStore implements AssessmentStore {
  final Map<String, AbilityEstimate> abilities = <String, AbilityEstimate>{};
  final Map<String, ParamEstimate> params = <String, ParamEstimate>{};
  final List<AssessmentSessionSummary> sessions = <AssessmentSessionSummary>[];
  final List<MetricSample> metrics = <MetricSample>[];
  int _nextId = 0;

  @override
  Future<void> ensureSeeded({DateTime? now}) async {}

  @override
  Future<List<AssessmentTaskConfig>> listTasks(
          {bool enabledOnly = true}) async =>
      kDefaultAssessmentTasks
          .where((task) => !enabledOnly || task.enabled)
          .toList(growable: false);

  @override
  Future<String> recordSession({
    required String taskId,
    required String designVersion,
    required String device,
    required DateTime startedAt,
    required DateTime completedAt,
    required String status,
    required List<TrialResult> trials,
    required List<MetricSample> metrics,
    List<String> qualityFlags = const <String>[],
  }) async {
    _nextId += 1;
    final sessionId = 'session-$_nextId';
    this.metrics.addAll(metrics);
    sessions.insert(
      0,
      AssessmentSessionSummary(
        sessionId: sessionId,
        taskId: taskId,
        designVersion: designVersion,
        device: device,
        startedAt: startedAt,
        completedAt: completedAt,
        status: status,
        qualityFlags: qualityFlags,
        metrics: metrics,
      ),
    );
    return sessionId;
  }

  /// 和真实仓储一致：没测过的项返回系统默认值，而不是缺席。
  @override
  Future<List<AbilityEstimate>> readAbilities() async => <AbilityEstimate>[
        for (final spec in kAbilitySpecs)
          abilities[spec.id] ??
              AbilityEstimate(
                abilityId: spec.id,
                mean: spec.defaultMean,
                uncertainty: spec.defaultUncertainty,
                nMeasurements: 0,
                source: EstimateSources.defaultPrior,
              ),
      ];

  @override
  Future<List<ParamEstimate>> readCognitiveParams() async => <ParamEstimate>[
        for (final spec in kCognitiveParamSpecs)
          params[spec.id] ??
              ParamEstimate(
                paramId: spec.id,
                value: spec.defaultValue,
                uncertainty: spec.defaultUncertainty,
                source: EstimateSources.defaultPrior,
              ),
      ];

  @override
  Future<void> writeEstimates({
    List<AbilityEstimate> abilities = const <AbilityEstimate>[],
    List<ParamEstimate> params = const <ParamEstimate>[],
  }) async {
    for (final ability in abilities) {
      if (this.abilities[ability.abilityId]?.isUserOverride == true) continue;
      this.abilities[ability.abilityId] = ability;
    }
    for (final param in params) {
      if (this.params[param.paramId]?.isUserOverride == true) continue;
      this.params[param.paramId] = param;
    }
  }

  @override
  Future<List<TaskAbilityMapping>> readTaskAbilityMappings({
    bool enabledOnly = true,
  }) async =>
      kDefaultTaskAbilityMappings
          .where((mapping) => !enabledOnly || mapping.enabled)
          .toList(growable: false);

  @override
  Future<List<AbilityParamMapping>> readAbilityParamMappings({
    bool enabledOnly = true,
  }) async =>
      kDefaultAbilityParamMappings
          .where((mapping) => !enabledOnly || mapping.enabled)
          .toList(growable: false);

  @override
  Future<List<AssessmentSessionSummary>> readSessions({int limit = 20}) async =>
      sessions.take(limit).toList(growable: false);

  @override
  Future<AssessmentSessionSummary?> readSession(String sessionId) async {
    for (final session in sessions) {
      if (session.sessionId == sessionId) return session;
    }
    return null;
  }

  @override
  Future<void> setAbilityUserOverride({
    required String abilityId,
    required double mean,
  }) async {}

  @override
  Future<void> setParamUserOverride({
    required String paramId,
    required double value,
  }) async {}

  @override
  Future<void> clearAbilityUserOverride({required String abilityId}) async {}

  @override
  Future<void> clearParamUserOverride({required String paramId}) async {}
}
