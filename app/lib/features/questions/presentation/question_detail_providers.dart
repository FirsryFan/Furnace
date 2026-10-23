/// 题目详情页要读的三份东西：题目本身、已入库的思维链、以及卡点评估要用的状态读数。
///
/// 全部是**只读**的 `FutureProvider`：本页不写任何表，唯一的写动作是
/// 「AI 解题」按钮调用 `application/**` 的管道（由那条链路自己负责落库）。
///
/// 三个 provider 都 `watchDatabaseRevision()`：管道把链写完、或别处改了题，
/// `DbWriteInterceptor` → `DataChangeBus` 会让它们重跑，页面自己不必 invalidate。
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/state/data_revision.dart';
import '../../../data/database/app_database_provider.dart';
import '../../../data/database/database.dart';
import '../../../data/repositories/question_repository.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../domain/services/cognitive/cognitive_model.dart';
import '../../../domain/services/questions/attempt_history.dart';
import '../../../domain/services/reasoning/capability_action.dart';
import '../../../domain/services/reasoning/reasoning_prompt.dart';
import '../../../domain/services/scheduling/thread_balance_inputs.dart';
import '../../../domain/services/srs/dsr_card_state.dart';
import '../../../domain/services/srs/dsr_memory.dart';

/// 详情页顶部要的一份数据：题目 + 它的选项。
class QuestionDetail {
  const QuestionDetail({required this.question, required this.options});

  final Question question;
  final List<QuestionOption> options;

  /// 有没有被标成正确的选项。选择题的答案有两个载体（`questions.answer`
  /// 与 `question_options.isCorrect`），这里只回答"选项里有没有标"。
  bool get hasMarkedCorrect => options.any((option) => option.isCorrect);
}

/// 按 id 读题目；不存在时返回 `null`（不抛，因为"题被删了"是正常路径）。
final questionDetailProvider =
    FutureProvider.autoDispose.family<QuestionDetail?, String>((ref, id) async {
  ref.watchDatabaseRevision();
  final repository = ref.watch(questionRepositoryProvider);
  final question = await repository.byId(id);
  if (question == null) {
    return null;
  }
  return QuestionDetail(
    question: question,
    options: await repository.optionsOf(id),
  );
});

/// 一道题的自测作答历史（新→旧）。没有记录时是**空历史**而不是 null：
/// "还没自测过"是一份合法读数，界面按 isEmpty 决定要不要显示那一行。
final questionAttemptHistoryProvider = FutureProvider.autoDispose
    .family<QuestionAttemptHistory, String>((ref, questionId) async {
  ref.watchDatabaseRevision();
  final repository = ref.watch(questionAttemptRepositoryProvider);
  return QuestionAttemptHistory.fromEntries(
    await repository.historyFor(questionId),
  );
});

/// 详情页「上一题 / 下一题」的邻居：按题号找前后最近的一道。
///
/// `null` = 这道题自己没有题号（还没回填 / 被清空），页面就不摆翻页按钮；
/// `QuestionSerialNeighbors.isEmpty` = 它已经是题库里的最小或最大号。
final questionSerialNeighborsProvider = FutureProvider.autoDispose
    .family<QuestionSerialNeighbors?, String>((ref, questionId) async {
  ref.watchDatabaseRevision();
  final repository = ref.watch(questionRepositoryProvider);
  final question = await repository.byId(questionId);
  final serialNo = question?.serialNo;
  if (serialNo == null) {
    return null;
  }
  return repository.serialNeighbors(serialNo);
});

/// 库里最新的一条链，已经还原成解析器的产物形状。
class StoredChain {
  const StoredChain({
    required this.chainId,
    required this.chain,
    required this.createdAt,
  });

  final String chainId;
  final ParsedChain chain;
  final DateTime createdAt;
}

/// 读库里最新的一条链；一条都没有时返回 `null`。
final questionStoredChainProvider =
    FutureProvider.autoDispose.family<StoredChain?, String>((ref, id) async {
  ref.watchDatabaseRevision();
  final repository = ref.watch(questionRepositoryProvider);
  final chains = await repository.chainsOf(id);
  if (chains.isEmpty) {
    return null;
  }
  // 同题可以有多条链（§3：链是派生数据，互不覆盖）。取最新一条；`createdAt`
  // 打平时按 id 兜底——同一次运行里连写两条是同一毫秒，不兜底的话「最新一条」
  // 在同一毫秒内不确定，页面会在两次刷新之间跳来跳去。
  final ordered = List<ReasoningChain>.of(chains)
    ..sort((a, b) {
      final byTime = b.createdAt.compareTo(a.createdAt);
      return byTime != 0 ? byTime : b.id.compareTo(a.id);
    });
  final latest = ordered.first;
  final steps = await repository.stepsOf(latest.id);
  final chain = parsedChainFromRows(latest, steps);
  if (chain == null) {
    return null;
  }
  return StoredChain(
    chainId: latest.id,
    chain: chain,
    createdAt: DateTime.fromMillisecondsSinceEpoch(latest.createdAt),
  );
});

/// 把 `reasoning_steps` 的行还原成 [ParsedChain]；没有步骤时返回 `null`。
///
/// 有一处**必然的失真**：数据库的 `idx` 从 0 起，而 `chainJsonContract` 里的
/// `index` 从 1 起，所以这里统一 `index = idx + 1`。其余字段一一对应，`action`
/// 走词表反查——查不到就留 `null`（`knownAction == false`），历史数据里存在
/// 已经从词表移除的 action key，那不是错误，是信号。
ParsedChain? parsedChainFromRows(
  ReasoningChain chain,
  List<ReasoningStep> steps,
) {
  if (steps.isEmpty) {
    // 空链入库是允许的（`saveChain` 的注释），但对界面来说它等于"还没有链"：
    // 硬渲染一个没有任何步骤的卡片，比说"还没有"更难看懂。
    return null;
  }
  return ParsedChain(
    summary: chain.summary,
    steps: <ParsedStep>[
      for (final step in steps)
        ParsedStep(
          index: step.idx + 1,
          goal: step.goal,
          actionType: step.actionType,
          action: CapabilityAction.byKey(step.actionType),
          justification: step.justification,
          checkMethod: step.checkMethod,
          // 没记风险时用中性值 0.5：「不知道」不等于「不会卡」。
          stuckRisk: step.stuckRisk ?? defaultStuckRisk,
          knowledgeHints: _decodeHints(step.knowledgeHints),
        ),
    ],
  );
}

/// `knowledge_hints` 存的是 JSON 数组文本。解析不了就当作"没有提示"——
/// 一行脏数据不该让整道题的链读不出来。
List<String> _decodeHints(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) {
    return const <String>[];
  }
  try {
    final decoded = jsonDecode(trimmed);
    if (decoded is List) {
      return <String>[
        for (final item in decoded)
          if (item is String && item.trim().isNotEmpty) item,
      ];
    }
  } on FormatException {
    return const <String>[];
  }
  return const <String>[];
}

/// 知识点 id → 记忆状态读数。键就是 `kp-…` 的 id，与模型的 `knowledgeHints`
/// 精确匹配（评估器只认精确 key）。
///
/// 数据源与认知页（`cognitive_model_page.dart`）保持一致：一行 `card_states`
/// 就是一份状态，`knowledge_point_id` 缺失时回落到卡模板的绑定。
/// **一个知识点有多张卡时取 id 最小的一行**——不发明聚合函数，也不假装
/// 多张卡是同一份读数。
final questionKnowledgeStatesProvider =
    FutureProvider.autoDispose<Map<String, DsrState>>((ref) async {
  ref.watchDatabaseRevision();
  final database = ref.watch(appDatabaseProvider);
  final nowHours = modelHoursOf(DateTime.now());
  final rows = await database.select(database.cardStates).get();
  final templates = await database.select(database.cardTemplates).get();
  final knowledgePointOfTemplate = <String, String>{
    for (final template in templates) template.id: template.knowledgePointId,
  };

  final ordered = List<CardState>.of(rows)
    ..sort((a, b) => a.id.compareTo(b.id));
  final readings = <String, DsrState>{};
  for (final row in ordered) {
    final knowledgePointId =
        row.knowledgePointId ?? knowledgePointOfTemplate[row.cardTemplateId];
    if (knowledgePointId == null || knowledgePointId.trim().isEmpty) {
      continue;
    }
    readings.putIfAbsent(
      knowledgePointId,
      () => DsrCardState.read(row, nowHours: nowHours),
    );
  }
  return readings;
});

/// 这道题挂在哪些知识点上（靠"题目与知识点共享同一个标签"推出来）。
///
/// 用与 ThreadFlow 段落 B 同一个解析器 [TaskKnowledgePointResolver]，只是把
/// `sourceObjectType` 换成 `question`：同一份推导规则，不在题库页再写一遍。
final questionKnowledgePointIdsProvider = FutureProvider.autoDispose
    .family<List<String>, String>((ref, questionId) async {
  ref.watchDatabaseRevision();
  final database = ref.watch(appDatabaseProvider);
  final rows = await database.select(database.objectTags).get();
  final links = <ObjectTagLink>[
    for (final row in rows)
      ObjectTagLink(
        tagId: row.tagId,
        objectType: row.objectType,
        objectId: row.objectId,
      ),
  ];
  final bySource = TaskKnowledgePointResolver.resolveFromTagLinks(
    links,
    sourceObjectType: kQuestionObjectType,
  );
  return bySource[questionId] ?? const <String>[];
});
