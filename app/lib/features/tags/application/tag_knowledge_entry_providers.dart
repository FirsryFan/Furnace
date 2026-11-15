/// 标签知识入口的 Riverpod 接线（只读；契约 §4.3 的 `TagKnowledgeIndex`）。
///
/// 页面与将来的 AI 工具都从这里拿同一个索引实例，避免各自拼 SQL 造成
/// 「同一标签两个页面计数不同」。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/state/data_revision.dart';
import '../../../data/repositories/repository_providers.dart';
import 'tag_knowledge_index.dart';

/// 统一只读索引；依赖的五个仓储都来自 [repository_providers]。
final tagKnowledgeIndexProvider = Provider<TagKnowledgeIndex>((ref) {
  return TagKnowledgeIndex(
    tags: ref.watch(tagRepositoryProvider),
    questions: ref.watch(questionRepositoryProvider),
    anki: ref.watch(ankiRepositoryProvider),
    tasks: ref.watch(taskRepositoryProvider),
    reviewPlans: ref.watch(reviewPlanRepositoryProvider),
  );
});

/// 一次入口查询的范围。
///
/// 用 record 当 family 键：record 的结构相等就是「同一个查询」，不用手写
/// `==` / `hashCode`。
typedef TagKnowledgeQuery = ({String tagId, bool includeDescendants});

/// 一个标签（可选整棵子树）的题/卡/任务快照。
///
/// 任何写库都会让 [dataRevisionProvider] 变，从而自动重算——标签改名、删题、
/// 新建卡片后回到这一页不需要手动刷新。
final tagKnowledgeSnapshotProvider = FutureProvider.autoDispose
    .family<TagKnowledgeSnapshot, TagKnowledgeQuery>((ref, query) {
  ref.watchDatabaseRevision();
  return ref.watch(tagKnowledgeIndexProvider).snapshot(
        query.tagId,
        includeDescendants: query.includeDescendants,
      );
});
