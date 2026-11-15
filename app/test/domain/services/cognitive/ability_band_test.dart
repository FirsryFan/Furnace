import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/cognitive/ability_band.dart';

/// 方便构造一条「均值 + 窄区间」的实测输入。
AbilityBandReading _read(
  double mean, {
  int nObs = 10,
  AbilitySource source = AbilitySource.measured,
  AbilityBandPolicy policy = AbilityBandPolicy.mastery,
}) {
  return readAbilityBand(
    AbilityBandInput(
      source: source,
      nObs: nObs,
      mean: mean,
      interval: AbilityInterval(lo: mean - 0.02, hi: mean + 0.02),
    ),
    policy: policy,
  );
}

void main() {
  group('AbilityBand / AbilitySource 基础枚举', () {
    test('六个档位的显示字：S/A/B/C/D/?', () {
      expect(AbilityBand.values, hasLength(6));
      expect(AbilityBand.s.label, 'S');
      expect(AbilityBand.a.label, 'A');
      expect(AbilityBand.b.label, 'B');
      expect(AbilityBand.c.label, 'C');
      expect(AbilityBand.d.label, 'D');
      expect(AbilityBand.unknown.label, '?');
    });

    test('只有 unknown 不是真实档位', () {
      for (final band in AbilityBand.values) {
        expect(band.isKnown, band != AbilityBand.unknown);
      }
    });

    test('来源编码归类与 ability-matrix 的 measured/preset/unknown 对齐', () {
      for (final code in const <String>[
        'measured',
        'assessment_v1',
        'item_response',
        'self_report',
        'process_feedback',
      ]) {
        expect(AbilitySource.fromCode(code), AbilitySource.measured, reason: code);
      }
      for (final code in const <String>[
        'preset',
        'preset_or_default',
        'preset_fixed',
        'default',
      ]) {
        expect(AbilitySource.fromCode(code), AbilitySource.preset, reason: code);
      }
      for (final code in const <String?>[
        'unknown',
        '',
        '   ',
        null,
        'mystery_source',
      ]) {
        expect(AbilitySource.fromCode(code), AbilitySource.unknown, reason: '$code');
      }
      // 三段 code 都能原样解析回来（稳定编码）。
      for (final source in AbilitySource.values) {
        expect(AbilitySource.fromCode(source.code), source);
      }
    });

    test('三个来源 code 就是矩阵 class 的三个词', () {
      expect(AbilitySource.measured.code, 'measured');
      expect(AbilitySource.preset.code, 'preset');
      expect(AbilitySource.unknown.code, 'unknown');
    });
  });

  group('均值边界：闭区间、上边界归高档', () {
    test('0–1 掌握度：S/A/B/C/D 的边界与相邻值', () {
      expect(_read(1.0).band, AbilityBand.s);
      expect(_read(0.90).band, AbilityBand.s);
      expect(_read(0.8999).band, AbilityBand.a);
      expect(_read(0.75).band, AbilityBand.a);
      expect(_read(0.7499).band, AbilityBand.b);
      expect(_read(0.60).band, AbilityBand.b);
      expect(_read(0.5999).band, AbilityBand.c);
      expect(_read(0.40).band, AbilityBand.c);
      expect(_read(0.3999).band, AbilityBand.d);
      expect(_read(0.0).band, AbilityBand.d);
    });

    test('0–1 掌握度：档位显示字就是 S/D，不带百分比', () {
      expect(_read(0.95).display, 'S');
      expect(_read(0.45).display, 'C');
      expect(_read(0.35).display, 'D');
      expect(_read(0.95).toJson()['display'], 'S');
    });

    test('logit 轴：S/A/B/C/D 的边界与相邻值', () {
      AbilityBand bandOf(double mean) =>
          _read(mean, policy: AbilityBandPolicy.abilityLogit).band;
      expect(bandOf(1.5), AbilityBand.s);
      expect(bandOf(1.4999), AbilityBand.a);
      expect(bandOf(0.75), AbilityBand.a);
      expect(bandOf(0.7499), AbilityBand.b);
      expect(bandOf(0.0), AbilityBand.b);
      expect(bandOf(-0.0001), AbilityBand.c);
      expect(bandOf(-0.75), AbilityBand.c);
      expect(bandOf(-0.7501), AbilityBand.d);
    });

    test('同一后验映射稳定（纯函数，同一输入同一输出）', () {
      const input = AbilityBandInput(
        source: AbilitySource.measured,
        nObs: 8,
        mean: 0.62,
        interval: AbilityInterval(lo: 0.56, hi: 0.68),
      );
      final first = readAbilityBand(input);
      final second = readAbilityBand(input);
      expect(first.band, AbilityBand.b);
      expect(second.band, first.band);
      expect(second.toJson(), first.toJson());
    });
  });

  group('证据不足 → unknown / ?', () {
    test('观测数低于门槛（默认 minObservations=3）→ ?', () {
      final reading = readAbilityBand(
        const AbilityBandInput(
          source: AbilitySource.measured,
          nObs: 2,
          mean: 0.95,
          interval: AbilityInterval(lo: 0.93, hi: 0.97),
        ),
      );
      expect(reading.band, AbilityBand.unknown);
      expect(reading.display, '?');
      expect(reading.unknownReason, AbilityUnknownReason.tooFewObservations);
    });

    test('观测数正好到门槛 3 → 给档', () {
      final reading = readAbilityBand(
        const AbilityBandInput(
          source: AbilitySource.measured,
          nObs: 3,
          mean: 0.95,
          interval: AbilityInterval(lo: 0.93, hi: 0.97),
        ),
      );
      expect(reading.band, AbilityBand.s);
      expect(reading.unknownReason, AbilityUnknownReason.none);
    });

    test('区间宽度超过上限（默认 0.60）→ ?；等于上限 → 给档', () {
      final tooWide = readAbilityBand(
        const AbilityBandInput(
          source: AbilitySource.measured,
          nObs: 10,
          mean: 0.55,
          interval: AbilityInterval(lo: 0.10, hi: 0.90),
        ),
      );
      expect(tooWide.band, AbilityBand.unknown);
      expect(tooWide.unknownReason, AbilityUnknownReason.uncertainInterval);

      final exact = readAbilityBand(
        const AbilityBandInput(
          source: AbilitySource.measured,
          nObs: 10,
          mean: 0.55,
          interval: AbilityInterval(lo: 0.25, hi: 0.85),
        ),
      );
      expect(exact.band, AbilityBand.c);
    });

    test('实测行既没区间也没 sd → ?（不确定度是必填的）', () {
      final reading = readAbilityBand(
        const AbilityBandInput(
          source: AbilitySource.measured,
          nObs: 10,
          mean: 0.8,
        ),
      );
      expect(reading.band, AbilityBand.unknown);
      expect(reading.unknownReason, AbilityUnknownReason.missingUncertainty);
    });

    test('有 sd 时按 95% 宽度判定：宽 sd → ?，窄 sd → 给档', () {
      final wide = readAbilityBand(
        const AbilityBandInput(
          source: AbilitySource.measured,
          nObs: 10,
          mean: 0.8,
          sd: 0.2,
        ),
      );
      expect(wide.band, AbilityBand.unknown);
      expect(wide.unknownReason, AbilityUnknownReason.uncertainInterval);
      expect(wide.interval?.width, closeTo(2 * 1.959964 * 0.2, 1e-9));

      final narrow = readAbilityBand(
        const AbilityBandInput(
          source: AbilitySource.measured,
          nObs: 10,
          mean: 0.8,
          sd: 0.1,
        ),
      );
      expect(narrow.band, AbilityBand.a);
    });

    test('区间优先于 sd：区间够窄时，宽 sd 不再把档位抹成 ?', () {
      final reading = readAbilityBand(
        const AbilityBandInput(
          source: AbilitySource.measured,
          nObs: 10,
          mean: 0.8,
          interval: AbilityInterval(lo: 0.78, hi: 0.82),
          sd: 5,
        ),
      );
      expect(reading.band, AbilityBand.a);
      expect(reading.interval?.width, closeTo(0.04, 1e-12));
    });

    test('没有均值 → ?（noMean）', () {
      final reading = readAbilityBand(
        const AbilityBandInput(
          source: AbilitySource.measured,
          nObs: 10,
        ),
      );
      expect(reading.band, AbilityBand.unknown);
      expect(reading.unknownReason, AbilityUnknownReason.noMean);
    });

    test('来源 unknown：即使均值看起来很高也只给 ?', () {
      final reading = readAbilityBand(
        const AbilityBandInput(
          source: AbilitySource.unknown,
          nObs: 10,
          mean: 0.99,
          interval: AbilityInterval(lo: 0.98, hi: 1.0),
        ),
      );
      expect(reading.band, AbilityBand.unknown);
      expect(reading.display, '?');
      expect(reading.unknownReason, AbilityUnknownReason.sourceUnknown);
    });

    test('不显示假精确百分比：? 也没有数字', () {
      final reading = readAbilityBand(
        const AbilityBandInput(
          source: AbilitySource.measured,
          nObs: 1,
          mean: 0.5,
          sd: 0.1,
        ),
      );
      expect(reading.display, '?');
      expect(reading.toJson()['display'], '?');
      expect(reading.toJson().keys, isNot(contains('percent')));
      expect(reading.toJson().keys, isNot(contains('percentage')));
    });
  });

  group('preset 与 measured 的区分', () {
    test('preset 有均值：给档但标记「（预设）」，不是实测档', () {
      final reading = _read(
        0.8,
        source: AbilitySource.preset,
        nObs: 0,
      );
      expect(reading.band, AbilityBand.a);
      expect(reading.source, AbilitySource.preset);
      expect(reading.isMeasured, isFalse);
      expect(reading.isPreset, isTrue);
      expect(reading.display, 'A（预设）');
      expect(reading.toJson()['evidence_class'], 'preset');
    });

    test('preset 不受实测门槛约束：n_obs=0 也能落档', () {
      final reading = _read(
        0.95,
        source: AbilitySource.preset,
        nObs: 0,
      );
      expect(reading.band, AbilityBand.s);
      expect(reading.display, 'S（预设）');
    });

    test('preset 没有均值：显示「?（预设）」，不编档', () {
      final reading = readAbilityBand(
        const AbilityBandInput(
          source: AbilitySource.preset,
          nObs: 0,
        ),
      );
      expect(reading.band, AbilityBand.unknown);
      expect(reading.unknownReason, AbilityUnknownReason.noMean);
      expect(reading.display, '?（预设）');
    });

    test('measured 已知档：isMeasured 为 true，display 不带预设标记', () {
      final reading = _read(0.8);
      expect(reading.isMeasured, isTrue);
      expect(reading.isPreset, isFalse);
      expect(reading.display, 'A');
    });
  });

  group('policy 可配置（阈值与门槛）', () {
    test('自定义阈值会改变落档', () {
      final reading = _read(
        0.56,
        policy: const AbilityBandPolicy(
          thresholds: AbilityBandThresholds(
            scale: AbilityBandScale.probability,
            s: 0.50,
            a: 0.45,
            b: 0.40,
            c: 0.35,
          ),
        ),
      );
      expect(reading.band, AbilityBand.s);
    });

    test('自定义 maxIntervalWidth 会把同一条后验从 ? 放成档', () {
      const input = AbilityBandInput(
        source: AbilitySource.measured,
        nObs: 3,
        mean: 0.6,
        interval: AbilityInterval(lo: 0.2266, hi: 0.8848),
      );
      expect(readAbilityBand(input).band, AbilityBand.unknown);
      final widePolicy = readAbilityBand(
        input,
        policy: const AbilityBandPolicy(maxIntervalWidth: 0.7),
      );
      expect(widePolicy.band, AbilityBand.b);
    });

    test('默认策略未标定：calibrated=false 会带进序列化', () {
      final reading = _read(0.8);
      expect(reading.calibrated, isFalse);
      expect(reading.toJson()['calibrated'], isFalse);
    });

    test('policy 可以声明已标定（当前没有这样的数据，只保证字段可表达）', () {
      final reading = _read(
        0.8,
        policy: const AbilityBandPolicy(calibrated: true),
      );
      expect(reading.toJson()['calibrated'], isTrue);
    });
  });

  group('与 ability-matrix JSON 对齐', () {
    test('knowledge 实测行（真实 UI 投影）：读字段、宽区间 → ?', () {
      // 取自 runs/ability-matrix-ui.json 的一条 measured knowledge 行。
      final input = AbilityBandInput.fromMatrixKnowledgeRow(
        <String, Object?>{
          'mastery': <String, Object?>{
            'class': 'measured',
            'source': 'self_report',
            'mean': 0.6,
            'intervals': <String, Object?>{
              '95': <Object?>[0.2266, 0.8848],
              '80': <Object?>[0.3402, 0.8136],
            },
          },
          'evidence': <String, Object?>{'n_obs': 3},
        },
      );
      expect(input.source, AbilitySource.measured);
      expect(input.nObs, 3);
      expect(input.mean, 0.6);
      expect(input.interval?.level, 0.95);
      expect(input.interval?.width, closeTo(0.6582, 1e-9));

      final reading = readAbilityBand(input);
      expect(reading.band, AbilityBand.unknown);
      expect(reading.unknownReason, AbilityUnknownReason.uncertainInterval);
      expect(reading.display, '?');
    });

    test('knowledge 实测行（真实 UI 投影）：同一行在更宽 policy 下能落档', () {
      final input = AbilityBandInput.fromMatrixKnowledgeRow(
        <String, Object?>{
          'mastery': <String, Object?>{
            'class': 'measured',
            'mean': 0.8,
            'intervals': <String, Object?>{
              '95': <Object?>[0.76, 0.84],
            },
          },
          'evidence': <String, Object?>{'n_obs': 8},
        },
      );
      expect(readAbilityBand(input).band, AbilityBand.a);
    });

    test('完整矩阵的 intervals 列表形态也能读（取最高可信度那条）', () {
      final input = AbilityBandInput.fromMatrixKnowledgeRow(
        <String, Object?>{
          'mastery': <String, Object?>{
            'source': 'self_report',
            'mean': 0.8,
            'intervals': <Object?>[
              <String, Object?>{'lo': 0.78, 'hi': 0.82, 'level': 0.8},
              <String, Object?>{'lo': 0.76, 'hi': 0.84, 'level': 0.95},
            ],
          },
          'evidence': <String, Object?>{'n_obs': 8},
        },
      );
      expect(input.source, AbilitySource.measured);
      expect(input.interval?.level, 0.95);
      expect(input.interval?.lo, 0.76);
      expect(input.interval?.hi, 0.84);
      expect(readAbilityBand(input).band, AbilityBand.a);
    });

    test('preset knowledge 行：class/source 归到 preset', () {
      final input = AbilityBandInput.fromMatrixKnowledgeRow(
        <String, Object?>{
          'mastery': <String, Object?>{
            'class': 'preset',
            'source': 'default',
            'mean': 0.7,
            'intervals': const <Object?>[],
          },
          'evidence': <String, Object?>{'n_obs': 0},
        },
      );
      expect(input.source, AbilitySource.preset);
      final reading = readAbilityBand(input);
      expect(reading.band, AbilityBand.b);
      expect(reading.display, 'B（预设）');
      expect(reading.isMeasured, isFalse);
    });

    test('capability 行（logit）：读 mean/uncertainty/n_measurements', () {
      // 取自 runs/ability-matrix-ui.json 的一条 measured capability 行。
      final input = AbilityBandInput.fromMatrixCapability(
        <String, Object?>{
          'ability_id': 'inhibitory_control',
          'class': 'measured',
          'mean': 1.917202,
          'uncertainty': 0.707107,
          'n_measurements': 5,
          'source': 'assessment_v1',
        },
      );
      expect(input.source, AbilitySource.measured);
      expect(input.mean, 1.917202);
      expect(input.sd, 0.707107);
      expect(input.nObs, 5);
      expect(input.interval, isNull); // 区间由 sd 在 read 时换算

      final reading = readAbilityBand(
        input,
        policy: AbilityBandPolicy.abilityLogit,
      );
      expect(reading.thresholds.scale, AbilityBandScale.logit);
      expect(reading.band, AbilityBand.s);
    });

    test('capability 行（preset 默认值）：mean=null → ?（预设）', () {
      final input = AbilityBandInput.fromMatrixCapability(
        <String, Object?>{
          'ability_id': 'working_memory_capacity',
          'class': 'preset',
          'mean': null,
          'uncertainty': 0.7,
          'n_measurements': 0,
          'source': 'default',
        },
      );
      expect(input.source, AbilitySource.preset);
      final reading = readAbilityBand(
        input,
        policy: AbilityBandPolicy.abilityLogit,
      );
      expect(reading.band, AbilityBand.unknown);
      expect(reading.display, '?（预设）');
    });

    test('capability 行（n_measurements < 3）：即使均值高也 ?', () {
      final input = AbilityBandInput.fromMatrixCapability(
        <String, Object?>{
          'class': 'measured',
          'mean': 1.9,
          'uncertainty': 0.5,
          'n_measurements': 1,
          'source': 'assessment_v1',
        },
      );
      final reading = readAbilityBand(
        input,
        policy: AbilityBandPolicy.abilityLogit,
      );
      expect(reading.band, AbilityBand.unknown);
      expect(reading.unknownReason, AbilityUnknownReason.tooFewObservations);
    });
  });

  group('序列化与非法输入', () {
    test('toJson 字段稳定：band/source/display/unknown_reason/scale', () {
      final json = _read(0.8).toJson();
      expect(json['band'], 'a');
      expect(json['band_label'], 'A');
      expect(json['source'], 'measured');
      expect(json['evidence_class'], 'measured');
      expect(json['display'], 'A');
      expect(json['unknown_reason'], 'none');
      expect(json['scale'], 'probability');
      expect(json['n_obs'], 10);
      expect(json['mean'], 0.8);
      expect(
        json['thresholds'],
        <String, Object?>{
          'scale': 'probability',
          's': 0.90,
          'a': 0.75,
          'b': 0.60,
          'c': 0.40,
        },
      );
    });

    test('负观测数 → ArgumentError', () {
      expect(
        () => readAbilityBand(
          const AbilityBandInput(
            source: AbilitySource.measured,
            nObs: -1,
            mean: 0.8,
          ),
        ),
        throwsArgumentError,
      );
    });

    test('NaN / 无穷均值 → ArgumentError', () {
      for (final mean in <double>[double.nan, double.infinity]) {
        expect(
          () => readAbilityBand(
            AbilityBandInput(
              source: AbilitySource.measured,
              nObs: 10,
              mean: mean,
            ),
          ),
          throwsArgumentError,
          reason: '$mean',
        );
      }
    });

    test('负 sd → ArgumentError', () {
      expect(
        () => readAbilityBand(
          const AbilityBandInput(
            source: AbilitySource.measured,
            nObs: 10,
            mean: 0.8,
            sd: -0.1,
          ),
        ),
        throwsArgumentError,
      );
    });

    test('区间 lo > hi → ArgumentError', () {
      expect(
        () => readAbilityBand(
          const AbilityBandInput(
            source: AbilitySource.measured,
            nObs: 10,
            mean: 0.8,
            interval: AbilityInterval(lo: 0.9, hi: 0.7),
          ),
        ),
        throwsArgumentError,
      );
    });

    test('阈值不严格递减 → ArgumentError', () {
      expect(
        () => readAbilityBand(
          const AbilityBandInput(
            source: AbilitySource.measured,
            nObs: 10,
            mean: 0.8,
            interval: AbilityInterval(lo: 0.78, hi: 0.82),
          ),
          policy: const AbilityBandPolicy(
            thresholds: AbilityBandThresholds(
              scale: AbilityBandScale.probability,
              s: 0.5,
              a: 0.6,
              b: 0.2,
              c: 0.1,
            ),
          ),
        ),
        throwsArgumentError,
      );
    });

    test('非法 policy 门槛 → ArgumentError', () {
      expect(
        () => readAbilityBand(
          const AbilityBandInput(
            source: AbilitySource.measured,
            nObs: 10,
            mean: 0.8,
          ),
          policy: const AbilityBandPolicy(minObservations: 0),
        ),
        throwsArgumentError,
      );
      expect(
        () => readAbilityBand(
          const AbilityBandInput(
            source: AbilitySource.measured,
            nObs: 10,
            mean: 0.8,
          ),
          policy: const AbilityBandPolicy(maxIntervalWidth: 0),
        ),
        throwsArgumentError,
      );
    });

    test('NaN 阈值 → ArgumentError', () {
      expect(
        () => readAbilityBand(
          const AbilityBandInput(
            source: AbilitySource.measured,
            nObs: 10,
            mean: 0.8,
            interval: AbilityInterval(lo: 0.78, hi: 0.82),
          ),
          policy: const AbilityBandPolicy(
            thresholds: AbilityBandThresholds(
              scale: AbilityBandScale.probability,
              s: double.nan,
              a: 0.75,
              b: 0.60,
              c: 0.40,
            ),
          ),
        ),
        throwsArgumentError,
      );
    });
  });
}
