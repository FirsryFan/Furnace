import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/features/assessment/domain/assessment_cog_profile.dart';
import 'package:furnace/features/assessment/domain/assessment_models.dart';

AbilityEstimate _ability(
  String abilityId, {
  double mean = 0.0,
  double uncertainty = 0.5,
  int nMeasurements = 1,
  String source = EstimateSources.assessment,
}) {
  return AbilityEstimate(
    abilityId: abilityId,
    mean: mean,
    uncertainty: uncertainty,
    nMeasurements: nMeasurements,
    source: source,
  );
}

ParamEstimate _param(
  String paramId, {
  double value = 0.5,
  double uncertainty = 0.5,
  String source = EstimateSources.derived,
}) {
  return ParamEstimate(
    paramId: paramId,
    value: value,
    uncertainty: uncertainty,
    source: source,
  );
}

Map<String, Object?> _profile({
  List<AbilityEstimate> abilities = const <AbilityEstimate>[
    AbilityEstimate(
      abilityId: AbilityIds.processingSpeed,
      mean: 0.8,
      uncertainty: 0.4,
      nMeasurements: 3,
      source: EstimateSources.assessment,
    ),
  ],
  List<ParamEstimate> params = const <ParamEstimate>[
    ParamEstimate(
      paramId: CognitiveParamIds.taskDurationEstimate,
      value: 0.6,
      uncertainty: 0.4,
      source: EstimateSources.derived,
    ),
  ],
  DateTime? exportedAt,
}) {
  return buildCogProfile(
    abilities: abilities,
    cognitiveParams: params,
    exportedAt: exportedAt ?? DateTime.utc(2026, 10, 29, 0, 0, 0),
  );
}

void main() {
  group('buildCogProfile 结构', () {
    test('顶层键序固定', () {
      expect(_profile().keys.toList(), <String>[
        'format_version',
        'exported_at',
        'design_version',
        'mapping_version',
        'abilities',
        'cognitive_params',
        'privacy',
      ]);
    });

    test('格式版本、设计/映射版本与默认隐私声明', () {
      final profile = _profile();
      expect(profile['format_version'], kCogProfileFormatVersion);
      expect(profile['format_version'], '1.0');
      expect(profile['design_version'], kAssessmentDesignVersion);
      expect(profile['mapping_version'], kAssessmentMappingVersion);
      expect(profile['privacy'], kCogProfilePrivacyZh);
      expect(profile['privacy'], contains('不含'));
    });

    test('exported_at 转成 UTC ISO-8601', () {
      final profile = buildCogProfile(
        abilities: const <AbilityEstimate>[],
        cognitiveParams: const <ParamEstimate>[],
        exportedAt: DateTime.parse('2026-10-29T08:30:00+08:00'),
      );
      expect(profile['exported_at'], '2026-10-29T00:30:00.000Z');
    });

    test('privacy 可覆盖，版本号可注入', () {
      final profile = buildCogProfile(
        abilities: const <AbilityEstimate>[],
        cognitiveParams: const <ParamEstimate>[],
        exportedAt: DateTime.utc(2026, 1, 1),
        designVersion: '1.1',
        mappingVersion: '3.0',
        privacy: '自定义声明',
      );
      expect(profile['privacy'], '自定义声明');
      expect(profile['design_version'], '1.1');
      expect(profile['mapping_version'], '3.0');
    });
  });

  group('能力条目', () {
    test('按 AbilityIds.all 排序，未知 id 排最后且字典序', () {
      final profile = _profile(
        abilities: <AbilityEstimate>[
          _ability('zzz_unknown'),
          _ability(AbilityIds.crossLanguageCost),
          _ability(AbilityIds.processingSpeed),
          _ability('aaa_unknown'),
        ],
      );
      final entries = profile['abilities']! as List<Object?>;
      expect(
        entries
            .map((entry) => (entry! as Map<String, Object?>)['ability_id'])
            .toList(),
        <String>[
          AbilityIds.processingSpeed,
          AbilityIds.crossLanguageCost,
          'aaa_unknown',
          'zzz_unknown',
        ],
      );
    });

    test('能力条目键序与字段值', () {
      final profile = _profile();
      final entries = profile['abilities']! as List<Object?>;
      final entry = entries.single! as Map<String, Object?>;
      expect(entry.keys.toList(), <String>[
        'ability_id',
        'mean',
        'uncertainty',
        'n_measurements',
        'source',
      ]);
      expect(entry['ability_id'], AbilityIds.processingSpeed);
      expect(entry['mean'], 0.8);
      expect(entry['uncertainty'], 0.4);
      expect(entry['n_measurements'], 3);
      expect(entry['source'], EstimateSources.assessment);
    });

    test('重复 ability_id 取最后一条，空白 id 被跳过', () {
      final profile = _profile(
        abilities: <AbilityEstimate>[
          _ability(AbilityIds.processingSpeed, mean: 1),
          _ability('  '),
          _ability(AbilityIds.processingSpeed, mean: 2),
        ],
      );
      final entries = profile['abilities']! as List<Object?>;
      expect(entries, hasLength(1));
      expect((entries.single! as Map<String, Object?>)['mean'], 2);
    });

    test('能力数值净化：NaN、越界、负测量数、空 source', () {
      final profile = _profile(
        abilities: <AbilityEstimate>[
          _ability(
            AbilityIds.processingSpeed,
            mean: double.nan,
            uncertainty: -1,
            nMeasurements: -5,
            source: '  ',
          ),
          _ability(AbilityIds.inhibitoryControl, uncertainty: 2),
        ],
      );
      final entries = profile['abilities']! as List<Object?>;
      final first = entries[0]! as Map<String, Object?>;
      expect(first['mean'], 0.0);
      expect(first['uncertainty'], 0.0);
      expect(first['n_measurements'], 0);
      expect(first['source'], EstimateSources.defaultPrior);
      final second = entries[1]! as Map<String, Object?>;
      expect(second['uncertainty'], 1.0);
    });
  });

  group('认知参数条目', () {
    test('按 CognitiveParamIds.all 排序，未知 id 排最后且字典序', () {
      final profile = _profile(
        params: <ParamEstimate>[
          _param('zzz_param'),
          _param(CognitiveParamIds.timeOfDayBias),
          _param(CognitiveParamIds.taskDurationEstimate),
          _param('aaa_param'),
        ],
      );
      final entries = profile['cognitive_params']! as List<Object?>;
      expect(
        entries
            .map((entry) => (entry! as Map<String, Object?>)['param_id'])
            .toList(),
        <String>[
          CognitiveParamIds.taskDurationEstimate,
          CognitiveParamIds.timeOfDayBias,
          'aaa_param',
          'zzz_param',
        ],
      );
    });

    test('参数条目键序与字段值', () {
      final profile = _profile();
      final entries = profile['cognitive_params']! as List<Object?>;
      final entry = entries.single! as Map<String, Object?>;
      expect(entry.keys.toList(), <String>[
        'param_id',
        'value',
        'uncertainty',
        'source',
      ]);
      expect(entry['param_id'], CognitiveParamIds.taskDurationEstimate);
      expect(entry['value'], 0.6);
      expect(entry['uncertainty'], 0.4);
      expect(entry['source'], EstimateSources.derived);
    });

    test('参数数值净化：NaN 与越界', () {
      final profile = _profile(
        params: <ParamEstimate>[
          _param(
            CognitiveParamIds.taskDurationEstimate,
            value: double.nan,
            uncertainty: double.nan,
            source: '  ',
          ),
          _param(CognitiveParamIds.chunkingThreshold, value: 3),
          _param(CognitiveParamIds.interruptionCost, value: -2),
        ],
      );
      final entries = profile['cognitive_params']! as List<Object?>;
      final first = entries[0]! as Map<String, Object?>;
      expect(first['value'], 0.5);
      expect(first['uncertainty'], 1.0);
      expect(first['source'], EstimateSources.defaultPrior);
      expect((entries[1]! as Map<String, Object?>)['value'], 1.0);
      expect((entries[2]! as Map<String, Object?>)['value'], 0.0);
    });

    test('重复 param_id 取最后一条，空白 id 被跳过', () {
      final profile = _profile(
        params: <ParamEstimate>[
          _param(CognitiveParamIds.taskDurationEstimate, value: 0.2),
          _param('   '),
          _param(CognitiveParamIds.taskDurationEstimate, value: 0.8),
        ],
      );
      final entries = profile['cognitive_params']! as List<Object?>;
      expect(entries, hasLength(1));
      expect((entries.single! as Map<String, Object?>)['value'], 0.8);
    });
  });

  group('编码与边界', () {
    test('空输入输出空数组', () {
      final profile = buildCogProfile(
        abilities: const <AbilityEstimate>[],
        cognitiveParams: const <ParamEstimate>[],
        exportedAt: DateTime.utc(2026, 1, 1),
      );
      expect(profile['abilities'], isEmpty);
      expect(profile['cognitive_params'], isEmpty);
    });

    test('pretty 编码可被 jsonDecode 还原', () {
      final profile = _profile();
      final text = encodeCogProfile(profile);
      expect(text, contains('\n'));
      final decoded = jsonDecode(text) as Map<String, Object?>;
      expect(decoded['format_version'], '1.0');
      expect(decoded['abilities'], isA<List<Object?>>());
      expect((decoded['abilities']! as List<Object?>), hasLength(1));
      expect(decoded['privacy'], kCogProfilePrivacyZh);
    });

    test('非 pretty 编码为单行', () {
      final text = encodeCogProfile(_profile(), pretty: false);
      expect(text, isNot(contains('\n')));
      expect(text, contains('"format_version":"1.0"'));
    });

    test('不修改输入列表', () {
      final abilities = <AbilityEstimate>[_ability(AbilityIds.processingSpeed)];
      final params = <ParamEstimate>[
        _param(CognitiveParamIds.expectedPressure)
      ];
      buildCogProfile(
        abilities: abilities,
        cognitiveParams: params,
        exportedAt: DateTime.utc(2026, 1, 1),
      );
      expect(abilities, hasLength(1));
      expect(params, hasLength(1));
    });
  });
}
