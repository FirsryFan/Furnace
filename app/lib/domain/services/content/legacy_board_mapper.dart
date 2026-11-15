/// 旧内容包 9 板块 → 新板块库 L0–L5 的只读映射器（task-95 / P2 D9 接线，
/// 2026-11-15）。
///
/// 为什么需要这一层：`board_library.dart` 只定义了 L0–L5 目录与选配规则，现有
/// 三份内容包仍是旧 9 板块（`five_dimension` / `thinking_dag` / `key_eye` /
/// `traps` / `hints` / `error_causes` / `variants` / `extensions` /
/// `extra_tasks`）。本文件把两者接起来：选配仍由 [selectBoards] 决定，再用旧
/// 内容包里的实际条目判断「有没有」——没有的板块不返回（不造「暂无」占位）。
///
/// 五条口径：
///
/// 1. **旧 → 新按层合并**：旧 9 板块映射到 L0–L5；L2 的题眼/陷阱/错因/卡点/
///    分层提示同属一层；L3 顺序固定「额外任务 → 变式 → 同源题」；L4 拆
///    「扩展资料 / 学科史」两个子类（学科史旧内容包没有，见 [BoardSourceGap]）。
/// 2. **只引用不复制**：输出的每个板块只带 JSON Pointer 引用（例如
///    `boards/physics-board.json#/key_eye/items`）与条目数，正文仍只在内容包。
/// 3. **五维不固定**：不建 `five_dimension` 板块；旧五维的键与内容题型四轴
///    （carrier/task/thinking/scope）进 L5 元信息，见 [BoardSelection.meta]。
/// 4. **简单题不配过程结构**：难度判定见 [inferLegacyComplexity]；简单题不选
///    Thinking DAG / 过程解析 / 卡点 / 分层提示（与 `selectBoards` 的
///    `complex_only` 一致）。
/// 5. **不猜**：题型四轴认不出时退回对所有板块适用的 `concept`，并在
///    `question_type_source` 标记；旧内容里没有的板块不返回；不认识的顶层键
///    记进 `panels`（status=unknown），不硬套。
///
/// 边界：不读文件、不读时钟、不联网、不写库/UI；输入是已经 `jsonDecode` 的
/// `question.json` 与 `boards/<subject>-board.json` 两个 Map。
library;

import 'dart:convert';

import 'board_library.dart';

/// 选板结果 JSON 的版本（只写不读；供报告/内容包对账）。
const String kBoardSelectionSchemaVersion = 'furnace.board-selection/1';

/// 旧内容包里的 9 个公共板块键（顺序沿用旧 schema 的板块顺序）。
abstract final class LegacyBoardPanels {
  /// 五维（旧 schema 的固定五字段；新库不再建板块）。
  static const String fiveDimension = 'five_dimension';

  /// Thinking DAG（节点/边/成功路径/替代路径/失败支）。
  static const String thinkingDag = 'thinking_dag';

  /// 题眼。
  static const String keyEye = 'key_eye';

  /// 陷阱。
  static const String traps = 'traps';

  /// 分层提示（`hints.policy` + `hints.ladder`）。
  static const String hints = 'hints';

  /// 错因。
  static const String errorCauses = 'error_causes';

  /// 变式（含 `related_questions` 同源题候选）。
  static const String variants = 'variants';

  /// 扩展/上位知识（旧库没有单独的学科史板块）。
  static const String extensions = 'extensions';

  /// 额外任务。
  static const String extraTasks = 'extra_tasks';

  /// 九个公共板块（固定顺序）。
  static const List<String> nine = <String>[
    fiveDimension,
    thinkingDag,
    keyEye,
    traps,
    hints,
    errorCauses,
    variants,
    extensions,
    extraTasks,
  ];

  /// 板级元信息（不是板块）。
  static const String meta = 'meta';

  /// 学科专属板（不是 9 个公共板块之一；新库没有对应条目）。
  static const String subjectSpecific = 'subject_specific';

  /// 题目本体（来自 `question.json`，不是 board 板块）。
  static const String questionEntity = 'question_entity';

  /// board 文件里已知的顶层键（其余按未知键记录，不猜映射）。
  static const Set<String> boardTopLevelKeys = <String>{
    'schema_version',
    'subject',
    'question_id',
    meta,
    subjectSpecific,
    ...nine,
  };
}

/// 旧板块的处理状态（写进 [BoardSelection.panels]，供报告/测试核对）。
abstract final class LegacyPanelStatus {
  /// 有内容，且已选进 [BoardSelection.boards]。
  static const String mapped = 'mapped';

  /// 不是独立板块，被吸收进 L5 元信息（五维/板级 meta）。
  static const String absorbed = 'absorbed';

  /// 旧板块本身没有条目 → 不返回占位。
  static const String empty = 'empty';

  /// `meta.omitted_boards` 明确剪掉（不返回，也不造占位）。
  static const String omitted = 'omitted';

  /// 有内容，但本层策略/题型/触发条件不配（例如简单题不配 DAG/提示）。
  static const String notSelected = 'not_selected';

  /// 新板块库 L0–L5 没有对应条目（学科专属板）。
  static const String unmapped = 'unmapped';

  /// 不认识的顶层键；不猜映射。
  static const String unknown = 'unknown';
}

/// [LegacyComplexityDecision.source] 的取值。
abstract final class LegacyComplexitySources {
  /// 调用方显式传入。
  static const String override = 'override';

  /// 有分层提示阶梯：A4 口径「只有难想/最后小问/新颖角度才给提示」。
  static const String hintsLadder = 'hints_ladder';

  /// 有可独立验证的第二解法（`alternate_paths.kind=second_method`）。
  static const String secondMethod = 'second_method';

  /// `meta.difficulty.value` 达到阈值（AI 估计，只作弱信号）。
  static const String difficultyThreshold = 'difficulty_threshold';

  /// 以上信号都没有 → 简单题。
  static const String defaultSimple = 'default_simple';
}

/// [BoardSelection.questionTypeSource] 的取值。
abstract final class LegacyQuestionTypeSources {
  /// 调用方显式传入。
  static const String override = 'override';

  /// 由内容题型四轴 `classification.content_type.axes` 推导。
  static const String contentTypeAxes = 'content_type_axes';

  /// 四轴认不出 → 退回 `concept`（对所有板块适用，不因题型删板块）。
  static const String fallbackConcept = 'fallback_concept';
}

/// 旧的复杂度判定口径（旧内容包没有显式 complexity 字段，只能从事实推导）。
abstract final class LegacyComplexityPolicy {
  /// 复杂判定阈值：`difficulty.value` 是 1–10 刻度
  /// （`common.schema.json` `difficulty.value` 的 minimum/maximum），4 分及以上
  /// 按「中等及以上」处理。这是 AI 估计（`source=ai`，confidence 常为 0.35），
  /// 所以只作兜底信号，不单独定案。
  static const double complexDifficultyMin = 4;

  /// 真正的第二解法 kind；`shortcut_path` / `unverified_alternative_reading` /
  /// `subquestion_path` 都不算一题多解（见 `panel-common.schema.json`
  /// `alternate_path.kind` 的说明）。
  static const String secondMethodKind = 'second_method';
}

/// 内容题型四轴 → 板块选配用的粗粒度题型（[BoardQuestionType]）。
///
/// 这不是「五维字段映射」：只把 `classification.content_type.axes` 的 task
/// （必要时看 carrier）折算成 [selectBoards] 需要的粗粒度题型名。选配词表只有
/// 7 个值，内容 task 有 13 个，因此聚合规则是**启发式**，认不出的 task 返回
/// null（由调用方决定是否退回 `concept`）。
abstract final class LegacyQuestionTypeMapping {
  /// 认作「语言/文学文本」的 carrier（`evaluate` 类任务据它区分阅读与计算）。
  static const Set<String> languageCarriers = <String>{
    'material_text',
    'classical_text',
    'poetry',
    'language_use',
    'writing_prompt',
    'vocabulary',
    'syntax',
    'cloze',
    'continuation',
  };

  /// 由四轴（至少 task）推导粗粒度题型；认不出返回 null（不猜）。
  static String? fromContentTypeAxes(Map<String, Object?>? axes) {
    if (axes == null) {
      return null;
    }
    final task = _strOrNull(axes['task'])?.trim().toLowerCase();
    if (task == null || task.isEmpty) {
      return null;
    }
    final carrier = _strOrNull(axes['carrier'])?.trim().toLowerCase() ?? '';
    switch (task) {
      case 'prove':
        return BoardQuestionType.proof;
      case 'compute':
        return BoardQuestionType.calculation;
      case 'transform':
      case 'model':
        return BoardQuestionType.derivation;
      case 'explain':
        return BoardQuestionType.concept;
      case 'summarize':
      case 'retrieve':
      case 'translate':
        return BoardQuestionType.reading;
      case 'write':
        return BoardQuestionType.expression;
      case 'design':
        return BoardQuestionType.experiment;
      case 'predict':
      case 'diagnose':
        return BoardQuestionType.concept;
      case 'evaluate':
        // 「评价」本身不区分文/理：语言文学载体按阅读，其余按计算/论证处理。
        return languageCarriers.contains(carrier)
            ? BoardQuestionType.reading
            : BoardQuestionType.calculation;
      default:
        return null;
    }
  }
}

/// 复杂度判定结果：结果是简单/复杂，来源说明是哪条旧内容事实触发的。
class LegacyComplexityDecision {
  const LegacyComplexityDecision(this.complexity, this.source);

  /// 判定出的复杂度。
  final QuestionComplexity complexity;

  /// [LegacyComplexitySources] 之一。
  final String source;

  /// JSON 形态（报告/测试用）。
  Map<String, Object?> toJson() => <String, Object?>{
        'complexity': complexity.code,
        'source': source,
      };
}

/// 由旧内容事实推导复杂度（旧内容包没有显式 complexity 字段）。
///
/// 规则按顺序：
///
/// 1. `hints.ladder` 非空 → 复杂（A4：只有难想/最后小问/新颖角度才给提示）；
/// 2. `thinking_dag.alternate_paths[].kind == second_method` → 复杂（有可独立
///    验证的第二解法）；
/// 3. `meta.difficulty.value >= 4`（1–10 刻度，AI 估计）→ 复杂（兜底弱信号）；
/// 4. 否则 → 简单。
///
/// 已知限制：旧内容没有权威复杂度标签，这是启发式；调用方可用
/// [LegacyBoardMapper.map] 的 `complexity` 参数显式覆盖。
LegacyComplexityDecision inferLegacyComplexity({
  required Map<String, Object?> question,
  required Map<String, Object?> board,
}) {
  final hintLadder = _list(_map(board[LegacyBoardPanels.hints])['ladder']);
  if (hintLadder.isNotEmpty) {
    return const LegacyComplexityDecision(
      QuestionComplexity.complex,
      LegacyComplexitySources.hintsLadder,
    );
  }

  final alternates =
      _list(_map(board[LegacyBoardPanels.thinkingDag])['alternate_paths']);
  for (final raw in alternates) {
    final kind = _strOrNull(_map(raw)['kind'])?.toLowerCase();
    if (kind == LegacyComplexityPolicy.secondMethodKind) {
      return const LegacyComplexityDecision(
        QuestionComplexity.complex,
        LegacyComplexitySources.secondMethod,
      );
    }
  }

  final difficulty =
      _doubleOrNull(_map(_map(question['meta'])['difficulty'])['value']);
  if (difficulty != null &&
      difficulty >= LegacyComplexityPolicy.complexDifficultyMin) {
    return const LegacyComplexityDecision(
      QuestionComplexity.complex,
      LegacyComplexitySources.difficultyThreshold,
    );
  }

  return const LegacyComplexityDecision(
    QuestionComplexity.simple,
    LegacyComplexitySources.defaultSimple,
  );
}

/// 一个被选中的板块：只带引用与计数，不含正文。
class BoardSelectionEntry {
  BoardSelectionEntry({
    required this.boardId,
    required this.level,
    required this.order,
    required this.legacyPanel,
    required List<String> sourceRefs,
    required this.itemCount,
  }) : sourceRefs = List<String>.unmodifiable(sourceRefs);

  /// 板块库的稳定 id（例如 `l2_key_eye`）。
  final String boardId;

  /// 所属层级。
  final BoardLevel level;

  /// 同层内排序键（来自板块库目录）。
  final int order;

  /// 这个板块由哪个旧板块供给（`question_entity` 表示 `question.json`）。
  final String legacyPanel;

  /// JSON Pointer 引用列表（`<file>#/<pointer>`）；正文不复制。
  final List<String> sourceRefs;

  /// 旧内容条目数（L0/L5 记 1：一道题/一条元信息）。
  final int itemCount;

  Map<String, Object?> toJson() => <String, Object?>{
        'board_id': boardId,
        'level': level.code,
        'order': order,
        'legacy_panel': legacyPanel,
        'source_refs': <String>[...sourceRefs],
        'item_count': itemCount,
      };
}

/// 一个「按触发条件该有、但旧内容里没有来源」的新板块。
///
/// 这不是占位：它只出现在 [BoardSelection.emptyBoards] 里供报告/测试核对，
/// 不会进 [BoardSelection.boards]，界面也不应把它当板块渲染。
class BoardSourceGap {
  const BoardSourceGap({
    required this.boardId,
    required this.level,
    required this.reason,
    required this.note,
  });

  /// 板块库的稳定 id。
  final String boardId;

  /// 所属层级。
  final BoardLevel level;

  /// 稳定原因码：`empty_legacy_panel` / `no_candidates` / `no_legacy_source`。
  final String reason;

  /// 一句话解释（中文）。
  final String note;

  Map<String, Object?> toJson() => <String, Object?>{
        'board_id': boardId,
        'level': level.code,
        'reason': reason,
        'note': note,
      };
}

/// 一个旧板块的处理结果（映射/空/剪掉/未映射/未知）。
class LegacyPanelDisposition {
  LegacyPanelDisposition({
    required this.panel,
    required this.status,
    required this.note,
    List<String> targetBoardIds = const <String>[],
  }) : targetBoardIds = List<String>.unmodifiable(targetBoardIds);

  /// 旧板块键（或 `meta` / `subject_specific` / 未知顶层键）。
  final String panel;

  /// [LegacyPanelStatus] 之一。
  final String status;

  /// 一句话解释。
  final String note;

  /// 这个旧板块供给/应供给的新板块 id。
  final List<String> targetBoardIds;

  Map<String, Object?> toJson() => <String, Object?>{
        'panel': panel,
        'status': status,
        'target_board_ids': <String>[...targetBoardIds],
        'note': note,
      };
}

/// 一道题的选板结果（JSON 可序列化；不含正文）。
class BoardSelection {
  BoardSelection({
    required this.questionId,
    required this.subject,
    required this.complexity,
    required this.complexitySource,
    required this.questionType,
    required this.questionTypeSource,
    required List<BoardSelectionEntry> boards,
    required List<BoardSourceGap> emptyBoards,
    required List<LegacyPanelDisposition> panels,
    required Map<String, Object?> meta,
  })  : boards = List<BoardSelectionEntry>.unmodifiable(boards),
        emptyBoards = List<BoardSourceGap>.unmodifiable(emptyBoards),
        panels = List<LegacyPanelDisposition>.unmodifiable(panels),
        meta = Map<String, Object?>.unmodifiable(meta);

  /// 内容包题目 id（`Q-…`）。
  final String questionId;

  /// 学科键（`physics` / `math` / `chinese`）。
  final String subject;

  /// 判定出的复杂度。
  final QuestionComplexity complexity;

  /// [LegacyComplexitySources] 之一。
  final String complexitySource;

  /// 板块选配用的粗粒度题型（[BoardQuestionType]）。
  final String questionType;

  /// [LegacyQuestionTypeSources] 之一。
  final String questionTypeSource;

  /// 选中的板块，按（层级、order）升序；L0 在前、L5 最后。
  final List<BoardSelectionEntry> boards;

  /// 触发条件命中但旧内容没有来源的板块（审计用，不是占位）。
  final List<BoardSourceGap> emptyBoards;

  /// 旧板块的处理结果（含未映射/丢弃/未知）。
  final List<LegacyPanelDisposition> panels;

  /// L5 元信息载荷：内容题型四轴、能力码、难度、来源、五维键、板版本。
  final Map<String, Object?> meta;

  /// 选中的板块 id 列表（按输出顺序）。
  List<String> get boardIds => <String>[
        for (final board in boards) board.boardId,
      ];

  /// 某层的选中板块（保持输出顺序）。
  List<BoardSelectionEntry> boardsAt(BoardLevel level) => <BoardSelectionEntry>[
        for (final board in boards)
          if (board.level == level) board,
      ];

  /// 按 id 找选中板块；没有就返回 null（不造占位）。
  BoardSelectionEntry? boardById(String boardId) {
    for (final board in boards) {
      if (board.boardId == boardId) return board;
    }
    return null;
  }

  /// 序列化为 JSON 对象（snake_case 键）。
  Map<String, Object?> toJson() => <String, Object?>{
        'schema_version': kBoardSelectionSchemaVersion,
        'question_id': questionId,
        'subject': subject,
        'complexity': complexity.code,
        'complexity_source': complexitySource,
        'question_type': questionType,
        'question_type_source': questionTypeSource,
        'boards': <Map<String, Object?>>[
          for (final board in boards) board.toJson(),
        ],
        'empty_boards': <Map<String, Object?>>[
          for (final gap in emptyBoards) gap.toJson(),
        ],
        'panels': <Map<String, Object?>>[
          for (final panel in panels) panel.toJson(),
        ],
        'meta': <String, Object?>{...meta},
      };

  /// 序列化为 JSON 字符串（`dart:convert`，不依赖 Flutter）。
  String toJsonString() => jsonEncode(toJson());
}

/// 旧内容包 9 板块 → 新板块库 L0–L5 的映射器（纯函数，无 I/O）。
class LegacyBoardMapper {
  const LegacyBoardMapper();

  /// 把一份旧内容包映射成 [BoardSelection]。
  ///
  /// [question] 是 `question.json` 的 JSON 对象；[board] 是
  /// `boards/<subject>-board.json`。两个参数都只读，映射器不修改传入 Map。
  ///
  /// 可选参数：
  /// * [questionType]：显式粗粒度题型；不传则由内容题型四轴推导。
  /// * [complexity]：显式复杂度；不传则由 [inferLegacyComplexity] 推导。
  /// * [questionPath] / [boardPath]：写进引用的相对路径（默认
  ///   `question.json` 与 `boards/<subject>-board.json`）。
  ///
  /// 严格性：`question.id` / `question.subject` 缺失、或 board 的
  /// `question_id` 与 question 不一致时抛 [FormatException]（对不上的题不往下
  /// 走）；其它字段宽松处理，未知顶层键记进 `panels`（status=unknown）。
  BoardSelection map({
    required Map<String, Object?> question,
    Map<String, Object?> board = const <String, Object?>{},
    String? questionType,
    QuestionComplexity? complexity,
    String questionPath = 'question.json',
    String? boardPath,
  }) {
    final questionId = _requiredString(question['id'], 'question.id');
    final subject = _requiredString(question['subject'], 'question.subject');
    final boardQuestionId = _strOrNull(board['question_id']);
    if (boardQuestionId != null && boardQuestionId != questionId) {
      throw FormatException(
        'board.question_id=$boardQuestionId 与 question.id=$questionId 不一致',
      );
    }

    final resolvedBoardPath = boardPath ?? 'boards/$subject-board.json';
    final axes = _map(
      _map(_map(question['classification'])['content_type'])['axes'],
    );
    final questionTypeDecision = _resolveQuestionType(questionType, axes);
    final complexityDecision = complexity == null
        ? inferLegacyComplexity(question: question, board: board)
        : LegacyComplexityDecision(
            complexity,
            LegacyComplexitySources.override,
          );

    final omitted = _omittedPanels(board);
    final facts = _LegacyFacts.of(
      question: question,
      board: board,
      questionPath: questionPath,
      boardPath: resolvedBoardPath,
      omitted: omitted,
    );

    final selected = selectBoards(
      questionType: questionTypeDecision.type,
      complexity: complexityDecision.complexity,
      hasMultipleSolutions: facts.secondMethodIndexes.isNotEmpty,
      hasUpperKnowledge: facts.extensions.isNotEmpty,
      hasTraining: facts.hasTraining,
    );

    final boards = <BoardSelectionEntry>[];
    final emptyBoards = <BoardSourceGap>[];
    for (final definition in selected) {
      final panel = _boardToLegacyPanel[definition.id];
      if (panel != null && omitted.containsKey(panel)) {
        continue;
      }
      final source = facts.sourceFor(definition.id);
      if (source == null) {
        emptyBoards.add(
          BoardSourceGap(
            boardId: definition.id,
            level: definition.level,
            reason: facts.gapReason(definition.id),
            note: _gapNote(definition.id),
          ),
        );
        continue;
      }
      boards.add(
        BoardSelectionEntry(
          boardId: definition.id,
          level: definition.level,
          order: definition.order,
          legacyPanel: source.panel,
          sourceRefs: source.refs,
          itemCount: source.itemCount,
        ),
      );
    }

    return BoardSelection(
      questionId: questionId,
      subject: subject,
      complexity: complexityDecision.complexity,
      complexitySource: complexityDecision.source,
      questionType: questionTypeDecision.type,
      questionTypeSource: questionTypeDecision.source,
      boards: boards,
      emptyBoards: emptyBoards,
      panels: _panelDispositions(
        board: board,
        boards: boards,
        omitted: omitted,
        complexity: complexityDecision.complexity,
        facts: facts,
      ),
      meta: _buildMeta(
        question: question,
        board: board,
        fiveDimensionKeys: facts.fiveDimensionKeys,
      ),
    );
  }

  static _QuestionTypeDecision _resolveQuestionType(
    String? explicit,
    Map<String, Object?> axes,
  ) {
    final normalized = (explicit ?? '').trim();
    if (normalized.isNotEmpty) {
      return _QuestionTypeDecision(
        normalized,
        LegacyQuestionTypeSources.override,
      );
    }
    final mapped = LegacyQuestionTypeMapping.fromContentTypeAxes(axes);
    if (mapped != null) {
      return _QuestionTypeDecision(
        mapped,
        LegacyQuestionTypeSources.contentTypeAxes,
      );
    }
    return const _QuestionTypeDecision(
      BoardQuestionType.concept,
      LegacyQuestionTypeSources.fallbackConcept,
    );
  }

  static List<LegacyPanelDisposition> _panelDispositions({
    required Map<String, Object?> board,
    required List<BoardSelectionEntry> boards,
    required Map<String, String> omitted,
    required QuestionComplexity complexity,
    required _LegacyFacts facts,
  }) {
    final selectedIds = <String>{for (final entry in boards) entry.boardId};
    final dispositions = <LegacyPanelDisposition>[];

    for (final panel in LegacyBoardPanels.nine) {
      if (omitted.containsKey(panel)) {
        dispositions.add(
          LegacyPanelDisposition(
            panel: panel,
            status: LegacyPanelStatus.omitted,
            note: '旧内容包 meta.omitted_boards 明确剪掉：${omitted[panel]}',
            targetBoardIds: _panelTargetBoards[panel] ?? const <String>[],
          ),
        );
        continue;
      }
      if (facts.isEmpty(panel)) {
        dispositions.add(
          LegacyPanelDisposition(
            panel: panel,
            status: LegacyPanelStatus.empty,
            note: '旧板块没有条目；不返回占位。',
          ),
        );
        continue;
      }
      if (panel == LegacyBoardPanels.fiveDimension) {
        dispositions.add(
          LegacyPanelDisposition(
            panel: LegacyBoardPanels.fiveDimension,
            status: LegacyPanelStatus.absorbed,
            note: '五维不固定为五个字段/板块；键与内容题型四轴进 L5 元信息。',
            targetBoardIds: const <String>['l5_meta'],
          ),
        );
        continue;
      }
      final targets = _panelTargetBoards[panel] ?? const <String>[];
      final selectedTargets = <String>[
        for (final target in targets)
          if (selectedIds.contains(target)) target,
      ];
      if (selectedTargets.isEmpty) {
        dispositions.add(
          LegacyPanelDisposition(
            panel: panel,
            status: LegacyPanelStatus.notSelected,
            note: _notSelectedNote(panel, complexity),
            targetBoardIds: targets,
          ),
        );
        continue;
      }
      dispositions.add(
        LegacyPanelDisposition(
          panel: panel,
          status: LegacyPanelStatus.mapped,
          note: '映射到 ${selectedTargets.join('、')}；只保留引用，不复制正文。',
          targetBoardIds: selectedTargets,
        ),
      );
    }

    final boardMeta = _map(board[LegacyBoardPanels.meta]);
    dispositions.add(
      LegacyPanelDisposition(
        panel: LegacyBoardPanels.meta,
        status: boardMeta.isEmpty
            ? LegacyPanelStatus.empty
            : LegacyPanelStatus.absorbed,
        note: boardMeta.isEmpty
            ? '旧内容包没有板级元信息。'
            : '板版本进 L5；剪枝项（omitted_boards）参与选配；覆盖/失效规则只留在内容包，不单独成板。',
        targetBoardIds: const <String>['l5_meta'],
      ),
    );

    final subjectSpecific = _map(board[LegacyBoardPanels.subjectSpecific]);
    dispositions.add(
      LegacyPanelDisposition(
        panel: LegacyBoardPanels.subjectSpecific,
        status: subjectSpecific.isEmpty
            ? LegacyPanelStatus.empty
            : LegacyPanelStatus.unmapped,
        note: subjectSpecific.isEmpty
            ? '旧内容包没有学科专属板。'
            : '新板块库 L0–L5 没有学科专属板块；内容仍留在内容包，未映射。',
      ),
    );

    // 不认识的顶层键：不猜映射，只记录（便于发现 schema 漂移）。
    for (final entry in board.entries) {
      if (LegacyBoardPanels.boardTopLevelKeys.contains(entry.key)) {
        continue;
      }
      dispositions.add(
        LegacyPanelDisposition(
          panel: entry.key,
          status: LegacyPanelStatus.unknown,
          note: '板块库没有对应条目；未猜测映射（值类型 ${entry.value.runtimeType}）。',
        ),
      );
    }

    return dispositions;
  }

  static Map<String, Object?> _buildMeta({
    required Map<String, Object?> question,
    required Map<String, Object?> board,
    required List<String> fiveDimensionKeys,
  }) {
    final classification = _map(question['classification']);
    final contentType = _map(classification['content_type']);
    final axes = _map(contentType['axes']);
    final questionMeta = _map(question['meta']);
    final difficulty = _map(questionMeta['difficulty']);

    final meta = <String, Object?>{};
    final code = _strOrNull(contentType['code']);
    if (code != null) {
      meta['content_type_code'] = code;
    }
    final label = _strOrNull(contentType['label']);
    if (label != null) {
      meta['content_type_label'] = label;
    }
    if (axes.isNotEmpty) {
      final axesJson = <String, Object?>{};
      final carrier = _strOrNull(axes['carrier']);
      if (carrier != null) {
        axesJson['carrier'] = carrier;
      }
      final task = _strOrNull(axes['task']);
      if (task != null) {
        axesJson['task'] = task;
      }
      final thinking = <String>[
        for (final raw in _list(axes['thinking'])) raw.toString(),
      ];
      if (thinking.isNotEmpty) {
        axesJson['thinking'] = thinking;
      }
      final scope = _strOrNull(axes['scope']);
      if (scope != null) {
        axesJson['scope'] = scope;
      }
      meta['content_type_axes'] = axesJson;
    }

    final capabilityCodes = <String>[
      for (final raw in _list(classification['capability']))
        if ((_strOrNull(_map(raw)['code']) ?? '').isNotEmpty)
          _strOrNull(_map(raw)['code'])!,
    ];
    if (capabilityCodes.isNotEmpty) {
      meta['capability_codes'] = capabilityCodes;
    }

    final difficultyJson = <String, Object?>{};
    final difficultyValue = _doubleOrNull(difficulty['value']);
    if (difficultyValue != null) {
      difficultyJson['value'] = difficultyValue;
    }
    final difficultySource = _strOrNull(difficulty['source']);
    if (difficultySource != null) {
      difficultyJson['source'] = difficultySource;
    }
    final difficultyConfidence = _doubleOrNull(difficulty['confidence']);
    if (difficultyConfidence != null) {
      difficultyJson['confidence'] = difficultyConfidence;
    }
    if (difficultyJson.isNotEmpty) {
      meta['difficulty'] = difficultyJson;
    }

    final sourceJson = <String, Object?>{};
    final sourceLevel = _strOrNull(questionMeta['source_level']);
    if (sourceLevel != null) {
      sourceJson['level'] = sourceLevel;
    }
    final sourceLabel = _strOrNull(questionMeta['source_label']);
    if (sourceLabel != null) {
      sourceJson['label'] = sourceLabel;
    }
    final year = _intOrNull(questionMeta['year']);
    if (year != null) {
      sourceJson['year'] = year;
    }
    final region = _strOrNull(questionMeta['region']);
    if (region != null) {
      sourceJson['region'] = region;
    }
    if (sourceJson.isNotEmpty) {
      meta['source'] = sourceJson;
    }

    meta['five_dimension_keys'] = List<String>.unmodifiable(fiveDimensionKeys);

    final boardVersion =
        _intOrNull(_map(board[LegacyBoardPanels.meta])['board_version']);
    if (boardVersion != null) {
      meta['board_version'] = boardVersion;
    }
    return meta;
  }
}

/// 显式/推导出的粗粒度题型。
class _QuestionTypeDecision {
  const _QuestionTypeDecision(this.type, this.source);

  final String type;
  final String source;
}

/// 一个板块的引用来源。
class _BoardSource {
  const _BoardSource({
    required this.panel,
    required this.refs,
    required this.itemCount,
  });

  final String panel;
  final List<String> refs;
  final int itemCount;
}

/// 从旧内容包 Map 里一次性读出的选配事实（只读）。
class _LegacyFacts {
  _LegacyFacts({
    required this.boardPath,
    required this.fiveDimensionKeys,
    required this.dagNodes,
    required this.dagEdges,
    required this.successPath,
    required this.secondMethodIndexes,
    required this.failedBranches,
    required this.keyEyeItems,
    required this.trapsItems,
    required this.hintLadder,
    required this.errorCauseItems,
    required this.variants,
    required this.extensions,
    required this.extraTasks,
    required this.similarCandidateCount,
    required this.similarCandidateRefs,
    required this.questionEntityRefs,
    required this.l5Refs,
    required this.boardMeta,
  });

  factory _LegacyFacts.of({
    required Map<String, Object?> question,
    required Map<String, Object?> board,
    required String questionPath,
    required String boardPath,
    required Map<String, String> omitted,
  }) {
    final questionMeta = _map(question['meta']);
    final answerParts = _list(_map(question['answer'])['parts']);
    final questionEntityRefs = <String>['$questionPath#/stem'];
    if (answerParts.isNotEmpty) {
      questionEntityRefs.add('$questionPath#/answer/parts');
    }
    if (_list(question['solutions']).isNotEmpty) {
      questionEntityRefs.add('$questionPath#/solutions');
    }
    if (_list(question['figures']).isNotEmpty) {
      questionEntityRefs.add('$questionPath#/figures');
    }
    if (_map(question['scoring']).isNotEmpty) {
      questionEntityRefs.add('$questionPath#/scoring');
    }

    final fiveDimension = omitted.containsKey(LegacyBoardPanels.fiveDimension)
        ? const <String, Object?>{}
        : _map(board[LegacyBoardPanels.fiveDimension]);
    final dag = _map(board[LegacyBoardPanels.thinkingDag]);
    final alternatePaths = _list(dag['alternate_paths']);
    final secondMethodIndexes = <int>[];
    for (var index = 0; index < alternatePaths.length; index++) {
      final kind =
          _strOrNull(_map(alternatePaths[index])['kind'])?.toLowerCase();
      if (kind == LegacyComplexityPolicy.secondMethodKind) {
        secondMethodIndexes.add(index);
      }
    }

    final variants = _list(_map(board[LegacyBoardPanels.variants])['items']);
    final similarCandidateRefs = <String>[];
    var similarCandidateCount = 0;
    for (var index = 0; index < variants.length; index++) {
      final candidates = _list(
        _map(_map(variants[index])['related_questions'])['candidates'],
      );
      if (candidates.isEmpty) {
        continue;
      }
      similarCandidateCount += candidates.length;
      similarCandidateRefs.add(
        '$boardPath#/variants/items/$index/related_questions/candidates',
      );
    }

    final l5Refs = <String>[];
    if (fiveDimension.isNotEmpty) {
      l5Refs.add('$boardPath#/five_dimension');
    }
    if (_map(_map(_map(question['classification'])['content_type'])['axes'])
        .isNotEmpty) {
      l5Refs.add('$questionPath#/classification/content_type/axes');
    }
    if (questionMeta.isNotEmpty) {
      l5Refs.add('$questionPath#/meta');
    }
    if (l5Refs.isEmpty) {
      l5Refs.add('$questionPath#/classification');
    }

    return _LegacyFacts(
      boardPath: boardPath,
      fiveDimensionKeys: <String>[
        for (final key in fiveDimension.keys) key,
      ],
      dagNodes: _list(dag['nodes']),
      dagEdges: _list(dag['edges']),
      successPath: _list(dag['success_path']),
      secondMethodIndexes: List<int>.unmodifiable(secondMethodIndexes),
      failedBranches: _list(dag['failed_branches']),
      keyEyeItems: _list(_map(board[LegacyBoardPanels.keyEye])['items']),
      trapsItems: _list(_map(board[LegacyBoardPanels.traps])['items']),
      hintLadder: _list(_map(board[LegacyBoardPanels.hints])['ladder']),
      errorCauseItems:
          _list(_map(board[LegacyBoardPanels.errorCauses])['items']),
      variants: variants,
      extensions: _list(_map(board[LegacyBoardPanels.extensions])['items']),
      extraTasks: _list(_map(board[LegacyBoardPanels.extraTasks])['items']),
      similarCandidateCount: similarCandidateCount,
      similarCandidateRefs: List<String>.unmodifiable(similarCandidateRefs),
      questionEntityRefs: List<String>.unmodifiable(questionEntityRefs),
      l5Refs: List<String>.unmodifiable(l5Refs),
      boardMeta: _map(board[LegacyBoardPanels.meta]),
    );
  }

  final String boardPath;
  final List<String> fiveDimensionKeys;
  final List<Object?> dagNodes;
  final List<Object?> dagEdges;
  final List<Object?> successPath;
  final List<int> secondMethodIndexes;
  final List<Object?> failedBranches;
  final List<Object?> keyEyeItems;
  final List<Object?> trapsItems;
  final List<Object?> hintLadder;
  final List<Object?> errorCauseItems;
  final List<Object?> variants;
  final List<Object?> extensions;
  final List<Object?> extraTasks;
  final int similarCandidateCount;
  final List<String> similarCandidateRefs;
  final List<String> questionEntityRefs;
  final List<String> l5Refs;
  final Map<String, Object?> boardMeta;

  bool get hasTraining =>
      extraTasks.isNotEmpty || variants.isNotEmpty || similarCandidateCount > 0;

  /// 旧板块是否有条目（空板块不返回占位）。
  bool isEmpty(String panel) => switch (panel) {
        LegacyBoardPanels.fiveDimension => fiveDimensionKeys.isEmpty,
        LegacyBoardPanels.thinkingDag => dagNodes.isEmpty,
        LegacyBoardPanels.keyEye => keyEyeItems.isEmpty,
        LegacyBoardPanels.traps => trapsItems.isEmpty,
        LegacyBoardPanels.hints => hintLadder.isEmpty,
        LegacyBoardPanels.errorCauses => errorCauseItems.isEmpty,
        LegacyBoardPanels.variants => variants.isEmpty,
        LegacyBoardPanels.extensions => extensions.isEmpty,
        LegacyBoardPanels.extraTasks => extraTasks.isEmpty,
        LegacyBoardPanels.meta => boardMeta.isEmpty,
        LegacyBoardPanels.subjectSpecific => false,
        _ => true,
      };

  /// 某个新板块的内容引用；旧内容里没有来源时返回 null（不造占位）。
  _BoardSource? sourceFor(String boardId) {
    final boardPath = this.boardPath;
    switch (boardId) {
      case 'l0_question_entity':
        return _BoardSource(
          panel: LegacyBoardPanels.questionEntity,
          refs: questionEntityRefs,
          itemCount: 1,
        );
      case 'l5_meta':
        return _BoardSource(
          panel: LegacyBoardPanels.fiveDimension,
          refs: l5Refs,
          itemCount: 1,
        );
      case 'l1_thinking_dag':
        if (dagNodes.isEmpty) return null;
        return _BoardSource(
          panel: LegacyBoardPanels.thinkingDag,
          refs: <String>[
            '$boardPath#/thinking_dag/nodes',
            '$boardPath#/thinking_dag/edges',
          ],
          itemCount: dagNodes.length,
        );
      case 'l1_solution_walkthrough':
        if (dagNodes.isEmpty) return null;
        return _BoardSource(
          panel: LegacyBoardPanels.thinkingDag,
          refs: successPath.isNotEmpty
              ? <String>['$boardPath#/thinking_dag/success_path']
              : <String>['$boardPath#/thinking_dag/nodes'],
          itemCount:
              successPath.isNotEmpty ? successPath.length : dagNodes.length,
        );
      case 'l1_multi_solution':
        if (secondMethodIndexes.isEmpty) return null;
        return _BoardSource(
          panel: LegacyBoardPanels.thinkingDag,
          refs: <String>[
            for (final index in secondMethodIndexes)
              '$boardPath#/thinking_dag/alternate_paths/$index',
          ],
          itemCount: secondMethodIndexes.length,
        );
      case 'l2_key_eye':
        return keyEyeItems.isEmpty
            ? null
            : _BoardSource(
                panel: LegacyBoardPanels.keyEye,
                refs: <String>['$boardPath#/key_eye/items'],
                itemCount: keyEyeItems.length,
              );
      case 'l2_traps':
        return trapsItems.isEmpty
            ? null
            : _BoardSource(
                panel: LegacyBoardPanels.traps,
                refs: <String>['$boardPath#/traps/items'],
                itemCount: trapsItems.length,
              );
      case 'l2_error_causes':
        return errorCauseItems.isEmpty
            ? null
            : _BoardSource(
                panel: LegacyBoardPanels.errorCauses,
                refs: <String>['$boardPath#/error_causes/items'],
                itemCount: errorCauseItems.length,
              );
      case 'l2_stuck_points':
        // 旧 9 板块没有独立「卡点」板；由 thinking_dag.failed_branches 派生。
        return failedBranches.isEmpty
            ? null
            : _BoardSource(
                panel: LegacyBoardPanels.thinkingDag,
                refs: <String>['$boardPath#/thinking_dag/failed_branches'],
                itemCount: failedBranches.length,
              );
      case 'l2_layered_hints':
        return hintLadder.isEmpty
            ? null
            : _BoardSource(
                panel: LegacyBoardPanels.hints,
                refs: <String>['$boardPath#/hints/ladder'],
                itemCount: hintLadder.length,
              );
      case 'l3_extra_tasks':
        return extraTasks.isNotEmpty
            ? _BoardSource(
                panel: LegacyBoardPanels.extraTasks,
                refs: <String>['$boardPath#/extra_tasks/items'],
                itemCount: extraTasks.length,
              )
            : null;
      case 'l3_variants':
        return variants.isNotEmpty
            ? _BoardSource(
                panel: LegacyBoardPanels.variants,
                refs: <String>['$boardPath#/variants/items'],
                itemCount: variants.length,
              )
            : null;
      case 'l3_similar_questions':
        return similarCandidateCount == 0
            ? null
            : _BoardSource(
                panel: LegacyBoardPanels.variants,
                refs: similarCandidateRefs,
                itemCount: similarCandidateCount,
              );
      case 'l4_extension_material':
        return extensions.isNotEmpty
            ? _BoardSource(
                panel: LegacyBoardPanels.extensions,
                refs: <String>['$boardPath#/extensions/items'],
                itemCount: extensions.length,
              )
            : null;
      case 'l4_subject_history':
        // 旧 9 板块没有学科史板（D10 尚未做），不拿扩展资料冒充。
        return null;
      default:
        return null;
    }
  }

  /// 空板块原因码。
  String gapReason(String boardId) => switch (boardId) {
        'l4_subject_history' => 'no_legacy_source',
        'l3_similar_questions' => 'no_candidates',
        _ => 'empty_legacy_panel',
      };
}

/// 空板块的一句话解释。
String _gapNote(String boardId) => switch (boardId) {
      'l4_subject_history' => '旧内容包没有学科史板块（D10 尚未做）；不拿扩展资料冒充，不造占位。',
      'l3_similar_questions' =>
        '旧板块 variants[].related_questions.candidates 为空（searched_empty）；不硬造同源题。',
      _ => '旧板块对应条目为空；不返回占位。',
    };

/// 新板块 id → 供给它的旧板块（L0/L5 不参与 omitted 剪枝）。
const Map<String, String> _boardToLegacyPanel = <String, String>{
  'l1_thinking_dag': LegacyBoardPanels.thinkingDag,
  'l1_solution_walkthrough': LegacyBoardPanels.thinkingDag,
  'l1_multi_solution': LegacyBoardPanels.thinkingDag,
  'l2_key_eye': LegacyBoardPanels.keyEye,
  'l2_traps': LegacyBoardPanels.traps,
  'l2_error_causes': LegacyBoardPanels.errorCauses,
  'l2_stuck_points': LegacyBoardPanels.thinkingDag,
  'l2_layered_hints': LegacyBoardPanels.hints,
  'l3_extra_tasks': LegacyBoardPanels.extraTasks,
  'l3_variants': LegacyBoardPanels.variants,
  'l3_similar_questions': LegacyBoardPanels.variants,
  'l4_extension_material': LegacyBoardPanels.extensions,
  'l4_subject_history': LegacyBoardPanels.extensions,
};

/// 旧板块 → 供给的新板块（报告用；实际选配仍由 selectBoards 决定）。
const Map<String, List<String>> _panelTargetBoards = <String, List<String>>{
  LegacyBoardPanels.fiveDimension: <String>['l5_meta'],
  LegacyBoardPanels.thinkingDag: <String>[
    'l1_thinking_dag',
    'l1_solution_walkthrough',
    'l1_multi_solution',
    'l2_stuck_points',
  ],
  LegacyBoardPanels.keyEye: <String>['l2_key_eye'],
  LegacyBoardPanels.traps: <String>['l2_traps'],
  LegacyBoardPanels.hints: <String>['l2_layered_hints'],
  LegacyBoardPanels.errorCauses: <String>['l2_error_causes'],
  LegacyBoardPanels.variants: <String>[
    'l3_variants',
    'l3_similar_questions',
  ],
  LegacyBoardPanels.extensions: <String>[
    'l4_extension_material',
    'l4_subject_history',
  ],
  LegacyBoardPanels.extraTasks: <String>['l3_extra_tasks'],
};

/// 「有内容但没被选」的一句话原因。
String _notSelectedNote(String panel, QuestionComplexity complexity) {
  if (complexity == QuestionComplexity.simple &&
      (panel == LegacyBoardPanels.thinkingDag ||
          panel == LegacyBoardPanels.hints)) {
    return panel == LegacyBoardPanels.thinkingDag
        ? '简单题不配过程结构（Thinking DAG/过程解析/卡点不选）；旧 DAG 仍留在内容包。'
        : '简单题不给提示（用户 A4）；分层提示不选。';
  }
  return '按 selectBoards 的触发条件/题型不配；旧内容仍留在内容包。';
}

/// `meta.omitted_boards[]` → {旧板块键: 原因}。
Map<String, String> _omittedPanels(Map<String, Object?> board) {
  final omitted = <String, String>{};
  for (final raw
      in _list(_map(board[LegacyBoardPanels.meta])['omitted_boards'])) {
    final json = _map(raw);
    final panel = (_strOrNull(json['board']) ?? '').trim().toLowerCase();
    if (panel.isEmpty) {
      continue;
    }
    omitted[panel] = _strOrNull(json['reason']) ?? '未写原因';
  }
  return omitted;
}

// ---------------------------------------------------------------------------
// JSON 读取内部工具：只接受 JSON 原生类型；类型不符按「没有」处理（宽松读）。
// ---------------------------------------------------------------------------

Map<String, Object?> _map(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) {
    return <String, Object?>{
      for (final entry in value.entries)
        if (entry.key is String) entry.key as String: entry.value,
    };
  }
  return const <String, Object?>{};
}

List<Object?> _list(Object? value) => value is List ? value : const <Object?>[];

String? _strOrNull(Object? value) {
  if (value == null) return null;
  final text = value.toString();
  return text.isEmpty ? null : text;
}

int? _intOrNull(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString().trim());
}

double? _doubleOrNull(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString().trim());
}

String _requiredString(Object? value, String where) {
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$where 必须是非空字符串，实际是 $value');
  }
  return value.trim();
}
