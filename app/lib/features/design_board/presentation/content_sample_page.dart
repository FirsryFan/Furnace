import 'package:flutter/material.dart';

import '../domain/design_board.dart';
import '../domain/feedback_answer_composer.dart';
import 'developer_info_page.dart';

/// Student-facing, print-friendly view of one real content sample.
///
/// 2026-11-15 user rule: 学生页只放学生要读的东西 ——
/// 题干 · 图（有才显示，没图不写“无附图”）· 答题区（选择/填空不给，解答题给）
/// → 我有问题（学生先做题，卡住时再问，按这道题的内容组织回答）
/// → Thinking DAG（短节点 + 公式/关键量/结论）→ 答案 → 解析原文
/// → 诊断（题眼/陷阱/错因/卡点/分层提示合并）→ 训练（额外任务→变式→同源题）
/// → 扩展资料 / 学科史 → 另一种答案与理由【AI】。
///
/// task-96: 板块的有无/顺序由 `LegacyBoardMapper` 的选板结果
/// ([DesignBoardCard.boardSelection]) 决定，页面不再按旧 9 板块硬渲染：
/// - 简单题不显示 Thinking DAG / 过程解析（解析原文）/ 卡点 / 分层提示；
/// - 复杂题才显示；
/// - L2 五条合并成一个“诊断”块；
/// - L3 固定“额外任务 → 变式 → 同源题”；
/// - L4 拆“扩展资料 / 学科史”；
/// - L5 元信息不进学生正文；空板块不占位（没有“暂无”卡片）。
/// 旧 asset（没有 boardSelection）时回落到旧布局，不让页面消失。
///
/// 简单题不自动展开 DAG/答案/解析：这些卡片默认折叠，学生先自己做；只有主动
/// 提问或点开时才看到解析内容。
///
/// Report wording (trust/hash/evidence/盲解/“不写进主链”) and the old technical
/// sections live in [DeveloperInfoPage]; they are not part of the student view.
class ContentSamplePage extends StatelessWidget {
  const ContentSamplePage({super.key, required this.sample});

  final DesignBoardCard sample;

  @override
  Widget build(BuildContext context) {
    final content = sample.studentContent;
    return Scaffold(
      appBar: AppBar(title: const Text('题目详情')),
      body: content == null
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('这道题暂时没有学生视图内容'),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: _studentSections(context, content),
            ),
    );
  }

  /// 选板结果驱动的学生页区块（按 L0→L4 顺序；空板块不占位）。
  List<Widget> _studentSections(BuildContext context, StudentContent content) {
    final selection = sample.boardSelection;
    final legacy = selection == null;
    final hasDag = legacy
        ? sample.dagGraph != null
        : selection.hasBoard('l1_thinking_dag') && sample.dagGraph != null;
    final hasWalkthrough =
        legacy || selection.hasBoard('l1_solution_walkthrough');
    // 只有《高考试题分析》来源有解析原文；简单题选板不含过程解析，不显示。
    final showSolution = content.showSourceAnalysis && hasWalkthrough;
    final diagnostic = _panelsAtLevel(content.panels, 'L2');
    final training = _panelsAtLevel(content.panels, 'L3');
    final extensionPanels = _panelsWithBoard(
      content.panels,
      'l4_extension_material',
    );
    final historyPanels = _panelsWithBoard(
      content.panels,
      'l4_subject_history',
    );
    final stuckPoints = !legacy && selection.hasBoard('l2_stuck_points');

    return <Widget>[
      _StemCard(content: content, sampleId: sample.id),
      if (content.needsAnswerArea)
        _AnswerAreaCard(
          sampleId: sample.id,
          heightMm: content.answerAreaHeightMm,
        ),
      _FeedbackCard(
        sampleId: sample.id,
        content: content,
        // 简单题没有 DAG：提问只按错因/答案组织，不编步骤。
        graph: hasDag ? sample.dagGraph : null,
      ),
      if (hasDag) _DagStudentCard(graph: sample.dagGraph!, sampleId: sample.id),
      _CollapsedAnswerCard(
        sampleId: sample.id,
        answer: content.answer,
      ),
      if (showSolution)
        _CollapsedSolutionCard(
          sampleId: sample.id,
          solution: content.solution,
          note: content.solutionNote,
        ),
      if (legacy) ...[
        _SectionCard(
          title: '分层提示',
          child: _HintContent(panels: content.panels),
        ),
        _BoardsSection(
          panels: content.panels,
          upperKnowledge: content.upperKnowledge,
        ),
      ] else ...[
        if (diagnostic.isNotEmpty)
          _DiagnosticSection(
            panels: diagnostic,
            graph: sample.dagGraph,
            showStuckPoints: stuckPoints,
            sampleId: sample.id,
          ),
        if (training.isNotEmpty)
          _TrainingSection(panels: training, sampleId: sample.id),
        if (extensionPanels.isNotEmpty || content.upperKnowledge.isNotEmpty)
          _ExtensionSection(
            panels: extensionPanels,
            upperKnowledge: content.upperKnowledge,
            sampleId: sample.id,
          ),
        if (historyPanels.isNotEmpty)
          _SubjectHistorySection(panels: historyPanels, sampleId: sample.id),
      ],
      _AiAnswerCard(ai: content.aiAnswer),
      const SizedBox(height: 12),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          key: Key('open-developer-info-${sample.id}'),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (context) => DeveloperInfoPage(sample: sample),
            ),
          ),
          icon: const Icon(Icons.info_outline, size: 18),
          label: const Text('开发者信息'),
        ),
      ),
    ];
  }
}

/// 某一层（L0–L5）被选中的板块面板，保持 asset 里的顺序。
List<StudentPanel> _panelsAtLevel(List<StudentPanel> panels, String level) =>
    <StudentPanel>[
      for (final panel in panels)
        if (panel.level == level) panel,
    ];

/// 指定板块 id 的面板（L4 两个子类用它区分扩展资料/学科史）。
List<StudentPanel> _panelsWithBoard(
  List<StudentPanel> panels,
  String boardId,
) =>
    <StudentPanel>[
      for (final panel in panels)
        if (panel.boardId == boardId) panel,
    ];

class _SectionCard extends StatelessWidget {
  const _SectionCard({super.key, required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: Colors.black26),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}

/// 题干块：题干全文 + 图（有则显示）。没有图时这里什么都不加，不写“无附图”。
class _StemCard extends StatelessWidget {
  const _StemCard({required this.content, required this.sampleId});

  final StudentContent content;
  final String sampleId;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: '题干',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            content.stem,
            style: const TextStyle(fontSize: 14, height: 1.5),
          ),
          for (final figure in content.figures) ...[
            const SizedBox(height: 12),
            _FigureBlock(figure: figure, sampleId: sampleId),
          ],
        ],
      ),
    );
  }
}

/// 题干图：只渲染已打包的 asset；图注有就写一行，没有就不写。
class _FigureBlock extends StatelessWidget {
  const _FigureBlock({required this.figure, required this.sampleId});

  final StudentFigure figure;
  final String sampleId;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: Key('figure-$sampleId'),
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Image.asset(
          figure.path,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
        ),
        if (figure.caption.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            figure.caption,
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ],
      ],
    );
  }
}

/// 答题区：解答题给一块**空白边框**区域（无横线）；选择/填空不渲染本卡片。
///
/// 高度来自内容包投影（按分值/小问数），页面只画边框，不写“预留 N 行/高度估算”。
class _AnswerAreaCard extends StatelessWidget {
  const _AnswerAreaCard({required this.sampleId, required this.heightMm});

  final String sampleId;
  final double heightMm;

  /// 1 mm ≈ 96/25.4 逻辑像素（屏幕预览；真实打印排版由导出器按毫米处理）。
  static const double _logicalPxPerMm = 96 / 25.4;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: '答题区',
      child: Container(
        key: Key('answer-area-$sampleId'),
        width: double.infinity,
        height: heightMm * _logicalPxPerMm,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.black54, width: 0.8),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

/// Solution is collapsed by default so it does not leak the answer before the
/// student has attempted the question.
class _CollapsedSolutionCard extends StatelessWidget {
  const _CollapsedSolutionCard({
    required this.sampleId,
    required this.solution,
    required this.note,
  });

  final String sampleId;
  final String solution;
  final String note;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: Colors.black26),
      ),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        key: Key('solution-panel-$sampleId'),
        tilePadding: const EdgeInsets.symmetric(horizontal: 14),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        title: const Text(
          '解析原文（据解析卷，对完答案再看）',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            height: 1.3,
          ),
        ),
        children: [
          Column(
            key: Key('solution-content-$sampleId'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                solution,
                style: const TextStyle(fontSize: 13, height: 1.6),
              ),
              const SizedBox(height: 6),
              Text(
                note,
                style: const TextStyle(fontSize: 11, color: Colors.black54),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Answer is collapsed by default: students should attempt the problem before
/// seeing it (learner-review P0 "先做题再看答案").
class _CollapsedAnswerCard extends StatelessWidget {
  const _CollapsedAnswerCard({required this.sampleId, required this.answer});

  final String sampleId;
  final String answer;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: Colors.black26),
      ),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        key: Key('answer-panel-$sampleId'),
        tilePadding: const EdgeInsets.symmetric(horizontal: 14),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        title: const Text(
          '答案（先自己做，再看答案）',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            height: 1.3,
          ),
        ),
        children: [
          Text(
            answer,
            key: Key('answer-content-$sampleId'),
            style: const TextStyle(
              fontSize: 16,
              height: 1.45,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _HintContent extends StatelessWidget {
  const _HintContent({required this.panels});

  final List<StudentPanel> panels;

  @override
  Widget build(BuildContext context) {
    final hints = panels.where((panel) => panel.title == '分层提示').toList();
    if (hints.isEmpty || hints.first.items.isEmpty) {
      return const Text('暂无', style: TextStyle(fontSize: 13, height: 1.5));
    }
    return _Bullets(items: hints.first.items);
  }
}

const TextStyle _subsectionTitleStyle = TextStyle(
  fontSize: 13,
  fontWeight: FontWeight.w600,
  height: 1.3,
);

/// 一个板块的小节：标题 + 条目（空板块不会走到这里）。
class _BoardSubsection extends StatelessWidget {
  const _BoardSubsection({required this.panel});

  final StudentPanel panel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Text(panel.title, style: _subsectionTitleStyle),
        const SizedBox(height: 4),
        _Bullets(items: panel.items),
      ],
    );
  }
}

/// L2 诊断层：题眼/陷阱/错因/卡点/分层提示合并为一块（2026-11-15 task-96）。
///
/// 只渲染选板结果里选中且内容非空的条目；简单题没有卡点/分层提示，就不出现。
class _DiagnosticSection extends StatelessWidget {
  const _DiagnosticSection({
    required this.panels,
    required this.graph,
    required this.showStuckPoints,
    required this.sampleId,
  });

  final List<StudentPanel> panels;
  final DagGraph? graph;
  final bool showStuckPoints;
  final String sampleId;

  @override
  Widget build(BuildContext context) {
    final graph = this.graph;
    // 卡点（旧内容里由 failed_branches 派生）只在选板结果含 l2_stuck_points 时出现。
    final branches = showStuckPoints && graph != null
        ? graph.failureBranches
        : const <DagFailureBranch>[];
    return _SectionCard(
      key: Key('diagnostic-section-$sampleId'),
      title: '诊断',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final panel in panels) _BoardSubsection(panel: panel),
          if (branches.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text('卡点', style: _subsectionTitleStyle),
            for (final branch in branches) ...[
              const SizedBox(height: 6),
              _FailureBranchCard(branch: branch),
            ],
          ],
        ],
      ),
    );
  }
}

/// L3 训练层：额外任务 → 变式 → 同源题（顺序由选板结果的 order 固定）。
class _TrainingSection extends StatelessWidget {
  const _TrainingSection({required this.panels, required this.sampleId});

  final List<StudentPanel> panels;
  final String sampleId;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      key: Key('training-section-$sampleId'),
      title: '训练（由近及远）',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final panel in panels) _BoardSubsection(panel: panel),
        ],
      ),
    );
  }
}

/// L4 背景层之一：扩展资料（有上位知识全文块就按全文块渲染）。
class _ExtensionSection extends StatelessWidget {
  const _ExtensionSection({
    required this.panels,
    required this.upperKnowledge,
    required this.sampleId,
  });

  final List<StudentPanel> panels;
  final List<StudentKnowledge> upperKnowledge;
  final String sampleId;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      key: Key('extension-section-$sampleId'),
      title: '扩展资料',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (upperKnowledge.isNotEmpty)
            for (final item in upperKnowledge) _KnowledgeBlock(item: item)
          else
            for (final panel in panels)
              // 小节标题与块标题重名时不重复写一遍标题。
              if (panel.title == '扩展资料')
                _Bullets(items: panel.items)
              else
                _BoardSubsection(panel: panel),
        ],
      ),
    );
  }
}

/// L4 背景层之二：学科史。旧内容包没有来源时选板结果不选它，整个块不出现。
class _SubjectHistorySection extends StatelessWidget {
  const _SubjectHistorySection({
    required this.panels,
    required this.sampleId,
  });

  final List<StudentPanel> panels;
  final String sampleId;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      key: Key('subject-history-section-$sampleId'),
      title: '学科史',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final panel in panels)
            if (panel.title == '学科史')
              _Bullets(items: panel.items)
            else
              _BoardSubsection(panel: panel),
        ],
      ),
    );
  }
}

class _BoardsSection extends StatelessWidget {
  const _BoardsSection({
    required this.panels,
    required this.upperKnowledge,
  });

  final List<StudentPanel> panels;

  /// 上位知识全文块；有就按块渲染，不再用 240 字摘要截断。
  final List<StudentKnowledge> upperKnowledge;

  @override
  Widget build(BuildContext context) {
    final others = panels.where((panel) => panel.title != '分层提示').toList();
    return _SectionCard(
      title: '九板块内容',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final panel in others) ...[
            const SizedBox(height: 12),
            Text(
              panel.title,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 6),
            if (panel.title == '扩展/上位知识' && upperKnowledge.isNotEmpty)
              for (final item in upperKnowledge) _KnowledgeBlock(item: item)
            else if (panel.items.isEmpty)
              const Text('暂无', style: TextStyle(fontSize: 13))
            else
              _Bullets(items: panel.items),
          ],
        ],
      ),
    );
  }
}

/// 上位知识全文块：标题 + 是什么 / 为什么值得学 / 怎么用 / 搭建步骤 / 示例 / 限制。
class _KnowledgeBlock extends StatelessWidget {
  const _KnowledgeBlock({required this.item});

  final StudentKnowledge item;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black38),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.level.isEmpty ? item.title : '【${item.level}】${item.title}',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
          if (item.what.isNotEmpty) ...[
            const SizedBox(height: 6),
            _LabeledText(label: '是什么', text: item.what),
          ],
          if (item.why.isNotEmpty) ...[
            const SizedBox(height: 6),
            _LabeledText(label: '为什么值得学', text: item.why),
          ],
          if (item.how.isNotEmpty) ...[
            const SizedBox(height: 6),
            _LabeledText(label: '怎么用', text: item.how),
          ],
          if (item.buildSteps.isNotEmpty) ...[
            const SizedBox(height: 6),
            const Text(
              '搭建步骤',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.black54,
              ),
            ),
            for (var i = 0; i < item.buildSteps.length; i++) ...[
              const SizedBox(height: 3),
              Text(
                '${i + 1}. ${item.buildSteps[i]}',
                style: const TextStyle(fontSize: 13, height: 1.5),
              ),
            ],
          ],
          if (item.example.isNotEmpty) ...[
            const SizedBox(height: 6),
            _LabeledText(label: '示例', text: item.example),
          ],
          if (item.limitations.isNotEmpty) ...[
            const SizedBox(height: 6),
            _LabeledText(label: '限制', text: item.limitations),
          ],
        ],
      ),
    );
  }
}

class _Bullets extends StatelessWidget {
  const _Bullets({required this.items});

  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final item in items) ...[
          const SizedBox(height: 4),
          Text('· $item', style: const TextStyle(fontSize: 13, height: 1.55)),
        ],
      ],
    );
  }
}

class _AiAnswerCard extends StatelessWidget {
  const _AiAnswerCard({required this.ai});

  final StudentAiAnswer ai;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: '另一种答案与理由【AI】',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _LabeledText(label: '答案', text: ai.answer),
          const SizedBox(height: 8),
          _LabeledText(label: '为什么这样想', text: ai.reasoning),
          const SizedBox(height: 8),
          const _LabeledText(
            label: '请你判断',
            text: '你同意吗？哪一步有问题？',
          ),
        ],
      ),
    );
  }
}

class _LabeledText extends StatelessWidget {
  const _LabeledText({required this.label, required this.text});

  final String label;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.black54,
          ),
        ),
        const SizedBox(height: 3),
        Text(text, style: const TextStyle(fontSize: 13, height: 1.55)),
      ],
    );
  }
}

/// Vertical, print-friendly Thinking DAG flowchart (no colour, no horizontal
/// scrolling). Collapsed by default so students think first (learner-review P0).
///
/// 2026-11-15: 标题只写 “Thinking DAG”，不再附 “按逻辑顺序 / 先自己走一遍 /
/// N 个逻辑节点 / 未独立审核 / 无语义校验” 之类的解释文案；节点本身是
/// 短节点 + 公式 + 关键量 + 结论（前代思路图形态）。
class _DagStudentCard extends StatelessWidget {
  const _DagStudentCard({required this.graph, required this.sampleId});

  final DagGraph? graph;
  final String sampleId;

  @override
  Widget build(BuildContext context) {
    final graph = this.graph;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: Colors.black26),
      ),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        key: Key('dag-panel-$sampleId'),
        tilePadding: const EdgeInsets.symmetric(horizontal: 14),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        title: const Text(
          'Thinking DAG',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            height: 1.3,
          ),
        ),
        children: [
          if (graph == null)
            const Text('暂无')
          else ...[
            _DagFlow(graph: graph, key: Key('dag-flow-$sampleId')),
            if (graph.alternatePaths.isNotEmpty) ...[
              const SizedBox(height: 14),
              const Text(
                '另一条路',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                ),
              ),
              for (final path in graph.alternatePaths) ...[
                const SizedBox(height: 8),
                _AlternatePathCard(graph: graph, path: path),
              ],
            ],
          ],
        ],
      ),
    );
  }
}

class _DagFlow extends StatelessWidget {
  const _DagFlow({super.key, required this.graph});

  final DagGraph graph;

  @override
  Widget build(BuildContext context) {
    final layers = _buildLayers(graph);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < layers.length; i++) ...[
          if (i > 0) _DagConnector(branch: layers[i].length > 1),
          if (layers[i].length == 1)
            _DagNodeCard(node: layers[i].first)
          else
            Container(
              margin: const EdgeInsets.only(left: 20),
              padding: const EdgeInsets.only(left: 12),
              decoration: const BoxDecoration(
                border: Border(left: BorderSide(color: Colors.black26)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final node in layers[i]) ...[
                    _DagNodeCard(node: node),
                    if (node != layers[i].last) const SizedBox(height: 8),
                  ],
                ],
              ),
            ),
        ],
      ],
    );
  }
}

class _DagConnector extends StatelessWidget {
  const _DagConnector({required this.branch});

  final bool branch;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(width: 1, height: 10, color: Colors.black26),
        Text(
          branch ? '└ 分支' : '▼',
          style: const TextStyle(fontSize: 10, color: Colors.black54),
        ),
        Container(width: 1, height: 4, color: Colors.black26),
      ],
    );
  }
}

class _DagNodeCard extends StatelessWidget {
  const _DagNodeCard({required this.node});

  final DagNode node;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.black87, width: 0.8),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 1,
                ),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.black45),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  _semanticLabel(node.kind),
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            node.label,
            style: const TextStyle(
              fontSize: 13,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
          for (final formula in node.formulas) ...[
            const SizedBox(height: 5),
            Text(
              formula,
              style: const TextStyle(
                fontSize: 12,
                height: 1.4,
                fontFamily: 'monospace',
                color: Colors.black87,
              ),
            ),
          ],
          if (node.keyQuantities.isNotEmpty) ...[
            const SizedBox(height: 5),
            Text(
              '关键量：${node.keyQuantities.join('；')}',
              style: const TextStyle(fontSize: 11, height: 1.45),
            ),
          ],
          if (node.result.isNotEmpty) ...[
            const SizedBox(height: 5),
            Text(
              '结论：${node.result}',
              style: const TextStyle(
                fontSize: 11,
                height: 1.45,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One real alternate route from the content package (second method or an
/// unverified reading). No colour: a bordered block with the node sequence.
///
/// 2026-11-15: 只给方法名 + 节点路径；verdict/“不写进主链/得分口径”这类
/// 报告腔不再出现在学生页。
class _AlternatePathCard extends StatelessWidget {
  const _AlternatePathCard({required this.graph, required this.path});

  final DagGraph graph;
  final DagAlternatePath path;

  @override
  Widget build(BuildContext context) {
    final labels = <String, String>{
      for (final node in graph.nodes) node.id: node.label,
    };
    final sequence = path.nodeIds
        .map((id) => labels[id] ?? id)
        .where((label) => label.isNotEmpty)
        .join(' → ');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black54),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            path.methodName,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
          if (sequence.isNotEmpty) ...[
            const SizedBox(height: 5),
            Text(
              sequence,
              style: const TextStyle(fontSize: 11, height: 1.5),
            ),
          ],
        ],
      ),
    );
  }
}

class _FailureBranchCard extends StatelessWidget {
  const _FailureBranchCard({required this.branch});

  final DagFailureBranch branch;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black54),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        branch.why,
        style: const TextStyle(fontSize: 11, height: 1.5),
      ),
    );
  }
}

String _semanticLabel(String kind) => switch (kind) {
      'condition' => '审题',
      'goal' => '目标',
      'insight' => '洞察',
      'prerequisite_recall' => '回忆',
      'decision' => '判断',
      'check' => '验证/排除',
      'computation' => '计算',
      'formula_or_model' => '建模',
      'conclusion' => '结论',
      'verify' => '验证',
      _ => '步骤',
    };

/// Logical layering via longest path from the roots (DAG is acyclic after
/// task-51). Sibling nodes (e.g. 03→{04,05,06,07}) share a layer and are drawn
/// as a vertically stacked branch; the developer list keeps node ids.
List<List<DagNode>> _buildLayers(DagGraph graph) {
  final indegree = <String, int>{for (final node in graph.nodes) node.id: 0};
  final adjacency = <String, List<String>>{
    for (final node in graph.nodes) node.id: <String>[],
  };
  for (final edge in graph.edges) {
    if (!indegree.containsKey(edge.from) || !indegree.containsKey(edge.to)) {
      continue;
    }
    adjacency[edge.from]!.add(edge.to);
    indegree[edge.to] = indegree[edge.to]! + 1;
  }
  final layerOf = <String, int>{for (final node in graph.nodes) node.id: 0};
  final ready = <String>[
    for (final entry in indegree.entries)
      if (entry.value == 0) entry.key,
  ];
  var visited = 0;
  while (ready.isNotEmpty) {
    final node = ready.removeLast();
    visited++;
    for (final target in adjacency[node]!) {
      final candidate = layerOf[node]! + 1;
      if (candidate > layerOf[target]!) {
        layerOf[target] = candidate;
      }
      indegree[target] = indegree[target]! - 1;
      if (indegree[target] == 0) {
        ready.add(target);
      }
    }
  }
  if (visited != graph.nodes.length) {
    // Cyclic input should be rejected upstream; keep a safe render path.
    final byId = <int, List<DagNode>>{};
    for (var i = 0; i < graph.nodes.length; i++) {
      byId.putIfAbsent(i, () => <DagNode>[]).add(graph.nodes[i]);
    }
    return [for (final index in byId.keys.toList()..sort()) byId[index]!];
  }
  final byLayer = <int, List<DagNode>>{};
  for (final node in graph.nodes) {
    byLayer.putIfAbsent(layerOf[node.id]!, () => <DagNode>[]).add(node);
  }
  return [
    for (final index in byLayer.keys.toList()..sort()) byLayer[index]!,
  ];
}

const TextStyle _feedbackLabelStyle = TextStyle(
  fontSize: 12,
  fontWeight: FontWeight.w600,
  color: Colors.black54,
  height: 1.4,
);

/// “我有问题”入口：学生先做题，卡住时把问题写下来。
///
/// 默认折叠，不抢在答题前展开；回答只来自这道题已有的学生可见内容
/// （DAG 短节点 / 错因 / 答案），没有对应内容时明确说没有，不补写解析。
/// 保留已问过的记录，支持追问（短追问会继承上一轮的问题线索）。
class _FeedbackCard extends StatefulWidget {
  const _FeedbackCard({
    required this.sampleId,
    required this.content,
    required this.graph,
  });

  final String sampleId;
  final StudentContent content;
  final DagGraph? graph;

  @override
  State<_FeedbackCard> createState() => _FeedbackCardState();
}

class _FeedbackCardState extends State<_FeedbackCard> {
  static const FeedbackAnswerComposer _composer = FeedbackAnswerComposer();
  final TextEditingController _input = TextEditingController();
  final List<FeedbackExchange> _history = <FeedbackExchange>[];

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  List<String> get _errorCauses => <String>[
        for (final panel in widget.content.panels)
          if (panel.title == '错因') ...panel.items,
      ];

  void _submit() {
    final question = _input.text.trim();
    if (question.isEmpty) {
      return;
    }
    final answer = _composer.ask(
      question: question,
      stem: widget.content.stem,
      nodes: widget.graph?.nodes ?? const <DagNode>[],
      errorCauses: _errorCauses,
      answer: widget.content.answer,
      priorExchanges: _history,
    );
    setState(() {
      _history.add(FeedbackExchange(question: question, answer: answer));
      _input.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: Colors.black26),
      ),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        key: Key('feedback-panel-${widget.sampleId}'),
        tilePadding: const EdgeInsets.symmetric(horizontal: 14),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        title: const Text(
          '我有问题',
          style:
              TextStyle(fontSize: 15, fontWeight: FontWeight.w700, height: 1.3),
        ),
        subtitle: const Text(
          '做题时卡住就把问题写下来，按这道题的内容回答',
          style: TextStyle(fontSize: 12, height: 1.4),
        ),
        children: <Widget>[
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '例如：“为什么 C 不对？”“速度大小的表达式是什么？”',
              style:
                  TextStyle(fontSize: 12, color: Colors.black54, height: 1.5),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Expanded(
                child: TextField(
                  key: Key('feedback-input-${widget.sampleId}'),
                  controller: _input,
                  minLines: 1,
                  maxLines: 3,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _submit(),
                  style: const TextStyle(fontSize: 14, height: 1.4),
                  decoration: const InputDecoration(
                    hintText: '写下你的问题',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                key: Key('feedback-send-${widget.sampleId}'),
                onPressed: _submit,
                child: const Text('提问'),
              ),
            ],
          ),
          if (_history.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text(
                '还没有提问。',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ),
          for (var i = 0; i < _history.length; i++)
            _FeedbackExchangeView(
              sampleId: widget.sampleId,
              index: i,
              exchange: _history[i],
            ),
        ],
      ),
    );
  }
}

/// 一条已回答的问题：先复述问题，再给相关步骤/公式、结论、易错点。
class _FeedbackExchangeView extends StatelessWidget {
  const _FeedbackExchangeView({
    required this.sampleId,
    required this.index,
    required this.exchange,
  });

  final String sampleId;
  final int index;
  final FeedbackExchange exchange;

  @override
  Widget build(BuildContext context) {
    final answer = exchange.answer;
    final conclusion = answer.conclusion;
    return Container(
      key: Key('feedback-answer-$sampleId-$index'),
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black38),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '你问：${exchange.question}',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 6),
          if (!answer.matched)
            Text(
              answer.noMatchMessage ?? '这题没有直接对应内容。',
              key: Key('feedback-nomatch-$sampleId-$index'),
              style: const TextStyle(fontSize: 13, height: 1.55),
            )
          else ...<Widget>[
            if (answer.steps.isNotEmpty) ...<Widget>[
              const Text('相关步骤与公式', style: _feedbackLabelStyle),
              for (var i = 0; i < answer.steps.length; i++)
                _FeedbackStepView(index: i, step: answer.steps[i]),
            ],
            if (conclusion != null && conclusion.isNotEmpty) ...<Widget>[
              const SizedBox(height: 6),
              Text(
                '结论：$conclusion',
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            if (answer.mistakes.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              const Text('易错点', style: _feedbackLabelStyle),
              for (var i = 0; i < answer.mistakes.length; i++)
                _FeedbackMistakeView(index: i, mistake: answer.mistakes[i]),
            ],
            const SizedBox(height: 6),
            Text(
              answer.closing,
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
        ],
      ),
    );
  }
}

class _FeedbackStepView extends StatelessWidget {
  const _FeedbackStepView({required this.index, required this.step});

  final int index;
  final FeedbackStep step;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '${index + 1}. ${step.label}',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              height: 1.45,
            ),
          ),
          if (step.explanation.isNotEmpty) ...<Widget>[
            const SizedBox(height: 2),
            Text(
              step.explanation,
              style: const TextStyle(fontSize: 12, height: 1.6),
            ),
          ],
          for (final formula in step.formulas) ...<Widget>[
            const SizedBox(height: 2),
            Text(
              formula,
              style: const TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
                height: 1.4,
              ),
            ),
          ],
          if (step.keyQuantities.isNotEmpty) ...<Widget>[
            const SizedBox(height: 2),
            Text(
              '关键量：${step.keyQuantities.join('；')}',
              style: const TextStyle(fontSize: 12, height: 1.5),
            ),
          ],
          if (step.result.isNotEmpty) ...<Widget>[
            const SizedBox(height: 2),
            Text(
              '结论：${step.result}',
              style: const TextStyle(fontSize: 12, height: 1.5),
            ),
          ],
        ],
      ),
    );
  }
}

class _FeedbackMistakeView extends StatelessWidget {
  const _FeedbackMistakeView({required this.index, required this.mistake});

  final int index;
  final FeedbackMistake mistake;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '${index + 1}. ${mistake.title}',
            style: const TextStyle(fontSize: 13, height: 1.5),
          ),
          if (mistake.rootCause.isNotEmpty) ...<Widget>[
            const SizedBox(height: 2),
            Text(
              '根因：${mistake.rootCause}',
              style: const TextStyle(
                  fontSize: 12, color: Colors.black87, height: 1.5),
            ),
          ],
          if (mistake.remedy.isNotEmpty) ...<Widget>[
            const SizedBox(height: 2),
            Text(
              '补救：${mistake.remedy}',
              style: const TextStyle(
                  fontSize: 12, color: Colors.black87, height: 1.5),
            ),
          ],
        ],
      ),
    );
  }
}
