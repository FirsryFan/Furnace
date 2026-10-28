/// 评测运行引擎：一次会话的 trial 推进、反应记录与判分。
///
/// 冻结 API（UI 已按此写）——签名不要改：
///
/// ```dart
/// AssessmentRunEngine({required AssessmentTaskConfig task, required int seed,
///     required DateTime startedAt});
/// AssessmentTaskConfig get task;
/// List<PlannedTrial> get trials;
/// PlannedTrial? get current;
/// int get trialIndex;
/// bool get isFinished;
/// bool get isPracticePhase;
/// bool get awaitingResponse;
/// void markShown(DateTime at);
/// TrialResult submit({required Object? response, required DateTime at});
/// TrialResult submitTimeout({required DateTime at});
/// List<TrialResult> get recorded;
/// ```
///
/// 语义：
///
/// * **RT = submit 时间 - markShown 时间**；没 markShown 就先 submit 属于调用方
///   bug，抛 StateError（不静默记 rt=0，那会污染指标）。
/// * **正确性按任务类型判定**，期望值形态见 [PlannedTrial.expectedResponse]：
///   choice / stroop / switching / decision 比较选项码；go-nogo / n-back 比较
///   是否按键；digit-span 比较倒背字符串。
/// * **超时**：§4.3.2「No-Go 不点=正确」——期望反应为 false 的 trial 超时算对，
///   其余超时算错；rtMs 一律 null（不是 0）。
/// * **recorded 含练习 trial**（isPractice=true），指标层自己按
///   [PlannedTrial.isMeasured] / [TrialResult.isMeasured] 过滤。
/// * 纯 Dart：不 import Flutter、不读时钟（时间全部由调用方传入）。
library;

import '../domain/assessment_models.dart';
import 'stimulus_generators.dart';

// UI 用 engine 拿类型即可，不需要额外 import models。
export 'stimulus_generators.dart' show PlannedTrial;

/// 一次任务会话的运行状态机。
class AssessmentRunEngine {
  AssessmentRunEngine({
    required this.task,
    required int seed,
    required this.startedAt,
  }) : _trials = generatePlannedTrials(task: task, seed: seed);

  /// 本次会话的任务定义。
  final AssessmentTaskConfig task;

  /// 会话开始时间（调用方传入，便于测试与重放）。
  final DateTime startedAt;

  final List<PlannedTrial> _trials;
  final List<TrialResult> _recorded = <TrialResult>[];

  int _index = 0;
  DateTime? _shownAt;

  /// 全部计划 trial（练习在前），只读。
  List<PlannedTrial> get trials => _trials;

  /// 当前 trial；会话结束后为 null。
  PlannedTrial? get current =>
      _index >= 0 && _index < _trials.length ? _trials[_index] : null;

  /// 当前 trial 的序号（与 [PlannedTrial.trialIndex] 一致）；结束后等于 trial 总数。
  int get trialIndex => _index;

  /// 所有 trial 都处理完了。
  bool get isFinished => _index >= _trials.length;

  /// 当前是否处于练习阶段。
  bool get isPracticePhase => current?.isPractice ?? false;

  /// 当前 trial 已呈现、还没作答。
  bool get awaitingResponse => current != null && _shownAt != null;

  /// 标记当前 trial 的刺激呈现时刻；RT 以此为起点。
  void markShown(DateTime at) {
    if (current == null) {
      throw StateError('会话已结束，没有可呈现的 trial');
    }
    _shownAt = at;
  }

  /// 提交一次反应并前进到下一个 trial。
  TrialResult submit({required Object? response, required DateTime at}) {
    final trial = current;
    if (trial == null) {
      throw StateError('会话已结束，不能再提交');
    }
    final shownAt = _shownAt;
    if (shownAt == null) {
      throw StateError('submit 之前必须先 markShown（否则 RT 没有起点）');
    }
    final rtMs = _elapsedMs(shownAt: shownAt, at: at);
    final result = TrialResult(
      trialIndex: trial.trialIndex,
      blockIndex: trial.blockIndex,
      stimulus: _recordedStimulus(trial),
      response: _responseMap(response),
      rtMs: rtMs,
      correct: _judge(trial, response),
      isPractice: trial.isPractice,
      timestamp: at,
    );
    _recorded.add(result);
    _advance();
    return result;
  }

  /// 本次 trial 超时：rtMs=null；只有「期望不点」的 trial 算对（§4.3.2）。
  TrialResult submitTimeout({required DateTime at}) {
    final trial = current;
    if (trial == null) {
      throw StateError('会话已结束，不能再提交');
    }
    if (_shownAt == null) {
      throw StateError('submitTimeout 之前必须先 markShown');
    }
    final expected = trial.expectedResponse;
    final result = TrialResult(
      trialIndex: trial.trialIndex,
      blockIndex: trial.blockIndex,
      stimulus: _recordedStimulus(trial),
      rtMs: null,
      correct: expected is bool ? !expected : false,
      isPractice: trial.isPractice,
      timestamp: at,
    );
    _recorded.add(result);
    _advance();
    return result;
  }

  /// 已记录的 trial（含练习），只读快照。
  List<TrialResult> get recorded => List<TrialResult>.unmodifiable(_recorded);

  /// 记录 trial 时把 [PlannedTrial.condition] 并进 stimulus。
  ///
  /// [TrialResult] 没有 condition 字段，而指标层（switch_cost / conflict_cost /
  /// d_prime / fish_trial_accuracy …）要按条件分组；合并进 stimulus 后这些标记
  /// 会随 stimulus_json 一起落库，旧数据不受影响（旧数据没有这些键，指标返回
  /// null 而不是算错）。同名字段以 stimulus 为准。
  static Map<String, Object?> _recordedStimulus(PlannedTrial trial) =>
      Map<String, Object?>.unmodifiable(<String, Object?>{
        ...trial.stimulus,
        ...trial.condition,
      });

  void _advance() {
    _index += 1;
    _shownAt = null;
  }

  static int _elapsedMs({required DateTime shownAt, required DateTime at}) {
    final elapsed = at.difference(shownAt).inMilliseconds;
    return elapsed < 0 ? 0 : elapsed;
  }

  /// 期望反应与用户反应的比较；期望为 null 表示无客观正确答案。
  static bool? _judge(PlannedTrial trial, Object? response) {
    final expected = trial.expectedResponse;
    if (expected == null) return null;
    if (expected is bool) {
      final pressed = _asPressed(response);
      return pressed != null && pressed == expected;
    }
    final normalized = _asChoiceCode(response);
    if (normalized == null) return false;
    return normalized == '$expected';
  }

  /// 把 UI 的反应统一成 Map（TrialResult.response 的类型要求）。
  static Map<String, Object?> _responseMap(Object? response) {
    if (response == null) return const <String, Object?>{};
    if (response is Map<String, Object?>) {
      return Map<String, Object?>.unmodifiable(response);
    }
    if (response is Map) {
      return Map<String, Object?>.unmodifiable(<String, Object?>{
        for (final entry in response.entries) '${entry.key}': entry.value,
      });
    }
    if (response is String) {
      return Map<String, Object?>.unmodifiable(
          <String, Object?>{'choice': response});
    }
    if (response is bool) {
      return Map<String, Object?>.unmodifiable(
          <String, Object?>{'pressed': response});
    }
    return Map<String, Object?>.unmodifiable(
        <String, Object?>{'value': response});
  }

  /// 选项码：直接给 String，或 Map 里的 choice / value / answer 字段。
  static String? _asChoiceCode(Object? response) {
    if (response is String) {
      final trimmed = response.trim();
      return trimmed.isEmpty ? null : trimmed;
    }
    if (response is Map) {
      for (final key in const <String>['choice', 'value', 'answer']) {
        final value = response[key];
        if (value is String && value.trim().isNotEmpty) return value.trim();
      }
    }
    return null;
  }

  /// 是否按键：bool，或 Map 的 pressed 字段，或 tap / withhold 字符串。
  static bool? _asPressed(Object? response) {
    if (response is bool) return response;
    if (response is Map) {
      final pressed = response['pressed'];
      if (pressed is bool) return pressed;
      final choice = response['choice'];
      if (choice is String) return _pressedFromCode(choice);
      return null;
    }
    if (response is String) return _pressedFromCode(response);
    return null;
  }

  static bool? _pressedFromCode(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'tap':
      case 'go':
      case 'yes':
      case 'true':
        return true;
      case 'withhold':
      case 'nogo':
      case 'no':
      case 'false':
        return false;
      default:
        return null;
    }
  }
}
