/// 「按能力动作找题」的读法：一个动作 key → 链上出现过它的题目。
///
/// 只有一处 IO（`readQuestionsForAction`，纯 Dart、AI 工具也能用），这里只加数据版本。
/// 与组卷的动作偏好、找相似题的动作对齐共用 `readChainActionTypes` 的口径：
/// **只认最新一条链**，不把"解过很多次"变成"命中很多次"。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/state/data_revision.dart';
import '../../../data/database/app_database_provider.dart';
import 'question_corpus_reader.dart';

/// 某个能力动作对应的题目清单（来源分级高的在前，平手按题目 id）。
final questionsForActionProvider = FutureProvider.autoDispose
    .family<List<CapabilityQuestionRow>, String>((ref, actionType) async {
  ref.watchDatabaseRevision();
  return readQuestionsForAction(ref.watch(appDatabaseProvider), actionType);
});
