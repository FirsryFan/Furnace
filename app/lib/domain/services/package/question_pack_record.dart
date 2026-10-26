/// 题库包（.tqb）里的题目记录与媒体编解码（纯逻辑）。
///
/// 题库包是一个 zip：`manifest.json` + `questions.json` + `media/...`。
/// 本文件只负责 **题目记录** 这一层的 JSON 形状与逐字段校验：
/// 不 import dart:io、不碰 drift/Flutter，方便 zip 容器层与 UI 层复用。
///
/// 解码约定：一条坏记录就让整包失败（抛 [QuestionPackException]），
/// 宁可整包拒绝也不静默丢题；错误消息是中文，[QuestionPackException.path]
/// 指向具体位置，形如 `questions[3].options[0].label`。
library;

import 'dart:convert';

import 'question_pack_manifest.dart';

/// 题库包里最多允许的题目条数。
const int kQuestionPackMaxRecords = 5000;

const Set<String> _kAllowedMediaRoles = <String>{'stem', 'answer', 'solution'};
final RegExp _kOptionLabelPattern = RegExp(r'^[A-Z]$');

/// 文本格式 `plain`：历史题库包的缺省语义，走原来的纯文本/行内公式渲染。
const String kQuestionPackTextFormatPlain = 'plain';

/// 文本格式 `markdown`：题干/答案/解析是整段 Markdown + LaTeX（handoff 管线 v1）。
const String kQuestionPackTextFormatMarkdown = 'markdown';

const Set<String> _kAllowedTextFormats = <String>{
  kQuestionPackTextFormatPlain,
  kQuestionPackTextFormatMarkdown,
};

/// 能力点代码：A1…A10（与 reasoning 词表一致）。
final RegExp _kCapabilityCodePattern = RegExp(r'^A(10|[1-9])$');

/// 题库包里的一个媒体文件（题干配图 / 答案截图 / 解析截图）。
class QuestionPackMedia {
  const QuestionPackMedia({
    required this.packPath,
    this.fileName,
    this.mime,
    this.role = 'stem',
    this.sortOrder = 0,
  });

  /// 包内相对 POSIX 路径，例如 `media/q-0001-stem-0.png`。
  final String packPath;

  /// 原始文件名（可空），只用于展示，例如 `IMG_2043.png`。
  final String? fileName;

  /// MIME 类型（可空），例如 `image/png`。
  final String? mime;

  /// 用途：`stem`（题干配图）/ `answer`（答案截图）/ `solution`（解析截图）。
  final String role;

  /// 展示顺序，小的在前。
  final int sortOrder;

  Map<String, Object?> toJson() => <String, Object?>{
        'pack_path': packPath,
        if (fileName != null) 'file_name': fileName,
        if (mime != null) 'mime': mime,
        'role': role,
        'sort_order': sortOrder,
      };

  /// 从已解码的 JSON 对象还原一个媒体描述。
  factory QuestionPackMedia.fromJson(
    Map<String, Object?> json, {
    String path = 'media[]',
  }) {
    final String packPath =
        _requireSafePackPath(json['pack_path'], '$path.pack_path');
    final String role = _decodeMediaRole(json['role'], '$path.role');
    final int sortOrder = _decodeNonNegativeInt(
      json['sort_order'],
      '$path.sort_order',
      'sort_order',
    );
    final String? fileName = _decodeOptionalTrimmedString(
      json['file_name'],
      '$path.file_name',
      'file_name',
    );
    if (fileName != null &&
        (fileName.contains('/') || fileName.contains('\\'))) {
      _fail('file_name 不能包含路径分隔符：$fileName', '$path.file_name');
    }
    final String? mime = _decodeOptionalTrimmedString(
      json['mime'],
      '$path.mime',
      'mime',
    );
    return QuestionPackMedia(
      packPath: packPath,
      fileName: fileName,
      mime: mime,
      role: role,
      sortOrder: sortOrder,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is QuestionPackMedia &&
        other.packPath == packPath &&
        other.fileName == fileName &&
        other.mime == mime &&
        other.role == role &&
        other.sortOrder == sortOrder;
  }

  @override
  int get hashCode => Object.hash(packPath, fileName, mime, role, sortOrder);

  @override
  String toString() => 'QuestionPackMedia(packPath: $packPath, role: $role, '
      'sortOrder: $sortOrder)';
}

/// 题库包里的一个选项（A/B/C/D）。
class QuestionPackOption {
  const QuestionPackOption({
    required this.label,
    required this.content,
    this.isCorrect = false,
    this.sortOrder = 0,
  });

  /// 选项字母，解码时统一成大写 A-Z。
  final String label;

  /// 选项内容（可含 LaTeX/换行，按原样保留）。
  final String content;

  /// 是否正确答案。
  final bool isCorrect;

  /// 展示顺序，小的在前。
  final int sortOrder;

  Map<String, Object?> toJson() => <String, Object?>{
        'label': label,
        'content': content,
        'is_correct': isCorrect,
        'sort_order': sortOrder,
      };

  /// 从已解码的 JSON 对象还原一个选项。
  factory QuestionPackOption.fromJson(
    Map<String, Object?> json, {
    String path = 'options[]',
  }) {
    final String label = _decodeOptionLabel(json['label'], '$path.label');
    final Object? content = json['content'];
    if (content is! String || content.trim().isEmpty) {
      _fail('选项内容不能为空', '$path.content');
    }
    final int sortOrder = _decodeNonNegativeInt(
      json['sort_order'],
      '$path.sort_order',
      'sort_order',
    );
    final Object? isCorrect = json['is_correct'];
    if (isCorrect != null && isCorrect is! bool) {
      _fail('is_correct 必须是布尔值', '$path.is_correct');
    }
    return QuestionPackOption(
      label: label,
      content: content,
      isCorrect: isCorrect as bool? ?? false,
      sortOrder: sortOrder,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is QuestionPackOption &&
        other.label == label &&
        other.content == content &&
        other.isCorrect == isCorrect &&
        other.sortOrder == sortOrder;
  }

  @override
  int get hashCode => Object.hash(label, content, isCorrect, sortOrder);

  @override
  String toString() => 'QuestionPackOption(label: $label, '
      'content: $content, isCorrect: $isCorrect, sortOrder: $sortOrder)';
}

/// 题库包里的一道题。
class QuestionPackRecord {
  const QuestionPackRecord({
    required this.stem,
    this.answer,
    this.solution,
    this.subjectKey = '',
    this.questionType = 'solution',
    this.sourceLevel = 'unknown',
    this.sourceLabel = '',
    this.year,
    this.region,
    this.difficulty,
    this.difficultySource,
    this.trapNote,
    this.origin = 'manual',
    this.state = 'structured',
    this.serialNo,
    this.sourceUrl,
    this.zujuanQuestionId,
    this.zujuanBankId,
    this.textFormat = kQuestionPackTextFormatPlain,
    this.extensionOf,
    this.capability = const <String>[],
    this.options = const <QuestionPackOption>[],
    this.tagPaths = const <String>[],
    this.media = const <QuestionPackMedia>[],
  });

  /// 题干，必须 trim 后非空。
  final String stem;

  /// 标准答案（可空，可能是选项字母或一段文字）。
  final String? answer;

  /// 解析过程（可空）。
  final String? solution;

  /// 学科 key（可空字符串），例如 `math`。
  final String subjectKey;

  /// 题型，默认 `solution`。
  final String questionType;

  /// 来源等级，默认 `unknown`。
  final String sourceLevel;

  /// 人读的出处文字（可空字符串），例如「2024 湖南师大附中月考」。
  final String sourceLabel;

  /// 年份（可空，非空时 1900..2100）。
  final int? year;

  /// 地区（可空），例如 `湖南`。
  final String? region;

  /// 难度（可空，1–10 的实数，对应题库的 real 列）。
  final double? difficulty;

  /// 难度来源（可空）：`prior` / `ai` / `manual`。
  final String? difficultySource;

  /// 易错点 / 常见错因（可空）。
  final String? trapNote;

  /// 来源：默认 `manual`，另有 `ai_scan` / `furnace` 等。
  final String origin;

  /// 结构化状态，默认 `structured`。
  final String state;

  /// 题库题号（可空，非空时 >= 1）。
  final int? serialNo;

  /// 外部来源页 URL（可空）。
  final String? sourceUrl;

  /// 组卷网题目 id（可空）。
  final String? zujuanQuestionId;

  /// 组卷网学科 bankid（可空）。
  final String? zujuanBankId;

  /// 题干/答案/解析的文本格式：`plain`（缺省）或 `markdown`。
  ///
  /// 解码时只接受这两个值；历史包没有该字段时按 [kQuestionPackTextFormatPlain]
  /// 处理，因此旧包行为不变。
  final String textFormat;

  /// 扩展题挂靠的母题组卷网题目 id（可空）。
  ///
  /// 语义只是「指向同题库里某道母题的 zujuan_question_id」，不建外键、不要求
  /// 母题在同包里；悬空引用由上层忽略，不阻断导入。
  final String? extensionOf;

  /// 能力点代码数组（A1…A10），升序、不重复；空列表表示未标注。
  final List<String> capability;

  /// 选项，按给定顺序保留；同一记录内 label 不重复。
  final List<QuestionPackOption> options;

  /// 标签路径（每项 trim 后非空、不重复），例如 `['数学', '函数', '单调性']`。
  final List<String> tagPaths;

  /// 媒体文件（配图/答案截图），按 packPath 或 sortOrder 展示。
  final List<QuestionPackMedia> media;

  Map<String, Object?> toJson() => <String, Object?>{
        'stem': stem,
        if (answer != null) 'answer': answer,
        if (solution != null) 'solution': solution,
        'subject_key': subjectKey,
        'question_type': questionType,
        'source_level': sourceLevel,
        'source_label': sourceLabel,
        if (year != null) 'year': year,
        if (region != null) 'region': region,
        if (difficulty != null) 'difficulty': difficulty,
        if (difficultySource != null) 'difficulty_source': difficultySource,
        if (trapNote != null) 'trap_note': trapNote,
        'origin': origin,
        'state': state,
        if (serialNo != null) 'serial_no': serialNo,
        if (sourceUrl != null) 'source_url': sourceUrl,
        if (zujuanQuestionId != null) 'zujuan_question_id': zujuanQuestionId,
        if (zujuanBankId != null) 'zujuan_bank_id': zujuanBankId,
        // plain 是缺省语义，不落键，历史包导出结果保持逐字节稳定。
        if (textFormat != kQuestionPackTextFormatPlain)
          'text_format': textFormat,
        if (extensionOf != null) 'extension_of': extensionOf,
        if (capability.isNotEmpty) 'capability': <String>[...capability],
        'options': <Object?>[
          for (final QuestionPackOption option in options) option.toJson(),
        ],
        'tag_paths': <String>[...tagPaths],
        'media': <Object?>[
          for (final QuestionPackMedia item in media) item.toJson(),
        ],
      };

  /// 从已解码的 JSON 对象还原一道题。
  ///
  /// [path] 用于错误定位，调用方通常传 `questions[3]`；缺失的可选字段用默认值，
  /// 未知字段忽略（向后兼容）。
  factory QuestionPackRecord.fromJson(
    Map<String, Object?> json, {
    String path = 'questions[]',
  }) {
    final Object? stem = json['stem'];
    if (stem is! String || stem.trim().isEmpty) {
      _fail('题干为空：stem 不能为空', '$path.stem');
    }
    final String? answer =
        _decodeOptionalString(json['answer'], '$path.answer');
    final String? solution =
        _decodeOptionalString(json['solution'], '$path.solution');
    final String subjectKey =
        _decodeStringOrDefault(json['subject_key'], '', '$path.subject_key');
    final String questionType = _decodeStringOrDefault(
      json['question_type'],
      'solution',
      '$path.question_type',
    );
    final String sourceLevel = _decodeStringOrDefault(
      json['source_level'],
      'unknown',
      '$path.source_level',
    );
    final String sourceLabel =
        _decodeStringOrDefault(json['source_label'], '', '$path.source_label');
    final int? year = _decodeYear(json['year'], '$path.year');
    final String? region =
        _decodeOptionalString(json['region'], '$path.region');
    final double? difficulty =
        _decodeDifficulty(json['difficulty'], '$path.difficulty');
    final String? difficultySource = _decodeOptionalString(
        json['difficulty_source'], '$path.difficulty_source');
    final String? trapNote =
        _decodeOptionalString(json['trap_note'], '$path.trap_note');
    final String origin =
        _decodeStringOrDefault(json['origin'], 'manual', '$path.origin');
    final String state =
        _decodeStringOrDefault(json['state'], 'structured', '$path.state');
    final int? serialNo = _decodeSerialNo(json['serial_no'], '$path.serial_no');
    final String? sourceUrl =
        _decodeOptionalString(json['source_url'], '$path.source_url');
    final String? zujuanQuestionId = _decodeOptionalString(
      json['zujuan_question_id'],
      '$path.zujuan_question_id',
    );
    final String? zujuanBankId = _decodeOptionalString(
      json['zujuan_bank_id'],
      '$path.zujuan_bank_id',
    );
    final String textFormat = _decodeTextFormat(
      json['text_format'],
      '$path.text_format',
    );
    final String? extensionOf = _decodeOptionalTrimmedString(
      json['extension_of'],
      '$path.extension_of',
      'extension_of',
    );
    final List<String> capability = _decodeCapability(
      json['capability'],
      '$path.capability',
    );
    final List<QuestionPackOption> options = _decodeOptions(
      json['options'],
      '$path.options',
    );
    final List<String> tagPaths = _decodeTagPaths(
      json['tag_paths'],
      '$path.tag_paths',
    );
    final List<QuestionPackMedia> media = _decodeMedia(
      json['media'],
      '$path.media',
    );
    return QuestionPackRecord(
      stem: stem,
      answer: answer,
      solution: solution,
      subjectKey: subjectKey,
      questionType: questionType,
      sourceLevel: sourceLevel,
      sourceLabel: sourceLabel,
      year: year,
      region: region,
      difficulty: difficulty,
      difficultySource: difficultySource,
      trapNote: trapNote,
      origin: origin,
      state: state,
      serialNo: serialNo,
      sourceUrl: sourceUrl,
      zujuanQuestionId: zujuanQuestionId,
      zujuanBankId: zujuanBankId,
      textFormat: textFormat,
      extensionOf: extensionOf,
      capability: capability,
      options: options,
      tagPaths: tagPaths,
      media: media,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is QuestionPackRecord &&
        other.stem == stem &&
        other.answer == answer &&
        other.solution == solution &&
        other.subjectKey == subjectKey &&
        other.questionType == questionType &&
        other.sourceLevel == sourceLevel &&
        other.sourceLabel == sourceLabel &&
        other.year == year &&
        other.region == region &&
        other.difficulty == difficulty &&
        other.difficultySource == difficultySource &&
        other.trapNote == trapNote &&
        other.origin == origin &&
        other.state == state &&
        other.serialNo == serialNo &&
        other.sourceUrl == sourceUrl &&
        other.zujuanQuestionId == zujuanQuestionId &&
        other.zujuanBankId == zujuanBankId &&
        other.textFormat == textFormat &&
        other.extensionOf == extensionOf &&
        _listEquals(other.capability, capability) &&
        _listEquals(other.options, options) &&
        _listEquals(other.tagPaths, tagPaths) &&
        _listEquals(other.media, media);
  }

  @override
  int get hashCode => Object.hash(
        Object.hashAll(<Object?>[
          stem,
          answer,
          solution,
          subjectKey,
          questionType,
          sourceLevel,
          sourceLabel,
          year,
          region,
          difficulty,
          difficultySource,
          trapNote,
          origin,
          state,
          serialNo,
          sourceUrl,
          zujuanQuestionId,
          zujuanBankId,
          textFormat,
          extensionOf,
        ]),
        Object.hashAll(capability),
        Object.hashAll(options),
        Object.hashAll(tagPaths),
        Object.hashAll(media),
      );

  @override
  String toString() => 'QuestionPackRecord(stem: $stem, '
      'questionType: $questionType, serialNo: $serialNo, '
      'textFormat: $textFormat, capability: ${capability.length}, '
      'options: ${options.length}, tagPaths: ${tagPaths.length}, '
      'media: ${media.length})';
}

/// 把题目记录编码成 `questions.json` 的文本（JSON 数组）。
String encodeQuestionPackRecords(List<QuestionPackRecord> records) =>
    jsonEncode(<Object?>[
      for (final QuestionPackRecord record in records) record.toJson(),
    ]);

/// 从已解码的 JSON 数组还原题目记录。
///
/// 入参必须是 `jsonDecode` 之后的 List（直接传 JSON 文本会抛 [QuestionPackException]）；
/// 空数组允许；任何一条结构错误都让整个包失败。
List<QuestionPackRecord> decodeQuestionPackRecords(
  Object? json, {
  String path = 'questions.json',
}) {
  if (json is! List) {
    _fail('题库包题目文件必须是 JSON 数组', path);
  }
  if (json.length > kQuestionPackMaxRecords) {
    _fail(
      '题库包里的题目太多：${json.length} 条（最多 $kQuestionPackMaxRecords 条）',
      path,
    );
  }
  final List<QuestionPackRecord> records = <QuestionPackRecord>[];
  for (int index = 0; index < json.length; index++) {
    final Map<String, Object?>? map = _asStringKeyedMap(json[index]);
    if (map == null) {
      _fail('第 ${index + 1} 条题目不是 JSON 对象', 'questions[$index]');
    }
    records.add(QuestionPackRecord.fromJson(map, path: 'questions[$index]'));
  }
  return List<QuestionPackRecord>.unmodifiable(records);
}

// ---------------------------------------------------------------------------
// 私有校验/解码工具（两个记录类共用）。
// ---------------------------------------------------------------------------

Never _fail(String message, String path) =>
    throw QuestionPackException(message, path: path);

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

List<QuestionPackOption> _decodeOptions(Object? value, String path) {
  if (value == null) {
    return const <QuestionPackOption>[];
  }
  if (value is! List) {
    _fail('options 必须是数组', path);
  }
  final List<QuestionPackOption> options = <QuestionPackOption>[];
  final Set<String> seenLabels = <String>{};
  for (int index = 0; index < value.length; index++) {
    final Map<String, Object?>? map = _asStringKeyedMap(value[index]);
    if (map == null) {
      _fail('选项必须是 JSON 对象', '$path[$index]');
    }
    final QuestionPackOption option = QuestionPackOption.fromJson(
      map,
      path: '$path[$index]',
    );
    if (!seenLabels.add(option.label)) {
      _fail(
        '选项 label 重复：${option.label}',
        '$path[$index].label',
      );
    }
    options.add(option);
  }
  return List<QuestionPackOption>.unmodifiable(options);
}

List<QuestionPackMedia> _decodeMedia(Object? value, String path) {
  if (value == null) {
    return const <QuestionPackMedia>[];
  }
  if (value is! List) {
    _fail('media 必须是数组', path);
  }
  final List<QuestionPackMedia> media = <QuestionPackMedia>[];
  for (int index = 0; index < value.length; index++) {
    final Map<String, Object?>? map = _asStringKeyedMap(value[index]);
    if (map == null) {
      _fail('媒体项必须是 JSON 对象', '$path[$index]');
    }
    media.add(QuestionPackMedia.fromJson(map, path: '$path[$index]'));
  }
  return List<QuestionPackMedia>.unmodifiable(media);
}

List<String> _decodeTagPaths(Object? value, String path) {
  if (value == null) {
    return const <String>[];
  }
  if (value is! List) {
    _fail('tag_paths 必须是数组', path);
  }
  final List<String> tagPaths = <String>[];
  final Set<String> seen = <String>{};
  for (int index = 0; index < value.length; index++) {
    final Object? item = value[index];
    if (item is! String || item.trim().isEmpty) {
      _fail('标签路径不能为空', '$path[$index]');
    }
    final String tag = item.trim();
    if (!seen.add(tag)) {
      _fail('标签路径重复：$tag', '$path[$index]');
    }
    tagPaths.add(tag);
  }
  return List<String>.unmodifiable(tagPaths);
}

String _decodeOptionLabel(Object? value, String path) {
  if (value is! String) {
    _fail('选项 label 必须是单个字母 A-Z', path);
  }
  final String label = value.trim().toUpperCase();
  if (!_kOptionLabelPattern.hasMatch(label)) {
    _fail('选项 label 必须是单个字母 A-Z：$value', path);
  }
  return label;
}

String _requireSafePackPath(Object? value, String path) {
  if (value is! String) {
    _fail('pack_path 必须是字符串', path);
  }
  final String packPath = value.trim();
  if (packPath.isEmpty) {
    _fail('pack_path 不能为空', path);
  }
  if (packPath.startsWith('/')) {
    _fail('pack_path 必须是相对路径，不能以 / 开头：$packPath', path);
  }
  if (packPath.contains('\\')) {
    _fail('pack_path 必须是 POSIX 路径，不能包含反斜杠：$packPath', path);
  }
  final List<String> segments = packPath.split('/');
  for (final String segment in segments) {
    if (segment.isEmpty) {
      _fail('pack_path 不能包含空路径段：$packPath', path);
    }
    if (segment == '.' || segment == '..') {
      _fail('pack_path 不能包含 . 或 .. 路径段：$packPath', path);
    }
  }
  return packPath;
}

String _decodeMediaRole(Object? value, String path) {
  if (value == null) {
    return 'stem';
  }
  if (value is! String || !_kAllowedMediaRoles.contains(value)) {
    _fail(
      'role 必须是 stem / answer / solution 之一：$value',
      path,
    );
  }
  return value;
}

int _decodeNonNegativeInt(Object? value, String path, String fieldName) {
  if (value == null) {
    return 0;
  }
  if (value is! int) {
    _fail('$fieldName 必须是非负整数', path);
  }
  if (value < 0) {
    _fail('$fieldName 不能为负数：$value', path);
  }
  return value;
}

String? _decodeOptionalTrimmedString(
  Object? value,
  String path,
  String fieldName,
) {
  if (value == null) {
    return null;
  }
  if (value is! String) {
    _fail('$fieldName 必须是字符串', path);
  }
  final String trimmed = value.trim();
  if (trimmed.isEmpty) {
    _fail('$fieldName 不能为空字符串', path);
  }
  return trimmed;
}

String? _decodeOptionalString(Object? value, String path) {
  if (value == null) {
    return null;
  }
  if (value is! String) {
    _fail('必须是字符串', path);
  }
  return value;
}

String _decodeStringOrDefault(Object? value, String fallback, String path) {
  if (value == null) {
    return fallback;
  }
  if (value is! String) {
    _fail('必须是字符串', path);
  }
  return value;
}

String _decodeTextFormat(Object? value, String path) {
  if (value == null) {
    return kQuestionPackTextFormatPlain;
  }
  if (value is! String || !_kAllowedTextFormats.contains(value)) {
    _fail('text_format 只能是 plain 或 markdown：$value', path);
  }
  return value;
}

/// 能力点数组：每项形如 `A1`…`A10`，去重后按数字升序（导入结果与书写顺序无关）。
List<String> _decodeCapability(Object? value, String path) {
  if (value == null) {
    return const <String>[];
  }
  if (value is! List) {
    _fail('capability 必须是数组', path);
  }
  final Set<String> codes = <String>{};
  for (int index = 0; index < value.length; index++) {
    final Object? item = value[index];
    if (item is! String || !_kCapabilityCodePattern.hasMatch(item.trim())) {
      _fail('capability 每项必须是 A1…A10：$item', '$path[$index]');
    }
    codes.add(item.trim());
  }
  final List<String> sorted = codes.toList()
    ..sort((String a, String b) => _capabilityRank(a) - _capabilityRank(b));
  return List<String>.unmodifiable(sorted);
}

int _capabilityRank(String code) => int.parse(code.substring(1));

int? _decodeYear(Object? value, String path) {
  if (value == null) {
    return null;
  }
  if (value is! int || value < 1900 || value > 2100) {
    _fail('year 必须在 1900..2100 之间：$value', path);
  }
  return value;
}

int? _decodeSerialNo(Object? value, String path) {
  if (value == null) {
    return null;
  }
  if (value is! int || value < 1) {
    _fail('serial_no 必须是 >= 1 的整数：$value', path);
  }
  return value;
}

double? _decodeDifficulty(Object? value, String path) {
  if (value == null) {
    return null;
  }
  if (value is! num) {
    _fail('difficulty 必须是数字', path);
  }
  final double difficulty = value.toDouble();
  if (!difficulty.isFinite) {
    _fail('difficulty 必须是有限数字', path);
  }
  return difficulty;
}

bool _listEquals<T>(List<T> left, List<T> right) {
  if (identical(left, right)) {
    return true;
  }
  if (left.length != right.length) {
    return false;
  }
  for (int index = 0; index < left.length; index++) {
    if (left[index] != right[index]) {
      return false;
    }
  }
  return true;
}
