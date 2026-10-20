/// 题目编号与题目配图在界面上的读侧：编号徽章、配图缩略图、大图查看。
///
/// 三份数据都是只读 provider：
///
///  * [questionSerialProvider]：题库列表的数据源（`PaperCandidate`）里没有编号，
///    所以按 id 单独读一次 `questions.serialNo`；
///  * [questionImagesProvider]：走 `QuestionMediaStore.list` 的配图清单；
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

import '../../../core/state/data_revision.dart';
import '../../../data/database/app_database_provider.dart';
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

/// 一道题的配图清单（按 sortOrder、createdAt、id 排，store 已经排好）。
final questionImagesProvider =
    FutureProvider.autoDispose.family<List<QuestionImage>, String>(
  (ref, questionId) => ref.watch(questionMediaStoreProvider).list(questionId),
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

/// 题目配图区块：没图就整个不出现，不让空相框占版面。
///
/// 详情页传 `editable: true` 后多出「添加图片」入口与每张图右上角的删除按钮；
/// 别的调用（列表缩略图等）默认只读，行为与以前一致。
class QuestionImagesSection extends ConsumerStatefulWidget {
  const QuestionImagesSection({
    super.key,
    required this.questionId,
    this.editable = false,
  });

  final String questionId;

  /// 是否允许在这里加图、删图。
  final bool editable;

  @override
  ConsumerState<QuestionImagesSection> createState() =>
      _QuestionImagesSectionState();
}

class _QuestionImagesSectionState extends ConsumerState<QuestionImagesSection> {
  /// 添加/删除进行中：按钮一起禁用，避免同一张图被反复提交。
  bool _busy = false;

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
      // questionImagesProvider 没有 watch 数据修订号：写完必须手动让它重读。
      ref.invalidate(questionImagesProvider(widget.questionId));
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

  Future<void> _deleteImage(QuestionImage image) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.questionImageDeleteTitle),
        content: Text(l10n.questionImageDeleteConfirm(image.fileName)),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.commonClose),
          ),
          FilledButton(
            key: questionImageDeleteConfirmButtonKey,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.questionImageDeleteAction),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    try {
      await ref.read(questionMediaStoreProvider).delete(image);
      if (!mounted) {
        return;
      }
      ref.invalidate(questionImagesProvider(widget.questionId));
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.questionImageDeleted)),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.questionImageDeleteFailed('$error'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final imagesAsync = ref.watch(questionImagesProvider(widget.questionId));
    if (imagesAsync.hasError) {
      return Padding(
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
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          children: <Widget>[
            TextButton.icon(
              key: questionImageAddButtonKey,
              onPressed: _busy ? null : _addImages,
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: Text(l10n.questionImageAdd),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                l10n.questionImageEmptyHint,
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
      );
    }
    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  Icons.photo_library_outlined,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Text(l10n.questionDetailImagesSection,
                    style: theme.textTheme.titleSmall),
                const SizedBox(width: 8),
                Text(
                  l10n.questionImageCount(images.length),
                  style: theme.textTheme.bodySmall,
                ),
                if (widget.editable) ...<Widget>[
                  const Spacer(),
                  TextButton.icon(
                    key: questionImageAddButtonKey,
                    onPressed: _busy ? null : _addImages,
                    icon: const Icon(Icons.add_photo_alternate_outlined),
                    label: Text(l10n.questionImageAdd),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                for (final image in images)
                  QuestionImageTile(
                    image: image,
                    onDelete: widget.editable && !_busy
                        ? () => _deleteImage(image)
                        : null,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
