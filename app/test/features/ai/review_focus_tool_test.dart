import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/anki_repository.dart';
import 'package:furnace/data/repositories/tag_repository.dart';
import 'package:furnace/data/repositories/task_repository.dart';
import 'package:furnace/data/repositories/time_block_repository.dart';
import 'package:furnace/features/ai/domain/ai_tool.dart';
import 'package:furnace/features/ai/domain/tool_registry.dart';
import 'package:furnace/features/ai/tools/card_group_tools.dart'
    show kKnowledgePointObjectType;
import 'package:furnace/features/ai/tools/review_focus_tool.dart';

/// User request (2026-10-26): "下周要考试，某些板块内容要进入复习，就提前进来"——
/// 对 AI 说一句话，就把某个卡组（标签子树）下未来 N 天内到期的卡提前到今天。
///
/// 这里钉的是工具的**副作用边界**：dry_run 不写库、apply 只改 due_at、
/// undo 能逐张写回、子树与 days/limit 生效、新卡与已到期卡不动。
void main() {
  final now = DateTime(2026, 10, 26, 20);
  final nowMs = now.millisecondsSinceEpoch;
  const dayMs = 86400000;

  late AppDatabase db;
  late TagRepository tags;
  late AnkiRepository anki;
  late ReviewFocusTool tool;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    tags = TagRepository(db);
    anki = AnkiRepository(db);
    tool = ReviewFocusTool(
      db: db,
      anki: anki,
      tags: tags,
      clock: () => now,
    );
  });

  tearDown(() async {
    await db.close();
  });

  Future<ToolResult> run(Map<String, Object?> arguments) {
    return tool.run(ToolInvocation(
      toolName: tool.name,
      action: tool.name,
      arguments: arguments,
    ));
  }

  Map<String, Object?> bodyOf(ToolResult result) =>
      (result.modelResult! as Map).cast<String, Object?>();

  Map<String, Object?> countsOf(ToolResult result) =>
      (bodyOf(result)['counts']! as Map).cast<String, Object?>();

  /// 建一个知识点、挂到 [tag] 上，再建一张已学过的卡与它 [dueIn] 到期。
  Future<CardState> seedCard({
    required Tag tag,
    required String title,
    required Duration dueIn,
    int repetitions = 3,
  }) async {
    final point = await anki.createKnowledgePoint(
      title: title,
      content: '正文',
    );
    await tags.addTagToObject(
      tagId: tag.id,
      objectType: kKnowledgePointObjectType,
      objectId: point.id,
    );
    final state = await anki.getOrCreateUnitCardState(point.id, 'essay');
    await anki.updateUnitCardState(
      state.id,
      repetitions: repetitions,
      state: repetitions <= 0 ? 'new' : 'review',
      dueAt: nowMs + dueIn.inMilliseconds,
    );
    return (await anki.cardStateById(state.id))!;
  }

  group('预览（dry_run 默认）不写库', () {
    test('只报数、不改 due_at、不给 before 快照', () async {
      final root = await tags.createTag(name: '生物');
      final card = await seedCard(
        tag: root,
        title: '细胞膜',
        dueIn: const Duration(days: 3),
      );

      final result = await run({'tag': '生物'});

      expect(result.ok, isTrue);
      expect(result.summary, contains('预览（还没写库）'));
      expect(result.summary, contains('1 张'));
      expect(countsOf(result)['pull'], 1);
      expect(bodyOf(result)['dry_run'], isTrue);
      expect(result.beforeJson, isNull);
      final after = await anki.cardStateById(card.id);
      expect(after!.dueAt, nowMs + 3 * dayMs);
    });
  });

  group('确认之后只改 due_at', () {
    test('拉进今天，返回 undo 快照（原 due_at 逐张记录）', () async {
      final root = await tags.createTag(name: '生物');
      final first = await seedCard(
        tag: root,
        title: '细胞膜',
        dueIn: const Duration(days: 3),
      );
      final second = await seedCard(
        tag: root,
        title: '细胞核',
        dueIn: const Duration(days: 6),
      );

      final result = await run({'tag': '生物', 'dry_run': false});

      expect(result.ok, isTrue);
      expect(result.summary, contains('已把卡组「生物」'));
      expect(countsOf(result)['pull'], 2);
      expect((await anki.cardStateById(first.id))!.dueAt, nowMs);
      expect((await anki.cardStateById(second.id))!.dueAt, nowMs);
      // 记忆状态不动：只写 due_at。
      expect((await anki.cardStateById(first.id))!.repetitions, 3);

      final before =
          (jsonDecode(result.beforeJson!) as Map).cast<String, Object?>();
      expect(await restoreReviewFocus(db, before), isTrue);
      expect((await anki.cardStateById(first.id))!.dueAt, nowMs + 3 * dayMs);
      expect((await anki.cardStateById(second.id))!.dueAt, nowMs + 6 * dayMs);
    });

    test('一张都没拉时不写库、不给 undo 快照', () async {
      final root = await tags.createTag(name: '生物');
      await seedCard(
        tag: root,
        title: '新卡',
        dueIn: const Duration(days: 2),
        repetitions: 0,
      );

      final result = await run({'tag': '生物', 'dry_run': false});

      expect(result.ok, isTrue);
      expect(countsOf(result)['pull'], 0);
      expect(countsOf(result)['new_cards'], 1);
      expect(result.beforeJson, isNull);
    });
  });

  group('范围：标签子树、days、limit', () {
    test('只拉标签子树下的卡，兄弟标签的卡不动', () async {
      final root = await tags.createTag(name: '生物');
      final chapterOne = await tags.createTag(name: '必修1', parentId: root.id);
      final chapterTwo = await tags.createTag(name: '必修2', parentId: root.id);
      final inside = await seedCard(
        tag: chapterOne,
        title: '细胞膜',
        dueIn: const Duration(days: 2),
      );
      final outside = await seedCard(
        tag: chapterTwo,
        title: '遗传',
        dueIn: const Duration(days: 2),
      );

      final result = await run({'tag': '生物/必修1', 'dry_run': false});

      expect(countsOf(result)['pull'], 1);
      expect((await anki.cardStateById(inside.id))!.dueAt, nowMs);
      expect((await anki.cardStateById(outside.id))!.dueAt, nowMs + 2 * dayMs);
    });

    test('days 决定 horizon：默认 7 天，传 3 天则更远的不动', () async {
      final root = await tags.createTag(name: '生物');
      final near = await seedCard(
        tag: root,
        title: '近',
        dueIn: const Duration(days: 2),
      );
      final far = await seedCard(
        tag: root,
        title: '远',
        dueIn: const Duration(days: 20),
      );

      final result = await run({'tag': '生物', 'days': 3, 'dry_run': false});

      expect(countsOf(result)['pull'], 1);
      expect(countsOf(result)['too_far'], 1);
      expect((await anki.cardStateById(near.id))!.dueAt, nowMs);
      expect((await anki.cardStateById(far.id))!.dueAt, nowMs + 20 * dayMs);
    });

    test('limit 只拉最近的若干张，其余报「还有 N 张没拉」', () async {
      final root = await tags.createTag(name: '生物');
      final nearest = await seedCard(
        tag: root,
        title: '最近',
        dueIn: const Duration(days: 1),
      );
      await seedCard(
        tag: root,
        title: '较远',
        dueIn: const Duration(days: 5),
      );

      final result = await run({'tag': '生物', 'limit': 1, 'dry_run': false});

      expect(countsOf(result)['pull'], 1);
      expect(countsOf(result)['beyond_limit'], 1);
      expect((await anki.cardStateById(nearest.id))!.dueAt, nowMs);
    });

    test('已经到期和更远的卡都不动', () async {
      final root = await tags.createTag(name: '生物');
      final due = await seedCard(
        tag: root,
        title: '已到期',
        dueIn: const Duration(days: -1),
      );
      final far = await seedCard(
        tag: root,
        title: '下个月',
        dueIn: const Duration(days: 30),
      );

      final result = await run({'tag': '生物', 'dry_run': false});

      expect(countsOf(result)['already_due'], 1);
      expect(countsOf(result)['too_far'], 1);
      expect(countsOf(result)['pull'], 0);
      expect((await anki.cardStateById(due.id))!.dueAt, nowMs - dayMs);
      expect((await anki.cardStateById(far.id))!.dueAt, nowMs + 30 * dayMs);
    });
  });

  group('参数与提示', () {
    test('卡组下没有卡片时说清楚，不报错', () async {
      await tags.createTag(name: '空卡组');

      final result = await run({'tag': '空卡组'});

      expect(result.ok, isTrue);
      expect(result.summary, contains('没有挂任何知识点/闪存卡'));
      expect(countsOf(result)['total'], 0);
    });

    test('不存在的标签指向 query_content(kind: tag)', () async {
      final result = await run({'tag': '不存在的卡组'});

      expect(result.ok, isFalse);
      expect(result.summary, contains('query_content(kind: tag)'));
    });

    test('days 越界与 limit 越界都被拒绝', () async {
      await tags.createTag(name: '生物');

      final tooManyDays = await run({'tag': '生物', 'days': 400});
      final badLimit = await run({'tag': '生物', 'limit': 0});

      expect(tooManyDays.ok, isFalse);
      expect(tooManyDays.summary, contains('0–90'));
      expect(badLimit.ok, isFalse);
      expect(badLimit.summary, contains('1–2000'));
    });

    test('卡组设了每天复习上限时，提示可用 manage_review_plan 调', () async {
      final root = await tags.createTag(name: '生物');
      await db.into(db.reviewGroupPlans).insert(
            ReviewGroupPlansCompanion.insert(
              id: 'plan-1',
              tagId: root.id,
              reviewCardsPerDay: const Value(5),
              createdAt: nowMs,
              updatedAt: nowMs,
            ),
          );
      await seedCard(
        tag: root,
        title: '细胞膜',
        dueIn: const Duration(days: 2),
      );

      final preview = await run({'tag': '生物'});
      final applied = await run({'tag': '生物', 'dry_run': false});

      expect(preview.summary, contains('每天复习上限 5 张'));
      expect(preview.summary, contains('manage_review_plan'));
      expect(applied.summary, contains('manage_review_plan'));
      expect(bodyOf(preview)['review_cap'], 5);
    });

    test('工具声明为可撤销的写操作，并已注册进 app 工具表', () async {
      expect(tool.name, 'focus_review');
      expect(tool.readOnly, isFalse);
      expect(tool.riskFor(''), ToolRisk.write);
      expect(tool.reversibleFor(''), isTrue);

      final registry = ToolRegistry.forApp(
        db: db,
        tasks: TaskRepository(db),
        blocks: TimeBlockRepository(db),
        anki: anki,
        tags: tags,
        clock: () => now,
      );
      expect(registry.byName('focus_review'), isNotNull);
    });
  });
}
