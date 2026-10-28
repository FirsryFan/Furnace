import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/features/assessment/domain/assessment_models.dart';
import 'package:furnace/features/assessment/presentation/assessment_display.dart';
import 'package:furnace/l10n/app_localizations.dart';

void main() {
  late AppLocalizations zh;
  late AppLocalizations en;

  setUpAll(() async {
    zh = await AppLocalizations.delegate.load(const Locale('zh'));
    en = await AppLocalizations.delegate.load(const Locale('en'));
  });

  AssessmentTaskConfig taskConfig(
    String taskId, {
    String displayName = '',
    AssessmentTaskType type = AssessmentTaskType.choiceReaction,
    int estimatedDurationSeconds = 120,
  }) {
    return AssessmentTaskConfig(
      taskId: taskId,
      displayName: displayName,
      taskType: type,
      estimatedDurationSeconds: estimatedDurationSeconds,
    );
  }

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
      nMeasurements: 1,
      source: source,
      stale: stale,
    );
  }

  ParamEstimate param(
    String paramId,
    double value, {
    String source = EstimateSources.derived,
  }) {
    return ParamEstimate(
      paramId: paramId,
      value: value,
      uncertainty: 0.3,
      source: source,
    );
  }

  AssessmentSessionSummary session(
    String sessionId, {
    String taskId = 'go_nogo',
    String status = 'completed',
    DateTime? startedAt,
  }) {
    final start = startedAt ?? DateTime(2026, 10, 27, 9);
    return AssessmentSessionSummary(
      sessionId: sessionId,
      taskId: taskId,
      designVersion: kAssessmentDesignVersion,
      device: AssessmentDevices.windowsMouse,
      startedAt: start,
      completedAt:
          status == 'completed' ? start.add(const Duration(minutes: 3)) : null,
      status: status,
    );
  }

  group('任务名', () {
    test('按 taskId 映射到本地化任务名', () {
      expect(
        assessmentTaskName(zh, taskConfig('fast_simple_task_i')),
        zh.taskFastSimpleTaskI,
      );
      expect(
        assessmentTaskName(zh, taskConfig('fast_simple_task_ii')),
        zh.taskFastSimpleTaskIi,
      );
      expect(
        assessmentTaskName(zh, taskConfig('fast_simple_task_iii')),
        zh.taskFastSimpleTaskIii,
      );
      expect(assessmentTaskName(zh, taskConfig('go_nogo')), zh.taskGoNogo);
      expect(
        assessmentTaskName(zh, taskConfig('digit_span_backward')),
        zh.taskDigitSpanBackward,
      );
      expect(assessmentTaskName(zh, taskConfig('n_back_2')), zh.taskNBack2);
      expect(
        assessmentTaskName(zh, taskConfig('stroop_crosslang')),
        zh.taskStroopCrosslang,
      );
      expect(
        assessmentTaskName(zh, taskConfig('task_switching')),
        zh.taskSwitching,
      );
      expect(
        assessmentTaskName(zh, taskConfig('fatigue_block')),
        zh.taskFatigueBlock,
      );
      expect(
        assessmentTaskName(zh, taskConfig('decision_fatigue')),
        zh.taskDecisionFatigue,
      );
    });

    test('未知 id 优先回显 displayName，空则回显 id', () {
      expect(
        assessmentTaskName(
          zh,
          taskConfig('custom_task', displayName: '我的自建任务'),
        ),
        '我的自建任务',
      );
      expect(
        assessmentTaskName(zh, taskConfig('custom_task')),
        'custom_task',
      );
    });

    test('任务类型可兜底，但 choice_reaction 不猜名字', () {
      expect(
        assessmentTaskName(
          zh,
          taskConfig('renamed_nback', type: AssessmentTaskType.nBack),
        ),
        zh.taskNBack2,
      );
      expect(
        assessmentTaskName(
          zh,
          taskConfig('renamed_choice', type: AssessmentTaskType.choiceReaction),
        ),
        'renamed_choice',
      );
    });

    test('只有 taskId 时走 id 映射，未知 id 原样回显', () {
      expect(assessmentTaskNameById(zh, 'stroop_crosslang'),
          zh.taskStroopCrosslang);
      expect(assessmentTaskNameById(zh, 'practice_block'), 'practice_block');
    });

    test('英文界面使用英文任务名', () {
      expect(
        assessmentTaskNameById(en, 'go_nogo'),
        en.taskGoNogo,
      );
      expect(en.taskGoNogo, isNot(zh.taskGoNogo));
    });
  });

  group('能力 / 参数 / 指标名', () {
    test('十个能力 id 全部映射到本地化文案', () {
      expect(assessmentAbilityName(zh, AbilityIds.processingSpeed),
          zh.abilityProcessingSpeed);
      expect(assessmentAbilityName(zh, AbilityIds.inhibitoryControl),
          zh.abilityInhibitoryControl);
      expect(
        assessmentAbilityName(zh, AbilityIds.workingMemoryCapacity),
        zh.abilityWorkingMemoryCapacity,
      );
      expect(
        assessmentAbilityName(zh, AbilityIds.workingMemoryUpdateSpeed),
        zh.abilityWorkingMemoryUpdateSpeed,
      );
      expect(
        assessmentAbilityName(zh, AbilityIds.distractionResistance),
        zh.abilityDistractionResistance,
      );
      expect(
        assessmentAbilityName(zh, AbilityIds.switchCostAbility),
        zh.abilitySwitchCostAbility,
      );
      expect(assessmentAbilityName(zh, AbilityIds.fatigueSlope),
          zh.abilityFatigueSlope);
      expect(assessmentAbilityName(zh, AbilityIds.stabilityDrift),
          zh.abilityStabilityDrift);
      expect(assessmentAbilityName(zh, AbilityIds.decisionFatigue),
          zh.abilityDecisionFatigue);
      expect(
        assessmentAbilityName(zh, AbilityIds.crossLanguageCost),
        zh.abilityCrossLanguageCost,
      );
    });

    test('九个参数 id 全部映射到本地化文案', () {
      expect(
        assessmentParamName(zh, CognitiveParamIds.taskDurationEstimate),
        zh.paramTaskDurationEstimate,
      );
      expect(
        assessmentParamName(zh, CognitiveParamIds.chunkingThreshold),
        zh.paramChunkingThreshold,
      );
      expect(
        assessmentParamName(zh, CognitiveParamIds.interruptionCost),
        zh.paramInterruptionCost,
      );
      expect(
        assessmentParamName(zh, CognitiveParamIds.switchPenalty),
        zh.paramSwitchPenalty,
      );
      expect(
        assessmentParamName(zh, CognitiveParamIds.highLoadDiscount),
        zh.paramHighLoadDiscount,
      );
      expect(
        assessmentParamName(zh, CognitiveParamIds.similarFatiguePenalty),
        zh.paramSimilarFatiguePenalty,
      );
      expect(
        assessmentParamName(zh, CognitiveParamIds.scheduleIntensityCap),
        zh.paramScheduleIntensityCap,
      );
      expect(
        assessmentParamName(zh, CognitiveParamIds.expectedPressure),
        zh.paramExpectedPressure,
      );
      expect(
        assessmentParamName(zh, CognitiveParamIds.timeOfDayBias),
        zh.paramTimeOfDayBias,
      );
    });

    test('指标名映射，未知名字原样回显', () {
      expect(assessmentMetricName(zh, MetricNames.rtMedian), zh.metricRtMedian);
      expect(assessmentMetricName(zh, MetricNames.accuracy), zh.metricAccuracy);
      expect(assessmentMetricName(zh, MetricNames.dPrime), zh.metricDPrime);
      expect(
        assessmentMetricName(zh, MetricNames.defaultChoiceRate),
        zh.metricDefaultChoiceRate,
      );
      expect(assessmentMetricName(zh, 'max_span'), 'max_span');
    });

    test('未知能力 / 参数 id 原样回显', () {
      expect(assessmentAbilityName(zh, 'future_ability'), 'future_ability');
      expect(assessmentParamName(zh, 'future_param'), 'future_param');
    });
  });

  group('数值格式化', () {
    test('比例类指标用百分比，保留一位小数', () {
      expect(assessmentMetricValueText(MetricNames.accuracy, 0.856), '85.6%');
      expect(assessmentMetricValueText(MetricNames.hitRate, 1.0), '100.0%');
      expect(assessmentMetricValueText(MetricNames.falseAlarmRate, 0.0333),
          '3.3%');
      expect(
        assessmentMetricValueText(MetricNames.fishTrialAccuracy, 0.5),
        '50.0%',
      );
      expect(
        assessmentMetricValueText(MetricNames.defaultChoiceRate, 0.125),
        '12.5%',
      );
    });

    test('反应时类指标用毫秒整数', () {
      expect(assessmentMetricValueText(MetricNames.rtMedian, 512.6), '513 ms');
      expect(assessmentMetricValueText(MetricNames.rtIqr, 88.4), '88 ms');
      expect(assessmentMetricValueText(MetricNames.rtCost, 42.0), '42 ms');
      expect(assessmentMetricValueText(MetricNames.repeatRt, 600.2), '600 ms');
      expect(assessmentMetricValueText(MetricNames.switchRt, 731.5), '732 ms');
      expect(
          assessmentMetricValueText(MetricNames.congruentRt, 498.0), '498 ms');
    });

    test('跨度类保留一位小数，其余保留两位', () {
      expect(assessmentMetricValueText(MetricNames.stableSpan, 3.26), '3.3');
      expect(assessmentMetricValueText(MetricNames.maxSpan, 5.0), '5.0');
      expect(assessmentMetricValueText(MetricNames.dPrime, 1.234), '1.23');
      expect(assessmentMetricValueText('unknown_metric', 0.5), '0.50');
    });

    test('估计值统一两位小数', () {
      expect(assessmentEstimateValueText(0), '0.00');
      expect(assessmentEstimateValueText(1.5), '1.50');
      expect(assessmentEstimateValueText(-0.333), '-0.33');
    });
  });

  group('时长与时间', () {
    test('预计时长换算成分钟，不足一分钟按一分钟', () {
      expect(assessmentTaskDurationMinutes(0), 1);
      expect(assessmentTaskDurationMinutes(-30), 1);
      expect(assessmentTaskDurationMinutes(30), 1);
      expect(assessmentTaskDurationMinutes(90), 2);
      expect(assessmentTaskDurationMinutes(600), 10);
    });

    test('用时时长格式 mm:ss，超过一小时带小时位', () {
      expect(assessmentDurationText(Duration.zero), '00:00');
      expect(assessmentDurationText(const Duration(seconds: 65)), '01:05');
      expect(assessmentDurationText(const Duration(minutes: 10)), '10:00');
      expect(assessmentDurationText(const Duration(hours: 1, seconds: 65)),
          '1:01:05');
      expect(assessmentDurationText(const Duration(seconds: -3)), '00:00');
    });

    test('历史时间用本地 yyyy-MM-dd HH:mm', () {
      expect(
        assessmentHistoryTimeText(DateTime(2026, 10, 27, 9, 5)),
        '2026-10-27 09:05',
      );
      expect(
        assessmentHistoryTimeText(DateTime(2026, 1, 2, 0, 0)),
        '2026-01-02 00:00',
      );
    });
  });

  group('来源与质量标记', () {
    test('来源徽标映射，未知来源原样回显', () {
      expect(
        assessmentSourceLabel(zh, EstimateSources.defaultPrior),
        zh.assessmentProfileSourceDefault,
      );
      expect(
        assessmentSourceLabel(zh, EstimateSources.assessment),
        zh.assessmentProfileSourceAssessment,
      );
      expect(
        assessmentSourceLabel(zh, EstimateSources.derived),
        zh.assessmentProfileSourceDerived,
      );
      expect(
        assessmentSourceLabel(zh, EstimateSources.userOverride),
        zh.assessmentProfileSourceOverride,
      );
      expect(assessmentSourceLabel(zh, 'legacy_v0'), 'legacy_v0');
    });

    test('质量标记空列表显示「无」，否则用分隔符连接原始编码', () {
      expect(assessmentQualityFlagsText(zh, const []),
          zh.assessmentResultQualityNone);
      expect(
        assessmentQualityFlagsText(zh, const ['too_fast', 'high_lapse']),
        'too_fast · high_lapse',
      );
    });
  });

  group('聚合', () {
    test('按任务统计已完成会话数，默认排除未完成', () {
      final sessions = [
        session('s1', taskId: 'go_nogo'),
        session('s2', taskId: 'go_nogo'),
        session('s3', taskId: 'go_nogo', status: 'aborted'),
        session('s4', taskId: 'n_back_2'),
        session('s5', taskId: 'n_back_2', status: 'incomplete'),
      ];
      expect(assessmentSessionCountsByTaskId(sessions), {
        'go_nogo': 2,
        'n_back_2': 1,
      });
      expect(assessmentSessionCountsByTaskId(sessions, completedOnly: false), {
        'go_nogo': 3,
        'n_back_2': 2,
      });
    });

    test('能力按稳定顺序排列，未知 id 排末尾', () {
      final sorted = assessmentSortedAbilities([
        ability(AbilityIds.decisionFatigue, 0.2),
        ability('future_ability', 0.9),
        ability(AbilityIds.processingSpeed, 0.1),
      ]);
      expect(sorted.map((item) => item.abilityId).toList(), [
        AbilityIds.processingSpeed,
        AbilityIds.decisionFatigue,
        'future_ability',
      ]);
    });

    test('参数按稳定顺序排列，未知 id 排末尾', () {
      final sorted = assessmentSortedParams([
        param(CognitiveParamIds.timeOfDayBias, 0.4),
        param('future_param', 0.5),
        param(CognitiveParamIds.taskDurationEstimate, 0.6),
      ]);
      expect(sorted.map((item) => item.paramId).toList(), [
        CognitiveParamIds.taskDurationEstimate,
        CognitiveParamIds.timeOfDayBias,
        'future_param',
      ]);
    });
  });
}
