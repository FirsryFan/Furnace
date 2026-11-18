/// 知识包启用位对内容查询的过滤（2026-11-19，「禁用知识包后内容真的不出现」）。
///
/// **归属规则（唯一权威：`package_items`）**
///
///  * 一行 `package_items(package_id, object_type, object_id)` = 该包「拥有」这个
///    本地对象。没有 `package_items` 行的对象（用户手动创建/编辑的内容）永远不受
///    包开关影响；
///  * 同一对象可以被多个包拥有（`package_items` 的唯一键是
///    `(package_id, object_type, object_id)`）。**任一**拥有它的包启用就可见，
///    **全部**拥有包都禁用才隐藏——这样两个包带同一份内容时，禁用其中一个不会把
///    另一个包的内容也藏掉；
///  * `knowledge_packages.enabled` 为 NULL 读作启用（v42 之前导入的老包），只有
///    显式 `false` 才隐藏；`PackageRepository.isPackageEnabled` 是同一口径；
///  * `package_items.package_id` 指向不存在的包（坏数据 / 清理残留）按启用处理：
///    宁可多显示，不因为一条坏外键把用户内容藏起来。
///
/// 过滤只发生在**查询层**：不删行、不改 schema，包重新启用后同样的查询自然恢复。
/// 对象类型取值复用 [ObjectTypes]（`tag` / `knowledge_point` / `card_template` /
/// `mind_map` / `question`）。
///
/// 已知边界（不在本次范围）：
///  * 标签树/题库等按 id 的**钻取读**（`getTagById`、`knowledgePointsByIds`、
///    `getTemplatesForKnowledgePoint`）不过滤：它们只由已过滤的列表进入；
///  * 标签上的对象计数（`TagRepository.objectCountByTagId`）不过滤，隐藏对象的
///    聚合数量可能仍显示在手动标签的角标上。
library;

import '../../domain/services/tags/object_types.dart';
import '../database/database.dart';

/// 一次查询要用的「被禁用包隐藏的对象 id」快照。
///
/// 由 [loadPackageVisibility] 从 `package_items` + `knowledge_packages` 算出；
/// 没有 `package_items` 行或没有任何包被禁用时是 [PackageVisibility.none]，
/// 调用方可以据此直接返回原列表（零过滤开销）。
class PackageVisibility {
  const PackageVisibility._(this._hiddenByType);

  /// 没有任何内容被隐藏（大多数库的常态）。
  static const PackageVisibility none =
      PackageVisibility._(<String, Set<String>>{});

  /// `object_type` -> 被禁用包独占的对象 id。
  final Map<String, Set<String>> _hiddenByType;

  bool get isEmpty => _hiddenByType.isEmpty;

  /// [objectType]（[ObjectTypes] 的值）的 [objectId] 是否被禁用的包隐藏。
  ///
  /// 没有归属、或仍被任一启用包拥有的对象返回 false（= 可见）。
  bool isHidden(String objectType, String objectId) =>
      _hiddenByType[objectType]?.contains(objectId) ?? false;

  /// [items] 里所有不被隐藏的对象，保持原顺序。
  List<T> visible<T>(
    String objectType,
    Iterable<T> items,
    String Function(T) objectIdOf,
  ) {
    if (isEmpty) {
      return items is List<T> ? items : List<T>.of(items);
    }
    return <T>[
      for (final item in items)
        if (!isHidden(objectType, objectIdOf(item))) item,
    ];
  }
}

/// 读出当前被禁用的知识包隐藏的对象。
///
/// 没有任何包被禁用时只读 `knowledge_packages` 就返回 [PackageVisibility.none]
/// （常见路径零过滤开销）；有禁用包时再读 `package_items`。
///
/// 只读；同一份库状态每次返回相同的隐藏集合。`includeDisabledPackages` 是给
/// 「整库导出」这类需要看到全部内容的调用方的旁路。
Future<PackageVisibility> loadPackageVisibility(
  AppDatabase db, {
  bool includeDisabledPackages = false,
}) async {
  if (includeDisabledPackages) {
    return PackageVisibility.none;
  }
  final packageRows = await db.select(db.knowledgePackages).get();
  // 没有包被禁用（也就是绝大多数库）时不可能隐藏任何对象：悬空的 package_id
  // 也按启用处理，所以这一步可以跳过 `package_items` 的读取。
  if (packageRows.every((row) => row.enabled != false)) {
    return PackageVisibility.none;
  }
  final itemRows = await db.select(db.packageItems).get();
  if (itemRows.isEmpty) {
    return PackageVisibility.none;
  }
  // NULL 读作启用；缺失的包 id（坏数据）也按启用处理。
  final enabledById = <String, bool>{
    for (final row in packageRows) row.id: row.enabled != false,
  };

  // (object_type, object_id) -> 拥有它的每个包是否启用。
  final ownerEnabledByObject = <String, List<bool>>{};
  final objectByKey = <String, ({String type, String id})>{};
  for (final item in itemRows) {
    final key = '${item.objectType}\u0000${item.objectId}';
    objectByKey[key] = (type: item.objectType, id: item.objectId);
    (ownerEnabledByObject[key] ??= <bool>[])
        .add(enabledById[item.packageId] ?? true);
  }

  final hiddenByType = <String, Set<String>>{};
  for (final entry in ownerEnabledByObject.entries) {
    if (entry.value.any((enabled) => enabled)) {
      continue;
    }
    final object = objectByKey[entry.key]!;
    (hiddenByType[object.type] ??= <String>{}).add(object.id);
  }
  if (hiddenByType.isEmpty) {
    return PackageVisibility.none;
  }
  return PackageVisibility._(
    Map<String, Set<String>>.unmodifiable(<String, Set<String>>{
      for (final entry in hiddenByType.entries)
        entry.key: Set<String>.unmodifiable(entry.value),
    }),
  );
}
