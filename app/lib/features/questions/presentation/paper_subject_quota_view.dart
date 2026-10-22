/// 组卷页的「学科配额」界面：配额编辑区 + 生成后的分布/被挡/缺口。
///
/// 分工：
/// * 状态全在 paperSpecProvider（PaperSpecNotifier.setSubjectMax /
///   setSubjectMin / clearSubjectQuota），这一层不自己保存配额，也不重算卷子；
/// * 卷子结果全来自 PaperPlan（bySubject / quotaBlockedQuestions /
///   subjectShortfalls），这里只排版，不改域层措辞；
/// * 输入解析、学科排序、分布排序都是纯函数（文件上半部分），widget 测试与单测
///   直接调它们，避免在测试里复刻一遍校验规则。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/services/paper/paper_composer.dart';
import '../../../domain/services/paper/subject_quota.dart';
import '../../../domain/services/reasoning/capability_action.dart';
import '../../../l10n/app_localizations.dart';
import '../application/paper_plan_provider.dart';
import '../application/question_stem_display_provider.dart';

/// 配额编辑区根节点（widget 测试用它定位整块）。
const Key paperSubjectQuotaSectionKey = Key('paper-subject-quota-section');

/// 「清空配额」按钮。
const Key paperSubjectQuotaClearKey = Key('paper-subject-quota-clear');

/// 生成后的「学科分布 / 被挡 / 保底缺口」卡片。
const Key paperSubjectQuotaOutcomeKey = Key('paper-subject-quota-outcome');

/// 某学科的上限输入框（学科键原样进 key，测试据此定位）。
Key paperSubjectQuotaMaxKey(String subjectKey) =>
    Key('paper-subject-quota-max-$subjectKey');

/// 某学科的保底输入框。
Key paperSubjectQuotaMinKey(String subjectKey) =>
    Key('paper-subject-quota-min-$subjectKey');

/// 一次输入框内容解析结果。
///
/// 三种状态必须区分开：空（清掉这条配额）、合法整数（提交）、非法（不提交，
/// 输入框标红）。只用 int? 会把「没填」和「填错」混成同一个 null。
class PaperSubjectQuotaInput {
  const PaperSubjectQuotaInput._({this.value, required this.isInvalid});

  /// 解析出的整数值；空输入与非法输入都是 null，用 isInvalid 区分。
  final int? value;

  /// 非整数或负数 → true（调用方不许提交）。
  final bool isInvalid;

  /// 空输入 = 清掉这一科这一项配额。
  bool get isEmpty => value == null && !isInvalid;
}

/// 解析一个配额输入框：空 → 空；非负整数 → 合法；其余（负数、小数、文字）→ 非法。
///
/// 上限 0 是合法的（= 这一科一道都不选），所以这里只把负数拒掉；保底输入 0 由
/// PaperSpecNotifier.setSubjectMin 按「<1 = 去掉保底」处理。
PaperSubjectQuotaInput parsePaperSubjectQuotaInput(String raw) {
  final text = raw.trim();
  if (text.isEmpty) {
    return const PaperSubjectQuotaInput._(isInvalid: false);
  }
  final value = int.tryParse(text);
  if (value == null || value < 0) {
    return const PaperSubjectQuotaInput._(isInvalid: true);
  }
  return PaperSubjectQuotaInput._(value: value, isInvalid: false);
}

/// 配额区要列哪些学科、按什么顺序：先按题库里出现过的顺序，再补只在筛选里
/// 出现过的键（按字典序）。空白键一律丢掉。
List<String> paperSubjectQuotaSubjects({
  required Iterable<String> selectedSubjects,
  required Iterable<String> bankSubjects,
}) {
  final remaining = <String>{
    for (final key in selectedSubjects)
      if (key.trim().isNotEmpty) key.trim(),
  };
  final ordered = <String>[];
  for (final key in bankSubjects) {
    final trimmed = key.trim();
    if (trimmed.isEmpty || !remaining.remove(trimmed)) continue;
    ordered.add(trimmed);
  }
  final rest = remaining.toList()..sort();
  return [...ordered, ...rest];
}

/// 学科分布排序：数量倒序，同数量按学科键字典序（保证渲染稳定可断言）。
/// 0 道与空白键不列（0 道等于不存在）。
List<MapEntry<String, int>> paperSubjectDistributionSorted(
  Map<String, int> bySubject,
) {
  final entries = <MapEntry<String, int>>[
    for (final entry in bySubject.entries)
      if (entry.key.trim().isNotEmpty && entry.value > 0)
        MapEntry(entry.key.trim(), entry.value),
  ];
  entries.sort((a, b) {
    final byCount = b.value.compareTo(a.value);
    if (byCount != 0) return byCount;
    return a.key.compareTo(b.key);
  });
  return entries;
}

/// 被上限挡下的题最多列几条。
const int paperSubjectQuotaBlockedPreviewLimit = 3;

/// 被上限挡下的预览条目（按域层扫描顺序，最多 limit 条）。
List<QuotaBlockedQuestion> paperSubjectQuotaBlockedPreview(
  List<QuotaBlockedQuestion> blocked, {
  int limit = paperSubjectQuotaBlockedPreviewLimit,
}) =>
    blocked.take(limit).toList();

/// 预览之外还剩几条（0 = 全都列出来了，不显示「还有」）。
int paperSubjectQuotaBlockedHidden(
  List<QuotaBlockedQuestion> blocked, {
  int limit = paperSubjectQuotaBlockedPreviewLimit,
}) {
  final hidden = blocked.length - limit;
  return hidden > 0 ? hidden : 0;
}

/// 题干预览：折掉换行与连续空白、截到 maxChars 个字符（超出加省略号）。
/// 空题干返回空串（调用方回退到题号）。
String paperSubjectQuotaStemPreview(String stem, {int maxChars = 24}) {
  final text = stem.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (text.isEmpty) return '';
  if (text.length <= maxChars) return text;
  return '${text.substring(0, maxChars)}…';
}

/// 学科显示名：与组卷页 subjectLabelOf 用同一份词表（CapabilityAction）。
/// 词表里没有的键原样显示，不静默归类。
String paperSubjectLabelOf(AppLocalizations l10n, String subjectKey) {
  final key = subjectKey.trim();
  if (key.isEmpty) return l10n.questionPaperSubjectNone;
  return CapabilityAction.subjectLabelsZh[key] ?? key;
}

/// 一次读全表的题干一行文本；数据未到时用空 map（各行回退成题号）。
Map<String, QuestionStemDisplay> _watchStemDisplays(WidgetRef ref) =>
    ref.watch(questionStemDisplayProvider).maybeWhen(
          data: (value) => value,
          orElse: () => const <String, QuestionStemDisplay>{},
        );

/// 快照题的小标签：只在「有正文摘录」时摆——没有摘录时 [QuestionStemDisplay.text]
/// 本身就是「整题截图 · N 处公式/图」，再摆一次会重复（与题库列表同口径）。
bool _showsSnapshotBadge(QuestionStemDisplay? display) =>
    display != null && display.isSnapshot && display.hasExcerpt;

/// 「整题截图」小标签（不加卡片，只占行尾一小段）。
Widget _snapshotBadge(BuildContext context) {
  final theme = Theme.of(context);
  return Padding(
    padding: const EdgeInsets.only(left: 6),
    child: Text(
      AppLocalizations.of(context).questionBankSnapshotBadge,
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    ),
  );
}

/// 配额编辑区。
///
/// 只有「已选学科」才列输入框：配额是按学科生效的，没选学科时整卷不限学科，
/// 此时摆一排输入框只会让用户以为每一科都已经被限制住。
class PaperSubjectQuotaSection extends ConsumerWidget {
  const PaperSubjectQuotaSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final spec = ref.watch(paperSpecProvider);
    final subjectOptions = ref.watch(paperSubjectOptionsProvider);
    final notifier = ref.read(paperSpecProvider.notifier);
    final quota = spec.subjectQuota;
    final resolvedQuota = quota?.resolve();
    final bankSubjects = subjectOptions.maybeWhen(
      data: (keys) => keys,
      orElse: () => const <String>[],
    );
    final subjects = paperSubjectQuotaSubjects(
      selectedSubjects: spec.subjectKeys,
      bankSubjects: bankSubjects,
    );

    return Card(
      key: paperSubjectQuotaSectionKey,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.paperSubjectQuotaTitle,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                TextButton.icon(
                  key: paperSubjectQuotaClearKey,
                  onPressed: quota == null ? null : notifier.clearSubjectQuota,
                  icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
                  label: Text(l10n.paperSubjectQuotaClear),
                ),
              ],
            ),
            Text(
              l10n.paperSubjectQuotaHint,
              style: theme.textTheme.bodySmall,
            ),
            if (subjects.isEmpty) ...[
              const SizedBox(height: 8),
              Text(
                l10n.paperSubjectQuotaNoSubjects,
                style: theme.textTheme.bodySmall,
              ),
            ] else ...[
              const SizedBox(height: 12),
              for (final subjectKey in subjects)
                Padding(
                  key: ValueKey('paper-subject-quota-row-$subjectKey'),
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _SubjectQuotaRow(
                    subjectKey: subjectKey,
                    maxValue: resolvedQuota?.maxFor(subjectKey),
                    minValue: (resolvedQuota?.minFor(subjectKey) ?? 0) > 0
                        ? resolvedQuota?.minFor(subjectKey)
                        : null,
                    onMaxChanged: (value) =>
                        notifier.setSubjectMax(subjectKey, value),
                    onMinChanged: (value) =>
                        notifier.setSubjectMin(subjectKey, value),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 一科一行：学科名 + 上限输入 + 保底输入。
class _SubjectQuotaRow extends StatelessWidget {
  const _SubjectQuotaRow({
    required this.subjectKey,
    required this.maxValue,
    required this.minValue,
    required this.onMaxChanged,
    required this.onMinChanged,
  });

  final String subjectKey;
  final int? maxValue;
  final int? minValue;
  final ValueChanged<int?> onMaxChanged;
  final ValueChanged<int?> onMinChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 96,
          child: Text(
            paperSubjectLabelOf(l10n, subjectKey),
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        SizedBox(
          width: 150,
          child: _QuotaNumberField(
            key: paperSubjectQuotaMaxKey(subjectKey),
            label: l10n.paperSubjectQuotaMaxLabel,
            value: maxValue,
            onChanged: onMaxChanged,
          ),
        ),
        SizedBox(
          width: 150,
          child: _QuotaNumberField(
            key: paperSubjectQuotaMinKey(subjectKey),
            label: l10n.paperSubjectQuotaMinLabel,
            value: minValue,
            onChanged: onMinChanged,
          ),
        ),
      ],
    );
  }
}

/// 一个整数配额输入框：空 = 不限；非法内容标红且不提交。
///
/// 输入框自己持有一个 controller（不能每次重建都从 spec 生成文本，否则打字打到
/// 一半就被上一帧的值覆盖）。外部变化只在两种情况下回写文本：
/// * 新值是空串（清空配额 / 重置）：连正在编辑的框一起清掉；
/// * 输入框没聚焦：把外部改动同步进来。
class _QuotaNumberField extends StatefulWidget {
  const _QuotaNumberField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final int? value;
  final ValueChanged<int?> onChanged;

  @override
  State<_QuotaNumberField> createState() => _QuotaNumberFieldState();
}

class _QuotaNumberFieldState extends State<_QuotaNumberField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  bool _invalid = false;

  static String _textOf(int? value) => value == null ? '' : value.toString();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _textOf(widget.value));
    _focusNode = FocusNode();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _QuotaNumberField oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = _textOf(widget.value);
    if (_controller.text == next) return;
    if (next.isEmpty || !_focusNode.hasFocus) {
      _controller.text = next;
      _invalid = false;
    }
  }

  void _onChanged(String raw) {
    final parsed = parsePaperSubjectQuotaInput(raw);
    if (parsed.isInvalid) {
      if (!_invalid) setState(() => _invalid = true);
      return;
    }
    if (_invalid) setState(() => _invalid = false);
    widget.onChanged(parsed.value);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return TextField(
      controller: _controller,
      focusNode: _focusNode,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: widget.label,
        isDense: true,
        border: const OutlineInputBorder(),
        errorText: _invalid ? l10n.paperSubjectQuotaInvalid : null,
      ),
      onChanged: _onChanged,
    );
  }
}

/// 生成后的配额结果：学科分布、被上限挡下的题、保底缺口。
///
/// 三块都空时整体返回零高度（不摆一张什么都没说的卡片）。
class PaperSubjectQuotaOutcome extends ConsumerWidget {
  const PaperSubjectQuotaOutcome({super.key, required this.plan});

  final PaperPlan plan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final distribution = paperSubjectDistributionSorted(plan.bySubject);
    final blocked = plan.quotaBlockedQuestions;
    final shortfalls = plan.subjectShortfalls;
    if (distribution.isEmpty && blocked.isEmpty && shortfalls.isEmpty) {
      return const SizedBox.shrink();
    }

    final displays = _watchStemDisplays(ref);
    final preview = paperSubjectQuotaBlockedPreview(blocked);
    final hidden = paperSubjectQuotaBlockedHidden(blocked);

    return Card(
      key: paperSubjectQuotaOutcomeKey,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (distribution.isNotEmpty) ...[
              Text(
                l10n.paperSubjectDistribution,
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [
                  for (final entry in distribution)
                    Text(
                      '${paperSubjectLabelOf(l10n, entry.key)} · '
                      '${l10n.questionPaperCountOption(entry.value)}',
                    ),
                ],
              ),
            ],
            if (blocked.isNotEmpty) ...[
              if (distribution.isNotEmpty) const SizedBox(height: 12),
              Text(
                l10n.paperSubjectQuotaBlocked(blocked.length),
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              for (final item in preview)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        l10n.paperSubjectQuotaBlockedItem(
                          paperSubjectLabelOf(l10n, item.subjectKey),
                          item.subjectLimit,
                          _blockedDescription(item, displays),
                        ),
                      ),
                    ),
                    if (_showsSnapshotBadge(displays[item.questionId]))
                      _snapshotBadge(context),
                  ],
                ),
              if (hidden > 0)
                Text(
                  l10n.paperSubjectQuotaBlockedMore(hidden),
                  style: theme.textTheme.bodySmall,
                ),
            ],
            if (shortfalls.isNotEmpty) ...[
              if (distribution.isNotEmpty || blocked.isNotEmpty)
                const SizedBox(height: 12),
              Text(
                l10n.paperSubjectQuotaShortfallTitle,
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              for (final shortfall in shortfalls)
                shortfall.isUncovered
                    ? Text(
                        l10n.paperSubjectQuotaShortfallEmpty(
                          paperSubjectLabelOf(l10n, shortfall.subjectKey),
                        ),
                      )
                    : Text(
                        l10n.paperSubjectQuotaShortfall(
                          paperSubjectLabelOf(l10n, shortfall.subjectKey),
                          shortfall.minimumCount - shortfall.selectedCount,
                          shortfall.availableCount,
                        ),
                      ),
            ],
          ],
        ),
      ),
    );
  }

  /// 被挡题的那一行：优先题干一行文本（快照题用摘录），空时回退到题号。
  String _blockedDescription(
    QuotaBlockedQuestion item,
    Map<String, QuestionStemDisplay> displays,
  ) {
    final preview =
        paperSubjectQuotaStemPreview(displays[item.questionId]?.text ?? '');
    return preview.isEmpty ? item.questionId : preview;
  }
}
