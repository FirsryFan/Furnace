/// 跨学科「能力动作」（thinking move）词表——推理层的第一块基石。
///
/// 这张词表要回答的问题是：**学生卡住的时候，卡住的是哪一个动作？**
///
/// 为什么是跨学科的：数学 / 物理 / 化学 / 生物 / 语文 / 历史 / 信息学竞赛 /
/// 强基 的题目长得完全不一样，但解题时调用的「动作」高度重合——识别不变量、
/// 分类讨论、反证、极端化、量纲检验……这正是本文件存在的理由：在 OI / 强基
/// 题上训练出的动作能力，应该能迁移到高考题上；如果每个学科各写一套互不相干
/// 的动作名，迁移就成了口号而不是数据。
///
/// 三条设计约束：
/// * [key] 是**稳定标识**，snake_case，永远不本地化、不翻译、不改名——它会
///   被写进数据库并被统计，改一次等于让历史数据失去意义。中文只出现在
///   [labelZh] / [descriptionZh] 里。
/// * [subjectHints] 是「这个动作在哪些学科轨道上真的会出现」的判断，不是测量。
///   它决定 [transferable]，而 [transferable] 决定 [catalog] 的排序。
/// * 词表只描述**动作**，不描述知识点、不描述题型。「这题考三角恒等变换」是
///   知识点；「这一步在化归」才是能力动作。
library;

/// 一个跨学科的能力动作。
///
/// 实例全部是编译期常量（见 [CapabilityAction.catalog]），因此比较引用是安全
/// 的；但业务代码应当用 [key] 比较，因为 key 是写入数据库的那个值。
class CapabilityAction {
  const CapabilityAction({
    required this.key,
    required this.labelZh,
    required this.labelEn,
    required this.descriptionZh,
    required this.subjectHints,
    required this.transferable,
    required this.sortOrder,
  });

  /// 稳定标识，snake_case，永不本地化。数据库里存的就是它。
  final String key;

  /// 中文展示名，例如「不变量识别」。
  final String labelZh;

  /// 英文展示名，例如 `Invariant recognition`。仅用于排版/导出，不参与判断。
  final String labelEn;

  /// 一句话说清「学生做这个动作时在干什么」。给模型看的提示词也用它。
  final String descriptionZh;

  /// 该动作会出现的学科轨道，取值必须来自 [subjectKeys]。
  ///
  /// 这是判断题：宁可少写一个学科，也不要为了好看凑数——[transferable] 与
  /// 排序都由它推出，凑数会直接把「迁移性」这个信号稀释掉。
  final List<String> subjectHints;

  /// 是否跨学科可迁移。
  ///
  /// 判据（而不是感觉）：`subjectHints.length >= transferableSubjectThreshold`，
  /// 即该动作至少在 [transferableSubjectThreshold] 条学科轨道上出现。
  /// `capability_action_test.dart` 会强制这个等式，禁止手写一个与
  /// [subjectHints] 矛盾的布尔值。
  final bool transferable;

  /// 展示/入库顺序，0 起连续递增，等于它在 [catalog] 中的下标。
  final int sortOrder;

  /// 允许出现在 [subjectHints] 里的学科轨道键（稳定、snake_case）。
  ///
  /// 八个轨道对应产品要覆盖的八类材料；[subjectLabelsZh] 给出中文名。
  static const List<String> subjectKeys = <String>[
    'math',
    'physics',
    'chemistry',
    'biology',
    'chinese',
    'history',
    'informatics',
    'qiangji',
  ];

  /// 学科轨道的中文名，用于提示词与界面。
  static const Map<String, String> subjectLabelsZh = <String, String>{
    'math': '数学',
    'physics': '物理',
    'chemistry': '化学',
    'biology': '生物',
    'chinese': '语文',
    'history': '历史',
    'informatics': '信息学竞赛',
    'qiangji': '强基计划',
  };

  /// [transferable] 的判据阈值：至少出现在 4 条学科轨道上才算可迁移。
  ///
  /// 4 而不是 3：八轨道里跨过一半才算「跨学科」；取 3 会让只覆盖数学/信息学/
  /// 强基（这三者共享同一批竞赛技巧）的动作也被标成可迁移，而那恰恰是我们要
  /// 和真正跨学科的动作区分开的情况。
  static const int transferableSubjectThreshold = 4;

  /// 排序后的完整词表：**迁移性强的在前**。
  ///
  /// 排序规则（有测试守着，不是人工美感）：
  /// 1. [transferable] 为 true 的排前面；
  /// 2. 组内按 `subjectHints.length` 从多到少；
  /// 3. 数量相同时按本文件里的书写顺序（也就是 [sortOrder]）。
  ///
  /// 词表是**开放的**：加一个动作只需要在这里追加一行并分配 [sortOrder]，
  /// 已有的 key 不得改动或删除（历史数据已经在用）。
  static const List<CapabilityAction> catalog = <CapabilityAction>[
    CapabilityAction(
      key: 'first_principles',
      labelZh: '从定义出发',
      labelEn: 'Work from definitions',
      descriptionZh: '回到概念或量的定义（是什么、怎么算），把题目翻译成定义式再往下推，而不是套结论。',
      subjectHints: <String>[
        'math',
        'physics',
        'chemistry',
        'biology',
        'chinese',
        'history',
        'informatics',
        'qiangji',
      ],
      transferable: true,
      sortOrder: 0,
    ),
    CapabilityAction(
      key: 'analogy_transfer',
      labelZh: '类比迁移',
      labelEn: 'Analogy transfer',
      descriptionZh: '找到结构与当前问题相同的已知问题或模型，把已知的解法、结论迁移过来，并检验可迁移的前提是否成立。',
      subjectHints: <String>[
        'math',
        'physics',
        'chemistry',
        'biology',
        'chinese',
        'history',
        'informatics',
      ],
      transferable: true,
      sortOrder: 1,
    ),
    CapabilityAction(
      key: 'induction',
      labelZh: '归纳',
      labelEn: 'Induction',
      descriptionZh: '从若干特例或现象中找出普遍规律，或用归纳法（含数学归纳、递推）证明规律对一切情形成立。',
      subjectHints: <String>[
        'math',
        'physics',
        'chemistry',
        'biology',
        'chinese',
        'history',
        'informatics',
      ],
      transferable: true,
      sortOrder: 2,
    ),
    CapabilityAction(
      key: 'case_split',
      labelZh: '分类讨论',
      labelEn: 'Case split',
      descriptionZh: '按互斥且完备的标准把情形分成若干类，逐类解决后合并，特别注意边界归属与重复计数。',
      subjectHints: <String>[
        'math',
        'physics',
        'chemistry',
        'biology',
        'history',
        'informatics',
        'qiangji',
      ],
      transferable: true,
      sortOrder: 3,
    ),
    CapabilityAction(
      key: 'sanity_check',
      labelZh: '回代检验',
      labelEn: 'Sanity check and back-substitution',
      descriptionZh: '把结论代回原条件、代入特殊值或与常识比较，确认没有算错、没有漏条件、没有答非所问。',
      subjectHints: <String>[
        'math',
        'physics',
        'chemistry',
        'biology',
        'informatics',
        'qiangji',
      ],
      transferable: true,
      sortOrder: 4,
    ),
    CapabilityAction(
      key: 'invariant_recognition',
      labelZh: '不变量识别',
      labelEn: 'Invariant recognition',
      descriptionZh: '在变化过程中找出保持不变的量、结构或性质，用它把复杂的动态过程压成一句话。',
      subjectHints: <String>[
        'math',
        'physics',
        'chemistry',
        'biology',
        'informatics',
        'qiangji',
      ],
      transferable: true,
      sortOrder: 5,
    ),
    CapabilityAction(
      key: 'reduction',
      labelZh: '化归',
      labelEn: 'Reduction',
      descriptionZh: '把陌生问题转化为已解决的等价问题（换元、变形、找同构），而不是对着原式硬算。',
      subjectHints: <String>[
        'math',
        'physics',
        'chemistry',
        'biology',
        'informatics',
        'qiangji',
      ],
      transferable: true,
      sortOrder: 6,
    ),
    CapabilityAction(
      key: 'extreme_case',
      labelZh: '极端化/边界检验',
      labelEn: 'Extreme and boundary cases',
      descriptionZh: '令变量取极端值或边界值（0、无穷、相等、退化），看结论是否成立，用来快速证伪或锁定正确形式。',
      subjectHints: <String>[
        'math',
        'physics',
        'chemistry',
        'biology',
        'informatics',
        'qiangji',
      ],
      transferable: true,
      sortOrder: 7,
    ),
    CapabilityAction(
      key: 'state_tracking',
      labelZh: '状态追踪',
      labelEn: 'State tracking',
      descriptionZh: '明确每一步的状态由哪些变量描述、状态如何转移，按时间或操作顺序推演，不漏掉已经发生的状态。',
      subjectHints: <String>[
        'math',
        'physics',
        'chemistry',
        'biology',
        'informatics',
        'qiangji',
      ],
      transferable: true,
      sortOrder: 8,
    ),
    CapabilityAction(
      key: 'monotonicity',
      labelZh: '单调性',
      labelEn: 'Monotonicity',
      descriptionZh: '判断一个量随参数是增是减（或先增后减），借单调性比较大小、证明唯一性、估计取值范围。',
      subjectHints: <String>[
        'math',
        'physics',
        'chemistry',
        'biology',
        'informatics',
        'qiangji',
      ],
      transferable: true,
      sortOrder: 9,
    ),
    CapabilityAction(
      key: 'symmetry',
      labelZh: '对称性',
      labelEn: 'Symmetry',
      descriptionZh: '利用图形的对称、变量的轮换对称或问题的对偶性，只算一半、减少变量，或直接得到相等关系。',
      subjectHints: <String>[
        'math',
        'physics',
        'chemistry',
        'biology',
        'informatics',
      ],
      transferable: true,
      sortOrder: 10,
    ),
    CapabilityAction(
      key: 'proof_by_contradiction',
      labelZh: '反证',
      labelEn: 'Proof by contradiction',
      descriptionZh: '先假设结论不成立，推出与已知条件、定义或常识矛盾，从而否定这个假设。',
      subjectHints: <String>[
        'math',
        'physics',
        'chinese',
        'informatics',
        'qiangji',
      ],
      transferable: true,
      sortOrder: 11,
    ),
    CapabilityAction(
      key: 'counterexample_construction',
      labelZh: '构造反例',
      labelEn: 'Construct a counterexample',
      descriptionZh: '对一个看似成立的命题，构造满足前提但结论不成立的具体例子，用来证伪或找出命题缺失的条件。',
      subjectHints: <String>[
        'math',
        'physics',
        'chinese',
        'informatics',
        'qiangji',
      ],
      transferable: true,
      sortOrder: 12,
    ),
    CapabilityAction(
      key: 'conservation_law',
      labelZh: '守恒量',
      labelEn: 'Conservation law',
      descriptionZh: '写出过程中的守恒关系（能量、质量、电量、物质的量、动量等），用守恒跳过中间细节。',
      subjectHints: <String>[
        'math',
        'physics',
        'chemistry',
        'biology',
        'informatics',
      ],
      transferable: true,
      sortOrder: 13,
    ),
    CapabilityAction(
      key: 'invariant_decomposition',
      labelZh: '分解与不变量',
      labelEn: 'Decomposition and invariants',
      descriptionZh: '把大对象拆成互不影响的小块分别处理，并维护拆分后仍然成立的不变量（如每块的和、最大最小值）。',
      subjectHints: <String>[
        'math',
        'physics',
        'chemistry',
        'biology',
        'informatics',
      ],
      transferable: true,
      sortOrder: 14,
    ),
    CapabilityAction(
      key: 'dimensional_check',
      labelZh: '量纲/量级检验',
      labelEn: 'Dimensional and order-of-magnitude check',
      descriptionZh: '检查等式两边的单位与数量级是否一致，用估算快速判断一个公式是否可能正确。',
      subjectHints: <String>['math', 'physics', 'chemistry', 'biology'],
      transferable: true,
      sortOrder: 15,
    ),
    CapabilityAction(
      key: 'constructive_upper_bound',
      labelZh: '构造与放缩',
      labelEn: 'Construction and bounding',
      descriptionZh: '通过构造满足条件的对象给出上界，或把表达式放大/缩小成可求和、可比较的形式，夹出目标值。',
      subjectHints: <String>['math', 'physics', 'informatics', 'qiangji'],
      transferable: true,
      sortOrder: 16,
    ),
    CapabilityAction(
      key: 'graph_modeling',
      labelZh: '建模成图',
      labelEn: 'Modeling as a graph',
      descriptionZh: '把对象之间的关系抽成点与边（或状态与转移），再套用连通性、路径、匹配等已有结论。',
      subjectHints: <String>['math', 'chemistry', 'biology', 'informatics'],
      transferable: true,
      sortOrder: 17,
    ),
    CapabilityAction(
      key: 'information_bound',
      labelZh: '信息/下界论证',
      labelEn: 'Information-theoretic lower bound',
      descriptionZh: '数一数「一共有多少种可能、需要多少信息」，用计数或熵给出任何算法都突破不了的下界。',
      subjectHints: <String>['math', 'informatics', 'qiangji'],
      transferable: false,
      sortOrder: 18,
    ),
    CapabilityAction(
      key: 'amortized_argument',
      labelZh: '摊还/均摊',
      labelEn: 'Amortized argument',
      descriptionZh: '不看单次操作的最坏情况，而是把总代价摊到整体（均摊法、势能法），证明整体复杂度可接受。',
      subjectHints: <String>['math', 'informatics'],
      transferable: false,
      sortOrder: 19,
    ),
  ];

  /// 词表里的全部 key，按 [catalog] 顺序。写提示词、做校验、入库枚举都用它。
  static List<String> get keys =>
      <String>[for (final action in catalog) action.key];

  static final Map<String, CapabilityAction> _byKey =
      <String, CapabilityAction>{
    for (final action in catalog) action.key: action,
  };

  /// 按 key 查动作；未知 key 返回 `null`，**永不抛异常**。
  ///
  /// 不抛异常是刻意的：模型返回的 actionType 属于外部输入，未知值应该变成
  /// `knownAction == false` 的数据（见 `reasoning_prompt.dart`），而不是让整条
  /// 思维链解析失败。前后空白会被忽略；大小写不忽略——错大小写就是未知 key，
  /// 因为我们不想悄悄把 `Invariant_Recognition` 归一化成合法值。
  static CapabilityAction? byKey(String key) => _byKey[key.trim()];

  /// 该动作是否在词表里（等价于 `byKey(key) != null`）。
  static bool isKnownKey(String key) => byKey(key) != null;

  /// 序列化。字段名与数据库列名保持一一对应，避免中间层再翻译一次。
  Map<String, Object?> toJson() => <String, Object?>{
        'key': key,
        'labelZh': labelZh,
        'labelEn': labelEn,
        'descriptionZh': descriptionZh,
        'subjectHints': subjectHints,
        'transferable': transferable,
        'sortOrder': sortOrder,
      };

  /// [toJson] 的别名，方便在集合里直接 `.map((a) => a.json)`。
  Map<String, Object?> get json => toJson();

  @override
  String toString() => 'CapabilityAction($key)';
}
