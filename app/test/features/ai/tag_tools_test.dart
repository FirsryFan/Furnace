import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/anki_repository.dart';
import 'package:furnace/data/repositories/tag_repository.dart';
import 'package:furnace/data/repositories/task_repository.dart';
import 'package:furnace/data/repositories/time_block_repository.dart';
import 'package:furnace/features/ai/domain/ai_tool.dart';
import 'package:furnace/features/ai/domain/tool_registry.dart';
import 'package:furnace/features/ai/tools/tag_tools.dart';

/// The AI's write path into the tag tree.
///
/// The tree is the part that needs testing: a tag under the wrong parent is a
/// different tag with a different path, so "the parent could not be resolved"
/// has to be a refusal rather than a silent creation at the top level.
void main() {
  late AppDatabase db;
  late TagRepository tags;
  late CreateTagsTool tool;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    tags = TagRepository(db);
    tool = CreateTagsTool(tags);
  });

  tearDown(() async {
    await db.close();
  });

  Future<ToolResult> call(Map<String, Object?> arguments) {
    return tool.run(ToolInvocation(
      toolName: CreateTagsTool.toolName,
      action: CreateTagsTool.toolName,
      arguments: arguments,
    ));
  }

  Map<String, Object?> resultOf(ToolResult result) =>
      (result.modelResult! as Map).cast<String, Object?>();

  List<Map<String, Object?>> createdOf(ToolResult result) => [
        for (final item in resultOf(result)['created']! as List)
          (item as Map).cast<String, Object?>(),
      ];

  test('creates a top-level tag and reports its path and id', () async {
    final result = await call({
      'tags': [
        {'name': '物理'},
      ],
    });

    expect(result.ok, isTrue);
    expect(result.summary, contains('物理'));
    final created = createdOf(result).single;
    expect(created['path'], '物理');
    expect(await tags.getTagById(created['id']! as String), isNotNull);
  });

  test('creates a child under a parent given by path, and by id', () async {
    final physics = await tags.createTag(name: '物理');

    final byPath = await call({
      'tags': [
        {'name': '力学', 'parent_path': '物理'},
      ],
    });
    final byId = await call({
      'tags': [
        {'name': '光学', 'parent_id': physics.id},
      ],
    });

    expect(byPath.ok, isTrue);
    expect(createdOf(byPath).single['path'], '物理/力学');
    expect(byId.ok, isTrue);
    expect(createdOf(byId).single['path'], '物理/光学');
  });

  test('refuses an unknown parent instead of creating at the top level',
      () async {
    final result = await call({
      'tags': [
        {'name': '力学', 'parent_path': '物理/力学/不存在'},
      ],
    });

    expect(result.ok, isFalse);
    expect(result.error, contains('找不到路径'));
    expect(await tags.getAllTags(), isEmpty);
  });

  test('creates several tags in one call', () async {
    final result = await call({
      'tags': [
        {'name': '化学'},
        {'name': '生物'},
      ],
    });

    expect(result.ok, isTrue);
    expect(result.summary, contains('2 个标签'));
    expect(createdOf(result), hasLength(2));
    expect((await tags.getAllTags()).map((tag) => tag.name),
        containsAll(['化学', '生物']));
  });

  test('a duplicate sibling name gets a suffix instead of failing', () async {
    await tags.createTag(name: '物理');

    final result = await call({
      'tags': [
        {'name': '物理'},
      ],
    });

    expect(result.ok, isTrue);
    expect(createdOf(result).single['path'], '物理-2');
  });

  test('undo removes exactly what the call created', () async {
    final existing = await tags.createTag(name: '数学');
    final result = await call({
      'tags': [
        {'name': '物理'},
        {'name': '力学', 'parent_path': '物理'},
      ],
    });
    final physicsId = createdOf(result).first['id']! as String;
    expect(await tags.getAllTags(), hasLength(3));

    var undone = false;
    final decoded = result.afterJson;
    if (decoded != null) {
      undone = await deleteCreatedTags(
        db,
        (jsonDecode(decoded) as Map).cast<String, Object?>(),
      );
    }

    expect(undone, isTrue);
    final left = await tags.getAllTags();
    expect(
      left.map((tag) => tag.id),
      [existing.id],
      reason: 'the subtree goes with the parent; the pre-existing tag stays',
    );
  });

  test('empty and oversized batches are refused', () async {
    expect((await call({'tags': const []})).ok, isFalse);
    final tooMany = await call({
      'tags': [
        for (var i = 0; i < CreateTagsTool.maxTagsPerCall + 1; i++)
          {'name': '标签$i'},
      ],
    });
    expect(tooMany.ok, isFalse);
    expect(tooMany.error, contains('最多创建'));
    expect(await tags.getAllTags(), isEmpty);
  });

  test('a name containing / is refused', () async {
    final result = await call({
      'tags': [
        {'name': '物理/力学'},
      ],
    });

    expect(result.ok, isFalse);
    expect(result.error, contains('不能含 /'));
  });

  test('it is registered, writable and reversible', () {
    final registry = ToolRegistry.forApp(
      db: db,
      tasks: TaskRepository(db),
      blocks: TimeBlockRepository(db),
      anki: AnkiRepository(db),
      tags: tags,
    );

    expect(registry.byName(CreateTagsTool.toolName), isA<CreateTagsTool>());
    expect(tool.riskFor('create_tags'), ToolRisk.write);
    expect(tool.reversibleFor('create_tags'), isTrue);
    expect(tool.readOnly, isFalse);
  });
}
