/// 未验证交付契约（设计 §7.5 / §9）。
///
/// Checker 两轮仍不过（或无法判断）时，答案**仍然交付**，但必须明确标成未验证，
/// 并带上两样东西：
///
///  * [TeachingExtension]：题后批判性思维延伸——把 checker 发现的隐藏问题变成
///    学生能自己回答的问题，而不是直接给判词；
///  * [LearningRecord]：给 agent 设计方的学习资料（cluster / issue 类别 / 证据 /
///    架构提示 / provenance run），用于后续把确定性规则前移。
///
/// 这三者都是**确定性模板**从结构化 checker issue 生成，不是 LLM 总结（与
/// `checker_handoff.dart` 同一条约束）：[TeachingExtension.fromIssue] /
/// [LearningRecord.fromIssue] 是纯函数，模板按 issue 类别固定。
library;

import 'checker_report.dart';

/// 一次交付的验证状态。
enum DeliveryStatus {
  /// checker 通过：正常交付，**不生成**教学延伸。
  verified('verified'),

  /// checker 两轮不过：答案照常交付，但标未验证并附教学延伸 + 学习记录。
  unverified('unverified'),

  /// 系统无法判断（checker uncheckable / fail 但没有可关闭 issue）：交付并转人工。
  humanRequired('human_required');

  const DeliveryStatus(this.id);

  /// 落库/日志用的稳定值。
  final String id;

  /// 是否必须带教学延伸：只有 verified 不需要。
  bool get needsTeachingExtension => this != DeliveryStatus.verified;

  /// 宽松解析：未知值退化成 [humanRequired]，绝不冒充 verified。
  static DeliveryStatus fromId(String? id) => switch (id) {
        'verified' => DeliveryStatus.verified,
        'unverified' => DeliveryStatus.unverified,
        _ => DeliveryStatus.humanRequired,
      };
}

/// 题后批判性思维延伸。
///
/// [hiddenIssue] 说明 checker 实际发现、而答案本身没有暴露的问题；[userPrompts]
/// 是留给学生自己回答的问题（不是直接公布答案）；[expectedReasoning] 是学生
/// 应该能说出的推理要点。
class TeachingExtension {
  const TeachingExtension({
    required this.title,
    required this.hiddenIssue,
    required this.userPrompts,
    required this.expectedReasoning,
  });

  /// 从一条 checker issue 机械生成延伸（确定性模板，不调用模型）。
  factory TeachingExtension.fromIssue(CheckIssue issue) {
    return TeachingExtension(
      title: _titleFor(issue.category),
      hiddenIssue: '这道题已经做完了，但过程里有一个没有真正解决的问题：'
          '${issue.violated}（证据：${issue.evidence}；最小修复要求：'
          '${issue.minimalFix}）',
      userPrompts: _userPromptsFor(issue.category),
      expectedReasoning: '学生应能自己说出：${issue.minimalFix}；并指出原来的推理'
          '在哪一步失效。',
    );
  }

  /// 没有结构化 issue（例如 checker uncheckable）时的通用延伸。
  factory TeachingExtension.generic() {
    return const TeachingExtension(
      title: '题后延伸：这份答案没有被完全验证',
      hiddenIssue: 'Checker 无法完成过程审查，答案按未验证交付；过程里可能仍有未被发现的问题。',
      userPrompts: <String>[
        '你能指出自己解法里最不确定的一步吗？依据是什么？',
        '如果题目条件改一处，你的答案会先在哪里失效？',
      ],
      expectedReasoning: '学生应能定位自己推理中最薄弱的一步，并说明判断依据。',
    );
  }

  /// 延伸的小标题。
  final String title;

  /// 答案表面上没暴露、但 checker 发现的问题。
  final String hiddenIssue;

  /// 留给学生自己回答的问题（不直接给答案）。
  final List<String> userPrompts;

  /// 学生应该能说出的推理要点。
  final String expectedReasoning;

  Map<String, Object?> toJson() => {
        'title': title,
        'hidden_issue': hiddenIssue,
        'user_prompts': userPrompts,
        'expected_reasoning': expectedReasoning,
      };

  static String _titleFor(CheckIssueCategory category) => switch (category) {
        CheckIssueCategory.missingCase => '题后延伸：被漏掉的那一类情况',
        CheckIssueCategory.unjustifiedStep => '题后延伸：这一步凭什么成立',
        CheckIssueCategory.invalidAlgebra => '题后延伸：等价的边界',
        CheckIssueCategory.unit => '题后延伸：单位与量纲',
        CheckIssueCategory.conditionUnused => '题后延伸：没用上的条件',
        CheckIssueCategory.contradiction => '题后延伸：互相矛盾的两个结论',
        CheckIssueCategory.circular => '题后延伸：把结论当前提',
        CheckIssueCategory.undefinedSymbol => '题后延伸：符号的定义域',
        CheckIssueCategory.branchOverlap => '题后延伸：分支是否重叠',
        CheckIssueCategory.endpoint => '题后延伸：端点能不能取到',
        CheckIssueCategory.other => '题后延伸：解法最先失效的地方',
      };

  static List<String> _userPromptsFor(CheckIssueCategory category) =>
      switch (category) {
        CheckIssueCategory.missingCase => const <String>[
            '原解漏掉了哪一类情况？把完整的分支列出来。',
            '如果条件放宽/收紧，需要补上哪些分支？',
          ],
        CheckIssueCategory.unjustifiedStep => const <String>[
            '这一步凭什么成立？依据是题目条件、前一步结果还是某个定理？',
            '能举一个反例说明这一步不总是成立吗？',
          ],
        CheckIssueCategory.invalidAlgebra => const <String>[
            '这一步变形在什么条件下等价？把等价条件写出来。',
            '如果等价条件不满足，结论会变成什么？',
          ],
        CheckIssueCategory.unit => const <String>[
            '最终量的单位是什么？由哪些量组合得到？',
            '换一种单位表示，答案会怎么变？',
          ],
        CheckIssueCategory.conditionUnused => const <String>[
            '题目的哪条条件没有被用到？它真的可以删掉吗？',
            '如果删掉这条条件，答案会怎么变化？',
          ],
        CheckIssueCategory.contradiction => const <String>[
            '过程中哪两个结论互相矛盾？你更相信哪一个，依据是什么？',
            '矛盾的那一步从哪里开始分岔？',
          ],
        CheckIssueCategory.circular => const <String>[
            '这一步的结论是否已经在前面被当作前提用过？',
            '如果去掉这个前提，还能推出同样的结果吗？',
          ],
        CheckIssueCategory.undefinedSymbol => const <String>[
            '这个符号在题里有定义吗？它的取值范围是什么？',
            '符号定义变了，结论会跟着变吗？',
          ],
        CheckIssueCategory.branchOverlap => const <String>[
            '两个分支是否有重叠区域？重叠部分怎么处理？',
            '分支的枚举漏了哪些边界值？',
          ],
        CheckIssueCategory.endpoint => const <String>[
            '端点/边界值能不能取到？为什么？',
            '如果端点取不到，答案的区间应该怎么写？',
          ],
        CheckIssueCategory.other => const <String>[
            '如果题目条件改一处，你的解法哪一步会先失效？',
            '你能把答案每一步的依据各写一句话吗？',
          ],
      };
}

/// 给 agent 设计方的学习资料（不是给学生看的）。
///
/// 每条记录一次「checker 发现的未解决问题」的类别、证据、来源 run，以及一个
/// 按类别固定的架构提示（下一步该把哪类检查前移成确定性规则）。[architectureHint]
/// 是确定性模板 + 设计推断，不是已验证的架构结论。
class LearningRecord {
  const LearningRecord({
    required this.cluster,
    required this.issueCategory,
    required this.evidence,
    required this.architectureHint,
    required this.provenanceRunId,
  });

  /// 从一条 checker issue 生成学习记录（确定性模板）。
  factory LearningRecord.fromIssue({
    required String cluster,
    required CheckIssue issue,
    required String provenanceRunId,
    String? evidence,
  }) {
    return LearningRecord.fromCategory(
      cluster: cluster,
      issueCategory: issue.category,
      evidence: evidence ??
          '${issue.evidence}；违反：${issue.violated}；最小修复：'
              '${issue.minimalFix}',
      provenanceRunId: provenanceRunId,
    );
  }

  /// 从类别直接生成（没有具体 issue 时，例如 uncheckable）。
  factory LearningRecord.fromCategory({
    required String cluster,
    required CheckIssueCategory issueCategory,
    required String evidence,
    required String provenanceRunId,
  }) {
    if (cluster.trim().isEmpty) {
      throw ArgumentError.value(cluster, 'cluster', '学习记录必须带 cluster');
    }
    if (provenanceRunId.trim().isEmpty) {
      throw ArgumentError.value(
        provenanceRunId,
        'provenanceRunId',
        '学习记录必须带来源 run id',
      );
    }
    return LearningRecord(
      cluster: cluster,
      issueCategory: issueCategory,
      evidence: evidence,
      architectureHint: architectureHintFor(issueCategory),
      provenanceRunId: provenanceRunId,
    );
  }

  /// 经验簇（例如 `student_exam`），用于后续按簇聚合。
  final String cluster;

  /// checker issue 的类别（与 `checker_report.dart` 共用词表）。
  final CheckIssueCategory issueCategory;

  /// 具体证据：哪一步、违反了什么、最小修复要求。
  final String evidence;

  /// 架构提示：下一步应该把哪类检查前移成确定性规则。
  final String architectureHint;

  /// 来源 run id，保证学习资料可追溯。
  final String provenanceRunId;

  /// 按 issue 类别固定的架构提示（确定性模板 + 设计推断，不是已验证结论）。
  static String architectureHintFor(CheckIssueCategory category) =>
      switch (category) {
        CheckIssueCategory.missingCase =>
          '把分支枚举列为 required 锚点，由确定性 Precheck 直接判定漏支；'
              'Checker 的 missing_case 应保持 fatal，repair 只补分支。',
        CheckIssueCategory.unjustifiedStep =>
          '用确定性规则发现「无依据跳步」（§7.7：invalid 高精度，valid 不是'
              '认证），作为 Checker 的输入而不是自动通过依据。',
        CheckIssueCategory.invalidAlgebra =>
          '在 claim 层记录等式变形的前提，用符号/数值代入做等价性检查，'
              '不靠自然语言评语。',
        CheckIssueCategory.unit => '把单位/量纲检查放进确定性 Precheck（单位解析 + 量纲表），'
            '不要让 LLM 复核单位。',
        CheckIssueCategory.conditionUnused =>
          '为题目条件建立 ifUsed 锚点：claim 没有引用某条件就标记，'
              '而不是靠 checker 通读发现。',
        CheckIssueCategory.contradiction =>
          'ClaimLedger 对矛盾 claim 立即 refuted 并失效其下游，'
              '禁止被 refuted 的结论进入最终答案。',
        CheckIssueCategory.circular =>
          '用 ClaimKey + 依赖版本检测「把结论当前提」，命中即停（过程 blocker），'
              '不要继续重写。',
        CheckIssueCategory.undefinedSymbol =>
          '把符号定义与取值范围放进结构化 state；未定义符号在 Precheck 直接'
              ' invalid。',
        CheckIssueCategory.branchOverlap => '分支覆盖用集合/区间运算做确定性检查（重叠 + 漏支），'
            '不依赖 checker 的主观判断。',
        CheckIssueCategory.endpoint =>
          '把端点/边界条件做成 required 锚点，由 AnswerGate 直接判定能否取到。',
        CheckIssueCategory.other => '把这次 issue 的结构化字段（步骤、证据、最小修复）沉淀为新的确定性'
            ' Precheck 规则；同一类别重复出现时优先规则化。',
      };

  Map<String, Object?> toJson() => {
        'cluster': cluster,
        'issue_category': issueCategory.id,
        'evidence': evidence,
        'architecture_hint': architectureHint,
        'provenance_run_id': provenanceRunId,
      };
}

/// 未验证交付：checker 两轮不过 / 无法判断时交给用户的结果。
///
/// [status] 只有 [DeliveryStatus.unverified] 与 [DeliveryStatus.humanRequired]
/// 两种；verified 的正常交付不构造本对象（因此不会有教学延伸）。
class UnverifiedDelivery {
  const UnverifiedDelivery._({
    required this.status,
    required this.reason,
    required this.answer,
    required this.extension,
    required this.learningRecord,
  });

  /// checker 两轮不过：答案交付但标 unverified。
  factory UnverifiedDelivery.fromCheckerFailure({
    required String reason,
    required String answer,
    required TeachingExtension extension,
    required LearningRecord learningRecord,
  }) {
    _requireDeliverable(reason: reason, answer: answer);
    return UnverifiedDelivery._(
      status: DeliveryStatus.unverified,
      reason: reason,
      answer: answer,
      extension: extension,
      learningRecord: learningRecord,
    );
  }

  /// 系统无法判断：交付并转人工。
  factory UnverifiedDelivery.humanRequired({
    required String reason,
    required String answer,
    required TeachingExtension extension,
    required LearningRecord learningRecord,
  }) {
    _requireDeliverable(reason: reason, answer: answer);
    return UnverifiedDelivery._(
      status: DeliveryStatus.humanRequired,
      reason: reason,
      answer: answer,
      extension: extension,
      learningRecord: learningRecord,
    );
  }

  /// [DeliveryStatus.unverified] 或 [DeliveryStatus.humanRequired]。
  final DeliveryStatus status;

  /// 为什么是未验证交付（人可读，可进 UI/日志）。
  final String reason;

  /// 照常交付的答案（未验证，不是 pass）。
  final String answer;

  /// 题后批判性思维延伸。
  final TeachingExtension extension;

  /// 给 agent 设计方的学习记录。
  final LearningRecord learningRecord;

  /// 未验证交付永远不是 verified。
  bool get isVerified => false;

  Map<String, Object?> toJson() => {
        'status': status.id,
        'reason': reason,
        'answer': answer,
        'extension': extension.toJson(),
        'learning_record': learningRecord.toJson(),
      };

  static void _requireDeliverable({
    required String reason,
    required String answer,
  }) {
    if (reason.trim().isEmpty) {
      throw ArgumentError.value(reason, 'reason', '未验证交付必须说明原因');
    }
    if (answer.trim().isEmpty) {
      throw ArgumentError.value(answer, 'answer', '未验证交付必须带答案');
    }
  }
}
