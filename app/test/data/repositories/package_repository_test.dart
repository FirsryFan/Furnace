import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/anki_repository.dart';
import 'package:furnace/data/repositories/mind_map_repository.dart';
import 'package:furnace/data/repositories/package_repository.dart';
import 'package:furnace/data/repositories/tag_repository.dart';
import 'package:furnace/domain/package/knowledge_package_manifest.dart';
import 'package:furnace/features/packages/application/package_import_service.dart';

/// Knowledge package lifecycle: the v42 `enabled` flag (NULL reads as enabled)
/// and uninstalling a package while keeping the content it imported.
void main() {
  late AppDatabase db;
  late PackageRepository packages;
  late PackageImportService importService;
  late AnkiRepository anki;
  late TagRepository tags;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    packages = PackageRepository(db);
    anki = AnkiRepository(db);
    tags = TagRepository(db);
    importService = PackageImportService(
      packageRepository: packages,
      tagRepository: tags,
      ankiRepository: anki,
      mindMapRepository: MindMapRepository(db),
    );
  });

  tearDown(() async {
    await db.close();
  });

  KnowledgePackageManifest manifestFor(String packageId) {
    return KnowledgePackageManifest(
      formatVersion: 1,
      packageId: packageId,
      name: '知识包 $packageId',
      version: '1.0.0',
      author: '测试作者',
      exportedAt: DateTime.utc(2026, 11, 1),
      tags: const [PackageTag(id: 'tag-1', name: '光合作用', color: 123)],
      knowledgePoints: const [
        PackageKnowledgePoint(
          id: 'kp-1',
          title: '光合作用场所',
          content: '光合作用的主要场所是叶绿体。',
          tags: ['tag-1'],
        ),
      ],
    );
  }

  // tag + knowledge point + auto-generated fill-blank template.
  const importedItemCount = 3;

  group('enabled flag (v42)', () {
    test('NULL enabled reads as enabled', () async {
      await packages.upsertPackage(manifestFor('pkg-null'));

      final row = (await packages.getPackageById('pkg-null'))!;
      expect(row.enabled, isNull, reason: 'the column is left NULL on import');
      expect(packages.isPackageEnabled(row), isTrue);
    });

    test('disable/enable round trip is persisted', () async {
      await packages.upsertPackage(manifestFor('pkg-1'));

      await packages.setPackageEnabled('pkg-1', false);
      final disabled = (await packages.getPackageById('pkg-1'))!;
      expect(disabled.enabled, isFalse);
      expect(packages.isPackageEnabled(disabled), isFalse);

      await packages.setPackageEnabled('pkg-1', true);
      final enabled = (await packages.getPackageById('pkg-1'))!;
      expect(enabled.enabled, isTrue, reason: 'enabling writes true, not NULL');
      expect(packages.isPackageEnabled(enabled), isTrue);
    });

    test('getAllPackages carries the flag for the library list', () async {
      await packages.upsertPackage(manifestFor('pkg-1'));
      await packages.setPackageEnabled('pkg-1', false);

      final rows = await packages.getAllPackages();
      expect(rows, hasLength(1));
      expect(packages.isPackageEnabled(rows.single), isFalse);
    });

    test('toggling an unknown id is a no-op', () async {
      await packages.setPackageEnabled('does-not-exist', false);
      expect(await packages.getPackageById('does-not-exist'), isNull);
    });
  });

  group('deletePackage', () {
    test('removes the package and its items but keeps imported content',
        () async {
      final summary = await importService.importManifest(manifestFor('pkg-1'));
      expect(summary.knowledgePointsCreated, 1);
      expect(summary.templatesCreated, 1);
      expect(summary.tagsCreated, 1);

      final itemsBefore = await (db.select(db.packageItems)
            ..where((t) => t.packageId.equals('pkg-1')))
          .get();
      expect(itemsBefore, hasLength(importedItemCount));

      final deleted = await packages.deletePackage('pkg-1');
      expect(deleted, importedItemCount);

      expect(await packages.getPackageById('pkg-1'), isNull);
      expect(await db.select(db.packageItems).get(), isEmpty);
      expect((await packages.itemCountsByPackage())['pkg-1'], isNull);

      final kps = await anki.getKnowledgePoints();
      expect(kps, hasLength(1));
      expect(kps.single.title, '光合作用场所');
      expect(
        await anki.getTemplatesForKnowledgePoint(kps.single.id),
        isNotEmpty,
        reason: 'card templates and states belong to the content',
      );
      expect(await tags.getAllTags(), hasLength(1));
    });

    test('unknown id returns 0 and does not throw', () async {
      expect(await packages.deletePackage('does-not-exist'), 0);
      expect(await packages.deletePackage('does-not-exist'), 0);
    });

    test('deleting the same package twice is a no-op the second time',
        () async {
      await importService.importManifest(manifestFor('pkg-1'));

      expect(await packages.deletePackage('pkg-1'), importedItemCount);
      expect(await packages.deletePackage('pkg-1'), 0);
    });

    test('only the target package is removed', () async {
      await packages.upsertPackage(manifestFor('pkg-1'));
      await packages.upsertPackage(manifestFor('pkg-2'));
      await packages.addPackageItem(
        packageId: 'pkg-1',
        objectType: 'tag',
        objectId: 'local-tag-1',
        externalId: 'tag-1',
      );
      await packages.addPackageItem(
        packageId: 'pkg-2',
        objectType: 'tag',
        objectId: 'local-tag-2',
        externalId: 'tag-1',
      );

      expect(await packages.deletePackage('pkg-1'), 1);

      expect(await packages.getPackageById('pkg-1'), isNull);
      expect(await packages.getPackageById('pkg-2'), isNotNull);
      expect((await packages.itemCountsByPackage()).keys, ['pkg-2']);
    });
  });

  group('re-import', () {
    test('re-importing an existing package keeps its disabled state', () async {
      await packages.upsertPackage(manifestFor('pkg-1'));
      await packages.setPackageEnabled('pkg-1', false);

      await packages.upsertPackage(manifestFor('pkg-1'));

      final row = (await packages.getPackageById('pkg-1'))!;
      expect(row.enabled, isFalse, reason: 're-import must not re-enable');
      expect(packages.isPackageEnabled(row), isFalse);
    });
  });
}
