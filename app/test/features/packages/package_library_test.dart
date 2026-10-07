import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/anki_repository.dart';
import 'package:furnace/data/repositories/mind_map_repository.dart';
import 'package:furnace/data/repositories/package_repository.dart';
import 'package:furnace/data/repositories/tag_repository.dart';
import 'package:furnace/domain/package/knowledge_package_manifest.dart';
import 'package:furnace/features/packages/application/package_export_service.dart';
import 'package:furnace/features/packages/application/package_import_service.dart';

/// The knowledge library's two user-visible promises:
///
/// * an export can be the whole library (as it always was) or exactly one
///   chapter, chosen by tag;
/// * the page can list what was imported, because the records are already in
///   the database.
void main() {
  late AppDatabase db;
  late TagRepository tags;
  late AnkiRepository anki;
  late MindMapRepository maps;
  late PackageRepository packages;
  late PackageExportService export;
  late PackageImportService import;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    tags = TagRepository(db);
    anki = AnkiRepository(db);
    maps = MindMapRepository(db);
    packages = PackageRepository(db);
    export = PackageExportService(
      tagRepository: tags,
      ankiRepository: anki,
      mindMapRepository: maps,
    );
    import = PackageImportService(
      packageRepository: packages,
      tagRepository: tags,
      ankiRepository: anki,
      mindMapRepository: maps,
    );
  });

  tearDown(() async {
    await db.close();
  });

  /// Two tagged knowledge points and one mind map: the smallest library where a
  /// scope can be wrong in a visible way.
  Future<(Tag, Tag)> seed() async {
    final physics = await tags.createTag(name: '物理');
    final chemistry = await tags.createTag(name: '化学');
    final first = await anki.createKnowledgePoint(title: '牛顿', content: 'F=ma');
    final second = await anki.createKnowledgePoint(title: '光合', content: '叶绿体');
    await tags.addTagToObject(
      tagId: physics.id,
      objectType: 'knowledge_point',
      objectId: first.id,
    );
    await tags.addTagToObject(
      tagId: chemistry.id,
      objectType: 'knowledge_point',
      objectId: second.id,
    );
    await maps.createMindMap('总览');
    return (physics, chemistry);
  }

  test('an unscoped export still carries the whole library', () async {
    await seed();

    final manifest = await export.buildManifest();

    expect(manifest.tags, hasLength(2));
    expect(manifest.knowledgePoints, hasLength(2));
    expect(manifest.mindMaps, hasLength(1));
  });

  test('a tag-scoped export carries that tag and its knowledge points only',
      () async {
    final (physics, _) = await seed();

    final manifest = await export.buildManifest(tagIds: {physics.id});

    expect(manifest.tags.map((tag) => tag.name), ['物理']);
    expect(manifest.knowledgePoints.map((kp) => kp.title), ['牛顿']);
    expect(
      manifest.mindMaps,
      isEmpty,
      reason: 'a partially exported map would be a broken tree, not a smaller one',
    );
  });

  test('the asked-for version is written into the manifest', () async {
    final manifest = await export.buildManifest(version: '2.3.4');

    expect(manifest.version, '2.3.4');
  });

  test('the library lists imports with their item counts', () async {
    await import.importManifest(
      KnowledgePackageManifest(
        formatVersion: 1,
        packageId: 'pkg-lib',
        name: '光合作用',
        version: '1.2.0',
        author: '张三',
        exportedAt: DateTime.utc(2026, 10, 2),
        knowledgePoints: const [
          PackageKnowledgePoint(
            id: 'kp-1',
            title: '光合作用场所',
            content: '光合作用的主要场所是叶绿体。',
            templates: [],
          ),
        ],
      ),
    );

    final rows = await packages.getAllPackages();
    expect(rows, hasLength(1));
    expect(rows.single.name, '光合作用');
    expect(rows.single.version, '1.2.0');

    final counts = await packages.itemCountsByPackage();
    expect(counts['pkg-lib']!['knowledge_point'], 1);
    expect(
      counts['pkg-lib']!['card_template'],
      1,
      reason: 'the importer auto-generates one fill-blank template',
    );
  });

  test('an empty library has no counts to show', () async {
    expect(await packages.getAllPackages(), isEmpty);
    expect(await packages.itemCountsByPackage(), isEmpty);
  });
}
