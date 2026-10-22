/// 组卷页的「领域配额」界面：配额编辑区 + 生成后的分布/被挡/缺口。
///
/// 分工：
/// * 状态全在 paperSpecProvider（PaperSpecNotifier.setDomainMax /
///   setDomainMin / clearDomainQuota），这一层不自己保存配额，也不重算卷子；
/// * 卷子结果全来自 PaperPlan（byDomain / quotaBlockedByDomain /
///   domainShortfalls / uncoveredDomains），这里只排版，不改域层措辞；
/// * 输入解析、领域键收集、分布排序都是纯函数（文件上半部分），widget 测试与
///   单测直接调它们，避免在测试里复刻一遍校验规则。
///
/// 领域键与学科键是两套命名空间：领域是知识点标签路径的第一段（如「数学」），
/// 学科是题目行上的 subjectKey（如 math）。同一张卷子上两套配额各自生效。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/services/paper/domain_quota.dart';
import '../../../domain/services/paper/paper_composer.dart';
import '../../../l10n/app_localizations.dart';
import '../application/paper_plan_provider.dart';
import '../application/question_stem_display_provider.dart';

/// 配额编辑区根节点（widget 测试用它定位整块）。
const Key paperDomainQuotaSectionKey = Key('paper-domain-quota-section');

/// 「清空配额」按钮。
const Key paperDomainQuotaClearKey = Key('paper-domain-quota-clear');

/// 生成后的「领域分布 / 被挡 / 保底缺口」卡片。
const Key paperDomainQuotaOutcomeKey = Key('paper-domain-quota-outcome');

/// 某领域的上限输入框（领域键原样进 key，测试据此定位）。
Key paperDomainQuotaMaxKey(String domain) =>
    Key('paper-domain-quota-max-$domain');

/// 某领域的保底输入框。
Key paperDomainQuotaMinKey(String domain) =>
    Key('paper-domain-quota-min-$domain');

/// 一次输入框内容解析结果（与学科配额同口径：空 / 合法 / 非法三态）。
///
/// 只用 int? 会把「没填」和「填错」混成同一个 null，因此单独带一个 isInvalid。
class PaperDomainQuotaInput {
  const PaperDomainQuotaInput._({this.value, required this.isInvalid});

  /// 解析出的整数值；空输入与非法输入都是 null，用 isInvalid 区分。
  final int? value;

  /// 非整数或负数 → true（调用方不许提交）。
  final bool isInvalid;

  /// 空输入 = 清掉这一领域这一项配额。
  bool get isEmpty => value == null && !isInvalid;
}

/// 解析一个配额输入框：空 → 空；非负整数 → 合法；其余（负数、小数、文字）→ 非法。
///
/// 上限 0 是合法的（= 这个领域一道都不选）；保底输入 0 由
/// PaperSpecNotifier.setDomainMin 按「<1 = 去掉保底」处理。
PaperDomainQuotaInput parsePaperDomainQuotaInput(String raw) {
  final text = raw.trim();
  if (text.isEmpty) {
    return const PaperDomainQuotaInput._(isInvalid: false);
  }
  final value = int.tryParse(text);
  if (value == null || value < 0) {
    return const PaperDomainQuotaInput._(isInvalid: true);
  }
  return PaperDomainQuotaInput._(value: value, isInvalid: false);
}

/// 题库里出现过的领域键：知识点标签路径的第一段，去重、按字典序。
///
/// 用 [DomainQuotaResolver.domainOfTagPath] 解析（与域层配额键同一套规则）；
/// 每个元素必须是一条完整标签路径，不能传已经切好的片段列表。
List<String> paperDomainQuotaBankDomains(
  Map<String, List<String>> knowledgePointTagPaths,
) {
  final domains = <String>{};
  for (final paths in knowledgePointTagPaths.values) {
    for (final path in paths) {
      final domain = DomainQuotaResolver.domainOfTagPath(path);
      if (domain != null) domains.add(domain);
    }
  }
  return domains.toList()..sort();
}

/// 配额区要列哪些领域、按什么顺序：先按题库里出现过的顺序（已排序），再补
/// 只在配额里出现过的键（按字典序）。空白键一律丢掉。
///
/// 已配置但题库里暂时没有候选的领域也要列出来：否则用户看不到、也清不掉。
List<String> paperDomainQuotaDomains({
  required Iterable<String> configuredDomains,
  required Iterable<String> bankDomains,
}) {
  final seen = <String>{};
  final ordered = <String>[];
  for (final raw in bankDomains) {
    final domain = raw.trim();
    if (domain.isEmpty || !seen.add(domain)) continue;
    ordered.add(domain);
  }
  final extras = <String>[];
  for (final raw in configuredDomains) {
    final domain = raw.trim();
    if (domain.isEmpty || !seen.add(domain)) continue;
    extras.add(domain);
  }
  extras.sort();
  return [...ordered, ...extras];
}

/// 领域分布排序：数量倒序，同数量按领域键字典序（保证渲染稳定可断言）。
/// 0 道与空白键不列（0 道等于不存在）。
List<MapEntry<String, int>> paperDomainQuotaDistributionSorted(
  Map<String, int> byDomain,
) {
  final entries = <MapEntry<String, int>>[
    for (final entry in byDomain.entries)
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
const int paperDomainQuotaBlockedPreviewLimit = 3;

/// 被上限挡下的预览条目（按域层扫描顺序，最多 limit 条）。
List<DomainQuotaBlockedQuestion> paperDomainQuotaBlockedPreview(
  List<DomainQuotaBlockedQuestion> blocked, {
  int limit = paperDomainQuotaBlockedPreviewLimit,
}) =>
    blocked.take(limit).toList();

/// 预览之外还剩几条（0 = 全都列出来了，不显示「还有」）。
int paperDomainQuotaBlockedHidden(
  List<DomainQuotaBlockedQuestion> blocked, {
  int limit = paperDomainQuotaBlockedPreviewLimit,
}) {
  final hidden = blocked.length - limit;
  return hidden > 0 ? hidden : 0;
}

/// 题干预览：折掉换行与连续空白、截到 maxChars 个字符（超出加省略号）。
/// 空题干返回空串（调用方回退到题号）。
String paperDomainQuotaStemPreview(String stem, {int maxChars = 24}) {
  final flattened = stem
      .replaceAll('\n', ' ')
      .replaceAll('\r', ' ')
      .replaceAll('\t', ' ')
      .trim();
  final text = flattened.split(' ').where((part) => part.isNotEmpty).join(' ');
  if (text.isEmpty) return '';
  if (text.length <= maxChars) return text;
  return '${text.substring(0, maxChars)}…';
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
/// 领域行 = 题库里出现过的领域 + 已配置但题库暂时没候选的领域；两者都没有时
/// 整块不摆（默认不启用的时候页面与历史一致，不摆一张空卡片）。
class PaperDomainQuotaSection extends ConsumerWidget {
  const PaperDomainQuotaSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final spec = ref.watch(paperSpecProvider);
    final corpus = ref.watch(paperCorpusProvider);
    final notifier = ref.read(paperSpecProvider.notifier);
    final quota = spec.domainQuota;
    final resolvedQuota = quota?.resolve();
    final bankDomains = corpus.maybeWhen(
      data: (value) =>
          paperDomainQuotaBankDomains(value.knowledgePointTagPaths),
      orElse: () => const <String>[],
    );
    final configuredDomains = <String>[
      if (resolvedQuota != null) ...resolvedQuota.maxPerDomain.keys,
      if (resolvedQuota != null) ...resolvedQuota.minPerDomain.keys,
    ];
    final domains = paperDomainQuotaDomains(
      configuredDomains: configuredDomains,
      bankDomains: bankDomains,
    );
    if (domains.isEmpty) {
      return const SizedBox.shrink();
    }

    return Card(
      key: paperDomainQuotaSectionKey,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.paperDomainQuotaTitle,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                TextButton.icon(
                  key: paperDomainQuotaClearKey,
                  onPressed: quota == null ? null : notifier.clearDomainQuota,
                  icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
                  label: Text(l10n.paperDomainQuotaClear),
                ),
              ],
            ),
            Text(
              l10n.paperDomainQuotaHint,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            for (final domain in domains)
              Padding(
                key: ValueKey('paper-domain-quota-row-$domain'),
                padding: const EdgeInsets.only(bottom: 8),
                child: _DomainQuotaRow(
                  domain: domain,
                  maxValue: resolvedQuota?.maxFor(domain),
                  minValue: (resolvedQuota?.minFor(domain) ?? 0) > 0
                      ? resolvedQuota?.minFor(domain)
                      : null,
                  onMaxChanged: (value) => notifier.setDomainMax(domain, value),
                  onMinChanged: (value) => notifier.setDomainMin(domain, value),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 一个领域一行：领域名 + 上限输入 + 保底输入。
class _DomainQuotaRow extends StatelessWidget {
  const _DomainQuotaRow({
    required this.domain,
    required this.maxValue,
    required this.minValue,
    required this.onMaxChanged,
    required this.onMinChanged,
  });

  final String domain;
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
            domain,
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        SizedBox(
          width: 150,
          child: _QuotaNumberField(
            key: paperDomainQuotaMaxKey(domain),
            label: l10n.paperDomainQuotaMaxLabel,
            value: maxValue,
            onChanged: onMaxChanged,
          ),
        ),
        SizedBox(
          width: 150,
          child: _QuotaNumberField(
            key: paperDomainQuotaMinKey(domain),
            label: l10n.paperDomainQuotaMinLabel,
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
    final parsed = parsePaperDomainQuotaInput(raw);
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
        errorText: _invalid ? l10n.paperDomainQuotaInvalid : null,
      ),
      onChanged: _onChanged,
    );
  }
}

/// 生成后的配额结果：领域分布、被上限挡下的题、保底缺口、未覆盖领域。
///
/// 三块都空时整体返回零高度（不摆一张什么都没说的卡片）。
class PaperDomainQuotaOutcome extends ConsumerWidget {
  const PaperDomainQuotaOutcome({super.key, required this.plan});

  final PaperPlan plan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final distribution = paperDomainQuotaDistributionSorted(plan.byDomain);
    final blocked = plan.quotaBlockedByDomain;
    final shortfalls = plan.domainShortfalls;
    if (distribution.isEmpty && blocked.isEmpty && shortfalls.isEmpty) {
      return const SizedBox.shrink();
    }

    final displays = _watchStemDisplays(ref);
    final preview = paperDomainQuotaBlockedPreview(blocked);
    final hidden = paperDomainQuotaBlockedHidden(blocked);

    return Card(
      key: paperDomainQuotaOutcomeKey,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (distribution.isNotEmpty) ...[
              Text(
                l10n.paperDomainQuotaDistribution,
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [
                  for (final entry in distribution)
                    Text(
                      '${entry.key} · ${l10n.questionPaperCountOption(entry.value)}',
                    ),
                ],
              ),
            ],
            if (blocked.isNotEmpty) ...[
              if (distribution.isNotEmpty) const SizedBox(height: 12),
              Text(
                l10n.paperDomainQuotaBlocked(blocked.length),
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              for (final item in preview)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        l10n.paperDomainQuotaBlockedItem(
                          item.domain,
                          item.domainLimit,
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
                  l10n.paperDomainQuotaBlockedMore(hidden),
                  style: theme.textTheme.bodySmall,
                ),
            ],
            if (shortfalls.isNotEmpty) ...[
              if (distribution.isNotEmpty || blocked.isNotEmpty)
                const SizedBox(height: 12),
              Text(
                l10n.paperDomainQuotaShortfallTitle,
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              for (final shortfall in shortfalls)
                shortfall.isUncovered
                    ? Text(
                        l10n.paperDomainQuotaShortfallEmpty(
                          shortfall.domain,
                        ),
                      )
                    : Text(
                        l10n.paperDomainQuotaShortfall(
                          shortfall.domain,
                          shortfall.minimumCount - shortfall.selectedCount,
                          shortfall.availableCount,
                        ),
                      ),
            ],
            if (plan.uncoveredDomains.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                l10n.paperDomainQuotaUncovered(
                  plan.uncoveredDomains.join('、'),
                ),
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 被挡题的那一行：优先题干一行文本（快照题用摘录），空时回退到题号。
  String _blockedDescription(
    DomainQuotaBlockedQuestion item,
    Map<String, QuestionStemDisplay> displays,
  ) {
    final preview =
        paperDomainQuotaStemPreview(displays[item.questionId]?.text ?? '');
    return preview.isEmpty ? item.questionId : preview;
  }
}
