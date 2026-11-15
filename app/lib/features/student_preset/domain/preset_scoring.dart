/// 4 档学生预设 + 3 题小样的**只读展示模型**（原型，未标定）。
///
/// 数据源：工作区 `PRESET-SCORING-2026-11-15.json`（task-58 的规则模型输出），
/// 由 `.work/preset-ui/build_preset_asset.py` 压成 `assets/preset_scoring.json`。
///
/// 边界（本文件里刻意写成常量，页面和测试都引用同一份文字）：
/// * 18 分是**原型尺度**（每题 6 分），不是高考分值，不能换算成 150 分制；
/// * 所有学习者参数 `source=preset`、`calibrated=false`、`is_measurement=false`；
/// * 3 题小样 = 物理/数学/语文各 1 题，只是诊断样本，不是成绩。
library;

import 'dart:convert';

/// 页面顶部/卡片上必须出现的三条标记（task-64 验收项）。
const List<String> presetDisclaimerBadges = <String>[
  '3 题小样',
  '预设估计',
  '非高考分',
];

/// 选择只存在内存时的说明；不要写成"已保存设置"。
const String presetSelectionMemoryNote =
    '原型：选择只保存在本应用内存（本次运行有效），不写数据库，也暂未影响解题/评分。';

/// 间隔说明：Monte Carlo 区间是**模型不确定性**，不是学生分数区间。
const String presetIntervalNote =
    '90% 区间是模型参数不确定性区间（预设值 + 未标定系数），不是真实学生分数区间。';

class PresetScoringData {
  const PresetScoringData({
    required this.schema,
    required this.sourceDocument,
    required this.sourceStatus,
    required this.oneLine,
    required this.disclaimers,
    required this.sample,
    required this.presets,
  });

  factory PresetScoringData.fromJson(Map<String, Object?> json) {
    final sampleJson = _map(json['sample']);
    return PresetScoringData(
      schema: json['schema'] as String? ?? '',
      sourceDocument: json['source_document'] as String? ?? '',
      sourceStatus: json['source_status'] as String? ?? '',
      oneLine: json['one_line'] as String? ?? '',
      disclaimers: _stringList(json['disclaimers']),
      sample: PresetSample.fromJson(sampleJson),
      presets: List<PresetOption>.unmodifiable(
        _list(json['presets']).map((raw) => PresetOption.fromJson(_map(raw))),
      ),
    );
  }

  /// 解析本地 asset；顶层必须是 JSON 对象，否则抛 [FormatException]。
  static PresetScoringData decode(String raw) {
    final decoded = _decodeObject(raw, 'preset_scoring.json');
    return PresetScoringData.fromJson(decoded);
  }

  final String schema;
  final String sourceDocument;
  final String sourceStatus;
  final String oneLine;
  final List<String> disclaimers;
  final PresetSample sample;
  final List<PresetOption> presets;

  PresetOption? optionById(String? presetId) {
    for (final preset in presets) {
      if (preset.id == presetId) {
        return preset;
      }
    }
    return null;
  }

  /// 小样包含哪三题（"物理 Q-PH0001 平抛运动…"）。
  String get sampleLine => sample.questions
      .map((q) => '${q.subjectLabel} ${q.id} ${q.topicLabel}')
      .join(' · ');
}

class PresetSample {
  const PresetSample({
    required this.questionCount,
    required this.pointsTotal,
    required this.pointsPerQuestion,
    required this.isFullExam,
    required this.isMeasurement,
    required this.scaleNote,
    required this.questions,
  });

  factory PresetSample.fromJson(Map<String, Object?> json) {
    return PresetSample(
      questionCount: _int(json['question_count']),
      pointsTotal: _double(json['points_total']),
      pointsPerQuestion: _double(json['points_per_question']),
      isFullExam: json['is_full_exam'] == true,
      isMeasurement: json['is_measurement'] == true,
      scaleNote: json['scale_note'] as String? ?? '',
      questions: List<PresetSampleQuestion>.unmodifiable(
        _list(json['questions'])
            .map((raw) => PresetSampleQuestion.fromJson(_map(raw))),
      ),
    );
  }

  final int questionCount;
  final double pointsTotal;
  final double pointsPerQuestion;
  final bool isFullExam;
  final bool isMeasurement;
  final String scaleNote;
  final List<PresetSampleQuestion> questions;
}

class PresetSampleQuestion {
  const PresetSampleQuestion({
    required this.id,
    required this.subjectLabel,
    required this.topicLabel,
  });

  factory PresetSampleQuestion.fromJson(Map<String, Object?> json) {
    return PresetSampleQuestion(
      id: json['id'] as String? ?? '',
      subjectLabel: json['subject_label'] as String? ?? '',
      topicLabel: json['topic_label'] as String? ?? '',
    );
  }

  final String id;
  final String subjectLabel;
  final String topicLabel;
}

/// 一张预设卡：名称/描述/三题小样期望分/区间/强弱项/预计卡点。
class PresetOption {
  const PresetOption({
    required this.id,
    required this.name,
    required this.description,
    required this.expectedPoints,
    required this.pointsTotal,
    required this.rate,
    required this.intervalLow,
    required this.intervalHigh,
    required this.strengths,
    required this.weaknesses,
    required this.questionLines,
  });

  factory PresetOption.fromJson(Map<String, Object?> json) {
    final expected = _map(json['expected']);
    final interval = _list(expected['interval90']);
    return PresetOption(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      expectedPoints: _double(expected['points']),
      pointsTotal: _double(expected['points_total']),
      rate: _double(expected['rate']),
      intervalLow: interval.isNotEmpty ? _double(interval[0]) : 0,
      intervalHigh: interval.length > 1 ? _double(interval[1]) : 0,
      strengths: _stringList(json['strengths']),
      weaknesses: _stringList(json['weaknesses']),
      questionLines: List<PresetQuestionLine>.unmodifiable(
        _list(json['question_lines'])
            .map((raw) => PresetQuestionLine.fromJson(_map(raw))),
      ),
    );
  }

  final String id;
  final String name;
  final String description;

  /// 三题小样模型期望分（原型 18 分制）。
  final double expectedPoints;
  final double pointsTotal;
  final double rate;
  final double intervalLow;
  final double intervalHigh;
  final List<String> strengths;
  final List<String> weaknesses;
  final List<PresetQuestionLine> questionLines;

  /// 例：`4.58/18`。两位小数与报告表格一致。
  String get pointsLabel =>
      '${expectedPoints.toStringAsFixed(2)}/${_totalLabel(pointsTotal)}';

  /// 例：`25.5%`。
  String get rateLabel => '${(rate * 100).toStringAsFixed(1)}%';

  /// 例：`3.68–5.41`（模型不确定性区间）。
  String get intervalLabel =>
      '${intervalLow.toStringAsFixed(2)}–${intervalHigh.toStringAsFixed(2)}';

  /// 每科一行：`物理 2.58/6 卡住`。
  List<String> get questionLineLabels => questionLines
      .map(
        (line) =>
            '${line.subjectLabel} '
            '${line.expectedPoints.toStringAsFixed(2)}/'
            '${_totalLabel(line.pointsTotal)} ${line.outcome}',
      )
      .toList(growable: false);
}

class PresetQuestionLine {
  const PresetQuestionLine({
    required this.questionId,
    required this.subjectLabel,
    required this.expectedPoints,
    required this.pointsTotal,
    required this.outcome,
    required this.stuckStep,
    required this.stuckStepLabel,
    required this.stuckSeverity,
  });

  factory PresetQuestionLine.fromJson(Map<String, Object?> json) {
    return PresetQuestionLine(
      questionId: json['question_id'] as String? ?? '',
      subjectLabel: json['subject_label'] as String? ?? '',
      expectedPoints: _double(json['expected_points']),
      pointsTotal: _double(json['points_total']),
      outcome: json['outcome'] as String? ?? '',
      stuckStep: json['stuck_step'] as String? ?? '',
      stuckStepLabel: json['stuck_step_label'] as String? ?? '',
      stuckSeverity: json['stuck_severity'] as String? ?? '',
    );
  }

  final String questionId;
  final String subjectLabel;
  final double expectedPoints;
  final double pointsTotal;

  /// 「对」「卡住」「错」之一（报告 §4.5 的工程阈值标签，不是教学结论）。
  final String outcome;
  final String stuckStep;
  final String stuckStepLabel;
  final String stuckSeverity;

  /// 例：`物理 N-Q1-06 检验 C：合速度大小增大（高）`。
  String get stuckLabel =>
      '$subjectLabel $stuckStep $stuckStepLabel（$stuckSeverity）';
}

// ---------------------------------------------------------------------------
// JSON helpers（保持与设计板块的解析风格一致：缺失字段给空值，不抛难懂的异常）
// ---------------------------------------------------------------------------

Map<String, Object?> _decodeObject(String raw, String label) {
  final decoded = jsonDecode(raw);
  if (decoded is Map) {
    return decoded.cast<String, Object?>();
  }
  throw FormatException('$label: 顶层必须是 JSON 对象');
}

Map<String, Object?> _map(Object? raw) {
  if (raw is Map) {
    return raw.cast<String, Object?>();
  }
  return const <String, Object?>{};
}

List<Object?> _list(Object? raw) =>
    raw is List ? raw.cast<Object?>() : const <Object?>[];

List<String> _stringList(Object? raw) => List<String>.unmodifiable(
  _list(raw).whereType<String>(),
);

double _double(Object? raw) {
  if (raw is num) {
    return raw.toDouble();
  }
  if (raw is String) {
    return double.tryParse(raw) ?? 0;
  }
  return 0;
}

int _int(Object? raw) {
  if (raw is num) {
    return raw.toInt();
  }
  return int.tryParse('${raw ?? ''}') ?? 0;
}

String _totalLabel(double total) {
  final asInt = total.roundToDouble();
  return asInt == total ? asInt.toStringAsFixed(0) : total.toStringAsFixed(1);
}
