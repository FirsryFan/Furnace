/// 一份 `run/1` 想建的东西 → **待确认提案**（roadmap §2-C ②，轮次九十一）。
///
/// 为什么是"提案"而不是直接建：执行层已经把 `knowledge` 动作算成了节点/边，但那些
/// 东西是模型从照片/贴进来的文本里读出来的，与人自己写下的知识点不是一回事。材料摄取
/// 那条路（轮次六十三～六十五）已经定过这条纪律 —— **先摆成待确认清单，人点头才建**
/// —— 这一层就让 `run/1` 走同一条路，而不是另开一个写者。
///
/// 于是这里**只写两张表**：`material_intake_batches` 与 `material_intake_proposals`
/// （幂等键是这一跑的 `run_id`）。`knowledge_points` / `knowledge_edges` 一行都不动 ——
/// 那是清单页上"确认"那一步的事。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/app_database_provider.dart';
import '../../../data/database/database.dart';
import '../../../data/repositories/anki_repository.dart';
import '../../../data/repositories/material_intake_repository.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../domain/services/ingest/run_executor.dart';
import '../../../domain/services/ingest/run_knowledge_plan.dart';
import '../../../domain/services/ingest/run_reading.dart';

/// 把一次演练里"要新建的东西"落成待确认提案，返回那一批。
///
/// [sourceRef] 是来源的人话（照片转写 / 贴在界面上的 `run/1`），只进清单的
/// "出处"那一行，不影响幂等键。
Future<MaterialIntakeBatch> recordRunKnowledge({
  required RunExecutionReport report,
  required AppDatabase db,
  required AnkiRepository anki,
  DateTime? now,
  String? sourceRef,
}) async {
  final repository = MaterialIntakeRepository(db, ankiRepository: anki);
  final inventory = await repository.externalNodeInventory();
  final plan = planRunKnowledge(
    report: report,
    existingNodeIds: <String>{for (final entry in inventory) entry.id},
    existingTitles: await repository.existingTitles(),
    // 库里已有的节点也有名字：连接提案的两端优先说名字（这一跑自己建的节点由计划层
    // 自己认），都没有才退回 id。
    nodeLabels: <String, String>{
      for (final entry in inventory) entry.id: entry.name,
    },
    sourceRef: sourceRef,
  );
  if (plan.isEmpty) {
    throw const RunKnowledgeException(
      '这份 `run/1` 里没有要新建的东西（动作全是 review / exposure / goal / time），'
      '所以一行提案都没落 —— 编一批空清单出来只会让人白点一次头。',
    );
  }
  return repository.record(
    plan,
    summaryText: '从一份 `run/1` 里读出来的待确认提案：这一跑跑了 '
        '${report.traces.length} 条动作，其中 ${plan.proposals.length} 样'
        '是要新建的东西（节点/线索边）—— 确认之后才真的建。',
    // 演练本身不落库，但"这一跑当时做了什么"（每条动作的原话 + 读数）跟着提案一起
    // 留在批次上（schema v23）：过几天回来点头时还看得见。
    detailText: runDetailTextOf(report),
    analyzedAt: now ?? DateTime.now(),
    sourceKind: 'run',
  );
}

/// 界面上"把要建的东西交给人确认"那一下要调的东西。
typedef RunIntakeRecorder = Future<MaterialIntakeBatch> Function(
  RunExecutionReport report,
);

/// 谁都别自己 new 一个：界面注入它，测试覆盖它。
final runIntakeRecorderProvider = Provider<RunIntakeRecorder>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final anki = ref.watch(ankiRepositoryProvider);
  return (report) => recordRunKnowledge(
        report: report,
        db: db,
        anki: anki,
        now: DateTime.now(),
      );
});
