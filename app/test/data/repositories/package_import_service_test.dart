import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knowflow/data/database/database.dart';
import 'package:knowflow/data/repositories/anki_repository.dart';
import 'package:knowflow/data/repositories/mind_map_repository.dart';
import 'package:knowflow/data/repositories/package_repository.dart';
import 'package:knowflow/data/repositories/tag_repository.dart';
import 'package:knowflow/domain/package/knowledge_package_manifest.dart';
import 'package:knowflow/features/packages/application/package_import_service.dart';

void main() {
  late AppDatabase db;
  late PackageImportService service;
  late AnkiRepository anki;
  late TagRepository tags;
  late PackageRepository packages;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    anki = AnkiRepository(db);
    tags = TagRepository(db);
    packages = PackageRepository(db);
    service = PackageImportService(
      packageRepository: packages,
      tagRepository: tags,
      ankiRepository: anki,
      mindMapRepository: MindMapRepository(db),
    );
  });

  tearDown(() async {
    await db.close();
  });

  test('imports knowledge point and auto-generates fill-blank', () async {
    final manifest = KnowledgePackageManifest(
      formatVersion: 1,
      packageId: 'pkg-1',
      name: '光合作用',
      version: '1.0.0',
      author: '张三',
      exportedAt: DateTime.utc(2026, 8, 19),
      tags: const [
        PackageTag(id: 'tag-1', name: '光合作用', color: 123),
      ],
      knowledgePoints: const [
        PackageKnowledgePoint(
          id: 'kp-1',
          title: '光合作用场所',
          content: '光合作用的主要场所是叶绿体。',
          tags: ['tag-1'],
          templates: [],
        ),
      ],
    );

    final summary = await service.importManifest(manifest);

    expect(summary.knowledgePointsCreated, 1);
    expect(summary.templatesCreated, 1);
    expect(summary.tagsCreated, 1);

    final kps = await anki.getKnowledgePoints();
    expect(kps, hasLength(1));
    final templates = await anki.getTemplatesForKnowledgePoint(kps.single.id);
    expect(templates, hasLength(1));
    expect(templates.single.type, 'fill_blank');

    final allTags = await tags.getAllTags();
    expect(allTags, hasLength(1));

    final pkg = await packages.getPackageById('pkg-1');
    expect(pkg, isNotNull);
    expect(pkg!.name, '光合作用');
  });

  test('re-import does not duplicate templates', () async {
    final manifest = KnowledgePackageManifest(
      formatVersion: 1,
      packageId: 'pkg-2',
      name: '重复导入',
      version: '1.0.0',
      author: '李四',
      exportedAt: DateTime.utc(2026, 8, 19),
      knowledgePoints: const [
        PackageKnowledgePoint(
          id: 'kp-2',
          title: '测试',
          content: '测试内容是数字 42。',
          templates: [],
        ),
      ],
    );

    await service.importManifest(manifest);
    await service.importManifest(manifest);

    final kps = await anki.getKnowledgePoints();
    expect(kps, hasLength(1));
    final templates = await anki.getTemplatesForKnowledgePoint(kps.single.id);
    expect(templates, hasLength(1));
  });
}
