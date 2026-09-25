import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/database.dart';
import '../../../data/repositories/anki_repository.dart';
import '../../../data/repositories/diffusion_log_repository.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../data/repositories/tag_repository.dart';
import '../../../data/repositories/task_repository.dart';
import '../../../domain/services/cloze/cloze_engine.dart';
import '../../../domain/services/cloze/tag_diffusion.dart';
import '../../../domain/services/config/furnace_defaults.dart';
import '../../../domain/services/srs/fsrs_scheduler.dart';

/// One ready-to-answer unit in the review queue.
class ReviewItem {
  const ReviewItem({
    required this.knowledgePoint,
    required this.cardState,
    required this.unitKey,
    required this.content,
    required this.question,
    required this.answer,
    this.slotStart,
    this.slotLength,
    this.isNew = false,
  });

  final KnowledgePoint knowledgePoint;
  final CardState cardState;
  final String unitKey;

  /// Full item text (Markdown-ish), used to render the blank in place.
  final String content;

  /// Rendered question text with the blank shown as `______`.
  final String question;

  /// The exact expected answer for the blank.
  final String answer;

  final int? slotStart;
  final int? slotLength;

  /// A blank that has never been shown before.
  final bool isNew;

  String get knowledgePointId => knowledgePoint.id;
  String get title => knowledgePoint.title;
}

/// The outcome of one graded answer.
class ReviewOutcome {
  const ReviewOutcome({
    required this.correct,
    required this.expected,
    required this.nextDueAt,
    required this.scheduledDays,
    required this.released,
    required this.stillForced,
    required this.boosted,
  });

  final bool correct;
  final String expected;
  final DateTime nextDueAt;
  final int scheduledDays;

  /// The binding was cleared (it had reached the required streak).
  final bool released;

  /// The unit must come back inside today's queue.
  final bool stillForced;

  /// Knowledge points lifted by tag diffusion because of this wrong answer.
  final List<BoostedItem> boosted;
}

/// A knowledge point that got row priority because a related one went wrong.
class BoostedItem {
  const BoostedItem({
    required this.title,
    required this.factor,
    required this.distance,
  });

  final String title;
  final double factor;
  final int distance;
}

/// The review engine (blueprint 4, user annotations 17/18/19).
///
/// - Blank granularity: ONE blank per question (annotation 17).
/// - A wrong answer marks THAT blank `active`; it must reappear within the
///   same day's queue, a few cards later, or immediately when nothing else is
///   left (annotation 17).
/// - Strict grading compares characters exactly, with no normalisation at all
///   (annotation 18).
/// - Answering wrong lifts related knowledge points through the tag tree and
///   records the day's ledger for the separate insight screen (annotation 19).
class ReviewService {
  ReviewService({
    required this.ankiRepository,
    required this.tagRepository,
    required this.taskRepository,
    required this.diffusionLogRepository,
    Random? random,
  }) : random = random ?? Random();

  final AnkiRepository ankiRepository;
  final TagRepository tagRepository;
  final TaskRepository taskRepository;
  final DiffusionLogRepository diffusionLogRepository;
  final Random random;

  /// How many cards must pass before an active (wrong-answer) blank returns.
  static const int relearnGapCards = 3;

  // --- queue ---------------------------------------------------------------

  /// Builds today's queue: due knowledge points, plus active units pinned to
  /// reappear inside the same day.
  Future<List<ReviewItem>> buildQueue({DateTime? now}) async {
    final moment = now ?? DateTime.now();
    final points = await ankiRepository.getKnowledgePoints();
    final due = <ReviewItem>[];
    final forced = <ReviewItem>[];
    final boostedIds = <String, double>{};

    for (final boost in await ankiRepository.getAllBoosts()) {
      boostedIds[boost.knowledgePointId] = boost.factor;
    }

    for (final point in points) {
      final states = await ankiRepository.unitStatesForKnowledgePoint(point.id);
      final forcedStates =
          states.where((state) => state.forced == 1).toList();
      for (final state in forcedStates) {
        final item = await _itemFor(
          point,
          state,
          preferredUnitKey: state.unitKey,
        );
        if (item != null) {
          forced.add(item);
        }
      }

      // Normal draw: only units that are due and not currently forced.
      // A knowledge point that has never been reviewed has no state yet, and
      // there is nothing bound to it either, so it is simply due.
      final dueState = _dueState(states, moment);
      final neverReviewed = states.isEmpty;
      if (dueState == null && !neverReviewed) {
        continue;
      }
      final item = await _itemFor(point, dueState);
      if (item != null) {
        due.add(item);
      }
    }

    // Boost ordering: a lifted knowledge point floats to the front of its band
    // (x1.8 > x1.3 > 1.0), stable otherwise.
    due.sort((a, b) {
      final fa = boostedIds[a.knowledgePointId] ?? 1.0;
      final fb = boostedIds[b.knowledgePointId] ?? 1.0;
      return fb.compareTo(fa);
    });

    return _interleave(forced, due);
  }

  /// Places active units a few cards after their wrong answer; when nothing
  /// else is queued they simply repeat (annotation 17).
  List<ReviewItem> _interleave(List<ReviewItem> forced, List<ReviewItem> due) {
    if (forced.isEmpty) {
      return due;
    }
    final result = <ReviewItem>[...due];
    for (var i = 0; i < forced.length; i++) {
      final index = (i + 1) * relearnGapCards;
      if (index >= result.length) {
        result.add(forced[i]);
      } else {
        result.insert(index, forced[i]);
      }
    }
    return result;
  }

  /// The most overdue, not-yet-forced unit of [states], or null when nothing
  /// is due.
  CardState? _dueState(List<CardState> states, DateTime now) {
    final eligible = states
        .where((s) => s.forced != 1)
        .where((s) => s.dueAt == null || s.dueAt! <= now.millisecondsSinceEpoch)
        .toList();
    if (eligible.isEmpty) {
      return null;
    }
    eligible.sort((a, b) => (a.dueAt ?? 0).compareTo(b.dueAt ?? 0));
    return eligible.first;
  }

  /// Gets (creating if needed) the unit to present for [point].
  ///
  /// [state] is null for a knowledge point that has never been reviewed: the
  /// real unit state is created once the blank has been chosen (there are no
  /// half-made states, so a knowledge point never shows up twice).
  Future<ReviewItem?> _itemFor(
    KnowledgePoint point,
    CardState? state, {
    String? preferredUnitKey,
  }) async {
    final content = point.content;
    final seedKeywords = [point.title];
    final tags = await tagRepository.tagsForObject(
      objectType: 'knowledge_point',
      objectId: point.id,
    );
    seedKeywords.addAll([
      for (final tag in tags)
        if (tag.name.isNotEmpty) tag.name,
    ]);
    final candidates = ClozeEngine.discoverCandidates(
      content,
      seedKeywords: seedKeywords,
    );
    if (candidates.isEmpty) {
      // Nothing blankable: fall back to an essay-style self-judged unit.
      final fallbackKey = state?.unitKey ?? 'essay';
      final resolved =
          state ?? await ankiRepository.getOrCreateUnitCardState(point.id, fallbackKey);
      return ReviewItem(
        knowledgePoint: point,
        cardState: resolved,
        unitKey: fallbackKey,
        content: content,
        question: point.title,
        answer: content,
        isNew: resolved.repetitions == 0,
      );
    }

    final usedKeys = await ankiRepository.usedClozeSlotKeys(point.id);
    final unitKey = preferredUnitKey ?? state?.unitKey;
    if (state != null &&
        unitKey != null &&
        unitKey.isNotEmpty &&
        candidates.any((c) => c.slotKey == unitKey)) {
      // The unit already bound to this state (a forced relearn draw keeps
      // exactly the blank that was answered wrong).
      return _clozeItem(point, state, candidates, unitKey);
    }

    // Free-blank draw: with probability p try an unused blank, otherwise
    // replay a historical one (spec 1.3.2).
    final exhausted = candidates.every((c) => usedKeys.contains(c.slotKey));
    final ClozeChoice choice;
    try {
      choice = ClozeEngine.chooseSlot(
        candidates: candidates,
        usedSlotKeys: usedKeys,
        exhausted: exhausted,
        newClozeProbability: FurnaceDefaults.newClozeProbability,
        random: random,
      );
    } on StateError {
      return null;
    }

    final slotState = await ankiRepository.getOrCreateUnitCardState(
      point.id,
      choice.slotKey,
    );
    return _clozeItem(point, slotState, candidates, choice.slotKey,
        isNew: choice.isNew);
  }

  Future<ReviewItem> _clozeItem(
    KnowledgePoint point,
    CardState state,
    List<ClozeCandidate> candidates,
    String slotKey, {
    bool isNew = false,
  }) async {
    var candidate = candidates.where((c) => c.slotKey == slotKey).firstOrNull;
    if (candidate == null) {
      // The unit key came from the database and the content changed since:
      // rediscover a blank so the item is still answerable.
      candidate = candidates.first;
      slotKey = candidate.slotKey;
    }
    final answer = candidate.answerIn(point.content);
    final question = '${point.content.substring(0, candidate.start)}'
        '______'
        '${point.content.substring(candidate.start + candidate.length)}';
    await ankiRepository.createClozeSlot(
      knowledgePointId: point.id,
      slotKey: candidate.slotKey,
      definition: jsonEncode({
        'start': candidate.start,
        'length': candidate.length,
      }),
    );
    return ReviewItem(
      knowledgePoint: point,
      cardState: state,
      unitKey: slotKey,
      content: point.content,
      question: question,
      answer: answer,
      slotStart: candidate.start,
      slotLength: candidate.length,
      isNew: isNew || state.repetitions == 0,
    );
  }

  /// Consumes one boost cycle when a lifted knowledge point is actually drawn
  /// (the boost decays after [FurnaceDefaults.boostCycles] draws).
  Future<void> consumeBoost(String knowledgePointId) async {
    final boost = await ankiRepository.boostFor(knowledgePointId);
    if (boost == null) {
      return;
    }
    final remaining = boost.remainingCycles - 1;
    if (remaining <= 0) {
      await ankiRepository.deleteBoost(knowledgePointId);
    } else {
      await ankiRepository.upsertBoost(
        knowledgePointId: knowledgePointId,
        factor: boost.factor,
        remainingCycles: remaining,
      );
    }
  }

  // --- grading -------------------------------------------------------------

  /// Strict-mode comparison: EXACT characters, no normalisation whatsoever
  /// (user annotation 18 - Chinese dictation and English spelling).
  static bool strictMatch(String expected, String submitted) {
    return expected == submitted;
  }

  /// Grades one answer and reschedules the unit.
  Future<ReviewOutcome> grade({
    required ReviewItem item,
    required bool correct,
    required FsrsRating rating,
    String? submitted,
    int? responseSeconds,
    bool strict = true,
    DateTime? now,
  }) async {
    final moment = now ?? DateTime.now();
    final effectiveRating =
        correct ? rating : FsrsRating.again;

    final state = item.cardState;
    final lastReview = state.lastReviewedAt == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(state.lastReviewedAt!);
    final memory = state.stability == null
        ? null
        : FsrsMemory(
            stability: state.stability!,
            difficulty: state.difficulty ?? 5.0,
          );

    final schedule = FsrsScheduler.schedule(
      memory: memory,
      lastReview: lastReview ?? moment,
      now: moment,
      rating: effectiveRating,
    );

    // Wrong answer -> bind THIS blank so it must come back today; correct
    // answers advance the streak and release the binding after two in a row.
    final forcedBefore = state.forced == 1;
    final step = ForcedMachine.grade(
      correct: correct,
      forcedBefore: forcedBefore,
      streakBefore: state.forcedStreak,
      now: moment,
      relearnMinutes: FurnaceDefaults.forcedRelearnMinutes,
      releaseStreak: FurnaceDefaults.forcedConsecutiveCorrect,
    );

    final nextDueAt = correct && !step.forced
        ? schedule.dueAt
        : moment.add(const Duration(minutes: FurnaceDefaults.forcedRelearnMinutes));

    await ankiRepository.updateUnitCardState(
      state.id,
      dueAt: nextDueAt.millisecondsSinceEpoch,
      state: step.forced ? 'learning_forced' : 'review',
      stability: schedule.memory.stability,
      difficulty: schedule.memory.difficulty,
      intervalDays: schedule.scheduledDays.toDouble(),
      repetitions: state.repetitions + 1,
      lapses: correct ? state.lapses : state.lapses + 1,
      forced: step.forced ? 1 : 0,
      forcedStreak: step.forcedStreak,
      lastReviewedAt: moment.millisecondsSinceEpoch,
    );

    await ankiRepository.addReviewLog(
      cardStateId: state.id,
      cardTemplateId: item.unitKey,
      rating: rating.index,
      ratingFsrs: effectiveRating.value,
      correct: correct ? 1 : 0,
      judgeMode: strict ? 'auto' : 'self',
      format: item.slotStart == null ? 'essay' : 'fill',
      msTaken: responseSeconds == null ? null : responseSeconds * 1000,
      unitKey: item.unitKey,
      reviewedAt: moment.millisecondsSinceEpoch,
    );

    await ankiRepository.addClozeHistory(
      knowledgePointId: item.knowledgePointId,
      slotKey: item.unitKey,
      correct: correct ? 1 : 0,
      usedAt: moment.millisecondsSinceEpoch,
    );

    var boosted = const <BoostedItem>[];
    if (!correct) {
      boosted = await _recordWrong(item, moment);
    }

    return ReviewOutcome(
      correct: correct,
      expected: item.answer,
      nextDueAt: nextDueAt,
      scheduledDays: schedule.scheduledDays,
      released: step.released,
      stillForced: step.forced,
      boosted: boosted,
    );
  }

  // --- the day's ledger + tag diffusion ------------------------------------

  /// Records the wrong answer, lifts related knowledge points through the tag
  /// tree, and writes the day's ledger lines (annotation 19).
  Future<List<BoostedItem>> _recordWrong(
    ReviewItem item,
    DateTime moment,
  ) async {
    final wrongTags = await _tagPathsFor(item.knowledgePointId);

    final drafts = <DiffusionLogDraft>[
      DiffusionLogDraft(
        ownerType: 'knowledge',
        kind: 'wrong',
        ownerId: item.knowledgePointId,
        ownerTitle: item.title,
        knowledgePointId: item.knowledgePointId,
        knowledgePointTitle: item.title,
        detail: item.answer,
        occurredAt: moment,
      ),
    ];
    final boosted = <BoostedItem>[];

    if (wrongTags.isNotEmpty) {
      final points = await ankiRepository.getKnowledgePoints();
      for (final other in points) {
        if (other.id == item.knowledgePointId) {
          continue;
        }
        final otherTags = await _tagPathsFor(other.id);
        if (otherTags.isEmpty) {
          continue;
        }
        var bestFactor = 1.0;
        int? bestDistance;
        for (final tag in otherTags) {
          final factor = TagDiffusion.boostFactor(
            wrongPaths: wrongTags,
            candidatePath: tag,
          );
          final distance = TagDiffusion.ledgerDistance(
            wrongPaths: wrongTags,
            candidatePath: tag,
          );
          if (factor > bestFactor) {
            bestFactor = factor;
            bestDistance = distance;
          }
        }
        if (bestFactor <= 1.0 || bestDistance == null) {
          continue;
        }
        await ankiRepository.upsertBoost(
          knowledgePointId: other.id,
          factor: bestFactor,
          remainingCycles: FurnaceDefaults.boostCycles,
        );
        boosted.add(BoostedItem(
          title: other.title,
          factor: bestFactor,
          distance: bestDistance,
        ));
        drafts.add(DiffusionLogDraft(
          ownerType: 'knowledge',
          kind: 'boost',
          ownerId: other.id,
          ownerTitle: other.title,
          knowledgePointId: other.id,
          knowledgePointTitle: other.title,
          distance: bestDistance,
          factor: bestFactor,
          occurredAt: moment,
        ));
      }
    }

    await diffusionLogRepository.appendAll(drafts);
    return boosted;
  }

  Future<List<String>> _tagPathsFor(String knowledgePointId) async {
    final tags = await tagRepository.tagsForObject(
      objectType: 'knowledge_point',
      objectId: knowledgePointId,
    );
    return [
      for (final tag in tags)
        if (tag.path != null && tag.path!.isNotEmpty) tag.path!,
    ];
  }

  // --- Knowledge -> Thread loop --------------------------------------------

  /// Creates a Thread event from a knowledge point (spec 2 loop, R5 item).
  Future<Task> createEventFromItem(ReviewItem item, {String? title}) {
    return taskRepository.createTask(
      title: title ?? item.title,
      description: '来自复习：${item.title}',
    );
  }

  /// Counts for the review header: due now, and how many are pinned as active.
  Future<({int due, int active})> counts({DateTime? now}) async {
    final moment = now ?? DateTime.now();
    final points = await ankiRepository.getKnowledgePoints();
    var due = 0;
    var active = 0;
    for (final point in points) {
      final states = await ankiRepository.unitStatesForKnowledgePoint(point.id);
      active += states.where((s) => s.forced == 1).length;
      if (_dueState(states, moment) != null) {
        due++;
      }
    }
    return (due: due, active: active);
  }
}

final reviewServiceProvider = Provider<ReviewService>((ref) {
  return ReviewService(
    ankiRepository: ref.watch(ankiRepositoryProvider),
    tagRepository: ref.watch(tagRepositoryProvider),
    taskRepository: ref.watch(taskRepositoryProvider),
    diffusionLogRepository: ref.watch(diffusionLogRepositoryProvider),
  );
});
