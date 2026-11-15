/// 从一条用户消息自动取会话标题。
///
/// 纯函数、无时钟、无网络、无数据库：标题规则要能被单测直接钉住，而不是靠打开
/// 页面观察。调用方（`AiRepository.autoTitleFromFirstMessage`）只负责判断「这个
/// 会话的标题还是占位符吗」，怎么取名字在这里。
///
/// 规则（确定性的，不调用模型）：
///
///  * 取**第一行非空文本**。多行粘贴的常见形态是「一句主题 + 一长串要求」，标题
///    应该来自主题那一行；
///  * 去掉行首的 markdown 装饰（`#` 标题、`>` 引用、`-`/`*`/`+` 列表、`1.`
///    编号），否则左栏会出现一排「# 」；
///  * 空白折叠成一个空格；换行、制表符不可能进入标题；
///  * 最多 [maxLength] 个字符（按 rune 计，不会把 emoji 切一半），超出就截断并
///    加 `…`——截断的标题不能看起来像完整的。
///
/// 什么都不剩（空白消息）时返回 `null`，调用方保持占位标题。
library;

/// 左栏标题的默认长度上限。
///
/// 左栏宽 240 逻辑像素、单行省略，24 个汉字已经会省略；再长对左栏没有意义，
/// 只是把信息推到看不见的地方。
const int defaultConversationTitleLength = 24;

/// 行首的 markdown 装饰：标题 / 引用 / 无序列表 / 有序列表。
final RegExp _leadingDecoration =
    RegExp(r'^\s*(?:#{1,6}\s*|>\s*|[-*+]\s+|\d+[.)]\s+)');

/// 连续空白（含换行、制表符、全角空格之外的普通空白）。
final RegExp _whitespaceRun = RegExp(r'\s+');

/// 为用户消息 [text] 取一个左栏标题；没有可命名的内容时返回 `null`。
String? autoConversationTitle(
  String text, {
  int maxLength = defaultConversationTitleLength,
}) {
  if (maxLength <= 0) {
    return null;
  }
  String? firstLine;
  for (final line in text.split('\n')) {
    final stripped = line.replaceFirst(_leadingDecoration, '');
    final collapsed = stripped.replaceAll(_whitespaceRun, ' ').trim();
    if (collapsed.isNotEmpty) {
      firstLine = collapsed;
      break;
    }
  }
  if (firstLine == null) {
    return null;
  }
  final runes = firstLine.runes.toList(growable: false);
  if (runes.length <= maxLength) {
    return firstLine;
  }
  final cut = String.fromCharCodes(runes.take(maxLength)).trimRight();
  if (cut.isEmpty) {
    return null;
  }
  return '$cut…';
}
