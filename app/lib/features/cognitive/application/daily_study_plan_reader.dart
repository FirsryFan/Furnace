/// 今日学习计划的**读表与 provider 层**（application 层，不碰界面、不调模型）。
///
/// 排序 / 预算 / 中文文案全在 `domain/services/reasoning/daily_study_plan.dart`
/// （纯逻辑、不读库、不读时钟）。这里只做一件事：把散在四处的读数拼成
/// `DailyStudyPlan.build` 的输入，并把「今天到期的卡片张数」注入进去。
///
/// 口径与 `chain_insights_reader.dart` / `learning_advice_provider.dart` 同源：
/// 洞察按**当前**词表 overlay 重判（用户改词表后旧标记过期，重判比猜快照更
/// 可信）；词表读取失败退空 overlay，不阻塞整个计划。
///
/// 这一层一次读全库（链、步骤、题、候选投影）。题库是本地 SQLite、行数万级
/// 以内，一次读完可接受；页面上再按需缓存，不要逐知识点去问库。
library;

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/state/data_revision.dart';
import '../../../data/database/app_database_provider.dart';
import '../../../data/database/database.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../data/repositories/settings_repository.dart';
import '../../../domain/services/reasoning/capability_action_overlay.dart';
import '../../../domain/services/reasoning/capability_profile.dart';
import '../../../domain/services/reasoning/chain_insights.dart';
import '../../../domain/services/reasoning/daily_study_plan.dart';
import '../../../domain/services/reasoning/learning_advice.dart';
import '../../../domain/services/reasoning/practice_recommendation.dart';
import '../../questions/application/capability_vocabulary_store.dart';
import '../../questions/application/chain_insights_reader.dart';
import '../../questions/application/practice_recommendation_provider.dart';

/// 读一份今日学习计划：洞察 + 学习建议 + 配题推荐 + 到期卡片 → [DailyStudyPlan]。
///
/// [dueCardCount] 由调用方从间隔重复队列读出后注入：这一层不读时钟、不判断
/// 「什么叫到期」——到期口径只属于 `getDueCardStates`。null / 负数 / 0 都表示
/// 没有到期卡片（`DailyStudyPlan.build` 自己处理这个边界）。
///
/// 读表失败不在这里吞掉：语料读取本身不抛（解析宽容），只有数据库 IO 失败会
/// 冒泡，让上层按自己的错误态显示，而不是静默给一份空计划。
Future<DailyStudyPlan> readDailyStudyPlan({
  required AppDatabase database,
  required int dueCardCount,
  int dailyMinutes = DailyStudyPlan.defaultDailyMinutes,
  int maxSteps = DailyStudyPlan.defaultMaxSteps,
}) async {
  final insights = await readDailyStudyPlanInsights(database);
  final profile = await readDailyStudyPlanProfile(database);
  final advice = LearningAdvicePlan.build(
    insights: insights,
    profile: profile,
    corpusQuestionCount: await readDailyStudyPlanQuestionCount(database),
  );
  final recommendations = PracticeRecommendationPlan.build(
    insights: insights,
    advicePlan: advice,
    candidates: await readPracticeQuestionCandidates(database),
  );
  return DailyStudyPlan.build(
    insights: insights,
    advices: advice,
    recommendations: recommendations,
    dueCardCount: dueCardCount,
    dailyMinutes: dailyMinutes,
    maxSteps: maxSteps,
  );
}

/// 全库洞察读数（按当前词表 overlay 判定 known / custom / unknown）。
///
/// 词表读取失败退空 overlay 继续聚合：自定义词表坏掉只影响 known/custom 的
/// 判定，不该挡住整份学习计划（与 `chainInsightsProvider` 同一条退化口径）。
Future<ChainInsights> readDailyStudyPlanInsights(AppDatabase database) async {
  final corpus = await readChainInsightCorpus(database);
  CapabilityActionOverlay overlay;
  try {
    overlay =
        await CapabilityVocabularyStore(SettingsRepository(database)).load();
  } on Object {
    overlay = CapabilityActionOverlay.empty;
  }
  return ChainInsights.aggregate(
    chains: corpus.chains,
    catalog: overlay.catalog,
  );
}

/// 能力动作画像：全库解题步骤 → [CapabilityProfile.of]（"最该练"的顺序）。
///
/// 不按知识点过滤：今日计划的练习步骤来自配题推荐的命中，画像只用来判断
/// 「这个动作是不是风险动作」，不需要与推荐范围对齐。
Future<List<CapabilityReading>> readDailyStudyPlanProfile(
  AppDatabase database,
) async {
  final steps = await database.select(database.reasoningSteps).get();
  return CapabilityProfile.of(<CapabilityStepSample>[
    for (final step in steps)
      CapabilityStepSample(
        actionType: step.actionType,
        stuckRisk: step.stuckRisk,
      ),
  ]);
}

/// 题库总题数（一次 COUNT）：只用来判断「还有多少题没有解题链」。
Future<int> readDailyStudyPlanQuestionCount(AppDatabase database) async {
  final count = database.questions.id.count();
  final row = await (database.selectOnly(database.questions)
        ..addColumns([count]))
      .getSingle();
  return row.read(count) ?? 0;
}

/// 今天的计划。
///
/// 数据库一有写入就重算（与复习页 / 洞察页看同一个 `dataRevision`）：刚收的题、
/// 刚拆的链、刚答完的卡都会改变今天的步骤。到期卡数取「现在」这个瞬间，
/// 与 `todayPlanProvider` 的时钟口径一致。
final dailyStudyPlanProvider =
    FutureProvider.autoDispose<DailyStudyPlan>((ref) async {
  ref.watchDatabaseRevision();
  final database = ref.watch(appDatabaseProvider);
  final ankiRepository = ref.watch(ankiRepositoryProvider);
  final dueCards = await ankiRepository.getDueCardStates(
    DateTime.now().millisecondsSinceEpoch,
  );
  return readDailyStudyPlan(
    database: database,
    dueCardCount: dueCards.length,
  );
});
