import 'package:drift/drift.dart';

import '../../domain/services/config/threadflow_defaults.dart';
import '../database/database.dart';
import '../ids.dart';

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
    return (await _db.select(_db.cardTemplates)..where((t) => t.id.equals(id)))
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
    return (await _db.select(_db.cardStates)..where((t) => t.id.equals(id)))
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
        intervalDays: intervalDays == null
            ? const Value.absent()
            : Value(intervalDays),
        ease: ease == null ? const Value.absent() : Value(ease),
        repetitions: repetitions == null
            ? const Value.absent()
            : Value(repetitions),
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
    await (_db.update(_db.cardTemplates)..where((t) => t.id.equals(id)))
        .write(
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
      await (_db.delete(_db.reviewLogs)
            ..where((t) => t.cardTemplateId.equals(id)))
          .go();
      await (_db.delete(_db.cardStates)
            ..where((t) => t.cardTemplateId.equals(id)))
          .go();
      await (_db.delete(_db.cardTemplates)..where((t) => t.id.equals(id)))
          .go();
    });
  }

  Future<void> deleteKnowledgePoint(String id) async {
    await _db.transaction(() async {
      final templates = await getTemplatesForKnowledgePoint(id);
      for (final template in templates) {
        await (_db.delete(_db.reviewLogs)
              ..where((t) => t.cardTemplateId.equals(template.id)))
            .go();
        await (_db.delete(_db.cardStates)
              ..where((t) => t.cardTemplateId.equals(template.id)))
            .go();
        await (_db.delete(_db.cardTemplates)
              ..where((t) => t.id.equals(template.id)))
            .go();
      }
      await (_db.delete(_db.knowledgePoints)..where((t) => t.id.equals(id)))
          .go();
    });
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
    return (await _db.select(_db.cardStates)..where((t) => t.id.equals(id)))
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
        stability: stability == null
            ? const Value.absent()
            : Value(stability),
        difficulty: difficulty == null
            ? const Value.absent()
            : Value(difficulty),
        intervalDays: intervalDays == null
            ? const Value.absent()
            : Value(intervalDays),
        repetitions: repetitions == null
            ? const Value.absent()
            : Value(repetitions),
        lapses: lapses == null ? const Value.absent() : Value(lapses),
        forced: forced == null ? const Value.absent() : Value(forced),
        forcedStreak: forcedStreak == null
            ? const Value.absent()
            : Value(forcedStreak),
        lastReviewedAt: lastReviewedAt == null
            ? const Value.absent()
            : Value(lastReviewedAt),
        updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );
  }

  /// Extended review log (v2). All new columns optional; preset-card callers
  /// keep using the legacy signature unchanged.
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
            reviewedAt: reviewedAt,
            createdAt: reviewedAt,
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
    await (_db.update(_db.clozeSlots)..where((t) => t.id.equals(slotId)))
        .write(
      ClozeSlotsCompanion(
        exhausted: const Value(1),
        updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );
  }

  Future<List<ClozeSlot>> clozeSlotsForKnowledgePoint(
      String knowledgePointId) {
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
    final cycles = remainingCycles ?? ThreadflowDefaults.boostCycles;
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
