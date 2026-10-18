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

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/state/data_revision.dart';
import '../../../data/database/app_database_provider.dart';
import '../../../domain/services/questions/question_number.dart';
import '../../../l10n/app_localizations.dart';
import '../application/question_media_providers.dart';
import '../data/question_media_store.dart';

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
class QuestionImageTile extends ConsumerWidget {
  const QuestionImageTile({
    super.key,
    required this.image,
    this.size = 96,
  });

  final QuestionImage image;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final bytesAsync = ref.watch(questionImageBytesProvider(image.relPath));
    final bytes = bytesAsync.valueOrNull;
    if (bytes == null) {
      return SizedBox(
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
    }
    return Tooltip(
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
class QuestionImagesSection extends ConsumerWidget {
  const QuestionImagesSection({super.key, required this.questionId});

  final String questionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final imagesAsync = ref.watch(questionImagesProvider(questionId));
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
      return const SizedBox.shrink();
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
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                for (final image in images) QuestionImageTile(image: image),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
