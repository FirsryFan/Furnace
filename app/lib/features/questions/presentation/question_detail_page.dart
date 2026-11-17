/// 题目详情页：一道题的完整视图 + 推理管道的入口与可读展示。
///
/// 版块顺序（2026-11-17 用户口径：一个合格题库里的题，应该在一页里看全）：
///
///  1. **题干**：题名/题号/来源行 + 题干与题干配图 + 选项与自测；
///  2. **答案与解析**：答案、解析、坑点与答案截图；缺数据时写「暂无」；
///  3. **思维 DAG**：AI 解题产出的分步思维链（本地 `reasoning_chains` /
///     `reasoning_steps`），没有就写「暂无」；AI 解题的按钮与失败面在
///     页底的「AI 解题 / MindNet 认知评价」版块里；
///  4. **元数据**：来源说明、年份、地区、题型、难度、能力点、标签（只显示
///     已有数据；`state`/`origin`/`aiQuality`/内部 id 仍是开发者字段）；
///  5. **相似题目推荐**：只从题库里找；
///  6. **来源文件与来源包**：`content_refs` 里的来源包引用 + 原题链接；
///     组卷网检索入口只对组卷网有列表页的学科出现（信息学/历史/算法竞赛不摆）；
///  7. **AI 解题 / MindNet 认知评价**：一个完整版块放在页底——跑解题、看失败面、
///     看 MindNet 只读读数。
///
/// 两条本页坚持的诚实性规则：
///
///  * **失败面照样展示**：模型没配好、回复不合契约、题目 id 不存在，都显示
///    `failureReason` 与已收到的 `rawReply`，不弹一个"出错了"就吞掉。
///  * **没有数据要说出来**：缺答案/缺链/缺来源包/缺标签都写「暂无」，
///    不拿"看着像"的内容凑数，也不留一块空白卡片。
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/database.dart';
import '../../../data/media/image_size.dart';
import '../../../data/repositories/question_repository.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../domain/services/cognitive/cognitive_model.dart';
import '../../../domain/services/cognitive/problem_evaluator.dart'
    show ProblemVerdict;
import '../../../domain/services/paper/similar_questions.dart';
import '../../../domain/services/questions/objective_answer.dart';
import '../../../domain/services/questions/question_capability.dart';
import '../../../domain/services/questions/question_number_query.dart';
import '../../../domain/services/questions/question_option_layout.dart';
import '../../../domain/services/questions/question_source.dart';
import '../../../domain/services/questions/question_stem_image_plan.dart';
import '../../../domain/services/reasoning/capability_action.dart';
import '../../../domain/services/reasoning/reasoning_prompt.dart';
import '../../../domain/services/reasoning/stuck_point_evaluator.dart';
import '../../../domain/services/srs/dsr_memory.dart';
import '../../../l10n/app_localizations.dart';
import '../../cognitive/presentation/zone_labels.dart';
import '../application/question_cognitive_provider.dart';
import '../application/question_reasoning_service.dart';
import '../application/question_stem_display_provider.dart';
import '../application/similar_question_provider.dart';
import 'question_developer_page.dart';
import 'question_detail_providers.dart';
import 'question_markdown_view.dart';
import 'question_media_view.dart';
import 'question_stem_markdown_view.dart';
import 'question_zujuan_search.dart';

/// 「自测」开关与「提交答案」按钮的 key（测试定位用）。
const Key questionSelfTestToggleKey = Key('question-self-test-toggle');
const Key questionSelfTestSubmitKey = Key('question-self-test-submit');

/// 自测模式下单个选项行的 key：`question-self-test-option-<label>`。
Key questionSelfTestOptionKey(String label) =>
    ValueKey<String>('question-self-test-option-$label');

/// 详情页单个选项格子的 key：`question-option-cell-<label>`。
///
/// 不管单列还是两列布局都在，测试用它断言排布（同一行的 dy 相同 = 两列）。
Key questionDetailOptionCellKey(String label) =>
    ValueKey<String>('question-option-cell-$label');

/// 自测防剧透提示的 key：自测未提交时，AI 解题/相似题/找原题三个区块被收起，
/// 在这里显示一句说明（测试定位用）。
const Key questionDetailSpoilerGuardHintKey =
    Key('question-detail-spoiler-guard-hint');

/// AI 解题区块的 key：自测未提交时整块不渲染（测试定位用）。
const Key questionDetailReasoningSectionKey =
    Key('question-detail-reasoning-section');

/// 相似题区块的 key：自测未提交时整块不渲染（测试定位用）。
const Key questionDetailSimilarSectionKey =
    Key('question-detail-similar-section');

/// 「MindNet 认知评价」卡片的 key（测试定位用）。
///
/// 空态也渲染这张卡（标题 + 一句「还读不到」），所以测试既能断言「有卡片」，
/// 也能断言空态文案；加载中/读库失败时整块零高度，这个 key 不出现。
const Key questionCognitiveSectionKey = Key('question-cognitive-section');

/// 「思维 DAG」版块的 key（测试定位用）。空链时也渲染（标题 + 「暂无」），
/// 所以这个 key 在页面读题成功后恒定出现；自测防剧透期间整块不渲染。
const Key questionDetailDagSectionKey = Key('question-detail-dag-section');

/// 「元数据」版块的 key（测试定位用）。
const Key questionDetailMetadataSectionKey =
    Key('question-detail-metadata-section');

/// 「来源文件与来源包」版块的 key（测试定位用）。
const Key questionDetailSourceSectionKey =
    Key('question-detail-source-section');

/// 来源版块里「复制原题链接」按钮的 key（测试定位用）。
const Key questionDetailSourceCopyKey = Key('question-detail-source-copy');

/// 页底「AI 解题 / MindNet 认知评价」完整版块的 key（测试定位用）。
const Key questionDetailAiCognitiveSectionKey =
    Key('question-detail-ai-cognitive-section');

/// 自测历史摘要行的 key（测试定位用）。
const Key questionAttemptHistoryKey = Key('question-attempt-history');

/// 自测历史里「查看/收起明细」按钮的 key（测试定位用）。
const Key questionAttemptDetailToggleKey =
    Key('question-attempt-detail-toggle');

/// 自测历史里「清除记录」按钮的 key（测试定位用）。
const Key questionAttemptClearKey = Key('question-attempt-clear');

/// 自测历史里的单条作答记录 key：`question-attempt-entry-<id>`（测试定位用）。
Key questionAttemptEntryKeyFor(String id) =>
    ValueKey<String>('question-attempt-entry-$id');

/// 自测历史明细里单条记录删除按钮的 key：`question-attempt-delete-<id>`（测试定位用）。
Key questionAttemptEntryDeleteKeyFor(String id) =>
    ValueKey<String>('question-attempt-delete-$id');

/// AppBar 上「上一题」按钮的 key（测试定位用）。
///
/// 没有邻居时按钮**禁用而不是隐藏**：翻页按钮的位置要稳，题号 1 与题号 100
/// 看起来应该是同一个页面，只是箭头能不能按。
const Key questionDetailPreviousQuestionKey =
    Key('question-detail-previous-question');

/// AppBar 上「下一题」按钮的 key（测试定位用）。
const Key questionDetailNextQuestionKey = Key('question-detail-next-question');

/// 「第 N / 共 M 题」进度行的 key（测试定位用）。
///
/// 分页读数只有"本题有题号"时才有（见 `questionSerialPositionProvider`），
/// 没有就在页面上完全不出现这一行。
const Key questionDetailSerialPositionKey =
    Key('question-detail-serial-position');

/// 「本组共 N 小问」提示行的 key（测试定位用）。
///
/// 独立题不渲染这一行；题组（一篇文章 + 多个小问）才出现。
const Key questionDetailGroupHintKey = Key('question-detail-group-hint');

/// AppBar 上「跳题号」按钮的 key（测试定位用）。
const Key questionDetailJumpSerialKey = Key('question-detail-jump-serial');

/// 「能力点」chips 区块的 key（测试定位用）。
///
/// 题目没标能力点时整块不渲染，所以测试既可以断言"有"，也可以断言"没有"。
const Key questionCapabilityChipsKey = Key('question-capability-chips');

/// 「扩展题 / 母题」关联区块的 key（测试定位用）。
const Key questionExtensionLinksKey = Key('question-extension-links');

/// 母题入口行的 key（测试定位用）。
///
/// 母题在库里时才可点；只有组卷网题号时这一行是禁用态、**没有这个 key**，
/// 测试据此区分"能进去"与"只能看题号"。
const Key questionExtensionParentKey = Key('question-extension-parent');

/// 扩展题子题入口行的 key：`question-extension-child-<questionId>`。
Key questionExtensionChildKey(String questionId) =>
    ValueKey<String>('question-extension-child-$questionId');

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

  /// 自测防剧透：题目正文打开了自测且还没提交时，本页把会剧透步骤的区块
  /// （AI 解题、相似题、找原题）整块收起，提交或结束自测后恢复。
  bool _spoilersHidden = false;

  void _onSelfTestChanged(bool active) {
    if (!mounted || _spoilersHidden == active) {
      return;
    }
    setState(() {
      _spoilersHidden = active;
    });
  }

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

  /// 翻到相邻题：用 `pushReplacement` 而不是 `push`。
  ///
  /// 翻页是"在同一层里横向走"，不是"往下钻"——每按一次就往返回栈里堆一层，
  /// 按十次后要按十次返回才能回到题库，那是 bug 不是功能。
  void _openNeighbor(QuestionSerialNeighbor neighbor) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => QuestionDetailPage(questionId: neighbor.questionId),
      ),
    );
  }

  /// 「跳题号」：先弹输入框拿到检索，再按题号查库。
  ///
  /// 三种结果都**不给假动作**：认不出就不关框（在输入框上写原因）；库里没有就
  /// 只弹一句提示、页面原地不动；正好是当前这道题就什么都不做（不 pushReplacement
  /// 到自己——那会白重载一遍页面）。只有真跳到别的题才换路由。
  Future<void> _jumpToSerial() async {
    final query = await showDialog<QuestionNumberQuery>(
      context: context,
      builder: (_) => const _JumpToSerialDialog(),
    );
    if (query == null || !mounted) {
      return;
    }
    final found = await ref
        .read(questionRepositoryProvider)
        .findBySerialNo(query.serialNo);
    if (!mounted) {
      return;
    }
    final l10n = AppLocalizations.of(context);
    if (found == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              l10n.questionDetailJumpSerialNotFound(query.normalizedLabel)),
        ),
      );
      return;
    }
    if (found.id == widget.questionId) {
      return;
    }
    _openNeighborSerial(found.id);
  }

  /// 跳到指定题号命中的那道题；语义与 `_openNeighbor` 一致（同层横走，不堆栈）。
  void _openNeighborSerial(String questionId) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => QuestionDetailPage(questionId: questionId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final detailAsync = ref.watch(questionDetailProvider(widget.questionId));
    // 只 watch 一次：两个按钮读的都是这份邻居读数（loading/error/无题号 → 都禁用）。
    final neighborsAsync =
        ref.watch(questionSerialNeighborsProvider(widget.questionId));
    final neighbors = neighborsAsync.valueOrNull;
    // 「第 N / 共 M 题」：null（无题号 / 题库里没有带号题 / 读失败）就整行不渲染。
    final position = ref
        .watch(questionSerialPositionProvider(widget.questionId))
        .valueOrNull;
    final detail = detailAsync.valueOrNull;
    final missing = detailAsync.hasValue && detail == null;

    return Scaffold(
      appBar: AppBar(
        // 题名是学生页的主标题；「第 N / 共 M 题」只是次级读数，放 AppBar
        // 副行，不从题面顶部抢走第一眼（2026-11-15 学生端干净 UI）。
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(l10n.questionDetailTitle),
            if (position != null)
              Text(
                key: questionDetailSerialPositionKey,
                l10n.questionDetailSerialPosition(
                  position.index,
                  position.total,
                ),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
          ],
        ),
        actions: [
          IconButton(
            key: questionDetailPreviousQuestionKey,
            icon: const Icon(Icons.chevron_left),
            tooltip: l10n.questionDetailPreviousQuestion,
            onPressed: neighbors?.previous == null
                ? null
                : () => _openNeighbor(neighbors!.previous!),
          ),
          IconButton(
            key: questionDetailNextQuestionKey,
            icon: const Icon(Icons.chevron_right),
            tooltip: l10n.questionDetailNextQuestion,
            onPressed: neighbors?.next == null
                ? null
                : () => _openNeighbor(neighbors!.next!),
          ),
          IconButton(
            key: questionDetailJumpSerialKey,
            icon: const Icon(Icons.tag),
            tooltip: l10n.questionDetailJumpSerialTooltip,
            onPressed: _jumpToSerial,
          ),
        ],
      ),
      // 详情页是"一页看完一道题"：用 SingleChildScrollView 而不是懒加载
      // ListView——版块顺序是产品口径的一部分，缺数据时也要渲染「暂无」的
      // 版块（不能用懒加载把屏幕外的版块当成"不存在"）。
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
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
              // 学生视图：题干/选项/答案/自测/学习读数。改名、改来源、原题
              // 链接编辑、配图编辑、入库体检等开发动作统一收进「开发者信息」。
              _QuestionBody(
                detail: detail,
                onSelfTestChanged: _onSelfTestChanged,
              ),
            if (detail != null) ...[
              // 3. 思维 DAG：AI 解题产出的分步链；没有就写「暂无」。
              if (!_spoilersHidden) ...[
                const SizedBox(height: 16),
                _DagSection(
                  key: questionDetailDagSectionKey,
                  questionId: widget.questionId,
                  lastRun: _lastRun,
                ),
              ],
              // 4. 元数据：来源/年份/地区/题型/难度/能力点/标签，只摆已有数据。
              const SizedBox(height: 16),
              _QuestionMetadataSection(
                key: questionDetailMetadataSectionKey,
                question: detail.question,
              ),
              // 5. 相似题目推荐（自测未提交时收起：相似题会剧透解法）。
              if (!_spoilersHidden) ...[
                const SizedBox(height: 16),
                _SimilarQuestionsSection(
                  key: questionDetailSimilarSectionKey,
                  questionId: widget.questionId,
                ),
                // 6. 来源文件与来源包（含原题链接；自测未提交时同样收起）。
                const SizedBox(height: 16),
                _QuestionSourceSection(
                  key: questionDetailSourceSectionKey,
                  question: detail.question,
                ),
              ],
              if (_spoilersHidden)
                Padding(
                  key: questionDetailSpoilerGuardHintKey,
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(
                    l10n.questionDetailSelfTestSpoilerHidden,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ),
              // 7. AI 解题 / MindNet 认知评价：一个完整版块放在页底。
              const SizedBox(height: 16),
              Column(
                key: questionDetailAiCognitiveSectionKey,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l10n.questionDetailAiCognitiveSection,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  if (!_spoilersHidden) ...[
                    const SizedBox(height: 8),
                    _ReasoningSection(
                      key: questionDetailReasoningSectionKey,
                      questionId: widget.questionId,
                      running: _running,
                      lastRun: _lastRun,
                      enabled: true,
                      onSolve: _solve,
                    ),
                  ],
                  // MindNet 认知评价：只读读数；不剧透解法，自测中也保留。
                  QuestionCognitiveSection(questionId: widget.questionId),
                ],
              ),
              // 开发者信息的**唯一**入口：内部字段、来源编辑与配图管理都在那一页。
              // 学生页不摊开这些，只留一个低权重文字按钮。
              const SizedBox(height: 24),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: questionDeveloperEntryKey,
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          QuestionDeveloperPage(questionId: widget.questionId),
                    ),
                  ),
                  icon: const Icon(Icons.code, size: 16),
                  label: Text(l10n.questionDeveloperEntry),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 「跳题号」输入框：只负责把输入解析成 [QuestionNumberQuery]，不查库。
///
/// 认不出（脏输入 / 空）时**不关对话框**，把原因写在输入框下面——关掉再弹一次
/// 只会让人把同一个错字重打一遍。查库与跳转由页面做（对话框不碰 state）。
class _JumpToSerialDialog extends StatefulWidget {
  const _JumpToSerialDialog();

  @override
  State<_JumpToSerialDialog> createState() => _JumpToSerialDialogState();
}

class _JumpToSerialDialogState extends State<_JumpToSerialDialog> {
  final TextEditingController _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final query = parseQuestionNumberQuery(_controller.text);
    if (query == null) {
      setState(() {
        _error = AppLocalizations.of(context).questionDetailJumpSerialInvalid;
      });
      return;
    }
    Navigator.of(context).pop(query);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.questionDetailJumpSerialTitle),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(
          labelText: l10n.questionDetailJumpSerialFieldLabel,
          hintText: l10n.questionDetailJumpSerialHint,
          errorText: _error,
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(l10n.questionDetailJumpSerialAction),
        ),
      ],
    );
  }
}

/// 学生视图里的题目正文：题干、选项、答案、解析。
///
/// 不再套卡片底座：题干、图片、选项、答案直接铺在页面背景上，靠小节标题、
/// 间距和细分隔线分段（需求原文：「很多文字不需要放在一个卡片底座上」）。
///
/// 开发侧动作（改题名 / 改来源 / 原题链接 / 配图增删 / 入库体检 / 原始字段）
/// 一律不在这里：学生页只读，入口是页底的「开发者信息」（`QuestionDeveloperPage`）。
class _QuestionBody extends StatefulWidget {
  const _QuestionBody({
    required this.detail,
    this.onSelfTestChanged,
  });

  final QuestionDetail detail;

  /// 自测防剧透状态变化：true = 打开自测且未提交（父页面据此收起会剧透的区块），
  /// false = 没在自测 / 已提交 / 已结束。可选：测试里可以只关心正文。
  final ValueChanged<bool>? onSelfTestChanged;

  @override
  State<_QuestionBody> createState() => _QuestionBodyState();
}

/// 题目展示里的「自测」状态：本地 State，不落库、不进 Riverpod。
///
/// 自测只对能自动判分的客观题开放（域层 `canScoreObjectiveQuestion` 说了算）；
/// 打开后先藏答案，提交后 `scoreObjectiveAnswer` 判分并恢复答案；结束自测时
/// 选择与判分结果一起清空，页面回到改动前完全一致的样子。
class _QuestionBodyState extends State<_QuestionBody> {
  /// 自测是否打开（提交后仍是打开状态，只是选项锁定、答案已恢复）。
  bool _selfTest = false;

  /// 已勾选的选项 label。单选/多选都用复选框：判分交给域层，不在 UI 里
  /// 替用户规定互斥。
  final Set<String> _selectedLabels = <String>{};

  /// 本次提交的判分结果；null = 还没提交。
  ObjectiveAttemptResult? _attempt;

  bool get _submitted => _attempt != null;

  /// 自测打开但未提交：这段时间必须藏住正确答案标记、答案、解析与答案截图。
  bool get _answersHidden => _selfTest && !_submitted;

  List<ObjectiveOption> get _objectiveOptions => <ObjectiveOption>[
        for (final option in widget.detail.options)
          ObjectiveOption(label: option.label, isCorrect: option.isCorrect),
      ];

  /// 把「现在要不要防剧透」告诉父页面：只有「自测中且未提交」这一段要藏。
  void _notifySelfTestChanged() {
    widget.onSelfTestChanged?.call(_answersHidden);
  }

  void _toggleSelfTest() {
    setState(() {
      _selfTest = !_selfTest;
      _selectedLabels.clear();
      _attempt = null;
    });
    _notifySelfTestChanged();
  }

  void _toggleOption(String label) {
    if (!_selfTest || _submitted) {
      return;
    }
    setState(() {
      if (!_selectedLabels.add(label)) {
        _selectedLabels.remove(label);
      }
    });
  }

  void _submit() {
    if (!_selfTest || _submitted || _selectedLabels.isEmpty) {
      return;
    }
    final result = scoreObjectiveAnswer(
      questionType: widget.detail.question.questionType,
      options: _objectiveOptions,
      selectedLabels: _selectedLabels,
    );
    setState(() {
      _attempt = result;
    });
    // 提交后答案面恢复，剧透区块也跟着回来。
    _notifySelfTestChanged();
    // 只有「判得出对错」的提交才落库（空选/非客观题没有可判的东西）；
    // 写库失败不该把这次作答变成错误，所以异步吞掉。
    if (result.isCorrect || result.isIncorrect) {
      _recordAttempt(result);
    }
  }

  /// 把这次判分追加进 `question_attempts`；失败只记日志，界面照常显示判分。
  Future<void> _recordAttempt(ObjectiveAttemptResult result) async {
    final container = ProviderScope.containerOf(context, listen: false);
    try {
      await container.read(questionAttemptRepositoryProvider).record(
            questionId: widget.detail.question.id,
            selectedLabels: result.selectedLabels,
            isCorrect: result.isCorrect,
          );
    } catch (error, stackTrace) {
      debugPrint('自测作答写库失败：$error\n$stackTrace');
    }
  }

  /// 选项栏的整体排布：短选项两列/流式，长选项一行一个，窄屏退化单列。
  ///
  /// 判定在 `question_option_layout.dart`（纯逻辑、可单测）：四个选项都是短
  /// 单行文字（如化学 Q15）且宽度够时排两列，否则保持原来的一行一个。自测
  /// 勾选、正确答案标记、判分横幅都在单元格里，不因换排布丢信息。
  Widget _buildOptionsLayout(
    BuildContext context,
    List<QuestionOption> options,
  ) {
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        // 2560 宽屏下选项不要拉满整页；两列时每列约 380px，短选项不再空。
        constraints: const BoxConstraints(maxWidth: 780),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final twoColumns = questionOptionsFlowIntoTwoColumns(
              optionContents: <String>[
                for (final option in options) option.content
              ],
              availableWidth: constraints.maxWidth,
            );
            if (!twoColumns) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  for (final option in options)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: KeyedSubtree(
                        key: questionDetailOptionCellKey(option.label),
                        child: _buildOptionCell(context, option),
                      ),
                    ),
                ],
              );
            }
            final cellWidth =
                (constraints.maxWidth - kTwoColumnOptionSpacing) / 2;
            return Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Wrap(
                spacing: kTwoColumnOptionSpacing,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.start,
                children: <Widget>[
                  for (final option in options)
                    SizedBox(
                      key: questionDetailOptionCellKey(option.label),
                      width: cellWidth,
                      child: _buildOptionCell(context, option),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  /// 一个选项格子。普通模式与改动前一致；自测模式加复选框、整格可点选、
  /// 选中高亮，提交后锁定。未提交时**不显示**「正确答案」标记。
  Widget _buildOptionCell(BuildContext context, QuestionOption option) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final selected = _selectedLabels.contains(option.label);
    final selectable = _selfTest && !_submitted;

    Widget labelText() => Text(
          '${option.label}.',
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        );
    // 题目声明为 Markdown 时选项也跟着整段渲染；缺省仍是原文 + 行内公式。
    // 选项里的「［图N］」公式图与题干共用同一套图片清单，走统一 Markdown
    // 渲染器的行内图片路径（化学压轴题的选项中段全是公式图）。
    Widget contentText() => QuestionMarkdownTextWithImages(
          questionId: widget.detail.question.id,
          text: option.content,
          markdown: questionTextFormatIsMarkdown(
            widget.detail.question.textFormat,
          ),
        );
    final correctMark = option.isCorrect && !_answersHidden
        ? Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Text(
              l10n.questionDetailCorrectOption,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          )
        : null;

    if (!_selfTest) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: labelText(),
          ),
          Flexible(child: contentText()),
          if (correctMark != null) correctMark,
        ],
      );
    }

    return InkWell(
      key: questionSelfTestOptionKey(option.label),
      borderRadius: BorderRadius.circular(8),
      onTap: selectable ? () => _toggleOption(option.label) : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? theme.colorScheme.primaryContainer : null,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Checkbox(
              value: selected,
              onChanged: selectable ? (_) => _toggleOption(option.label) : null,
              visualDensity: VisualDensity.compact,
            ),
            Padding(
              padding: const EdgeInsets.only(right: 6, top: 10),
              child: labelText(),
            ),
            Flexible(
              child: Padding(
                padding: const EdgeInsets.only(top: 10),
                // 自测里整行都是点击目标：选项文字若是可选中的
                // SelectableText，会吃掉这次点击，让 InkWell 收不到。
                child: IgnorePointer(child: contentText()),
              ),
            ),
            if (correctMark != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: correctMark,
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final detail = widget.detail;
    final question = detail.question;

    // 学生页的来源行只留「年份 / 地区 / 科目」这类题面身份：`content_package`、
    // `已结构化`、来源分级、内部 id 都是开发字段，统一在「开发者信息」里。
    final meta = <String>[
      question.subjectKey.trim().isEmpty
          ? l10n.questionIntakeSubjectNone
          : CapabilityAction.subjectLabelsZh[question.subjectKey] ??
              question.subjectKey,
      if (question.year != null) l10n.questionDetailYear(question.year!),
      if (question.region != null && question.region!.trim().isNotEmpty)
        question.region!.trim(),
    ];

    final answer = question.answer?.trim() ?? '';
    final solution = question.solution?.trim() ?? '';
    final trapNote = question.trapNote?.trim() ?? '';
    // 只有 `.tqb` 明确标了 `text_format: markdown` 的题才整段渲染；历史题
    // （NULL / plain）保持「原文 + 行内公式」的老口径。
    final markdownText = questionTextFormatIsMarkdown(question.textFormat);
    // 题名是用户自己起的扫描标签：没起名就明确显示「未命名」，不拿题干冒充。
    final title = (question.title ?? '').trim();
    final hasTitle = title.isNotEmpty;
    // 自测只对客观题开放：题干类型、选项、正确项三件事任何一件不满足都不摆
    // 入口（判据在域层，UI 不自己发明）。
    final canSelfTest = canScoreObjectiveQuestion(
      questionType: question.questionType,
      options: _objectiveOptions,
    );

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
                  if (meta.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      meta.join(' · '),
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // 题组提示：一篇文章 + 多个小问在题库里是一道题；打开组内任意一题时
        // 明确告诉用户「本组共 N 小问」，不让人以为自己只看到半道题。
        // 独立题零高度（不占版面）。
        _QuestionGroupHint(questionId: question.id),
        // 题干版块标题：让「题干 / 答案 / 思维 DAG / 元数据 …」的版块边界
        // 一眼可见（此前题干没有任何标题，只有题名与来源行）。
        Text(l10n.questionIntakeStemLabel, style: theme.textTheme.titleSmall),
        const SizedBox(height: 2),
        // 题干与题干配图混排：文字段/图片段按「［图1］」占位拆分，
        // 没被占位引用的图接在题干文字末尾（见 question_stem_segments.dart）。
        _QuestionStemView(
          questionId: question.id,
          stem: question.stem,
          markdown: markdownText,
        ),
        // 扩展关联（handoff §7 M2）：有数据才出现，空时零高度。能力点归
        // 「元数据」版块（同一份数据只出现一次）。
        _QuestionRelationsSection(question: question),
        if (detail.options.isNotEmpty) ...[
          const SizedBox(height: 16),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  l10n.questionIntakeOptionsLabel,
                  style: theme.textTheme.titleSmall,
                ),
              ),
              // 自测入口只对能自动判分的客观题出现：点开先藏答案，提交后
              // 用域层判分，答错时告诉用户正确选项。
              if (canSelfTest)
                TextButton.icon(
                  key: questionSelfTestToggleKey,
                  onPressed: _toggleSelfTest,
                  icon: Icon(
                    _selfTest ? Icons.close : Icons.fact_check_outlined,
                    size: 18,
                  ),
                  label: Text(
                    _selfTest
                        ? l10n.questionDetailSelfTestExit
                        : l10n.questionDetailSelfTest,
                  ),
                ),
            ],
          ),
          if (_answersHidden)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                l10n.questionDetailSelfTestHiddenHint,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          if (_attempt != null) _SelfTestResultBanner(result: _attempt!),
          _buildOptionsLayout(context, detail.options),
          // 未选任何选项时禁用：自测要有一个明确的「我答完了」动作。
          if (_selfTest && !_submitted)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  key: questionSelfTestSubmitKey,
                  onPressed: _selectedLabels.isEmpty ? null : _submit,
                  icon: const Icon(Icons.check),
                  label: Text(l10n.questionDetailSelfTestSubmit),
                ),
              ),
            ),
        ],
        // 自测历史摘要：放在自测开关/选项这一带；一次没做过时整块不占位。
        _AttemptHistoryLine(questionId: question.id),
        // ---- 答案与解析版块 ----
        // 自测中（未提交）整块（含版块标题）收起：标题本身不剧透，但答案区
        // 紧跟着它，摆一个空标题只会让人去猜"下面藏了什么"。
        if (!_answersHidden) ...[
          const SizedBox(height: 20),
          Text(
            l10n.questionDetailAnswerSection,
            style: theme.textTheme.titleSmall,
          ),
          if (answer.isNotEmpty)
            _LabelledText(
              label: l10n.questionIntakeAnswerLabel,
              value: answer,
              markdown: markdownText,
            ),
          if (solution.isNotEmpty)
            _LabelledText(
              label: l10n.questionIntakeSolutionLabel,
              value: solution,
              markdown: markdownText,
            ),
          if (trapNote.isNotEmpty)
            _LabelledText(
              label: l10n.questionDetailTrapNote,
              value: trapNote,
              markdown: markdownText,
            ),
          // 答案截图：有文字答案时跟在答案段后；没有文字答案时也照样摆
          // （组卷网登录后才看得到的整张答案图，和题干配图分开存、分开显示）。
          const SizedBox(height: 8),
          QuestionImagesSection(
            questionId: question.id,
            kind: QuestionImagesSectionKind.answer,
          ),
          // 文字答案/解析/坑点都没有、图片也没有：明说「暂无（未处理）」，
          // 不留一个只有标题的空版块。
          if (answer.isEmpty && solution.isEmpty && trapNote.isEmpty)
            _EmptyAnswerHint(questionId: question.id),
        ],
      ],
    );
  }
}

/// 「本组共 N 小问」：一篇文章 + 多个小问在题库里算**一道题**（题组）。
///
/// 只在题组且组内多于一个小问时出现；独立题返回零高度，不占版面、不改旧页面
/// 的版块顺序。数据来自 `questionGroupInfoProvider`（与题库列表折叠同一份组键）。
class _QuestionGroupHint extends ConsumerWidget {
  const _QuestionGroupHint({required this.questionId});

  final String questionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final info =
        ref.watch(questionGroupInfoProvider(questionId)).valueOrNull;
    if (info == null || !info.isGroup) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          key: questionDetailGroupHintKey,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: theme.colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '${info.label} · ${l10n.questionDetailGroupSize(info.size)}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSecondaryContainer,
            ),
          ),
        ),
      ),
    );
  }
}

/// 答案版块的诚实空态：没有文字答案/解析/坑点、也没有答案截图时才显示。
///
/// 单独一个 Consumer，是因为"有没有答案图"读的是异步 provider；`_QuestionBody`
/// 不把这份读数塞进自己的 State，避免为了一个空态把整个正文变成 Consumer。
class _EmptyAnswerHint extends ConsumerWidget {
  const _EmptyAnswerHint({required this.questionId});

  final String questionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final images =
        ref.watch(questionAnswerImagesProvider(questionId)).valueOrNull;
    if (images != null && images.isNotEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        l10n.questionDetailAnswerEmpty,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// 题目的「扩展题 / 母题」关联（handoff §7 M2）。
///
/// **有数据才出现**：扩展关联两边都空时整块零高度。能力点不在这里了——它是
/// 「元数据」版块的一行（同一份数据只出现一次），判据仍走 `questions.capability`。
/// 扩展关联走 `questionExtensionLinksProvider`（`extension_of` 反查）。
class _QuestionRelationsSection extends ConsumerWidget {
  const _QuestionRelationsSection({required this.question});

  final Question question;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final links =
        ref.watch(questionExtensionLinksProvider(question.id)).valueOrNull;
    if (links == null || links.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: _QuestionExtensionLinksView(links: links),
    );
  }
}

/// 能力点 chips：只读（标注能力点目前不在本题详情页做）。
class _QuestionCapabilityChips extends StatelessWidget {
  const _QuestionCapabilityChips({required this.codes});

  final List<String> codes;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Column(
      key: questionCapabilityChipsKey,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(l10n.questionCapabilitySection, style: theme.textTheme.titleSmall),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: <Widget>[
            for (final code in codes)
              Chip(
                label: Text(_capabilityChipLabel(code)),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                side: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
          ],
        ),
      ],
    );
  }
}

/// 能力点 chip 文案：`A2 信息定位与提取`。
///
/// 词表按既有约定只带中文标签（英文界面也显示中文，不另造译名）；
/// 认不出的代码原样显示——脏数据不该在界面上被静默吞掉。
String _capabilityChipLabel(String code) {
  final capability = QuestionCapability.fromCode(code);
  if (capability == null) {
    return code;
  }
  return '${capability.code} ${capability.labelZh}';
}

/// 扩展关联：母题入口 + 扩展题列表。
class _QuestionExtensionLinksView extends StatelessWidget {
  const _QuestionExtensionLinksView({required this.links});

  final QuestionExtensionLinks links;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Column(
      key: questionExtensionLinksKey,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (links.isExtension) _QuestionExtensionParentRow(links: links),
        if (links.isExtension && links.children.isNotEmpty)
          const SizedBox(height: 8),
        if (links.children.isNotEmpty) ...[
          Text(
            l10n.questionExtensionChildrenTitle(links.children.length),
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          for (final child in links.children)
            _QuestionExtensionChildRow(child: child),
        ],
      ],
    );
  }
}

/// 母题入口行：母题在库里就点得进去；只有组卷网题号时是禁用态 + 缺失说明。
class _QuestionExtensionParentRow extends StatelessWidget {
  const _QuestionExtensionParentRow({required this.links});

  final QuestionExtensionLinks links;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final parent = links.parent;
    if (parent == null) {
      // 母题还没导入：题号照样摆出来（能拿去组卷网核），但不给假动作。
      return Tooltip(
        message: l10n.questionExtensionParentMissing,
        child: Row(
          children: <Widget>[
            Icon(
              Icons.subdirectory_arrow_left,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                l10n.questionExtensionParentZujuan(
                  links.parentZujuanQuestionId,
                ),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Text(
              l10n.questionExtensionParentMissing,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }
    final serialNo = parent.serialNo;
    final label = serialNo != null
        ? l10n.questionExtensionParentSerial(serialNo)
        : l10n.questionExtensionParentZujuan(links.parentZujuanQuestionId);
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        key: questionExtensionParentKey,
        onPressed: () => _openQuestionDetail(context, parent.id),
        icon: const Icon(Icons.subdirectory_arrow_left, size: 18),
        label: Text(label),
      ),
    );
  }
}

/// 扩展题子题行：题号 + 一行预览，点进子题详情。
class _QuestionExtensionChildRow extends StatelessWidget {
  const _QuestionExtensionChildRow({required this.child});

  final Question child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      key: questionExtensionChildKey(child.id),
      borderRadius: BorderRadius.circular(6),
      onTap: () => _openQuestionDetail(context, child.id),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: <Widget>[
            QuestionSerialBadge(
              serialNo: child.serialNo,
              dense: true,
              copyable: false,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _questionRelationPreview(child),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium,
              ),
            ),
            Icon(
              Icons.chevron_right,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

/// 关联行的预览文字：优先题名，没有就压成一行的题干。
String _questionRelationPreview(Question question) {
  final title = (question.title ?? '').trim();
  if (title.isNotEmpty) {
    return title;
  }
  final stem = question.stem.replaceAll(RegExp(r'\s+'), ' ').trim();
  return stem.isEmpty ? '—' : stem;
}

/// 打开关联题目：母题 / 扩展题都是"往下钻一层"，用 push。
///
/// 与同层翻页的 `pushReplacement`（见 `_openNeighbor`）不同：从母题返回时
/// 应该回到当前这道题，而不是被换掉。
void _openQuestionDetail(BuildContext context, String questionId) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => QuestionDetailPage(questionId: questionId),
    ),
  );
}

/// 自测判分后的结果横幅：对/错 +（答错时）正确选项 label。
class _SelfTestResultBanner extends StatelessWidget {
  const _SelfTestResultBanner({required this.result});

  final ObjectiveAttemptResult result;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final correct = result.isCorrect;
    final background = correct
        ? theme.colorScheme.primaryContainer
        : theme.colorScheme.errorContainer;
    final foreground = correct
        ? theme.colorScheme.onPrimaryContainer
        : theme.colorScheme.onErrorContainer;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            correct ? Icons.check_circle_outline : Icons.cancel_outlined,
            color: foreground,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  correct
                      ? l10n.questionDetailSelfTestCorrect
                      : l10n.questionDetailSelfTestIncorrect,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                // 答对时不重复「正确答案：B」——那行只在答错时帮忙定位。
                if (result.isIncorrect)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      l10n.questionDetailSelfTestCorrectLabels(
                        result.correctLabels.join('、'),
                      ),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: foreground,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 自测历史摘要：做过几次、对几次、最近一次何时对/错。
///
/// 读 [questionAttemptHistoryProvider]（落库后经 `DataChangeBus` 自动重读）；
/// 加载中、读失败、或一次都没做过时**整块不渲染**——空白占位只会让页面更乱。
///
/// 展开状态是本组件的本地状态（不落库、不进 provider）：离开页面再回来，
/// 历史行回到收起的默认样子。
class _AttemptHistoryLine extends ConsumerStatefulWidget {
  const _AttemptHistoryLine({required this.questionId});

  final String questionId;

  @override
  ConsumerState<_AttemptHistoryLine> createState() =>
      _AttemptHistoryLineState();
}

class _AttemptHistoryLineState extends ConsumerState<_AttemptHistoryLine> {
  /// 是否展开了逐条明细。
  bool _expanded = false;

  /// 删除请求在飞：防重入，也把按钮禁掉避免连点。
  bool _clearing = false;

  /// 正在删除的明细行 id；非 null 时所有单条删除按钮禁用（防连点）。
  String? _deletingEntryId;

  /// 清除本题全部作答记录：先确认，再删；失败只弹提示，不动页面。
  ///
  /// 删除成功后显式失效 [questionAttemptHistoryProvider]——生产里写库会经
  /// `DataChangeBus` 自动重读，但测试（以及没装写拦截器的环境）没有那层，
  /// 题号行必须自己消失，不能等下一次页面重建。
  Future<void> _clearRecords() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.questionDetailAttemptClearConfirmTitle),
        content: Text(l10n.questionDetailAttemptClearConfirmBody),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.questionDetailAttemptClearAction),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    setState(() => _clearing = true);
    try {
      await ProviderScope.containerOf(context, listen: false)
          .read(questionAttemptRepositoryProvider)
          .deleteForQuestion(widget.questionId);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _clearing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.questionDetailAttemptClearFailed('$error')),
        ),
      );
      return;
    }
    if (!mounted) {
      return;
    }
    ref.invalidate(questionAttemptHistoryProvider(widget.questionId));
    setState(() {
      _clearing = false;
      _expanded = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.questionDetailAttemptClearDone)),
    );
  }

  /// 删除明细里的单条作答记录：成功刷新历史，失败只提示、行不动。
  ///
  /// 只删这一行（[QuestionAttemptRepository.deleteAttempt]）；成功后显式失效
  /// [questionAttemptHistoryProvider]——测试环境没有写拦截器，行必须自己消失。
  Future<void> _deleteEntry(String entryId) async {
    if (_deletingEntryId != null) {
      return;
    }
    final l10n = AppLocalizations.of(context);
    setState(() => _deletingEntryId = entryId);
    try {
      await ProviderScope.containerOf(context, listen: false)
          .read(questionAttemptRepositoryProvider)
          .deleteAttempt(entryId);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _deletingEntryId = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.questionDetailAttemptEntryDeleteFailed('$error')),
        ),
      );
      return;
    }
    if (!mounted) {
      return;
    }
    ref.invalidate(questionAttemptHistoryProvider(widget.questionId));
    setState(() => _deletingEntryId = null);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.questionDetailAttemptEntryDeleteDone)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final history = ref
        .watch(questionAttemptHistoryProvider(widget.questionId))
        .valueOrNull;
    if (history == null || history.isEmpty) {
      return const SizedBox.shrink();
    }
    final latest = history.latest!;
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final at = _formatAttemptTime(latest.attemptedAt);
    return Padding(
      key: questionAttemptHistoryKey,
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            l10n.questionDetailAttemptHistory(history.total, history.correct),
            style: muted,
          ),
          const SizedBox(height: 2),
          Text(
            latest.isCorrect
                ? l10n.questionDetailAttemptLastCorrect(at)
                : l10n.questionDetailAttemptLastIncorrect(at),
            style: muted,
          ),
          // 两个次级动作放同一行；窄屏时 Wrap 自己折行，不挤成溢出。
          Wrap(
            spacing: 4,
            children: <Widget>[
              TextButton(
                key: questionAttemptDetailToggleKey,
                onPressed: () => setState(() => _expanded = !_expanded),
                child: Text(
                  _expanded
                      ? l10n.questionDetailAttemptDetailHide
                      : l10n.questionDetailAttemptDetailToggle(history.total),
                ),
              ),
              TextButton(
                key: questionAttemptClearKey,
                onPressed: _clearing ? null : _clearRecords,
                child: Text(l10n.questionDetailAttemptClearAction),
              ),
            ],
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  for (final entry in history.entries)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Row(
                        key: questionAttemptEntryKeyFor(entry.id),
                        children: <Widget>[
                          Text(
                            _formatAttemptTime(entry.attemptedAt),
                            style: muted,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            entry.isCorrect
                                ? l10n.questionDetailSelfTestCorrect
                                : l10n.questionDetailSelfTestIncorrect,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: entry.isCorrect
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.error,
                            ),
                          ),
                          const Spacer(),
                          // 弱于内容的单条删除：小图标、紧凑点按区，整组防连点。
                          IconButton(
                            key: questionAttemptEntryDeleteKeyFor(entry.id),
                            onPressed: _deletingEntryId == null
                                ? () => _deleteEntry(entry.id)
                                : null,
                            tooltip:
                                l10n.questionDetailAttemptEntryDeleteTooltip,
                            icon: const Icon(Icons.delete_outline, size: 16),
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 28,
                              minHeight: 28,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// 自测历史里的时间：`yyyy-MM-dd HH:mm`（本地时区，与任务详情页同一写法）。
String _formatAttemptTime(DateTime at) {
  String pad(int value) => value.toString().padLeft(2, '0');
  return '${at.year}-${pad(at.month)}-${pad(at.day)} '
      '${pad(at.hour)}:${pad(at.minute)}';
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
  const _QuestionStemView({
    required this.questionId,
    required this.stem,
    this.markdown = false,
  });

  final String questionId;
  final String stem;

  /// 题目是否为 Markdown 文本；true 时文字段整段渲染（图片段不变）。
  final bool markdown;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final images = ref.watch(questionImagesProvider(questionId)).valueOrNull;

    // B0：文件名带 `fullcard_` 前缀的是「整卡截图」，不看像素尺寸直接按
    // snapshot 排版（正文占位中性化成「…」，整图跟到末尾）。
    final hasFullcardImage = images != null &&
        images.any(
          (image) =>
              image.fileName.trim().toLowerCase().startsWith('fullcard_'),
        );

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
      hasFullcardImage: hasFullcardImage,
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
        ),
      );
    }

    // 多图题（化学 Q15 的 18 处公式图这类）：把占位翻成行内 Markdown 图片，
    // 交给统一渲染器排版，避免题面被切成「一列大图 + 碎文字」。
    //
    // 注意**不能**沿用快照判定：`planQuestionStemRender` 把「有一张 >= 1000×400
    // 的大图」当整卡截图，而导入的公式图是同一字号放大导出的（化学 Q15 有
    // 2624×1408、2912×576 这类），18 张里任何一张都会把整题误判成快照，于是
    // 公式图全被堆到正文末尾。显式 `fullcard_` 标记仍按快照处理；多图题一律
    // 走行内排版。
    if (markdown && images != null && images.length >= 2 && !hasFullcardImage) {
      return KeyedSubtree(
        key: questionStemImagesKey,
        child: QuestionMarkdownTextWithImages(
          questionId: questionId,
          text: stem,
          style: theme.textTheme.titleMedium,
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
              child: MarkdownQuestionText(
                text: segment.text,
                style: theme.textTheme.titleMedium,
                markdown: markdown,
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
      ],
    );
  }
}

/// 「思维 DAG」版块：AI 解题产出的分步链 + 卡点评估 + 挂载的知识点。
///
/// 链是派生数据（`reasoning_chains` / `reasoning_steps`），同一道题可以有多条；
/// 这里只读库里最新一条、或本次刚跑出来的那条。**没有链时版块照样在**：标题 +
/// 一句「暂无」，让人知道"这块还没处理"，而不是一块凭空消失的版面。
class _DagSection extends ConsumerWidget {
  const _DagSection({
    super.key,
    required this.questionId,
    required this.lastRun,
  });

  final String questionId;
  final ReasoningRunResult? lastRun;

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
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.questionDetailDagSection,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                if (chain != null)
                  Text(
                    l10n.questionDetailDagStepCount(chain.steps.length),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
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

/// AI 解题版块：跑解题的按钮 + 失败面。
///
/// 链与卡点评估在「思维 DAG」版块展示——同一份链不在两处重复画。按钮的文案
/// 跟着"库里有没有链"变（解一次 / 再解一次），所以这里仍要读一次链读数。
class _ReasoningSection extends ConsumerWidget {
  const _ReasoningSection({
    super.key,
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
    final chain = lastRun?.chain ?? stored?.chain;

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
  const _LabelledText({
    required this.label,
    required this.value,
    this.markdown = false,
  });

  final String label;
  final String value;

  /// 题目声明为 Markdown 时整段渲染（答案/解析/理由跟随）；推理链等页面
  /// 自有文本用缺省 false，保持原口径。
  final bool markdown;

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
          MarkdownQuestionText(text: value, markdown: markdown),
        ],
      ),
    );
  }
}

/// 找相似题：只从**已有题库**里找。领域层已经排好序、写好理由，这里不改顺序、
/// 不复算分量、不把 `score` 当百分比——只画 `reasonZh` 与「跨学科迁移」角标。
///
/// 一道都不像时（空列表）只给空态（并提示把照片或题目发给「智能化」助手）：
/// **不许拿"看着像"的题凑数**，这是本片用户口径里最硬的一条。
class _SimilarQuestionsSection extends ConsumerWidget {
  const _SimilarQuestionsSection({super.key, required this.questionId});

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
    // 只靠题干字符串的列表统一走「一行显示文本」：快照题显示摘录/标签，
    // 不再把「［图N］」原始占位吐出来。
    final displays = ref.watch(questionStemDisplayProvider);
    final display = displays.valueOrNull?[similar.questionId];
    final displayText = display?.text.trim() ?? '';
    final loadingStem = displays.isLoading && !displays.hasValue;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Row(
        children: [
          // 候选的号是异步读的（列表数据源里没有 serialNo）；读不到显示「未编号」。
          QuestionSerialBadgeById(questionId: similar.questionId),
          const SizedBox(width: 8),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Flexible(
                  child: Text(
                    loadingStem
                        ? '…'
                        : (displayText.isEmpty
                            ? l10n.questionDetailQuestionMissing
                            : displayText),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // 快照题有正文摘录时才补徽标（无摘录时 text 本身就是标签）。
                if (display != null &&
                    display.isSnapshot &&
                    display.hasExcerpt) ...[
                  const SizedBox(width: 6),
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      l10n.questionBankSnapshotBadge,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ],
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

/// 「元数据」版块：来源说明 / 年份 / 地区 / 题型 / 难度 / 能力点 / 标签。
///
/// 只摆库里**已有**的字段。`state` / `origin` / `aiQuality` / 来源分级 / 内部
/// id 这些开发字段仍在「开发者信息」页，不搬到学生页。没有值的行写「暂无」，
/// 不猜、不补——「没标注」本身就是要让人看见的信息。
class _QuestionMetadataSection extends ConsumerWidget {
  const _QuestionMetadataSection({super.key, required this.question});

  final Question question;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final tags = ref.watch(questionTagsProvider(question.id)).valueOrNull;
    final codes = decodeQuestionCapability(question.capability);
    final none = l10n.questionDetailMetadataNone;
    final sourceLabel = question.sourceLabel.trim();
    final region = (question.region ?? '').trim();
    final difficulty = question.difficulty;
    final year = question.year;
    final tagPaths = <String>[
      for (final tag in tags ?? const <Tag>[])
        (tag.path?.trim().isNotEmpty ?? false)
            ? tag.path!.trim()
            : tag.name.trim(),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.questionDetailMetadataSection,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            _MetadataRow(
              label: l10n.questionIntakeSourceLabelLabel,
              value: sourceLabel.isEmpty ? none : sourceLabel,
            ),
            _MetadataRow(
              label: l10n.questionIntakeYearLabel,
              value: year == null ? none : l10n.questionDetailYear(year),
            ),
            _MetadataRow(
              label: l10n.questionIntakeRegionLabel,
              value: region.isEmpty ? none : region,
            ),
            _MetadataRow(
              label: l10n.questionIntakeQuestionTypeLabel,
              value: question.questionType.trim().isEmpty
                  ? none
                  : questionTypeLabelZh(question.questionType),
            ),
            _MetadataRow(
              label: l10n.questionDetailMetadataDifficulty,
              value: difficulty == null
                  ? none
                  : '${_formatDifficultyValue(difficulty)}/10',
            ),
            const SizedBox(height: 10),
            if (codes.isEmpty)
              _MetadataRow(
                label: l10n.questionCapabilitySection,
                value: none,
              )
            else
              _QuestionCapabilityChips(codes: codes),
            const SizedBox(height: 10),
            Text(
              l10n.questionDetailMetadataTags,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            if (tagPaths.isEmpty)
              Text(none, style: theme.textTheme.bodyMedium)
            else
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: <Widget>[
                  for (final path in tagPaths)
                    Chip(
                      label: Text(path),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      side: BorderSide(color: theme.colorScheme.outlineVariant),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// 难度值的展示：整数不带小数点，带小数的保留一位。
String _formatDifficultyValue(double value) =>
    value == value.roundToDouble()
        ? value.round().toString()
        : value.toStringAsFixed(1);

/// 元数据里的一行「标签 + 值」：标签固定宽度，值占满剩余宽度并自动换行。
class _MetadataRow extends StatelessWidget {
  const _MetadataRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(value, style: theme.textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

/// 「来源文件与来源包」版块。
///
/// 数据只有两类真实来源：
///  * `content_refs`：导入时登记的内容包/整卷引用（题目 role=`source_package`，
///    整卷导入的 content_id 形如 `<paperKey>#Q<n>`），引用摘要里可能带来源图
///    文件路径；这里只读引用行，不复制正文；
///  * `questions.source_url`：原题链接（可复制，不引入 url_launcher）。
///
/// 两者都没有就写「暂无」。组卷网检索入口也放在这里：它只对组卷网有列表页的
/// 学科出现（信息学/历史/算法竞赛这类题不摆，见 `question_zujuan_search.dart`）。
class _QuestionSourceSection extends ConsumerWidget {
  const _QuestionSourceSection({super.key, required this.question});

  final Question question;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final refsAsync = ref.watch(questionContentRefsProvider(question.id));
    final source = questionSourceFor(
      sourceUrl: question.sourceUrl,
      zujuanQuestionId: question.zujuanQuestionId,
      zujuanBankId: question.zujuanBankId,
    );
    final refs = refsAsync.valueOrNull;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  Icons.folder_open_outlined,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  l10n.questionDetailSourceSection,
                  style: theme.textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 4),
            if (source == null)
              _MetadataRow(
                label: l10n.questionDetailOriginalLink,
                value: l10n.questionDetailMetadataNone,
              )
            else ...[
              _MetadataRow(
                label: l10n.questionDetailOriginalLink,
                value: source.url,
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: questionDetailSourceCopyKey,
                  onPressed: () => _copySourceUrl(context, source.url),
                  icon: const Icon(Icons.copy_outlined, size: 16),
                  label: Text(l10n.questionDetailCopyLink),
                ),
              ),
            ],
            const SizedBox(height: 8),
            if (refsAsync.isLoading && !refsAsync.hasValue)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: LinearProgressIndicator(),
              )
            else if (refsAsync.hasError)
              Text(l10n.questionDetailSourceFailed('${refsAsync.error}'))
            else if (refs == null || refs.isEmpty)
              Text(
                l10n.questionDetailSourceEmpty,
                style: theme.textTheme.bodyMedium,
              )
            else ...[
              Text(
                l10n.questionDetailSourcePackage,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              for (final ref in refs) _SourceRefView(sourceRef: ref),
            ],
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: QuestionZujuanSearchButton(
                stem: question.stem,
                subjectKey: question.subjectKey,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 复制原题链接：仓库约定不引入 url_launcher，复制后提示去浏览器粘贴。
Future<void> _copySourceUrl(BuildContext context, String url) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  await Clipboard.setData(ClipboardData(text: url));
  if (!context.mounted) {
    return;
  }
  messenger.showSnackBar(SnackBar(content: Text(l10n.questionSourceCopyDone)));
}

/// 一条来源引用：内容 id + 引用摘要（整卷标题/来源说明/年份/地区/版本）+
/// 来源图文件路径。摘要解析失败只少一行，不影响版块其余部分。
class _SourceRefView extends StatelessWidget {
  const _SourceRefView({required this.sourceRef});

  final ContentRefRow sourceRef;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final summary = _sourceRefSummary(sourceRef);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SelectableText(
            sourceRef.contentId,
            style: theme.textTheme.bodyMedium,
          ),
          if (summary.parts.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                summary.parts.join(' · '),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          if (summary.figurePaths.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '${l10n.questionDetailSourceFile}：${summary.figurePaths.join('、')}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 一条来源引用里能展示的摘要（都来自 `metadata_json` 与版本列，不复制正文）。
class _SourceRefSummary {
  const _SourceRefSummary({required this.parts, required this.figurePaths});

  /// 整卷标题/来源说明/年份/地区/版本这类一行摘要。
  final List<String> parts;

  /// 引用摘要里登记的来源图文件路径。
  final List<String> figurePaths;
}

_SourceRefSummary _sourceRefSummary(ContentRefRow sourceRef) {
  Map<String, Object?>? metadata;
  final raw = sourceRef.metadataJson;
  if (raw != null && raw.trim().isNotEmpty) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, Object?>) {
        metadata = decoded;
      }
    } on FormatException {
      // 摘要只是引用信息，坏了就少显示一行，不影响页面。
    }
  }
  String textOf(String key) {
    final value = metadata?[key];
    if (value is String) {
      return value.trim();
    }
    return value is num ? value.toString() : '';
  }

  final parts = <String>[
    if (textOf('paper_title').isNotEmpty) textOf('paper_title'),
    if (textOf('source_label').isNotEmpty) textOf('source_label'),
    if (textOf('subject').isNotEmpty) textOf('subject'),
    if (textOf('year').isNotEmpty) textOf('year'),
    if (textOf('region').isNotEmpty) textOf('region'),
    if (sourceRef.contentVersion != null)
      'v${sourceRef.contentVersion}',
    if (sourceRef.contentHash != null && sourceRef.contentHash!.isNotEmpty)
      'hash ${sourceRef.contentHash!.substring(0, sourceRef.contentHash!.length > 12 ? 12 : sourceRef.contentHash!.length)}…',
  ];
  final figures = <String>[];
  final rawFigures = metadata?['figures'];
  if (rawFigures is List) {
    for (final figure in rawFigures) {
      if (figure is Map) {
        final path = figure['path'];
        if (path is String && path.trim().isNotEmpty) {
          figures.add(path.trim());
        }
      }
    }
  }
  return _SourceRefSummary(parts: parts, figurePaths: figures);
}

/// 「MindNet 认知评价」卡片：题目内容 × 认知模型的第一块可测界面。
///
/// 只读：数据全来自 [questionCognitiveReadingProvider]，卡片不写库、不调模型。
/// 加载中/读库失败时整块零高度（附加读数不该挡住详情页）；空态显示一句
/// 「还读不到」，不编一行数。
class QuestionCognitiveSection extends ConsumerWidget {
  const QuestionCognitiveSection({super.key, required this.questionId});

  final String questionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final reading =
        ref.watch(questionCognitiveReadingProvider(questionId)).valueOrNull;
    if (reading == null) {
      return const SizedBox.shrink();
    }

    return Card(
      key: questionCognitiveSectionKey,
      margin: const EdgeInsets.only(top: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  Icons.hub_outlined,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  l10n.questionCognitiveTitle,
                  style: theme.textTheme.titleSmall,
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (reading.isEmpty)
              Text(l10n.questionCognitiveEmpty,
                  style: theme.textTheme.bodySmall)
            else ...<Widget>[
              Text(l10n.questionCognitiveZone(zoneLabel(l10n, reading.zone))),
              const SizedBox(height: 4),
              Text(
                l10n.questionCognitiveFit(cognitiveFitLabel(reading.verdict!)),
              ),
              if (reading.hasPrior) ...<Widget>[
                const SizedBox(height: 4),
                Text(
                  l10n.cognitiveEncodingPrior(
                    reading.priorR0!.toStringAsFixed(2),
                  ),
                ),
              ],
              if (reading.reason.trim().isNotEmpty)
                _LabelledText(
                  label: l10n.questionCognitiveReason,
                  value: reading.reason,
                ),
              _LabelledText(
                label: l10n.questionCognitiveAdvice,
                value: cognitiveAdviceLabel(reading.suggestion),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              l10n.questionCognitiveUncalibrated,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 六种判词的中文短标签。
///
/// l10n 目前只有 `questionCognitiveFit(verdict)` 模板、没有逐值键（本任务也
/// 不改 ARB），所以具体措辞先放在这里；将来给六种判词加 ARB 键时整段迁走。
String cognitiveFitLabel(ProblemVerdict verdict) => switch (verdict) {
      ProblemVerdict.tooEasy => '已经会了，复习收益低',
      ProblemVerdict.zpd => '发展中区，可做',
      ProblemVerdict.tooHard => '偏难，现在做是硬啃',
      ProblemVerdict.outOfScope => '超纲或死角',
      ProblemVerdict.redundant => '与已有内容重复',
      ProblemVerdict.highValue => '值得现在做',
    };

/// 建议的中文短标签（同上：l10n 没有逐值键）。
String cognitiveAdviceLabel(QuestionCognitiveSuggestion suggestion) =>
    switch (suggestion) {
      QuestionCognitiveSuggestion.practiceNow => '现在练',
      QuestionCognitiveSuggestion.buildPrior => '先补先验（危险区，先复习/先测评）',
      QuestionCognitiveSuggestion.postpone => '暂缓',
      QuestionCognitiveSuggestion.keepPlan => '按计划练',
    };
