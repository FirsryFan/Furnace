/// 一次 agent 运行的状态（`AgentRun`），以及运行里的每一步。
///
/// 这是《STUDENT-MODE-AND-AGENT-LOOP-DESIGN-2026-11-14》§7.1 的
/// `AgentRunState`：全局层所有 preset 共用的一种「这次跑到哪、花了多少、为什么
/// 停」的记录。它**不是**对话历史：对话正文在 `ai_messages`，运行记录是审计
/// 流水，两者的生命周期不同（删会话不该抹掉运行证据）。
///
/// 两条硬约束：
///
///  * 状态里**不放 raw CoT**。[reasoningChars] 只是长度，原文留在 trace 文件；
///    过程审计读的是 trace/内存里的 reasoning，不是这里的字段。
///  * 时间戳一律是 epoch ms（与项目里其它表同一个时钟），不是 `DateTime`——
///    域层不依赖存储格式，由 store 负责落库。
library;

import 'agent_budget.dart';

/// 让 `import 'agent_run.dart'` 的调用方也能拿到 [StopReason]（它定义在
/// `agent_budget.dart`，与预算判定放在一起；运行状态里要写它）。
export 'agent_budget.dart' show StopReason;

/// 这次运行属于哪种会话模式（设计文档 §5.1 `mode`）。
enum AgentMode {
  chat('chat'),
  student('student');

  const AgentMode(this.id);

  /// 落库用的稳定值。
  final String id;

  static AgentMode fromId(String? id) => switch (id) {
        'student' => AgentMode.student,
        _ => AgentMode.chat,
      };
}

/// 运行当前处在哪个阶段（设计文档 §5.1 `phase`、§8 状态机）。
enum AgentPhase {
  solve('solve'),
  answer('answer'),
  verify('verify'),
  repair('repair'),
  present('present');

  const AgentPhase(this.id);

  final String id;

  static AgentPhase fromId(String? id) => switch (id) {
        'answer' => AgentPhase.answer,
        'verify' => AgentPhase.verify,
        'repair' => AgentPhase.repair,
        'present' => AgentPhase.present,
        _ => AgentPhase.solve,
      };
}

/// 运行的终态（设计文档 §5.1 `status`）。
///
/// `running` 之外的四态是**互斥**的：`answered` 是拿到了答案并（可能）验证过，
/// `failed` 是没拿到可用答案，`stopped` 是被预算/循环/取消停下。不要把
/// `unknown` / `error` 的验证结论混进 `answered`——那会变成「静默 pass」。
enum AgentRunStatus {
  running('running'),
  answered('answered'),
  failed('failed'),
  stopped('stopped');

  const AgentRunStatus(this.id);

  final String id;

  static AgentRunStatus fromId(String? id) => switch (id) {
        'answered' => AgentRunStatus.answered,
        'failed' => AgentRunStatus.failed,
        'stopped' => AgentRunStatus.stopped,
        _ => AgentRunStatus.running,
      };
}

/// 一次运行的可变状态。
///
/// 字段与 `agent_runs` 一一对应（设计文档 §5.1 / §7.1）。步骤数、token、时间戳
/// 由调用方在每一步结束后用 [recordStep] / [addUsage] 累加；[phase] 用
/// [enterPhase] 推进；终态用 [finish] 落定。
class AgentRunState {
  AgentRunState({
    required this.id,
    required this.conversationId,
    required this.presetId,
    required this.mode,
    required this.startedAt,
    this.phase = AgentPhase.solve,
    this.status = AgentRunStatus.running,
    this.stopReason,
    this.steps = 0,
    this.promptTokens = 0,
    this.completionTokens = 0,
    this.reasoningTokens,
    this.reasoningChars = 0,
    this.elapsedMs,
    this.answerSheetJson,
    this.tracePath,
    this.verifierVerdict,
    this.processReportJson,
    this.endedAt,
  });

  /// 开一次运行。`startedAt` 由调用方给（域层不读时钟，测试可复现）。
  factory AgentRunState.start({
    required String id,
    required String conversationId,
    required String presetId,
    required AgentMode mode,
    required int startedAt,
  }) {
    return AgentRunState(
      id: id,
      conversationId: conversationId,
      presetId: presetId,
      mode: mode,
      startedAt: startedAt,
    );
  }

  final String id;
  final String conversationId;
  final String presetId;
  final AgentMode mode;
  final int startedAt;

  AgentPhase phase;
  AgentRunStatus status;
  StopReason? stopReason;
  int steps;
  int promptTokens;
  int completionTokens;

  /// provider 报告的 reasoning token；NULL = 没报（不是 0）。
  int? reasoningTokens;

  /// reasoning 的字符数（**不是**全文）。
  int reasoningChars;

  int? elapsedMs;

  /// 结构化答案卡 JSON（`StudentAnswerSheet.toJson()`），不放 raw CoT。
  String? answerSheetJson;

  String? tracePath;
  String? verifierVerdict;
  String? processReportJson;
  int? endedAt;

  bool get isRunning => status == AgentRunStatus.running;

  bool get isTerminal => !isRunning;

  /// 推进阶段。已经结束的运行不再推进（终态优先）。
  void enterPhase(AgentPhase next) {
    if (isTerminal) {
      return;
    }
    phase = next;
  }

  /// 记一步：步数 +1，并累加 token / reasoning 长度。
  ///
  /// [reasoningChars] 是这一步 reasoning 文本的长度，不是文本本身。
  void recordStep({
    int promptTokens = 0,
    int completionTokens = 0,
    int? reasoningTokens,
    int reasoningChars = 0,
  }) {
    steps += 1;
    addUsage(
      promptTokens: promptTokens,
      completionTokens: completionTokens,
      reasoningTokens: reasoningTokens,
      reasoningChars: reasoningChars,
    );
  }

  /// 只累加用量（不增加步数）：answer/verify 这类不占步的模型调用走这里。
  ///
  /// provider 没给 reasoning token 时不覆盖已有值——NULL 与 0 是两件事。
  void addUsage({
    int promptTokens = 0,
    int completionTokens = 0,
    int? reasoningTokens,
    int reasoningChars = 0,
  }) {
    this.promptTokens += promptTokens;
    this.completionTokens += completionTokens;
    if (reasoningTokens != null) {
      this.reasoningTokens = (this.reasoningTokens ?? 0) + reasoningTokens;
    }
    this.reasoningChars += reasoningChars;
  }

  /// 落定终态。
  ///
  /// [nowMs] 是调用方同一个时钟的当前时刻；给了就顺便记 [endedAt] 和
  /// [elapsedMs]（负数夹成 0，不编造负时长）。已经落定的运行不会二次覆盖——
  /// 重放/重复调用时第一条终态才是真的。
  void finish(
    AgentRunStatus status, {
    StopReason? stopReason,
    int? nowMs,
    int? elapsedMs,
  }) {
    if (isTerminal) {
      return;
    }
    this.status = status;
    this.stopReason = stopReason;
    if (nowMs != null) {
      endedAt = nowMs;
      final duration = nowMs - startedAt;
      this.elapsedMs = elapsedMs ?? (duration < 0 ? 0 : duration);
    } else {
      this.elapsedMs = elapsedMs;
    }
  }

  /// 已结束运行的真实时长；没有 endedAt 时返回 NULL。
  int? get durationMs {
    final end = endedAt;
    if (end == null) {
      return null;
    }
    final value = end - startedAt;
    return value < 0 ? 0 : value;
  }

  void attachAnswerSheet(String json) => answerSheetJson = json;

  void attachTrace(String? path) => tracePath = path;

  void attachVerifierVerdict(String? verdict) => verifierVerdict = verdict;

  void attachProcessReport(String? json) => processReportJson = json;

  @override
  String toString() => 'AgentRunState($id, ${mode.id}/$presetId, '
      'phase: ${phase.id}, status: ${status.id}, steps: $steps)';
}

/// 一步的种类（设计文档 §5.2 `kind`）。
enum AgentStepKind {
  model('model'),
  answer('answer'),
  verify('verify'),
  repair('repair'),
  persist('persist');

  const AgentStepKind(this.id);

  final String id;

  static AgentStepKind fromId(String? id) => switch (id) {
        'answer' => AgentStepKind.answer,
        'verify' => AgentStepKind.verify,
        'repair' => AgentStepKind.repair,
        'persist' => AgentStepKind.persist,
        _ => AgentStepKind.model,
      };
}

/// 一步的结果（设计文档 §5.2 `status`）。
enum AgentStepStatus {
  ok('ok'),
  failed('failed'),
  skipped('skipped');

  const AgentStepStatus(this.id);

  final String id;

  static AgentStepStatus fromId(String? id) => switch (id) {
        'failed' => AgentStepStatus.failed,
        'skipped' => AgentStepStatus.skipped,
        _ => AgentStepStatus.ok,
      };
}

/// 一条运行步骤（`agent_steps` 一行的领域形态）。
///
/// [summary] 只放一句人话（例如「模型返回答案卡」），**不放 raw CoT**；
/// [stateFingerprint] / [argsHash] / [claimHash] 是 StepGuard 与 ProcessAuditor
/// 判断「重复 / 周期 / 无进展」的锚点。
class AgentStep {
  const AgentStep({
    required this.id,
    required this.runId,
    required this.seq,
    required this.phase,
    required this.kind,
    required this.status,
    required this.createdAt,
    this.toolName,
    this.argsHash,
    this.stateFingerprint,
    this.claimHash,
    this.tokens,
    this.summary,
  });

  final String id;
  final String runId;
  final int seq;
  final AgentPhase phase;
  final AgentStepKind kind;
  final AgentStepStatus status;
  final int createdAt;
  final String? toolName;
  final String? argsHash;
  final String? stateFingerprint;
  final String? claimHash;
  final int? tokens;
  final String? summary;

  @override
  String toString() => 'AgentStep($runId#$seq, ${kind.id}/${status.id}, '
      'phase: ${phase.id})';
}
