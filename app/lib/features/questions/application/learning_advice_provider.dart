/// 学习建议的接线：洞察读数 + 能力动作画像 + 题库题数 → `LearningAdvicePlan`。
///
/// 三个输入都是现算的（`chainInsightsProvider` / `capabilityProfileProvider` /
/// `questionCorpusCountProvider`）；建议层本身仍是纯逻辑、不读库、不读时钟，
/// 所以这里只做拼装与失败退化，口径全在
/// `domain/services/reasoning/learning_advice.dart`。
library;

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/state/data_revision.dart';
import '../../../data/database/app_database_provider.dart';
import '../../../domain/services/reasoning/learning_advice.dart';
import 'capability_profile_provider.dart';
import 'chain_insights_reader.dart';

/// 题库总题数（一次 COUNT；跟数据库修订号走，刚收的题立即算进来）。
///
/// 只用来回答"还有多少题没有解题链"；这里不做业务判断，空库返回 0。
final questionCorpusCountProvider = FutureProvider<int>((ref) async {
  ref.watchDatabaseRevision();
  final db = ref.watch(appDatabaseProvider);
  final count = db.questions.id.count();
  final row =
      await (db.selectOnly(db.questions)..addColumns([count])).getSingle();
  return row.read(count) ?? 0;
});

/// 全库学习建议：默认"3 步高风险"阈值、最多 5 条。
///
/// 已知动作的判定由 `chainInsightsProvider` 按**当前**词表 overlay 重做，
/// 这里不再重复读词表，避免两处口径漂移。
final learningAdviceProvider = FutureProvider<LearningAdvicePlan>((ref) async {
  final insights = await ref.watch(chainInsightsProvider.future);
  final profile = await ref.watch(capabilityProfileProvider.future);
  final corpus = await ref.watch(questionCorpusCountProvider.future);
  return LearningAdvicePlan.build(
    insights: insights,
    profile: profile,
    corpusQuestionCount: corpus,
  );
});
