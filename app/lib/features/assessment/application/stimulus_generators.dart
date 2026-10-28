/// 评测任务的刺激生成：把任务配置 + 随机种子变成一串 [PlannedTrial]。
///
/// 纪律（设计文档 §4）：
///
/// * **确定性**：全部随机性来自 `math.Random(seed)`，同一个 seed 逐 trial 相同；
///   测试据此钉住序列，不做「大概随机」的断言。
/// * **纯逻辑**：不 import Flutter、不读时钟、不碰数据库；界面只消费生成结果。
/// * **练习先行**：练习 trial 排在最前并标 `isPractice: true`，引擎与指标层按
///   [PlannedTrial.isMeasured] 过滤；练习不计入正式测量。
/// * **刺激里放够 UI 需要的信息**（prompt / options / option_labels / 原始刺激），
///   UI 不需要回头问引擎「这一 trial 该画什么」。
///
/// 依据：设计文档 v1.0 §4.2（任务清单）、§4.3（试次与时长）、§4.3.2（No-Go
/// 不点=正确）、§4.3.8（decision_fatigue 暂定）。配置键契约见
/// `task_registry.dart` 顶部注释。
library;

import 'dart:math' as math;

import '../domain/assessment_models.dart';
import 'task_registry.dart';

/// 数字广度每个长度重复测几次（§4.3：每个长度 2 次）。
const int kDigitSpanAttemptsPerLength = 2;

/// 一个计划内的 trial：刺激、期望反应与条件标记。
///
/// 这是运行引擎与刺激生成器之间的 transport 类型（共享契约
/// `assessment_models.dart` 目前没有它——已报 Lead，Lead 确认放本文件即可，
/// UI 通过 `assessment_engine.dart` 的 export 拿类型）。
class PlannedTrial {
  const PlannedTrial({
    required this.trialIndex,
    required this.blockIndex,
    required this.stimulus,
    required this.expectedResponse,
    this.isPractice = false,
    this.condition = const <String, Object?>{},
  });

  /// 本会话内从 0 开始的序号（练习 trial 也占号，与 TrialResult.trialIndex 对齐）。
  final int trialIndex;

  /// 块序号：单块任务恒为 0；疲劳任务按段分块；练习 trial 归第 0 块。
  final int blockIndex;

  /// 呈现给 UI 的刺激（JSON 可编码对象）。
  final Map<String, Object?> stimulus;

  /// 期望反应：choice / stroop / switching / decision 为 String 选项码；
  /// go-nogo / n-back / fatigue 为 bool（true = 该点）；digit-span 为倒背字符串。
  final Object? expectedResponse;

  /// 练习 trial：只用于熟悉流程，不进测量。
  final bool isPractice;

  /// 条件标记（§3.2 的分组维度：一致/冲突/钓鱼、切换/重复、匹配/不匹配…）。
  final Map<String, Object?> condition;

  /// 有效 trial：非练习。所有指标只统计有效 trial。
  bool get isMeasured => !isPractice;

  Map<String, Object?> toJson() => <String, Object?>{
        'trial_index': trialIndex,
        'block_index': blockIndex,
        'is_practice': isPractice,
        'stimulus': stimulus,
        'expected_response': expectedResponse,
        'condition': condition,
      };

  @override
  String toString() => 'PlannedTrial(#$trialIndex, block $blockIndex, '
      '${isPractice ? 'practice' : 'measured'})';
}

/// 任务配置的解析结果：生成器与引擎共用的一套参数。
///
/// 每个字段都有默认值，[TaskRunParameters.fromConfig] 只覆盖配置里出现的键；
/// 类型不对的值按默认值处理（不抛），因为配置是数据而不是代码，坏数据应该在
/// 注册表校验里报。
class TaskRunParameters {
  const TaskRunParameters({
    this.trials = 0,
    this.practiceTrials = 0,
    this.blocks = 1,
    this.isiMinMs = 300,
    this.isiMaxMs = 700,
    this.responseWindowMs = 2500,
    this.options = const <String>[],
    this.goRatio = 0.7,
    this.n = 2,
    this.matchRatio = 0.35,
    this.congruentRatio = 0.4,
    this.conflictRatio = 0.4,
    this.fishRatio = 0.2,
    this.switchRatio = 0.5,
    this.digitSpanStartLength = 3,
    this.digitSpanLengths = const <int>[3, 4, 5, 6, 7, 8, 9],
    this.digitSpanFailuresToStop = 2,
    this.digitSpanDisplayMs = 1500,
    this.digitSpanGapMs = 500,
    this.fatigueBlockSeconds = 60,
    this.fatigueTrialsPerBlock = 30,
  });

  /// 从 [AssessmentTaskConfig.config] 解析；缺失键走默认值。
  factory TaskRunParameters.fromConfig(Map<String, Object?> config) {
    final options = config['options'];
    return TaskRunParameters(
      trials: _intOption(config, 'trials', 0),
      practiceTrials: _intOption(config, 'practice_trials', 0),
      blocks: _positiveOr(_intOption(config, 'blocks', 1), 1),
      isiMinMs: _intOption(config, 'isi_min_ms', 300),
      isiMaxMs: _intOption(config, 'isi_max_ms', 700),
      responseWindowMs: _intOption(config, 'response_window_ms', 2500),
      options: options is List
          ? <String>[
              for (final value in options)
                if (value is String && value.trim().isNotEmpty) value.trim(),
            ]
          : const <String>[],
      goRatio: _doubleOption(config, 'go_ratio', 0.7),
      n: _positiveOr(_intOption(config, 'n', 2), 1),
      matchRatio: _doubleOption(config, 'match_ratio', 0.35),
      congruentRatio: _doubleOption(config, 'congruent_ratio', 0.4),
      conflictRatio: _doubleOption(config, 'conflict_ratio', 0.4),
      fishRatio: _doubleOption(config, 'fish_ratio', 0.2),
      switchRatio: _doubleOption(config, 'switch_ratio', 0.5),
      digitSpanStartLength: _intOption(config, 'start_length', 3),
      digitSpanLengths: _intListOption(config, 'lengths'),
      digitSpanFailuresToStop: _intOption(config, 'failures_to_stop', 2),
      digitSpanDisplayMs: _intOption(config, 'display_ms', 1500),
      digitSpanGapMs: _intOption(config, 'gap_ms', 500),
      fatigueBlockSeconds: _intOption(config, 'block_seconds', 60),
      fatigueTrialsPerBlock:
          _positiveOr(_intOption(config, 'trials_per_block', 30), 1),
    );
  }

  /// 正式测量的 trial 数（不含练习）。
  final int trials;

  /// 练习 trial 数。
  final int practiceTrials;

  /// 块数（单块任务为 1）。
  final int blocks;

  /// 刺激呈现前空屏（ms）的下界 / 上界。
  final int isiMinMs;
  final int isiMaxMs;

  /// 反应窗口（ms）；超时由引擎判错并记 rtMs=null。
  final int responseWindowMs;

  /// choice 类任务的选项码（顺序即 UI 顺序）。
  final List<String> options;

  /// go 试次比例（go/no-go 任务）。
  final double goRatio;

  /// n-back 的 n。
  final int n;

  /// n-back 匹配比例。
  final double matchRatio;

  /// Stroop 三类 trial 的比例：一致 / 冲突 / 钓鱼。
  final double congruentRatio;
  final double conflictRatio;
  final double fishRatio;

  /// task-switching 的切换比例。
  final double switchRatio;

  /// 数字广度：起始长度、阶梯长度表、连续失败停止阈值、呈现时长、间隔。
  final int digitSpanStartLength;
  final List<int> digitSpanLengths;
  final int digitSpanFailuresToStop;
  final int digitSpanDisplayMs;
  final int digitSpanGapMs;

  /// 疲劳块：每段秒数、每段 trial 数。
  final int fatigueBlockSeconds;
  final int fatigueTrialsPerBlock;
}

int _intOption(Map<String, Object?> config, String key, int fallback) {
  final value = config[key];
  if (value is int) return value;
  if (value is num) return value.round();
  return fallback;
}

double _doubleOption(Map<String, Object?> config, String key, double fallback) {
  final value = config[key];
  if (value is num) return value.toDouble();
  return fallback;
}

int _positiveOr(int value, int fallback) => value > 0 ? value : fallback;

List<int> _intListOption(Map<String, Object?> config, String key) {
  final value = config[key];
  if (value is! List) return const <int>[3, 4, 5, 6, 7, 8, 9];
  final lengths = <int>[
    for (final item in value)
      if (item is int && item > 0)
        item
      else if (item is num && item > 0)
        item.round(),
  ];
  return lengths.isEmpty ? const <int>[3, 4, 5, 6, 7, 8, 9] : lengths;
}

/// 生成一个任务的全部 trial（练习在前，正式 trial 在后）。
///
/// 未知 taskId → 按 taskType 兜底；两者都不认识 → ArgumentError（不静默返回空
/// 队列，那会变成一个「什么都测不出来」的假会话）。
List<PlannedTrial> generatePlannedTrials({
  required AssessmentTaskConfig task,
  required int seed,
  TaskRunParameters? parameters,
}) {
  final params = parameters ?? TaskRunParameters.fromConfig(task.config);
  final random = math.Random(seed);
  final trials = switch (task.taskId) {
    AssessmentTaskIds.fastSimpleI =>
      _shapeClassificationTrials(params: params, random: random),
    AssessmentTaskIds.fastSimpleIi =>
      _sumComparisonTrials(params: params, random: random),
    AssessmentTaskIds.fastSimpleIii =>
      _sameDifferentTrials(params: params, random: random),
    AssessmentTaskIds.goNogo => _goNogoTrials(params: params, random: random),
    AssessmentTaskIds.digitSpanBackward =>
      _digitSpanTrials(params: params, random: random),
    AssessmentTaskIds.nBack2 => _nBackTrials(params: params, random: random),
    AssessmentTaskIds.stroopCrosslang =>
      _stroopTrials(params: params, random: random),
    AssessmentTaskIds.taskSwitching =>
      _switchingTrials(params: params, random: random),
    AssessmentTaskIds.fatigueBlock =>
      _fatigueBlockTrials(params: params, random: random),
    AssessmentTaskIds.decisionFatigue =>
      _decisionFatigueTrials(params: params, random: random),
    _ => _byTaskType(task.taskType, params: params, random: random),
  };
  return List<PlannedTrial>.unmodifiable(trials);
}

List<PlannedTrial> _byTaskType(
  AssessmentTaskType type, {
  required TaskRunParameters params,
  required math.Random random,
}) {
  return switch (type) {
    AssessmentTaskType.choiceReaction =>
      _shapeClassificationTrials(params: params, random: random),
    AssessmentTaskType.goNogo => _goNogoTrials(params: params, random: random),
    AssessmentTaskType.nBack => _nBackTrials(params: params, random: random),
    AssessmentTaskType.stroop => _stroopTrials(params: params, random: random),
    AssessmentTaskType.switching =>
      _switchingTrials(params: params, random: random),
    AssessmentTaskType.fatigue =>
      _fatigueBlockTrials(params: params, random: random),
    AssessmentTaskType.digitSpan =>
      _digitSpanTrials(params: params, random: random),
    AssessmentTaskType.decisionFatigue =>
      _decisionFatigueTrials(params: params, random: random),
  };
}

/// 练习 trial 复用正式 trial 的前几个刺激，再把序号重排成连续序列。
List<PlannedTrial> _finalize({
  required int practiceCount,
  required List<PlannedTrial> measured,
}) {
  final trials = <PlannedTrial>[];
  if (measured.isEmpty) return trials;
  for (var index = 0; index < practiceCount; index++) {
    final template = measured[index % measured.length];
    trials.add(
      PlannedTrial(
        trialIndex: trials.length,
        blockIndex: 0,
        stimulus: template.stimulus,
        expectedResponse: template.expectedResponse,
        isPractice: true,
        condition: template.condition,
      ),
    );
  }
  for (final trial in measured) {
    trials.add(
      PlannedTrial(
        trialIndex: trials.length,
        blockIndex: trial.blockIndex,
        stimulus: trial.stimulus,
        expectedResponse: trial.expectedResponse,
        condition: trial.condition,
      ),
    );
  }
  return trials;
}

int _measuredCount(TaskRunParameters params, int fallback) =>
    params.trials > 0 ? params.trials : fallback;

int _practiceCount(TaskRunParameters params) =>
    params.practiceTrials > 0 ? params.practiceTrials : 0;

// ---------------------------------------------------------------------------
// fast_simple_task_i：图形分类（圆 / 方），§4.2 快速分类 I
// ---------------------------------------------------------------------------

List<PlannedTrial> _shapeClassificationTrials({
  required TaskRunParameters params,
  required math.Random random,
}) {
  final count = _measuredCount(params, 30);
  final shapes = <String>[
    for (var index = 0; index < count; index++)
      index.isEven ? 'circle' : 'square',
  ]..shuffle(random);
  final measured = <PlannedTrial>[
    for (var index = 0; index < count; index++)
      PlannedTrial(
        trialIndex: index,
        blockIndex: 0,
        stimulus: <String, Object?>{
          'prompt': '这个图形是圆还是方？',
          'shape': shapes[index],
          'options': const <String>['circle', 'square'],
          'option_labels': const <String, String>{'circle': '圆', 'square': '方'},
        },
        expectedResponse: shapes[index],
        condition: <String, Object?>{'shape': shapes[index]},
      ),
  ];
  return _finalize(practiceCount: _practiceCount(params), measured: measured);
}

// ---------------------------------------------------------------------------
// fast_simple_task_ii：两位数加和是否大于 6（§4.2 快速分类 II）
// ---------------------------------------------------------------------------

List<PlannedTrial> _sumComparisonTrials({
  required TaskRunParameters params,
  required math.Random random,
}) {
  final count = _measuredCount(params, 30);
  final measured = <PlannedTrial>[];
  for (var index = 0; index < count; index++) {
    final greater = index.isEven;
    final sum = greater ? 7 + random.nextInt(4) : 2 + random.nextInt(5);
    final low = math.max(1, sum - 5);
    final high = math.min(5, sum - 1);
    final left = low + random.nextInt(high - low + 1);
    final right = sum - left;
    final expression = '$left + $right';
    measured.add(
      PlannedTrial(
        trialIndex: index,
        blockIndex: 0,
        stimulus: <String, Object?>{
          'prompt': '$expression 的和大于 6 吗？',
          'expression': expression,
          'left': left,
          'right': right,
          'sum': sum,
          'options': const <String>['yes', 'no'],
          'option_labels': const <String, String>{'yes': '是', 'no': '否'},
        },
        expectedResponse: greater ? 'yes' : 'no',
        condition: <String, Object?>{
          'sum': sum,
          'greater_than_six': greater,
        },
      ),
    );
  }
  return _finalize(practiceCount: _practiceCount(params), measured: measured);
}

// ---------------------------------------------------------------------------
// fast_simple_task_iii：快速匹配 / 同异判断（§4.2 可选副本）
// ---------------------------------------------------------------------------

List<PlannedTrial> _sameDifferentTrials({
  required TaskRunParameters params,
  required math.Random random,
}) {
  final count = _measuredCount(params, 30);
  final measured = <PlannedTrial>[];
  for (var index = 0; index < count; index++) {
    final same = index.isEven;
    final leftShape = random.nextBool() ? 'circle' : 'square';
    final rightShape =
        same ? leftShape : (leftShape == 'circle' ? 'square' : 'circle');
    measured.add(
      PlannedTrial(
        trialIndex: index,
        blockIndex: 0,
        stimulus: <String, Object?>{
          'prompt': '两个图形一样吗？',
          'left_shape': leftShape,
          'right_shape': rightShape,
          'options': const <String>['same', 'different'],
          'option_labels': const <String, String>{
            'same': '一样',
            'different': '不一样',
          },
        },
        expectedResponse: same ? 'same' : 'different',
        condition: <String, Object?>{'same': same},
      ),
    );
  }
  return _finalize(practiceCount: _practiceCount(params), measured: measured);
}

// ---------------------------------------------------------------------------
// go_nogo：Go 圆 / No-Go 方，约 70/30（§4.2 / §4.3.2）
// ---------------------------------------------------------------------------

List<PlannedTrial> _goNogoTrials({
  required TaskRunParameters params,
  required math.Random random,
}) {
  final count = _measuredCount(params, 70);
  final goCount = (count * params.goRatio).round().clamp(0, count);
  final booleans = <bool>[
    for (var index = 0; index < count; index++) index < goCount,
  ]..shuffle(random);
  final measured = <PlannedTrial>[
    for (var index = 0; index < count; index++)
      PlannedTrial(
        trialIndex: index,
        blockIndex: 0,
        stimulus: <String, Object?>{
          'prompt': '看到圆点就点，方形不要点',
          'shape': booleans[index] ? 'circle' : 'square',
          'options': const <String>['tap', 'withhold'],
          'option_labels': const <String, String>{'tap': '点', 'withhold': '不点'},
        },
        expectedResponse: booleans[index],
        condition: <String, Object?>{'should_tap': booleans[index]},
      ),
  ];
  return _finalize(practiceCount: _practiceCount(params), measured: measured);
}

// ---------------------------------------------------------------------------
// digit_span_backward：固定阶梯（3..9 各 2 次）的可复现近似（§4.2）
// ---------------------------------------------------------------------------

List<PlannedTrial> _digitSpanTrials({
  required TaskRunParameters params,
  required math.Random random,
}) {
  final lengths = params.digitSpanLengths;
  final measured = <PlannedTrial>[];
  for (final length in lengths) {
    for (var attempt = 0; attempt < kDigitSpanAttemptsPerLength; attempt++) {
      final digits = <int>[1 + random.nextInt(9)];
      for (var position = 1; position < length; position++) {
        digits.add(random.nextInt(10));
      }
      measured.add(
        PlannedTrial(
          trialIndex: measured.length,
          blockIndex: 0,
          stimulus: <String, Object?>{
            'prompt': '倒着背出这串数字',
            'digits': digits,
            'length': length,
          },
          expectedResponse: digits.reversed.join(),
          condition: <String, Object?>{'length': length, 'attempt': attempt},
        ),
      );
    }
  }
  return _finalize(practiceCount: _practiceCount(params), measured: measured);
}

// ---------------------------------------------------------------------------
// n_back_2：2-back 字母匹配（§4.2 / §4.3）
// ---------------------------------------------------------------------------

List<PlannedTrial> _nBackTrials({
  required TaskRunParameters params,
  required math.Random random,
}) {
  const letters = 'ABCDEFGHIJ';
  final n = params.n;
  final count = _measuredCount(params, 60);
  final sequence = <String>[];
  for (var index = 0; index < count; index++) {
    if (index < n) {
      sequence.add(letters[random.nextInt(letters.length)]);
      continue;
    }
    final match = random.nextDouble() < params.matchRatio;
    if (match) {
      sequence.add(sequence[index - n]);
      continue;
    }
    String letter;
    do {
      letter = letters[random.nextInt(letters.length)];
    } while (letter == sequence[index - n]);
    sequence.add(letter);
  }
  final measured = <PlannedTrial>[
    for (var index = 0; index < count; index++)
      PlannedTrial(
        trialIndex: index,
        blockIndex: 0,
        stimulus: <String, Object?>{
          'prompt': '这个字母和前面第 $n 个一样吗？',
          'letter': sequence[index],
          'n': n,
          'sequence': List<String>.unmodifiable(sequence.sublist(0, index + 1)),
          'options': const <String>['same', 'different'],
          'option_labels': const <String, String>{
            'same': '一样',
            'different': '不一样'
          },
        },
        expectedResponse: index >= n && sequence[index] == sequence[index - n],
        condition: <String, Object?>{
          'n': n,
          'match': index >= n && sequence[index] == sequence[index - n],
        },
      ),
  ];
  return _finalize(practiceCount: _practiceCount(params), measured: measured);
}

// ---------------------------------------------------------------------------
// stroop_crosslang：中文颜色词 + 英文选项 red/blue，含钓鱼 trial（§4.2）
// ---------------------------------------------------------------------------

List<PlannedTrial> _stroopTrials({
  required TaskRunParameters params,
  required math.Random random,
}) {
  final count = _measuredCount(params, 50);
  final fishCount = (count * params.fishRatio).round().clamp(0, count);
  final conflictCount =
      (count * params.conflictRatio).round().clamp(0, count - fishCount);
  final congruentCount = count - fishCount - conflictCount;
  final kinds = <String>[
    for (var index = 0; index < congruentCount; index++) 'congruent',
    for (var index = 0; index < conflictCount; index++) 'conflict',
    for (var index = 0; index < fishCount; index++) 'fish',
  ]..shuffle(random);
  final measured = <PlannedTrial>[
    for (var index = 0; index < count; index++)
      _stroopTrial(index: index, kind: kinds[index], random: random),
  ];
  return _finalize(practiceCount: _practiceCount(params), measured: measured);
}

PlannedTrial _stroopTrial({
  required int index,
  required String kind,
  required math.Random random,
}) {
  final ink = random.nextBool() ? 'red' : 'blue';
  final fish = kind == 'fish';
  final congruent = kind == 'congruent';
  final word = fish
      ? (ink == 'red' ? 'BLUE' : 'RED')
      : (congruent ? (ink == 'red' ? '红' : '蓝') : (ink == 'red' ? '蓝' : '红'));
  final wordInk =
      fish ? ink : (congruent ? ink : (ink == 'red' ? 'blue' : 'red'));
  return PlannedTrial(
    trialIndex: index,
    blockIndex: 0,
    stimulus: <String, Object?>{
      'prompt': '选字体颜色对应的英文（不是字义）',
      'word': word,
      'ink': ink,
      'options': const <String>['red', 'blue'],
    },
    expectedResponse: ink,
    condition: <String, Object?>{
      'kind': kind,
      'word': word,
      'word_ink': wordInk,
    },
  );
}

// ---------------------------------------------------------------------------
// task_switching：数字奇偶 / 字母大小写，切换约 50/50（§4.2）
// ---------------------------------------------------------------------------

List<PlannedTrial> _switchingTrials({
  required TaskRunParameters params,
  required math.Random random,
}) {
  final count = _measuredCount(params, 70);
  final measured = <PlannedTrial>[];
  var cue = 'parity';
  for (var index = 0; index < count; index++) {
    var switched = false;
    if (index > 0) {
      switched = random.nextDouble() < params.switchRatio;
      if (switched) cue = cue == 'parity' ? 'case' : 'parity';
    }
    final PlannedTrial trial;
    if (cue == 'parity') {
      final value = 1 + random.nextInt(9);
      trial = PlannedTrial(
        trialIndex: index,
        blockIndex: 0,
        stimulus: <String, Object?>{
          'prompt': '这个数是奇数还是偶数？',
          'cue': cue,
          'value': value,
          'options': const <String>['odd', 'even'],
          'option_labels': const <String, String>{'odd': '奇数', 'even': '偶数'},
        },
        expectedResponse: value.isOdd ? 'odd' : 'even',
        condition: <String, Object?>{'cue': cue, 'switched': switched},
      );
    } else {
      const letters = 'ABCDE';
      final upper = random.nextBool();
      final letter = letters[random.nextInt(letters.length)];
      final value = upper ? letter : letter.toLowerCase();
      trial = PlannedTrial(
        trialIndex: index,
        blockIndex: 0,
        stimulus: <String, Object?>{
          'prompt': '这个字母是大写还是小写？',
          'cue': cue,
          'value': value,
          'options': const <String>['upper', 'lower'],
          'option_labels': const <String, String>{
            'upper': '大写',
            'lower': '小写',
          },
        },
        expectedResponse: upper ? 'upper' : 'lower',
        condition: <String, Object?>{'cue': cue, 'switched': switched},
      );
    }
    measured.add(trial);
  }
  return _finalize(practiceCount: _practiceCount(params), measured: measured);
}

// ---------------------------------------------------------------------------
// fatigue_block：3 段 x 60 秒重复点击（§4.2 / §4.3）
// ---------------------------------------------------------------------------

List<PlannedTrial> _fatigueBlockTrials({
  required TaskRunParameters params,
  required math.Random random,
}) {
  final blocks = params.blocks > 0 ? params.blocks : 3;
  final perBlock = params.fatigueTrialsPerBlock;
  final count = blocks * perBlock;
  final measured = <PlannedTrial>[
    for (var index = 0; index < count; index++)
      PlannedTrial(
        trialIndex: index,
        blockIndex: index ~/ perBlock,
        stimulus: <String, Object?>{
          'prompt': '看到方块就点',
          'block_index': index ~/ perBlock,
          'block_seconds': params.fatigueBlockSeconds,
          'trial_in_block': index % perBlock,
        },
        expectedResponse: true,
        condition: <String, Object?>{
          'block_index': index ~/ perBlock,
          'trial_in_block': index % perBlock,
        },
      ),
  ];
  return _finalize(practiceCount: _practiceCount(params), measured: measured);
}

// ---------------------------------------------------------------------------
// decision_fatigue：连续二选一，选数值更大者（§4.2 / §4.3.8，暂定）
// ---------------------------------------------------------------------------

List<PlannedTrial> _decisionFatigueTrials({
  required TaskRunParameters params,
  required math.Random random,
}) {
  final count = _measuredCount(params, 75);
  final measured = <PlannedTrial>[
    for (var index = 0; index < count; index++)
      _decisionTrial(index: index, random: random),
  ];
  return _finalize(practiceCount: _practiceCount(params), measured: measured);
}

PlannedTrial _decisionTrial({
  required int index,
  required math.Random random,
}) {
  final left = 1 + random.nextInt(9);
  var right = 1 + random.nextInt(9);
  while (right == left) {
    right = 1 + random.nextInt(9);
  }
  final leftIsLarger = left > right;
  return PlannedTrial(
    trialIndex: index,
    blockIndex: 0,
    stimulus: <String, Object?>{
      'prompt': '选数值更大的那个',
      'left': left,
      'right': right,
      'options': const <String>['left', 'right'],
      'option_labels': const <String, String>{'left': '左', 'right': '右'},
    },
    expectedResponse: leftIsLarger ? 'left' : 'right',
    condition: <String, Object?>{
      'left_value': left,
      'right_value': right,
    },
  );
}
