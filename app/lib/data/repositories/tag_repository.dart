import 'package:drift/drift.dart';

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
    return (await _db.select(_db.tags)..where((t) => t.id.equals(id)))
        .getSingle();
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
  Future<void> deleteTag(String id) async {
    final ids = [id, ...await _descendantIds(id)];
    await _db.transaction(() async {
      for (final tagId in ids) {
        await (_db.delete(_db.objectTags)
              ..where((t) => t.tagId.equals(tagId)))
            .go();
      }
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

  Future<List<ObjectTag>> objectLinksForTag(String tagId) {
    return (_db.select(_db.objectTags)..where((t) => t.tagId.equals(tagId)))
        .get();
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
    final parentPath = tag.parentId == null
        ? null
        : (await getTagById(tag.parentId!))?.path;
    var name = tag.name;
    var candidate =
        parentPath == null ? name : '$parentPath/$name';
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
    final children =
        rows.where((r) => r.parentId == id).toList()..sort((a, b) => a.id.compareTo(b.id));
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
