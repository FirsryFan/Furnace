/// 扩展题（变式）与母题关联：把 `extension_of` 解析成可查询的索引（纯逻辑）。
///
/// 背景：`FURNACE-PIPELINE-SPEC-v1.md` §7 M2 给 .tqb 记录加了可选字段
/// `extension_of: "<zujuan_question_id>"`——扩展题（变式）挂到母题上；§7 M3 要求
/// 后续把「错题 / 变式」按专题标签与能力挂进复习队列。本文件只做**解析与索引**：
/// 不 import drift / 数据库 / entity，不读库、不写库、不抛异常（遇到脏数据只记进
/// [QuestionExtensionIndex.problems]），同一输入永远同一输出。
///
/// 口径（每条都有测试钉住）：
/// * 输入行用 [QuestionExtensionRow]：`questionId` 是本地题目 id，
///   `zujuanQuestionId` 是组卷网题号（`extension_of` 指向它），`serialNo` 只用来
///   排序扩展题。
/// * 文本先 trim；空白 `zujuanQuestionId` / `extensionOfZujuanQuestionId` 视为
///   「没有」；空白 `questionId` 的行进问题清单（`missingQuestionId`），不参与关联。
/// * 同 `questionId` 出现多次 → 只认输入里的第一条，其余记
///   `duplicateQuestionId`。
/// * 同 `zujuanQuestionId` 出现多次 → 也只认第一条；其余行**整行**不参与关联
///   （`duplicateZujuanQuestionId`），这样一道母题不会因两个候选而解析出两套关系。
/// * `extension_of` 等于自己的 `zujuan_question_id` → `selfReference`；
///   两条以上首尾相连成环（A→B→A、A→B→C→A）→ 环上每条记 `mutualReference`，
///   环上的边都不算；指向库内不存在的题号 → `danglingParent`。
/// * 母题本身无效（在环上）时，它的扩展题记 `invalidParent`，沿着父链一层层
///   传下去；传递用迭代走链，**不递归**，环再长也不会爆栈。
/// * 既没有母题、也没被任何扩展题指向的独立题不进索引。
/// * 扩展题列表按 `serialNo` 升序；没有号（null 或 <1）的排在有号之后、保持输入
///   顺序；同号按输入顺序。比较器带输入下标，所以不依赖 `List.sort` 的稳定性：
///   输入换一个排列，得到的顺序也完全确定。
/// * [QuestionExtensionIndex.problems] 按「题目 id → 问题类型 → 原因文案 →
///   details」固定排序并去重，输入顺序不影响结果。
library;

/// 关联解析发现的问题类型（[code] 是稳定编码，落库/日志/UI 用，不随枚举改名而变）。
enum QuestionExtensionProblemKind {
  /// 行的 `questionId` trim 后为空，没法当索引键。
  missingQuestionId('missing_question_id'),

  /// 同一 `questionId` 出现多次：只认第一条。
  duplicateQuestionId('duplicate_question_id'),

  /// 同一 `zujuanQuestionId` 出现多次：只认第一条，其余行整行不参与关联。
  duplicateZujuanQuestionId('duplicate_zujuan_question_id'),

  /// `extension_of` 指向自己的 `zujuan_question_id`。
  selfReference('self_reference'),

  /// 首尾相连成环（A→B→A、A→B→C→A）：环上的边全部不算。
  mutualReference('mutual_reference'),

  /// `extension_of` 指向的组卷网题号在本题库里不存在。
  danglingParent('dangling_parent'),

  /// 母题本身无效（在环上），这道扩展题跟着无效；沿父链迭代传递。
  invalidParent('invalid_parent');

  const QuestionExtensionProblemKind(this.code);

  /// 稳定编码（小写蛇形）。
  final String code;
}

/// 一条参与关联解析的题目行（不可变值对象，不依赖 drift/DB）。
///
/// 只放关联需要的字段：本地 id、组卷网题号、`extension_of`、排序用的序号。
/// 其余题目字段（题干、选项、标签…）由调用方自己的行对象持有，不进本层。
class QuestionExtensionRow {
  const QuestionExtensionRow({
    required this.questionId,
    this.zujuanQuestionId,
    this.extensionOfZujuanQuestionId,
    this.serialNo,
  });

  /// 本地题目 id（主键；trim 后必须非空）。
  final String questionId;

  /// 组卷网题号（`questions.zujuan_question_id` 的同形值；可空）。
  final String? zujuanQuestionId;

  /// 母题的组卷网题号（.tqb 的 `extension_of`；可空 = 独立题）。
  final String? extensionOfZujuanQuestionId;

  /// 题目编号（`serial_no`）；只用于扩展题排序，null 或 <1 视为没有号。
  final int? serialNo;

  @override
  String toString() =>
      'QuestionExtensionRow($questionId, zujuan: $zujuanQuestionId, '
      'extensionOf: $extensionOfZujuanQuestionId, serial: $serialNo)';
}

/// 一条有效的「母题 → 扩展题」关联。
class QuestionExtensionLink {
  const QuestionExtensionLink({
    required this.parentQuestionId,
    required this.extensionQuestionId,
  });

  /// 母题的本地题目 id。
  final String parentQuestionId;

  /// 扩展题（变式）的本地题目 id。
  final String extensionQuestionId;

  /// 给 UI / 日志 / 后续落库用的稳定 JSON（键名小写蛇形）。
  Map<String, Object?> toJson() => <String, Object?>{
        'parent_question_id': parentQuestionId,
        'extension_question_id': extensionQuestionId,
      };

  @override
  bool operator ==(Object other) =>
      other is QuestionExtensionLink &&
      other.parentQuestionId == parentQuestionId &&
      other.extensionQuestionId == extensionQuestionId;

  @override
  int get hashCode => Object.hash(parentQuestionId, extensionQuestionId);

  @override
  String toString() =>
      'QuestionExtensionLink($parentQuestionId → $extensionQuestionId)';
}

/// 关联解析发现的一个问题（无效关系 / 被忽略的行）。
class QuestionExtensionProblem {
  QuestionExtensionProblem({
    required this.questionId,
    required this.kind,
    required this.reasonZh,
    Map<String, String> details = const <String, String>{},
  }) : details = Map<String, String>.unmodifiable(details);

  /// 出问题的题目 id（可能是空串：那一行的 `questionId` 本身为空）。
  final String questionId;

  /// 问题类型。
  final QuestionExtensionProblemKind kind;

  /// 给人看的中文原因（确定性文案，便于测试与回显）。
  final String reasonZh;

  /// 机器可读的补充字段（小写蛇形键；不可变）。
  final Map<String, String> details;

  /// 稳定 JSON（键名小写蛇形）。
  Map<String, Object?> toJson() => <String, Object?>{
        'question_id': questionId,
        'kind': kind.code,
        'reason_zh': reasonZh,
        'details': details,
      };

  @override
  String toString() =>
      'QuestionExtensionProblem($questionId, ${kind.code}, $reasonZh)';
}

/// `extension_of` 解析结果：母题→扩展题列表、扩展题→母题、问题清单。
///
/// 构造后不可变；[extensionsByParentQuestionId] 的键按题目 id 升序插入、
/// 每个列表的扩展题顺序见 library doc。
class QuestionExtensionIndex {
  QuestionExtensionIndex._({
    required Map<String, List<QuestionExtensionLink>>
        extensionsByParentQuestionId,
    required Map<String, String> parentQuestionIdOfExtension,
    required List<QuestionExtensionProblem> problems,
  })  : extensionsByParentQuestionId =
            Map<String, List<QuestionExtensionLink>>.unmodifiable(
          extensionsByParentQuestionId,
        ),
        parentQuestionIdOfExtension =
            Map<String, String>.unmodifiable(parentQuestionIdOfExtension),
        problems = List<QuestionExtensionProblem>.unmodifiable(problems);

  /// 空索引：没有关联、没有问题（空输入 / 全是独立题时的结果）。
  static final QuestionExtensionIndex empty = QuestionExtensionIndex._(
    extensionsByParentQuestionId: <String, List<QuestionExtensionLink>>{},
    parentQuestionIdOfExtension: <String, String>{},
    problems: <QuestionExtensionProblem>[],
  );

  /// 母题 id → 扩展题列表（列表不可变，顺序见 library doc）。
  final Map<String, List<QuestionExtensionLink>> extensionsByParentQuestionId;

  /// 扩展题 id → 母题 id（只含有效关联）。
  final Map<String, String> parentQuestionIdOfExtension;

  /// 无效关系与被忽略行的问题清单（不可变，排序确定）。
  final List<QuestionExtensionProblem> problems;

  /// 没有任何有效关联。
  bool get isEmpty => extensionsByParentQuestionId.isEmpty;

  /// [isEmpty] 的取反。
  bool get isNotEmpty => !isEmpty;

  /// 至少有 C 个扩展题的母题数。
  int get parentCount => extensionsByParentQuestionId.length;

  /// 有效扩展题总数（每道扩展题只算一次）。
  int get extensionCount => parentQuestionIdOfExtension.length;

  /// 有问题（无效关系 / 被忽略行）时为 true；不代表没有任何有效关联。
  bool get hasProblems => problems.isNotEmpty;

  /// 查询某道母题的扩展题（无 → 空列表，不抛异常）。
  List<QuestionExtensionLink> extensionsOf(String parentQuestionId) {
    final String id = parentQuestionId.trim();
    if (id.isEmpty) {
      return const <QuestionExtensionLink>[];
    }
    return extensionsByParentQuestionId[id] ?? const <QuestionExtensionLink>[];
  }

  /// 查询某道母题的扩展题 id（按索引顺序）。
  List<String> extensionQuestionIdsOf(String parentQuestionId) =>
      List<String>.unmodifiable(<String>[
        for (final QuestionExtensionLink link in extensionsOf(parentQuestionId))
          link.extensionQuestionId,
      ]);

  /// 查询某道扩展题的母题 id；不是扩展题（或关联无效）返回 null。
  String? parentQuestionIdOf(String extensionQuestionId) {
    final String id = extensionQuestionId.trim();
    if (id.isEmpty) {
      return null;
    }
    return parentQuestionIdOfExtension[id];
  }

  /// 这道题是不是一道有效扩展题。
  bool isExtension(String questionId) => parentQuestionIdOf(questionId) != null;

  /// 某道题相关的问题（按 [problems] 顺序；无 → 空列表）。
  List<QuestionExtensionProblem> problemsFor(String questionId) {
    final String id = questionId.trim();
    if (id.isEmpty) {
      return const <QuestionExtensionProblem>[];
    }
    return List<
        QuestionExtensionProblem>.unmodifiable(<QuestionExtensionProblem>[
      for (final QuestionExtensionProblem problem in problems)
        if (problem.questionId == id) problem,
    ]);
  }

  @override
  String toString() => 'QuestionExtensionIndex(parents: $parentCount, '
      'extensions: $extensionCount, problems: ${problems.length})';
}

/// 由 `extension_of` 行数据构建索引（纯函数，不抛异常）。
///
/// 空输入返回 [QuestionExtensionIndex.empty]；脏数据（空白 id、重复 id / 重复题号、
/// 自指、成环、悬空引用）都进 [QuestionExtensionIndex.problems]，有效关联照常保留。
QuestionExtensionIndex buildQuestionExtensionIndex(
  Iterable<QuestionExtensionRow> rows,
) {
  final List<QuestionExtensionProblem> problems = <QuestionExtensionProblem>[];
  final List<_CleanRow> cleanRows = <_CleanRow>[];
  final Set<String> seenQuestionIds = <String>{};
  final Map<String, String> questionIdByZujuanId = <String, String>{};
  int inputIndex = 0;
  for (final QuestionExtensionRow row in rows) {
    final int index = inputIndex++;
    final String questionId = row.questionId.trim();
    if (questionId.isEmpty) {
      problems.add(QuestionExtensionProblem(
        questionId: questionId,
        kind: QuestionExtensionProblemKind.missingQuestionId,
        reasonZh: '题目 id 为空，无法参与母题关联',
        details: <String, String>{'input_index': '$index'},
      ));
      continue;
    }
    if (!seenQuestionIds.add(questionId)) {
      problems.add(QuestionExtensionProblem(
        questionId: questionId,
        kind: QuestionExtensionProblemKind.duplicateQuestionId,
        reasonZh: '同一题目 id 出现多次，只认第一条',
        details: <String, String>{
          'input_index': '$index',
          'kept_input_index': '${_firstInputIndex(cleanRows, questionId)}',
        },
      ));
      continue;
    }
    final String? zujuan = _nonEmpty(row.zujuanQuestionId);
    final String? extensionOf = _nonEmpty(row.extensionOfZujuanQuestionId);
    final int? serialNo =
        (row.serialNo != null && row.serialNo! >= 1) ? row.serialNo : null;
    if (zujuan != null) {
      final String? firstQuestionId = questionIdByZujuanId[zujuan];
      if (firstQuestionId != null) {
        problems.add(QuestionExtensionProblem(
          questionId: questionId,
          kind: QuestionExtensionProblemKind.duplicateZujuanQuestionId,
          reasonZh: '组卷网题号 $zujuan 已被 $firstQuestionId 占用，这一行整行不参与关联',
          details: <String, String>{
            'zujuan_question_id': zujuan,
            'first_question_id': firstQuestionId,
            'input_index': '$index',
          },
        ));
        continue;
      }
      questionIdByZujuanId[zujuan] = questionId;
    }
    cleanRows.add(_CleanRow(
      questionId: questionId,
      zujuanQuestionId: zujuan,
      extensionOfZujuanQuestionId: extensionOf,
      serialNo: serialNo,
      inputIndex: index,
    ));
  }

  if (cleanRows.isEmpty) {
    return QuestionExtensionIndex._(
      extensionsByParentQuestionId: <String, List<QuestionExtensionLink>>{},
      parentQuestionIdOfExtension: <String, String>{},
      problems: _sortedProblems(problems),
    );
  }

  // 第一步：逐行解析 extension_of，得到「扩展题 → 母题」候选边。
  final Map<String, String> parentByChild = <String, String>{};
  for (final _CleanRow row in cleanRows) {
    final String? extensionOf = row.extensionOfZujuanQuestionId;
    if (extensionOf == null) {
      continue;
    }
    if (row.zujuanQuestionId != null && extensionOf == row.zujuanQuestionId) {
      problems.add(QuestionExtensionProblem(
        questionId: row.questionId,
        kind: QuestionExtensionProblemKind.selfReference,
        reasonZh: '母题指向自己（extension_of == 自己的组卷网题号 $extensionOf）',
        details: <String, String>{
          'zujuan_question_id': extensionOf,
          'input_index': '${row.inputIndex}',
        },
      ));
      continue;
    }
    final String? parentQuestionId = questionIdByZujuanId[extensionOf];
    if (parentQuestionId == null) {
      problems.add(QuestionExtensionProblem(
        questionId: row.questionId,
        kind: QuestionExtensionProblemKind.danglingParent,
        reasonZh: 'extension_of 指向的组卷网题号 $extensionOf 不在本题库内',
        details: <String, String>{
          'extension_of': extensionOf,
          'input_index': '${row.inputIndex}',
        },
      ));
      continue;
    }
    parentByChild[row.questionId] = parentQuestionId;
  }

  // 第二步：迭代找环并把「母题本身无效」沿父链传下去（不递归，环再长也不爆栈）。
  final Map<String, _ChainState> states = <String, _ChainState>{};
  final List<String> childIds = <String>[
    for (final _CleanRow row in cleanRows)
      if (parentByChild.containsKey(row.questionId)) row.questionId,
  ]..sort();
  for (final String start in childIds) {
    if (states.containsKey(start)) {
      continue;
    }
    final List<String> path = <String>[];
    final Map<String, int> pathIndex = <String, int>{};
    String? current = start;
    while (current != null) {
      final _ChainState? known = states[current];
      if (known != null) {
        // 这条路挂到已经判过的节点上：根有效则整条有效，否则整条跟着无效。
        final _ChainState resolved = known == _ChainState.valid
            ? _ChainState.valid
            : _ChainState.invalid;
        for (final String id in path) {
          states[id] = resolved;
        }
        break;
      }
      final int? seenAt = pathIndex[current];
      if (seenAt != null) {
        final List<String> cycle = path.sublist(seenAt);
        for (final String id in cycle) {
          states[id] = _ChainState.cycle;
        }
        for (int i = 0; i < seenAt; i++) {
          states[path[i]] = _ChainState.invalid;
        }
        final List<String> ordered = _rotateCycleToSmallest(cycle);
        final String chain = <String>[...ordered, ordered.first].join(' → ');
        for (final String id in cycle) {
          problems.add(QuestionExtensionProblem(
            questionId: id,
            kind: QuestionExtensionProblemKind.mutualReference,
            reasonZh: '母题关系成环（互相指向）：$chain',
            details: <String, String>{'cycle': chain},
          ));
        }
        break;
      }
      pathIndex[current] = path.length;
      path.add(current);
      current = parentByChild[current];
    }
    if (current == null) {
      for (final String id in path) {
        states[id] = _ChainState.valid;
      }
    }
  }

  // 第三步：环上节点的扩展题记 invalidParent（states == invalid）。
  for (final MapEntry<String, String> entry in parentByChild.entries) {
    if (states[entry.key] != _ChainState.invalid) {
      continue;
    }
    final String parentId = entry.value;
    final _ChainState parentState = states[parentId] ?? _ChainState.invalid;
    problems.add(QuestionExtensionProblem(
      questionId: entry.key,
      kind: QuestionExtensionProblemKind.invalidParent,
      reasonZh: '母题 $parentId 本身在无效的母题关系里，这道扩展题跟着无效',
      details: <String, String>{
        'parent_question_id': parentId,
        'parent_state': parentState == _ChainState.cycle
            ? _ChainState.cycle.name
            : _ChainState.invalid.name,
      },
    ));
  }

  // 第四步：只为有效边建索引，并按 serialNo 排序扩展题。
  final Map<String, List<_ChildOrder>> childrenByParent =
      <String, List<_ChildOrder>>{};
  final Map<String, String> parentOfExtension = <String, String>{};
  for (final _CleanRow row in cleanRows) {
    final String? parentId = parentByChild[row.questionId];
    if (parentId == null || states[row.questionId] != _ChainState.valid) {
      continue;
    }
    parentOfExtension[row.questionId] = parentId;
    childrenByParent
        .putIfAbsent(parentId, () => <_ChildOrder>[])
        .add(_ChildOrder(
          extensionQuestionId: row.questionId,
          serialNo: row.serialNo,
          inputIndex: row.inputIndex,
        ));
  }

  final List<String> parentIds = childrenByParent.keys.toList()..sort();
  final Map<String, List<QuestionExtensionLink>> byParent =
      <String, List<QuestionExtensionLink>>{};
  for (final String parentId in parentIds) {
    final List<_ChildOrder> children = childrenByParent[parentId]!
      ..sort(_compareChildOrder);
    byParent[parentId] = List<QuestionExtensionLink>.unmodifiable(
      <QuestionExtensionLink>[
        for (final _ChildOrder child in children)
          QuestionExtensionLink(
            parentQuestionId: parentId,
            extensionQuestionId: child.extensionQuestionId,
          ),
      ],
    );
  }

  return QuestionExtensionIndex._(
    extensionsByParentQuestionId: byParent,
    parentQuestionIdOfExtension: parentOfExtension,
    problems: _sortedProblems(problems),
  );
}

/// 一条清洗后的输入行（内部用）。
class _CleanRow {
  const _CleanRow({
    required this.questionId,
    required this.zujuanQuestionId,
    required this.extensionOfZujuanQuestionId,
    required this.serialNo,
    required this.inputIndex,
  });

  final String questionId;
  final String? zujuanQuestionId;
  final String? extensionOfZujuanQuestionId;
  final int? serialNo;
  final int inputIndex;
}

/// 扩展题排序键（serialNo 优先，缺失排后、按输入顺序兜底）。
class _ChildOrder {
  const _ChildOrder({
    required this.extensionQuestionId,
    required this.serialNo,
    required this.inputIndex,
  });

  final String extensionQuestionId;
  final int? serialNo;
  final int inputIndex;
}

/// 父链判定结果：ok（一路走到头）/ cycle（在环上）/ invalid（连到环上）。
enum _ChainState { valid, cycle, invalid }

int _compareChildOrder(_ChildOrder a, _ChildOrder b) {
  final int? sa = a.serialNo;
  final int? sb = b.serialNo;
  if (sa != null && sb != null) {
    final int bySerial = sa.compareTo(sb);
    if (bySerial != 0) {
      return bySerial;
    }
  } else if (sa == null && sb != null) {
    return 1;
  } else if (sa != null && sb == null) {
    return -1;
  }
  return a.inputIndex.compareTo(b.inputIndex);
}

List<QuestionExtensionProblem> _sortedProblems(
  List<QuestionExtensionProblem> problems,
) {
  final List<QuestionExtensionProblem> sorted =
      List<QuestionExtensionProblem>.of(problems)
        ..sort((QuestionExtensionProblem a, QuestionExtensionProblem b) {
          final int byQuestion = a.questionId.compareTo(b.questionId);
          if (byQuestion != 0) {
            return byQuestion;
          }
          final int byKind = a.kind.index.compareTo(b.kind.index);
          if (byKind != 0) {
            return byKind;
          }
          final int byReason = a.reasonZh.compareTo(b.reasonZh);
          if (byReason != 0) {
            return byReason;
          }
          return _detailsKey(a.details).compareTo(_detailsKey(b.details));
        });
  final List<QuestionExtensionProblem> deduped = <QuestionExtensionProblem>[];
  QuestionExtensionProblem? last;
  for (final QuestionExtensionProblem problem in sorted) {
    if (last != null &&
        last.questionId == problem.questionId &&
        last.kind == problem.kind &&
        last.reasonZh == problem.reasonZh &&
        _detailsKey(last.details) == _detailsKey(problem.details)) {
      continue;
    }
    deduped.add(problem);
    last = problem;
  }
  return List<QuestionExtensionProblem>.unmodifiable(deduped);
}

String _detailsKey(Map<String, String> details) {
  final List<String> keys = details.keys.toList()..sort();
  return <String>[for (final String key in keys) '$key=${details[key]}']
      .join('&');
}

/// 环的展示顺序从字典序最小的 id 开始（同一环无论从哪里走都同一文案）。
List<String> _rotateCycleToSmallest(List<String> cycle) {
  int start = 0;
  for (int i = 1; i < cycle.length; i++) {
    if (cycle[i].compareTo(cycle[start]) < 0) {
      start = i;
    }
  }
  if (start == 0) {
    return List<String>.of(cycle);
  }
  return <String>[...cycle.sublist(start), ...cycle.sublist(0, start)];
}

String? _nonEmpty(String? raw) {
  if (raw == null) {
    return null;
  }
  final String trimmed = raw.trim();
  return trimmed.isEmpty ? null : trimmed;
}

int _firstInputIndex(List<_CleanRow> cleanRows, String questionId) {
  for (final _CleanRow row in cleanRows) {
    if (row.questionId == questionId) {
      return row.inputIndex;
    }
  }
  return -1;
}
