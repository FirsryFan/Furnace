import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/cognitive/fast_engine.dart';
import 'package:furnace/domain/services/cognitive/rhythm_gate.dart';

/// The four `check()`s of `mechanisms/rhythm.gate.js`'s manifest, plus the
/// engine-level wiring: a gate that is not installed must leave the port
/// bit-for-bit comparable with the vectors, and one that is installed must
/// actually move `availability`.
void main() {
  group('manifest self-checks of rhythm.gate', () {
    test('① T0=1s / tick=250ms / duty=0.5 ⇒ a 4-tick cycle with exactly 2 on',
        () {
      final gate = RhythmGate();
      expect(gate.cycleTicksFor(load: 0), 4);
      final plan = gate.planFor(cycle: 4, vigilance: 1);
      expect(plan.length, 4);
      expect(plan.where((open) => open).length, 2);
      // The open window sits at the start of the cycle (reference quirk).
      expect(plan, <bool>[true, true, false, false]);
    });

    test('② λ_L=1: load 0→4 stretches the cycle 4→8 ticks (1.00→2.00 s)', () {
      final gate = RhythmGate();
      expect(gate.cycleTicksFor(load: 0) * 250 / 1000, 1.0);
      expect(gate.cycleTicksFor(load: 4) * 250 / 1000, 2.0);
      expect(gate.cycleTicksFor(load: 2), 6);
      // The reference rounds up to at least one tick.
      expect(
        RhythmGate(params: const RhythmGateParams(t0Seconds: 0.01))
            .cycleTicksFor(load: 0),
        1,
      );
    });

    test('③ vigilance halves the window: vig=0.5 ⇒ 1 of 4, vig=0 ⇒ none', () {
      final gate = RhythmGate();
      expect(gate.openCountFor(cycle: 4, vigilance: 1.0), 2);
      expect(gate.openCountFor(cycle: 4, vigilance: 0.5), 1);
      expect(gate.openCountFor(cycle: 4, vigilance: 0.0), 0);
    });

    test('③b G_vig = exp(-t_on/τ_vig): 1/e 在 20 分钟，半衰 ≈ 13.9 分钟', () {
      final gate = RhythmGate();
      expect(gate.vigilanceFor(minutesOn: 0), 1.0);
      expect(gate.vigilanceFor(minutesOn: 20), closeTo(1 / math.e, 1e-12));
      expect(gate.halfVigilanceMinutes, closeTo(20 * math.ln2, 1e-12));
      expect(
        gate.vigilanceFor(minutesOn: gate.halfVigilanceMinutes),
        closeTo(0.5, 1e-12),
      );
    });

    test('④ ablation duty=1 ⇒ every tick is on (still scaled by vigilance)',
        () {
      final all = RhythmGate(params: const RhythmGateParams(duty: 1));
      expect(all.planFor(cycle: 4, vigilance: 1).every((open) => open), isTrue);
      expect(all.openCountFor(cycle: 8, vigilance: 1), 8);
      expect(all.openCountFor(cycle: 4, vigilance: 0.5), 2,
          reason: 'duty=1 关掉的是占空比，不是警觉衰减');
    });

    test('markov 与 theta 都被显式拒收，理由写在异常里', () {
      expect(
        () =>
            RhythmGate(params: const RhythmGateParams(mode: RhythmMode.markov)),
        throwsA(isA<UnsupportedError>().having(
          (e) => e.message,
          'message',
          contains('PRNG'),
        )),
        reason: 'markov 需要随机数，静默替换就是同名不同模型',
      );
      expect(
        () =>
            RhythmGate(params: const RhythmGateParams(mode: RhythmMode.theta)),
        throwsA(isA<UnsupportedError>().having(
          (e) => e.message,
          'message',
          contains('openCountFor'),
        )),
        reason: '参考实现根本没实现 θ 采样，按 duty 处理同样是同名不同模型',
      );
    });

    test('tick.gate: 开口在周期开头，警觉低于一半时理由换成 vigilance_low', () {
      final fresh = RhythmGate();
      expect(
        [for (var t = 1; t <= 4; t += 1) fresh.blockReasonFor(tick: t)],
        <String?>[null, null, 'off_phase', 'off_phase'],
      );
      // τ_vig = 0.1 分钟 ⇒ 24 个 tick（0.25 秒/个，合 6 秒）后 vig = 1/e。
      final tired =
          RhythmGate(params: const RhythmGateParams(tauVigMinutes: 0.1));
      for (var i = 0; i < 24; i += 1) {
        tired.advanceTick();
      }
      expect(tired.minutesOn, closeTo(0.1, 1e-12));
      expect(tired.vigilance, closeTo(1 / math.e, 1e-12));
      // open = round(0.5 · 0.3679 · 4) = 1
      expect(
        [for (var t = 1; t <= 4; t += 1) tired.blockReasonFor(tick: t)],
        <String?>[null, 'vigilance_low', 'vigilance_low', 'vigilance_low'],
      );
    });

    test('round.before 的整轮读数（RhythmCycle）按负荷定周期、按警觉开窗', () {
      final cycle = RhythmGate().beginRound(load: 4);
      expect(cycle.cycleTicks, 8);
      expect(cycle.openTicks, 4);
      expect(cycle.availability, 0.5);
      expect(cycle.toJson()['open_ticks'], 4);
      expect(cycle.toJson()['mode'], 'duty');
      // 周期变长时窗口是「前一半 tick」，不是前一半时间的一半
      expect(cycle.vigilance, 1.0);
    });

    test('copy() 保住已积累的 on-task 时间（反事实克隆不该重置警觉）', () {
      final gate = RhythmGate();
      for (var i = 0; i < 24; i += 1) {
        gate.advanceTick();
      }
      final copy = gate.copy();
      expect(copy.minutesOn, gate.minutesOn);
      expect(copy.vigilance, gate.vigilance);
      copy.advanceTick();
      expect(gate.minutesOn, isNot(copy.minutesOn));
    });
  });

  group('rhythm.gate 接进 FastEngine', () {
    // `T_ign = 0` 是硬阈值分支：本 port 在 (0,1) 的点火概率上会**抛错**
    // （mulberry32 PRNG 未移植），所以测试得像向量一样把它钉成 0。
    const moduleDefaults = <String, Object?>{
      'dynamics.shunting': <String, Object?>{},
      'attention.capacity': <String, Object?>{},
      'attention.ignition': <String, Object?>{'T_ign': 0.0},
      'context.goal': <String, Object?>{},
      'rhythm.gate': <String, Object?>{},
    };

    FastEngine build({
      required bool withGate,
      Map<String, Object?> overrides = const <String, Object?>{},
    }) {
      final ids = <String>[
        FastMechanisms.shunting,
        FastMechanisms.capacity,
        FastMechanisms.ignition,
        FastMechanisms.goal,
        if (withGate) FastMechanisms.rhythm,
      ];
      return FastEngine(
        graph: FastGraph.fromSpec(
          <String, Object?>{
            'nodes': <Object?>[
              <String, Object?>{
                'id': 'A',
                'name': '起点',
                'type': 'knowledge',
                'ms': 0.9
              },
              <String, Object?>{
                'id': 'B',
                'name': '中间',
                'type': 'knowledge',
                'ms': 0.9
              },
              <String, Object?>{
                'id': 'C',
                'name': '目标',
                'type': 'knowledge',
                'ms': 0.7
              },
            ],
            'edges': <Object?>[
              <String, Object?>{'id': 'e1', 'from': 'A', 'to': 'B', 'ls': 0.9},
              <String, Object?>{'id': 'e2', 'from': 'B', 'to': 'C', 'ls': 0.9},
            ],
          },
          currentRealTime: 0,
        ),
        mechanisms: FastMechanisms.fromModuleDefaults(
          moduleDefaults,
          ids: ids,
          overrides: overrides,
        ),
        overrides: overrides,
      )..startDiffusion(<String>['A'], <String>['C']);
    }

    test('不装是默认：availability 恰好 1、周期 1（对拍向量之所以还成立）', () {
      final engine = build(withGate: false);
      final round = engine.runRounds(1).single;
      expect(engine.rhythmInstalled, isFalse);
      expect(round.availability, 1.0);
      expect(round.cycleTicks, 1);
    });

    test('装上之后同一次扩散真的变了：availability < 1 且激活不同', () {
      final off = build(withGate: false).runRounds(1).single;
      final on = build(withGate: true).runRounds(1).single;

      // 起点 A 的激活（=1）在阈值之上，所以 round.before 手上是有负荷的：
      // load = 1 ⇒ T_cycle = T0·(1 + load/4) = 1.25 s ⇒ 5 tick。
      expect(on.cycleTicks, 5);
      expect(on.availability, closeTo(3 / 5, 1e-12),
          reason: 'duty=0.5 × vig=1 ⇒ 5 tick 里 3 个在（round(2.5) 向远离零取整）');
      expect(off.availability, 1.0);
      // availability 是节律影响动力学的唯一通道：同一张图、同一次驱动，
      // 亚阈/激活的落点因此不同（§4.1 的 a₁ = a* + (a−a*)·e^(−k·α)）。
      // 起点 A 不做探针：它是被夹住的起点（两条路都停在 1.0）。
      expect(on.a['B'], isNot(closeTo(off.a['B']!, 1e-12)));
    });

    test('消融 duty=1：availability 又回到 1，激活与不装时逐位相同', () {
      final off = build(withGate: false).runRounds(1).single;
      final on = build(
        withGate: true,
        overrides: const <String, Object?>{'rhythm.gate.duty': 1.0},
      ).runRounds(1).single;
      expect(on.availability, 1.0);
      expect(on.a, off.a);
      expect(on.q, off.q);
      expect(on.conscious, off.conscious);
    });

    test('duty=0 ⇒ availability=0，原本不可达的「完全不在」分支真的被走到', () {
      final absent = build(
        withGate: true,
        overrides: const <String, Object?>{'rhythm.gate.duty': 0.0},
      ).runRounds(1).single;
      final present = build(withGate: false).runRounds(1).single;
      expect(absent.availability, 0.0);
      expect(absent.conscious, isEmpty, reason: 'α=0 时再强的线索也进不了意识（§4.5）');
      expect(present.conscious, isNotEmpty, reason: '同一张图不装门的时候是会点火的');
      // 到不了意识的都留在亚阈，且不是被"丢掉"。
      expect(absent.subconscious, isNotEmpty);
    });

    test('警觉真的会随时间关窗：τ_vig 调小后 availability 掉下来', () {
      final fresh = build(withGate: true).runRounds(1).single;
      final tired = build(
        withGate: true,
        overrides: const <String, Object?>{'rhythm.gate.tau_vig_minutes': 0.02},
      ).runRounds(1).single;
      expect(tired.availability, lessThan(fresh.availability),
          reason: '同一轮、同样的 duty，只有警觉不同');
    });

    test('克隆保住节律时钟（反事实规划不该把警觉清零）', () {
      final engine = build(withGate: true);
      engine.runRounds(1);
      final clone = engine.clone();
      expect(clone.rhythmInstalled, isTrue);
      expect(clone.rhythmGate!.minutesOn, engine.rhythmGate!.minutesOn);
    });
  });
}
