/// 题库页顶部「自测统计」一行的数据版本绑定点：读的是全库作答记录条数 +
/// 答对条数（`QuestionAttemptRepository.stats`，纯派生，不落库）。
///
/// 有任何写入（自测落库、清除某题作答、设置页清空全部）都会让 `dataRevision`
/// 变化，这一行随之重算；页面不用自己 invalidate。加载中/读失败时没有值，
/// 页面按「整行不渲染」处理——不占位、不假装 0 条。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/state/data_revision.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../domain/services/questions/attempt_stats.dart';

/// 全库自测统计（题库页顶部一行）。
final questionAttemptStatsProvider =
    FutureProvider.autoDispose<QuestionAttemptStats>((ref) async {
  ref.watchDatabaseRevision();
  return ref.watch(questionAttemptRepositoryProvider).stats();
});
