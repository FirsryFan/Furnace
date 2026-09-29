import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/srs/dsr_memory.dart';

/// Conformance test for the Dart port of MindNet's DSR memory layer.
///
/// The vectors in `test/fixtures/mindnet_vectors.json` were generated from the
/// real JS implementation (`generated_from.commit` inside the file) and are the
/// agreed contract: `docs/MINDNET_CONTRACT.md` §6.2 fixes the rules, and the
/// contract's point is that **`rel <= 1e-12` is a hard standard** - anything
/// larger is a real implementation difference, not floating-point noise, so it
/// must not be waved through with a loose tolerance.
///
/// This is why the port is trustworthy: it is not "looks like the same curve",
/// it is "reproduces 43 published values".
void main() {
  final file = File('test/fixtures/mindnet_vectors.json');
  if (!file.existsSync()) {
    test('mindnet conformance vectors', () {
      fail('missing ${file.path} - the contract requires the snapshot to be '
          'vendored into this repository');
    });
    return;
  }

  final vectors =
      jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
  final tierA = (vectors['tierA'] as List).cast<Map<String, Object?>>();
  final tolerances = (vectors['tolerances'] as Map).cast<String, Object?>();
  final rel = (tolerances['rel'] as num).toDouble();
  final abs = (tolerances['abs'] as num).toDouble();
  final decimals = (tolerances['rounded_decimals'] as num).toInt();

  /// Compares one published value.
  ///
  /// The published numbers are the generator's `round6` output, so the port's
  /// value is rounded the same way before comparing - comparing full precision
  /// against a rounded number and calling the 5e-7 difference an implementation
  /// mismatch is exactly the trap the tolerances file warns about. Rounding is
  /// reproducible in both languages (half-away-from-zero), so after it the
  /// contract's `rel <= 1e-12` is a meaningful standard.
  void expectClose(String id, String field, double actual, num expected) {
    final want = expected.toDouble();
    final got = DsrMemory.round6(actual);
    final diff = (got - want).abs();
    final scale = want.abs() > 1 ? want.abs() : 1.0;
    final ok = diff <= abs || diff / scale <= rel;
    expect(
      ok,
      isTrue,
      reason: '$id: $field actual=$got (raw=$actual) expected=$want '
          'diff=$diff (rel=${diff / scale}, allowed rel=$rel abs=$abs)',
    );
  }

  Map<String, Object?> inputOf(Map<String, Object?> v) =>
      (v['input'] as Map).cast<String, Object?>();

  Map<String, Object?> expectedOf(Map<String, Object?> v) =>
      (v['expected'] as Map).cast<String, Object?>();

  /// The published values are rounded to 6 decimals by the generator, so the
  /// port is compared the same way. `must_be_exact` fields are set-valued and
  /// do not appear in tierA.
  void compareAll(String id, Map<String, Object?> actual,
      Map<String, Object?> expected) {
    for (final entry in expected.entries) {
      final want = entry.value;
      if (want is num) {
        final got = actual[entry.key];
        expect(got, isA<num>(),
            reason: '$id: missing numeric field ${entry.key}');
        expectClose(id, entry.key, (got! as num).toDouble(), want);
      } else {
        // Enum-ish fields (kind) are compared exactly, as the tolerances file
        // requires.
        expect(actual[entry.key], want, reason: '$id: ${entry.key}');
      }
    }
  }

  DsrState stateOf(Map<String, Object?> input) =>
      DsrState.fromJson((input['state'] as Map).cast<String, Object?>());

  group('A01 constants', () {
    test('curveC and the shipped defaults match', () {
      final vector = tierA.firstWhere((v) => (v['id'] as String).startsWith('A01-'));
      final input = inputOf(vector);
      final expected = expectedOf(vector);

      final gamma = (input['gamma'] as num).toDouble();
      expectClose(vector['id'] as String, 'c', DsrMemory.curveC(gamma),
          expected['c']! as num);

      const defaults = DsrParams();
      for (final entry in {
        'kappa': defaults.kappa,
        'beta': defaults.beta,
        'eta': defaults.eta,
      }.entries) {
        expectClose(vector['id'] as String, entry.key, entry.value,
            expected[entry.key]! as num);
      }
    });
  });

  group('A02/A03 psi', () {
    test('every published psi value is reproduced', () {
      var checked = 0;
      for (final vector in tierA) {
        final api = vector['api'] as String;
        if (!api.startsWith('memoryDsr.psi')) {
          continue;
        }
        final input = inputOf(vector);
        final z = (input['z'] as num).toDouble();
        final gamma = (input['gamma'] as num?)?.toDouble() ?? 0.1542;
        final params = DsrParams(
          gamma: gamma,
          decayModel: input['decay_model'] == 'exponential'
              ? DsrDecayModel.exponential
              : DsrDecayModel.power,
        );
        compareAll(vector['id'] as String, {
          'psi': DsrMemory.psi(z, params),
        }, expectedOf(vector));
        checked++;
      }
      expect(checked, greaterThanOrEqualTo(13),
          reason: 'the vectors should cover both curve shapes');
    });
  });

  group('A04 retrievability', () {
    test('R is reproduced for every published (state, t)', () {
      var checked = 0;
      for (final vector in tierA) {
        if (vector['api'] != 'memoryDsr.retrievabilityOf(node, t)') {
          continue;
        }
        final input = inputOf(vector);
        final state = stateOf(input);
        final t = (input['t'] as num).toDouble();
        final r = DsrMemory.retrievability(state, t).r;
        final expected = expectedOf(vector);
        expectClose(vector['id'] as String, 'R', r, expected['R']! as num);
        if (expected.containsKey('ms')) {
          // `ms` is the exported retrievability; the two must agree.
          expectClose(vector['id'] as String, 'ms', r, expected['ms']! as num);
        }
        checked++;
      }
      expect(checked, 6);
    });
  });

  group('A05 scheduleInterval', () {
    test('the interval for every target retention is reproduced', () {
      var checked = 0;
      for (final vector in tierA) {
        if (vector['api'] != 'memoryDsr.scheduleInterval(node, 0, target)') {
          continue;
        }
        final input = inputOf(vector);
        final state = stateOf(input);
        final now = (input['now'] as num?)?.toDouble() ?? 0;
        final target = (input['target'] as num).toDouble();
        final hours = DsrMemory.scheduleInterval(state, now, target);
        compareAll(vector['id'] as String, {'hours': hours}, expectedOf(vector));
        checked++;
      }
      expect(checked, 6);
    });

    test('a target above R0 reports "review now" instead of a negative interval',
        () {
      // Not in the vectors, but it is the documented behaviour and the reason
      // `R0` exists at all: the curve cannot reach a retention above the
      // encoding ceiling.
      final state = DsrState.initial(now: 0, ms: 0.5);
      expect(DsrMemory.scheduleInterval(state, 0, 0.85), 0);
      expect(DsrMemory.scheduleInterval(state, 0, 0.5), 0);
    });
  });

  group('A06/A07/A08 applyReview', () {
    test('every published review outcome is reproduced', () {
      var checked = 0;
      final coveredEvents = <String>{};
      for (final vector in tierA) {
        final api = vector['api'] as String;
        if (!api.startsWith('memoryDsr.applyReview')) {
          continue;
        }
        final input = inputOf(vector);
        final state = stateOf(input);
        final t = (input['t'] as num).toDouble();
        final event = DsrReviewEvent.fromJson(
            (input['event'] as Map?)?.cast<String, Object?>());
        coveredEvents.add(event.type.id);

        final outcome = DsrMemory.applyReview(state, t, event);
        compareAll(vector['id'] as String, outcome.toJson(), expectedOf(vector));
        checked++;
      }
      expect(checked, 17);
      // The port must have been exercised by every event kind, not just the
      // happy path.
      expect(coveredEvents, containsAll(DsrEventType.values.map((e) => e.id)));
    });

    test('the state is mutated, not just reported', () {
      // The JS mutates the node's bag and callers rely on it; a port that only
      // returned numbers would look correct here and break the caller.
      final state = DsrState.initial(now: 0);
      final before = state.s;
      DsrMemory.applyReview(
        state,
        20,
        const DsrReviewEvent(type: DsrEventType.retrievalSuccess),
      );
      expect(state.s, greaterThan(before));
      expect(state.lastReview, 20);
      expect(state.history, hasLength(1));
      expect(state.n, 1);
    });

    test('grade moves difficulty, not this review\'s stability gain', () {
      // The semantic trap the vectors pin down (MINDNET_CONTRACT §6.2): grading
      // an answer Easy does not lengthen the interval right now. It lowers D,
      // which raises the gain of *subsequent* reviews.
      final byGrade = <int, DsrReviewOutcome>{};
      for (final grade in [1, 2, 3, 4]) {
        final state = DsrState.initial(now: 0);
        byGrade[grade] = DsrMemory.applyReview(
          state,
          20,
          DsrReviewEvent(type: DsrEventType.retrievalSuccess, grade: grade),
        );
      }
      // Difficulty is ordered the way the grade is.
      expect(byGrade[1]!.dAfter, greaterThan(byGrade[2]!.dAfter));
      expect(byGrade[2]!.dAfter, greaterThan(byGrade[3]!.dAfter));
      expect(byGrade[3]!.dAfter, greaterThan(byGrade[4]!.dAfter));
      // And a harder grade leaves the item *less* stable, because the gain was
      // computed before D changed for this review... so the differences here
      // come from the round that will follow. What must hold now is that the
      // immediate gain did not depend on the grade at all.
      final gains = byGrade.values.map((o) => o.sInc!).toSet();
      expect(gains, hasLength(1),
          reason: 'the immediate SInc must be identical across grades');
    });

    test('Sigma amplifies the gain (savings effect)', () {
      final low = DsrState.initial(now: 0)..sigma = 0.0;
      final high = DsrState.initial(now: 0)..sigma = 0.9;
      final lowInc = DsrMemory.stabilityIncrease(
          low, DsrMemory.retrievability(low, 20).r, const DsrParams(),
          DsrEventType.retrievalSuccess);
      final highInc = DsrMemory.stabilityIncrease(
          high, DsrMemory.retrievability(high, 20).r, const DsrParams(),
          DsrEventType.retrievalSuccess);
      expect(highInc, greaterThan(lowInc));
    });

    test('a lapse drops stability and records failure evidence', () {
      final state = DsrState.initial(now: 0);
      state.s = 400;
      final outcome = DsrMemory.applyReview(
        state,
        30,
        const DsrReviewEvent(type: DsrEventType.lapse, grade: 1),
      );
      expect(outcome.kind, 'lapse');
      expect(outcome.sInc, isNull,
          reason: 'a lapse has no stability gain to report');
      expect(state.s, lessThan(400));
      // Failure evidence, decayed lazily from `lastFail`.
      expect(DsrMemory.failureEvidenceOf(state, 30), 1.0);
      // `fail_tau_hours` is 720, so one tau later the evidence is exp(-1).
      expect(DsrMemory.failureEvidenceOf(state, 30 + 720),
          closeTo(math.exp(-1), 1e-9),
          reason: 'the default failure time constant is 30 days');
      expect(DsrMemory.failureEvidenceOf(state, 30 + 1440),
          closeTo(math.exp(-2), 1e-9));
    });

    test('R0 grows only on successful retrieval, and never past 1', () {
      final state = DsrState.initial(now: 0, ms: 0.99);
      DsrMemory.applyReview(
        state,
        10,
        const DsrReviewEvent(type: DsrEventType.reread),
      );
      expect(state.r0, 0.99,
          reason: 'rereading is not evidence of retrieval');
      for (var i = 0; i < 50; i++) {
        DsrMemory.applyReview(
          state,
          state.lastReview + 10,
          const DsrReviewEvent(type: DsrEventType.retrievalSuccess),
        );
      }
      expect(state.r0, lessThanOrEqualTo(1.0));
      expect(state.r0, greaterThan(0.99));
    });

    test('the history is bounded', () {
      final state = DsrState.initial(now: 0);
      for (var i = 0; i < 250; i++) {
        DsrMemory.applyReview(
          state,
          state.lastReview + 1,
          const DsrReviewEvent(type: DsrEventType.retrievalSuccess),
        );
      }
      expect(state.history.length, lessThanOrEqualTo(200));
    });
  });

  group('snapshot provenance', () {
    test('the vendored vectors state where they came from', () {
      // Without this the file is just "some numbers"; with it, a future reader
      // can re-generate and diff. The contract requires pinning a commit.
      final from = (vectors['generated_from'] as Map).cast<String, Object?>();
      expect(from['repo'], contains('MindNet'));
      expect((from['commit'] as String).length, 40);
      expect(vectors['protocol'], 'mindnet.conformance/1');
    });

    test('the tolerance rules the contract agreed are the ones used here', () {
      expect(rel, 1e-12);
      expect(decimals, 6);
    });
  });
}
