import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/anki_repository.dart';
import 'package:furnace/data/repositories/review_plan_repository.dart';
import 'package:furnace/data/repositories/tag_repository.dart';
import 'package:furnace/data/repositories/task_repository.dart';
import 'package:furnace/data/repositories/time_block_repository.dart';
import 'package:furnace/features/ai/domain/ai_tool.dart';
import 'package:furnace/features/ai/domain/tool_registry.dart';
import 'package:furnace/features/ai/tools/card_group_tools.dart';
import 'package:furnace/features/ai/tools/content_query_tools.dart';

/// The gap this file closes: the model could see flashcards and tags, but had no
/// way to say "this card belongs to that card group" or "this group gets 20 new
/// cards a day". Both are tag writes, and both are what the user asked for.
void main() {
  late AppDatabase db;
  late TagRepository tags;
  late AnkiRepository anki;
  late ReviewPlanRepository plans;
  late LinkCardTagsTool link;
  late ManageReviewPlanTool manage;
  late QueryContentTool query;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    tags = TagRepository(db);
    anki = AnkiRepository(db);
    plans = ReviewPlanRepository(db, anki);
    link = LinkCardTagsTool(db: db, anki: anki, tags: tags);
    manage = ManageReviewPlanTool(tags: tags, plans: plans);
    query = QueryContentTool(db: db, anki: anki, tags: tags, plans: plans);
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

  Map<String, Object?> bodyOf(ToolResult result) =>
      (result.modelResult! as Map).cast<String, Object?>();

  Future<int> linkRows() async => (await db.select(db.objectTags).get()).length;

  Future<KnowledgePoint> makeCard(String title, {String? source}) {
    return anki.createKnowledgePoint(
      title: title,
      content: '正文',
      source: source,
    );
  }

  group('a tag can be named three ways', () {
    test('by id, by full path, and by a unique name', () async {
      final root = await tags.createTag(name: '生物');
      final child = await tags.createTag(name: '必修1', parentId: root.id);

      expect((await resolveTagForTool(tags, root.id)).id, root.id);
      expect((await resolveTagForTool(tags, '生物/必修1')).id, child.id);
      expect((await resolveTagForTool(tags, '必修1')).id, child.id);
    });

    test('a duplicated name is refused instead of guessed', () async {
      final a = await tags.createTag(name: '甲');
      final b = await tags.createTag(name: '乙');
      await tags.createTag(name: '同名', parentId: a.id);
      await tags.createTag(name: '同名', parentId: b.id);

      await expectLater(
        () => resolveTagForTool(tags, '同名'),
        throwsA(
          isA<ToolArgError>().having(
            (error) => error.message,
            'message',
            allOf(contains('甲/同名'), contains('乙/同名')),
          ),
        ),
      );
    });

    test('an unknown tag points at the query that lists paths', () async {
      await expectLater(
        () => resolveTagForTool(tags, '不存在'),
        throwsA(
          isA<ToolArgError>().having(
            (error) => error.message,
            'message',
            contains('query_content(kind: tag)'),
          ),
        ),
      );
    });
  });

  group('explicit linking', () {
    test('links every card it was given and reports the count', () async {
      final tag = await tags.createTag(name: '生物');
      final one = await makeCard('细胞膜');
      final two = await makeCard('细胞核');

      final result = await run(link, {
        'tag': '生物',
        'card_ids': [one.id, two.id],
      });

      expect(result.ok, isTrue);
      final body = bodyOf(result);
      expect(body['mode'], 'explicit');
      expect(body['linked'], 2);
      expect(body['already'], 0);
      expect((body['tag']! as Map)['path'], '生物');
      expect(body['cards'], hasLength(2));
      expect(await linkRows(), 2);
      expect(
          await tags.tagsForObject(
            objectType: kKnowledgePointObjectType,
            objectId: one.id,
          ),
          hasLength(1));
      expect(result.afterJson, isNotNull);
      final decoded = jsonDecode(result.afterJson!) as Map;
      expect(decoded['links'], hasLength(2));
      expect(tag.id, isNotEmpty);
    });

    test('running it twice does not double the links', () async {
      await tags.createTag(name: '生物');
      final one = await makeCard('细胞膜');

      await run(link, {
        'tag': '生物',
        'card_ids': [one.id]
      });
      final second = await run(link, {
        'tag': '生物',
        'card_ids': [one.id]
      });

      expect(second.ok, isTrue);
      expect(bodyOf(second)['linked'], 0);
      expect(bodyOf(second)['already'], 1);
      expect(await linkRows(), 1);
      expect(second.afterJson, isNotNull);
      expect(jsonDecode(second.afterJson!)['links'], isEmpty);
    });

    test('one unknown card id refuses the whole call without writing',
        () async {
      await tags.createTag(name: '生物');
      final real = await makeCard('细胞膜');

      final result = await run(link, {
        'tag': '生物',
        'card_ids': [real.id, 'kp-does-not-exist'],
      });

      expect(result.ok, isFalse);
      expect(result.error, contains('不是库里的闪存卡'));
      expect(result.error, contains('kp-does-not-exist'));
      expect(await linkRows(), 0, reason: 'all or nothing');
      expect(
          await tags.tagsForObject(
            objectType: kKnowledgePointObjectType,
            objectId: real.id,
          ),
          isEmpty);
    });

    test('a missing tag or card_ids is an argument error, not a write',
        () async {
      final one = await makeCard('细胞膜');
      final noTag = await run(link, {
        'card_ids': [one.id]
      });
      expect(noTag.ok, isFalse);
      expect(noTag.error, contains('`tag`'));

      await tags.createTag(name: '生物');
      final noCards = await run(link, {'tag': '生物'});
      expect(noCards.ok, isFalse);
      expect(noCards.error, contains('`card_ids`'));
      expect(await linkRows(), 0);
    });
  });

  group('bulk linking by the path already written in source', () {
    late String sectionOne;
    late String sectionTwo;

    setUp(() async {
      final subject = await tags.createTag(name: '生物');
      final high = await tags.createTag(name: '高中生物', parentId: subject.id);
      final book = await tags.createTag(name: '必修1 分子与细胞', parentId: high.id);
      final chapter = await tags.createTag(name: '第1章 走近细胞', parentId: book.id);
      final one = await tags.createTag(
        name: '第1节 细胞是生命活动的基本单位',
        parentId: chapter.id,
      );
      final two = await tags.createTag(
        name: '第2节 细胞的多样性和统一性',
        parentId: chapter.id,
      );
      sectionOne = one.path ?? one.name;
      sectionTwo = two.path ?? two.name;
    });

    test('dry run reports matches and writes nothing', () async {
      await makeCard('细胞学说', source: '课本 P2｜$sectionOne');
      await makeCard('原核与真核', source: '笔记｜$sectionTwo');
      await makeCard('没有路径', source: '课本 P2 没写路径');
      await makeCard('路径不存在', source: '课本 P9｜生物/必修2/第9节 不存在');

      final result = await run(link, {'from_source_paths': true});

      final body = bodyOf(result);
      expect(result.ok, isTrue);
      expect(body['mode'], 'source_paths');
      expect(body['dry_run'], isTrue);
      expect(body['scanned'], 4);
      expect(body['matched'], 2);
      expect(body['linked'], 0);
      expect(body['ambiguous'], 0);
      expect(body['unmatched'], 2);
      expect(body['matches'], hasLength(2));
      expect(result.afterJson, isNull, reason: 'preview has nothing to undo');
      expect(await linkRows(), 0);
    });

    test('dry_run=false writes exactly the matches', () async {
      final card = await makeCard('细胞学说', source: '课本 P2｜$sectionOne');
      await makeCard('原核与真核', source: '笔记｜$sectionTwo');

      final result = await run(link, {
        'from_source_paths': true,
        'dry_run': false,
      });

      expect(result.ok, isTrue);
      expect(bodyOf(result)['linked'], 2);
      expect(await linkRows(), 2);
      final linked = await tags.tagsForObject(
        objectType: kKnowledgePointObjectType,
        objectId: card.id,
      );
      expect(linked.map((tag) => tag.path), [sectionOne]);
      expect(result.afterJson, isNotNull);
    });

    test('a second pass leaves already-grouped cards alone', () async {
      await makeCard('细胞学说', source: '课本 P2｜$sectionOne');
      await makeCard('没有路径', source: '没写');
      await run(link, {'from_source_paths': true, 'dry_run': false});

      final second = await run(link, {
        'from_source_paths': true,
        'dry_run': false,
      });

      expect(bodyOf(second)['scanned'], 1);
      expect(bodyOf(second)['matched'], 0);
      expect(await linkRows(), 1);
    });

    test('a path that matches two tags equally is reported, not guessed',
        () async {
      final left = await tags.createTag(name: '甲');
      final right = await tags.createTag(name: '乙');
      await tags.createTag(name: '同名', parentId: left.id);
      await tags.createTag(name: '同名', parentId: right.id);
      await makeCard('同名卡', source: '课本 P1｜同名');

      final result = await run(link, {
        'from_source_paths': true,
        'dry_run': false,
      });

      expect(bodyOf(result)['linked'], 0);
      expect(bodyOf(result)['ambiguous'], 1);
      final samples = bodyOf(result)['ambiguous_samples']! as List;
      expect((samples.single as Map)['candidates'], hasLength(2));
      expect(await linkRows(), 0);
    });

    test('a source that stops at one level still matches the deeper tag',
        () async {
      // The tag tree has 生物/高中生物/…/第1节 …, but this card's source only
      // records the section name. Exactly one tag explains it, so it is used.
      final sectionName = sectionOne.split('/').last;
      final card = await makeCard('短路径卡', source: '课本 P3｜$sectionName');

      final result = await run(link, {
        'from_source_paths': true,
        'dry_run': false,
      });

      expect(bodyOf(result)['matched'], 1);
      expect(bodyOf(result)['linked'], 1);
      final linked = await tags.tagsForObject(
        objectType: kKnowledgePointObjectType,
        objectId: card.id,
      );
      expect(linked.single.path, sectionOne);
    });

    test('limit caps the scan and says how many are left', () async {
      for (var i = 0; i < 4; i++) {
        await makeCard('卡$i', source: '课本｜$sectionOne');
      }

      final result = await run(link, {'from_source_paths': true, 'limit': 2});

      expect(bodyOf(result)['scanned'], 2);
      expect(bodyOf(result)['remaining'], 2);
      expect(result.summary, contains('还有 2 张'));
    });

    test('no tags at all is an argument error with the next step', () async {
      // This group's fixture creates a tag tree; drop it to model an empty tag
      // database without opening a second connection to the same memory db.
      await db.delete(db.tags).go();

      final result = await run(link, {'from_source_paths': true});

      expect(result.ok, isFalse);
      expect(result.error, contains('create_tags'));
    });
  });

  group('undo', () {
    test('unlinkCardTags removes only the links it made', () async {
      await tags.createTag(name: '生物');
      final one = await makeCard('细胞膜');
      final two = await makeCard('细胞核');
      final result = await run(link, {
        'tag': '生物',
        'card_ids': [one.id, two.id],
      });
      final snapshot =
          (jsonDecode(result.afterJson!) as Map).cast<String, Object?>();

      final undone = await unlinkCardTags(db, snapshot);

      expect(undone, isTrue);
      expect(await linkRows(), 0);
      expect(await tags.getAllTags(), hasLength(1), reason: 'the tag stays');
    });

    test('restoreReviewPlan puts the old row back, and clears a first set',
        () async {
      final tag = await tags.createTag(name: '生物');
      final first = await run(manage, {
        'action': 'set',
        'tag': tag.id,
        'new_cards_per_day': 20,
        'review_cards_per_day': 0,
      });
      // The first set had no old row: this snapshot says exactly that.
      final firstSnapshot =
          (jsonDecode(first.beforeJson!) as Map).cast<String, Object?>();
      expect(firstSnapshot['plan'], isNull);

      final second = await run(manage, {
        'action': 'set',
        'tag': tag.id,
        'new_cards_per_day': 5,
        'review_cards_per_day': 5,
      });
      final snapshot =
          (jsonDecode(second.beforeJson!) as Map).cast<String, Object?>();
      expect((snapshot['plan']! as Map)['new_cards_per_day'], 20);

      expect(await restoreReviewPlan(db, snapshot), isTrue);
      var rows = await plans.groupPlans();
      expect(rows.single.newCardsPerDay, 20);
      expect(rows.single.reviewCardsPerDay, 0);

      // Undoing the very first set removes the plan entirely.
      expect(await restoreReviewPlan(db, firstSnapshot), isTrue);
      rows = await plans.groupPlans();
      expect(rows, isEmpty, reason: 'first set had no old row');
    });
  });

  group('manage review plan', () {
    test('set writes the daily target and snapshots the absence', () async {
      final tag = await tags.createTag(name: '生物');

      final result = await run(manage, {
        'action': 'set',
        'tag': '生物',
        'new_cards_per_day': 20,
        'review_cards_per_day': 0,
      });

      expect(result.ok, isTrue);
      final plan = (await plans.groupPlans()).single;
      expect(plan.tagId, tag.id);
      expect(plan.newCardsPerDay, 20);
      expect(plan.reviewCardsPerDay, 0);
      expect(result.summary, contains('0=旧卡不限量'));
      final snapshot = jsonDecode(result.beforeJson!) as Map;
      expect(snapshot['plan'], isNull);
    });

    test('negative numbers are refused', () async {
      await tags.createTag(name: '生物');

      final result = await run(manage, {
        'action': 'set',
        'tag': '生物',
        'new_cards_per_day': -1,
        'review_cards_per_day': 0,
      });

      expect(result.ok, isFalse);
      expect(result.error, contains('不能是负数'));
      expect(await plans.groupPlans(), isEmpty);
    });

    test('clear removes the plan', () async {
      await tags.createTag(name: '生物');
      await run(manage, {
        'action': 'set',
        'tag': '生物',
        'new_cards_per_day': 20,
        'review_cards_per_day': 5,
      });

      final result = await run(manage, {'action': 'clear', 'tag': '生物'});

      expect(result.ok, isTrue);
      expect(bodyOf(result)['plan'], isNull);
      expect(await plans.groupPlans(), isEmpty);
    });

    test('a set without the two numbers is an argument error', () async {
      await tags.createTag(name: '生物');

      final result = await run(manage, {'action': 'set', 'tag': '生物'});

      expect(result.ok, isFalse);
      expect(result.error, contains('new_cards_per_day'));
    });
  });

  group('the query side shows the new state', () {
    test('flashcards carry their tags and an untagged flag', () async {
      await tags.createTag(name: '生物');
      final grouped = await makeCard('细胞膜');
      await makeCard('没归组');
      await run(link, {
        'tag': '生物',
        'card_ids': [grouped.id]
      });

      final result = await run(query, {'kind': 'flashcard'});
      final items = (bodyOf(result)['items']! as List)
          .cast<Map>()
          .map((item) => item.cast<String, Object?>())
          .toList();

      final linked = items.firstWhere((item) => item['id'] == grouped.id);
      expect(linked['tags'], hasLength(1));
      expect((linked['tags']! as List).single['path'], '生物');
      expect(linked['untagged'], isFalse);
      expect(linked['tag_count'], 1);

      final loose = items.firstWhere((item) => item['title'] == '没归组');
      expect(loose['tags'], isEmpty);
      expect(loose['untagged'], isTrue);
    });

    test('review_plan lists configured groups and the ungrouped count',
        () async {
      await tags.createTag(name: '生物');
      await makeCard('这张没归组');
      await run(manage, {
        'action': 'set',
        'tag': '生物',
        'new_cards_per_day': 20,
        'review_cards_per_day': 10,
      });

      final result = await run(query, {'kind': 'review_plan'});

      expect(result.ok, isTrue);
      final body = bodyOf(result);
      final plan = (body['items']! as List).single as Map;
      expect(plan['tag_path'], '生物');
      expect(plan['new_cards_per_day'], 20);
      expect(plan['review_cards_per_day'], 10);
      // The extras are merged at the top level, next to count/items.
      expect(body['total_flashcards'], 1);
      expect(body['ungrouped_flashcards'], 1);
      expect(body['note'], contains('manage_review_plan'));
    });
  });

  group('the app registry actually offers them', () {
    test('link_card_tags and manage_review_plan are registered', () async {
      final registry = ToolRegistry.forApp(
        db: db,
        tasks: TaskRepository(db),
        blocks: TimeBlockRepository(db),
        anki: anki,
        tags: tags,
      );

      final linkTool = registry.byName('link_card_tags');
      final planTool = registry.byName('manage_review_plan');
      expect(linkTool, isNotNull);
      expect(planTool, isNotNull);
      expect(linkTool!.readOnly, isFalse);
      expect(planTool!.readOnly, isFalse);
      // The read side already knows the plan kind through the same registry.
      expect(registry.byName('query_content'), isNotNull);
    });
  });

  group('the tools declare themselves as reversible writes', () {
    test('link_card_tags and manage_review_plan', () {
      for (final tool in [link, manage]) {
        expect(tool.readOnly, isFalse, reason: tool.name);
        expect(tool.riskFor(''), ToolRisk.write, reason: tool.name);
        expect(tool.reversibleFor(''), isTrue, reason: tool.name);
      }
    });
  });
}
