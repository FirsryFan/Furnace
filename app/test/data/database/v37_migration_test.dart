import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/tag_repository.dart';
import 'package:furnace/domain/services/tags/tag_usage.dart';
import 'package:sqlite3/sqlite3.dart' as sql;

/// v36 -> v37：标签用途声明 `tags.usage_codes`（轮次一百七十六，
/// docs/REVIEW_FEEDBACK.md §10/§11）。
///
/// 列可空、NULL 读作「这一级没有声明」——用途不限制、子标签继承祖先的声明。
/// 迁移只补列、不回填：回填等于给每个标签凭空写一条用户从没做过的声明。
///
/// 要锁的四件事：
///
///  1. 真实 v36 文件升级后，已有标签原样还在、两行都读作「没声明」；
///  2. 写声明后立刻能解析、重开还在；子标签读到继承的用途；
///  3. 写空集合回到 NULL（恢复继承），不是写空串；
///  4. 已经被盖成 v37、却缺这一列的文件靠 beforeOpen 自愈。
void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('furnace_mig37_');
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// 用当前 schema 建库、插两个标签（根 + 子），然后把 usage_codes 列 DROP 掉、
  /// 把 user_version 压回 [userVersion]。
  Future<File> buildDb({
    required int userVersion,
    required String name,
  }) async {
    final dbFile = File('${tempDir.path}/$name.db');
    final fresh = AppDatabase.forTesting(NativeDatabase(dbFile));
    await fresh.into(fresh.tags).insert(
          TagsCompanion.insert(
            id: 'tag-root',
            name: '语文',
            path: const Value('语文'),
            createdAt: 1700000000000,
            updatedAt: 1700000000000,
          ),
        );
    await fresh.into(fresh.tags).insert(
          TagsCompanion.insert(
            id: 'tag-child',
            parentId: const Value('tag-root'),
            name: '作文',
            path: const Value('语文/作文'),
            createdAt: 1700000000000,
            updatedAt: 1700000000000,
          ),
        );
    await fresh.close();

    final raw = sql.sqlite3.open(dbFile.path);
    raw.execute('ALTER TABLE tags DROP COLUMN usage_codes');
    raw.execute('PRAGMA user_version = $userVersion');
    raw.dispose();
    return dbFile;
  }

  test('真实 v36 文件升级后：标签原样还在、用途读作没声明，写后能解析、重开还在', () async {
    final file = await buildDb(userVersion: 36, name: 'v36');
    var db = AppDatabase.forTesting(NativeDatabase(file));
    var repository = TagRepository(db);

    final tags = await repository.getAllTags();
    expect(tags, hasLength(2), reason: '升级只补列，不删数据');
    expect(tags.every((tag) => tag.usageCodes == null), isTrue,
        reason: 'NULL = 这一级没有声明，迁移不回填');
    var resolver = repository.resolverFor(tags);
    expect(resolver.hasAnyDeclaration, isFalse);
    expect(resolver.effectiveFor('tag-child'), isNull);
    expect(resolver.isVisibleFor('tag-child', TagUsage.time), isTrue,
        reason: '整条链都没声明 = 不限制');

    await repository.updateTagUsageCodes('tag-root', {TagUsage.time});
    resolver = repository.resolverFor(await repository.getAllTags());
    expect(resolver.declaredFor('tag-root'), {TagUsage.time});
    expect(resolver.effectiveFor('tag-child'), {TagUsage.time},
        reason: '子标签没有声明就继承父级');
    expect(resolver.isVisibleFor('tag-child', TagUsage.question), isFalse);
    await db.close();

    // 已经是 v37，重开不再迁移；声明必须原样还在。
    db = AppDatabase.forTesting(NativeDatabase(file));
    repository = TagRepository(db);
    resolver = repository.resolverFor(await repository.getAllTags());
    expect(resolver.effectiveFor('tag-child'), {TagUsage.time});
    await db.close();
  });

  test('写空集合清除声明、回到继承（落到 NULL 而不是空串）', () async {
    final file = await buildDb(userVersion: 36, name: 'clear');
    final db = AppDatabase.forTesting(NativeDatabase(file));
    final repository = TagRepository(db);

    await repository.updateTagUsageCodes('tag-root', {TagUsage.time});
    await repository.updateTagUsageCodes('tag-child', {TagUsage.question});
    var resolver = repository.resolverFor(await repository.getAllTags());
    expect(resolver.effectiveFor('tag-child'), {TagUsage.question},
        reason: '自己的声明覆盖父级，不做并集');

    await repository.updateTagUsageCodes('tag-child', {});
    final child = (await repository.getAllTags())
        .firstWhere((tag) => tag.id == 'tag-child');
    expect(child.usageCodes, isNull, reason: '清除声明写回 NULL；空串会被解码成另一回事');
    resolver = repository.resolverFor(await repository.getAllTags());
    expect(resolver.effectiveFor('tag-child'), {TagUsage.time},
        reason: '清掉自己的声明后回到继承父级');
    await db.close();
  });

  test('被盖成 v37 却缺 usage_codes 列的文件，靠自愈补列', () async {
    final file = await buildDb(userVersion: 37, name: 'fake37');
    final db = AppDatabase.forTesting(NativeDatabase(file));
    final repository = TagRepository(db);

    // 没有自愈的话，getAllTags() 就会 no such column 抛异常。
    final tags = await repository.getAllTags();
    expect(tags, hasLength(2));
    await repository.updateTagUsageCodes('tag-root', {TagUsage.knowledge});
    expect(
      (await repository.getAllTags())
          .firstWhere((tag) => tag.id == 'tag-root')
          .usageCodes,
      'knowledge',
    );
    await db.close();
  });
}
