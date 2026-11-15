/// 板块库 L0–L5（P2 D9 / task-94，2026-11-15）。
///
/// 用户已定的层级（写死在 [kBoardCatalog] 里，不在各处散落）：
///
/// * **L0 题目本体**：题干/图/选项/答案/解析/评分参考；
/// * **L1 过程结构**：Thinking DAG / 一题多解 / 关键步骤（过程解析）；
/// * **L2 诊断（合并）**：题眼/陷阱/错因/卡点/分层提示；
/// * **L3 训练（由近及远）**：额外任务 → 变式 → 同源题；
/// * **L4 背景**：扩展资料 / 学科史（理论/工具发展，不记人名年代）；
/// * **L5 元信息**：能力标签/难度/认知负荷/来源/适用题型。
///
/// 四条纪律（本文件的边界）：
///
/// 1. **五维不再作为固定五字段**：这里没有 `five_dimension` 板块；五维由内容
///    题型四轴（[FiveDimensionPolicy.contentTypeAxes]）推导，归入 L5 元信息。
/// 2. **简单题不配过程结构**：Thinking DAG 与过程解析只在
///    [QuestionComplexity.complex] 时选中；卡点与分层提示依赖过程结构，简单题
///    也不选（与产品 A4「简单题不给提示」一致）。L0 的「解析」是题目本体字段，
///    由内容包/来源决定有没有，不由本库生成。
/// 3. **空/不适用不返回占位**：题型为空直接返回空表；L3/L4 由调用方显式传
///    `hasTraining` / `hasUpperKnowledge`，没有就整段不出现，不造「暂无」条目。
/// 4. **只做域**：不接 UI / content-store / solver / DB；不读时钟、不联网。
///    JSON 双向序列化只做 `Map`/字符串互转，供内容包与 UI 共用同一份定义。
///
/// 题型词表说明：本库的 [BoardQuestionType] 是**板块选配用的粗粒度题型名**，
/// 不是内容包 `classification.content_type` 的四轴对象（那仍是权威口径）；两者
/// 的映射尚未接线，见 `BOARD-LIBRARY-2026-11-15.md`「未接」一节。
library;

import 'dart:convert';

/// 板块层级 L0–L5。枚举顺序即层级顺序（L0 在前）。
enum BoardLevel {
  /// 题目本体：题干/图/选项/答案/解析/评分参考。
  l0('L0', '题目本体', '题干/图/选项/答案/解析/评分参考'),

  /// 过程结构：Thinking DAG / 一题多解 / 关键步骤（过程解析）。
  l1('L1', '过程结构', 'Thinking DAG / 一题多解 / 关键步骤'),

  /// 诊断（合并）：题眼/陷阱/错因/卡点/分层提示。
  l2('L2', '诊断（合并）', '题眼/陷阱/错因/卡点/分层提示'),

  /// 训练（由近及远）：额外任务 → 变式 → 同源题。
  l3('L3', '训练（由近及远）', '额外任务 → 变式 → 同源题'),

  /// 背景：扩展资料 / 学科史。
  l4('L4', '背景', '扩展资料 / 学科史'),

  /// 元信息：能力标签/难度/认知负荷/来源/适用题型。
  l5('L5', '元信息', '能力标签/难度/认知负荷/来源/适用题型');

  const BoardLevel(this.code, this.label, this.summary);

  /// 稳定编码：`L0`…`L5`。
  final String code;

  /// 层级中文名。
  final String label;

  /// 层级一句话摘要（报告/日志用，不当作 UI 文案体系）。
  final String summary;

  /// 由编码找层级（大小写/空白容错）；认不出返回 null（不猜）。
  static BoardLevel? tryFromCode(String? code) {
    final normalized = (code ?? '').trim().toLowerCase();
    for (final level in BoardLevel.values) {
      if (level.code.toLowerCase() == normalized) return level;
    }
    return null;
  }
}

/// 题目复杂度：决定过程结构（DAG/过程解析）是否配。
enum QuestionComplexity {
  /// 简单题：只保留题目本体 + 诊断 + 元信息；不配 DAG/过程解析。
  simple('simple', '简单题'),

  /// 复杂题：配过程结构（DAG + 过程解析），可继续配多解/训练/背景。
  complex('complex', '复杂题');

  const QuestionComplexity(this.code, this.label);

  /// 稳定编码：`simple` / `complex`。
  final String code;

  /// 中文名。
  final String label;

  /// 由编码找复杂度（大小写/空白容错）；认不出返回 null（不猜）。
  static QuestionComplexity? tryFromCode(String? code) {
    final normalized = (code ?? '').trim().toLowerCase();
    for (final complexity in QuestionComplexity.values) {
      if (complexity.code == normalized) return complexity;
    }
    return null;
  }
}

/// 板块触发条件。[selectBoards] 只按它 + [BoardDefinition.applicableQuestionTypes]
/// 决定要不要选中；不在选中结果里的板块不返回占位条目。
enum BoardTrigger {
  /// 总是适用（L0 题目本体、L5 元信息、常驻诊断）。
  always('always', '总是适用'),

  /// 仅复杂题（DAG、过程解析、卡点、分层提示）。
  complexOnly('complex_only', '仅复杂题'),

  /// 检测到一题多解（一题多解）。
  multipleSolutions('multiple_solutions', '检测到一题多解'),

  /// 存在上位知识（扩展资料、学科史）。
  upperKnowledge('upper_knowledge', '存在上位知识'),

  /// 存在训练需求（额外任务、变式、同源题）。
  training('training', '存在训练需求');

  const BoardTrigger(this.code, this.label);

  /// 稳定编码。
  final String code;

  /// 中文名。
  final String label;

  /// 由编码找触发条件（大小写/空白容错）；认不出返回 null（不猜）。
  static BoardTrigger? tryFromCode(String? code) {
    final normalized = (code ?? '').trim().toLowerCase();
    for (final trigger in BoardTrigger.values) {
      if (trigger.code == normalized) return trigger;
    }
    return null;
  }
}

/// 板块选配用的粗粒度题型词表。
///
/// 这是**选配词汇**，不是内容包的 `classification.content_type` 四轴。选配时
/// 传空串表示题型未知，[selectBoards] 会返回空表（不猜、不返回占位）。
abstract final class BoardQuestionType {
  /// 概念辨析。
  static const String concept = 'concept';

  /// 计算/求解。
  static const String calculation = 'calculation';

  /// 推导/变形。
  static const String derivation = 'derivation';

  /// 证明/论证。
  static const String proof = 'proof';

  /// 实验/探究。
  static const String experiment = 'experiment';

  /// 阅读/理解。
  static const String reading = 'reading';

  /// 表达/写作。
  static const String expression = 'expression';

  /// 词表全集（顺序固定，便于报告/测试）。
  static const List<String> values = <String>[
    concept,
    calculation,
    derivation,
    proof,
    experiment,
    reading,
    expression,
  ];
}

/// 「五维」的现行口径：不再固定成五个字段/板块。
///
/// 旧 Content Schema 把五维写成 `question_type/exam_method/setter_intent/
/// solution_path/ability_training` 五个块；用户 2026-11-15 定为「五维不固定」，
/// 只作为 L5 元信息 + 内容题型四轴的推导结果。本类把这条口径写成可测常量，
/// 避免以后有人又把五维加回成第 16 个板块。
abstract final class FiveDimensionPolicy {
  /// 五维是否仍是固定五字段/五板块：否。
  static const bool fixedFields = false;

  /// 内容题型四轴（权威口径在内容包 `classification.content_type.axes`）。
  static const List<String> contentTypeAxes = <String>[
    'carrier',
    'task',
    'thinking',
    'scope',
  ];

  /// 一句话口径（报告/文档引用）。
  static const String note = '五维不固定为五个字段/板块；由内容题型四轴'
      '（carrier/task/thinking/scope）推导后进 L5 元信息。';
}

/// 一个板块定义：板块库的目录项，不是板块内容本身。
///
/// 本类只描述「有哪些板块、在哪层、什么题型/条件下配、是否必需要有」；具体
/// 题目里的题眼/陷阱/变式等内容仍由内容包承载（本文件不存正文）。
class BoardDefinition {
  const BoardDefinition({
    required this.id,
    required this.name,
    required this.level,
    required this.description,
    this.applicableQuestionTypes = const <String>[],
    this.required = false,
    this.studentVisible = true,
    required this.order,
    this.trigger = BoardTrigger.always,
  });

  /// 稳定 id（内容包/UI/测试共用；不复用旧 `five_dimension` 键）。
  final String id;

  /// 板块中文名。
  final String name;

  /// 所属层级。
  final BoardLevel level;

  /// 这个板块是什么、边界在哪。
  final String description;

  /// 适用题型（[BoardQuestionType] 词表）；空列表 = 所有题型都适用。
  final List<String> applicableQuestionTypes;

  /// 适配时是否必需：必需板块不能静默缺失（内容可以明确写「暂无」并给理由）。
  final bool required;

  /// 是否进入学生视图；元信息等开发者维度为 false。
  final bool studentVisible;

  /// 同层内排序键（升序）。层间留空：L0=10、L1=20…，方便以后插条目。
  final int order;

  /// 触发条件；由 [selectBoards] 解释。
  final BoardTrigger trigger;

  /// 这个板块是否适用于 [questionType]；空串一律不适用（不猜）。
  bool appliesTo(String questionType) {
    final normalized = questionType.trim().toLowerCase();
    if (normalized.isEmpty) return false;
    if (applicableQuestionTypes.isEmpty) return true;
    for (final type in applicableQuestionTypes) {
      if (type.trim().toLowerCase() == normalized) return true;
    }
    return false;
  }

  /// 触发条件是否满足（不看题型；题型判断在 [appliesTo]）。
  bool matches({
    required QuestionComplexity complexity,
    required bool hasMultipleSolutions,
    required bool hasUpperKnowledge,
    required bool hasTraining,
  }) {
    return switch (trigger) {
      BoardTrigger.always => true,
      BoardTrigger.complexOnly => complexity == QuestionComplexity.complex,
      BoardTrigger.multipleSolutions => hasMultipleSolutions,
      BoardTrigger.upperKnowledge => hasUpperKnowledge,
      BoardTrigger.training => hasTraining,
    };
  }

  /// 序列化为 JSON 对象（snake_case 键；内容包/UI 共用）。
  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'name': name,
        'level': level.code,
        'description': description,
        'applicable_question_types': <String>[...applicableQuestionTypes],
        'required': required,
        'student_visible': studentVisible,
        'order': order,
        'trigger': trigger.code,
      };

  /// 从 JSON 对象还原；不认识的层级/触发条件、缺失必填字段都抛
  /// [FormatException]（不静默降级成别的板块）。
  ///
  /// 必填：`id` / `name` / `level` / `description` / `order`；
  /// 可选：`applicable_question_types`（默认空）/ `required` / `student_visible`
  /// （默认取构造默认值）/ `trigger`（默认 `always`）。未知键忽略，便于向前兼容。
  static BoardDefinition fromJson(Object? json) {
    final map = _asMap(json, '板块定义');
    final id = _requiredString(map, 'id', '板块定义');
    final name = _requiredString(map, 'name', '板块定义');
    final level = _requiredLevel(map);
    final description = _requiredString(map, 'description', '板块定义');
    final order = _requiredInt(map, 'order', '板块定义');
    final trigger = _optionalTrigger(map);

    return BoardDefinition(
      id: id,
      name: name,
      level: level,
      description: description,
      applicableQuestionTypes: _optionalStringList(
        map,
        'applicable_question_types',
        '板块定义',
      ),
      required: _optionalBool(map, 'required', '板块定义') ?? false,
      studentVisible: _optionalBool(map, 'student_visible', '板块定义') ?? true,
      order: order,
      trigger: trigger,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is BoardDefinition &&
        other.id == id &&
        other.name == name &&
        other.level == level &&
        other.description == description &&
        _listEquals(other.applicableQuestionTypes, applicableQuestionTypes) &&
        other.required == required &&
        other.studentVisible == studentVisible &&
        other.order == order &&
        other.trigger == trigger;
  }

  @override
  int get hashCode => Object.hash(
        id,
        name,
        level,
        description,
        Object.hashAll(applicableQuestionTypes),
        required,
        studentVisible,
        order,
        trigger,
      );

  @override
  String toString() => 'BoardDefinition(${level.code} $id)';
}

/// 内置板块目录：L0–L5 各层条目，按（层级、order）升序排列。
///
/// 数量：L0 1 条、L1 3 条、L2 5 条（合并诊断）、L3 3 条（由近及远）、
/// L4 2 条（两个子类）、L5 1 条，共 15 条。这里没有 `five_dimension` 板块。
const List<BoardDefinition> kBoardCatalog = <BoardDefinition>[
  // ---- L0 题目本体 ----
  BoardDefinition(
    id: 'l0_question_entity',
    name: '题目本体',
    level: BoardLevel.l0,
    description: '题干/题图/选项/答案/解析/评分参考；题目事实层，不由板块生成或改写。',
    required: true,
    order: 10,
  ),

  // ---- L1 过程结构 ----
  BoardDefinition(
    id: 'l1_thinking_dag',
    name: 'Thinking DAG',
    level: BoardLevel.l1,
    description: '按逻辑依赖组织的步骤、分支与失败支；只复杂题配。',
    required: true,
    order: 20,
    trigger: BoardTrigger.complexOnly,
  ),
  BoardDefinition(
    id: 'l1_solution_walkthrough',
    name: '过程解析',
    level: BoardLevel.l1,
    description: '按步骤讲解解题过程（关键步骤）；简单题不配，答案由 L0 承载。',
    required: true,
    order: 21,
    trigger: BoardTrigger.complexOnly,
  ),
  BoardDefinition(
    id: 'l1_multi_solution',
    name: '一题多解',
    level: BoardLevel.l1,
    description: '同一题的多条解法路径；只在检测到多解时配，禁止硬凑。',
    applicableQuestionTypes: <String>[
      BoardQuestionType.calculation,
      BoardQuestionType.derivation,
      BoardQuestionType.proof,
    ],
    order: 22,
    trigger: BoardTrigger.multipleSolutions,
  ),

  // ---- L2 诊断（合并为一个层级，不再拆成五个层） ----
  BoardDefinition(
    id: 'l2_key_eye',
    name: '题眼',
    level: BoardLevel.l2,
    description: '决定解法的那一句/那个结构（key eye）；说明为什么它是关键。',
    required: true,
    order: 30,
  ),
  BoardDefinition(
    id: 'l2_traps',
    name: '陷阱',
    level: BoardLevel.l2,
    description: '陷阱与易错点：学生会怎么做错、正确动作是什么、怎么验证。',
    required: true,
    order: 31,
  ),
  BoardDefinition(
    id: 'l2_error_causes',
    name: '错因',
    level: BoardLevel.l2,
    description: '错因：症状/根因/诊断问题/补救动作，与步骤或知识点挂钩。',
    required: true,
    order: 32,
  ),
  BoardDefinition(
    id: 'l2_stuck_points',
    name: '卡点',
    level: BoardLevel.l2,
    description: '按步骤标注学生最可能卡住的位置；依赖过程结构，只复杂题配。',
    order: 33,
    trigger: BoardTrigger.complexOnly,
  ),
  BoardDefinition(
    id: 'l2_layered_hints',
    name: '分层提示',
    level: BoardLevel.l2,
    description: '逐级提示且不得含最终答案；简单题不给（用户 A4）。',
    required: true,
    order: 34,
    trigger: BoardTrigger.complexOnly,
  ),

  // ---- L3 训练（由近及远：额外任务 → 变式 → 同源题；order 固定） ----
  BoardDefinition(
    id: 'l3_extra_tasks',
    name: '额外任务',
    level: BoardLevel.l3,
    description: '针对原题让学产生一个可判定的产出；离原题最近。',
    order: 40,
    trigger: BoardTrigger.training,
  ),
  BoardDefinition(
    id: 'l3_variants',
    name: '变式',
    level: BoardLevel.l3,
    description: '换条件/表征但保留同一能力；不重复原题过程（重复宁删）。',
    required: true,
    order: 41,
    trigger: BoardTrigger.training,
  ),
  BoardDefinition(
    id: 'l3_similar_questions',
    name: '同源题',
    level: BoardLevel.l3,
    description: '按图/步骤/载体匹配的真实题库候选；没检索到就空并写明范围，不硬造。',
    required: true,
    order: 42,
    trigger: BoardTrigger.training,
  ),

  // ---- L4 背景（两个子类） ----
  BoardDefinition(
    id: 'l4_extension_material',
    name: '扩展资料',
    level: BoardLevel.l4,
    description: '上位知识：从高中知识一步步搭到上位结论，给用法、示例与限制。',
    required: true,
    order: 50,
    trigger: BoardTrigger.upperKnowledge,
  ),
  BoardDefinition(
    id: 'l4_subject_history',
    name: '学科史',
    level: BoardLevel.l4,
    description: '理论与工具的来路（讲思想与工具怎么发展，不记人名年代）。',
    order: 51,
    trigger: BoardTrigger.upperKnowledge,
  ),

  // ---- L5 元信息 ----
  BoardDefinition(
    id: 'l5_meta',
    name: '元信息',
    level: BoardLevel.l5,
    description: '能力标签/难度/认知负荷/来源/适用题型；五维不固定，由内容题型四轴推导。',
    required: true,
    studentVisible: false,
    order: 60,
  ),
];

/// 按 id 找板块；找不到返回 null（不猜）。
BoardDefinition? findBoard(String id) {
  final normalized = id.trim();
  if (normalized.isEmpty) return null;
  for (final board in kBoardCatalog) {
    if (board.id == normalized) return board;
  }
  return null;
}

/// 某层的全部板块（保持目录顺序）。
List<BoardDefinition> boardsForLevel(BoardLevel level) {
  return List<BoardDefinition>.unmodifiable(<BoardDefinition>[
    for (final board in kBoardCatalog)
      if (board.level == level) board,
  ]);
}

/// 按层级分组（保持 [BoardLevel.values] 的层级顺序，组内保持传入顺序）。
Map<BoardLevel, List<BoardDefinition>> groupBoardsByLevel(
  Iterable<BoardDefinition> boards,
) {
  final grouped = <BoardLevel, List<BoardDefinition>>{};
  for (final board in boards) {
    grouped.putIfAbsent(board.level, () => <BoardDefinition>[]).add(board);
  }
  return Map<BoardLevel, List<BoardDefinition>>.unmodifiable(<BoardLevel,
      List<BoardDefinition>>{
    for (final level in BoardLevel.values)
      if (grouped.containsKey(level))
        level: List<BoardDefinition>.unmodifiable(grouped[level]!),
  });
}

/// 选板：按题型 + 复杂度 + 三个内容事实，返回该题要配的板块（按层级/order 排序）。
///
/// 规则（与 task-94 的验收口径一一对应）：
///
/// * [questionType] 为空/空白：直接返回空表（题型未知不猜，不返回占位）。
/// * 简单题不配 DAG/过程解析：两个 `complexOnly` 的 L1 板块不会出现；
///   卡点、分层提示同样依赖过程结构，简单题也不出现。
/// * 复杂题才配 DAG（以及同属 L1 的过程解析）。
/// * L3 只在 [hasTraining] 时出现，且顺序固定：额外任务 → 变式 → 同源题。
/// * L4 只在 [hasUpperKnowledge] 时出现，两个子类同时给出（扩展资料、学科史）。
/// * L5 元信息总是最后出现；五维不单独成板。
/// * 不适用/没有的板块**不返回**，不造「暂无」占位。
///
/// 返回列表是不可修改的；顺序与 [kBoardCatalog] 的（层级、order）一致。
List<BoardDefinition> selectBoards({
  required String questionType,
  required QuestionComplexity complexity,
  bool hasMultipleSolutions = false,
  bool hasUpperKnowledge = false,
  bool hasTraining = false,
}) {
  if (questionType.trim().isEmpty) {
    return const <BoardDefinition>[];
  }

  final selected = <BoardDefinition>[
    for (final board in kBoardCatalog)
      if (board.appliesTo(questionType) &&
          board.matches(
            complexity: complexity,
            hasMultipleSolutions: hasMultipleSolutions,
            hasUpperKnowledge: hasUpperKnowledge,
            hasTraining: hasTraining,
          ))
        board,
  ];

  // 目录本身已排好；这里显式排序，保证「L3 额外任务→变式→同源题」不依赖
  // 目录书写顺序，也不依赖调用方传参顺序。
  selected.sort((a, b) {
    final byLevel = a.level.index.compareTo(b.level.index);
    if (byLevel != 0) return byLevel;
    final byOrder = a.order.compareTo(b.order);
    if (byOrder != 0) return byOrder;
    return a.id.compareTo(b.id);
  });
  return List<BoardDefinition>.unmodifiable(selected);
}

/// 目录 → JSON 对象列表（默认导出内置目录）。
List<Map<String, Object?>> encodeBoardCatalog([
  List<BoardDefinition> boards = kBoardCatalog,
]) {
  return List<Map<String, Object?>>.unmodifiable(<Map<String, Object?>>[
    for (final board in boards) board.toJson(),
  ]);
}

/// JSON 对象列表 → 目录；任何一项不合法都抛 [FormatException]（带序号）。
List<BoardDefinition> decodeBoardCatalog(Object? json) {
  if (json is! List) {
    throw FormatException('板块库 JSON 必须是数组，实际是 ${json.runtimeType}');
  }
  final boards = <BoardDefinition>[];
  for (var index = 0; index < json.length; index++) {
    try {
      boards.add(BoardDefinition.fromJson(json[index]));
    } on FormatException catch (error) {
      throw FormatException('板块库第 $index 项：${error.message}');
    }
  }
  return List<BoardDefinition>.unmodifiable(boards);
}

/// 目录 → JSON 字符串（UTF-8 无关，纯 `dart:convert`）。
String encodeBoardCatalogJson([
  List<BoardDefinition> boards = kBoardCatalog,
]) {
  return jsonEncode(encodeBoardCatalog(boards));
}

/// JSON 字符串 → 目录；JSON 语法错误或结构不合法都抛 [FormatException]。
List<BoardDefinition> decodeBoardCatalogJson(String source) {
  return decodeBoardCatalog(jsonDecode(source));
}

// ---------------------------------------------------------------------------
// JSON 解析内部工具：只接受 JSON 原生类型，类型不符就抛 FormatException。
// ---------------------------------------------------------------------------

Map<String, Object?> _asMap(Object? json, String where) {
  if (json is Map<String, Object?>) return json;
  if (json is Map) {
    return <String, Object?>{
      for (final entry in json.entries)
        if (entry.key is String) entry.key as String: entry.value,
    };
  }
  throw FormatException('$where 必须是 JSON 对象，实际是 ${json.runtimeType}');
}

String _requiredString(Map<String, Object?> map, String key, String where) {
  final value = map[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$where.$key 必须是非空字符串，实际是 $value');
  }
  return value.trim();
}

BoardLevel _requiredLevel(Map<String, Object?> map) {
  final code = _requiredString(map, 'level', '板块定义');
  final level = BoardLevel.tryFromCode(code);
  if (level == null) {
    throw FormatException('板块定义.level 不认识的层级：$code（期望 L0–L5）');
  }
  return level;
}

BoardTrigger _optionalTrigger(Map<String, Object?> map) {
  final value = map['trigger'];
  if (value == null) return BoardTrigger.always;
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('板块定义.trigger 必须是字符串，实际是 $value');
  }
  final trigger = BoardTrigger.tryFromCode(value);
  if (trigger == null) {
    throw FormatException('板块定义.trigger 不认识的触发条件：$value');
  }
  return trigger;
}

int _requiredInt(Map<String, Object?> map, String key, String where) {
  final value = map[key];
  if (value is! int) {
    throw FormatException('$where.$key 必须是整数，实际是 $value');
  }
  if (value < 0) {
    throw FormatException('$where.$key 不能为负：$value');
  }
  return value;
}

List<String> _optionalStringList(
  Map<String, Object?> map,
  String key,
  String where,
) {
  final value = map[key];
  if (value == null) return const <String>[];
  if (value is! List) {
    throw FormatException('$where.$key 必须是字符串数组，实际是 $value');
  }
  final types = <String>[];
  for (final item in value) {
    if (item is! String || item.trim().isEmpty) {
      throw FormatException('$where.$key 含非法项：$item');
    }
    types.add(item.trim().toLowerCase());
  }
  return List<String>.unmodifiable(types);
}

bool? _optionalBool(Map<String, Object?> map, String key, String where) {
  final value = map[key];
  if (value == null) return null;
  if (value is! bool) {
    throw FormatException('$where.$key 必须是布尔值，实际是 $value');
  }
  return value;
}

bool _listEquals(List<String> a, List<String> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var index = 0; index < a.length; index++) {
    if (a[index] != b[index]) return false;
  }
  return true;
}
