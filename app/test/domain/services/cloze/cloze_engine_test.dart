import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:knowflow/domain/services/cloze/cloze_engine.dart';

void main() {
  group('candidate discovery (spec 1.3.1/1.3.2)', () {
    test('definition pattern creates a blank after 是', () {
      const content = '光合作用的主要场所是叶绿体。';
      final candidates = ClozeEngine.discoverCandidates(content);
      expect(candidates, isNotEmpty);
      final first = candidates.first;
      expect(content.substring(first.start, first.start + first.length),
          '叶绿体');
    });

    test('seed keywords (title/tags) are preferred', () {
      const content = '电动势等于非静电力做的功与电荷量的比值，单位是伏特。';
      final candidates = ClozeEngine.discoverCandidates(content,
          seedKeywords: const ['电动势']);
      expect(candidates.first.slotKey, 'c0');
      expect(candidates.first.answerIn(content), '电动势');
    });

    test('numbers are candidates and slots do not overlap', () {
      const content = '万有引力常量约为6.674e-11，地球半径6371千米。';
      final candidates = ClozeEngine.discoverCandidates(content);
      final spans = candidates.map((c) => (start: c.start, end: c.start + c.length)).toList();
      for (var i = 0; i < spans.length; i++) {
        for (var j = i + 1; j < spans.length; j++) {
          expect(spans[i].start >= spans[j].end || spans[j].start >= spans[i].end,
              isTrue, reason: 'slots must not overlap');
        }
      }
      // Numbers present in content should have candidates anchored on them.
      expect(
        candidates.any((c) =>
            RegExp(r'\d+(\.\d+)?').hasMatch(c.answerIn(content))),
        isTrue,
      );
    });
  });

  group('free cloze draw (spec 1.3.2)', () {
    List<ClozeCandidate> candidates() => const [
          ClozeCandidate(slotKey: 'c0', start: 0, length: 2),
          ClozeCandidate(slotKey: 'c1', start: 3, length: 2),
          ClozeCandidate(slotKey: 'c2', start: 6, length: 2),
        ];

    test('new blanks are drawn when probability triggers and unused exist',
        () {
      final random = Random(42);
      var sawNew = false;
      for (var i = 0; i < 200; i++) {
        final choice = ClozeEngine.chooseSlot(
          candidates: candidates(),
          usedSlotKeys: const {},
          exhausted: false,
          newClozeProbability: 1.0, // always try new
          random: random,
        );
        expect(choice.isNew, isTrue);
        expect(['c0', 'c1', 'c2'], contains(choice.slotKey));
        sawNew = true;
      }
      expect(sawNew, isTrue);
    });

    test('exhausted flag forces historical draws only', () {
      final random = Random(7);
      final used = {'c0', 'c1', 'c2'};
      for (var i = 0; i < 50; i++) {
        final choice = ClozeEngine.chooseSlot(
          candidates: candidates(),
          usedSlotKeys: used,
          exhausted: true,
          newClozeProbability: 1.0,
          random: random,
        );
        expect(choice.isNew, isFalse);
        expect(used, contains(choice.slotKey));
      }
    });

    test('partially used points draw both fresh and historical slots', () {
      final random = Random(99);
      final used = {'c0'};
      final seen = <String>{};
      for (var i = 0; i < 300; i++) {
        final choice = ClozeEngine.chooseSlot(
          candidates: candidates(),
          usedSlotKeys: used,
          exhausted: false,
          newClozeProbability: 0.5,
          random: random,
        );
        seen.add(choice.slotKey);
        if (choice.isNew) {
          expect(used, isNot(contains(choice.slotKey)));
        } else {
          expect(used, contains(choice.slotKey));
        }
      }
      expect(seen, containsAll(['c0', 'c1', 'c2']));
    });
  });

  group('forced-binding machine (spec 1.3.2)', () {
    final now = DateTime(2026, 9, 7, 20);
    ForcedStep grade({
      required bool correct,
      required bool forcedBefore,
      required int streakBefore,
    }) =>
        ForcedMachine.grade(
          correct: correct,
          forcedBefore: forcedBefore,
          streakBefore: streakBefore,
          now: now,
          relearnMinutes: 10,
          releaseStreak: 2,
        );

    test('first wrong answer binds the unit with an immediate redo', () {
      final step = grade(correct: false, forcedBefore: false, streakBefore: 0);
      expect(step.forced, isTrue);
      expect(step.forcedStreak, 0);
      expect(step.immediateRedo, isTrue);
      expect(step.nextDueAt, now.add(const Duration(minutes: 10)));
      expect(step.released, isFalse);
    });

    test('first correct while bound keeps it bound, second releases', () {
      final first = grade(correct: true, forcedBefore: true, streakBefore: 0);
      expect(first.forced, isTrue);
      expect(first.forcedStreak, 1);
      expect(first.released, isFalse);
      expect(first.nextDueAt, now.add(const Duration(minutes: 10)));

      final second = grade(correct: true, forcedBefore: true, streakBefore: 1);
      expect(second.forced, isFalse);
      expect(second.forcedStreak, 0);
      expect(second.released, isTrue);
      expect(second.nextDueAt, isNull);
    });

    test('wrong answer while bound resets the streak', () {
      final step = grade(correct: false, forcedBefore: true, streakBefore: 1);
      expect(step.forced, isTrue);
      expect(step.forcedStreak, 0);
      expect(step.immediateRedo, isTrue);
    });

    test('correct answers outside a binding do not enter one', () {
      final step = grade(correct: true, forcedBefore: false, streakBefore: 0);
      expect(step.forced, isFalse);
      expect(step.released, isFalse);
      expect(step.nextDueAt, isNull);
    });
  });
}
