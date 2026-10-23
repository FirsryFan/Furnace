/// 选择题客观判分：把「用户选了什么」与「选项里标了哪些正确答案」比成一份结果。
///
/// 这一层只服务 UI 的即时核对（交卷后立刻显示对错），不写库、不依赖题型枚举类
/// 以外的任何状态。口径：
///
/// * **客观题型只有** `single_choice` / `multi_choice`（`trim` + `toLowerCase`
///   后比较）。其它题型（`fill_blank` / `solution` / `open` / 空串 / 未知）一律
///   [ObjectiveAttemptStatus.notObjective]，四个 label 列表都为空——不猜一个分数。
/// * 客观题但选项里**没有任何** `isCorrect: true` 时也是 notObjective：没有正确
///   答案标记就无法判分，这不等于「全错」。
/// * 标签归一化：`trim` + `toUpperCase`（所以 `' b '` 与 `'B'` 是同一个选项）；
///   归一化后为空的标签不参与正确集合，也不构成一次选择。
/// * 选择为空（归一化后没有任何非空标签）→ `emptySelection`：还没作答，但
///   [ObjectiveAttemptResult.correctLabels] 照样填上（界面可以提示「应选 A」）。
/// * 判对条件：选择集合与正确集合**完全相等**。`single_choice` 与
///   `multi_choice` 共用同一套集合相等判定，所以单选多选一项会进
///   [ObjectiveAttemptResult.extraLabels] → 判错。
/// * 输出列表全部升序、去重、不可修改；函数不抛异常（`options` 为空也不抛）。
///
/// 纯函数：不读 IO、不使用时间/随机数，同一输入永远同一输出。
library;

/// 客观题型的取值（比较前先 `trim` + `toLowerCase`）。
const Set<String> _objectiveQuestionTypes = <String>{
  'single_choice',
  'multi_choice',
};

/// 一次客观判分的状态。
///
/// 顺序有意义：`notObjective` 最先（压根没法判），`emptySelection` 次之（能判但
/// 用户没作答），最后才是对/错。
enum ObjectiveAttemptStatus {
  notObjective,
  emptySelection,
  correct,
  incorrect,
}

/// 客观题的一个选项：标签 + 是否被标为正确答案。
///
/// [label] 不要求已经归一化（判分时统一 `trim` + `toUpperCase`）；空标签的选项会
/// 被忽略，不参与正确集合。
class ObjectiveOption {
  const ObjectiveOption({required this.label, required this.isCorrect});

  /// 选项标签（如 `A`、`B`；判分时归一化）。
  final String label;

  /// 这道题的答案里是否包含该选项。
  final bool isCorrect;
}

/// 一次判分的结果。
///
/// 四个 label 列表都由 [scoreObjectiveAnswer] 生成：升序、去重、不可修改。直接
/// `const` 构造时调用方自己保证不要修改传入列表。
class ObjectiveAttemptResult {
  const ObjectiveAttemptResult({
    required this.status,
    required this.selectedLabels,
    required this.correctLabels,
    required this.missingLabels,
    required this.extraLabels,
  });

  /// 判分状态。
  final ObjectiveAttemptStatus status;

  /// 归一化后的选择（升序）。
  final List<String> selectedLabels;

  /// 正确选项标签（升序）；`notObjective` 时为空。
  final List<String> correctLabels;

  /// 正确但没选（升序）。
  final List<String> missingLabels;

  /// 选了但不对（升序）。
  final List<String> extraLabels;

  /// 是否完全答对；`notObjective` / `emptySelection` 都是 false。
  bool get isCorrect => status == ObjectiveAttemptStatus.correct;

  /// 是否答错（漏选 / 多选错项）；`notObjective` / `emptySelection` 都是 false。
  bool get isIncorrect => status == ObjectiveAttemptStatus.incorrect;
}

/// 题型是否为客观题：`single_choice` / `multi_choice`（`trim` + 小写后比较）。
///
/// 空串、空白串、未知题型、`fill_blank` / `solution` / `open` 都返回 false。
bool isObjectiveQuestionType(String questionType) {
  return _objectiveQuestionTypes.contains(questionType.trim().toLowerCase());
}

/// 这道题现在能不能判分：题型是客观题，**且**至少有一个正确选项标签。
///
/// 注意这是 [isObjectiveQuestionType] 的超集条件：题型不对，即使选项里有人标了
/// `isCorrect: true` 也不能按客观题判（它可能是一道填空题被误标）。
bool canScoreObjectiveQuestion({
  required String questionType,
  required List<ObjectiveOption> options,
}) {
  if (!isObjectiveQuestionType(questionType)) {
    return false;
  }
  return _correctLabelSet(options).isNotEmpty;
}

/// 判一次客观题作答。
///
/// [questionType] 决定能不能判；[options] 用 `isCorrect` 标出正确答案；
/// [selectedLabels] 是用户勾选的标签（顺序/大小写/空白都不影响结果）。
///
/// 返回结果的四个列表升序、去重、不可修改；任何输入都不抛异常。
ObjectiveAttemptResult scoreObjectiveAnswer({
  required String questionType,
  required List<ObjectiveOption> options,
  required Iterable<String> selectedLabels,
}) {
  if (!isObjectiveQuestionType(questionType)) {
    return const ObjectiveAttemptResult(
      status: ObjectiveAttemptStatus.notObjective,
      selectedLabels: <String>[],
      correctLabels: <String>[],
      missingLabels: <String>[],
      extraLabels: <String>[],
    );
  }

  final correctLabels = _sortedLabels(_correctLabelSet(options));
  if (correctLabels.isEmpty) {
    // 客观题但没有正确标记（或正确选项全是空标签）：判不了，不是「全错」。
    return const ObjectiveAttemptResult(
      status: ObjectiveAttemptStatus.notObjective,
      selectedLabels: <String>[],
      correctLabels: <String>[],
      missingLabels: <String>[],
      extraLabels: <String>[],
    );
  }

  final selectedSet = _labelSet(selectedLabels);
  final selected = _sortedLabels(selectedSet);
  if (selected.isEmpty) {
    return ObjectiveAttemptResult(
      status: ObjectiveAttemptStatus.emptySelection,
      selectedLabels: selected,
      correctLabels: correctLabels,
      missingLabels: const <String>[],
      extraLabels: const <String>[],
    );
  }

  final correctSet = correctLabels.toSet();
  final missing = <String>[
    for (final label in correctLabels)
      if (!selectedSet.contains(label)) label,
  ];
  final extra = <String>[
    for (final label in selected)
      if (!correctSet.contains(label)) label,
  ];
  return ObjectiveAttemptResult(
    status: missing.isEmpty && extra.isEmpty
        ? ObjectiveAttemptStatus.correct
        : ObjectiveAttemptStatus.incorrect,
    selectedLabels: selected,
    correctLabels: correctLabels,
    missingLabels: List<String>.unmodifiable(missing),
    extraLabels: List<String>.unmodifiable(extra),
  );
}

/// 收集 options 里被标为正确的标签，交给 [_labelSet] 归一化。
Set<String> _correctLabelSet(Iterable<ObjectiveOption> options) {
  return _labelSet(
    options.where((option) => option.isCorrect).map((option) => option.label),
  );
}

/// 把一批标签归一化成集合（`trim` + 大写，空标签剔除）。
Set<String> _labelSet(Iterable<String> labels) {
  final normalized = <String>{};
  for (final label in labels) {
    final clean = label.trim().toUpperCase();
    if (clean.isNotEmpty) {
      normalized.add(clean);
    }
  }
  return normalized;
}

/// 集合 → 升序、去重、不可修改的列表。
List<String> _sortedLabels(Set<String> labels) {
  final sorted = labels.toList()..sort();
  return List<String>.unmodifiable(sorted);
}
