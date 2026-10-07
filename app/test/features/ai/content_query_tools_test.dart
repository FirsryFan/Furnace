import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/ai_repository.dart';
import 'package:furnace/data/repositories/anki_repository.dart';
import 'package:furnace/data/repositories/tag_repository.dart';
import 'package:furnace/data/repositories/task_repository.dart';
import 'package:furnace/data/repositories/time_block_repository.dart';
import 'package:furnace/features/ai/domain/ai_tool.dart';
import 'package:furnace/features/ai/domain/approval_engine.dart';
import 'package:furnace/features/ai/domain/tool_registry.dart';
import 'package:furnace/features/ai/tools/content_query_tools.dart';
import 'package:furnace/features/ai/tools/deletion_tools.dart';

/// "The agent may touch everything; whether it may is the user's choice."
///
/// The tools are only half of that sentence. This file covers the other half:
/// the agent can *find* what to act on (which is what made deletion unusable
/// before), and looking never costs the user a confirmation while deleting
/// always does.
void main() {
  late AppDatabase db;
  late TagRepository tags;
  late AnkiRepository anki;
  late TaskRepository tasks;
  late QueryContentTool query;
  late DeleteContentTool delete;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    tags = TagRepository(db);
    anki = AnkiRepository(db);
    tasks = TaskRepository(db);
    query = QueryContentTool(db: db, anki: anki, tags: tags);
    delete = DeleteContentTool(db: db, anki: anki, tags: tags);
  });

  tearDown(() async {
    await db.close();
  });

  Future<ToolResult> run(AiTool tool, Map<String, Object?> arguments) {
    return tool.run(ToolInvocation(
      toolName: tool.name,
      action: tool.name,
      arguments: arguments,
    ));
  }

  Map<String, Object?> resultOf(ToolResult result) =>
      (result.modelResult! as Map).cast<String, Object?>();

  List<Map<String, Object?>> itemsOf(ToolResult result) => [
        for (final item in resultOf(result)['items']! as List)
          (item as Map).cast<String, Object?>(),
      ];

  group('the agent can see what it is about to change', () {
    test('tags come back with path, parent and id', () async {
      final root = await tags.createTag(name: '物理');
      final child = await tags.createTag(name: '力学', parentId: root.id);
      final task = await tasks.createTask(title: '写作业');
      await tags.addTagToObject(
        tagId: child.id,
        objectType: 'task',
        objectId: task.id,
      );

      final result = await run(query, {'kind': 'tag'});

      expect(result.ok, isTrue);
      final items = itemsOf(result);
      expect(items, hasLength(2));
      // Sorted by path: the tree reads top-down.
      expect(items.first['name'], '物理');
      final mechanics = items.last;
      expect(mechanics['id'], child.id);
      expect(mechanics['parent_id'], root.id);
      expect(mechanics['path'], '物理/力学');
      expect(mechanics['linked_objects'], 1);
    });

    test('flashcards come back with their card count', () async {
      final point = await anki.createKnowledgePoint(
        title: '光合作用',
        content: '主要场所是叶绿体。',
        source: '课本 P32',
      );
      await anki.createTemplate(
        knowledgePointId: point.id,
        type: 'essay',
        question: '意义？',
        answer: '把光能转成化学能。',
      );

      final result = await run(query, {'kind': 'flashcard'});

      final item = itemsOf(result).single;
      expect(item['id'], point.id);
      expect(item['title'], '光合作用');
      expect(item['source'], '课本 P32');
      expect(item['card_count'], 1);
    });

    test('cards name the flashcard they belong to', () async {
      final point = await anki.createKnowledgePoint(title: '牛顿', content: 'F=ma');
      final card = await anki.createTemplate(
        knowledgePointId: point.id,
        type: 'essay',
        question: '第二定律说的是什么？',
        answer: 'F=ma',
      );

      final result = await run(query, {'kind': 'card'});

      final item = itemsOf(result).single;
      expect(item['id'], card.id);
      expect(item['flashcard_id'], point.id);
      expect(item['flashcard_title'], '牛顿');
      expect(item['question'], '第二定律说的是什么？');
    });

    test('filter narrows the list, case-insensitively', () async {
      await tags.createTag(name: 'Physics');
      await tags.createTag(name: '化学');

      final result = await run(query, {'kind': 'tag', 'filter': 'phys'});

      expect(itemsOf(result).map((item) => item['name']), ['Physics']);
    });

    test('limit caps the rows and says how many there are', () async {
      for (var i = 0; i < 5; i++) {
        await tags.createTag(name: '标签$i');
      }

      final result = await run(query, {'kind': 'tag', 'limit': 2});

      final body = resultOf(result);
      expect(body['count'], 5);
      expect(body['returned'], 2);
      expect(result.summary, contains('前 2 个'));
    });

    test('an unknown kind is refused', () async {
      final result = await run(query, {'kind': 'everything'});

      expect(result.ok, isFalse);
      expect(result.error, contains('不支持的 kind'));
    });
  });

  group('looking is free, deleting is not', () {
    test('a read-only tool never needs confirmation, in either mode', () {
      for (final mode in AiPermissionMode.values) {
        final decision = ApprovalEngine(mode: mode)
            .forInvocation(query, {'kind': 'tag'});
        expect(
          decision.disposition,
          ToolDisposition.executeNow,
          reason: 'reading is not acting ($mode)',
        );
        expect(decision.reason, contains('只读'));
      }
    });

    test('the delete tool always needs one-by-one confirmation', () {
      for (final mode in AiPermissionMode.values) {
        final decision = ApprovalEngine(mode: mode)
            .forInvocation(delete, {'kind': 'tag', 'name': '物理'});
        expect(decision.disposition, ToolDisposition.individualApproval);
      }
    });

    test('the previously read-only tools declare themselves too', () {
      final registry = ToolRegistry.forApp(
        db: db,
        tasks: tasks,
        blocks: TimeBlockRepository(db),
        anki: anki,
        tags: tags,
      );

      for (final name in const [
        'query_tasks',
        'query_schedule',
        'evaluate_problem_fit',
        'fetch_page',
        'query_content',
      ]) {
        expect(registry.byName(name)!.readOnly, isTrue, reason: name);
      }
      for (final name in const [
        'manage_task',
        'manage_time_block',
        'create_knowledge_cards',
        'delete_content',
      ]) {
        expect(registry.byName(name)!.readOnly, isFalse, reason: name);
      }
    });
  });

  group('the pair actually works end to end', () {
    test('query returns an id that the delete tool accepts', () async {
      final point = await anki.createKnowledgePoint(
        title: '光合作用',
        content: '主要场所是叶绿体。',
      );
      await anki.createTemplate(
        knowledgePointId: point.id,
        type: 'essay',
        question: '场所？',
        answer: '叶绿体',
      );

      // 1. what the model does first: find it.
      final found = await run(query, {'kind': 'flashcard', 'filter': '光合'});
      final id = itemsOf(found).single['id']! as String;

      // 2. then act on the id it was given.
      final deleted = await run(delete, {'kind': 'flashcard', 'id': id});

      expect(deleted.ok, isTrue);
      expect(await anki.getKnowledgePointById(id), isNull);
      expect(deleted.beforeJson, isNotNull, reason: 'still undoable');
    });

    test('a partial name is enough when it is unique, and refused when not',
        () async {
      final exact = await tags.createTag(name: '物理');

      // Unique partial match: usable, because the confirmation names it.
      final ok = await run(delete, {'kind': 'tag', 'name': '物'});
      expect(ok.ok, isTrue);
      expect(await tags.getTagById(exact.id), isNull);

      // Two loose matches and no exact one: refused, with the candidates.
      final competition = await tags.createTag(name: '化学竞赛');
      final experiment = await tags.createTag(name: '化学实验');
      final refused = await run(delete, {'kind': 'tag', 'name': '化学'});
      expect(refused.ok, isFalse);
      expect(refused.error, contains('匹配到 2 个标签'));
      expect(refused.error, contains('query_content'));
      expect(await tags.getTagById(competition.id), isNotNull);
      expect(await tags.getTagById(experiment.id), isNotNull);
    });

    test('an exact name still wins over a longer partial match', () async {
      final exact = await tags.createTag(name: '化学');
      final longer = await tags.createTag(name: '化学竞赛');

      final result = await run(delete, {'kind': 'tag', 'name': '化学'});

      expect(result.ok, isTrue);
      expect(
        await tags.getTagById(exact.id),
        isNull,
        reason: 'the exact hit is the one the user named',
      );
      expect(await tags.getTagById(longer.id), isNotNull);
    });
  });
}
