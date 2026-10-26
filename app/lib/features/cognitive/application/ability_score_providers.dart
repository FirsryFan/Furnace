/// 能力画像页要读的两份东西：每项能力最近一次分数、每项能力测过几次。
///
/// 两份都 `watchDatabaseRevision()`：测评页写完 `ability_scores`（schema v38）之后，
/// `DbWriteInterceptor` → `DataChangeBus` 会让画像页重读，页面自己不必 invalidate。
/// 只读：本文件不写任何表。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/state/data_revision.dart';
import '../../../data/repositories/ability_score_repository.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../domain/services/cognitive/ability_assessment.dart';

/// 每项能力**最近一次**分数；没测过的能力不出现在 map 里（不是 0 分，也不是 null 分）。
final abilityLatestScoresProvider =
    FutureProvider.autoDispose<Map<AbilityKey, AbilityScoreEntry>>((ref) async {
  ref.watchDatabaseRevision();
  final repository = ref.watch(abilityScoreRepositoryProvider);
  return repository.latestByAbility();
});

/// 每项能力一共测过几次；四项都有键（没测过是 0），页面直接 `counts[key] ?? 0`。
final abilityScoreCountsProvider =
    FutureProvider.autoDispose<Map<AbilityKey, int>>((ref) async {
  ref.watchDatabaseRevision();
  final repository = ref.watch(abilityScoreRepositoryProvider);
  final counts = await Future.wait<int>([
    for (final key in AbilityKey.values) repository.countFor(key),
  ]);
  return <AbilityKey, int>{
    for (var index = 0; index < AbilityKey.values.length; index++)
      AbilityKey.values[index]: counts[index],
  };
});
