/// 段落 B 在**应用层**的输入读取：数据库里的挂载关系 + 认知层的读数。
///
/// 领域分工：
///
/// * 纯数据（`ThreadBalanceInputs` / `ObjectTagLink` / 任务→知识点解析）在
///   `domain/services/scheduling/thread_balance_inputs.dart`；
/// * 认知读数 → 排序读数的投影在
///   `domain/services/scheduling/cognitive_readings.dart`；
/// * 这个文件只做"读表 + 拼装"，是排序前唯一的 IO 点。
///
/// 一条纪律：诊断走**认知页自己的 provider**（`cognitiveLibraryDiagnosisProvider`），
/// 不在这里重算——页面上说"危险"的知识点，Thread 里必须就是优先的，两边共用
/// 同一次诊断（D2：一个数字一个来源）。这条跨 feature 的 import 方向是
/// `thread/application → cognitive/presentation`，是当前观察层还在页面里的
/// 历史遗留；将来把观察输入搬到 `cognitive/application/` 时，这个 import 跟着
/// 改一行即可（`docs/THREADFLOW_TWO_SEGMENT.md` 有记录）。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/state/data_revision.dart';
import '../../../data/database/app_database_provider.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../domain/services/cognitive/fast_diagnosis.dart';
import '../../../domain/services/scheduling/cognitive_readings.dart';
import '../../../domain/services/scheduling/domain_balance.dart';
import '../../../domain/services/scheduling/thread_balance_inputs.dart';
import '../../cognitive/presentation/cognitive_model_page.dart'
    show cognitiveLibraryDiagnosisProvider;

/// 这次排序的外部输入。
///
/// 读的是 `Tags` / `ObjectTags`（挂载关系）、`cognitiveLibraryDiagnosisProvider`
/// （危险区/发展区）与测评先验。任何一层缺数据都只是让输入变稀，不抛异常：
/// 认知页的 provider 自己会把"没跑"表示成 [LibraryDiagnosis.notRun]。
final threadBalanceInputsProvider =
    FutureProvider.autoDispose<ThreadBalanceInputs>((ref) async {
  ref.watchDatabaseRevision();
  final db = ref.watch(appDatabaseProvider);
  final tagRows = await db.select(db.tags).get();
  final linkRows = await db.select(db.objectTags).get();
  // 理由行念的是知识点**名字**，而挂载关系里只有 id（见下面键空间翻译）。
  final knowledgePointRows = await db.select(db.knowledgePoints).get();

  final objectLinks = <ObjectTagLink>[
    for (final row in linkRows)
      ObjectTagLink(
        tagId: row.tagId,
        objectType: row.objectType,
        objectId: row.objectId,
      ),
  ];
  final taskKnowledgePoints =
      TaskKnowledgePointResolver.resolveFromTagLinks(objectLinks);
  final knowledgePointIds = <String>{
    for (final values in taskKnowledgePoints.values) ...values,
  };

  final diagnosis = await ref.watch(cognitiveLibraryDiagnosisProvider.future);
  final priors =
      await ref.watch(assessmentRepositoryProvider).priorEstimatesFor(
            knowledgePointIds,
          );

  // 键空间翻译（实测，Q6）：`Tags.id` 是 `tag-…`，`KnowledgePoints.id` 是
  // `kp-…`（`anki_repository.dart:25` 的 `_newId('kp')`），**两者不是同一个
  // 命名空间**。而 `LibraryDiagnosis.byKnowledgePoint` 的键是**标签 id**——
  // 快层的图节点就是标签行（`cognitive_graph.dart:105` 的
  // `CognitiveTag.fromTag` 直接取 `row.id`），诊断也是按 `tag.id` 去查
  // `rowsByKnowledgePoint` 的（`library_diagnosis.dart:147-157`）。
  // 排序这边要按**知识点 id** 对齐（任务挂的是知识点），所以必须先翻译：
  // 一个知识点可以有多个标签，取 id 最小的那个有诊断结论的标签，保证确定性。
  final tagIdsByKnowledgePoint = <String, List<String>>{};
  for (final row in linkRows) {
    if (row.objectType != kKnowledgePointObjectType) continue;
    (tagIdsByKnowledgePoint[row.objectId] ??= <String>[]).add(row.tagId);
  }
  final verdictsByKnowledgePoint = <String, BottleneckType>{};
  if (diagnosis.fastLayerRan) {
    final knowledgePointIds = tagIdsByKnowledgePoint.keys.toList()..sort();
    for (final knowledgePointId in knowledgePointIds) {
      final tagIds = tagIdsByKnowledgePoint[knowledgePointId]!..sort();
      for (final tagId in tagIds) {
        final verdict = diagnosis.byKnowledgePoint[tagId];
        if (verdict != null) {
          verdictsByKnowledgePoint[knowledgePointId] = verdict;
          break;
        }
      }
    }
  }

  return ThreadBalanceInputs(
    taskKnowledgePoints: taskKnowledgePoints,
    readings: CognitiveReadingsAdapter.readingsFor(
      knowledgePointIds: knowledgePointIds,
      // fastLayerRan == false 是"这轮没跑"，不是"库很健康"：传 null 才能让
      // 段落 B 知道"诊断缺席"，而不是"诊断过、没问题"。
      diagnosisByKnowledgePoint:
          diagnosis.fastLayerRan ? verdictsByKnowledgePoint : null,
      priors: priors,
    ),
    tags: <DomainTag>[
      for (final row in tagRows)
        DomainTag(
          id: row.id,
          parentId: row.parentId,
          path: row.path,
          name: row.name,
        ),
    ],
    taskTagLinks: <TaskTagLink>[
      for (final row in linkRows)
        if (row.objectType == kTaskObjectType)
          TaskTagLink(taskId: row.objectId, tagId: row.tagId),
    ],
    // 只给理由行说话用；排序仍然按 id。
    knowledgePointNames: <String, String>{
      for (final row in knowledgePointRows)
        if (row.title.trim().isNotEmpty) row.id: row.title.trim(),
    },
  );
});
