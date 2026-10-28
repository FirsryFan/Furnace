import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/features/assessment/application/task_registry.dart';
import 'package:furnace/features/assessment/domain/assessment_models.dart';

/// 注册表是数据契约：少一条映射、多一个默认开启的任务、weight 写反，
/// 都会在真实会话里静默变成错误的能力读数。这里逐条钉住设计文档 §4.2 /
/// §7.1 / §7.2 的条目。
void main() {
  AssessmentTaskConfig taskOf(String taskId) {
    final task = defaultAssessmentTask(taskId);
    expect(task, isNotNull, reason: '注册表缺少任务 $taskId');
    return task!;
  }

  int intConfig(AssessmentTaskConfig task, String key) {
    final value = task.config[key];
    expect(value, isA<int>(), reason: '${task.taskId}.$key 应为 int');
    return value! as int;
  }

  double doubleConfig(AssessmentTaskConfig task, String key) {
    final value = task.config[key];
    expect(value, isA<num>(), reason: '${task.taskId}.$key 应为数值');
    return (value! as num).toDouble();
  }

  group('AssessmentTaskIds', () {
    test('10 个任务、id 稳定且不重复', () {
      expect(AssessmentTaskIds.all, hasLength(10));
      expect(AssessmentTaskIds.all.toSet(), hasLength(10));
      expect(AssessmentTaskIds.all, <String>[
        'fast_simple_task_i',
        'fast_simple_task_ii',
        'fast_simple_task_iii',
        'go_nogo',
        'digit_span_backward',
        'n_back_2',
        'stroop_crosslang',
        'task_switching',
        'fatigue_block',
        'decision_fatigue',
      ]);
    });

    test('defaultAssessmentTask 去空白后匹配，未知返回 null', () {
      expect(defaultAssessmentTask(' go_nogo ')?.taskId, 'go_nogo');
      expect(defaultAssessmentTask('n_back_2')?.taskType,
          AssessmentTaskType.nBack);
      expect(defaultAssessmentTask('does_not_exist'), isNull);
      expect(defaultAssessmentTask(''), isNull);
    });
  });

  group('kDefaultAssessmentTasks', () {
    test('10 个任务，顺序与 AssessmentTaskIds.all 一致', () {
      expect(kDefaultAssessmentTasks, hasLength(10));
      expect(
        <String>[for (final task in kDefaultAssessmentTasks) task.taskId],
        AssessmentTaskIds.all,
      );
    });

    test('默认开启的只有 8 个：fast_simple_task_iii 与 decision_fatigue 关闭', () {
      final disabled = <String>[
        for (final task in kDefaultAssessmentTasks)
          if (!task.enabled) task.taskId,
      ];
      expect(disabled, <String>[
        AssessmentTaskIds.fastSimpleIii,
        AssessmentTaskIds.decisionFatigue,
      ]);
      expect(
        <String>[
          for (final task in kDefaultAssessmentTasks)
            if (task.provisional) task.taskId,
        ],
        <String>[AssessmentTaskIds.decisionFatigue],
        reason: '§4.3.8：决策疲劳信度未验证，只标 provisional 的暂定任务',
      );
    });

    test('时长按 §4.3 推算值（未标定，但必须是正数并成组）', () {
      final durations = <String, int>{
        for (final task in kDefaultAssessmentTasks)
          task.taskId: task.estimatedDurationSeconds,
      };
      expect(durations, <String, int>{
        AssessmentTaskIds.fastSimpleI: 120,
        AssessmentTaskIds.fastSimpleIi: 120,
        AssessmentTaskIds.fastSimpleIii: 120,
        AssessmentTaskIds.goNogo: 240,
        AssessmentTaskIds.digitSpanBackward: 180,
        AssessmentTaskIds.nBack2: 240,
        AssessmentTaskIds.stroopCrosslang: 210,
        AssessmentTaskIds.taskSwitching: 240,
        AssessmentTaskIds.fatigueBlock: 240,
        AssessmentTaskIds.decisionFatigue: 180,
      });
    });

    test('每个任务都有非空产出指标，且都是已知指标名', () {
      const knownMetrics = <String>{
        MetricNames.rtMedian,
        MetricNames.rtIqr,
        MetricNames.accuracy,
        MetricNames.hitRate,
        MetricNames.falseAlarmRate,
        MetricNames.dPrime,
        MetricNames.rtCost,
        MetricNames.loadSlope,
        MetricNames.stableSpan,
        MetricNames.maxSpan,
        MetricNames.rtSlope,
        MetricNames.varianceDrift,
        MetricNames.switchCost,
        MetricNames.conflictCost,
        MetricNames.decisionDrift,
        MetricNames.repeatRt,
        MetricNames.switchRt,
        MetricNames.congruentRt,
        MetricNames.lapseSlope,
        MetricNames.fishTrialAccuracy,
        MetricNames.defaultChoiceRate,
      };
      for (final task in kDefaultAssessmentTasks) {
        expect(task.producedMetrics, isNotEmpty,
            reason: '${task.taskId} 没有产出指标');
        expect(knownMetrics.containsAll(task.producedMetrics), isTrue,
            reason: '${task.taskId} 出现未知指标 ${task.producedMetrics}');
      }
      expect(taskOf(AssessmentTaskIds.goNogo).producedMetrics, <String>[
        MetricNames.hitRate,
        MetricNames.falseAlarmRate,
        MetricNames.dPrime,
        MetricNames.rtCost,
      ]);
      expect(
        taskOf(AssessmentTaskIds.fatigueBlock).producedMetrics,
        <String>[
          MetricNames.rtSlope,
          MetricNames.varianceDrift,
          MetricNames.lapseSlope,
        ],
      );
    });

    test('质量检查都带通用三项与设备一致性', () {
      for (final task in kDefaultAssessmentTasks) {
        expect(task.qualityChecks, contains(QualityFlags.incomplete));
        expect(task.qualityChecks, contains(QualityFlags.practiceBlock));
        expect(task.qualityChecks, contains(QualityFlags.tooFast));
        expect(task.qualityChecks, contains(QualityFlags.deviceMismatch));
        expect(
          task.qualityChecks.toSet(),
          hasLength(task.qualityChecks.length),
          reason: '${task.taskId} 的质量检查有重复',
        );
      }
    });

    test('config 键值与 §4.3 试次一致', () {
      for (final taskId in <String>[
        AssessmentTaskIds.fastSimpleI,
        AssessmentTaskIds.fastSimpleIi,
        AssessmentTaskIds.fastSimpleIii,
      ]) {
        final task = taskOf(taskId);
        expect(intConfig(task, 'trials'), 30);
        expect(intConfig(task, 'practice_trials'), 8);
        expect(intConfig(task, 'isi_min_ms'), 1000);
        expect(intConfig(task, 'isi_max_ms'), 2500);
        expect(intConfig(task, 'response_window_ms'), 1500);
        expect(task.config['options'], isA<List<String>>());
        expect((task.config['options']! as List<String>), isNotEmpty);
      }
      expect(intConfig(taskOf(AssessmentTaskIds.goNogo), 'trials'), 70);
      expect(
        doubleConfig(taskOf(AssessmentTaskIds.goNogo), 'go_ratio'),
        0.7,
      );
      expect(intConfig(taskOf(AssessmentTaskIds.nBack2), 'trials'), 60);
      expect(intConfig(taskOf(AssessmentTaskIds.nBack2), 'n'), 2);
      expect(
        doubleConfig(taskOf(AssessmentTaskIds.nBack2), 'match_ratio'),
        0.35,
      );
      expect(
          intConfig(taskOf(AssessmentTaskIds.stroopCrosslang), 'trials'), 50);
      expect(
        doubleConfig(taskOf(AssessmentTaskIds.stroopCrosslang), 'fish_ratio'),
        0.25,
      );
      expect(intConfig(taskOf(AssessmentTaskIds.taskSwitching), 'trials'), 70);
      expect(
        doubleConfig(taskOf(AssessmentTaskIds.taskSwitching), 'switch_ratio'),
        0.5,
      );
      final fatigue = taskOf(AssessmentTaskIds.fatigueBlock);
      expect(intConfig(fatigue, 'blocks'), 3);
      expect(intConfig(fatigue, 'block_seconds'), 60);
      expect(intConfig(fatigue, 'trials_per_block'), 30);
      expect(
          intConfig(taskOf(AssessmentTaskIds.decisionFatigue), 'trials'), 75);
    });

    test('digit_span 配置给的是 3..9 阶梯', () {
      final task = taskOf(AssessmentTaskIds.digitSpanBackward);
      expect(intConfig(task, 'start_length'), 3);
      expect(task.config['lengths'], <int>[3, 4, 5, 6, 7, 8, 9]);
      expect(intConfig(task, 'failures_to_stop'), 2);
    });

    test('config 里的键都在文档契约内，类型可序列化', () {
      const allowedKeys = <String>{
        'trials',
        'practice_trials',
        'blocks',
        'isi_min_ms',
        'isi_max_ms',
        'response_window_ms',
        'options',
        'go_ratio',
        'n',
        'match_ratio',
        'congruent_ratio',
        'conflict_ratio',
        'fish_ratio',
        'switch_ratio',
        'start_length',
        'lengths',
        'failures_to_stop',
        'display_ms',
        'gap_ms',
        'block_seconds',
        'trials_per_block',
      };
      for (final task in kDefaultAssessmentTasks) {
        expect(allowedKeys.containsAll(task.config.keys), isTrue,
            reason: '${task.taskId} 出现未约定的 config 键');
        for (final value in task.config.values) {
          expect(
            value is int ||
                value is double ||
                value is String ||
                value is bool ||
                value is List,
            isTrue,
            reason: '${task.taskId} 的 config 值不可序列化：$value',
          );
        }
      }
    });
  });

  group('kDefaultTaskAbilityMappings（§7.1）', () {
    test('13 条：9 条默认启用 + 4 条可选关闭', () {
      expect(kDefaultTaskAbilityMappings, hasLength(13));
      final enabled = kDefaultTaskAbilityMappings
          .where((mapping) => mapping.enabled)
          .toList();
      expect(enabled, hasLength(9));
      expect(
        <String>[for (final mapping in enabled) mapping.taskId],
        containsAll(<String>[
          AssessmentTaskIds.fastSimpleI,
          AssessmentTaskIds.fastSimpleIi,
          AssessmentTaskIds.goNogo,
          AssessmentTaskIds.digitSpanBackward,
          AssessmentTaskIds.nBack2,
          AssessmentTaskIds.stroopCrosslang,
          AssessmentTaskIds.taskSwitching,
          AssessmentTaskIds.fatigueBlock,
        ]),
      );
      final disabled = kDefaultTaskAbilityMappings
          .where((mapping) => !mapping.enabled)
          .toList();
      expect(
        <String>[for (final mapping in disabled) mapping.taskId],
        <String>[
          AssessmentTaskIds.fastSimpleIii,
          AssessmentTaskIds.stroopCrosslang,
          AssessmentTaskIds.stroopCrosslang,
          AssessmentTaskIds.decisionFatigue,
        ],
      );
    });

    test('每条映射的 taskId / ability / metricSource 都合法', () {
      for (final mapping in kDefaultTaskAbilityMappings) {
        expect(AssessmentTaskIds.all, contains(mapping.taskId));
        expect(AbilityIds.all, contains(mapping.abilityId));
        expect(mapping.metricSource.trim(), isNotEmpty);
        expect(mapping.weight, greaterThan(0));
        expect(mapping.weight, lessThanOrEqualTo(1));
        expect(mapping.mappingVersion, kAssessmentMappingVersion);
      }
    });

    test('默认映射权重：stroop 0.7 / 可选 processing 0.3 / 跨语言 0.2', () {
      TaskAbilityMapping find(String taskId, String abilityId) =>
          kDefaultTaskAbilityMappings.firstWhere(
            (mapping) =>
                mapping.taskId == taskId && mapping.abilityId == abilityId,
            orElse: () => throw StateError('缺少映射 $taskId -> $abilityId'),
          );
      expect(
        find(AssessmentTaskIds.stroopCrosslang,
                AbilityIds.distractionResistance)
            .weight,
        0.7,
      );
      expect(
        find(AssessmentTaskIds.stroopCrosslang, AbilityIds.processingSpeed)
            .weight,
        0.3,
      );
      expect(
        find(AssessmentTaskIds.stroopCrosslang, AbilityIds.crossLanguageCost)
            .weight,
        0.2,
      );
      expect(
        find(AssessmentTaskIds.stroopCrosslang, AbilityIds.crossLanguageCost)
            .enabled,
        isFalse,
      );
    });

    test('指标来源与任务主指标一致', () {
      TaskAbilityMapping find(String taskId, String abilityId) =>
          kDefaultTaskAbilityMappings.firstWhere(
            (mapping) =>
                mapping.taskId == taskId && mapping.abilityId == abilityId,
          );
      expect(
        find(AssessmentTaskIds.fastSimpleI, AbilityIds.processingSpeed)
            .metricSource,
        MetricNames.rtMedian,
      );
      expect(
        find(AssessmentTaskIds.goNogo, AbilityIds.inhibitoryControl)
            .metricSource,
        MetricNames.dPrime,
      );
      expect(
        find(AssessmentTaskIds.digitSpanBackward,
                AbilityIds.workingMemoryCapacity)
            .metricSource,
        MetricNames.stableSpan,
      );
      expect(
        find(
          AssessmentTaskIds.fatigueBlock,
          AbilityIds.stabilityDrift,
        ).metricSource,
        MetricNames.varianceDrift,
      );
    });

    test('按能力聚合的默认权重和（能力值 = 该能力下所有启用任务加权）', () {
      final weightByAbility = <String, double>{};
      for (final mapping in kDefaultTaskAbilityMappings) {
        if (!mapping.enabled) continue;
        weightByAbility[mapping.abilityId] =
            (weightByAbility[mapping.abilityId] ?? 0) + mapping.weight;
      }
      expect(weightByAbility[AbilityIds.processingSpeed], 2.0);
      expect(weightByAbility[AbilityIds.inhibitoryControl], 1.0);
      expect(weightByAbility[AbilityIds.workingMemoryCapacity], 1.0);
      expect(weightByAbility[AbilityIds.workingMemoryUpdateSpeed], 1.0);
      expect(weightByAbility[AbilityIds.distractionResistance], 0.7);
      expect(weightByAbility[AbilityIds.switchCostAbility], 1.0);
      expect(weightByAbility[AbilityIds.fatigueSlope], 1.0);
      expect(weightByAbility[AbilityIds.stabilityDrift], 1.0);
      expect(weightByAbility[AbilityIds.decisionFatigue], isNull,
          reason: '决策疲劳任务默认关闭，不应有启用映射');
      expect(weightByAbility[AbilityIds.crossLanguageCost], isNull);
    });
  });

  group('kDefaultAbilityParamMappings（§7.2）', () {
    test('13 条、能力与参数都在已知表内、无重复 pair', () {
      expect(kDefaultAbilityParamMappings, hasLength(13));
      final pairs = <String>{};
      for (final mapping in kDefaultAbilityParamMappings) {
        expect(AbilityIds.all, contains(mapping.abilityId));
        expect(CognitiveParamIds.all, contains(mapping.paramId));
        expect(mapping.weight, greaterThan(0));
        expect(mapping.weight, lessThanOrEqualTo(1));
        expect(mapping.mappingVersion, kAssessmentMappingVersion);
        expect(
          mapping.direction,
          anyOf(MappingDirection.positive, MappingDirection.negative),
        );
        expect(
          pairs.add('${mapping.abilityId}|${mapping.paramId}'),
          isTrue,
          reason: '重复映射 ${mapping.abilityId} -> ${mapping.paramId}',
        );
      }
    });

    test('方向语义：上限类参数用 negative，惩罚/偏置类用 positive', () {
      AbilityParamMapping find(String abilityId, String paramId) =>
          kDefaultAbilityParamMappings.firstWhere(
            (mapping) =>
                mapping.abilityId == abilityId && mapping.paramId == paramId,
          );
      expect(
        find(
          AbilityIds.inhibitoryControl,
          CognitiveParamIds.interruptionCost,
        ).direction,
        MappingDirection.negative,
      );
      expect(
        find(
          AbilityIds.switchCostAbility,
          CognitiveParamIds.switchPenalty,
        ).direction,
        MappingDirection.negative,
      );
      expect(
        find(
          AbilityIds.workingMemoryCapacity,
          CognitiveParamIds.highLoadDiscount,
        ).direction,
        MappingDirection.negative,
      );
      expect(
        find(
          AbilityIds.fatigueSlope,
          CognitiveParamIds.similarFatiguePenalty,
        ).direction,
        MappingDirection.positive,
      );
      expect(
        find(
          AbilityIds.stabilityDrift,
          CognitiveParamIds.expectedPressure,
        ).direction,
        MappingDirection.positive,
      );
      expect(
        find(
          AbilityIds.decisionFatigue,
          CognitiveParamIds.timeOfDayBias,
        ).direction,
        MappingDirection.positive,
      );
    });

    test('关键权重照 §7.2', () {
      double weightOf(String abilityId, String paramId) =>
          kDefaultAbilityParamMappings
              .firstWhere(
                (mapping) =>
                    mapping.abilityId == abilityId &&
                    mapping.paramId == paramId,
              )
              .weight;
      expect(
        weightOf(
          AbilityIds.processingSpeed,
          CognitiveParamIds.taskDurationEstimate,
        ),
        0.7,
      );
      expect(
        weightOf(
          AbilityIds.inhibitoryControl,
          CognitiveParamIds.interruptionCost,
        ),
        0.6,
      );
      expect(
        weightOf(
          AbilityIds.inhibitoryControl,
          CognitiveParamIds.switchPenalty,
        ),
        0.4,
      );
      expect(
        weightOf(
          AbilityIds.distractionResistance,
          CognitiveParamIds.interruptionCost,
        ),
        0.4,
      );
      expect(
        weightOf(
          AbilityIds.workingMemoryCapacity,
          CognitiveParamIds.highLoadDiscount,
        ),
        0.6,
      );
      expect(
        weightOf(
          AbilityIds.fatigueSlope,
          CognitiveParamIds.scheduleIntensityCap,
        ),
        0.6,
      );
      expect(
        weightOf(
          AbilityIds.decisionFatigue,
          CognitiveParamIds.timeOfDayBias,
        ),
        0.8,
      );
    });
  });
}
