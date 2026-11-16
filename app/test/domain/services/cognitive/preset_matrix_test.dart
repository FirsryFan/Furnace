import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/cognitive/preset_matrix.dart';

void main() {
  test('measured 行读出 mean/uncertainty/n_obs，preset_global 只给全局先验', () {
    final seed = PresetMatrixSeed.fromJson(<String, Object?>{
      'knowledge': <String, Object?>{
        'measured': <Object?>[
          <String, Object?>{
            'kp_id': 'kp-1',
            'mastery': <String, Object?>{
              'mean': 0.6,
              'intervals': <String, Object?>{
                '95': <Object?>[0.2, 0.9],
              },
            },
            'evidence': <String, Object?>{'n_obs': 3},
          },
        ],
        'preset_global': <Object?>[
          <String, Object?>{
            'band': 'S',
            'mean': 0.9,
            'uncertainty': 0.15,
          },
          <String, Object?>{
            'band': 'A',
            'mean': 0.75,
            'uncertainty': 0.15,
          },
        ],
      },
      'missing_measured_kp_ids': <Object?>['kp-gone'],
    });

    expect(seed.measuredCount, 1);
    expect(seed.measuredFor('kp-1')!.mean, 0.6);
    expect(seed.measuredFor('kp-1')!.uncertainty, closeTo(0.35, 1e-9));
    expect(seed.measuredFor('kp-1')!.nObs, 3);
    expect(seed.measuredFor('kp-1')!.isMeasured, isTrue);
    expect(seed.measuredFor('kp-2'), isNull);
    expect(seed.presetMeanFor('S'), 0.9);
    expect(seed.presetMeanFor('D'), isNull);
    expect(seed.missingMeasuredIds, <String>['kp-gone']);
  });

  test('preset_global 不是 measured：不伪造 n_obs/来源', () {
    final seed = PresetMatrixSeed.fromJson(<String, Object?>{
      'knowledge': <String, Object?>{
        'preset_global': <Object?>[
          <String, Object?>{'band': 'B', 'mean': 0.6, 'uncertainty': 0.15},
        ],
      },
    });

    expect(seed.measuredCount, 0);
    expect(seed.hasGlobalPreset, isTrue);
    expect(seed.presetMeanFor('B'), 0.6);
    expect(seed.measuredFor('anything'), isNull);
  });
}
