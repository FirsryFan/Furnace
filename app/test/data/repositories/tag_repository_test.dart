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
}
