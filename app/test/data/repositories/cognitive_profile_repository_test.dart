import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/cognitive_profile_repository.dart';
import 'package:furnace/features/assessment/application/assessment_session_service.dart';
import 'package:furnace/features/assessment/application/task_registry.dart';
import 'package:furnace/features/assessment/domain/assessment_models.dart';

/// 评测板块仓储（schema v41 的八张 `cog_*` 表）的持久化口径。
///
/// 契约里最容易写错、也最容易被后续改动破坏的几条：
///
///  * `ensureSeeded` 幂等：重复调用不重复插任务/映射，也不把默认估计变成
///    「测过一次」；
///  * 没测过的能力/参数也返回 10 + 9 行（画像页要有东西画），source=default；
///  * `writeEstimates` **不覆盖** user_override 行；
///  * 用户覆盖会夹到量纲范围内（能力 z-score -5..5、参数 0..1），清除覆盖
///    只改 source、保留数值与 n；
///  * 会话的 trials/metrics/quality_flags 都能按 sessionId 读回。
void main() {
  late AppDatabase db;
  late CognitiveProfileRepository repo;
  final moment = DateTime(2026, 10, 29, 1, 45);

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = CognitiveProfileRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('seed 幂等，且没测过也有 10 项能力 + 9 个参数（source=default）', () async {
    await repo.ensureSeeded(now: moment);
    await repo.ensureSeeded(now: moment);

    final tasks = await repo.listTasks(enabledOnly: false);
    expect(tasks.length, kDefaultAssessmentTasks.length);
    expect(
      (await repo.listTasks()).length,
      kDefaultAssessmentTasks.where((task) => task.enabled).length,
    );
    expect(
      (await repo.readTaskAbilityMappings(enabledOnly: false)).length,
      kDefaultTaskAbilityMappings.length,
    );
    expect(
      (await repo.readAbilityParamMappings(enabledOnly: false)).length,
      kDefaultAbilityParamMappings.length,
    );

    final abilities = await repo.readAbilities();
    expect(abilities.length, kAbilitySpecs.length);
    for (final ability in abilities) {
      final spec = kAbilitySpecs.firstWhere((s) => s.id == ability.abilityId);
      expect(ability.source, EstimateSources.defaultPrior);
      expect(ability.nMeasurements, 0);
      expect(ability.mean, spec.defaultMean);
      expect(ability.uncertainty, spec.defaultUncertainty);
    }

    final params = await repo.readCognitiveParams();
    expect(params.length, kCognitiveParamSpecs.length);
    for (final param in params) {
      final spec =
          kCognitiveParamSpecs.firstWhere((s) => s.id == param.paramId);
      expect(param.source, EstimateSources.defaultPrior);
      expect(param.value, spec.defaultValue);
      expect(param.uncertainty, spec.defaultUncertainty);
    }
  });

  test('会话的 trials / metrics / quality_flags 能读回，列表按时间倒序', () async {
    await repo.ensureSeeded(now: moment);
    final taskId = kDefaultAssessmentTasks.first.taskId;

    final first = await repo.recordSession(
      taskId: taskId,
      designVersion: kAssessmentDesignVersion,
      device: AssessmentDevices.windowsMouse,
      startedAt: moment,
      completedAt: moment.add(const Duration(minutes: 2)),
      status: AssessmentSessionStatuses.completed,
      trials: const <TrialResult>[
        TrialResult(trialIndex: 0, blockIndex: 0, rtMs: 410, correct: true),
        TrialResult(trialIndex: 1, blockIndex: 0, rtMs: 390, correct: false),
        TrialResult(
          trialIndex: 2,
          blockIndex: 0,
          rtMs: 200,
          correct: true,
          isPractice: true,
        ),
      ],
      metrics: const <MetricSample>[
        MetricSample(name: MetricNames.rtMedian, value: 410, nTrials: 2),
        MetricSample(
          name: MetricNames.accuracy,
          value: 0.5,
          nTrials: 2,
          qualityFlags: <String>[QualityFlags.lowTrialCount],
        ),
      ],
      qualityFlags: const <String>[
        QualityFlags.lowTrialCount,
        QualityFlags.highLapse,
      ],
    );
    final second = await repo.recordSession(
      taskId: taskId,
      designVersion: kAssessmentDesignVersion,
      device: AssessmentDevices.windowsMouse,
      startedAt: moment.add(const Duration(hours: 1)),
      completedAt: moment.add(const Duration(hours: 1, minutes: 1)),
      status: AssessmentSessionStatuses.aborted,
      trials: const <TrialResult>[],
      metrics: const <MetricSample>[],
    );

    final session = await repo.readSession(first);
    expect(session, isNotNull);
    expect(session!.device, AssessmentDevices.windowsMouse);
    expect(session.status, AssessmentSessionStatuses.completed);
    expect(session.qualityFlags,
        <String>[QualityFlags.lowTrialCount, QualityFlags.highLapse]);
    expect(session.metrics.length, 2);
    expect(session.metrics.first.value, 410);
    expect(session.metrics.last.qualityFlags,
        <String>[QualityFlags.lowTrialCount]);

    final sessions = await repo.readSessions(limit: 20);
    expect(sessions.length, 2);
    expect(sessions.first.sessionId, second, reason: '开始时间新的排前面');
    expect(sessions.first.status, AssessmentSessionStatuses.aborted);
    expect(await repo.readSessions(limit: 0), isEmpty);
    expect(await repo.readSession('cog-missing'), isNull);
  });

  test('writeEstimates 存下来源/贡献/设备/stale，读回不丢', () async {
    await repo.ensureSeeded(now: moment);

    await repo.writeEstimates(
      abilities: const <AbilityEstimate>[
        AbilityEstimate(
          abilityId: AbilityIds.processingSpeed,
          mean: 0.6,
          uncertainty: 0.3,
          nMeasurements: 2,
          source: EstimateSources.assessment,
          device: AssessmentDevices.windowsMouse,
          contributions: <AbilityContribution>[
            AbilityContribution(
              taskId: 'fast_simple_task_i',
              weight: 1,
              metric: MetricNames.rtMedian,
            ),
          ],
        ),
        AbilityEstimate(
          abilityId: AbilityIds.inhibitoryControl,
          mean: 0.2,
          uncertainty: 0.5,
          nMeasurements: 1,
          source: EstimateSources.assessment,
          stale: true,
        ),
      ],
      params: const <ParamEstimate>[
        ParamEstimate(
          paramId: CognitiveParamIds.taskDurationEstimate,
          value: 0.42,
          uncertainty: 0.4,
          source: EstimateSources.derived,
          derivedFrom: <ParamSourceWeight>[
            ParamSourceWeight(
                abilityId: AbilityIds.processingSpeed, weight: .7),
          ],
        ),
      ],
    );

    final abilities = await repo.readAbilities();
    final processing =
        abilities.firstWhere((a) => a.abilityId == AbilityIds.processingSpeed);
    expect(processing.mean, .6);
    expect(processing.uncertainty, .3);
    expect(processing.nMeasurements, 2);
    expect(processing.source, EstimateSources.assessment);
    expect(processing.device, AssessmentDevices.windowsMouse);
    expect(processing.contributions.single.taskId, 'fast_simple_task_i');
    expect(processing.contributions.single.metric, MetricNames.rtMedian);
    expect(
      abilities
          .firstWhere((a) => a.abilityId == AbilityIds.inhibitoryControl)
          .stale,
      isTrue,
    );

    final params = await repo.readCognitiveParams();
    final duration = params.firstWhere(
      (p) => p.paramId == CognitiveParamIds.taskDurationEstimate,
    );
    expect(duration.value, .42);
    expect(duration.source, EstimateSources.derived);
    expect(duration.derivedFrom.single.abilityId, AbilityIds.processingSpeed);
  });

  test('用户覆盖：夹到量纲内、停止自动合并、清除后保留数值只改来源', () async {
    await repo.ensureSeeded(now: moment);
    await repo.writeEstimates(
      abilities: const <AbilityEstimate>[
        AbilityEstimate(
          abilityId: AbilityIds.processingSpeed,
          mean: 0.4,
          uncertainty: 0.3,
          nMeasurements: 2,
          source: EstimateSources.assessment,
        ),
      ],
    );

    await repo.setAbilityUserOverride(
      abilityId: AbilityIds.processingSpeed,
      mean: 9,
    );
    var ability = (await repo.readAbilities())
        .firstWhere((a) => a.abilityId == AbilityIds.processingSpeed);
    expect(ability.mean, 5, reason: 'z-score 量纲上限 5');
    expect(ability.source, EstimateSources.userOverride);
    expect(ability.nMeasurements, 2, reason: '覆盖不动测量次数');
    expect(ability.uncertainty, .3, reason: '覆盖不动不确定性');
    expect(ability.isUserOverride, isTrue);

    // 覆盖之后再来一次自动合并：不能把用户输入冲掉。
    await repo.writeEstimates(
      abilities: const <AbilityEstimate>[
        AbilityEstimate(
          abilityId: AbilityIds.processingSpeed,
          mean: -1,
          uncertainty: .2,
          nMeasurements: 3,
          source: EstimateSources.assessment,
        ),
      ],
    );
    ability = (await repo.readAbilities())
        .firstWhere((a) => a.abilityId == AbilityIds.processingSpeed);
    expect(ability.mean, 5);
    expect(ability.nMeasurements, 2);

    await repo.clearAbilityUserOverride(
      abilityId: AbilityIds.processingSpeed,
    );
    ability = (await repo.readAbilities())
        .firstWhere((a) => a.abilityId == AbilityIds.processingSpeed);
    expect(ability.source, EstimateSources.assessment,
        reason: '有测量记录 → 回到测量来源');
    expect(ability.mean, 5, reason: '清除覆盖不丢用户看到过的数值');

    // 从没测过的能力被覆盖后清除：回到默认来源。
    await repo.setAbilityUserOverride(
      abilityId: AbilityIds.workingMemoryCapacity,
      mean: -2,
    );
    await repo.clearAbilityUserOverride(
      abilityId: AbilityIds.workingMemoryCapacity,
    );
    final defaulted = (await repo.readAbilities())
        .firstWhere((a) => a.abilityId == AbilityIds.workingMemoryCapacity);
    expect(defaulted.source, EstimateSources.defaultPrior);
    expect(defaulted.nMeasurements, 0);
  });

  test('参数覆盖：0..1 夹取、清除后回到 derived / default', () async {
    await repo.ensureSeeded(now: moment);
    await repo.writeEstimates(
      params: const <ParamEstimate>[
        ParamEstimate(
          paramId: CognitiveParamIds.similarFatiguePenalty,
          value: .3,
          uncertainty: .4,
          source: EstimateSources.derived,
          derivedFrom: <ParamSourceWeight>[
            ParamSourceWeight(abilityId: AbilityIds.fatigueSlope, weight: .7),
          ],
        ),
      ],
    );

    await repo.setParamUserOverride(
      paramId: CognitiveParamIds.similarFatiguePenalty,
      value: 1.4,
    );
    var param = (await repo.readCognitiveParams()).firstWhere(
      (p) => p.paramId == CognitiveParamIds.similarFatiguePenalty,
    );
    expect(param.value, 1, reason: '参数是 0..1 的模型内变量');
    expect(param.source, EstimateSources.userOverride);

    await repo.writeEstimates(
      params: const <ParamEstimate>[
        ParamEstimate(
          paramId: CognitiveParamIds.similarFatiguePenalty,
          value: .9,
          uncertainty: .2,
          source: EstimateSources.derived,
        ),
      ],
    );
    param = (await repo.readCognitiveParams()).firstWhere(
      (p) => p.paramId == CognitiveParamIds.similarFatiguePenalty,
    );
    expect(param.value, 1);

    await repo.clearParamUserOverride(
      paramId: CognitiveParamIds.similarFatiguePenalty,
    );
    param = (await repo.readCognitiveParams()).firstWhere(
      (p) => p.paramId == CognitiveParamIds.similarFatiguePenalty,
    );
    expect(param.source, EstimateSources.derived);
    expect(param.value, 1);

    // 从没写过 derivedFrom 的参数，清除覆盖后回到默认来源。
    await repo.setParamUserOverride(
      paramId: CognitiveParamIds.expectedPressure,
      value: 0,
    );
    await repo.clearParamUserOverride(
      paramId: CognitiveParamIds.expectedPressure,
    );
    final defaulted = (await repo.readCognitiveParams()).firstWhere(
      (p) => p.paramId == CognitiveParamIds.expectedPressure,
    );
    expect(defaulted.source, EstimateSources.defaultPrior);
  });
}
