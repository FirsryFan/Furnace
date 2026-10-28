import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/features/assessment/domain/assessment_mapping.dart';
import 'package:furnace/features/assessment/domain/assessment_models.dart';

TaskAbilityMapping _mapping({
  String taskId = 'choice_reaction',
  String abilityId = AbilityIds.processingSpeed,
  double weight = 1,
  String metricSource = MetricNames.rtMedian,
  bool enabled = true,
  String mappingVersion = kAssessmentMappingVersion,
}) {
  return TaskAbilityMapping(
    taskId: taskId,
    abilityId: abilityId,
    weight: weight,
    metricSource: metricSource,
    enabled: enabled,
    mappingVersion: mappingVersion,
  );
}

MetricSample _sample(
  String name,
  double value, {
  int nTrials = 30,
  List<String> qualityFlags = const <String>[],
}) {
  return MetricSample(
    name: name,
    value: value,
    nTrials: nTrials,
    qualityFlags: qualityFlags,
  );
}

void main() {
  group('mapSessionToAbilityMeasurements 正常映射', () {
    test('单个映射产出测量并标准化', () {
      final result = mapSessionToAbilityMeasurements(
        taskId: 'choice_reaction',
        mappings: <TaskAbilityMapping>[_mapping()],
        metrics: <MetricSample>[_sample(MetricNames.rtMedian, 750)],
      );
      expect(result.measurements, hasLength(1));
      expect(result.skipped, isEmpty);
      final measurement = result.measurements.single;
      expect(measurement.abilityId, AbilityIds.processingSpeed);
      expect(measurement.taskId, 'choice_reaction');
      expect(measurement.metricName, MetricNames.rtMedian);
      expect(measurement.value, 750);
      expect(measurement.zScore, closeTo(-1.0, 1e-9));
      expect(measurement.weight, 1);
      expect(measurement.nTrials, 30);
    });

    test('越高越好的指标方向正确', () {
      final result = mapSessionToAbilityMeasurements(
        taskId: 'choice_reaction',
        mappings: <TaskAbilityMapping>[
          _mapping(metricSource: MetricNames.accuracy),
        ],
        metrics: <MetricSample>[_sample(MetricNames.accuracy, 0.9)],
      );
      expect(result.measurements.single.zScore, closeTo(1.0, 1e-9));
    });

    test('多条映射按输入顺序产出', () {
      final result = mapSessionToAbilityMeasurements(
        taskId: 'choice_reaction',
        mappings: <TaskAbilityMapping>[
          _mapping(abilityId: AbilityIds.inhibitoryControl),
          _mapping(abilityId: AbilityIds.processingSpeed),
        ],
        metrics: <MetricSample>[_sample(MetricNames.rtMedian, 600)],
      );
      expect(
        result.measurements.map((m) => m.abilityId).toList(),
        <String>[AbilityIds.inhibitoryControl, AbilityIds.processingSpeed],
      );
    });

    test('同一指标多个样本时取第一次', () {
      final result = mapSessionToAbilityMeasurements(
        taskId: 'choice_reaction',
        mappings: <TaskAbilityMapping>[_mapping()],
        metrics: <MetricSample>[
          _sample(MetricNames.rtMedian, 600),
          _sample(MetricNames.rtMedian, 1500),
        ],
      );
      expect(result.measurements.single.value, 600);
      expect(result.measurements.single.zScore, 0);
    });

    test('nTrials 负数归零、质量标记透传', () {
      final result = mapSessionToAbilityMeasurements(
        taskId: 'choice_reaction',
        mappings: <TaskAbilityMapping>[_mapping()],
        metrics: <MetricSample>[
          _sample(
            MetricNames.rtMedian,
            600,
            nTrials: -4,
            qualityFlags: const <String>[QualityFlags.tooFast],
          ),
        ],
      );
      final measurement = result.measurements.single;
      expect(measurement.nTrials, 0);
      expect(measurement.qualityFlags, <String>[QualityFlags.tooFast]);
    });

    test('设备、测量时间、映射版本透传', () {
      final measuredAt = DateTime.utc(2026, 4, 4);
      final result = mapSessionToAbilityMeasurements(
        taskId: 'choice_reaction',
        mappings: <TaskAbilityMapping>[_mapping(mappingVersion: '2.0')],
        metrics: <MetricSample>[_sample(MetricNames.rtMedian, 600)],
        device: AssessmentDevices.windowsMouse,
        measuredAt: measuredAt,
      );
      final measurement = result.measurements.single;
      expect(measurement.device, AssessmentDevices.windowsMouse);
      expect(measurement.measuredAt, measuredAt);
      expect(measurement.mappingVersion, '2.0');
      final fallback = mapSessionToAbilityMeasurements(
        taskId: 'choice_reaction',
        mappings: <TaskAbilityMapping>[_mapping(mappingVersion: '  ')],
        metrics: <MetricSample>[_sample(MetricNames.rtMedian, 600)],
      );
      expect(fallback.measurements.single.mappingVersion,
          kAssessmentMappingVersion);
    });
  });

  group('跳过规则', () {
    test('disabled 映射与 taskId 不匹配的映射不产出也不计跳过', () {
      final result = mapSessionToAbilityMeasurements(
        taskId: 'choice_reaction',
        mappings: <TaskAbilityMapping>[
          _mapping(enabled: false),
          _mapping(taskId: 'n_back'),
        ],
        metrics: <MetricSample>[_sample(MetricNames.rtMedian, 600)],
      );
      expect(result.measurements, isEmpty);
      expect(result.skipped, isEmpty);
    });

    test('缺指标计 missing_metric', () {
      final result = mapSessionToAbilityMeasurements(
        taskId: 'choice_reaction',
        mappings: <TaskAbilityMapping>[_mapping()],
        metrics: const <MetricSample>[],
      );
      expect(result.measurements, isEmpty);
      expect(result.skipped.single.reason,
          AbilityMappingSkipReasons.missingMetric);
      expect(result.skipped.single.metricName, MetricNames.rtMedian);
    });

    test('指标没有先验基线计 unknown_metric', () {
      final result = mapSessionToAbilityMeasurements(
        taskId: 'choice_reaction',
        mappings: <TaskAbilityMapping>[_mapping(metricSource: 'custom_metric')],
        metrics: <MetricSample>[_sample('custom_metric', 1)],
      );
      expect(result.skipped.single.reason,
          AbilityMappingSkipReasons.unknownMetric);
    });

    test('权重非正或非有限计 invalid_weight', () {
      final zero = mapSessionToAbilityMeasurements(
        taskId: 'choice_reaction',
        mappings: <TaskAbilityMapping>[_mapping(weight: 0)],
        metrics: <MetricSample>[_sample(MetricNames.rtMedian, 600)],
      );
      expect(
          zero.skipped.single.reason, AbilityMappingSkipReasons.invalidWeight);
      final nan = mapSessionToAbilityMeasurements(
        taskId: 'choice_reaction',
        mappings: <TaskAbilityMapping>[_mapping(weight: double.nan)],
        metrics: <MetricSample>[_sample(MetricNames.rtMedian, 600)],
      );
      expect(
          nan.skipped.single.reason, AbilityMappingSkipReasons.invalidWeight);
    });

    test('能力 id 为空计 missing_ability', () {
      final result = mapSessionToAbilityMeasurements(
        taskId: 'choice_reaction',
        mappings: <TaskAbilityMapping>[_mapping(abilityId: '  ')],
        metrics: <MetricSample>[_sample(MetricNames.rtMedian, 600)],
      );
      expect(result.skipped.single.reason,
          AbilityMappingSkipReasons.missingAbility);
    });

    test('指标值 NaN 计 invalid_value', () {
      final result = mapSessionToAbilityMeasurements(
        taskId: 'choice_reaction',
        mappings: <TaskAbilityMapping>[_mapping()],
        metrics: <MetricSample>[_sample(MetricNames.rtMedian, double.nan)],
      );
      expect(
          result.skipped.single.reason, AbilityMappingSkipReasons.invalidValue);
    });

    test('跳过明细按映射输入顺序', () {
      final result = mapSessionToAbilityMeasurements(
        taskId: 'choice_reaction',
        mappings: <TaskAbilityMapping>[
          _mapping(metricSource: MetricNames.accuracy),
          _mapping(),
        ],
        metrics: <MetricSample>[_sample(MetricNames.rtMedian, 600)],
      );
      expect(result.skipped, hasLength(1));
      expect(result.skipped.single.metricName, MetricNames.accuracy);
      expect(result.measurements, hasLength(1));
    });

    test('空 taskId 直接返回空结果', () {
      expect(
        mapSessionToAbilityMeasurements(
          taskId: '   ',
          mappings: <TaskAbilityMapping>[_mapping()],
          metrics: <MetricSample>[_sample(MetricNames.rtMedian, 600)],
        ).isEmpty,
        isTrue,
      );
    });
  });

  group('abilityMeasurementsForSession 便捷入口', () {
    test('返回测量列表并通过 onSkipped 回报跳过原因', () {
      final skippedReasons = <String>[];
      final measurements = abilityMeasurementsForSession(
        taskId: 'choice_reaction',
        mappings: <TaskAbilityMapping>[
          _mapping(),
          _mapping(
              abilityId: AbilityIds.inhibitoryControl,
              metricSource: MetricNames.dPrime),
        ],
        metrics: <MetricSample>[_sample(MetricNames.rtMedian, 600)],
        onSkipped: (skipped) => skippedReasons.add(skipped.reason),
      );
      expect(measurements, hasLength(1));
      expect(skippedReasons, <String>[AbilityMappingSkipReasons.missingMetric]);
    });

    test('不传 onSkipped 也不抛', () {
      final measurements = abilityMeasurementsForSession(
        taskId: 'choice_reaction',
        mappings: <TaskAbilityMapping>[_mapping()],
        metrics: const <MetricSample>[],
      );
      expect(measurements, isEmpty);
    });

    test('结果列表不可变', () {
      final result = mapSessionToAbilityMeasurements(
        taskId: 'choice_reaction',
        mappings: <TaskAbilityMapping>[_mapping()],
        metrics: <MetricSample>[_sample(MetricNames.rtMedian, 600)],
      );
      expect(
        () => result.measurements.add(result.measurements.single),
        throwsUnsupportedError,
      );
      expect(
          () => result.skipped.add(
                const AbilityMappingSkipped(
                  taskId: 't',
                  abilityId: 'a',
                  metricName: 'm',
                  reason: 'r',
                ),
              ),
          throwsUnsupportedError);
    });
  });
}
