import 'package:drift/drift.dart';

import '../../domain/services/config/furnace_defaults.dart';
import '../../features/anki/application/card_type_preference.dart';
import '../../features/anki/application/judge_mode_preference.dart';
import '../database/database.dart';
import 'anki_repository.dart';

/// Persistence for the user's review preferences and the per-group daily plan.
///
/// Kept separate from `SettingsRepository` because it belongs to the Knowledge
/// module, not to the app-wide single-row settings: everything here is either a
/// review preference or a row per card group, and the two share one reason to
/// change (the review surface).
///
/// "卡组" is a **tag**, and a group covers that tag's whole subtree. That is how
/// the rest of the app already reads the tag tree - `TagRepository` keeps a full
/// `path` (`文化课/数学`) up to date in cascade, and both `getTagsUnderPath` and
/// `TagDiffusion` treat a path as covering everything below it - so a plan on a
/// parent tag has to include the knowledge points filed under its children, or
/// "语文" would mean nothing whenever the user filed cards under "语文/作文".
class ReviewPlanRepository {
  ReviewPlanRepository(this._db, this._anki);

  final AppDatabase _db;
  final AnkiRepository _anki;

  /// The card-group tag paths of a set of knowledge points, keyed by id.
  ///
  /// Exposed through the repository rather than making the plan surface reach
  /// for `AnkiRepository` itself: the plan's definition of "which group does this
  /// card belong to" has to be one implementation, and it lives here.
  Future<Map<String, List<String>>> knowledgePointTagPaths(
    Iterable<String> knowledgePointIds,
  ) =>
      _anki.tagPathsForObjects(
        objectType: 'knowledge_point',
        objectIds: knowledgePointIds,
      );

  // --- review preferences --------------------------------------------------

  /// The persisted default judging mode, or [JudgeModePreference.strict] when
  /// the user never chose (NULL) - today's behaviour.
  Future<JudgeModePreference> getJudgeModePreference() async {
    final row = await _settingsRow();
    return JudgeModePreference.fromStorage(row?.ankiJudgeMode);
  }

  /// The persisted card type preference, or [CardTypePreference.mixed] (the
  /// fill-blank fallback) when the user never chose.
  Future<CardTypePreference> getCardTypePreference() async {
    final row = await _settingsRow();
    return CardTypePreference.fromStorage(row?.ankiCardTypePreference);
  }

  /// Both preferences in one read, for a screen that shows them together.
  Future<AnkiReviewPreferences> getPreferences() async {
    final row = await _settingsRow();
    return AnkiReviewPreferences(
      judgeMode: JudgeModePreference.fromStorage(row?.ankiJudgeMode),
      cardType: CardTypePreference.fromStorage(row?.ankiCardTypePreference),
    );
  }

  /// Stores the default judging mode.
  Future<void> setJudgeModePreference(JudgeModePreference preference) =>
      _writeSettings(ankiJudgeMode: preference.storageValue);

  /// Stores the card type preference.
  Future<void> setCardTypePreference(CardTypePreference preference) =>
      _writeSettings(ankiCardTypePreference: preference.storageValue);

  // --- per-group daily plan ------------------------------------------------

  /// Every configured group target, ordered by the group's tag path.
  Future<List<CardGroupPlan>> groupPlans() async {
    final rows = await (_db.select(_db.reviewGroupPlans).join([
      innerJoin(
        _db.tags,
        _db.tags.id.equalsExp(_db.reviewGroupPlans.tagId),
      ),
    ])
          ..orderBy([OrderingTerm.asc(_db.tags.path)]))
        .get();
    return [
      for (final row in rows)
        CardGroupPlan(
          id: row.readTable(_db.reviewGroupPlans).id,
          tagId: row.readTable(_db.reviewGroupPlans).tagId,
          tagPath: row.readTable(_db.tags).path ?? '',
          newCardsPerDay: row.readTable(_db.reviewGroupPlans).newCardsPerDay,
          reviewCardsPerDay:
              row.readTable(_db.reviewGroupPlans).reviewCardsPerDay,
        ),
    ];
  }

  /// Creates or replaces [tagId]'s daily target.
  ///
  /// The row id is derived from the tag id rather than minted, so "one row per
  /// tag" is enforced by the primary key as well as by the unique index - an
  /// upsert can never leave a second, older target behind for the same group.
  Future<void> setGroupPlan({
    required String tagId,
    required int newCardsPerDay,
    required int reviewCardsPerDay,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.transaction(() async {
      // Never store a negative target: -1 is not a smaller limit than 0, it is a
      // typo, and every reader would then have to special-case it.
      if (newCardsPerDay < 0 || reviewCardsPerDay < 0) {
        throw ArgumentError('daily targets must not be negative');
      }
      await _db.into(_db.reviewGroupPlans).insert(
            ReviewGroupPlansCompanion.insert(
              id: 'rgp::$tagId',
              tagId: tagId,
              newCardsPerDay: Value(newCardsPerDay),
              reviewCardsPerDay: Value(reviewCardsPerDay),
              createdAt: now,
              updatedAt: now,
            ),
            onConflict: DoUpdate(
              (_) => ReviewGroupPlansCompanion(
                newCardsPerDay: Value(newCardsPerDay),
                reviewCardsPerDay: Value(reviewCardsPerDay),
                updatedAt: Value(now),
              ),
              target: [_db.reviewGroupPlans.tagId],
            ),
          );
    });
  }

  /// Removes [tagId]'s target, which returns the group to "not configured"
  /// (unlimited) rather than to a zero limit.
  Future<void> clearGroupPlan(String tagId) async {
    await (_db.delete(_db.reviewGroupPlans)
          ..where((t) => t.tagId.equals(tagId)))
        .go();
  }

  /// Drops the targets of tags that are about to be deleted.
  ///
  /// Called by `TagRepository.deleteTag` inside its own transaction. The foreign
  /// key on `review_group_plans.tag_id` already states the intent, but
  /// `PRAGMA foreign_keys` is only switched on in `beforeOpen` and an older file
  /// may never have had it on - and a plan row left behind on a tag id that no
  /// longer resolves is invisible debris that a later, unrelated tag id could
  /// collide with. The cleanup is therefore explicit rather than delegated.
  ///
  /// Deleting a *parent* tag removes its whole subtree, so every id in [tagIds]
  /// is cleared, not only the root.
  Future<void> deletePlansForTags(Iterable<String> tagIds) async {
    final ids = tagIds.toSet().toList();
    if (ids.isEmpty) {
      return;
    }
    await (_db.delete(_db.reviewGroupPlans)..where((t) => t.tagId.isIn(ids)))
        .go();
  }

  /// The tag paths a group covers: the tag itself plus every tag under it.
  ///
  /// Read from the database rather than derived from the group's own path,
  /// because the interesting question is which tags *exist* under it: a card
  /// filed under `数学/函数` belongs to the `数学` group, while a card under a
  /// sibling (`数学/几何`) does not.
  Future<List<String>> pathsForGroup(String tagId) async {
    final tag = await (_db.select(_db.tags)..where((t) => t.id.equals(tagId)))
        .getSingleOrNull();
    if (tag == null || tag.path == null || tag.path!.isEmpty) {
      return const [];
    }
    final path = tag.path!;
    final under = await (_db.select(_db.tags)
          ..where((t) => t.path.equals(path) | t.path.like('$path/%')))
        .get();
    return [
      for (final row in under)
        if (row.path != null && row.path!.isNotEmpty) row.path!,
    ];
  }

  /// Today's plan versus today's actual, per configured group.
  ///
  /// Counts, for every group:
  ///
  ///  * `alreadyDoneToday` - review logs written since local midnight whose
  ///    knowledge point carries any tag under the group;
  ///  * `newDoneToday` - how many of those points were introduced **today**
  ///    (their first review ever is today), i.e. how many new cards of the
  ///    group's daily new-card allowance are spent;
  ///  * `reviewDoneToday` - the rest of the log rows: answers on material the
  ///    group already had before today, which is what the review allowance is
  ///    about;
  ///  * `newRemaining` - the new-card allowance left (never null: a group with
  ///    `newCardsPerDay == 0` simply has none today);
  ///  * `remainingReviews` - the review allowance left, or null when the group
  ///    has no positive review target (i.e. it is not capped).
  ///
  /// A knowledge point's logs are counted in exactly one of the two buckets:
  /// re-answers of a card that was introduced today are neither a review of old
  /// material nor a second new card, so they only add to `alreadyDoneToday`.
  ///
  /// "Today" is the local calendar day: a daily plan that rolled over at UTC
  /// midnight would hand a user east of Greenwich a fresh allowance in the
  /// middle of their evening.
  Future<ReviewDayLoad> loadDay({DateTime? now}) async {
    final moment = now ?? DateTime.now();
    final dayStart = DateTime(moment.year, moment.month, moment.day);
    final plans = await groupPlans();
    if (plans.isEmpty) {
      // Nothing configured: no cap anywhere, so not even the usage query runs.
      return ReviewDayLoad.empty(dayStart: dayStart);
    }

    final done = await _anki.reviewCountsPerKnowledgePointSince(
      dayStart.millisecondsSinceEpoch,
    );
    // The split between "introduced today" and "already had it" comes from the
    // log history, not from the current repetitions column.
    final firstSeenToday = done.isEmpty
        ? const <String>{}
        : await _anki.knowledgePointsFirstReviewedSince(
            dayStart.millisecondsSinceEpoch,
            knowledgePointIds: done.keys,
          );
    // One lookup for every knowledge point that was reviewed today (and only
    // those): asking per group would repeat the same query once per row, and
    // asking per knowledge point would be one query per card in the library.
    final pathsByKnowledgePoint = done.isEmpty
        ? const <String, List<String>>{}
        : await _anki.tagPathsForObjects(
            objectType: 'knowledge_point',
            objectIds: done.keys,
          );

    final pathsByGroup = <String, List<String>>{};
    final entries = <ReviewGroupLoad>[];
    for (final plan in plans) {
      final paths = await pathsForGroup(plan.tagId);
      pathsByGroup[plan.tagId] = paths;
      final members = paths.toSet();
      var doneToday = 0;
      var newDone = 0;
      var reviewDone = 0;
      for (final entry in done.entries) {
        final pointPaths = pathsByKnowledgePoint[entry.key];
        if (pointPaths == null) {
          continue;
        }
        if (!pointPaths.any(members.contains)) {
          continue;
        }
        doneToday += entry.value;
        if (firstSeenToday.contains(entry.key)) {
          newDone += 1;
        } else {
          reviewDone += entry.value;
        }
      }
      entries.add(
        ReviewGroupLoad(
          plan: plan,
          memberPaths: paths,
          alreadyDoneToday: doneToday,
          newDoneToday: newDone,
          reviewDoneToday: reviewDone,
          newRemaining: (plan.newCardsPerDay - newDone).clamp(0, 1 << 30),
          remainingReviews: plan.isReviewCapped
              ? (plan.reviewCardsPerDay - reviewDone).clamp(0, 1 << 30)
              : null,
        ),
      );
    }
    return ReviewDayLoad(
      dayStart: dayStart,
      groups: entries,
      pathsByGroup: pathsByGroup,
    );
  }

  // --- internals -----------------------------------------------------------

  /// The single settings row, or null on a database that has none yet.
  Future<LocalSetting?> _settingsRow() async {
    final rows = await _db.select(_db.localSettings).get();
    return rows.isEmpty ? null : rows.first;
  }

  /// Writes one or both review preferences, creating the single settings row
  /// when it is missing.
  ///
  /// The insert branch matters: the practice screen can be reached before
  /// anything else has created `local_settings` (a fresh install whose first
  /// action is answering a card), and a preference that silently failed to save
  /// because of that ordering would be the exact bug this file exists to fix.
  Future<void> _writeSettings({
    String? ankiJudgeMode,
    String? ankiCardTypePreference,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.transaction(() async {
      final existing = await _db.select(_db.localSettings).getSingleOrNull();
      if (existing == null) {
        await _db.into(_db.localSettings).insert(
              LocalSettingsCompanion.insert(
                id: const Value(1),
                ankiJudgeMode: Value(ankiJudgeMode),
                ankiCardTypePreference: Value(ankiCardTypePreference),
                createdAt: now,
                updatedAt: now,
              ),
            );
        return;
      }
      await (_db.update(_db.localSettings)
            ..where((t) => t.id.equals(existing.id)))
          .write(
        LocalSettingsCompanion(
          ankiJudgeMode: ankiJudgeMode == null
              ? const Value.absent()
              : Value(ankiJudgeMode),
          ankiCardTypePreference: ankiCardTypePreference == null
              ? const Value.absent()
              : Value(ankiCardTypePreference),
          updatedAt: Value(now),
        ),
      );
    });
  }
}

/// Both persisted review preferences, read together.
class AnkiReviewPreferences {
  const AnkiReviewPreferences({
    required this.judgeMode,
    required this.cardType,
  });

  final JudgeModePreference judgeMode;
  final CardTypePreference cardType;
}

/// One group's stored daily target.
///
/// [tagPath] is resolved at read time and is what gets shown; [tagId] is what
/// the row is keyed by, because a rename rewrites every descendant's path.
class CardGroupPlan {
  const CardGroupPlan({
    required this.id,
    required this.tagId,
    required this.tagPath,
    required this.newCardsPerDay,
    required this.reviewCardsPerDay,
  });

  final String id;
  final String tagId;
  final String tagPath;
  final int newCardsPerDay;
  final int reviewCardsPerDay;

  /// Whether this group's reviews are limited at all.
  ///
  /// A non-positive review target means **unlimited**, not zero. The column is
  /// NOT NULL with a 0 default, so "0 reviews a day" would be the value of every
  /// row the moment it is created - and a first-run user who opened the plan UI
  /// and typed only a new-card number would silently stop seeing reviews. The
  /// table cannot express "zero reviews allowed"; that limit is not a study plan
  /// anyone wants, and a plan that stops review entirely is better expressed by
  /// not reviewing.
  bool get isReviewCapped => reviewCardsPerDay > 0;

  /// Whether the group ever asks for new cards.
  bool get wantsNewCards => newCardsPerDay > 0;
}

/// Today's plan versus actual for every configured group.
class ReviewDayLoad {
  const ReviewDayLoad({
    required this.dayStart,
    required this.groups,
    required this.pathsByGroup,
  });

  const ReviewDayLoad.empty({required DateTime dayStart})
      : this(dayStart: dayStart, groups: const [], pathsByGroup: const {});

  /// Local midnight of the day this load describes.
  final DateTime dayStart;

  final List<ReviewGroupLoad> groups;

  /// Group tag id -> the tag paths it covers. Held next to the entries so the
  /// queue can decide membership without a second trip to the database.
  final Map<String, List<String>> pathsByGroup;

  /// Whether anything is configured at all.
  bool get isEmpty => groups.isEmpty;

  /// The groups whose review allowance is spent.
  ///
  /// Only meaningful for capped groups (an uncapped group has no review
  /// allowance to run out of). The queue uses the per-group remaining counts
  /// rather than this set, so this stays a cheap read for anything that just
  /// wants to say "this group is done for today".
  Set<String> get reviewExhaustedGroups => {
        for (final group in groups)
          if (group.remainingReviews == 0) group.plan.tagId,
      };

  /// The groups a set of tag paths belongs to, restricted to [groupIds].
  Set<String> groupsForPaths(
    Iterable<String> tagPaths, {
    required Set<String> groupIds,
  }) {
    if (groupIds.isEmpty) {
      return const {};
    }
    final result = <String>{};
    for (final entry in pathsByGroup.entries) {
      if (!groupIds.contains(entry.key)) {
        continue;
      }
      if (tagPaths.any(entry.value.contains)) {
        result.add(entry.key);
      }
    }
    return result;
  }
}

/// One group's line in today's plan.
class ReviewGroupLoad {
  const ReviewGroupLoad({
    required this.plan,
    required this.memberPaths,
    required this.alreadyDoneToday,
    required this.newDoneToday,
    required this.reviewDoneToday,
    required this.newRemaining,
    required this.remainingReviews,
  });

  final CardGroupPlan plan;

  /// Tag paths counted as this group (the tag and its subtree).
  final List<String> memberPaths;

  /// Every answer logged today on this group's knowledge points.
  final int alreadyDoneToday;

  /// How many of those points were introduced today (first review ever today).
  final int newDoneToday;

  /// Today's answers on material the group already had before today.
  final int reviewDoneToday;

  /// New-card allowance left for today. Never null: `newCardsPerDay == 0`
  /// means "no new cards today", not "unlimited".
  final int newRemaining;

  /// Review allowance left, or null when the group is not review-capped.
  final int? remainingReviews;

  /// Whether the group can still draw a new card today.
  bool get newCardsAllowed => newRemaining > 0;
}

/// The path helper this file matches groups with.
///
/// Exposed so the queue and the tests spell "is this card in that group" the
/// same way the persistence layer does.
bool pathInGroup(String groupPath, String candidate) =>
    TagPath.isSameOrUnder(path: groupPath, candidate: candidate);
