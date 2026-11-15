/// 全局 StepGuard：在每一步之后判断「继续 / 强制交卷 / 停止 / 允许一次 repair」。
///
/// 这是《STUDENT-MODE-AND-AGENT-LOOP-DESIGN-2026-11-14》§7.2 的机制。它只提供
/// 判定，不执行动作：调用方（学生 Run 状态机 / 主 AgentLoop）拿到
/// [StepGuardDecision] 后自己决定是继续模型调用、转去写答案，还是落终态。
///
/// 为什么需要它（设计文档 §1.2）：单步的 `tool + args` hash 只能抓相邻重复；
/// `ABCDEFG -> ABCDEFG` 要靠动作序列 n-gram / 状态指纹 / 周期检测；纯思考循环
/// 没有工具动作，只能靠「状态指纹连续不变」和预算阈值兜底。所以这里是三件事
/// 一起判：**重复**（同 actionKey）、**周期**（n-gram）、**无进展**（指纹）。
library;

import 'dart:convert';

import 'agent_budget.dart';
import 'agent_run.dart';

/// StepGuard 给出的四种结论（设计文档 §7.2）。
enum StepGuardAction {
  /// 继续按原计划走。
  proceed('proceed'),

  /// 停止思考，进入答案阶段（reasoning 预算见底 / 重复 / 循环）。
  forceAnswer('force_answer'),

  /// 直接停止本次运行（步数预算、answer reserve 见底）。
  stop('stop'),

  /// 允许一次 repair（循环发生在验证阶段，且还有 repair 预算）。
  repair('repair');

  const StepGuardAction(this.id);

  final String id;
}

/// 一次判定结果。
class StepGuardDecision {
  const StepGuardDecision({
    required this.action,
    this.reason,
    this.message,
  });

  const StepGuardDecision.proceed()
      : action = StepGuardAction.proceed,
        reason = null,
        message = null;

  const StepGuardDecision.forceAnswer(StopReason this.reason, {this.message})
      : action = StepGuardAction.forceAnswer;

  const StepGuardDecision.stop(StopReason this.reason, {this.message})
      : action = StepGuardAction.stop;

  const StepGuardDecision.repair(StopReason this.reason, {this.message})
      : action = StepGuardAction.repair;

  final StepGuardAction action;

  /// 触发原因（`agent_runs.stop_reason` 的值）；proceed 时为 NULL。
  final StopReason? reason;

  /// 一句人话，便于日志/调试。
  final String? message;

  bool get isProceed => action == StepGuardAction.proceed;

  bool get isForceAnswer => action == StepGuardAction.forceAnswer;

  bool get isStop => action == StepGuardAction.stop;

  bool get isRepair => action == StepGuardAction.repair;

  /// 这次判定是否要终止当前「想下去」的循环（forceAnswer/stop/repair）。
  bool get interruptsLoop => !isProceed;

  @override
  String toString() =>
      'StepGuardDecision(${action.id}${reason == null ? '' : ': ${reason!.id}'})';
}

/// 防止一次运行在一个循环里烧完预算的判定器。
///
/// 判定顺序（先命中先返回，顺序即优先级，测试按这个顺序断言）：
///
///  1. `maxSteps` 用完 -> stop；
///  2. reasoning 预算达到 `forceAnswerRatio`（默认 70%）-> forceAnswer；
///  3. answer reserve 不足 -> stop；
///  4. 同一 actionKey 在 `repeatWindow` 步内出现 >= 3 次 -> forceAnswer；
///  5. 动作序列出现周期（ABAB / ABCABC）-> 验证阶段且还有 repair 预算时 repair，
///     否则 forceAnswer；
///  6. 状态指纹连续 `stagnationLimit` 次不变 -> forceAnswer；
///  7. 其余 -> proceed。
///
/// 调用方每一步调一次 [check]，指纹/actionKey 由调用方算（见
/// [AgentActionKey] / [AgentStateFingerprint]）。
class StepGuard {
  StepGuard({
    RunBudget budget = RunBudget.chat,
    int? repeatWindow,
    int? stagnationLimit,
    this.maxCyclePeriod = 4,
    this.repeatLimitInWindow = 3,
  })  : _budget = budget,
        _repeatWindow = repeatWindow ?? budget.repeatWindow,
        _stagnationLimit = stagnationLimit ?? budget.stagnationLimit,
        assert((repeatWindow ?? budget.repeatWindow) >= 2),
        assert((stagnationLimit ?? budget.stagnationLimit) >= 2),
        assert(maxCyclePeriod >= 2),
        assert(repeatLimitInWindow >= 2);

  final RunBudget _budget;
  final int _repeatWindow;
  final int _stagnationLimit;

  /// 周期检测的最大周期（ABCABC 的 3、ABAB 的 2）。
  final int maxCyclePeriod;

  /// 同一动作在窗口里出现多少次算重复。
  final int repeatLimitInWindow;

  final List<String> _actions = [];
  final List<int> _actionTimes = [];
  final List<String> _fingerprints = [];
  String? _lastFingerprint;
  int _sameFingerprintStreak = 0;
  int _lastNowMs = 0;

  /// 最近的动作序列（旧 -> 新），只读，便于日志与测试。
  List<String> get recentActions => List.unmodifiable(_actions);

  /// 最近的状态指纹序列（旧 -> 新）。
  List<String> get recentFingerprints => List.unmodifiable(_fingerprints);

  /// 当前连续「指纹没变」的次数（第一次 check 时是 1）。
  int get sameFingerprintStreak => _sameFingerprintStreak;

  /// 上一次 check 的时间戳。
  int get lastNowMs => _lastNowMs;

  RunBudget get budget => _budget;

  /// 清空历史（一次新的 run 开始时调用；同一个 guard 不要跨 run 复用）。
  void reset() {
    _actions.clear();
    _actionTimes.clear();
    _fingerprints.clear();
    _lastFingerprint = null;
    _sameFingerprintStreak = 0;
    _lastNowMs = 0;
  }

  /// 判定下一步。
  ///
  /// 每次调用都会把这步计入历史（无论结论是什么）：guard 判定的是「走到这一步
  /// 为止的历史」，不依赖调用方是否真的执行了下一步。
  StepGuardDecision check({
    required AgentRunState run,
    required String actionKey,
    required String stateFingerprint,
    required int nowMs,
    int? reasoningTokens,
    int? completionTokens,
    int repairsUsed = 0,
  }) {
    if (actionKey.trim().isEmpty) {
      throw ArgumentError.value(actionKey, 'actionKey', '不能为空');
    }
    if (stateFingerprint.trim().isEmpty) {
      throw ArgumentError.value(stateFingerprint, 'stateFingerprint', '不能为空');
    }

    _lastNowMs = nowMs;
    _actions.add(actionKey);
    _actionTimes.add(nowMs);
    _fingerprints.add(stateFingerprint);
    if (_lastFingerprint == stateFingerprint) {
      _sameFingerprintStreak += 1;
    } else {
      _lastFingerprint = stateFingerprint;
      _sameFingerprintStreak = 1;
    }

    // 1. 步数预算。
    if (run.steps >= _budget.maxSteps) {
      return StepGuardDecision.stop(
        StopReason.maxSteps,
        message: '步数预算用完（${_budget.maxSteps}）',
      );
    }

    // 2. reasoning 预算：想得够多了，必须转去写答案。
    final usedReasoning = reasoningTokens ?? run.reasoningTokens ?? 0;
    final threshold = _budget.forceAnswerAtReasoningTokens;
    if (threshold != null && usedReasoning >= threshold) {
      return StepGuardDecision.forceAnswer(
        StopReason.reasoningBudget,
        message: 'reasoning 已用 $usedReasoning / ${_budget.maxReasoningTokens}，达到交卷阈值 $threshold',
      );
    }

    // 3. answer reserve：再想下去答案就写不出来了。
    final usedCompletion = completionTokens ?? run.completionTokens;
    if (_budget.isAnswerReserveAtRisk(usedCompletion)) {
      return StepGuardDecision.stop(
        StopReason.answerReserve,
        message: 'completion 已用 $usedCompletion，remaining '
            '${_budget.remainingCompletionTokens(usedCompletion)} 低于 answer reserve ${_budget.answerReserveTokens}',
      );
    }

    // 4. 同一动作在窗口里重复太多次。
    if (_repeatInWindow(actionKey)) {
      return StepGuardDecision.forceAnswer(
        StopReason.repeatedAction,
        message: '动作「$actionKey」在最近 $_repeatWindow 步里重复出现',
      );
    }

    // 5. 动作序列周期（ABAB / ABCABC）。
    if (_hasCycle()) {
      if (run.phase == AgentPhase.verify && repairsUsed < _budget.maxRepair) {
        return const StepGuardDecision.repair(
          StopReason.cycleDetected,
          message: '验证阶段出现动作周期，允许一次 repair',
        );
      }
      return StepGuardDecision.forceAnswer(
        StopReason.cycleDetected,
        message: '动作序列出现周期（周期 <= $maxCyclePeriod）',
      );
    }

    // 6. 状态指纹连续不变：做了动作但没有推进。
    if (_sameFingerprintStreak >= _stagnationLimit) {
      return StepGuardDecision.forceAnswer(
        StopReason.noProgress,
        message: '状态指纹连续 $_sameFingerprintStreak 步不变',
      );
    }

    return const StepGuardDecision.proceed();
  }

  bool _repeatInWindow(String actionKey) {
    if (_actions.length < repeatLimitInWindow) {
      return false;
    }
    final start = _actions.length > _repeatWindow
        ? _actions.length - _repeatWindow
        : 0;
    final window = _actions.sublist(start);
    var count = 0;
    for (final action in window) {
      if (action == actionKey) {
        count += 1;
      }
    }
    return count >= repeatLimitInWindow;
  }

  /// 最近的动作序列里是否出现「连续两段相同」的周期。
  bool _hasCycle() {
    final actions = _actions;
    final n = actions.length;
    final maxPeriod = n ~/ 2 < maxCyclePeriod ? n ~/ 2 : maxCyclePeriod;
    for (var period = 2; period <= maxPeriod; period++) {
      final start = n - 2 * period;
      var equal = true;
      for (var i = 0; i < period; i++) {
        if (actions[start + i] != actions[start + period + i]) {
          equal = false;
          break;
        }
      }
      if (equal) {
        return true;
      }
    }
    return false;
  }
}

/// 动作键的稳定构造方式：tool + 规范化参数，或 model step 种类。
///
/// [StepGuard] 只比较字符串，不关心它怎么造；这里给一个统一口径，避免不同调用
/// 方对「同一个动作」各写一套（把时间戳/随机 id 塞进 key 会让重复永远测不到）。
abstract final class AgentActionKey {
  /// 工具动作：`tool:<name>:<args hash>`。
  ///
  /// [args] 会按键排序后 JSON 编码再哈希，所以 `{a:1,b:2}` 与 `{b:2,a:1}` 是
  /// 同一个动作；参数里**不要**放时间戳/随机 id，否则永远不重复。
  static String ofTool(String toolName, [Map<String, Object?> args = const {}]) {
    final canonical = _canonicalJson(args);
    return 'tool:$toolName:${_fnv1aHex(canonical)}';
  }

  /// 模型步骤：`step:<kind>[:<phase>]`。
  ///
  /// 学生模式没有工具，靠这个区分 solve/answer/verify 的模型调用；同一个
  /// phase 内的多次调用是同一个 key —— 连续重复正是要抓的。
  static String ofStep(AgentStepKind kind, {AgentPhase? phase}) {
    final suffix = phase == null ? '' : ':${phase.id}';
    return 'step:${kind.id}$suffix';
  }
}

/// 状态指纹：把一个状态映射稳定地压成短字符串。
///
/// 用途是「这一步和上一步的状态是不是同一个」：键排序后 JSON 编码再做
/// FNV-1a 32 位哈希。选 FNV 而不是加密哈希，是因为它无依赖、够快、够稳
/// （指纹只在一次运行内比较，不参与跨设备去重）。
abstract final class AgentStateFingerprint {
  /// 从任意 JSON-able 的状态映射算指纹。
  static String of(Map<String, Object?> state) =>
      _fnv1aHex(_canonicalJson(state));

  /// 从已拼好的字符串算指纹（调用方自己保证顺序稳定）。
  static String ofText(String text) => _fnv1aHex(text);
}

/// 键排序后的稳定 JSON：`{b:2,a:1}` 与 `{a:1,b:2}` 编码相同。
String _canonicalJson(Object? value) {
  if (value == null || value is num || value is bool || value is String) {
    return jsonEncode(value);
  }
  if (value is List) {
    return '[${value.map(_canonicalJson).join(',')}]';
  }
  if (value is Map) {
    final entries = value.entries.toList()
      ..sort((a, b) => a.key.toString().compareTo(b.key.toString()));
    final parts = <String>[
      for (final entry in entries)
        '${jsonEncode(entry.key.toString())}:${_canonicalJson(entry.value)}',
    ];
    return '{${parts.join(',')}}';
  }
  return jsonEncode(value.toString());
}

/// FNV-1a 32 位，返回 8 位 hex。
String _fnv1aHex(String input) {
  var hash = 0x811c9dc5;
  for (final unit in input.codeUnits) {
    hash ^= unit & 0xFFFF;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}
