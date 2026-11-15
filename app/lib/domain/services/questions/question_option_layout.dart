/// 选项 A/B/C/D 的排布判定（纯逻辑，不碰 Flutter）。
///
/// 四个选项都短（化学 Q15 那种）时一行一个会留出大片空白；四个都长（英语阅读
/// 题、解答步骤型选项）时两列又挤。这里给 UI 一个可测的判定：
///
///  * **短选项**：不超过 [kShortOptionMaxRunes] 个可见字符、单行、没有代码块；
///    公式与 `［图N］` 占位不计入可见字符（化学 Q15 的选项全是短文字 + 公式图）；
///  * **两列**还要宽度够：可用宽度 >= 两列各 [kTwoColumnOptionMinCellWidth] +
///    中间间距；窄窗口（手机/半屏）自动退化单列；
///  * 选项少于 2 个、或有空选项时不排两列。
library;

/// 短选项最多几个可见字符（rune；公式/图片占位不算）。
const int kShortOptionMaxRunes = 14;

/// 两列布局时每个选项格子的最小宽度（逻辑像素）。
const double kTwoColumnOptionMinCellWidth = 320;

/// 两列之间的间距。
const double kTwoColumnOptionSpacing = 12;

/// 选项内容里「看得见的文字」有多长（rune）。
///
/// 公式 `$…$`/`$$…$$` 记 1 个字符（视觉上一个公式块），`［图N］`/Markdown 图片
/// 记 0（那是图，不是文字），空白折叠。
int questionOptionVisibleLength(String content) {
  var text = content;
  text = text.replaceAll(
    RegExp(r'!\[[^\]\n]*\]\([^)\n]*\)'),
    '',
  );
  text = text.replaceAll(
    RegExp(r'[［\[【]\s*图\s*[0-9０-９]{1,3}\s*[］\]】]'),
    '',
  );
  text = text.replaceAll(RegExp(r'\$\$[\s\S]*?\$\$'), 'x');
  text = text.replaceAll(RegExp(r'\$[^$\n]*\$'), 'x');
  text = text.replaceAll(RegExp(r'\s+'), '');
  return text.runes.length;
}

/// 四个（或更多）选项能不能排成两列/流式。
///
/// 判定顺序：
/// 1. 选项 < 2 或可用宽度不够 → false；
/// 2. 任一选项多行 / 含代码栅栏 / 可见字符 > [maxShortRunes] / 为空 → false；
/// 3. 其余 → true。
bool questionOptionsFlowIntoTwoColumns({
  required List<String> optionContents,
  required double availableWidth,
  int maxShortRunes = kShortOptionMaxRunes,
  double minCellWidth = kTwoColumnOptionMinCellWidth,
  double spacing = kTwoColumnOptionSpacing,
}) {
  if (optionContents.length < 2) {
    return false;
  }
  if (availableWidth < minCellWidth * 2 + spacing) {
    return false;
  }
  for (final content in optionContents) {
    if (content.contains('\n')) {
      return false;
    }
    if (content.contains('```') || content.contains('~~~')) {
      return false;
    }
    final length = questionOptionVisibleLength(content);
    if (length == 0 || length > maxShortRunes) {
      return false;
    }
  }
  return true;
}
