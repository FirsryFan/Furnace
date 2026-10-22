/// 题目编号与题目配图在界面上的读侧：编号徽章、配图缩略图、大图查看、配图增删。
///
/// 三份数据都是只读 provider：
///
///  * [questionSerialProvider]：题库列表的数据源（`PaperCandidate`）里没有编号，
///    所以按 id 单独读一次 `questions.serialNo`；
///  * [questionImagesProvider]：题干配图清单（role=stem）；
///  * [questionAnswerImagesProvider]：答案/解析截图清单（role=answer）；
///  * [questionImageBytesProvider]：按 relPath 读字节，缩略图与大图共用。
///
/// 「没有图就不出现」是本文件的硬规则：空清单、读不出的图都不占版面，页面上不会
/// 出现一排空相框。
library;

import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

import '../../../core/state/data_revision.dart';
import '../../../data/database/app_database_provider.dart';
import '../../../domain/services/media/thumbnail_spec.dart';
import '../../../domain/services/questions/question_number.dart';
import '../../../l10n/app_localizations.dart';
import '../application/question_media_providers.dart';
import '../data/question_media_store.dart';
import 'drop_intake_filter.dart';

/// 按 id 读题目编号（`questions.serialNo`）；题不存在时返回 null。
final questionSerialProvider =
    FutureProvider.autoDispose.family<int?, String>((ref, questionId) async {
  ref.watchDatabaseRevision();
  final database = ref.watch(appDatabaseProvider);
  final serialNo = database.questions.serialNo;
  final query = database.selectOnly(database.questions)
    ..addColumns([serialNo])
    ..where(database.questions.id.equals(questionId));
  final row = await query.getSingleOrNull();
  return row?.read(serialNo);
});

/// 一道题的**题干配图**清单（role=stem；v27 之前的 NULL 旧行也算题干配图）。
///
/// 按 sortOrder、createdAt、id 排，store 已经排好。
final questionImagesProvider =
    FutureProvider.autoDispose.family<List<QuestionImage>, String>(
  (ref, questionId) => ref
      .watch(questionMediaStoreProvider)
      .list(questionId, role: QuestionImageRole.stem),
);

/// 一道题的**答案/解析截图**清单（role=answer）。
///
/// 组卷网登录后才看得到的整张答案图，单独一区，不和题干配图混。
final questionAnswerImagesProvider =
    FutureProvider.autoDispose.family<List<QuestionImage>, String>(
  (ref, questionId) => ref
      .watch(questionMediaStoreProvider)
      .list(questionId, role: QuestionImageRole.answer),
);

/// 按 relPath 读一张图的字节；文件不在了返回 null。
final questionImageBytesProvider =
    FutureProvider.autoDispose.family<Uint8List?, String>(
  (ref, relPath) => ref.watch(questionMediaStoreProvider).readBytes(relPath),
);

/// 详情页「添加配图」按钮的稳定 key（widget 测试点这里）。
const Key questionImageAddButtonKey = Key('question-image-add');

/// 删除确认对话框里「删除」按钮的 key。
const Key questionImageDeleteConfirmButtonKey =
    Key('question-image-delete-confirm');

/// 某一张图的删除按钮 key；不同图不能撞车。
Key questionImageDeleteButtonKey(String attachmentId) =>
    ValueKey<String>('question-image-delete-$attachmentId');

/// 题干配图区块的根 key：同页还有答案截图区时，测试用它分开断言。
const Key questionImagesSectionKey = Key('question-images-section');

/// 答案/解析截图区块的根 key。
const Key questionAnswerImagesSectionKey =
    Key('question-answer-images-section');

/// 「添加答案截图」按钮的 key（与题干配图的添加按钮分开）。
const Key questionAnswerImageAddButtonKey = Key('question-answer-image-add');

/// 删除答案截图时确认对话框里「删除」按钮的 key。
const Key questionAnswerImageDeleteConfirmButtonKey =
    Key('question-answer-image-delete-confirm');

/// 添加配图时让用户选的扩展名。
///
/// HEIC/HEIF 不在这里：Dart 的图片解码器不支持，选中也只会是坏图。
const List<String> questionImageAddExtensions = <String>[
  'png',
  'jpg',
  'jpeg',
  'webp',
  'gif',
  'bmp',
];

/// 文件名是不是 HEIC/HEIF（大小写不敏感）。
bool questionImageAddIsHeic(String fileName) {
  final lower = fileName.trim().toLowerCase();
  return lower.endsWith('.heic') || lower.endsWith('.heif');
}

/// 添加配图时按文件名推 MIME；HEIC 与不认识的扩展名返回 null（不接收）。
String? questionImageAddMimeForName(String fileName) {
  if (questionImageAddIsHeic(fileName)) {
    return null;
  }
  final mime = dropIntakeMimeForName(fileName);
  if (mime == null || mime == 'image/heic') {
    return null;
  }
  return mime;
}

/// 题干图文混排流（文字段 + 内嵌大图）的根 key：测试用它把题干图与答案图分开。
const Key questionStemImagesKey = Key('question-stem-images');

/// 题目原文（题干/选项/答案/解析）的渲染。
///
/// 规则和 AI 消息体同一个口径：**原文是数据，不整段当 markdown 改写**。
///
///  * 没有公式的文本走 [SelectableText]：`*`、`_`、`#` 这些字符原样显示，
///    不因为题面里恰巧出现就变成强调或列表；
///  * 只有成对的 `$…$` / `\(…\)` 公式才把整段交给 [GptMarkdown]，
///    打开 `useDollarSignsForLatex` 让公式真正排出来，而不是字面的美元符号。
///
/// 只认闭合的公式：单个 `$`（比如价格）仍按原文显示，避免半个定界符吃掉
/// 后面的整段文字（与 AI 消息的「结构完整才解析」一致）。
class QuestionRichText extends StatelessWidget {
  const QuestionRichText({
    super.key,
    required this.text,
    this.style,
    this.textAlign,
  });

  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;

  static final RegExp _dollarMath = RegExp(r'\$[^$\n]+?\$');
  static final RegExp _parenMath = RegExp(r'\\\([^)\n]*?\\\)');

  /// 是否含有完整闭合的行内公式定界符。
  static bool containsMath(String text) =>
      _dollarMath.hasMatch(text) || _parenMath.hasMatch(text);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (!containsMath(text)) {
      return SelectableText(text, style: style, textAlign: textAlign);
    }
    return SelectionArea(
      child: GptMarkdown(
        text,
        style: style,
        textAlign: textAlign ?? TextAlign.start,
        useDollarSignsForLatex: true,
        styleSheet: GptMarkdownStyleSheet(
          link: LinkStyle(color: theme.colorScheme.primary),
        ),
      ),
    );
  }
}

/// 列表里用的题号文字：没编号时用 l10n 的占位，不把中文常量带进英文界面。
String questionSerialText(AppLocalizations l10n, int? serialNo) =>
    serialNo == null
        ? l10n.questionSerialUnnumbered
        : formatQuestionSerial(serialNo);

/// 题号徽章：稳定标识，点一下复制（没编号的题不提供复制）。
class QuestionSerialBadge extends StatelessWidget {
  const QuestionSerialBadge({
    super.key,
    required this.serialNo,
    this.copyable = true,
    this.dense = false,
  });

  /// 题目编号；null 表示老题还没回填编号。
  final int? serialNo;

  /// 是否允许点击复制。
  final bool copyable;

  /// 列表里用的小号徽章。
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final label = questionSerialText(l10n, serialNo);
    final badge = Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 6 : 8,
        vertical: dense ? 2 : 3,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            Icons.tag,
            size: dense ? 12 : 14,
            color: theme.colorScheme.onSecondaryContainer,
          ),
          const SizedBox(width: 2),
          Text(
            label,
            style: (dense
                    ? theme.textTheme.labelSmall
                    : theme.textTheme.labelMedium)
                ?.copyWith(color: theme.colorScheme.onSecondaryContainer),
          ),
        ],
      ),
    );
    if (!copyable || serialNo == null) {
      return badge;
    }
    return Tooltip(
      message: l10n.questionSerialCopyTooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () {
          unawaited(Clipboard.setData(ClipboardData(text: label)));
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(content: Text(l10n.questionSerialCopied(label))),
            );
        },
        child: badge,
      ),
    );
  }
}

/// 按 id 读题号再渲染徽章：列表/候选行的号码是异步读出来的。
///
/// 读取中与读失败都返回零尺寸：列表行里宁可暂时没有号，也不摆一个空相框或
/// 半截加载圈；读到 null 时交给 [QuestionSerialBadge] 显示「未编号」占位文字。
class QuestionSerialBadgeById extends ConsumerWidget {
  const QuestionSerialBadgeById({
    super.key,
    required this.questionId,
    this.copyable = true,
    this.dense = true,
  });

  final String questionId;
  final bool copyable;
  final bool dense;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final serialAsync = ref.watch(questionSerialProvider(questionId));
    if (serialAsync.hasError ||
        (serialAsync.isLoading && !serialAsync.hasValue)) {
      return const SizedBox.shrink();
    }
    return QuestionSerialBadge(
      serialNo: serialAsync.valueOrNull,
      copyable: copyable,
      dense: dense,
    );
  }
}

/// 列表行首的小缩略图：没有配图就完全不占位。
class QuestionCoverThumbnail extends ConsumerWidget {
  const QuestionCoverThumbnail({
    super.key,
    required this.questionId,
    this.size = 48,
  });

  final String questionId;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final images = ref.watch(questionImagesProvider(questionId)).valueOrNull;
    if (images == null || images.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: QuestionImageTile(image: images.first, size: size),
    );
  }
}

/// 一张配图的缩略图：点开看大图；字节读不出来时给一个坏图标记，不崩。
///
/// 详情页的编辑模式传 [onDelete]：右上角多一个删除按钮，点击后的确认和落盘由
/// 调用方负责（缩略图本身不碰 store）。
class QuestionImageTile extends ConsumerWidget {
  const QuestionImageTile({
    super.key,
    required this.image,
    this.size = 96,
    this.onDelete,
  });

  final QuestionImage image;
  final double size;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    // 解码尺寸按「显示尺寸 × 设备像素比」算（上限 1024）：格子里只显示
    // 48-96 逻辑像素，按原图解码一张手机照片要几十 MB（thumbnail_spec.dart）。
    final decode = thumbnailDecodeSpec(
      logicalWidth: size.round(),
      logicalHeight: size.round(),
      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
    );
    final bytesAsync = ref.watch(questionImageBytesProvider(image.relPath));
    final bytes = bytesAsync.valueOrNull;
    final Widget content;
    if (bytes == null) {
      content = SizedBox(
        width: size,
        height: size,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            Icons.broken_image_outlined,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    } else {
      content = Tooltip(
        message: l10n.questionImageOpenTooltip,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            onTap: () =>
                showQuestionImageViewer(context, image: image, bytes: bytes),
            child: Image.memory(
              bytes,
              width: size,
              height: size,
              // 空 spec 表示尺寸非法：Flutter 断言 cache 必须 > 0，宁可不传。
              cacheWidth: decode.isEmpty ? null : decode.cacheWidth,
              cacheHeight: decode.isEmpty ? null : decode.cacheHeight,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (context, error, stackTrace) => SizedBox(
                width: size,
                height: size,
                child: Icon(
                  Icons.broken_image_outlined,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ),
      );
    }
    final delete = onDelete;
    if (delete == null) {
      return content;
    }
    return Stack(
      children: <Widget>[
        content,
        Positioned(
          top: 2,
          right: 2,
          child: IconButton(
            key: questionImageDeleteButtonKey(image.attachmentId),
            tooltip: l10n.questionImageDeleteTooltip,
            iconSize: 16,
            visualDensity: VisualDensity.compact,
            style: IconButton.styleFrom(
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
            ),
            onPressed: delete,
            // 不用 X：大图对话框也用 X 关闭，同一个页面里两个 X 会互相打架
            // （既有详情页测试按 `find.byIcon(Icons.close)` 点关闭）。
            icon: Icon(
              Icons.delete_outline,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

/// 打开大图对话框：可缩放，右上角关闭。
Future<void> showQuestionImageViewer(
  BuildContext context, {
  required QuestionImage image,
  required Uint8List bytes,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) {
      final screen = MediaQuery.sizeOf(dialogContext);
      return Dialog(
        child: SizedBox(
          width: screen.width * 0.9,
          height: screen.height * 0.85,
          child: Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        image.fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(dialogContext).textTheme.titleSmall,
                      ),
                    ),
                    IconButton(
                      tooltip: MaterialLocalizations.of(dialogContext)
                          .closeButtonTooltip,
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(dialogContext).pop(),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 5,
                  child: SizedBox.expand(
                    child: Image.memory(
                      bytes,
                      fit: BoxFit.contain,
                      gaplessPlayback: true,
                      errorBuilder: (context, error, stackTrace) => Center(
                        child: Icon(
                          Icons.broken_image_outlined,
                          size: 48,
                          color: Theme.of(dialogContext)
                              .colorScheme
                              .onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// 正文里的大图：题干图文混排与答案截图共用。
///
/// * 全宽显示、圆角 12、等比缩放，最高不超过屏幕高度的 60%（竖长截图也
///   不会把一屏占满，下面的内容还得能看见）；
/// * 点开走 [showQuestionImageViewer]（可缩放，且不解码成缩略图）；
/// * [editable] 时的右上角删除按钮复用详情页原来的确认流程与文案：
///   删完让对应的清单 provider 重读，页面上这张图与编辑行一起更新；
/// * 字节读不出来只给一块坏图占位，不崩、不整页失败。
class QuestionInlineImage extends ConsumerStatefulWidget {
  const QuestionInlineImage({
    super.key,
    required this.questionId,
    required this.image,
    this.kind = QuestionImagesSectionKind.stem,
    this.editable = false,
  });

  final String questionId;

  final QuestionImage image;

  /// 删除确认与提示文案用哪一套（题干配图 / 答案截图）。
  final QuestionImagesSectionKind kind;

  /// 是否允许在这张图上直接删除。
  final bool editable;

  @override
  ConsumerState<QuestionInlineImage> createState() =>
      _QuestionInlineImageState();
}

class _QuestionInlineImageState extends ConsumerState<QuestionInlineImage> {
  /// 删除进行中：按钮禁用，避免对同一张图重复提交。
  bool _busy = false;

  bool get _isAnswer => widget.kind == QuestionImagesSectionKind.answer;

  AutoDisposeFutureProvider<List<QuestionImage>> get _imagesProvider =>
      _isAnswer
          ? questionAnswerImagesProvider(widget.questionId)
          : questionImagesProvider(widget.questionId);

  Key get _deleteConfirmButtonKey => _isAnswer
      ? questionAnswerImageDeleteConfirmButtonKey
      : questionImageDeleteConfirmButtonKey;

  String _deleteTitle(AppLocalizations l10n) => _isAnswer
      ? l10n.questionAnswerImageDeleteTitle
      : l10n.questionImageDeleteTitle;

  String _deletedLabel(AppLocalizations l10n) =>
      _isAnswer ? l10n.questionAnswerImageDeleted : l10n.questionImageDeleted;

  Future<void> _deleteImage() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_deleteTitle(l10n)),
        content: Text(l10n.questionImageDeleteConfirm(widget.image.fileName)),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.commonClose),
          ),
          FilledButton(
            key: _deleteConfirmButtonKey,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.questionImageDeleteAction),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(questionMediaStoreProvider).delete(widget.image);
      if (!mounted) {
        return;
      }
      ref.invalidate(_imagesProvider);
      messenger.showSnackBar(
        SnackBar(content: Text(_deletedLabel(l10n))),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.questionImageDeleteFailed('$error'))),
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final bytes =
        ref.watch(questionImageBytesProvider(widget.image.relPath)).valueOrNull;
    // 竖长图最多占屏高 60%：下面还有答案/解析，不能让一张截图把整页顶走。
    final maxHeight = MediaQuery.sizeOf(context).height * 0.6;

    final Widget content = LayoutBuilder(
      builder: (context, constraints) {
        final fallbackWidth = MediaQuery.sizeOf(context).width;
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : fallbackWidth;
        Widget placeholderBox(IconData icon) => SizedBox(
              width: width,
              height: 180,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            );
        Widget brokenPlaceholder() =>
            placeholderBox(Icons.broken_image_outlined);
        // 解码完成前 Image 的高度会塌成 0，页面先跳一下再撑开：给一个占位高度。
        // 顺带让「图还在解码」时也能点开大图（bytes 已经读到了）。
        Widget pendingPlaceholder() => placeholderBox(Icons.image_outlined);
        if (bytes == null) {
          return brokenPlaceholder();
        }
        // 解码尺寸按「显示宽度 × DPR」估算（长边 1024 上限）。只传 cacheWidth：
        // 原图宽高比未知，同时传 cacheWidth/cacheHeight 会把图压变形；给宽度
        // 让解码器自己按比例算高度。
        final decode = thumbnailDecodeSpec(
          logicalWidth: width.round(),
          logicalHeight: width.round(),
          devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
        );
        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: () => showQuestionImageViewer(
                context,
                image: widget.image,
                bytes: bytes,
              ),
              child: Image.memory(
                bytes,
                width: width,
                fit: BoxFit.contain,
                cacheWidth: decode.isEmpty ? null : decode.cacheWidth,
                gaplessPlayback: true,
                frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                  if (wasSynchronouslyLoaded || frame != null) {
                    return child;
                  }
                  return pendingPlaceholder();
                },
                errorBuilder: (context, error, stackTrace) =>
                    brokenPlaceholder(),
              ),
            ),
          ),
        );
      },
    );

    if (!widget.editable) {
      return content;
    }
    return Stack(
      children: <Widget>[
        content,
        Positioned(
          top: 6,
          right: 6,
          child: IconButton(
            key: questionImageDeleteButtonKey(widget.image.attachmentId),
            tooltip: l10n.questionImageDeleteTooltip,
            iconSize: 16,
            visualDensity: VisualDensity.compact,
            style: IconButton.styleFrom(
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
            ),
            onPressed: _busy ? null : _deleteImage,
            // 不用 X：大图对话框也用 X 关闭，同一个页面里两个 X 会互相打架
            // （既有详情页测试按 `find.byIcon(Icons.close)` 点关闭）。
            icon: Icon(
              Icons.delete_outline,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

/// 图片区块的用途：题干配图，还是答案/解析截图。
///
/// 两者共用同一套「选图 → 校验 → 落盘 → 缩略图/大图 → 删除」流程，只有角色、
/// 标题与入口文案不同；答案截图单独一区，不和题干配图混。
enum QuestionImagesSectionKind {
  /// 题干配图（[QuestionImageRole.stem]）。
  stem,

  /// 答案/解析截图（[QuestionImageRole.answer]）。
  answer,
}

/// 题目图片区块：没图就整个不出现，不让空相框占版面。
///
/// 详情页传 `editable: true` 后多出添加入口与每张图右上角的删除按钮；
/// 别的调用（列表缩略图等）默认只读，行为与以前一致。
///
/// [kind] 决定这一区存的是题干配图（默认）还是答案/解析截图：两区各自读自己的
/// 清单、写自己的角色，互不混。
class QuestionImagesSection extends ConsumerStatefulWidget {
  const QuestionImagesSection({
    super.key,
    required this.questionId,
    this.editable = false,
    this.kind = QuestionImagesSectionKind.stem,
    this.showImages = true,
  });

  final String questionId;

  /// 是否允许在这里加图、删图。
  final bool editable;

  /// 这一区存的是题干配图还是答案截图。
  final QuestionImagesSectionKind kind;

  /// 是否把图片本身也画在这里。
  ///
  /// 题干配图在详情页按占位符与文字混排（由调用方渲染），这里传 false，
  /// 只保留末尾一行的添加入口与张数；答案截图没有混排问题，默认 true。
  final bool showImages;

  @override
  ConsumerState<QuestionImagesSection> createState() =>
      _QuestionImagesSectionState();
}

class _QuestionImagesSectionState extends ConsumerState<QuestionImagesSection> {
  /// 添加/删除进行中：按钮一起禁用，避免同一张图被反复提交。
  bool _busy = false;

  bool get _isAnswer => widget.kind == QuestionImagesSectionKind.answer;

  /// 写库/读库时用的角色；题干配图与答案截图各排各的 sortOrder。
  String get _role =>
      _isAnswer ? QuestionImageRole.answer : QuestionImageRole.stem;

  AutoDisposeFutureProvider<List<QuestionImage>> get _imagesProvider =>
      _isAnswer
          ? questionAnswerImagesProvider(widget.questionId)
          : questionImagesProvider(widget.questionId);

  Key get _sectionKey =>
      _isAnswer ? questionAnswerImagesSectionKey : questionImagesSectionKey;

  Key get _addButtonKey =>
      _isAnswer ? questionAnswerImageAddButtonKey : questionImageAddButtonKey;

  String _addLabel(AppLocalizations l10n) =>
      _isAnswer ? l10n.questionAnswerImageAdd : l10n.questionImageAdd;

  String _emptyHint(AppLocalizations l10n) => _isAnswer
      ? l10n.questionAnswerImageEmptyHint
      : l10n.questionImageEmptyHint;

  Future<void> _addImages() async {
    if (_busy) {
      return;
    }
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    List<PlatformFile> picked;
    try {
      picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: questionImageAddExtensions,
      );
    } catch (error) {
      // 选图打不开（缺平台实现、权限被撤）要说出来，不能让按钮看起来是死的。
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.questionImageAddFailed('$error'))),
      );
      return;
    }
    if (picked.isEmpty || !mounted) {
      return;
    }
    setState(() => _busy = true);
    final store = ref.read(questionMediaStoreProvider);
    var saved = 0;
    var skipped = 0;
    var heic = 0;
    for (final file in picked) {
      if (questionImageAddIsHeic(file.name)) {
        heic++;
        continue;
      }
      final mime = questionImageAddMimeForName(file.name);
      if (mime == null) {
        skipped++;
        continue;
      }
      try {
        final bytes = await file.readAsBytes();
        if (bytes.isEmpty) {
          // 0 字节文件不是图：Image.memory 解不出来，算跳过而不是落一张坏图。
          skipped++;
          continue;
        }
        await store.save(
          questionId: widget.questionId,
          fileName: file.name,
          bytes: bytes,
          mime: mime,
          role: _role,
        );
        saved++;
      } catch (_) {
        // 单个文件读不出来不整批失败：其余照收，最后一起说清楚。
        skipped++;
      }
    }
    if (!mounted) {
      return;
    }
    if (saved > 0) {
      // 图片清单 provider 不 watch 数据修订号：写完必须手动让它重读。
      ref.invalidate(_imagesProvider);
    }
    final parts = <String>[
      if (saved > 0) l10n.questionImageAddDone(saved),
      if (skipped > 0) l10n.questionImageAddSkipped(skipped),
      if (heic > 0) l10n.questionImageHeicUnsupported,
    ];
    if (parts.isNotEmpty) {
      messenger.showSnackBar(SnackBar(content: Text(parts.join(' · '))));
    }
    setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final imagesAsync = ref.watch(_imagesProvider);
    if (imagesAsync.hasError) {
      return Padding(
        key: _sectionKey,
        padding: const EdgeInsets.only(top: 12),
        child: Text(
          l10n.questionImageLoadFailed,
          style: theme.textTheme.bodySmall,
        ),
      );
    }
    final images = imagesAsync.valueOrNull;
    if (images == null || images.isEmpty) {
      if (!widget.editable) {
        return const SizedBox.shrink();
      }
      // 编辑模式也要有一个入口，但仍只占一行字，不摆空相框。
      return Padding(
        key: _sectionKey,
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          children: <Widget>[
            TextButton.icon(
              key: _addButtonKey,
              onPressed: _busy ? null : _addImages,
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: Text(_addLabel(l10n)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _emptyHint(l10n),
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
      );
    }
    // 图片本身不再套卡片底座：题干图按占位符混排在正文里，答案图
    // 直接跟在答案后面；这里只补一行「添加 + 已加 N 张」的编辑入口。
    return Column(
      key: _sectionKey,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (widget.showImages)
          for (final image in images)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: QuestionInlineImage(
                questionId: widget.questionId,
                image: image,
                kind: widget.kind,
                editable: widget.editable && !_busy,
              ),
            ),
        if (widget.editable)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: <Widget>[
                TextButton.icon(
                  key: _addButtonKey,
                  onPressed: _busy ? null : _addImages,
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: Text(_addLabel(l10n)),
                ),
                const SizedBox(width: 8),
                Text(
                  l10n.questionImageCount(images.length),
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
      ],
    );
  }
}
