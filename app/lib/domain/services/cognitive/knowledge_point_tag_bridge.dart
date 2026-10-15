/// `kp-…` 与 `tag-…` 之间的翻译（Q8）。
///
/// **为什么需要这个文件。** 本项目的知识点与标签是两套独立 id：
/// `KnowledgePoints.id` 由 `_newId('kp')` 生成
/// （`app/lib/data/repositories/anki_repository.dart`），`Tags.id` 由
/// `_newId('tag')` 生成（`app/lib/data/repositories/tag_repository.dart`）。
/// 而认知快层的图节点**是标签**：`CognitiveTag.fromTag(Tag row)` 直接取
/// `row.id`（`cognitive_graph.dart`），`LibraryDiagnosisRunner` 与
/// `ProblemEvaluator` 都按 `tag.id` 去查调用方给的 `rowsByKnowledgePoint`，
/// 并把不在图里的 id 直接丢掉。
///
/// 调用方手里有的是**知识点**（任务挂载、卡片状态、题目覆盖点），所以两边必须
/// 翻译一次。以前没有这一层，键混用导致整套观察层在真实数据上静默失效：
/// 界面永远显示"这轮没诊断"，AI 工具的 `judgedKnowledgePointIds` 永远为空
/// （证据见 `docs/THREADFLOW_TWO_SEGMENT.md` §8.3）。
///
/// 这个文件只做键的翻译，不认识 drift、不认识 Flutter，也不查表：挂载关系由
/// 调用方以 [ObjectTagLink] 传入（同一份 `ObjectTags` 投影）。
library;

import '../scheduling/thread_balance_inputs.dart';
import 'fast_diagnosis.dart';

// `ObjectTagLink` 是"一行 object_tags 投影"，目前住在排序层的输入文件里（Q6 与
// 排序层共用同一种投影）。这里再导出一次，好让调用方只 import 桥，不必为了
// 造一个 link 去 import scheduling。将来把它提到共享的 tags 域文件时，只改这
// 一行。
export '../scheduling/thread_balance_inputs.dart'
    show ObjectTagLink, kKnowledgePointObjectType;

/// 知识点 ↔ 标签的键翻译。
abstract final class KnowledgePointTagBridge {
  /// 知识点 id → 它**直挂**的标签 id（去重、每个点内排序、按知识点 id 排序）。
  ///
  /// 只收 `objectType == 'knowledge_point'` 的链接：祖先标签（`数学`、`文化课`）
  /// 不出现在 `ObjectTags` 里，因此不会被展开——"一个知识点挂了哪些标签"是
  /// 事实，祖先关系是图自己算的。
  static Map<String, List<String>> tagIdsByKnowledgePoint(
    Iterable<ObjectTagLink> links,
  ) {
    final tagIdsByPoint = <String, Set<String>>{};
    for (final link in links) {
      if (link.objectType != kKnowledgePointObjectType) {
        continue;
      }
      final tagId = link.tagId.trim();
      final pointId = link.objectId.trim();
      if (tagId.isEmpty || pointId.isEmpty) {
        continue;
      }
      (tagIdsByPoint[pointId] ??= <String>{}).add(tagId);
    }

    final pointIds = tagIdsByPoint.keys.toList()..sort();
    return <String, List<String>>{
      for (final pointId in pointIds)
        pointId: List<String>.unmodifiable(tagIdsByPoint[pointId]!.toList()..sort()),
    };
  }

  /// 一个知识点直挂的标签 id；没挂载就是空表（不是 `null`）。
  static List<String> tagIdsOf(
    String knowledgePointId,
    Map<String, List<String>> tagIdsByKnowledgePoint,
  ) {
    final trimmed = knowledgePointId.trim();
    if (trimmed.isEmpty) {
      return const <String>[];
    }
    return tagIdsByKnowledgePoint[trimmed] ?? const <String>[];
  }

  /// 一组知识点直挂的**全部**标签 id（去重、排序）。给 `starts`/`targets`
  /// 这类"一组点 → 一组图节点"的翻译用。
  static List<String> tagIdsOfAll(
    Iterable<String> knowledgePointIds,
    Map<String, List<String>> tagIdsByKnowledgePoint,
  ) {
    final collected = <String>{};
    for (final pointId in knowledgePointIds) {
      collected.addAll(tagIdsOf(pointId, tagIdsByKnowledgePoint));
    }
    return List<String>.unmodifiable(collected.toList()..sort());
  }

  /// 把"知识点键的表"展开成"标签键的表"（`rowsByKnowledgePoint` → 图节点键）。
  ///
  /// 同一知识点的每个直挂标签都拿到同一个值（记忆挂在知识点上，不是挂在标签上）。
  /// 泛型是有意的：调用方装的是 drift 的 `CardState`，这一层不需要认识它。
  ///
  /// 一个标签被多个知识点挂载时，按知识点 id 排序取**第一个**（确定性），
  /// 这种"两个知识点共用一个标签"的挂法本身是数据问题，翻译层不改写事实，
  /// 只是给出可复现的选择。
  static Map<String, T> expandKeys<T>({
    required Map<String, T> byKnowledgePoint,
    required Map<String, List<String>> tagIdsByKnowledgePoint,
  }) {
    final pointIds = byKnowledgePoint.keys.toList()..sort();
    final expanded = <String, T>{};
    for (final pointId in pointIds) {
      for (final tagId in tagIdsOf(pointId, tagIdsByKnowledgePoint)) {
        expanded.putIfAbsent(tagId, () => byKnowledgePoint[pointId] as T);
      }
    }
    return Map<String, T>.unmodifiable(expanded);
  }

  /// 把"标签键的结论"翻成"知识点键的结论"。
  ///
  /// 一个知识点挂多个标签时，取 id 最小且**有结论**的那个：标签的顺序是确定的，
  /// "有结论"优先于"id 小"，所以不会因为某个标签没被诊断就把整点当健康。
  /// 没有任何标签有结论的知识点**不进结果**——"没诊断过"与"健康"必须可区分。
  static Map<String, BottleneckType> verdictsByKnowledgePoint({
    required Map<String, BottleneckType> byTagId,
    required Map<String, List<String>> tagIdsByKnowledgePoint,
  }) {
    final pointIds = tagIdsByKnowledgePoint.keys.toList()..sort();
    final verdicts = <String, BottleneckType>{};
    for (final pointId in pointIds) {
      for (final tagId in tagIdsOf(pointId, tagIdsByKnowledgePoint)) {
        final verdict = byTagId[tagId];
        if (verdict != null) {
          verdicts[pointId] = verdict;
          break;
        }
      }
    }
    return Map<String, BottleneckType>.unmodifiable(verdicts);
  }
}
