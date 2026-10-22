/// 题库（顶部目的地）。
///
/// 用户反馈（m09439）：题库总览不需要那么多详细信息，呈现必要信息、标签和
/// 题目命名（自己命名或自动生成），图片要大一点。于是这一页：
///
/// * 上面四个按钮 = 往题库里加东西的全部入口；
/// * 一行小字统计 + 学科筛选 chips；
/// * 每行 = 封面图（128×96）+ 题名（没题名时用题干摘要兜底）+ 题号徽章、
///   学科、标签叶子名；行尾 ⋮ 菜单可改名 / 自动命名 / 复制题号。
///
/// 数据走 `questionLibraryOverviewProvider`（一次读全题目 + 题名 + 标签 + 图片
/// 清单，见 `question_library_reader.dart`）；页面只读，写库只发生在命名对话框
/// 与批量自动命名里，写完让 provider 失效。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/repository_providers.dart';
import '../../../domain/services/media/thumbnail_spec.dart';
import '../../../domain/services/questions/question_number.dart';
import '../../../l10n/app_localizations.dart';
import '../../cognitive/presentation/material_intake_page.dart';
import '../application/question_library_provider.dart';
import 'handwriting_queue_page.dart';
import 'question_audit_view.dart';
import 'question_detail_page.dart';
import 'question_intake_page.dart';
import 'question_media_view.dart';
import 'question_paper_page.dart' show QuestionPaperPage, subjectLabelOf;
import 'question_title_dialog.dart';

/// AppBar 上「自动命名缺名的题」按钮。
const Key questionBankAutoNameKey = Key('question-bank-auto-name');

/// 列表行按题 id 生成 key：`question-bank-row-<questionId>`（测试定位用）。
String questionBankRowKeyFor(String questionId) =>
    'question-bank-row-$questionId';

/// 标签路径的叶子名（`文化课/学科/数学` → `数学`），去重保序。
List<String> questionBankTagLeafNames(List<String> tagPaths) {
  final leaves = <String>[];
  for (final path in tagPaths) {
    final parts = path.split('/');
    final leaf = parts.isEmpty ? '' : parts.last.trim();
    if (leaf.isEmpty || leaves.contains(leaf)) {
      continue;
    }
    leaves.add(leaf);
  }
  return leaves;
}

/// 题库总览页。
class QuestionBankPage extends ConsumerStatefulWidget {
  const QuestionBankPage({super.key});

  @override
  ConsumerState<QuestionBankPage> createState() => _QuestionBankPageState();
}

class _QuestionBankPageState extends ConsumerState<QuestionBankPage> {
  /// 空串 = 全部学科。学科键是稳定 snake_case（`CapabilityAction.subjectKeys`），
  /// 筛选比较只用键，显示名走 `subjectLabelOf`。
  String _subjectKey = '';

  /// 批量自动命名进行中：防重入，也让按钮变成进度圈。
  bool _autoNaming = false;

  void _open(Widget page) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (context) => page),
    );
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _refresh() async {
    ref.invalidate(questionLibraryOverviewProvider);
    await ref.read(questionLibraryOverviewProvider.future);
  }

  /// 改名：对话框自己写库并 invalidate，这里只拿题库里其它行的题名做去重参考。
  Future<void> _rename(
    QuestionLibraryEntry entry,
    List<String> existingTitles,
  ) async {
    await showQuestionTitleDialog(
      context,
      questionId: entry.questionId,
      stem: entry.stem,
      currentTitle: entry.title,
      subjectKey: entry.subjectKey,
      questionType: entry.questionType,
      existingTitles: existingTitles,
    );
  }

  /// 单行自动命名：直接按题干生成一个建议题名写库（用户不满意可以再改名）。
  Future<void> _autoNameEntry(
    QuestionLibraryEntry entry,
    List<String> existingTitles,
  ) async {
    final l10n = AppLocalizations.of(context);
    final title = suggestQuestionTitleForEntry(
      entry,
      existingTitles: existingTitles,
    );
    if (title == null) {
      _showSnack(l10n.questionBankAutoNameNothing);
      return;
    }
    try {
      await ref
          .read(questionRepositoryProvider)
          .setQuestionTitle(entry.questionId, title);
      ref.invalidate(questionLibraryOverviewProvider);
      if (!mounted) {
        return;
      }
      _showSnack(l10n.questionTitleAutoNamed(title));
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showSnack(l10n.questionBankAutoNameFailed('$error'));
    }
  }

  /// 批量自动命名：只补没有题名的行，一次事务写库，失败按命中数汇总。
  Future<void> _autoNameMissing() async {
    if (_autoNaming) {
      return;
    }
    final l10n = AppLocalizations.of(context);
    final snapshot = ref.read(questionLibraryOverviewProvider).valueOrNull;
    if (snapshot == null) {
      return;
    }
    final titles = suggestBulkQuestionTitles(snapshot.entries);
    if (titles.isEmpty) {
      _showSnack(l10n.questionBankAutoNameNothing);
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.questionBankAutoNameDialogTitle(titles.length)),
        content: Text(l10n.questionBankAutoNameDialogBody),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.questionBankAutoNameStart),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    setState(() => _autoNaming = true);
    try {
      final changed =
          await ref.read(questionRepositoryProvider).setQuestionTitles(titles);
      ref.invalidate(questionLibraryOverviewProvider);
      await ref.read(questionLibraryOverviewProvider.future);
      if (!mounted) {
        return;
      }
      final failed = titles.length - changed;
      _showSnack(
        failed <= 0
            ? l10n.questionBankAutoNameDone(titles.length)
            : l10n.questionBankAutoNamePartial(changed, failed),
      );
    } catch (error) {
      if (mounted) {
        _showSnack(l10n.questionBankAutoNameFailed('$error'));
      }
    } finally {
      if (mounted) {
        setState(() => _autoNaming = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final overviewAsync = ref.watch(questionLibraryOverviewProvider);
    final snapshot = overviewAsync.valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.navQuestions),
        actions: <Widget>[
          if (snapshot != null && snapshot.untitledCount > 0)
            IconButton(
              key: questionBankAutoNameKey,
              tooltip: l10n.questionBankAutoNameTooltip,
              onPressed: _autoNaming ? null : _autoNameMissing,
              icon: _autoNaming
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_fix_high),
            ),
          IconButton(
            tooltip: l10n.questionBankRefresh,
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(questionLibraryOverviewProvider),
          ),
        ],
      ),
      body: overviewAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              l10n.questionBankFailed('$error'),
              textAlign: TextAlign.center,
            ),
          ),
        ),
        data: _buildBody,
      ),
    );
  }

  Widget _buildBody(QuestionLibrarySnapshot snapshot) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final subjects = snapshot.subjectKeys;
    final shown = _subjectKey.isEmpty
        ? snapshot.entries
        : snapshot.entries
            .where((entry) => entry.subjectKey == _subjectKey)
            .toList();
    final existingTitles = <String>[
      for (final entry in snapshot.entries)
        if (entry.hasTitle) entry.title!.trim(),
    ];

    return RefreshIndicator(
      onRefresh: _refresh,
      child: CustomScrollView(
        slivers: <Widget>[
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _EntryRow(
                    l10n: l10n,
                    onIntake: () => _open(const QuestionIntakePage()),
                    onPaper: () => _open(const QuestionPaperPage()),
                    onHandwriting: () => _open(const HandwritingQueuePage()),
                    onMaterial: () => _open(const MaterialIntakePage()),
                  ),
                  const SizedBox(height: 12),
                  if (snapshot.isEmpty) ...[
                    Text(
                      l10n.questionBankEmpty,
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l10n.questionBankEmptyHint,
                      style: theme.textTheme.bodySmall,
                    ),
                  ] else ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            l10n.questionBankSummary(
                              snapshot.totalCount,
                              subjects.length,
                            ),
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                        if (snapshot.truncated)
                          Text(
                            l10n.questionBankTruncated(snapshot.entries.length),
                            style: theme.textTheme.bodySmall,
                            textAlign: TextAlign.right,
                          ),
                      ],
                    ),
                    if (subjects.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: <Widget>[
                          ChoiceChip(
                            label: Text(l10n.questionBankAllSubjects),
                            selected: _subjectKey.isEmpty,
                            onSelected: (_) => setState(() => _subjectKey = ''),
                          ),
                          for (final key in subjects)
                            ChoiceChip(
                              label: Text(subjectLabelOf(l10n, key)),
                              selected: _subjectKey == key,
                              onSelected: (_) =>
                                  setState(() => _subjectKey = key),
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 8),
                    if (shown.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Text(
                          l10n.questionBankNoMatch,
                          textAlign: TextAlign.center,
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            sliver: SliverList.separated(
              itemCount: shown.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final entry = shown[index];
                return _QuestionRow(
                  entry: entry,
                  onOpen: () => _open(
                    QuestionDetailPage(questionId: entry.questionId),
                  ),
                  onRename: () => _rename(entry, existingTitles),
                  onAutoName: () => _autoNameEntry(entry, existingTitles),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// 四个"往题库里加东西"的入口。放最上面：这一页的主要动作是加题，不是浏览。
class _EntryRow extends StatelessWidget {
  const _EntryRow({
    required this.l10n,
    required this.onIntake,
    required this.onPaper,
    required this.onHandwriting,
    required this.onMaterial,
  });

  final AppLocalizations l10n;
  final VoidCallback onIntake;
  final VoidCallback onPaper;
  final VoidCallback onHandwriting;
  final VoidCallback onMaterial;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        FilledButton.tonalIcon(
          onPressed: onIntake,
          icon: const Icon(Icons.edit_note_outlined),
          label: Text(l10n.questionIntakeTitle),
        ),
        OutlinedButton.icon(
          onPressed: onPaper,
          icon: const Icon(Icons.playlist_add_check),
          label: Text(l10n.questionPaperTitle),
        ),
        OutlinedButton.icon(
          onPressed: onHandwriting,
          icon: const Icon(Icons.auto_fix_high),
          label: Text(l10n.handwritingQueueTitle),
        ),
        OutlinedButton.icon(
          onPressed: onMaterial,
          icon: const Icon(Icons.library_add_outlined),
          label: Text(l10n.materialIntakeTitle),
        ),
      ],
    );
  }
}

/// 行尾 ⋮ 菜单的三项动作。
enum _QuestionRowAction { rename, autoName, copySerial }

/// 一道题：封面大图 + 题名/题干摘要 + 题号/学科/标签 + 体检徽章 + ⋮ 菜单。
///
/// 不套 Card：整行铺在页面背景上，行间只用一条细分隔线（用户反馈「很多文字
/// 不需要放在一个卡片底座上」）。点整行进详情页。
class _QuestionRow extends ConsumerWidget {
  const _QuestionRow({
    required this.entry,
    required this.onOpen,
    required this.onRename,
    required this.onAutoName,
  });

  final QuestionLibraryEntry entry;
  final VoidCallback onOpen;
  final VoidCallback onRename;
  final VoidCallback onAutoName;

  void _copySerial(BuildContext context, AppLocalizations l10n) {
    final serialNo = entry.serialNo;
    if (serialNo == null) {
      return;
    }
    final label = formatQuestionSerial(serialNo);
    unawaited(Clipboard.setData(ClipboardData(text: label)));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(l10n.questionSerialCopied(label))));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cover = entry.coverImage;
    final title = (entry.title ?? '').trim();
    final leaves = questionBankTagLeafNames(entry.tagPaths);
    final preview = entry.stemPreview.isEmpty
        ? l10n.questionBankUntitled
        : entry.stemPreview;

    return InkWell(
      key: ValueKey(questionBankRowKeyFor(entry.questionId)),
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (cover != null) ...[
              _QuestionCover(image: cover),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title.isEmpty ? preview : title,
                    maxLines: title.isEmpty ? 1 : 2,
                    overflow: TextOverflow.ellipsis,
                    style: title.isEmpty
                        ? theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          )
                        : theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: <Widget>[
                      QuestionSerialBadge(
                        serialNo: entry.serialNo,
                        copyable: false,
                        dense: true,
                      ),
                      Text(
                        subjectLabelOf(l10n, entry.subjectKey),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      for (final leaf in leaves.take(3)) _TagPill(label: leaf),
                      if (leaves.length > 3)
                        _TagPill(label: '+${leaves.length - 3}'),
                    ],
                  ),
                ],
              ),
            ),
            QuestionAuditBadge(questionId: entry.questionId),
            PopupMenuButton<_QuestionRowAction>(
              key: ValueKey(questionBankRowMenuKeyFor(entry.questionId)),
              tooltip: l10n.questionBankRowMenuTooltip,
              onSelected: (action) {
                switch (action) {
                  case _QuestionRowAction.rename:
                    onRename();
                  case _QuestionRowAction.autoName:
                    onAutoName();
                  case _QuestionRowAction.copySerial:
                    _copySerial(context, l10n);
                }
              },
              itemBuilder: (context) => <PopupMenuEntry<_QuestionRowAction>>[
                PopupMenuItem<_QuestionRowAction>(
                  value: _QuestionRowAction.rename,
                  child: Text(l10n.questionTitleRename),
                ),
                PopupMenuItem<_QuestionRowAction>(
                  value: _QuestionRowAction.autoName,
                  child: Text(l10n.questionBankAutoNameMenu),
                ),
                PopupMenuItem<_QuestionRowAction>(
                  value: _QuestionRowAction.copySerial,
                  enabled: entry.serialNo != null,
                  child: Text(l10n.questionBankCopySerial),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 行首封面图：128×96 圆角 12；字节还没读出来时给同尺寸占位，不跳行。
class _QuestionCover extends ConsumerWidget {
  const _QuestionCover({required this.image});

  final QuestionLibraryImage image;

  static const int width = 128;
  static const int height = 96;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final bytes =
        ref.watch(questionImageBytesProvider(image.relPath)).valueOrNull;
    final decode = thumbnailDecodeSpec(
      logicalWidth: width,
      logicalHeight: height,
      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
    );

    final Widget placeholder = ColoredBox(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Icon(
        Icons.image_outlined,
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: width.toDouble(),
        height: height.toDouble(),
        child: bytes == null
            ? placeholder
            : Image.memory(
                bytes,
                width: width.toDouble(),
                height: height.toDouble(),
                fit: BoxFit.cover,
                gaplessPlayback: true,
                cacheWidth: decode.isEmpty ? null : decode.cacheWidth,
                cacheHeight: decode.isEmpty ? null : decode.cacheHeight,
                errorBuilder: (context, error, stackTrace) => placeholder,
              ),
      ),
    );
  }
}

/// 行内小标签 chip（标签叶子名 / 「+N」）。
class _TagPill extends StatelessWidget {
  const _TagPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
