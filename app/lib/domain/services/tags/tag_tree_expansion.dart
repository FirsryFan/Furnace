/// 标签树展开/折叠状态的持久化编解码（纯 Dart：不依赖 Flutter / drift）。
///
/// 契约（2026-11-17 用户要求）：
///  * **默认完全折叠**：没有任何保存值时返回空集合，也就是没有任何节点展开；
///  * 存的是「**展开**的标签 id」而不是「折叠的 id」：新加进树的节点不会出现在
///    历史保存值里，因此默认也是折叠的。若存折叠集合，新节点会因为不在集合里
///    而意外展开，与"默认全折叠"冲突；
///  * NULL / 空白 / 坏 JSON / 非字符串元素一律宽容降级成空集合，绝不抛错——
///    展开状态是体验偏好，不能因为一个坏字符串把标签页打不开；
///  * 写侧按 id 排序、去重、丢掉空白 id，同样的集合永远序列化成同一个字符串，
///    方便测试逐字节钉住，也避免每次写库内容抖动。
library;

import 'dart:convert';

/// 从 `local_settings.tag_tree_expanded_ids` 的原文还原展开集合。
///
/// NULL / 空白读作空集合（= 全折叠，出厂默认）；坏 JSON、非数组、非字符串元素
/// 都被忽略而不是抛错（见库文件头契约）。
Set<String> tagTreeExpandedIdsFromStorage(String? raw) {
  if (raw == null) {
    return const <String>{};
  }
  final trimmed = raw.trim();
  if (trimmed.isEmpty) {
    return const <String>{};
  }
  Object? decoded;
  try {
    decoded = jsonDecode(trimmed);
  } on FormatException {
    return const <String>{};
  }
  if (decoded is! List) {
    return const <String>{};
  }
  final ids = <String>{};
  for (final item in decoded) {
    if (item is! String) {
      continue;
    }
    final id = item.trim();
    if (id.isNotEmpty) {
      ids.add(id);
    }
  }
  return Set<String>.unmodifiable(ids);
}

/// 展开集合 → 持久化字符串（去重、排序后的 JSON 字符串数组）。
///
/// 空集合写成 `[]` 而不是 NULL：`[]` 表示"用户明确把所有节点都折叠了"，
/// NULL 表示"用户从没保存过"。两者当前渲染结果相同（都全折叠），但保留区别
/// 以后要区分"恢复出厂"与"用户选择全折叠"时不用再改存储格式。
String tagTreeExpandedIdsToStorage(Iterable<String> ids) {
  final normalized = <String>{};
  for (final id in ids) {
    final trimmed = id.trim();
    if (trimmed.isNotEmpty) {
      normalized.add(trimmed);
    }
  }
  final sorted = normalized.toList()..sort();
  return jsonEncode(sorted);
}
