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
import 'package:furnace/features/ai/tools/deletion_tools.dart';

/// The AI's delete path.
///
/// Two properties are what make a destructive tool acceptable at all, so they
/// are what this file tests: the model can never delete the wrong row by
/// guessing a name, and every deletion can be put back exactly as it was.
void main() {
  late AppDatabase db;
  late TagRepository tags;
  late AnkiRepository anki;
  late TaskRepository tasks;
  late DeleteContentTool tool;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    tags = TagRepository(db);
    anki = AnkiRepository(db);
    tasks = TaskRepository(db);
    tool = DeleteContentTool(db: db, anki: anki, tags: tags);
  });

  tearDown(() async {
    await db.close();
  });

  Future<ToolResult> call(Map<String, Object?> arguments) {
    return tool.run(ToolInvocation(
      toolName: DeleteContentTool.toolName,
      action: DeleteContentTool.toolName,
      arguments: arguments,
    ));
  }

  /// Undo, through the same entry point the agent loop uses.
  Future<bool> undo(ToolResult result) async {
    final decoded = jsonDecode(result.beforeJson!);
    return restoreDeletedContent(db, (decoded as Map).cast<String, Object?>());
  }

  Future<List<String>> tagIds() async =>
      [for (final tag in await tags.getAllTags()) tag.id];

  Future<int> reviewLogCount() async =>
      (await db.select(db.reviewLogs).get()).length;

  /// The repository has no by-id card-state getter, so the test reads the table
  /// directly - the assertion is about rows, not about a repository API.
  Future<CardState?> cardState(String id) =>
      (db.select(db.cardStates)..where((t) => t.id.equals(id)))
          .getSingleOrNull();

  group('registration', () {
    test('is in the app registry and destructive for every kind', () {
      final registry = ToolRegistry.forApp(
        db: db,
        tasks: tasks,
        blocks: TimeBlockRepository(db),
        anki: anki,
        tags: tags,
      );

      expect(registry.byName(DeleteContentTool.toolName), isNotNull);
      expect(
        registry.modelSpecs.map((spec) => spec.name),
        contains(DeleteContentTool.toolName),
      );
      for (final kind in DeleteContentTool.kinds) {
        expect(tool.riskFor(kind), ToolRisk.destructive);
        expect(tool.reversibleFor(kind), isTrue);
      }
    });
  });

  group('deleting a tag', () {
    test('takes the subtree and its links, and undo puts all of it back',
        () async {
      final task = await tasks.createTask(title: '写作业');
      final root = await tags.createTag(name: '物理');
      final child = await tags.createTag(name: '力学', parentId: root.id);
      final grandChild = await tags.createTag(name: '牛顿', parentId: child.id);
      await tags.addTagToObject(
        tagId: child.id,
        objectType: 'task',
        objectId: task.id,
      );

      final result = await call({'kind': 'tag', 'name': '物理'});

      expect(result.ok, isTrue);
      expect(result.summary, contains('物理'));
      expect(result.summary, contains('2 个子标签'));
      expect(result.isUndoable, isTrue);
      expect(await tagIds(), isEmpty);
      expect(
        await tags.tagsForObject(objectType: 'task', objectId: task.id),
        isEmpty,
        reason: 'object links die with the tag',
      );

      expect(await undo(result), isTrue);

      expect(await tagIds(), containsAll([root.id, child.id, grandChild.id]));
      final restored = await tags.getTagById(grandChild.id);
      expect(restored, isNotNull);
      expect(restored!.parentId, child.id, reason: 'the tree shape comes back');
      final links = await tags.tagsForObject(
        objectType: 'task',
        objectId: task.id,
      );
      expect(links.map((tag) => tag.id), [child.id]);
    });

    test('deletes by id as well as by name', () async {
      final tag = await tags.createTag(name: '化学');

      final result = await call({'kind': 'tag', 'id': tag.id});

      expect(result.ok, isTrue);
      expect(await tagIds(), isEmpty);
    });

    test('refuses an ambiguous name and lists the candidates', () async {
      final physics = await tags.createTag(name: '物理');
      final other = await tags.createTag(name: '其他');
      final twin = await tags.createTag(name: '物理', parentId: other.id);

      final result = await call({'kind': 'tag', 'name': '物理'});

      expect(result.ok, isFalse);
      expect(result.error, contains('匹配到 2 个标签'));
      expect(result.error, contains(physics.id));
      expect(result.error, contains(twin.id));
      expect(await tagIds(), hasLength(3), reason: 'nothing was deleted');
    });

    test('refuses a name that does not exist', () async {
      await tags.createTag(name: '物理');

      final result = await call({'kind': 'tag', 'name': '不存在的标签'});

      expect(result.ok, isFalse);
      expect(result.error, contains('找不到'));
      expect(await tagIds(), hasLength(1));
    });
  });

  group('deleting a card', () {
    test('removes the template, its state and its review log; undo restores',
        () async {
      final point = await anki.createKnowledgePoint(
        title: '牛顿第一定律',
        content: '物体在不受外力时保持原状态。',
      );
      final card = await anki.createTemplate(
        knowledgePointId: point.id,
        type: 'essay',
        question: '牛顿第一定律说的是什么？',
        answer: '不受外力时保持静止或匀速直线运动。',
      );
      final state = await anki.getOrCreateCardState(card.id);
      await anki.addReviewLog(
        cardStateId: state.id,
        cardTemplateId: card.id,
        rating: 3,
        reviewedAt: DateTime.now().millisecondsSinceEpoch,
      );
      expect(await reviewLogCount(), 1);

      final result = await call({
        'kind': 'card',
        'question': '牛顿第一定律说的是什么？',
      });

      expect(result.ok, isTrue);
      expect(await anki.getCardTemplateById(card.id), isNull);
      expect(await cardState(state.id), isNull);
      expect(await reviewLogCount(), 0);
      expect(
        await anki.getKnowledgePointById(point.id),
        isNotNull,
        reason: 'deleting one card leaves the flashcard in place',
      );

      expect(await undo(result), isTrue);

      expect(await anki.getCardTemplateById(card.id), isNotNull);
      expect(
        (await cardState(state.id))?.cardTemplateId,
        card.id,
        reason: 'the review state is part of the snapshot, not a casualty',
      );
      expect(await reviewLogCount(), 1, reason: 'the study history comes back');
    });

    test('refuses an ambiguous question', () async {
      final point = await anki.createKnowledgePoint(title: '点', content: '内容');
      await anki.createTemplate(
        knowledgePointId: point.id,
        type: 'essay',
        question: '同一个问题？',
        answer: '一',
      );
      await anki.createTemplate(
        knowledgePointId: point.id,
        type: 'essay',
        question: '同一个问题？',
        answer: '二',
      );

      final result = await call({'kind': 'card', 'question': '同一个问题？'});

      expect(result.ok, isFalse);
      expect(result.error, contains('匹配到 2 张卡片'));
      expect(await anki.getTemplatesForKnowledgePoint(point.id), hasLength(2));
    });
  });

  group('deleting a flashcard', () {
    test('takes its cards, states and logs; undo restores all of it', () async {
      final point = await anki.createKnowledgePoint(
        title: '光合作用',
        content: '主要场所是叶绿体。',
      );
      final first = await anki.createTemplate(
        knowledgePointId: point.id,
        type: 'fill_blank',
        question: '光合作用的主要场所是____。',
        answer: '叶绿体',
      );
      final second = await anki.createTemplate(
        knowledgePointId: point.id,
        type: 'essay',
        question: '光合作用的意义？',
        answer: '把光能转成化学能。',
      );
      final firstState = await anki.getOrCreateCardState(first.id);
      final secondState = await anki.getOrCreateCardState(second.id);
      await anki.addReviewLog(
        cardStateId: firstState.id,
        cardTemplateId: first.id,
        rating: 3,
        reviewedAt: DateTime.now().millisecondsSinceEpoch,
      );

      final result = await call({'kind': 'flashcard', 'title': '光合作用'});

      expect(result.ok, isTrue);
      expect(result.summary, contains('含 2 张卡片'));
      expect(await anki.getKnowledgePointById(point.id), isNull);
      expect(await anki.getTemplatesForKnowledgePoint(point.id), isEmpty);
      expect(await cardState(firstState.id), isNull);

      expect(await undo(result), isTrue);

      expect(await anki.getKnowledgePointById(point.id), isNotNull);
      final restoredTemplates =
          await anki.getTemplatesForKnowledgePoint(point.id);
      expect(restoredTemplates.map((t) => t.id), containsAll([first.id, second.id]));
      expect(
        (await cardState(secondState.id))?.cardTemplateId,
        second.id,
      );
      expect(await reviewLogCount(), 1);
    });

    test('refuses a title that matches nothing', () async {
      await anki.createKnowledgePoint(title: '光合作用', content: '内容');

      final result = await call({'kind': 'flashcard', 'title': '呼吸作用'});

      expect(result.ok, isFalse);
      expect(result.error, contains('找不到'));
      expect(
        (await anki.getKnowledgePoints()).map((p) => p.title),
        ['光合作用'],
      );
    });
  });

  group('arguments', () {
    test('an unknown kind is refused without touching anything', () async {
      final result = await call({'kind': 'everything'});

      expect(result.ok, isFalse);
      expect(result.error, contains('不支持的 kind'));
    });

    test('a missing locator is refused', () async {
      final result = await call({'kind': 'tag'});

      expect(result.ok, isFalse);
      expect(result.error, contains('需要 id 或 name'));
    });
  });
}
