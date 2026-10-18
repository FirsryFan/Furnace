/// 入库体检（QuestionIntakeAudit）：把组卷网 skill 的 H1–H4「可证伪硬伤」判据
/// 本地化成确定性检查。只报不改、不联网、不读 DB、不碰 UI。
///
/// 判据权威：lib/data/skill/zujuan_finder_skill.dart:90-101（H1 题干自身有毛病 /
/// H2 答案错 / H3 难度标错 / H4 重复题；样本 <5 道只算初筛、「未发现硬伤」不等于
/// 「已证明没问题」、判硬伤前先排除采集丢信息）。本文件只做其中能用纯文本确定判定
/// 的部分：
///
///  - H1：空/超短题干、选择题选项体系（数量/标签连续/标签重复/内容空）、单选与多选
///    的正确标记矛盾、题干说「如图」却没有图；
///  - H2：答案缺失、解析缺失、解析等于答案（只有答案没有过程）、答案不是选项字母、
///    答案与选项正确标记矛盾、有答案却没有正确标记；
///  - H3：difficulty / year / aiQuality 越界、学科为空或不在已知集合、来源分级未知
///    且来源说明为空；
///  - H4：同批题干指纹或归一化题干重复、题目编号重复/缺失；
///  - 本地点：没有关联知识点。
///
/// 不判（需要人或模型判断，见 docs/QUESTION_INTAKE_AUDIT_DESIGN.md 的「未做」）：
/// 知识正确性、条件不足/歧义/超纲、难度是否「真实」、近似重复（换数值/换选项顺序）、
/// 来源是否真的可信（不联网）。「未发现硬伤」不等于「已证明没问题」。
///
/// 阈值取舍集中写在 [QuestionIntakeAudit] 的构造参数与公开常量里；默认值只为下一轮
/// UI 初筛服务，不是已标定的质量结论。difficulty 默认区间 1–10 跟 questions 表口径
/// 一致（lib/data/database/tables.dart:1132、docs/QUESTION_BANK_DESIGN.md:41、收题页
/// lib/features/questions/presentation/question_intake_page.dart:127），不是 0–1；
/// 若以后改成归一化难度，注入 minDifficulty: 0 / maxDifficulty: 1 即可。
library;

import 'question_number.dart'
    show formatQuestionSerial, kUnnumberedQuestionLabel;

/// 体检严重度。报告内排序口径固定：error > warning > info（即 [index] 升序）。
enum QuestionAuditSeverity {
  /// 数据坏了：这道题现在不能正常判分/入库（例如单选题没有正确标记）。
  error,

  /// 可疑：可能是采集丢信息或标注缺失，不阻塞入库但提示人工看一眼。
  warning,

  /// 提示：不影响题目本身（例如还没有关联知识点）。
  info,
}

extension QuestionAuditSeverityLabel on QuestionAuditSeverity {
  /// 界面展示用的中文名。
  String get labelZh => switch (this) {
        QuestionAuditSeverity.error => '错误',
        QuestionAuditSeverity.warning => '警告',
        QuestionAuditSeverity.info => '提示',
      };
}

/// 所有判据 code 的常量表。code 是稳定契约（下一轮 UI/文档按它分组），改字面量要当
/// 破坏性变更处理；新增判据只追加，不改旧 code 的含义。
abstract final class QuestionAuditCodes {
  // ---- H1 题干/选项体系 ----
  static const String h1StemEmpty = 'h1_stem_empty';
  static const String h1StemTooShort = 'h1_stem_too_short';
  static const String h1ChoiceOptionsTooFew = 'h1_choice_options_too_few';
  static const String h1OptionLabelDuplicate = 'h1_option_label_duplicate';
  static const String h1OptionLabelNotSequential =
      'h1_option_label_not_sequential';
  static const String h1OptionContentEmpty = 'h1_option_content_empty';
  static const String h1SingleChoiceNoCorrect = 'h1_single_choice_no_correct';
  static const String h1SingleChoiceMultipleCorrect =
      'h1_single_choice_multiple_correct';
  static const String h1MultiChoiceNoCorrect = 'h1_multi_choice_no_correct';
  static const String h1FigureMissing = 'h1_figure_missing';

  // ---- H2 答案/解析 ----
  static const String h2AnswerMissing = 'h2_answer_missing';
  static const String h2SolutionMissing = 'h2_solution_missing';
  static const String h2SolutionEqualsAnswer = 'h2_solution_equals_answer';
  static const String h2AnswerNotInOptions = 'h2_answer_not_in_options';
  static const String h2AnswerConflictsCorrectMark =
      'h2_answer_conflicts_correct_mark';
  static const String h2AnswerWithoutCorrectMark =
      'h2_answer_without_correct_mark';

  // ---- H3 元信息 ----
  static const String h3DifficultyOutOfRange = 'h3_difficulty_out_of_range';
  static const String h3YearOutOfRange = 'h3_year_out_of_range';
  static const String h3SubjectMissing = 'h3_subject_missing';
  static const String h3SubjectUnknown = 'h3_subject_unknown';
  static const String h3SourceLevelUnknown = 'h3_source_level_unknown';
  static const String h3AiQualityOutOfRange = 'h3_ai_quality_out_of_range';

  // ---- H4 重复/编号 ----
  static const String h4DuplicateStem = 'h4_duplicate_stem';
  static const String h4DuplicateSerial = 'h4_duplicate_serial';
  static const String h4SerialMissing = 'h4_serial_missing';

  // ---- 本地点 ----
  static const String localNoKnowledgePoints = 'local_no_knowledge_points';

  /// 全部 code，按文档/表里的顺序。UI 做「判据图例」时直接用它。
  static const List<String> all = <String>[
    h1StemEmpty,
    h1StemTooShort,
    h1ChoiceOptionsTooFew,
    h1OptionLabelDuplicate,
    h1OptionLabelNotSequential,
    h1OptionContentEmpty,
    h1SingleChoiceNoCorrect,
    h1SingleChoiceMultipleCorrect,
    h1MultiChoiceNoCorrect,
    h1FigureMissing,
    h2AnswerMissing,
    h2SolutionMissing,
    h2SolutionEqualsAnswer,
    h2AnswerNotInOptions,
    h2AnswerConflictsCorrectMark,
    h2AnswerWithoutCorrectMark,
    h3DifficultyOutOfRange,
    h3YearOutOfRange,
    h3SubjectMissing,
    h3SubjectUnknown,
    h3SourceLevelUnknown,
    h3AiQualityOutOfRange,
    h4DuplicateStem,
    h4DuplicateSerial,
    h4SerialMissing,
    localNoKnowledgePoints,
  ];
}

/// 默认的「当前年份」。不隐式读 DateTime.now()：体检结果要可复现、可测，年份检查
/// 必须由调用方注入（任务口径：默认 2026 便于测试）。
const int kQuestionAuditDefaultCurrentYear = 2026;

/// 题干最少字符数（去掉空白后按 Unicode code point 计）。低于它报 warning：
/// 6 字是一个取舍——最短的完整单选题设问（「下列说法正确的是」）也有 8 字，
/// <6 基本是拍照切题残留或题干被截断（「如图」「第3题」）；阈值压低是为了不让
/// warning 淹没真问题，宁可漏报轻微截断也不误伤刻意出的短题。
const int kQuestionAuditMinStemChars = 6;

/// 年份下限：高考/教材语境下早于 1900 的题目年份基本是脏数据（0/占位符等）。
const int kQuestionAuditMinYear = 1900;

/// 年份允许超前当前年份一年：当年尚未考完的卷子/次年模拟卷会被标成未来年份。
const int kQuestionAuditFutureYearSlack = 1;

/// 难度默认下限（questions.difficulty 是 1–10，不是 0–1；见 library doc）。
const double kQuestionAuditMinDifficulty = 1.0;

/// 难度默认上限。
const double kQuestionAuditMaxDifficulty = 10.0;

/// aiQuality 下限（questions.aiQuality 口径 0–1，tables.dart:1148）。
const double kQuestionAuditMinAiQuality = 0.0;

/// aiQuality 上限。
const double kQuestionAuditMaxAiQuality = 1.0;

/// 走选项体系检查的题型（questions.questionType 口径，tables.dart:1117）。
const Set<String> kQuestionAuditChoiceTypes = <String>{
  'single_choice',
  'multi_choice',
};

/// 已知来源分级的镜像：与 lib/data/repositories/question_repository.dart:15-22 的
/// kSourceLevelWeight keys 保持一致。这里不能 import 那个文件（它 import drift，
/// 本文件要求纯 Dart），所以镜像一份；权威仍在仓储。默认构造参数里
/// knownSourceLevels 为空集 = 跳过该检查；接 UI 时传这个集合即可启用。
const Set<String> kQuestionAuditKnownSourceLevels = <String>{
  'gaokao',
  'provincial_diagnostic',
  'elite_school',
  'school',
  'personal',
  'unknown',
};

/// 一条待体检的选项（对应 question_options 表：label/content/isCorrect）。
class QuestionAuditOption {
  const QuestionAuditOption({
    required this.label,
    this.content = '',
    this.isCorrect = false,
  });

  /// 选项标签，例如 A。比较时忽略大小写与两端空白。
  final String label;

  /// 选项正文（纯文本）。
  final String content;

  /// 是否被标成正确选项。
  final bool isCorrect;

  @override
  String toString() => 'QuestionAuditOption($label, ${content.length} chars, '
      'isCorrect: $isCorrect)';
}

/// 一行待体检的题目。字段刻意与 questions / question_options 表一一对应，这样下一轮
/// UI 从 DB 读出来直接拼行即可，不需要体检层认识 drift。
///
/// 与任务书输入模型相比多了一个 [aiQuality]：H3 判据要求检查 aiQuality 越界，但任务书
/// 的行模型清单漏了这个字段；不加就实现不了该判据（见设计文档「偏离说明」）。
class QuestionAuditRow {
  const QuestionAuditRow({
    required this.questionId,
    this.serialNo,
    required this.stem,
    this.answer,
    this.solution,
    this.questionType = 'solution',
    this.subjectKey = '',
    this.sourceLevel = 'unknown',
    this.sourceLabel,
    this.year,
    this.region,
    this.difficulty,
    this.aiQuality,
    this.stemFingerprint,
    this.options = const <QuestionAuditOption>[],
    this.knowledgePointIds = const <String>[],
    this.imageCount = 0,
    this.state = 'raw',
  });

  /// 题目主键（questions.id）。
  final String questionId;

  /// 人可读编号（questions.serialNo，可空 = 还没编号）。
  final int? serialNo;

  /// 题干（纯文本；公式保留 LaTeX）。
  final String stem;

  /// 参考答案原文。
  final String? answer;

  /// 解析原文。
  final String? solution;

  /// single_choice / multi_choice / fill_blank / solution / open。
  final String questionType;

  /// 学科 key，例如 physics。
  final String subjectKey;

  /// 来源分级（见 [kQuestionAuditKnownSourceLevels]）。
  final String sourceLevel;

  /// 人可读来源，例如「2024 湖南师大附中月考」。
  final String? sourceLabel;

  /// 试卷年份。
  final int? year;

  /// 地区（本轮不判定，留给后续）。
  final String? region;

  /// 难度 1–10。
  final double? difficulty;

  /// AI 预评分 0–1。
  final double? aiQuality;

  /// 题干指纹（stemFingerprint，可空；空则按归一化题干比较重复）。
  final String? stemFingerprint;

  /// 选项（多选题也按顺序给）。
  final List<QuestionAuditOption> options;

  /// 关联知识点 id（可空）。
  final List<String> knowledgePointIds;

  /// 题干图片数量（来自 attachments；0 表示无图）。
  final int imageCount;

  /// 加工状态 raw / structured / processed（本轮不判定，留给 UI 过滤）。
  final String state;
}

/// 一条体检结论：只描述观察到的事实 + 为什么算硬伤，不改数据。
class QuestionAuditFinding {
  const QuestionAuditFinding({
    required this.questionId,
    required this.code,
    required this.severity,
    required this.messageZh,
    this.evidence = const <String, String>{},
  });

  /// 出问题的题目（questions.id）。
  final String questionId;

  /// 判据 code（[QuestionAuditCodes]）。
  final String code;

  /// 严重度。
  final QuestionAuditSeverity severity;

  /// 一句给人看的中文说明。
  final String messageZh;

  /// 判定依据（机器可读的键值），报告与 UI 用来展示「凭什么」。
  ///
  /// 键统一 snake_case；值一律转成字符串，方便直接塞日志/JSON。
  final Map<String, String> evidence;

  /// 浅序列化（UI 日志/调试用）。
  Map<String, Object?> toJson() => <String, Object?>{
        'question_id': questionId,
        'code': code,
        'severity': severity.name,
        'message_zh': messageZh,
        'evidence': evidence,
      };

  @override
  String toString() =>
      'QuestionAuditFinding($questionId, $code, ${severity.name})';
}

/// 一次体检的结果。构造后只读；排序保证见 [QuestionIntakeAudit.audit]。
class QuestionAuditReport {
  const QuestionAuditReport({required this.findings});

  /// 已排序的结论（questionId 升序 → error > warning > info → code 升序）。
  final List<QuestionAuditFinding> findings;

  int get errorCount => _count(QuestionAuditSeverity.error);

  int get warningCount => _count(QuestionAuditSeverity.warning);

  int get infoCount => _count(QuestionAuditSeverity.info);

  /// 一条结论都没有 = 本次检查未发现硬伤。不等于「已证明没问题」。
  bool get isClean => findings.isEmpty;

  /// 每种严重度的数量（给 UI 徽标用）。
  Map<QuestionAuditSeverity, int> get counts => <QuestionAuditSeverity, int>{
        for (final severity in QuestionAuditSeverity.values)
          severity: _count(severity),
      };

  /// 某道题的结论（按报告排序口径；没有则空列表）。
  List<QuestionAuditFinding> findingsFor(String questionId) =>
      <QuestionAuditFinding>[
        for (final finding in findings)
          if (finding.questionId == questionId) finding,
      ];

  /// 某个严重度的全部结论。
  List<QuestionAuditFinding> bySeverity(QuestionAuditSeverity severity) =>
      <QuestionAuditFinding>[
        for (final finding in findings)
          if (finding.severity == severity) finding,
      ];

  int _count(QuestionAuditSeverity severity) {
    var count = 0;
    for (final finding in findings) {
      if (finding.severity == severity) count++;
    }
    return count;
  }
}

/// 入库体检器：同一次批量体检共享同一套阈值，输出确定性报告。
///
/// 判据见 [QuestionAuditCodes]；只报不改、不联网、不读 DB。
class QuestionIntakeAudit {
  const QuestionIntakeAudit({
    this.currentYear = kQuestionAuditDefaultCurrentYear,
    this.knownSubjectKeys = const <String>{},
    this.knownSourceLevels = const <String>{},
    this.minDifficulty = kQuestionAuditMinDifficulty,
    this.maxDifficulty = kQuestionAuditMaxDifficulty,
  });

  /// 年份检查用的「今年」（默认 2026；不隐式用 DateTime.now）。
  final int currentYear;

  /// 已知学科 key 集合。空集 = 跳过「学科不在已知集合」检查（只检查空学科）。
  final Set<String> knownSubjectKeys;

  /// 已知来源分级集合。空集 = 跳过「来源分级未知」检查。
  final Set<String> knownSourceLevels;

  /// 难度允许下限（默认 1；0–1 归一化场景由调用方注入 0）。
  final double minDifficulty;

  /// 难度允许上限（默认 10；0–1 归一化场景由调用方注入 1）。
  final double maxDifficulty;

  /// 体检一批题，返回按固定口径排序的报告。
  ///
  /// 排序：questionId 升序 → severity（error > warning > info）→ code 升序；
  /// 完全相同的键再按产生顺序（实现里显式加 index 兜底，不依赖 List.sort 是否稳定）。
  QuestionAuditReport audit(Iterable<QuestionAuditRow> rows) {
    final list = rows.toList(growable: false);
    final findings = <QuestionAuditFinding>[
      for (final row in list) ..._findingsForRow(row),
      ..._duplicateStemFindings(list),
      ..._duplicateSerialFindings(list),
    ];
    return QuestionAuditReport(findings: _sortedFindings(findings));
  }

  /// 只体检一行（不含 H4 跨行重复检查）。UI 单题详情页可用它避免整批计算。
  List<QuestionAuditFinding> auditRow(QuestionAuditRow row) =>
      _sortedFindings(_findingsForRow(row));

  // ---------------------------------------------------------------------------
  // 行内判据
  // ---------------------------------------------------------------------------

  List<QuestionAuditFinding> _findingsForRow(QuestionAuditRow row) {
    final findings = <QuestionAuditFinding>[];
    final stem = row.stem.trim();
    final stemLength = _visibleLength(stem);
    if (stem.isEmpty) {
      findings.add(_finding(
        row,
        QuestionAuditCodes.h1StemEmpty,
        QuestionAuditSeverity.error,
        '题干为空',
        <String, String>{'stem_length': '0'},
      ));
    } else if (stemLength < kQuestionAuditMinStemChars) {
      findings.add(_finding(
        row,
        QuestionAuditCodes.h1StemTooShort,
        QuestionAuditSeverity.warning,
        '题干只有 $stemLength 个字符（阈值 $kQuestionAuditMinStemChars），'
        '像拍照切题残留或题干被截断',
        <String, String>{
          'stem_length': '$stemLength',
          'min_stem_chars': '$kQuestionAuditMinStemChars',
        },
      ));
    }

    final questionType = row.questionType.trim();
    final isChoice = kQuestionAuditChoiceTypes.contains(questionType);
    if (isChoice) {
      findings.addAll(_choiceFindings(row));
    }

    if (row.imageCount <= 0 && _figureReferencePattern.hasMatch(stem)) {
      findings.add(_finding(
        row,
        QuestionAuditCodes.h1FigureMissing,
        QuestionAuditSeverity.warning,
        '题干说「如图」但 imageCount=0：图片可能在采集时丢了',
        <String, String>{
          'image_count': '${row.imageCount}',
          'matched': _firstFigureMatch(stem),
        },
      ));
    }

    findings.addAll(_answerFindings(row, isChoice: isChoice));

    final difficulty = row.difficulty;
    if (difficulty != null) {
      final outOfRange = difficulty.isNaN ||
          difficulty < minDifficulty ||
          difficulty > maxDifficulty;
      if (outOfRange) {
        findings.add(_finding(
          row,
          QuestionAuditCodes.h3DifficultyOutOfRange,
          QuestionAuditSeverity.warning,
          '难度 $difficulty 不在 $minDifficulty–$maxDifficulty 区间',
          <String, String>{
            'difficulty': '$difficulty',
            'min': '$minDifficulty',
            'max': '$maxDifficulty',
          },
        ));
      }
    }

    final maxYear = currentYear + kQuestionAuditFutureYearSlack;
    final year = row.year;
    if (year != null && (year < kQuestionAuditMinYear || year > maxYear)) {
      findings.add(_finding(
        row,
        QuestionAuditCodes.h3YearOutOfRange,
        QuestionAuditSeverity.warning,
        '年份 $year 越界（允许 $kQuestionAuditMinYear–$maxYear）',
        <String, String>{
          'year': '$year',
          'min_year': '$kQuestionAuditMinYear',
          'max_year': '$maxYear',
        },
      ));
    }

    final subject = row.subjectKey.trim();
    if (subject.isEmpty) {
      findings.add(_finding(
        row,
        QuestionAuditCodes.h3SubjectMissing,
        QuestionAuditSeverity.warning,
        '学科为空',
        const <String, String>{},
      ));
    } else if (knownSubjectKeys.isNotEmpty &&
        !knownSubjectKeys.contains(subject)) {
      findings.add(_finding(
        row,
        QuestionAuditCodes.h3SubjectUnknown,
        QuestionAuditSeverity.warning,
        '学科「$subject」不在已知学科集合里',
        <String, String>{
          'subject_key': subject,
          'known_count': '${knownSubjectKeys.length}',
        },
      ));
    }

    final sourceLevel = row.sourceLevel.trim();
    final sourceLabel = row.sourceLabel?.trim() ?? '';
    if (knownSourceLevels.isNotEmpty &&
        !knownSourceLevels.contains(sourceLevel) &&
        sourceLabel.isEmpty) {
      findings.add(_finding(
        row,
        QuestionAuditCodes.h3SourceLevelUnknown,
        QuestionAuditSeverity.warning,
        '来源分级「$sourceLevel」不在已知分级里，且来源说明为空：'
        '这道题追不到出处',
        <String, String>{
          'source_level': sourceLevel,
          'source_label': '',
        },
      ));
    }

    final aiQuality = row.aiQuality;
    if (aiQuality != null) {
      final outOfRange = aiQuality.isNaN ||
          aiQuality < kQuestionAuditMinAiQuality ||
          aiQuality > kQuestionAuditMaxAiQuality;
      if (outOfRange) {
        findings.add(_finding(
          row,
          QuestionAuditCodes.h3AiQualityOutOfRange,
          QuestionAuditSeverity.warning,
          'aiQuality $aiQuality 不在 '
          '$kQuestionAuditMinAiQuality–$kQuestionAuditMaxAiQuality 区间',
          <String, String>{
            'ai_quality': '$aiQuality',
            'min': '$kQuestionAuditMinAiQuality',
            'max': '$kQuestionAuditMaxAiQuality',
          },
        ));
      }
    }

    final serialNo = row.serialNo;
    if (serialNo == null || serialNo < 1) {
      findings.add(_finding(
        row,
        QuestionAuditCodes.h4SerialMissing,
        QuestionAuditSeverity.info,
        '题目还没有编号（界面显示 $kUnnumberedQuestionLabel）',
        <String, String>{
          'serial_no': serialNo == null ? 'null' : '$serialNo',
        },
      ));
    }

    final knowledgePoints = <String>[
      for (final id in row.knowledgePointIds)
        if (id.trim().isNotEmpty) id.trim(),
    ];
    if (knowledgePoints.isEmpty) {
      findings.add(_finding(
        row,
        QuestionAuditCodes.localNoKnowledgePoints,
        QuestionAuditSeverity.info,
        '没有关联知识点（不影响判分，只影响按考点检索）',
        const <String, String>{},
      ));
    }

    return findings;
  }

  /// H1 选择题选项体系。
  List<QuestionAuditFinding> _choiceFindings(QuestionAuditRow row) {
    final findings = <QuestionAuditFinding>[];
    final options = row.options;
    final labels = <String>[
      for (final option in options) _normalizeLabel(option.label),
    ];

    if (options.length < 2) {
      findings.add(_finding(
        row,
        QuestionAuditCodes.h1ChoiceOptionsTooFew,
        QuestionAuditSeverity.error,
        '选择题只有 ${options.length} 个选项（至少 2 个）',
        <String, String>{
          'question_type': row.questionType.trim(),
          'option_count': '${options.length}',
        },
      ));
    }

    final duplicated = <String>[];
    final seen = <String>{};
    for (final label in labels) {
      if (!seen.add(label) && !duplicated.contains(label)) {
        duplicated.add(label);
      }
    }
    if (duplicated.isNotEmpty) {
      final duplicatedLabels = duplicated.map(_displayLabel).join('、');
      findings.add(_finding(
        row,
        QuestionAuditCodes.h1OptionLabelDuplicate,
        QuestionAuditSeverity.error,
        '选项标签重复：$duplicatedLabels',
        <String, String>{
          'duplicated_labels': duplicated.map(_displayLabel).join(','),
        },
      ));
    }

    if (options.length <= 26) {
      final expected = <String>[
        for (var index = 0; index < options.length; index++)
          String.fromCharCode(65 + index),
      ];
      var matches = labels.length == expected.length;
      if (matches) {
        for (var index = 0; index < labels.length; index++) {
          if (labels[index] != expected[index]) {
            matches = false;
            break;
          }
        }
      }
      if (!matches) {
        final actualLabels = labels.map(_displayLabel).join('、');
        findings.add(_finding(
          row,
          QuestionAuditCodes.h1OptionLabelNotSequential,
          QuestionAuditSeverity.warning,
          '选项标签不是 A/B/C… 连续序列（实际：$actualLabels）',
          <String, String>{
            'labels': labels.map(_displayLabel).join(','),
            'expected': expected.join(','),
          },
        ));
      }
    }

    final emptyLabels = <String>[];
    for (var index = 0; index < options.length; index++) {
      if (options[index].content.trim().isEmpty) {
        emptyLabels.add(_labelOrIndex(labels[index], index));
      }
    }
    if (emptyLabels.isNotEmpty) {
      final emptyJoined = emptyLabels.join('、');
      findings.add(_finding(
        row,
        QuestionAuditCodes.h1OptionContentEmpty,
        QuestionAuditSeverity.warning,
        '选项 $emptyJoined 的内容为空（采集可能丢了正文）',
        <String, String>{'empty_content_labels': emptyLabels.join(',')},
      ));
    }

    final correctLabels = <String>[
      for (var index = 0; index < options.length; index++)
        if (options[index].isCorrect) _labelOrIndex(labels[index], index),
    ];
    final questionType = row.questionType.trim();
    if (questionType == 'single_choice') {
      if (correctLabels.isEmpty) {
        findings.add(_finding(
          row,
          QuestionAuditCodes.h1SingleChoiceNoCorrect,
          QuestionAuditSeverity.error,
          '单选题没有标出正确选项（无法判分）',
          const <String, String>{},
        ));
      } else if (correctLabels.length > 1) {
        final correctJoined = correctLabels.join('、');
        findings.add(_finding(
          row,
          QuestionAuditCodes.h1SingleChoiceMultipleCorrect,
          QuestionAuditSeverity.error,
          '单选题标了 ${correctLabels.length} 个正确选项（$correctJoined）',
          <String, String>{
            'correct_labels': correctLabels.join(','),
            'correct_count': '${correctLabels.length}',
          },
        ));
      }
    } else if (questionType == 'multi_choice' && correctLabels.isEmpty) {
      findings.add(_finding(
        row,
        QuestionAuditCodes.h1MultiChoiceNoCorrect,
        QuestionAuditSeverity.error,
        '多选题没有标出正确选项（无法判分）',
        const <String, String>{},
      ));
    }

    return findings;
  }

  /// H2 答案与正确标记的一致性。
  List<QuestionAuditFinding> _answerFindings(
    QuestionAuditRow row, {
    required bool isChoice,
  }) {
    final findings = <QuestionAuditFinding>[];
    final answer = row.answer?.trim() ?? '';
    final solution = row.solution?.trim() ?? '';

    if (answer.isEmpty) {
      findings.add(_finding(
        row,
        QuestionAuditCodes.h2AnswerMissing,
        QuestionAuditSeverity.warning,
        '答案缺失（题库允许先存题干、答案后补，所以只算 warning）',
        const <String, String>{},
      ));
    }
    if (solution.isEmpty) {
      findings.add(_finding(
        row,
        QuestionAuditCodes.h2SolutionMissing,
        QuestionAuditSeverity.warning,
        '解析缺失',
        const <String, String>{},
      ));
    } else if (answer.isNotEmpty &&
        _collapseWhitespace(solution) == _collapseWhitespace(answer)) {
      findings.add(_finding(
        row,
        QuestionAuditCodes.h2SolutionEqualsAnswer,
        QuestionAuditSeverity.warning,
        '解析与答案完全相同：只有答案没有过程，不能托付',
        <String, String>{'answer': answer, 'solution': solution},
      ));
    }

    if (!isChoice || answer.isEmpty) {
      return findings;
    }

    final availableLabels = <String>{
      for (final option in row.options)
        if (option.label.trim().isNotEmpty) _normalizeLabel(option.label),
    };
    final letters = _answerLetters(answer);
    final sortedAvailable = availableLabels.toList()..sort();
    if (letters.isEmpty) {
      findings.add(_finding(
        row,
        QuestionAuditCodes.h2AnswerNotInOptions,
        QuestionAuditSeverity.error,
        '选择题答案「$answer」里没有选项字母（判分只读 answer 列，会判不了）',
        <String, String>{
          'answer': answer,
          'option_labels': sortedAvailable.join(','),
        },
      ));
      return findings;
    }

    final answerLetters = letters.toSet();
    final unknown = answerLetters.difference(availableLabels);
    if (unknown.isNotEmpty) {
      final unknownJoined = (unknown.toList()..sort()).join('、');
      findings.add(_finding(
        row,
        QuestionAuditCodes.h2AnswerNotInOptions,
        QuestionAuditSeverity.error,
        '答案字母 $unknownJoined 不在选项标签里',
        <String, String>{
          'answer': answer,
          'option_labels': sortedAvailable.join(','),
        },
      ));
      return findings;
    }

    final correctLabels = <String>{
      for (final option in row.options)
        if (option.isCorrect) _normalizeLabel(option.label),
    };
    if (correctLabels.isEmpty) {
      findings.add(_finding(
        row,
        QuestionAuditCodes.h2AnswerWithoutCorrectMark,
        QuestionAuditSeverity.warning,
        '有答案「$answer」但选项都没标正确标记：答案无法在选项上核验',
        <String, String>{
          'answer': answer,
          'option_labels': sortedAvailable.join(','),
        },
      ));
      return findings;
    }

    final notMarked = answerLetters.difference(correctLabels)
      ..removeWhere((label) => label.isEmpty);
    final missingFromAnswer = correctLabels.difference(answerLetters);
    final isMulti = row.questionType.trim() == 'multi_choice';
    final conflicts =
        notMarked.isNotEmpty || (isMulti && missingFromAnswer.isNotEmpty);
    if (conflicts) {
      final sortedCorrect = correctLabels.toList()..sort();
      final answerLabel = (answerLetters.toList()..sort()).join('、');
      findings.add(_finding(
        row,
        QuestionAuditCodes.h2AnswerConflictsCorrectMark,
        QuestionAuditSeverity.error,
        '答案（$answerLabel）与选项正确标记（${sortedCorrect.join('、')}）'
        '矛盾',
        <String, String>{
          'answer': answer,
          'answer_labels': answerLabel,
          'correct_labels': sortedCorrect.join(','),
        },
      ));
    }

    return findings;
  }

  // ---------------------------------------------------------------------------
  // 跨行判据（H4）
  // ---------------------------------------------------------------------------

  /// 同批重复题干：按归一化题干分组（始终做），有指纹的再按指纹分组；
  /// 两者命中都合并成一条 [QuestionAuditCodes.h4DuplicateStem]（不重复报）。
  List<QuestionAuditFinding> _duplicateStemFindings(
    List<QuestionAuditRow> rows,
  ) {
    final byStem = <String, List<int>>{};
    final byFingerprint = <String, List<int>>{};
    final normalizedStems = <String>[
      for (final row in rows) _normalizeStemForKey(row.stem),
    ];
    for (var index = 0; index < rows.length; index++) {
      final stemKey = normalizedStems[index];
      if (stemKey.isNotEmpty) {
        byStem.putIfAbsent(stemKey, () => <int>[]).add(index);
      }
      final fingerprint = rows[index].stemFingerprint?.trim() ?? '';
      if (fingerprint.isNotEmpty) {
        byFingerprint.putIfAbsent(fingerprint, () => <int>[]).add(index);
      }
    }

    final findings = <QuestionAuditFinding>[];
    for (var index = 0; index < rows.length; index++) {
      final others = <int>{};
      var matchedByStem = false;
      var matchedByFingerprint = false;
      final stemPeers = byStem[normalizedStems[index]];
      if (stemPeers != null && stemPeers.length > 1) {
        matchedByStem = true;
        others.addAll(stemPeers.where((peer) => peer != index));
      }
      final fingerprint = rows[index].stemFingerprint?.trim() ?? '';
      if (fingerprint.isNotEmpty) {
        final fingerprintPeers = byFingerprint[fingerprint];
        if (fingerprintPeers != null && fingerprintPeers.length > 1) {
          matchedByFingerprint = true;
          others.addAll(fingerprintPeers.where((peer) => peer != index));
        }
      }
      if (others.isEmpty) {
        continue;
      }
      final otherIds = <String>[
        for (final peer in others.toList()..sort()) rows[peer].questionId,
      ];
      final String matchedBy;
      if (matchedByStem && matchedByFingerprint) {
        matchedBy = 'both';
      } else if (matchedByFingerprint) {
        matchedBy = 'fingerprint';
      } else {
        matchedBy = 'stem';
      }
      findings.add(_finding(
        rows[index],
        QuestionAuditCodes.h4DuplicateStem,
        QuestionAuditSeverity.error,
        '与同批 ${otherIds.length} 道题题干重复：${otherIds.join('、')}',
        <String, String>{
          'other_question_ids': otherIds.join(','),
          'matched_by': matchedBy,
        },
      ));
    }
    return findings;
  }

  /// 同批重复题目编号（只比较正整数；NULL/0 由 h4_serial_missing 负责）。
  List<QuestionAuditFinding> _duplicateSerialFindings(
    List<QuestionAuditRow> rows,
  ) {
    final bySerial = <int, List<int>>{};
    for (var index = 0; index < rows.length; index++) {
      final serial = rows[index].serialNo;
      if (serial != null && serial >= 1) {
        bySerial.putIfAbsent(serial, () => <int>[]).add(index);
      }
    }

    final findings = <QuestionAuditFinding>[];
    for (final entry in bySerial.entries) {
      if (entry.value.length < 2) continue;
      final serialLabel = formatQuestionSerial(entry.key);
      final peers = entry.value;
      for (final index in peers) {
        final otherIds = <String>[
          for (final peer in peers)
            if (peer != index) rows[peer].questionId,
        ];
        findings.add(_finding(
          rows[index],
          QuestionAuditCodes.h4DuplicateSerial,
          QuestionAuditSeverity.error,
          '题目编号 $serialLabel 在同批里重复：${otherIds.join('、')}',
          <String, String>{
            'serial_no': '${entry.key}',
            'serial_label': serialLabel,
            'other_question_ids': otherIds.join(','),
          },
        ));
      }
    }
    return findings;
  }

  // ---------------------------------------------------------------------------
  // 内部工具
  // ---------------------------------------------------------------------------

  QuestionAuditFinding _finding(
    QuestionAuditRow row,
    String code,
    QuestionAuditSeverity severity,
    String messageZh, [
    Map<String, String> evidence = const <String, String>{},
  ]) =>
      QuestionAuditFinding(
        questionId: row.questionId,
        code: code,
        severity: severity,
        messageZh: messageZh,
        evidence: evidence,
      );

  /// 确定性排序：questionId → severity → code → 产生顺序（显式 index 兜底，
  /// 不依赖 Dart List.sort 的稳定性）。
  List<QuestionAuditFinding> _sortedFindings(
    List<QuestionAuditFinding> findings,
  ) {
    final indexed = <({int index, QuestionAuditFinding finding})>[
      for (var index = 0; index < findings.length; index++)
        (index: index, finding: findings[index]),
    ];
    indexed.sort((a, b) {
      final byQuestion = a.finding.questionId.compareTo(b.finding.questionId);
      if (byQuestion != 0) return byQuestion;
      final bySeverity =
          a.finding.severity.index.compareTo(b.finding.severity.index);
      if (bySeverity != 0) return bySeverity;
      final byCode = a.finding.code.compareTo(b.finding.code);
      if (byCode != 0) return byCode;
      return a.index.compareTo(b.index);
    });
    return List<QuestionAuditFinding>.unmodifiable(
      <QuestionAuditFinding>[for (final item in indexed) item.finding],
    );
  }
}

/// 便捷入口：构造默认 [QuestionIntakeAudit] 体检一批题。
QuestionAuditReport auditQuestionIntake(
  Iterable<QuestionAuditRow> rows, {
  int currentYear = kQuestionAuditDefaultCurrentYear,
  Set<String> knownSubjectKeys = const <String>{},
  Set<String> knownSourceLevels = const <String>{},
  double minDifficulty = kQuestionAuditMinDifficulty,
  double maxDifficulty = kQuestionAuditMaxDifficulty,
}) =>
    QuestionIntakeAudit(
      currentYear: currentYear,
      knownSubjectKeys: knownSubjectKeys,
      knownSourceLevels: knownSourceLevels,
      minDifficulty: minDifficulty,
      maxDifficulty: maxDifficulty,
    ).audit(rows);

// -----------------------------------------------------------------------------
// 纯函数工具
// -----------------------------------------------------------------------------

final RegExp _figureReferencePattern = RegExp(r'如图|见图|下图|上图');
final RegExp _whitespacePattern = RegExp(r'\s+');

/// 归一化题干（与 lib/data/repositories/question_repository.dart:41-47 的
/// normalizeStem 同一口径：去全部空白、去常见中英文标点、转小写）。
///
/// 这里镜像一份而不是 import 那个文件：它 import drift，本文件要求纯 Dart。
/// 镜像偏差只在「标点表」上——两边必须一起改；H4 的指纹分组与归一化分组是互补的
/// （指纹命中即使归一化不同也会报）。
String _normalizeStemForKey(String stem) => stem
    .replaceAll(_whitespacePattern, '')
    .replaceAll(
      RegExp(r'''[，。！？；：、“”‘’（）《》【】〈〉·,.!?;:"'()\[\]{}<>]'''),
      '',
    )
    .toLowerCase();

String _collapseWhitespace(String text) =>
    text.replaceAll(_whitespacePattern, '').trim();

int _visibleLength(String text) =>
    text.replaceAll(_whitespacePattern, '').runes.length;

String _normalizeLabel(String label) => label.trim().toUpperCase();

String _displayLabel(String normalizedLabel) =>
    normalizedLabel.isEmpty ? '<空标签>' : normalizedLabel;

String _labelOrIndex(String normalizedLabel, int index) =>
    normalizedLabel.isEmpty ? '第${index + 1}项' : normalizedLabel;

List<String> _answerLetters(String answer) => <String>[
      for (final match in RegExp(r'[A-Za-z]').allMatches(answer))
        match.group(0)!.toUpperCase(),
    ];

String _firstFigureMatch(String stem) {
  final match = _figureReferencePattern.firstMatch(stem);
  return match?.group(0) ?? '';
}
