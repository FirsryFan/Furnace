/// 题干/选项里「［图N］」公式图与文字混排的渲染入口（统一 Markdown 渲染器）。
///
/// 为什么单独一层：题干图在库里是 attachments 行（`QuestionImage` / relPath），
/// 题面里只留 `［图N］` 占位。原来的详情页把占位切成图片段、竖着一列摆，公式
/// 图（化学 Q15 有 18 处）会把题面撕成一列大图 + 碎文字。这里把占位翻成
/// Markdown 图片语法交给共享 `MarkdownRenderer`：gpt_markdown 的图片是**行内
/// widget span**，公式图于是能回到句子里，和文字一起折行。
///
/// 尺寸口径（纯展示，不改数据）：
///  * **行内公式图**（占位在句子里）：按图片像素高度的 [_inlineImageScale] 缩放，
///    夹在 [_minInlineHeight]–[_maxInlineHeight] 之间——导入的公式图是同一个
///    字号渲染出来的，统一比例缩放后彼此大小关系还是对的；
///  * **独立成行的图**（前后都是换行）：按像素尺寸显示，最多 [_maxFigureHeight]，
///    这就是插图（如化学 Q15 的曲线图），不按公式缩小；
///  * 字节还没读出来时给同尺寸的小占位，读出来再重建（不跳版）。
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/media/image_size.dart';
import '../../../domain/services/questions/question_blank_markup.dart';
import '../../../domain/services/questions/question_image_markdown.dart';
import '../../markdown/presentation/markdown_renderer.dart';
import 'question_blank_view.dart';
import 'question_markdown_view.dart';
import 'question_media_view.dart';

/// 行内公式图相对像素高度的缩放比例。
///
/// 导入管线把公式对象按同一字号转成 PNG，但转换比例很大（一个字符几百像素），
/// 所以按 0.045 缩回正文大小：`25°C` 这类短公式约 20px 高，分式约 60px 高。
const double _inlineImageScale = 0.045;

/// 行内公式图最小/最大显示高度（逻辑像素）。
const double _minInlineHeight = 14;
const double _maxInlineHeight = 200;

/// 独立成行的插图最大显示高度。
const double _maxFigureHeight = 360;

/// 题干/选项文本 + 题目图片（`［图N］` 占位）的 Markdown 渲染。
///
/// [text] 是原始题干/选项文本；[questionId] 用来读题干图清单与字节。没有图片
/// 或没有有效占位时行为与 [MarkdownQuestionText] 完全一致（不做额外包装）。
class QuestionMarkdownTextWithImages extends ConsumerWidget {
  const QuestionMarkdownTextWithImages({
    super.key,
    required this.questionId,
    required this.text,
    this.style,
    this.textAlign,
    this.markdown = true,
  });

  final String questionId;
  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;
  final bool markdown;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!markdown || !text.contains('图')) {
      return MarkdownQuestionText(
        text: text,
        style: style,
        textAlign: textAlign,
        markdown: markdown,
      );
    }
    final images = ref.watch(questionImagesProvider(questionId)).valueOrNull;
    if (images == null || images.isEmpty) {
      // 图片清单还没读出来：先按纯文字渲染，读出来后同一位置重建。
      return MarkdownQuestionText(
        text: text,
        style: style,
        textAlign: textAlign,
        markdown: markdown,
      );
    }
    final bytesByOrder = <Uint8List?>[];
    final sizesByOrder = <ImageSize?>[];
    for (var order = 0; order < images.length; order++) {
      final bytes =
          ref.watch(questionImageBytesProvider(images[order].relPath)).valueOrNull;
      bytesByOrder.add(bytes);
      final size = bytes == null ? null : readImageSize(bytes);
      sizesByOrder.add(size == null || !size.isValid ? null : size);
    }

    final markup = questionMarkdownWithImagePlaceholders(
      text,
      imageCount: images.length,
      heightOf: (placeholder) =>
          _displayHeight(sizesByOrder[placeholder.order], placeholder.ownLine),
    );
    if (!markup.hasImages) {
      return MarkdownQuestionText(
        text: text,
        style: style,
        textAlign: textAlign,
        markdown: markdown,
      );
    }

    final fontSize = style?.fontSize ??
        Theme.of(context).textTheme.bodyMedium?.fontSize ??
        14;
    return MarkdownRenderer(
      markdown: questionMarkdownSource(markup.markdown, fontSize: fontSize),
      style: style,
      textAlign: textAlign,
      imageBuilder: (context, url, width, height) {
        // 填空空位（组件化下划线）与题干图共用同一个行内图片通道。
        final blankCount = questionBlankCountFromUrl(url);
        if (blankCount != null) {
          return QuestionBlankUnderline(width: width, height: height);
        }
        final order = questionImageOrderFromUrl(url);
        if (order == null || order >= images.length) {
          return const SizedBox(width: 16, height: 16);
        }
        final bytes = bytesByOrder[order];
        final computed = height ??
            _displayHeight(sizesByOrder[order], isFigureUrl(url, markup));
        if (bytes == null) {
          return SizedBox(
            key: ValueKey<String>('question-inline-image-pending-$order'),
            width: computed == null ? 16 : computed * 0.6,
            height: computed ?? 16,
          );
        }
        final image = Image.memory(
          bytes,
          key: ValueKey<String>('question-inline-image-$order'),
          height: computed,
          fit: BoxFit.contain,
          gaplessPlayback: true,
          errorBuilder: (context, error, stackTrace) => SizedBox(
            width: 20,
            height: 20,
            child: Icon(
              Icons.broken_image_outlined,
              size: 16,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        );
        // 公式图是「黑字 + 透明底」的 PNG（WMF 转出来的），深色界面里直接放
        // 会看不见字；给一块浅色底，公式/曲线图在深色主题下仍然可读。浅色
        // 主题不加底，保持原样。
        if (Theme.of(context).brightness != Brightness.dark) {
          return image;
        }
        return DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(3),
          ),
          child: image,
        );
      },
      onImageTap: (url) {
        final order = questionImageOrderFromUrl(url);
        final bytes = order == null || order >= images.length
            ? null
            : bytesByOrder[order];
        if (order == null || bytes == null) {
          return;
        }
        showQuestionImageViewer(context, image: images[order], bytes: bytes);
      },
    );
  }
}

/// 该图片按展示口径应有的高度；拿不到像素尺寸时返回 null（交给渲染器）。
double? _displayHeight(ImageSize? size, bool ownLine) {
  if (size == null || !size.isValid) {
    return null;
  }
  final pixels = size.height.toDouble();
  if (ownLine) {
    return math.min(pixels, _maxFigureHeight);
  }
  return (pixels * _inlineImageScale).clamp(_minInlineHeight, _maxInlineHeight);
}

/// 这个 url 在本次转换里是不是「独立成行」的插图。
///
/// [markup] 里的占位本来就是按出现顺序排的；`question-image:N` 的 N 是
/// 1-based 图片下标，按同一顺序回查即可。
bool isFigureUrl(String url, QuestionImageMarkup markup) {
  final order = questionImageOrderFromUrl(url);
  if (order == null) {
    return false;
  }
  for (final placeholder in markup.placeholders) {
    if (placeholder.order == order) {
      return placeholder.ownLine;
    }
  }
  return false;
}
