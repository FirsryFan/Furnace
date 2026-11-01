/// Thread 顶栏精力预测的**应用层**读取：数据库 → [EnergyPredictionInput] →
/// [EnergyPredictor.predict]。
///
/// 领域分工（与 `domain/services/cognitive/energy_prediction.dart` 的库注释一致）：
/// 预测器是纯逻辑，不碰数据库、不读时钟；本文件是 UI 侧唯一的数据入口，负责
///
/// 1. 从 `completion_logs` / `review_logs` 读最近 [kEnergyHistoryDays] 天的记录，
/// 2. 从单行表 `thread_states` 读最近一次手填的精力值与时间戳
///    （`thread_states.energy` + `updated_at`，tables.dart:590-601），
/// 3. 把行投影成 [EnergyCompletion] / [EnergyReview] / [EnergyManualOverride]，
///    再调用纯逻辑预测器。
///
/// "没有数据"不是一个错误：预测器会返回中性先验与置信度 0、`shouldAutoSet`
/// false（见预测器"输出怎么读"），UI 据此**不能**自动写入一个编出来的值。
///
/// 时钟可注入：测试把 `now` 钉在某个时刻，生产用 [DateTime.now]。时区偏移取自
/// 传入的 `now`（`DateTime.utc` 为 0），这样测试与本机时区无关——与预测器测试的
/// 做法一致。
library;

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/state/data_revision.dart';
import '../../../data/database/app_database_provider.dart';
import '../../../data/database/database.dart';
import '../../../domain/services/cognitive/energy_prediction.dart';

/// 一条预测 + 预测器本身不暴露的一个 UI 事实：顶栏当前值是不是用户自己最近
/// 手填的覆盖值（"手动"徽标）。
///
/// 为什么不从 [EnergyPrediction] 反推：`confidence == 1.0 && !shouldAutoSet`
/// 也能被"同一天 8 条记录"的证据路径命中（置信度被 clamp 到 100%），那会把手填
/// 徽标错挂到纯预测上。这里用与预测器规则 1 相同的 [kEnergyManualWindow] 显式
/// 判定，口径同源。
class EnergyPredictionSnapshot {
  const EnergyPredictionSnapshot({
    required this.prediction,
    required this.manualOverrideActive,
  });

  /// 纯逻辑预测器的输出。
  final EnergyPrediction prediction;

  /// 顶栏的 `thread_states.energy` 是否仍在 [kEnergyManualWindow] 窗口内。
  final bool manualOverrideActive;
}

/// 把数据库里的精力证据投影成 [EnergyPredictionInput] 并跑预测。
///
/// 只读：不写任何表。故意不复用 `ThreadStateRepository`，因为预测输入是
/// "行的投影"，不需要 `ensureState()` 的建行副作用。
class EnergyPredictionReader {
  EnergyPredictionReader(this._db, {DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final DateTime Function() _clock;

  /// 读取并预测。[now] 省略时用注入的时钟（生产 = [DateTime.now]）。
  Future<EnergyPredictionSnapshot> read({DateTime? now}) async {
    final moment = now ?? _clock();
    final cutoffMs = moment
        .subtract(const Duration(days: kEnergyHistoryDays))
        .millisecondsSinceEpoch;

    // 只读窗口下界；晚于 now 的记录交给预测器按"时钟异常"忽略并写进依据，
    // 这里不提前吞掉（预测器要在 basis 里如实说明）。
    final completionRows = await (_db.select(_db.completionLogs)
          ..where((t) => t.completedAt.isBiggerOrEqualValue(cutoffMs)))
        .get();
    final reviewRows = await (_db.select(_db.reviewLogs)
          ..where((t) => t.reviewedAt.isBiggerOrEqualValue(cutoffMs)))
        .get();
    final stateRows = await _db.select(_db.threadStates).get();

    final manual = _manualOf(stateRows);
    final prediction = EnergyPredictor.predict(
      EnergyPredictionInput(
        now: moment,
        completions: <EnergyCompletion>[
          for (final row in completionRows)
            EnergyCompletion(
              completedAt: DateTime.fromMillisecondsSinceEpoch(row.completedAt),
              actualMinutes: row.actualMinutes,
              estimateMinutes: row.estimateMinutes,
              includeInModel: row.includeInModel,
            ),
        ],
        reviews: <EnergyReview>[
          for (final row in reviewRows)
            EnergyReview(
              reviewedAt: DateTime.fromMillisecondsSinceEpoch(row.reviewedAt),
              result: EnergyReviewResult.fromLog(
                correct: row.correct,
                ratingFsrs: row.ratingFsrs,
                rating: row.rating,
              ),
            ),
        ],
        manual: manual,
        // 东八区 = +8h；DateTime.utc(...) 的偏移是 0，所以测试与本机时区无关。
        utcOffset: moment.timeZoneOffset,
      ),
    );

    return EnergyPredictionSnapshot(
      prediction: prediction,
      manualOverrideActive: _isFreshManual(manual, moment),
    );
  }

  /// 单行表的投影。只有 `energy` 与 `updated_at` 都在时才是一条可定位的
  /// 手填值；有值没时间戳的老行无法放进 2 小时窗口，宁可不采用也不猜时刻。
  static EnergyManualOverride? _manualOf(List<ThreadState> stateRows) {
    if (stateRows.isEmpty) {
      return null;
    }
    final state = stateRows.first;
    final energy = state.energy;
    final updatedAt = state.updatedAt;
    if (energy == null || updatedAt == null) {
      return null;
    }
    return EnergyManualOverride(
      level: energy,
      recordedAt: DateTime.fromMillisecondsSinceEpoch(updatedAt),
    );
  }
}

/// 预测器规则 1 的同一口径：`now - recordedAt ∈ [0, kEnergyManualWindow)`。
bool _isFreshManual(EnergyManualOverride? manual, DateTime now) {
  if (manual == null) {
    return false;
  }
  final age = now.difference(manual.recordedAt);
  return !age.isNegative && age < kEnergyManualWindow;
}

/// 读者本身（测试可直接构造，注入时钟与内存库）。
final energyPredictionReaderProvider = Provider<EnergyPredictionReader>((ref) {
  return EnergyPredictionReader(ref.watch(appDatabaseProvider));
});

/// Thread 顶栏订阅的实时预测；任何提交后的数据库写入都会让它重算（与
/// `threadStateProvider` 同一条纪律），UI 写完精力后也会显式 invalidate。
final energyPredictionProvider =
    FutureProvider<EnergyPredictionSnapshot>((ref) async {
  ref.watchDatabaseRevision();
  return ref.watch(energyPredictionReaderProvider).read();
});
