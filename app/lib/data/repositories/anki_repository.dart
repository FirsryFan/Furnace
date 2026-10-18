import 'package:drift/drift.dart';

import '../../domain/services/config/furnace_defaults.dart';
import '../../domain/services/cognitive/learning_metrics.dart';
import '../database/database.dart';
import '../ids.dart';

/// `exposure_logs.source` written by the review screen's "读过，没测自己" press.
///
/// The column is free text because the value set grows (the roadmap's material
/// intake will add its own); this is the one producer today, and it lives here
/// next to the writer so the review flow and any future reader cannot disagree
/// about the spelling.
const String kExposureSourceAnswerReveal = 'answer_reveal';

/// Repository for knowledge points, card templates, card states and review
/// logs.
class AnkiRepository {
  AnkiRepository(this._db);

  final AppDatabase _db;

  // Knowledge points

  Future<KnowledgePoint> createKnowledgePoint({
    required String title,
    required String content,
    String? source,
    String? externalId,
    String? packageId,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = _newId('kp');
    await _db.into(_db.knowledgePoints).insert(
          KnowledgePointsCompanion.insert(
            id: id,
            title: title,
            content: content,
            source: Value(source),
            externalId: Value(externalId),
            packageId: Value(packageId),
            createdAt: now,
            updatedAt: now,
          ),
        );
    return (await _db.select(_db.knowledgePoints)
          ..where((t) => t.id.equals(id)))
        .getSingle();
  }

  Future<List<KnowledgePoint>> getKnowledgePoints({String? packageId}) {
    final query = _db.select(_db.knowledgePoints);
    if (packageId != null) {
      query.where((t) => t.packageId.equals(packageId));
    }
    query.orderBy([(t) => OrderingTerm.asc(t.createdAt)]);
    return query.get();
  }

  Future<KnowledgePoint?> getKnowledgePointById(String id) {
    return (_db.select(_db.knowledgePoints)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  Future<void> updateKnowledgePoint(
    String id, {
    String? title,
    String? content,
    String? source,
  }) async {
    await (_db.update(_db.knowledgePoints)..where((t) => t.id.equals(id)))
        .write(
      KnowledgePointsCompanion(
        title: title == null ? const Value.absent() : Value(title),
        content: content == null ? const Value.absent() : Value(content),
        source: source == null ? const Value.absent() : Value(source),
        updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );
  }

  // Card templates

  Future<CardTemplate> createTemplate({
    required String knowledgePointId,
    required String type,
    required String question,
    required String answer,
    List<String> options = const [],
    String? clozeTemplate,
    String? hint,
    String? externalId,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = _newId('tpl');
    await _db.into(_db.cardTemplates).insert(
          CardTemplatesCompanion.insert(
            id: id,
            knowledgePointId: knowledgePointId,
            type: type,
            question: question,
            answer: answer,
            options: Value(options.isEmpty ? null : _encodeOptions(options)),
            clozeTemplate: Value(clozeTemplate),
            hint: Value(hint),
            sortOrder: const Value(0),
            externalId: Value(externalId),
            createdAt: now,
            updatedAt: now,
          ),
        );
    return (await _db.select(_db.cardTemplates)
          ..where((t) => t.id.equals(id)))
        .getSingle();
  }

  Future<List<CardTemplate>> getTemplatesForKnowledgePoint(
    String knowledgePointId,
  ) {
    return (_db.select(_db.cardTemplates)
          ..where((t) => t.knowledgePointId.equals(knowledgePointId))
          ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
        .get();
  }

  Future<CardTemplate?> getCardTemplateById(String id) {
    return (_db.select(_db.cardTemplates)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  Future<List<CardTemplate>> getAllTemplates() {
    return _db.select(_db.cardTemplates).get();
  }

  /// The full tag tree paths of several objects at once, keyed by object id.
  ///
  /// The plan needs "which groups does this knowledge point belong to" for every
  /// knowledge point, and asking [TagRepository.tagsForObject] per point would be
  /// one query per row. Objects without any tag are simply absent from the map
  /// (never present with an empty list), so a caller can tell "untagged" from
  /// "no tags loaded yet" without a second lookup.
  ///
  /// Only rows whose `path` is non-empty are returned: the path is what the plan
  /// matches on, and a tag without one cannot be placed in the tree.
  Future<Map<String, List<String>>> tagPathsForObjects({
    required String objectType,
    required Iterable<String> objectIds,
  }) async {
    final ids = objectIds.toSet().toList();
    if (ids.isEmpty) {
      return const {};
    }
    final result = <String, List<String>>{};
    // Chunked because SQLite has a hard limit on bound variables (999 in the
    // builds this app ships) and a large library can exceed it.
    const chunkSize = 500;
    for (var start = 0; start < ids.length; start += chunkSize) {
      final end =
          start + chunkSize < ids.length ? start + chunkSize : ids.length;
      final links = await (_db.select(_db.objectTags)
            ..where(
              (t) =>
                  t.objectType.equals(objectType) &
                  t.objectId.isIn(ids.sublist(start, end)),
            ))
          .get();
      if (links.isEmpty) {
        continue;
      }
      final tagIds = {for (final link in links) link.tagId}.toList();
      final tags =
          await (_db.select(_db.tags)..where((t) => t.id.isIn(tagIds))).get();
      final pathById = <String, String>{
        for (final tag in tags)
          if (tag.path != null && tag.path!.isNotEmpty) tag.id: tag.path!,
      };
      for (final link in links) {
        final path = pathById[link.tagId];
        if (path == null) {
          continue;
        }
        result.putIfAbsent(link.objectId, () => []).add(path);
      }
    }
    return result;
  }

  // Card states and reviews

  Future<CardState> getOrCreateCardState(String cardTemplateId) async {
    final existing = await (_db.select(_db.cardStates)
          ..where((t) => t.cardTemplateId.equals(cardTemplateId)))
        .getSingleOrNull();
    if (existing != null) {
      return existing;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final id = _newId('cs');
    await _db.into(_db.cardStates).insert(
          CardStatesCompanion.insert(
            id: id,
            cardTemplateId: Value(cardTemplateId),
            createdAt: now,
            updatedAt: now,
          ),
        );
    return (await _db.select(_db.cardStates)
          ..where((t) => t.id.equals(id)))
        .getSingle();
  }

  Future<List<CardState>> getDueCardStates(int nowMillis) {
    return (_db.select(_db.cardStates)
          ..where(
            (t) => t.dueAt.isNull() | t.dueAt.isSmallerOrEqualValue(nowMillis),
          ))
        .get();
  }

  Future<void> updateCardState(
    String id, {
    int? dueAt,
    double? intervalDays,
    double? ease,
    int? repetitions,
    int? lapses,
    String? state,
    int? lastReviewedAt,
  }) async {
    await (_db.update(_db.cardStates)..where((t) => t.id.equals(id))).write(
      CardStatesCompanion(
        dueAt: Value(dueAt),
        intervalDays:
            intervalDays == null ? const Value.absent() : Value(intervalDays),
        ease: ease == null ? const Value.absent() : Value(ease),
        repetitions:
            repetitions == null ? const Value.absent() : Value(repetitions),
        lapses: lapses == null ? const Value.absent() : Value(lapses),
        state: state == null ? const Value.absent() : Value(state),
        lastReviewedAt: Value(lastReviewedAt),
        updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );
  }

  Future<void> updateTemplate(
    String id, {
    String? type,
    String? question,
    String? answer,
    List<String>? options,
    String? clozeTemplate,
    String? hint,
  }) async {
    await (_db.update(_db.cardTemplates)..where((t) => t.id.equals(id))).write(
      CardTemplatesCompanion(
        type: type == null ? const Value.absent() : Value(type),
        question: question == null ? const Value.absent() : Value(question),
        answer: answer == null ? const Value.absent() : Value(answer),
        options: options == null
            ? const Value.absent()
            : Value(options.isEmpty ? null : _encodeOptions(options)),
        clozeTemplate:
            clozeTemplate == null ? const Value.absent() : Value(clozeTemplate),
        hint: hint == null ? const Value.absent() : Value(hint),
        updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );
  }

  Future<void> deleteTemplate(String id) async {
    await _db.transaction(() async {
      final states = await (_db.select(_db.cardStates)
            ..where((t) => t.cardTemplateId.equals(id)))
          .get();
      final stateIds = [for (final state in states) state.id];
      if (stateIds.isNotEmpty) {
        await (_db.delete(_db.reviewLogs)
              ..where((t) => t.cardStateId.isIn(stateIds)))
            .go();
      }
      await (_db.delete(_db.reviewLogs)
            ..where((t) => t.cardTemplateId.equals(id)))
          .go();
      await (_db.delete(_db.cardStates)
            ..where((t) => t.cardTemplateId.equals(id)))
          .go();
      await (_db.delete(_db.cardTemplates)..where((t) => t.id.equals(id))).go();
    });
  }

  /// Deletes a flashcard and everything that belongs to it.
  ///
  /// "Everything" is the point of this method, and it took a leak to notice:
  /// card states come in two shapes - a template-backed one
  /// (`card_template_id` set) and a **presentation unit** one
  /// (`unit_key = 'cloze:…' / 'essay:…'`, no template at all). Deleting only the
  /// rows reachable through the templates left the unit states behind: the
  /// flashcard was gone from the Knowledge screen while its cards still showed
  /// up in the cognitive-model readings page and could still be counted by the
  /// model. States are therefore selected by `knowledge_point_id` *and* through
  /// the templates, so neither shape survives.
  ///
  /// The rest of the row set is cleaned for the same reason: cloze slots and
  /// history, the diffusion boost entry, and the tag links that point at the
  /// knowledge point. A leftover row that no screen happens to read today is
  /// still a bug waiting for the next reader.
  Future<void> deleteKnowledgePoint(String id) async {
    await _db.transaction(() async {
      final templates = await getTemplatesForKnowledgePoint(id);
      final states = await (_db.select(_db.cardStates)
            ..where(
              (t) =>
                  t.knowledgePointId.equals(id) |
                  t.cardTemplateId.isIn([for (final t in templates) t.id]),
            ))
          .get();
      final stateIds = [for (final state in states) state.id];
      if (stateIds.isNotEmpty) {
        await (_db.delete(_db.reviewLogs)
              ..where((t) => t.cardStateId.isIn(stateIds)))
            .go();
      }
      for (final template in templates) {
        await (_db.delete(_db.reviewLogs)
              ..where((t) => t.cardTemplateId.equals(template.id)))
            .go();
      }
      await (_db.delete(_db.cardStates)
            ..where(
              (t) =>
                  t.knowledgePointId.equals(id) |
                  t.cardTemplateId.isIn([for (final t in templates) t.id]),
            ))
          .go();
      await (_db.delete(_db.cardTemplates)
            ..where((t) => t.knowledgePointId.equals(id)))
          .go();
      await (_db.delete(_db.clozeSlots)
            ..where((t) => t.knowledgePointId.equals(id)))
          .go();
      await (_db.delete(_db.clozeHistory)
            ..where((t) => t.knowledgePointId.equals(id)))
          .go();
      await (_db.delete(_db.boostEntries)
            ..where((t) => t.knowledgePointId.equals(id)))
          .go();
      await (_db.delete(_db.objectTags)
            ..where((t) =>
                t.objectType.equals('knowledge_point') & t.objectId.equals(id)))
          .go();
      await (_db.delete(_db.knowledgePoints)..where((t) => t.id.equals(id)))
          .go();
    });
  }

  /// Counts the rows that hang off a flashcard which no longer exists.
  ///
  /// Used by the cognitive-model page to say "these are debris, not cards", and
  /// by the repair path below. A template-backed state is only debris when its
  /// *template* is gone (its `knowledge_point_id` may legitimately be NULL),
  /// while a unit state is debris when its knowledge point is gone - getting
  /// that distinction backwards would delete live review states.
  Future<int> countOrphanCardStates() async {
    final row = await _db
        .customSelect(
          'SELECT COUNT(*) AS n FROM card_states WHERE '
          '(card_template_id IS NULL AND (knowledge_point_id IS NULL OR '
          ' knowledge_point_id NOT IN (SELECT id FROM knowledge_points))) OR '
          '(card_template_id IS NOT NULL AND '
          ' card_template_id NOT IN (SELECT id FROM card_templates))',
        )
        .getSingle();
    return row.read<int>('n');
  }

  /// Deletes the debris [countOrphanCardStates] reports, plus the rows that
  /// reference it.
  ///
  /// This is the repair path for databases written while the cascade above was
  /// incomplete: those rows can never be reviewed (the review queue cannot
  /// present a card whose flashcard is gone) yet they were still listed as
  /// cards. Returns how many card states were removed, so the caller can tell
  /// the user what actually happened.
  Future<int> purgeOrphanKnowledgeRows() async {
    var removed = 0;
    await _db.transaction(() async {
      removed = await countOrphanCardStates();
      await _db.customStatement(
        'DELETE FROM review_logs WHERE card_state_id IN ('
        ' SELECT id FROM card_states WHERE '
        ' (card_template_id IS NULL AND (knowledge_point_id IS NULL OR '
        '  knowledge_point_id NOT IN (SELECT id FROM knowledge_points))) OR '
        ' (card_template_id IS NOT NULL AND '
        '  card_template_id NOT IN (SELECT id FROM card_templates)))',
      );
      await _db.customStatement(
        'DELETE FROM card_states WHERE '
        '(card_template_id IS NULL AND (knowledge_point_id IS NULL OR '
        ' knowledge_point_id NOT IN (SELECT id FROM knowledge_points))) OR '
        '(card_template_id IS NOT NULL AND '
        ' card_template_id NOT IN (SELECT id FROM card_templates))',
      );
      // Rows that name a flashcard which is gone. Each statement is the same
      // "delete what cannot be read any more" rule on another table.
      for (final table in const [
        'card_templates',
        'cloze_slots',
        'cloze_history',
        'boost_entries',
      ]) {
        await _db.customStatement(
          'DELETE FROM $table WHERE knowledge_point_id NOT IN '
          '(SELECT id FROM knowledge_points)',
        );
      }
      await _db.customStatement(
        "DELETE FROM object_tags WHERE object_type = 'knowledge_point' AND "
        'object_id NOT IN (SELECT id FROM knowledge_points)',
      );
      await _db.customStatement(
        'DELETE FROM review_logs WHERE card_state_id NOT IN '
        '(SELECT id FROM card_states)',
      );
    });
    return removed;
  }

  Future<List<int>> getReviewCountsPerDay(int days) async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day - (days - 1));
    final rows = await _db.select(_db.reviewLogs).get();
    final counts = List<int>.filled(days, 0);
    for (final row in rows) {
      final dt = DateTime.fromMillisecondsSinceEpoch(row.reviewedAt);
      final dayStart = DateTime(dt.year, dt.month, dt.day);
      final diff = dayStart.difference(start).inDays;
      if (diff >= 0 && diff < days) {
        counts[diff]++;
      }
    }
    return counts;
  }

  Future<int> countReviewsSince(int sinceMillis) async {
    final count = _db.reviewLogs.id.count();
    final query = _db.selectOnly(_db.reviewLogs)
      ..addColumns([count])
      ..where(_db.reviewLogs.reviewedAt.isBiggerOrEqualValue(sinceMillis));
    final row = await query.getSingle();
    return row.read(count) ?? 0;
  }

  /// How many reviews each knowledge point has already had since [sinceMillis].
  ///
  /// This is the "actual" half of the daily plan. It is counted per knowledge
  /// point rather than per card because the group a review belongs to is decided
  /// by the knowledge point's tags: a presentation unit (`cloze:…`,
  /// `essay:…`) and a template-backed card of the same material are the same
  /// material in the plan's eyes.
  ///
  /// `review_logs.card_state_id` is NOT NULL, but a log whose state row is gone
  /// (imported debris) cannot be attributed to anything, so the join is an inner
  /// one and those rows are simply not counted - attributing them to a group
  /// would need a guess.
  Future<Map<String, int>> reviewCountsPerKnowledgePointSince(
    int sinceMillis,
  ) async {
    final rows = await _db.customSelect(
      'SELECT cs.knowledge_point_id AS kp, COUNT(*) AS n '
      'FROM review_logs rl '
      'JOIN card_states cs ON cs.id = rl.card_state_id '
      'WHERE rl.reviewed_at >= ? AND cs.knowledge_point_id IS NOT NULL '
      'GROUP BY cs.knowledge_point_id',
      variables: [Variable.withInt(sinceMillis)],
    ).get();
    return {
      for (final row in rows) row.read<String>('kp'): row.read<int>('n'),
    };
  }

  /// The knowledge points whose **very first** review happened at or after
  /// [sinceMillis].
  ///
  /// The daily plan needs this to tell "a new card introduced today" apart from
  /// "a card from an earlier day reviewed today". `card_states.repetitions` is a
  /// current value - after the fact it cannot say *when* the first answer
  /// happened - so the review log is the only source for that split.
  ///
  /// Restricted to [knowledgePointIds] when given: the caller already holds the
  /// points reviewed today, and asking for the first review of every card in the
  /// library would scan the user's whole history.
  Future<Set<String>> knowledgePointsFirstReviewedSince(
    int sinceMillis, {
    Iterable<String>? knowledgePointIds,
  }) async {
    final ids = knowledgePointIds?.toSet().toList() ?? const <String>[];
    final scope = ids.isEmpty
        ? 'AND cs.knowledge_point_id IS NOT NULL '
        : 'AND cs.knowledge_point_id IN '
            '(${List.filled(ids.length, '?').join(', ')}) ';
    final rows = await _db.customSelect(
      'SELECT cs.knowledge_point_id AS kp, MIN(rl.reviewed_at) AS first_at '
      'FROM review_logs rl '
      'JOIN card_states cs ON cs.id = rl.card_state_id '
      'WHERE 1 = 1 $scope'
      'GROUP BY cs.knowledge_point_id '
      'HAVING first_at >= ?',
      variables: [
        for (final id in ids) Variable.withString(id),
        Variable.withInt(sinceMillis),
      ],
    ).get();
    return {for (final row in rows) row.read<String>('kp')};
  }

  /// Every review that can be judged, oldest first inside each card, with the
  /// interval since the previous review of the *same* card already attached.
  ///
  /// This is the input of `LearningMetrics` (milestone ②「记忆效果好」): the
  /// retention half needs nothing but these rows. `predicted_r` is read too and
  /// stays `null` for every row written before v11, which is why the
  /// calibration half has to admit it has no samples yet instead of drawing a
  /// curve from invented predictions.
  ///
  /// The join is a LEFT one on purpose: a log whose card_state row is gone
  /// (imported debris) still describes a real review, so it counts towards the
  /// curve with a `null` knowledge point rather than vanishing from the totals.
  Future<List<RetentionSample>> retentionSamples({
    int? sinceMillis,
    int limit = 5000,
  }) async {
    final rows = await _db.customSelect(
      'SELECT rl.card_state_id AS card, cs.knowledge_point_id AS kp, '
      'rl.reviewed_at AS at, rl.rating AS rating, rl.rating_fsrs AS fsrs, '
      'rl.correct AS correct, rl.predicted_r AS predicted '
      'FROM review_logs rl '
      'LEFT JOIN card_states cs ON cs.id = rl.card_state_id '
      '${sinceMillis == null ? '' : 'WHERE rl.reviewed_at >= ? '}'
      'ORDER BY rl.card_state_id ASC, rl.reviewed_at ASC LIMIT ?',
      variables: [
        if (sinceMillis != null) Variable.withInt(sinceMillis),
        Variable.withInt(limit),
      ],
    ).get();

    final samples = <RetentionSample>[
      for (final row in rows)
        RetentionSample(
          cardStateId: row.read<String>('card'),
          knowledgePointId: row.read<String?>('kp'),
          reviewedAtMs: row.read<int>('at'),
          recalled: recalledFromReview(
            rating: row.read<int?>('rating'),
            ratingFsrs: row.read<int?>('fsrs'),
            correct: row.read<int?>('correct') == null
                ? null
                : row.read<int>('correct') == 1,
          ),
          predictedR: row.read<double?>('predicted'),
        ),
    ];
    return withIntervals(samples);
  }

  // --- v2: presentation units (cloze / essay / preset) ----------------------
  /// Finds or creates the card state of a presentation unit. For preset cards
  /// pass [presetTemplateId]; cloze/essay units pass their own [unitKey].
  Future<CardState> getOrCreateUnitCardState(
    String knowledgePointId,
    String unitKey, {
    String? presetTemplateId,
  }) async {
    final existing = await (_db.select(_db.cardStates)
          ..where(
            (t) =>
                t.knowledgePointId.equals(knowledgePointId) &
                t.unitKey.equals(unitKey),
          ))
        .getSingleOrNull();
    if (existing != null) {
      return existing;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = _newId('cs');
    await _db.into(_db.cardStates).insert(
          CardStatesCompanion.insert(
            id: id,
            cardTemplateId: Value(presetTemplateId),
            knowledgePointId: Value(knowledgePointId),
            unitKey: Value(unitKey),
            createdAt: now,
            updatedAt: now,
          ),
        );
    return (await _db.select(_db.cardStates)
          ..where((t) => t.id.equals(id)))
        .getSingle();
  }

  Future<CardState?> unitCardState(String knowledgePointId, String unitKey) {
    return (_db.select(_db.cardStates)
          ..where(
            (t) =>
                t.knowledgePointId.equals(knowledgePointId) &
                t.unitKey.equals(unitKey),
          ))
        .getSingleOrNull();
  }

  Future<List<CardState>> unitStatesForKnowledgePoint(String knowledgePointId) {
    return (_db.select(_db.cardStates)
          ..where((t) => t.knowledgePointId.equals(knowledgePointId)))
        .get();
  }

  /// Generic v2 state update covering FSRS fields and the forced-binding
  /// machine (spec 1.3.2).
  Future<void> updateUnitCardState(
    String id, {
    int? dueAt,
    String? state,
    double? stability,
    double? difficulty,
    double? intervalDays,
    int? repetitions,
    int? lapses,
    int? forced,
    int? forcedStreak,
    int? lastReviewedAt,
  }) async {
    await (_db.update(_db.cardStates)..where((t) => t.id.equals(id))).write(
      CardStatesCompanion(
        dueAt: dueAt == null ? const Value.absent() : Value(dueAt),
        state: state == null ? const Value.absent() : Value(state),
        stability: stability == null ? const Value.absent() : Value(stability),
        difficulty:
            difficulty == null ? const Value.absent() : Value(difficulty),
        intervalDays:
            intervalDays == null ? const Value.absent() : Value(intervalDays),
        repetitions:
            repetitions == null ? const Value.absent() : Value(repetitions),
        lapses: lapses == null ? const Value.absent() : Value(lapses),
        forced: forced == null ? const Value.absent() : Value(forced),
        forcedStreak:
            forcedStreak == null ? const Value.absent() : Value(forcedStreak),
        lastReviewedAt: lastReviewedAt == null
            ? const Value.absent()
            : Value(lastReviewedAt),
        updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );
  }

  /// Writes **only** the two cognitive-model columns of one card state row.
  ///
  /// This is the narrow write seam of decision D2: `stability`, `difficulty`
  /// and `dueAt` stay FSRS's (written by [updateUnitCardState] in the same
  /// review), while `encoding_strength` (MindNet's `R0`) and `savings`
  /// (`Sigma`) belong to the cognitive model. One column, one writer - and the
  /// narrowness is the point, not an implementation detail:
  ///
  ///  * **`updatedAt` is not bumped here.** The review that produced these two
  ///    numbers has already written its own `updatedAt` through
  ///    [updateUnitCardState]; writing it again would put a second writer on a
  ///    column this method has no business owning.
  ///  * **A `null` argument means "leave that column alone"**, following the
  ///    `Value.absent()` convention the rest of this file uses. There is
  ///    deliberately **no way to clear either column back to NULL** from here:
  ///    model state either has a value and keeps evolving, or the row never
  ///    carried one. (A caller that really needs to erase model state must say
  ///    so with a method of its own rather than overloading `null`.)
  ///  * **Both arguments `null` is a no-op**: an all-absent companion would
  ///    issue a pointless empty `UPDATE`, so it returns without touching the
  ///    database.
  ///
  /// The values are meant to come from the cognitive model's own seam
  /// (`CognitiveModel.modelStateAfterReview`), never from a curve re-derived at
  /// the call site - that is what keeps one number from having two sources.
  Future<void> updateModelState(
    String id, {
    double? encodingStrength,
    double? savings,
  }) async {
    if (encodingStrength == null && savings == null) {
      return;
    }
    await (_db.update(_db.cardStates)..where((t) => t.id.equals(id))).write(
      CardStatesCompanion(
        encodingStrength: encodingStrength == null
            ? const Value.absent()
            : Value(encodingStrength),
        savings: savings == null ? const Value.absent() : Value(savings),
      ),
    );
  }

  /// Extended review log (v2). All new columns optional; preset-card callers
  /// keep using the legacy signature unchanged.
  ///
  /// [reviewedSolution] / [closeness] are the v9 failure-feedback pair and are
  /// left NULL unless the caller actually asked the user (a bare `false` would
  /// claim every miss was a plain lapse, and pre-v9 rows must stay
  /// distinguishable from a deliberate "还是不会").
  ///
  /// [predictedR] is the v11 pre-review prediction: the model's `R` at the
  /// moment the answer was shown, before the grade existed. Callers must pass
  /// what they actually predicted (or NULL when the advisor did not run);
  /// `addReviewLog` never derives it, because a value recomputed here would be
  /// computed *after* [correct] and the calibration curve would be worthless.
  Future<void> addReviewLog({
    required String cardStateId,
    required String cardTemplateId,
    required int rating,
    required int reviewedAt,
    String? unitKey,
    int? ratingFsrs,
    int? correct,
    String? judgeMode,
    String? format,
    int? msTaken,
    bool? reviewedSolution,
    double? closeness,
    double? predictedR,
  }) async {
    await _db.into(_db.reviewLogs).insert(
          ReviewLogsCompanion.insert(
            id: _newId('log'),
            cardStateId: cardStateId,
            cardTemplateId: Value(cardTemplateId),
            unitKey: Value(unitKey),
            rating: rating,
            ratingFsrs: Value(ratingFsrs),
            correct: Value(correct),
            judgeMode: Value(judgeMode),
            format: Value(format),
            msTaken: Value(msTaken),
            reviewedSolution: Value(reviewedSolution),
            closeness: Value(closeness),
            predictedR: Value(predictedR),
            reviewedAt: reviewedAt,
            createdAt: reviewedAt,
          ),
        );
  }

  /// v14: one "我读了，但没测自己" event - MindNet's `exposure`.
  ///
  /// Deliberately **not** a `review_logs` row. That table is the test record:
  /// `learning_metrics.dart` builds the retention buckets from it and the
  /// calibration curve grades its `predicted_r` against its `correct`, so a
  /// reading stored there would need a fabricated `rating` (NOT NULL) and would
  /// be counted as a recall test. The model side is unaffected by that choice -
  /// the caller still sends a `reread` event, which is its own event type
  /// (`DsrCardState.eventFor(rating: 3, reread: true)`).
  ///
  /// [exposedAt] is the wall-clock moment of the reading, the same clock
  /// `review_logs.reviewed_at` uses, so the two tables can be read together.
  Future<void> addExposureLog({
    required String cardStateId,
    required int exposedAt,
    String source = kExposureSourceAnswerReveal,
  }) async {
    await _db.into(_db.exposureLogs).insert(
          ExposureLogsCompanion.insert(
            id: _newId('exposure'),
            cardStateId: cardStateId,
            source: source,
            exposedAt: exposedAt,
            createdAt: exposedAt,
          ),
        );
  }

  // --- v2: cloze slots & history -------------------------------------------

  Future<ClozeSlot> createClozeSlot({
    required String knowledgePointId,
    required String slotKey,
    required String definition,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = _newId('slot');
    await _db.into(_db.clozeSlots).insert(
          ClozeSlotsCompanion.insert(
            id: id,
            knowledgePointId: knowledgePointId,
            slotKey: slotKey,
            definition: definition,
            createdAt: now,
            updatedAt: now,
          ),
          mode: InsertMode.insertOrIgnore,
        );
    final existing = await (_db.select(_db.clozeSlots)
          ..where(
            (t) =>
                t.knowledgePointId.equals(knowledgePointId) &
                t.slotKey.equals(slotKey),
          ))
        .getSingle();
    return existing;
  }

  Future<void> markClozeSlotExhausted(String slotId) async {
    await (_db.update(_db.clozeSlots)..where((t) => t.id.equals(slotId))).write(
      ClozeSlotsCompanion(
        exhausted: const Value(1),
        updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );
  }

  Future<List<ClozeSlot>> clozeSlotsForKnowledgePoint(String knowledgePointId) {
    final query = _db.select(_db.clozeSlots);
    query.where((t) => t.knowledgePointId.equals(knowledgePointId));
    query.orderBy([(t) => OrderingTerm.asc(t.slotKey)]);
    return query.get();
  }

  Future<void> addClozeHistory({
    required String knowledgePointId,
    required String slotKey,
    required int correct,
    required int usedAt,
  }) async {
    await _db.into(_db.clozeHistory).insert(
          ClozeHistoryCompanion.insert(
            id: _newId('ch'),
            knowledgePointId: knowledgePointId,
            slotKey: slotKey,
            correct: Value(correct),
            usedAt: usedAt,
            createdAt: usedAt,
          ),
        );
  }

  /// Slot keys already drawn at least once for [knowledgePointId].
  Future<Set<String>> usedClozeSlotKeys(String knowledgePointId) async {
    final rows = await (_db.select(_db.clozeHistory)
          ..where((t) => t.knowledgePointId.equals(knowledgePointId)))
        .get();
    return rows.map((r) => r.slotKey).toSet();
  }

  // --- v2: Mindnet diffusion boosts ----------------------------------------

  /// Creates or refreshes the boost for [knowledgePointId] (single row per
  /// knowledge point; highest factor wins, cycles reset to 3).
  Future<void> upsertBoost({
    required String knowledgePointId,
    required double factor,
    int? remainingCycles,
  }) async {
    final existing = await (_db.select(_db.boostEntries)
          ..where((t) => t.knowledgePointId.equals(knowledgePointId)))
        .getSingleOrNull();
    final now = DateTime.now().millisecondsSinceEpoch;
    final cycles = remainingCycles ?? FurnaceDefaults.boostCycles;
    if (existing == null) {
      await _db.into(_db.boostEntries).insert(
            BoostEntriesCompanion.insert(
              id: _newId('boost'),
              knowledgePointId: knowledgePointId,
              factor: factor,
              remainingCycles: Value(cycles),
              createdAt: now,
            ),
          );
      return;
    }
    final factor2 = factor > existing.factor ? factor : existing.factor;
    await (_db.update(_db.boostEntries)
          ..where((t) => t.knowledgePointId.equals(knowledgePointId)))
        .write(
      BoostEntriesCompanion(
        factor: Value(factor2),
        remainingCycles: Value(cycles),
      ),
    );
  }

  Future<BoostEntry?> boostFor(String knowledgePointId) {
    return (_db.select(_db.boostEntries)
          ..where((t) => t.knowledgePointId.equals(knowledgePointId)))
        .getSingleOrNull();
  }

  Future<List<BoostEntry>> getAllBoosts() {
    return _db.select(_db.boostEntries).get();
  }

  Future<void> deleteBoost(String knowledgePointId) async {
    await (_db.delete(_db.boostEntries)
          ..where((t) => t.knowledgePointId.equals(knowledgePointId)))
        .go();
  }

  String _encodeOptions(List<String> options) => options.join('\u0001');

  String _newId(String prefix) => Ids.next(prefix);
}
