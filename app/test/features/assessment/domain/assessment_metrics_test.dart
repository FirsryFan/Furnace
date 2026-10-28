import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/features/assessment/domain/assessment_metrics.dart';
import 'package:furnace/features/assessment/domain/assessment_models.dart';

TrialResult _trial({
  int index = 0,
  int block = 0,
  int? rtMs,
  bool? correct,
  bool practice = false,
  Map<String, Object?> stimulus = const <String, Object?>{},
}) {
  return TrialResult(
    trialIndex: index,
    blockIndex: block,
    rtMs: rtMs,
    correct: correct,
    isPractice: practice,
    stimulus: stimulus,
  );
}

void main() {
  group('反应时中位数与四分位距', () {
    test('空输入返回 null', () {
      expect(rtMedian(const <TrialResult>[]), isNull);
      expect(rtIqr(const <TrialResult>[]), isNull);
    });

    test('单个 RT 返回本身，且不足两个时 IQR 为 null', () {
      final trials = <TrialResult>[_trial(rtMs: 320)];
      expect(rtMedian(trials), 320);
      expect(rtIqr(trials), isNull);
    });

    test('偶数个 RT 中位数线性插值', () {
      final trials = <TrialResult>[
        _trial(rtMs: 400),
        _trial(rtMs: 100),
        _trial(rtMs: 300),
        _trial(rtMs: 200),
      ];
      expect(rtMedian(trials), 250);
    });

    test('IQR = Q3 - Q1（线性插值）', () {
      final trials = <TrialResult>[
        _trial(rtMs: 100),
        _trial(rtMs: 200),
        _trial(rtMs: 300),
        _trial(rtMs: 400),
      ];
      expect(rtIqr(trials), closeTo(150, 1e-9));
    });

    test('练习 trial 与没有 RT 的 trial 不参与', () {
      final trials = <TrialResult>[
        _trial(rtMs: 900, practice: true),
        _trial(rtMs: null),
        _trial(rtMs: 200),
      ];
      expect(rtMedian(trials), 200);
    });
  });

  group('正确率', () {
    test('空输入返回 null', () {
      expect(accuracy(const <TrialResult>[]), isNull);
    });

    test('没有判定结果的 trial 被跳过', () {
      final trials = <TrialResult>[
        _trial(rtMs: 200, correct: null),
        _trial(rtMs: 200, correct: true),
        _trial(rtMs: 200, correct: false),
        _trial(rtMs: 200, correct: true),
      ];
      expect(accuracy(trials), closeTo(2 / 3, 1e-9));
    });

    test('练习 trial 不计入', () {
      final trials = <TrialResult>[
        _trial(correct: false, practice: true),
        _trial(correct: true),
        _trial(correct: true),
      ];
      expect(accuracy(trials), 1.0);
    });

    test('全部正确为 1.0，全部错误为 0.0', () {
      expect(accuracy(<TrialResult>[_trial(correct: true)]), 1.0);
      expect(accuracy(<TrialResult>[_trial(correct: false)]), 0.0);
    });
  });

  group('信号检测论', () {
    final mixed = <TrialResult>[
      _trial(index: 0, correct: true, stimulus: const {'is_target': true}),
      _trial(index: 1, correct: false, stimulus: const {'is_target': true}),
      _trial(index: 2, correct: true, stimulus: const {'is_target': false}),
      _trial(index: 3, correct: false, stimulus: const {'is_target': false}),
    ];

    test('命中率与虚报率按 stimulus.is_target 分组', () {
      expect(hitRate(mixed), 0.5);
      expect(falseAlarmRate(mixed), 0.5);
      expect(dPrime(mixed), closeTo(0, 1e-9));
    });

    test('缺目标或非目标 trial 时返回 null', () {
      final onlyTargets = <TrialResult>[
        _trial(correct: true, stimulus: const {'is_target': true}),
      ];
      expect(hitRate(onlyTargets), 1.0);
      expect(falseAlarmRate(onlyTargets), isNull);
      expect(dPrime(onlyTargets), isNull);
    });

    test('d_prime 已知数值（3/4 命中、1/5 虚报）', () {
      final d = dPrimeFromCounts(
        hits: 3,
        targets: 4,
        falseAlarms: 1,
        nonTargets: 5,
      );
      expect(d, closeTo(1.1989, 0.01));
    });

    test('完美表现在 log-linear 校正后仍是有限正值', () {
      final d = dPrimeFromCounts(
        hits: 4,
        targets: 4,
        falseAlarms: 0,
        nonTargets: 4,
      );
      expect(d, closeTo(2.5631, 0.01));
    });

    test('d_prime 缺一组计数返回 null', () {
      expect(
        dPrimeFromCounts(hits: 1, targets: 2, falseAlarms: 0, nonTargets: 0),
        isNull,
      );
      expect(
        dPrimeFromCounts(hits: 0, targets: 0, falseAlarms: 0, nonTargets: 2),
        isNull,
      );
    });

    test('log-linear 校正公式与负数净化', () {
      expect(logLinearRate(successes: 3, trials: 4), 0.7);
      expect(logLinearRate(successes: 1, trials: 5), 0.25);
      expect(logLinearRate(successes: 0, trials: 0), 0.5);
      expect(logLinearRate(successes: -5, trials: -1), 0.5);
    });

    test('自定义 isTarget 回调生效', () {
      final trials = <TrialResult>[
        _trial(correct: true, stimulus: const {'go': true}),
        _trial(correct: false, stimulus: const {'go': true}),
        _trial(correct: true, stimulus: const {'go': false}),
      ];
      expect(hitRate(trials, isTarget: (t) => t.stimulus['go'] == true), 0.5);
    });

    test('练习 trial 不计入命中/虚报', () {
      final trials = <TrialResult>[
        _trial(
            correct: false,
            practice: true,
            stimulus: const {'is_target': true}),
        _trial(correct: true, stimulus: const {'is_target': true}),
      ];
      expect(hitRate(trials), 1.0);
    });
  });

  group('go/no-go 反应时代价', () {
    test('go 中位 - no-go 中位 / no-go 中位', () {
      final trials = <TrialResult>[
        _trial(rtMs: 600, stimulus: const {'is_target': true}),
        _trial(rtMs: 600, stimulus: const {'is_target': true}),
        _trial(rtMs: 500, stimulus: const {'is_target': false}),
        _trial(rtMs: 500, stimulus: const {'is_target': false}),
      ];
      expect(rtCost(trials), closeTo(0.2, 1e-9));
    });

    test('缺一组或 no-go 中位数为 0 返回 null', () {
      final noGoOnly = <TrialResult>[
        _trial(rtMs: 500, stimulus: const {'is_target': false}),
      ];
      expect(rtCost(noGoOnly), isNull);
      final zeroNoGo = <TrialResult>[
        _trial(rtMs: 600, stimulus: const {'is_target': true}),
        _trial(rtMs: 0, stimulus: const {'is_target': false}),
      ];
      expect(rtCost(zeroNoGo), isNull);
    });

    test('自定义 isTarget 回调生效', () {
      final trials = <TrialResult>[
        _trial(rtMs: 600, stimulus: const {'go': true}),
        _trial(rtMs: 400, stimulus: const {'go': false}),
      ];
      expect(
        rtCost(trials, isTarget: (t) => t.stimulus['go'] == true),
        closeTo(0.5, 1e-9),
      );
    });
  });

  group('稳定跨度', () {
    test('连续两次同跨度答对取该跨度', () {
      final trials = <TrialResult>[
        _trial(correct: true, stimulus: const {'span': 3}),
        _trial(correct: true, stimulus: const {'span': 3}),
      ];
      expect(stableSpan(trials), 3);
    });

    test('取满足条件的最高跨度', () {
      final trials = <TrialResult>[
        _trial(correct: true, stimulus: const {'span': 5}),
        _trial(correct: true, stimulus: const {'span': 5}),
        _trial(correct: true, stimulus: const {'span': 3}),
        _trial(correct: true, stimulus: const {'span': 3}),
      ];
      expect(stableSpan(trials), 5);
    });

    test('跨度切换打断连续计数', () {
      final trials = <TrialResult>[
        _trial(correct: true, stimulus: const {'span': 4}),
        _trial(correct: true, stimulus: const {'span': 3}),
      ];
      expect(stableSpan(trials), isNull);
    });

    test('requiredConsecutive 可调', () {
      final trials = <TrialResult>[
        _trial(correct: true, stimulus: const {'span': 4}),
        _trial(correct: true, stimulus: const {'span': 4}),
        _trial(correct: true, stimulus: const {'span': 4}),
      ];
      expect(stableSpan(trials, requiredConsecutive: 3), 4);
      expect(stableSpan(trials, requiredConsecutive: 4), isNull);
    });

    test('错误 trial 与缺跨度的 trial 都会打断', () {
      final brokenByWrong = <TrialResult>[
        _trial(correct: true, stimulus: const {'span': 4}),
        _trial(correct: false, stimulus: const {'span': 4}),
        _trial(correct: true, stimulus: const {'span': 4}),
      ];
      expect(stableSpan(brokenByWrong), isNull);
      final brokenByMissing = <TrialResult>[
        _trial(correct: true, stimulus: const {'span': 4}),
        _trial(correct: true),
        _trial(correct: true, stimulus: const {'span': 4}),
      ];
      expect(stableSpan(brokenByMissing), isNull);
    });

    test('自定义 spanOf 生效（response 里的跨度）', () {
      final trials = <TrialResult>[
        const TrialResult(
          trialIndex: 0,
          blockIndex: 0,
          correct: true,
          response: {'span': 6},
        ),
        const TrialResult(
          trialIndex: 1,
          blockIndex: 0,
          correct: true,
          response: {'span': 6},
        ),
      ];
      expect(
        stableSpan(trials, spanOf: (t) {
          final value = t.response['span'];
          return value is int ? value : null;
        }),
        6,
      );
    });

    test('练习 trial 不计入', () {
      final trials = <TrialResult>[
        _trial(correct: true, practice: true, stimulus: const {'span': 9}),
        _trial(correct: true, stimulus: const {'span': 3}),
        _trial(correct: true, stimulus: const {'span': 3}),
      ];
      expect(stableSpan(trials), 3);
    });
  });

  group('反应时随块斜率（Theil-Sen）', () {
    test('按块中位数取所有块对斜率的中位数', () {
      final trials = <TrialResult>[
        _trial(block: 0, rtMs: 100),
        _trial(block: 1, rtMs: 300),
        _trial(block: 2, rtMs: 200),
      ];
      expect(rtSlope(trials), closeTo(50, 1e-9));
    });

    test('少于两个块返回 null', () {
      final trials = <TrialResult>[
        _trial(block: 0, rtMs: 100),
        _trial(block: 0, rtMs: 200),
      ];
      expect(rtSlope(trials), isNull);
    });

    test('缺 RT 的 trial 与练习 trial 不参与', () {
      final trials = <TrialResult>[
        _trial(block: 0, rtMs: 100),
        _trial(block: 0, rtMs: null),
        _trial(block: 1, rtMs: 200),
        _trial(block: 1, rtMs: 300, practice: true),
      ];
      expect(rtSlope(trials), closeTo(100, 1e-9));
    });
  });

  group('方差漂移与决策漂移', () {
    test('后段方差是前段 4 倍', () {
      final trials = <TrialResult>[
        _trial(rtMs: 100),
        _trial(rtMs: 200),
        _trial(rtMs: 200),
        _trial(rtMs: 400),
      ];
      expect(varianceDrift(trials), closeTo(4.0, 1e-9));
    });

    test('少于四个 RT 返回 null', () {
      final trials = <TrialResult>[
        _trial(rtMs: 100),
        _trial(rtMs: 200),
        _trial(rtMs: 300),
      ];
      expect(varianceDrift(trials), isNull);
      expect(decisionDrift(trials), isNull);
    });

    test('前段方差为 0 返回 null', () {
      final trials = <TrialResult>[
        _trial(rtMs: 100),
        _trial(rtMs: 100),
        _trial(rtMs: 200),
        _trial(rtMs: 400),
      ];
      expect(varianceDrift(trials), isNull);
    });

    test('决策漂移 = 后段中位 / 前段中位', () {
      final trials = <TrialResult>[
        _trial(rtMs: 100),
        _trial(rtMs: 100),
        _trial(rtMs: 200),
        _trial(rtMs: 200),
      ];
      expect(decisionDrift(trials), closeTo(2.0, 1e-9));
    });

    test('前段中位数为 0 返回 null', () {
      final trials = <TrialResult>[
        _trial(rtMs: 0),
        _trial(rtMs: 0),
        _trial(rtMs: 100),
        _trial(rtMs: 100),
      ];
      expect(decisionDrift(trials), isNull);
    });
  });

  group('切换代价与冲突代价', () {
    test('切换代价 = switch 中位 - repeat 中位', () {
      final trials = <TrialResult>[
        _trial(rtMs: 700, stimulus: const {'switch': true}),
        _trial(rtMs: 700, stimulus: const {'switch': true}),
        _trial(rtMs: 500, stimulus: const {'switch': false}),
        _trial(rtMs: 500, stimulus: const {'switch': false}),
      ];
      expect(switchCost(trials), closeTo(200, 1e-9));
    });

    test('切换代价缺一组返回 null', () {
      final trials = <TrialResult>[
        _trial(rtMs: 700, stimulus: const {'switch': true}),
      ];
      expect(switchCost(trials), isNull);
    });

    test('冲突代价 = 不一致中位 - 一致中位', () {
      final trials = <TrialResult>[
        _trial(rtMs: 600, stimulus: const {'congruent': false}),
        _trial(rtMs: 600, stimulus: const {'congruent': false}),
        _trial(rtMs: 500, stimulus: const {'congruent': true}),
        _trial(rtMs: 500, stimulus: const {'congruent': true}),
      ];
      expect(conflictCost(trials), closeTo(100, 1e-9));
    });

    test('自定义选择器生效', () {
      final trials = <TrialResult>[
        _trial(rtMs: 650, stimulus: const {'kind': 'switch'}),
        _trial(rtMs: 450, stimulus: const {'kind': 'repeat'}),
      ];
      expect(
        switchCost(trials,
            isSwitchTrial: (t) => t.stimulus['kind'] == 'switch'),
        closeTo(200, 1e-9),
      );
    });
  });

  test('所有指标确定性且不修改输入', () {
    final trials = <TrialResult>[
      _trial(rtMs: 300, correct: true, stimulus: const {'is_target': true}),
      _trial(rtMs: 500, correct: false, stimulus: const {'is_target': false}),
    ];
    final snapshot = List<TrialResult>.of(trials);
    expect(rtMedian(trials), rtMedian(trials));
    expect(accuracy(trials), accuracy(trials));
    expect(hitRate(trials), hitRate(trials));
    expect(trials, snapshot);
  });
}
