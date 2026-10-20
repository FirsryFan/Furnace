/// 收题页「粘贴组卷网题面」对话框：解析 → 逐条预览/勾选/改题干 → 批量入库。
///
/// 分工：
///  * 解析归域层 `parseZujuanPaste`（纯文本、永不抛）；
///  * 草稿翻译归应用层 `zujuanDraftFromPasted`（来源字段、raw 状态、选项顺序）；
///  * 本文件只做界面与批量入库的编排：单条失败不拖垮整批，最后汇总
///    成功 / 重复 / 失败（重复 = 题干指纹已存在，`created == false`）。
///
/// 预览里题干可改：粘贴来的题面常带序号/来源括号，用户改完再入库是合理的；
/// 改后的文本作为 `stemOverride` 交给装配层，域层字段一个字不改。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/repository_providers.dart';
import '../../../domain/services/zujuan/zujuan_paste.dart';
import '../../../l10n/app_localizations.dart';
import '../application/zujuan_paste_import.dart';
import 'zujuan_pick_panel.dart'
    show zujuanPickDefaultSubject, zujuanSubjectLabel;
import '../../../domain/services/zujuan/zujuan_query.dart' show ZujuanSubject;

/// 收题页表单里的「粘贴组卷网题面」入口按钮。
const Key zujuanPasteOpenButtonKey = Key('zujuan-paste-open');

/// 对话框根（测试用来确认打开 / 关闭）。
const Key zujuanPasteDialogKey = Key('zujuan-paste-dialog');
const Key zujuanPasteInputKey = Key('zujuan-paste-input');
const Key zujuanPasteSubjectFieldKey = Key('zujuan-paste-subject');
const Key zujuanPasteParseKey = Key('zujuan-paste-parse');
const Key zujuanPasteImportKey = Key('zujuan-paste-import');
const Key zujuanPasteEmptyKey = Key('zujuan-paste-empty');

/// 第 [index] 条预览的勾选框 / 题干输入框。
Key zujuanPasteCheckboxKey(int index) =>
    ValueKey<String>('zujuan-paste-checkbox-$index');
Key zujuanPasteStemFieldKey(int index) =>
    ValueKey<String>('zujuan-paste-stem-$index');

/// 一次批量入库的汇总（成功 / 重复 / 失败）。
class ZujuanPasteSummary {
  const ZujuanPasteSummary({
    required this.saved,
    required this.duplicates,
    required this.failed,
  });

  final int saved;
  final int duplicates;
  final int failed;
}

/// 「全部入库」的启用条件：至少勾了一道、且没有正在入库。
bool zujuanPasteCanImport({
  required int selectedCount,
  required bool importing,
}) =>
    !importing && selectedCount > 0;

/// 打开粘贴对话框；返回值是用户按「全部入库」后的汇总（直接关掉为 null）。
///
/// [initialSubjectKey] 是收题表单当前的学科键，决定预览里默认的入库学科。
Future<ZujuanPasteSummary?> showZujuanPasteDialog(
  BuildContext context, {
  required AppLocalizations l10n,
  String? initialSubjectKey,
}) {
  return showDialog<ZujuanPasteSummary>(
    context: context,
    builder: (dialogContext) => _ZujuanPasteDialog(
      l10n: l10n,
      initialSubjectKey: initialSubjectKey,
    ),
  );
}

class _ZujuanPasteDialog extends ConsumerStatefulWidget {
  const _ZujuanPasteDialog({required this.l10n, this.initialSubjectKey});

  final AppLocalizations l10n;
  final String? initialSubjectKey;

  @override
  ConsumerState<_ZujuanPasteDialog> createState() => _ZujuanPasteDialogState();
}

class _ZujuanPasteDialogState extends ConsumerState<_ZujuanPasteDialog> {
  final _inputController = TextEditingController();
  final List<_PasteItem> _items = <_PasteItem>[];
  late ZujuanSubject _subject;
  bool _parsed = false;
  bool _importing = false;

  @override
  void initState() {
    super.initState();
    _subject = zujuanPickDefaultSubject(widget.initialSubjectKey);
  }

  @override
  void dispose() {
    _inputController.dispose();
    _disposeItems();
    super.dispose();
  }

  void _disposeItems() {
    for (final item in _items) {
      item.dispose();
    }
    _items.clear();
  }

  int get _selectedCount =>
      _items.where((item) => item.checked && item.importable).length;

  void _parse() {
    final parsed = parseZujuanPaste(_inputController.text);
    setState(() {
      _disposeItems();
      _items.addAll(parsed.map(_PasteItem.new));
      _parsed = true;
    });
  }

  Future<void> _import() async {
    if (_importing) return;
    final selected = _items
        .where((item) => item.checked && item.importable)
        .toList(growable: false);
    setState(() => _importing = true);
    final repository = ref.read(questionRepositoryProvider);
    var saved = 0;
    var duplicates = 0;
    var failed = 0;
    for (final item in selected) {
      try {
        final draft = zujuanDraftFromPasted(
          item.pasted,
          subjectKey: _subject.name,
          stemOverride: item.stemController.text,
        );
        final result = await repository.ingest(draft);
        if (result.created) {
          saved++;
        } else {
          duplicates++;
        }
      } catch (_) {
        // 单条坏数据不拖垮整批：失败计数，继续下一条。
        failed++;
      }
    }
    if (!mounted) return;
    setState(() => _importing = false);
    Navigator.of(context).pop(
      ZujuanPasteSummary(saved: saved, duplicates: duplicates, failed: failed),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    final theme = Theme.of(context);
    return Dialog(
      key: zujuanPasteDialogKey,
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
                      l10n.zujuanPasteTitle,
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: l10n.commonClose,
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              Text(l10n.zujuanPasteIntro, style: theme.textTheme.bodySmall),
              Text(
                l10n.zujuanPasteLoginHint,
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              TextField(
                key: zujuanPasteInputKey,
                controller: _inputController,
                minLines: 6,
                maxLines: 10,
                decoration: InputDecoration(
                  labelText: l10n.zujuanPasteInputLabel,
                  hintText: l10n.zujuanPasteInputHint,
                  alignLabelWithHint: true,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<ZujuanSubject>(
                      key: zujuanPasteSubjectFieldKey,
                      initialValue: _subject,
                      decoration: InputDecoration(
                        labelText: l10n.zujuanPickSubject,
                        border: const OutlineInputBorder(),
                      ),
                      items: [
                        for (final subject in ZujuanSubject.values)
                          DropdownMenuItem<ZujuanSubject>(
                            value: subject,
                            child: Text(zujuanSubjectLabel(subject)),
                          ),
                      ],
                      onChanged: _importing
                          ? null
                          : (value) {
                              if (value != null) {
                                setState(() => _subject = value);
                              }
                            },
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.tonalIcon(
                    key: zujuanPasteParseKey,
                    onPressed: _importing ? null : _parse,
                    icon: const Icon(Icons.manage_search),
                    label: Text(l10n.zujuanPasteParse),
                  ),
                ],
              ),
              if (_parsed) ...[
                const SizedBox(height: 12),
                if (_items.isEmpty)
                  Card(
                    key: zujuanPasteEmptyKey,
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(l10n.zujuanPasteParseEmpty),
                    ),
                  )
                else ...[
                  Text(
                    l10n.zujuanPastePreviewTitle(_items.length),
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  Flexible(
                    fit: FlexFit.loose,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 300),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: _items.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 8),
                        itemBuilder: _buildItem,
                      ),
                    ),
                  ),
                ],
              ],
              if (_items.isNotEmpty) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _selectedCount == 0
                          ? Text(
                              l10n.zujuanPasteNothingSelected,
                              style: theme.textTheme.bodySmall,
                            )
                          : const SizedBox.shrink(),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      key: zujuanPasteImportKey,
                      onPressed: zujuanPasteCanImport(
                        selectedCount: _selectedCount,
                        importing: _importing,
                      )
                          ? _import
                          : null,
                      icon: _importing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.playlist_add),
                      label: Text(
                        _importing
                            ? l10n.zujuanPasteImporting
                            : l10n.zujuanPasteImport,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildItem(BuildContext context, int index) {
    final l10n = widget.l10n;
    final theme = Theme.of(context);
    final item = _items[index];
    final pasted = item.pasted;
    final meta = <String>[
      if (pasted.sourceLabel != null)
        l10n.zujuanPasteItemSource(pasted.sourceLabel!),
      if (pasted.year != null) l10n.zujuanPasteItemYear(pasted.year!),
    ].join(' · ');
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 12, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              key: zujuanPasteCheckboxKey(index),
              value: item.checked && item.importable,
              onChanged: item.importable
                  ? (value) => setState(() => item.checked = value ?? false)
                  : null,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Text(
                        '${pasted.ordinal ?? index + 1}.',
                        style: theme.textTheme.labelMedium,
                      ),
                      if (meta.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            meta,
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  TextField(
                    key: zujuanPasteStemFieldKey(index),
                    controller: item.stemController,
                    minLines: 1,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: l10n.zujuanPasteItemStem,
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      if (pasted.options.isNotEmpty)
                        Text(
                          l10n.zujuanPasteItemOptions(pasted.options.length),
                          style: theme.textTheme.bodySmall,
                        ),
                      if (pasted.isPartial)
                        Text(
                          l10n.zujuanPastePartial,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                    ],
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

/// 一条预览：解析结果 + 可编辑题干 + 勾选状态。
class _PasteItem {
  _PasteItem(this.pasted)
      : stemController = TextEditingController(text: pasted.stem.trim()),
        checked = pasted.stem.trim().isNotEmpty;

  final ZujuanPastedQuestion pasted;
  final TextEditingController stemController;
  bool checked;

  bool get importable => stemController.text.trim().isNotEmpty;

  void dispose() => stemController.dispose();
}
