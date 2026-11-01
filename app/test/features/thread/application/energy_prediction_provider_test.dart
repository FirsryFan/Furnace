import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/anki_repository.dart';
import 'package:furnace/data/repositories/task_repository.dart';
import 'package:furnace/data/repositories/thread_state_repository.dart';
import 'package:furnace/domain/services/cognitive/energy_prediction.dart';
import 'package:furnace/features/thread/application/energy_prediction_provider.dart';

/// D13 的数据层验收：`energy_prediction_provider` 把 completion_logs /
/// review_logs / thread_states 投影成预测器输入，规则本身由
/// `energy_prediction_test.dart`（另一个 owner）钉住；这里只钉"读表与投影"。
void main() {
  late AppDatabase db;
  late EnergyPredictionReader reader;
  late String taskId;
  var seq = 0;

  /// 正午 UTC：时区偏移 0、不触发昼夜代理，预测结果只取决于造的数据。
  final now = DateTime.utc(2026, 11, 1, 12);

  setUp(() async {
    // 真机连接器装的就是这个 instrumentWrites（database.dart:1734/1744）：
    // 任何提交后的写入都广播到 DataChangeBus。装上它，下面"provider 接线"
    // 一组才能验证生产路径上的自动重算，而不是只验证手动 invalidate。
    db = AppDatabase.forTesting(instrumentWrites(NativeDatabase.memory()));
    reader = EnergyPredictionReader(db, clock: () => now);
    final task = await TaskRepository(db).createTask(title: '任务');
    taskId = task.id;
  });

  tearDown(() async {
    await db.close();
  });

  /// `completion_logs.task_id` 有外键，所以每条都挂在 setUp 建的任务上。
  Future<void> seedCompletion({
    required DateTime at,
    int? actualMinutes,
    int? estimateMinutes,
    bool includeInModel = true,
  }) async {
    final ms = at.millisecondsSinceEpoch;
    await db.into(db.completionLogs).insert(
          CompletionLogsCompanion.insert(
            id: 'cl-${seq++}',
            taskId: taskId,
            title: '完成的任务',
            completedAt: ms,
            actualMinutes: Value(actualMinutes),
            estimateMinutes: Value(estimateMinutes),
            includeInModel: Value(includeInModel),
            createdAt: ms,
          ),
        );
  }

  Future<void> seedReview({
    required DateTime at,
    int rating = 3,
    int? ratingFsrs,
    int? correct,
  }) async {
    final anki = AnkiRepository(db);
    final point = await anki.createKnowledgePoint(
      title: '光合作用',
      content: '场所是叶绿体',
    );
    final template = await anki.createTemplate(
      knowledgePointId: point.id,
      type: 'fill_blank',
      question: '光合作用的场所是？',
      answer: '叶绿体',
    );
    final state = await anki.getOrCreateCardState(template.id);
    await anki.addReviewLog(
      cardStateId: state.id,
      cardTemplateId: template.id,
      rating: rating,
      ratingFsrs: ratingFsrs,
      correct: correct,
      reviewedAt: at.millisecondsSinceEpoch,
    );
  }

  Future<void> seedManual({required int energy, required DateTime at}) async {
    await ThreadStateRepository(db).updateState(energy: energy, updatedAt: at);
  }

  group('无数据', () {
    test('没有日志也没有手填值 ⇒ 中性档、置信 0、不自动设定', () async {
      final snapshot = await reader.read();

      expect(snapshot.prediction.level, kEnergyNeutralLevel);
      expect(snapshot.prediction.confidence, 0.0);
      expect(snapshot.prediction.shouldAutoSet, isFalse);
      expect(snapshot.manualOverrideActive, isFalse);
      expect(snapshot.prediction.basis.last, kEnergyPredictionUncalibratedNote);
    });

    test('窗口外的记录不算证据（10 天前）', () async {
      await seedCompletion(
        at: now.subtract(const Duration(days: 10)),
        actualMinutes: 20,
        estimateMinutes: 30,
      );

      final snapshot = await reader.read();

      expect(snapshot.prediction.level, kEnergyNeutralLevel);
      expect(snapshot.prediction.confidence, 0.0);
      expect(
        snapshot.prediction.basis.first,
        contains('没有完成/复习记录'),
      );
    });
  });

  group('有数据', () {
    test('完成记录被投影成输入：吞吐快 ⇒ 升 1 档、置信 32%', () async {
      await seedCompletion(
        at: now.subtract(const Duration(hours: 26)),
        actualMinutes: 30,
        estimateMinutes: 40,
      );
      await seedCompletion(
        at: now.subtract(const Duration(hours: 2)),
        actualMinutes: 20,
        estimateMinutes: 30,
      );

      final snapshot = await reader.read();

      // 中性 5 + 1（两条可建模记录实际/预估加权 ≈0.70 ≤ 0.8）。
      expect(snapshot.prediction.level, 6);
      // 2 条可用证据 ×12% + 最近 24h 内有记录 +8% = 32%。
      expect(snapshot.prediction.confidence, closeTo(0.32, 1e-9));
      expect(snapshot.prediction.shouldAutoSet, isFalse);
      expect(snapshot.manualOverrideActive, isFalse);
      expect(
        snapshot.prediction.basis.any((line) => line.contains('实际用时')),
        isTrue,
      );
    });

    test('复习结果映射生效：24h 内 3 次 Again ⇒ 降 1 档', () async {
      for (var i = 0; i < 3; i++) {
        await seedReview(
          at: now.subtract(Duration(minutes: 6 + i)),
          rating: 0,
          ratingFsrs: 1,
        );
      }

      final snapshot = await reader.read();

      // 中性 5 - 1（3 条"完全没想起来"，占比 100% ≥ 50%）。
      expect(snapshot.prediction.level, 4);
      // 3 条已知结果 ×12% + 最近 24h 内有记录 +8% = 44%。
      expect(snapshot.prediction.confidence, closeTo(0.44, 1e-9));
      expect(snapshot.prediction.shouldAutoSet, isFalse);
    });
  });

  group('手工值优先', () {
    test('2 小时内手填值直接采用：手填值胜过证据、置信 1.0、不自动设定', () async {
      await seedCompletion(
        at: now.subtract(const Duration(hours: 26)),
        actualMinutes: 30,
        estimateMinutes: 40,
      );
      await seedCompletion(
        at: now.subtract(const Duration(hours: 2)),
        actualMinutes: 20,
        estimateMinutes: 30,
      );
      final recordedAt = now.subtract(const Duration(hours: 1));
      await seedManual(energy: 8, at: recordedAt);

      final snapshot = await reader.read();

      expect(snapshot.prediction.level, 8);
      expect(snapshot.prediction.confidence, 1.0);
      expect(snapshot.prediction.shouldAutoSet, isFalse);
      expect(snapshot.manualOverrideActive, isTrue);
      expect(
        snapshot.prediction.expiresAt.millisecondsSinceEpoch,
        recordedAt.millisecondsSinceEpoch + kEnergyManualWindow.inMilliseconds,
      );
    });

    test('超过 2 小时的手填值不算覆盖：回落到证据预测，徽标不亮', () async {
      await seedCompletion(
        at: now.subtract(const Duration(hours: 26)),
        actualMinutes: 30,
        estimateMinutes: 40,
      );
      await seedCompletion(
        at: now.subtract(const Duration(hours: 2)),
        actualMinutes: 20,
        estimateMinutes: 30,
      );
      await seedManual(
        energy: 8,
        at: now.subtract(const Duration(hours: 3)),
      );

      final snapshot = await reader.read();

      expect(snapshot.prediction.level, 6);
      expect(snapshot.manualOverrideActive, isFalse);
      expect(snapshot.prediction.basis.first, contains('手工值已过期'));
    });

    test('有手填值但没有 updated_at 的老行 ⇒ 不当作覆盖，也不编时间', () async {
      await db.into(db.threadStates).insert(
            ThreadStatesCompanion.insert(
              energy: const Value<int?>(7),
              createdAt: now.millisecondsSinceEpoch,
            ),
          );

      final snapshot = await reader.read();

      expect(snapshot.manualOverrideActive, isFalse);
      expect(snapshot.prediction.level, kEnergyNeutralLevel);
      expect(snapshot.prediction.confidence, 0.0);
    });
  });

  group('provider 接线', () {
    test('生产写入钩子 ⇒ 手填后 provider 自动重算（不靠手动 invalidate）', () async {
      final container = ProviderContainer(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
      );
      addTearDown(container.dispose);

      final before = await container.read(energyPredictionProvider.future);
      expect(before.manualOverrideActive, isFalse);

      await ThreadStateRepository(db).updateState(
        energy: 7,
        updatedAt: DateTime.now().subtract(const Duration(minutes: 5)),
      );
      // 让写入钩子的 DataChangeBus 事件送达 DataRevision。
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final after = await container.read(energyPredictionProvider.future);
      expect(after.manualOverrideActive, isTrue);
      expect(after.prediction.level, 7);
      expect(after.prediction.confidence, 1.0);
    });
  });
}
