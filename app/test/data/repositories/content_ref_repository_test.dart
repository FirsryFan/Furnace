import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/content_ref_repository.dart';

/// `ContentRefRepository`（schema v47，2026-11-15）：契约
/// `INTEGRATION-CONTRACT-2026-11-15.md` §2.2 / §2.3 / §2.4 的 ID 桥。
///
/// 要锁的五条：
///
///  * 同一条引用（content_id + object_type + object_id + role）写两次是一行；
///  * 内容换版（version/hash 变）原地更新同一条，旧 hash 留在 metadata；
///  * version 与 hash 必须成对（只给一个是脏数据）；
///  * 词表校验：object_type / role 只能取固定值；
///  * **不复制正文**：这张表没有任何题干/答案/解析字段。
void main() {
  late AppDatabase db;
  late ContentRefRepository refs;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    refs = ContentRefRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('写一条引用后可按 content_id 与产品对象双向查到', () async {
    final row = await refs.upsert(
      contentId: 'Q-PH0001',
      objectType: 'question',
      objectId: 'q-local-1',
      role: 'source_package',
      contentVersion: 2,
      contentHash: 'a' * 64,
      subject: 'physics',
      metadata: const <String, Object?>{'trust': 'A', 'source_mode': 'archive'},
    );

    expect(row.id, startsWith('cref-'));
    final byContent = await refs.listByContentId('Q-PH0001');
    expect(byContent, hasLength(1));
    expect(byContent.single.objectId, 'q-local-1');
    expect(byContent.single.role, 'source_package');

    final byObject = await refs.listForObject(
      objectType: 'question',
      objectId: 'q-local-1',
    );
    expect(byObject.single.contentId, 'Q-PH0001');
  });

  test('同一四元组写两次只有一行（唯一键），内容不变时不改 updated_at', () async {
    final first = await refs.upsert(
      contentId: 'Q-PH0001',
      objectType: 'question',
      objectId: 'q-local-1',
      role: 'source_package',
      contentVersion: 2,
      contentHash: 'a' * 64,
    );
    final second = await refs.upsert(
      contentId: 'Q-PH0001',
      objectType: 'question',
      objectId: 'q-local-1',
      role: 'source_package',
      contentVersion: 2,
      contentHash: 'a' * 64,
    );

    expect(second.id, first.id);
    expect(second.updatedAt, first.updatedAt);
    expect(await db.select(db.contentRefs).get(), hasLength(1));
  });

  test('数据库层唯一约束拒绝绕开仓储的重复插入', () async {
    await refs.upsert(
      contentId: 'Q-MA0001',
      objectType: 'question',
      objectId: 'q-local-2',
      role: 'source_package',
      contentVersion: 1,
      contentHash: 'b' * 64,
    );
    await expectLater(
      db.into(db.contentRefs).insert(
            ContentRefsCompanion.insert(
              id: 'cref-duplicate',
              contentId: 'Q-MA0001',
              objectType: 'question',
              objectId: 'q-local-2',
              role: 'source_package',
              contentVersion: const Value(1),
              contentHash: Value('b' * 64),
              createdAt: 1,
              updatedAt: 1,
            ),
          ),
      throwsA(anything),
    );
  });

  test('内容换版：原地更新同一条，旧 version/hash 进 metadata（审计）', () async {
    final first = await refs.upsert(
      contentId: 'Q-PH0001',
      objectType: 'question',
      objectId: 'q-local-1',
      role: 'source_package',
      contentVersion: 2,
      contentHash: 'a' * 64,
      metadata: const <String, Object?>{'trust': 'A'},
    );
    final updated = await refs.upsert(
      contentId: 'Q-PH0001',
      objectType: 'question',
      objectId: 'q-local-1',
      role: 'source_package',
      contentVersion: 3,
      contentHash: 'c' * 64,
    );

    expect(updated.id, first.id, reason: '原地更新，不是新建第二张版本表');
    expect(updated.contentVersion, 3);
    expect(updated.contentHash, 'c' * 64);
    expect(updated.updatedAt, greaterThanOrEqualTo(first.updatedAt));

    final metadata =
        jsonDecode(updated.metadataJson!) as Map<String, Object?>;
    expect(metadata['trust'], 'A', reason: '没有变化的旧 metadata 要保留');
    expect(metadata['previous_hash'], 'a' * 64);
    expect(metadata['previous_version'], 2);

    expect(await db.select(db.contentRefs).get(), hasLength(1));
    // 按旧 id 查还是同一条（content_id 是稳定键）。
    expect((await refs.listByContentId('Q-PH0001')).single.id, first.id);
  });

  test('version / hash 必须成对：只给一个抛 ArgumentError', () async {
    await expectLater(
      refs.upsert(
        contentId: 'Q-PH0001',
        objectType: 'question',
        objectId: 'q-local-1',
        role: 'source_package',
        contentVersion: 2,
      ),
      throwsA(isA<ArgumentError>()),
    );
    await expectLater(
      refs.upsert(
        contentId: 'Q-PH0001',
        objectType: 'question',
        objectId: 'q-local-1',
        role: 'source_package',
        contentHash: 'a' * 64,
      ),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('词表校验：object_type / role / content_id 非法直接拒绝', () async {
    await expectLater(
      refs.upsert(
        contentId: 'Q-PH0001',
        objectType: 'weekly_plan',
        objectId: 'x',
        role: 'source_package',
      ),
      throwsA(isA<ArgumentError>()),
    );
    await expectLater(
      refs.upsert(
        contentId: 'Q-PH0001',
        objectType: 'question',
        objectId: 'x',
        role: 'whatever',
      ),
      throwsA(isA<ArgumentError>()),
    );
    await expectLater(
      refs.upsert(
        contentId: '  ',
        objectType: 'question',
        objectId: 'x',
        role: 'source_package',
      ),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('只存引用、不复制正文：content_refs 没有任何正文字段', () async {
    final columns = await db.columnsOf('content_refs');
    for (final forbidden in <String>[
      'stem',
      'answer',
      'solution',
      'explanation',
      'question_text',
      'content_body',
      'dag_json',
      'title',
    ]) {
      expect(columns, isNot(contains(forbidden)),
          reason: 'content_refs 不许复制正文/快照字段：$forbidden');
    }
    // 引用的正文只能留在题目/知识点的原表里：内容 id 只出现在 content_refs。
    final ref = await refs.upsert(
      contentId: 'Q-PH0001',
      objectType: 'question',
      objectId: 'q-local-1',
      role: 'source_package',
      contentVersion: 2,
      contentHash: 'a' * 64,
    );
    expect(ref.contentId, 'Q-PH0001');
  });

  test('删引用不影响内容包：删掉后按 content_id 查为空', () async {
    await refs.upsert(
      contentId: 'Q-CH0001',
      objectType: 'task',
      objectId: 'task-1',
      role: 'paper_item',
    );
    expect(
      await refs.delete(
        contentId: 'Q-CH0001',
        objectType: 'task',
        objectId: 'task-1',
        role: 'paper_item',
      ),
      isTrue,
    );
    expect(await refs.listByContentId('Q-CH0001'), isEmpty);
    expect(
      await refs.delete(
        contentId: 'Q-CH0001',
        objectType: 'task',
        objectId: 'task-1',
        role: 'paper_item',
      ),
      isFalse,
    );
  });
}
