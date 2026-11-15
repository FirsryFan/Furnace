import 'dart:convert';

/// Read-only models for the design/content board.
///
/// The data is a trimmed local JSON asset (`assets/design_board.json`) generated
/// from `FURNACE-DESIGN-REFERENCE-2026-11-15.md` in the agent-control workspace.
/// Nothing here talks to the network or the database: the board is a viewer.
class DesignBoardData {
  const DesignBoardData({
    required this.sourceDocument,
    required this.sourceNote,
    required this.layers,
    required this.entries,
    required this.abilityMatrix,
    required this.contentSchema,
    this.realContentSamples = const <DesignBoardCard>[],
    required this.unfinished,
  });

  factory DesignBoardData.fromJson(Map<String, Object?> json) {
    final source = _map(json['source']);
    final layers = <DesignLayer>[
      for (final raw in _list(json['layers'])) DesignLayer.fromJson(_map(raw)),
    ];
    final entries = <DesignEntry>[
      for (final raw in _list(json['entries'])) DesignEntry.fromJson(_map(raw)),
    ];
    final unfinished = <String, String>{};
    for (final item in _map(json['unfinished']).entries) {
      unfinished[item.key] = _string(item.value);
    }
    final realContentSamples = <DesignBoardCard>[
      for (final raw in _list(json['realContentSamples']))
        DesignBoardCard.fromJson(_map(raw)),
    ];
    if (realContentSamples.isEmpty) {
      // Backwards-compatible single-sample shape (pre task-36 asset).
      final single = _optionalCard(json['realContentSample']);
      if (single != null) {
        realContentSamples.add(single);
      }
    }
    return DesignBoardData(
      sourceDocument: _string(source['document']),
      sourceNote: _string(source['note']),
      layers: List<DesignLayer>.unmodifiable(layers),
      entries: List<DesignEntry>.unmodifiable(entries),
      abilityMatrix: _optionalCard(json['abilityMatrix']),
      contentSchema: _optionalCard(json['contentSchema']),
      realContentSamples: List<DesignBoardCard>.unmodifiable(
        realContentSamples,
      ),
      unfinished: Map<String, String>.unmodifiable(unfinished),
    );
  }

  /// Decodes the asset text; throws [FormatException] on a non-object root.
  static DesignBoardData decode(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const FormatException('design_board.json: 顶层必须是 JSON 对象');
    }
    return DesignBoardData.fromJson(decoded.cast<String, Object?>());
  }

  /// The four status buckets the board renders, in display order.
  static const List<String> statusOrder = <String>[
    '已落地',
    '审核中',
    '否定',
    '待完善',
  ];

  final String sourceDocument;
  final String sourceNote;
  final List<DesignLayer> layers;
  final List<DesignEntry> entries;

  /// Optional read-only sample card; null means "数据未完成" (never faked).
  final DesignBoardCard? abilityMatrix;

  /// Optional read-only sample card; null means "数据未完成" (never faked).
  final DesignBoardCard? contentSchema;

  /// Compact snapshots of real content packages (physics Q-PH0001, math
  /// Q-MA0001); empty means none bundled. Each card is expandable.
  final List<DesignBoardCard> realContentSamples;

  /// Per-card reason shown when the optional sample is missing.
  final Map<String, String> unfinished;

  int get entryCount => entries.length;

  List<DesignEntry> entriesOf(String layerId) =>
      entries.where((entry) => entry.layer == layerId).toList(growable: false);

  Map<String, int> get statusCounts {
    final counts = <String, int>{for (final status in statusOrder) status: 0};
    for (final entry in entries) {
      counts[entry.status] = (counts[entry.status] ?? 0) + 1;
    }
    return counts;
  }
}

/// One layer of the five-layer design taxonomy.
class DesignLayer {
  const DesignLayer({
    required this.id,
    required this.label,
    required this.description,
  });

  factory DesignLayer.fromJson(Map<String, Object?> json) => DesignLayer(
        id: _string(json['id']),
        label: _string(json['label']),
        description: _string(json['description']),
      );

  final String id;
  final String label;
  final String description;
}

/// One design entry: name / type / status / one-line user verdict / mechanism.
class DesignEntry {
  const DesignEntry({
    required this.id,
    required this.name,
    required this.layer,
    required this.status,
    required this.statusRaw,
    required this.userVerdict,
    required this.userEval,
    required this.summary,
    required this.mechanism,
    required this.evidence,
    required this.paper,
  });

  factory DesignEntry.fromJson(Map<String, Object?> json) => DesignEntry(
        id: _string(json['id']),
        name: _string(json['name']),
        layer: _string(json['layer']),
        status: _string(json['status']),
        statusRaw: _string(json['statusRaw']),
        userVerdict: _string(json['userVerdict']),
        userEval: _string(json['userEval']),
        summary: _string(json['summary']),
        mechanism: _string(json['mechanism']),
        evidence: _string(json['evidence']),
        paper: _string(json['paper']),
      );

  final String id;
  final String name;
  final String layer;

  /// One of [DesignBoardData.statusOrder] (已落地 / 审核中 / 否定 / 待完善).
  final String status;

  /// The reference library's own status code, kept verbatim behind the chip.
  final String statusRaw;
  final String userVerdict;
  final String userEval;
  final String summary;
  final String mechanism;
  final String evidence;
  final String paper;
}

/// One concrete board (题眼/陷阱/…) for the student view.
///
/// 2026-11-15 task-96: [boardId]/[level]/[order] come from the board library
/// selection (`LegacyBoardMapper`), so the page can render by L0–L5 instead of
/// the old fixed 9-board list. Old assets without those keys stay readable
/// (defaults empty/0) and the page falls back to the legacy layout.
class StudentPanel {
  const StudentPanel({
    required this.title,
    required this.items,
    this.boardId = '',
    this.level = '',
    this.order = 0,
  });

  factory StudentPanel.fromJson(Map<String, Object?> json) => StudentPanel(
        title: _string(json['title']),
        items: List<String>.unmodifiable(_list(json['items']).map(_string)),
        boardId: _string(json['boardId']),
        level: _string(json['level']),
        order: _int(json['order']),
      );

  final String title;
  final List<String> items;

  /// 板块库 id（例如 `l2_key_eye`）；空字符串 = 旧 asset 没有选板信息。
  final String boardId;

  /// `L0`…`L5`；空字符串 = 旧 asset。
  final String level;

  /// 同层排序键（来自板块库目录）。
  final int order;
}

/// One selected board from the L0–L5 board library.
///
/// Mirrors `BoardSelectionEntry` in
/// `lib/domain/services/content/legacy_board_mapper.dart` (JSON `snake_case`).
class StudentBoardEntry {
  const StudentBoardEntry({
    required this.boardId,
    required this.level,
    required this.order,
    required this.legacyPanel,
    required this.sourceRefs,
    required this.itemCount,
  });

  factory StudentBoardEntry.fromJson(Map<String, Object?> json) =>
      StudentBoardEntry(
        boardId: _string(json['board_id']),
        level: _string(json['level']),
        order: _int(json['order']),
        legacyPanel: _string(json['legacy_panel']),
        sourceRefs: List<String>.unmodifiable(
          _list(json['source_refs']).map(_string),
        ),
        itemCount: _int(json['item_count']),
      );

  final String boardId;
  final String level;
  final int order;
  final String legacyPanel;
  final List<String> sourceRefs;
  final int itemCount;
}

/// A board the selection wanted but the legacy content package has no source for.
///
/// Audit only: the page never renders a placeholder for it.
class StudentBoardGap {
  const StudentBoardGap({
    required this.boardId,
    required this.level,
    required this.reason,
  });

  factory StudentBoardGap.fromJson(Map<String, Object?> json) =>
      StudentBoardGap(
        boardId: _string(json['board_id']),
        level: _string(json['level']),
        reason: _string(json['reason']),
      );

  final String boardId;
  final String level;

  /// `empty_legacy_panel` / `no_candidates` / `no_legacy_source`.
  final String reason;
}

/// The board-library selection for one question (`furnace.board-selection/1`).
///
/// Generated by the real `LegacyBoardMapper` (see `.work/build_design_board.py`
/// + `.work/export_board_selection.dart`): 简单题不选 L1 DAG/过程解析/卡点/提示；
/// 复杂题才选；L3 顺序额外任务→变式→同源题；L4 拆扩展资料/学科史；L5 元信息
/// 不进学生正文。The page reads this instead of guessing complexity itself.
class StudentBoardSelection {
  const StudentBoardSelection({
    required this.schemaVersion,
    required this.questionId,
    required this.subject,
    required this.complexity,
    required this.complexitySource,
    required this.questionType,
    required this.questionTypeSource,
    required this.boards,
    required this.emptyBoards,
  });

  factory StudentBoardSelection.fromJson(Map<String, Object?> json) =>
      StudentBoardSelection(
        schemaVersion: _string(json['schema_version']),
        questionId: _string(json['question_id']),
        subject: _string(json['subject']),
        complexity: _string(json['complexity']),
        complexitySource: _string(json['complexity_source']),
        questionType: _string(json['question_type']),
        questionTypeSource: _string(json['question_type_source']),
        boards: List<StudentBoardEntry>.unmodifiable(
          _list(json['boards']).map(
            (raw) => StudentBoardEntry.fromJson(_map(raw)),
          ),
        ),
        emptyBoards: List<StudentBoardGap>.unmodifiable(
          _list(json['empty_boards']).map(
            (raw) => StudentBoardGap.fromJson(_map(raw)),
          ),
        ),
      );

  final String schemaVersion;
  final String questionId;
  final String subject;

  /// `simple` / `complex`.
  final String complexity;

  /// 判定来源（`default_simple` / `hints_ladder` / `second_method` /
  /// `difficulty_threshold` / `override`）。
  final String complexitySource;

  /// 选配用的粗粒度题型（`concept` / `calculation` / `reading` …）。
  final String questionType;
  final String questionTypeSource;

  /// Selected boards in (level, order) order; L0 first, L5 last.
  final List<StudentBoardEntry> boards;

  /// Boards that were triggered but have no legacy source (never rendered).
  final List<StudentBoardGap> emptyBoards;

  List<String> get boardIds => <String>[
        for (final board in boards) board.boardId,
      ];

  bool hasBoard(String boardId) {
    for (final board in boards) {
      if (board.boardId == boardId) return true;
    }
    return false;
  }

  StudentBoardEntry? boardById(String boardId) {
    for (final board in boards) {
      if (board.boardId == boardId) return board;
    }
    return null;
  }

  bool get isSimple => complexity == 'simple';

  bool get isComplex => complexity == 'complex';
}

/// AI-authored alternative answer, explicitly non-official and for debate.
class StudentAiAnswer {
  const StudentAiAnswer({
    required this.answer,
    required this.reasoning,
    required this.debate,
    required this.note,
  });

  factory StudentAiAnswer.fromJson(Map<String, Object?> json) =>
      StudentAiAnswer(
        answer: _string(json['answer']),
        reasoning: _string(json['reasoning']),
        debate: _string(json['debate']),
        note: _string(json['note']),
      );

  final String answer;
  final String reasoning;
  final String debate;

  /// Developer-only caveat; the student page shows the 【AI】 title marker and
  /// nothing else. Empty string means "not bundled".
  final String note;
}

/// One 上位知识 block, rendered in full on the student page (never truncated).
class StudentKnowledge {
  const StudentKnowledge({
    required this.title,
    required this.level,
    required this.what,
    required this.why,
    required this.how,
    required this.buildSteps,
    required this.example,
    required this.limitations,
  });

  factory StudentKnowledge.fromJson(Map<String, Object?> json) =>
      StudentKnowledge(
        title: _string(json['title']),
        level: _string(json['level']),
        what: _string(json['what']),
        why: _string(json['why']),
        how: _string(json['how']),
        buildSteps: List<String>.unmodifiable(
          _list(json['buildSteps']).map(_string),
        ),
        example: _string(json['example']),
        limitations: _string(json['limitations']),
      );

  final String title;

  /// 前置知识 / 上位知识 / 远背景 / 竞赛·大学 / 跨领域.
  final String level;
  final String what;
  final String why;
  final String how;
  final List<String> buildSteps;
  final String example;
  final String limitations;
}

/// One figure attached to the question stem.
///
/// Student rule (2026-11-15): 有图就显示，没有图就什么都不写 —— the page never
/// prints “无附图”. An empty [StudentContent.figures] list therefore renders
/// nothing at all, and [path] must be a bundled `assets/...` path.
class StudentFigure {
  const StudentFigure({
    required this.id,
    required this.caption,
    required this.path,
  });

  factory StudentFigure.fromJson(Map<String, Object?> json) => StudentFigure(
        id: _string(json['id']),
        caption: _string(json['caption']),
        path: _string(json['path']),
      );

  final String id;
  final String caption;

  /// Bundled Flutter asset path (`assets/...`); empty means "cannot render".
  final String path;
}

/// Student-facing content extracted from the content package.
///
/// Deliberately contains no trust/hash/source pointers in the main body; those
/// stay in the developer info page.
class StudentContent {
  const StudentContent({
    required this.stem,
    required this.answer,
    required this.solution,
    required this.solutionNote,
    required this.showSourceAnalysis,
    required this.panels,
    required this.aiAnswer,
    this.figures = const <StudentFigure>[],
    this.responseKind = '',
    this.answerAreaHeightMm = 0,
    this.upperKnowledge = const <StudentKnowledge>[],
  });

  factory StudentContent.fromJson(Map<String, Object?> json) => StudentContent(
        stem: _string(json['stem']),
        answer: _string(json['answer']),
        solution: _string(json['solution']),
        solutionNote: _string(json['solutionNote']),
        showSourceAnalysis: json['showSourceAnalysis'] == true,
        panels: List<StudentPanel>.unmodifiable(
          _list(json['panels']).map(
            (raw) => StudentPanel.fromJson(_map(raw)),
          ),
        ),
        aiAnswer: StudentAiAnswer.fromJson(_map(json['aiAnswer'])),
        figures: List<StudentFigure>.unmodifiable(
          _list(json['figures']).map(
            (raw) => StudentFigure.fromJson(_map(raw)),
          ),
        ),
        responseKind: _string(json['responseKind']),
        answerAreaHeightMm: _double(json['answerAreaHeightMm']),
        upperKnowledge: List<StudentKnowledge>.unmodifiable(
          _list(json['upperKnowledge']).map(
            (raw) => StudentKnowledge.fromJson(_map(raw)),
          ),
        ),
      );

  final String stem;
  final String answer;
  final String solution;
  final String solutionNote;

  /// Only 《高考试题分析》-sourced questions show the original analysis text
  /// below the DAG; other sources rely on the DAG as the analysis.
  final bool showSourceAnalysis;
  final List<StudentPanel> panels;
  final StudentAiAnswer aiAnswer;

  /// Stem figures; empty means "no figure" (nothing is rendered, no “无附图”).
  final List<StudentFigure> figures;

  /// 上位知识全文块（不截断）；九板块里的同名条目只是短摘要。
  final List<StudentKnowledge> upperKnowledge;

  /// Paper form: `choice` / `fill` / `solution` (unknown stays empty).
  final String responseKind;

  /// 空白答题框高度（mm）；0 表示不给答题区（选择/填空）。
  ///
  /// 解答题按分值给高度（6 分约 70–90 mm，12 分约 120–150 mm），页面画
  /// 一个空白边框区域，不再画横线、也不显示行数/高度文案。
  final double answerAreaHeightMm;

  /// 选择/填空不给答题区；解答题（有空白框高度）才显示答题区。
  bool get needsAnswerArea =>
      responseKind != 'choice' &&
      responseKind != 'fill' &&
      answerAreaHeightMm > 0;
}

/// One node of the read-only Thinking DAG diagram.
class DagNode {
  const DagNode({
    required this.id,
    required this.kind,
    required this.role,
    required this.label,
    required this.body,
    required this.stepType,
    required this.formulas,
    required this.keyQuantities,
    required this.result,
  });

  factory DagNode.fromJson(Map<String, Object?> json) => DagNode(
        id: _string(json['id']),
        kind: _string(json['kind']),
        role: _string(json['role']),
        label: _string(json['label']),
        body: _string(json['body']),
        stepType: _string(json['stepType']),
        formulas:
            List<String>.unmodifiable(_list(json['formulas']).map(_string)),
        keyQuantities: List<String>.unmodifiable(
          _list(json['keyQuantities']).map(_string),
        ),
        result: _string(json['result']),
      );

  final String id;
  final String kind;
  final String role;
  final String label;

  /// Full derivation text (task-52 model); the DAG is itself the analysis.
  final String body;
  final String stepType;
  final List<String> formulas;
  final List<String> keyQuantities;
  final String result;
}

/// One alternative route on the same Thinking DAG (second method / unverified
/// reading). Rendered only when the content package really provides it.
class DagAlternatePath {
  const DagAlternatePath({
    required this.id,
    required this.kind,
    required this.methodName,
    required this.nodeIds,
    required this.verdict,
    required this.note,
  });

  factory DagAlternatePath.fromJson(Map<String, Object?> json) =>
      DagAlternatePath(
        id: _string(json['id']),
        kind: _string(json['kind']),
        methodName: _string(json['methodName']),
        nodeIds: List<String>.unmodifiable(
          _list(json['nodeIds']).map(_string),
        ),
        verdict: _string(json['verdict']),
        note: _string(json['note']),
      );

  final String id;
  final String kind;
  final String methodName;
  final List<String> nodeIds;
  final String verdict;
  final String note;
}

/// A real failure/exclusion branch recorded by the content package.
class DagFailureBranch {
  const DagFailureBranch({
    required this.root,
    required this.deadEnd,
    required this.why,
  });

  factory DagFailureBranch.fromJson(Map<String, Object?> json) =>
      DagFailureBranch(
        root: _string(json['root']),
        deadEnd: _string(json['deadEnd']),
        why: _string(json['why']),
      );

  final String root;
  final String deadEnd;
  final String why;
}

/// One directed edge of the Thinking DAG.
class DagEdge {
  const DagEdge({required this.from, required this.to, required this.type});

  factory DagEdge.fromJson(Map<String, Object?> json) => DagEdge(
        from: _string(json['from']),
        to: _string(json['to']),
        type: _string(json['type']),
      );

  final String from;
  final String to;
  final String type;
}

/// Structured Thinking DAG used by the CustomPaint diagram.
///
/// The graph is AI-authored (`expert_authored`), never independently reviewed,
/// and has no semantic checker. The UI must say that instead of implying an
/// audited/官方 graph.
class DagGraph {
  const DagGraph({
    required this.sourceMode,
    required this.nodes,
    required this.edges,
    required this.alternatePaths,
    required this.successPath,
    required this.failedBranches,
    required this.failureBranches,
    required this.note,
  });

  factory DagGraph.fromJson(Map<String, Object?> json) => DagGraph(
        sourceMode: _string(json['sourceMode']),
        nodes: List<DagNode>.unmodifiable(
          _list(json['nodes']).map((raw) => DagNode.fromJson(_map(raw))),
        ),
        edges: List<DagEdge>.unmodifiable(
          _list(json['edges']).map((raw) => DagEdge.fromJson(_map(raw))),
        ),
        alternatePaths: List<DagAlternatePath>.unmodifiable(
          _list(json['alternatePaths']).map(
            (raw) => DagAlternatePath.fromJson(_map(raw)),
          ),
        ),
        successPath: List<String>.unmodifiable(
          _list(json['successPath']).map(_string),
        ),
        failedBranches: _int(json['failedBranches']),
        failureBranches: List<DagFailureBranch>.unmodifiable(
          _list(json['failureBranches']).map(
            (raw) => DagFailureBranch.fromJson(_map(raw)),
          ),
        ),
        note: _string(json['note']),
      );

  final String sourceMode;
  final List<DagNode> nodes;
  final List<DagEdge> edges;
  final List<DagAlternatePath> alternatePaths;
  final List<String> successPath;
  final int failedBranches;
  final List<DagFailureBranch> failureBranches;
  final String note;
}

/// One titled block of a real-content sample detail page (e.g. "题干", "校验").
class DesignBoardSection {
  const DesignBoardSection({required this.title, required this.items});

  factory DesignBoardSection.fromJson(Map<String, Object?> json) =>
      DesignBoardSection(
        title: _string(json['title']),
        items: List<String>.unmodifiable(_list(json['items']).map(_string)),
      );

  final String title;
  final List<String> items;
}

/// Read-only Problem State summary derived from
/// `problem-state/<question>.problem.json`.
///
/// These instances are material snapshots: decisions are `proposed` (no
/// approval event), budget is null, and nothing is connected to
/// ProblemStateStore / DB / UI. The UI must not present them as approved.
class ProblemStateSummary {
  const ProblemStateSummary({
    required this.facts,
    required this.assumptions,
    required this.decisions,
    required this.unknowns,
    required this.artifacts,
    required this.factTrustVerified,
    required this.factTrustReported,
    required this.decisionsProposed,
    required this.decisionsAccepted,
    required this.decisionsRejected,
    required this.decisionsAllProposed,
    required this.unknownsShown,
    required this.unknownsMore,
    required this.oracleKind,
    required this.oracleDescription,
    required this.budgetNull,
    required this.nodeStatus,
    required this.note,
  });

  factory ProblemStateSummary.fromJson(Map<String, Object?> json) {
    final counts = _map(json['counts']);
    return ProblemStateSummary(
      facts: _int(counts['facts']),
      assumptions: _int(counts['assumptions']),
      decisions: _int(counts['decisions']),
      unknowns: _int(counts['unknowns']),
      artifacts: _int(counts['artifacts']),
      factTrustVerified: _int(json['factTrustVerified']),
      factTrustReported: _int(json['factTrustReported']),
      decisionsProposed: _int(json['decisionsProposed']),
      decisionsAccepted: _int(json['decisionsAccepted']),
      decisionsRejected: _int(json['decisionsRejected']),
      decisionsAllProposed: json['decisionsAllProposed'] == true,
      unknownsShown: List<String>.unmodifiable(
        _list(json['unknowns']).map(_string),
      ),
      unknownsMore: _int(json['unknownsMore']),
      oracleKind: _string(json['oracleKind']),
      oracleDescription: _string(json['oracleDescription']),
      budgetNull: json['budgetNull'] == true,
      nodeStatus: _string(json['nodeStatus']),
      note: _string(json['note']),
    );
  }

  final int facts;
  final int assumptions;
  final int decisions;
  final int unknowns;
  final int artifacts;
  final int factTrustVerified;
  final int factTrustReported;
  final int decisionsProposed;
  final int decisionsAccepted;
  final int decisionsRejected;
  final bool decisionsAllProposed;
  final List<String> unknownsShown;
  final int unknownsMore;
  final String oracleKind;
  final String oracleDescription;
  final bool budgetNull;
  final String nodeStatus;
  final String note;
}

/// An optional read-only example card (ability dimensions / content sections).
///
/// When the source data is missing the asset holds `null` and the page shows
/// "数据未完成" instead of inventing an example.
class DesignBoardCard {
  const DesignBoardCard({
    required this.title,
    required this.subtitle,
    required this.statusLabel,
    required this.chips,
    required this.lines,
    this.id = '',
    this.expandable = false,
    this.detailSections = const <DesignBoardSection>[],
    this.problemState,
    this.dagGraph,
    this.studentContent,
    this.boardSelection,
  });

  factory DesignBoardCard.fromJson(Map<String, Object?> json) =>
      DesignBoardCard(
        id: _string(json['id']),
        title: _string(json['title']),
        subtitle: _string(json['subtitle']),
        statusLabel: _string(json['statusLabel']),
        chips: List<String>.unmodifiable(_list(json['chips']).map(_string)),
        lines: List<String>.unmodifiable(_list(json['lines']).map(_string)),
        expandable: json['expandable'] == true,
        detailSections: List<DesignBoardSection>.unmodifiable(
          _list(json['detailSections']).map(
            (raw) => DesignBoardSection.fromJson(_map(raw)),
          ),
        ),
        problemState: _problemState(json['problemState']),
        dagGraph: _dagGraph(json['dagGraph']),
        studentContent: _studentContent(json['studentContent']),
        boardSelection: _boardSelection(json['boardSelection']),
      );

  final String id;
  final String title;
  final String subtitle;
  final String statusLabel;
  final List<String> chips;
  final List<String> lines;

  /// True for the real-content sample: flags stay visible, details expand.
  final bool expandable;

  /// Structured content for [ContentSamplePage]; empty means no detail page.
  final List<DesignBoardSection> detailSections;

  /// Read-only Problem State summary; null means the block is not bundled.
  final ProblemStateSummary? problemState;

  /// Structured Thinking DAG for the CustomPaint diagram; null = no diagram.
  final DagGraph? dagGraph;

  /// Student-facing content (stem/answer/panels/AI answer); null = none.
  final StudentContent? studentContent;

  /// L0–L5 board-library selection for this sample; null = old asset (legacy).
  final StudentBoardSelection? boardSelection;
}

StudentContent? _studentContent(Object? raw) {
  if (raw is! Map) {
    return null;
  }
  return StudentContent.fromJson(raw.cast<String, Object?>());
}

StudentBoardSelection? _boardSelection(Object? raw) {
  if (raw is! Map) {
    return null;
  }
  return StudentBoardSelection.fromJson(raw.cast<String, Object?>());
}

DagGraph? _dagGraph(Object? raw) {
  if (raw is! Map) {
    return null;
  }
  return DagGraph.fromJson(raw.cast<String, Object?>());
}

ProblemStateSummary? _problemState(Object? raw) {
  if (raw is! Map) {
    return null;
  }
  return ProblemStateSummary.fromJson(raw.cast<String, Object?>());
}

DesignBoardCard? _optionalCard(Object? raw) {
  if (raw is! Map) {
    return null;
  }
  return DesignBoardCard.fromJson(raw.cast<String, Object?>());
}

Map<String, Object?> _map(Object? raw) {
  if (raw is Map) {
    return raw.cast<String, Object?>();
  }
  return const <String, Object?>{};
}

List<Object?> _list(Object? raw) => raw is List ? raw : const <Object?>[];

String _string(Object? raw) => raw?.toString() ?? '';

int _int(Object? raw) => raw is num ? raw.toInt() : 0;

double _double(Object? raw) => raw is num ? raw.toDouble() : 0;
