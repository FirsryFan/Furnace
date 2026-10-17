import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/reasoning/capability_profile.dart';

/// 一条样本：动作 + 风险（可空）。
CapabilityStepSample sample(String action, [double? risk]) =>
    CapabilityStepSample(actionType: action, stuckRisk: risk);

void main() {
  group('能力动作画像：按动作聚合，只信真有的读数', () {
    test('同一动作的步骤归到一起：条数、高风险条数、平均风险都算对', () {
      final readings = CapabilityProfile.of(<CapabilityStepSample>[
        sample('case_split', 0.8),
        sample('case_split', 0.2),
        sample('case_split', 0.7),
        sample('construct_example', 0.3),
      ]);

      final split = readings.firstWhere((r) => r.actionType == 'case_split');
      expect(split.stepCount, 3);
      expect(split.riskyStepCount, 2, reason: '0.8 与 0.7 过线（>= 0.6）');
      expect(split.avgStuckRisk, closeTo((0.8 + 0.2 + 0.7) / 3, 1e-9));
      expect(split.known, isTrue);

      final construct =
          readings.firstWhere((r) => r.actionType == 'construct_example');
      expect(construct.stepCount, 1);
      expect(construct.riskyStepCount, 0);
    });

    test('没有风险读数的步骤只算条数，不进平均（不把"没判断"当成 0）', () {
      final readings = CapabilityProfile.of(<CapabilityStepSample>[
        sample('invariant', 0.9),
        sample('invariant'),
        sample('invariant'),
      ]);

      final invariant = readings.single;
      expect(invariant.stepCount, 3);
      expect(invariant.riskyStepCount, 1);
      expect(invariant.avgStuckRisk, closeTo(0.9, 1e-9),
          reason: '两条没读数的不该把 0.9 摊薄成 0.3');
    });

    test('一条读数都没有的动作：平均风险是 null，排在最后', () {
      final readings = CapabilityProfile.of(<CapabilityStepSample>[
        sample('no_reading'),
        sample('case_split', 0.1),
      ]);

      expect(readings.map((r) => r.actionType).toList(), <String>[
        'case_split',
        'no_reading',
      ]);
      expect(readings.last.avgStuckRisk, isNull);
      expect(readings.last.known, isFalse,
          reason: '词表里要是没有这个 key，known 必须是 false');
    });

    test('排序：平均风险高的在前；平手看高风险条数，再看条数', () {
      final readings = CapabilityProfile.of(<CapabilityStepSample>[
        sample('a', 0.5),
        sample('b', 0.9),
        sample('c', 0.9),
        sample('c', 0.9),
      ]);

      expect(
          readings.map((r) => r.actionType).toList(), <String>['c', 'b', 'a'],
          reason: 'c 与 b 平均一样，c 的高风险条数更多');
    });

    test('未知动作按原串显示，不硬塞进已知动作', () {
      final readings = CapabilityProfile.of(<CapabilityStepSample>[
        sample('brand_new_move', 0.7),
      ]);

      final reading = readings.single;
      expect(reading.known, isFalse);
      expect(reading.label, 'brand_new_move', reason: '原样展示，不归类');
      expect(reading.avgStuckRisk, closeTo(0.7, 1e-9));
    });

    test('空输入 / 全是空动作：返回空列表，不编一行"暂无异常"', () {
      expect(CapabilityProfile.of(const <CapabilityStepSample>[]), isEmpty);
      expect(
        CapabilityProfile.of(<CapabilityStepSample>[sample('  ', 0.9)]),
        isEmpty,
      );
    });

    test('动作与风险原样带走：toJson 里能看出这条读数是从哪来的', () {
      final reading = CapabilityProfile.of(<CapabilityStepSample>[
        sample('sanity_check', 0.65),
      ]).single;
      final json = reading.toJson();
      expect(json['action_type'], 'sanity_check');
      expect(json['step_count'], 1);
      expect(json['risky_step_count'], 1);
      expect(json['known'], isTrue);
    });
  });
}
