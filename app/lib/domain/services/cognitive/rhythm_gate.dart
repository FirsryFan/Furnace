import 'dart:math' as math;

/// Pure Dart port of MindNet's **`rhythm.gate`** mechanism: the tier that
/// answers "现在适合做费力的事吗" — attention availability
/// `α(τ) = α0 · G_duty(τ) · G_vig(τ) · G_flow(t)`
/// (`docs/MODEL_v2_MATH.md` §5; reference `mechanisms/rhythm.gate.js`).
///
/// ## What this port computes
///
/// The reference hook actually wires two of the three factors:
///
/// * `G_duty` — the duty cycle `1[(τ mod T)/T < d]`, with the workload-adaptive
///   period `T_cycle = T0 · (1 + λ_L · load/4)` (§5.3);
/// * `G_vig` — `exp(-t_on / τ_vig)`, vigilance decaying since the last break
///   (§5.2).
///
/// `α0` and `G_flow` (§5.4) appear in the model document but the reference hook
/// never multiplies them into the gate, so this port does not invent them
/// either: a factor nobody installs is exactly the "同名不同模型" this codebase
/// refuses elsewhere.
///
/// ## What is refused, and why refusing is the honest choice
///
/// [RhythmMode.markov] needs a random draw (`ctx.rng()` — MindNet's seeded
/// mulberry32 in `src/core/rng.js`) to move between focused and wandering. That
/// PRNG is not part of this port, the same scope cut that makes `FastEngine`
/// throw when a temperature `T_ign > 0` needs a draw; a fixed deterministic
/// substitute would not be the model in the docs.
///
/// [RhythmMode.theta] is documented (§5.1: `1[cos(2πfτ+φ) > 0]`, f ≈ 6 Hz) but
/// the reference's own `openCountFor()` implements **only** duty and markov
/// (`mode === 'markov' ? cycle : Math.round(duty * clamp(vig) * cycle)`), so a
/// θ installation there silently behaves like duty. Porting that would be a
/// different model wearing the same name, so the mode is refused here.
///
/// ## Quirks reproduced on purpose
///
/// * `round.before` sizes the round with the **load** term, while `tick.gate`
///   rebuilds the phase period from `T0` **without** it. Under load a round can
///   therefore span more ticks than the pattern's period; the pattern simply
///   repeats inside the round.
/// * The open window always sits at the **start** of the cycle
///   (`phase < open`), so a round never opens with a closed tick.
/// Which of §5.1's three gates a [RhythmGateParams] asks for. Only
/// [RhythmMode.duty] can be installed — see the library comment for why
/// [RhythmMode.markov] and [RhythmMode.theta] are refused instead of silently
/// approximated.
enum RhythmMode { duty, markov, theta }

class RhythmGateParams {
  const RhythmGateParams({
    this.mode = RhythmMode.duty,
    this.t0Seconds = 1.0,
    this.tickMs = 250.0,
    this.duty = 0.5,
    this.pOff = 0.02,
    this.pOn = 0.08,
    this.lambdaLoad = 1.0,
    this.tauVigMinutes = 20.0,
  });

  /// Which of §5.1's three gates. Only [RhythmMode.duty] is installable.
  final RhythmMode mode;

  /// Base period `T0` in seconds. Reference default 1.0 s.
  final double t0Seconds;

  /// One tick in milliseconds. Reference default 250 ms (the four manifest
  /// self-checks are stated at 250 ms), which makes `T0` exactly 4 ticks.
  final double tickMs;

  /// Duty fraction `d` of `G_duty`. Reference default 0.5.
  final double duty;

  /// `P(专注→走神)` per tick. Reference default 0.02. **Only markov uses it**,
  /// and markov is refused, so it is carried for transcription honesty only.
  final double pOff;

  /// `P(走神→专注)` per tick. Reference default 0.08; the pair gives a 20%
  /// steady-state wandering share. Only markov uses it.
  final double pOn;

  /// Load adaptation slope `λ_L` of §5.3. Reference default 1.0.
  final double lambdaLoad;

  /// Vigilance time constant `τ_vig` in minutes. Reference default 20 min, so
  /// vigilance halves after ≈ 13.9 minutes of unbroken on-task time.
  final double tauVigMinutes;
}

/// One "how much of this round are we actually *on*" reading, i.e. the values
/// the reference hook publishes as `payload.rhythm`.
class RhythmCycle {
  const RhythmCycle({
    required this.cycleTicks,
    required this.load,
    required this.vigilance,
    required this.openTicks,
  });

  final int cycleTicks;
  final double load;
  final double vigilance;
  final int openTicks;

  /// This round's `α` as the engine's tick loop computes it
  /// (`openTicks / cycleTicks`) — the *only* channel through which the rhythm
  /// tier reaches the dynamics (§4.1: `a₁ = a* + (a − a*)·e^(−k·α)`).
  double get availability => cycleTicks == 0 ? 1 : openTicks / cycleTicks;

  Map<String, Object?> toJson() => <String, Object?>{
        'mode': 'duty',
        'cycle_ticks': cycleTicks,
        'load': load,
        'vigilance': vigilance,
        'open_ticks': openTicks,
        'availability': availability,
      };
}

/// The gate itself. One instance per engine run: [minutesOn] is state, exactly
/// like the reference's `store.onMinutes`.
class RhythmGate {
  RhythmGate({this.params = const RhythmGateParams()}) {
    switch (params.mode) {
      case RhythmMode.duty:
        break;
      case RhythmMode.markov:
        throw UnsupportedError(
          'rhythm.gate 的 markov 模式需要随机数（MindNet 的 mulberry32 PRNG），'
          '本移植没有接入：参见 FastEngine 在 T_ign > 0 时抛错的同一条纪律。'
          '要装它，得先把 src/core/rng.js 移植进来。',
        );
      case RhythmMode.theta:
        throw UnsupportedError(
          'rhythm.gate 的 theta 模式在参考实现里没有落地：'
          'mechanisms/rhythm.gate.js 的 openCountFor() 只算 duty 与 markov，'
          'θ 的 cos 采样只写在文档与 manifest 里。按 duty 静默处理就是'
          '"同名不同模型"，所以这里拒收。',
        );
    }
  }

  /// The `ref = 4` of §5.3's `T_cycle = T0·(1 + λ_L·load/ref)`: the direct
  /// access zone's capacity in activation units, i.e. the load at which the
  /// cycle is `T0·(1 + λ_L)`.
  static const double referenceLoad = 4.0;

  final RhythmGateParams params;

  double _onMinutes = 0;

  /// Unbroken on-task minutes accumulated through [advanceTick].
  double get minutesOn => _onMinutes;

  /// `G_vig(τ) = exp(-t_on / τ_vig)` (§5.2).
  double vigilanceFor({required double minutesOn}) =>
      math.exp(-minutesOn / params.tauVigMinutes);

  /// Vigilance right now.
  double get vigilance => vigilanceFor(minutesOn: _onMinutes);

  /// On-task minutes after which vigilance has halved (`τ_vig · ln 2`).
  double get halfVigilanceMinutes => params.tauVigMinutes * math.ln2;

  /// `round.before`: how many ticks this round lasts, given the current load
  /// (§5.3). `load` is the sum of activations of nodes at or above their
  /// ignition threshold, so it is in "activation units" — the same unit as
  /// `attention.capacity`'s `W_DAR`.
  int cycleTicksFor({required double load}) {
    final seconds =
        params.t0Seconds * (1 + params.lambdaLoad * (load / referenceLoad));
    return math.max(1, (seconds * 1000 / params.tickMs).round());
  }

  /// `openCountFor(cycle, vig)`: how many of [cycle] ticks are open.
  ///
  /// Duty mode only — see the library comment for markov and theta.
  int openCountFor({required int cycle, required double vigilance}) {
    final clamped = vigilance.clamp(0.0, 1.0);
    final want = (params.duty * clamped * cycle).round();
    return want.clamp(0, cycle);
  }

  /// The reference's `planFor(options, vig)`: the open window at the start of
  /// the cycle, as a `List<bool>` of length [cycle].
  List<bool> planFor({required int cycle, required double vigilance}) {
    final open = openCountFor(cycle: cycle, vigilance: vigilance);
    return <bool>[for (var i = 0; i < cycle; i += 1) i < open];
  }

  /// `tick.before`: one more tick of on-task time has passed.
  void advanceTick() {
    _onMinutes += params.tickMs / 60000;
  }

  /// `tick.gate` for absolute tick number [tick] (the JS kernel's `tick`, which
  /// has already been incremented for this tick).
  ///
  /// Returns `null` when the tick is open, otherwise the block reason the
  /// reference emits: `'vigilance_low'` below half vigilance, else
  /// `'off_phase'`.
  String? blockReasonFor({required int tick}) {
    // tick.gate rebuilds the period from T0 alone (no load term) - a quirk of
    // the reference, reproduced rather than fixed.
    final cycle =
        math.max(1, (params.t0Seconds * 1000 / params.tickMs).round());
    final vig = vigilance;
    final open = openCountFor(cycle: cycle, vigilance: vig);
    final phase = (tick - 1) % cycle;
    if (phase < open) {
      return null;
    }
    return vig < 0.5 ? 'vigilance_low' : 'off_phase';
  }

  /// The whole `round.before` step for an engine round starting now: the round's
  /// tick length plus the vigilance/plan it will run under. The caller walks
  /// [RhythmCycle.cycleTicks] ticks through [advanceTick] + [blockReasonFor],
  /// exactly like the reference's tick loop.
  RhythmCycle beginRound({required double load}) {
    final cycle = cycleTicksFor(load: load);
    final vig = vigilance;
    final open = openCountFor(cycle: cycle, vigilance: vig);
    return RhythmCycle(
      cycleTicks: cycle,
      load: load,
      vigilance: vig,
      openTicks: open,
    );
  }

  /// A copy with the same accumulated on-task time: the counterfactual planner
  /// clones an engine mid-run and must not reset the clock.
  RhythmGate copy() => RhythmGate(params: params).._onMinutes = _onMinutes;
}
