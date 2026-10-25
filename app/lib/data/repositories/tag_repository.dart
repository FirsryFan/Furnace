import 'package:drift/drift.dart';

import '../../domain/services/tags/tag_usage.dart';
import '../database/database.dart';
import '../ids.dart';

/// Repository for the hierarchical tag system (v2, spec 1.1.2).
///
/// Tags form a tree (`parentId`); every tag caches its authoritative full
/// path string (`path`, e.g. `文化课/学科/语文/作文`). Paths are recomputed
/// in cascade on rename / move / delete, always inside a transaction.
class TagRepository {
  TagRepository(this._db);

  final AppDatabase _db;

  /// Creates a tag under [parentId] (null = top level). The path is derived
  /// from the parent path; sibling duplicates are auto-suffixed (`name-2`).
  Future<Tag> createTag({
    required String name,
    int? color,
    String? description,
    String? sourceNodeId,
    String? parentId,
  }) async {
    final cleanName = _cleanName(name);
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = _newId('tag');
    final parentPath = parentId == null ? null : (await _requirePath(parentId));
    final basePath = parentPath == null ? cleanName : '$parentPath/$cleanName';
    final path = await _uniquePath(basePath);

    await _db.into(_db.tags).insert(
          TagsCompanion.insert(
            id: id,
            parentId: Value(parentId),
            name: cleanName,
            path: Value(path),
            color: Value(color),
            description: Value(description),
            sourceNodeId: Value(sourceNodeId),
            createdAt: now,
            updatedAt: now,
          ),
        );
    return (_db.select(_db.tags)..where((t) => t.id.equals(id))).getSingle();
  }

  /// Imports a full node subtree as tags (Mindnet "系" import, spec 1.4.3).
  ///
  /// [nodes] must be ordered parents-first; each entry carries its text and
  /// optional existing parent tag id ([parentTagId]) when the parent node
  /// maps to a tag already created in this import. Returns created tag ids.
  Future<Map<String, String>> importSubtree({
    required List<({String nodeId, String text, String? parentNodeId})> nodes,
    String? parentTagId,
    int? color,
  }) async {
    final idByNode = <String, String>{};
    final existingParent = parentTagId;
    for (final node in nodes) {
      final parentId = node.parentNodeId == null
          ? existingParent
          : idByNode[node.parentNodeId];
      final tag = await createTag(
        name: node.text,
        color: color,
        sourceNodeId: node.nodeId,
        parentId: parentId,
      );
      idByNode[node.nodeId] = tag.id;
    }
    return idByNode;
  }

  Future<List<Tag>> getAllTags() {
    return _db.select(_db.tags).get();
  }

  Future<Tag?> getTagById(String id) {
    return (_db.select(_db.tags)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  Future<Tag?> getTagByPath(String path) {
    return (_db.select(_db.tags)..where((t) => t.path.equals(path)))
        .getSingleOrNull();
  }

  /// All tags whose path equals [path] or is under it.
  Future<List<Tag>> getTagsUnderPath(String path) {
    final query = _db.select(_db.tags);
    final pattern = '$path/%';
    query.where((t) => t.path.equals(path) | t.path.like(pattern));
    query.orderBy([(t) => OrderingTerm.asc(t.path)]);
    return query.get();
  }

  Future<List<Tag>> getChildren(String parentId) {
    final query = _db.select(_db.tags);
    query.where((t) => t.parentId.equals(parentId));
    query.orderBy([(t) => OrderingTerm.asc(t.createdAt)]);
    return query.get();
  }

  /// 把一行标签映射成用途解析器的快照（v37，轮次一百七十六）。
  ///
  /// 继承在读取时算：解析器只知道 id/parentId/本级声明，不查库、不递归。
  TagUsageResolver resolverFor(Iterable<Tag> tags) => TagUsageResolver([
        for (final tag in tags)
          TagUsageNode(
            id: tag.id,
            parentId: tag.parentId,
            declaredUsages: decodeTagUsageCodes(tag.usageCodes),
          ),
      ]);

  /// 写一个标签的用途声明；空集合写回 NULL（= 这一级没有声明，恢复继承）。
  ///
  /// 只写这一行，不动子标签：继承是读侧算的，所以改父标签的声明对整棵子树
  /// 立刻生效，也不需要级联回填（docs/REVIEW_FEEDBACK.md §10）。
  Future<void> updateTagUsageCodes(String tagId, Set<TagUsage> usages) async {
    await (_db.update(_db.tags)..where((t) => t.id.equals(tagId))).write(
      TagsCompanion(
        usageCodes: Value(encodeTagUsageCodes(usages)),
        updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );
  }

  /// Renames a tag and cascades the path change through its subtree.
  Future<void> renameTag(String id, String name) async {
    final cleanName = _cleanName(name);
    final tag = await getTagById(id);
    if (tag == null || tag.name == cleanName) {
      return;
    }
    await _db.transaction(() async {
      await (_db.update(_db.tags)..where((t) => t.id.equals(id))).write(
        TagsCompanion(
          name: Value(cleanName),
          updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
        ),
      );
      await _refreshSubtreePaths(id);
    });
  }

  /// Moves a tag (and its subtree) under [newParentId]; [newParentId] null
  /// moves it to the top level. Rejects cycles.
  Future<void> moveTag(String id, String? newParentId) async {
    final tag = await getTagById(id);
    if (tag == null || tag.parentId == newParentId) {
      return;
    }
    if (newParentId != null) {
      final descendants = await _descendantIds(id);
      if (descendants.contains(newParentId)) {
        throw ArgumentError('cannot move a tag under its own descendant');
      }
    }
    await _db.transaction(() async {
      await (_db.update(_db.tags)..where((t) => t.id.equals(id))).write(
        TagsCompanion(
          parentId: Value<String?>(newParentId),
          updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
        ),
      );
      await _refreshSubtreePaths(id);
    });
  }

  /// Deletes a tag with its whole subtree and all object links.
  ///
  /// The group's daily target goes with it (v8), in the same transaction: a plan
  /// row addresses a group by tag id, so a plan that outlived its tag would name
  /// a group nothing can resolve.
  Future<void> deleteTag(String id) async {
    final ids = [id, ...await _descendantIds(id)];
    await _db.transaction(() async {
      for (final tagId in ids) {
        await (_db.delete(_db.objectTags)..where((t) => t.tagId.equals(tagId)))
            .go();
      }
      await (_db.delete(_db.reviewGroupPlans)..where((t) => t.tagId.isIn(ids)))
          .go();
      await (_db.delete(_db.tags)..where((t) => t.id.isIn(ids))).go();
    });
  }

  Future<void> addTagToObject({
    required String tagId,
    required String objectType,
    required String objectId,
  }) async {
    await _db.into(_db.objectTags).insert(
          ObjectTagsCompanion.insert(
            id: _newId('link'),
            tagId: tagId,
            objectType: objectType,
            objectId: objectId,
            createdAt: DateTime.now().millisecondsSinceEpoch,
          ),
          mode: InsertMode.insertOrIgnore,
        );
  }

  Future<void> removeTagFromObject({
    required String tagId,
    required String objectType,
    required String objectId,
  }) async {
    await (_db.delete(_db.objectTags)
          ..where(
            (t) =>
                t.tagId.equals(tagId) &
                t.objectType.equals(objectType) &
                t.objectId.equals(objectId),
          ))
        .go();
  }

  /// Links [tagId] to many objects of [objectType] in **one transaction**.
  ///
  /// A batch flow ("tag these twenty questions at once") used to loop over
  /// [addTagToObject]; that opened one statement per object. Here the ids are
  /// trimmed, blanks dropped and duplicates collapsed (first occurrence wins)
  /// before a single multi-row insert runs.
  ///
  /// Existing links are **skipped, not errors**: the return value is the number
  /// of genuinely new rows, so a second identical call returns 0. That keeps
  /// double taps harmless without callers pre-filtering.
  ///
  /// [objectType] defaults to `question` for convenience but is never
  /// hard-coded inside the repository - pass the caller's own domain key
  /// (`knowledge_point`, ...).
  Future<int> addTagToObjects({
    required String tagId,
    required Iterable<String> objectIds,
    String objectType = 'question',
  }) async {
    final cleanTagId = tagId.trim();
    final cleanType = objectType.trim();
    final ids = _cleanObjectIds(objectIds);
    if (cleanTagId.isEmpty || cleanType.isEmpty || ids.isEmpty) {
      return 0;
    }
    return _db.transaction(() async {
      final existing = await (_db.selectOnly(_db.objectTags)
            ..addColumns([_db.objectTags.objectId])
            ..where(
              _db.objectTags.tagId.equals(cleanTagId) &
                  _db.objectTags.objectType.equals(cleanType) &
                  _db.objectTags.objectId.isIn(ids),
            ))
          .map((row) => row.read(_db.objectTags.objectId)!)
          .get();
      final known = existing.toSet();
      final missing = <String>[
        for (final objectId in ids)
          if (!known.contains(objectId)) objectId,
      ];
      if (missing.isEmpty) {
        return 0;
      }
      final now = DateTime.now().millisecondsSinceEpoch;
      await _db.batch((batch) {
        batch.insertAll(
          _db.objectTags,
          [
            for (final objectId in missing)
              ObjectTagsCompanion.insert(
                id: _newId('link'),
                tagId: cleanTagId,
                objectType: cleanType,
                objectId: objectId,
                createdAt: now,
              ),
          ],
          mode: InsertMode.insertOrIgnore,
        );
      });
      return missing.length;
    });
  }

  /// Removes many links of [tagId] to [objectIds] of [objectType] at once.
  ///
  /// Same cleaning as [addTagToObjects] (trim, drop blanks, de-duplicate) and a
  /// single transaction. Returns how many links were really deleted; ids that
  /// were not linked are skipped and do not make the call fail.
  Future<int> removeTagFromObjects({
    required String tagId,
    required Iterable<String> objectIds,
    String objectType = 'question',
  }) async {
    final cleanTagId = tagId.trim();
    final cleanType = objectType.trim();
    final ids = _cleanObjectIds(objectIds);
    if (cleanTagId.isEmpty || cleanType.isEmpty || ids.isEmpty) {
      return 0;
    }
    return _db.transaction(() async {
      return (_db.delete(_db.objectTags)
            ..where(
              (t) =>
                  t.tagId.equals(cleanTagId) &
                  t.objectType.equals(cleanType) &
                  t.objectId.isIn(ids),
            ))
          .go();
    });
  }

  /// Trimmed, blank-free, de-duplicated ids in first-seen order.
  static List<String> _cleanObjectIds(Iterable<String> objectIds) {
    final seen = <String>{};
    final clean = <String>[];
    for (final objectId in objectIds) {
      final id = objectId.trim();
      if (id.isEmpty || !seen.add(id)) {
        continue;
      }
      clean.add(id);
    }
    return clean;
  }

  Future<List<Tag>> tagsForObject({
    required String objectType,
    required String objectId,
  }) async {
    final query = _db.select(_db.tags).join([
      innerJoin(
        _db.objectTags,
        _db.objectTags.tagId.equalsExp(_db.tags.id),
      ),
    ])
      ..where(
        _db.objectTags.objectType.equals(objectType) &
            _db.objectTags.objectId.equals(objectId),
      );
    final rows = await query.get();
    return rows.map((row) => row.readTable(_db.tags)).toList();
  }

  // --- cards with no card group --------------------------------------------

  /// How many knowledge points carry no tag at all.
  ///
  /// A card group (*卡组*) *is* a tag, so a card with no tag belongs to no group
  /// and no daily target can ever reach it. That used to fail silently: the
  /// review-plan screen simply showed an empty list and the cards sat there
  /// forever. This count makes the gap visible, and
  /// [tagKnowledgePointsWithoutTags] fixes it in one action.
  Future<int> countKnowledgePointsWithoutTags() async {
    final row = await _db.customSelect(
      _untaggedKnowledgePointQuery('COUNT(*) AS c'),
      readsFrom: {_db.knowledgePoints, _db.objectTags},
    ).getSingle();
    return row.read<int>('c');
  }

  /// The ids of every knowledge point that carries no tag at all.
  Future<List<String>> knowledgePointIdsWithoutTags() async {
    final rows = await _db.customSelect(
      _untaggedKnowledgePointQuery('kp.id AS id'),
      readsFrom: {_db.knowledgePoints, _db.objectTags},
    ).get();
    return [for (final row in rows) row.read<String>('id')];
  }

  /// Links [tagId] to every knowledge point that currently has no tag.
  ///
  /// Returns how many cards got their first tag. Existing links are ignored, so
  /// calling this twice cannot duplicate anything - the second call just finds
  /// nothing left to do and returns 0.
  Future<int> tagKnowledgePointsWithoutTags(String tagId) async {
    if (await getTagById(tagId) == null) {
      throw ArgumentError('unknown tag: $tagId');
    }
    final ids = await knowledgePointIdsWithoutTags();
    if (ids.isEmpty) {
      return 0;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.batch((batch) {
      batch.insertAll(
        _db.objectTags,
        [
          for (final objectId in ids)
            ObjectTagsCompanion.insert(
              id: _newId('link'),
              tagId: tagId,
              objectType: 'knowledge_point',
              objectId: objectId,
              createdAt: now,
            ),
        ],
        mode: InsertMode.insertOrIgnore,
      );
    });
    return ids.length;
  }

  /// SQL for "knowledge points with no tag", shared by the two readers above.
  ///
  /// `NOT EXISTS` rather than a `LEFT JOIN ... IS NULL`: the join form would
  /// multiply rows when a card has several tags and force a `DISTINCT`.
  String _untaggedKnowledgePointQuery(String columns) =>
      'SELECT $columns FROM knowledge_points kp WHERE NOT EXISTS ('
      'SELECT 1 FROM object_tags ot WHERE ot.object_type = '
      "'knowledge_point' AND ot.object_id = kp.id)";

  Future<List<ObjectTag>> objectLinksForTag(String tagId) {
    return (_db.select(_db.objectTags)..where((t) => t.tagId.equals(tagId)))
        .get();
  }

  /// How many objects carry each tag, for the tag tree's "sort by content"
  /// mode (`tag_tree_sort.dart`).
  ///
  /// Direct mode ([includeDescendants] = false) counts only links attached to
  /// the tag itself, grouped by `tag_id`; tags without objects are omitted
  /// (callers read a missing key as 0). With [objectTypes] non-null only those
  /// `object_type`s are counted (`WHERE object_type IN (...)`); an empty set
  /// counts nothing.
  ///
  /// Subtree mode ([includeDescendants] = true) counts each tag plus all of its
  /// descendants, and returns **every** tag id in `tags` (0 when the subtree
  /// has no objects) so the UI can look a count up by id. The rollup uses the
  /// `parent_id` chain in memory - `path` is a derived cache and recursive SQL
  /// is not used here.
  ///
  /// Read-only: no table is written, and repeated calls on the same database
  /// state return the same counts.
  Future<Map<String, int>> objectCountByTagId({
    bool includeDescendants = false,
    Set<String>? objectTypes,
  }) async {
    final direct = await _directObjectCounts(objectTypes);
    if (!includeDescendants) {
      return direct;
    }

    final allTags = await _db.select(_db.tags).get();
    final parentById = <String, String?>{
      for (final tag in allTags) tag.id: tag.parentId,
    };
    final totals = <String, int>{for (final tag in allTags) tag.id: 0};
    direct.forEach((tagId, count) {
      // Walk up the parent chain; every ancestor counts the same link once.
      // Unknown tag ids (debris links) are ignored: they are not tags the tree
      // can show. The visited set only guards against a corrupt parent cycle.
      String? current = tagId;
      final visited = <String>{};
      while (current != null && parentById.containsKey(current)) {
        if (!visited.add(current)) {
          break;
        }
        totals[current] = totals[current]! + count;
        current = parentById[current];
      }
    });
    return totals;
  }

  /// Direct counts, grouped by `tag_id`; empty set means "no object type".
  Future<Map<String, int>> _directObjectCounts(Set<String>? objectTypes) async {
    if (objectTypes != null && objectTypes.isEmpty) {
      return <String, int>{};
    }
    final count = _db.objectTags.id.count();
    final query = _db.selectOnly(_db.objectTags)
      ..addColumns([_db.objectTags.tagId, count])
      ..groupBy([_db.objectTags.tagId]);
    if (objectTypes != null) {
      query.where(_db.objectTags.objectType.isIn(objectTypes));
    }
    final rows = await query.get();
    return {
      for (final row in rows)
        row.read(_db.objectTags.tagId)!: row.read(count) ?? 0,
    };
  }

  // --- internals -----------------------------------------------------------

  Future<String> _requirePath(String tagId) async {
    final tag = await getTagById(tagId);
    if (tag == null || tag.path == null) {
      throw ArgumentError('parent tag $tagId missing or without path');
    }
    return tag.path!;
  }

  Future<String> _uniquePath(String basePath) async {
    final existing = await getTagByPath(basePath);
    if (existing == null) {
      return basePath;
    }
    var n = 2;
    while (true) {
      final candidate = '$basePath-$n';
      if (await getTagByPath(candidate) == null) {
        return candidate;
      }
      n++;
    }
  }

  /// Recomputed [path] of [id] from its (possibly just changed) parent and
  /// cascades to descendants. Must run inside a transaction.
  Future<void> _refreshSubtreePaths(String id) async {
    final rows = await (_db.select(_db.tags)
          ..where((t) => t.id.equals(id) | t.parentId.equals(id)))
        .get();
    final tag = rows.where((r) => r.id == id).firstOrNull;
    if (tag == null) {
      return;
    }
    final parentPath =
        tag.parentId == null ? null : (await getTagById(tag.parentId!))?.path;
    var name = tag.name;
    var candidate = parentPath == null ? name : '$parentPath/$name';
    while (await _otherWithPath(candidate, excludeId: id) != null) {
      name = '$name-2';
      candidate = parentPath == null ? name : '$parentPath/$name';
    }
    if (candidate != tag.path) {
      await (_db.update(_db.tags)..where((t) => t.id.equals(id))).write(
        TagsCompanion(
          name: name != tag.name ? Value(name) : const Value.absent(),
          path: Value(candidate),
          updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
        ),
      );
    }
    final children = rows.where((r) => r.parentId == id).toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    for (final child in children) {
      await _refreshSubtreePaths(child.id);
    }
  }

  Future<Tag?> _otherWithPath(String path, {required String excludeId}) async {
    final query = _db.select(_db.tags)
      ..where((t) => t.path.equals(path) & t.id.equals(excludeId).not());
    return query.getSingleOrNull();
  }

  Future<List<String>> _descendantIds(String id) async {
    final result = <String>[];
    final children = await getChildren(id);
    for (final child in children) {
      result.add(child.id);
      result.addAll(await _descendantIds(child.id));
    }
    return result;
  }

  /// Names must not contain the path separator `/`.
  static String _cleanName(String name) {
    var clean = name.trim();
    clean = clean.replaceAll('/', '-');
    return clean.isEmpty ? 'untitled' : clean;
  }

  String _newId(String prefix) => Ids.next(prefix);
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final it = iterator;
    return it.moveNext() ? it.current : null;
  }
}
