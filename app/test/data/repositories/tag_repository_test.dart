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

  group('addTagToObjects / removeTagFromObjects：批量挂/摘标签', () {
    Future<Tag> makeTag([String name = '批量']) => tags.createTag(name: name);

    Future<Set<String>> linked(
      Tag tag, {
      String type = 'question',
    }) async =>
        (await tags.objectLinksForTag(tag.id))
            .where((link) => link.objectType == type)
            .map((link) => link.objectId)
            .toSet();

    Future<List<ObjectTag>> linksOf(Tag tag) => tags.objectLinksForTag(tag.id);

    test('一次挂多题：返回真实新增数，链接可按题反查', () async {
      final tag = await makeTag();

      expect(
        await tags.addTagToObjects(
          tagId: tag.id,
          objectIds: ['q-1', 'q-2', 'q-3'],
        ),
        3,
      );

      expect(await linked(tag), {'q-1', 'q-2', 'q-3'});
      expect((await db.select(db.objectTags).get()).length, 3);
      final back = await tags.tagsForObject(
        objectType: 'question',
        objectId: 'q-2',
      );
      expect(back.map((t) => t.id), [tag.id]);
    });

    test('重复挂同一批：第二次返回 0，链接行数不变', () async {
      final tag = await makeTag();
      const ids = ['q-1', 'q-2', 'q-3'];

      expect(await tags.addTagToObjects(tagId: tag.id, objectIds: ids), 3);
      expect(await tags.addTagToObjects(tagId: tag.id, objectIds: ids), 0);
      expect((await db.select(db.objectTags).get()).length, 3);
    });

    test('混合已挂/未挂：只计真正新增的', () async {
      final tag = await makeTag();
      expect(
        await tags.addTagToObjects(tagId: tag.id, objectIds: ['q-a']),
        1,
      );

      expect(
        await tags.addTagToObjects(
          tagId: tag.id,
          objectIds: ['q-a', 'q-b', 'q-c'],
        ),
        2,
      );
      expect(await linked(tag), {'q-a', 'q-b', 'q-c'});
    });

    test('空集合/空白 tagId/空白 objectId：立即 0 且不抛', () async {
      final tag = await makeTag();

      expect(await tags.addTagToObjects(tagId: tag.id, objectIds: []), 0);
      expect(await tags.removeTagFromObjects(tagId: tag.id, objectIds: []), 0);
      expect(
        await tags.addTagToObjects(
          tagId: '   ',
          objectIds: ['q-1'],
        ),
        0,
      );
      expect(
        await tags.addTagToObjects(
          tagId: tag.id,
          objectIds: ['  ', '', '\t'],
        ),
        0,
      );
      expect(
        await tags.removeTagFromObjects(tagId: tag.id, objectIds: ['   ']),
        0,
      );
      expect(await db.select(db.objectTags).get(), isEmpty);
      // 空 objectType 也是调用方的空输入，不能写出一条类型为空的链接。
      expect(
        await tags.addTagToObjects(
          tagId: tag.id,
          objectIds: ['q-1'],
          objectType: ' ',
        ),
        0,
      );
    });

    test('默认 objectType 是 question，可切换到别的类型（不写死）', () async {
      final tag = await makeTag();

      expect(await tags.addTagToObjects(tagId: tag.id, objectIds: ['q-1']), 1);
      expect(
        await tags.addTagToObjects(
          tagId: tag.id,
          objectIds: ['kp-1'],
          objectType: 'knowledge_point',
        ),
        1,
      );

      expect(await linked(tag), {'q-1'});
      expect(await linked(tag, type: 'knowledge_point'), {'kp-1'});
      final rows = await db.select(db.objectTags).get();
      expect(rows.map((row) => row.objectType).toSet(), {
        'question',
        'knowledge_point',
      });
    });

    test('objectType 隔离：同 id 在不同类型名下互不影响', () async {
      final tag = await makeTag();
      expect(await tags.addTagToObjects(tagId: tag.id, objectIds: ['x-1']), 1);
      expect(
        await tags.addTagToObjects(
          tagId: tag.id,
          objectIds: ['x-1'],
          objectType: 'note',
        ),
        1,
      );
      expect((await db.select(db.objectTags).get()).length, 2);

      expect(
        await tags.removeTagFromObjects(tagId: tag.id, objectIds: ['x-1']),
        1,
      );
      expect(await linked(tag), isEmpty);
      expect(await linked(tag, type: 'note'), {'x-1'});
    });

    test('批量摘：只删指定对象，返回真实删除数', () async {
      final tag = await makeTag();
      await tags.addTagToObjects(
        tagId: tag.id,
        objectIds: ['q-1', 'q-2', 'q-3'],
      );

      expect(
        await tags.removeTagFromObjects(tagId: tag.id, objectIds: ['q-2']),
        1,
      );
      expect(await linked(tag), {'q-1', 'q-3'});
    });

    test('摘不存在的链接：返回 0，别的链接不受影响', () async {
      final tag = await makeTag();
      await tags.addTagToObjects(tagId: tag.id, objectIds: ['q-1']);

      expect(
        await tags.removeTagFromObjects(
          tagId: tag.id,
          objectIds: ['q-9', 'q-8'],
        ),
        0,
      );
      expect(await linked(tag), {'q-1'});
    });

    test('同 id 重复传：只插一条，摘也只删一条', () async {
      final tag = await makeTag();

      expect(
        await tags.addTagToObjects(
          tagId: tag.id,
          objectIds: [' q-1 ', 'q-1', 'q-2'],
        ),
        2,
      );
      expect((await db.select(db.objectTags).get()).length, 2);

      expect(
        await tags.removeTagFromObjects(
          tagId: tag.id,
          objectIds: ['q-1', ' q-1 ', 'q-2'],
        ),
        2,
      );
      expect(await db.select(db.objectTags).get(), isEmpty);
    });

    test('tagId 前后空白按 trim 处理，且不会串到别的标签', () async {
      final first = await makeTag('语文');
      final second = await makeTag('数学');

      expect(
        await tags.addTagToObjects(
          tagId: '  ${first.id}  ',
          objectIds: ['q-1'],
        ),
        1,
      );
      expect(await linked(first), {'q-1'});
      expect(await linked(second), isEmpty);

      expect(
        await tags.removeTagFromObjects(
          tagId: ' ${first.id} ',
          objectIds: ['q-1'],
        ),
        1,
      );
      expect(await db.select(db.objectTags).get(), isEmpty);
    });

    test('挂 20 题一次走完：计数准确，第二次为 0', () async {
      final tag = await makeTag();
      final ids = [for (var i = 0; i < 20; i++) 'q-$i'];

      expect(await tags.addTagToObjects(tagId: tag.id, objectIds: ids), 20);
      expect(await tags.addTagToObjects(tagId: tag.id, objectIds: ids), 0);
      expect(await linksOf(tag), hasLength(20));
    });
  });
}
