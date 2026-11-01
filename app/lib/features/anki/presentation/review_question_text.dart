/// 闪存卡题干的富文本渲染：Markdown + LaTeX + 图片（照片）。
///
/// 只做渲染，不读库、不联网：
/// * 文字段复用题库详情页同一个 [MarkdownQuestionText]（纯文本 → SelectableText，
///   含完整公式 → GptMarkdown），所以纯文本/模板卡的观感与改造前一致；
/// * 图片有两个入口——
///   1. **［图N］占位**（全角/半角方括号、【】都认）：按 [images] 的 0-based
///      顺序插到文字里，切分口径复用 `question_stem_segments.dart`
///      （越界占位保留原文、没被引用的图接在末尾）；
///   2. **Markdown 图片路径** `![alt](path)`：调用方用 [imageByPath] 把路径映射
///      到已读出的字节；映射不到的路径在纯文本模式保留原文、Markdown 模式转成
///      行内代码字面显示——**绝不让渲染器去 NetworkImage 拉网络图**。
///
/// "不会崩"是硬口径：图字节坏了只画一个坏图占位，不抛、不吞掉同一段的文字。
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../domain/services/questions/question_stem_segments.dart';
import '../../questions/presentation/question_markdown_view.dart';

/// 一张已读成字节的题干图。
///
/// 来源由调用方决定（附件读盘、知识包资产、拍照整理），组件本身不碰 IO。
class ReviewQuestionImage {
  const ReviewQuestionImage({required this.bytes, this.semanticLabel});

  /// 图片字节（PNG/JPEG/WebP/GIF…，交给 Flutter 解码器）。
  final Uint8List bytes;

  /// 无障碍描述；null 时读屏不把它当内容图片。
  final String? semanticLabel;
}

/// 题干渲染块的根 key。
const Key reviewQuestionTextKey = Key('review-question-text');

/// 第 [order] 张题干图的 key（0-based，按插入顺序）。
Key reviewQuestionImageKey(int order) =>
    ValueKey<String>('review-question-image-$order');

/// 第 [order] 张题干图解码失败时的占位 key。
Key reviewQuestionBrokenImageKey(int order) =>
    ValueKey<String>('review-question-image-broken-$order');

/// 闪存卡题干：纯文本 / Markdown+LaTeX / ［图N］与 Markdown 图片路径混排。
class ReviewQuestionText extends StatelessWidget {
  const ReviewQuestionText({
    super.key,
    required this.text,
    this.style,
    this.textAlign,
    this.markdown = false,
    this.images = const <ReviewQuestionImage>[],
    this.imageByPath = const <String, ReviewQuestionImage>{},
    this.maxImageHeight = 320,
  });

  /// 题干原文。
  final String text;

  /// 正文样式；Markdown 的标题/列表按包内默认比例派生。
  final TextStyle? style;

  /// 段落水平对齐。
  final TextAlign? textAlign;

  /// true：整段按 Markdown 渲染（行内/块级公式、标题、列表都会解析）；false：
  /// 原文是数据，只有闭合的行内公式交给渲染器（与题库详情页同一口径）。
  final bool markdown;

  /// ［图N］占位对应的图片，0-based 顺序。
  final List<ReviewQuestionImage> images;

  /// Markdown 图片语法里的路径 → 图片。解析不到就按字面处理，不联网。
  final Map<String, ReviewQuestionImage> imageByPath;

  /// 单张图最大高度（逻辑像素），避免一张原图把整页撑爆。
  final double maxImageHeight;

  @override
  Widget build(BuildContext context) {
    final resolved = _resolveMarkdownImagePaths(
      text: text,
      images: images,
      imageByPath: imageByPath,
      markdown: markdown,
    );
    final layout = splitQuestionStemImages(
      resolved.text,
      imageCount: resolved.images.length,
    );
    final hasImage = layout.segments.any((segment) => segment.isImage) ||
        layout.unplacedImageOrders.isNotEmpty;
    if (!hasImage) {
      // 没有图：与改造前逐字一致，仍走同一个 MarkdownQuestionText。
      return KeyedSubtree(
        key: reviewQuestionTextKey,
        child: MarkdownQuestionText(
          text: resolved.text,
          style: style,
          textAlign: textAlign,
          markdown: markdown,
        ),
      );
    }

    return Column(
      key: reviewQuestionTextKey,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final segment in layout.segments)
          if (segment.isText)
            MarkdownQuestionText(
              text: segment.text,
              style: style,
              textAlign: textAlign,
              markdown: markdown,
            )
          else
            _imageOf(
              context,
              resolved.images[segment.imageOrder!],
              segment.imageOrder!,
            ),
        // 没被任何占位引用的图接在文字末尾（与题库详情页同一口径）。
        for (final order in layout.unplacedImageOrders)
          _imageOf(context, resolved.images[order], order),
      ],
    );
  }

  Widget _imageOf(BuildContext context, ReviewQuestionImage image, int order) {
    final theme = Theme.of(context);
    return Padding(
      key: reviewQuestionImageKey(order),
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxImageHeight),
        child: Image.memory(
          image.bytes,
          fit: BoxFit.contain,
          gaplessPlayback: true,
          semanticLabel: image.semanticLabel,
          // 解码完成前给一个占位高度，页面不会先塌一条再跳开。
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
            if (wasSynchronouslyLoaded || frame != null) {
              return child;
            }
            return const SizedBox(height: 120);
          },
          errorBuilder: (context, error, stackTrace) => Container(
            key: reviewQuestionBrokenImageKey(order),
            height: 120,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.broken_image_outlined,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

/// 把能解析到字节的 Markdown 图片语法换成 ［图N］占位，让同一套切分逻辑处理。
///
/// * 解析到：追加到图片列表末尾（于是 N = 追加后的 1-based 序号）；
/// * 解析不到：纯文本模式原样保留（SelectableText 不会去加载它）；Markdown 模式
///   转成行内代码字面显示——gpt_markdown 会把图片路径交给 NetworkImage，这里
///   必须堵住，否则离线的题干会触发网络请求。
({String text, List<ReviewQuestionImage> images}) _resolveMarkdownImagePaths({
  required String text,
  required List<ReviewQuestionImage> images,
  required Map<String, ReviewQuestionImage> imageByPath,
  required bool markdown,
}) {
  if (!text.contains('![')) {
    return (text: text, images: images);
  }
  final effective = <ReviewQuestionImage>[...images];
  final pattern = RegExp(r'!\[[^\]\n]*\]\(([^)\n]+)\)');
  final buffer = StringBuffer();
  var cursor = 0;
  for (final match in pattern.allMatches(text)) {
    buffer.write(text.substring(cursor, match.start));
    final path = match.group(1)!.trim();
    final image = imageByPath[path];
    if (image != null) {
      effective.add(image);
      buffer.write('［图${effective.length}］');
    } else if (markdown) {
      // 行内代码：字面显示原文，同时让 Markdown 渲染器没有图片可加载。
      buffer.write('`${match.group(0)}`');
    } else {
      buffer.write(match.group(0));
    }
    cursor = match.end;
  }
  buffer.write(text.substring(cursor));
  return (text: buffer.toString(), images: effective);
}
