/// 拍照整理的待确认队列（`docs/QUESTION_BANK_DESIGN.md` §7.3–§7.4）。
///
/// 用户口径是「全部走待确认清单，逐个确认；**确认前不写库**」。这一页只做三件事：
/// 把待整理的照片排出来、把模型整理出来的提案摆出来、让用户逐条或整批确认。
/// 真正的写库动作在 [HandwritingQueueNotifier]（application 层）里，页面不碰仓储。
///
/// 三条显示纪律（与组卷页、详情页同一条）：
///
///  * `rationaleZh` 是领域层给用户看的话，**原样显示**，页面不另写一套文案；
///  * `confidence` **不显示成百分比**——0.83 会让人读成"83% 正确"，而它其实是
///    模型自己的犹豫程度。这里折成「较确定 / 拿不准 / 不太确定」三档；
///  * `analyze` 失败时**只显示失败原因**，不显示上一轮的旧提案：留着旧提案会让
///    用户以为这次整理成功了（队列层也已经把旧 set 删掉了，这里是第二道保险）。
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/services/intake/handwriting_proposal_preview.dart';
import '../../../domain/services/intake/handwriting_proposals.dart';
import '../../../l10n/app_localizations.dart';
import '../application/handwriting_proposal_service.dart';
import '../data/handwriting_intake_store.dart';
import 'question_intake_page.dart';

/// 「全部确认」按钮：整批里有一条不能确认时它必须是禁用的。
const Key handwritingQueueApplyAllKey = Key('handwriting-queue-apply-all');

/// 某条提案的「确认」按钮（被预检阻断时禁用）。
Key handwritingProposalApplyKey(String proposalId) =>
    ValueKey<String>('handwriting-proposal-apply-$proposalId');

/// 某条提案的预检结论块（会写到哪 / 要看一眼什么 / 为什么不能确认）。
Key handwritingProposalPreviewKey(String proposalId) =>
    ValueKey<String>('handwriting-proposal-preview-$proposalId');

/// 「整理全部」：把队列里还没整理的照片一次跑完（运行中禁用并显示进度）。
const Key handwritingBatchAnalyzeAllKey = Key('handwriting-batch-analyze-all');

/// 批次运行中的「停止」：当前这张整理完后不再发起下一张。
const Key handwritingBatchStopKey = Key('handwriting-batch-stop');

/// 一次批次结束后的汇总行（成功 / 失败 / 跳过）。
const Key handwritingBatchSummaryKey = Key('handwriting-batch-summary');

/// 照片多选（合并整理）模式的入口：AppBar 右上角「选择照片」/「取消选择」。
const Key handwritingMergeModeKey = Key('handwriting-merge-mode');

/// 多选模式底部操作栏里的「合并整理（N 张）」。
const Key handwritingMergeRunKey = Key('handwriting-merge-run');

/// 多选模式下某张照片的勾选 chip（按相对路径定位）。
Key handwritingMergePhotoKey(String relPath) =>
    ValueKey<String>('handwriting-merge-photo-$relPath');

/// 某次多图整理的卡片（按 `sourceRef` 定位；队列里可以同时有多张）。
Key handwritingMergeRunCardKey(String sourceRef) =>
    ValueKey<String>('handwriting-merge-run-card-$sourceRef');

/// 某次多图整理卡片上的「全部确认」。
Key handwritingMergeApplyAllKey(String sourceRef) =>
    ValueKey<String>('handwriting-merge-apply-all-$sourceRef');

/// 某次多图整理卡片上的「忘掉」。
Key handwritingMergeForgetKey(String sourceRef) =>
    ValueKey<String>('handwriting-merge-forget-$sourceRef');

/// 待确认队列页。
///
/// [initialRelPath] 用于"从收题页点某张照片的「整理」"这条入口：进来就选中它。
class HandwritingQueuePage extends ConsumerStatefulWidget {
  const HandwritingQueuePage({super.key, this.initialRelPath});

  final String? initialRelPath;

  @override
  ConsumerState<HandwritingQueuePage> createState() =>
      _HandwritingQueuePageState();
}

class _HandwritingQueuePageState extends ConsumerState<HandwritingQueuePage> {
  String? _selectedRelPath;

  /// 照片多选（合并整理）模式：挑几张照片合成**一次**整理。
  bool _mergeMode = false;

  /// 勾选的照片相对路径，**按勾选顺序**（这个顺序就是交给模型的顺序）。
  final List<String> _mergeSelection = <String>[];

  /// 合并整理正在跑：防重入，按钮转圈。
  bool _mergeRunning = false;

  /// 上一次合并整理失败的原因（成功后清掉）。
  String? _mergeFailureReason;

  @override
  void initState() {
    super.initState();
    _selectedRelPath = widget.initialRelPath;
    // `HandwritingQueueNotifier.build()` 给的是空 state（它不主动读磁盘），
    // 所以"打开这一页就能看到待整理清单"必须由页面自己触发。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      ref.read(handwritingQueueProvider.notifier).refresh();
    });
  }

  PendingHandwritingImage? _selectedImage(
    List<PendingHandwritingImage> images,
  ) {
    if (images.isEmpty) {
      return null;
    }
    final current = _selectedRelPath;
    if (current != null) {
      for (final image in images) {
        if (image.relPath == current) {
          return image;
        }
      }
    }
    return images.first;
  }

  /// 这张照片能不能参与合并整理：已经整理出提案、正在整理、已经属于某次
  /// 多图整理的照片都不选——再合一次只会多花模型调用，还可能把同一页重复入库。
  bool _mergeSelectable(
    HandwritingQueueState queue,
    PendingHandwritingImage image,
  ) =>
      !queue.sets.containsKey(image.relPath) &&
      !queue.analyzing.contains(image.relPath) &&
      !queue.mergedPhotoPaths.contains(image.relPath);

  void _toggleMergeMode() {
    setState(() {
      _mergeMode = !_mergeMode;
      _mergeSelection.clear();
      _mergeFailureReason = null;
    });
  }

  void _toggleMergeSelection(
    HandwritingQueueState queue,
    PendingHandwritingImage image,
  ) {
    if (!_mergeSelectable(queue, image)) {
      return;
    }
    setState(() {
      final index = _mergeSelection.indexOf(image.relPath);
      if (index >= 0) {
        _mergeSelection.removeAt(index);
      } else {
        _mergeSelection.add(image.relPath);
      }
      _mergeFailureReason = null;
    });
  }

  Future<void> _runMerge() async {
    if (_mergeRunning || _mergeSelection.length < 2) {
      return;
    }
    final relPaths = List<String>.of(_mergeSelection);
    setState(() {
      _mergeRunning = true;
      _mergeFailureReason = null;
    });
    try {
      final run = await ref
          .read(handwritingQueueProvider.notifier)
          .analyzeMulti(relPaths);
      if (!mounted) {
        return;
      }
      setState(() {
        _mergeRunning = false;
        if (run.ok) {
          // 合并成功就退出多选：照片条上的「已合并」标记与结果卡片接着显示。
          _mergeMode = false;
          _mergeSelection.clear();
        } else {
          _mergeFailureReason = run.failureReason ?? '';
        }
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _mergeRunning = false;
        _mergeFailureReason = '$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final queue = ref.watch(handwritingQueueProvider);

    // 清单刷新后，选中的照片可能已经被删掉了：回落到的第一张。
    ref.listen(handwritingQueueProvider, (previous, next) {
      final selection = _selectedImage(next.images);
      if (selection?.relPath != _selectedRelPath) {
        setState(() => _selectedRelPath = selection?.relPath);
      }
    });

    final selected = _selectedImage(queue.images);
    final mergedPhotoPaths = queue.mergedPhotoPaths;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.handwritingQueueTitle),
        actions: [
          if (queue.images.isNotEmpty)
            TextButton(
              key: handwritingMergeModeKey,
              onPressed: (queue.batchRunning || _mergeRunning)
                  ? null
                  : _toggleMergeMode,
              child: Text(
                _mergeMode
                    ? l10n.handwritingMergeModeExit
                    : l10n.handwritingMergeModeEnter,
              ),
            ),
        ],
      ),
      bottomNavigationBar: _mergeMode
          ? _MergeActionBar(
              count: _mergeSelection.length,
              running: _mergeRunning,
              failureReason: _mergeFailureReason,
              onMerge: _runMerge,
            )
          : null,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            l10n.handwritingQueueSubtitle,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          if (queue.loading && queue.images.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: LinearProgressIndicator(),
            )
          else if (queue.images.isEmpty)
            _EmptyQueue(onOpenIntake: _openIntake)
          else ...[
            _BatchBar(queue: queue),
            const SizedBox(height: 12),
            _PhotoStrip(
              images: queue.images,
              selectedRelPath: selected?.relPath,
              onSelect: (image) =>
                  setState(() => _selectedRelPath = image.relPath),
              mergeMode: _mergeMode,
              mergeSelection: _mergeSelection,
              mergedPhotoPaths: mergedPhotoPaths,
              isSelectable: (image) => _mergeSelectable(queue, image),
              onToggleMerge: (image) => _toggleMergeSelection(queue, image),
            ),
            for (final run in queue.multiRuns) ...[
              const SizedBox(height: 12),
              _MultiRunCard(run: run, queue: queue),
            ],
            const SizedBox(height: 12),
            if (!_mergeMode && selected != null)
              _SelectedPhotoPanel(image: selected, queue: queue),
          ],
        ],
      ),
    );
  }

  void _openIntake() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (context) => const QuestionIntakePage()),
    );
  }
}

/// 一张照片都没有：空态 + 去收题页（不编造"正在整理"的假象）。
class _EmptyQueue extends StatelessWidget {
  const _EmptyQueue({required this.onOpenIntake});

  final VoidCallback onOpenIntake;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.handwritingQueueEmpty),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonalIcon(
                onPressed: onOpenIntake,
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: Text(l10n.handwritingQueueGoIntake),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 待整理照片清单；普通模式单选，多选（合并整理）模式变成可勾选的清单。
class _PhotoStrip extends StatelessWidget {
  const _PhotoStrip({
    required this.images,
    required this.selectedRelPath,
    required this.onSelect,
    required this.mergeMode,
    required this.mergeSelection,
    required this.mergedPhotoPaths,
    required this.isSelectable,
    required this.onToggleMerge,
  });

  final List<PendingHandwritingImage> images;
  final String? selectedRelPath;
  final ValueChanged<PendingHandwritingImage> onSelect;

  /// 多选（合并整理）模式：chip 变成可勾选的 [FilterChip]。
  final bool mergeMode;

  /// 多选模式下已经勾选的照片相对路径（按勾选顺序）。
  final List<String> mergeSelection;

  /// 已经属于某次多图整理的照片：展示「已合并」标记，并且不可再选。
  final Set<String> mergedPhotoPaths;

  final bool Function(PendingHandwritingImage image) isSelectable;
  final ValueChanged<PendingHandwritingImage> onToggleMerge;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.handwritingQueuePhotosLabel,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final image in images)
                  if (mergeMode)
                    _MergePhotoChip(
                      image: image,
                      selected: mergeSelection.contains(image.relPath),
                      merged: mergedPhotoPaths.contains(image.relPath),
                      selectable: isSelectable(image),
                      onToggle: () => onToggleMerge(image),
                    )
                  else
                    ChoiceChip(
                      label: _PhotoChipLabel(
                        image: image,
                        merged: mergedPhotoPaths.contains(image.relPath),
                      ),
                      selected: image.relPath == selectedRelPath,
                      onSelected: (_) => onSelect(image),
                    ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 多选模式下的一张照片 chip：勾选顺序就是交给模型的顺序。
class _MergePhotoChip extends StatelessWidget {
  const _MergePhotoChip({
    required this.image,
    required this.selected,
    required this.merged,
    required this.selectable,
    required this.onToggle,
  });

  final PendingHandwritingImage image;
  final bool selected;
  final bool merged;
  final bool selectable;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final chip = FilterChip(
      key: handwritingMergePhotoKey(image.relPath),
      label: _PhotoChipLabel(image: image, merged: merged),
      selected: selected,
      onSelected: selectable ? (_) => onToggle() : null,
      avatar: selected ? const Icon(Icons.check, size: 18) : null,
    );
    if (selectable) {
      return chip;
    }
    // 不可选要把原因说清楚：否则用户会以为自己点坏了。
    return Tooltip(message: l10n.handwritingMergeUnselectable, child: chip);
  }
}

/// 照片 chip 的文字：文件名；参与过多图整理的再挂一个「已合并」小标记。
class _PhotoChipLabel extends StatelessWidget {
  const _PhotoChipLabel({required this.image, required this.merged});

  final PendingHandwritingImage image;
  final bool merged;

  @override
  Widget build(BuildContext context) {
    if (!merged) {
      return Text(image.fileName);
    }
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(image.fileName),
        const SizedBox(width: 4),
        Text(
          l10n.handwritingMergedBadge,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// 多选模式的底部操作栏：已选张数、不足两张的提示、合并按钮与失败原因。
class _MergeActionBar extends StatelessWidget {
  const _MergeActionBar({
    required this.count,
    required this.running,
    required this.failureReason,
    required this.onMerge,
  });

  final int count;
  final bool running;
  final String? failureReason;
  final VoidCallback onMerge;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final failure = failureReason;
    final failureText = failure == null || failure.isEmpty
        ? null
        : '${l10n.handwritingMergeRunFailed}：$failure';
    return Material(
      color: scheme.surfaceContainerHighest,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (failureText != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    failureText,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      count < 2
                          ? l10n.handwritingMergeNeedTwo
                          : l10n.handwritingMergeHint,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    key: handwritingMergeRunKey,
                    onPressed: (count >= 2 && !running) ? onMerge : null,
                    icon: running
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.merge_type),
                    label: Text(
                      running
                          ? l10n.handwritingQueueAnalyzing
                          : l10n.handwritingMergeButton(count),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 一次多图/多页整理的结果卡片（只读）：照片缩略图 + 提案 + 全部确认 / 忘掉。
///
/// 单图面板里那套「逐条确认 / 编辑后保存」不进来：多页合并出来的提案要按整组
/// 一起看，逐条确认会让「跨页合并成一条」的语义在界面上重新碎掉。
class _MultiRunCard extends ConsumerStatefulWidget {
  const _MultiRunCard({required this.run, required this.queue});

  final HandwritingMultiRun run;
  final HandwritingQueueState queue;

  @override
  ConsumerState<_MultiRunCard> createState() => _MultiRunCardState();
}

class _MultiRunCardState extends ConsumerState<_MultiRunCard> {
  /// 这一组提案确认前的预检（只读）；加载中或失败时为 null。
  HandwritingIntakePreview? _preview;
  bool _previewLoading = false;

  /// 触发预检的输入签名：sourceRef + 这一组提案的 id 序列。
  String? _previewSignature;

  @override
  void initState() {
    super.initState();
    _reloadPreviewIfNeeded();
  }

  @override
  void didUpdateWidget(covariant _MultiRunCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _reloadPreviewIfNeeded();
  }

  String _signatureOf() {
    final ids =
        widget.run.set.proposals.map((proposal) => proposal.id).join(',');
    return '${widget.run.sourceRef}#$ids';
  }

  /// 这一组提案变了才重算；没变就沿用上一次结果，避免每帧读库。
  void _reloadPreviewIfNeeded() {
    final signature = _signatureOf();
    if (signature == _previewSignature) {
      return;
    }
    _previewSignature = signature;
    _preview = null;
    _previewLoading = widget.run.set.proposals.isNotEmpty;
    if (!_previewLoading) {
      return;
    }
    final future = ref
        .read(handwritingQueueProvider.notifier)
        .previewFor(widget.run.sourceRef);
    future.then(
      (value) {
        if (!mounted || _previewSignature != signature) {
          return;
        }
        setState(() {
          _preview = value;
          _previewLoading = false;
        });
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!mounted || _previewSignature != signature) {
          return;
        }
        debugPrint('多图确认前预检失败（界面按无预检降级）：$error');
        setState(() {
          _preview = null;
          _previewLoading = false;
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final queue = widget.queue;
    final run = widget.run;
    final sourceRef = run.sourceRef;
    final notifier = ref.read(handwritingQueueProvider.notifier);
    final applying = queue.applying.contains(sourceRef);
    final set = run.set;
    final remaining = _hasRemaining(queue, sourceRef, set);
    final previews = _preview;
    final blockedBatch = previews?.hasBlocked ?? false;
    final report =
        queue.lastReport?.sourceRef == sourceRef ? queue.lastReport : null;

    return Card(
      key: handwritingMergeRunCardKey(sourceRef),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.layers_outlined),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.handwritingMergeRunTitle(run.photoRelPaths.length),
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final relPath in run.photoRelPaths)
                  _PhotoThumb(relPath: relPath),
              ],
            ),
            const SizedBox(height: 12),
            if (set.isEmpty)
              Text(l10n.handwritingQueueNothingFound)
            else ...[
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.handwritingQueueProposalsLabel,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  FilledButton.tonalIcon(
                    key: handwritingMergeApplyAllKey(sourceRef),
                    onPressed: (applying || !remaining || blockedBatch)
                        ? null
                        : () => notifier.applyAll(sourceRef),
                    icon: const Icon(Icons.done_all),
                    label: Text(
                      applying
                          ? l10n.handwritingQueueApplying
                          : l10n.handwritingQueueApplyAll,
                    ),
                  ),
                ],
              ),
              if (_previewLoading)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          l10n.handwritingQueuePreviewLoading,
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
              if (previews != null && previews.hasBlocked)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    l10n.handwritingQueuePreviewBlockedSummary(
                      previews.readyCount,
                      previews.needsReviewCount,
                      previews.blockedCount,
                    ),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              for (final proposal in set.proposals)
                _ProposalCard(
                  proposal: proposal,
                  preview: _previewOfProposal(previews, proposal.id),
                  applied: queue.isApplied(sourceRef, proposal.id),
                  applying: applying,
                  outcome: _outcomeOf(report, proposal.id),
                  onApply: null,
                ),
            ],
            if (report != null) ...[
              const SizedBox(height: 12),
              Text(
                l10n.handwritingQueueReportSummary(
                  report.appliedCount,
                  report.failedCount,
                ),
                style: theme.textTheme.labelLarge,
              ),
            ],
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                key: handwritingMergeForgetKey(sourceRef),
                onPressed: applying ? null : () => notifier.forget(sourceRef),
                icon: const Icon(Icons.undo),
                label: Text(l10n.handwritingQueueForget),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 多图卡片里的一张照片缩略图：读不到字节（或字节不是图片）就给占位。
class _PhotoThumb extends ConsumerStatefulWidget {
  const _PhotoThumb({required this.relPath});

  static const double size = 88;

  final String relPath;

  @override
  ConsumerState<_PhotoThumb> createState() => _PhotoThumbState();
}

class _PhotoThumbState extends ConsumerState<_PhotoThumb> {
  late final Future<Uint8List?> _bytesFuture;

  @override
  void initState() {
    super.initState();
    _bytesFuture =
        ref.read(handwritingIntakeStoreProvider).readBytes(widget.relPath);
  }

  Widget _placeholder(ColorScheme scheme) => Container(
        color: scheme.surfaceContainerHighest,
        alignment: Alignment.center,
        child: Icon(
          Icons.image_not_supported_outlined,
          size: 24,
          color: scheme.onSurfaceVariant,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: _PhotoThumb.size,
        height: _PhotoThumb.size,
        child: FutureBuilder<Uint8List?>(
          future: _bytesFuture,
          builder: (context, snapshot) {
            final bytes = snapshot.data;
            if (bytes == null || bytes.isEmpty) {
              return _placeholder(scheme);
            }
            return Image.memory(
              bytes,
              width: _PhotoThumb.size,
              height: _PhotoThumb.size,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (context, error, stackTrace) =>
                  _placeholder(scheme),
            );
          },
        ),
      ),
    );
  }
}

/// 「整理全部」主按钮：进度、停止、结束汇总。
///
/// 运行中禁用它并显示「正在整理 i/N」；批次状态在 notifier 里，页面被遮住或
/// 离开再回来（`refresh()` 不会清批次字段）仍能看到进度与汇总。
class _BatchBar extends ConsumerWidget {
  const _BatchBar({required this.queue});

  final HandwritingQueueState queue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final notifier = ref.read(handwritingQueueProvider.notifier);
    final running = queue.batchRunning;
    final candidates = queue.batchCandidateCount;
    final report = queue.lastBatchReport;
    final progress = queue.batchTotal == 0
        ? null
        : (queue.batchDone / queue.batchTotal).clamp(0.0, 1.0);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    key: handwritingBatchAnalyzeAllKey,
                    onPressed: (!running && candidates > 0)
                        ? () => notifier.analyzeAll()
                        : null,
                    icon: running
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.auto_awesome),
                    label: Text(
                      running
                          ? l10n.handwritingQueueBatchProgress(
                              queue.batchCurrent,
                              queue.batchTotal,
                            )
                          : l10n.handwritingQueueBatchAll(candidates),
                    ),
                  ),
                ),
                if (running) ...[
                  const SizedBox(width: 8),
                  TextButton.icon(
                    key: handwritingBatchStopKey,
                    onPressed: queue.batchStopping ? null : notifier.stopBatch,
                    icon: const Icon(Icons.stop_circle_outlined),
                    label: Text(
                      queue.batchStopping
                          ? l10n.handwritingQueueBatchStopping
                          : l10n.handwritingQueueBatchStop,
                    ),
                  ),
                ],
              ],
            ),
            if (running)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: LinearProgressIndicator(value: progress),
              ),
            if (!running && report != null) ...[
              const SizedBox(height: 8),
              Text(
                l10n.handwritingQueueBatchReport(
                  report.succeeded,
                  report.failed,
                  report.skipped,
                ),
                key: handwritingBatchSummaryKey,
                style: theme.textTheme.labelLarge,
              ),
              if (report.stopped) ...[
                const SizedBox(height: 2),
                Text(
                  l10n.handwritingQueueBatchStopped,
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

/// 选中照片的整理面板：整理按钮、失败面、提案列表、确认与汇总。
class _SelectedPhotoPanel extends ConsumerStatefulWidget {
  const _SelectedPhotoPanel({required this.image, required this.queue});

  final PendingHandwritingImage image;
  final HandwritingQueueState queue;

  @override
  ConsumerState<_SelectedPhotoPanel> createState() =>
      _SelectedPhotoPanelState();
}

class _SelectedPhotoPanelState extends ConsumerState<_SelectedPhotoPanel> {
  /// 这一批提案确认前的预检结果（只读）。加载中或失败时为 null。
  HandwritingIntakePreview? _preview;
  bool _previewLoading = false;

  /// 触发预检的输入签名：照片路径 + 这一批提案的 id 序列。
  String? _previewSignature;

  @override
  void initState() {
    super.initState();
    _reloadPreviewIfNeeded();
  }

  @override
  void didUpdateWidget(covariant _SelectedPhotoPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    _reloadPreviewIfNeeded();
  }

  /// 失败时不拿旧提案出来显示：这次没整理成功，就不该看到上次的结果。
  HandwritingProposalSet? _setOf(HandwritingQueueState queue, String relPath) {
    if (queue.failures[relPath] != null) {
      return null;
    }
    return queue.sets[relPath];
  }

  String _signatureOf(HandwritingQueueState queue, String relPath) {
    final set = _setOf(queue, relPath);
    final ids = set == null
        ? 'none'
        : set.proposals.map((proposal) => proposal.id).join(',');
    return '$relPath#$ids';
  }

  /// 照片/提案变了才重算；没变就沿用上一次结果，避免每帧读库。
  void _reloadPreviewIfNeeded() {
    final relPath = widget.image.relPath;
    final signature = _signatureOf(widget.queue, relPath);
    if (signature == _previewSignature) {
      return;
    }
    _previewSignature = signature;
    _preview = null;
    _previewLoading = _setOf(widget.queue, relPath) != null;
    if (!_previewLoading) {
      return;
    }
    final future =
        ref.read(handwritingQueueProvider.notifier).previewFor(relPath);
    future.then(
      (value) {
        if (!mounted || _previewSignature != signature) {
          return;
        }
        setState(() {
          _preview = value;
          _previewLoading = false;
        });
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!mounted || _previewSignature != signature) {
          return;
        }
        debugPrint('确认前预检失败（界面按无预检降级）：$error');
        setState(() {
          _preview = null;
          _previewLoading = false;
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final queue = widget.queue;
    final image = widget.image;
    final notifier = ref.read(handwritingQueueProvider.notifier);
    final relPath = image.relPath;

    final analyzing = queue.analyzing.contains(relPath);
    final applying = queue.applying.contains(relPath);
    final failure = queue.failures[relPath];
    final set = _setOf(queue, relPath);
    final report =
        queue.lastReport?.sourceRef == relPath ? queue.lastReport : null;
    final remaining = set != null && _hasRemaining(queue, relPath, set);
    final previews = _preview;
    // 预检说这一批里有一条不能确认：整批确认一起禁用。
    final blockedBatch = previews?.hasBlocked ?? false;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.image_outlined),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    image.fileName,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: analyzing ? null : () => notifier.analyze(relPath),
                  icon: analyzing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.auto_fix_high_outlined),
                  label: Text(
                    analyzing
                        ? l10n.handwritingQueueAnalyzing
                        : l10n.handwritingQueueAnalyze,
                  ),
                ),
                if (set != null || failure != null) ...[
                  const SizedBox(width: 12),
                  TextButton.icon(
                    onPressed: applying ? null : () => notifier.forget(relPath),
                    icon: const Icon(Icons.undo),
                    label: Text(l10n.handwritingQueueForget),
                  ),
                ],
              ],
            ),
            if (analyzing)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: LinearProgressIndicator(),
              ),
            if (failure != null) ...[
              const SizedBox(height: 12),
              _FailureCard(reason: failure),
            ],
            if (set != null) ...[
              const SizedBox(height: 12),
              if (set.isEmpty)
                Text(l10n.handwritingQueueNothingFound)
              else ...[
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.handwritingQueueProposalsLabel,
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                    FilledButton.tonalIcon(
                      key: handwritingQueueApplyAllKey,
                      onPressed: (applying || !remaining || blockedBatch)
                          ? null
                          : () => notifier.applyAll(relPath),
                      icon: const Icon(Icons.done_all),
                      label: Text(
                        applying
                            ? l10n.handwritingQueueApplying
                            : l10n.handwritingQueueApplyAll,
                      ),
                    ),
                  ],
                ),
                if (_previewLoading)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      children: [
                        const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            l10n.handwritingQueuePreviewLoading,
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (previews != null && previews.hasBlocked)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      l10n.handwritingQueuePreviewBlockedSummary(
                        previews.readyCount,
                        previews.needsReviewCount,
                        previews.blockedCount,
                      ),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                for (final proposal in set.proposals)
                  _ProposalCard(
                    proposal: proposal,
                    preview: _previewOfProposal(previews, proposal.id),
                    applied: queue.isApplied(relPath, proposal.id),
                    applying: applying,
                    outcome: _outcomeOf(report, proposal.id),
                    onApply: () => notifier.applyProposal(relPath, proposal.id),
                    onEditForIntake:
                        proposal.kind == HandwritingProposalKind.question
                            ? () => unawaited(_editForIntake(
                                  context,
                                  ref,
                                  relPath,
                                  proposal,
                                ))
                            : null,
                  ),
              ],
            ],
            if (report != null) ...[
              const SizedBox(height: 12),
              Text(
                l10n.handwritingQueueReportSummary(
                  report.appliedCount,
                  report.failedCount,
                ),
                style: theme.textTheme.labelLarge,
              ),
            ],
            if (failure == null && set == null && !analyzing) ...[
              const SizedBox(height: 12),
              Text(l10n.handwritingQueueNotAnalyzed),
            ],
          ],
        ),
      ),
    );
  }

  /// 「编辑后保存」：把题目提案的草稿带到收题页校对（应用层只装配，不写库）。
  ///
  /// 返回 null 表示题干是空的：这类提案连草稿都装不出来，卡片上只显示提示，不给
  /// 这个入口。
  Future<void> _editForIntake(
    BuildContext context,
    WidgetRef ref,
    String relPath,
    HandwritingProposal proposal,
  ) async {
    final draft = await ref
        .read(handwritingProposalServiceProvider)
        .questionDraftForIntake(proposal);
    if (draft == null || !context.mounted) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => QuestionIntakePage(
          initialDraft: draft,
          initialRelPath: relPath,
          initialProposalId: proposal.id,
        ),
      ),
    );
  }
}

/// 整理失败的如实显示：原因照抄，不吞掉、不美化。
class _FailureCard extends StatelessWidget {
  const _FailureCard({required this.reason});

  final String reason;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.handwritingQueueFailureTitle,
            style: TextStyle(
              color: scheme.onErrorContainer,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          SelectableText(
            reason,
            style: TextStyle(color: scheme.onErrorContainer),
          ),
        ],
      ),
    );
  }
}

/// 一条待确认产物。
class _ProposalCard extends StatelessWidget {
  const _ProposalCard({
    required this.proposal,
    required this.applied,
    required this.applying,
    required this.outcome,
    required this.onApply,
    this.onEditForIntake,
    this.preview,
  });

  final HandwritingProposal proposal;

  /// 这条提案的确认前预检；未加载/加载失败时为 null（按旧行为显示）。
  final HandwritingProposalPreview? preview;
  final bool applied;
  final bool applying;
  final HandwritingApplyOutcome? outcome;

  /// 逐条确认；多图卡片是整组确认，传 null 时不显示单条按钮。
  final VoidCallback? onApply;

  /// 题目提案的「编辑后保存」入口；其它 kind 为 null（它们确认即入库）。
  final VoidCallback? onEditForIntake;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      margin: const EdgeInsets.only(top: 12),
      color: scheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // 三类产物的中文名来自领域层词表（`HandwritingProposalKind.labelZh`），
                // 与"标签树/知识点/闪存卡"这些既有词汇保持一致，不另立一套文案。
                Chip(
                  label: Text(proposal.kind.labelZh),
                  visualDensity: VisualDensity.compact,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    proposal.titleZh,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            if (preview != null) _ProposalPreviewBlock(preview: preview!),
            if (proposal.kind == HandwritingProposalKind.question)
              _QuestionProposalDetails(
                proposal: proposal,
                applied: applied,
                applying: applying,
                onEditForIntake: onEditForIntake,
              ),
            if (proposal.rationaleZh.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(proposal.rationaleZh),
            ],
            const SizedBox(height: 4),
            Text(
              l10n.handwritingProposalConfidence(
                _confidenceBand(l10n, proposal.confidence),
              ),
              style: theme.textTheme.bodySmall,
            ),
            if (proposal.cards.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                l10n.handwritingProposalCardCount(proposal.cards.length),
                style: theme.textTheme.labelLarge,
              ),
              for (final card in proposal.cards)
                Padding(
                  padding: const EdgeInsets.only(top: 4, left: 8),
                  child: Text('• ${card.question}'),
                ),
            ],
            if (outcome != null) ...[
              const SizedBox(height: 8),
              Text(
                outcome!.ok
                    ? outcome!.detailZh
                    : (outcome!.failureReason ?? ''),
                style: TextStyle(
                  color: outcome!.ok ? scheme.primary : scheme.error,
                ),
              ),
            ],
            const SizedBox(height: 8),
            if (onApply != null)
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  key: handwritingProposalApplyKey(proposal.id),
                  onPressed:
                      (applied || applying || (preview?.isBlocked ?? false))
                          ? null
                          : onApply,
                  icon: Icon(
                    applied ? Icons.check_circle_outline : Icons.check,
                  ),
                  label: Text(
                    applied
                        ? l10n.handwritingProposalApplied
                        : l10n.handwritingProposalApply,
                  ),
                ),
              )
            else if (applied)
              // 多图卡片没有逐条确认：已确认的只留一个只读状态，不再给按钮。
              Align(
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      size: 18,
                      color: scheme.primary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      l10n.handwritingProposalApplied,
                      style: TextStyle(color: scheme.primary),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 一条提案的预检结论：会写到哪里（previewLines），以及要看一眼/不能确认的原因。
///
/// 文案全部来自领域层预检（`previewLines`/`warnings`/`blockers`），这里只按 verdict
/// 上色加图标；ready 不额外提示，加载与判定本身不在这里做。
class _ProposalPreviewBlock extends StatelessWidget {
  const _ProposalPreviewBlock({required this.preview});

  final HandwritingProposalPreview preview;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final needsReview =
        preview.verdict == HandwritingPreviewVerdict.needsReview;
    final blocked = preview.isBlocked;
    final hintColor = blocked
        ? scheme.error
        : needsReview
            ? scheme.tertiary
            : null;
    final hintStyle = theme.textTheme.bodySmall?.copyWith(color: hintColor);
    return Padding(
      key: handwritingProposalPreviewKey(preview.proposalId),
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final line in preview.previewLines)
            Text(line, style: theme.textTheme.bodySmall),
          if (needsReview) ...[
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.visibility_outlined, size: 16, color: hintColor),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    l10n.handwritingQueuePreviewNeedsReview,
                    style: hintStyle?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            for (final warning in preview.warnings)
              Padding(
                padding: const EdgeInsets.only(top: 2, left: 20),
                child: Text('• $warning', style: hintStyle),
              ),
          ],
          if (blocked) ...[
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.block, size: 16, color: hintColor),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    l10n.handwritingQueuePreviewBlocked,
                    style: hintStyle?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            for (final blocker in preview.blockers)
              Padding(
                padding: const EdgeInsets.only(top: 2, left: 20),
                child: Text('• $blocker', style: hintStyle),
              ),
          ],
        ],
      ),
    );
  }
}

bool _hasRemaining(
  HandwritingQueueState queue,
  String relPath,
  HandwritingProposalSet set,
) {
  for (final proposal in set.proposals) {
    if (!queue.isApplied(relPath, proposal.id)) {
      return true;
    }
  }
  return false;
}

/// 从预检结果里挑出某条提案的结论；多图卡片与单图面板共用这一条。
HandwritingProposalPreview? _previewOfProposal(
  HandwritingIntakePreview? previews,
  String proposalId,
) {
  if (previews == null) {
    return null;
  }
  for (final preview in previews.previews) {
    if (preview.proposalId == proposalId) {
      return preview;
    }
  }
  return null;
}

HandwritingApplyOutcome? _outcomeOf(
  HandwritingApplyReport? report,
  String proposalId,
) {
  if (report == null) {
    return null;
  }
  for (final outcome in report.outcomes) {
    if (outcome.proposalId == proposalId) {
      return outcome;
    }
  }
  return null;
}

/// 置信度折成三档：数字给人"精确"的错觉，档位才是模型真正表达的东西。
String _confidenceBand(AppLocalizations l10n, double confidence) {
  if (confidence >= 0.75) {
    return l10n.handwritingProposalConfidenceHigh;
  }
  if (confidence >= 0.5) {
    return l10n.handwritingProposalConfidenceMedium;
  }
  return l10n.handwritingProposalConfidenceLow;
}

/// 解析摘要：卡片上只放一行，先折叠空白再截断；空解析返回空串。
String handwritingProposalSolutionSummary(String? raw, {int maxChars = 80}) {
  final collapsed = (raw ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
  if (collapsed.length <= maxChars) {
    return collapsed;
  }
  return '${collapsed.substring(0, maxChars)}…';
}

/// 题目提案的原文展示：题干、选项、答案、解析摘要，外加「编辑后保存」入口。
///
/// 题目是四类产物里唯一不能"确认即入库"的一种：确认只代表模型读对了，真正建题
/// 要先生成 [QuestionDraft] 带到收题页校对，用户按「入库」才写库。这里显示的是
/// 模型读出来的原文，不做润色；没认出题干时只给提示、不给入口。
class _QuestionProposalDetails extends StatelessWidget {
  const _QuestionProposalDetails({
    required this.proposal,
    required this.applied,
    required this.applying,
    required this.onEditForIntake,
  });

  final HandwritingProposal proposal;
  final bool applied;
  final bool applying;
  final VoidCallback? onEditForIntake;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final stem = (proposal.fields['stem'] ?? '').trim();
    if (stem.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline, size: 18, color: scheme.error),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                l10n.handwritingQuestionMissingStem,
                style: TextStyle(color: scheme.error),
              ),
            ),
          ],
        ),
      );
    }
    final answer = (proposal.fields['answer'] ?? '').trim();
    final solution = handwritingProposalSolutionSummary(
      proposal.fields['solution'],
    );
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText(
            stem,
            key: Key('handwriting-question-stem-${proposal.id}'),
          ),
          if (proposal.options.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              l10n.handwritingQuestionOptions(proposal.options.length),
              style: theme.textTheme.labelLarge,
            ),
            for (final option in proposal.options)
              Padding(
                padding: const EdgeInsets.only(top: 2, left: 8),
                child: Text('${option.label}. ${option.content}'),
              ),
          ],
          const SizedBox(height: 6),
          Text(
            l10n.handwritingQuestionAnswer(
              answer.isEmpty ? l10n.handwritingQuestionEmptyValue : answer,
            ),
          ),
          Text(
            l10n.handwritingQuestionSolution(
              solution.isEmpty ? l10n.handwritingQuestionEmptyValue : solution,
            ),
          ),
          if (onEditForIntake != null)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                key: Key('handwriting-question-edit-${proposal.id}'),
                onPressed: (applied || applying) ? null : onEditForIntake,
                icon: const Icon(Icons.edit_note),
                label: Text(l10n.handwritingQuestionEditForIntake),
              ),
            ),
        ],
      ),
    );
  }
}
