import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/package/knowledge_package_visibility.dart';
import 'package:furnace/data/repositories/anki_repository.dart';
import 'package:furnace/data/repositories/mind_map_repository.dart';
import 'package:furnace/data/repositories/package_repository.dart';
import 'package:furnace/data/repositories/tag_repository.dart';
import 'package:furnace/domain/package/knowledge_package_manifest.dart';
import 'package:furnace/features/packages/application/package_export_service.dart';
import 'package:furnace/features/packages/application/package_import_service.dart';
import 'package:furnace/features/questions/application/question_library_reader.dart';

/// 知识包开关的**内容过滤**契约（2026-11-19）。
///
/// 归属规则（唯一权威：`package_items`）：
///  * 没有 `package_items` 行的对象 = 用户手动内容，永远不受包开关影响；
///  * 同一对象被多个包拥有时，**任一**拥有包启用即可见，全部禁用才隐藏；
///  * `enabled` NULL 读作启用（v42 之前的老包）；
///  * 过滤只发生在查询层：内容行不删，重新启用后同样的查询自然恢复。
void main() {
  late AppDatabase db;
  late TagRepository tags;
  late AnkiRepository anki;
  late MindMapRepository maps;
  late PackageRepository packages;
  late PackageImportService importService;
  late PackageExportService exportService;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    tags = TagRepository(db);
    anki = AnkiRepository(db);
    maps = MindMapRepository(db);
    packages = PackageRepository(db);
    importService = PackageImportService(
      packageRepository: packages,
      tagRepository: tags,
      ankiRepository: anki,
      mindMapRepository: maps,
    );
    exportService = PackageExportService(
      tagRepository: tags,
      ankiRepository: anki,
      mindMapRepository: maps,
    );
  });

  tearDown(() async {
    await db.close();
  });

  /// 一个带「标签 + 知识点（自动生成一张填空题）+ 思维导图」的最小知识包。
  KnowledgePackageManifest manifestFor(String suffix) {
    return KnowledgePackageManifest(
      formatVersion: 1,
      packageId: 'pkg-$suffix',
      name: '知识包 $suffix',
      version: '1.0.0',
      author: '测试作者',
      exportedAt: DateTime.utc(2026, 11, 19),
      tags: [
        PackageTag(id: 'tag-$suffix', name: '$suffix 标签'),
      ],
      knowledgePoints: [
        PackageKnowledgePoint(
          id: 'kp-$suffix',
          title: '$suffix 知识点',
          content: '$suffix 的主要内容是第 ${suffix.codeUnitAt(0)} 号事实。',
          tags: ['tag-$suffix'],
        ),
      ],
      mindMaps: [
        PackageMindMap(
          id: 'map-$suffix',
          title: '$suffix 导图',
          nodes: [
            PackageMindNode(id: 'node-$suffix', text: '$suffix 节点'),
          ],
        ),
      ],
    );
  }

  Future<void> importTwo() async {
    await importService.importManifest(manifestFor('A'));
    await importService.importManifest(manifestFor('B'));
  }

  Future<String> kpIdOf(String title) async {
    final all = await anki.getKnowledgePoints(includeDisabledPackages: true);
    return all.singleWhere((point) => point.title == title).id;
  }

  Future<String> tagIdOf(String name) async {
    final all = await tags.getAllTags(includeDisabledPackages: true);
    return all.singleWhere((tag) => tag.name == name).id;
  }

  Future<void> insertQuestion(String id, String stem) async {
    await db.into(db.questions).insert(
          QuestionsCompanion.insert(
            id: id,
            stem: stem,
            stemFingerprint: Value('fp-$id'),
            createdAt: 0,
            updatedAt: 0,
          ),
        );
  }

  test('禁用 A：A 的标签/知识点/卡模板/导图都从默认查询里消失，B 不受影响', () async {
    await importTwo();
    await packages.setPackageEnabled('pkg-A', false);

    final visibleTags = await tags.getAllTags();
    expect(visibleTags.map((tag) => tag.name), ['B 标签']);

    final visiblePoints = await anki.getKnowledgePoints();
    expect(visiblePoints.map((point) => point.title), ['B 知识点']);

    final aKpId = await kpIdOf('A 知识点');
    final bKpId = await kpIdOf('B 知识点');
    final visibleTemplates = await anki.getAllTemplates();
    expect(
      visibleTemplates.map((template) => template.knowledgePointId).toSet(),
      {bKpId},
      reason: 'B 的自动填空题仍在，A 的自动填空题被过滤',
    );
    expect(
      (await anki.getAllTemplates(includeDisabledPackages: true))
          .map((template) => template.knowledgePointId)
          .toSet(),
      {aKpId, bKpId},
      reason: 'A 的卡模板还在库里，只是默认查询看不见',
    );

    final visibleMaps = await maps.getMindMaps();
    expect(visibleMaps.map((map) => map.title), ['B 导图']);
  });

  test('重新启用 A：A 的内容原样恢复（内容行从未被删）', () async {
    await importTwo();
    await packages.setPackageEnabled('pkg-A', false);
    await packages.setPackageEnabled('pkg-A', true);

    expect(
      (await tags.getAllTags()).map((tag) => tag.name).toSet(),
      {'A 标签', 'B 标签'},
    );
    expect(
      (await anki.getKnowledgePoints()).map((point) => point.title).toSet(),
      {'A 知识点', 'B 知识点'},
    );
    expect(
      (await maps.getMindMaps()).map((map) => map.title).toSet(),
      {'A 导图', 'B 导图'},
    );
    // 内容还在库里，只是刚才被查询过滤掉了。
    expect(
      (await anki.getKnowledgePoints(includeDisabledPackages: true)).length,
      2,
    );
  });

  test('手动创建的内容没有 package_items 归属，包禁用不影响它', () async {
    await importTwo();
    final manualTag = await tags.createTag(name: '手动标签');
    final manualPoint = await anki.createKnowledgePoint(
      title: '手动知识点',
      content: '用户自己写的知识点。',
    );
    final manualMap = await maps.createMindMap('手动导图');

    await packages.setPackageEnabled('pkg-A', false);

    expect(
      (await tags.getAllTags()).map((tag) => tag.id),
      contains(manualTag.id),
    );
    expect(
      (await anki.getKnowledgePoints()).map((point) => point.id),
      contains(manualPoint.id),
    );
    expect(
      (await maps.getMindMaps()).map((map) => map.id),
      contains(manualMap.id),
    );
    // 手动标签仍可用（没有包归属）——禁用包不会让它变灰或消失。
    expect(
      (await tags.getAllTags()).map((tag) => tag.name),
      contains('手动标签'),
    );
  });

  test('多包共有的对象：任一包启用即可见，全部禁用才隐藏', () async {
    await importTwo();
    final sharedKpId = await kpIdOf('A 知识点');
    // B 也「拥有」A 导入的同一个知识点（同一本地对象、两个包归属）。
    await packages.addPackageItem(
      packageId: 'pkg-B',
      objectType: 'knowledge_point',
      objectId: sharedKpId,
      externalId: 'kp-shared',
    );

    await packages.setPackageEnabled('pkg-A', false);
    expect(
      (await anki.getKnowledgePoints()).map((point) => point.id),
      contains(sharedKpId),
      reason: 'B 仍启用，共有对象必须可见',
    );

    await packages.setPackageEnabled('pkg-B', false);
    expect(
      (await anki.getKnowledgePoints()).map((point) => point.id),
      isNot(contains(sharedKpId)),
      reason: '所有拥有它的包都禁用后才隐藏',
    );

    await packages.setPackageEnabled('pkg-B', true);
    expect(
      (await anki.getKnowledgePoints()).map((point) => point.id),
      contains(sharedKpId),
    );
  });

  test('禁用的包只隐藏它独占的标签：手动标签挂在包标签下也不会被藏', () async {
    await importTwo();
    final packageTagId = await tagIdOf('A 标签');
    final child = await tags.createTag(name: '手动子标签', parentId: packageTagId);
    final manual = await tags.createTag(name: '手动平级标签');

    await packages.setPackageEnabled('pkg-A', false);

    final visible = await tags.getAllTags();
    final ids = visible.map((tag) => tag.id).toSet();
    expect(ids, isNot(contains(packageTagId)));
    expect(ids, contains(child.id), reason: '手动子标签本身没有包归属');
    expect(ids, contains(manual.id));
  });

  test('题库读表按 package_items(object_type=question) 过滤，手动题不受影响', () async {
    await importTwo();
    await insertQuestion('q-pkg', 'A 包里的题');
    await insertQuestion('q-manual', '用户手动录入的题');
    await packages.addPackageItem(
      packageId: 'pkg-A',
      objectType: 'question',
      objectId: 'q-pkg',
      externalId: 'Q-A-1',
    );

    final before = await readQuestionLibrary(db, limit: 0);
    expect(
      before.entries.map((entry) => entry.questionId).toSet(),
      {'q-pkg', 'q-manual'},
    );

    await packages.setPackageEnabled('pkg-A', false);
    final after = await readQuestionLibrary(db, limit: 0);
    expect(
      after.entries.map((entry) => entry.questionId).toSet(),
      {'q-manual'},
      reason: '被禁用包独占的题不出现，手动题照常出现',
    );

    final unfiltered =
        await readQuestionLibrary(db, limit: 0, includeDisabledPackages: true);
    expect(
      unfiltered.entries.map((entry) => entry.questionId).toSet(),
      {'q-pkg', 'q-manual'},
      reason: '旁路参数给出完整内容（整库导出这类调用方用）',
    );

    await packages.setPackageEnabled('pkg-A', true);
    expect(
      (await readQuestionLibrary(db, limit: 0))
          .entries
          .map((entry) => entry.questionId)
          .toSet(),
      {'q-pkg', 'q-manual'},
    );
  });

  test('导图/标签/知识点的禁用集合与 PackageVisibility 读法一致', () async {
    await importTwo();
    await packages.setPackageEnabled('pkg-A', false);

    final visibility = await loadPackageVisibility(db);
    expect(
      visibility.isHidden('tag', await tagIdOf('A 标签')),
      isTrue,
    );
    expect(
      visibility.isHidden('knowledge_point', await kpIdOf('A 知识点')),
      isTrue,
    );
    expect(visibility.isHidden('tag', await tagIdOf('B 标签')), isFalse);

    final enabledOnly = await loadPackageVisibility(
      db,
      includeDisabledPackages: true,
    );
    expect(enabledOnly.isEmpty, isTrue);
  });

  test('整库导出仍包含被禁用包的内容（禁用只影响浏览查询）', () async {
    await importTwo();
    await packages.setPackageEnabled('pkg-A', false);

    final manifest = await exportService.buildManifest();

    expect(
      manifest.tags.map((tag) => tag.name).toSet(),
      {'A 标签', 'B 标签'},
    );
    expect(
      manifest.knowledgePoints.map((point) => point.title).toSet(),
      {'A 知识点', 'B 知识点'},
    );
    expect(
      manifest.mindMaps.map((map) => map.title).toSet(),
      {'A 导图', 'B 导图'},
    );
  });
}
