import 'package:drift/drift.dart';

import '../../domain/package/knowledge_package_manifest.dart';
import '../database/database.dart';
import '../ids.dart';

/// Repository for imported knowledge package metadata and item mappings.
class PackageRepository {
  PackageRepository(this._db);

  final AppDatabase _db;

  Future<KnowledgePackage> upsertPackage(
      KnowledgePackageManifest manifest) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    // Re-importing must not silently re-enable a disabled package: REPLACE
    // resets columns the companion leaves absent, and `enabled` NULL reads as
    // enabled (v42). Carry the previous flag forward instead.
    final previous = await getPackageById(manifest.packageId);
    await _db.into(_db.knowledgePackages).insert(
          KnowledgePackagesCompanion.insert(
            id: manifest.packageId,
            name: manifest.name,
            version: manifest.version,
            author: manifest.author,
            description: Value(manifest.description),
            importedAt: now,
            createdAt: now,
            updatedAt: now,
            enabled: Value(previous?.enabled),
          ),
          mode: InsertMode.insertOrReplace,
        );
    return (_db.select(_db.knowledgePackages)
          ..where((t) => t.id.equals(manifest.packageId)))
        .getSingle();
  }

  Future<KnowledgePackage?> getPackageById(String id) {
    return (_db.select(_db.knowledgePackages)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  /// Every imported package, newest first - what the knowledge library lists.
  Future<List<KnowledgePackage>> getAllPackages() {
    return (_db.select(_db.knowledgePackages)
          ..orderBy([(t) => OrderingTerm.desc(t.importedAt)]))
        .get();
  }

  /// How many imported objects each package owns, keyed by package id and then
  /// by `package_items.object_type`.
  ///
  /// One query for the whole list on purpose: the library shows every package
  /// at once, and N+1 queries there would be visible.
  Future<Map<String, Map<String, int>>> itemCountsByPackage() async {
    final rows = await _db.select(_db.packageItems).get();
    final counts = <String, Map<String, int>>{};
    for (final row in rows) {
      final byType = counts.putIfAbsent(row.packageId, () => <String, int>{});
      byType[row.objectType] = (byType[row.objectType] ?? 0) + 1;
    }
    return counts;
  }

  Future<PackageItem?> findPackageItem({
    required String packageId,
    required String objectType,
    required String externalId,
  }) {
    return (_db.select(_db.packageItems)
          ..where(
            (t) =>
                t.packageId.equals(packageId) &
                t.objectType.equals(objectType) &
                t.externalId.equals(externalId),
          ))
        .getSingleOrNull();
  }

  Future<void> addPackageItem({
    required String packageId,
    required String objectType,
    required String objectId,
    required String externalId,
  }) async {
    await _db.into(_db.packageItems).insert(
          PackageItemsCompanion.insert(
            id: _newId('pkgitem'),
            packageId: packageId,
            objectType: objectType,
            objectId: objectId,
            externalId: externalId,
            createdAt: DateTime.now().millisecondsSinceEpoch,
          ),
          mode: InsertMode.insertOrIgnore,
        );
  }

  /// Whether [package] is currently enabled.
  ///
  /// `knowledge_packages.enabled` is nullable (v42): NULL reads as enabled, so
  /// packages imported before the column existed - and rows written by
  /// [upsertPackage] - keep working. Only an explicit `false` disables one.
  bool isPackageEnabled(KnowledgePackage package) => package.enabled ?? true;

  /// Enables or disables [packageId], leaving the imported content untouched.
  ///
  /// Enabling writes `true` (not NULL) so the user's choice is explicit. An
  /// unknown id matches no row and is a silent no-op.
  Future<void> setPackageEnabled(String packageId, bool enabled) async {
    await (_db.update(_db.knowledgePackages)
          ..where((t) => t.id.equals(packageId)))
        .write(KnowledgePackagesCompanion(enabled: Value(enabled)));
  }

  /// Uninstalls [packageId]: deletes its `package_items` mappings and then the
  /// `knowledge_packages` row in one transaction, returning the number of item
  /// rows removed.
  ///
  /// Content rows imported from the package (knowledge points, card templates
  /// and states, tags, mind maps) are deliberately kept: the user may have
  /// edited or reviewed them since, and the UI warns that uninstalling only
  /// drops the package shell. Unknown ids return 0 and deleting twice is a
  /// no-op; neither throws.
  Future<int> deletePackage(String packageId) {
    return _db.transaction(() async {
      final itemsDeleted = await (_db.delete(_db.packageItems)
            ..where((t) => t.packageId.equals(packageId)))
          .go();
      await (_db.delete(_db.knowledgePackages)
            ..where((t) => t.id.equals(packageId)))
          .go();
      return itemsDeleted;
    });
  }

  String _newId(String prefix) => Ids.next(prefix);
}
