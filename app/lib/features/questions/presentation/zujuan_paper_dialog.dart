/// 收题页「整卷对照」对话框：粘贴组卷网试卷页，对照本地题库。
///
/// 分工：
///  * 试卷页 → 题号清单归域层 `parseZujuanPaperText`（纯文本、永不抛）；
///  * 题号清单 ↔ 题库归应用层 `loadZujuanPaperProgress`（只读，空抽取不查库）；
///  * 本文件只做界面：预览已收录 / 缺题、给出缺题链接、复制。
///
/// 不联网、不抓页面：组卷网有反爬且答案要登录，链接复制到浏览器由用户自己打开。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/repository_providers.dart';
import '../../../domain/services/zujuan/zujuan_link.dart'
    show zujuanQuestionDetailUrl;
import '../../../domain/services/zujuan/zujuan_paper_extract.dart';
import '../../../l10n/app_localizations.dart';
import '../application/zujuan_paper_progress.dart';

/// 收题页表单里的「整卷对照」入口按钮。
const Key zujuanPaperOpenButtonKey = Key('zujuan-paper-open');

/// 对话框根（测试用来确认打开 / 关闭）。
const Key zujuanPaperDialogKey = Key('zujuan-paper-dialog');
const Key zujuanPaperInputKey = Key('zujuan-paper-input');
const Key zujuanPaperParseKey = Key('zujuan-paper-parse');
const Key zujuanPaperCopyKey = Key('zujuan-paper-copy');
const Key zujuanPaperEmptyKey = Key('zujuan-paper-empty');

/// 某道缺题在界面上能不能给链接。
///
/// 与 `loadZujuanPaperProgress` 生成 missingLinks 用的是同一个 helper 和同一个
/// bankId（整卷页的），所以标着「有链接」的行一定在复制出的链接清单里。
bool zujuanPaperHasQuestionLink(
  ZujuanPaperProgress progress,
  String questionId,
) {
  return zujuanQuestionDetailUrl(
        bankId: progress.extract.bankId,
        questionId: questionId,
      ) !=
      null;
}

/// 打开「整卷对照」对话框；结果全部在对话框里展示，关闭即结束。
Future<void> showZujuanPaperDialog(
  BuildContext context, {
  required AppLocalizations l10n,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => _ZujuanPaperDialog(l10n: l10n),
  );
}

class _ZujuanPaperDialog extends ConsumerStatefulWidget {
  const _ZujuanPaperDialog({required this.l10n});

  final AppLocalizations l10n;

  @override
  ConsumerState<_ZujuanPaperDialog> createState() => _ZujuanPaperDialogState();
}

class _ZujuanPaperDialogState extends ConsumerState<_ZujuanPaperDialog> {
  final _inputController = TextEditingController();
  ZujuanPaperProgress? _progress;
  bool _parsed = false;
  bool _parsing = false;

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  Future<void> _parse() async {
    if (_parsing) return;
    final extract = parseZujuanPaperText(_inputController.text);
    if (extract.questionIds.isEmpty) {
      // 没认出题号时不查库：界面要能区分「没认出」与「认出了但全缺」。
      setState(() {
        _progress = ZujuanPaperProgress(extract: extract);
        _parsed = true;
      });
      return;
    }
    setState(() => _parsing = true);
    ZujuanPaperProgress progress;
    try {
      progress = await loadZujuanPaperProgress(
        repository: ref.read(questionRepositoryProvider),
        extract: extract,
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _parsing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$error')),
      );
      return;
    }
    if (!mounted) return;
    setState(() {
      _progress = progress;
      _parsed = true;
      _parsing = false;
    });
  }

  Future<void> _copyMissingLinks() async {
    final progress = _progress;
    if (progress == null || !progress.hasMissingLinks) return;
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: progress.missingLinksText));
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(content: Text(widget.l10n.zujuanPaperCopied)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    final theme = Theme.of(context);
    final progress = _progress;
    final results =
        (_parsed && progress != null && progress.extract.questionIds.isNotEmpty)
            ? progress
            : null;
    return Dialog(
      key: zujuanPaperDialogKey,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 560,
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.zujuanPaperTitle,
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: l10n.zujuanPaperClose,
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              Text(l10n.zujuanPaperIntro, style: theme.textTheme.bodySmall),
              const SizedBox(height: 12),
              TextField(
                key: zujuanPaperInputKey,
                controller: _inputController,
                minLines: 4,
                maxLines: 8,
                decoration: InputDecoration(
                  labelText: l10n.zujuanPaperInputLabel,
                  hintText: l10n.zujuanPaperInputHint,
                  alignLabelWithHint: true,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.tonalIcon(
                      key: zujuanPaperParseKey,
                      onPressed: _parsing ? null : _parse,
                      icon: const Icon(Icons.manage_search),
                      label: Text(l10n.zujuanPaperParse),
                    ),
                  ),
                ],
              ),
              if (_parsed) ...[
                const SizedBox(height: 12),
                if (results == null)
                  Card(
                    key: zujuanPaperEmptyKey,
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(l10n.zujuanPaperParseEmpty),
                    ),
                  )
                else ...[
                  Flexible(
                    fit: FlexFit.loose,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 360),
                      child: SingleChildScrollView(
                        child: _buildResults(context, l10n, results),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      key: zujuanPaperCopyKey,
                      onPressed:
                          results.hasMissingLinks ? _copyMissingLinks : null,
                      icon: const Icon(Icons.content_copy),
                      label: Text(l10n.zujuanPaperCopyMissing),
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResults(
    BuildContext context,
    AppLocalizations l10n,
    ZujuanPaperProgress progress,
  ) {
    final theme = Theme.of(context);
    final title = progress.title?.trim() ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title.isEmpty ? l10n.zujuanPaperUntitled : title,
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        Text(
          l10n.zujuanPaperHeader(
            progress.questionCount,
            progress.matchedCount,
            progress.missingCount,
          ),
          style: theme.textTheme.bodySmall,
        ),
        for (final warning in progress.warnings)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(warning, style: theme.textTheme.bodySmall),
          ),
        if (progress.matched.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            l10n.zujuanPaperMatchedSection,
            style: theme.textTheme.titleSmall,
          ),
          for (final item in progress.matched)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                l10n.zujuanPaperMatchedItem(
                  item.serialLabel,
                  item.stemPreview,
                ),
                style: theme.textTheme.bodySmall,
              ),
            ),
        ],
        if (progress.missingQuestionIds.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            l10n.zujuanPaperMissingSection,
            style: theme.textTheme.titleSmall,
          ),
          for (final id in progress.missingQuestionIds)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                zujuanPaperHasQuestionLink(progress, id)
                    ? l10n.zujuanPaperMissingWithLink(id)
                    : l10n.zujuanPaperMissingNoLink(id),
                style: theme.textTheme.bodySmall,
              ),
            ),
          if (!progress.hasMissingLinks)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                l10n.zujuanPaperNoBank,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
        ],
      ],
    );
  }
}
