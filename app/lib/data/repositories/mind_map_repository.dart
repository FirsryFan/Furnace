import 'package:drift/drift.dart';

import '../database/database.dart';
import '../ids.dart';

/// Repository for mind maps and mind map nodes.
class MindMapRepository {
  MindMapRepository(this._db);

  final AppDatabase _db;

  Future<MindMap> createMindMap(String title) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = _newId('map');
    await _db.into(_db.mindMaps).insert(
          MindMapsCompanion.insert(
            id: id,
            title: title,
            createdAt: now,
            updatedAt: now,
          ),
        );
    return (await _db.select(_db.mindMaps)..where((t) => t.id.equals(id)))
        .getSingle();
  }

  Future<List<MindMap>> getMindMaps() {
    return _db.select(_db.mindMaps).get();
  }

  Future<MindNode> addNode({
    required String mapId,
    String? parentId,
    required String text,
    String? notes,
    bool isTag = false,
    String? tagId,
    int sortOrder = 0,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = _newId('node');
    await _db.into(_db.mindNodes).insert(
          MindNodesCompanion.insert(
            id: id,
            mapId: mapId,
            parentId: Value(parentId),
            nodeText: text,
            notes: Value(notes),
            isTag: Value(isTag),
            tagId: Value(tagId),
            sortOrder: Value(sortOrder),
            createdAt: now,
            updatedAt: now,
          ),
        );
    return (await _db.select(_db.mindNodes)..where((t) => t.id.equals(id)))
        .getSingle();
  }

  Future<List<MindNode>> getNodesForMap(String mapId) {
    return (_db.select(_db.mindNodes)..where((t) => t.mapId.equals(mapId)))
        .get();
  }

  Future<void> updateNode(
    String id, {
    String? text,
    String? notes,
    bool? isTag,
    String? tagId,
    bool? collapsed,
    int? sortOrder,
    bool clearNotes = false,
  }) async {
    await (_db.update(_db.mindNodes)..where((t) => t.id.equals(id))).write(
      MindNodesCompanion(
        nodeText: text == null ? const Value.absent() : Value(text),
        notes: clearNotes
            ? Value<String?>(null)
            : (notes == null ? const Value.absent() : Value(notes)),
        isTag: isTag == null ? const Value.absent() : Value(isTag),
        tagId: tagId == null ? const Value.absent() : Value(tagId),
        collapsed: collapsed == null ? const Value.absent() : Value(collapsed),
        sortOrder: sortOrder == null ? const Value.absent() : Value(sortOrder),
        updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );
  }

  Future<void> moveNode(String id, {required bool up}) async {
    final node = await (_db.select(_db.mindNodes)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (node == null) {
      return;
    }
    final allNodes = await getNodesForMap(node.mapId);
    final siblings = allNodes
        .where((n) => n.parentId == node.parentId)
        .toList()
      ..sort((a, b) {
        final byOrder = a.sortOrder.compareTo(b.sortOrder);
        if (byOrder != 0) {
          return byOrder;
        }
        return a.createdAt.compareTo(b.createdAt);
      });
    final index = siblings.indexWhere((n) => n.id == id);
    final target = up ? index - 1 : index + 1;
    if (index < 0 || target < 0 || target >= siblings.length) {
      return;
    }
    final other = siblings[target];
    await _db.transaction(() async {
      await (_db.update(_db.mindNodes)..where((t) => t.id.equals(node.id)))
          .write(MindNodesCompanion(sortOrder: Value(other.sortOrder)));
      await (_db.update(_db.mindNodes)..where((t) => t.id.equals(other.id)))
          .write(MindNodesCompanion(sortOrder: Value(node.sortOrder)));
    });
  }

  Future<void> deleteNode(String id) async {
    await _db.transaction(() async {
      await _deleteSubtree(id);
    });
  }

  Future<void> deleteMindMap(String mapId) async {
    await _db.transaction(() async {
      final nodes = await getNodesForMap(mapId);
      for (final node in nodes) {
        await _deleteSubtree(node.id);
      }
      await (_db.delete(_db.mindMaps)..where((t) => t.id.equals(mapId))).go();
    });
  }

  Future<void> _deleteSubtree(String nodeId) async {
    final children = await (_db.select(_db.mindNodes)
          ..where((t) => t.parentId.equals(nodeId)))
        .get();
    for (final child in children) {
      await _deleteSubtree(child.id);
    }
    await (_db.delete(_db.mindNodes)..where((t) => t.id.equals(nodeId))).go();
  }

  String _newId(String prefix) => Ids.next(prefix);
}
