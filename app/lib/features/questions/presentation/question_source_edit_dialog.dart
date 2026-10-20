/// 改「原题链接」的对话框：粘贴链接、组卷网路径或题号 → 域层解析 → 写回三列。
///
/// 分工：
///  * 解析是纯逻辑（domain/services/zujuan/zujuan_source_input.dart）：认不出返回
///    null，UI 据此区分「没填」和「填错了」，不猜；
///  * 写库只调用 QuestionRepository.updateSourceLinks（null = 该列不动，空串 =
///    清空）；保存成功后 invalidate 详情 provider，页面自己去重读；
///  * 本文件不联网、不打开浏览器、不引入 url_launcher。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/database.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../domain/services/zujuan/zujuan_source_input.dart';
import '../../../l10n/app_localizations.dart';
import 'question_detail_providers.dart';

/// 详情页「编辑 / 添加原题链接」入口按钮的 key（页面与测试共用）。
const Key questionSourceEditButtonKey = Key('question-source-edit');

/// 对话框根、输入框、预览、保存、清空与二次确认按钮的 key（测试定位用）。
const Key questionSourceEditDialogKey = Key('question-source-edit-dialog');
const Key questionSourceEditInputKey = Key('question-source-edit-input');
const Key questionSourceEditSaveKey = Key('question-source-edit-save');
const Key questionSourceEditClearKey = Key('question-source-edit-clear');
const Key questionSourceEditClearConfirmKey =
    Key('question-source-edit-clear-confirm');
const Key questionSourceEditCancelKey = Key('question-source-edit-cancel');
const Key questionSourceEditEmptyHintKey = Key('question-source-edit-empty');

/// 打开「改原题链接」对话框。
///
/// 页面只负责把当前这道题的快照传进来；保存、清空、刷新都由对话框与
/// [QuestionRepository.updateSourceLinks] + invalidate 完成。
Future<void> showQuestionSourceEditDialog(
  BuildContext context, {
  required Question question,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => QuestionSourceEditDialog(question: question),
  );
}

/// 改原题链接：输入 → 预览解析结果 → 保存 / 清空（清空要二次确认）。
class QuestionSourceEditDialog extends ConsumerStatefulWidget {
  const QuestionSourceEditDialog({super.key, required this.question});

  final Question question;

  @override
  ConsumerState<QuestionSourceEditDialog> createState() =>
      _QuestionSourceEditDialogState();
}

class _QuestionSourceEditDialogState
    extends ConsumerState<QuestionSourceEditDialog> {
  late final TextEditingController _controller;
  bool _saving = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.question.sourceUrl?.trim() ?? '',
    );
    _controller.addListener(_onInputChanged);
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onInputChanged)
      ..dispose();
    super.dispose();
  }

  void _onInputChanged() {
    if (!mounted) return;
    // 输入一变，上一轮的失败提示就作废：用户改的是输入，不是重试。
    setState(() => _errorText = null);
  }

  /// 当前输入的解析结果；`null` = 认不出（保存按钮禁用）。
  ZujuanSourceInput? get _parsed => parseZujuanSourceInput(_controller.text);

  bool get _canSave {
    final parsed = _parsed;
    return !_saving && parsed != null && !parsed.isEmpty;
  }

  Future<void> _save() async {
    final parsed = _parsed;
    if (_saving || parsed == null || parsed.isEmpty) return;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _saving = true;
      _errorText = null;
    });
    try {
      // null = 这一列不动：别的站 URL 只写 source_url，不冲掉已有的组卷网 id。
      final updated =
          await ref.read(questionRepositoryProvider).updateSourceLinks(
                widget.question.id,
                sourceUrl: parsed.sourceUrl,
                zujuanQuestionId: parsed.zujuanQuestionId,
                zujuanBankId: parsed.zujuanBankId,
              );
      ref.invalidate(questionDetailProvider(widget.question.id));
      if (!mounted) return;
      if (!updated) {
        // 行不存在（题刚被删）：不假装保存成功，留在对话框里说清楚。
        setState(() {
          _saving = false;
          _errorText = l10n.questionSourceEditFailed(
            l10n.questionDetailQuestionMissing,
          );
        });
        return;
      }
      Navigator.of(context).pop();
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.questionSourceEditSaved)),
      );
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _errorText = l10n.questionSourceEditFailed('$error');
      });
    }
  }

  Future<void> _clear() async {
    if (_saving) return;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.questionSourceEditClear),
        content: Text(l10n.questionSourceEditClearConfirm),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.questionSourceCancel),
          ),
          FilledButton(
            key: questionSourceEditClearConfirmKey,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.questionSourceEditClear),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _saving = true;
      _errorText = null;
    });
    try {
      await ref.read(questionRepositoryProvider).updateSourceLinks(
            widget.question.id,
            sourceUrl: '',
            zujuanQuestionId: '',
            zujuanBankId: '',
          );
      ref.invalidate(questionDetailProvider(widget.question.id));
      if (!mounted) return;
      Navigator.of(context).pop();
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.questionSourceEditCleared)),
      );
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _errorText = l10n.questionSourceEditFailed('$error');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final parsed = _parsed;
    final empty = parsed == null || parsed.isEmpty;
    return Dialog(
      key: questionSourceEditDialogKey,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                l10n.questionSourceEditTitle,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              TextField(
                key: questionSourceEditInputKey,
                controller: _controller,
                autofocus: true,
                minLines: 1,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: l10n.questionSourceEditInputLabel,
                  hintText: l10n.questionSourceEditInputHint,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              _PreviewRow(
                label: l10n.questionSourceEditPreviewUrl,
                value: parsed?.sourceUrl ?? l10n.questionSourceEditPreviewNoUrl,
              ),
              _PreviewRow(
                label: l10n.questionSourceEditPreviewQuestionId,
                value: parsed?.zujuanQuestionId ?? _previewEmptyValue,
              ),
              _PreviewRow(
                label: l10n.questionSourceEditPreviewBankId,
                value: parsed?.zujuanBankId ?? _previewEmptyValue,
              ),
              if (empty)
                Padding(
                  key: questionSourceEditEmptyHintKey,
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    l10n.questionSourceEditEmptyHint,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.error),
                  ),
                ),
              if (_errorText != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _errorText!,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.error),
                  ),
                ),
              const SizedBox(height: 16),
              Row(
                children: <Widget>[
                  TextButton(
                    key: questionSourceEditClearKey,
                    onPressed: _saving ? null : _clear,
                    child: Text(l10n.questionSourceEditClear),
                  ),
                  const Spacer(),
                  TextButton(
                    key: questionSourceEditCancelKey,
                    onPressed:
                        _saving ? null : () => Navigator.of(context).pop(),
                    child: Text(l10n.questionSourceCancel),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    key: questionSourceEditSaveKey,
                    onPressed: _canSave ? _save : null,
                    child: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(l10n.questionSourceEditSave),
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

/// 预览里「这一列没有值」的占位（例如别站 URL 的两个组卷网 id）。
const String _previewEmptyValue = '—';

/// 预览的一行：标签 + 解析出的值（值不 selectable：这里是确认，不是复制入口）。
class _PreviewRow extends StatelessWidget {
  const _PreviewRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 96,
            child: Text(label, style: theme.textTheme.bodySmall),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(value, style: theme.textTheme.bodySmall)),
        ],
      ),
    );
  }
}
