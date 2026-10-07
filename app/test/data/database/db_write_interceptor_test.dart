import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/core/state/data_change_bus.dart';
import 'package:furnace/core/state/data_revision.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/repository_providers.dart';
import 'package:furnace/data/repositories/tag_repository.dart';
import 'package:furnace/features/tags/presentation/tag_tree_page.dart';

/// The "no restart needed" contract, proven end to end:
///
/// a repository write -> the drift interceptor -> [DataChangeBus] -> the
/// revision provider -> the app's own reader provider refetches.
///
/// The database is built with [instrumentWrites], the very function
/// `_openConnection` uses, so this is the production path and not a copy of it.
void main() {
  late AppDatabase db;

  setUp(() {
    DataChangeBus.instance.debugReset();
    db = AppDatabase.forTesting(instrumentWrites(NativeDatabase.memory()));
  });

  tearDown(() async {
    await db.close();
  });

  test('a read announces nothing', () async {
    final events = <int>[];
    final subscription = DataChangeBus.instance.changes.listen(events.add);

    await TagRepository(db).getAllTags();
    await Future<void>.delayed(Duration.zero);

    expect(events, isEmpty);
    await subscription.cancel();
  });

  test('a write through a repository announces exactly one change', () async {
    final events = <int>[];
    final subscription = DataChangeBus.instance.changes.listen(events.add);

    await TagRepository(db).createTag(name: '物理');
    await Future<void>.delayed(Duration.zero);

    expect(events, hasLength(1));
    expect(events.single, DataChangeBus.instance.revision);
    await subscription.cancel();
  });

  test('one batch of writes is one change', () async {
    final events = <int>[];
    final subscription = DataChangeBus.instance.changes.listen(events.add);

    await db.batch((batch) {
      batch.insertAll(db.tags, [
        for (final name in ['甲', '乙', '丙'])
          TagsCompanion.insert(
            id: 'tag_$name',
            name: name,
            createdAt: 1,
            updatedAt: 1,
          ),
      ]);
    });
    await Future<void>.delayed(Duration.zero);

    expect(events, hasLength(1));
    await subscription.cancel();
  });

  test('writes separated by awaits are announced separately', () async {
    final events = <int>[];
    final subscription = DataChangeBus.instance.changes.listen(events.add);
    final repo = TagRepository(db);

    // Honest statement of the granularity: the unit of coalescing is one
    // microtask, and a repository call awaits its own insert, so three separate
    // calls are three events. What keeps bulk work cheap is that unlistened
    // providers are not recomputed at all.
    await repo.createTag(name: '甲');
    await repo.createTag(name: '乙');
    await repo.createTag(name: '丙');
    await Future<void>.delayed(Duration.zero);

    expect(events, hasLength(3));
    await subscription.cancel();
  });

  test('the app reader refetches after a write it did not perform', () async {
    final container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);
    container.listen(allTagsProvider, (_, __) {}, fireImmediately: true);

    expect(await container.read(allTagsProvider.future), isEmpty);

    // A write from anywhere else in the app - an AI tool, a package import, the
    // management page. Nothing here invalidates `allTagsProvider`.
    await container.read(tagRepositoryProvider).createTag(name: '化学');
    await Future<void>.delayed(Duration.zero);

    final after = await container.read(allTagsProvider.future);
    expect(after.map((tag) => tag.name), contains('化学'));
  });

  test('a write does not fire before it happened', () async {
    final container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);

    expect(container.read(dataRevisionProvider), DataChangeBus.instance.revision);
    expect(
      await container.read(allTagsProvider.future),
      isEmpty,
      reason: 'the reader starts empty and no write has happened yet',
    );
  });
}
