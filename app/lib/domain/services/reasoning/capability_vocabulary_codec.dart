/// 能力动作词表的 JSON 文件编解码 —— 给编辑页的「从文件导入 / 导出为 .json」用。
///
/// 纯 Dart：不 import Flutter / 数据库 / 网络，也不做 IO——调用方自己读文件拿到
/// String 再交给 [decodeCapabilityVocabularyText]；导出时把
/// [encodeCapabilityVocabularyJson] 的产物自己写盘。
///
/// 文件格式（与 [CapabilityActionOverlay.toJson] 一致，v1）：
///
///     {
///       "version": 1,
///       "customActions": [
///         {
///           "key": "force_diagram",
///           "labelZh": "画受力图",
///           "labelEn": "Free-body diagram",
///           "descriptionZh": "把研究对象独立出来，按性质逐个画力。",
///           "subjectHints": ["physics", "math"]
///         }
///       ]
///     }
///
/// 三条口径（都有测试守着）：
/// 1. **不抛异常**：坏文件、坏条目、超长、错版本都只记 issue，返回能返回的结果。
/// 2. **不静默丢**：被跳过的条目一定带 index 进 [CapabilityVocabularyDecodeIssue]；
///    通过结构关的条目，语义校验仍走 [CapabilityActionOverlay.catalog]（与界面、
///    解析器同一套规则），它的 issue 原样合并进来。
/// 3. **确定性**：同一输入两次编解码输出相同；issue 排序固定（fatal 在前，再按
///    条目 index 升序）。
library;

import 'dart:convert';

import 'capability_action_overlay.dart';

/// 解码问题代码。用枚举而不是字符串，测试与界面才能断言「具体是哪一类问题」。
enum CapabilityVocabularyDecodeIssueCode {
  /// 文件为空（或只有空白/BOM）。
  emptyDocument,

  /// 文件原始 UTF-8 字节数超过 [CapabilityVocabularyDecodeResult.maxDocumentBytes]。
  documentTooLarge,

  /// 不是合法 JSON（语法错误）。
  invalidJson,

  /// 顶层既不是对象也不是条目数组。
  invalidTopLevel,

  /// 文件版本大于 [CapabilityVocabularyDecodeResult.formatVersion]。
  unsupportedVersion,

  /// 整数版本但小于 1。
  invalidVersion,

  /// 版本不是整数（字符串、null、布尔等）。
  versionNotInteger,

  /// 顶层出现了不认识的键；忽略，不影响导入。
  unknownTopLevelKey,

  /// customActions 缺失或不是数组。
  customActionsNotList,

  /// 某一条自定义动作不是对象。
  entryNotObject,

  /// 某一条自定义动作缺 key（缺失、null、空白串）。
  entryMissingKey,

  /// 某一条自定义动作的 key 不是字符串。
  entryKeyNotString,

  /// 条目通过了结构关，但被 overlay 的既有语义校验拒绝。
  ///
  /// 具体原因见 [CapabilityVocabularyDecodeIssue.overlayReason]。
  entryRejected,
}

/// 解码时发现的一条问题。
///
/// [fatal] 为 true 表示文件整体不可用（解码返回空 overlay）；否则是「部分失败」，
/// 其余条目仍然尽量导入。条目级问题的 [index] 是在 customActions 数组里的
/// **原始下标**（含被前面的坏条目挤掉的偏移）。
class CapabilityVocabularyDecodeIssue {
  const CapabilityVocabularyDecodeIssue({
    required this.code,
    required this.message,
    this.fatal = false,
    this.index,
    this.key,
    this.overlayReason,
  });

  /// 问题类别。
  final CapabilityVocabularyDecodeIssueCode code;

  /// 给人看的一句话解释（中文）；界面直接显示，不必自己翻译枚举。
  final String message;

  /// 是否致命：true 时 [CapabilityVocabularyDecodeResult.overlay] 一定是空 overlay。
  final bool fatal;

  /// 条目级问题对应的原始下标；顶层/文档级问题为 null。
  final int? index;

  /// 出问题的 key（能取到时填；例如被语义校验拒绝的条目）。
  final String? key;

  /// [CapabilityVocabularyDecodeIssueCode.entryRejected] 的原始原因
  /// （来自 [CapabilityActionOverlay.catalog] 的 issues）。
  final CapabilityActionOverlayIssueReason? overlayReason;

  /// 是否是条目级问题（带 index）。
  bool get isEntryLevel => index != null;

  Map<String, Object?> toJson() => <String, Object?>{
        'code': code.name,
        'message': message,
        'fatal': fatal,
        'index': index,
        'key': key,
        'overlay_reason': overlayReason?.name,
      };

  @override
  String toString() =>
      'CapabilityVocabularyDecodeIssue(${code.name}, fatal: $fatal, index: $index, key: "$key"): $message';
}

/// [decodeCapabilityVocabularyText] 的结果。
///
/// 解码本身**永不抛异常**：坏文件返回空 overlay + 至少一条 fatal issue。
class CapabilityVocabularyDecodeResult {
  CapabilityVocabularyDecodeResult({
    required this.overlay,
    required List<CapabilityVocabularyDecodeIssue> issues,
    required this.version,
    required this.hadBom,
    required this.byteLength,
  }) : issues = List<CapabilityVocabularyDecodeIssue>.unmodifiable(issues);

  /// 当前支持的文件版本。
  static const int formatVersion = 1;

  /// 文件原始 UTF-8 字节数上限（64KB）。
  ///
  /// 这是**原始文本**的字节数，不是条目数：词表应该很小，超大文件更可能是
  /// 选错文件或恶意输入。
  static const int maxDocumentBytes = 64 * 1024;

  /// 解出的 overlay：只含**通过结构关**的条目；可能仍含被语义校验拒绝的条目
  /// （它们的 catalog issue 已合并进 [issues]，界面需要显示「哪条没生效」）。
  final CapabilityActionOverlay overlay;

  /// 按固定顺序排好的问题：fatal 在前，再按条目 index 升序。
  final List<CapabilityVocabularyDecodeIssue> issues;

  /// 文件声明的版本：对象缺省、裸数组按 1；非整数或非法整数为 null。
  final int? version;

  /// 输入是否以 UTF-8 BOM 开头（已剥掉，不算进 JSON 正文）。
  final bool hadBom;

  /// 输入文本的原始 UTF-8 字节数（含 BOM）。
  final int byteLength;

  /// 是否有 fatal issue（文件整体不可用）。
  bool get hasFatal => issues.any((issue) => issue.fatal);

  /// 是否真的能拿去导入：没有 fatal，且至少有一条条目通过结构关。
  ///
  /// 注意：合法但空的词表（零条自定义动作）[isUsable] 为 false——导入它没有
  /// 任何效果，界面应提示「没有可导入的条目」，而不是假装成功。
  bool get isUsable => !hasFatal && overlay.customActions.isNotEmpty;
}

/// 编码成稳定 JSON。
///
/// 结构固定为 {version: 1, customActions: [...]}，键顺序固定（Map 的插入
/// 顺序），条目字段顺序由 CustomCapabilityAction.toJson 固定。因此同样输入
/// 两次编码得到**逐字节相同**的字符串。
///
/// [pretty] 为 true 时两空格缩进、以换行结尾（适合写文件给人看）；为 false 时
/// 是无空白的紧凑 JSON（适合塞进剪贴板 / 二维码）。
///
/// 编码不做语义校验：overlay 里没通过校验的条目也会原样写出，导入后才能由
/// 解码 + 界面说清「哪条为什么没生效」。
String encodeCapabilityVocabularyJson(
  CapabilityActionOverlay overlay, {
  bool pretty = true,
}) {
  final payload = <String, Object?>{
    'version': CapabilityVocabularyDecodeResult.formatVersion,
    'customActions': <Object?>[
      for (final action in overlay.customActions) action.toJson(),
    ],
  };
  if (!pretty) {
    return jsonEncode(payload);
  }
  return '${_prettyJson.convert(payload)}\n';
}

const JsonEncoder _prettyJson = JsonEncoder.withIndent('  ');

/// 「分享 / 导出」入口的便捷包装。
///
/// 没有自定义动作时返回 null——空词表导出没有意义，界面应禁用分享按钮，而不是
/// 生成一个空词表 JSON 让人以为分享成功了。
///
/// 其它情况等价于 [encodeCapabilityVocabularyJson]；编码本身不会失败，返回可空是
/// 为了把「没有内容」和「内容」在类型上分开。
String? tryEncodeOverlayForSharing(
  CapabilityActionOverlay overlay, {
  bool pretty = true,
}) {
  if (overlay.customActions.isEmpty) {
    return null;
  }
  return encodeCapabilityVocabularyJson(overlay, pretty: pretty);
}

/// 解码文件文本（UTF-8 字节已被调用方解成 String）。
///
/// 处理：BOM、首尾空白、CRLF、两种顶层形状（带 version 的对象 / 裸条目数组）、
/// 版本缺省与过新、未知顶层键、非对象/缺 key/非字符串 key 的条目、以及
/// overlay 已有的语义校验。**永不抛异常**。
CapabilityVocabularyDecodeResult decodeCapabilityVocabularyText(String text) {
  final byteLength = utf8.encode(text).length;
  final hadBom = text.startsWith('\uFEFF');
  final body = (hadBom ? text.substring(1) : text).trim();

  if (byteLength > CapabilityVocabularyDecodeResult.maxDocumentBytes) {
    return _fatal(
      code: CapabilityVocabularyDecodeIssueCode.documentTooLarge,
      message:
          '文件原始 UTF-8 字节数 $byteLength 超过上限 ${CapabilityVocabularyDecodeResult.maxDocumentBytes} 字节（64KB）：请检查是否选错文件，或精简后再导入。',
      hadBom: hadBom,
      byteLength: byteLength,
    );
  }
  if (body.isEmpty) {
    return _fatal(
      code: CapabilityVocabularyDecodeIssueCode.emptyDocument,
      message: '文件是空的（或只有空白/BOM）：没有可导入的能力动作。',
      hadBom: hadBom,
      byteLength: byteLength,
    );
  }

  Object? decoded;
  try {
    decoded = jsonDecode(body);
  } on FormatException catch (error) {
    return _fatal(
      code: CapabilityVocabularyDecodeIssueCode.invalidJson,
      message: '不是合法 JSON：${error.message}。',
      hadBom: hadBom,
      byteLength: byteLength,
    );
  }

  final issues = <CapabilityVocabularyDecodeIssue>[];
  final List<Object?> entries;
  final int? version;

  if (decoded is Map) {
    final map = Map<String, Object?>.from(decoded);
    final unknownKeys = <String>[
      for (final key in map.keys)
        if (key != 'version' && key != 'customActions') key,
    ]..sort();
    for (final key in unknownKeys) {
      issues.add(CapabilityVocabularyDecodeIssue(
        code: CapabilityVocabularyDecodeIssueCode.unknownTopLevelKey,
        message: '顶层字段「$key」不认识：已忽略，不影响其它字段。',
        key: key,
      ));
    }
    version = _decodeVersion(
      map['version'],
      present: map.containsKey('version'),
      issues: issues,
    );
    final rawEntries = map['customActions'];
    if (rawEntries is List) {
      entries = rawEntries.cast<Object?>();
    } else {
      entries = const <Object?>[];
      issues.add(const CapabilityVocabularyDecodeIssue(
        code: CapabilityVocabularyDecodeIssueCode.customActionsNotList,
        message: '「customActions」缺失或不是数组：没有可导入的条目。',
      ));
    }
  } else if (decoded is List) {
    entries = decoded.cast<Object?>();
    version = CapabilityVocabularyDecodeResult.formatVersion;
  } else {
    return _fatal(
      code: CapabilityVocabularyDecodeIssueCode.invalidTopLevel,
      message:
          '顶层必须是对象（含 version / customActions）或条目数组，收到 ${_describeValue(decoded)}。',
      hadBom: hadBom,
      byteLength: byteLength,
    );
  }

  final accepted = <Map<String, Object?>>[];
  final originalIndexes = <int>[];
  for (var index = 0; index < entries.length; index++) {
    final raw = entries[index];
    if (raw is! Map) {
      issues.add(CapabilityVocabularyDecodeIssue(
        code: CapabilityVocabularyDecodeIssueCode.entryNotObject,
        message: '第 $index 条自定义动作不是对象（收到 ${_describeValue(raw)}）：已跳过。',
        index: index,
      ));
      continue;
    }
    final entry = Map<String, Object?>.from(raw);
    final rawKey = entry['key'];
    if (rawKey == null || (rawKey is String && rawKey.trim().isEmpty)) {
      issues.add(CapabilityVocabularyDecodeIssue(
        code: CapabilityVocabularyDecodeIssueCode.entryMissingKey,
        message: '第 $index 条自定义动作缺 key（必须是非空字符串）：已跳过。',
        index: index,
      ));
      continue;
    }
    if (rawKey is! String) {
      issues.add(CapabilityVocabularyDecodeIssue(
        code: CapabilityVocabularyDecodeIssueCode.entryKeyNotString,
        message:
            '第 $index 条自定义动作的 key 不是字符串（收到 ${_describeValue(rawKey)}）：已跳过。',
        index: index,
      ));
      continue;
    }
    accepted.add(entry);
    originalIndexes.add(index);
  }

  final overlay = CapabilityActionOverlay.fromJson(
    <Object?>[for (final entry in accepted) entry],
  );

  final indexesByKey = <String, List<int>>{};
  for (var i = 0; i < accepted.length; i++) {
    final key = (accepted[i]['key']! as String).trim();
    indexesByKey.putIfAbsent(key, () => <int>[]).add(originalIndexes[i]);
  }
  for (final overlayIssue in overlay.catalog.issues) {
    final indexes = indexesByKey[overlayIssue.key];
    issues.add(CapabilityVocabularyDecodeIssue(
      code: CapabilityVocabularyDecodeIssueCode.entryRejected,
      message: overlayIssue.message,
      index: indexes != null && indexes.length == 1 ? indexes.single : null,
      key: overlayIssue.key,
      overlayReason: overlayIssue.reason,
    ));
  }

  issues.sort(_compareIssues);
  return CapabilityVocabularyDecodeResult(
    overlay: overlay,
    issues: issues,
    version: version,
    hadBom: hadBom,
    byteLength: byteLength,
  );
}

CapabilityVocabularyDecodeResult _fatal({
  required CapabilityVocabularyDecodeIssueCode code,
  required String message,
  required bool hadBom,
  required int byteLength,
}) {
  return CapabilityVocabularyDecodeResult(
    overlay: CapabilityActionOverlay.empty,
    issues: <CapabilityVocabularyDecodeIssue>[
      CapabilityVocabularyDecodeIssue(
          code: code, message: message, fatal: true),
    ],
    version: null,
    hadBom: hadBom,
    byteLength: byteLength,
  );
}

int? _decodeVersion(
  Object? raw, {
  required bool present,
  required List<CapabilityVocabularyDecodeIssue> issues,
}) {
  if (!present) {
    return CapabilityVocabularyDecodeResult.formatVersion;
  }
  if (raw is int) {
    if (raw < 1) {
      issues.add(CapabilityVocabularyDecodeIssue(
        code: CapabilityVocabularyDecodeIssueCode.invalidVersion,
        message: '「version」必须大于等于 1（收到 $raw）：版本无法识别，但仍按当前格式尽量解析条目。',
      ));
      return null;
    }
    if (raw > CapabilityVocabularyDecodeResult.formatVersion) {
      issues.add(CapabilityVocabularyDecodeIssue(
        code: CapabilityVocabularyDecodeIssueCode.unsupportedVersion,
        message:
            '文件版本 $raw 高于当前支持的 ${CapabilityVocabularyDecodeResult.formatVersion}：仍尽量导入已知字段，新字段忽略。',
      ));
      return raw;
    }
    return raw;
  }
  issues.add(CapabilityVocabularyDecodeIssue(
    code: CapabilityVocabularyDecodeIssueCode.versionNotInteger,
    message: '「version」必须是整数（收到 ${_describeValue(raw)}）：版本无法识别，但仍按当前格式尽量解析条目。',
  ));
  return null;
}

/// 稳定排序：fatal 在前，再按条目 index 升序；文档级问题（index 为 null）排在
/// 条目级之前；同层再按枚举序、key、消息兜底，保证同输入同输出。
int _compareIssues(
  CapabilityVocabularyDecodeIssue a,
  CapabilityVocabularyDecodeIssue b,
) {
  if (a.fatal != b.fatal) {
    return a.fatal ? -1 : 1;
  }
  final aIndex = a.index ?? -1;
  final bIndex = b.index ?? -1;
  if (aIndex != bIndex) {
    return aIndex.compareTo(bIndex);
  }
  final byCode = a.code.index.compareTo(b.code.index);
  if (byCode != 0) {
    return byCode;
  }
  final byKey = (a.key ?? '').compareTo(b.key ?? '');
  if (byKey != 0) {
    return byKey;
  }
  return a.message.compareTo(b.message);
}

/// 把任意 JSON 值描述成一句可读的话（用于 issue 消息，截断超长内容）。
String _describeValue(Object? value) {
  if (value == null) {
    return 'null';
  }
  final text = value is String ? '「$value」' : '$value';
  return text.length <= 40 ? text : '${text.substring(0, 40)}…';
}
