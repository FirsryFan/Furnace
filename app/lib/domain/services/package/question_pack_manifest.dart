/// 题库包（.tqb）包清单编解码（纯逻辑）。
///
/// 题库包是一个 zip，根目录的 `manifest.json` 描述包的格式、版本与计数，
/// 具体题目在 `questions.json`（见 question_pack_record.dart），配图在 `media/`。
///
/// 本文件不 import dart:io、不碰 drift/Flutter：zip 容器层、数据读取层、UI 各自复用。
/// 解码入参必须是 `jsonDecode` 之后的 Map（直接传 JSON 文本会抛 [QuestionPackException]）。
library;

import 'dart:convert';

/// 题库包的格式标识，写进 `manifest.json` 的 `format` 字段。
const String kQuestionPackFormat = 'furnace-question-bank';

/// 当前题库包版本，写进 `manifest.json` 的 `version` 字段。
const int kQuestionPackVersion = 1;

/// 题库包结构错误（清单或题目记录不合法时抛出）。
///
/// [message] 是给人看的中文说明，[path] 指向出错位置（如 `manifest.version`、
/// `questions[3].stem`）；容器层可以直接把这两项拼进提示。
class QuestionPackException implements Exception {
  const QuestionPackException(this.message, {this.path});

  /// 中文错误说明。
  final String message;

  /// 出错位置（可空）。
  final String? path;

  @override
  String toString() => path == null
      ? 'QuestionPackException: $message'
      : 'QuestionPackException: $message（$path）';
}

/// 题库包包清单（`manifest.json`）。
class QuestionPackManifest {
  const QuestionPackManifest({
    required this.exportedAt,
    this.appVersion = '',
    required this.questionCount,
    required this.mediaCount,
    this.generatedBy = 'Furnace',
  });

  /// 导出时间。
  final DateTime exportedAt;

  /// 导出时 App 的版本号（可空字符串）。
  final String appVersion;

  /// 题目条数（>= 0）。
  final int questionCount;

  /// 媒体文件条数（>= 0）。
  final int mediaCount;

  /// 生成者标识，默认 `Furnace`。
  final String generatedBy;

  /// 固定格式标识，等于 [kQuestionPackFormat]。
  String get format => kQuestionPackFormat;

  /// 固定格式版本，等于 [kQuestionPackVersion]。
  int get version => kQuestionPackVersion;

  /// 编码成 `manifest.json` 的对象（键顺序恒定）。
  Map<String, Object?> toJson() => <String, Object?>{
        'format': format,
        'version': version,
        'exported_at': exportedAt.toIso8601String(),
        'app_version': appVersion,
        'question_count': questionCount,
        'media_count': mediaCount,
        'generated_by': generatedBy,
      };

  /// 从已解码的 JSON 对象还原清单。
  ///
  /// 未知字段忽略；缺省的可选字段按空串；任何不合法都抛 [QuestionPackException]。
  factory QuestionPackManifest.fromJson(
    Map<String, Object?> json, {
    String path = 'manifest.json',
  }) {
    final Object? format = json['format'];
    if (format != kQuestionPackFormat) {
      throw QuestionPackException(
        '不是题库包：format 必须是 $kQuestionPackFormat',
        path: '$path.format',
      );
    }
    final Object? version = json['version'];
    if (version is! int || version != kQuestionPackVersion) {
      throw QuestionPackException(
        '不认识的题库包版本：${_describeValue(version)}（只支持 $kQuestionPackVersion）',
        path: '$path.version',
      );
    }
    final Object? rawExportedAt = json['exported_at'];
    final DateTime? exportedAt =
        rawExportedAt is String ? DateTime.tryParse(rawExportedAt) : null;
    if (exportedAt == null) {
      throw QuestionPackException(
        'exported_at 不是合法的 ISO-8601 时间：${_describeValue(rawExportedAt)}',
        path: '$path.exported_at',
      );
    }
    final int questionCount = _requireNonNegativeInt(
      json['question_count'],
      path: '$path.question_count',
      fieldName: 'question_count',
    );
    final int mediaCount = _requireNonNegativeInt(
      json['media_count'],
      path: '$path.media_count',
      fieldName: 'media_count',
    );
    final String appVersion =
        _optionalString(json['app_version'], path: '$path.app_version') ?? '';
    final String generatedBy =
        _optionalString(json['generated_by'], path: '$path.generated_by') ?? '';
    return QuestionPackManifest(
      exportedAt: exportedAt,
      appVersion: appVersion,
      questionCount: questionCount,
      mediaCount: mediaCount,
      generatedBy: generatedBy,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is QuestionPackManifest &&
        other.exportedAt == exportedAt &&
        other.appVersion == appVersion &&
        other.questionCount == questionCount &&
        other.mediaCount == mediaCount &&
        other.generatedBy == generatedBy;
  }

  @override
  int get hashCode => Object.hash(
        exportedAt,
        appVersion,
        questionCount,
        mediaCount,
        generatedBy,
      );

  @override
  String toString() => 'QuestionPackManifest(exportedAt: $exportedAt, '
      'appVersion: $appVersion, questionCount: $questionCount, '
      'mediaCount: $mediaCount, generatedBy: $generatedBy)';
}

/// 把清单编码成 `manifest.json` 的文本。
String encodeQuestionPackManifest(QuestionPackManifest manifest) =>
    jsonEncode(manifest.toJson());

/// 从已解码的 JSON 对象还原清单（入参必须是 `jsonDecode` 之后的 Map）。
QuestionPackManifest decodeQuestionPackManifest(
  Object? json, {
  String path = 'manifest.json',
}) {
  final Map<String, Object?>? map = _asStringKeyedMap(json);
  if (map == null) {
    throw QuestionPackException('题库包清单必须是 JSON 对象', path: path);
  }
  return QuestionPackManifest.fromJson(map, path: path);
}

Map<String, Object?>? _asStringKeyedMap(Object? value) {
  if (value is! Map) {
    return null;
  }
  final Map<String, Object?> result = <String, Object?>{};
  for (final MapEntry<Object?, Object?> entry in value.entries) {
    final Object? key = entry.key;
    if (key is! String) {
      return null;
    }
    result[key] = entry.value;
  }
  return result;
}

int _requireNonNegativeInt(
  Object? value, {
  required String path,
  required String fieldName,
}) {
  if (value is! int) {
    throw QuestionPackException(
      '$fieldName 必须是非负整数：${_describeValue(value)}',
      path: path,
    );
  }
  if (value < 0) {
    throw QuestionPackException(
      '$fieldName 不能为负数：$value',
      path: path,
    );
  }
  return value;
}

String? _optionalString(Object? value, {required String path}) {
  if (value == null) {
    return null;
  }
  if (value is! String) {
    throw QuestionPackException(
      '必须是字符串：${_describeValue(value)}',
      path: path,
    );
  }
  return value;
}

String _describeValue(Object? value) {
  if (value == null) {
    return 'null';
  }
  if (value is String) {
    return '「$value」';
  }
  return '$value';
}
