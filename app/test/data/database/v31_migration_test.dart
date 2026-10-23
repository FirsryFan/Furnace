import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/handwriting_proposal_repository.dart';
import 'package:furnace/domain/services/intake/handwriting_proposals.dart';
import 'package:sqlite3/sqlite3.dart' as sql;

/// v30 -> v31：多图/多页整理（`handwriting_intake_runs.source_photos`，轮次一百四十八）。
///
/// 一列可空文本，存 JSON 路径数组：NULL / 空数组 = 单图整理，来源就是
/// `source_ref` 那条照片路径；非空时 `source_ref` 是 `multi:<hash>`，照片按用户
/// 选择顺序存在这一列里。迁移不回填——老行当然是单图整理，NULL 正好是那个语义。
///
/// 要锁的三件事：
///
///  1. 真实 v30 文件升级后，老 run 读作单图（`sourcePhotos` 空、`isMulti` false），
///     且升级后立刻能存多图 run、重开仍在；
///  2. 已经被盖成 v31、却没有这一列的文件靠 beforeOpen 自愈——Drift 在
///     user_version 等于当前版本时完全跳过 onUpgrade；
///  3. 坏 JSON / 空数组 / 非字符串元素一律容忍成"单图"，不抛异常。
void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('furnace_mig31_');
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// 用当前 schema 建库、放一条老 run（单图），然后把 source_photos 列 DROP 掉、
  /// 把 user_version 压回 [userVersion]。
  Future<File> buildDb({
    required int userVersion,
    required String name,
  }) async {
    final dbFile = File('${tempDir.path}/$name.db');
    final fresh = AppDatabase.forTesting(NativeDatabase(dbFile));
    await fresh.into(fresh.handwritingIntakeRuns).insert(
          HandwritingIntakeRunsCompanion.insert(
            sourceRef: 'handwriting_intake/photo-1/page.png',
            analyzedAt: 1700000000000,
            createdAt: 1700000000000,
          ),
        );
    await fresh.close();

    final raw = sql.sqlite3.open(dbFile.path);
    raw.execute(
        'ALTER TABLE handwriting_intake_runs DROP COLUMN source_photos');
    raw.execute('PRAGMA user_version = $userVersion');
    raw.dispose();
    return dbFile;
  }

  HandwritingProposalSet tagSet(String sourceRef) => parseHandwritingProposals(
        '{"proposals": [{"kind": "tag", "title": "动量守恒", '
        '"fields": {"parent_path": ""}}]}',
        sourceRef: sourceRef,
      );

  test('真实 v30 文件升级后：老 run 读作单图，且立刻能存多图、重开还在', () async {
    final file = await buildDb(userVersion: 30, name: 'v30');
    var db = AppDatabase.forTesting(NativeDatabase(file));
    var repo = HandwritingProposalRepository(db);

    var runs = await repo.runs();
    expect(runs, hasLength(1));
    expect(runs.single.sourceRef, 'handwriting_intake/photo-1/page.png');
    expect(runs.single.sourcePhotos, isEmpty, reason: '迁移不回填，空 = 单图');
    expect(runs.single.isMulti, isFalse);

    // 升级后立刻存一条多图 run。
    const multiRef = 'multi:00000000000000ab';
    await repo.saveRun(
      set: tagSet(multiRef),
      analyzedAt: DateTime.fromMillisecondsSinceEpoch(1700000001000),
      sourcePhotos: <String>['a.png', 'b.png'],
    );
    runs = await repo.runs();
    expect(runs, hasLength(2));
    final multi = runs.firstWhere((run) => run.sourceRef == multiRef);
    expect(multi.sourcePhotos, <String>['a.png', 'b.png'], reason: '顺序即页序');
    expect(multi.isMulti, isTrue);
    await db.close();

    // 已经是 v31，重开不再迁移；照片列表必须原样还在。
    db = AppDatabase.forTesting(NativeDatabase(file));
    repo = HandwritingProposalRepository(db);
    final reopened =
        (await repo.runs()).firstWhere((run) => run.sourceRef == multiRef);
    expect(reopened.sourcePhotos, <String>['a.png', 'b.png']);
    await db.close();
  });

  test('被盖成 v31 却缺 source_photos 列的文件，靠自愈补列', () async {
    final file = await buildDb(userVersion: 31, name: 'fake31');
    final db = AppDatabase.forTesting(NativeDatabase(file));
    final repo = HandwritingProposalRepository(db);

    // 没有自愈的话，这一读就会因为 no such column 抛异常。
    final runs = await repo.runs();
    expect(runs.single.sourcePhotos, isEmpty);

    const multiRef = 'multi:00000000000000cd';
    await repo.saveRun(
      set: tagSet(multiRef),
      analyzedAt: DateTime.fromMillisecondsSinceEpoch(1700000002000),
      sourcePhotos: <String>['p1.png', 'p2.png'],
    );
    final saved = (await repo.runs()).firstWhere(
      (run) => run.sourceRef == multiRef,
    );
    expect(saved.sourcePhotos, <String>['p1.png', 'p2.png']);
    await db.close();
  });

  test('坏 JSON / 空数组 / 非字符串元素：容忍成单图，不抛异常', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final repo = HandwritingProposalRepository(db);

    Future<void> seedRaw(String sourceRef, String? rawPhotos) async {
      await db.into(db.handwritingIntakeRuns).insert(
            HandwritingIntakeRunsCompanion.insert(
              sourceRef: sourceRef,
              analyzedAt: 1700000000000,
              createdAt: 1700000000000,
              sourcePhotos: Value(rawPhotos),
            ),
          );
    }

    await seedRaw('bad-json', 'not json');
    await seedRaw('empty-array', '[]');
    await seedRaw('mixed', jsonEncode(<Object>[1, 'a.png', '', 'b.png']));

    final runs = await repo.runs();
    final byRef = <String, HandwritingStoredRun>{
      for (final run in runs) run.sourceRef: run,
    };
    expect(byRef['bad-json']!.sourcePhotos, isEmpty);
    expect(byRef['empty-array']!.sourcePhotos, isEmpty);
    expect(byRef['mixed']!.sourcePhotos, <String>['a.png', 'b.png']);
    expect(runs.every((run) => run.isMulti == run.sourcePhotos.isNotEmpty),
        isTrue);
    await db.close();
  });
}
