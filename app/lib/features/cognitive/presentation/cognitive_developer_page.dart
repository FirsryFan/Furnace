/// 开发者信息页：认知模型的原始读数（task-103 从用户层搬出来）。
///
/// 用户反馈「认知模型/MindNet 太复杂」：模型 id、R0/Gain/Σ、band/zone、每张卡的
/// due/interval/suggested、calibration、orphan、fast layer、prior count、机制参数
/// 这些**开发者字段**不该占主界面。它们整页搬到这里，唯一入口是设置页
/// 开发者分区里的「开发者信息（只读）」；用户层只到顶层「学习状态」模块
/// （设置页不再放认知模型原页，task-113）。
///
/// 页面仍然只读：所有卡片读的都是 `select`；唯一会写库的是「清掉失效卡片状态」
/// 的孤儿修复，那是一个显式按钮，和以前一样。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/repository_providers.dart';
import '../../../domain/services/cognitive/learning_metrics.dart';
import '../../../domain/services/cognitive/metacognition.dart';
import '../../../domain/services/cognitive/user_persona.dart';
import '../../../domain/services/reasoning/capability_profile.dart';
import '../../../l10n/app_localizations.dart';
import '../../anki/application/review_advisory.dart';
import '../../assessment/presentation/assessment_page.dart';
import '../../questions/application/capability_profile_provider.dart';
import '../../questions/presentation/capability_action_questions_page.dart';
import '../application/leaf_preset_matrix_provider.dart';
import '../application/preset_matrix_provider.dart';
import '../../settings/application/user_persona_provider.dart';
import '../../settings/presentation/user_persona_page.dart';
import 'cognitive_graph_page.dart';
import 'cognitive_model_page.dart';
import 'mechanism_page.dart';

/// 设置页「开发者信息」入口（用户层的「认知模型页底部链接」在 task-113
/// 随原页一起删除，设置页开发者分区是唯一入口）。
const Key settingsCognitiveDeveloperTileKey =
    Key('settings-cognitive-developer-tile');

/// 开发者字段那个「自我描述」卡片（task-187 原在认知模型页顶部）。
const Key cognitiveModelPersonaCardKey = Key('cognitive-model-persona-card');

/// 开发者/审计视图：原「认知模型」页的全部原始读数。
class CognitiveDeveloperPage extends ConsumerWidget {
  const CognitiveDeveloperPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final readings = ref.watch(cognitiveReadingsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.mindnetDeveloperInfoTitle),
        actions: <Widget>[
          IconButton(
            tooltip: l10n.mechanismPanelOpen,
            icon: const Icon(Icons.tune),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const MechanismPage(),
              ),
            ),
          ),
        ],
      ),
      body: readings.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _ErrorNote(l10n: l10n, error: error),
        data: (data) => ListView(
          padding: const EdgeInsets.all(12),
          children: [
            _AssessmentEntry(l10n: l10n),
            const SizedBox(height: 8),
            _Notes(
              l10n: l10n,
              fastLayerRan: data.fastLayerRan,
              priorCount: data.priorCount,
            ),
            const SizedBox(height: 8),
            const _PresetMatrixCard(),
            const SizedBox(height: 8),
            const _LeafPresetMatrixCard(),
            const SizedBox(height: 8),
            const _PersonaCard(),
            const SizedBox(height: 8),
            const _GraphEntryCard(),
            const SizedBox(height: 8),
            const _OrphanRepairBanner(),
            _Summary(l10n: l10n, readings: data),
            if (data.fastLayerRan)
              _Metacognition(l10n: l10n, reading: data.metacognition),
            const _LearningMetricsSection(),
            const _CapabilityProfileSection(),
            const SizedBox(height: 8),
            if (data.cards.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  l10n.cognitiveEmpty,
                  textAlign: TextAlign.center,
                ),
              )
            else
              for (final card in data.cards) _CardTile(l10n: l10n, card: card),
          ],
        ),
      ),
    );
  }
}

/// MindNet 预设矩阵 seed 的只读摘要。
///
/// 只显示数据层可核对的事实：多少 measured、哪些预设档、preset_global 不是实测。
class _PresetMatrixCard extends ConsumerWidget {
  const _PresetMatrixCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final seed = ref.watch(presetMatrixSeedProvider);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: seed.when(
          loading: () => const Text('矩阵 seed：读取中…'),
          error: (error, _) => Text('矩阵 seed 读取失败：$error'),
          data: (data) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <String>[
              '矩阵 seed（只读）',
              '实测单元：${data.measuredCount}',
              '预设档：${data.presetGlobalMean.keys.join(" / ")}',
              'preset_global 是全局先验，不是逐知识点实测；其余仍为 unknown。',
            ]
                .map((line) => Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(line),
                    ))
                .toList(),
          ),
        ),
      ),
    );
  }
}

/// The way out of "every number here is a default": one short measurement.
///
/// It sits above the notes because the page's own disclaimers are about what
/// the model does *not* know yet, and this is the only action that changes that
/// - a user who reads "weights are uncalibrated" and has nowhere to go learns
/// nothing. The page stays select-only: the write happens on the assessment
/// page, behind an explicit tap.
class _AssessmentEntry extends StatelessWidget {
  const _AssessmentEntry({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.assessmentTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const AssessmentPage(),
                ),
              ),
              icon: const Icon(Icons.assignment_outlined),
              label: Text(l10n.assessmentEntryAction),
            ),
          ],
        ),
      ),
    );
  }
}

/// The repair path for card states whose flashcard is already gone.
///
/// Those rows were written by an older, incomplete cascade; they can never be
/// reviewed, so the page reports how many there are and offers to remove them
/// instead of drawing them as nameless cards. The action is explicit on
/// purpose: a silent cleanup on load would be a data change behind the user's
/// back, on a page that otherwise promises to be read-only.
class _OrphanRepairBanner extends ConsumerWidget {
  const _OrphanRepairBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final count = ref.watch(orphanCardStateCountProvider).valueOrNull ?? 0;
    if (count == 0) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final onContainer = theme.colorScheme.onErrorContainer;
    return Card(
      color: theme.colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.cleaning_services_outlined, color: onContainer),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.cognitiveOrphanTitle(count),
                    style: theme.textTheme.titleSmall
                        ?.copyWith(color: onContainer),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              l10n.cognitiveOrphanDetail,
              style: theme.textTheme.bodySmall?.copyWith(color: onContainer),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () async {
                  final removed = await ref
                      .read(ankiRepositoryProvider)
                      .purgeOrphanKnowledgeRows();
                  ref.invalidate(orphanCardStateCountProvider);
                  ref.invalidate(cognitiveObservationInputsProvider);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(l10n.cognitiveOrphanDone(removed)),
                      ),
                    );
                  }
                },
                child: Text(l10n.cognitiveOrphanAction(count)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// What the numbers are *allowed* to mean. Rendered above the list on purpose:
/// a user who reads only the first screen must not conclude that the model
/// 图的入口：读数页是"一列数字"，网络图是"同一批数字的另一种画法"。
///
/// **开发者旧功能（2026-11-17 学习状态清理）**：用户学习状态页的「知识网络图」
/// 入口已删除；这张旧 MindNet 视图只从这里（设置 → 开发者信息）进入。它不是
/// 用户学习状态的读数来源，页面上的档位/强弱项也不再依赖它。
///
/// 只读是两页共同的承诺；这里只给一条能走到的路（用户反馈"希望有一个可视化的界面"）。
class _GraphEntryCard extends StatelessWidget {
  const _GraphEntryCard();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: const Icon(Icons.hub_outlined),
        title: Text(l10n.cognitiveGraphTitle),
        subtitle: Text(l10n.cognitiveGraphHint),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const CognitiveGraphPage(),
          ),
        ),
      ),
    );
  }
}

/// 自我描述卡片：用户不用翻到设置页也能看到 AI 对话会带上的那段背景。
///
/// 页面本身仍然只读：卡片只展示预览，「编辑」跳到和设置入口同一个
/// [UserPersonaPage]，写库只发生在那一页。
class _PersonaCard extends ConsumerWidget {
  const _PersonaCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final persona = ref.watch(userPersonaProvider).valueOrNull;
    final hasPersona = userPersonaIsPresent(persona);
    return Card(
      key: cognitiveModelPersonaCardKey,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.badge_outlined, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.personaTitle,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              hasPersona
                  ? userPersonaPreview(persona, maxChars: 160)
                  : l10n.personaEmpty,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const UserPersonaPage(),
                  ),
                ),
                child: Text(l10n.commonEdit),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// schedules reviews or that its weights are calibrated.
class _Notes extends StatelessWidget {
  const _Notes({
    required this.l10n,
    required this.fastLayerRan,
    required this.priorCount,
  });

  final AppLocalizations l10n;

  /// Whether the tierB run happened. The note says which, because the page now
  /// runs it - a "the page never diagnoses" sentence would be a lie.
  final bool fastLayerRan;

  /// How many cards are currently showing a measurement prior as their starting
  /// point (M1d). Zero is a fact worth stating: it tells the user the numbers on
  /// this page are all defaults or observations, and the measurement page is one
  /// tap away.
  final int priorCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _NoteRow(
              icon: Icons.insights_outlined,
              title: l10n.cognitiveAdvisorMode,
              detail: l10n.cognitiveAdvisorModeDetail,
              emphasis: theme.colorScheme.primary,
            ),
            const SizedBox(height: 8),
            _NoteRow(
              icon: Icons.warning_amber_outlined,
              title: l10n.cognitiveUncalibratedWeights,
              detail: l10n.cognitiveUncalibratedWeightsDetail,
              emphasis: theme.colorScheme.error,
            ),
            const SizedBox(height: 8),
            _NoteRow(
              icon: Icons.lock_outline,
              title: l10n.cognitiveReadOnlyNote,
              detail: l10n.cognitiveZoneNote,
              emphasis: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 8),
            _NoteRow(
              icon: Icons.travel_explore_outlined,
              title: l10n.cognitiveFastLayerNote,
              detail: fastLayerRan
                  ? l10n.cognitiveFastLayerRanDetail
                  : l10n.cognitiveFastLayerNotRunDetail,
              emphasis: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 8),
            _NoteRow(
              icon: Icons.psychology_outlined,
              title: l10n.cognitiveZoneDanger,
              detail: l10n.cognitiveDangerNote,
              emphasis: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 8),
            _NoteRow(
              icon: Icons.assignment_turned_in_outlined,
              title: l10n.cognitivePriorNote,
              detail: priorCount > 0
                  ? l10n.cognitivePriorCount(priorCount)
                  : l10n.cognitivePriorNone,
              emphasis: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

/// The metacognition layer's read, shown as named lists rather than a chart.
///
/// This is the only block on the page that puts two different quantities side by
/// side - what the model believes (belief) against what the cards can actually
/// do (retrievability) - so a single number would hide the point. The names and
/// the gap threshold come from [MetacognitionReading]; this widget rounds
/// nothing and decides nothing.
///
/// It renders only when the tierB run happened, because danger and
/// underestimation are statements *about a run*: without one there is nothing to
/// compare, and drawing the empty list would read as "no problem".
class _Metacognition extends StatelessWidget {
  const _Metacognition({required this.l10n, required this.reading});

  final AppLocalizations l10n;
  final MetacognitionReading reading;

  /// ' · ' rather than a locale comma: the same separator reads correctly in
  /// both languages, so this widget does not have to branch on locale.
  static String _names(List<MetacognitionRow> rows) =>
      [for (final row in rows) row.name].join(' · ');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.psychology_outlined,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.cognitiveMetacognitionTitle,
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(l10n.cognitiveMetacognitionDetail, style: subtle),
              const SizedBox(height: 8),
              if (!reading.hasRows)
                Text(l10n.cognitiveMetacognitionNoRows, style: subtle)
              else ...[
                Text(
                  l10n.cognitiveMetacognitionCalibration(
                    reading.calibration.toStringAsFixed(3),
                  ),
                  style: subtle,
                ),
                if (reading.danger.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    l10n.cognitiveMetacognitionDanger(_names(reading.danger)),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ],
                if (reading.anxiety.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    l10n.cognitiveMetacognitionAnxiety(_names(reading.anxiety)),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.tertiary,
                    ),
                  ),
                ],
                if (reading.danger.isEmpty && reading.anxiety.isEmpty) ...[
                  const SizedBox(height: 6),
                  Text(l10n.cognitiveMetacognitionLevel, style: subtle),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// "学得到底怎么样"——M6 的留存率与校准度。
///
/// 这一块是整页唯一一个**不看成模型自己的读数**的卡片：数字全部来自复习日志，
/// 所以它是模型的考官，而不是模型的自我介绍。校准那一半在没有带预测的复习时
/// 明说没有，而不是画一条由假设拼出来的曲线。
class _LearningMetricsSection extends ConsumerWidget {
  const _LearningMetricsSection();

  static String _days(double value) => value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toStringAsFixed(1);

  static String _range(RetentionBucket bucket) => bucket.hiDays.isFinite
      ? '${_days(bucket.loDays)}–${_days(bucket.hiDays)}'
      : '${_days(bucket.loDays)}+';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final subtle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final metrics = ref.watch(learningMetricsProvider);

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.insights_outlined,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.learningMetricsTitle,
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(l10n.learningMetricsDetail, style: subtle),
              const SizedBox(height: 8),
              if (metrics.isLoading)
                const SizedBox(
                  height: 16,
                  child: Center(
                    child: SizedBox(
                      height: 14,
                      width: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              else if (metrics.hasError)
                Text(l10n.learningMetricsUnavailable, style: subtle)
              else
                ..._body(l10n, theme, subtle, metrics.requireValue),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _body(
    AppLocalizations l10n,
    ThemeData theme,
    TextStyle? subtle,
    LearningMetrics data,
  ) {
    if (data.isEmpty) {
      return [Text(l10n.learningMetricsEmpty, style: subtle)];
    }

    final retained = (data.retention * 100).round();
    final shown = [
      for (final b in data.buckets)
        if (b.samples > 0) b
    ];
    return [
      Text(
        l10n.learningMetricsOverall(data.reviewedCount, retained),
        style: theme.textTheme.bodyMedium,
      ),
      const SizedBox(height: 6),
      if (shown.isEmpty)
        Text(l10n.learningMetricsNoBuckets, style: subtle)
      else
        for (final bucket in shown)
          Text(
            l10n.learningMetricsBucket(
              _range(bucket),
              bucket.samples,
              (bucket.retention * 100).round(),
            ),
            style: subtle,
          ),
      const SizedBox(height: 6),
      // 有预测样本才谈校准；否则这句话就是"这一版之前根本没记过预测"，
      // 与"模型很准"（brier 0）必须能被区分开。
      Text(
        data.hasCalibration
            ? l10n.learningMetricsCalibration(
                data.brier!.toStringAsFixed(3),
                data.ece!.toStringAsFixed(3),
              )
            : l10n.learningMetricsNoCalibration,
        style: subtle,
      ),
    ];
  }
}

/// 能力动作画像（推理层读数）：把已入库解题链的步骤按「跨学科动作」聚一遍。
///
/// 与学习度量并排的理由：两者都是**从派生数据里读出来的我**（记忆层读保留率、
/// 推理层读"卡在哪个动作"）。聚合与排序在 `capability_profile.dart`（纯逻辑），
/// 这里只负责渲染与"没有样本就说没有"。
class _CapabilityProfileSection extends ConsumerWidget {
  const _CapabilityProfileSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final subtle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final profile = ref.watch(capabilityProfileProvider);

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.account_tree_outlined,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.capabilityProfileTitle,
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(l10n.capabilityProfileDetail, style: subtle),
              const SizedBox(height: 8),
              if (profile.isLoading)
                const SizedBox(
                  height: 16,
                  child: Center(
                    child: SizedBox(
                      height: 14,
                      width: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              else if (profile.hasError)
                Text(l10n.capabilityProfileUnavailable, style: subtle)
              else
                ..._body(context, l10n, theme, subtle, profile.requireValue),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _body(
    BuildContext context,
    AppLocalizations l10n,
    ThemeData theme,
    TextStyle? subtle,
    List<CapabilityReading> readings,
  ) {
    if (readings.isEmpty) {
      return [Text(l10n.capabilityProfileEmpty, style: subtle)];
    }
    return [
      // 每一行都能点开：动作 → 哪些题练到这个动作（「按能力动作找题」页）。
      // 画像只回答"该练哪个"，点开才回答"练哪几道"。
      for (final reading in readings)
        InkWell(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => CapabilityActionQuestionsPage(
                actionType: reading.actionType,
              ),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.capabilityProfileRow(
                      reading.label,
                      reading.stepCount,
                      reading.riskyStepCount,
                      reading.avgStuckRisk == null
                          ? l10n.capabilityProfileNoRisk
                          : reading.avgStuckRisk!.toStringAsFixed(2),
                    ),
                    style: subtle,
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      if (readings.any((reading) => !reading.known))
        Text(l10n.capabilityProfileUnknownNote, style: subtle),
    ];
  }
}

class _NoteRow extends StatelessWidget {
  const _NoteRow({
    required this.icon,
    required this.title,
    required this.detail,
    required this.emphasis,
  });

  final IconData icon;
  final String title;
  final String detail;
  final Color emphasis;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: emphasis),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(color: emphasis),
              ),
              Text(detail, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ],
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.l10n, required this.readings});

  final AppLocalizations l10n;
  final CognitiveReadings readings;

  @override
  Widget build(BuildContext context) {
    final meanR = readings.meanR;
    final bands = [
      for (final band in ReviewBand.values)
        if ((readings.bandCounts[band] ?? 0) > 0)
          '${bandLabel(l10n, band)} ${readings.bandCounts[band]}',
    ].join(' · ');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.cognitiveSummary(readings.cardCount, readings.modelId),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            Text(l10n.cognitiveSummaryBands(bands)),
            Text(l10n.cognitiveReadAt(readings.nowUtc.toLocal().toString())),
            Text(
              l10n.cognitiveSummaryNumbers(
                readings.newCount,
                meanR == null ? '—' : meanR.toStringAsFixed(3),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CardTile extends StatelessWidget {
  const _CardTile({required this.l10n, required this.card});

  final AppLocalizations l10n;
  final CognitiveCardReading card;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = card.knowledgePointTitle.isEmpty
        ? card.cardStateId
        : card.knowledgePointTitle;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleSmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _Chip(
                  text: card.isNew
                      ? l10n.cognitiveNewCard
                      : l10n.cognitiveSeenCard,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              l10n.cognitiveCardId(card.cardStateId),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                _Chip(
                  text: l10n.cognitiveRetrievability(
                    card.r.toStringAsFixed(3),
                  ),
                ),
                _Chip(text: l10n.cognitiveGain(card.gain.toStringAsFixed(3))),
                _Chip(
                  text: card.r0FromPrior
                      ? l10n.cognitiveEncodingPrior(
                          card.displayedR0.toStringAsFixed(2),
                        )
                      : l10n.cognitiveEncoding(
                          card.displayedR0.toStringAsFixed(2)),
                ),
                _Chip(
                  text: l10n.cognitiveSavings(card.sigma.toStringAsFixed(2)),
                ),
                _Chip(text: l10n.cognitiveTags(card.tagCount)),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${l10n.cognitiveColumnBand}: ${bandLabel(l10n, card.band)}'
              '${card.band == ReviewBand.boosted ? ' ×${card.boostFactor.toStringAsFixed(1)}' : ''}',
              style: theme.textTheme.bodyMedium,
            ),
            Text(
              '${l10n.cognitiveColumnZone}: ${zoneLabel(l10n, card.zone)}',
              style: theme.textTheme.bodyMedium,
            ),
            Text(
              '${l10n.cognitiveColumnSchedule}: '
              '${_scheduleText(l10n, card)}',
              style: theme.textTheme.bodyMedium,
            ),
            if (!card.scoreUsedForOrdering && !card.isNew)
              Text(
                l10n.cognitiveGainNotUsed,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            if (card.isNew)
              Text(
                l10n.cognitiveNewCardNotOrdered,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
          ],
        ),
      ),
    );
  }

  String _scheduleText(AppLocalizations l10n, CognitiveCardReading card) {
    final due = card.dueAt == null
        ? l10n.cognitiveNoSchedule
        : DateTime.fromMillisecondsSinceEpoch(card.dueAt!).toLocal().toString();
    return '${l10n.cognitiveDue(due)} · '
        '${l10n.cognitiveInterval(card.intervalDays.toStringAsFixed(1))} · '
        '${l10n.cognitiveSuggestedInterval(card.suggestedIntervalDays)}';
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(text, style: Theme.of(context).textTheme.bodySmall),
    );
  }
}

class _ErrorNote extends StatelessWidget {
  const _ErrorNote({required this.l10n, required this.error});

  final AppLocalizations l10n;
  final Object error;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(l10n.cognitiveErrorTitle),
          const SizedBox(height: 8),
          Text('$error', style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

/// 逐知识点预设矩阵 seed 的只读摘要。
class _LeafPresetMatrixCard extends ConsumerWidget {
  const _LeafPresetMatrixCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final seed = ref.watch(leafPresetMatrixProvider);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: seed.when(
          loading: () => const Text('逐点矩阵 seed：读取中…'),
          error: (error, _) => Text('逐点矩阵 seed 读取失败：$error'),
          data: (data) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <String>[
              '逐点矩阵 seed（只读）',
              '节点：${data.nodeCount}',
              '单元：${data.cellCount}',
              '预设档：${data.bands.join(" / ")}',
              '能力项：${data.abilityCodes.join(" / ")}',
              '全部 preset_global，n_obs=0；不是逐点实测，也未接学习状态。',
            ]
                .map((line) => Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(line),
                    ))
                .toList(),
          ),
        ),
      ),
    );
  }
}
