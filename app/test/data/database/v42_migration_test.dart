import 'dart:io';

import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/package_repository.dart';
import 'package:sqlite3/sqlite3.dart' as sql;

/// v41 -> v42: knowledge_packages.enabled（2026-11-01，知识库入口下沉设置 + 启用/禁用）。
///
/// 列可空、NULL 读作「启用」：老库导入过的包默认仍生效，迁移只补列、不回填
/// （回填会把「v41 当时默认启用」冻进每一台已有安装）。要锁的三件事：
///
///  1. 真实 v41 文件升级后 enabled 为 NULL、仓储读作启用；写入禁用后重开还是 false
///     （已经是 v42，不再迁移）；
///  2. 版本号被盖成 v42 却缺这一列的文件靠 beforeOpen 自愈补列，数据不丢；
///  3. 迁移幂等：连续打开两次不抛，NULL 与数据都不变。
void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('furnace_mig42_');
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// 用当前 schema 建库、写一行 v41 时代的包，然后把 enabled 列 DROP 掉、
  /// 把 user_version 压回 [userVersion]——造出「v42 之前」的文件。
  Future<File> buildDb({
    required String name,
    required int userVersion,
  }) async {
    final dbFile = File('${tempDir.path}/$name.db');
    final fresh = AppDatabase.forTesting(NativeDatabase(dbFile));
    await fresh.into(fresh.knowledgePackages).insert(
          KnowledgePackagesCompanion.insert(
            id: 'pkg-loops',
            name: '光合作用知识包',
            version: '1.0.0',
            author: '测试作者',
            importedAt: 1700000000000,
            createdAt: 1700000000000,
            updatedAt: 1700000000000,
          ),
        );
    await fresh.close();

    final raw = sql.sqlite3.open(dbFile.path);
    raw.execute('ALTER TABLE knowledge_packages DROP COLUMN enabled');
    raw.execute('PRAGMA user_version = $userVersion');
    raw.dispose();
    return dbFile;
  }

  List<String> columnNames(String path, String table) {
    final raw = sql.sqlite3.open(path);
    try {
      return [
        for (final row in raw.select('PRAGMA table_info($table)'))
          row['name'] as String,
      ];
    } finally {
      raw.dispose();
    }
  }

  int userVersionOf(String path) {
    final raw = sql.sqlite3.open(path);
    try {
      return raw.select('PRAGMA user_version').single['user_version'] as int;
    } finally {
      raw.dispose();
    }
  }

  /// 直接读文件里那一格：NULL / 0 / 1，用来区分「没回填」与「真禁用」。
  Object? enabledValueOf(String path) {
    final raw = sql.sqlite3.open(path);
    try {
      return raw.select('SELECT enabled FROM knowledge_packages WHERE id = ?',
          ['pkg-loops']).single['enabled'];
    } finally {
      raw.dispose();
    }
  }

  int packageCountOf(String path) {
    final raw = sql.sqlite3.open(path);
    try {
      return raw
          .select('SELECT COUNT(*) AS c FROM knowledge_packages')
          .single['c'] as int;
    } finally {
      raw.dispose();
    }
  }

  test('真实 v41 文件升级后：enabled 为 NULL（读作启用），禁用后重开仍是禁用', () async {
    final file = await buildDb(name: 'v41', userVersion: 41);
    expect(
      columnNames(file.path, 'knowledge_packages'),
      isNot(contains('enabled')),
      reason: '前提：v41 文件没有这一列',
    );

    var db = AppDatabase.forTesting(NativeDatabase(file));
    var repo = PackageRepository(db);

    var package = await repo.getPackageById('pkg-loops');
    expect(package, isNotNull);
    expect(
      package!.enabled,
      isNull,
      reason: '迁移只补列、不回填；NULL 才有「老包默认启用」的语义',
    );
    expect(repo.isPackageEnabled(package), isTrue);

    final rawRow = await db.customSelect(
      'SELECT enabled FROM knowledge_packages WHERE id = ?',
      variables: [Variable.withString('pkg-loops')],
    ).getSingle();
    expect(
      rawRow.readNullable<bool>('enabled'),
      isNull,
      reason: '文件里真的是 NULL，不是被悄悄写成 1',
    );

    await repo.setPackageEnabled('pkg-loops', false);
    package = (await repo.getPackageById('pkg-loops'))!;
    expect(package.enabled, isFalse);
    expect(repo.isPackageEnabled(package), isFalse);
    await db.close();

    // 迁移把版本号写到 v42、列也补上了；禁用是显式 0。
    expect(userVersionOf(file.path), 42);
    expect(columnNames(file.path, 'knowledge_packages'), contains('enabled'));
    expect(enabledValueOf(file.path), 0, reason: 'false 落库是整数 0（Drift 布尔）');

    // 已经是 v42，重开不再迁移；禁用状态与包数据原样还在。
    db = AppDatabase.forTesting(NativeDatabase(file));
    repo = PackageRepository(db);
    package = (await repo.getPackageById('pkg-loops'))!;
    expect(package.enabled, isFalse);
    expect(repo.isPackageEnabled(package), isFalse);
    expect(package.name, '光合作用知识包');
    expect(package.version, '1.0.0');
    expect(package.author, '测试作者');
    expect((await repo.getAllPackages()).length, 1);
    await db.close();
  });

  test('版本号被盖成 v42、但缺 enabled 列的库：beforeOpen 自愈补列、数据不丢', () async {
    final file = await buildDb(name: 'fake42', userVersion: 42);
    expect(
      columnNames(file.path, 'knowledge_packages'),
      isNot(contains('enabled')),
      reason: '前提：版本号已是 42，但列还没加',
    );
    expect(userVersionOf(file.path), 42);

    final db = AppDatabase.forTesting(NativeDatabase(file));
    final repo = PackageRepository(db);

    // 没有自愈的话，这一次读就会 no such column。
    final package = (await repo.getPackageById('pkg-loops'))!;
    expect(package.name, '光合作用知识包');
    expect(package.version, '1.0.0');
    expect(package.author, '测试作者');
    expect(package.enabled, isNull);
    expect(repo.isPackageEnabled(package), isTrue, reason: 'NULL 读作启用');

    await repo.setPackageEnabled('pkg-loops', true);
    expect(
      (await repo.getPackageById('pkg-loops'))!.enabled,
      isTrue,
      reason: '启用写显式 true，不是 NULL',
    );
    await db.close();

    expect(userVersionOf(file.path), 42, reason: '自愈不改版本号');
    expect(
      columnNames(file.path, 'knowledge_packages'),
      contains('enabled'),
      reason: 'beforeOpen 补的列，文件层面也看得到',
    );
    expect(enabledValueOf(file.path), 1);
    expect(packageCountOf(file.path), 1, reason: '自愈补列不能丢行');
  });

  test('迁移幂等：连续打开两次不抛、NULL 与数据不变', () async {
    final file = await buildDb(name: 'twice', userVersion: 41);

    var db = AppDatabase.forTesting(NativeDatabase(file));
    var repo = PackageRepository(db);
    expect(
      repo.isPackageEnabled((await repo.getPackageById('pkg-loops'))!),
      isTrue,
    );
    await db.close();
    expect(userVersionOf(file.path), 42, reason: '第一次打开完成 v41 -> v42');

    // 第二次打开：onUpgrade 不再跑，只剩 beforeOpen 探列；NULL 不能被改写。
    db = AppDatabase.forTesting(NativeDatabase(file));
    repo = PackageRepository(db);
    final package = (await repo.getPackageById('pkg-loops'))!;
    expect(
      package.enabled,
      isNull,
      reason: '幂等：第二次打开不能再补值/回填',
    );
    expect(package.name, '光合作用知识包');
    expect((await repo.getAllPackages()).length, 1);
    await db.close();

    expect(userVersionOf(file.path), 42);
    expect(enabledValueOf(file.path), isNull, reason: '两次打开后仍是 NULL');
    expect(packageCountOf(file.path), 1);
  });
}
