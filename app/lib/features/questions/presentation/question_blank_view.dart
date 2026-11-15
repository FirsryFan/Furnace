/// 填空空位的**组件化**渲染（固定高度底线，跟随文字行、深浅色都可见）。
///
/// 为什么不是一个字符：`______` 当字符渲染时线高/位置完全跟着 glyph 走，
/// 不同字号/字体下粗细与基线不一致；深色主题里还容易和背景糊在一起。这里画成
/// 一个固定高度的行内 widget（底部一条 1.5px 线）：
///
///  * 宽度来自题面里下划线个数（`question_blank_markup.dart` 的同一份尺寸算法），
///    同一题内多个空位一致；
///  * 高度 `1.25em`，用 [PlaceholderAlignment.bottom] 与文字行底对齐——
///    线落在基线下沿，就是"一条空白下划线"；
///  * 线色取 `onSurface`（深色主题下自动变浅），不会消失；
///  * 公式下标 `a_i`、代码里的 `_` 不经过这里（领域层已经排除）。
library;

import 'package:flutter/material.dart';

import '../../../domain/services/questions/question_blank_markup.dart';

/// 一条空白下划线（填空空位）。
class QuestionBlankUnderline extends StatelessWidget {
  const QuestionBlankUnderline({
    super.key,
    this.width,
    this.height,
    this.color,
  });

  /// 空位宽度；null 时按正文字号取默认宽（3 个下划线）。
  final double? width;

  /// 行内占位高度；null 时取 `1.25em`。
  final double? height;

  /// 线色；null 时取文字色（深色主题自动变浅）。
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fontSize = theme.textTheme.bodyMedium?.fontSize ?? 14;
    final resolvedHeight = height ?? fontSize * 1.25;
    final lineColor = color ??
        theme.colorScheme.onSurface.withValues(alpha: 0.75);
    return SizedBox(
      width: width,
      height: resolvedHeight,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          height: 1.5,
          decoration: BoxDecoration(
            color: lineColor,
            borderRadius: BorderRadius.circular(1),
          ),
        ),
      ),
    );
  }
}

/// `MarkdownRenderer(imageBuilder:)` 的空位分支：空位 URL → 下划线组件；
/// 其它 URL 走包内默认行为（题面 Markdown 里极少有网络图，保持原样）。
Widget questionBlankOrNetworkImage(
  BuildContext context,
  String url,
  double? width,
  double? height,
) {
  final underscores = questionBlankCountFromUrl(url);
  if (underscores != null) {
    return QuestionBlankUnderline(width: width, height: height);
  }
  return Image.network(url);
}

/// 纯文本题面里的空位：把文字与下划线组件混排。
///
/// 用 `SelectionArea + RichText` 而不是 `SelectableText.rich`：后者底层是
/// `EditableText`，不支持 WidgetSpan。这样纯文本仍然可选中/复制。
class QuestionTextWithBlankWidgets extends StatelessWidget {
  const QuestionTextWithBlankWidgets({
    super.key,
    required this.text,
    this.style,
    this.textAlign = TextAlign.start,
  });

  final String text;
  final TextStyle? style;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    final fontSize = style?.fontSize ??
        Theme.of(context).textTheme.bodyMedium?.fontSize ??
        14;
    final blanks = parseQuestionBlanks(text);
    if (blanks.isEmpty) {
      return SelectableText(text, style: style, textAlign: textAlign);
    }
    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final blank in blanks) {
      if (blank.start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, blank.start)));
      }
      final size = questionBlankDisplaySize(blank.underscores, fontSize);
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.bottom,
          child: QuestionBlankUnderline(
            width: size.width,
            height: size.height,
          ),
        ),
      );
      cursor = blank.end;
    }
    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor)));
    }
    return SelectionArea(
      child: RichText(
        textAlign: textAlign,
        text: TextSpan(
          style: style ?? DefaultTextStyle.of(context).style,
          children: spans,
        ),
      ),
    );
  }
}
