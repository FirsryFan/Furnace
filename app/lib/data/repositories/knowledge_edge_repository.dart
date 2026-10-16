import 'package:drift/drift.dart';

import '../database/database.dart';

/// 一条线索边的读法（`knowledge_edges`，轮次六十八定案；`docs/MINDNET_ROADMAP.md` §2-C ④）。
///
/// 这是**只读快照**：这条边的写入只有一处（`MaterialIntakeRepository.apply` 里
/// 被确认过的连接），这里只把库里那行翻译成人能看的东西 —— 两端的标题、材料出处、
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

/// 线索边的读法（这一层不写）。
///
/// 只读是刻意的：边的写入路径只有材料摄取那一条（先确认、再落库），
/// 多一个写者就多一处能绕开"确认前不写"的地方。
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
