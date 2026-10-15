/// 复习度量的只读工具（Q16）：让 agent 能读到"记忆效果"，而不是猜。
///
/// 为什么是工具而不是技能文档：`docs/ASSESSMENT_DESIGN.md:134` 明列"把度量接进
/// AI 工具"是未做项。没有它，用户问"我最近记东西到底行不行"时，agent 只有三个坏选择：
/// 猜、去翻原始复习日志自己算、或者说"我不知道"。前两个都会编数字。
///
/// 这个工具把**同一套领域逻辑**（`LearningMetrics` + `CalibrationReport`）
/// 直接暴露给模型，并且把诚实规则一起带过去：
///
/// - 留存率立刻可算（只需要复习结果）；
/// - 校准要求预测在判分**之前**落库，老行没有这个值、也不补算，所以这里会明说
///   "还没有样本"；样本不足 30 条、或结果只有一类时，`CalibrationReport` 拒绝给
///   系数，工具照原话转达，绝不自己凑一个偏置出来。
///
/// 只读：`readOnly => true`（两种权限模式下引擎都不会为它逐条询问），
/// 不改排程、不写任何表。
library;

import '../../../data/database/database.dart';
import '../../../domain/services/cognitive/learning_metrics.dart';
import '../../../domain/services/srs/dsr_memory.dart';
import '../../cognitive/application/calibration_reader.dart';
import '../domain/ai_tool.dart';

/// 读复习历史：留存率（按间隔分桶）+ 校准（Brier/ECE + 标定偏置）。
class ReviewMetricsTool extends AiTool {
  ReviewMetricsTool({required AppDatabase db}) : _db = db;

  final AppDatabase _db;

  /// 一次读多少条复习（`retentionSamples` 的默认值同款）。
  static const int defaultLimit = 5000;

  /// 上限：再多也读得动，但摘要会失真，且没必要。
  static const int maxLimit = 20000;

  /// 校准分箱上限（默认用领域层的 [defaultCalibrationBinCount]）。
  static const int maxBinCount = 20;

  /// 摘要里最多点几个留存桶。
  static const int maxBucketLines = 4;

  @override
  String get name => 'review_metrics';

  @override
  String get description => '读复习日志，给出记忆效果的两个读数：①**留存率**（按"距上次复习多少天"分桶，'
      '只用复习结果判定是否记得）；②**校准**（复习时判分**之前**模型预测的 R 与真实'
      '结果的对齐：Brier/ECE，以及标定偏置 b、斜率 a、是否显著）。'
      '回答"我最近的记忆效果怎么样""模型是不是过度自信""留存率掉在哪一段"时用它。'
      '**只读**：不写数据、不改复习排程、不生成题目。'
      '样本不足或没有预测值时它会明说算不出来——不要拿摘要之外的数字当成结论。';

  @override
  Map<String, Object?> get parameters => {
        'type': 'object',
        'properties': {
          'since_days': {
            'type': 'integer',
            'description': '只看最近多少天的复习（不传＝全部历史）。',
          },
          'calibration_bin_count': {
            'type': 'integer',
            'description':
                '校准分箱数，默认 $defaultCalibrationBinCount，范围 1..$maxBinCount。',
          },
          'include_buckets': {
            'type': 'boolean',
            'description': '是否返回留存分桶与校准分箱明细（默认 true）。',
          },
          'limit': {
            'type': 'integer',
            'description': '最多读多少条复习，默认 $defaultLimit，上限 $maxLimit。',
          },
        },
        'required': <String>[],
      };

  /// 只读工具：没有 action，这个值是"中性占位"，让引擎不逐条询问（见 [AiTool.riskFor]）。
  @override
  ToolRisk riskFor(String action) => ToolRisk.write;

  @override
  bool reversibleFor(String action) => true;

  @override
  bool get readOnly => true;

  @override
  bool get availableOnCurrentPlatform => true;

  @override
  Future<ToolResult> run(ToolInvocation invocation) async {
    try {
      final args = ToolArgs(invocation.arguments);

      final sinceDays = args.optInt('since_days');
      if (sinceDays != null && sinceDays < 0) {
        throw ToolArgError(
          '`since_days` 不能是负数（0 表示只看今天；不传表示全部历史），收到 $sinceDays',
        );
      }

      final binCount =
          args.optInt('calibration_bin_count') ?? defaultCalibrationBinCount;
      if (binCount < 1 || binCount > maxBinCount) {
        throw ToolArgError(
          '`calibration_bin_count` 必须在 1..$maxBinCount 之间，收到 $binCount',
        );
      }

      final limit = (args.optInt('limit') ?? defaultLimit).clamp(1, maxLimit);
      final includeBuckets = args.optBool('include_buckets') ?? true;

      final now = DateTime.now();
      final sinceMillis = sinceDays == null
          ? null
          : now.subtract(Duration(days: sinceDays)).millisecondsSinceEpoch;

      final reading = await readCalibrationReading(
        _db,
        sinceMillis: sinceMillis,
        limit: limit,
        calibrationBinCount: binCount,
      );
      final metrics = reading.metrics;
      final report = reading.report;

      final payload = <String, Object?>{
        'schema': 'mindnet.review_metrics/1',
        'since_days': sinceDays,
        'limit': limit,
        'reviewed': metrics.reviewedCount,
        'recalled': metrics.recalledCount,
        'retention': DsrMemory.round6(metrics.retention),
        'calibrated_samples': metrics.calibratedCount,
        'brier':
            metrics.brier == null ? null : DsrMemory.round6(metrics.brier!),
        'ece': metrics.ece == null ? null : DsrMemory.round6(metrics.ece!),
        'calibration': report.toJson(),
        if (includeBuckets)
          'buckets': [for (final bucket in metrics.buckets) bucket.toJson()],
        if (includeBuckets)
          'bins': [for (final bin in metrics.bins) bin.toJson()],
      };

      if (metrics.isEmpty) {
        return ToolResult(
          ok: true,
          summary: '复习日志里还没有记录：留存率和校准都要靠复习攒出来，'
              '现在没有任何数字可讲——我不会编一个。',
          modelResult: payload,
        );
      }

      final lines = <String>[
        '共 ${metrics.reviewedCount} 次复习，整体记住 '
            '${_percent(metrics.retention)}（${metrics.recalledCount} '
            '/${metrics.reviewedCount}）。',
      ];

      final informative = <RetentionBucket>[
        for (final bucket in metrics.buckets)
          if (bucket.samples > 0) bucket,
      ];
      if (informative.isNotEmpty) {
        final shown = informative.length <= maxBucketLines
            ? informative
            : informative.sublist(informative.length - maxBucketLines);
        lines.add(
          '留存率分桶：${shown.map((b) => '${_range(b)}天 ${_percent(b.retention)}'
              '（${b.samples} 次）').join('；')}。',
        );
      } else {
        lines.add('每个桶都还没有样本（第一次复习没有"间隔"可言，不进分桶）。');
      }

      if (report.samples == 0) {
        lines.add(
          '校准还没有样本：预测值从 v11 起才在判分前落库，历史复习没有这个值、'
          '也不补算——所以现在只有留存率，没有"准不准"。',
        );
      } else {
        lines.add(
          '校准（${report.samples} 条带预测）：Brier '
          '${metrics.brier == null ? '—' : DsrMemory.round6(metrics.brier!)}、ECE '
          '${metrics.ece == null ? '—' : DsrMemory.round6(metrics.ece!)}。'
          '${report.summaryZh}',
        );
      }

      return ToolResult(
        ok: true,
        summary: lines.join(' '),
        modelResult: payload,
      );
    } on ToolArgError catch (e) {
      return ToolResult.failure(e.message);
    }
  }

  static String _percent(double ratio) =>
      '${(ratio * 100).toStringAsFixed(1)}%';

  static String _range(RetentionBucket bucket) {
    if (!bucket.hiDays.isFinite) return '${_trim(bucket.loDays)}+';
    return '${_trim(bucket.loDays)}–${_trim(bucket.hiDays)}';
  }

  static String _trim(double days) {
    if (days == days.roundToDouble()) return days.toInt().toString();
    return days.toStringAsFixed(1);
  }
}
