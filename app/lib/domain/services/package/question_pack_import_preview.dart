/// 题库包（.tqb）导入前预检聚合（纯逻辑）。
///
/// 把 [QuestionPackManifest]、题目记录列表与 [QuestionPackImportPlan] 合成一份
/// 给导入对话框直接显示的预检结果：清单计数与实际内容对账、是否全新增、
/// 合并去重后的提示，以及确定性的中文摘要 [QuestionPackImportPreview.summaryZh]。
///
/// 本文件不读库、不碰 IO、不修改入参：容器层（zip 解包）拿到三个对象后调用
/// [buildQuestionPackImportPreview] 即可；plan 与 records 的一一对应由调用方保证。
library;

import 'question_pack_manifest.dart';
import 'question_pack_plan.dart';
import 'question_pack_record.dart';

/// 题库包导入前预检结果。
///
/// 值对象：计数与提示都是快照，构造后不再变化；[warnings] 与 [missingTagPaths]
/// 在通过 [buildQuestionPackImportPreview] 构造时是不可变列表。
class QuestionPackImportPreview {
  const QuestionPackImportPreview({
    required this.manifestQuestionCount,
    required this.manifestMediaCount,
    required this.recordCount,
    required this.mediaCount,
    required this.appVersion,
    required this.exportedAt,
    required this.createCount,
    required this.skipCount,
    required this.missingTagCount,
    required this.warnings,
    required this.missingTagPaths,
    this.snapshotLikeCount = 0,
  });

  /// 包清单（manifest.json）里写的题目条数。
  final int manifestQuestionCount;

  /// 包清单里写的媒体条数。
  final int manifestMediaCount;

  /// 实际读到的题目条数（records.length）。
  final int recordCount;

  /// 实际读到的媒体条数（所有 record.media 之和）。
  final int mediaCount;

  /// 导出时的 App 版本号（可空字符串，来自包清单）。
  final String appVersion;

  /// 导出时间（来自包清单；通过 [buildQuestionPackImportPreview] 构造时必非空，
  /// 保留可空是为了让容器层在清单缺失时间时也能表达）。
  final DateTime? exportedAt;

  /// 会新建的题目数（来自导入计划）。
  final int createCount;

  /// 会跳过的题目数（来自导入计划）。
  final int skipCount;

  /// 题库里不存在的标签路径个数（等于 [missingTagPaths] 的长度）。
  final int missingTagCount;

  /// 「整卡快照」题数：题干里有两处以上「［图N］」占位、但题干图（role 为
  /// stem）只有 1 张整题截图的题。默认 0；通过
  /// [buildQuestionPackImportPreview] 构造时逐条统计，直接构造时可显式传入。
  final int snapshotLikeCount;

  /// 合并后的提示：先包清单层（题数/媒体数对不上），再整卡快照提示
  /// （见 [snapshotLikeCount]），再导入计划原顺序，完全相同字符串只保留
  /// 第一次出现。
  final List<String> warnings;

  /// 包里出现、题库里没有的标签路径（原样来自导入计划）。
  final List<String> missingTagPaths;

  /// 包里一道题都没有。
  bool get isEmpty => recordCount == 0;

  /// 有需要用户注意的提示。
  bool get hasWarnings => warnings.isNotEmpty;

  /// 包里每道题都会新建（空包不算、有跳过就不算）。
  bool get isFullyNew => createCount > 0 && skipCount == 0;

  /// 包清单写的题数/媒体数与实际读到的对不上。
  bool get hasManifestMismatch =>
      manifestQuestionCount != recordCount || manifestMediaCount != mediaCount;

  /// 确定性的中文摘要，每行一条；至少两行，最多五行。
  ///
  /// 第 1 行：包里共 N 道题、M 张配图（导出自 App X，yyyy-MM-dd HH:mm）；
  /// 括号内按需出现，时间不转换时区（按 [exportedAt] 自身的年月日时分格式化）。
  /// 第 2 行：仅当 [snapshotLikeCount] 大于 0（整卡快照提示）。
  /// 第 3 行：新增 / 跳过 / 两者都有 / 都没有可导入的新题。
  /// 第 4 行：仅当 [missingTagCount] 大于 0。
  /// 第 5 行：仅当 [warnings] 非空。
  List<String> get summaryZh {
    final List<String> lines = <String>[
      _firstSummaryLine(
        questionCount: recordCount,
        mediaCount: mediaCount,
        appVersion: appVersion,
        exportedAt: exportedAt,
      ),
    ];
    if (snapshotLikeCount > 0) {
      lines.add('整卡快照：$snapshotLikeCount 道题（公式在整图里）');
    }
    lines.add(
      _secondSummaryLine(createCount: createCount, skipCount: skipCount),
    );
    if (missingTagCount > 0) {
      lines.add('有 $missingTagCount 个标签在本题库里不存在，相关题导入后不挂这些标签');
    }
    if (warnings.isNotEmpty) {
      lines.add('另有 ${warnings.length} 条提示（见下）');
    }
    return List<String>.unmodifiable(lines);
  }

  /// snake_case 机器可读；[exportedAt] 为空时 `exported_at` 输出 null。
  Map<String, Object?> toJson() => <String, Object?>{
        'manifest_question_count': manifestQuestionCount,
        'manifest_media_count': manifestMediaCount,
        'record_count': recordCount,
        'media_count': mediaCount,
        'app_version': appVersion,
        'exported_at': exportedAt?.toIso8601String(),
        'create_count': createCount,
        'skip_count': skipCount,
        'missing_tag_count': missingTagCount,
        'snapshot_like_count': snapshotLikeCount,
        'warnings': <String>[...warnings],
        'missing_tag_paths': <String>[...missingTagPaths],
      };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is QuestionPackImportPreview &&
        other.manifestQuestionCount == manifestQuestionCount &&
        other.manifestMediaCount == manifestMediaCount &&
        other.recordCount == recordCount &&
        other.mediaCount == mediaCount &&
        other.appVersion == appVersion &&
        other.exportedAt == exportedAt &&
        other.createCount == createCount &&
        other.skipCount == skipCount &&
        other.missingTagCount == missingTagCount &&
        other.snapshotLikeCount == snapshotLikeCount &&
        _listEquals<String>(other.warnings, warnings) &&
        _listEquals<String>(other.missingTagPaths, missingTagPaths);
  }

  @override
  int get hashCode => Object.hash(
        manifestQuestionCount,
        manifestMediaCount,
        recordCount,
        mediaCount,
        appVersion,
        exportedAt,
        createCount,
        skipCount,
        missingTagCount,
        snapshotLikeCount,
        Object.hashAll(warnings),
        Object.hashAll(missingTagPaths),
      );

  @override
  String toString() => 'QuestionPackImportPreview(recordCount: $recordCount, '
      'mediaCount: $mediaCount, createCount: $createCount, '
      'skipCount: $skipCount, missingTagCount: $missingTagCount, '
      'snapshotLikeCount: $snapshotLikeCount, '
      'warnings: ${warnings.length})';
}

/// 汇总题库包的导入前预检。
///
/// [manifest] 来自包清单，[records] 来自 questions.json，[plan] 来自
/// [planQuestionPackImport]；三者都不读库、不修改入参。
QuestionPackImportPreview buildQuestionPackImportPreview({
  required QuestionPackManifest manifest,
  required List<QuestionPackRecord> records,
  required QuestionPackImportPlan plan,
}) {
  var mediaCount = 0;
  var snapshotLikeCount = 0;
  for (final QuestionPackRecord record in records) {
    mediaCount += record.media.length;
    if (_looksLikeSnapshotRecord(record)) {
      snapshotLikeCount++;
    }
  }

  final List<String> warnings = <String>[];
  final Set<String> seen = <String>{};
  void addWarning(String warning) {
    if (seen.add(warning)) {
      warnings.add(warning);
    }
  }

  if (manifest.questionCount != records.length) {
    addWarning('包清单写着 ${manifest.questionCount} 道题，实际读到 ${records.length} 道');
  }
  if (manifest.mediaCount != mediaCount) {
    addWarning('包清单写着 ${manifest.mediaCount} 张配图，实际读到 $mediaCount 张');
  }
  if (snapshotLikeCount > 0) {
    addWarning(
      '这个包是整卡快照包：$snapshotLikeCount 道题的题干只有一张整题截图，'
      '公式以「［图N］」占位显示；详情页会按原题整图展示。',
    );
  }
  for (final String warning in plan.warnings) {
    addWarning(warning);
  }

  return QuestionPackImportPreview(
    manifestQuestionCount: manifest.questionCount,
    manifestMediaCount: manifest.mediaCount,
    recordCount: records.length,
    mediaCount: mediaCount,
    appVersion: manifest.appVersion,
    exportedAt: manifest.exportedAt,
    createCount: plan.createCount,
    skipCount: plan.skipCount,
    missingTagCount: plan.missingTagPaths.length,
    snapshotLikeCount: snapshotLikeCount,
    warnings: List<String>.unmodifiable(warnings),
    missingTagPaths: List<String>.unmodifiable(plan.missingTagPaths),
  );
}

String _firstSummaryLine({
  required int questionCount,
  required int mediaCount,
  required String appVersion,
  required DateTime? exportedAt,
}) {
  final String head = '包里共 $questionCount 道题、$mediaCount 张配图';
  final List<String> details = <String>[];
  final String version = appVersion.trim();
  if (version.isNotEmpty) {
    details.add('导出自 App $version');
  }
  if (exportedAt != null) {
    details.add(_formatToMinute(exportedAt));
  }
  if (details.isEmpty) {
    return head;
  }
  return '$head（${details.join('，')}）';
}

String _secondSummaryLine({required int createCount, required int skipCount}) {
  if (createCount == 0 && skipCount == 0) {
    return '包里没有可以导入的新题';
  }
  final List<String> parts = <String>[];
  if (createCount > 0) {
    parts.add('导入后新增 $createCount 道');
  }
  if (skipCount > 0) {
    parts.add('跳过 $skipCount 道（题库里已有同一道题，或包里重复）');
  }
  return parts.join('，');
}

String _formatToMinute(DateTime value) {
  String pad2(int number) => number.toString().padLeft(2, '0');
  final String year = value.year.toString().padLeft(4, '0');
  return '$year-${pad2(value.month)}-${pad2(value.day)} '
      '${pad2(value.hour)}:${pad2(value.minute)}';
}

bool _listEquals<T>(List<T> left, List<T> right) {
  if (identical(left, right)) {
    return true;
  }
  if (left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) {
      return false;
    }
  }
  return true;
}

/// 命中「整卡快照」特征的最少占位次数。
const int _kSnapshotLikeMinPlaceholders = 2;

/// 「［图N］」占位，与 question_stem_segments.dart 里的正则同一口径：
/// 全角/半角方括号与【】、全角数字、N 为 1~3 位。
final RegExp _figurePlaceholderPattern = RegExp(
  r'[［\[【]\s*图\s*([0-9０-９]{1,3})\s*[］\]】]',
);

/// 这道题像不像「整卡快照」：题干里「［图N］」占位出现两次以上，且题干图
/// （role 为 stem）恰好 1 张（整题截图）。answer/solution 截图不计入。
bool _looksLikeSnapshotRecord(QuestionPackRecord record) {
  if (_figurePlaceholderPattern.allMatches(record.stem).length <
      _kSnapshotLikeMinPlaceholders) {
    return false;
  }
  var stemMedia = 0;
  for (final QuestionPackMedia item in record.media) {
    if (item.role == 'stem') {
      stemMedia++;
    }
  }
  return stemMedia == 1;
}
