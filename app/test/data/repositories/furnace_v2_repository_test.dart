import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/anki_repository.dart';
import 'package:furnace/data/repositories/tag_repository.dart';
import 'package:furnace/data/repositories/task_repository.dart';
import 'package:furnace/data/repositories/thread_state_repository.dart';

void main() {
  late AppDatabase db;
  late TagRepository tags;
  late TaskRepository tasks;
  late AnkiRepository anki;
  late ThreadStateRepository thread;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    tags = TagRepository(db);
    tasks = TaskRepository(db);
    anki = AnkiRepository(db);
    thread = ThreadStateRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('Thread state (spec 1.1.3)', () {
    test('persists energy and goal with timestamp', () async {
      await thread.updateState(
        energy: 4,
        goalText: '复习数学',
        goalNodeId: 'node-9',
        goalPath: '学科/数学',
      );
      final state = await thread.getState();
      expect(state!.energy, 4);
      expect(state.goalText, '复习数学');
      expect(state.goalNodeId, 'node-9');
      expect(state.updatedAt, isNotNull);
    });

    test('staleness works on missing and old state', () async {
      expect(await thread.isStale(const Duration(hours: 2)), isTrue);
      await thread.updateState(
        energy: 8,
        updatedAt: DateTime.now().subtract(const Duration(hours: 3)),
      );
      expect(await thread.isStale(const Duration(hours: 2)), isTrue);
      await thread.updateState(energy: 9);
      expect(await thread.isStale(const Duration(hours: 2)), isFalse);
    });

    test('can clear goal fields', () async {
      await thread.updateState(energy: 5, goalText: 'x', goalNodeId: 'n');
      await thread.updateState(goalText: null, clearGoal: true);
      final state = await thread.getState();
      expect(state!.goalText, isNull);
      expect(state.goalNodeId, isNull);
      expect(state.energy, 5);
    });
  });

  group('Tag tree (spec 1.1.2 / D3)', () {
    test('creates hierarchical tags with authoritative paths', () async {
      final culture = await tags.createTag(name: '文化课');
      final subject =
          await tags.createTag(name: '学科', parentId: culture.id);
      final lang = await tags.createTag(name: '语文', parentId: subject.id);
      final essay = await tags.createTag(name: '作文', parentId: lang.id);
      expect(essay.path, '文化课/学科/语文/作文');
      expect(lang.path, '文化课/学科/语文');
    });

    test('duplicate sibling names get suffixed', () async {
      final a = await tags.createTag(name: '阅读');
      final b = await tags.createTag(name: '阅读');
      expect(a.path, '阅读');
      expect(b.path, '阅读-2');
    });

    test('rename cascades paths down the subtree', () async {
      final top = await tags.createTag(name: '文化课');
      final lang = await tags.createTag(name: '语文', parentId: top.id);
      final essay = await tags.createTag(name: '作文', parentId: lang.id);
      expect(essay.path, '文化课/语文/作文');
      await tags.renameTag(lang.id, '中文');
      final after = await tags.getTagByPath('文化课/中文/作文');
      expect(after, isNotNull);
      expect(after!.parentId, lang.id);
      expect(await tags.getTagByPath('文化课/中文'), isNotNull);
    });

    test('move reparents and refreshes paths; cycles rejected', () async {
      final a = await tags.createTag(name: 'a');
      final b = await tags.createTag(name: 'b');
      final a1 = await tags.createTag(name: 'a1', parentId: a.id);
      final a2 = await tags.createTag(name: 'a2', parentId: a.id);
      await tags.moveTag(a1.id, b.id);
      expect((await tags.getTagById(a1.id))!.path, 'b/a1');
      await expectLater(
        tags.moveTag(a.id, a2.id),
        throwsArgumentError,
      );
      // A cycle move must leave the tree untouched.
      expect((await tags.getTagById(a.id))!.parentId, isNull);
    });

    test('subtree query and delete', () async {
      final top = await tags.createTag(name: 'top');
      final mid = await tags.createTag(name: 'mid', parentId: top.id);
      final leaf = await tags.createTag(name: 'leaf', parentId: mid.id);
      await tags.addTagToObject(
        tagId: leaf.id,
        objectType: 'task',
        objectId: 'some-task',
      );
      final under = await tags.getTagsUnderPath('top');
      expect(under.map((t) => t.id), containsAll([top.id, mid.id, leaf.id]));
      await tags.deleteTag(top.id);
      expect(await tags.getTagById(mid.id), isNull);
      expect(
        await tags.tagsForObject(objectType: 'task', objectId: 'some-task'),
        isEmpty,
      );
    });
  });

  group('Task v2 fields and completion history (D7)', () {
    test('creates and clears v2 fields', () async {
      final task = await tasks.createTask(
        title: '写实验报告',
        expectedAt: 1700000000000,
        energyRequired: 7,
        estimateMinutes: 40,
      );
      expect(task.expectedAt, 1700000000000);
      expect(task.energyRequired, 7);
      await tasks.updateTask(
        task.id,
        clearExpectedAt: true,
        clearEnergyRequired: true,
      );
      final after = await tasks.getTaskById(task.id);
      expect(after!.expectedAt, isNull);
      expect(after.energyRequired, isNull);
    });

    test('completing a task writes a completion log snapshot', () async {
      final tag = await tags.createTag(name: '物理');
      final task = await tasks.createTask(
        title: '错题本物理',
        estimateMinutes: 20,
      );
      await tasks.completeTask(
        task.id,
        tagIds: [tag.id],
        tagPaths: [tag.path!],
      );
      final done = await tasks.getTaskById(task.id);
      expect(done!.status, 'done');
      expect(done.completedAt, isNotNull);
      final logs = await tasks.getCompletionLogs();
      expect(logs, hasLength(1));
      expect(logs.single.taskId, task.id);
      expect(logs.single.title, '错题本物理');
      expect(logs.single.tagPaths, tag.path);
    });
  });

  group('Presentation units / cloze / boosts (v2 Knowledge)', () {
    test('unit card states are idempotent per (kp, unitKey)', () async {
      final kp = await anki.createKnowledgePoint(
        title: '词条',
        content: '内容',
      );
      final first = await anki.getOrCreateUnitCardState(kp.id, 'cloze:slot-a');
      final second =
          await anki.getOrCreateUnitCardState(kp.id, 'cloze:slot-a');
      expect(first.id, second.id);
      expect(first.knowledgePointId, kp.id);
      expect(first.unitKey, 'cloze:slot-a');

      await anki.updateUnitCardState(
        first.id,
        stability: 1.2,
        difficulty: 5.0,
        dueAt: 1700000000000,
        forced: 1,
        forcedStreak: 0,
      );
      final after = await anki.unitCardState(kp.id, 'cloze:slot-a');
      expect(after!.stability, 1.2);
      expect(after.difficulty, 5.0);
      expect(after.forced, 1);
    });

    test('cloze slot history tracks used slot keys', () async {
      final kp = await anki.createKnowledgePoint(title: 'kp', content: 'c');
      final slot =
          await anki.createClozeSlot(knowledgePointId: kp.id, slotKey: 'c0', definition: '{}');
      expect(slot.exhausted, 0);
      await anki.addClozeHistory(
        knowledgePointId: kp.id,
        slotKey: 'c0',
        correct: 0,
        usedAt: 1700000000000,
      );
      expect(await anki.usedClozeSlotKeys(kp.id), {'c0'});
      await anki.markClozeSlotExhausted(slot.id);
      final after = await anki.clozeSlotsForKnowledgePoint(kp.id);
      expect(after.single.exhausted, 1);
    });

    test('boost upsert keeps max factor and resets cycles', () async {
      final kp = await anki.createKnowledgePoint(title: 'kp', content: 'c');
      await anki.upsertBoost(knowledgePointId: kp.id, factor: 1.3);
      await anki.upsertBoost(knowledgePointId: kp.id, factor: 1.8);
      final boost = await anki.boostFor(kp.id);
      expect(boost!.factor, 1.8);
      expect(boost.remainingCycles, 3);
      await anki.deleteBoost(kp.id);
      expect(await anki.boostFor(kp.id), isNull);
    });
  });
}
