/// 一个 problem 的领域状态（Problem State Store 的最小内核）。
///
/// 这是《STUDENT-MODE-AND-AGENT-LOOP-DESIGN-2026-11-14》L1 缺口的领域模型落地
/// （`FURNACE-DESIGN-REFERENCE-2026-11-15.md` 的 L1-01）：让「到底要解决什么」
/// 跨轮稳定，而不是每轮重新框定。
///
/// 五条硬约束：
///
///  * 一个 [ProblemNode] 是根；task 只是它的视图，必须引用 [ProblemNode.id]
///    （见 [ProblemState.attachTask]），不能独立存在。
///  * 事实（[ProblemFact]）、假设（[ProblemAssumption]）、决策
///    （[ProblemDecision]）、未知（[ProblemUnknown]）**分栏存放**。把假设混进
///    事实层，等于把没核对过的东西当证据用；这道分隔由类型和存储结构保证，
///    不靠调用方自觉。
///  * 聚合只追加：[ProblemState] 的每次变更都写一条 [ProblemEvent]，
///    [ProblemState.version] 由事件数派生（事件数 + 1），所以版本只增不减；
///    [ProblemState.revoke] 只把节点标成 revoked，**不删任何历史**。
///  * 验收标准（[AcceptanceOracle]）和预算（[ProblemBudget]）挂在同一个聚合
///    上：没有 oracule 的「完成」只是声称完成，没有预算的「继续」不可停线。
///  * artifact 只存引用（[ArtifactRef]：path + hash + version），正文不抄进
///    状态——状态是索引，不是内容仓库。
///
/// 本文件是纯 Dart：不 import Flutter / drift / StudentRun / Checker，也不读
/// 时钟（时间戳全部由调用方给，测试可复现）。持久化接口在
/// `problem_state_store.dart`，目前只有内存实现；产品路径接线是另一件事。
library;

/// 问题节点当前处在哪个阶段。
///
/// [revoked] 是治理动作（撤销），[solved] 是完成；两者都是终态——终态之后
/// 不能再追加事实/假设/决策/未知，但**已有历史一条不删**。
enum ProblemStatus {
  draft('draft'),
  active('active'),
  paused('paused'),
  solved('solved'),
  revoked('revoked');

  const ProblemStatus(this.id);

  /// 落库/日志用的稳定值；中文标签不要写进这里。
  final String id;

  /// 终态：不再接受新的条目（历史只读）。
  bool get isTerminal => this == solved || this == revoked;

  static ProblemStatus fromId(String? id) => switch (id) {
        'active' => ProblemStatus.active,
        'paused' => ProblemStatus.paused,
        'solved' => ProblemStatus.solved,
        'revoked' => ProblemStatus.revoked,
        _ => ProblemStatus.draft,
      };
}

/// 一条事实的可信程度。
///
/// 与 [ProblemFact.source] 分开：source 回答「从哪来」，trust 回答「核对到
/// 哪一步」。没有来源的事实不允许构造。
enum FactTrust {
  /// 只有来源，还没有任何核对（题干原文、用户口述）。
  reported('reported'),

  /// 由其它事实推出来，推导链没有独立验证。
  inferred('inferred'),

  /// 被独立核对过（确定性 oracle / 工具输出 / 教师确认）。
  verified('verified'),

  /// 有反证或争议，不能当依据用。
  disputed('disputed');

  const FactTrust(this.id);

  final String id;

  static FactTrust fromId(String? id) => switch (id) {
        'inferred' => FactTrust.inferred,
        'verified' => FactTrust.verified,
        'disputed' => FactTrust.disputed,
        _ => FactTrust.reported,
      };
}

/// 假设当前是什么状态。
enum AssumptionStatus {
  open('open'),
  confirmed('confirmed'),
  refuted('refuted'),
  dropped('dropped');

  const AssumptionStatus(this.id);

  final String id;

  static AssumptionStatus fromId(String? id) => switch (id) {
        'confirmed' => AssumptionStatus.confirmed,
        'refuted' => AssumptionStatus.refuted,
        'dropped' => AssumptionStatus.dropped,
        _ => AssumptionStatus.open,
      };
}

/// 决策的审批状态。
///
/// `proposed` 是提出，`accepted` 是被批准（可以执行/作为结论），`rejected`
/// 是被否掉。审批结果由 [ProblemState.updateDecisionStatus] 写入并留下事件。
enum DecisionStatus {
  proposed('proposed'),
  accepted('accepted'),
  rejected('rejected');

  const DecisionStatus(this.id);

  final String id;

  static DecisionStatus fromId(String? id) => switch (id) {
        'accepted' => DecisionStatus.accepted,
        'rejected' => DecisionStatus.rejected,
        _ => DecisionStatus.proposed,
      };
}

/// 未知问题的状态。
enum UnknownStatus {
  open('open'),
  resolving('resolving'),
  resolved('resolved'),
  dropped('dropped');

  const UnknownStatus(this.id);

  final String id;

  static UnknownStatus fromId(String? id) => switch (id) {
        'resolving' => UnknownStatus.resolving,
        'resolved' => UnknownStatus.resolved,
        'dropped' => UnknownStatus.dropped,
        _ => UnknownStatus.open,
      };
}

/// 验收 oracle 的种类。
enum OracleKind {
  deterministic('deterministic'),
  rubric('rubric'),
  human('human'),
  model('model');

  const OracleKind(this.id);

  final String id;

  static OracleKind fromId(String? id) => switch (id) {
        'rubric' => OracleKind.rubric,
        'human' => OracleKind.human,
        'model' => OracleKind.model,
        _ => OracleKind.deterministic,
      };
}

/// 预算的消耗状态（由 [ProblemBudget.status] 派生）。
enum BudgetStatus {
  ok('ok'),

  /// 有任一维度达到 [ProblemBudget.warningRatio]，但还没用尽。
  warning('warning'),

  /// 有任一维度达到或超过上限。
  exhausted('exhausted');

  const BudgetStatus(this.id);

  final String id;
}

/// 一条事实：从来源直接读到、不需要再推导的陈述。
///
/// [source] 是引用（路径 / URL / trace seq / message id），[evidence] 是可回源
/// 的片段。构造时强制非空：没有来源的「事实」是假设，应该进
/// [ProblemAssumption]。
class ProblemFact {
  ProblemFact({
    required this.id,
    required this.text,
    required this.source,
    this.evidence,
    this.confidence = 1,
    this.trust = FactTrust.reported,
    required this.createdAt,
  }) {
    if (id.trim().isEmpty) {
      throw ArgumentError.value(id, 'id', 'fact id 不能为空');
    }
    if (text.trim().isEmpty) {
      throw ArgumentError.value(text, 'text', 'fact 内容不能为空');
    }
    if (source.trim().isEmpty) {
      throw ArgumentError.value(source, 'source', 'fact 必须有来源引用');
    }
    if (confidence < 0 || confidence > 1) {
      throw RangeError.range(confidence, 0, 1, 'confidence');
    }
  }

  final String id;

  /// 事实本身的陈述。
  final String text;

  /// 来源指针：路径 / URL / trace seq / message id。
  final String source;

  /// 可回源的片段；NULL = 只有整份来源。
  final String? evidence;

  /// 0..1；1 表示「来源直接给出」而不是模型猜的。
  final double confidence;

  final FactTrust trust;

  final int createdAt;

  Map<String, Object?> toJson() => {
        'id': id,
        'text': text,
        'source': source,
        'evidence': evidence,
        'confidence': confidence,
        'trust': trust.id,
        'created_at': createdAt,
      };

  static ProblemFact? fromJson(Object? json) {
    if (json is! Map) {
      return null;
    }
    final id = _string(json['id']);
    final text = _string(json['text']);
    final source = _string(json['source']);
    if (id == null ||
        id.isEmpty ||
        text == null ||
        text.isEmpty ||
        source == null ||
        source.isEmpty) {
      return null;
    }
    final rawConfidence = json['confidence'];
    final confidence = rawConfidence is num ? rawConfidence.toDouble() : 1.0;
    return ProblemFact(
      id: id,
      text: text,
      source: source,
      evidence: _string(json['evidence']),
      confidence: confidence.clamp(0.0, 1.0).toDouble(),
      trust: FactTrust.fromId(_string(json['trust'])),
      createdAt: _int(json['created_at']) ?? 0,
    );
  }

  @override
  String toString() => 'ProblemFact($id, ${trust.id}, source: $source)';
}

/// 一条显式假设：为了让推导成立而先接受、但还没被证实的前提。
///
/// 与 [ProblemFact] 分开存放是刻意的：假设可以被推翻，事实被推翻需要走撤销；
/// 混在一起会让「假设当事实」变成静默错误。
class ProblemAssumption {
  ProblemAssumption({
    required this.id,
    required this.statement,
    this.rationale,
    this.status = AssumptionStatus.open,
    required this.createdAt,
  }) {
    if (id.trim().isEmpty) {
      throw ArgumentError.value(id, 'id', 'assumption id 不能为空');
    }
    if (statement.trim().isEmpty) {
      throw ArgumentError.value(statement, 'statement', 'assumption 内容不能为空');
    }
  }

  final String id;

  /// 假设的内容，例如「忽略摩擦」。
  final String statement;

  /// 为什么先接受它（可回源的依据或「题目未提」这类理由）。
  final String? rationale;

  final AssumptionStatus status;

  final int createdAt;

  ProblemAssumption withStatus(AssumptionStatus status) => ProblemAssumption(
        id: id,
        statement: statement,
        rationale: rationale,
        status: status,
        createdAt: createdAt,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'statement': statement,
        'rationale': rationale,
        'status': status.id,
        'created_at': createdAt,
      };

  static ProblemAssumption? fromJson(Object? json) {
    if (json is! Map) {
      return null;
    }
    final id = _string(json['id']);
    final statement = _string(json['statement']);
    if (id == null || id.isEmpty || statement == null || statement.isEmpty) {
      return null;
    }
    return ProblemAssumption(
      id: id,
      statement: statement,
      rationale: _string(json['rationale']),
      status: AssumptionStatus.fromId(_string(json['status'])),
      createdAt: _int(json['created_at']) ?? 0,
    );
  }

  @override
  String toString() => 'ProblemAssumption($id, ${status.id})';
}

/// 一条决策：选了什么（[choice]）、为什么（[rationale]）、还考虑过什么
/// （[alternatives]）。
///
/// [status] 是审批状态；`accepted` 的决策才可以被当作结论引用。
class ProblemDecision {
  ProblemDecision({
    required this.id,
    required this.choice,
    required this.rationale,
    List<String> alternatives = const <String>[],
    this.status = DecisionStatus.proposed,
    required this.createdAt,
    this.decidedAt,
  }) : alternatives = List<String>.unmodifiable(alternatives) {
    if (id.trim().isEmpty) {
      throw ArgumentError.value(id, 'id', 'decision id 不能为空');
    }
    if (choice.trim().isEmpty) {
      throw ArgumentError.value(choice, 'choice', 'decision 必须写清选了什么');
    }
    if (rationale.trim().isEmpty) {
      throw ArgumentError.value(rationale, 'rationale', 'decision 必须给理由');
    }
  }

  final String id;

  /// 选定的方案。
  final String choice;

  /// 选择理由。
  final String rationale;

  /// 被放弃的备选方案（只写名字/一句话，不写正文）。
  final List<String> alternatives;

  final DecisionStatus status;

  final int createdAt;

  /// 审批落定的时间；`proposed` 时为 NULL。
  final int? decidedAt;

  bool get isAccepted => status == DecisionStatus.accepted;

  ProblemDecision withStatus(DecisionStatus status, {int? decidedAt}) =>
      ProblemDecision(
        id: id,
        choice: choice,
        rationale: rationale,
        alternatives: alternatives,
        status: status,
        createdAt: createdAt,
        decidedAt: status == DecisionStatus.proposed
            ? null
            : (decidedAt ?? this.decidedAt),
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'choice': choice,
        'rationale': rationale,
        'alternatives': alternatives,
        'status': status.id,
        'created_at': createdAt,
        'decided_at': decidedAt,
      };

  static ProblemDecision? fromJson(Object? json) {
    if (json is! Map) {
      return null;
    }
    final id = _string(json['id']);
    final choice = _string(json['choice']);
    final rationale = _string(json['rationale']);
    if (id == null ||
        id.isEmpty ||
        choice == null ||
        choice.isEmpty ||
        rationale == null ||
        rationale.isEmpty) {
      return null;
    }
    final rawAlternatives = json['alternatives'];
    final alternatives = <String>[
      if (rawAlternatives is List)
        for (final item in rawAlternatives)
          if (item is String) item,
    ];
    return ProblemDecision(
      id: id,
      choice: choice,
      rationale: rationale,
      alternatives: alternatives,
      status: DecisionStatus.fromId(_string(json['status'])),
      createdAt: _int(json['created_at']) ?? 0,
      decidedAt: _int(json['decided_at']),
    );
  }

  @override
  String toString() => 'ProblemDecision($id, ${status.id}, "$choice")';
}

/// 一条未知：还没解决的问题，以及它归谁（[owner]）。
///
/// 未知不是失败；它必须显式存在，否则 agent 会把「没想清楚」演成「已完成」。
class ProblemUnknown {
  ProblemUnknown({
    required this.id,
    required this.question,
    required this.owner,
    this.status = UnknownStatus.open,
    required this.createdAt,
    this.resolution,
    this.resolvedAt,
  }) {
    if (id.trim().isEmpty) {
      throw ArgumentError.value(id, 'id', 'unknown id 不能为空');
    }
    if (question.trim().isEmpty) {
      throw ArgumentError.value(question, 'question', 'unknown 必须写清问题');
    }
    if (owner.trim().isEmpty) {
      throw ArgumentError.value(owner, 'owner', 'unknown 必须指定 owner');
    }
  }

  final String id;

  /// 未决问题本身。
  final String question;

  /// 谁负责把它解决（solver / checker / user …）。
  final String owner;

  final UnknownStatus status;

  final int createdAt;

  /// 解决结论；未解决时为 NULL。
  final String? resolution;

  /// 解决时间；未解决时为 NULL。
  final int? resolvedAt;

  bool get isResolved => status == UnknownStatus.resolved;

  ProblemUnknown withResolution(String resolution, int resolvedAt) =>
      ProblemUnknown(
        id: id,
        question: question,
        owner: owner,
        status: UnknownStatus.resolved,
        createdAt: createdAt,
        resolution: resolution,
        resolvedAt: resolvedAt,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'question': question,
        'owner': owner,
        'status': status.id,
        'created_at': createdAt,
        'resolution': resolution,
        'resolved_at': resolvedAt,
      };

  static ProblemUnknown? fromJson(Object? json) {
    if (json is! Map) {
      return null;
    }
    final id = _string(json['id']);
    final question = _string(json['question']);
    final owner = _string(json['owner']);
    if (id == null ||
        id.isEmpty ||
        question == null ||
        question.isEmpty ||
        owner == null ||
        owner.isEmpty) {
      return null;
    }
    return ProblemUnknown(
      id: id,
      question: question,
      owner: owner,
      status: UnknownStatus.fromId(_string(json['status'])),
      createdAt: _int(json['created_at']) ?? 0,
      resolution: _string(json['resolution']),
      resolvedAt: _int(json['resolved_at']),
    );
  }

  @override
  String toString() => 'ProblemUnknown($id, ${status.id}, owner: $owner)';
}

/// 「怎么算做完了」的验收 oracle。
///
/// [kind] 说判定方式，[source] 是 oracle 的引用（rubric 文件 / 标准答案 /
/// 教师确认记录），[description] 是给人看的一句话。没有 oracle 的 problem
/// 只能算「还在做」，不能算「做完」。
class AcceptanceOracle {
  AcceptanceOracle({
    required this.kind,
    required this.source,
    required this.description,
  }) {
    if (source.trim().isEmpty) {
      throw ArgumentError.value(source, 'source', 'oracle 必须有来源引用');
    }
    if (description.trim().isEmpty) {
      throw ArgumentError.value(
        description,
        'description',
        'oracle 必须说明判定标准',
      );
    }
  }

  final OracleKind kind;

  /// oracle 的引用（路径 / hash / 人工确认记录 id）。
  final String source;

  /// 判定标准的人话描述。
  final String description;

  Map<String, Object?> toJson() => {
        'kind': kind.id,
        'source': source,
        'description': description,
      };

  static AcceptanceOracle? fromJson(Object? json) {
    if (json is! Map) {
      return null;
    }
    final source = _string(json['source']);
    final description = _string(json['description']);
    if (source == null ||
        source.isEmpty ||
        description == null ||
        description.isEmpty) {
      return null;
    }
    return AcceptanceOracle(
      kind: OracleKind.fromId(_string(json['kind'])),
      source: source,
      description: description,
    );
  }

  @override
  String toString() => 'AcceptanceOracle(${kind.id}, source: $source)';
}

/// 一个 problem 的预算与已用量。
///
/// 上限为 NULL = 该维度不设限（例如普通对话没有 reasoning 预算）。已用量允许
/// 超过上限：超了是**事实**，要能记录下来并让 [status] 变成
/// [BudgetStatus.exhausted]，而不是把数字夹回上限假装没超。
class ProblemBudget {
  const ProblemBudget({
    this.maxTokens,
    this.maxTimeMs,
    this.maxRounds,
    this.usedTokens = 0,
    this.usedTimeMs = 0,
    this.usedRounds = 0,
  })  : assert(maxTokens == null || maxTokens > 0, 'maxTokens 必须为正或 NULL'),
        assert(maxTimeMs == null || maxTimeMs > 0, 'maxTimeMs 必须为正或 NULL'),
        assert(maxRounds == null || maxRounds > 0, 'maxRounds 必须为正或 NULL'),
        assert(usedTokens >= 0),
        assert(usedTimeMs >= 0),
        assert(usedRounds >= 0);

  /// 任一维度用到这个比例就报 warning（设计里的 70~80% 预警带）。
  static const double warningRatio = 0.8;

  final int? maxTokens;
  final int? maxTimeMs;
  final int? maxRounds;

  final int usedTokens;
  final int usedTimeMs;
  final int usedRounds;

  bool get isConfigured =>
      maxTokens != null || maxTimeMs != null || maxRounds != null;

  bool get isExhausted =>
      _atOrOver(maxTokens, usedTokens) ||
      _atOrOver(maxTimeMs, usedTimeMs) ||
      _atOrOver(maxRounds, usedRounds);

  BudgetStatus get status {
    if (isExhausted) {
      return BudgetStatus.exhausted;
    }
    final ratios = <double>[
      if (maxTokens != null) usedTokens / maxTokens!,
      if (maxTimeMs != null) usedTimeMs / maxTimeMs!,
      if (maxRounds != null) usedRounds / maxRounds!,
    ];
    if (ratios.any((ratio) => ratio >= warningRatio)) {
      return BudgetStatus.warning;
    }
    return BudgetStatus.ok;
  }

  int? get remainingTokens =>
      maxTokens == null ? null : maxTokens! - usedTokens;

  int? get remainingTimeMs =>
      maxTimeMs == null ? null : maxTimeMs! - usedTimeMs;

  int? get remainingRounds =>
      maxRounds == null ? null : maxRounds! - usedRounds;

  /// 累加用量，返回新的预算（原对象不变）。
  ProblemBudget addUsage({int tokens = 0, int timeMs = 0, int rounds = 0}) {
    if (tokens < 0 || timeMs < 0 || rounds < 0) {
      throw ArgumentError('用量增量不能为负（tokens: $tokens, timeMs: $timeMs, '
          'rounds: $rounds）');
    }
    return ProblemBudget(
      maxTokens: maxTokens,
      maxTimeMs: maxTimeMs,
      maxRounds: maxRounds,
      usedTokens: usedTokens + tokens,
      usedTimeMs: usedTimeMs + timeMs,
      usedRounds: usedRounds + rounds,
    );
  }

  static bool _atOrOver(int? max, int used) => max != null && used >= max;

  Map<String, Object?> toJson() => {
        'max_tokens': maxTokens,
        'max_time_ms': maxTimeMs,
        'max_rounds': maxRounds,
        'used_tokens': usedTokens,
        'used_time_ms': usedTimeMs,
        'used_rounds': usedRounds,
      };

  static ProblemBudget? fromJson(Object? json) {
    if (json is! Map) {
      return null;
    }
    int? limit(String key) {
      final raw = json[key];
      return raw is int && raw > 0 ? raw : null;
    }

    int used(String key) {
      final raw = json[key];
      return raw is int && raw >= 0 ? raw : 0;
    }

    return ProblemBudget(
      maxTokens: limit('max_tokens'),
      maxTimeMs: limit('max_time_ms'),
      maxRounds: limit('max_rounds'),
      usedTokens: used('used_tokens'),
      usedTimeMs: used('used_time_ms'),
      usedRounds: used('used_rounds'),
    );
  }

  @override
  String toString() => 'ProblemBudget(tokens: $usedTokens/$maxTokens, '
      'timeMs: $usedTimeMs/$maxTimeMs, rounds: $usedRounds/$maxRounds)';
}

/// 一个 artifact 的引用：路径 + hash + 版本。
///
/// 只存引用不存正文（reference-first）。[hash] 为空字符串表示「还没算 hash」，
/// 这样的引用不能当内容证据用，但可以让调用方先登记。
class ArtifactRef {
  const ArtifactRef({
    required this.path,
    this.hash = '',
    this.version = 1,
  })  : assert(path != '', 'artifact path 不能为空'),
        assert(version > 0, 'artifact version 必须为正');

  final String path;

  /// 内容的快照 hash（sha256 或项目现有 FNV 方案）；'' = 未计算。
  final String hash;

  final int version;

  bool get isContentAddressed => hash.isNotEmpty;

  Map<String, Object?> toJson() => {
        'path': path,
        'hash': hash,
        'version': version,
      };

  static ArtifactRef? fromJson(Object? json) {
    if (json is! Map) {
      return null;
    }
    final path = _string(json['path']);
    if (path == null || path.isEmpty) {
      return null;
    }
    final version = _int(json['version']);
    return ArtifactRef(
      path: path,
      hash: _string(json['hash']) ?? '',
      version: version == null || version <= 0 ? 1 : version,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ArtifactRef &&
      other.path == path &&
      other.hash == hash &&
      other.version == version;

  @override
  int get hashCode => Object.hash(path, hash, version);

  @override
  String toString() => 'ArtifactRef($path@$version, hash: $hash)';
}

/// 一条挂在 problem 上的 task 引用。
///
/// task 不能独立存在：[problemId] 既不能在构造时为空，也不能与宿主节点的 id
/// 不一致（[ProblemState.attachTask] 会再查一次）。task 本体（标题/状态）属于
/// task 自己的领域，这里只存挂载关系和标题快照。
class ProblemTaskLink {
  ProblemTaskLink({
    required this.taskId,
    required this.problemId,
    this.title = '',
    required this.attachedAt,
  }) {
    if (taskId.trim().isEmpty) {
      throw ArgumentError.value(taskId, 'taskId', 'task id 不能为空');
    }
    if (problemId.trim().isEmpty) {
      throw ArgumentError.value(
        problemId,
        'problemId',
        'task 必须引用 problemId，不能独立存在',
      );
    }
  }

  final String taskId;

  /// task 挂靠的 problem；非空是硬约束。
  final String problemId;

  /// 挂载时的标题快照（task 本体不归 problem state 管）。
  final String title;

  final int attachedAt;

  Map<String, Object?> toJson() => {
        'task_id': taskId,
        'problem_id': problemId,
        'title': title,
        'attached_at': attachedAt,
      };

  static ProblemTaskLink? fromJson(Object? json) {
    if (json is! Map) {
      return null;
    }
    final taskId = _string(json['task_id']);
    final problemId = _string(json['problem_id']);
    if (taskId == null ||
        taskId.isEmpty ||
        problemId == null ||
        problemId.isEmpty) {
      return null;
    }
    return ProblemTaskLink(
      taskId: taskId,
      problemId: problemId,
      title: _string(json['title']) ?? '',
      attachedAt: _int(json['attached_at']) ?? 0,
    );
  }

  @override
  String toString() => 'ProblemTaskLink($taskId -> $problemId)';
}

/// 追加事件的历史。事件只增不删，[ProblemState.version] 从它派生。
class ProblemEvent {
  const ProblemEvent({
    required this.seq,
    required this.kind,
    required this.createdAt,
    this.refId,
    this.summary,
    this.payload = const <String, Object?>{},
  });

  /// 1 起的连续序号（= 写入后的 version - 1）。
  final int seq;

  final ProblemEventKind kind;

  final int createdAt;

  /// 受影响条目的 id（fact / decision / unknown / task …）。
  final String? refId;

  /// 一句人话，给日志和 UI 用；不放正文。
  final String? summary;

  /// 结构化载荷，必须是 JSON 可编码的原始值（toJson 之后的内容）。
  final Map<String, Object?> payload;

  Map<String, Object?> toJson() => {
        'seq': seq,
        'kind': kind.id,
        'created_at': createdAt,
        'ref_id': refId,
        'summary': summary,
        'payload': payload,
      };

  static ProblemEvent? fromJson(Object? json) {
    if (json is! Map) {
      return null;
    }
    final seq = _int(json['seq']);
    final kind = _string(json['kind']);
    if (seq == null || seq <= 0 || kind == null) {
      return null;
    }
    final rawPayload = json['payload'];
    final payload = rawPayload is Map
        ? <String, Object?>{
            for (final entry in rawPayload.entries)
              if (entry.key is String) entry.key as String: entry.value,
          }
        : const <String, Object?>{};
    return ProblemEvent(
      seq: seq,
      kind: ProblemEventKind.fromId(kind),
      createdAt: _int(json['created_at']) ?? 0,
      refId: _string(json['ref_id']),
      summary: _string(json['summary']),
      payload: payload,
    );
  }

  @override
  String toString() => 'ProblemEvent(#$seq, ${kind.id})';
}

/// 追加事件的种类。
enum ProblemEventKind {
  nodeUpdated('node_updated'),
  statusChanged('status_changed'),
  factAdded('fact_added'),
  assumptionAdded('assumption_added'),
  decisionAdded('decision_added'),
  decisionStatusChanged('decision_status_changed'),
  unknownAdded('unknown_added'),
  unknownResolved('unknown_resolved'),
  taskAttached('task_attached'),
  artifactAdded('artifact_added'),
  oracleSet('oracle_set'),
  budgetUpdated('budget_updated'),
  usageRecorded('usage_recorded'),
  revoked('revoked'),

  /// 外部追加的历史事件（不改变事实/假设/决策/未知分栏）。
  custom('custom');

  const ProblemEventKind(this.id);

  final String id;

  static ProblemEventKind fromId(String? id) => switch (id) {
        'node_updated' => ProblemEventKind.nodeUpdated,
        'status_changed' => ProblemEventKind.statusChanged,
        'fact_added' => ProblemEventKind.factAdded,
        'assumption_added' => ProblemEventKind.assumptionAdded,
        'decision_added' => ProblemEventKind.decisionAdded,
        'decision_status_changed' => ProblemEventKind.decisionStatusChanged,
        'unknown_added' => ProblemEventKind.unknownAdded,
        'unknown_resolved' => ProblemEventKind.unknownResolved,
        'task_attached' => ProblemEventKind.taskAttached,
        'artifact_added' => ProblemEventKind.artifactAdded,
        'oracle_set' => ProblemEventKind.oracleSet,
        'budget_updated' => ProblemEventKind.budgetUpdated,
        'usage_recorded' => ProblemEventKind.usageRecorded,
        'revoked' => ProblemEventKind.revoked,
        _ => ProblemEventKind.custom,
      };
}

/// 一个 problem 节点的根：它要解决什么，现在什么状态。
class ProblemNode {
  ProblemNode({
    required this.id,
    required this.title,
    required this.goal,
    this.status = ProblemStatus.draft,
    required this.created,
    required this.updated,
  }) {
    if (id.trim().isEmpty) {
      throw ArgumentError.value(id, 'id', 'problem id 不能为空');
    }
    if (title.trim().isEmpty) {
      throw ArgumentError.value(title, 'title', 'problem 必须有标题');
    }
    if (goal.trim().isEmpty) {
      throw ArgumentError.value(goal, 'goal', 'problem 必须写清目标');
    }
  }

  final String id;
  final String title;

  /// 根目标：这次到底要解决什么。任务只是它的视图。
  final String goal;

  final ProblemStatus status;

  final int created;

  /// 最后一次变更时间（每次追加事件都会更新）。
  final int updated;

  ProblemNode copyWith({
    String? title,
    String? goal,
    ProblemStatus? status,
    int? updated,
  }) =>
      ProblemNode(
        id: id,
        title: title ?? this.title,
        goal: goal ?? this.goal,
        status: status ?? this.status,
        created: created,
        updated: updated ?? this.updated,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'title': title,
        'goal': goal,
        'status': status.id,
        'created': created,
        'updated': updated,
      };

  static ProblemNode? fromJson(Object? json) {
    if (json is! Map) {
      return null;
    }
    final id = _string(json['id']);
    final title = _string(json['title']);
    final goal = _string(json['goal']);
    if (id == null ||
        id.isEmpty ||
        title == null ||
        title.isEmpty ||
        goal == null ||
        goal.isEmpty) {
      return null;
    }
    final created = _int(json['created']) ?? 0;
    return ProblemNode(
      id: id,
      title: title,
      goal: goal,
      status: ProblemStatus.fromId(_string(json['status'])),
      created: created,
      updated: _int(json['updated']) ?? created,
    );
  }

  @override
  String toString() => 'ProblemNode($id, ${status.id})';
}

/// 一个 problem 的聚合状态。
///
/// 结构上分栏：node / facts / assumptions / decisions / unknowns / tasks /
/// artifacts / oracle / budget，各自独立；**没有**一个混合的「entries」列表，
/// 所以「事实和假设混在一起」在类型层面就写不出来。
///
/// 变更只追加：每个 `addXxx` / `attachTask` / `recordUsage` 都会写一条
/// [ProblemEvent] 并推高 [version]；没有删除接口，[revoke] 也不删历史。
class ProblemState {
  /// 新建一个空状态；[ProblemNode] 自带的 created/updated 是唯一初始时间。
  ProblemState({required ProblemNode node})
      : _node = node,
        _facts = <ProblemFact>[],
        _assumptions = <ProblemAssumption>[],
        _decisions = <ProblemDecision>[],
        _unknowns = <ProblemUnknown>[],
        _tasks = <ProblemTaskLink>[],
        _artifacts = <ArtifactRef>[],
        _events = <ProblemEvent>[];

  ProblemState._({
    required ProblemNode node,
    required List<ProblemFact> facts,
    required List<ProblemAssumption> assumptions,
    required List<ProblemDecision> decisions,
    required List<ProblemUnknown> unknowns,
    required List<ProblemTaskLink> tasks,
    required List<ArtifactRef> artifacts,
    required List<ProblemEvent> events,
    AcceptanceOracle? oracle,
    ProblemBudget? budget,
  })  : _node = node,
        _facts = facts,
        _assumptions = assumptions,
        _decisions = decisions,
        _unknowns = unknowns,
        _tasks = tasks,
        _artifacts = artifacts,
        _events = events,
        _oracle = oracle,
        _budget = budget;

  ProblemNode _node;
  final List<ProblemFact> _facts;
  final List<ProblemAssumption> _assumptions;
  final List<ProblemDecision> _decisions;
  final List<ProblemUnknown> _unknowns;
  final List<ProblemTaskLink> _tasks;
  final List<ArtifactRef> _artifacts;
  final List<ProblemEvent> _events;
  AcceptanceOracle? _oracle;
  ProblemBudget? _budget;

  ProblemNode get node => _node;

  /// 事实（有来源、已核对/待核对），与 [assumptions] 严格分开。
  List<ProblemFact> get facts => List<ProblemFact>.unmodifiable(_facts);

  /// 假设（先接受、未证实），与 [facts] 严格分开。
  List<ProblemAssumption> get assumptions =>
      List<ProblemAssumption>.unmodifiable(_assumptions);

  List<ProblemDecision> get decisions =>
      List<ProblemDecision>.unmodifiable(_decisions);

  List<ProblemUnknown> get unknowns =>
      List<ProblemUnknown>.unmodifiable(_unknowns);

  List<ProblemTaskLink> get tasks => List<ProblemTaskLink>.unmodifiable(_tasks);

  List<ArtifactRef> get artifacts => List<ArtifactRef>.unmodifiable(_artifacts);

  /// 验收 oracle；NULL = 还没有判定「做完」的标准。
  AcceptanceOracle? get oracle => _oracle;

  ProblemBudget? get budget => _budget;

  /// 只追加的事件历史（按写入顺序，seq 从 1 开始连续）。
  List<ProblemEvent> get events => List<ProblemEvent>.unmodifiable(_events);

  /// 版本号 = 事件数 + 1。事件只追加，所以版本只增不减；revoke 也会推高它。
  int get version => _events.length + 1;

  bool get isRevoked => _node.status == ProblemStatus.revoked;

  /// 终态（solved/revoked）后不再接受新条目。
  bool get isMutable => !_node.status.isTerminal;

  /// 追加一条事实。id 在同一 problem 内唯一（重复是编程错误，直接报错）。
  ProblemFact addFact(ProblemFact fact, {int? nowMs}) {
    _ensureMutable('add fact ${fact.id}');
    if (_facts.any((existing) => existing.id == fact.id)) {
      throw StateError('problem ${_node.id} 已经有 fact ${fact.id}');
    }
    _facts.add(fact);
    _appendEvent(
      ProblemEventKind.factAdded,
      refId: fact.id,
      summary: fact.text,
      payload: <String, Object?>{'fact': fact.toJson()},
      nowMs: nowMs,
    );
    return fact;
  }

  /// 追加一条假设。假设进的是 assumptions 栏，不碰 facts。
  ProblemAssumption addAssumption(
    ProblemAssumption assumption, {
    int? nowMs,
  }) {
    _ensureMutable('add assumption ${assumption.id}');
    if (_assumptions.any((existing) => existing.id == assumption.id)) {
      throw StateError('problem ${_node.id} 已经有 assumption ${assumption.id}');
    }
    _assumptions.add(assumption);
    _appendEvent(
      ProblemEventKind.assumptionAdded,
      refId: assumption.id,
      summary: assumption.statement,
      payload: <String, Object?>{'assumption': assumption.toJson()},
      nowMs: nowMs,
    );
    return assumption;
  }

  /// 追加一条决策（初始审批状态由 [ProblemDecision.status] 决定）。
  ProblemDecision addDecision(ProblemDecision decision, {int? nowMs}) {
    _ensureMutable('add decision ${decision.id}');
    if (_decisions.any((existing) => existing.id == decision.id)) {
      throw StateError('problem ${_node.id} 已经有 decision ${decision.id}');
    }
    _decisions.add(decision);
    _appendEvent(
      ProblemEventKind.decisionAdded,
      refId: decision.id,
      summary: decision.choice,
      payload: <String, Object?>{'decision': decision.toJson()},
      nowMs: nowMs,
    );
    return decision;
  }

  /// 追加一条未知。
  ProblemUnknown addUnknown(ProblemUnknown unknown, {int? nowMs}) {
    _ensureMutable('add unknown ${unknown.id}');
    if (_unknowns.any((existing) => existing.id == unknown.id)) {
      throw StateError('problem ${_node.id} 已经有 unknown ${unknown.id}');
    }
    _unknowns.add(unknown);
    _appendEvent(
      ProblemEventKind.unknownAdded,
      refId: unknown.id,
      summary: unknown.question,
      payload: <String, Object?>{'unknown': unknown.toJson()},
      nowMs: nowMs,
    );
    return unknown;
  }

  /// 把一条 task 挂到本 problem 上。
  ///
  /// [problemId] 必须与本节点 id 一致——task 不能独立存在。同一个 taskId 重复
  /// 挂载是幂等的（返回已有链接，不追加事件）。
  ProblemTaskLink attachTask({
    required String taskId,
    required String problemId,
    String title = '',
    int? nowMs,
  }) {
    if (problemId.trim().isEmpty) {
      throw ArgumentError.value(
        problemId,
        'problemId',
        'task 必须引用 problemId，不能独立存在',
      );
    }
    if (problemId != _node.id) {
      throw ArgumentError.value(
        problemId,
        'problemId',
        'task 必须挂到 ${_node.id}，收到 $problemId',
      );
    }
    _ensureMutable('attach task $taskId');
    for (final existing in _tasks) {
      if (existing.taskId == taskId) {
        return existing;
      }
    }
    final link = ProblemTaskLink(
      taskId: taskId,
      problemId: problemId,
      title: title,
      attachedAt: nowMs ?? _node.updated,
    );
    _tasks.add(link);
    _appendEvent(
      ProblemEventKind.taskAttached,
      refId: taskId,
      summary: title,
      payload: <String, Object?>{'task': link.toJson()},
      nowMs: nowMs,
    );
    return link;
  }

  /// 登记一个 artifact 引用；完全相同的 (path, hash, version) 幂等。
  ArtifactRef addArtifact(ArtifactRef artifact, {int? nowMs}) {
    _ensureMutable('add artifact ${artifact.path}');
    if (_artifacts.contains(artifact)) {
      return artifact;
    }
    _artifacts.add(artifact);
    _appendEvent(
      ProblemEventKind.artifactAdded,
      refId: artifact.path,
      payload: <String, Object?>{'artifact': artifact.toJson()},
      nowMs: nowMs,
    );
    return artifact;
  }

  /// 设置/替换验收 oracle。旧值已经在上一条 oracleSet 事件的 payload 里。
  void setOracle(AcceptanceOracle oracle, {int? nowMs}) {
    _ensureMutable('set oracle');
    _oracle = oracle;
    _appendEvent(
      ProblemEventKind.oracleSet,
      summary: oracle.description,
      payload: <String, Object?>{'oracle': oracle.toJson()},
      nowMs: nowMs,
    );
  }

  /// 设置/替换预算（会记录一条 budgetUpdated 事件）。
  void setBudget(ProblemBudget budget, {int? nowMs}) {
    _ensureMutable('set budget');
    _budget = budget;
    _appendEvent(
      ProblemEventKind.budgetUpdated,
      payload: <String, Object?>{'budget': budget.toJson()},
      nowMs: nowMs,
    );
  }

  /// 累加预算用量；没设预算时报错（不要静默记账到空气里）。
  void recordUsage({
    int tokens = 0,
    int timeMs = 0,
    int rounds = 0,
    int? nowMs,
  }) {
    _ensureMutable('record usage');
    final current = _budget;
    if (current == null) {
      throw StateError('problem ${_node.id} 还没有预算，先 setBudget');
    }
    final next =
        current.addUsage(tokens: tokens, timeMs: timeMs, rounds: rounds);
    _budget = next;
    _appendEvent(
      ProblemEventKind.usageRecorded,
      summary: 'tokens+$tokens timeMs+$timeMs rounds+$rounds',
      payload: <String, Object?>{
        'tokens': tokens,
        'time_ms': timeMs,
        'rounds': rounds,
        'used_tokens': next.usedTokens,
        'used_time_ms': next.usedTimeMs,
        'used_rounds': next.usedRounds,
        'status': next.status.id,
      },
      nowMs: nowMs,
    );
  }

  /// 改变一条决策的审批状态，并留下 decisionStatusChanged 事件。
  ///
  /// 状态没变时幂等（不追加事件）。
  ProblemDecision updateDecisionStatus(
    String decisionId,
    DecisionStatus status, {
    String? note,
    int? nowMs,
  }) {
    _ensureMutable('update decision $decisionId');
    final index = _decisionIndex(decisionId);
    final current = _decisions[index];
    if (current.status == status) {
      return current;
    }
    final at = nowMs ?? _node.updated;
    final updated = current.withStatus(status, decidedAt: at);
    _decisions[index] = updated;
    _appendEvent(
      ProblemEventKind.decisionStatusChanged,
      refId: decisionId,
      summary: note ?? updated.status.id,
      payload: <String, Object?>{
        'status': updated.status.id,
        'note': note,
        'decided_at': updated.decidedAt,
      },
      nowMs: at,
    );
    return updated;
  }

  /// 把一条未知标记为已解决，并写入结论。
  ///
  /// 已经解决过的未知是幂等的（保留第一次结论，不追加事件）。
  ProblemUnknown markUnknownResolved(
    String unknownId, {
    String? resolution,
    int? nowMs,
  }) {
    _ensureMutable('resolve unknown $unknownId');
    final index = _unknownIndex(unknownId);
    final current = _unknowns[index];
    if (current.isResolved) {
      return current;
    }
    final at = nowMs ?? _node.updated;
    final updated = current.withResolution(resolution ?? '', at);
    _unknowns[index] = updated;
    _appendEvent(
      ProblemEventKind.unknownResolved,
      refId: unknownId,
      summary: updated.question,
      payload: <String, Object?>{'resolution': updated.resolution},
      nowMs: at,
    );
    return updated;
  }

  /// 改变节点状态（不含 revoke，revoke 走 [revoke]）。同状态幂等。
  void transitionTo(ProblemStatus status, {String? reason, int? nowMs}) {
    if (status == ProblemStatus.revoked) {
      revoke(reason: reason, nowMs: nowMs);
      return;
    }
    if (status == _node.status) {
      return;
    }
    _ensureMutable('change status');
    final at = nowMs ?? _node.updated;
    _node = _node.copyWith(status: status, updated: at);
    _appendEvent(
      ProblemEventKind.statusChanged,
      summary: reason,
      payload: <String, Object?>{'status': status.id},
      nowMs: at,
    );
  }

  /// 撤销这个 problem：状态置 revoked，**历史一条不删**。
  ///
  /// 已撤销时幂等（不追加事件）。撤销是治理动作，允许从 solved 过来；之后
  /// 任何 addXxx 都会被拒绝，但 facts / assumptions / decisions / unknowns /
  /// tasks / artifacts / events 原样保留，JSON 往返也保留。
  void revoke({String? reason, int? nowMs}) {
    if (isRevoked) {
      return;
    }
    final at = nowMs ?? _node.updated;
    _node = _node.copyWith(status: ProblemStatus.revoked, updated: at);
    _appendEvent(
      ProblemEventKind.revoked,
      summary: reason,
      payload: <String, Object?>{'reason': reason},
      nowMs: at,
    );
  }

  /// 追加一条**不改变条目分栏**的历史事件（store.append 用）。
  ///
  /// 条目本身的变更必须走对应的 addXxx，这样 payload 与分栏不会脱节。
  ProblemEvent recordEvent(
    ProblemEventKind kind, {
    String? refId,
    String? summary,
    Map<String, Object?> payload = const <String, Object?>{},
    int? nowMs,
  }) {
    _ensureMutable('append event ${kind.id}');
    return _appendEvent(
      kind,
      refId: refId,
      summary: summary,
      payload: payload,
      nowMs: nowMs,
    );
  }

  /// 深拷贝（走 JSON 往返；store 用它隔离内外引用）。
  ProblemState copy() {
    final restored = ProblemState.fromJson(toJson());
    if (restored == null) {
      throw StateError('problem ${_node.id} 的状态无法 JSON 往返');
    }
    return restored;
  }

  Map<String, Object?> toJson() => {
        'node': _node.toJson(),
        'facts': [for (final fact in _facts) fact.toJson()],
        'assumptions': [
          for (final assumption in _assumptions) assumption.toJson(),
        ],
        'decisions': [for (final decision in _decisions) decision.toJson()],
        'unknowns': [for (final unknown in _unknowns) unknown.toJson()],
        'tasks': [for (final task in _tasks) task.toJson()],
        'artifacts': [for (final artifact in _artifacts) artifact.toJson()],
        'oracle': _oracle?.toJson(),
        'budget': _budget?.toJson(),
        'events': [for (final event in _events) event.toJson()],
      };

  /// 从 JSON 恢复；坏数据返回 NULL，不猜、不静默修补。
  ///
  /// 事件 seq 必须是 1..n 连续：历史有洞说明数据已被篡改/截断，整份状态拒收。
  /// 版本不写进 JSON——它由事件数派生，避免出现两个互相矛盾的版本来源。
  static ProblemState? fromJson(Object? json) {
    if (json is! Map) {
      return null;
    }
    final node = ProblemNode.fromJson(json['node']);
    if (node == null) {
      return null;
    }
    final rawEvents = json['events'];
    if (rawEvents != null && rawEvents is! List) {
      return null;
    }
    final events = <ProblemEvent>[];
    if (rawEvents is List) {
      for (final raw in rawEvents) {
        final event = ProblemEvent.fromJson(raw);
        if (event == null || event.seq != events.length + 1) {
          return null;
        }
        events.add(event);
      }
    }
    return ProblemState._(
      node: node,
      facts: _parseList<ProblemFact>(json['facts'], ProblemFact.fromJson),
      assumptions: _parseList<ProblemAssumption>(
        json['assumptions'],
        ProblemAssumption.fromJson,
      ),
      decisions: _parseList<ProblemDecision>(
        json['decisions'],
        ProblemDecision.fromJson,
      ),
      unknowns: _parseList<ProblemUnknown>(
        json['unknowns'],
        ProblemUnknown.fromJson,
      ),
      tasks: _parseList<ProblemTaskLink>(
        json['tasks'],
        ProblemTaskLink.fromJson,
      ),
      artifacts: _parseList<ArtifactRef>(
        json['artifacts'],
        ArtifactRef.fromJson,
      ),
      events: events,
      oracle: AcceptanceOracle.fromJson(json['oracle']),
      budget: ProblemBudget.fromJson(json['budget']),
    );
  }

  static List<T> _parseList<T>(Object? raw, T? Function(Object?) parse) {
    if (raw is! List) {
      return <T>[];
    }
    final result = <T>[];
    for (final item in raw) {
      final value = parse(item);
      if (value != null) {
        result.add(value);
      }
    }
    return result;
  }

  int _decisionIndex(String decisionId) {
    final index =
        _decisions.indexWhere((decision) => decision.id == decisionId);
    if (index < 0) {
      throw StateError('problem ${_node.id} 没有 decision $decisionId');
    }
    return index;
  }

  int _unknownIndex(String unknownId) {
    final index = _unknowns.indexWhere((unknown) => unknown.id == unknownId);
    if (index < 0) {
      throw StateError('problem ${_node.id} 没有 unknown $unknownId');
    }
    return index;
  }

  void _ensureMutable(String action) {
    if (!isMutable) {
      throw StateError(
        'problem ${_node.id} 已是 ${_node.status.id}，不能再 $action；'
        '历史只追加不删除',
      );
    }
  }

  ProblemEvent _appendEvent(
    ProblemEventKind kind, {
    String? refId,
    String? summary,
    Map<String, Object?> payload = const <String, Object?>{},
    int? nowMs,
  }) {
    final at = nowMs ?? _node.updated;
    final event = ProblemEvent(
      seq: _events.length + 1,
      kind: kind,
      createdAt: at,
      refId: refId,
      summary: summary,
      payload: Map<String, Object?>.unmodifiable(payload),
    );
    _events.add(event);
    _node = _node.copyWith(updated: at);
    return event;
  }

  @override
  String toString() => 'ProblemState(${_node.id}, ${_node.status.id}, '
      'v$version, facts: ${_facts.length}, assumptions: ${_assumptions.length}, '
      'decisions: ${_decisions.length}, unknowns: ${_unknowns.length}, '
      'tasks: ${_tasks.length})';
}

String? _string(Object? value) => value is String ? value : null;

int? _int(Object? value) => value is int ? value : null;
