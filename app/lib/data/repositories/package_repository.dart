import 'package:drift/drift.dart';

import '../../domain/package/knowledge_package_manifest.dart';
import '../database/database.dart';
import '../ids.dart';

/// Repository for imported knowledge package metadata and item mappings.
class PackageRepository {
  PackageRepository(this._db);

  final AppDatabase _db;

  Future<KnowledgePackage> upsertPackage(KnowledgePackageManifest manifest) async {
    final now = DateTime.now().millisecondsSinceEpoch;
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
          ),
          mode: InsertMode.insertOrReplace,
        );
    return (await _db.select(_db.knowledgePackages)
            ..where((t) => t.id.equals(manifest.packageId)))
        .getSingle();
  }

  Future<KnowledgePackage?> getPackageById(String id) {
    return (_db.select(_db.knowledgePackages)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
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

  String _newId(String prefix) => Ids.next(prefix);
}
