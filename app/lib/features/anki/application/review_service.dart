import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/database.dart';
import '../../../data/repositories/anki_repository.dart';
import '../../../data/repositories/diffusion_log_repository.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../data/repositories/review_plan_repository.dart';
import '../../../data/repositories/tag_repository.dart';
import '../../../data/repositories/task_repository.dart';
import '../../../domain/services/cloze/cloze_engine.dart';
import '../../../domain/services/cloze/tag_diffusion.dart';
import '../../../domain/services/cognitive/cognitive_model.dart';
import '../../../domain/services/config/furnace_defaults.dart';
import '../../../domain/services/srs/fsrs_scheduler.dart';
import 'review_advisory.dart';

/// How one queued unit is presented and judged.
enum ReviewItemKind {
  /// A blank in the material, answered by typing.
  fillBlank,

  /// A single-choice card, answered by picking one of [ReviewItem.options].
  mcq,

  /// A prompt whose answer is prose: the user judges it, the app never compares
  /// it.
  essay,
}

/// Who decides whether an answer is right.
///
/// The value is written verbatim to `review_logs.judge_mode`, whose only two
/// values are `auto` / `self` (see `ReviewLogs.judgeMode`). Lenient auto grading
/// is therefore recorded as `auto` as well: `judge_mode` says *who* judged, and
/// [ReviewService.strictMatch] vs [ReviewService.lenientMatch] says how.
enum JudgeMode {
  /// The app compared the answer with the expected one.
  auto('auto'),

  /// The user judged their own answer after seeing the expected one.
  self('self');

  const JudgeMode(this.wireValue);

  final String wireValue;
}

/// How `auto` compares characters.
enum AutoStrictness {
  /// Exact characters, no normalisation at all (user annotation 18 - Chinese
  /// dictation and English spelling).
  strict,

  /// What a human would accept: whitespace, full/half-width forms, punctuation,
  /// case, and a small typo budget. See [ReviewService.lenientMatch].
  lenient,
}

/// One ready-to-answer unit in the review queue.
class ReviewItem {
  const ReviewItem({
    required this.knowledgePoint,
    required this.cardState,
    required this.unitKey,
    required this.content,
    required this.question,
    required this.answer,
    this.kind = ReviewItemKind.fillBlank,
    this.options = const [],
    this.hint,
    this.templateId,
    this.clozeSlotKey,
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

  /// The exact expected answer for the blank, or (for [ReviewItemKind.mcq]) the
  /// option the card marks as correct.
  final String answer;

  final ReviewItemKind kind;

  /// The choices of an [ReviewItemKind.mcq] card, in the order the template
  /// stored them. Empty for the other kinds.
  final List<String> options;

  /// The author's hint for this unit, if there is one. Shown only when the user
  /// asks for it, and never written to the review log: it is not a graded event.
  final String? hint;

  /// The card template this unit came from, or null for a unit the review engine
  /// derived from the knowledge point's content.
  final String? templateId;

  /// The cloze slot of a content-derived blank (`c0`, `c1`, …). Null for
  /// template-backed units, which is how [ReviewService.grade] knows whether the
  /// cloze history applies at all.
  final String? clozeSlotKey;

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
/// - Three ways to judge an answer, all kept: strict auto (characters exactly,
///   no normalisation at all - annotation 18), lenient auto ([lenientMatch]) and
///   self ([JudgeMode.self], for prose). The engine only produces the verdict
///   for the first two; who judged is recorded in `review_logs.judge_mode`.
/// - Every unit the user can create is reviewable: the content-derived blanks
///   *and* the card templates authored by hand, imported from a package or
///   written by the AI tool (see [_statesFor]).
/// - Answering wrong lifts related knowledge points through the tag tree and
///   records the day's ledger for the separate insight screen (annotation 19).
class ReviewService {
  ReviewService({
    required this.ankiRepository,
    required this.tagRepository,
    required this.taskRepository,
    required this.diffusionLogRepository,
    Random? random,
    CognitiveModel? cognitiveModel,
  })  : random = random ?? Random(),
        cognitiveModel = cognitiveModel ?? const MindNetCognitiveModel();

  final AnkiRepository ankiRepository;
  final TagRepository tagRepository;
  final TaskRepository taskRepository;
  final DiffusionLogRepository diffusionLogRepository;
  final Random random;

  /// The advisor (D1). It orders the model band and produces the two
  /// model-owned numbers; it never decides `dueAt`, and a failure inside it
  /// must not stop a review. Injected rather than constructed at the call site
  /// so the implementation stays swappable (`cognitiveModelProvider`, and
  /// `HeuristicCognitiveModel` when the model must not be consulted).
  final CognitiveModel cognitiveModel;

  /// How many cards must pass before an active (wrong-answer) blank returns.
  static const int relearnGapCards = 3;

  // --- queue ---------------------------------------------------------------

  /// Builds today's queue: due knowledge points, plus active units pinned to
  /// reappear inside the same day.
  ///
  /// [plan] is today's per-group load, or null when the caller has nothing
  /// configured. It has exactly one effect: a group whose daily **review**
  /// allowance is spent stops drawing *new* cards for the rest of the day
  /// (user request "每天各个卡组的任务量"). With `plan == null` - which is what
  /// every install that never opened the plan UI passes - the queue is built
  /// exactly as it was before the plan existed.
  ///
  /// **A card answered wrong today is never suppressed by the cap.** The forced
  /// loop below runs before the cap is consulted and ignores it entirely: an
  /// error has to reappear in the same day's queue until it is answered right
  /// twice in a row (annotation 17). A daily allowance limits how much *new*
  /// material a group introduces; it must not be able to hold a mistake open.
  Future<List<ReviewItem>> buildQueue({
    DateTime? now,
    ReviewDayLoad? plan,
  }) async {
    final moment = now ?? DateTime.now();
    final points = await ankiRepository.getKnowledgePoints();
    final due = <ReviewItem>[];
    final forced = <ReviewItem>[];
    final boostedIds = <String, double>{};

    // The groups that have used up their daily allowance. Empty for a database
    // with no plan at all, which is also what makes the membership queries below
    // free in that case.
    final exhaustedGroups = plan?.reviewExhaustedGroups ?? const <String>{};
    final exhaustedMembers = <String, Set<String>>{};
    var exhaustedMembersLoaded = false;

    for (final boost in await ankiRepository.getAllBoosts()) {
      boostedIds[boost.knowledgePointId] = boost.factor;
    }

    for (final point in points) {
      final templates =
          await ankiRepository.getTemplatesForKnowledgePoint(point.id);
      final contentStates =
          await ankiRepository.unitStatesForKnowledgePoint(point.id);
      final states = await _statesFor(contentStates, templates);
      final forcedStates =
          states.where((state) => state.forced == 1).toList();
      for (final state in forcedStates) {
        final item = await _itemFor(
          point,
          state,
          templates: templates,
          preferredUnitKey: state.unitKey,
        );
        if (item != null) {
          forced.add(item);
        }
      }

      // Normal draw: only units that are due and not currently forced.
      //
      // A knowledge point that has never been drawn has no content-derived unit
      // yet, and then there is nothing bound to it either, so it is simply due.
      // A knowledge point whose *authored* cards are not due still gets its
      // content-derived unit created on the next draw: the free-blank mechanism
      // (spec 1.3.2) is what brings the same material back through different
      // blanks, and a card the user wrote must not switch it off.
      final dueState = _dueState(states, moment);

      // Today's per-group allowance is consulted BEFORE the "nothing new to
      // draw" exit below, not after it. The order is the rule: a knowledge point
      // whose unit is not due because its *only* unit has already been created
      // is still a card this group would present for the first time today, and a
      // cap that let it through here would not be a cap at all.
      //
      // "New" is decided by `repetitions`, not by `dueState == null`. The first
      // build of a queue already creates the unit row of a card it drew (with
      // `due_at` NULL and `repetitions` 0), so the second build sees a state
      // while the card is still one the user has never actually answered -
      // `ReviewItem.isNew` uses exactly this counter, and the cap has to agree
      // with it or it would let precisely those cards through.
      if (exhaustedGroups.isNotEmpty && _isUnseenDraw(states, moment)) {
        if (!exhaustedMembersLoaded) {
          for (final entry in (await ankiRepository.tagPathsForObjects(
            objectType: 'knowledge_point',
            objectIds: [for (final p in points) p.id],
          ))
              .entries) {
            exhaustedMembers[entry.key] = entry.value.toSet();
          }
          exhaustedMembersLoaded = true;
        }
        final pointPaths = exhaustedMembers[point.id] ?? const <String>{};
        if (exhaustedGroups.every((group) =>
            (plan!.pathsByGroup[group] ?? const <String>[])
                .any(pointPaths.contains))) {
          continue;
        }
      }

      if (dueState == null && contentStates.isNotEmpty) {
        continue;
      }
      final item = await _itemFor(point, dueState, templates: templates);
      if (item != null) {
        due.add(item);
      }
    }

    // Banded order (D1/D4/D5). The model band's ordering is the model's own
    // total order - this call site only decides which band an item belongs to,
    // never how two items inside a band compare. Boost ordering used to be a
    // sort here; it is now the `boosted` band, which is what keeps exactly one
    // rule per band.
    final candidates = <ReviewCandidate>[];
    final byCandidate = Map<ReviewCandidate, ReviewItem>.identity();
    for (final item in [...forced, ...due]) {
      final candidate = ReviewCandidate(
        knowledgePointId: item.knowledgePointId,
        row: item.cardState,
        isNew: item.isNew,
      );
      candidates.add(candidate);
      byCandidate[candidate] = item;
    }

    final ordering = ReviewAdvisory.order(
      candidates: candidates,
      model: cognitiveModel,
      nowHours: modelHoursOf(moment),
      boostFactorByKnowledgePoint: boostedIds,
    );

    // Forced items keep the caller's order and are handed to `_interleave`
    // unchanged: where a wrong-answer blank reappears is annotation 17's rule,
    // not the advisor's.
    final orderedForced = <ReviewItem>[];
    final orderedDue = <ReviewItem>[];
    for (final candidate in ordering.ranked) {
      final item = byCandidate[candidate]!;
      if (ordering.bandByCardStateId[candidate.cardStateId] ==
          ReviewBand.forced) {
        orderedForced.add(item);
      } else {
        orderedDue.add(item);
      }
    }

    return _interleave(orderedForced, orderedDue);
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

  /// Whether the next normal draw of this knowledge point would be a card the
  /// user has never answered.
  ///
  /// True when every unit that could be drawn right now still has
  /// `repetitions == 0`. The `forced != 1` filter matters: a bound unit is
  /// re-presented by the wrong-answer rule and is not what the daily cap is
  /// about, while the eligibility filter is the same one [_dueState] uses - so
  /// a card with a real schedule (a review) makes this false even when its
  /// `dueAt` is null because it was only ever *drawn*, never answered.
  bool _isUnseenDraw(List<CardState> states, DateTime now) {
    final drawable = states
        .where((s) => s.forced != 1)
        .where((s) => s.dueAt == null || s.dueAt! <= now.millisecondsSinceEpoch);
    // No state at all: the knowledge point has never been drawn, so this is new
    // material by definition.
    return drawable.every((s) => s.repetitions == 0);
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
    eligible.sort((a, b) {
      final byDue = (a.dueAt ?? 0).compareTo(b.dueAt ?? 0);
      // Two units can be equally due - both never reviewed, so both have a null
      // `dueAt`. The id breaks the tie so the draw is reproducible instead of
      // depending on sort stability.
      return byDue != 0 ? byDue : a.id.compareTo(b.id);
    });
    return eligible.first;
  }

  /// The content-derived unit states of a knowledge point plus one state per
  /// card template.
  ///
  /// The second half is what makes a card the user actually authored reviewable.
  /// `AnkiRepository.getOrCreateCardState` keys a template's state by
  /// `card_template_id` and leaves `knowledge_point_id` NULL, so it never
  /// appears in `unitStatesForKnowledgePoint`; the template is the only link
  /// back to the material. Without this, the manage page, the package importer
  /// and the AI tool all wrote cards that could never come up.
  ///
  /// `getOrCreateCardState` is the repository's find-or-create for exactly that
  /// key (and `card_states` is UNIQUE on `card_template_id`), so a template
  /// without a state - a card that is otherwise invisible to review - gets one
  /// here.
  Future<List<CardState>> _statesFor(
    List<CardState> contentStates,
    List<CardTemplate> templates,
  ) async {
    final states = [...contentStates];
    final seen = {for (final state in states) state.id};
    for (final template in templates) {
      final state = await ankiRepository.getOrCreateCardState(template.id);
      if (seen.add(state.id)) {
        states.add(state);
      }
    }
    return states;
  }

  /// The hint to show for a unit derived from the content.
  ///
  /// Such a unit has no template row of its own, so the only hints the user
  /// could have written for this material are the ones on its cards; the first
  /// non-empty one is used. A template-backed unit carries its own hint and
  /// never comes through here.
  static String? _materialHint(List<CardTemplate> templates) {
    for (final template in templates) {
      final hint = template.hint?.trim();
      if (hint != null && hint.isNotEmpty) {
        return hint;
      }
    }
    return null;
  }

  /// Gets (creating if needed) the unit to present for [point].
  ///
  /// [state] is null for a knowledge point that has never been reviewed: the
  /// real unit state is created once the blank has been chosen (there are no
  /// half-made states, so a knowledge point never shows up twice).
  Future<ReviewItem?> _itemFor(
    KnowledgePoint point,
    CardState? state, {
    required List<CardTemplate> templates,
    String? preferredUnitKey,
  }) async {
    final templateId = state?.cardTemplateId;
    if (state != null && templateId != null) {
      return _templateItem(point, state, templates: templates);
    }

    final content = point.content;
    final hint = _materialHint(templates);
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
        // Prose: the app never compares it, the user judges it (that is what
        // `ReviewItemKind.essay` means downstream).
        kind: ReviewItemKind.essay,
        hint: hint,
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
      return _clozeItem(point, state, candidates, unitKey, hint: hint);
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
        isNew: choice.isNew, hint: hint);
  }

  /// Presents a card template (`mcq` / `essay` / a preset `fill_blank`).
  ///
  /// The template stores its choices `\u0001`-separated (see
  /// `AnkiRepository._encodeOptions`; the manage page and the package importer
  /// write and read the same encoding).
  Future<ReviewItem?> _templateItem(
    KnowledgePoint point,
    CardState state, {
    required List<CardTemplate> templates,
  }) async {
    final templateId = state.cardTemplateId;
    if (templateId == null) {
      return null;
    }
    final template =
        templates.where((t) => t.id == templateId).firstOrNull ??
            await ankiRepository.getCardTemplateById(templateId);
    if (template == null) {
      // The template is gone but its state row is not: that row is debris, and
      // `AnkiRepository.purgeOrphanKnowledgeRows` is what removes it.
      return null;
    }

    final hint = template.hint?.trim();
    final question = template.question.trim();
    final answer = template.answer.trim();
    final options = _decodeOptions(template.options);
    var kind = ReviewItemKind.essay;
    switch (template.type) {
      case 'mcq':
        // A choice card with no choices cannot be answered by choosing, and is
        // dropped from the queue by no one: it is presented as a self-judged
        // card instead, so the material stays reviewable.
        kind = options.isEmpty ? ReviewItemKind.essay : ReviewItemKind.mcq;
      case 'fill_blank':
        kind = ReviewItemKind.fillBlank;
      case 'essay':
        kind = ReviewItemKind.essay;
      default:
        // A type written by a build newer than this one: showing the answer and
        // letting the user judge it is the only presentation that cannot be
        // wrong about a format this build does not know.
        kind = ReviewItemKind.essay;
    }

    return ReviewItem(
      knowledgePoint: point,
      cardState: state,
      unitKey: 'preset:${template.id}',
      content: point.content,
      // A fill-blank template may carry the `___` marker in its question (the
      // auto-generator writes it that way); the practice screen shows blanks as
      // `______` throughout.
      question: kind == ReviewItemKind.essay
          ? question
          : _renderBlank(template.clozeTemplate ?? question),
      answer: answer,
      kind: kind,
      options: kind == ReviewItemKind.mcq ? options : const [],
      hint: (hint == null || hint.isEmpty) ? null : hint,
      templateId: template.id,
      isNew: state.repetitions == 0,
    );
  }

  static List<String> _decodeOptions(String? raw) {
    if (raw == null || raw.isEmpty) {
      return const [];
    }
    return [
      for (final option in raw.split('\u0001'))
        if (option.trim().isNotEmpty) option.trim(),
    ];
  }

  static String _renderBlank(String question) =>
      question.replaceAll(RegExp('_{3,}'), '______');

  Future<ReviewItem> _clozeItem(
    KnowledgePoint point,
    CardState state,
    List<ClozeCandidate> candidates,
    String slotKey, {
    bool isNew = false,
    String? hint,
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
      hint: hint,
      // Only a content-derived blank has a slot: it is the one unit whose draws
      // belong in `cloze_history`.
      clozeSlotKey: candidate.slotKey,
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

  /// Lenient comparison: what a human would accept.
  ///
  /// Both sides are reduced by [normalizeForLenient] - full-width forms folded
  /// to half-width, whitespace and punctuation dropped, case ignored - and then
  /// may differ by up to [typoBudgetFor] substituted characters. The order
  /// matters: normalising first is what makes "叶绿体。" and "叶绿体" the same
  /// answer, so the typo budget is never spent on punctuation the user could not
  /// have typed on purpose.
  ///
  /// It is deliberately *not* the strict comparison: 语文默写 and English
  /// spelling stay strict (annotation 18), and this is the mode for "I knew it,
  /// I just typed it sloppily".
  static bool lenientMatch(String expected, String submitted) {
    final wanted = normalizeForLenient(expected);
    final actual = normalizeForLenient(submitted);
    if (wanted == actual) {
      return true;
    }
    if (wanted.isEmpty || actual.isEmpty) {
      return false;
    }
    return _withinTypoBudget(wanted, actual, typoBudgetFor(wanted.length));
  }

  /// The form lenient grading compares: no whitespace, no punctuation, no case.
  ///
  /// Dropping punctuation rather than mapping it is what lets a Chinese comma
  /// equal an English one *and* a missing full stop equal none at all. It also
  /// makes `1/2` compare equal to `12`; that is the price of tolerating a
  /// missing comma, and it is paid only in lenient mode, with strict mode one
  /// tap away. Full-width forms fold onto half-width before the punctuation
  /// sweep (the Unicode "compatibility" idea, in the small: U+FF01..U+FF5E is
  /// U+0021..U+007E shifted by 0xFEE0, plus the ideographic space).
  static String normalizeForLenient(String value) {
    final buffer = StringBuffer();
    for (final rune in value.runes) {
      buffer.writeCharCode(
        rune >= 0xFF01 && rune <= 0xFF5E ? rune - 0xFEE0 : rune,
      );
    }
    return buffer.toString().replaceAll(_lenientNoise, '').toLowerCase();
  }

  /// How many single-character slips are still "the same answer".
  ///
  /// One for anything short, two only once the answer is long enough
  /// (≥ 12 characters) that two edits cannot turn one fact into another. A
  /// three-character answer therefore accepts exactly one wrong character, which
  /// is the line between 叶绿体/叶绿休 and 叶绿体/线粒体.
  static int typoBudgetFor(int length) => length >= 12 ? 2 : 1;

  /// Whether [a] and [b] differ in at most [budget] positions.
  ///
  /// Insertions and deletions are deliberately not forgiven: a character that is
  /// missing or extra changes what the answer says (叶绿体 vs 叶绿 is a different
  /// answer, not a slip). The only insertions and deletions lenient mode
  /// tolerates are whitespace and punctuation, and
  /// [normalizeForLenient] has already removed those.
  static bool _withinTypoBudget(String a, String b, int budget) {
    if (a.length != b.length) {
      return false;
    }
    var differences = 0;
    for (var i = 0; i < a.length; i++) {
      if (a.codeUnitAt(i) != b.codeUnitAt(i) && ++differences > budget) {
        return false;
      }
    }
    return true;
  }

  /// Whitespace and punctuation, including the marks a Chinese IME produces and
  /// the full-width forms the fold above has already turned into ASCII.
  ///
  /// The ASCII ranges are the ones that matter after folding (`!-/`, `:-@`,
  /// `[-\``, `{-~`); the CJK block and the full-width ranges cover what the
  /// fold cannot reach.
  static final RegExp _lenientNoise = RegExp(
    r'[\s!-/:-@\[-`{-~'
    r'\u00a0\u00b7\u2010-\u2027\u2030-\u205e\u2212'
    r'\u3000-\u303f\u30fb\uff01-\uff0f\uff1a-\uff20\uff3b-\uff40\uff5b-\uff65]',
  );

  /// The index of the option that [answer] names, or null when none does.
  ///
  /// Authors type the option itself (`叶绿体`) or its letter (`B`); both are
  /// accepted, because the manage page's answer field forces neither shape and a
  /// choice card the app cannot match would otherwise be unanswerable.
  static int? correctOptionIndex({
    required List<String> options,
    required String answer,
  }) {
    final wanted = answer.trim();
    if (wanted.isEmpty) {
      return null;
    }
    for (var i = 0; i < options.length; i++) {
      if (options[i].trim() == wanted) {
        return i;
      }
    }
    final letter = wanted.toUpperCase();
    if (letter.length == 1) {
      for (var i = 0; i < options.length; i++) {
        if (_optionLetterOf(options[i].trim()) == letter) {
          return i;
        }
      }
    }
    return null;
  }

  /// Auto-judges one multiple-choice answer **by option identity**: the option
  /// the user tapped must be the option the card's answer names. Text is never
  /// compared, so a typo can neither pass nor fail a choice.
  ///
  /// Returns null when the card cannot be auto-judged at all - nothing was
  /// selected, the options are missing, or the stored answer names an option
  /// that does not exist. The caller then presents the card for self-judging
  /// instead of guessing.
  static bool? mcqMatch({
    required List<String> options,
    required String answer,
    String? selected,
  }) {
    final index = correctOptionIndex(options: options, answer: answer);
    if (index == null || selected == null) {
      return null;
    }
    return options[index].trim() == selected.trim();
  }

  /// The leading `A`/`B`/… of an option written as `B. …`, `B、…` or `B) …`.
  static String? _optionLetterOf(String option) {
    final match = RegExp(r'^([A-Za-z])\s*[.、,，:：)）]').firstMatch(option);
    return match?.group(1)?.toUpperCase();
  }

  /// Grades one answer and reschedules the unit.
  ///
  /// [judgeMode] says who judged it and is written to `review_logs.judge_mode`
  /// as it stands. `auto` covers both strict and lenient comparison: the column
  /// has no third value, and *how* the `auto` verdict was reached is a property
  /// of the caller's [AutoStrictness], not of the log.
  /// [reviewedSolution] and [closeness] describe what happened *after* a
  /// failed recall, which is a different event in the model's vocabulary
  /// (MindNet `docs/IO_PROTOCOL.md` §2.3: `wrong + reviewed_solution: true` →
  /// `retrieval_failure_feedback`). They are only read when [correct] is false:
  ///
  ///  * `reviewedSolution == false` (the default) - a bare miss. The model
  ///    records a `lapse`, which *cuts* stability.
  ///  * `reviewedSolution == true` - the user read the expected answer and the
  ///    recall was still recognisable. The model records
  ///    `retrieval_failure_feedback`, whose stability gain is scaled by
  ///    [closeness], so "差点想起来" is not recorded as forgetting.
  ///
  /// Neither case moves FSRS (D1): [correct] being false already forces Again,
  /// and the forced-relearn binding below is identical for both. The distinction
  /// reaches the model's two columns and the log's v9 columns, nothing else.
  Future<ReviewOutcome> grade({
    required ReviewItem item,
    required bool correct,
    required FsrsRating rating,
    String? submitted,
    int? responseSeconds,
    JudgeMode judgeMode = JudgeMode.auto,
    bool reviewedSolution = false,
    double closeness = 0.5,
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

    // D2: the model owns exactly two columns, and this is their only writer.
    // `updateUnitCardState` above stays the only writer of stability /
    // difficulty / dueAt, so neither side can overwrite the other. `state` is
    // the row *before* this review - the seam's contract is "row plus event".
    //
    // Advisement never blocks a review (D1): if the model is unavailable or
    // throws, the review still completes and only the model's two columns keep
    // their previous values.
    try {
      final modelState = cognitiveModel.modelStateAfterReview(
        state,
        rating: effectiveRating.value,
        nowHours: modelHoursOf(moment),
        // Both only matter for a failed recall; `DsrCardState.eventFor` ignores
        // them for a successful one, so passing them unconditionally cannot
        // change a right answer's numbers.
        reviewedSolution: reviewedSolution,
        closeness: closeness,
      );
      await ankiRepository.updateModelState(
        state.id,
        encodingStrength: modelState.r0,
        savings: modelState.sigma,
      );
    } catch (_) {
      // Deliberately swallowed: the cognitive model is an advisor, and a
      // review that was already recorded must not be reported as failed
      // because the advisor misbehaved.
    }

    await ankiRepository.addReviewLog(
      cardStateId: state.id,
      // The real template id for a template-backed card; for a content-derived
      // unit the only id there is is its unit key, which is what this column
      // received before templates were reviewable at all.
      cardTemplateId: item.templateId ?? item.unitKey,
      rating: rating.index,
      ratingFsrs: effectiveRating.value,
      correct: correct ? 1 : 0,
      judgeMode: judgeMode.wireValue,
      format: _formatOf(item),
      msTaken: responseSeconds == null ? null : responseSeconds * 1000,
      unitKey: item.unitKey,
      // NULL, not false, for every right answer: the question "did you read the
      // answer afterwards?" is not asked when the answer came back, and a `0`
      // here would make the log claim it was.
      reviewedSolution: correct ? null : reviewedSolution,
      closeness: correct || !reviewedSolution ? null : closeness,
      reviewedAt: moment.millisecondsSinceEpoch,
    );

    // `cloze_history` is the free-blank draw's memory: which slots have been
    // used decides whether the next draw creates a new blank or replays one
    // (spec 1.3.2). A template-backed card has no slot, and writing its unit key
    // here would claim a blank that does not exist.
    if (item.clozeSlotKey != null) {
      await ankiRepository.addClozeHistory(
        knowledgePointId: item.knowledgePointId,
        slotKey: item.clozeSlotKey!,
        correct: correct ? 1 : 0,
        usedAt: moment.millisecondsSinceEpoch,
      );
    }

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

  /// The value for `review_logs.format`, whose documented vocabulary is
  /// `mcq / mcq_multi / ordered_multi / fill / essay`. This build stores no
  /// multi-answer card, so a choice card is a single `mcq`.
  static String _formatOf(ReviewItem item) => switch (item.kind) {
        ReviewItemKind.mcq => 'mcq',
        ReviewItemKind.essay => 'essay',
        ReviewItemKind.fillBlank => 'fill',
      };

  // --- the day's ledger + tag diffusion ------------------------------------

  /// Records the wrong answer, lifts related knowledge points through the tag
  /// tree, and writes the day's ledger lines (annotation 19).
  ///
  /// **This is a heuristic, not a model quantity** (D5, MINDNET_CONTRACT §6.5):
  /// `TagDiffusion` walks the tag tree undirected and multiplies by
  /// `1.8 / 1.3`, numbers that have no calibration source. It is kept because
  /// it demonstrably helps today, and it is kept *separate*: the lift becomes
  /// its own `boosted` band (`ReviewAdvisory`), never a term inside the model's
  /// score, and its conclusion must not be shown side by side with the model's
  /// diagnosis as if they were the same kind of statement - the two can
  /// disagree (a point the model calls a dead end can still be lifted here).
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
      // Same unit set the queue draws from, so the counter cannot promise cards
      // the queue would never show.
      final states = await _statesFor(
        await ankiRepository.unitStatesForKnowledgePoint(point.id),
        await ankiRepository.getTemplatesForKnowledgePoint(point.id),
      );
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
    // The one place the app decides which model implementation is in use.
    cognitiveModel: ref.watch(cognitiveModelProvider),
  );
});
