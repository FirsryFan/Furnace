/// 认知快层的**非 Riverpod** 入口（Q13）：读表 + 跑一次 `LibraryDiagnosisRunner`。
///
/// 为什么要有这个文件：诊断结论原来只活在 `cognitiveModelPage` 的
/// `cognitiveLibraryDiagnosisProvider` 里，工具层（`features/ai/tools`）拿不到
/// Riverpod，于是要么放弃组卷读数、要么复制一份读表逻辑。复制会立刻违反
/// D2（同一个数字只有一个来源），而且 Q8 那个键空间 bug（`kp-…` 被当成
/// `tag-…`）正是"同一件事有两处实现"的产物。
///
/// 所以这里把「读表 + 跑 runner」搬出来，页面 provider 与 AI 工具都调它：
/// 同一个库、同一个模型、同一个时钟 → 同一个结论。
///
/// 这个文件不做 Flutter、不做 Riverpod：只吃 `AppDatabase`。
library;

import '../../../data/database/database.dart';
import '../../../domain/services/cognitive/cognitive_graph.dart';
import '../../../domain/services/cognitive/cognitive_model.dart';
import '../../../domain/services/cognitive/knowledge_point_tag_bridge.dart';
import '../../../domain/services/cognitive/library_diagnosis.dart';

/// How many recently reviewed knowledge points seed the diffusion ("what the
/// user is holding in mind right now", §6.3). A product rule, not a calibrated
/// number: the model cannot tell us this, so it is stated here once.
const int cognitiveStartNodeLimit = 5;

/// One card as the observation surface sees it: the stored row plus what it
/// belongs to. `isNew` is the review flow's own flag (D4), not a second
/// definition derived from the row.
class CognitiveObservedUnit {
  const CognitiveObservedUnit({
    required this.row,
    required this.knowledgePointTitle,
    required this.tagCount,
    required this.isNew,
  });

  /// Reads one unit back from the probe's JSON handshake.
  ///
  /// The map is the CLI's read-only export of a `card_states` row plus the two
  /// facts the model seam cannot see by itself (the title, the tag count). It is
  /// parsed here - next to [CardState] - so the shape has one owner.
  factory CognitiveObservedUnit.fromJson(Map<String, Object?> json) {
    final row = (json['row'] as Map?)?.cast<String, Object?>() ?? const {};
    return CognitiveObservedUnit(
      row: CardState(
        id: _jsonString(row['id']) ?? '',
        cardTemplateId: _jsonString(row['cardTemplateId']),
        dueAt: _jsonInt(row['dueAt']),
        intervalDays: _jsonDouble(row['intervalDays']) ?? 0,
        ease: _jsonDouble(row['ease']) ?? 2.5,
        repetitions: _jsonInt(row['repetitions']) ?? 0,
        lapses: _jsonInt(row['lapses']) ?? 0,
        state: _jsonString(row['state']) ?? 'new',
        lastReviewedAt: _jsonInt(row['lastReviewedAt']),
        createdAt: _jsonInt(row['createdAt']) ?? 0,
        updatedAt: _jsonInt(row['updatedAt']) ?? 0,
        knowledgePointId: _jsonString(row['knowledgePointId']),
        unitKey: _jsonString(row['unitKey']),
        stability: _jsonDouble(row['stability']),
        difficulty: _jsonDouble(row['difficulty']),
        encodingStrength: _jsonDouble(row['encodingStrength']),
        savings: _jsonDouble(row['savings']),
        forced: _jsonInt(row['forced']) ?? 0,
        forcedStreak: _jsonInt(row['forcedStreak']) ?? 0,
      ),
      knowledgePointTitle: _jsonString(json['knowledgePointTitle']) ?? '',
      tagCount: _jsonInt(json['tagCount']) ?? 0,
      isNew: json['isNew'] == true,
    );
  }

  final CardState row;
  final String knowledgePointTitle;
  final int tagCount;
  final bool isNew;

  /// The only value that identifies exactly one unit: `unitKey` can repeat
  /// across knowledge points (`'essay'` is the fallback for unblankable
  /// content), so every lookup is keyed by this.
  String get cardStateId => row.id;

  String get knowledgePointId => row.knowledgePointId ?? '';

  Map<String, Object?> toJson() => {
        'knowledgePointTitle': knowledgePointTitle,
        'tagCount': tagCount,
        'isNew': isNew,
        'row': {
          'id': row.id,
          'cardTemplateId': row.cardTemplateId,
          'dueAt': row.dueAt,
          'intervalDays': row.intervalDays,
          'ease': row.ease,
          'repetitions': row.repetitions,
          'lapses': row.lapses,
          'state': row.state,
          'lastReviewedAt': row.lastReviewedAt,
          'createdAt': row.createdAt,
          'updatedAt': row.updatedAt,
          'knowledgePointId': row.knowledgePointId,
          'unitKey': row.unitKey,
          'stability': row.stability,
          'difficulty': row.difficulty,
          'encodingStrength': row.encodingStrength,
          'savings': row.savings,
          'forced': row.forced,
          'forcedStreak': row.forcedStreak,
        },
      };
}

/// Everything the page reads before any model call: the units and the (explicitly
/// heuristic) diffusion boosts.
class CognitiveObservationInputs {
  const CognitiveObservationInputs({
    required this.units,
    this.boostFactorByKnowledgePoint = const {},
  });

  factory CognitiveObservationInputs.fromJson(Map<String, Object?> json) {
    final units = (json['units'] as List?) ?? const [];
    final boosts = (json['boostFactorByKnowledgePoint'] as Map?)
            ?.cast<String, Object?>() ??
        const {};
    return CognitiveObservationInputs(
      units: [
        for (final unit in units)
          CognitiveObservedUnit.fromJson((unit as Map).cast<String, Object?>()),
      ],
      boostFactorByKnowledgePoint: {
        for (final entry in boosts.entries)
          if (_jsonDouble(entry.value) case final factor?) entry.key: factor,
      },
    );
  }

  final List<CognitiveObservedUnit> units;

  /// `DiffusionBoost` factors, keyed the way the review flow keys them (D5: a
  /// heuristic, not a model quantity - it selects a band, never a score).
  final Map<String, double> boostFactorByKnowledgePoint;

  Map<String, Object?> toJson() => {
        'units': [for (final unit in units) unit.toJson()],
        'boostFactorByKnowledgePoint': boostFactorByKnowledgePoint,
      };
}

/// One database read, all `select`s.
///
/// A card state is only a card when its flashcard still exists, and the two
/// shapes resolve that link differently: a template-backed state names the
/// flashcard through its template, while a presentation unit (`cloze:…` /
/// `essay:…`) names it directly. Rows that resolve to nothing are debris from a
/// deletion performed before the cascade was complete - they are counted
/// separately (`orphanCardStateCountProvider`) instead of being drawn as cards
/// with no name.
Future<CognitiveObservationInputs> readCognitiveObservationInputs(
  AppDatabase db,
) async {
  final points = await db.select(db.knowledgePoints).get();
  final titles = {for (final point in points) point.id: point.title};

  // Tag counts for knowledge points. Plain `select` + counting in Dart: this is
  // the read-only observation surface, so it stays on the simplest drift calls
  // the rest of the app uses.
  final tagRows = await db.select(db.objectTags).get();
  final tagCounts = <String, int>{};
  for (final row in tagRows) {
    if (row.objectType != kKnowledgePointObjectType) {
      continue;
    }
    tagCounts[row.objectId] = (tagCounts[row.objectId] ?? 0) + 1;
  }

  final states = await db.select(db.cardStates).get();
  final boosts = await db.select(db.boostEntries).get();

  final templates = await db.select(db.cardTemplates).get();
  final flashcardOfTemplate = {
    for (final template in templates) template.id: template.knowledgePointId,
  };

  final live = <(CardState, String)>[];
  for (final state in states) {
    final templateId = state.cardTemplateId;
    final flashcardId = state.knowledgePointId ??
        (templateId == null ? null : flashcardOfTemplate[templateId]);
    if (flashcardId == null || !titles.containsKey(flashcardId)) {
      continue;
    }
    live.add((state, flashcardId));
  }

  return CognitiveObservationInputs(
    units: [
      for (final (state, flashcardId) in live)
        CognitiveObservedUnit(
          row: state,
          knowledgePointTitle: titles[flashcardId]!,
          tagCount: tagCounts[flashcardId] ?? 0,
          isNew: state.repetitions == 0,
        ),
    ],
    boostFactorByKnowledgePoint: {
      for (final boost in boosts)
        if (titles.containsKey(boost.knowledgePointId))
          boost.knowledgePointId: boost.factor,
    },
  );
}

/// 知识点 id → 它直挂的标签 id（Q8）。
///
/// 这一层存在是因为**两套 id 不是一回事**：知识点是 `kp-…`，标签是 `tag-…`，
/// 而认知快层的图节点是标签（`cognitive_graph.dart` 的 `CognitiveTag.fromTag`
/// 直接取 `row.id`）。调用方手里的是知识点，runner 要的是图节点，所以读一次
/// `object_tags` 交给 [KnowledgePointTagBridge] 翻译。
///
/// 以前没有这一层：调用方把知识点 id 直接当图节点 id 传进去，`starts`/`targets`/
/// `rowsByKnowledgePoint` 在真实数据上全被丢掉，界面永远显示"这轮没诊断"
/// （实测与解释见 `docs/THREADFLOW_TWO_SEGMENT.md` §8.3）。
Future<Map<String, List<String>>> readKnowledgePointTagIds(
    AppDatabase db) async {
  final rows = await db.select(db.objectTags).get();
  return KnowledgePointTagBridge.tagIdsByKnowledgePoint(<ObjectTagLink>[
    for (final row in rows)
      ObjectTagLink(
        tagId: row.tagId,
        objectType: row.objectType,
        objectId: row.objectId,
      ),
  ]);
}

/// The tierB run behind the zone column: the tag tree plus one representative
/// card row per knowledge point, diffused once from the most recently reviewed
/// points toward today's due set.
///
/// Two product rules are visible here on purpose (Furnace has no goal entity):
///
/// * `starts` = the [cognitiveStartNodeLimit] most recently reviewed points.
/// * `targets` = the points with something due now (or a forced card) - "what
///   this session is trying to push". Nodes outside that set can therefore be
///   reported as `off_goal` / `dead_end`, which is what those verdicts mean.
///
/// `danger` can appear here: it is the metacognition layer's verdict on a
/// tagged point that has a representative card row and is not one of `starts` -
/// `LibraryDiagnosisRunner._readMetacognition` derives the belief/reality gap
/// from the stored rows, it does not need a belief table. A point with no card
/// row (or no finite reading) is skipped there, so "absent" means "no data",
/// not "healthy".
///
/// `null` is not a possible return: the "did the layer run" fact is carried by
/// [LibraryDiagnosis.notRun]'s `fastLayerRan == false` (an empty tag set or an
/// empty observation surface returns exactly that).
Future<LibraryDiagnosis> readLibraryDiagnosis(
  AppDatabase db, {
  required CognitiveModel model,
  DateTime? now,
  CognitiveObservationInputs? inputs,
}) async {
  final moment = now ?? DateTime.now();
  final nowHours = modelHoursOf(moment);
  final observation = inputs ?? await readCognitiveObservationInputs(db);
  final units = observation.units;

  final tags = [
    for (final row in await db.select(db.tags).get()) CognitiveTag.fromTag(row),
  ];
  if (tags.isEmpty || units.isEmpty) {
    return LibraryDiagnosis.notRun;
  }

  // One representative row per knowledge point, using the same rule as the AI
  // tool (`representativeCardRow`) so the page and the tool cannot disagree.
  final rowsByKnowledgePoint = <String, List<CardState>>{};
  for (final unit in units) {
    (rowsByKnowledgePoint[unit.knowledgePointId] ??= <CardState>[])
        .add(unit.row);
  }
  final rows = <String, CardState>{};
  for (final entry in rowsByKnowledgePoint.entries) {
    final row = representativeCardRow(entry.value);
    if (row != null) {
      rows[entry.key] = row;
    }
  }

  final reviewed = [
    for (final entry in rows.entries)
      if (entry.value.lastReviewedAt != null) entry,
  ]..sort((a, b) {
      final byReviewed =
          b.value.lastReviewedAt!.compareTo(a.value.lastReviewedAt!);
      return byReviewed != 0 ? byReviewed : a.key.compareTo(b.key);
    });
  final starts = [
    for (final entry in reviewed.take(cognitiveStartNodeLimit)) entry.key,
  ];

  final nowMs = moment.millisecondsSinceEpoch;
  final targets = [
    for (final entry in rows.entries)
      if (entry.value.forced == 1 ||
          (entry.value.dueAt != null && entry.value.dueAt! <= nowMs))
        entry.key,
  ];

  // Everything above is keyed by **knowledge point** (`kp-…`) because that is
  // what cards and observations hang off. The runner's graph is built from
  // **tags** (`tag-…`), so we hand it the bridge and it translates in and out
  // (`LibraryDiagnosisRunner.run`, Q8). Without that translation the runner
  // silently drops every row and start, and the surface shows "no diagnosis yet"
  // no matter how much data there is - the bug documented in
  // `docs/THREADFLOW_TWO_SEGMENT.md` §8.3.
  final tagIdsByKnowledgePoint = await readKnowledgePointTagIds(db);

  return LibraryDiagnosisRunner.run(
    tags: tags,
    rowsByKnowledgePoint: rows,
    model: model,
    nowHours: nowHours,
    startKnowledgePointIds: starts,
    targetKnowledgePointIds: targets,
    tagIdsByKnowledgePoint: tagIdsByKnowledgePoint,
  );
}

String? _jsonString(Object? value) => value == null ? null : value as String;

int? _jsonInt(Object? value) => switch (value) {
      int value => value,
      num value => value.toInt(),
      String value => int.tryParse(value),
      _ => null,
    };

double? _jsonDouble(Object? value) => switch (value) {
      double value => value,
      num value => value.toDouble(),
      String value => double.tryParse(value),
      _ => null,
    };
