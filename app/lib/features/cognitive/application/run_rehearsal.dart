/// 把一份 `mindnet.run/1` 请求**真的跑进引擎** —— 演练。
///
/// 为什么要有它：`run_executor.dart` 从轮次七十八就写好了，却一直没有调用者
/// （roadmap 一直挂着的那条「执行层没有调用者」）。这一层就是那个调用者，它回答
/// 「谁去装配引擎」这个问题：
///
///  1. **图先摆好**：请求里提到的节点（`review`/`exposure` 的 node、`goal` 的
///     starts/targets、以及边提到而没有任何 `knowledge` 动作去建的那两端），凡是库里
///     已经有的（`knowledge_points.external_id`），就按请求自己的 id 空间摆进仿真图；
///     节点 `ms` 用库里那张代表卡片的模型读数（`CognitiveModel.modelReadingOf(row).r0`）
///     —— 与库诊断同一个来源；读不出来就**省略**（引擎按 0.8），并把这个事实记进
///     [RunRehearsal.nodesWithoutMs]，不替它编一个数。
///  2. **边也摆好**：`knowledge_edges` 里两端都已经进图的那些边（`from_id`/`to_id` 存的
///     就是节点 id）。
///  3. **只装记忆层**：`executeRun` 只 apply 动作、不跑轮次，逐轮那四个机制一个也用不上；
///     复习/再读要动记忆袋，所以只装 `memory.dsr`（见 `MechanismCatalog.runRehearsalIds`，
///     机制面板因此会如实多列一处装配）。
///  4. **只跑不落库**：库里的 `knowledge_points` / `knowledge_edges` / `card_states` /
///     记忆态一个字都不动。把演练结果落库是另一件事（还没做），所以这里刻意不写。
///
/// 仍然诚实的边界：库里的复习历史**没有**变成记忆袋 —— 仿真图上的袋子从默认状态起算，
/// `ms` 只决定节点自己的读数起点。所以演练回答的是"这份请求会落在哪条机制路径上、
/// 动到哪些数"，不是"你的真实进度会变成多少"。
library;

import '../../../data/database/database.dart';
import '../../../data/repositories/anki_repository.dart';
import '../../../data/repositories/knowledge_edge_repository.dart';
import '../../../domain/services/cognitive/cognitive_model.dart';
import '../../../domain/services/cognitive/fast_engine.dart';
import '../../../domain/services/cognitive/library_diagnosis.dart';
import '../../../domain/services/cognitive/mechanism_catalog.dart';
import '../../../domain/services/ingest/material_ingest.dart';
import '../../../domain/services/ingest/run_executor.dart';

/// 一次演练：执行报告 + 摆进仿真图的那份"库里长什么样"。
class RunRehearsal {
  const RunRehearsal({
    required this.report,
    required this.seedNodeIds,
    required this.seedEdgeIds,
    required this.nodesWithoutMs,
    required this.unknownNodeIds,
  });

  /// `executeRun` 的报告（每条动作的痕迹都在里面）。
  final RunExecutionReport report;

  /// 库里已有、被摆进仿真图的节点 id（按请求提到它们的顺序）。
  final List<String> seedNodeIds;

  /// 两端都进了仿真图、从库里接过来的线索边 id。
  final List<String> seedEdgeIds;

  /// 进了图但读不出 `ms` 的节点：引擎用默认 0.8，这里如实列出来。
  final List<String> nodesWithoutMs;

  /// 动作指向、库里也没有的节点（`knowledge` 动作自己声明要建的那些不算）。
  final List<String> unknownNodeIds;

  bool get ok => report.ok;

  /// 留下了增量的条数：建节点/建边/推时钟/复习……每条跑成的动作都会说自己改了什么。
  int get changedCount =>
      report.traces.where((trace) => trace.ok && trace.delta.isNotEmpty).length;

  /// 真的动了机制钩子的条数 —— 判据是增量里带着机制名（目前只有记忆层回话：
  /// `review` / `exposure` 会带 `mechanism: 'memory.dsr'`）。建节点/推时钟那些不算。
  int get touchedMechanisms => report.traces
      .where((trace) => trace.ok && trace.delta['mechanism'] != null)
      .length;

  String get text {
    final buffer = StringBuffer('演练（只跑不落库，共 ${report.traces.length} 条动作）：');
    if (!report.ok) {
      buffer.write('停在「${report.traces.last.text}」。');
    } else {
      buffer.write('全部跑完（${report.appliedCount} 条应用，'
          '$changedCount 条留下了增量，$touchedMechanisms 条真的动了机制）。');
    }
    buffer.write('图里先摆好 ${seedNodeIds.length} 个库里已有的节点、'
        '${seedEdgeIds.length} 条库里已有的边');
    if (nodesWithoutMs.isNotEmpty) {
      buffer.write('；${nodesWithoutMs.length} 个节点没有 ms'
          '（模型读不出 r0，引擎按默认 0.8）');
    }
    if (unknownNodeIds.isNotEmpty) {
      buffer.write('；${unknownNodeIds.length} 个节点库里没有、'
          '也没有动作去建它');
    }
    buffer.write('。');
    return buffer.toString();
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'report': report.toJson(),
        'seed_node_ids': seedNodeIds,
        'seed_edge_ids': seedEdgeIds,
        'nodes_without_ms': nodesWithoutMs,
        'unknown_node_ids': unknownNodeIds,
      };
}

/// 装配引擎、摆好图，然后把 [request] 的动作跑一遍。
///
/// [now] 只在请求**自己没有**时间基（`time.model_hours` 缺失）时用得上：那时引擎从
/// 这一刻起算，动作若只给 `at.wall` 就会如实报"没有锚点"（不拿"现在"冒充锚点）。
Future<RunRehearsal> rehearseRun({
  required MaterialRunRequest request,
  required AppDatabase db,
  required CognitiveModel model,
  DateTime? now,
  RunAnchor? anchor,
}) async {
  final moment = now ?? DateTime.now();
  final nowHours = modelHoursOf(moment);
  final anki = AnkiRepository(db);

  // 1) 请求提到的节点：动作指向的、动作要建的、以及边提到的那两端。
  final mentioned = <String>{};
  final created = <String>{};
  for (final action in request.actions) {
    if (action.kind == 'knowledge') {
      final nodeId = (action.node?['id'] as String?) ?? action.nodeId;
      if (nodeId != null && nodeId.isNotEmpty) {
        created.add(nodeId);
      }
      final edge = action.edge;
      for (final end in <Object?>[edge?['from'], edge?['to']]) {
        if (end is String && end.isNotEmpty) {
          mentioned.add(end);
        }
      }
      continue;
    }
    final nodeId = action.nodeId;
    if (nodeId != null && nodeId.isNotEmpty) {
      mentioned.add(nodeId);
    }
    mentioned.addAll(action.targets ?? const <String>[]);
    mentioned.addAll(action.starts ?? const <String>[]);
  }

  // 2) 库里已有的图：节点按 `external_id`（同一个 id 有多行时取第一行）。
  final pointsByExternalId = <String, KnowledgePoint>{};
  for (final point in await anki.getKnowledgePoints()) {
    final externalId = point.externalId;
    if (externalId != null && externalId.isNotEmpty) {
      pointsByExternalId.putIfAbsent(externalId, () => point);
    }
  }

  final nodes = <Map<String, Object?>>[];
  final seedNodeIds = <String>[];
  final nodesWithoutMs = <String>[];
  final unknownNodeIds = <String>[];
  for (final id in mentioned) {
    // 请求自己会建的节点不先摆：`knowledge` 动作重复建同一个 id 会抛（那是真实行为，
    // 由执行报告如实报出来），这里不去替它掩盖。
    if (created.contains(id)) {
      continue;
    }
    final point = pointsByExternalId[id];
    if (point == null) {
      unknownNodeIds.add(id);
      continue;
    }
    final row = representativeCardRow(
      await anki.unitStatesForKnowledgePoint(point.id),
    );
    final r0 =
        row == null ? null : model.modelReadingOf(row, nowHours: nowHours).r0;
    final hasMs = r0 != null && r0.isFinite && r0 > 0 && r0 <= 1;
    if (!hasMs) {
      nodesWithoutMs.add(id);
    }
    nodes.add(<String, Object?>{
      'id': id,
      'name': point.title,
      // 库里没有"节点类型"这一列：标成 knowledge_point。引擎目前不读这个字段，
      // 不替它编一个更细的类型。
      'type': 'knowledge_point',
      if (hasMs) 'ms': r0,
    });
    seedNodeIds.add(id);
  }

  // 3) 边：两端都在仿真图里的才接过来（一端不在，那条边在演练里也走不通）。
  final seedEdgeIds = <String>[];
  final edges = <Map<String, Object?>>[];
  for (final edge in await KnowledgeEdgeRepository(db).all()) {
    if (!seedNodeIds.contains(edge.fromId) ||
        !seedNodeIds.contains(edge.toId)) {
      continue;
    }
    edges.add(<String, Object?>{
      'id': edge.id,
      'from': edge.fromId,
      'to': edge.toId,
      if (edge.ls != null) 'ls': edge.ls,
    });
    seedEdgeIds.add(edge.id);
  }

  // 4) 时间基：请求自己声明的优先（那份 `time` 也是它的锚点）。
  final hours = request.time.provided ? request.time.modelHours : nowHours;
  final wall =
      request.time.wall == null ? null : DateTime.tryParse(request.time.wall!);
  final seedAnchor = anchor ??
      (request.time.provided
          ? RunAnchor(modelHours: request.time.modelHours, wall: wall)
          : null);

  const overrides = MechanismCatalog.transcribedIgnition;
  final engine = FastEngine(
    graph: FastGraph.fromSpec(
      <String, Object?>{
        'nodes': nodes,
        'edges': edges,
      },
      currentRealTime: hours,
    ),
    mechanisms: FastMechanisms.fromModuleDefaults(
      const <String, Object?>{},
      ids: MechanismCatalog.runRehearsalIds,
      overrides: overrides,
    ),
    overrides: overrides,
    hours: hours,
  );

  return RunRehearsal(
    report: executeRun(request, engine: engine, anchor: seedAnchor),
    seedNodeIds: seedNodeIds,
    seedEdgeIds: seedEdgeIds,
    nodesWithoutMs: nodesWithoutMs,
    unknownNodeIds: unknownNodeIds,
  );
}
