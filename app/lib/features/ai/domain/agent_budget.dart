/// 一次 agent 运行的预算（步数 / token / repair / 验证次数）与它为什么停下来。
///
/// 这是《STUDENT-MODE-AND-AGENT-LOOP-DESIGN-2026-11-14》§7.2 的 `RunBudget`：
/// 全局层只提供机制，具体数字属于 preset composition —— 学生模式是
/// 20k reasoning + 3k answer reserve，普通对话没有 reasoning 预算。
///
/// 为什么把 [StopReason] 放在这个文件：停止原因是预算判定（StepGuard）的产物，
/// 它和预算一起定义才有意义；`agent_run.dart` 只负责把选中的原因写进运行状态。
library;

/// 一次运行为什么停下来。
///
/// [id] 是写进 `agent_runs.stop_reason` 的稳定值，**不要本地化**；中文标签只给
/// 调试/日志用。NULL（没有这个枚举值）表示还在跑或正常结束。
enum StopReason {
  /// 步数预算用完。
  maxSteps('max_steps'),

  /// 同一个动作在窗口里重复太多次（相邻打转）。
  repeatedAction('repeated_action'),

  /// 动作序列出现周期（ABCABC），或过程审计发现循环。
  cycleDetected('cycle_detected'),

  /// 过程审计发现循环 / 无进展（`ProcessReport.loopDetected` / `stagnation`）。
  ///
  /// 与 [cycleDetected]（动作序列周期）分开：这一条来自**过程审计读 CoT** 的
  /// 信号，内容验证即使 pass 也不能直接定稿（设计文档 §7.4 / §8）。
  processLoop('process_loop'),

  /// 过程审计发现反复自我怀疑（`self_doubt` 标记，按次数或密度）。
  processSelfDoubt('process_self_doubt'),

  /// 状态指纹连续不变：做了动作但状态没有任何推进。
  noProgress('no_progress'),

  /// reasoning 预算达到阈值，必须转去写答案。
  reasoningBudget('reasoning_budget'),

  /// answer reserve 被吃掉了，再想下去就写不出答案。
  answerReserve('answer_reserve'),

  /// verifier 判 fail，repair 次数已经用尽。
  verifierFailed('verifier_failed'),

  /// Unknown to keep the stop-reason surface stable; verifier 调用次数用尽。
  verifierExhausted('verifier_exhausted'),

  /// repair 预算用尽。
  repairExhausted('repair_exhausted'),

  /// 验证器本身出错（不是答案错）。
  verifierError('verifier_error'),

  /// solve/parse 阶段就失败了。
  solveFailed('solve_failed'),

  /// 其它运行错误。
  error('error'),

  /// 用户取消。
  cancelled('cancelled');

  const StopReason(this.id);

  /// 落库/日志用的稳定值。
  final String id;

  /// 解析存储值；NULL / 未知值返回 NULL（不要猜一个原因）。
  static StopReason? fromId(String? id) {
    if (id == null) {
      return null;
    }
    for (final reason in StopReason.values) {
      if (reason.id == id) {
        return reason;
      }
    }
    return null;
  }
}

/// 一次运行的预算。
///
/// 两个预设的出厂值：
///
///  * [RunBudget.chat]：普通对话，没有 reasoning 预算、不做 repair/验证；
///  * [RunBudget.student]：学生模式，20k reasoning + 3k answer reserve，
///    最多 1 次 repair / 1 次 verifier（设计文档 §2.2/§4.2）。
///
/// 数字是「上限」不是「目标」：预算用完不等于运行失败，[StopReason] 会说清是
/// 哪一条触发。
class RunBudget {
  const RunBudget({
    required this.maxSteps,
    this.maxReasoningTokens,
    required this.maxCompletionTokens,
    this.answerReserveTokens = 0,
    this.maxRepair = 0,
    this.maxVerifierCalls = 0,
    this.repeatWindow = 4,
    this.stagnationLimit = 3,
    this.forceAnswerRatio = 0.7,
  })  : assert(maxSteps > 0, 'maxSteps 必须为正'),
        assert(maxReasoningTokens == null || maxReasoningTokens >= 0),
        assert(maxCompletionTokens >= 0),
        assert(answerReserveTokens >= 0),
        assert(maxRepair >= 0),
        assert(maxVerifierCalls >= 0),
        assert(repeatWindow >= 2),
        assert(stagnationLimit >= 2),
        assert(forceAnswerRatio > 0 && forceAnswerRatio <= 1);

  /// 普通对话：一轮里最多 [maxSteps] 次模型往返，没有 reasoning 预算概念。
  static const RunBudget chat = RunBudget(
    maxSteps: 12,
    maxCompletionTokens: 8192,
  );

  /// 学生模式：设计文档 §2.2「budget 20k reasoning + 3k answer reserve」。
  ///
  /// `maxCompletionTokens` = 20000 + 3000：reasoning 与答案共享同一个输出预算
  /// （DeepSeek 的 reasoning token 计入 completion），reserve 是**留给答案的**
  /// 那一部分，不是额外的一份。
  static const RunBudget student = RunBudget(
    maxSteps: 8,
    maxReasoningTokens: 20000,
    maxCompletionTokens: 23000,
    answerReserveTokens: 3000,
    maxRepair: 1,
    maxVerifierCalls: 1,
  );

  /// 最多多少步（模型往返 / 工具步）。
  final int maxSteps;

  /// reasoning token 预算；NULL = 不设 reasoning 预算（普通对话）。
  final int? maxReasoningTokens;

  /// completion token 预算（reasoning + 答案共用的输出上限）。
  final int maxCompletionTokens;

  /// 留给答案的 token 数：reasoning 吃掉之后必须还剩这么多才允许继续想。
  final int answerReserveTokens;

  /// 最多 repair 次数（学生 v1 = 1）。
  final int maxRepair;

  /// 最多 verifier 调用次数（学生 v1 = 1，repair 后可复用一次，总上限 2）。
  final int maxVerifierCalls;

  /// 多久窗口内重复同一个动作算「重复」。
  final int repeatWindow;

  /// 状态指纹连续不变多少步算「无进展」。
  final int stagnationLimit;

  /// reasoning 预算用到这个比例就必须转去写答案（设计文档 §7.2：70%）。
  final double forceAnswerRatio;

  /// 触发 forceAnswer 的 reasoning token 阈值；没有 reasoning 预算时返回 NULL。
  int? get forceAnswerAtReasoningTokens {
    final budget = maxReasoningTokens;
    if (budget == null || budget <= 0) {
      return null;
    }
    return (budget * forceAnswerRatio).floor();
  }

  /// 走完 [completionTokens] 之后还剩多少 completion 预算（可能为负）。
  int remainingCompletionTokens(int completionTokens) =>
      maxCompletionTokens - completionTokens;

  /// 剩下的 completion 预算是否已经不足以留出 answer reserve。
  bool isAnswerReserveAtRisk(int completionTokens) =>
      remainingCompletionTokens(completionTokens) < answerReserveTokens;

  RunBudget copyWith({
    int? maxSteps,
    int? maxReasoningTokens,
    int? maxCompletionTokens,
    int? answerReserveTokens,
    int? maxRepair,
    int? maxVerifierCalls,
    int? repeatWindow,
    int? stagnationLimit,
    double? forceAnswerRatio,
  }) {
    return RunBudget(
      maxSteps: maxSteps ?? this.maxSteps,
      maxReasoningTokens: maxReasoningTokens ?? this.maxReasoningTokens,
      maxCompletionTokens: maxCompletionTokens ?? this.maxCompletionTokens,
      answerReserveTokens: answerReserveTokens ?? this.answerReserveTokens,
      maxRepair: maxRepair ?? this.maxRepair,
      maxVerifierCalls: maxVerifierCalls ?? this.maxVerifierCalls,
      repeatWindow: repeatWindow ?? this.repeatWindow,
      stagnationLimit: stagnationLimit ?? this.stagnationLimit,
      forceAnswerRatio: forceAnswerRatio ?? this.forceAnswerRatio,
    );
  }

  @override
  String toString() => 'RunBudget(maxSteps: $maxSteps, '
      'maxReasoningTokens: $maxReasoningTokens, '
      'maxCompletionTokens: $maxCompletionTokens, '
      'answerReserveTokens: $answerReserveTokens, '
      'maxRepair: $maxRepair, maxVerifierCalls: $maxVerifierCalls)';
}
