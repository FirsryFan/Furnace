/// 标定的读取层：把"复习日志"喂给 `CalibrationReport`（Q16 标定协议 v1）。
///
/// 与 `library_diagnosis_reader.dart` 分开是有意的：
///
/// - 诊断读的是**模型自己的状态**（`card_states` / `object_tags` / boost），它回答
///   "现在哪里危险"；
/// - 标定读的只有 `review_logs`，它回答"模型当时说的准不准"。这是全 app 唯一一条
///   **外部**检查：读数页的"学习效果"卡片之所以可信，就是因为它的数字不来自模型的
///   自我叙述。把两者塞进一个 reader 会让"这条结论到底是自证还是被检验"变得模糊。
///
/// 没有 Flutter、没有 Riverpod：谁调用谁提供 `AppDatabase`。
library;

import '../../../data/database/database.dart';
import '../../../data/repositories/anki_repository.dart';
import '../../../domain/services/cognitive/calibration.dart';
import '../../../domain/services/cognitive/learning_metrics.dart';

/// 一次读取的完整结果：留存读数 + 校准结论。
///
/// 两半共用同一批样本（同一次 `retentionSamples()`），所以界面上的"留存率"与
/// "偏置"讲的一定是同一批复习，不会一边算 5000 条、另一边算 200 条。
class CalibrationReading {
  const CalibrationReading({required this.report, required this.metrics});

  /// 标定结论（能不能看、往哪偏）。
  final CalibrationReport report;

  /// 留存率与 Brier / ECE 分箱（`learning_metrics.dart`）。
  final LearningMetrics metrics;

  bool get isEmpty => metrics.isEmpty && report.samples == 0;
}

/// 读一次复习历史，产出留存读数 + 校准结论。
///
/// [sinceMillis] 只影响样本范围（AI 工具的 `since_days` 会换算成它）；
/// [bucketEdges] / [calibrationBinCount] 直接透给 `LearningMetrics.read`，
/// 保持与读数页同一套默认值。
Future<CalibrationReading> readCalibrationReading(
  AppDatabase db, {
  int? sinceMillis,
  int limit = 5000,
  List<double> bucketEdges = defaultIntervalBucketEdgesDays,
  int calibrationBinCount = defaultCalibrationBinCount,
}) async {
  final samples = await AnkiRepository(db).retentionSamples(
    sinceMillis: sinceMillis,
    limit: limit,
  );
  return CalibrationReading(
    report: CalibrationReport.read(samples: samples),
    metrics: LearningMetrics.read(
      samples: samples,
      bucketEdges: bucketEdges,
      calibrationBinCount: calibrationBinCount,
    ),
  );
}

/// 只要校准结论的那一层（不需要留存分桶时用）。
Future<CalibrationReport> readCalibrationReport(
  AppDatabase db, {
  int? sinceMillis,
  int limit = 5000,
}) async {
  final reading = await readCalibrationReading(
    db,
    sinceMillis: sinceMillis,
    limit: limit,
  );
  return reading.report;
}
