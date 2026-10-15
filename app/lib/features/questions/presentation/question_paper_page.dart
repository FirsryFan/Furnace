/// 组卷页：把纯逻辑组卷器（`domain/services/paper/paper_composer.dart`）接到界面上。
///
/// 这一页只做三件事：给控制项、展示卷子、如实报缺口。
///
/// **属于领域层的措辞一律不在这里重写**：`reasonZh` / `improvementNote` /
/// `backgroundZh` 与 [PaperZone.labelZh] 都是从 [PaperPlan] 里直接取出来的字符串，
/// 页面只负责排版。理由/提升点的文案改在域层改，页面跟着就变。
///
/// 缺口不是错误：`uncoveredKnowledgePointIds` 是"题库里一道候选都没有"，
/// 按用户口径（AI 不能自己出题）如实留空并引导去收题；
/// `deferredKnowledgePointIds` 是"有候选但被数量/配额挤掉"，提示调大目标题数。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/services/paper/paper_composer.dart';
import '../../../domain/services/reasoning/capability_action.dart';
import '../../../l10n/app_localizations.dart';
import '../application/paper_plan_provider.dart';
import 'question_vocab_labels.dart';

/// 目标题数下拉的选项（本页冻结：5 / 10 / 15 / 20）。
const List<int> paperTargetCountOptions = <int>[5, 10, 15, 20];

/// 来源下限下拉的候选（不含"不限"，那是 `null`）。
const List<String> paperMinSourceLevelOptions = <String>[
  'gaokao',
  'provincial_diagnostic',
  'elite_school',
  'school',
  'personal',
];

/// 目标难度下拉的候选：1.0–10.0、步长 0.5（"不限"是 `null`，单独一项）。
///
/// 难度在领域层是**偏好**不是硬筛（`PaperComposer._difficultyFit`：没有目标难度
/// 时人人都拿 1.0；设了目标难度后，没填难度的题拿 0.5，只往后排、不会被排除），
/// 所以这里的措辞是「越接近越靠前」，不说"只看这个难度"。
const List<double> paperTargetDifficultyOptions = <double>[
  1.0,
  1.5,
  2.0,
  2.5,
  3.0,
  3.5,
  4.0,
  4.5,
  5.0,
  5.5,
  6.0,
  6.5,
  7.0,
  7.5,
  8.0,
  8.5,
  9.0,
  9.5,
  10.0,
];

/// 每个知识点上限的候选（"自动"是 `null`，交由组卷器按候选分布算）。
const List<int> paperPerKnowledgePointCapOptions = <int>[1, 2, 3, 4, 5];

/// 组卷页。
class QuestionPaperPage extends ConsumerWidget {
  const QuestionPaperPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final subjectOptions = ref.watch(paperSubjectOptionsProvider);
    final plan = ref.watch(paperPlanProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.questionPaperTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(l10n.questionPaperSubtitle),
          const SizedBox(height: 12),
          _PaperControls(subjectOptions: subjectOptions),
          const SizedBox(height: 12),
          plan.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, _) => Text(l10n.questionPaperFailed('$error')),
            data: (plan) =>
                _PaperBody(plan: plan, subjectOptions: subjectOptions),
          ),
        ],
      ),
    );
  }
}

/// 控制区：目标题数 / 学科多选 / 来源下限 / 目标难度 / 每个知识点上限 / 重置。
///
/// 六个控件都只调 `paperSpecProvider.notifier`，重算交给 `paperPlanProvider`
/// （它 `watchDatabaseRevision()` 且跟随 spec），本页不自己算、不自己 invalidate。
class _PaperControls extends ConsumerWidget {
  const _PaperControls({required this.subjectOptions});

  final AsyncValue<List<String>> subjectOptions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final spec = ref.watch(paperSpecProvider);
    final notifier = ref.read(paperSpecProvider.notifier);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<int>(
              initialValue: spec.targetCount,
              decoration: InputDecoration(
                  labelText: l10n.questionPaperTargetCountLabel),
              items: [
                for (final count in paperTargetCountOptions)
                  DropdownMenuItem<int>(
                    value: count,
                    child: Text(l10n.questionPaperCountOption(count)),
                  ),
              ],
              onChanged: (value) {
                if (value != null) notifier.setTargetCount(value);
              },
            ),
            const SizedBox(height: 16),
            Text(l10n.questionPaperSubjectLabel),
            const SizedBox(height: 6),
            subjectOptions.when(
              loading: () => const LinearProgressIndicator(),
              error: (error, _) => Text(l10n.questionPaperFailed('$error')),
              data: (keys) => keys.isEmpty
                  ? Text(l10n.questionPaperSubjectAny)
                  : Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        for (final key in keys)
                          FilterChip(
                            label: Text(subjectLabelOf(l10n, key)),
                            selected: spec.subjectKeys.contains(key),
                            onSelected: (_) => notifier.toggleSubject(key),
                          ),
                      ],
                    ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: spec.minSourceLevel ?? '',
              decoration: InputDecoration(
                  labelText: l10n.questionPaperSourceLevelLabel),
              items: [
                DropdownMenuItem<String>(
                  value: '',
                  child: Text(l10n.questionPaperSourceLevelAny),
                ),
                for (final level in paperMinSourceLevelOptions)
                  DropdownMenuItem<String>(
                    value: level,
                    child: Text(sourceLevelLabel(l10n, level)),
                  ),
              ],
              onChanged: (value) => notifier.setMinSourceLevel(
                value == null || value.isEmpty ? null : value,
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<double>(
              initialValue: spec.targetDifficulty,
              decoration:
                  InputDecoration(labelText: l10n.questionPaperDifficultyLabel),
              items: [
                DropdownMenuItem<double>(
                  value: null,
                  child: Text(l10n.questionPaperDifficultyAny),
                ),
                for (final value in paperTargetDifficultyOptions)
                  DropdownMenuItem<double>(
                    value: value,
                    child: Text(
                      l10n.questionPaperDifficultyOption(
                        value.toStringAsFixed(1),
                      ),
                    ),
                  ),
              ],
              onChanged: notifier.setTargetDifficulty,
            ),
            const SizedBox(height: 4),
            Text(
              l10n.questionPaperDifficultyHint,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              initialValue: spec.perKnowledgePointCap,
              decoration:
                  InputDecoration(labelText: l10n.questionPaperCapLabel),
              items: [
                DropdownMenuItem<int>(
                  value: null,
                  child: Text(l10n.questionPaperCapAuto),
                ),
                for (final cap in paperPerKnowledgePointCapOptions)
                  DropdownMenuItem<int>(
                    value: cap,
                    child: Text(l10n.questionPaperCapOption(cap)),
                  ),
              ],
              onChanged: notifier.setPerKnowledgePointCap,
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: notifier.reset,
                icon: const Icon(Icons.restart_alt),
                label: Text(l10n.questionPaperReset),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 卷面 + 缺口。
class _PaperBody extends ConsumerWidget {
  const _PaperBody({required this.plan, required this.subjectOptions});

  final PaperPlan plan;
  final AsyncValue<List<String>> subjectOptions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final knowledgePointNames = ref.watch(paperKnowledgePointLabelsProvider);

    if (plan.items.isEmpty) {
      // 题库空 vs 条件太窄：用"题库里有没有出现过任何学科"区分，别让两种空态说同一句话。
      final bankEmpty = subjectOptions.maybeWhen(
        data: (keys) => keys.isEmpty,
        orElse: () => false,
      );
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                bankEmpty
                    ? l10n.questionPaperEmptyBank
                    : l10n.questionPaperEmptyPlan,
              ),
              const SizedBox(height: 8),
              _copyButton(
                context,
                l10n,
                knowledgePointNames,
                enabled: false,
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                // 第一个参数是"想要的题数"，第二个是"实际凑到的"：
                // 短卷必须读成"想要 10 道，凑到 2 道"，不能反过来。
                l10n.questionPaperHeadline(
                  plan.requestedCount,
                  plan.items.length,
                ),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            _copyButton(context, l10n, knowledgePointNames, enabled: true),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '${l10n.questionPaperCandidateCount(plan.candidateCount)} · '
          '${l10n.questionPaperOverallNeed(plan.overallNeed.toStringAsFixed(2))}',
        ),
        if (plan.isShort) ...[
          const SizedBox(height: 8),
          Card(
            color: Theme.of(context).colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(l10n.questionPaperShortNotice),
            ),
          ),
        ],
        const SizedBox(height: 12),
        for (var index = 0; index < plan.items.length; index++)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _PaperItemCard(
              index: index + 1,
              item: plan.items[index],
              knowledgePointNames: knowledgePointNames,
            ),
          ),
        if (plan.uncoveredKnowledgePointIds.isNotEmpty)
          _GapSection(
            title: l10n.questionPaperUncoveredTitle,
            body: l10n.questionPaperUncoveredBody,
            ids: plan.uncoveredKnowledgePointIds,
            knowledgePointNames: knowledgePointNames,
          ),
        if (plan.deferredKnowledgePointIds.isNotEmpty)
          _GapSection(
            title: l10n.questionPaperDeferredTitle,
            body: l10n.questionPaperDeferredBody,
            ids: plan.deferredKnowledgePointIds,
            knowledgePointNames: knowledgePointNames,
          ),
      ],
    );
  }

  /// 「复制卷面」按钮。空卷面时**禁用**，而不是复制出一个空壳。
  ///
  /// 选"禁用"而不是"点完弹提示"的理由：空卷是正常状态（题库还空 / 条件太窄），
  /// 卡片里已经写明了是哪种空；禁用比再弹一条提示更安静，而且点不动就绝不会
  /// 往剪贴板里写空文本——空文本粘进 Word 等于把用户剪贴板里原来的东西清掉。
  Widget _copyButton(
    BuildContext context,
    AppLocalizations l10n,
    AsyncValue<Map<String, String>> knowledgePointNames, {
    required bool enabled,
  }) {
    return TextButton.icon(
      onPressed:
          enabled ? () => _copyPaper(context, l10n, knowledgePointNames) : null,
      icon: const Icon(Icons.copy_all_outlined),
      label: Text(l10n.questionPaperCopy),
    );
  }

  /// 把当前卷面写进剪贴板，成功后提示。
  ///
  /// 文本由 [renderPaperText] 生成（纯函数，格式写在那个函数的注释里）；
  /// 这里只负责"写"和"提示"，不重排、不复算分数。
  Future<void> _copyPaper(
    BuildContext context,
    AppLocalizations l10n,
    AsyncValue<Map<String, String>> knowledgePointNames,
  ) async {
    final names = knowledgePointNames.maybeWhen(
      data: (map) => map,
      orElse: () => const <String, String>{},
    );
    final text = renderPaperText(
      l10n: l10n,
      plan: plan,
      knowledgePointNames: names,
    );
    if (text.isEmpty) return; // 兜底：空文本不污染剪贴板。
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.questionPaperCopyDone)),
    );
  }
}

/// 一道题的卡片：序号 + 学科/来源/档位 + 知识点 + 领域层给的三段文案。
class _PaperItemCard extends StatelessWidget {
  const _PaperItemCard({
    required this.index,
    required this.item,
    required this.knowledgePointNames,
  });

  final int index;
  final PaperItem item;
  final AsyncValue<Map<String, String>> knowledgePointNames;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final knowledgePointId = item.knowledgePointId;
    final knowledgePointText = knowledgePointId == null
        ? l10n.questionPaperKnowledgePointNone
        : knowledgePointNameOf(knowledgePointNames, knowledgePointId);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  l10n.questionPaperItemIndex(index),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      _TagChip(label: subjectLabelOf(l10n, item.subjectKey)),
                      _TagChip(label: sourceLevelLabel(l10n, item.sourceLevel)),
                      _TagChip(label: item.zone.labelZh),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
                '${l10n.questionPaperKnowledgePointLabel}：$knowledgePointText'),
            const SizedBox(height: 8),
            _LabelledText(
              label: l10n.questionPaperItemReasonLabel,
              text: item.reasonZh,
            ),
            _LabelledText(
              label: l10n.questionPaperItemImprovementLabel,
              text: item.improvementNote,
            ),
            _LabelledText(
              label: l10n.questionPaperItemBackgroundLabel,
              text: item.backgroundZh,
            ),
          ],
        ),
      ),
    );
  }
}

/// 缺口清单：标题 + 为什么 + 逐个知识点。
class _GapSection extends StatelessWidget {
  const _GapSection({
    required this.title,
    required this.body,
    required this.ids,
    required this.knowledgePointNames,
  });

  final String title;
  final String body;
  final List<String> ids;
  final AsyncValue<Map<String, String>> knowledgePointNames;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(body),
            const SizedBox(height: 8),
            for (final id in ids)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child:
                    Text('• ${knowledgePointNameOf(knowledgePointNames, id)}'),
              ),
          ],
        ),
      ),
    );
  }
}

/// 「标签 + 原文」两行。空字符串不渲染，免得出现一个没有内容的标题。
class _LabelledText extends StatelessWidget {
  const _LabelledText({required this.label, required this.text});

  final String label;
  final String text;

  @override
  Widget build(BuildContext context) {
    if (text.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 2),
          Text(text),
        ],
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(label),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}

/// 学科显示名：词表在 `CapabilityAction.subjectLabelsZh`（与收题页同一份），
/// 空学科键说"未标注学科"，词表里没有的键原样显示（不静默归类）。
String subjectLabelOf(AppLocalizations l10n, String subjectKey) {
  final key = subjectKey.trim();
  if (key.isEmpty) return l10n.questionPaperSubjectNone;
  return CapabilityAction.subjectLabelsZh[key] ?? key;
}

/// 知识点 id → 可读名。名称还没读到（或库里没有这个点）时原样显示 id。
String knowledgePointNameOf(
  AsyncValue<Map<String, String>> names,
  String knowledgePointId,
) {
  return names.maybeWhen(
    data: (map) => map[knowledgePointId] ?? knowledgePointId,
    orElse: () => knowledgePointId,
  );
}

/// 把卷面渲染成可打印的纯文本（「复制卷面」用的就是它；纯函数，便于断言）。
///
/// 格式（稳定，测试按这个断言）：
/// ```
/// 想要 N 道，凑到 M 道          ← questionPaperHeadline(requestedCount, items.length)
///
/// 1. [学科] [来源] [档位]
/// 知识点名
/// 理由：<PaperItem.reasonZh>
/// 提升点：<improvementNote>     ← 非空才写
/// 背景：<backgroundZh>          ← 非空才写
///
/// 未覆盖的知识点：              ← plan 里非空才写
/// • 知识点名
/// 被上限挡下的知识点：
/// • 知识点名
/// ```
///
/// 三条刻意的取舍：
/// * **不放题面/答案**：把答案糊进卷面，对"打印出来拿纸做"是坏事；题面由收题页/
///   详情页负责展示。这里只放"为什么排这道题"。
/// * **不重排、不复算分数**：顺序与分数都是 [PaperPlan] 算好的，这里只做排版；
///   `score`/`components` 也不进文本（裸分数对读者没有意义）。
/// * **缺口如实写**：id 经 `knowledgePointNames` 变成可读名，查不到就原样显示 id，
///   不猜、不隐藏。
String renderPaperText({
  required AppLocalizations l10n,
  required PaperPlan plan,
  required Map<String, String> knowledgePointNames,
}) {
  if (plan.items.isEmpty) return '';

  final buffer = StringBuffer()
    ..writeln(
      // 第一个参数是"要凑几道"，第二个是"实际凑到几道"。
      l10n.questionPaperHeadline(plan.requestedCount, plan.items.length),
    );

  for (var index = 0; index < plan.items.length; index++) {
    final item = plan.items[index];
    final pointId = item.knowledgePointId;
    final pointText = pointId == null
        ? l10n.questionPaperKnowledgePointNone
        : (knowledgePointNames[pointId] ?? pointId);
    buffer
      ..writeln()
      ..writeln(
        '${index + 1}. '
        '[${subjectLabelOf(l10n, item.subjectKey)}] '
        '[${sourceLevelLabel(l10n, item.sourceLevel)}] '
        '[${item.zone.labelZh}]',
      )
      ..writeln(pointText)
      ..writeln('${l10n.questionPaperCopyReasonLabel}：${item.reasonZh}');
    if (item.improvementNote.trim().isNotEmpty) {
      buffer.writeln(
        '${l10n.questionPaperCopyImprovementLabel}：${item.improvementNote}',
      );
    }
    if (item.backgroundZh.trim().isNotEmpty) {
      buffer.writeln(
        '${l10n.questionPaperCopyBackgroundLabel}：${item.backgroundZh}',
      );
    }
  }

  void writeGaps(String heading, List<String> ids) {
    if (ids.isEmpty) return;
    buffer
      ..writeln()
      ..writeln('$heading：');
    for (final id in ids) {
      buffer.writeln('• ${knowledgePointNames[id] ?? id}');
    }
  }

  writeGaps(
    l10n.questionPaperCopyUncoveredHeading,
    plan.uncoveredKnowledgePointIds,
  );
  writeGaps(
    l10n.questionPaperCopyDeferredHeading,
    plan.deferredKnowledgePointIds,
  );

  return buffer.toString().trimRight();
}
