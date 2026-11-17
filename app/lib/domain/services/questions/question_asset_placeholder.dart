/// 源题面里的 `{{asset:NAME}}` 图片占位（纯逻辑，不碰 Flutter / dart:io）。
///
/// 为什么需要这一层：整卷抽取源（`exam-papers/*/paper.json`）把图片写成
/// `{{asset:q14_img01.png}}` 这种**源格式占位**，本应由导入管线换成图片附件 +
/// `［图N］` 占位。历史上有一批题是「原样导入」的（stem/选项直接带着
/// `{{asset:...}}`），题库卡片与详情页就会把占位符当正文显示给用户
/// （例：2024 英语卷 45 道题）。这里提供：
///
///  * 识别/定位占位符（[parseQuestionAssetReferences]）；
///  * 把每个占位映射到已入库附件（按**原文件名**，附件落盘保留原文件名，见
///    `QuestionMediaStore.save` 的 `question_images/<qid>/<attId>/<原文件名>`）
///    并替换成统一的 `［图N］` 占位，交给既有图文混排管线；
///  * 找不到附件时换成明确的「图片缺失」文字，**绝不把原始占位符留给用户**；
///  * `.wmf` 是 Flutter 不支持的格式：即使源里有同名文件也渲染不了，所以单独
///    标注「WMF 格式不支持」；若导入时已转成同名 `.png`，按转换后的图渲染。
///
/// 口径：只认 `{{asset:...}}`（允许花括号/冒号两侧空白、名字两侧空白）；
/// `{{ asset: x }}` 也认。不是这个形状的 `{{...}}` 保持原文，不猜。
library;

/// 源题面里的资产占位：`{{asset:NAME}}`。
final RegExp questionAssetPlaceholderPattern = RegExp(
  r'\{\{\s*asset\s*:\s*([^{}]+?)\s*\}\}',
);

/// 图片占位的替换写法：`［图N］`（N 为 1-based 图序）。
String questionAssetImageToken(int order) => '［图${order + 1}］';

/// 缺失图片的提示：`［图片缺失：NAME］`。
String questionAssetMissingLabel(String name) => '［图片缺失：$name］';

/// WMF 不支持的提示：`［图片缺失：NAME（WMF 格式不支持）］`。
String questionAssetWmfUnsupportedLabel(String name) =>
    '［图片缺失：$name（WMF 格式不支持）］';

/// 加载中/不知道附件时的中性提示：`［图］`（不是原始占位符）。
const String kQuestionAssetPendingToken = '［图］';

/// 占位符在原文里的一次出现。
class QuestionAssetReference {
  const QuestionAssetReference({
    required this.name,
    required this.start,
    required this.end,
    required this.ownLine,
  });

  /// 资产文件名，例如 `q14_img01.png`。
  final String name;

  /// 占位符在原文里的起止偏移（`[start, end)`，含两层花括号）。
  final int start;
  final int end;

  /// 这个占位是不是独立成行（前后只有空白或换行）。
  final bool ownLine;

  /// 小写扩展名（不含点）；没有扩展名返回空串。
  String get extension {
    final dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) return '';
    return name.substring(dot + 1).toLowerCase();
  }

  /// 这个引用是不是 Windows 图元文件（Flutter 不能渲染）。
  bool get isWmf => extension == 'wmf' || extension == 'emf';

  /// 把 `.wmf` 换成 `.png` 后的候选名；非 WMF 返回 null。
  ///
  /// 导入管线把 MathType 公式图转 PNG 时通常保持主文件名不变，所以同名 `.png`
  /// 存在就说明「转换过」，按转换后的图显示。
  String? get convertedPngName {
    if (!isWmf) return null;
    final dot = name.lastIndexOf('.');
    if (dot < 0) return '$name.png';
    return '${name.substring(0, dot)}.png';
  }

  @override
  String toString() =>
      'QuestionAssetReference($name, ownLine: $ownLine, '
      'start: $start, end: $end)';

  @override
  bool operator ==(Object other) =>
      other is QuestionAssetReference &&
      other.name == name &&
      other.start == start &&
      other.end == end &&
      other.ownLine == ownLine;

  @override
  int get hashCode => Object.hash(name, start, end, ownLine);
}

/// 一次占位替换的结果。
class QuestionAssetText {
  const QuestionAssetText({
    required this.text,
    required this.references,
    required this.resolved,
    required this.missing,
    required this.wmfUnsupported,
  });

  /// 替换后的文本：有效引用变成 `［图N］`，其余变成明确的缺失提示。
  final String text;

  /// 原文里的每个 `{{asset:...}}`，按出现顺序。
  final List<QuestionAssetReference> references;

  /// 解析到附件（含 WMF→同名 PNG）的引用数。
  final int resolved;

  /// 没解析到附件、也不是 WMF 的引用数。
  final int missing;

  /// WMF 且没有同名 PNG 可用的引用数。
  final int wmfUnsupported;

  bool get hasReferences => references.isNotEmpty;

  bool get hasMissingMedia => missing > 0 || wmfUnsupported > 0;

  @override
  String toString() =>
      'QuestionAssetText(refs: ${references.length}, resolved: $resolved, '
      'missing: $missing, wmfUnsupported: $wmfUnsupported)';
}

/// 文本里有没有 `{{asset:...}}` 占位。
bool containsQuestionAssetPlaceholder(String text) =>
    text.isNotEmpty && questionAssetPlaceholderPattern.hasMatch(text);

/// 解析所有占位（不修改文本）。
List<QuestionAssetReference> parseQuestionAssetReferences(String text) {
  if (text.isEmpty) return const <QuestionAssetReference>[];
  return <QuestionAssetReference>[
    for (final match in questionAssetPlaceholderPattern.allMatches(text))
      if (match.group(1)?.trim() case final name? when name.isNotEmpty)
        QuestionAssetReference(
          name: name,
          start: match.start,
          end: match.end,
          ownLine: _isOwnLine(text, match.start, match.end),
        ),
  ];
}

/// 把 `{{asset:...}}` 换成能渲染的占位或明确的缺失提示。
///
/// [attachmentNames] 是这道题已入库附件的**原文件名**（`QuestionImage.fileName`），
/// 顺序与 `［图N］` 的 N 一致（N = 下标 + 1）。按原文件名精确匹配；`.wmf` 找不到
/// 时再找同名 `.png`（导入时转换过的公式图）。
///
/// [pending] 为 true 表示附件清单还没读出来：此时**不判断缺失**，统一换成中性的
/// `［图］`，读出来后再重建（避免先闪一下「图片缺失」）。
QuestionAssetText renderQuestionAssetPlaceholders(
  String text, {
  required List<String> attachmentNames,
  bool pending = false,
}) {
  final references = parseQuestionAssetReferences(text);
  if (references.isEmpty) {
    return QuestionAssetText(
      text: text,
      references: const <QuestionAssetReference>[],
      resolved: 0,
      missing: 0,
      wmfUnsupported: 0,
    );
  }
  final orderByName = <String, int>{};
  for (var index = 0; index < attachmentNames.length; index++) {
    final name = attachmentNames[index].trim();
    if (name.isEmpty) continue;
    orderByName.putIfAbsent(name, () => index);
  }

  final buffer = StringBuffer();
  var cursor = 0;
  var resolved = 0;
  var missing = 0;
  var wmfUnsupported = 0;
  for (final reference in references) {
    buffer.write(text.substring(cursor, reference.start));
    cursor = reference.end;
    if (pending) {
      buffer.write(kQuestionAssetPendingToken);
      continue;
    }
    var order = orderByName[reference.name];
    if (order == null) {
      final converted = reference.convertedPngName;
      if (converted != null) {
        order = orderByName[converted];
      }
    }
    if (order != null) {
      resolved++;
      buffer.write(questionAssetImageToken(order));
      continue;
    }
    if (reference.isWmf) {
      wmfUnsupported++;
      buffer.write(questionAssetWmfUnsupportedLabel(reference.name));
    } else {
      missing++;
      buffer.write(questionAssetMissingLabel(reference.name));
    }
  }
  buffer.write(text.substring(cursor));
  return QuestionAssetText(
    text: buffer.toString(),
    references: references,
    resolved: resolved,
    missing: missing,
    wmfUnsupported: wmfUnsupported,
  );
}

/// 只列表摘要用：把所有占位换成中性 [token]（不区分缺失/已解析）。
///
/// 列表没有附件清单，判不了「图在不在」；这里只保证**不把原始占位符显示给
/// 用户**，是否缺图由详情页/待处理入口说明。
String collapseQuestionAssetPlaceholders(
  String text, {
  String token = kQuestionAssetPendingToken,
}) {
  if (!containsQuestionAssetPlaceholder(text)) return text;
  return text.replaceAll(questionAssetPlaceholderPattern, token);
}

/// 占位前后是不是只有空白（或行首行尾）。
bool _isOwnLine(String text, int start, int end) {
  var before = start - 1;
  while (before >= 0 && (text[before] == ' ' || text[before] == '\t')) {
    before--;
  }
  if (before >= 0 && text[before] != '\n' && text[before] != '\r') {
    return false;
  }
  var after = end;
  while (after < text.length && (text[after] == ' ' || text[after] == '\t')) {
    after++;
  }
  if (after < text.length && text[after] != '\n' && text[after] != '\r') {
    return false;
  }
  return true;
}
