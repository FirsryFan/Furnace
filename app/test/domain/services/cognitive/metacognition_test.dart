import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/cognitive/metacognition.dart';

/// The belief formula is a port of `mechanisms/metacognition.belief.js`, so these
/// tests pin the *ported* numbers and the four acceptance checks the JS module
/// itself declares (fluency drives belief; `S` is not an input; recency decays;
/// `w_fluency = 0` flattens it).
///
/// Every weight is 未标定 - the tests pin the module's defaults, not a calibrated
/// claim. If a future calibration changes them, these are the tests that must be
/// updated deliberately.
void main() {
  const params = MetacognitionParams();

  MetacognitionObservation obs(
    String node, {
    double fluency = 0.5,
    double? r0 = 0.8,
    double r = 0.5,
    double recencyHours = 0,
    bool isStart = false,
  }) =>
      MetacognitionObservation(
        node: node,
        name: node,
        fluency: fluency,
        r0: r0,
        r: r,
        recencyHours: recencyHours,
        isStart: isStart,
      );

  group('the belief formula', () {
    test('is the module defaults, all uncalibrated', () {
      expect(params.wFluency, 1.5);
      expect(params.wEncoding, 0.8);
      expect(params.wRecency, 0.8);
      expect(params.tauRecencyHours, 6);
      expect(params.b0, 1.5);
      expect(params.delta, 0.2);
      expect(params.toJson()['calibrated'], isFalse);
    });

    test('fluency drives belief: more fluency, more confidence', () {
      final low = Metacognition.beliefOf(
          fluency: 0.1, r0: 0.8, recencyHours: 0, params: params);
      final high = Metacognition.beliefOf(
          fluency: 0.9, r0: 0.8, recencyHours: 0, params: params);

      expect(high, greaterThan(low));
      // Pinned so a weight change cannot slip through as "still monotone".
      expect(low, closeTo(0.522484, 1e-6));
      expect(high, closeTo(0.784147, 1e-6));
    });

    test('a fully lit, freshly seen, well-encoded point is 0.832019', () {
      final belief = Metacognition.beliefOf(
          fluency: 1.0, r0: 1.0, recencyHours: 0, params: params);

      expect(belief, closeTo(0.832019, 1e-6));
    });

    test('recency: just seen beats a day ago, same everything else', () {
      final fresh = Metacognition.beliefOf(
          fluency: 0.5, r0: 0.8, recencyHours: 0, params: params);
      final stale = Metacognition.beliefOf(
          fluency: 0.5, r0: 0.8, recencyHours: 24, params: params);

      expect(fresh, greaterThan(stale));
      expect(fresh, closeTo(0.665967, 1e-6));
      expect(stale, closeTo(0.476181, 1e-6));
    });

    test('an unknown encoding ceiling is 0.5, not the model reading default',
        () {
      final unknown = Metacognition.beliefOf(
          fluency: 0.5, r0: null, recencyHours: 1, params: params);
      final half = Metacognition.beliefOf(
          fluency: 0.5, r0: 0.5, recencyHours: 1, params: params);

      expect(unknown, half);
    });

    test('S is not an input: the signature cannot see stability at all', () {
      // Two identical inputs, and nothing in the API to vary that would stand for
      // the FSRS stability column.
      final a = Metacognition.beliefOf(
          fluency: 0.5, r0: 0.8, recencyHours: 1, params: params);
      final b = Metacognition.beliefOf(
          fluency: 0.5, r0: 0.8, recencyHours: 1, params: params);

      expect(a, b);
    });

    test('turning fluency off flattens belief: cramming stops helping', () {
      const off = MetacognitionParams(wFluency: 0);
      final low = Metacognition.beliefOf(
          fluency: 0.05, r0: 0.8, recencyHours: 0, params: off);
      final high = Metacognition.beliefOf(
          fluency: 0.95, r0: 0.8, recencyHours: 0, params: off);

      expect(low, high);
    });

    test('the sigmoid is stable at both extremes', () {
      expect(Metacognition.sigmoid(-1e6), 0.0);
      expect(Metacognition.sigmoid(1e6), 1.0);
      expect(Metacognition.sigmoid(0), 0.5);
      expect(Metacognition.sigmoid(-1000).isFinite, isTrue);
    });
  });

  group('the reading', () {
    test('nothing counted means zero calibration, not perfect calibration',
        () {
      final reading = Metacognition.read(observations: const []);

      expect(reading.rows, isEmpty);
      expect(reading.calibration, 0);
      expect(reading.hasRows, isFalse);
      expect(MetacognitionReading.empty.toJson()['calibration'], 0);
    });

    test('start nodes are skipped, exactly as the JS does', () {
      final reading = Metacognition.read(observations: [
        obs('start', isStart: true),
        obs('other'),
      ]);

      expect(reading.rows.map((row) => row.node), const ['other']);
    });

    test('danger is confidence above reality, anxiety is the other way round',
        () {
      final reading = Metacognition.read(observations: [
        // belief 0.832019 - R 0.1 = +0.732019 -> danger
        obs('confident', fluency: 1.0, r0: 1.0, r: 0.1),
        // belief 0.522484 - R 0.95 = -0.427516 -> anxiety
        obs('diffident', fluency: 0.1, r0: 0.8, r: 0.95),
        // belief 0.832019 - R 0.75 = +0.082019 -> neither
        obs('calibrated', fluency: 1.0, r0: 1.0, r: 0.75),
      ]);

      expect(reading.rows.length, 3);
      expect(reading.danger.map((row) => row.node), const ['confident']);
      expect(reading.anxiety.map((row) => row.node), const ['diffident']);
      expect(reading.calibration, closeTo(0.413851, 1e-6));
    });

    test('the two tails are sorted by how far off they are', () {
      final reading = Metacognition.read(observations: [
        // +0.732019 (confidence 0.832019, R 0.1)
        obs('big-gap', fluency: 1.0, r0: 1.0, r: 0.1),
        // +0.414959 (confidence 0.714959, R 0.3)
        obs('small-gap', fluency: 0.6, r0: 0.9, r: 0.3),
        // -0.427516
        obs('very-diffident', fluency: 0.1, r0: 0.8, r: 0.95),
        // -0.322484 (confidence 0.522484, R 0.845)
        obs('mildly-diffident', fluency: 0.1, r0: 0.8, r: 0.845),
      ]);

      expect(reading.danger.map((row) => row.node),
          const ['big-gap', 'small-gap']);
      expect(reading.anxiety.map((row) => row.node),
          const ['very-diffident', 'mildly-diffident']);
    });

    test('belief and diff are rounded to six decimals like the JS', () {
      final reading = Metacognition.read(observations: [obs('rounded')]);

      for (final row in reading.rows) {
        expect(row.belief, (row.belief * 1e6).roundToDouble() / 1e6);
        expect(row.diff, (row.diff * 1e6).roundToDouble() / 1e6);
      }
    });

    test('the JSON handshake names the layer and carries all three parts', () {
      final reading = Metacognition.read(observations: [
        obs('confident', fluency: 1.0, r0: 1.0, r: 0.1),
      ]);
      final json = reading.toJson();

      expect(json['schema'], 'mindnet.metacognition/1');
      expect(json['calibration'], isA<double>());
      expect((json['danger']! as List).length, 1);
      expect((json['anxiety']! as List), isEmpty);
      expect((json['rows']! as List).length, 1);
      expect(
        ((json['rows']! as List).first as Map<String, Object?>)['R'],
        closeTo(0.1, 1e-9),
      );
    });
  });
}
