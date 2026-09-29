/// Dart port of MindNet's DSR memory layer (`mechanisms/memory.dsr.js`).
///
/// Why a port rather than a bridge: MindNet is a Node package, and Android has
/// no Node runtime, so "call it" is impossible on the platform this app is
/// mainly for. The contract agrees on a port and supplies conformance vectors
/// to prove it (`docs/MINDNET_CONTRACT.md` §6.1/§6.2).
///
/// **Provenance**: ported from the `c624884` snapshot, which is the revision the
/// conformance vectors were generated against. The MindNet repository has moved
/// on since; that is fine and expected - the vectors are the contract, and
/// `mindnet_dsr_conformance_test.dart` fails if this port drifts from them.
///
/// Units matter and are easy to get wrong: **`S` and `t` are HOURS here**,
/// while `FsrsScheduler` works in DAYS. `curveC`/`psi` are the same curve in
/// both (`gamma = -w20`, `c` identical), so only the boundary converts.
///
/// This file is deliberately pure: no database, no clock, no Flutter. `u` (the
/// "now" in hours) is always passed in, exactly as the JS does.
library;

import 'dart:math' as math;

/// The tunable constants, matching MindNet's `PARAMS` defaults.
///
/// Held in one object rather than as bare globals because the contract's
/// stability promise is explicit: **default parameter values are the one thing
/// that is allowed to change between MindNet versions, so they must never be
/// hard-coded into call sites** (MINDNET_CONTRACT §6.6). Reading them from here
/// keeps that promise cheap.
class DsrParams {
  const DsrParams({
    this.decayModel = DsrDecayModel.power,
    this.gamma = 0.1542,
    this.beta = 0.1367,
    this.eta = 1.0461,
    this.kappa = 8.01921,
    this.kappaRereadRatio = 0.1,
    this.kappaSavings = 0.5,
    this.cR0 = 0.05,
    this.cSigma = 0.5,
    this.d1 = 0.1,
    this.d2 = 0.5,
    this.d0 = 5.1618,
    this.failTauHours = 720,
    this.legacyK = 24,
  });

  /// Builds from a `module_defaults` map as found in the conformance vectors,
  /// so a test can drive the port from the published numbers instead of
  /// duplicating them.
  factory DsrParams.fromJson(Map<String, Object?> json) {
    double num_(String key, double fallback) {
      final value = json[key];
      if (value is num) {
        return value.toDouble();
      }
      return fallback;
    }

    return DsrParams(
      decayModel: json['decay_model'] == 'exponential'
          ? DsrDecayModel.exponential
          : DsrDecayModel.power,
      gamma: num_('gamma', 0.1542),
      beta: num_('beta', 0.1367),
      eta: num_('eta', 1.0461),
      kappa: num_('kappa', 8.01921),
      kappaRereadRatio: num_('kappa_reread_ratio', 0.1),
      kappaSavings: num_('kappa_savings', 0.5),
      cR0: num_('c_R0', 0.05),
      cSigma: num_('c_Sigma', 0.5),
      d1: num_('d1', 0.1),
      d2: num_('d2', 0.5),
      d0: num_('D0', 5.1618),
      failTauHours: num_('fail_tau_hours', 720),
      legacyK: num_('legacy_k', 24),
    );
  }

  final DsrDecayModel decayModel;
  final double gamma;
  final double beta;
  final double eta;
  final double kappa;
  final double kappaRereadRatio;
  final double kappaSavings;
  final double cR0;
  final double cSigma;
  final double d1;
  final double d2;
  final double d0;
  final double failTauHours;
  final double legacyK;

  /// FSRS-4.5's post-lapse stability shape (w11-w14 in MindNet.
  static const double lapseCf = 2.1072;
  static const double lapseGammaD = 0.0793;
  static const double lapseGammaS = 0.3246;
  static const double lapseGammaR = 1.587;

  static const double dMin = 1;
  static const double dMax = 10;
}

enum DsrDecayModel { power, exponential }

/// The slow state of one node ("bag" in the JS).
///
/// Field names follow MindNet so the two can be compared line by line; the
/// unusual ones are explained rather than renamed, because a rename here would
/// make the conformance diff unreadable.
class DsrState {
  DsrState({
    required this.r0,
    required this.s,
    required this.sigma,
    required this.d,
    this.n = 0,
    this.f = 0,
    this.lastFail,
    required this.lastReview,
    List<DsrHistoryEntry>? history,
    required this.initializedAt,
  }) : history = history ?? <DsrHistoryEntry>[];

  /// Encoding strength / ceiling. `R = R0 * psi(t / S)`, so `R0` is the most
  /// retrievable the item can be, and `S` is "hours until R falls to 0.9 * R0".
  double r0;

  /// Stability, in hours.
  double s;

  /// Storage strength (Bjork's savings effect). Only ever grows.
  double sigma;

  /// Difficulty, 1..10.
  double d;

  /// Successful retrieval count.
  int n;

  /// Undecayed failure count; the effective evidence decays from [lastFail].
  double f;

  /// Real time (hours since epoch) of the last failure, or null.
  double? lastFail;

  /// Real time (hours since epoch) of the last review.
  double lastReview;

  List<DsrHistoryEntry> history;

  final double initializedAt;

  /// Lazily initialises a state exactly as `ensureState` does when `ms` is the
  /// only thing known about an item.
  factory DsrState.initial({
    required double now,
    double? ms,
    DsrParams params = const DsrParams(),
    double? lastReview,
  }) {
    final r0 = (ms != null && ms > 0) ? math.min(1.0, ms) : 0.8;
    return DsrState(
      r0: r0,
      // The v1.1 equivalence: S = k * R0.
      s: params.legacyK * r0,
      sigma: r0,
      d: params.d0,
      lastReview: lastReview ?? now,
      initializedAt: now,
    );
  }

  DsrState copy() => DsrState(
        r0: r0,
        s: s,
        sigma: sigma,
        d: d,
        n: n,
        f: f,
        lastFail: lastFail,
        lastReview: lastReview,
        history: [...history],
        initializedAt: initializedAt,
      );

  Map<String, Object?> toJson() => {
        'R0': r0,
        'S': s,
        'Sigma': sigma,
        'D': d,
        'N': n,
        'F': f,
        'lastFail': lastFail,
        'lastReview': lastReview,
        'history': [for (final h in history) h.toJson()],
        'initializedAt': initializedAt,
      };

  static DsrState fromJson(Map<String, Object?> json) {
    double d(String key, [double fallback = 0]) {
      final value = json[key];
      return value is num ? value.toDouble() : fallback;
    }

    return DsrState(
      r0: d('R0', 0.8),
      s: d('S', 19.2),
      sigma: d('Sigma', 0.8),
      d: d('D', 5.1618),
      n: (json['N'] as num?)?.toInt() ?? 0,
      f: d('F'),
      lastFail: (json['lastFail'] as num?)?.toDouble(),
      lastReview: d('lastReview'),
      history: [
        for (final raw in (json['history'] as List?) ?? const [])
          if (raw is Map)
            DsrHistoryEntry(
              u: (raw['u'] as num?)?.toDouble() ?? 0,
              type: raw['type'] as String? ?? '',
              r: (raw['R'] as num?)?.toDouble() ?? 0,
              s: (raw['S'] as num?)?.toDouble() ?? 0,
              grade: (raw['grade'] as num?)?.toInt() ?? 0,
            ),
      ],
      initializedAt: d('initializedAt'),
    );
  }
}

class DsrHistoryEntry {
  const DsrHistoryEntry({
    required this.u,
    required this.type,
    required this.r,
    required this.s,
    required this.grade,
  });

  final double u;
  final String type;
  final double r;
  final double s;
  final int grade;

  Map<String, Object?> toJson() =>
      {'u': u, 'type': type, 'R': r, 'S': s, 'grade': grade};
}

enum DsrEventType {
  retrievalSuccess('retrieval_success'),
  reread('reread'),
  retrievalFailureFeedback('retrieval_failure_feedback'),
  lapse('lapse');

  const DsrEventType(this.id);
  final String id;

  static DsrEventType fromId(String? id) => switch (id) {
        'reread' => DsrEventType.reread,
        'retrieval_failure_feedback' => DsrEventType.retrievalFailureFeedback,
        'lapse' => DsrEventType.lapse,
        _ => DsrEventType.retrievalSuccess,
      };
}

class DsrReviewEvent {
  const DsrReviewEvent({
    this.type = DsrEventType.retrievalSuccess,
    this.grade = 3,
    this.closeness = 0.5,
  });

  final DsrEventType type;
  final int grade;

  /// Only meaningful for `retrievalFailureFeedback`: how close the answer was.
  final double closeness;

  static DsrReviewEvent fromJson(Map<String, Object?>? json) {
    if (json == null) {
      return const DsrReviewEvent();
    }
    final type = DsrEventType.fromId(json['type'] as String?);
    return DsrReviewEvent(
      type: type,
      grade: (json['grade'] as num?)?.toInt() ??
          (type == DsrEventType.lapse ? 1 : 3),
      closeness: (json['closeness'] as num?)?.toDouble() ?? 0.5,
    );
  }
}

/// What `applyReview` changed, mirroring the JS return object field for field.
class DsrReviewOutcome {
  const DsrReviewOutcome({
    required this.sAfter,
    required this.rAfter,
    required this.r0After,
    required this.sigmaAfter,
    required this.dAfter,
    required this.rAtReview,
    required this.sInc,
    required this.kind,
  });

  final double sAfter;
  final double rAfter;
  final double r0After;
  final double sigmaAfter;
  final double dAfter;
  final double rAtReview;

  /// Null for a lapse (stability falls instead of growing).
  final double? sInc;

  final String kind;

  Map<String, Object?> toJson() => {
        'S_after': sAfter,
        'R_after': rAfter,
        'R0_after': r0After,
        'Sigma_after': sigmaAfter,
        'D_after': dAfter,
        'R_at_review': rAtReview,
        if (sInc != null) 'SInc': sInc,
        'kind': kind,
      };
}

/// The ported memory layer.
///
/// Every function takes `nowHours` explicitly, exactly like the JS takes `u`;
/// nothing here reads a clock. That is what makes the conformance test possible
/// and what keeps the model's behaviour reproducible.
abstract final class DsrMemory {
  /// `curveC`: c = 0.9^(-1/gamma) - 1.
  static double curveC(double gamma) => math.pow(0.9, -1 / gamma) - 1;

  /// `psi`: the forgetting curve shape, without R0.
  static double psi(double z, DsrParams o) {
    if (z <= 0) {
      return 1;
    }
    if (o.decayModel == DsrDecayModel.exponential) {
      return math.exp(-z);
    }
    return math.pow(1 + curveC(o.gamma) * z, -o.gamma).toDouble();
  }

  /// Rounding used by every published value: 6 decimals, half-away-from-zero.
  ///
  /// Matching this exactly matters - the vectors compare rounded values, so a
  /// different rounding rule shows up as a spurious failure.
  static double round6(double x) {
    final f = math.pow(10, 6);
    return (x * f).roundToDouble() / f;
  }

  /// Retrievability at [nowHours], together with the elapsed hours.
  static ({double r, double dt}) retrievability(
    DsrState state,
    double nowHours, [
    DsrParams params = const DsrParams(),
  ]) {
    final dt = math.max(0.0, nowHours - state.lastReview);
    final r = state.r0 * psi(dt / state.s, params);
    return (r: r, dt: dt);
  }

  /// `scheduleInterval`: hours until retrievability falls to [targetRetention].
  ///
  /// Returns 0 when the target is at or above `R0`: the curve can never reach
  /// it, so the item needs reviewing now (or a higher encoding strength first).
  /// That is a real case, not an edge to paper over - it is what makes a
  /// low-`R0` item visibly different from a well-encoded one.
  static double scheduleInterval(
    DsrState state,
    double nowHours,
    double targetRetention, [
    DsrParams params = const DsrParams(),
  ]) {
    final r = targetRetention;
    if (!(r > 0 && r < 1)) {
      throw ArgumentError('目标留存率必须在 (0,1) 内，实际 $targetRetention');
    }
    if (r >= state.r0) {
      return 0;
    }
    final c = curveC(params.gamma);
    if (params.decayModel == DsrDecayModel.exponential) {
      return state.s * math.log(state.r0 / r);
    }
    return (state.s / c) * (math.pow(r / state.r0, -1 / params.gamma) - 1);
  }

  /// `stabilityIncrease`: the multiplicative gain of one successful review.
  static double stabilityIncrease(
    DsrState state,
    double r,
    DsrParams o,
    DsrEventType kind, [
    double closeness = 0.5,
  ]) {
    final ratio = switch (kind) {
      DsrEventType.reread => o.kappaRereadRatio,
      DsrEventType.retrievalFailureFeedback =>
        math.min(1.0, math.max(0.0, closeness)),
      _ => 1.0,
    };
    final mu = 1 + o.kappaSavings * state.sigma;
    final dClamped =
        math.min(DsrParams.dMax, math.max(DsrParams.dMin, state.d));
    final difficultyTerm = 11 - dClamped;
    final saturation = math.exp(o.eta * (1 - r)) - 1;
    final inc = 1 +
        o.kappa *
            ratio *
            mu *
            difficultyTerm *
            math.pow(state.s, -o.beta) *
            saturation;
    return math.max(1.0, inc);
  }

  /// `failureEvidenceOf`: decayed failure evidence (lazy, O(1)).
  static double failureEvidenceOf(
    DsrState state,
    double nowHours, [
    DsrParams params = const DsrParams(),
  ]) {
    final lastFail = state.lastFail;
    if (lastFail == null) {
      return 0;
    }
    return state.f *
        math.exp(-math.max(0.0, nowHours - lastFail) / params.failTauHours);
  }

  /// `recordFailure`: decays the old evidence, then adds one.
  static double recordFailure(
    DsrState state,
    double nowHours, [
    DsrParams params = const DsrParams(),
  ]) {
    final lastFail = state.lastFail;
    if (lastFail != null) {
      state.f = state.f *
          math.exp(-math.max(0.0, nowHours - lastFail) / params.failTauHours);
    }
    state.f += 1;
    state.lastFail = nowHours;
    return state.f;
  }

  /// `applyReview`: advances the state by one review event and reports what
  /// changed. Mutates [state] the way the JS mutates the node's bag.
  static DsrReviewOutcome applyReview(
    DsrState state,
    double nowHours,
    DsrReviewEvent event, [
    DsrParams params = const DsrParams(),
  ]) {
    final before = retrievability(state, nowHours, params);
    final r = before.r;
    final now = nowHours;

    double? sInc;
    if (event.type == DsrEventType.lapse) {
      // Real forgetting: stability drops, but Sigma is kept - that is the
      // savings effect, and dropping it here would make relearning
      // indistinguishable from learning.
      final sAfter = DsrParams.lapseCf *
          math.pow(state.d, -DsrParams.lapseGammaD) *
          (math.pow(state.s + 1, DsrParams.lapseGammaS) - 1) *
          math.exp(DsrParams.lapseGammaR * (1 - r));
      state.s = math.max(1e-6, sAfter.toDouble());
      recordFailure(state, now, params);
    } else {
      final inc = stabilityIncrease(state, r, params, event.type, event.closeness);
      state.s = state.s * inc;
      sInc = inc;
      if (event.type == DsrEventType.retrievalSuccess) {
        state.n += 1;
        state.r0 = math.min(1.0, state.r0 + params.cR0 * (1 - state.r0));
      }
    }

    // Difficulty: the performance grade, plus "took a long time to recall is
    // harder". Note that grade does NOT change this review's stability gain -
    // it moves D, and D affects *later* gains. The vectors pin that.
    final deltaD = -params.d1 * (event.grade - 3) + params.d2 * (1 - r);
    state.d = math.min(DsrParams.dMax, math.max(DsrParams.dMin, state.d + deltaD));

    // Storage strength only grows: effort = how much was forgotten + how close
    // it was to being recalled.
    final effort =
        math.min(1.0, math.max(0.0, (1 - r) + (1 - event.closeness)));
    state.sigma =
        math.min(1.0, state.sigma + params.cSigma * effort * (1 - state.sigma));

    state.lastReview = now;
    state.history.add(DsrHistoryEntry(
      u: now,
      type: event.type.id,
      r: round6(r),
      s: round6(state.s),
      grade: event.grade,
    ));
    if (state.history.length > 200) {
      state.history.removeAt(0);
    }

    final after = retrievability(state, now, params);
    return DsrReviewOutcome(
      sAfter: round6(state.s),
      rAfter: round6(after.r),
      r0After: round6(state.r0),
      sigmaAfter: round6(state.sigma),
      dAfter: round6(state.d),
      rAtReview: round6(r),
      sInc: sInc == null ? null : round6(sInc),
      kind: event.type == DsrEventType.lapse ? 'lapse' : 'review',
    );
  }
}
