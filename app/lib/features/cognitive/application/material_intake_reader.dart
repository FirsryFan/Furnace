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

/// 已经从"待确认清单"里读回来、并且已经点过头的某一批：批次读数 + 已确认的提案。
typedef MaterialIntakeApplied = ({
  MaterialIntakeBatch batch,
  List<MaterialIntakeProposal> proposals,
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
