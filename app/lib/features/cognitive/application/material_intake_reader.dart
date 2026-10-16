/// 材料入库页要的那一条推导（`docs/MINDNET_ROADMAP.md` §2-C ① 的界面入口）。
///
/// `mindnet.material/1` 信封 → 校验 → 标准清单 + 图补丁 + `run/1` 请求 →
/// **待确认提案**。与 `ingest_material` / `apply_material_intake` 两个工具走的是同一串
/// 确定性函数（`MaterialIngest.convert` → `MaterialIntakePlanner.plan`）：信封定了提案就
/// 定了，所以"页面上看到的"与"点头之后写下的"不可能不是同一份。
///
/// 纪律（和拍照整理同一条）：**确认前不写知识点**。"待确认清单"本身要落库 ——
/// 否则关掉页面就不知道刚才摆的是什么；落的是 `material_intake_batches` +
/// `material_intake_proposals`（`applied_at` NULL = 还没确认），写知识点/线索边只在
/// `MaterialIntakeRepository.apply` 里发生，本层不碰。
///
/// 入口有三个：**贴信封**（[readMaterialPlan] → [recordMaterialPlan]）、
/// **从清单恢复**（[readPendingBatches] → [readPendingBatch]）与
/// **看已经确认完的**（[readAppliedBatches] → [readAppliedBatch]）—— 后两个都不重算，
/// 只是把当初登记的那份读回来（一个读还没点头的，一个读已经写下去的）。
library;

import 'dart:convert';

import '../../../data/repositories/material_intake_repository.dart';
import '../../../domain/services/cognitive/cognitive_model.dart';
import '../../../domain/services/ingest/material_ingest.dart';
import '../../../domain/services/ingest/material_intake_plan.dart';

/// 一次"看提案"的全部产物：信封、转化、提案。
typedef MaterialIntakeDraft = ({
  MaterialEnvelope envelope,
  MaterialConversion conversion,
  MaterialIntakePlan plan,
});

/// 对象或 JSON 文本 → 信封。给的是别的东西就用人话说清楚哪里不对（页面要显示）。
MaterialEnvelope decodeMaterialEnvelope(Object? raw) {
  Object? decoded = raw;
  if (raw is String) {
    final text = raw.trim();
    if (text.isEmpty) {
      throw const FormatException('信封是空的：把 AI 产出的 mindnet.material/1 贴进来');
    }
    try {
      decoded = jsonDecode(text);
    } on FormatException catch (error) {
      throw FormatException('信封不是合法的 JSON 文本（${error.message}）');
    }
  }
  if (decoded is Map) {
    return MaterialEnvelope.fromJson(<String, Object?>{
      for (final entry in decoded.entries) '${entry.key}': entry.value,
    });
  }
  throw const FormatException('信封必须是对象或 JSON 文本');
}

/// 看提案：先按材料推导，再拿现有知识点标题标"同名已存在"（`record` 用的也是这一份）。
///
/// 抛 `FormatException`（信封本身不是对象/JSON）、`MaterialIngestException`
/// （信封不合规：整份拒绝，一行不写）。
Future<MaterialIntakeDraft> readMaterialPlan({
  required MaterialIntakeRepository repository,
  required Object? raw,
  required DateTime moment,
  bool includeTopicHubs = false,
}) async {
  final envelope = decodeMaterialEnvelope(raw);
  final conversion = MaterialIngest.convert(
    envelope,
    nowHours: modelHoursOf(moment),
  );
  final plan = MaterialIntakePlanner.plan(
    conversion,
    envelope: envelope,
    existingTitles: await repository.existingTitles(),
    includeTopicHubs: includeTopicHubs,
  );
  return (envelope: envelope, conversion: conversion, plan: plan);
}

/// 把这份提案登记成"待确认"（幂等：同一批重算不会长出第二份，已确认的一个字不动）。
///
/// 出处与 `captured_at` 从信封里取：材料元数据只信材料自己写的那份。
Future<MaterialIntakeBatch> recordMaterialPlan({
  required MaterialIntakeRepository repository,
  required MaterialIntakeDraft draft,
  required DateTime moment,
}) async {
  final source = draft.envelope.source;
  return repository.record(
    draft.plan,
    summaryText: draft.conversion.summary.text,
    analyzedAt: moment,
    sourceKind: source?.kind,
    capturedAtMs:
        DateTime.tryParse(source?.capturedAt ?? '')?.millisecondsSinceEpoch,
  );
}

/// 从"待确认清单"恢复出来的一批：批次读数 + 还没确认的提案。
typedef MaterialIntakePending = ({
  MaterialIntakeBatch batch,
  List<MaterialIntakeProposal> proposals,
});

/// 关掉页面之后的入口：把库里还没确认的那批提案读回来。
///
/// 与"贴信封看提案"共用同一条纪律的后半段 —— 提案在**看提案**那一刻就已经落库了
/// （`applied_at` NULL），这里不做任何重算，只是把它按原顺序读回来。所以恢复出来的提案
/// 与当初在屏幕上看到的那份逐字相同；`record` 的幂等也意味着拿同一份信封再贴一次，
/// 得到的还是同一批。
Future<MaterialIntakePending?> readPendingBatch({
  required MaterialIntakeRepository repository,
  required String batchId,
}) async {
  final batch = await repository.batch(batchId);
  if (batch == null) {
    return null;
  }
  return (batch: batch, proposals: await repository.pendingProposals(batchId));
}

/// 还有哪几批没确认完（新的在前）。空列表 = 没有欠账。
Future<List<MaterialIntakeBatch>> readPendingBatches({
  required MaterialIntakeRepository repository,
}) async {
  final all = await repository.batches();
  return <MaterialIntakeBatch>[
    for (final batch in all)
      if (batch.unappliedCount > 0) batch,
  ];
}

/// 已经被点名过、并且已经确认完的某一批：批次读数 + 已确认的提案
/// （每条带"这次新建的 / 本来就有的"）。
typedef MaterialIntakeApplied = ({
  MaterialIntakeBatch batch,
  List<MaterialAppliedProposal> proposals,
});

/// 已经确认完的批次（新的在前）：这批点名过、没有欠账。
///
/// 判据是**库里现在的数**，不是"当初登记过多少条"：还留着一条落不了的连接
/// （`unapplied_count > 0`）就算欠账，只能待在待确认清单里 —— 否则同一批会同时
/// 出现在两张单子上，用户以为它做完了，其实还有一条没落地。
Future<List<MaterialIntakeBatch>> readAppliedBatches({
  required MaterialIntakeRepository repository,
}) async {
  final all = await repository.batches();
  return <MaterialIntakeBatch>[
    for (final batch in all)
      if (!batch.isEmpty && batch.unappliedCount == 0) batch,
  ];
}

/// 这批当初确认了什么（读不到返回 null）。
///
/// 读的是**已经写下去**的那些提案（`applied_at` 非空）：题目是"我上次到底建了什么"，
/// 不是"我上次打算建什么"——后者要在待确认清单里看。
Future<MaterialIntakeApplied?> readAppliedBatch({
  required MaterialIntakeRepository repository,
  required String batchId,
}) async {
  final batch = await repository.batch(batchId);
  if (batch == null) {
    return null;
  }
  return (
    batch: batch,
    proposals: await repository.appliedProposals(batchId),
  );
}

/// 一条还没落地的连接"为什么落不了"：提案 id → 人话（能落的没有条目）。
typedef MaterialIntakeMissingEndpoints = Map<String, String>;

/// 这条连接会不会落不了 —— 与确认时的成绩单**逐条对齐**的三件事：
///
/// ① 提案自己没带端点（`from`/`to` 为空）→ `noEndpointsNote`；
/// ② 边已经在库里（`knownEdgeIds` 里有它）→ 不算落不了，确认时会说"已存在"；
/// ③ 两端都得在影子图里 —— 库里已有的 `external_id`，加上**这一批的点提案**将要建出来
///    的 id（同一次 `apply` 里先点后边，所以本批的点算数）。
///
/// 两个刻意的选择：
/// ① **不在库里存"落不了"这件事**。它是"现在这一刻库里的样子"的函数：缺的那一端后来
/// 补进图里（本批的点被确认、或用户手建一个），这条连接就该能落 —— 存下来就会变成一句
/// 过期的话（对比 `already_existed`：那句只在点头那一刻成立，所以它才必须落库）。
/// ② 点提案里"同名已存在"（`exists`）的不算数：`_createPoint` 对它**不写行**，
/// 于是它的 `external_id` 也不会出现在库里，连着它的边照样落不了。
MaterialIntakeMissingEndpoints pendingMissingEndpointsOf({
  required List<MaterialIntakeProposal> proposals,
  required Set<String> knownNodeIds,
  required Set<String> knownEdgeIds,
}) {
  // 这一批的点提案会把哪些 id 送进图里（`_createPoint` 的判据照抄一遍）。
  final shadow = <String>{
    ...knownNodeIds,
    for (final proposal in proposals)
      if (proposal.kind == MaterialIntakeKind.knowledgePoint &&
          proposal.nodeId != null &&
          !proposal.exists &&
          !knownNodeIds.contains(proposal.nodeId))
        proposal.nodeId!,
  };
  return <String, String>{
    for (final proposal in proposals)
      if (proposal.kind == MaterialIntakeKind.connection)
        if (proposal.from == null || proposal.to == null)
          proposal.id: MaterialIntakeRepository.noEndpointsNote
        else if (!knownEdgeIds.contains(edgeIdOf(proposal.id)) &&
            (!shadow.contains(proposal.from) || !shadow.contains(proposal.to)))
          proposal.id: MaterialIntakeRepository.missingEndpointNote(
            from: proposal.from!,
            to: proposal.to!,
            fromKnown: shadow.contains(proposal.from),
            toKnown: shadow.contains(proposal.to),
          ),
  };
}

/// 提案 id → 落库时的边 id（`record` 存的提案 id 带 `edge:` 前缀，边表不带）。
String edgeIdOf(String proposalId) => proposalId.startsWith('edge:')
    ? proposalId.substring('edge:'.length)
    : proposalId;

/// 从库里读这一批还没落地的提案，再算一遍上面那份"缺哪一端"。
Future<MaterialIntakeMissingEndpoints> readPendingMissingEndpoints({
  required MaterialIntakeRepository repository,
  required String batchId,
}) async {
  final pending = await repository.pendingProposals(batchId);
  if (pending.isEmpty) {
    return const <String, String>{};
  }
  return pendingMissingEndpointsOf(
    proposals: pending,
    knownNodeIds: await repository.knownExternalNodeIds(),
    knownEdgeIds: await repository.knownEdgeIds(),
  );
}
