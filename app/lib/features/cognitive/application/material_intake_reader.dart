/// 材料入库页要的那一条推导（`docs/MINDNET_ROADMAP.md` §2-C ① 的界面入口）。
///
/// `mindnet.material/1` 信封 → 校验 → 标准清单 + 图补丁 + `run/1` 请求 →
/// **待确认提案**。与 `ingest_material` / `apply_material_intake` 两个工具走的是同一串
/// 确定性函数（`MaterialIngest.convert` → `MaterialIntakePlanner.plan`）：信封定了提案就
/// 定了，所以"页面上看到的"与"点头之后写下的"不可能不是同一份。
///
/// 纪律（和拍照整理同一条）：**确认前不写知识点**。"待确认清单"本身要落库 ——
/// 否则关掉页面就不知道刚才摆的是什么；落的是 `material_intake_batches` +
/// `material_intake_proposals`（`applied_at` NULL = 还没确认），写知识点只在
/// `MaterialIntakeRepository.apply` 里发生，本层不碰。
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
