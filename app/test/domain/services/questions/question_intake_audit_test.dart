import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/questions/question_intake_audit.dart';

/// 入库体检（task-15）验收点：
///
///  * 干净题零 finding；每条判据 code 至少一例触发；
///  * 跨行「重复题干（含指纹回退）」「重复题目编号」两边都报；
///  * 优先级排序稳定（questionId → error > warning > info → code）；
///  * 阈值边界：题干长度/难度/年份/aiQuality 的恰好上下界；
///  * 默认 14 个旧行为不受影响不存在（这是新文件），但干净数据必须零噪音。

const String _defaultStem = '某同学用打点计时器探究加速度与力、质量的关系，得到一条点迹清晰的纸带。'
    '下列关于该实验操作的说法正确的是';

const List<QuestionAuditOption> _defaultOptions = <QuestionAuditOption>[
  QuestionAuditOption(
    label: 'A',
    content: '平衡摩擦力时不需要挂砂桶',
    isCorrect: true,
  ),
  QuestionAuditOption(label: 'B', content: '实验前应把长木板右端垫高'),
  QuestionAuditOption(label: 'C', content: '砂桶总质量应远小于小车质量'),
  QuestionAuditOption(label: 'D', content: '纸带上相邻计数点时间间隔为 0.02 s'),
];

const String _defaultSolution = '对纸带上的点迹逐差可得加速度，再与砂桶重力比较，故 A 正确。';

/// 造一行默认「干净」题目；覆盖参数时自己保证其他字段仍自洽。
QuestionAuditRow _row({
  String questionId = 'q-1',
  int? serialNo = 1,
  String stem = _defaultStem,
  String? answer = 'A',
  String? solution = _defaultSolution,
  String questionType = 'single_choice',
  String subjectKey = 'physics',
  String sourceLevel = 'gaokao',
  String? sourceLabel = '2024 湖南师大附中月考',
  int? year = 2024,
  double? difficulty = 5,
  double? aiQuality = 0.8,
  String? stemFingerprint,
  List<QuestionAuditOption>? options,
  List<String> knowledgePointIds = const <String>['kp-newton'],
  int imageCount = 2,
  String state = 'structured',
}) =>
    QuestionAuditRow(
      questionId: questionId,
      serialNo: serialNo,
      stem: stem,
      answer: answer,
      solution: solution,
      questionType: questionType,
      subjectKey: subjectKey,
      sourceLevel: sourceLevel,
      sourceLabel: sourceLabel,
      year: year,
      difficulty: difficulty,
      aiQuality: aiQuality,
      stemFingerprint: stemFingerprint,
      options: options ?? _defaultOptions,
      knowledgePointIds: knowledgePointIds,
      imageCount: imageCount,
      state: state,
    );

QuestionAuditReport _audit(
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

QuestionAuditReport _auditOne(
  QuestionAuditRow row, {
  int currentYear = kQuestionAuditDefaultCurrentYear,
  Set<String> knownSubjectKeys = const <String>{},
  Set<String> knownSourceLevels = const <String>{},
  double minDifficulty = kQuestionAuditMinDifficulty,
  double maxDifficulty = kQuestionAuditMaxDifficulty,
}) =>
    _audit(
      <QuestionAuditRow>[row],
      currentYear: currentYear,
      knownSubjectKeys: knownSubjectKeys,
      knownSourceLevels: knownSourceLevels,
      minDifficulty: minDifficulty,
      maxDifficulty: maxDifficulty,
    );

List<String> _codes(QuestionAuditReport report) => <String>[
      for (final finding in report.findings) finding.code,
    ];

bool _has(QuestionAuditReport report, String code) =>
    report.findings.any((finding) => finding.code == code);

QuestionAuditFinding _findingOf(
  QuestionAuditReport report,
  String code, {
  String? questionId,
}) =>
    report.findings.firstWhere(
      (finding) =>
          finding.code == code &&
          (questionId == null || finding.questionId == questionId),
    );

void main() {
  group('干净基线', () {
    test('干净题零 finding，报告 isClean', () {
      final report = _auditOne(_row());
      expect(report.findings, isEmpty);
      expect(report.isClean, isTrue);
      expect(report.errorCount, 0);
      expect(report.warningCount, 0);
      expect(report.infoCount, 0);
      expect(report.counts[QuestionAuditSeverity.error], 0);
      expect(report.findingsFor('q-1'), isEmpty);
      expect(report.bySeverity(QuestionAuditSeverity.warning), isEmpty);
    });

    test('顶层函数 auditQuestionIntake 与类入口结果一致', () {
      final viaClass = _auditOne(_row());
      final viaFunction = auditQuestionIntake(<QuestionAuditRow>[_row()]);
      expect(_codes(viaFunction), _codes(viaClass));
      expect(viaFunction.isClean, viaClass.isClean);
    });

    test('auditRow 只做行内检查：不算跨行重复', () {
      final rows = <QuestionAuditRow>[
        _row(questionId: 'q-1', serialNo: 1),
        _row(questionId: 'q-2', serialNo: 2),
      ];
      final batch = _audit(rows);
      expect(_codes(batch), contains(QuestionAuditCodes.h4DuplicateStem));
      final single = const QuestionIntakeAudit().auditRow(rows.first);
      expect(
        single.map((finding) => finding.code),
        isNot(contains(QuestionAuditCodes.h4DuplicateStem)),
      );
    });
  });

  group('H1 题干', () {
    test('空题干 error', () {
      final report = _auditOne(_row(stem: ''));
      final finding = _findingOf(report, QuestionAuditCodes.h1StemEmpty);
      expect(finding.severity, QuestionAuditSeverity.error);
      expect(finding.evidence['stem_length'], '0');
    });

    test('全空白题干也算空', () {
      expect(
        _has(_auditOne(_row(stem: '   \n\t ')), QuestionAuditCodes.h1StemEmpty),
        isTrue,
      );
    });

    test('5 字符题干 warning，6 字符恰好不报', () {
      final short = _auditOne(_row(stem: '12345'));
      final finding = _findingOf(short, QuestionAuditCodes.h1StemTooShort);
      expect(finding.severity, QuestionAuditSeverity.warning);
      expect(finding.evidence['stem_length'], '5');
      expect(finding.evidence['min_stem_chars'], '6');

      final boundary = _auditOne(_row(stem: '123456'));
      expect(_has(boundary, QuestionAuditCodes.h1StemTooShort), isFalse);
      expect(boundary.isClean, isTrue);
    });

    test('空白不计入题干长度', () {
      final report = _auditOne(_row(stem: '  1  2  3  '));
      expect(_has(report, QuestionAuditCodes.h1StemTooShort), isTrue);
    });

    test('题干说「如图」但图丢失 → h1_figure_missing', () {
      final report = _auditOne(
        _row(stem: '如图甲所示，滑块沿斜面下滑，求滑到底端时的速度大小。', imageCount: 0),
      );
      final finding = _findingOf(report, QuestionAuditCodes.h1FigureMissing);
      expect(finding.severity, QuestionAuditSeverity.warning);
      expect(finding.evidence['image_count'], '0');
      expect(finding.evidence['matched'], '如图');
    });

    test('有图时不报 figure_missing；「下图」同样识别', () {
      final withImage = _auditOne(
        _row(stem: '如图甲所示，滑块沿斜面下滑，求滑到底端时的速度大小。', imageCount: 2),
      );
      expect(_has(withImage, QuestionAuditCodes.h1FigureMissing), isFalse);

      final figure = _auditOne(
        _row(stem: '下图中滑块与斜面间的动摩擦因数是多少？', imageCount: 0),
      );
      expect(_has(figure, QuestionAuditCodes.h1FigureMissing), isTrue);
    });

    test('无图字样且 imageCount=0 不报', () {
      expect(
        _has(
            _auditOne(_row(imageCount: 0)), QuestionAuditCodes.h1FigureMissing),
        isFalse,
      );
    });
  });

  group('H1 选项体系', () {
    test('选择题只有 1 个选项 error', () {
      final report = _auditOne(
        _row(
          options: const <QuestionAuditOption>[
            QuestionAuditOption(label: 'A', content: '唯一选项', isCorrect: true),
          ],
        ),
      );
      final finding =
          _findingOf(report, QuestionAuditCodes.h1ChoiceOptionsTooFew);
      expect(finding.severity, QuestionAuditSeverity.error);
      expect(finding.evidence['option_count'], '1');
    });

    test('选择题 0 个选项：too_few + 没有正确标记', () {
      final report = _auditOne(
        _row(options: const <QuestionAuditOption>[], answer: null),
      );
      expect(_has(report, QuestionAuditCodes.h1ChoiceOptionsTooFew), isTrue);
      expect(_has(report, QuestionAuditCodes.h1SingleChoiceNoCorrect), isTrue);
    });

    test('选项标签重复 error', () {
      final report = _auditOne(
        _row(
          options: const <QuestionAuditOption>[
            QuestionAuditOption(label: 'A', content: '甲', isCorrect: true),
            QuestionAuditOption(label: 'A', content: '乙'),
            QuestionAuditOption(label: 'B', content: '丙'),
            QuestionAuditOption(label: 'C', content: '丁'),
          ],
        ),
      );
      final finding =
          _findingOf(report, QuestionAuditCodes.h1OptionLabelDuplicate);
      expect(finding.severity, QuestionAuditSeverity.error);
      expect(finding.evidence['duplicated_labels'], 'A');
    });

    test('选项标签非连续 warning（A/B/D）', () {
      final report = _auditOne(
        _row(
          options: const <QuestionAuditOption>[
            QuestionAuditOption(label: 'A', content: '甲', isCorrect: true),
            QuestionAuditOption(label: 'B', content: '乙'),
            QuestionAuditOption(label: 'D', content: '丙'),
          ],
        ),
      );
      final finding =
          _findingOf(report, QuestionAuditCodes.h1OptionLabelNotSequential);
      expect(finding.severity, QuestionAuditSeverity.warning);
      expect(finding.evidence['labels'], 'A,B,D');
      expect(finding.evidence['expected'], 'A,B,C');
    });

    test('小写标签归一化后不报重复/非连续', () {
      final report = _auditOne(
        _row(
          options: const <QuestionAuditOption>[
            QuestionAuditOption(label: 'a', content: '甲', isCorrect: true),
            QuestionAuditOption(label: 'b', content: '乙'),
            QuestionAuditOption(label: 'c', content: '丙'),
            QuestionAuditOption(label: 'd', content: '丁'),
          ],
        ),
      );
      expect(_has(report, QuestionAuditCodes.h1OptionLabelDuplicate), isFalse);
      expect(
        _has(report, QuestionAuditCodes.h1OptionLabelNotSequential),
        isFalse,
      );
    });

    test('选项内容为空 warning，证据带标签', () {
      final report = _auditOne(
        _row(
          options: const <QuestionAuditOption>[
            QuestionAuditOption(label: 'A', content: '甲', isCorrect: true),
            QuestionAuditOption(label: 'B', content: '   '),
            QuestionAuditOption(label: 'C', content: '丙'),
            QuestionAuditOption(label: 'D', content: '丁'),
          ],
        ),
      );
      final finding =
          _findingOf(report, QuestionAuditCodes.h1OptionContentEmpty);
      expect(finding.severity, QuestionAuditSeverity.warning);
      expect(finding.evidence['empty_content_labels'], 'B');
    });

    test('单选无正确标记 error；同时 H2 报「有答案无标记」', () {
      final report = _auditOne(
        _row(
          options: const <QuestionAuditOption>[
            QuestionAuditOption(label: 'A', content: '甲'),
            QuestionAuditOption(label: 'B', content: '乙'),
            QuestionAuditOption(label: 'C', content: '丙'),
            QuestionAuditOption(label: 'D', content: '丁'),
          ],
        ),
      );
      final h1 = _findingOf(report, QuestionAuditCodes.h1SingleChoiceNoCorrect);
      expect(h1.severity, QuestionAuditSeverity.error);
      expect(
        _has(report, QuestionAuditCodes.h2AnswerWithoutCorrectMark),
        isTrue,
      );
    });

    test('单选标 2 个正确 error；H2 不重复报矛盾', () {
      final report = _auditOne(
        _row(
          options: const <QuestionAuditOption>[
            QuestionAuditOption(label: 'A', content: '甲', isCorrect: true),
            QuestionAuditOption(label: 'B', content: '乙', isCorrect: true),
            QuestionAuditOption(label: 'C', content: '丙'),
            QuestionAuditOption(label: 'D', content: '丁'),
          ],
        ),
      );
      final finding = _findingOf(
        report,
        QuestionAuditCodes.h1SingleChoiceMultipleCorrect,
      );
      expect(finding.severity, QuestionAuditSeverity.error);
      expect(finding.evidence['correct_count'], '2');
      expect(
        _has(report, QuestionAuditCodes.h2AnswerConflictsCorrectMark),
        isFalse,
      );
    });

    test('多选无正确标记 error', () {
      final report = _auditOne(
        _row(
          questionType: 'multi_choice',
          answer: 'A',
          options: const <QuestionAuditOption>[
            QuestionAuditOption(label: 'A', content: '甲'),
            QuestionAuditOption(label: 'B', content: '乙'),
            QuestionAuditOption(label: 'C', content: '丙'),
            QuestionAuditOption(label: 'D', content: '丁'),
          ],
        ),
      );
      final finding =
          _findingOf(report, QuestionAuditCodes.h1MultiChoiceNoCorrect);
      expect(finding.severity, QuestionAuditSeverity.error);
    });

    test('非选择题不套用选项判据', () {
      final report = _auditOne(
        _row(
          questionType: 'fill_blank',
          answer: 'DNA',
          options: const <QuestionAuditOption>[],
        ),
      );
      final codes = _codes(report);
      expect(codes, isNot(contains(QuestionAuditCodes.h1ChoiceOptionsTooFew)));
      expect(codes, isNot(contains(QuestionAuditCodes.h4SerialMissing)));
    });
  });

  group('H2 答案/解析', () {
    test('答案缺失 warning；解析缺失 warning', () {
      final missingAnswer = _auditOne(_row(answer: null));
      expect(
        _findingOf(missingAnswer, QuestionAuditCodes.h2AnswerMissing).severity,
        QuestionAuditSeverity.warning,
      );
      final missingSolution = _auditOne(_row(solution: null));
      expect(
        _findingOf(missingSolution, QuestionAuditCodes.h2SolutionMissing)
            .severity,
        QuestionAuditSeverity.warning,
      );
    });

    test('空字符串答案/解析同样按缺失处理', () {
      expect(
        _has(
            _auditOne(_row(answer: '   ')), QuestionAuditCodes.h2AnswerMissing),
        isTrue,
      );
      expect(
        _has(
          _auditOne(_row(solution: '  ')),
          QuestionAuditCodes.h2SolutionMissing,
        ),
        isTrue,
      );
    });

    test('解析与答案相同（忽略空白）→ solution_equals_answer', () {
      final report = _auditOne(_row(answer: 'A', solution: ' A '));
      expect(
        _findingOf(report, QuestionAuditCodes.h2SolutionEqualsAnswer).severity,
        QuestionAuditSeverity.warning,
      );
    });

    test('答案不是选项字母（E / 略）→ answer_not_in_options error', () {
      final notLetter = _auditOne(_row(answer: 'E'));
      expect(
        _findingOf(notLetter, QuestionAuditCodes.h2AnswerNotInOptions).severity,
        QuestionAuditSeverity.error,
      );
      final noLetter = _auditOne(_row(answer: '略'));
      expect(
        _has(noLetter, QuestionAuditCodes.h2AnswerNotInOptions),
        isTrue,
      );
    });

    test('答案与正确标记矛盾 error', () {
      final report = _auditOne(
        _row(
          answer: 'A',
          options: const <QuestionAuditOption>[
            QuestionAuditOption(label: 'A', content: '甲'),
            QuestionAuditOption(label: 'B', content: '乙', isCorrect: true),
            QuestionAuditOption(label: 'C', content: '丙'),
            QuestionAuditOption(label: 'D', content: '丁'),
          ],
        ),
      );
      final finding = _findingOf(
        report,
        QuestionAuditCodes.h2AnswerConflictsCorrectMark,
      );
      expect(finding.severity, QuestionAuditSeverity.error);
      expect(finding.evidence['answer_labels'], 'A');
      expect(finding.evidence['correct_labels'], 'B');
    });

    test('多选答案漏掉一个正确标记也算矛盾', () {
      final report = _auditOne(
        _row(
          questionType: 'multi_choice',
          answer: 'AB',
          options: const <QuestionAuditOption>[
            QuestionAuditOption(label: 'A', content: '甲', isCorrect: true),
            QuestionAuditOption(label: 'B', content: '乙'),
            QuestionAuditOption(label: 'C', content: '丙', isCorrect: true),
            QuestionAuditOption(label: 'D', content: '丁'),
          ],
        ),
      );
      final finding = _findingOf(
        report,
        QuestionAuditCodes.h2AnswerConflictsCorrectMark,
      );
      expect(finding.evidence['answer_labels'], 'A、B');
      expect(finding.evidence['correct_labels'], 'A,C');
    });

    test('小写答案与正确标记一致时不报矛盾', () {
      final report = _auditOne(_row(answer: 'a'));
      expect(
        _has(report, QuestionAuditCodes.h2AnswerConflictsCorrectMark),
        isFalse,
      );
      expect(report.isClean, isTrue);
    });

    test('多选答案 A/B 与标记 A/B 一致', () {
      final report = _auditOne(
        _row(
          questionType: 'multi_choice',
          answer: 'A、B',
          options: const <QuestionAuditOption>[
            QuestionAuditOption(label: 'A', content: '甲', isCorrect: true),
            QuestionAuditOption(label: 'B', content: '乙', isCorrect: true),
            QuestionAuditOption(label: 'C', content: '丙'),
            QuestionAuditOption(label: 'D', content: '丁'),
          ],
        ),
      );
      expect(report.findings, isEmpty);
    });
  });

  group('H3 元信息', () {
    test('难度 0 报越界、1 与 10 不报、10.1 报', () {
      expect(
        _has(
          _auditOne(_row(difficulty: 0)),
          QuestionAuditCodes.h3DifficultyOutOfRange,
        ),
        isTrue,
      );
      expect(_auditOne(_row(difficulty: 1)).isClean, isTrue);
      expect(_auditOne(_row(difficulty: 10)).isClean, isTrue);
      expect(
        _has(
          _auditOne(_row(difficulty: 10.1)),
          QuestionAuditCodes.h3DifficultyOutOfRange,
        ),
        isTrue,
      );
    });

    test('难度可注入 0–1 归一化区间', () {
      expect(
        _auditOne(_row(difficulty: 0), minDifficulty: 0, maxDifficulty: 1)
            .isClean,
        isTrue,
      );
      expect(
        _has(
          _auditOne(
            _row(difficulty: 1.5),
            minDifficulty: 0,
            maxDifficulty: 1,
          ),
          QuestionAuditCodes.h3DifficultyOutOfRange,
        ),
        isTrue,
      );
    });

    test('难度空值不报；NaN 报越界', () {
      expect(_auditOne(_row(difficulty: null)).isClean, isTrue);
      expect(
        _has(
          _auditOne(_row(difficulty: double.nan)),
          QuestionAuditCodes.h3DifficultyOutOfRange,
        ),
        isTrue,
      );
    });

    test('年份边界：1899 报、1900 不报、currentYear+1 不报、+2 报', () {
      expect(
        _has(_auditOne(_row(year: 1899)), QuestionAuditCodes.h3YearOutOfRange),
        isTrue,
      );
      expect(_auditOne(_row(year: 1900)).isClean, isTrue);
      expect(
        _auditOne(_row(year: kQuestionAuditDefaultCurrentYear + 1)).isClean,
        isTrue,
      );
      expect(
        _has(
          _auditOne(_row(year: kQuestionAuditDefaultCurrentYear + 2)),
          QuestionAuditCodes.h3YearOutOfRange,
        ),
        isTrue,
      );
    });

    test('年份检查用注入的 currentYear', () {
      final report = _auditOne(_row(year: 2031), currentYear: 2030);
      expect(report.isClean, isTrue);
      expect(
        _has(
          _audit(_rowList(_row(year: 2032)), currentYear: 2030),
          QuestionAuditCodes.h3YearOutOfRange,
        ),
        isTrue,
      );
    });

    test('学科为空 warning', () {
      final finding = _findingOf(
        _auditOne(_row(subjectKey: ' ')),
        QuestionAuditCodes.h3SubjectMissing,
      );
      expect(finding.severity, QuestionAuditSeverity.warning);
    });

    test('已知学科集合注入后未知学科报 warning', () {
      final report = _auditOne(
        _row(subjectKey: 'math'),
        knownSubjectKeys: const <String>{'physics'},
      );
      expect(_has(report, QuestionAuditCodes.h3SubjectUnknown), isTrue);
      final ok = _auditOne(
        _row(subjectKey: 'physics'),
        knownSubjectKeys: const <String>{'physics'},
      );
      expect(ok.isClean, isTrue);
    });

    test('默认不给已知学科集合时跳过 unknown 检查', () {
      final report = _auditOne(_row(subjectKey: 'math'));
      expect(_has(report, QuestionAuditCodes.h3SubjectUnknown), isFalse);
    });

    test('来源分级未知且来源说明空才报', () {
      final unknown = _auditOne(
        _row(sourceLevel: 'no_such_level', sourceLabel: null),
        knownSourceLevels: const <String>{'gaokao'},
      );
      expect(_has(unknown, QuestionAuditCodes.h3SourceLevelUnknown), isTrue);

      final withLabel = _auditOne(
        _row(sourceLevel: 'no_such_level', sourceLabel: '2023 某校月考'),
        knownSourceLevels: const <String>{'gaokao'},
      );
      expect(_has(withLabel, QuestionAuditCodes.h3SourceLevelUnknown), isFalse);

      final known = _auditOne(
        _row(sourceLevel: 'gaokao', sourceLabel: null),
        knownSourceLevels: const <String>{'gaokao'},
      );
      expect(known.isClean, isTrue);
    });

    test('默认来源分级集合为空时跳过检查', () {
      final report = _auditOne(_row(sourceLevel: 'no_such_level'));
      expect(_has(report, QuestionAuditCodes.h3SourceLevelUnknown), isFalse);
    });

    test('aiQuality 越界与边界', () {
      expect(_auditOne(_row(aiQuality: 0)).isClean, isTrue);
      expect(_auditOne(_row(aiQuality: 1)).isClean, isTrue);
      expect(_auditOne(_row(aiQuality: null)).isClean, isTrue);
      for (final bad in <double>[-0.1, 1.2, double.nan]) {
        expect(
          _has(
            _auditOne(_row(aiQuality: bad)),
            QuestionAuditCodes.h3AiQualityOutOfRange,
          ),
          isTrue,
          reason: 'aiQuality=$bad 应越界',
        );
      }
    });
  });

  group('H4 跨行重复', () {
    test('同题干不同标点/空白 → 两边都报，matched_by=stem', () {
      const first = '一物体从斜面顶端由静止滑下，求滑到底端时的速度大小，已知斜面长 L、倾角 θ。';
      const second = '一物体从斜面顶端由静止滑下, 求滑到底端时的速度大小, 已知斜面长L、倾角θ';
      final report = _audit(<QuestionAuditRow>[
        _row(questionId: 'q-1', serialNo: 1, stem: first),
        _row(questionId: 'q-2', serialNo: 2, stem: second),
      ]);
      final one = _findingOf(
        report,
        QuestionAuditCodes.h4DuplicateStem,
        questionId: 'q-1',
      );
      final two = _findingOf(
        report,
        QuestionAuditCodes.h4DuplicateStem,
        questionId: 'q-2',
      );
      expect(one.evidence['other_question_ids'], 'q-2');
      expect(one.evidence['matched_by'], 'stem');
      expect(two.evidence['other_question_ids'], 'q-1');
      expect(one.severity, QuestionAuditSeverity.error);
    });

    test('指纹相同但题干不同也报，matched_by=fingerprint', () {
      final report = _audit(<QuestionAuditRow>[
        _row(questionId: 'q-1', stemFingerprint: 'fp-abc'),
        _row(
          questionId: 'q-2',
          stem: '另一个完全不同的题干，用于验证指纹分组不依赖文本归一化。',
          stemFingerprint: 'fp-abc',
        ),
      ]);
      final finding = _findingOf(
        report,
        QuestionAuditCodes.h4DuplicateStem,
        questionId: 'q-1',
      );
      expect(finding.evidence['matched_by'], 'fingerprint');
      expect(finding.evidence['other_question_ids'], 'q-2');
    });

    test('题干与指纹都相同 → matched_by=both', () {
      final report = _audit(<QuestionAuditRow>[
        _row(questionId: 'q-1', stemFingerprint: 'fp-same'),
        _row(questionId: 'q-2', stemFingerprint: 'fp-same'),
      ]);
      expect(
        _findingOf(report, QuestionAuditCodes.h4DuplicateStem,
                questionId: 'q-1')
            .evidence['matched_by'],
        'both',
      );
    });

    test('三道同题干：每行证据列出另外两道', () {
      final report = _audit(<QuestionAuditRow>[
        _row(questionId: 'q-1', serialNo: 1),
        _row(questionId: 'q-2', serialNo: 2),
        _row(questionId: 'q-3', serialNo: 3),
      ]);
      final first = _findingOf(
        report,
        QuestionAuditCodes.h4DuplicateStem,
        questionId: 'q-1',
      );
      expect(first.evidence['other_question_ids'], 'q-2,q-3');
      expect(
          report.findings
              .where((f) => f.code == QuestionAuditCodes.h4DuplicateStem),
          hasLength(3));
    });

    test('空题干不参与重复分组', () {
      final report = _audit(<QuestionAuditRow>[
        _row(questionId: 'q-1', stem: ''),
        _row(questionId: 'q-2', stem: '   '),
      ]);
      expect(_has(report, QuestionAuditCodes.h4DuplicateStem), isFalse);
      expect(_has(report, QuestionAuditCodes.h1StemEmpty), isTrue);
    });

    test('重复题目编号 error，证据带 TR 编号', () {
      final report = _audit(<QuestionAuditRow>[
        _row(questionId: 'q-1', serialNo: 7),
        _row(questionId: 'q-2', serialNo: 7),
      ]);
      final finding = _findingOf(
        report,
        QuestionAuditCodes.h4DuplicateSerial,
        questionId: 'q-1',
      );
      expect(finding.severity, QuestionAuditSeverity.error);
      expect(finding.evidence['serial_label'], 'TR-00007');
      expect(finding.evidence['other_question_ids'], 'q-2');
      expect(finding.messageZh, contains('TR-00007'));
    });

    test('serialNo 缺失/0/负数都报 info', () {
      expect(
        _findingOf(
          _auditOne(_row(serialNo: null)),
          QuestionAuditCodes.h4SerialMissing,
        ).severity,
        QuestionAuditSeverity.info,
      );
      for (final bad in <int>[0, -3]) {
        expect(
          _has(
            _auditOne(_row(serialNo: bad)),
            QuestionAuditCodes.h4SerialMissing,
          ),
          isTrue,
          reason: 'serialNo=$bad',
        );
      }
    });
  });

  group('本地点', () {
    test('没有关联知识点报 info；空白 id 过滤后为空也报', () {
      expect(
        _findingOf(
          _auditOne(_row(knowledgePointIds: const <String>[])),
          QuestionAuditCodes.localNoKnowledgePoints,
        ).severity,
        QuestionAuditSeverity.info,
      );
      expect(
        _has(
          _auditOne(_row(knowledgePointIds: const <String>['  ', ''])),
          QuestionAuditCodes.localNoKnowledgePoints,
        ),
        isTrue,
      );
      expect(
        _auditOne(_row(knowledgePointIds: const <String>['kp-a'])).isClean,
        isTrue,
      );
    });
  });

  group('报告结构与排序', () {
    test('计数与 findingsFor/bySeverity 口径一致', () {
      final report = _audit(<QuestionAuditRow>[
        _row(questionId: 'qa', answer: null, serialNo: null),
        _row(questionId: 'qb', stem: ''),
      ]);
      expect(report.errorCount, 1);
      expect(report.warningCount, 1);
      expect(report.infoCount, 1);
      expect(report.counts[QuestionAuditSeverity.error], 1);
      expect(report.bySeverity(QuestionAuditSeverity.warning), hasLength(1));
      expect(
        report.findingsFor('qa').map((f) => f.code),
        contains(QuestionAuditCodes.h2AnswerMissing),
      );
      expect(report.findingsFor('nope'), isEmpty);
    });

    test('排序：questionId 升序 → 严重度 → code 升序', () {
      final report = _audit(<QuestionAuditRow>[
        _row(
          questionId: 'q-1',
          answer: null,
          difficulty: 0,
          subjectKey: '',
          serialNo: null,
          knowledgePointIds: const <String>[],
        ),
        _row(questionId: 'q-2', stem: ''),
      ]);
      expect(_codes(report), <String>[
        QuestionAuditCodes.h2AnswerMissing,
        QuestionAuditCodes.h3DifficultyOutOfRange,
        QuestionAuditCodes.h3SubjectMissing,
        QuestionAuditCodes.h4SerialMissing,
        QuestionAuditCodes.localNoKnowledgePoints,
        QuestionAuditCodes.h1StemEmpty,
      ]);
    });

    test('同输入两次审计序列完全一致（确定性）', () {
      final rows = <QuestionAuditRow>[
        _row(questionId: 'q-2', stem: ''),
        _row(questionId: 'q-1', answer: null),
        _row(questionId: 'q-3', difficulty: 0),
      ];
      String print(QuestionAuditReport report) => _codes(report).join('|');
      expect(print(_audit(rows)), print(_audit(rows)));
    });

    test('report.findings 不可修改', () {
      final report = _auditOne(_row(difficulty: 0));
      expect(
        () => report.findings.add(report.findings.first),
        throwsUnsupportedError,
      );
    });

    test('finding.toJson / 严重度中文名', () {
      final finding = _findingOf(
        _auditOne(_row(difficulty: 0)),
        QuestionAuditCodes.h3DifficultyOutOfRange,
      );
      final json = finding.toJson();
      expect(json['question_id'], 'q-1');
      expect(json['code'], QuestionAuditCodes.h3DifficultyOutOfRange);
      expect(json['severity'], 'warning');
      expect(finding.severity.labelZh, '警告');
      expect(QuestionAuditSeverity.error.labelZh, '错误');
      expect(QuestionAuditSeverity.info.labelZh, '提示');
    });
  });

  test('每条判据 code 都至少有一例触发（26 条全覆盖）', () {
    expect(QuestionAuditCodes.all, hasLength(26));
    expect(QuestionAuditCodes.all.toSet(), hasLength(26));

    const noCorrect = <QuestionAuditOption>[
      QuestionAuditOption(label: 'A', content: '甲'),
      QuestionAuditOption(label: 'B', content: '乙'),
      QuestionAuditOption(label: 'C', content: '丙'),
      QuestionAuditOption(label: 'D', content: '丁'),
    ];

    final rows = <QuestionAuditRow>[
      _row(questionId: 'c01', serialNo: 1, stem: ''),
      _row(questionId: 'c02', serialNo: 2, stem: 'abc'),
      _row(
        questionId: 'c03',
        serialNo: 3,
        options: const <QuestionAuditOption>[
          QuestionAuditOption(label: 'A', content: '唯一', isCorrect: true),
        ],
      ),
      _row(
        questionId: 'c04',
        serialNo: 4,
        options: const <QuestionAuditOption>[
          QuestionAuditOption(label: 'A', content: '甲', isCorrect: true),
          QuestionAuditOption(label: 'A', content: '乙'),
          QuestionAuditOption(label: 'B', content: '丙'),
        ],
      ),
      _row(
        questionId: 'c05',
        serialNo: 5,
        options: const <QuestionAuditOption>[
          QuestionAuditOption(label: 'A', content: '甲', isCorrect: true),
          QuestionAuditOption(label: 'B', content: '乙'),
          QuestionAuditOption(label: 'D', content: '丙'),
        ],
      ),
      _row(
        questionId: 'c06',
        serialNo: 6,
        options: const <QuestionAuditOption>[
          QuestionAuditOption(label: 'A', content: '', isCorrect: true),
          QuestionAuditOption(label: 'B', content: '乙'),
          QuestionAuditOption(label: 'C', content: '丙'),
          QuestionAuditOption(label: 'D', content: '丁'),
        ],
      ),
      _row(questionId: 'c07', serialNo: 7, options: noCorrect),
      _row(
        questionId: 'c08',
        serialNo: 8,
        options: const <QuestionAuditOption>[
          QuestionAuditOption(label: 'A', content: '甲', isCorrect: true),
          QuestionAuditOption(label: 'B', content: '乙', isCorrect: true),
          QuestionAuditOption(label: 'C', content: '丙'),
        ],
      ),
      _row(
        questionId: 'c09',
        serialNo: 9,
        questionType: 'multi_choice',
        options: noCorrect,
      ),
      _row(
        questionId: 'c10',
        serialNo: 10,
        stem: '如图甲所示，滑块沿斜面下滑，求滑到底端时的速度大小。',
        imageCount: 0,
      ),
      _row(questionId: 'c11', serialNo: 11, answer: null),
      _row(questionId: 'c12', serialNo: 12, solution: null),
      _row(questionId: 'c13', serialNo: 13, answer: 'A', solution: 'A'),
      _row(questionId: 'c14', serialNo: 14, answer: 'E'),
      _row(
        questionId: 'c15',
        serialNo: 15,
        answer: 'A',
        options: const <QuestionAuditOption>[
          QuestionAuditOption(label: 'A', content: '甲'),
          QuestionAuditOption(label: 'B', content: '乙', isCorrect: true),
        ],
      ),
      _row(questionId: 'c17', serialNo: 17, difficulty: 0),
      _row(questionId: 'c18', serialNo: 18, year: 1899),
      _row(questionId: 'c19', serialNo: 19, subjectKey: ''),
      _row(questionId: 'c20', serialNo: 20, subjectKey: 'math'),
      _row(
        questionId: 'c21',
        serialNo: 21,
        sourceLevel: 'no_such_level',
        sourceLabel: '',
      ),
      _row(questionId: 'c22', serialNo: 22, aiQuality: 1.5),
      _row(questionId: 'c23', serialNo: 23, stem: '同批重复题干，用于覆盖重复判据，第一行内容足够长。'),
      _row(questionId: 'c24', serialNo: 24, stem: '同批重复题干，用于覆盖重复判据，第一行内容足够长。'),
      _row(questionId: 'c25', serialNo: 40),
      _row(questionId: 'c26', serialNo: 40),
      _row(questionId: 'c27', serialNo: null),
      _row(
          questionId: 'c28', serialNo: 28, knowledgePointIds: const <String>[]),
    ];

    final report = _audit(
      rows,
      knownSubjectKeys: const <String>{'physics'},
      knownSourceLevels: const <String>{'gaokao', 'unknown'},
    );
    final codes = _codes(report).toSet();
    expect(codes, containsAll(QuestionAuditCodes.all));
    for (final code in QuestionAuditCodes.all) {
      expect(codes, contains(code), reason: 'code=$code 没有被任何用例触发');
    }
    for (final finding in report.findings) {
      expect(QuestionAuditCodes.all, contains(finding.code));
    }
  });
}

/// 把单行包成 list（少数需要注入 currentYear 的写法用）。
List<QuestionAuditRow> _rowList(QuestionAuditRow row) =>
    <QuestionAuditRow>[row];
