import 'package:furnace/domain/services/ingest/material_intake_plan.dart';
import 'package:furnace/domain/services/ingest/run_executor.dart';

/// 一份 `run/1` 想建的东西没法变成提案时的说法（人话，直接给工具/界面用）。
///
/// 只有两种：**没跑完**（那就整份不算，理由里带上第一条没跑成的原因）与
/// **没有可建的东西**（这份请求里的动作都不建结构）。两者都不允许"挑能跑的先建"。
class RunKnowledgeException implements Exception {
  const RunKnowledgeException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 把一次演练里"要新建的东西"变成一份**待确认**提案计划。
///
/// 为什么要它（roadmap §2-C ②）：执行层（`run_executor.dart`）已经把 `knowledge`
/// 动作算成了节点/边，但它自己的纪律是"不动库"；而"把结果写进
/// `knowledge_points` / `knowledge_edges` 是**别的层**的事"。这一层就是那个"别的层"
/// 的入口 —— 但它**不直接写**，而是走材料摄取那条已经建好的路：
/// 先落下待确认提案（幂等键就是这一跑的 `run_id`），用户在"添加资料"的清单上
/// 点头之后才真的建。理由与材料一样：这些东西是模型从照片/贴进来的文本里读出来的，
/// 与人自己写下的知识点不是一回事，不该绕过"人确认"那道关。
///
/// 三条纪律，与材料入库同一条：
/// ① **没跑完的一跑不许变成提案**（`report.ok == false` 抛
///    [RunKnowledgeException]）—— 引擎跑到一半的中间态不是一份可确认的清单；
/// ② 提案只来自**引擎自己回报的增量**（`trace.delta`），不重读请求里写了什么 ——
///    跑出来的才是它真要建的（节点 id、名字、边的 `ls` 都取引擎的），
///    这样"清单上摆的"与"预览里说的"不可能不一样；
/// ③ 幂等键是 `run_id`：同一份请求确认两次不会建出两个知识点或两条边
///    （提案 id 是 `<run_id>#kp:<nodeId>` / `<run_id>#edge:<edgeId>`，
///    落库那一步按 `external_id` 与边 id 再去一次重）。
MaterialIntakePlan planRunKnowledge({
  required RunExecutionReport report,
  required Set<String> existingNodeIds,
  required Set<String> existingTitles,
  Map<String, String> nodeLabels = const <String, String>{},
  String? sourceRef,
}) {
  if (!report.ok) {
    final failure = report.failure!;
    throw RunKnowledgeException(
      '这一跑没跑完：第 ${failure.index + 1} 条动作（${failure.kind}）没跑成'
      ' —— ${failure.error}。'
      '没跑完的一跑不许变成提案（与材料入库同一条纪律：要么整份算清、要么一条都不动）。',
    );
  }

  final batchId = report.runId;
  final proposals = <MaterialIntakeProposal>[];
  final skipped = <MaterialIntakeSkip>[];

  // 两端说人话（轮次九十八）：先拿这一跑自己建的节点名字，再拿调用方给的（库里已有
  // 的节点 id → 标题），都没有才退回 id —— 清单上摆一串 `en::w::a → en::w::b`，
  // 人认不出这条边连的是谁。
  final labels = <String, String>{...nodeLabels};
  for (final trace in report.traces) {
    if (trace.kind != 'knowledge' || trace.delta['added'] != 'node') {
      continue;
    }
    final node = trace.delta['node'];
    if (node is! Map) {
      continue;
    }
    final json = node.cast<String, Object?>();
    final id = json['id']?.toString().trim() ?? '';
    final name = json['name']?.toString().trim() ?? '';
    if (id.isNotEmpty && name.isNotEmpty) {
      labels[id] = name;
    }
  }

  for (final trace in report.traces) {
    if (trace.kind != 'knowledge') {
      skipped.add(MaterialIntakeSkip(
        ref: 'action:${trace.index + 1}',
        reason: '第 ${trace.index + 1} 条是 ${trace.kind}，不建东西 —— '
            '这批提案只管"要新建什么"',
      ));
      continue;
    }

    final added = trace.delta['added'];
    final region = 'run/1 第 ${trace.index + 1} 条 knowledge 动作';
    final node = trace.delta['node'];
    final edge = trace.delta['edge'];

    if (added == 'node' && node is Map) {
      final json = node.cast<String, Object?>();
      final nodeId = json['id']?.toString().trim() ?? '';
      if (nodeId.isEmpty) {
        skipped.add(MaterialIntakeSkip(
          ref: 'action:${trace.index + 1}',
          reason: '第 ${trace.index + 1} 条要建的节点没有 id，认不出它是谁',
        ));
        continue;
      }
      final name = json['name']?.toString().trim() ?? '';
      final title = name.isEmpty ? nodeId : name;
      final type = json['type']?.toString().trim() ?? '';
      proposals.add(MaterialIntakeProposal(
        id: 'kp:$nodeId',
        kind: MaterialIntakeKind.knowledgePoint,
        title: title,
        nodeId: nodeId,
        // 正文这一跑没说就不编：留空，`why` 里说清"等你在清单上补"。
        body: '',
        why: '这份 `run/1` 要新建一个节点'
            '${type.isEmpty ? '' : '（类型 $type）'}；'
            '${name.isEmpty ? '它连名字都没给，标题只能用 id' : '正文这一跑没说'}，'
            '落库时内容留空、等你在清单上补',
        exists:
            existingTitles.contains(title) || existingNodeIds.contains(nodeId),
        evidence: MaterialIntakeEvidence(
          source: sourceRef,
          region: region,
          quote: trace.summary,
          batchId: batchId,
        ),
      ));
      continue;
    }

    if (added == 'edge' && edge is Map) {
      final json = edge.cast<String, Object?>();
      final from = json['from']?.toString().trim() ?? '';
      final to = json['to']?.toString().trim() ?? '';
      final edgeId = json['id']?.toString().trim() ?? '';
      if (from.isEmpty || to.isEmpty || edgeId.isEmpty) {
        skipped.add(MaterialIntakeSkip(
          ref: 'action:${trace.index + 1}',
          reason: '第 ${trace.index + 1} 条要建的边缺 id/from/to，认不出它连的是谁',
        ));
        continue;
      }
      proposals.add(MaterialIntakeProposal(
        id: 'edge:$edgeId',
        kind: MaterialIntakeKind.connection,
        title: '${labels[from] ?? from} → ${labels[to] ?? to}',
        from: from,
        to: to,
        // 引擎算出来的 0.8（请求没写 ls 时）在这里也照抄 —— 它已经带 `ls_calibrated: false`
        // 的未标定标记，与材料那条路同一个口径。
        ls: switch (json['ls']) {
          final num value => value.toDouble(),
          _ => null,
        },
        origin: 'run',
        body: '',
        why: '这份 `run/1` 要新建一条线索边'
            '（严格有向；两端都得在图里，缺一端就落不了、如实报 `deferred`）',
        exists: false,
        evidence: MaterialIntakeEvidence(
          source: sourceRef,
          region: region,
          quote: trace.summary,
          batchId: batchId,
        ),
      ));
      continue;
    }

    skipped.add(MaterialIntakeSkip(
      ref: 'action:${trace.index + 1}',
      reason: '第 ${trace.index + 1} 条 knowledge 动作没回报增量'
          '（既不是新节点也不是新边），不编一条提案出来',
    ));
  }

  return MaterialIntakePlan(
    batchId: batchId,
    sourceRef: sourceRef,
    proposals: proposals,
    skipped: skipped,
  );
}
