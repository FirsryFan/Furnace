import 'package:drift/drift.dart';

import '../database/database.dart';

/// 一条线索边的读法（`knowledge_edges`，轮次六十八定案；`docs/MINDNET_ROADMAP.md` §2-C ④）。
///
/// 这是**只读快照**：把库里那行翻译成人能看的东西 —— 两端的标题、材料出处、
/// `ls` 以及它有没有标定来源。
class KnowledgeEdgeView {
  const KnowledgeEdgeView({
    required this.id,
    required this.fromId,
    required this.toId,
    required this.origin,
    required this.lsCalibrated,
    required this.createdAt,
    this.fromTitle,
    this.toTitle,
    this.source,
    this.ls,
  });

  /// 边的幂等键（INGEST 算出来的 `e_<from>__<to>`）。
  final String id;

  /// 起点 / 终点的节点 id（= `knowledge_points.external_id`）。
  final String fromId;
  final String toId;

  /// 两端的标题；那一端不在 `knowledge_points` 里时是 null ——
  /// 界面按 id 显示就好，**不编一个名字**（编了就等于替图编造节点）。
  final String? fromTitle;
  final String? toTitle;

  /// 材料里写的是哪种关系（`contains` / `produce` / `topic` / `manual` / `material`）。
  /// 它是出处，不是权重。
  final String origin;

  /// 材料出处那句（例如 `材料：词汇书（第 12 页）`）。
  final String? source;

  /// 线索强度 `ls`。可空：材料没给就不假装有。
  final double? ls;

  /// `ls` 有没有标定来源（`MEMORY_RECORD.md` §3.5 说没有 —— 所以默认 false）。
  final bool lsCalibrated;

  final int createdAt;

  /// 有一端不在库里（端点还没建，或已被删）。界面必须说出来。
  bool get hasMissingEndpoint => fromTitle == null || toTitle == null;
}

/// 图里的一个端点：有 `external_id` 的知识点（手写的点当不了边的端点）。
class KnowledgeEdgeEndpoint {
  const KnowledgeEdgeEndpoint({required this.externalId, required this.title});

  final String externalId;
  final String title;
}

/// 手写一条边的结果。每种结果都要能说人话，所以分开报，不合成一个 bool。
enum ManualEdgeOutcome {
  created,

  /// 这个方向已经有一条边了（**任何** origin 的都算）—— 没重复加。
  alreadyExists,

  /// 两端必须都已经在图里（按 `external_id` 找得到知识点）。
  unknownEndpoint,

  /// 起点和终点是同一个点：自己连自己不是线索。
  samePoint,
}

class ManualEdgeResult {
  const ManualEdgeResult(
    this.outcome, {
    this.edgeId,
    this.existingOrigin,
  });

  final ManualEdgeOutcome outcome;

  /// `created` 时是新边的 id；`alreadyExists` 时是那条既有边的 id。
  final String? edgeId;

  /// `alreadyExists` 时那条既有边是什么关系来的（界面要如实说出来）。
  final String? existingOrigin;
}

/// 删一条手写边。材料确认来的边不归这里删。
enum ManualEdgeDeleteOutcome {
  deleted,

  /// 这条边已经不在了（别处删过 / id 看错）。
  notFound,

  /// 它不是手写的：出处是材料，删了会让"材料里写了什么"和库里对不上。
  notManual,
}

/// 线索边的读法，以及**唯一的第二个写者**：手写边（`origin: 'manual'`）。
///
/// 写入的分工是刻意的：材料确认那条路负责"材料里写的连接"，这里只负责"用户自己看出来的连接"。
/// 手写边由此有了几处硬约束 —— 两端必须已经在图里、同一个方向只留一条（不管它是谁写的）、
/// 只能删自己写的（材料边要回材料那一步），`ls` 一律不给（没有标定来源就不假装有）。
class KnowledgeEdgeRepository {
  KnowledgeEdgeRepository(this._db);

  final AppDatabase _db;

  /// 全部线索边，新的在前；两端的标题按 `knowledge_points.external_id` 解出来。
  Future<List<KnowledgeEdgeView>> all() async {
    final rows = await _selectEdgeRows().get();
    return _viewsOf(rows);
  }

  /// 与某个知识点相连的线索边（**出边和入边都在里面**；方向由调用方按 id 判断）。
  ///
  /// [externalId] 就是 `knowledge_points.external_id`（材料节点 id）。手写的知识点
  /// 没有 `external_id`，它们本来就不在图里 —— 那种情况调用方要自己说清楚，
  /// 不要拿一个空列表冒充"它没有边"。
  Future<List<KnowledgeEdgeView>> forPoint(String externalId) async {
    final rows = await (_selectEdgeRows()
          ..where(
              (t) => t.fromId.equals(externalId) | t.toId.equals(externalId)))
        .get();
    return _viewsOf(rows);
  }

  /// 图里有 id 的知识点：可以当边的端点。按标题排序（手写边那个选择框要定序）。
  ///
  /// 没有 `external_id` 的知识点**不在这里**：它们没有图里的身份，连不了边 ——
  /// 这与"读法不替图编造节点"是同一条纪律，只是换了个方向。
  Future<List<KnowledgeEdgeEndpoint>> graphPoints() async {
    final rows = await (_db.select(_db.knowledgePoints)
          ..where((t) => t.externalId.isNotNull()))
        .get();
    final byId = <String, String>{};
    for (final row in rows) {
      final externalId = row.externalId;
      if (externalId != null) {
        // 同一个 external_id 有多行时取第一个：与解标题同一套规则。
        byId.putIfAbsent(externalId, () => row.title);
      }
    }
    final endpoints = <KnowledgeEdgeEndpoint>[
      for (final entry in byId.entries)
        KnowledgeEdgeEndpoint(externalId: entry.key, title: entry.value),
    ]..sort((a, b) {
        final byTitle = a.title.compareTo(b.title);
        return byTitle != 0 ? byTitle : a.externalId.compareTo(b.externalId);
      });
    return endpoints;
  }

  /// 手写一条线索边（`origin: 'manual'`，`ls` 不给、`source` 为空 —— 没有出处就别编一个）。
  ///
  /// 幂等键按方向写死（`manual:<from>-><to>`），并且在插入前先看**任何** origin 的既有边：
  /// 同一个方向只留一条，材料写过的不再手写一条平行的。
  Future<ManualEdgeResult> createManualEdge({
    required String fromId,
    required String toId,
    int? now,
  }) async {
    if (fromId == toId) {
      return const ManualEdgeResult(ManualEdgeOutcome.samePoint);
    }

    final known = await (_db.select(_db.knowledgePoints)
          ..where((t) => t.externalId.isIn(<String>{fromId, toId})))
        .get();
    final knownIds = <String>{
      for (final row in known)
        if (row.externalId != null) row.externalId!,
    };
    if (!knownIds.contains(fromId) || !knownIds.contains(toId)) {
      return const ManualEdgeResult(ManualEdgeOutcome.unknownEndpoint);
    }

    final existing = await (_db.select(_db.knowledgeEdges)
          ..where((t) => t.fromId.equals(fromId) & t.toId.equals(toId)))
        .getSingleOrNull();
    if (existing != null) {
      return ManualEdgeResult(
        ManualEdgeOutcome.alreadyExists,
        edgeId: existing.id,
        existingOrigin: existing.origin,
      );
    }

    final id = 'manual:$fromId->$toId';
    final stamp = now ?? DateTime.now().millisecondsSinceEpoch;
    await _db.into(_db.knowledgeEdges).insert(
          KnowledgeEdgesCompanion.insert(
            id: id,
            fromId: fromId,
            toId: toId,
            origin: 'manual',
            batchId: const Value<String?>(null),
            source: const Value<String?>(null),
            createdAt: stamp,
            updatedAt: stamp,
          ),
        );
    return ManualEdgeResult(ManualEdgeOutcome.created, edgeId: id);
  }

  /// 删一条**手写**边。材料来的边返回 [ManualEdgeDeleteOutcome.notManual] 并且**真的不删**。
  Future<ManualEdgeDeleteOutcome> deleteManualEdge(String edgeId) async {
    final row = await (_db.select(_db.knowledgeEdges)
          ..where((t) => t.id.equals(edgeId)))
        .getSingleOrNull();
    if (row == null) {
      return ManualEdgeDeleteOutcome.notFound;
    }
    if (row.origin != 'manual') {
      return ManualEdgeDeleteOutcome.notManual;
    }
    await (_db.delete(_db.knowledgeEdges)..where((t) => t.id.equals(edgeId)))
        .go();
    return ManualEdgeDeleteOutcome.deleted;
  }

  /// 一张表的两种读法共用同一套次序：新的在前，同一个时间戳按 id 定序。
  SimpleSelectStatement<$KnowledgeEdgesTable, KnowledgeEdgeRow>
      _selectEdgeRows() => _db.select(_db.knowledgeEdges)
        ..orderBy(<OrderClauseGenerator<$KnowledgeEdgesTable>>[
          (t) => OrderingTerm.desc(t.createdAt),
          (t) => OrderingTerm.asc(t.id),
        ]);

  /// 把库里那些行翻译成读法：两端的标题按 `knowledge_points.external_id` 解出来。
  Future<List<KnowledgeEdgeView>> _viewsOf(List<KnowledgeEdgeRow> rows) async {
    if (rows.isEmpty) {
      return const <KnowledgeEdgeView>[];
    }

    final endpoints = <String>{
      for (final row in rows) row.fromId,
      for (final row in rows) row.toId,
    };
    final points = await (_db.select(_db.knowledgePoints)
          ..where((t) => t.externalId.isIn(endpoints)))
        .get();
    final titles = <String, String>{};
    for (final point in points) {
      final externalId = point.externalId;
      if (externalId != null) {
        // 同一个 external_id 出现多次时取第一个：读法要确定，不许每次刷新换个名字。
        titles.putIfAbsent(externalId, () => point.title);
      }
    }

    return <KnowledgeEdgeView>[
      for (final row in rows)
        KnowledgeEdgeView(
          id: row.id,
          fromId: row.fromId,
          toId: row.toId,
          fromTitle: titles[row.fromId],
          toTitle: titles[row.toId],
          origin: row.origin,
          source: row.source,
          ls: row.ls,
          lsCalibrated: row.lsCalibrated,
          createdAt: row.createdAt,
        ),
    ];
  }
}
