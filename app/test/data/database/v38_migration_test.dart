import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/ability_score_repository.dart';
import 'package:furnace/domain/services/cognitive/ability_assessment.dart';
import 'package:sqlite3/sqlite3.dart' as sql;

/// v37 -> v38：能力测评分数表 `ability_scores`（轮次一百七十七，
/// docs/REVIEW_FEEDBACK.md §8）。
///
/// 纯新增一张只追加的表，老库没有一行要回填。要锁的四件事：
///
///  1. 真实 v37 文件（库里有数据、只是没有这张表）升级后表就建出来，空表可读；
///  2. 升级后立刻能写四项能力、重开还在（画像页读到的就是这些行）；
///  3. 被盖成 v38 却缺表的文件靠 beforeOpen 自愈（否则画像页抛 no such table，
///     看起来像「我从没测过」）；
///  4. 表自带唯一约束之外没有隐含假设：同一项能力写多行、latest 取最新。
void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('furnace_mig38_');
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// 用当前 schema 建库、插一个标签（证明升级不动别的表），再把 ability_scores
  /// 整张表 DROP 掉、把 user_version 压回 [userVersion]。
  Future<File> buildDb({
    required int userVersion,
    required String name,
    bool dropTable = true,
  }) async {
    final dbFile = File('${tempDir.path}/$name.db');
    final fresh = AppDatabase.forTesting(NativeDatabase(dbFile));
    await fresh.into(fresh.tags).insert(
          TagsCompanion.insert(
            id: 'tag-root',
            name: '数学',
            path: const Value('数学'),
            createdAt: 1700000000000,
            updatedAt: 1700000000000,
          ),
        );
    await fresh.close();

    final raw = sql.sqlite3.open(dbFile.path);
    if (dropTable) {
      raw.execute('DROP TABLE ability_scores');
    }
    raw.execute('PRAGMA user_version = $userVersion');
    raw.dispose();
    return dbFile;
  }

  test('真实 v37 文件升级后：表建出来、可读可写、重开还在', () async {
    final file = await buildDb(userVersion: 37, name: 'v37');
    var db = AppDatabase.forTesting(NativeDatabase(file));
    var repository = AbilityScoreRepository(db);

    expect(await repository.countAll(), 0, reason: '升级只建表，不凭空造分数');
    expect(await repository.latestByAbility(), isEmpty);

    await repository.record(
      key: AbilityKey.reactionSpeed,
      score: 82.5,
      metrics: const <String, Object?>{
        'samples_ms': <int>[260, 280, 300],
        'median_ms': 280,
      },
      now: DateTime.fromMillisecondsSinceEpoch(1700000100000),
    );
    await repository.record(
      key: AbilityKey.workingMemory,
      score: 66,
      now: DateTime.fromMillisecondsSinceEpoch(1700000200000),
    );

    var latest = await repository.latestByAbility();
    expect(latest.keys,
        unorderedEquals([AbilityKey.reactionSpeed, AbilityKey.workingMemory]));
    expect(latest[AbilityKey.reactionSpeed]!.score, 82.5);
    expect(latest[AbilityKey.reactionSpeed]!.metrics['median_ms'], 280);
    expect(latest[AbilityKey.workingMemory]!.metrics, isEmpty,
        reason: '没给 metrics 就是空表，写库时落 NULL');
    await db.close();

    // 已经是 v38，重开不再迁移；分数与指标必须原样还在。
    db = AppDatabase.forTesting(NativeDatabase(file));
    repository = AbilityScoreRepository(db);
    latest = await repository.latestByAbility();
    expect(latest[AbilityKey.reactionSpeed]!.score, 82.5);
    expect(await repository.countFor(AbilityKey.workingMemory), 1);
    await db.close();
  });

  test('同一项能力写多行：latestByAbility 取最新、countFor 数全部', () async {
    final file = await buildDb(userVersion: 37, name: 'multi');
    final db = AppDatabase.forTesting(NativeDatabase(file));
    final repository = AbilityScoreRepository(db);

    await repository.record(
      key: AbilityKey.patternRecognition,
      score: 40,
      now: DateTime.fromMillisecondsSinceEpoch(1700000000000),
    );
    await repository.record(
      key: AbilityKey.patternRecognition,
      score: 90,
      now: DateTime.fromMillisecondsSinceEpoch(1700000300000),
    );
    final latest = await repository.latestByAbility();
    expect(latest[AbilityKey.patternRecognition]!.score, 90);
    expect(await repository.countFor(AbilityKey.patternRecognition), 2);
    expect(await repository.countFor(AbilityKey.attentionStability), 0);
    expect(await repository.countAll(), 2);
    await db.close();
  });

  test('被盖成 v38 却缺表的文件，靠自愈建表', () async {
    final file = await buildDb(userVersion: 38, name: 'fake38');
    final db = AppDatabase.forTesting(NativeDatabase(file));
    final repository = AbilityScoreRepository(db);

    // 没有自愈的话，这里就 no such table 抛异常。
    expect(await repository.countAll(), 0);
    await repository.record(key: AbilityKey.attentionStability, score: 55);
    expect(await repository.countAll(), 1);
    await db.close();
  });
}
