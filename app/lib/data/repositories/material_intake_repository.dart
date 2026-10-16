/// 材料摄取的**落库层**：把"要建什么"记进库，并在确认后真的建（roadmap §2-C ①，
/// 轮次六十四）。
///
/// 三层分工，一层都不许越界：
///  * `MaterialIngest`（`domain/services/ingest/material_ingest.dart`）把信封变成
///    图补丁与 `mindnet.run/1` 请求 —— 确定性、无数据库；
///  * `MaterialIntakePlanner`（`domain/services/ingest/material_intake_plan.dart`）
///    把图补丁折成"要建哪些知识点/连接、每条什么出处" —— 纯 Dart，一行不写；
///  * 这里（`data/repositories/`）把提案记进库（`record`），并在用户确认后写
///    `knowledge_points`（`apply`）。
///
/// 三条纪律：
///  * **确认前不写知识点**：`record` 只写提案表，`knowledge_points` 只在 `apply`
///    时被碰。用户没点头的东西不该出现在复习队列里（与拍照整理同一条先例）。
///  * **幂等**：批次主键就是信封的 `batch_id`（INGEST 契约的幂等键），提案主键是
///    `<batchId>#<proposalId>`（id 由内容决定）。同一份材料重算 → 覆盖未确认的提案，
///    不会长出第二批；同一条提案确认两次 → 第二次看到 `applied_at` 就不动了，更不会
///    建出两个知识点。
///  * **没定的事不假装做完**：落不了的连接（有一端还不在库里）留在待办里，
///    `apply` 的结果里如实报成 `deferred` —— 编一条连不上两端的边比不写更坏。
///    连接落在 `knowledge_edges`（线索边，严格有向；`ls` 带 `ls_calibrated: false`
///    的未标定标记），包含语义仍只在标签树的父子边里（`tags.parent_id`）。
library;

import 'dart:convert';

import 'package:drift/drift.dart';

import '../../domain/services/ingest/material_intake_plan.dart';
import '../../domain/services/ingest/transcribe_run.dart';
import '../database/database.dart';
import 'anki_repository.dart';

/// 还没被确认的一批提案（给工具/界面读）。
class MaterialIntakeBatch {
  const MaterialIntakeBatch({
    required this.batchId,
    this.topic,
    this.sourceRef,
    this.sourceKind,
    this.capturedAtMs,
    required this.analyzedAtMs,
    required this.summaryText,
    required this.skipped,
    required this.proposalCount,
    required this.unappliedCount,
    required this.appliedCount,
  });

  final String batchId;
  final String? topic;
  final String? sourceRef;
  final String? sourceKind;
  final int? capturedAtMs;
  final int analyzedAtMs;

  /// 转化汇总那句话（`MaterialSummary.text`）。
  final String summaryText;

  /// 留在清单外的条目与原因。
  final List<MaterialIntakeSkip> skipped;

  final int proposalCount;

  /// 还没处理的提案数（知识点与连接都算：连接要等两端都在库里，见 §2-C ④）。
  final int unappliedCount;

  /// 已经点过头的提案数（`applied_at` 非空）。`unappliedCount == 0` 且这批不是空的
  /// ⇒ 这批"确认完了"，界面把它从待确认挪到"已经确认完的"。
  final int appliedCount;

  bool get isEmpty => proposalCount == 0;

  Map<String, Object?> toJson() => <String, Object?>{
        'batch_id': batchId,
        if (topic != null) 'topic': topic,
        if (sourceRef != null) 'source': sourceRef,
        if (sourceKind != null) 'source_kind': sourceKind,
        'analyzed_at_ms': analyzedAtMs,
        'summary': summaryText,
        'proposal_count': proposalCount,
        'unapplied_count': unappliedCount,
        'applied_count': appliedCount,
        'skipped_count': skipped.length,
        'skipped': [for (final item in skipped) item.toJson()],
      };
}

/// `apply` 建出来的一个知识点。
class MaterialAppliedPoint {
  const MaterialAppliedPoint({
    required this.proposalId,
    required this.knowledgePointId,
    required this.title,
    this.nodeId,
  });

  final String proposalId;

  /// 库里那一行的 id（`kp-…`）。
  final String knowledgePointId;

  final String title;

  /// 写进 `knowledge_points.external_id` 的节点 id（`en::w::resilient`）。
  final String? nodeId;

  Map<String, Object?> toJson() => <String, Object?>{
        'proposal_id': proposalId,
        'knowledge_point_id': knowledgePointId,
        'title': title,
        if (nodeId != null) 'node_id': nodeId,
      };
}

/// `apply` 建出来的一条**线索边**（`knowledge_edges`）。
class MaterialAppliedEdge {
  const MaterialAppliedEdge({
    required this.proposalId,
    required this.edgeId,
    required this.fromId,
    required this.toId,
    this.origin,
  });

  final String proposalId;

  /// 边自己的 id（INGEST 的 `e_<from>__<to>`），同时是幂等键。
  final String edgeId;

  /// 两端（材料节点 id = `knowledge_points.external_id`）。
  final String fromId;
  final String toId;

  /// 材料里的关系（`contains` / `produce` / `topic`）。
  final String? origin;

  Map<String, Object?> toJson() => <String, Object?>{
        'proposal_id': proposalId,
        'edge_id': edgeId,
        'from': fromId,
        'to': toId,
        if (origin != null) 'origin': origin,
      };
}

/// 一次 `apply` 的结果：建了什么、什么已存在、什么还等着。
class MaterialApplyOutcome {
  const MaterialApplyOutcome({
    required this.batchId,
    required this.created,
    required this.createdEdges,
    required this.existing,
    required this.existingEdges,
    required this.deferred,
    required this.remaining,
  });

  final String batchId;

  /// 真的新建出来的知识点。
  final List<MaterialAppliedPoint> created;

  /// 真的新建出来的线索边（`knowledge_edges`）。
  final List<MaterialAppliedEdge> createdEdges;

  /// 同名或同一个 `external_id` 已在库里的提案（去重，没有重复写）。
  final List<String> existing;

  /// 已经在库里的边（同一条边 id，没有重复写）。
  final List<String> existingEdges;

  /// 连接提案：两端不齐，落不了 —— 如实留着，并把缺的那一端写进理由。
  final List<String> deferred;

  /// 处理完以后这一批还剩多少条没动。
  final int remaining;

  /// 人话一行（给工具/日志用）。
  String get text {
    if (created.isEmpty &&
        createdEdges.isEmpty &&
        existing.isEmpty &&
        existingEdges.isEmpty &&
        deferred.isEmpty) {
      return '批次 $batchId 没有待确认的提案';
    }
    final parts = <String>[
      if (created.isNotEmpty) '新建 ${created.length} 个知识点',
      if (createdEdges.isNotEmpty) '新建 ${createdEdges.length} 条连接',
      if (existing.isNotEmpty || existingEdges.isNotEmpty)
        '${existing.length + existingEdges.length} 条已存在（没重复建）',
      if (deferred.isNotEmpty) '${deferred.length} 条连接落不了（有一端还不在库里）',
    ];
    final left = remaining > 0 ? '；还剩 $remaining 条待确认' : '';
    return '批次 $batchId：${parts.join('、')}$left';
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'batch_id': batchId,
        'created': [for (final point in created) point.toJson()],
        'created_count': created.length,
        'created_edges': [for (final edge in createdEdges) edge.toJson()],
        'created_edge_count': createdEdges.length,
        'existing': existing,
        'existing_edges': existingEdges,
        'deferred': deferred,
        'remaining': remaining,
      };
}

/// `apply` 用不了时抛这个（批次不存在 / 提案 id 不认识）。
class MaterialApplyException implements Exception {
  const MaterialApplyException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 材料摄取的提案表 + 确认写入。
class MaterialIntakeRepository {
  MaterialIntakeRepository(
    this._db, {
    AnkiRepository? ankiRepository,
    DateTime Function()? clock,
  })  : _anki = ankiRepository ?? AnkiRepository(_db),
        _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final AnkiRepository _anki;
  final DateTime Function() _clock;

  /// 把一份计划记进库（幂等）。
  ///
  /// 同一 [MaterialIntakePlan.batchId] 再记一次，效果是"用新算的替换还没确认的
  /// 提案"：已确认（`applied_at` 非空）的行**不动** —— 重算不能把用户已经点过头的
  /// 记录抹掉，更不能让已经建出来的知识点在下一轮被再建一遍。
  Future<MaterialIntakeBatch> record(
    MaterialIntakePlan plan, {
    required String summaryText,
    required DateTime analyzedAt,
    String? sourceKind,
    int? capturedAtMs,
  }) async {
    final now = _clock().millisecondsSinceEpoch;
    await _db.transaction(() async {
      // 未确认的提案整批替换。
      await (_db.delete(_db.materialIntakeProposals)
            ..where(
                (t) => t.batchId.equals(plan.batchId) & t.appliedAt.isNull()))
          .go();
      for (var index = 0; index < plan.proposals.length; index++) {
        final proposal = plan.proposals[index];
        await _db.into(_db.materialIntakeProposals).insert(
              MaterialIntakeProposalsCompanion.insert(
                id: '${plan.batchId}#${proposal.id}',
                batchId: plan.batchId,
                proposalId: proposal.id,
                sortIndex: index,
                kind: proposal.kind.id,
                payloadJson: jsonEncode(proposal.toJson()),
                createdAt: now,
                updatedAt: now,
              ),
              mode: InsertMode.insertOrIgnore,
            );
      }
      await _db.into(_db.materialIntakeBatches).insertOnConflictUpdate(
            MaterialIntakeBatchesCompanion.insert(
              batchId: plan.batchId,
              topic: Value(plan.topic),
              sourceRef: Value(plan.sourceRef),
              sourceKind: Value(sourceKind),
              capturedAt: Value(capturedAtMs),
              analyzedAt: analyzedAt.millisecondsSinceEpoch,
              summaryText: summaryText,
              skippedJson:
                  jsonEncode([for (final skip in plan.skipped) skip.toJson()]),
              proposalCount: plan.proposals.length,
              createdAt: now,
              updatedAt: now,
            ),
          );
    });
    return (await batch(plan.batchId))!;
  }

  /// 库里现有知识点的标题（计划层算 `exists` 用）。
  ///
  /// 放在仓储里而不是让工具自己去查，是为了让"拿哪份标题去重"只有一处口径：**看**提案的
  /// 那一层与**写**提案的这一层必须看同一份，否则会出现"看着说不重复建、写的时候又建了"。
  Future<Set<String>> existingTitles() async => <String>{
        for (final point in await _anki.getKnowledgePoints()) point.title,
      };

  /// 库里已知的 MindNet 节点（材料入库时写在 `knowledge_points.external_id` 上）。
  ///
  /// 转写规程要用它填【图清单】：`review`/`exposure`/`goal` 只能指向图里已有的节点，
  /// 而"图"在应用侧的真实来源就是这一列 —— 让 AI 猜 id 是 TRANSCRIBE §1 第 2 条
  /// 明令禁止的事，所以清单必须从库里查。
  Future<List<TranscribeInventoryEntry>> externalNodeInventory() async {
    final rows = await (_db.select(_db.knowledgePoints)
          ..where((t) => t.externalId.isNotNull()))
        .get();
    final inventory = <TranscribeInventoryEntry>[];
    for (final row in rows) {
      final id = row.externalId;
      if (id == null || id.isEmpty) {
        continue;
      }
      inventory.add((id: id, name: row.title));
    }
    return inventory;
  }

  /// 一个批次（读不到返回 null）。
  Future<MaterialIntakeBatch?> batch(String batchId) async {
    final row = await (_db.select(_db.materialIntakeBatches)
          ..where((t) => t.batchId.equals(batchId)))
        .getSingleOrNull();
    if (row == null) {
      return null;
    }
    return _toBatch(row);
  }

  /// 所有批次，新的在前。
  Future<List<MaterialIntakeBatch>> batches() async {
    final rows = await (_db.select(_db.materialIntakeBatches)
          ..orderBy([
            (t) => OrderingTerm.desc(t.analyzedAt),
            (t) => OrderingTerm.desc(t.batchId),
          ]))
        .get();
    return [for (final row in rows) await _toBatch(row)];
  }

  /// 一批里还没确认的提案，按记录时的次序。
  Future<List<MaterialIntakeProposal>> pendingProposals(String batchId) async {
    final rows = await (_db.select(_db.materialIntakeProposals)
          ..where((t) => t.batchId.equals(batchId) & t.appliedAt.isNull())
          ..orderBy([(t) => OrderingTerm.asc(t.sortIndex)]))
        .get();
    return [for (final row in rows) _toProposal(row)];
  }

  /// 一批里已经确认过的提案（`applied_at` 非空），按记录时的次序。
  ///
  /// "确认过"就是"写过库"：知识点与线索边各自落成，缺端的连接根本没标 `applied_at`
  /// （它们还在 `pendingProposals` 里），所以这份名单里不会出现"其实没落"的条目。
  Future<List<MaterialIntakeProposal>> appliedProposals(String batchId) async {
    final rows = await (_db.select(_db.materialIntakeProposals)
          ..where((t) => t.batchId.equals(batchId) & t.appliedAt.isNotNull())
          ..orderBy([(t) => OrderingTerm.asc(t.sortIndex)]))
        .get();
    return [for (final row in rows) _toProposal(row)];
  }

  /// 一批里的全部提案（含已确认的），按记录时的次序。
  Future<List<MaterialIntakeProposal>> proposals(String batchId) async {
    final rows = await (_db.select(_db.materialIntakeProposals)
          ..where((t) => t.batchId.equals(batchId))
          ..orderBy([(t) => OrderingTerm.asc(t.sortIndex)]))
        .get();
    return [for (final row in rows) _toProposal(row)];
  }

  /// 用户确认：把还没处理的提案落到 `knowledge_points` 与 `knowledge_edges`。
  ///
  /// [proposalIds] 为空表示"这一批还没处理的全部"；给了就只处理这些（界面上的
  /// 逐条确认）。返回的名单按"建了 / 已存在 / 落不了"分开：知识点与连接各自计数，
  /// `deferred` 只装连接 —— 连接的**两端必须都在**（本批刚建的或库里已有的节点 id），
  /// 否则落不了，如实留在待办里（与 MindNet `validateRequest` 的影子图同一条规则）。
  Future<MaterialApplyOutcome> apply({
    required String batchId,
    List<String>? proposalIds,
    DateTime? appliedAt,
  }) async {
    final row = await (_db.select(_db.materialIntakeBatches)
          ..where((t) => t.batchId.equals(batchId)))
        .getSingleOrNull();
    if (row == null) {
      throw MaterialApplyException('没有这个批次：$batchId');
    }
    final requested = proposalIds?.toSet();
    final now = (appliedAt ?? _clock()).millisecondsSinceEpoch;

    final created = <MaterialAppliedPoint>[];
    final createdEdges = <MaterialAppliedEdge>[];
    final existing = <String>[];
    final existingEdges = <String>[];
    final deferred = <String>[];
    var remaining = 0;

    await _db.transaction(() async {
      final rows = await (_db.select(_db.materialIntakeProposals)
            ..where((t) => t.batchId.equals(batchId) & t.appliedAt.isNull())
            ..orderBy([(t) => OrderingTerm.asc(t.sortIndex)]))
          .get();
      // 先处理知识点：连接的两端可能正是这一批刚建出来的（影子图规则）。
      final pending =
          <({MaterialIntakeProposal proposal, MaterialIntakeProposalRow row})>[
        for (final row in rows) (proposal: _toProposal(row), row: row),
      ];
      pending.sort((a, b) {
        final byKind = a.proposal.kind.index.compareTo(b.proposal.kind.index);
        return byKind != 0
            ? byKind
            : a.row.sortIndex.compareTo(b.row.sortIndex);
      });
      for (final entry in pending) {
        final proposal = entry.proposal;
        final proposalRow = entry.row;
        final picked = requested == null || requested.contains(proposal.id);
        if (proposal.kind == MaterialIntakeKind.connection) {
          if (!picked) {
            remaining++;
            continue;
          }
          final edge = await _createEdge(proposal, batchId, now);
          if (edge.created) {
            createdEdges.add(edge.edge!);
          } else if (edge.missingEndpoint != null) {
            deferred.add(proposal.id);
            remaining++;
            continue;
          } else {
            existingEdges.add(proposal.id);
          }
          await _markApplied(proposalRow, now);
          continue;
        }
        if (!picked) {
          remaining++;
          continue;
        }

        final point = await _createPoint(proposal, now);
        if (point.created) {
          created.add(point.point!);
        } else {
          existing.add(proposal.id);
        }
        await _markApplied(proposalRow, now);
      }
    });

    return MaterialApplyOutcome(
      batchId: batchId,
      created: created,
      createdEdges: createdEdges,
      existing: existing,
      existingEdges: existingEdges,
      deferred: deferred,
      remaining: remaining,
    );
  }

  Future<void> _markApplied(MaterialIntakeProposalRow row, int now) async {
    await (_db.update(_db.materialIntakeProposals)
          ..where((t) => t.id.equals(row.id)))
        .write(MaterialIntakeProposalsCompanion(
      appliedAt: Value(now),
      updatedAt: Value(now),
    ));
  }

  /// 建一条**线索边**，或者因为端点不齐 / 已经在库里而不建。
  ///
  /// 三条规则：① 两端都必须在（本批刚建的知识点有 `external_id`，库里原有的也算）——
  /// 缺一端就落不了，返回 `missingEndpoint` 让调用方如实报 `deferred`；
  /// ② 幂等看边 id（INGEST 算的 `e_<from>__<to>`），重复确认不长第二条；
  /// ③ 严格有向：一条边只从 [MaterialIntakeProposal.from] 指向 [to]，反向要另建。
  Future<
      ({
        bool created,
        MaterialAppliedEdge? edge,
        String? missingEndpoint,
      })> _createEdge(
    MaterialIntakeProposal proposal,
    String batchId,
    int now,
  ) async {
    final from = proposal.from;
    final to = proposal.to;
    if (from == null || to == null) {
      return (created: false, edge: null, missingEndpoint: '边缺端点');
    }
    final edgeId = proposal.id.startsWith('edge:')
        ? proposal.id.substring('edge:'.length)
        : proposal.id;
    final existingRow = await (_db.select(_db.knowledgeEdges)
          ..where((t) => t.id.equals(edgeId)))
        .getSingleOrNull();
    if (existingRow != null) {
      return (created: false, edge: null, missingEndpoint: null);
    }
    final fromKnown = await _nodeExists(from);
    final toKnown = await _nodeExists(to);
    if (!fromKnown || !toKnown) {
      final missing = !fromKnown && !toKnown
          ? '两端都还不在库里'
          : (!fromKnown ? '起点 $from 还不在库里' : '终点 $to 还不在库里');
      return (created: false, edge: null, missingEndpoint: missing);
    }
    await _db.into(_db.knowledgeEdges).insert(KnowledgeEdgesCompanion.insert(
          id: edgeId,
          fromId: from,
          toId: to,
          origin: proposal.origin ?? 'material',
          ls: Value(proposal.ls),
          batchId: Value(batchId),
          source: Value(_sourceLabel(proposal.evidence)),
          createdAt: now,
          updatedAt: now,
        ));
    return (
      created: true,
      edge: MaterialAppliedEdge(
        proposalId: proposal.id,
        edgeId: edgeId,
        fromId: from,
        toId: to,
        origin: proposal.origin,
      ),
      missingEndpoint: null,
    );
  }

  /// 这个节点 id 是不是已经在库里（`knowledge_points.external_id`）。
  Future<bool> _nodeExists(String nodeId) async {
    final found = await (_db.select(_db.knowledgePoints)
          ..where((t) => t.externalId.equals(nodeId))
          ..limit(1))
        .getSingleOrNull();
    return found != null;
  }

  /// 建一个知识点，或者发现"已经在库里"。
  ///
  /// 两道去重，缺一不可：① 提案自己带了 `exists`（同名，算计划时就看得出来）；
  /// ② 同 `external_id`（`en::w::…`）已经有一行 —— 同名判断看的是标题，用户改过
  /// 标题之后它就抓不住了，而 `external_id` 是材料决定的内容 id。
  Future<({bool created, MaterialAppliedPoint? point})> _createPoint(
    MaterialIntakeProposal proposal,
    int now,
  ) async {
    final nodeId = proposal.nodeId;
    if (nodeId != null) {
      final found = await (_db.select(_db.knowledgePoints)
            ..where((t) => t.externalId.equals(nodeId))
            ..limit(1))
          .getSingleOrNull();
      if (found != null) {
        return (created: false, point: null);
      }
    }
    if (proposal.exists) {
      return (created: false, point: null);
    }
    final point = await _anki.createKnowledgePoint(
      title: proposal.title,
      content: proposal.body,
      source: _sourceLabel(proposal.evidence),
      externalId: nodeId,
    );
    return (
      created: true,
      point: MaterialAppliedPoint(
        proposalId: proposal.id,
        knowledgePointId: point.id,
        title: point.title,
        nodeId: nodeId,
      ),
    );
  }

  /// 出处那一行（`knowledge_points.source` 是自由文本，材料摄取是它的新产出方）。
  ///
  /// 写成 `材料：词汇书（第 12 页）`：`evidence` 的完整形状留在提案表的
  /// `payload_json` 里，这一列只要够人认出来源。
  static String? _sourceLabel(MaterialIntakeEvidence evidence) {
    final source = evidence.source;
    final page = evidence.page;
    if (source == null && page == null) {
      return null;
    }
    final pageText = page == null ? '' : '（第 ${page.round()} 页）';
    return '材料：${source ?? '未标出处'}$pageText';
  }

  Future<MaterialIntakeBatch> _toBatch(MaterialIntakeBatchRow row) async {
    // 一次查询把两边的数都数出来：待确认（给"待确认清单"）与已确认（给历史）。
    final rows = await (_db.select(_db.materialIntakeProposals)
          ..where((t) => t.batchId.equals(row.batchId)))
        .get();
    var unapplied = 0;
    var applied = 0;
    for (final proposal in rows) {
      if (proposal.appliedAt == null) {
        unapplied++;
      } else {
        applied++;
      }
    }
    return MaterialIntakeBatch(
      batchId: row.batchId,
      topic: row.topic,
      sourceRef: row.sourceRef,
      sourceKind: row.sourceKind,
      capturedAtMs: row.capturedAt,
      analyzedAtMs: row.analyzedAt,
      summaryText: row.summaryText,
      skipped: _skippedOf(row.skippedJson),
      proposalCount: row.proposalCount,
      unappliedCount: unapplied,
      appliedCount: applied,
    );
  }

  static List<MaterialIntakeSkip> _skippedOf(String json) {
    final decoded = jsonDecode(json);
    if (decoded is! List) {
      return const <MaterialIntakeSkip>[];
    }
    return [
      for (final item in decoded)
        if (item is Map)
          MaterialIntakeSkip.fromJson(item.cast<String, Object?>()),
    ];
  }

  static MaterialIntakeProposal _toProposal(MaterialIntakeProposalRow row) {
    final decoded = jsonDecode(row.payloadJson);
    if (decoded is! Map) {
      throw FormatException('提案 ${row.id} 的 payload 不是对象');
    }
    return MaterialIntakeProposal.fromJson(decoded.cast<String, Object?>());
  }
}
