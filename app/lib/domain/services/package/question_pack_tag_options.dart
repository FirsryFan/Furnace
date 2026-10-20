/// 题库包标签路径筛选选项（纯逻辑，不依赖 Flutter / dart:io）。
///
/// 输入是一条题目记录身上的标签路径集合（`QuestionPackRecord.tagPaths`），
/// 输出是给筛选界面用的可勾选项列表：路径、该路径下的题目数、是否已选。
/// 排序规则与界面无关：题目数降序，其次路径字面量升序。
class QuestionPackTagPathOption {
  const QuestionPackTagPathOption({
    required this.path,
    required this.questionCount,
    this.selected = false,
  });

  /// 归一后的标签路径（去掉了两端空白，不会是空串）。
  final String path;

  /// 该路径下的题目数（永远 >= 0，缺省按 0）。
  final int questionCount;

  /// 是否已选。
  final bool selected;

  /// 排序权重，等于题目数（负数已归 0）。
  int get weight => questionCount;

  /// 路径是否为空（只可能手动构造出来；正常选项不会为空）。
  bool get isEmpty => path.trim().isEmpty;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'path': path,
      'question_count': questionCount,
      'selected': selected,
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is QuestionPackTagPathOption &&
        other.path == path &&
        other.questionCount == questionCount &&
        other.selected == selected;
  }

  @override
  int get hashCode => Object.hash(path, questionCount, selected);

  @override
  String toString() {
    return 'QuestionPackTagPathOption(path: $path, questionCount: $questionCount, '
        'selected: $selected)';
  }
}

/// 把标签路径列表整理成筛选选项。
///
/// * [tagPaths]：原始路径集合；去两端空白、丢空串、按归一后的路径去重，
///   保留首次出现的顺序；
/// * [questionCountByPath]：路径 -> 题目数；缺省 0，负数按 0；
/// * [selectedPaths]：已选路径；trim 后精确匹配（区分大小写）；
/// * [maxOptionCount]：最多返回多少项（selected 选项永远保留，可能超过该上限）；
///   `<= 0` 时只保留 selected 选项。
///
/// 排序：questionCount 降序 -> path 的 `compareTo` 升序（与运行语言无关）。
/// 返回不可变列表。
List<QuestionPackTagPathOption> questionPackTagPathOptions({
  required Iterable<String> tagPaths,
  Map<String, int> questionCountByPath = const <String, int>{},
  Set<String> selectedPaths = const <String>{},
  int maxOptionCount = 200,
}) {
  final List<String> normalizedPaths = <String>[];
  final Set<String> seen = <String>{};
  for (final String raw in tagPaths) {
    final String? normalized = normalizeQuestionPackTagPath(raw);
    if (normalized == null || !seen.add(normalized)) {
      continue;
    }
    normalizedPaths.add(normalized);
  }

  final Set<String> selected = selectedQuestionPackTagPaths(selectedPaths);
  final List<QuestionPackTagPathOption> options = <QuestionPackTagPathOption>[
    for (final String path in normalizedPaths)
      QuestionPackTagPathOption(
        path: path,
        questionCount: _clampCount(questionCountByPath[path]),
        selected: selected.contains(path),
      ),
  ];
  options.sort(_compareOptions);

  if (maxOptionCount <= 0) {
    return List<QuestionPackTagPathOption>.unmodifiable(
      options.where((QuestionPackTagPathOption option) => option.selected),
    );
  }

  final List<QuestionPackTagPathOption> kept = <QuestionPackTagPathOption>[];
  final Set<String> keptPaths = <String>{};
  for (final QuestionPackTagPathOption option in options) {
    if (kept.length >= maxOptionCount) {
      break;
    }
    kept.add(option);
    keptPaths.add(option.path);
  }
  for (final QuestionPackTagPathOption option in options) {
    if (option.selected && !keptPaths.contains(option.path)) {
      kept.add(option);
      keptPaths.add(option.path);
    }
  }
  return List<QuestionPackTagPathOption>.unmodifiable(kept);
}

/// 归一化单个标签路径：trim；空串 -> null；内部连续空白不压缩。
String? normalizeQuestionPackTagPath(String? raw) {
  if (raw == null) {
    return null;
  }
  final String trimmed = raw.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  return trimmed;
}

/// 把已选路径列表归一成不可变集合：trim、丢空、去重。
Set<String> selectedQuestionPackTagPaths(Iterable<String> raw) {
  final Set<String> selected = <String>{};
  for (final String value in raw) {
    final String trimmed = value.trim();
    if (trimmed.isNotEmpty) {
      selected.add(trimmed);
    }
  }
  return Set<String>.unmodifiable(selected);
}

int _clampCount(int? value) {
  if (value == null || value < 0) {
    return 0;
  }
  return value;
}

int _compareOptions(QuestionPackTagPathOption a, QuestionPackTagPathOption b) {
  final int byCount = b.questionCount.compareTo(a.questionCount);
  if (byCount != 0) {
    return byCount;
  }
  return a.path.compareTo(b.path);
}
