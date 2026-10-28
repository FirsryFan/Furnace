import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/features/assessment/application/cognitive_params_provider.dart';
import 'package:furnace/features/assessment/domain/assessment_models.dart';

ParamEstimate _estimate(
  String paramId, {
  double value = 0.5,
  double uncertainty = 0.2,
  String source = EstimateSources.assessment,
}) {
  return ParamEstimate(
    paramId: paramId,
    value: value,
    uncertainty: uncertainty,
    source: source,
  );
}

void main() {
  group('常量与默认值', () {
    test('不确定性阈值是 0.4', () {
      expect(kThreadParamMaxUncertainty, 0.4);
    });

    test('Thread 参数 id 与 CognitiveParamIds.all 完全一致', () {
      expect(kThreadRelevantParamIds, CognitiveParamIds.all);
      expect(kThreadRelevantParamIds, hasLength(9));
    });

    test('空 provider 返回九项系统默认先验', () {
      const provider = CognitiveParamsProvider(
        estimates: <String, ParamEstimate>{},
      );
      final params = provider.getParamsForThread();
      expect(params.keys.toList(), kThreadRelevantParamIds);
      for (final id in kThreadRelevantParamIds) {
        final estimate = params[id]!;
        expect(estimate.value, 0.5);
        expect(estimate.uncertainty, kDefaultAbilityUncertainty);
        expect(estimate.source, EstimateSources.defaultPrior);
      }
    });
  });

  group('回退规则', () {
    test('高不确定性回退默认值', () {
      final provider = CognitiveParamsProvider.fromEstimates(<ParamEstimate>[
        _estimate(
          CognitiveParamIds.switchPenalty,
          value: 0.9,
          uncertainty: 0.8,
        ),
      ]);
      final estimate = provider.estimateFor(CognitiveParamIds.switchPenalty);
      expect(estimate.paramId, CognitiveParamIds.switchPenalty);
      expect(estimate.value, 0.5);
      expect(estimate.uncertainty, kDefaultAbilityUncertainty);
      expect(estimate.source, EstimateSources.defaultPrior);
      final suggestion = provider.suggestions(
          paramIds: <String>[CognitiveParamIds.switchPenalty]).single;
      expect(suggestion.usedDefault, isTrue);
      expect(suggestion.defaultValue, 0.5);
      expect(suggestion.suggestedValue, 0.5);
    });

    test('不超阈值保留原始值', () {
      final provider = CognitiveParamsProvider.fromEstimates(<ParamEstimate>[
        _estimate(
          CognitiveParamIds.chunkingThreshold,
          value: 0.82,
          uncertainty: 0.3,
          source: EstimateSources.derived,
        ),
      ]);
      final estimate =
          provider.estimateFor(CognitiveParamIds.chunkingThreshold);
      expect(estimate.value, 0.82);
      expect(estimate.uncertainty, 0.3);
      expect(estimate.source, EstimateSources.derived);
      final suggestion = provider.suggestions(
          paramIds: <String>[CognitiveParamIds.chunkingThreshold]).single;
      expect(suggestion.usedDefault, isFalse);
    });

    test('不确定性等于阈值时保留原始（严格大于才回退）', () {
      final provider = CognitiveParamsProvider.fromEstimates(<ParamEstimate>[
        _estimate(
          CognitiveParamIds.interruptionCost,
          value: 0.7,
          uncertainty: kThreadParamMaxUncertainty,
        ),
      ]);
      final estimate = provider.estimateFor(CognitiveParamIds.interruptionCost);
      expect(estimate.value, 0.7);
      expect(estimate.uncertainty, kThreadParamMaxUncertainty);
      expect(estimate.source, EstimateSources.assessment);
    });

    test('user_override 高不确定性仍被信任', () {
      final provider = CognitiveParamsProvider.fromEstimates(<ParamEstimate>[
        _estimate(
          CognitiveParamIds.expectedPressure,
          value: 0.95,
          uncertainty: 0.95,
          source: EstimateSources.userOverride,
        ),
      ]);
      final estimate = provider.estimateFor(CognitiveParamIds.expectedPressure);
      expect(estimate.value, 0.95);
      expect(estimate.uncertainty, 0.95);
      expect(estimate.source, EstimateSources.userOverride);
      final suggestion = provider.suggestions(
          paramIds: <String>[CognitiveParamIds.expectedPressure]).single;
      expect(suggestion.usedDefault, isFalse);
      expect(suggestion.isUserOverride, isTrue);
    });

    test('原始 source 就是 default 时原样使用', () {
      final provider = CognitiveParamsProvider.fromEstimates(<ParamEstimate>[
        _estimate(
          CognitiveParamIds.highLoadDiscount,
          value: 0.5,
          uncertainty: kDefaultAbilityUncertainty,
          source: EstimateSources.defaultPrior,
        ),
      ]);
      final estimate = provider.estimateFor(CognitiveParamIds.highLoadDiscount);
      expect(estimate.uncertainty, kDefaultAbilityUncertainty);
      expect(estimate.source, EstimateSources.defaultPrior);
      expect(
        provider
            .suggestions(paramIds: <String>[CognitiveParamIds.highLoadDiscount])
            .single
            .usedDefault,
        isTrue,
      );
    });

    test('缺失的参数 id 用系统默认先验', () {
      final provider = CognitiveParamsProvider.fromEstimates(
        const <ParamEstimate>[],
      );
      final estimate =
          provider.estimateFor(CognitiveParamIds.similarFatiguePenalty);
      expect(estimate.paramId, CognitiveParamIds.similarFatiguePenalty);
      expect(estimate.value, 0.5);
      expect(estimate.uncertainty, kDefaultAbilityUncertainty);
      expect(estimate.source, EstimateSources.defaultPrior);
    });

    test('未登记 id 用中性出厂值兜底', () {
      final provider = CognitiveParamsProvider.fromEstimates(
        const <ParamEstimate>[],
      );
      final estimate = provider.estimateFor('custom_param');
      expect(estimate.paramId, 'custom_param');
      expect(estimate.value, 0.5);
      expect(estimate.uncertainty, kDefaultAbilityUncertainty);
      expect(estimate.source, EstimateSources.defaultPrior);
      expect(
          provider
              .suggestions(paramIds: <String>['custom_param'])
              .single
              .defaultValue,
          0.5);
    });

    test('NaN 或无穷大的不确定性视为不可用并回退', () {
      final provider = CognitiveParamsProvider.fromEstimates(<ParamEstimate>[
        _estimate(
          CognitiveParamIds.taskDurationEstimate,
          value: 0.9,
          uncertainty: double.nan,
        ),
        _estimate(
          CognitiveParamIds.scheduleIntensityCap,
          value: 0.9,
          uncertainty: double.infinity,
        ),
      ]);
      for (final id in <String>[
        CognitiveParamIds.taskDurationEstimate,
        CognitiveParamIds.scheduleIntensityCap,
      ]) {
        final estimate = provider.estimateFor(id);
        expect(estimate.value, 0.5);
        expect(estimate.source, EstimateSources.defaultPrior);
      }
    });

    test('自定义阈值生效', () {
      final provider = CognitiveParamsProvider.fromEstimates(
        <ParamEstimate>[
          _estimate(
            CognitiveParamIds.timeOfDayBias,
            value: 0.9,
            uncertainty: 0.2,
          ),
        ],
        maxUncertainty: 0.1,
      );
      final estimate = provider.estimateFor(CognitiveParamIds.timeOfDayBias);
      expect(estimate.value, 0.5);
      expect(estimate.source, EstimateSources.defaultPrior);
    });
  });

  group('fromEstimates 归一化', () {
    test('id 去首尾空白并丢弃空 id', () {
      final provider = CognitiveParamsProvider.fromEstimates(<ParamEstimate>[
        _estimate('  chunking_threshold  ', value: 0.1),
        _estimate('   ', value: 0.2),
        _estimate('', value: 0.3),
      ]);
      expect(provider.estimates.keys.toList(), <String>['chunking_threshold']);
      expect(provider.estimates['chunking_threshold']!.value, 0.1);
    });

    test('重复 id 后写覆盖先写', () {
      final provider = CognitiveParamsProvider.fromEstimates(<ParamEstimate>[
        _estimate(CognitiveParamIds.switchPenalty, value: 0.1),
        _estimate(CognitiveParamIds.switchPenalty, value: 0.9),
      ]);
      expect(provider.estimates, hasLength(1));
      expect(provider.estimates[CognitiveParamIds.switchPenalty]!.value, 0.9);
    });

    test('estimates 是只读视图', () {
      final provider = CognitiveParamsProvider.fromEstimates(<ParamEstimate>[
        _estimate(CognitiveParamIds.expectedPressure),
      ]);
      expect(
        () => provider.estimates[CognitiveParamIds.expectedPressure] =
            _estimate(CognitiveParamIds.expectedPressure),
        throwsUnsupportedError,
      );
      expect(
        () => provider.estimates.remove(CognitiveParamIds.expectedPressure),
        throwsUnsupportedError,
      );
    });

    test('直接构造时返回的 estimates 也不可变', () {
      final raw = <String, ParamEstimate>{
        CognitiveParamIds.taskDurationEstimate: _estimate(
          CognitiveParamIds.taskDurationEstimate,
        ),
      };
      final provider = CognitiveParamsProvider(estimates: raw);
      expect(
        () => provider.estimates.clear(),
        throwsUnsupportedError,
      );
    });
  });

  group('getParamsForThread 排序与子集', () {
    test('默认返回九项且顺序稳定', () {
      final provider = CognitiveParamsProvider.fromEstimates(
        const <ParamEstimate>[],
      );
      final params = provider.getParamsForThread();
      expect(params.keys.toList(), kThreadRelevantParamIds);
      expect(params, hasLength(9));
    });

    test('子集：已知 id 按固定顺序，未知 id 排后按字典序', () {
      final provider = CognitiveParamsProvider.fromEstimates(
        const <ParamEstimate>[],
      );
      final params = provider.getParamsForThread(
        paramIds: <String>[
          CognitiveParamIds.timeOfDayBias,
          'zzz_param',
          CognitiveParamIds.taskDurationEstimate,
          'aaa_param',
          CognitiveParamIds.timeOfDayBias,
          '   ',
        ],
      );
      expect(params.keys.toList(), <String>[
        CognitiveParamIds.taskDurationEstimate,
        CognitiveParamIds.timeOfDayBias,
        'aaa_param',
        'zzz_param',
      ]);
    });

    test('paramIds 为空迭代器时返回空表', () {
      final provider = CognitiveParamsProvider.fromEstimates(
        const <ParamEstimate>[],
      );
      expect(provider.getParamsForThread(paramIds: const <String>[]), isEmpty);
    });

    test('子集里未知 id 也能拿到兜底估计', () {
      final provider = CognitiveParamsProvider.fromEstimates(
        const <ParamEstimate>[],
      );
      final params = provider.getParamsForThread(
        paramIds: <String>['unknown_x'],
      );
      final estimate = params['unknown_x']!;
      expect(estimate.value, 0.5);
      expect(estimate.source, EstimateSources.defaultPrior);
    });
  });

  group('suggestions', () {
    test('字段映射与顺序', () {
      final provider = CognitiveParamsProvider.fromEstimates(<ParamEstimate>[
        _estimate(
          CognitiveParamIds.chunkingThreshold,
          value: 0.8,
          uncertainty: 0.1,
          source: EstimateSources.derived,
        ),
        _estimate(
          CognitiveParamIds.switchPenalty,
          value: 0.9,
          uncertainty: 0.8,
        ),
      ]);
      final suggestions = provider.suggestions(
        paramIds: <String>[
          CognitiveParamIds.switchPenalty,
          CognitiveParamIds.chunkingThreshold,
        ],
      );
      expect(suggestions, hasLength(2));
      final kept = suggestions[0];
      expect(kept.paramId, CognitiveParamIds.chunkingThreshold);
      expect(kept.defaultValue, 0.5);
      expect(kept.suggestedValue, 0.8);
      expect(kept.uncertainty, 0.1);
      expect(kept.source, EstimateSources.derived);
      expect(kept.usedDefault, isFalse);
      final fallback = suggestions[1];
      expect(fallback.paramId, CognitiveParamIds.switchPenalty);
      expect(fallback.suggestedValue, 0.5);
      expect(fallback.uncertainty, kDefaultAbilityUncertainty);
      expect(fallback.source, EstimateSources.defaultPrior);
      expect(fallback.usedDefault, isTrue);
    });

    test('顶层函数与实例方法结果一致', () {
      final provider = CognitiveParamsProvider.fromEstimates(<ParamEstimate>[
        _estimate(CognitiveParamIds.taskDurationEstimate, value: 0.7),
      ]);
      const ids = <String>[
        CognitiveParamIds.taskDurationEstimate,
        'unknown_y',
      ];
      expect(
        threadWeightSuggestions(provider, paramIds: ids),
        provider.suggestions(paramIds: ids),
      );
    });

    test('建议列表不可变', () {
      final provider = CognitiveParamsProvider.fromEstimates(
        const <ParamEstimate>[],
      );
      final suggestions = threadWeightSuggestions(provider);
      expect(
        () => suggestions.add(suggestions.first),
        throwsUnsupportedError,
      );
    });

    test('toJson 键序与值', () {
      const suggestion = ThreadWeightSuggestion(
        paramId: 'switch_penalty',
        defaultValue: 0.5,
        suggestedValue: 0.82,
        uncertainty: 0.2,
        source: EstimateSources.derived,
        usedDefault: false,
      );
      expect(suggestion.toJson().keys.toList(), <String>[
        'param_id',
        'default_value',
        'suggested_value',
        'uncertainty',
        'source',
        'used_default',
      ]);
      expect(suggestion.toJson(), <String, Object?>{
        'param_id': 'switch_penalty',
        'default_value': 0.5,
        'suggested_value': 0.82,
        'uncertainty': 0.2,
        'source': EstimateSources.derived,
        'used_default': false,
      });
    });

    test('值相等即相等且 hashCode 一致', () {
      const a = ThreadWeightSuggestion(
        paramId: 'switch_penalty',
        defaultValue: 0.5,
        suggestedValue: 0.8,
        uncertainty: 0.2,
        source: EstimateSources.derived,
        usedDefault: false,
      );
      const b = ThreadWeightSuggestion(
        paramId: 'switch_penalty',
        defaultValue: 0.5,
        suggestedValue: 0.8,
        uncertainty: 0.2,
        source: EstimateSources.derived,
        usedDefault: false,
      );
      const c = ThreadWeightSuggestion(
        paramId: 'switch_penalty',
        defaultValue: 0.5,
        suggestedValue: 0.9,
        uncertainty: 0.2,
        source: EstimateSources.derived,
        usedDefault: false,
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
      final unique = <ThreadWeightSuggestion>{};
      unique.add(a);
      unique.add(b);
      expect(unique, hasLength(1));
    });
  });
}
