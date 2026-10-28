/// 评测板块的 Riverpod 接线：数据层仓储 → 服务 → 页面。
///
/// 页面只依赖这组 provider，不直接 new 仓储；测试可以用 override 注入内存实现。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/app_database_provider.dart';
import '../../../data/repositories/cognitive_profile_repository.dart';
import '../domain/assessment_models.dart';
import 'assessment_session_service.dart';
import 'cognitive_params_provider.dart';

/// 评测数据层（实现见 `cognitive_profile_repository.dart`）。
final assessmentStoreProvider = Provider<AssessmentStore>((ref) {
  return CognitiveProfileRepository(ref.watch(appDatabaseProvider));
});

/// 一次会话的编排服务。
final assessmentSessionServiceProvider =
    Provider<AssessmentSessionService>((ref) {
  return AssessmentSessionService(store: ref.watch(assessmentStoreProvider));
});

/// 可选的测评任务（首次触发 seed 默认任务与默认映射）。
final assessmentTasksProvider =
    FutureProvider<List<AssessmentTaskConfig>>((ref) async {
  final store = ref.watch(assessmentStoreProvider);
  await store.ensureSeeded();
  return store.listTasks(enabledOnly: true);
});

/// 认知档案：能力、参数与最近会话历史。
final assessmentProfileProvider =
    FutureProvider<AssessmentProfileSnapshot>((ref) async {
  final store = ref.watch(assessmentStoreProvider);
  await store.ensureSeeded();
  final abilities = await store.readAbilities();
  final params = await store.readCognitiveParams();
  final sessions = await store.readSessions(limit: 20);
  return AssessmentProfileSnapshot(
    abilities: abilities,
    params: params,
    sessions: sessions,
  );
});

/// Thread 侧参数视图：本机认知参数估计 + 「不确定性过高回退默认」规则。
///
/// 档案还在加载或读取失败时退化为全默认先验：Thread 永远能拿到可用的值，
/// 只是 `usedDefault` 为真，调用方可以据此降权或标注「暂用默认值」。
final cognitiveParamsProvider = Provider<CognitiveParamsProvider>((ref) {
  final params = ref.watch(assessmentProfileProvider).valueOrNull?.params ??
      const <ParamEstimate>[];
  return CognitiveParamsProvider.fromEstimates(params);
});

/// Thread 权重建议（九项参数，顺序固定，便于确定性 UI 与测试）。
///
/// 只给建议值，不写库、不覆盖用户设置；要不要采纳由 Thread 侧决定。
final threadWeightSuggestionsProvider =
    Provider<List<ThreadWeightSuggestion>>((ref) {
  return threadWeightSuggestions(ref.watch(cognitiveParamsProvider));
});

/// 认知档案页的数据快照（只读）。
class AssessmentProfileSnapshot {
  const AssessmentProfileSnapshot({
    required this.abilities,
    required this.params,
    required this.sessions,
  });

  /// 全部 10 项能力（没测过的是先验，`nMeasurements == 0`）。
  final List<AbilityEstimate> abilities;

  /// 全部 9 个认知模型参数。
  final List<ParamEstimate> params;

  /// 最近会话（新→旧，最多 20 条）。
  final List<AssessmentSessionSummary> sessions;

  /// 测过的能力（至少一次有效测量）。
  List<AbilityEstimate> get measuredAbilities =>
      List<AbilityEstimate>.unmodifiable(
        abilities.where((ability) => ability.nMeasurements > 0),
      );

  /// 有历史会话或至少测过一次能力。
  bool get hasHistory => sessions.isNotEmpty || measuredAbilities.isNotEmpty;
}
