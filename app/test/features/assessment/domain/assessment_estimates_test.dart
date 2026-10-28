import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/features/assessment/domain/assessment_estimates.dart';
import 'package:furnace/features/assessment/domain/assessment_models.dart';

AbilityEstimate _ability(
  String abilityId, {
  double mean = 0,
  double uncertainty = 0.5,
  int nMeasurements = 1,
  String source = EstimateSources.defaultPrior,
  bool stale = false,
  String designVersion = kAssessmentDesignVersion,
  String mappingVersion = kAssessmentMappingVersion,
  List<AbilityContribution> contributions = const <AbilityContribution>[],
  Map<String, Object?> personalBaseline = const <String, Object?>{},
}) {
  return AbilityEstimate(
    abilityId: abilityId,
    mean: mean,
    uncertainty: uncertainty,
    nMeasurements: nMeasurements,
    source: source,
    stale: stale,
    designVersion: designVersion,
    mappingVersion: mappingVersion,
    contributions: contributions,
    personalBaseline: personalBaseline,
  );
}

AbilityMeasurement _measurement({
  String abilityId = AbilityIds.processingSpeed,
  String taskId = 'choice_reaction',
  String metricName = MetricNames.rtMedian,
  double value = 600,
  double zScore = 0,
  double weight = 1,
  int nMeasurements = 1,
  double uncertainty = kAbilityMeasurementBaseUncertainty,
  List<String> qualityFlags = const <String>[],
  DateTime? measuredAt,
}) {
  return AbilityMeasurement(
    abilityId: abilityId,
    taskId: taskId,
    metricName: metricName,
    value: value,
    zScore: zScore,
    weight: weight,
    nMeasurements: nMeasurements,
    uncertainty: uncertainty,
    qualityFlags: qualityFlags,
    measuredAt: measuredAt,
  );
}

void main() {
  group('加权中位数', () {
    test('空输入返回 null', () {
      expect(weightedMedian(const <WeightedValue>[]), isNull);
    });

    test('全部权重非法时返回 null', () {
      expect(
        weightedMedian(const <WeightedValue>[
          WeightedValue(value: 1, weight: 0),
          WeightedValue(value: 2, weight: -1),
          WeightedValue(value: 3, weight: double.nan),
        ]),
        isNull,
      );
    });

    test('单值直接返回', () {
      expect(
        weightedMedian(
            const <WeightedValue>[WeightedValue(value: 5, weight: 1)]),
        5,
      );
    });

    test('等权两项取较小时的累计过半规则', () {
      expect(
        weightedMedian(const <WeightedValue>[
          WeightedValue(value: 1, weight: 1),
          WeightedValue(value: 2, weight: 1),
        ]),
        1.0,
      );
    });

    test('权重大的一侧胜出', () {
      expect(
        weightedMedian(const <WeightedValue>[
          WeightedValue(value: 1, weight: 1),
          WeightedValue(value: 2, weight: 2),
        ]),
        2.0,
      );
    });

    test('非有限值被忽略', () {
      expect(
        weightedMedian(const <WeightedValue>[
          WeightedValue(value: double.nan, weight: 100),
          WeightedValue(value: double.infinity, weight: 100),
          WeightedValue(value: 7, weight: 1),
        ]),
        7,
      );
    });

    test('负数与乱序输入按值升序累计', () {
      expect(
        weightedMedian(const <WeightedValue>[
          WeightedValue(value: 10, weight: 1),
          WeightedValue(value: -10, weight: 1),
          WeightedValue(value: 0, weight: 1),
        ]),
        0.0,
      );
    });
  });

  group('standardizeMetric', () {
    test('基线值标准化为 0', () {
      expect(standardizeMetric(MetricNames.rtMedian, 600), 0.0);
      expect(standardizeMetric(MetricNames.accuracy, 0.75), 0.0);
    });

    test('越低越好的指标方向取反', () {
      expect(standardizeMetric(MetricNames.rtMedian, 450), closeTo(1.0, 1e-9));
      expect(standardizeMetric(MetricNames.rtMedian, 750), closeTo(-1.0, 1e-9));
    });

    test('越高越好的指标方向不变', () {
      expect(standardizeMetric(MetricNames.accuracy, 0.9), closeTo(1.0, 1e-9));
      expect(standardizeMetric(MetricNames.dPrime, 2.8), closeTo(1.0, 1e-9));
    });

    test('极端值夹在 ±kMetricZLimit', () {
      expect(standardizeMetric(MetricNames.rtMedian, 0), kMetricZLimit);
      expect(standardizeMetric(MetricNames.rtMedian, 2000), -kMetricZLimit);
    });

    test('未知指标与非有限输入返回 null', () {
      expect(standardizeMetric('not_a_metric', 1), isNull);
      expect(standardizeMetric(MetricNames.accuracy, double.nan), isNull);
      expect(standardizeMetric(MetricNames.accuracy, double.infinity), isNull);
    });

    test('指标名两侧空白被忽略', () {
      expect(standardizeMetric('  accuracy  ', 0.75), 0.0);
    });
  });

  group('AbilityMeasurement 校验与质量标记', () {
    test('合法测量 isValid 为真', () {
      expect(_measurement().isValid, isTrue);
    });

    test('权重非正、z 值非有限、能力 id 为空都判无效', () {
      expect(_measurement(weight: 0).isValid, isFalse);
      expect(_measurement(weight: -1).isValid, isFalse);
      expect(_measurement(zScore: double.nan).isValid, isFalse);
      expect(_measurement(abilityId: '  ').isValid, isFalse);
    });

    test('每个已知质量标记 +0.1', () {
      final measurement = _measurement(qualityFlags: const <String>[
        'too_fast',
        'low_trial_count',
      ]);
      expect(measurement.uncertaintyWithQualityFlags, closeTo(0.7, 1e-9));
    });

    test('重复与未知质量标记只算一次/忽略', () {
      final duplicated = _measurement(qualityFlags: const <String>[
        'too_fast',
        ' too_fast ',
        'bogus_flag',
      ]);
      expect(duplicated.uncertaintyWithQualityFlags, closeTo(0.6, 1e-9));
    });

    test('多项标记后夹到 1.0', () {
      final measurement = _measurement(uncertainty: 0.95, qualityFlags: const [
        'too_fast',
        'too_slow',
      ]);
      expect(measurement.uncertaintyWithQualityFlags, 1.0);
    });
  });

  group('mergeAbilityEstimate 合并规则', () {
    test('无旧估计时新建估计', () {
      final merged = mergeAbilityEstimate(
        current: null,
        measurement: _measurement(zScore: 1.5),
      );
      expect(merged, isNotNull);
      expect(merged!.mean, 1.5);
      expect(merged.nMeasurements, 1);
      expect(merged.uncertainty, closeTo(1 / 1.414213562, 1e-6));
      expect(merged.source, EstimateSources.assessment);
      expect(merged.contributions, hasLength(1));
      expect(merged.contributions.single.taskId, 'choice_reaction');
      expect(merged.contributions.single.metric, MetricNames.rtMedian);
    });
    test('质量标记把新估计的不确定性也上调（每个 +0.1）', () {
      final merged = mergeAbilityEstimate(
        current: null,
        measurement: _measurement(
          zScore: 1.5,
          qualityFlags: const <String>['too_fast'],
        ),
      );
      expect(merged, isNotNull);
      expect(merged!.uncertainty, closeTo(1 / 1.414213562 + 0.1, 1e-6));
    });

    test('user_override 旧估计不覆盖（原样返回同一对象）', () {
      final current = _ability(
        AbilityIds.processingSpeed,
        mean: 3,
        source: EstimateSources.userOverride,
      );
      final merged = mergeAbilityEstimate(
        current: current,
        measurement: _measurement(zScore: -2),
      );
      expect(identical(merged, current), isTrue);
    });

    test('无效测量返回旧估计', () {
      final current = _ability(AbilityIds.processingSpeed, mean: 1);
      final merged = mergeAbilityEstimate(
        current: current,
        measurement: _measurement(weight: 0),
      );
      expect(identical(merged, current), isTrue);
    });

    test('能力 id 不一致时不合并', () {
      final current = _ability(AbilityIds.inhibitoryControl, mean: 1);
      final merged = mergeAbilityEstimate(
        current: current,
        measurement: _measurement(abilityId: AbilityIds.processingSpeed),
      );
      expect(identical(merged, current), isTrue);
    });

    test('stale 旧估计被新测量替换', () {
      final current = _ability(
        AbilityIds.processingSpeed,
        mean: 2,
        nMeasurements: 5,
        stale: true,
      );
      final merged = mergeAbilityEstimate(
        current: current,
        measurement: _measurement(zScore: 0.5),
      );
      expect(merged!.mean, 0.5);
      expect(merged.nMeasurements, 1);
    });

    test('设计/映射版本不一致时被替换', () {
      final oldDesign = _ability(
        AbilityIds.processingSpeed,
        mean: 2,
        designVersion: '0.9',
      );
      final merged = mergeAbilityEstimate(
        current: oldDesign,
        measurement: _measurement(zScore: 0.25),
      );
      expect(merged!.mean, 0.25);
      final oldMapping = _ability(
        AbilityIds.processingSpeed,
        mean: 2,
        mappingVersion: '0.9',
      );
      final mergedMapping = mergeAbilityEstimate(
        current: oldMapping,
        measurement: _measurement(zScore: 0.75),
      );
      expect(mergedMapping!.mean, 0.75);
    });

    test('按 (1-u)*n 加权后取中位数', () {
      final current = _ability(
        AbilityIds.processingSpeed,
        mean: 2,
        uncertainty: 0.5,
        nMeasurements: 1,
      );
      final merged = mergeAbilityEstimate(
        current: current,
        measurement: _measurement(zScore: 0),
      );
      expect(merged!.mean, 0.0);
      expect(merged.nMeasurements, 2);
      expect(merged.uncertainty, closeTo(1 / 1.732050808, 1e-6));
    });

    test('质量标记提高新测量不确定性、改变合并权重', () {
      final current = _ability(
        AbilityIds.processingSpeed,
        mean: 2,
        uncertainty: 0.5,
        nMeasurements: 1,
      );
      final merged = mergeAbilityEstimate(
        current: current,
        measurement: _measurement(zScore: 0, qualityFlags: const ['too_fast']),
      );
      expect(merged!.mean, 2.0);
    });

    test('nMeasurements 累加', () {
      final current = _ability(
        AbilityIds.processingSpeed,
        mean: 0,
        uncertainty: 0.5,
        nMeasurements: 3,
      );
      final merged = mergeAbilityEstimate(
        current: current,
        measurement: _measurement(zScore: 1, nMeasurements: 2),
      );
      expect(merged!.nMeasurements, 5);
      expect(merged.uncertainty, closeTo(1 / 2.449489743, 1e-6));
    });

    test('贡献按 taskId + metric 去重并更新权重', () {
      final current = _ability(
        AbilityIds.processingSpeed,
        mean: 1,
        contributions: const <AbilityContribution>[
          AbilityContribution(
              taskId: 'choice_reaction', weight: 0.3, metric: 'rt_median'),
          AbilityContribution(taskId: 'n_back', weight: 1, metric: 'accuracy'),
        ],
      );
      final merged = mergeAbilityEstimate(
        current: current,
        measurement: _measurement(zScore: 0.8, weight: 2),
      );
      expect(merged!.contributions, hasLength(2));
      final reaction = merged.contributions
          .where((c) => c.taskId == 'choice_reaction')
          .single;
      expect(reaction.weight, 2);
    });

    test('保留个人基线与旧更新时间', () {
      final current = AbilityEstimate(
        abilityId: AbilityIds.processingSpeed,
        mean: 1,
        uncertainty: 0.5,
        nMeasurements: 1,
        source: EstimateSources.defaultPrior,
        personalBaseline: const <String, Object?>{'rt_median': 580},
        updatedAt: DateTime.utc(2026, 1, 1),
      );
      final merged = mergeAbilityEstimate(
        current: current,
        measurement: _measurement(zScore: 0.2),
      );
      expect(merged!.personalBaseline['rt_median'], 580);
      expect(merged.updatedAt, DateTime.utc(2026, 1, 1));
    });

    test('测量时间优先于旧更新时间，source 可注入', () {
      final measuredAt = DateTime.utc(2026, 2, 2);
      final merged = mergeAbilityEstimate(
        current: _ability(AbilityIds.processingSpeed, mean: 0),
        measurement: _measurement(zScore: 0.3, measuredAt: measuredAt),
        source: EstimateSources.derived,
      );
      expect(merged!.updatedAt, measuredAt);
      expect(merged.source, EstimateSources.derived);
    });
  });

  group('deriveParams', () {
    test('没有能力或映射时返回空列表', () {
      expect(
        deriveParams(abilities: const [], mappings: const []),
        isEmpty,
      );
    });

    test('disabled 映射与缺失能力的映射被忽略', () {
      final abilities = <AbilityEstimate>[_ability(AbilityIds.processingSpeed)];
      final mappings = <AbilityParamMapping>[
        const AbilityParamMapping(
          abilityId: AbilityIds.processingSpeed,
          paramId: CognitiveParamIds.taskDurationEstimate,
          weight: 1,
          direction: MappingDirection.positive,
          enabled: false,
        ),
        const AbilityParamMapping(
          abilityId: 'unknown_ability',
          paramId: CognitiveParamIds.chunkingThreshold,
          weight: 1,
          direction: MappingDirection.positive,
        ),
      ];
      expect(
        deriveParams(abilities: abilities, mappings: mappings),
        isEmpty,
      );
    });

    test('positive 映射：z=1 得到 value=0.75', () {
      final abilities = <AbilityEstimate>[
        _ability(AbilityIds.processingSpeed, mean: 1, uncertainty: 0.5),
      ];
      final mappings = <AbilityParamMapping>[
        const AbilityParamMapping(
          abilityId: AbilityIds.processingSpeed,
          paramId: CognitiveParamIds.taskDurationEstimate,
          weight: 1,
          direction: MappingDirection.positive,
        ),
      ];
      final params = deriveParams(abilities: abilities, mappings: mappings);
      expect(params, hasLength(1));
      final param = params.single;
      expect(param.paramId, CognitiveParamIds.taskDurationEstimate);
      expect(param.value, closeTo(0.75, 1e-9));
      expect(param.uncertainty, closeTo(0.5, 1e-9));
      expect(param.source, EstimateSources.derived);
      expect(param.derivedFrom.single.abilityId, AbilityIds.processingSpeed);
      expect(param.derivedFrom.single.weight, 1);
    });

    test('negative 映射方向取反', () {
      final abilities = <AbilityEstimate>[
        _ability(AbilityIds.inhibitoryControl, mean: 1, uncertainty: 0.6),
      ];
      final mappings = <AbilityParamMapping>[
        const AbilityParamMapping(
          abilityId: AbilityIds.inhibitoryControl,
          paramId: CognitiveParamIds.interruptionCost,
          weight: 2,
          direction: MappingDirection.negative,
        ),
      ];
      final params = deriveParams(abilities: abilities, mappings: mappings);
      expect(params.single.value, closeTo(0.25, 1e-9));
      expect(params.single.uncertainty, closeTo(0.6, 1e-9));
    });

    test('未知方向按 positive 处理', () {
      final abilities = <AbilityEstimate>[
        _ability(AbilityIds.processingSpeed, mean: 1)
      ];
      final mappings = <AbilityParamMapping>[
        const AbilityParamMapping(
          abilityId: AbilityIds.processingSpeed,
          paramId: CognitiveParamIds.taskDurationEstimate,
          weight: 1,
          direction: 'sideways',
        ),
      ];
      final params = deriveParams(abilities: abilities, mappings: mappings);
      expect(params.single.value, closeTo(0.75, 1e-9));
    });

    test('信号在 ±2 个 z 处饱和，value 夹在 0..1', () {
      final positive = deriveParams(
        abilities: <AbilityEstimate>[
          _ability(AbilityIds.processingSpeed, mean: 10)
        ],
        mappings: <AbilityParamMapping>[
          const AbilityParamMapping(
            abilityId: AbilityIds.processingSpeed,
            paramId: CognitiveParamIds.taskDurationEstimate,
            weight: 1,
            direction: MappingDirection.positive,
          ),
        ],
      );
      expect(positive.single.value, 1.0);
      final negative = deriveParams(
        abilities: <AbilityEstimate>[
          _ability(AbilityIds.processingSpeed, mean: -10)
        ],
        mappings: <AbilityParamMapping>[
          const AbilityParamMapping(
            abilityId: AbilityIds.processingSpeed,
            paramId: CognitiveParamIds.taskDurationEstimate,
            weight: 1,
            direction: MappingDirection.positive,
          ),
        ],
      );
      expect(negative.single.value, 0.0);
    });

    test('参数不确定性夹在 [0.15, 0.9]', () {
      List<ParamEstimate> paramsFor(double uncertainty) => deriveParams(
            abilities: <AbilityEstimate>[
              _ability(AbilityIds.processingSpeed,
                  mean: 0, uncertainty: uncertainty),
            ],
            mappings: <AbilityParamMapping>[
              const AbilityParamMapping(
                abilityId: AbilityIds.processingSpeed,
                paramId: CognitiveParamIds.taskDurationEstimate,
                weight: 1,
                direction: MappingDirection.positive,
              ),
            ],
          );
      expect(paramsFor(0.01).single.uncertainty, kDerivedParamMinUncertainty);
      expect(paramsFor(1.0).single.uncertainty, kDerivedParamMaxUncertainty);
    });

    test('user_override 参数跳过，其它参数照常推导', () {
      final abilities = <AbilityEstimate>[
        _ability(AbilityIds.processingSpeed, mean: 1)
      ];
      final mappings = <AbilityParamMapping>[
        const AbilityParamMapping(
          abilityId: AbilityIds.processingSpeed,
          paramId: CognitiveParamIds.taskDurationEstimate,
          weight: 1,
          direction: MappingDirection.positive,
        ),
        const AbilityParamMapping(
          abilityId: AbilityIds.processingSpeed,
          paramId: CognitiveParamIds.chunkingThreshold,
          weight: 1,
          direction: MappingDirection.positive,
        ),
      ];
      final current = <ParamEstimate>[
        const ParamEstimate(
          paramId: CognitiveParamIds.taskDurationEstimate,
          value: 0.9,
          uncertainty: 0.1,
          source: EstimateSources.userOverride,
        ),
      ];
      final params = deriveParams(
        abilities: abilities,
        mappings: mappings,
        currentParams: current,
      );
      expect(params, hasLength(1));
      expect(params.single.paramId, CognitiveParamIds.chunkingThreshold);
    });

    test('输出顺序：已知参数按设计顺序，未知参数排后且字典序', () {
      final abilities = <AbilityEstimate>[
        _ability(AbilityIds.processingSpeed, mean: 1)
      ];
      final mappings = <AbilityParamMapping>[
        const AbilityParamMapping(
          abilityId: AbilityIds.processingSpeed,
          paramId: CognitiveParamIds.timeOfDayBias,
          weight: 1,
          direction: MappingDirection.positive,
        ),
        const AbilityParamMapping(
          abilityId: AbilityIds.processingSpeed,
          paramId: CognitiveParamIds.taskDurationEstimate,
          weight: 1,
          direction: MappingDirection.positive,
        ),
        const AbilityParamMapping(
          abilityId: AbilityIds.processingSpeed,
          paramId: 'zzz_custom_param',
          weight: 1,
          direction: MappingDirection.positive,
        ),
      ];
      final params = deriveParams(abilities: abilities, mappings: mappings);
      expect(params.map((p) => p.paramId).toList(), <String>[
        CognitiveParamIds.taskDurationEstimate,
        CognitiveParamIds.timeOfDayBias,
        'zzz_custom_param',
      ]);
    });

    test('同一参数多条映射按权重加权平均', () {
      final abilities = <AbilityEstimate>[
        _ability(AbilityIds.processingSpeed, mean: 2, uncertainty: 0.4),
        _ability(AbilityIds.inhibitoryControl, mean: -2, uncertainty: 0.6),
      ];
      final mappings = <AbilityParamMapping>[
        const AbilityParamMapping(
          abilityId: AbilityIds.processingSpeed,
          paramId: CognitiveParamIds.taskDurationEstimate,
          weight: 1,
          direction: MappingDirection.positive,
        ),
        const AbilityParamMapping(
          abilityId: AbilityIds.inhibitoryControl,
          paramId: CognitiveParamIds.taskDurationEstimate,
          weight: 1,
          direction: MappingDirection.positive,
        ),
      ];
      final params = deriveParams(abilities: abilities, mappings: mappings);
      expect(params.single.value, closeTo(0.5, 1e-9));
      expect(params.single.uncertainty, closeTo(0.5, 1e-9));
      expect(params.single.derivedFrom, hasLength(2));
    });

    test('非正权重、空参数 id 的映射被忽略', () {
      final abilities = <AbilityEstimate>[
        _ability(AbilityIds.processingSpeed, mean: 1)
      ];
      final mappings = <AbilityParamMapping>[
        const AbilityParamMapping(
          abilityId: AbilityIds.processingSpeed,
          paramId: CognitiveParamIds.taskDurationEstimate,
          weight: 0,
          direction: MappingDirection.positive,
        ),
        const AbilityParamMapping(
          abilityId: AbilityIds.processingSpeed,
          paramId: '  ',
          weight: 1,
          direction: MappingDirection.positive,
        ),
      ];
      expect(
        deriveParams(abilities: abilities, mappings: mappings),
        isEmpty,
      );
    });

    test('能力均值 NaN 按 0 处理', () {
      final abilities = <AbilityEstimate>[
        _ability(AbilityIds.processingSpeed, mean: double.nan),
      ];
      final mappings = <AbilityParamMapping>[
        const AbilityParamMapping(
          abilityId: AbilityIds.processingSpeed,
          paramId: CognitiveParamIds.taskDurationEstimate,
          weight: 1,
          direction: MappingDirection.positive,
        ),
      ];
      final params = deriveParams(abilities: abilities, mappings: mappings);
      expect(params.single.value, closeTo(0.5, 1e-9));
    });

    test('重复能力 id 取最后一条', () {
      final abilities = <AbilityEstimate>[
        _ability(AbilityIds.processingSpeed, mean: 1),
        _ability(AbilityIds.processingSpeed, mean: 2),
      ];
      final mappings = <AbilityParamMapping>[
        const AbilityParamMapping(
          abilityId: AbilityIds.processingSpeed,
          paramId: CognitiveParamIds.taskDurationEstimate,
          weight: 1,
          direction: MappingDirection.positive,
        ),
      ];
      final params = deriveParams(abilities: abilities, mappings: mappings);
      expect(params.single.value, 1.0);
    });

    test('updatedAt 透传且结果列表不可变', () {
      final updatedAt = DateTime.utc(2026, 3, 3);
      final params = deriveParams(
        abilities: <AbilityEstimate>[
          _ability(AbilityIds.processingSpeed, mean: 1)
        ],
        mappings: <AbilityParamMapping>[
          const AbilityParamMapping(
            abilityId: AbilityIds.processingSpeed,
            paramId: CognitiveParamIds.taskDurationEstimate,
            weight: 1,
            direction: MappingDirection.positive,
          ),
        ],
        updatedAt: updatedAt,
      );
      expect(params.single.updatedAt, updatedAt);
      expect(() => params.add(params.single), throwsUnsupportedError);
    });
  });
}
