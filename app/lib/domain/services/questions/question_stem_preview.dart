/// 题干的一行可读摘要（纯逻辑，不依赖 Flutter / dart:io）。
///
/// 抓题包里的题干是给渲染层准备的：行内公式包在美元符里，题干图片只留一个
/// [图N] 占位。题库列表、题名兜底、导出提示这些地方只需要「一眼认出是哪道题」，
/// 所以这里把标记收掉、把公式内部保留、把图片占位换成统一的 [图]，再折叠空白、
/// 按 runes 截断。真正的图文混排由详情页负责，不走这里。
library;

/// 列表摘要的默认长度（runes，不是 UTF-16 code unit，避免切坏 emoji）。
const int kQuestionStemPreviewMaxLength = 60;

/// 图片占位替换后的统一写法（全角方括号，与抓题侧一致）。
const String kQuestionStemPreviewImageToken = '［图］';

final RegExp _displayMathPattern = RegExp(r'\$\$([\s\S]*?)\$\$');
final RegExp _inlineMathPattern = RegExp(r'\$([^$\n]*?)\$');
final RegExp _markdownImagePattern = RegExp(r'!\[([^\]]*)\]\([^)]*\)');
final RegExp _markdownLinkPattern = RegExp(r'\[([^\]]+)\]\([^)]*\)');
final RegExp _imagePlaceholderPattern = RegExp(
  r'[［\[【]\s*图\s*[0-9０-９]{1,3}\s*[］\]】]',
);

/// 把完整题干收成一行摘要。
///
/// 口径：
/// - 先去掉 $$…$$ 与 $…$ 的**定界符**，公式内部原样保留（$x^2$ 变成 x^2）；
///   没配对的美元符直接删掉，不让它出现在列表里。
/// - Markdown 图片整段删掉；Markdown 链接只留文字。
/// - [图1] / 【图2】 / 全角数字占位统一换成 [图]；越界或没有数字的方括号不动。
/// - 所有空白（含换行、制表、全角空格）折叠成一个半角空格后 trim。
/// - 按 runes 截断到 [maxLength]，超出补一个省略号；[maxLength] <= 0 返回空串。
///
/// 不抛异常：空题干、纯标记都返回空串。
String questionStemPreview(
  String stem, {
  int maxLength = kQuestionStemPreviewMaxLength,
}) {
  if (maxLength <= 0 || stem.isEmpty) {
    return '';
  }
  var text = stem;
  text = text.replaceAllMapped(
    _displayMathPattern,
    (match) => match.group(1) ?? '',
  );
  text = text.replaceAllMapped(
    _inlineMathPattern,
    (match) => match.group(1) ?? '',
  );
  // 走到这里还剩下的美元符都是没配对的，删掉而不是原样留在列表里。
  text = text.replaceAll('\$', '');
  text = text.replaceAll(_markdownImagePattern, ' ');
  text = text.replaceAllMapped(
    _markdownLinkPattern,
    (match) => match.group(1) ?? '',
  );
  text =
      text.replaceAll(_imagePlaceholderPattern, kQuestionStemPreviewImageToken);
  final collapsed = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (collapsed.isEmpty) {
    return '';
  }
  final runes = collapsed.runes.toList(growable: false);
  if (runes.length <= maxLength) {
    return collapsed;
  }
  return '${String.fromCharCodes(runes.take(maxLength))}…';
}
