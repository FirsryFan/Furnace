/// 标签树同层排序的纯逻辑层（纯 Dart：不依赖 Flutter / drift / dart:io）。
///
/// 标签树页面目前只用 `name.compareTo` 给同层兄弟排序
/// （`app/lib/features/tags/presentation/tag_tree_page.dart:56`）。这里把
/// 「字典序 / 按内容量 / 按添加时间」三种口径抽成确定性纯函数，供页面和后续
/// 数据查询（COUNT(object_tags)）复用。
///
/// 约定：
/// - 只排**同层兄弟**：不建树、不查库、不做 UI、不碰 l10n；
/// - 每种口径都是全序：契约里的决胜字段之后继续兜底比较到四个字段，两个条目
///   只有四个字段完全一样时才算相等，因此任意输入顺序得到的输出顺序唯一；
/// - 入参不会被修改，返回值是新列表；
/// - 不做国际化 / 拼音排序：字典序就是 Dart `String.compareTo`（UTF-16 代码
///   单元序），与现有页面的排序行为逐字节一致，不要换成 collation 实现。
library;

/// 标签树同层排序的三种口径。
enum TagTreeSortMode {
  /// 字典序：`name.compareTo` 升序（与 `tag_tree_page.dart:56` 一致）。
  alphabetical('alphabetical', '字典序'),

  /// 按标签下挂的内容量降序（多者在前）；负数计数按 0 参与比较。
  byObjectCount('object_count', '按内容量'),

  /// 按标签创建时间升序（先加的在前）。
  byCreatedAt('created_at', '按添加时间');

  const TagTreeSortMode(this.code, this.labelZh);

  /// 稳定的机器可读编码，snake_case，便于持久化 / 工具参数复用。
  final String code;

  /// 中文显示名（直接给 UI 用；l10n 接线由 UI 层负责）。
  final String labelZh;

  /// 按 [code] 反查口径：两端空白先 trim、大小写不敏感；认不出返回 null。
  static TagTreeSortMode? byCode(String raw) {
    final normalized = raw.trim().toLowerCase();
    if (normalized.isEmpty) return null;
    for (final mode in values) {
      if (mode.code == normalized) return mode;
    }
    return null;
  }
}

/// 标签树里一个同层条目：排序只关心这四个字段。
///
/// [id] 是决胜用的稳定标识（标签主键）；[name] 是显示名（`Tag.name`，不含
/// 路径）；[createdAt] 是添加时间；[objectCount] 是标签下挂内容数，由调用方
/// 查询后填入，缺省 0（负数在比较时按 0 处理，原始值不改）。
class TagTreeSortEntry {
  const TagTreeSortEntry({
    required this.id,
    required this.name,
    required this.createdAt,
    this.objectCount = 0,
  });

  final String id;
  final String name;
  final DateTime createdAt;
  final int objectCount;

  /// 参与排序的内容量：负数当 0（[objectCount] 保留原始值）。
  int get sortableObjectCount => objectCount < 0 ? 0 : objectCount;

  @override
  String toString() =>
      'TagTreeSortEntry(id: $id, name: $name, createdAt: $createdAt, '
      'objectCount: $objectCount)';
}

/// 同层排序入口：返回新列表，不修改 [siblings]。
///
/// 空列表返回空列表；单项返回只含该项的新列表。排序规则见 [TagTreeSortMode]。
List<TagTreeSortEntry> sortTagTreeSiblings(
  List<TagTreeSortEntry> siblings,
  TagTreeSortMode mode,
) {
  final sorted = List<TagTreeSortEntry>.of(siblings);
  sorted.sort((a, b) => _compareEntries(a, b, mode));
  return sorted;
}

/// 中文显示名（可空签名：UI 可直接拿去做 `?? ''` 之类兜底，当前永不为 null）。
String? tagTreeSortModeNameZh(TagTreeSortMode mode) => mode.labelZh;

/// 全序比较：契约里的决胜字段之后继续兜底，保证 comparator 只在两个条目四个
/// 字段完全相同时返回 0。`List.sort` 不保证稳定排序，这样输出依然唯一。
int _compareEntries(
  TagTreeSortEntry a,
  TagTreeSortEntry b,
  TagTreeSortMode mode,
) =>
    switch (mode) {
      TagTreeSortMode.alphabetical => _compareAlphabetical(a, b),
      TagTreeSortMode.byObjectCount => _compareByObjectCount(a, b),
      TagTreeSortMode.byCreatedAt => _compareByCreatedAt(a, b),
    };

/// 字典序：name 升序 → createdAt 升序 → id 升序 → 内容量升序（兜底）。
int _compareAlphabetical(TagTreeSortEntry a, TagTreeSortEntry b) {
  final byName = a.name.compareTo(b.name);
  if (byName != 0) return byName;
  final byCreatedAt = a.createdAt.compareTo(b.createdAt);
  if (byCreatedAt != 0) return byCreatedAt;
  final byId = a.id.compareTo(b.id);
  if (byId != 0) return byId;
  return a.sortableObjectCount.compareTo(b.sortableObjectCount);
}

/// 内容量降序（负数当 0）→ name 升序 → id 升序 → createdAt 升序（兜底）。
int _compareByObjectCount(TagTreeSortEntry a, TagTreeSortEntry b) {
  final byCount = b.sortableObjectCount.compareTo(a.sortableObjectCount);
  if (byCount != 0) return byCount;
  final byName = a.name.compareTo(b.name);
  if (byName != 0) return byName;
  final byId = a.id.compareTo(b.id);
  if (byId != 0) return byId;
  return a.createdAt.compareTo(b.createdAt);
}

/// 添加时间升序 → name 升序 → id 升序 → 内容量降序（兜底）。
int _compareByCreatedAt(TagTreeSortEntry a, TagTreeSortEntry b) {
  final byCreatedAt = a.createdAt.compareTo(b.createdAt);
  if (byCreatedAt != 0) return byCreatedAt;
  final byName = a.name.compareTo(b.name);
  if (byName != 0) return byName;
  final byId = a.id.compareTo(b.id);
  if (byId != 0) return byId;
  return b.sortableObjectCount.compareTo(a.sortableObjectCount);
}
