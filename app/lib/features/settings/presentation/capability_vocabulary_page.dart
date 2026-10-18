/// 能力动作词表编辑页（docs/REASONING_LAYER_DESIGN.md §4 的用户侧入口）。
///
/// 分工：编辑规则、dirty 判定与保存语义都在 application 层
/// （capability_vocabulary_editor_provider.dart），本文件只做展示与输入：
/// * 内置动作只读（key 已经写进历史数据，改它要改代码发版）；
/// * 自定义动作可新增 / 编辑 / 删除 / 上移下移；
/// * 粘贴 JSON 导入（customActions 对象或条目数组）；
/// * 保存 / 放弃（只有 dirty 才可点）、issues 展示、空态与加载/错误态；
/// * 退出未保存提醒（PopScope）。
///
/// 界面只调 application 层的方法，不自己校验、不自己写库：这样「表单里为什么
/// 不行」与「词表合并时为什么拒绝」永远只有一套规则。
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/services/reasoning/capability_action.dart';
import '../../../domain/services/reasoning/capability_action_overlay.dart';
import '../../../l10n/app_localizations.dart';
import '../../questions/application/capability_vocabulary_editor_provider.dart';

/// 「新增动作」按钮。
const Key capabilityVocabularyAddButtonKey = Key('capability-vocabulary-add');

/// 底部「放弃修改」按钮。
const Key capabilityVocabularyRevertButtonKey =
    Key('capability-vocabulary-revert');

/// 底部「保存」按钮。
const Key capabilityVocabularySaveButtonKey = Key('capability-vocabulary-save');

/// 「粘贴 JSON 导入」按钮。
const Key capabilityVocabularyImportButtonKey =
    Key('capability-vocabulary-import');

/// 导入对话框里的多行输入框。
const Key capabilityVocabularyImportFieldKey =
    Key('capability-vocabulary-import-field');

/// 导入对话框的确认按钮。
const Key capabilityVocabularyImportConfirmKey =
    Key('capability-vocabulary-import-confirm');

/// 新增/编辑对话框的保存按钮。
const Key capabilityVocabularyDialogSaveKey =
    Key('capability-vocabulary-dialog-save');

/// 新增/编辑对话框的 key 输入框。
const Key capabilityVocabularyKeyFieldKey =
    Key('capability-vocabulary-key-field');

/// 新增/编辑对话框的中文名输入框。
const Key capabilityVocabularyLabelZhFieldKey =
    Key('capability-vocabulary-label-zh-field');

/// 新增/编辑对话框的英文名输入框。
const Key capabilityVocabularyLabelEnFieldKey =
    Key('capability-vocabulary-label-en-field');

/// 新增/编辑对话框的一句话说明输入框。
const Key capabilityVocabularyDescriptionFieldKey =
    Key('capability-vocabulary-description-field');

/// 内置动作分组的标题（ExpansionTile）。
const Key capabilityVocabularyBuiltInTileKey =
    Key('capability-vocabulary-builtin-tile');

/// 一条自定义动作的整行（用来断言顺序与存在性）。
Key capabilityVocabularyCustomRowKey(String key) =>
    ValueKey<String>('capability-vocabulary-row-$key');

/// 一条自定义动作的「编辑」按钮。
Key capabilityVocabularyEditKey(String key) =>
    ValueKey<String>('capability-vocabulary-edit-$key');

/// 一条自定义动作的「删除」按钮。
Key capabilityVocabularyDeleteKey(String key) =>
    ValueKey<String>('capability-vocabulary-delete-$key');

/// 一条自定义动作的「上移」按钮。
Key capabilityVocabularyMoveUpKey(String key) =>
    ValueKey<String>('capability-vocabulary-up-$key');

/// 一条自定义动作的「下移」按钮。
Key capabilityVocabularyMoveDownKey(String key) =>
    ValueKey<String>('capability-vocabulary-down-$key');

/// 能力动作词表编辑页。
class CapabilityVocabularyPage extends ConsumerStatefulWidget {
  const CapabilityVocabularyPage({super.key});

  @override
  ConsumerState<CapabilityVocabularyPage> createState() =>
      _CapabilityVocabularyPageState();
}

class _CapabilityVocabularyPageState
    extends ConsumerState<CapabilityVocabularyPage> {
  /// 已经确认「放弃并离开」，正在真正弹出路由。
  bool _popConfirmed = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final editor = ref.watch(capabilityVocabularyEditorProvider);
    final state = editor.valueOrNull;
    final isDirty = state?.isDirty ?? false;

    return PopScope(
      canPop: !isDirty || _popConfirmed,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          return;
        }
        _handlePopInvoked(l10n);
      },
      child: Scaffold(
        appBar: AppBar(title: Text(l10n.capabilityVocabularyTitle)),
        body: editor.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stackTrace) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                l10n.capabilityVocabularyLoadFailed('$error'),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          data: (state) => _buildBody(context, l10n, state),
        ),
        bottomNavigationBar:
            state == null ? null : _buildBottomBar(context, l10n, state),
      ),
    );
  }

  /// 退出前确认：有未保存改动时先弹对话框，确认放弃才真正弹出路由。
  Future<void> _handlePopInvoked(AppLocalizations l10n) async {
    final leave = await _confirmLeave(l10n);
    if (leave != true || !mounted) {
      return;
    }
    setState(() => _popConfirmed = true);
    Navigator.of(context).pop();
  }

  Widget _buildBody(
    BuildContext context,
    AppLocalizations l10n,
    CapabilityVocabularyEditorState state,
  ) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        Text(
          l10n.capabilityVocabularyHint,
          style: theme.textTheme.bodyMedium,
        ),
        if (state.hasIssues) ...[
          const SizedBox(height: 12),
          _IssuesCard(
            l10n: l10n,
            issues: state.issues,
            onDismiss: () => ref
                .read(capabilityVocabularyEditorProvider.notifier)
                .clearIssues(),
          ),
        ],
        const SizedBox(height: 16),
        _BuiltInActionsCard(l10n: l10n),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.capabilityVocabularyCustomSection(state.customActionCount),
                style: theme.textTheme.titleMedium,
              ),
            ),
            FilledButton.tonalIcon(
              key: capabilityVocabularyAddButtonKey,
              onPressed: _addAction,
              icon: const Icon(Icons.add),
              label: Text(l10n.capabilityVocabularyAdd),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (state.overlay.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              l10n.capabilityVocabularyCustomEmpty,
              style: theme.textTheme.bodySmall,
            ),
          )
        else
          for (var index = 0;
              index < state.overlay.customActions.length;
              index++)
            _buildCustomActionCard(
              context,
              l10n,
              state.overlay.customActions[index],
              index,
              state.overlay.customActions.length,
            ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            key: capabilityVocabularyImportButtonKey,
            onPressed: _showImportDialog,
            icon: const Icon(Icons.content_paste_outlined),
            label: Text(l10n.capabilityVocabularyImport),
          ),
        ),
      ],
    );
  }

  Widget _buildCustomActionCard(
    BuildContext context,
    AppLocalizations l10n,
    CustomCapabilityAction action,
    int index,
    int total,
  ) {
    final theme = Theme.of(context);
    final editor = ref.read(capabilityVocabularyEditorProvider.notifier);
    final subjectLabels = [
      for (final hint in action.subjectHints)
        CapabilityAction.subjectLabelsZh[hint] ?? hint,
    ];
    return Card(
      key: capabilityVocabularyCustomRowKey(action.key),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    action.labelZh,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                IconButton(
                  key: capabilityVocabularyEditKey(action.key),
                  tooltip: l10n.commonEdit,
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  onPressed: () => _editAction(action),
                ),
                IconButton(
                  key: capabilityVocabularyDeleteKey(action.key),
                  tooltip: l10n.commonDelete,
                  icon: const Icon(Icons.delete_outline, size: 20),
                  onPressed: () => editor.remove(action.key),
                ),
              ],
            ),
            Text(action.key, style: theme.textTheme.bodySmall),
            if (action.descriptionZh.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(action.descriptionZh, style: theme.textTheme.bodySmall),
            ],
            if (subjectLabels.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                '${l10n.capabilityVocabularySubjectHints}：'
                '${subjectLabels.join(' / ')}',
                style: theme.textTheme.bodySmall,
              ),
            ],
            Row(
              children: [
                IconButton(
                  key: capabilityVocabularyMoveUpKey(action.key),
                  tooltip: l10n.capabilityVocabularyMoveUp,
                  icon: const Icon(Icons.arrow_upward, size: 18),
                  onPressed: index == 0
                      ? null
                      : () => editor.reorder(action.key, index - 1),
                ),
                IconButton(
                  key: capabilityVocabularyMoveDownKey(action.key),
                  tooltip: l10n.capabilityVocabularyMoveDown,
                  icon: const Icon(Icons.arrow_downward, size: 18),
                  onPressed: index == total - 1
                      ? null
                      : () => editor.reorder(action.key, index + 1),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar(
    BuildContext context,
    AppLocalizations l10n,
    CapabilityVocabularyEditorState state,
  ) {
    final theme = Theme.of(context);
    final canAct = state.isDirty && !state.isSaving;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (state.isDirty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Icon(
                      Icons.edit_note,
                      size: 16,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      l10n.capabilityVocabularyDirty,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: capabilityVocabularyRevertButtonKey,
                    onPressed: canAct
                        ? () => ref
                            .read(capabilityVocabularyEditorProvider.notifier)
                            .revert()
                        : null,
                    child: Text(l10n.capabilityVocabularyRevert),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    key: capabilityVocabularySaveButtonKey,
                    onPressed: canAct ? _save : null,
                    child: state.isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(l10n.commonSave),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(capabilityVocabularyEditorProvider.notifier).save();
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.capabilityVocabularySaved)),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.capabilityVocabularySaveFailed('$error')),
        ),
      );
    }
  }

  Future<void> _addAction() async {
    final l10n = AppLocalizations.of(context);
    final draft = await showDialog<CustomCapabilityAction>(
      context: context,
      builder: (context) => _CapabilityActionDialog(l10n: l10n),
    );
    if (draft == null || !mounted) {
      return;
    }
    ref.read(capabilityVocabularyEditorProvider.notifier).add(draft);
  }

  Future<void> _editAction(CustomCapabilityAction existing) async {
    final l10n = AppLocalizations.of(context);
    final draft = await showDialog<CustomCapabilityAction>(
      context: context,
      builder: (context) =>
          _CapabilityActionDialog(l10n: l10n, existing: existing),
    );
    if (draft == null || !mounted) {
      return;
    }
    ref.read(capabilityVocabularyEditorProvider.notifier).updateAction(
          existing.key,
          labelZh: draft.labelZh,
          labelEn: draft.labelEn,
          descriptionZh: draft.descriptionZh,
          subjectHints: draft.subjectHints,
        );
  }

  Future<void> _showImportDialog() async {
    final l10n = AppLocalizations.of(context);
    final raw = await showDialog<String>(
      context: context,
      builder: (_) => _ImportJsonDialog(l10n: l10n),
    );
    if (raw == null || raw.isEmpty || !mounted) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException catch (error) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            l10n.capabilityVocabularyImportInvalidJson(error.message),
          ),
        ),
      );
      return;
    }
    final editor = ref.read(capabilityVocabularyEditorProvider.notifier);
    final before = ref
            .read(capabilityVocabularyEditorProvider)
            .valueOrNull
            ?.customActionCount ??
        0;
    editor.importJson(decoded);
    if (!mounted) {
      return;
    }
    final after = ref
            .read(capabilityVocabularyEditorProvider)
            .valueOrNull
            ?.customActionCount ??
        0;
    final accepted = after - before;
    if (accepted > 0) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.capabilityVocabularyImportDone(accepted))),
      );
    }
  }

  Future<bool?> _confirmLeave(AppLocalizations l10n) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.capabilityVocabularyLeaveTitle),
        content: Text(l10n.capabilityVocabularyLeaveBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.capabilityVocabularyLeaveStay),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.capabilityVocabularyLeaveDiscard),
          ),
        ],
      ),
    );
  }
}

/// 内置动作的只读分组：默认收起，点开才列出（词表再长也不该把页面撑爆）。
class _BuiltInActionsCard extends StatelessWidget {
  const _BuiltInActionsCard({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const catalog = CapabilityAction.catalog;
    return Card(
      child: ExpansionTile(
        key: capabilityVocabularyBuiltInTileKey,
        title: Text(l10n.capabilityVocabularyBuiltInSection(catalog.length)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            l10n.capabilityVocabularyBuiltInNote,
            style: theme.textTheme.bodySmall,
          ),
        ),
        children: [
          for (final action in catalog)
            ListTile(
              dense: true,
              title: Text(action.labelZh),
              subtitle: Text(action.key),
            ),
        ],
      ),
    );
  }
}

/// 最近一次操作被拒绝的条目：直接显示 domain 层给出的原因。
class _IssuesCard extends StatelessWidget {
  const _IssuesCard({
    required this.l10n,
    required this.issues,
    required this.onDismiss,
  });

  final AppLocalizations l10n;
  final List<CapabilityActionOverlayIssue> issues;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.capabilityVocabularyIssuesTitle(issues.length),
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                IconButton(
                  tooltip: l10n.capabilityVocabularyIssueDismiss,
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: onDismiss,
                ),
              ],
            ),
            for (final issue in issues)
              Padding(
                padding: const EdgeInsets.only(right: 8, bottom: 4),
                child: Text(
                  '• ${issue.message}',
                  style: theme.textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 新增 / 编辑一条自定义动作的对话框。
///
/// 表单里先用 domain 层同一个 validateCustomCapabilityAction 拦一次：能不关
/// 对话框就告诉用户「key 为什么不行」；重复 key 与总量上限只有编辑层知道，
/// 因此关掉对话框后由页面顶部的 issues 卡片说明。
/// 粘贴 JSON 的输入对话框。
///
/// 控制器挂在对话框自己的 State 上：路由退场动画期间 TextField 还会重建，
/// 若由页面在 showDialog 返回后立刻 dispose，会撞上
/// "A TextEditingController was used after being disposed"。
class _ImportJsonDialog extends StatefulWidget {
  const _ImportJsonDialog({required this.l10n});

  final AppLocalizations l10n;

  @override
  State<_ImportJsonDialog> createState() => _ImportJsonDialogState();
}

class _ImportJsonDialogState extends State<_ImportJsonDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    return AlertDialog(
      title: Text(l10n.capabilityVocabularyImportTitle),
      content: SizedBox(
        width: 520,
        child: TextField(
          key: capabilityVocabularyImportFieldKey,
          controller: _controller,
          minLines: 6,
          maxLines: 10,
          decoration: InputDecoration(
            hintText: l10n.capabilityVocabularyImportHint,
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          key: capabilityVocabularyImportConfirmKey,
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: Text(l10n.commonConfirm),
        ),
      ],
    );
  }
}

class _CapabilityActionDialog extends StatefulWidget {
  const _CapabilityActionDialog({required this.l10n, this.existing});

  final AppLocalizations l10n;
  final CustomCapabilityAction? existing;

  @override
  State<_CapabilityActionDialog> createState() =>
      _CapabilityActionDialogState();
}

class _CapabilityActionDialogState extends State<_CapabilityActionDialog> {
  late final TextEditingController _keyController;
  late final TextEditingController _labelZhController;
  late final TextEditingController _labelEnController;
  late final TextEditingController _descriptionController;
  late final List<String> _subjectHints;
  String? _errorMessage;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _keyController = TextEditingController(text: existing?.key ?? '');
    _labelZhController = TextEditingController(text: existing?.labelZh ?? '');
    _labelEnController = TextEditingController(text: existing?.labelEn ?? '');
    _descriptionController =
        TextEditingController(text: existing?.descriptionZh ?? '');
    _subjectHints = <String>[...?existing?.subjectHints];
  }

  @override
  void dispose() {
    _keyController.dispose();
    _labelZhController.dispose();
    _labelEnController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _toggleSubject(String key, bool selected) {
    setState(() {
      if (selected) {
        if (!_subjectHints.contains(key)) {
          _subjectHints.add(key);
        }
      } else {
        _subjectHints.remove(key);
      }
    });
  }

  void _submit() {
    final existing = widget.existing;
    final draft = CustomCapabilityAction(
      key: existing?.key ?? _keyController.text,
      labelZh: _labelZhController.text,
      labelEn: _labelEnController.text,
      descriptionZh: _descriptionController.text,
      subjectHints: <String>[
        for (final key in CapabilityAction.subjectKeys)
          if (_subjectHints.contains(key)) key,
      ],
    );
    final issue = validateCustomCapabilityAction(draft);
    if (issue != null) {
      setState(() => _errorMessage = issue.message);
      return;
    }
    Navigator.of(context).pop(
      CustomCapabilityAction(
        key: draft.key.trim(),
        labelZh: draft.labelZh.trim(),
        labelEn: draft.labelEn.trim(),
        descriptionZh: draft.descriptionZh.trim(),
        subjectHints: draft.subjectHints,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(
        _isEditing
            ? l10n.capabilityVocabularyEditTitle
            : l10n.capabilityVocabularyAdd,
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                key: capabilityVocabularyKeyFieldKey,
                controller: _keyController,
                enabled: !_isEditing,
                decoration: InputDecoration(
                  labelText: l10n.capabilityVocabularyKeyLabel,
                  helperText: l10n.capabilityVocabularyKeyHint,
                  helperMaxLines: 3,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: capabilityVocabularyLabelZhFieldKey,
                controller: _labelZhController,
                decoration: InputDecoration(
                  labelText: l10n.capabilityVocabularyLabelZh,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: capabilityVocabularyLabelEnFieldKey,
                controller: _labelEnController,
                decoration: InputDecoration(
                  labelText: l10n.capabilityVocabularyLabelEn,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: capabilityVocabularyDescriptionFieldKey,
                controller: _descriptionController,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: l10n.capabilityVocabularyDescriptionZh,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                l10n.capabilityVocabularySubjectHints,
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final key in CapabilityAction.subjectKeys)
                    FilterChip(
                      label: Text(
                        CapabilityAction.subjectLabelsZh[key] ?? key,
                      ),
                      selected: _subjectHints.contains(key),
                      onSelected: (selected) => _toggleSubject(key, selected),
                    ),
                ],
              ),
              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _errorMessage!,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          key: capabilityVocabularyDialogSaveKey,
          onPressed: _submit,
          child: Text(l10n.commonSave),
        ),
      ],
    );
  }
}
