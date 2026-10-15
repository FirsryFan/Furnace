import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/cognitive/rhythm_gate.dart';
import 'package:furnace/domain/services/cognitive/study_rhythm.dart';

void main() {
  final base = DateTime(2026, 10, 16, 9, 0);
  DateTime at(int minutes) => base.add(Duration(minutes: minutes));
  DateTime withMs(DateTime moment, int ms) =>
      moment.add(Duration(milliseconds: ms));

  group('sittings derived from the study log', () {
    test('没有动作就没有坐段', () {
      expect(StudyRhythm.sessions(const <DateTime>[]), isEmpty);
      expect(
        StudyRhythm.currentSession(const <DateTime>[], now: at(0)),
        isNull,
      );
    });

    test('单个动作 = 一个零长度坐段', () {
      final sessions = StudyRhythm.sessions(<DateTime>[at(0)]);
      expect(sessions, hasLength(1));
      expect(sessions.single.actionCount, 1);
      expect(sessions.single.span, Duration.zero);
    });

    test('间隔小于阈值算同一段，等于阈值也算（≤ 而不是 <）', () {
      final justUnder = StudyRhythm.sessions(<DateTime>[
        at(0),
        at(14),
        at(29),
      ]);
      expect(justUnder, hasLength(1));
      expect(justUnder.single.actionCount, 3);
      expect(justUnder.single.startedAt, at(0));
      expect(justUnder.single.lastActionAt, at(29));

      final exactly = StudyRhythm.sessions(<DateTime>[at(0), at(15)]);
      expect(exactly, hasLength(1));
    });

    test('超过阈值 1 毫秒就断开', () {
      final sessions = StudyRhythm.sessions(<DateTime>[
        at(0),
        withMs(at(15), 1),
        at(20),
      ]);
      expect(sessions, hasLength(2));
      expect(sessions.first.startedAt, at(0));
      expect(sessions.first.lastActionAt, at(0));
      expect(sessions.last.startedAt, withMs(at(15), 1));
      expect(sessions.last.actionCount, 2);
    });

    test('乱序输入先排序，结果与有序一致', () {
      final shuffled = StudyRhythm.sessions(<DateTime>[at(29), at(0), at(14)]);
      expect(shuffled, hasLength(1));
      expect(shuffled.single.startedAt, at(0));
      expect(shuffled.single.lastActionAt, at(29));
    });

    test('同刻的重复动作不撑开新段', () {
      final sessions = StudyRhythm.sessions(<DateTime>[at(5), at(5), at(5)]);
      expect(sessions, hasLength(1));
      expect(sessions.single.actionCount, 3);
      expect(sessions.single.span, Duration.zero);
    });
  });

  group('currentSitting', () {
    test('最后一个动作在阈值内 ⇒ 还在这一段里', () {
      final session = StudyRhythm.currentSession(
        <DateTime>[at(-20), at(-10), at(-5)],
        now: at(0),
      );
      expect(session, isNotNull);
      expect(session!.startedAt, at(-20));
      expect(session.lastActionAt, at(-5));
      expect(session.actionCount, 3);
    });

    test('离开超过阈值 ⇒ 没有坐段（而不是 α = 1）', () {
      expect(
        StudyRhythm.currentSession(<DateTime>[at(-30), at(-20)], now: at(0)),
        isNull,
      );
    });

    test('正好卡在阈值上仍算在段里', () {
      expect(
        StudyRhythm.currentSession(<DateTime>[at(-15)], now: at(0)),
        isNotNull,
      );
      expect(
        StudyRhythm.currentSession(<DateTime>[withMs(at(-15), -1)], now: at(0)),
        isNull,
      );
    });

    test('晚于 now 的动作（时钟回拨/预写）被忽略，不吃掉当前坐段', () {
      final session = StudyRhythm.currentSession(
        <DateTime>[at(-10), at(5)],
        now: at(0),
      );
      expect(session, isNotNull);
      expect(session!.startedAt, at(-10));
      expect(session.actionCount, 1);
    });
  });

  group('reading', () {
    test('没有坐段 ⇒ 没有读数（不编一个可用性）', () {
      expect(
        StudyRhythm.read(actions: <DateTime>[at(-40)], now: at(0)),
        isNull,
      );
      expect(
        StudyRhythm.read(actions: const <DateTime>[], now: at(0)),
        isNull,
      );
    });

    test('20 分钟坐段 ⇒ G_vig = 1/e，占空比门按 duty 开窗', () {
      final reading = StudyRhythm.read(
        actions: <DateTime>[at(-20), at(-10), at(-2)],
        now: at(0),
        load: 4,
      );
      expect(reading, isNotNull);
      expect(reading!.minutesOnRounded, 20);
      expect(reading.vigilance, closeTo(1 / 2.718281828459045, 1e-12));
      // load = 4 = referenceLoad ⇒ T_cycle = T0·(1 + 1) = 2.0 s ⇒ 8 tick。
      expect(reading.cycleTicks, 8);
      // open = round(0.5 · 0.3679 · 8) = round(1.47) = 1。
      expect(reading.openTicks, 1);
      expect(reading.availability, closeTo(1 / 8, 1e-12));
      expect(reading.advice, StudyAdvice.moderate);
      expect(reading.vigilancePercent, 37);
      expect(reading.session.actionCount, 3);
    });

    test('刚坐下（1 分钟）⇒ α 接近 1、建议做难', () {
      final reading = StudyRhythm.read(
        actions: <DateTime>[at(-1), at(0)],
        now: at(0),
      );
      expect(reading!.minutesOnRounded, 1);
      expect(reading.vigilance, closeTo(0.951229424500714, 1e-12));
      expect(reading.advice, StudyAdvice.hard);
      expect(reading.cycleTicks, 4);
      expect(reading.openTicks, 2);
      expect(reading.availability, closeTo(0.5, 1e-12));
    });

    test('长坐段（每 15 分钟一次动作，共 120 分钟）⇒ 建议休息，且数字一起给出', () {
      final reading = StudyRhythm.read(
        actions: <DateTime>[
          at(-120),
          at(-105),
          at(-90),
          at(-75),
          at(-60),
          at(-45),
          at(-30),
          at(-15),
        ],
        now: at(0),
      );
      expect(reading!.session.actionCount, 8);
      expect(reading.minutesOnRounded, 120);
      expect(reading.advice, StudyAdvice.rest);
      expect(reading.vigilance, lessThan(kRhythmRestBelow));
      expect(reading.toJson()['advice'], 'rest');
      expect(reading.toJson()['minutes_on'], 120);
    });

    test('负负荷直接拒绝', () {
      expect(
        () => StudyRhythm.read(
          actions: <DateTime>[at(0)],
          now: at(0),
          load: -1,
        ),
        throwsArgumentError,
      );
    });
  });

  group('advice thresholds', () {
    test('边界值落在"更努力"的一侧', () {
      expect(StudyRhythm.adviceFor(1.0), StudyAdvice.hard);
      expect(StudyRhythm.adviceFor(kRhythmHardAbove), StudyAdvice.hard);
      expect(
          StudyRhythm.adviceFor(kRhythmHardAbove - 1e-9), StudyAdvice.moderate);
      expect(StudyRhythm.adviceFor(kRhythmRestBelow), StudyAdvice.moderate);
      expect(StudyRhythm.adviceFor(kRhythmRestBelow - 1e-9), StudyAdvice.rest);
      expect(StudyRhythm.adviceFor(double.nan), StudyAdvice.none);
    });

    test('半衰期与 rhythm.gate 的参数是同一条口径（τ_vig·ln2）', () {
      expect(
        StudyRhythm.halfVigilanceMinutes(),
        closeTo(20 * 0.6931471805599453, 1e-9),
      );
      expect(
        StudyRhythm.halfVigilanceMinutes(
          params: const RhythmGateParams(tauVigMinutes: 10),
        ),
        closeTo(6.931471805599453, 1e-9),
      );
    });
  });
}
