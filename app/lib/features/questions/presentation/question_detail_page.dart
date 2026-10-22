/// 题目详情页：一道题的完整视图 + 推理管道的入口与可读展示。
///
/// 三件事按顺序摊在一页上：
///
///  1. **题目现状**：题干、选项（标出正确答案）、答案、解析、来源/年份/难度。
///  2. **AI 解题**：按一下调 `QuestionReasoningService.solveAndDecompose`，
///     模型给的分步思维链当场展示，并（默认）落进 `reasoning_chains` /
///     `reasoning_steps`——链是派生数据，同一道题可以有多条，互不覆盖。
///  3. **卡点评估**：`StuckPointEvaluator` 把「模型判断的风险」和「你自己的记忆
///     状态读数」等权融合，逐步给建议。评估结果**不进数据库**：它是"此刻的看法"，
///     不是事实；链才是事实。
///
/// 两条本页坚持的诚实性规则：
///
///  * **失败面照样展示**：模型没配好、回复不合契约、题目 id 不存在，都显示
///    `failureReason` 与已收到的 `rawReply`，不弹一个"出错了"就吞掉。
///  * **没有状态数据要说出来**：`unmatchedHints` 是"本地没有你的读数"，不是
///    "这一步没问题"。两者在界面上的差别必须看得见。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/database.dart';
import '../../../data/media/image_size.dart';
import '../../../data/repositories/question_repository.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../domain/services/cognitive/cognitive_model.dart';
import '../../../domain/services/paper/similar_questions.dart';
import '../../../domain/services/questions/question_source.dart';
import '../../../domain/services/questions/question_stem_image_plan.dart';
import '../../../domain/services/reasoning/capability_action.dart';
import '../../../domain/services/reasoning/reasoning_prompt.dart';
import '../../../domain/services/reasoning/stuck_point_evaluator.dart';
import '../../../domain/services/srs/dsr_memory.dart';
import '../../../l10n/app_localizations.dart';
import '../application/question_reasoning_service.dart';
import '../application/similar_question_provider.dart';
import 'question_audit_view.dart';
import 'question_detail_providers.dart';
import 'question_intake_page.dart';
import 'question_media_view.dart';
import 'question_source_edit_dialog.dart';
import 'question_title_dialog.dart';
import 'question_vocab_labels.dart';
import 'question_zujuan_search.dart';

/// 复制「原题链接」按钮的 key（测试定位用）。
const Key questionSourceCopyButtonKey = Key('question-source-copy');

/// 详情页只吃一个 id：其余全部现读，页面上任何东西都不是调用方传进来的快照。
class QuestionDetailPage extends ConsumerStatefulWidget {
  const QuestionDetailPage({super.key, required this.questionId});

  final String questionId;

  @override
  ConsumerState<QuestionDetailPage> createState() => _QuestionDetailPageState();
}

class _QuestionDetailPageState extends ConsumerState<QuestionDetailPage> {
  bool _running = false;

  /// 本次按下按钮的结果。`null` = 这次进来还没按过——于是页面只显示库里那条链。
  ReasoningRunResult? _lastRun;

  Future<void> _solve() async {
    if (_running) {
      return;
    }
    setState(() {
      _running = true;
      _lastRun = null;
    });
    final result = await ref
        .read(questionReasoningServiceProvider)
        .solveAndDecompose(widget.questionId);
    if (!mounted) {
      return;
    }
    setState(() {
      _running = false;
      _lastRun = result;
    });
  }

  /// 改原题链接：加 / 改 / 清空都在对话框里完成（对话框自己 invalidate 详情）。
  Future<void> _editSourceLinks(Question question) async {
    await showQuestionSourceEditDialog(context, question: question);
  }

  /// 改题名：对话框自己写库并 invalidate 题库总览 / 本题详情（同一套逻辑也在
  /// 题库列表的 ⋮ 菜单里用）。这里不重复写库，也不重复 invalidate。
  Future<void> _editTitle(Question question) async {
    await showQuestionTitleDialog(
      context,
      questionId: question.id,
      stem: question.stem,
      currentTitle: question.title,
      subjectKey: question.subjectKey,
      questionType: question.questionType,
    );
  }

  /// 改来源：只动"来源元信息"四列（题干与答案一个字不改）。
  ///
  /// 题目进来时的来源分级常常是 `unknown`（粘贴时没标、拍照读不出），事后知道了
  /// "这是 2024 湖南师大附中的月考"，得有个地方改 —— 不然 `aiQuality`/排序的权重
  /// 一直按"未标注"算。
  Future<void> _editSource(Question question) async {
    final edited = await showDialog<
        ({String level, String label, int? year, String? region})>(
      context: context,
      builder: (_) => _EditSourceDialog(question: question),
    );
    if (edited == null || !mounted) {
      return;
    }
    try {
      await ref.read(questionRepositoryProvider).updateSource(
            question.id,
            sourceLevel: edited.level,
            sourceLabel: edited.label,
            year: edited.year,
            region: edited.region,
          );
      // 保存完立刻重读：不把"屏幕上已经变了"寄望于全局写拦截器（测试里不装它，
      // 而且这一页本来就该在「我按了保存」之后自己刷新）。
      ref.invalidate(questionDetailProvider(question.id));
    } on ArgumentError catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('${error.message}')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final detailAsync = ref.watch(questionDetailProvider(widget.questionId));
    final detail = detailAsync.valueOrNull;
    final missing = detailAsync.hasValue && detail == null;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.questionDetailTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (detailAsync.isLoading && !detailAsync.hasValue)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: LinearProgressIndicator(),
            )
          else if (detailAsync.hasError)
            Text('${detailAsync.error}')
          else if (missing)
            Text(l10n.questionDetailQuestionMissing)
          else if (detail != null)
            _QuestionBody(
              detail: detail,
              onEditTitle: () => _editTitle(detail.question),
              onEditSource: () => _editSource(detail.question),
              onEditSourceLinks: () => _editSourceLinks(detail.question),
            ),
          // 组卷网入口紧贴题面（题干/配图）下方：候选为空时它自己是零高度。
          if (detail != null)
            QuestionZujuanSearchButton(stem: detail.question.stem),
          // 入库体检：只报不改；体检没跑出来/失败时整块零高度，不挡下面的解题入口。
          if (detail != null)
            QuestionAuditSection(questionId: widget.questionId),
          const SizedBox(height: 16),
          _ReasoningSection(
            questionId: widget.questionId,
            running: _running,
            lastRun: _lastRun,
            enabled: detail != null,
            onSolve: _solve,
          ),
          const SizedBox(height: 16),
          _SimilarQuestionsSection(questionId: widget.questionId),
        ],
      ),
    );
  }
}

/// 题目本身：题干、选项、答案、解析、来源与质量。
///
/// 不再套卡片底座：题干、图片、选项、答案直接铺在页面背景上，靠小节标题、
/// 间距和细分隔线分段（需求原文：「很多文字不需要放在一个卡片底座上」）。
class _QuestionBody extends StatelessWidget {
  const _QuestionBody({
    required this.detail,
    this.onEditTitle,
    this.onEditSource,
    this.onEditSourceLinks,
  });

  final QuestionDetail detail;

  /// 「改题名」（可空：没给缝就不摆这个按钮）。题名是自己起的标签，不是题干。
  final VoidCallback? onEditTitle;

  /// 「改来源」（可空：没给缝就不摆这个按钮 —— 与页面上别的可注入动作同一个做法）。
  final VoidCallback? onEditSource;

  /// 「改原题链接」：加/改/清空都走同一个对话框；没有可信链接时也留入口。
  final VoidCallback? onEditSourceLinks;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final question = detail.question;

    // 「点回去核对原题」只认可信的绝对 http(s) 链接，或组卷网两个数字 id；
    // 别的（相对路径、javascript: 之类）一律当作没有来源（question_source.dart）。
    final source = questionSourceFor(
      sourceUrl: question.sourceUrl,
      zujuanQuestionId: question.zujuanQuestionId,
      zujuanBankId: question.zujuanBankId,
    );

    final meta = <String>[
      question.subjectKey.trim().isEmpty
          ? l10n.questionIntakeSubjectNone
          : CapabilityAction.subjectLabelsZh[question.subjectKey] ??
              question.subjectKey,
      sourceLevelLabel(l10n, question.sourceLevel),
      stateLabel(l10n, question.state),
      _originLabel(l10n, question.origin),
      if (question.year != null) l10n.questionDetailYear(question.year!),
      if (question.region != null && question.region!.trim().isNotEmpty)
        question.region!.trim(),
    ];

    final answer = question.answer?.trim() ?? '';
    final solution = question.solution?.trim() ?? '';
    final trapNote = question.trapNote?.trim() ?? '';
    // 题名是用户自己起的扫描标签：没起名就明确显示「未命名」，不拿题干冒充。
    final title = (question.title ?? '').trim();
    final hasTitle = title.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            QuestionSerialBadge(serialNo: question.serialNo),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    hasTitle ? title : l10n.questionTitleUntitled,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: hasTitle
                        ? theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          )
                        : theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    meta.join(' · '),
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            if (onEditTitle != null)
              IconButton(
                key: questionTitleEditButtonKey,
                tooltip: l10n.questionTitleEditTooltip,
                onPressed: onEditTitle,
                icon: const Icon(Icons.edit_outlined, size: 18),
                visualDensity: VisualDensity.compact,
              ),
            // 「改来源」：来源分级/来源说明/年份/地区都是"事后也可能知道"的
            // 元信息，题干与答案不动。
            if (onEditSource != null)
              TextButton.icon(
                onPressed: onEditSource,
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: Text(l10n.questionDetailEditSource),
              ),
          ],
        ),
        // 来源行自己有顶部 8 间距；没有可信链接时不给来源名，但仍留一个
        // 低权重「添加原题链接」入口（用户手里可能有链接，只是还没入库）。
        if (source != null)
          _QuestionSourceLine(
            source: source,
            onEditSourceLinks: onEditSourceLinks,
          )
        else if (onEditSourceLinks != null)
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: TextButton.icon(
                key: questionSourceEditButtonKey,
                onPressed: onEditSourceLinks,
                icon: const Icon(Icons.add_link, size: 16),
                label: Text(l10n.questionSourceAdd),
              ),
            ),
          ),
        const SizedBox(height: 12),
        // 题干与题干配图混排：文字段/图片段按「［图1］」占位拆分，
        // 没被占位引用的图接在题干文字末尾（见 question_stem_segments.dart）。
        _QuestionStemView(
          questionId: question.id,
          stem: question.stem,
        ),
        if (question.difficulty != null) ...[
          const SizedBox(height: 4),
          Text(
            l10n.questionDetailDifficulty(_number(question.difficulty!)),
            style: theme.textTheme.bodySmall,
          ),
        ],
        if (detail.options.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            l10n.questionIntakeOptionsLabel,
            style: theme.textTheme.titleSmall,
          ),
          for (final option in detail.options)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 选项标签加粗、内容走公式渲染（$…$ 会排成数学）。
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Text(
                      '${option.label}.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Expanded(
                    child: QuestionRichText(text: option.content),
                  ),
                  if (option.isCorrect)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Text(
                        l10n.questionDetailCorrectOption,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
        if (answer.isNotEmpty) ...[
          const SizedBox(height: 16),
          _LabelledText(
            label: l10n.questionIntakeAnswerLabel,
            value: answer,
          ),
          // 答案截图紧跟答案段：组卷网登录后才看得到的整张答案图，
          // 和题干配图分开存、也分开显示。
          const SizedBox(height: 8),
          QuestionImagesSection(
            questionId: question.id,
            editable: true,
            kind: QuestionImagesSectionKind.answer,
          ),
        ],
        if (solution.isNotEmpty)
          _LabelledText(
            label: l10n.questionIntakeSolutionLabel,
            value: solution,
          ),
        if (trapNote.isNotEmpty)
          _LabelledText(
            label: l10n.questionDetailTrapNote,
            value: trapNote,
          ),
        if (answer.isEmpty) ...[
          // 没有文字答案时也不藏编辑入口：不是每道题都有现成答案，
          // 用户可能先只截了一张答案图。
          const SizedBox(height: 8),
          QuestionImagesSection(
            questionId: question.id,
            editable: true,
            kind: QuestionImagesSectionKind.answer,
          ),
        ],
        if (question.aiQuality != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              l10n.questionDetailAiQuality(_number(question.aiQuality!)),
              style: theme.textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}

/// 题干 + 题干配图的渲染流。
///
/// 摆法由 [planQuestionStemRender] 决定：普通题的图按「［图1］」占位内联，
/// 没被占位引用的图接在题干末尾；整卡截图（尺寸够大的一张整题图，或 1 图 +
/// 多个占位却拿不到尺寸）不内联——正文里的占位变成「…」，图统一放到正文
/// 末尾、前面加一行「原题整图」小标题，避免一张巨图插在正文中间。
///
/// 图片数据没加载出来时先按「没有图」渲染文字，加载完成后同一位置重建；
/// 个别图读不出来只会少一张图，不会抛。
class _QuestionStemView extends ConsumerWidget {
  const _QuestionStemView({required this.questionId, required this.stem});

  final String questionId;
  final String stem;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final images = ref.watch(questionImagesProvider(questionId)).valueOrNull;

    // 逐图读像素尺寸：字节还没回来 / 头部解析失败都填 null，交给 plan 兜底。
    final imageSizes = <QuestionStemImageSize?>[];
    if (images != null) {
      for (final image in images) {
        final bytes =
            ref.watch(questionImageBytesProvider(image.relPath)).valueOrNull;
        final size = bytes == null ? null : readImageSize(bytes);
        imageSizes.add(
          size == null || !size.isValid
              ? null
              : QuestionStemImageSize(size.width, size.height),
        );
      }
    }

    final plan = planQuestionStemRender(
      stem,
      imageCount: images?.length ?? 0,
      imageSizes: imageSizes,
    );

    Widget imageAt(int order) {
      final list = images;
      if (list == null || order < 0 || order >= list.length) {
        return const SizedBox.shrink();
      }
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: QuestionInlineImage(
          questionId: questionId,
          image: list[order],
          editable: true,
        ),
      );
    }

    return Column(
      key: questionStemImagesKey,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final segment in plan.segments)
          if (segment.isText)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: QuestionRichText(
                text: segment.text,
                style: theme.textTheme.titleMedium,
              ),
            )
          else
            imageAt(segment.imageOrder ?? -1),
        if (plan.isSnapshot && plan.hasTrailingImages)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(
              l10n.questionDetailOriginalCardImage,
              style: theme.textTheme.titleSmall,
            ),
          ),
        for (final order in plan.trailingImageOrders) imageAt(order),
        // 末尾一行只留「添加配图 + 已加 N 张」，图片本身已经混排在上面。
        QuestionImagesSection(
          questionId: questionId,
          editable: true,
          showImages: false,
        ),
      ],
    );
  }
}

/// 推理管道区块：按钮 + 失败面 + 链与卡点评估。
class _ReasoningSection extends ConsumerWidget {
  const _ReasoningSection({
    required this.questionId,
    required this.running,
    required this.lastRun,
    required this.enabled,
    required this.onSolve,
  });

  final String questionId;
  final bool running;
  final ReasoningRunResult? lastRun;
  final bool enabled;
  final Future<void> Function() onSolve;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    final stored =
        ref.watch(questionStoredChainProvider(questionId)).valueOrNull;
    final statesAsync = ref.watch(questionKnowledgeStatesProvider);
    final knowledgePointIds =
        ref.watch(questionKnowledgePointIdsProvider(questionId)).valueOrNull ??
            const <String>[];

    // 本次运行的结果优先（它比库里的新）；没按过按钮就看库里最新那条。
    final chain = lastRun?.chain ?? stored?.chain;
    final fromLibrary = lastRun?.chain == null && chain != null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.questionDetailReasoningSection,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: (!enabled || running) ? null : onSolve,
                icon: running
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_awesome),
                label: Text(
                  running
                      ? l10n.questionDetailSolving
                      : chain == null
                          ? l10n.questionDetailSolveButton
                          : l10n.questionDetailResolveButton,
                ),
              ),
            ),
            if (lastRun != null && !lastRun!.ok) _FailureCard(result: lastRun!),
            if (knowledgePointIds.isNotEmpty)
              _KnowledgePointChips(
                ids: knowledgePointIds,
                states: statesAsync.valueOrNull,
              ),
            const SizedBox(height: 12),
            if (chain == null)
              Text(
                l10n.questionDetailNoChainYet,
                style: theme.textTheme.bodyMedium,
              )
            else
              statesAsync.when(
                loading: () => Row(
                  children: [
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 8),
                    Text(l10n.questionDetailStatesLoading),
                  ],
                ),
                error: (error, _) =>
                    Text(l10n.questionDetailStatesFailed('$error')),
                data: (states) => _ChainView(
                  chain: chain,
                  states: states,
                  fromLibrary: fromLibrary,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 链的整体风险 + 逐步卡点。
class _ChainView extends StatelessWidget {
  const _ChainView({
    required this.chain,
    required this.states,
    required this.fromLibrary,
  });

  final ParsedChain chain;
  final Map<String, DsrState> states;
  final bool fromLibrary;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final report = StuckPointEvaluator.evaluate(
      steps: chain.steps,
      // 评估器的"现在"与状态读数的"现在"必须是同一个时钟：两边都用
      // `modelHoursOf`（自 Unix 纪元起的小时），差一小时就会让风险读数漂。
      nowHours: modelHoursOf(DateTime.now()),
      statesByKnowledgePoint: states,
    );
    // 步骤的文字（justification / checkMethod / knowledgeHints）不在评估结果里，
    // 按步号配回原始步骤。步号重复时后一条覆盖前一条——不额外发明合并规则。
    final parsedByIndex = <int, ParsedStep>{
      for (final step in chain.steps) step.index: step,
    };
    final mostLikely = report.mostLikely;
    final covered = report.steps.where((step) => step.hasStateEvidence).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (fromLibrary)
          Text(l10n.questionDetailChainFromLibrary,
              style: theme.textTheme.bodySmall),
        if (chain.summary.trim().isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(chain.summary, style: theme.textTheme.bodyLarge),
        ],
        const SizedBox(height: 8),
        Text(
            l10n.questionDetailOverallRisk((report.overallRisk * 100).round())),
        const SizedBox(height: 4),
        LinearProgressIndicator(value: report.overallRisk),
        if (mostLikely != null) ...[
          const SizedBox(height: 4),
          Text(l10n.questionDetailMostLikelyStep(mostLikely.index)),
        ],
        const SizedBox(height: 4),
        Text(
          l10n.questionDetailEvidenceCoverage(covered, report.steps.length),
          style: theme.textTheme.bodySmall,
        ),
        for (final point in report.steps)
          _StepCard(point: point, step: parsedByIndex[point.index]),
        if (report.unmatchedHints.isNotEmpty)
          _UnmatchedHints(hints: report.unmatchedHints),
      ],
    );
  }
}

/// 一步：模型怎么说 + 融合后的风险 + 建议。
class _StepCard extends StatelessWidget {
  const _StepCard({required this.point, required this.step});

  final StepStuckPoint point;

  /// 对应的原始步骤；理论上总在（评估器就是拿它算的），缺失时退化成只显示评估结果。
  final ParsedStep? step;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final step = this.step;
    final riskColor =
        point.isHighRisk ? theme.colorScheme.error : theme.colorScheme.primary;
    final goal = (step?.goal ?? point.goal).trim();
    final justification = step?.justification.trim() ?? '';
    final checkMethod = step?.checkMethod.trim() ?? '';
    final hints = step?.knowledgeHints ?? const <String>[];

    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  l10n.questionDetailStepTitle(point.index),
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    point.actionLabelZh,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
            if (step != null && !step.knownAction)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  l10n.questionDetailUnknownAction(point.actionType),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.error),
                ),
              ),
            if (goal.isNotEmpty)
              _LabelledText(
                  label: l10n.questionDetailStepGoalLabel, value: goal),
            if (justification.isNotEmpty)
              _LabelledText(
                label: l10n.questionDetailStepJustificationLabel,
                value: justification,
              ),
            if (checkMethod.isNotEmpty)
              _LabelledText(
                label: l10n.questionDetailStepCheckLabel,
                value: checkMethod,
              ),
            if (hints.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                l10n.questionDetailStepKnowledgeLabel,
                style: theme.textTheme.labelSmall,
              ),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final hint in hints)
                    Chip(
                      label: Text(hint),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            Text(
              l10n.questionDetailModelRisk((point.modelRisk * 100).round()),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            LinearProgressIndicator(value: point.modelRisk, color: riskColor),
            // 融合值只在真的有状态证据时才显示：否则它等于模型风险，多画一根
            // 一样的条会让人以为"你自己的数据也这么说了"。
            if (point.hasStateEvidence) ...[
              const SizedBox(height: 6),
              Text(
                l10n.questionDetailFusedRisk((point.fusedRisk * 100).round()),
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 4),
              LinearProgressIndicator(value: point.fusedRisk, color: riskColor),
            ],
            const SizedBox(height: 8),
            Text(
              l10n.questionDetailSuggestionLabel,
              style: theme.textTheme.labelSmall,
            ),
            Text(point.suggestion),
          ],
        ),
      ),
    );
  }
}

/// 失败面：原因 + 原始回复。
class _FailureCard extends StatelessWidget {
  const _FailureCard({required this.result});

  final ReasoningRunResult result;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final rawReply = result.rawReply?.trim() ?? '';
    final failureReason = result.failureReason;

    return Card(
      margin: const EdgeInsets.only(top: 12),
      color: theme.colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  Icons.error_outline,
                  color: theme.colorScheme.onErrorContainer,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.questionDetailRunFailedTitle,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            if (failureReason != null)
              _LabelledText(
                label: l10n.questionDetailFailureReasonLabel,
                value: failureReason,
              ),
            const SizedBox(height: 8),
            Text(
              l10n.questionDetailRawReplyLabel,
              style: theme.textTheme.labelSmall,
            ),
            const SizedBox(height: 4),
            SelectableText(
              rawReply.isNotEmpty
                  ? rawReply
                  : l10n.questionDetailRawReplyMissing,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// 全链没有状态读数的知识点提示：明说"不是没问题"。
class _UnmatchedHints extends StatelessWidget {
  const _UnmatchedHints({required this.hints});

  final List<String> hints;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.questionDetailUnmatchedHintsTitle,
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              l10n.questionDetailUnmatchedHintsBody,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final hint in hints)
                  Chip(
                    label: Text(hint),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 题目挂载的知识点；没有读数的那些标一个提示图标。
class _KnowledgePointChips extends StatelessWidget {
  const _KnowledgePointChips({required this.ids, required this.states});

  final List<String> ids;

  /// 状态读数还在路上时是 `null`——此时不标"没有读数"，因为还不知道。
  final Map<String, DsrState>? states;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final readings = states;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.questionDetailKnowledgePointsLabel,
            style: theme.textTheme.labelSmall,
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final id in ids)
                Chip(
                  label: Text(id),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  avatar: readings != null && !readings.containsKey(id)
                      ? Tooltip(
                          message: l10n.questionDetailKnowledgePointNoReading,
                          child: const Icon(Icons.help_outline, size: 16),
                        )
                      : null,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 一个"标签 + 值"的竖排小段。详情页上大量重复的排版只有这一种。
class _LabelledText extends StatelessWidget {
  const _LabelledText({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label, style: theme.textTheme.labelSmall),
          const SizedBox(height: 2),
          // 答案/解析/理由里也可能有 $…$ 公式：和题干走同一个渲染口径，
          // 但字号跟随正文（题干是 titleMedium，这些是默认 body 风格）。
          QuestionRichText(text: value),
        ],
      ),
    );
  }
}

/// 「题目来源」：一行链接图标 + 来源名 + 复制按钮 + 编辑按钮。
///
/// 只复制链接，不打开浏览器：App 不内置 url_launcher（链接交给浏览器打开）。
/// 组卷网来源显示「组卷网原题」，其它站显示规范化后的 host。没有可信链接时
/// 调用方不摆这一行，改摆「添加原题链接」入口（同一个 key）。
class _QuestionSourceLine extends StatelessWidget {
  const _QuestionSourceLine({required this.source, this.onEditSourceLinks});

  final QuestionSourceRef source;

  /// 打开「改原题链接」对话框；可空（没给缝就不摆编辑按钮）。
  final VoidCallback? onEditSourceLinks;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: <Widget>[
          Icon(
            Icons.link,
            size: 16,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              source.isZujuan ? l10n.questionSourceZujuan : source.host,
              style: theme.textTheme.bodySmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TextButton.icon(
            key: questionSourceCopyButtonKey,
            onPressed: () => _copyQuestionSource(context, source),
            icon: const Icon(Icons.copy_outlined, size: 16),
            label: Text(l10n.questionSourceCopyLink),
          ),
          if (onEditSourceLinks != null)
            TextButton.icon(
              key: questionSourceEditButtonKey,
              onPressed: onEditSourceLinks,
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: Text(l10n.questionSourceEdit),
            ),
        ],
      ),
    );
  }
}

/// 复制规范化后的原题链接，写进剪贴板后再提示（顺序与题号复制一致，
/// 既有测试用的就是 SystemChannels.platform 的 `Clipboard.setData`）。
Future<void> _copyQuestionSource(
  BuildContext context,
  QuestionSourceRef source,
) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  await Clipboard.setData(ClipboardData(text: source.url));
  if (!context.mounted) return;
  messenger.showSnackBar(SnackBar(content: Text(l10n.questionSourceCopyDone)));
}

/// 来源（`origin`）：手工 / 拍照扫描 / Furnace 内建。
String _originLabel(AppLocalizations l10n, String origin) => switch (origin) {
      'manual' => l10n.questionIntakeOriginManual,
      'ai_scan' => l10n.questionIntakeOriginAiScan,
      'furnace' => l10n.questionIntakeOriginFurnace,
      _ => origin.trim().isEmpty ? l10n.questionIntakeOriginManual : origin,
    };

/// 数值显示：整数不拖 `.0`，小数保留一位（难度 6 而不是 6.0）。
String _number(double value) {
  final rounded = value.roundToDouble();
  return rounded == value
      ? rounded.toInt().toString()
      : value.toStringAsFixed(1);
}

/// 找相似题：只从**已有题库**里找。领域层已经排好序、写好理由，这里不改顺序、
/// 不复算分量、不把 `score` 当百分比——只画 `reasonZh` 与「跨学科迁移」角标。
///
/// 一道都不像时（空列表）只给空态 + 去收题入口：**不许拿"看着像"的题凑数**，
/// 这是本片用户口径里最硬的一条。
class _SimilarQuestionsSection extends ConsumerWidget {
  const _SimilarQuestionsSection({required this.questionId});

  final String questionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final similar = ref.watch(similarQuestionsProvider(questionId));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.questionSimilarTitle, style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(l10n.questionSimilarSubtitle,
                style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),
            similar.when(
              loading: () => Row(
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  Text(l10n.questionSimilarLoading),
                ],
              ),
              error: (error, _) => Text(l10n.questionSimilarFailed('$error')),
              data: (items) => items.isEmpty
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l10n.questionSimilarEmpty),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: FilledButton.tonalIcon(
                            onPressed: () => _openIntake(context),
                            icon: const Icon(Icons.add),
                            label: Text(l10n.questionSimilarGoIntake),
                          ),
                        ),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          l10n.questionSimilarCount(items.length),
                          style: theme.textTheme.bodySmall,
                        ),
                        for (final item in items)
                          _SimilarQuestionTile(similar: item),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 一条候选：题干摘要（点进它的详情页）+ 领域层给的理由原文。
class _SimilarQuestionTile extends ConsumerWidget {
  const _SimilarQuestionTile({required this.similar});

  final SimilarQuestion similar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final detail = ref.watch(questionDetailProvider(similar.questionId));
    final stem = detail.valueOrNull?.question.stem.trim();
    final loadingStem = detail.isLoading && !detail.hasValue;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Row(
        children: [
          // 候选的号是异步读的（列表数据源里没有 serialNo）；读不到显示「未编号」。
          QuestionSerialBadgeById(questionId: similar.questionId),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              loadingStem
                  ? '…'
                  : (stem == null || stem.isEmpty
                      ? l10n.questionDetailQuestionMissing
                      : stem),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (similar.crossSubjectTransfer) ...[
            const SizedBox(width: 8),
            _TransferBadge(label: l10n.questionSimilarCrossSubject),
          ],
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(similar.reasonZh, style: theme.textTheme.bodySmall),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) =>
              QuestionDetailPage(questionId: similar.questionId),
        ),
      ),
    );
  }
}

/// 「跨学科迁移」角标：学科不同、但解题动作同型（`crossSubjectTransfer`）。
class _TransferBadge extends StatelessWidget {
  const _TransferBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall
            ?.copyWith(color: theme.colorScheme.onSecondaryContainer),
      ),
    );
  }
}

/// 空态里的「去收题」：AI 不出题，库里没有就去收。
void _openIntake(BuildContext context) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (context) => const QuestionIntakePage()),
  );
}

/// 「改来源」对话框：来源分级（白名单下拉）+ 来源说明/年份/地区。
///
/// 三条纪律：① 只改来源元信息（题干/答案/选项一个字不动）；② 留空的字段 =
/// **不改**那一列（不是清空 —— 想清空得再定一次口径，这一轮不顺手做半套）；
/// ③ 年份写错就停在对话框里说清楚，不悄悄当"没填"。
class _EditSourceDialog extends StatefulWidget {
  const _EditSourceDialog({required this.question});

  final Question question;

  @override
  State<_EditSourceDialog> createState() => _EditSourceDialogState();
}

class _EditSourceDialogState extends State<_EditSourceDialog> {
  late String _level = widget.question.sourceLevel;
  late final TextEditingController _labelController =
      TextEditingController(text: widget.question.sourceLabel);
  late final TextEditingController _yearController =
      TextEditingController(text: widget.question.year?.toString() ?? '');
  late final TextEditingController _regionController =
      TextEditingController(text: widget.question.region ?? '');
  String? _yearProblem;

  @override
  void dispose() {
    _labelController.dispose();
    _yearController.dispose();
    _regionController.dispose();
    super.dispose();
  }

  void _save() {
    final l10n = AppLocalizations.of(context);
    final rawYear = _yearController.text.trim();
    int? year;
    if (rawYear.isNotEmpty) {
      year = int.tryParse(rawYear);
      if (year == null || year < 1900 || year > 2200) {
        setState(() => _yearProblem = l10n.questionDetailEditSourceYearBad);
        return;
      }
    }
    final label = _labelController.text.trim();
    final region = _regionController.text.trim();
    Navigator.of(context).pop((
      level: _level,
      label: label,
      year: year,
      region: region.isEmpty ? null : region,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.questionDetailEditSourceTitle),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            DropdownButtonFormField<String>(
              initialValue: _level,
              decoration: InputDecoration(
                labelText: l10n.questionIntakeSourceLevelLabel,
              ),
              items: <DropdownMenuItem<String>>[
                for (final level in kSourceLevelWeight.keys)
                  DropdownMenuItem<String>(
                    value: level,
                    child: Text(sourceLevelLabel(l10n, level)),
                  ),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() => _level = value);
                }
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _labelController,
              decoration: InputDecoration(
                labelText: l10n.questionIntakeSourceLabelLabel,
                hintText: l10n.questionIntakeSourceLabelHint,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _yearController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: l10n.questionIntakeYearLabel,
                errorText: _yearProblem,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _regionController,
              decoration: InputDecoration(
                labelText: l10n.questionIntakeRegionLabel,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.questionDetailEditSourceHint,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonClose),
        ),
        FilledButton(
          onPressed: _save,
          child: Text(l10n.commonSave),
        ),
      ],
    );
  }
}
