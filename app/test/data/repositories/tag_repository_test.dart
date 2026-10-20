import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/anki_repository.dart';
import 'package:furnace/data/repositories/tag_repository.dart';

/// Cards with no card group: counting them, finding them, and the one-shot fix.
///
/// The load-bearing claims:
///
///  * an untagged knowledge point counts as "in no card group"; tagging it -
///    even with a tag far down a subtree - takes it out of that count;
///  * the fix tags exactly the untagged cards and touches nothing else;
///  * running the fix twice is a no-op (0 the second time), so a double tap
///    cannot create duplicate links;
///  * an unknown tag id is a programming error, not a silent no-op.
void main() {
  late AppDatabase db;
  late AnkiRepository anki;
  late TagRepository tags;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    anki = AnkiRepository(db);
    tags = TagRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<KnowledgePoint> card(String title) =>
      anki.createKnowledgePoint(title: title, content: 'content of $title');

  test('every card counts as ungrouped until a tag is attached', () async {
    expect(await tags.countKnowledgePointsWithoutTags(), 0);

    final first = await card('first');
    final second = await card('second');
    expect(await tags.countKnowledgePointsWithoutTags(), 2);
    expect(
      (await tags.knowledgePointIdsWithoutTags()).toSet(),
      {first.id, second.id},
    );

    final tag = await tags.createTag(name: '语文');
    await tags.addTagToObject(
      tagId: tag.id,
      objectType: 'knowledge_point',
      objectId: first.id,
    );

    expect(await tags.countKnowledgePointsWithoutTags(), 1);
    expect(await tags.knowledgePointIdsWithoutTags(), [second.id]);
  });

  test('a tag deep in a subtree is enough: the tag itself is the group',
      () async {
    final root = await tags.createTag(name: '文化课');
    final child = await tags.createTag(name: '语文', parentId: root.id);
    final leaf = await tags.createTag(name: '作文', parentId: child.id);
    final tagged = await card('tagged');
    await tags.addTagToObject(
      tagId: leaf.id,
      objectType: 'knowledge_point',
      objectId: tagged.id,
    );

    expect(await tags.countKnowledgePointsWithoutTags(), 0);
    expect(await tags.knowledgePointIdsWithoutTags(), isEmpty);
  });

  test('the one-shot fix tags only the untagged cards and cannot duplicate',
      () async {
    final tag = await tags.createTag(name: '数学');
    final first = await card('first');
    await card('second');
    final already = await card('already');
    await tags.addTagToObject(
      tagId: tag.id,
      objectType: 'knowledge_point',
      objectId: already.id,
    );

    expect(await tags.tagKnowledgePointsWithoutTags(tag.id), 2);
    expect(await tags.countKnowledgePointsWithoutTags(), 0);
    expect(
      (await tags.tagsForObject(
        objectType: 'knowledge_point',
        objectId: first.id,
      ))
          .map((t) => t.id),
      [tag.id],
    );
    // The already-tagged card keeps exactly one link; nothing was doubled.
    expect(
      (await tags.tagsForObject(
        objectType: 'knowledge_point',
        objectId: already.id,
      ))
          .map((t) => t.id),
      [tag.id],
    );
    expect((await db.select(db.objectTags).get()).length, 3);

    // Second run: nothing left to do, and the existing links are untouched.
    expect(await tags.tagKnowledgePointsWithoutTags(tag.id), 0);
    expect((await db.select(db.objectTags).get()).length, 3);
  });

  test('an unknown tag id is rejected instead of silently doing nothing',
      () async {
    await card('first');
    expect(
      () => tags.tagKnowledgePointsWithoutTags('tag-does-not-exist'),
      throwsArgumentError,
    );
  });

  group('objectCountByTagId：标签树「按内容量排序」的数据源', () {
    Future<({Tag root, Tag child, Tag leaf})> seedThreeLevel() async {
      final root = await tags.createTag(name: '文化课');
      final child = await tags.createTag(name: '语文', parentId: root.id);
      final leaf = await tags.createTag(name: '作文', parentId: child.id);
      return (root: root, child: child, leaf: leaf);
    }

    Future<void> attach(
      Tag tag,
      List<String> objectIds, {
      String type = 'knowledge_point',
    }) async {
      for (final objectId in objectIds) {
        await tags.addTagToObject(
          tagId: tag.id,
          objectType: type,
          objectId: objectId,
        );
      }
    }

    test('空库：两种模式都返回空 map', () async {
      expect(await tags.objectCountByTagId(), isEmpty);
      expect(await tags.objectCountByTagId(includeDescendants: true), isEmpty);
    });

    test('直接模式：按 tag_id 计数，没有对象的标签不出现', () async {
      final tree = await seedThreeLevel();
      await attach(tree.leaf, ['kp-1', 'kp-2']);
      await attach(tree.root, ['kp-3']);

      final counts = await tags.objectCountByTagId();
      expect(counts, {tree.leaf.id: 2, tree.root.id: 1});
      expect(counts.containsKey(tree.child.id), isFalse);
    });

    test('直接模式：同一标签挂不同类型对象时都计入', () async {
      final tree = await seedThreeLevel();
      await attach(tree.leaf, ['kp-1', 'kp-2']);
      await attach(tree.leaf, ['q-1'], type: 'question');

      expect(await tags.objectCountByTagId(), {tree.leaf.id: 3});
    });

    test('objectTypes 过滤：直接模式只统计指定类型', () async {
      final tree = await seedThreeLevel();
      await attach(tree.leaf, ['kp-1', 'kp-2']);
      await attach(tree.leaf, ['q-1'], type: 'question');

      expect(
        await tags.objectCountByTagId(objectTypes: {'knowledge_point'}),
        {tree.leaf.id: 2},
      );
      expect(
        await tags.objectCountByTagId(objectTypes: {'question'}),
        {tree.leaf.id: 1},
      );
      expect(
        await tags.objectCountByTagId(
          objectTypes: {'knowledge_point', 'question'},
        ),
        {tree.leaf.id: 3},
      );
      expect(await tags.objectCountByTagId(objectTypes: {'note'}), isEmpty);
    });

    test('objectTypes 空集合：直接模式空 map，累计模式全部标签为 0', () async {
      final tree = await seedThreeLevel();
      await attach(tree.leaf, ['kp-1']);

      expect(await tags.objectCountByTagId(objectTypes: <String>{}), isEmpty);
      final totals = await tags.objectCountByTagId(
        includeDescendants: true,
        objectTypes: <String>{},
      );
      expect(totals, {tree.root.id: 0, tree.child.id: 0, tree.leaf.id: 0});
    });

    test('子树累计：返回全部标签，父节点是子树和', () async {
      final tree = await seedThreeLevel();
      await attach(tree.leaf, ['kp-1', 'kp-2']);
      await attach(tree.root, ['kp-3']);

      final totals = await tags.objectCountByTagId(includeDescendants: true);
      expect(totals, {tree.root.id: 3, tree.child.id: 2, tree.leaf.id: 2});
      expect(totals.length, 3);
    });

    test('子树累计：三层各自的对象分别累加', () async {
      final tree = await seedThreeLevel();
      await attach(tree.root, ['kp-r']);
      await attach(tree.child, ['kp-c1', 'kp-c2']);
      await attach(tree.leaf, ['kp-l1', 'kp-l2', 'kp-l3']);

      final totals = await tags.objectCountByTagId(includeDescendants: true);
      expect(totals, {tree.root.id: 6, tree.child.id: 5, tree.leaf.id: 3});
    });

    test('子树累计：兄弟分支互不串味，无对象标签为 0', () async {
      final tree = await seedThreeLevel();
      final other = await tags.createTag(name: '数学');
      await attach(tree.leaf, ['kp-1']);

      final totals = await tags.objectCountByTagId(includeDescendants: true);
      expect(totals[tree.root.id], 1);
      expect(totals[tree.leaf.id], 1);
      expect(totals[other.id], 0);
    });

    test('objectTypes 过滤：子树累计按过滤后的计数累加', () async {
      final tree = await seedThreeLevel();
      await attach(tree.root, ['q-1'], type: 'question');
      await attach(tree.leaf, ['kp-1', 'kp-2']);

      final totals = await tags.objectCountByTagId(
        includeDescendants: true,
        objectTypes: {'knowledge_point'},
      );
      expect(totals, {tree.root.id: 2, tree.child.id: 2, tree.leaf.id: 2});
    });

    test('新建但未挂对象的标签：直接模式不出现，累计模式计 0', () async {
      final lonely = await tags.createTag(name: '未使用');
      expect(await tags.objectCountByTagId(), isEmpty);
      expect(
        await tags.objectCountByTagId(includeDescendants: true),
        {lonely.id: 0},
      );
    });

    test('连续调用结果稳定（两种模式）', () async {
      final tree = await seedThreeLevel();
      await attach(tree.leaf, ['kp-1']);

      final directA = await tags.objectCountByTagId();
      final directB = await tags.objectCountByTagId();
      expect(directB, directA);

      final subtreeA = await tags.objectCountByTagId(includeDescendants: true);
      final subtreeB = await tags.objectCountByTagId(includeDescendants: true);
      expect(subtreeB, subtreeA);
    });

    test('只读：不修改 tags / object_tags 的行数', () async {
      final tree = await seedThreeLevel();
      await attach(tree.leaf, ['kp-1']);
      final tagRows = (await db.select(db.tags).get()).length;
      final linkRows = (await db.select(db.objectTags).get()).length;

      await tags.objectCountByTagId();
      await tags.objectCountByTagId(
        includeDescendants: true,
        objectTypes: {'knowledge_point'},
      );

      expect((await db.select(db.tags).get()).length, tagRows);
      expect((await db.select(db.objectTags).get()).length, linkRows);
    });
  });
}
