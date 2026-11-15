/// 题目锚点（Anchor）与检查点（Checkpoint）的领域模型。
///
/// 设计原则：不限制解法；题目决定的关键量/关系/点/临界/定义域是方法无关的
/// 必要条件。答案或过程一旦涉及这些锚点，就必须满足约束；没有涉及则不误杀。
///
/// 这里只定义数据；执行由 `DeterministicAnswerGate`（AnswerGate）和未来的
/// Checker Agent 分别消费 required 与 conditional 锚点。
library;

/// 锚点类型。
enum CheckpointKind {
  quantity('quantity'),
  relation('relation'),
  point('point'),
  critical('critical'),
  domain('domain'),
  evidence('evidence');

  const CheckpointKind(this.id);
  final String id;
}

/// 锚点的检查范围。
enum CheckpointScope {
  /// 任何合法解法都必须满足/声明（最终答案、定义域、临界排除、端点）。
  required('required'),

  /// 解里提到该锚点就必须对；没提到不罚。
  ifReferenced('if_referenced'),

  /// 把它当前提使用就必须对；只出现名字不算。
  ifUsed('if_used');

  const CheckpointScope(this.id);
  final String id;
}

/// 约束类型。当前 AnswerGate 只执行可确定性检查的类型。
enum CheckpointConstraintKind {
  numeric('numeric'),
  symbolic('symbolic'),
  interval('interval'),
  exclusion('exclusion'),
  domain('domain'),
  textEvidence('text_evidence');

  const CheckpointConstraintKind(this.id);
  final String id;
}

/// 一条锚点约束。
class CheckpointConstraint {
  const CheckpointConstraint({
    required this.kind,
    required this.acceptable,
    this.alternatives = const <String>[],
    this.tolerance,
    this.description = '',
  });

  final CheckpointConstraintKind kind;

  /// 归一化后必须出现的可接受片段；命中任意一个即可。
  final List<String> acceptable;

  /// 其他可接受的写法/等价表达；与 [acceptable] 取并集。
  final List<String> alternatives;

  /// numeric 约束可用的容差；null 表示精确文本/符号检查。
  final double? tolerance;

  final String description;

  bool get isCheckable => acceptable.isNotEmpty || alternatives.isNotEmpty;
}

/// 一个题目锚点。
class Checkpoint {
  const Checkpoint({
    required this.id,
    required this.label,
    required this.kind,
    required this.scope,
    required this.constraints,
  });

  final String id;
  final String label;
  final CheckpointKind kind;
  final CheckpointScope scope;
  final List<CheckpointConstraint> constraints;

  bool get isRequired => scope == CheckpointScope.required;
}

/// 一组锚点（通常来自题目/解析的 rubric）。
class CheckpointSet {
  const CheckpointSet({required this.checkpoints});

  final List<Checkpoint> checkpoints;

  Iterable<Checkpoint> get required =>
      checkpoints.where((checkpoint) => checkpoint.isRequired);

  Iterable<Checkpoint> get conditional => checkpoints.where(
        (checkpoint) => checkpoint.scope != CheckpointScope.required,
      );
}
