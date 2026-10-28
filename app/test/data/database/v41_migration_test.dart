import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/cognitive_profile_repository.dart';
import 'package:furnace/features/assessment/application/assessment_session_service.dart';
import 'package:furnace/features/assessment/application/task_registry.dart';
import 'package:furnace/features/assessment/domain/assessment_models.dart';
import 'package:sqlite3/sqlite3.dart' as sql;

/// v40 -> v41：评测板块的八张 `cog_*` 表（轮次一百八十五，用户评测板块 v1.0）。
///
/// 迁移是纯新增表、不回填。要锁三件事：
///
///  1. 真实 v40 文件升级后八张表都在，仓储能 seed、能记录一次会话；
///  2. 已经是 v41 的文件重开时不再迁移，数据原样还在；
///  3. 版本号被盖成 v40、但表已经先建好的文件不会因重复 createTable 报错，
///     也不会丢数据（[_tableExists] 探测分支）。
const _cogTables = <String>[
  'cog_assessment_tasks',
  'cog_assessment_sessions',
  'cog_assessment_trials',
  'cog_assessment_metrics',
  'cog_ability_estimates',
  'cog_cognitive_params',
  'cog_task_ability_mapping',
  'cog_ability_param_mapping',
];

void main() {
  late Directory tempDir;
  final moment = DateTime(2026, 10, 29, 1, 30);

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('furnace_mig41_');
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// 用当前 schema 建库，再按 [dropTables] 把八张 cog 表删掉、
  /// 把 user_version 压回 [userVersion]。
  Future<File> buildDb({
    required String name,
    required int userVersion,
    bool dropTables = true,
  }) async {
    final file = File('${tempDir.path}/$name.db');
    final fresh = AppDatabase.forTesting(NativeDatabase(file));
    await CognitiveProfileRepository(fresh).ensureSeeded(now: moment);
    await fresh.close();

    if (dropTables) {
      final raw = sql.sqlite3.open(file.path);
      for (final table in _cogTables) {
        raw.execute('DROP TABLE IF EXISTS $table');
      }
      raw.execute('PRAGMA user_version = $userVersion');
      raw.dispose();
    } else {
      final raw = sql.sqlite3.open(file.path);
      raw.execute('PRAGMA user_version = $userVersion');
      raw.dispose();
    }
    return file;
  }

  /// 只看八张新表：老库里还有一张 v10 的 `cognitive_priors`，
  /// 用 `LIKE 'cog_%'` 会把它一起数进来。
  List<String> tableNames(String path) {
    final raw = sql.sqlite3.open(path);
    final placeholders = List<String>.filled(_cogTables.length, '?').join(',');
    final rows = raw.select(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name IN ($placeholders)",
      _cogTables,
    );
    final names = <String>[for (final row in rows) row['name'] as String];
    raw.dispose();
    return names;
  }

  test('真实 v40 文件升级后：八张表都在，seed 与一次会话都能落库', () async {
    final file = await buildDb(name: 'v40', userVersion: 40);
    expect(tableNames(file.path), isEmpty, reason: '前提：八张表已被删掉');

    var db = AppDatabase.forTesting(NativeDatabase(file));
    var repo = CognitiveProfileRepository(db);
    await repo.ensureSeeded(now: moment);

    final tasks = await repo.listTasks(enabledOnly: false);
    expect(tasks.length, kDefaultAssessmentTasks.length);
    expect(
      (await repo.listTasks()).length,
      kDefaultAssessmentTasks.where((task) => task.enabled).length,
      reason: '默认关闭的暂定任务不出现在可选列表里',
    );
    final abilities = await repo.readAbilities();
    expect(abilities.length, kAbilitySpecs.length);
    expect(abilities.first.source, EstimateSources.defaultPrior);
    expect(
      (await repo.readCognitiveParams()).length,
      kCognitiveParamSpecs.length,
    );

    final taskId = tasks.first.taskId;
    final sessionId = await repo.recordSession(
      taskId: taskId,
      designVersion: kAssessmentDesignVersion,
      device: AssessmentDevices.windowsMouse,
      startedAt: moment,
      completedAt: moment.add(const Duration(minutes: 2)),
      status: AssessmentSessionStatuses.completed,
      trials: const <TrialResult>[
        TrialResult(trialIndex: 0, blockIndex: 0, rtMs: 420, correct: true),
      ],
      metrics: const <MetricSample>[
        MetricSample(name: MetricNames.rtMedian, value: 420, nTrials: 1),
      ],
      qualityFlags: const <String>[QualityFlags.lowTrialCount],
    );
    await db.close();

    // 已经是 v41，重开不再迁移；数据必须原样还在。
    db = AppDatabase.forTesting(NativeDatabase(file));
    repo = CognitiveProfileRepository(db);
    final session = await repo.readSession(sessionId);
    expect(session, isNotNull);
    expect(session!.status, AssessmentSessionStatuses.completed);
    expect(session.qualityFlags, <String>[QualityFlags.lowTrialCount]);
    expect(session.metrics.single.value, 420);
    expect(
      (await repo.listTasks(enabledOnly: false)).length,
      kDefaultAssessmentTasks.length,
      reason: 'seed 幂等：重开不会再插一遍任务',
    );
    await db.close();
  });

  test('版本号被盖成 v40、但八张表已存在的库：迁移跳过建表且不丢数据', () async {
    final file = await buildDb(
      name: 'fake40',
      userVersion: 40,
      dropTables: false,
    );
    expect(tableNames(file.path).length, _cogTables.length);

    final db = AppDatabase.forTesting(NativeDatabase(file));
    final repo = CognitiveProfileRepository(db);
    expect(
      (await repo.listTasks(enabledOnly: false)).length,
      kDefaultAssessmentTasks.length,
      reason: '重复 createTable 没有被执行，原有行还在',
    );
    await repo.ensureSeeded(now: moment);
    expect(
      (await repo.listTasks(enabledOnly: false)).length,
      kDefaultAssessmentTasks.length,
    );
    await db.close();
    expect(tableNames(file.path).length, _cogTables.length);
  });
}
