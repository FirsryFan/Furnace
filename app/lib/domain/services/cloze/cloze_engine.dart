/// ClozeEngine - free-blank machinery (spec 1.3.2).
///
/// - Slot candidates are discovered from the knowledge point content by
///   deterministic heuristics (keywords, definition patterns 是/为, ：
///   tails, numbers). Each candidate maps to a stable slot key (c0, c1, ...)
///   and a character span of the content.
/// - Free cloze: with probability [newClozeProbability] the draw tries a
///   brand-new (never-used) slot; otherwise it replays a historical slot.
///   When no unused slot exists the knowledge point is marked exhausted and
///   only historical draws happen.
/// - The forced-binding machine (wrong answer -> immediate redo + short
///   relearning interval until two consecutive correct answers) is pure.
library;

import 'dart:math';

/// A discoverable blank within the content.
class ClozeCandidate {
  const ClozeCandidate({
    required this.slotKey,
    required this.start,
    required this.length,
  });

  final String slotKey;
  final int start;
  final int length;

  String answerIn(String content) => content.substring(start, start + length);
}

class ClozeChoice {
  const ClozeChoice({required this.slotKey, required this.isNew});

  final String slotKey;
  final bool isNew;
}

abstract final class ClozeEngine {
  /// Discovers deterministic blank candidates. [seedKeywords] (e.g. the
  /// knowledge point title/tags) get first priority, then definition
  /// patterns and numbers. Slots never overlap.
  static List<ClozeCandidate> discoverCandidates(
    String content, {
    List<String> seedKeywords = const [],
  }) {
    final taken = <({int start, int end})>[];
    final candidates = <ClozeCandidate>[];

    void add(int start, int length) {
      if (length <= 0 || start < 0 || start + length > content.length) {
        return;
      }
      for (final t in taken) {
        if (start < t.end && start + length > t.start) {
          return; // overlap
        }
      }
      taken.add((start: start, end: start + length));
      candidates.add(ClozeCandidate(
        slotKey: 'c${candidates.length}',
        start: start,
        length: length,
      ));
    }

    for (final keyword in seedKeywords) {
      final trimmed = keyword.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      var from = 0;
      while (true) {
        final index = content.indexOf(trimmed, from);
        if (index < 0) {
          break;
        }
        add(index, trimmed.length);
        from = index + trimmed.length;
      }
    }

    // Definition pattern: blank the tail after 是 / 为 (one sentence part).
    for (final marker in ['是', '为']) {
      var from = 0;
      while (true) {
        final index = content.indexOf(marker, from);
        if (index < 0) {
          break;
        }
        final tail = _sentenceTail(content, index + marker.length);
        if (tail.isNotEmpty) {
          add(index + marker.length, tail.length);
        }
        from = index + marker.length;
      }
    }

    // Colon tails.
    for (final marker in ['：', ':']) {
      var from = 0;
      while (true) {
        final index = content.indexOf(marker, from);
        if (index < 0) {
          break;
        }
        final tail = _sentenceTail(content, index + 1);
        if (tail.isNotEmpty) {
          add(index + 1, tail.length);
        }
        from = index + 1;
      }
    }

    // Numbers.
    final numberRe = RegExp(r'\d+(\.\d+)?');
    for (final match in numberRe.allMatches(content)) {
      add(match.start, match.end - match.start);
    }

    return candidates;
  }

  static String _sentenceTail(String content, int from) {
    if (from >= content.length) {
      return '';
    }
    var end = content.length;
    for (final terminator in ['。', '！', '？', '!', '?', '；', ';', '，', ',']) {
      final index = content.indexOf(terminator, from);
      if (index >= 0 && index < end) {
        end = index;
      }
    }
    var tail = content.substring(from, end);
    tail = tail.replaceFirst(RegExp(r'[\s]+$'), '');
    return tail.trim();
  }

  /// Free-blank draw. Uses [random]; pass a seeded [Random] in tests/UI.
  static ClozeChoice chooseSlot({
    required List<ClozeCandidate> candidates,
    required Set<String> usedSlotKeys,
    required bool exhausted,
    required double newClozeProbability,
    required Random random,
  }) {
    final unused = [
      for (final c in candidates)
        if (!usedSlotKeys.contains(c.slotKey)) c,
    ];
    final tryNew = !exhausted && random.nextDouble() < newClozeProbability;
    if (tryNew && unused.isNotEmpty) {
      final pick = unused[random.nextInt(unused.length)];
      return ClozeChoice(slotKey: pick.slotKey, isNew: true);
    }
    // Historical draw (prefers used slots; falls back to any when the
    // history is empty but candidates exist).
    final pool = usedSlotKeys.isEmpty
        ? candidates
        : [
            for (final c in candidates)
              if (usedSlotKeys.contains(c.slotKey)) c,
          ];
    if (pool.isEmpty) {
      // No candidates at all: caller must mark the point exhausted.
      throw StateError('no cloze candidates available');
    }
    final pick = pool[random.nextInt(pool.length)];
    return ClozeChoice(slotKey: pick.slotKey, isNew: false);
  }

  /// Whether the point still has unused blanks (drives the exhausted flag).
  static bool hasUnused({
    required List<ClozeCandidate> candidates,
    required Set<String> usedSlotKeys,
  }) =>
      candidates.any((c) => !usedSlotKeys.contains(c.slotKey));
}

/// Result of grading one review through the forced-binding machine.
class ForcedStep {
  const ForcedStep({
    required this.forced,
    required this.forcedStreak,
    required this.immediateRedo,
    required this.nextDueAt,
    required this.released,
  });

  final bool forced;

  /// Consecutive correct answers while forced.
  final int forcedStreak;

  /// True when the same unit must be redone right away (wrong answer).
  final bool immediateRedo;

  final DateTime? nextDueAt;

  /// True when the binding is released (2 consecutive correct) - the caller
  /// then resumes FSRS scheduling.
  final bool released;
}

/// Forced-binding state machine (spec 1.3.2 wrong-answer handling).
abstract final class ForcedMachine {
  /// Steps the machine after an answer.
  ///
  /// [forcedBefore] / [streakBefore] describe the state BEFORE this review.
  static ForcedStep grade({
    required bool correct,
    required bool forcedBefore,
    required int streakBefore,
    required DateTime now,
    required int relearnMinutes,
    required int releaseStreak,
  }) {
    if (!correct) {
      // Wrong: binding forces on, streak resets, redo now and again after
      // the short relearning interval.
      return ForcedStep(
        forced: true,
        forcedStreak: 0,
        immediateRedo: true,
        nextDueAt: now.add(Duration(minutes: relearnMinutes)),
        released: false,
      );
    }
    if (!forcedBefore) {
      // Correct outside a binding: nothing to do (FSRS handles scheduling).
      return ForcedStep(
        forced: false,
        forcedStreak: 0,
        immediateRedo: false,
        nextDueAt: null,
        released: false,
      );
    }
    final streak = streakBefore + 1;
    if (streak >= releaseStreak) {
      return ForcedStep(
        forced: false,
        forcedStreak: 0,
        immediateRedo: false,
        nextDueAt: null,
        released: true,
      );
    }
    return ForcedStep(
      forced: true,
      forcedStreak: streak,
      immediateRedo: false,
      nextDueAt: now.add(Duration(minutes: relearnMinutes)),
      released: false,
    );
  }
}
