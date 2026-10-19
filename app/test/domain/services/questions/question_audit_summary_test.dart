import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/questions/question_audit_summary.dart';
import 'package:furnace/domain/services/questions/question_intake_audit.dart';

QuestionAuditFinding _finding(
  String questionId,
  String code,
  QuestionAuditSeverity severity,
) =>
    QuestionAuditFinding(
      questionId: questionId,
      code: code,
      severity: severity,
      messageZh: '说明',
    );

QuestionAuditReport _report(List<QuestionAuditFinding> findings) =>
    QuestionAuditReport(findings: findings);

QuestionAuditReport _cleanReport() =>
    const QuestionAuditReport(findings: <QuestionAuditFinding>[]);

List<String> _codesOf(QuestionAuditSummary summary) => <String>[
      for (final count in summary.codeCounts) count.code,
    ];

List<String> _offenderIds(QuestionAuditSummary summary) => <String>[
      for (final offender in summary.topOffenders) offender.questionId,
    ];

void main() {
  group('空输入与 empty 常量', () {
    test('空输入返回零值、不抛', () {
      final summary = QuestionAuditSummary.summarize(
        const <QuestionAuditReport>[],
      );
      expect(summary.questionCount, 0);
      expect(summary.cleanQuestionCount, 0);
      expect(summary.dirtyQuestionCount, 0);
      expect(summary.cleanRatio, 0);
      expect(summary.findingCount, 0);
      expect(summary.codeCounts, isEmpty);
      expect(summary.topOffenders, isEmpty);
      expect(summary.truncatedOffenderCount, 0);
      expect(summary.isEmpty, isTrue);
      expect(summary.isClean, isTrue);
    });

    test('空输入的 toJson 三档计数全 0', () {
      final json = QuestionAuditSummary.summarize(
        const <QuestionAuditReport>[],
      ).toJson();
      expect(json['question_count'], 0);
      expect(json['clean_ratio'], 0);
      expect(json['findings_by_severity'], <String, int>{
        'error': 0,
        'warning': 0,
        'info': 0,
      });
      expect(json['is_empty'], isTrue);
      expect(json['is_clean'], isTrue);
    });

    test('空输入与 QuestionAuditSummary.empty 序列化一致', () {
      final summary = QuestionAuditSummary.summarize(
        <QuestionAuditReport>[],
      );
      expect(
        jsonEncode(summary.toJson()),
        jsonEncode(QuestionAuditSummary.empty.toJson()),
      );
    });

    test('空输入配负数截断参数也不抛', () {
      final summary = QuestionAuditSummary.summarize(
        const <QuestionAuditReport>[],
        maxOffenders: -3,
        maxSampleQuestionIds: -1,
      );
      expect(summary.isEmpty, isTrue);
      expect(summary.topOffenders, isEmpty);
    });
  });

  group('全干净', () {
    test('三道干净题：比例 1、没有判据与 offender', () {
      final summary = QuestionAuditSummary.summarize(
        <QuestionAuditReport>[
          _cleanReport(),
          _cleanReport(),
          _cleanReport(),
        ],
      );
      expect(summary.questionCount, 3);
      expect(summary.cleanQuestionCount, 3);
      expect(summary.dirtyQuestionCount, 0);
      expect(summary.cleanRatio, 1);
      expect(summary.findingsBySeverity[QuestionAuditSeverity.error], 0);
      expect(summary.codeCounts, isEmpty);
      expect(summary.topOffenders, isEmpty);
      expect(summary.truncatedOffenderCount, 0);
      expect(summary.isEmpty, isFalse);
      expect(summary.isClean, isTrue);
    });

    test('全干净 toJson：clean_ratio 1、is_empty false', () {
      final json = QuestionAuditSummary.summarize(
        <QuestionAuditReport>[_cleanReport()],
      ).toJson();
      expect(json['clean_ratio'], 1);
      expect(json['is_empty'], isFalse);
      expect(json['is_clean'], isTrue);
      expect(json['code_counts'], isEmpty);
    });

    test('空库与全干净都是 isClean，只有 isEmpty 不同', () {
      final empty = QuestionAuditSummary.summarize(
        const <QuestionAuditReport>[],
      );
      final allClean = QuestionAuditSummary.summarize(
        <QuestionAuditReport>[_cleanReport(), _cleanReport()],
      );
      expect(empty.isClean, isTrue);
      expect(allClean.isClean, isTrue);
      expect(empty.isEmpty, isTrue);
      expect(allClean.isEmpty, isFalse);
    });
  });

  group('混合严重度与题数口径', () {
    test('一道题同时命中三档：三档各 1、脏题 1、比例 0', () {
      final summary = QuestionAuditSummary.summarize(
        <QuestionAuditReport>[
          _report(<QuestionAuditFinding>[
            _finding('q1', QuestionAuditCodes.h1StemEmpty,
                QuestionAuditSeverity.error),
            _finding('q1', QuestionAuditCodes.h2AnswerMissing,
                QuestionAuditSeverity.warning),
            _finding('q1', QuestionAuditCodes.localNoKnowledgePoints,
                QuestionAuditSeverity.info),
          ]),
        ],
      );
      expect(summary.questionCount, 1);
      expect(summary.dirtyQuestionCount, 1);
      expect(summary.cleanQuestionCount, 0);
      expect(summary.cleanRatio, 0);
      expect(summary.errorCount, 1);
      expect(summary.warningCount, 1);
      expect(summary.infoCount, 1);
      expect(summary.findingCount, 3);
    });

    test('两干净两脏：cleanRatio 0.5、脏题 2', () {
      final summary = QuestionAuditSummary.summarize(
        <QuestionAuditReport>[
          _cleanReport(),
          _report(<QuestionAuditFinding>[
            _finding('q2', QuestionAuditCodes.h1StemEmpty,
                QuestionAuditSeverity.error),
          ]),
          _cleanReport(),
          _report(<QuestionAuditFinding>[
            _finding('q4', QuestionAuditCodes.h1StemTooShort,
                QuestionAuditSeverity.warning),
          ]),
        ],
      );
      expect(summary.questionCount, 4);
      expect(summary.cleanQuestionCount, 2);
      expect(summary.dirtyQuestionCount, 2);
      expect(summary.cleanRatio, 0.5);
      expect(summary.errorCount, 1);
      expect(summary.warningCount, 1);
      expect(summary.infoCount, 0);
    });

    test('同一题两条 error：offender errorCount 2、findingCount 2', () {
      final summary = QuestionAuditSummary.summarize(
        <QuestionAuditReport>[
          _report(<QuestionAuditFinding>[
            _finding('q1', QuestionAuditCodes.h1StemEmpty,
                QuestionAuditSeverity.error),
            _finding('q1', QuestionAuditCodes.h4DuplicateStem,
                QuestionAuditSeverity.error),
          ]),
        ],
      );
      expect(summary.findingCount, 2);
      expect(summary.topOffenders.single.errorCount, 2);
      expect(summary.topOffenders.single.warningCount, 0);
      expect(summary.topOffenders.single.infoCount, 0);
    });

    test('三档计数来自所有 report（不按题去重）', () {
      final summary = QuestionAuditSummary.summarize(
        <QuestionAuditReport>[
          _report(<QuestionAuditFinding>[
            _finding('q1', QuestionAuditCodes.h1StemEmpty,
                QuestionAuditSeverity.error),
            _finding('q1', QuestionAuditCodes.h2AnswerMissing,
                QuestionAuditSeverity.warning),
          ]),
          _report(<QuestionAuditFinding>[
            _finding('q2', QuestionAuditCodes.h2SolutionMissing,
                QuestionAuditSeverity.warning),
            _finding('q2', QuestionAuditCodes.localNoKnowledgePoints,
                QuestionAuditSeverity.info),
          ]),
        ],
      );
      expect(summary.findingsBySeverity, <QuestionAuditSeverity, int>{
        QuestionAuditSeverity.error: 1,
        QuestionAuditSeverity.warning: 2,
        QuestionAuditSeverity.info: 1,
      });
      expect(summary.findingCount, 4);
    });
  });

  group('codeCounts 聚合', () {
    test('同 code 两题：findingCount 2、questionCount 2、样例升序', () {
      final summary = QuestionAuditSummary.summarize(
        <QuestionAuditReport>[
          _report(<QuestionAuditFinding>[
            _finding('q-2', QuestionAuditCodes.h1StemEmpty,
                QuestionAuditSeverity.error),
          ]),
          _report(<QuestionAuditFinding>[
            _finding('q-1', QuestionAuditCodes.h1StemEmpty,
                QuestionAuditSeverity.error),
          ]),
        ],
      );
      final count = summary.codeCounts.single;
      expect(count.code, QuestionAuditCodes.h1StemEmpty);
      expect(count.severity, QuestionAuditSeverity.error);
      expect(count.findingCount, 2);
      expect(count.questionCount, 2);
      expect(count.sampleQuestionIds, <String>['q-1', 'q-2']);
    });

    test('同题同 code 两条：findingCount 2、questionCount 1', () {
      final summary = QuestionAuditSummary.summarize(
        <QuestionAuditReport>[
          _report(<QuestionAuditFinding>[
            _finding('q1', QuestionAuditCodes.h1StemEmpty,
                QuestionAuditSeverity.error),
            _finding('q1', QuestionAuditCodes.h1StemEmpty,
                QuestionAuditSeverity.error),
          ]),
        ],
      );
      final count = summary.codeCounts.single;
      expect(count.findingCount, 2);
      expect(count.questionCount, 1);
      expect(count.sampleQuestionIds, <String>['q1']);
    });

    test('样例题号按字符串升序（不是数字序）', () {
      final summary = QuestionAuditSummary.summarize(
        <QuestionAuditReport>[
          for (final id in <String>['q-10', 'q-2', 'q-1'])
            _report(<QuestionAuditFinding>[
              _finding(id, QuestionAuditCodes.h1StemEmpty,
                  QuestionAuditSeverity.error),
            ]),
        ],
        maxSampleQuestionIds: 10,
      );
      expect(
        summary.codeCounts.single.sampleQuestionIds,
        <String>['q-1', 'q-10', 'q-2'],
      );
    });

    test('sample 默认上限 5：六道题只留前 5 个', () {
      final summary = QuestionAuditSummary.summarize(
        <QuestionAuditReport>[
          for (var i = 1; i <= 6; i++)
            _report(<QuestionAuditFinding>[
              _finding('q$i', QuestionAuditCodes.h1StemEmpty,
                  QuestionAuditSeverity.error),
            ]),
        ],
      );
      final count = summary.codeCounts.single;
      expect(count.questionCount, 6);
      expect(count.sampleQuestionIds, <String>['q1', 'q2', 'q3', 'q4', 'q5']);
    });

    test('sample 上限可配置为 2', () {
      final summary = QuestionAuditSummary.summarize(
        <QuestionAuditReport>[
          for (final id in <String>['a', 'b', 'c'])
            _report(<QuestionAuditFinding>[
              _finding(id, QuestionAuditCodes.h1StemEmpty,
                  QuestionAuditSeverity.error),
            ]),
        ],
        maxSampleQuestionIds: 2,
      );
      expect(summary.codeCounts.single.sampleQuestionIds, <String>['a', 'b']);
    });

    test('sample 上限 0 与负数的样例为空', () {
      final zero = QuestionAuditSummary.summarize(
        <QuestionAuditReport>[
          _report(<QuestionAuditFinding>[
            _finding('q1', QuestionAuditCodes.h1StemEmpty,
                QuestionAuditSeverity.error),
          ]),
        ],
        maxSampleQuestionIds: 0,
      );
      final negative = QuestionAuditSummary.summarize(
        <QuestionAuditReport>[
          _report(<QuestionAuditFinding>[
            _finding('q1', QuestionAuditCodes.h1StemEmpty,
                QuestionAuditSeverity.error),
          ]),
        ],
        maxSampleQuestionIds: -5,
      );
      expect(zero.codeCounts.single.sampleQuestionIds, isEmpty);
      expect(negative.codeCounts.single.sampleQuestionIds, isEmpty);
    });

    test('同 code 严重度冲突时取最重一档', () {
      final summary = QuestionAuditSummary.summarize(
        <QuestionAuditReport>[
          _report(<QuestionAuditFinding>[
            _finding('q1', QuestionAuditCodes.h1StemEmpty,
                QuestionAuditSeverity.info),
            _finding('q2', QuestionAuditCodes.h1StemEmpty,
                QuestionAuditSeverity.error),
          ]),
        ],
      );
      expect(summary.codeCounts.single.severity, QuestionAuditSeverity.error);
    });

    test('codeCounts 排序：severity 优先，再 findingCount 降序', () {
      final summary = QuestionAuditSummary.summarize(
        <QuestionAuditReport>[
          _report(<QuestionAuditFinding>[
            _finding('q1', 'z_info', QuestionAuditSeverity.info),
            _finding('q1', 'a_warn', QuestionAuditSeverity.warning),
            _finding('q1', 'b_warn', QuestionAuditSeverity.warning),
            _finding('q1', 'c_error', QuestionAuditSeverity.error),
          ]),
          _report(<QuestionAuditFinding>[
            _finding('q2', 'a_warn', QuestionAuditSeverity.warning),
            _finding('q2', 'b_warn', QuestionAuditSeverity.warning),
          ]),
        ],
      );
      expect(_codesOf(summary), <String>[
        'c_error',
        'a_warn',
        'b_warn',
        'z_info',
      ]);
      expect(summary.codeCounts[1].findingCount, 2);
    });

    test('codeCounts 同严重度同条数按 questionCount 降序', () {
      final summary = QuestionAuditSummary.summarize(
        <QuestionAuditReport>[
          _report(<QuestionAuditFinding>[
            _finding('q1', 'z_many', QuestionAuditSeverity.warning),
            _finding('q1', 'a_few', QuestionAuditSeverity.warning),
            _finding('q2', 'z_many', QuestionAuditSeverity.warning),
            _finding('q3', 'z_many', QuestionAuditSeverity.warning),
            _finding('q1', 'a_few', QuestionAuditSeverity.warning),
            _finding('q1', 'a_few', QuestionAuditSeverity.warning),
          ]),
        ],
      );
      // 两个 code 都是 3 条 warning：z_many 跨 3 题、a_few 只在 1 题。
      expect(_codesOf(summary), <String>['z_many', 'a_few']);
      expect(summary.codeCounts[0].questionCount, 3);
      expect(summary.codeCounts[1].questionCount, 1);
    });
  });

  group('topOffenders', () {
    test('priorityScore = error*10 + warning*3 + info*1', () {
      final summary = QuestionAuditSummary.summarize(
        <QuestionAuditReport>[
          _report(<QuestionAuditFinding>[
            _finding('q1', QuestionAuditCodes.h1StemEmpty,
                QuestionAuditSeverity.error),
            _finding('q1', QuestionAuditCodes.h4DuplicateStem,
                QuestionAuditSeverity.error),
            _finding('q1', QuestionAuditCodes.h2AnswerMissing,
                QuestionAuditSeverity.warning),
            _finding('q1', QuestionAuditCodes.localNoKnowledgePoints,
                QuestionAuditSeverity.info),
          ]),
        ],
      );
      final offender = summary.topOffenders.single;
      expect(offender.priorityScore, 2 * 10 + 3 + 1);
      expect(offender.errorCount, 2);
      expect(offender.warningCount, 1);
      expect(offender.infoCount, 1);
    });

    test('按 priorityScore 降序', () {
      final summary = QuestionAuditSummary.summarize(
        <QuestionAuditReport>[
          _report(<QuestionAuditFinding>[
            _finding('low', QuestionAuditCodes.localNoKnowledgePoints,
                QuestionAuditSeverity.info),
          ]),
          _report(<QuestionAuditFinding>[
            _finding('high', QuestionAuditCodes.h1StemEmpty,
                QuestionAuditSeverity.error),
          ]),
        ],
      );
      expect(_offenderIds(summary), <String>['high', 'low']);
    });

    test('同分按 errorCount 降序', () {
      final summary = QuestionAuditSummary.summarize(
        <QuestionAuditReport>[
          _report(<QuestionAuditFinding>[
            _finding('q_error', 'e1', QuestionAuditSeverity.error),
            _finding('q_error', 'i1', QuestionAuditSeverity.info),
            _finding('q_error', 'i2', QuestionAuditSeverity.info),
            _finding('q_error', 'i3', QuestionAuditSeverity.info),
          ]),
          _report(<QuestionAuditFinding>[
            _finding('q_warn', 'w1', QuestionAuditSeverity.warning),
            _finding('q_warn', 'w2', QuestionAuditSeverity.warning),
            _finding('q_warn', 'w3', QuestionAuditSeverity.warning),
            _finding('q_warn', 'w4', QuestionAuditSeverity.warning),
            _finding('q_warn', 'i4', QuestionAuditSeverity.info),
          ]),
        ],
      );
      // 同分 13：q_error 有 1 条 error，q_warn 是 4 warning + 1 info。
      expect(summary.topOffenders[0].priorityScore, 13);
      expect(summary.topOffenders[1].priorityScore, 13);
      expect(_offenderIds(summary), <String>['q_error', 'q_warn']);
    });

    test('同分同 error 再按 warning 降序', () {
      final summary = QuestionAuditSummary.summarize(
        <QuestionAuditReport>[
          _report(<QuestionAuditFinding>[
            _finding('q_warn', 'e1', QuestionAuditSeverity.error),
            _finding('q_warn', 'w1', QuestionAuditSeverity.warning),
          ]),
          _report(<QuestionAuditFinding>[
            _finding('q_info', 'e2', QuestionAuditSeverity.error),
            _finding('q_info', 'i1', QuestionAuditSeverity.info),
            _finding('q_info', 'i2', QuestionAuditSeverity.info),
            _finding('q_info', 'i3', QuestionAuditSeverity.info),
          ]),
        ],
      );
      // 两边都是 13 分、都是 1 条 error：q_warn 多 1 条 warning 排前。
      expect(summary.topOffenders[0].priorityScore, 13);
      expect(summary.topOffenders[1].priorityScore, 13);
      expect(_offenderIds(summary), <String>['q_warn', 'q_info']);
    });

    test('完全同分按 questionId 升序', () {
      final summary = QuestionAuditSummary.summarize(
        <QuestionAuditReport>[
          _report(<QuestionAuditFinding>[
            _finding('q-b', QuestionAuditCodes.h1StemEmpty,
                QuestionAuditSeverity.error),
          ]),
          _report(<QuestionAuditFinding>[
            _finding('q-a', QuestionAuditCodes.h1StemEmpty,
                QuestionAuditSeverity.error),
          ]),
        ],
      );
      expect(_offenderIds(summary), <String>['q-a', 'q-b']);
    });

    test('offender 的 codes 去重且升序', () {
      final summary = QuestionAuditSummary.summarize(
        <QuestionAuditReport>[
          _report(<QuestionAuditFinding>[
            _finding('q1', 'z_code', QuestionAuditSeverity.warning),
            _finding('q1', 'a_code', QuestionAuditSeverity.warning),
            _finding('q1', 'z_code', QuestionAuditSeverity.warning),
          ]),
        ],
      );
      expect(summary.topOffenders.single.codes, <String>['a_code', 'z_code']);
    });

    test('offender 截断到 maxOffenders 并记 truncated', () {
      final summary = QuestionAuditSummary.summarize(
        <QuestionAuditReport>[
          for (var i = 0; i < 3; i++)
            _report(<QuestionAuditFinding>[
              _finding('q$i', QuestionAuditCodes.h1StemEmpty,
                  QuestionAuditSeverity.error),
            ]),
        ],
        maxOffenders: 2,
      );
      expect(summary.topOffenders.length, 2);
      expect(summary.truncatedOffenderCount, 1);
    });

    test('maxOffenders 为 0 / 负数时只截断不抛', () {
      final zero = QuestionAuditSummary.summarize(
        <QuestionAuditReport>[
          _report(<QuestionAuditFinding>[
            _finding('q1', QuestionAuditCodes.h1StemEmpty,
                QuestionAuditSeverity.error),
          ]),
        ],
        maxOffenders: 0,
      );
      final negative = QuestionAuditSummary.summarize(
        <QuestionAuditReport>[
          _report(<QuestionAuditFinding>[
            _finding('q1', QuestionAuditCodes.h1StemEmpty,
                QuestionAuditSeverity.error),
          ]),
        ],
        maxOffenders: -10,
      );
      expect(zero.topOffenders, isEmpty);
      expect(zero.truncatedOffenderCount, 1);
      expect(negative.topOffenders, isEmpty);
      expect(negative.truncatedOffenderCount, 1);
    });

    test('干净题不进 offender 列表', () {
      final summary = QuestionAuditSummary.summarize(
        <QuestionAuditReport>[
          _cleanReport(),
          _report(<QuestionAuditFinding>[
            _finding('dirty', QuestionAuditCodes.h1StemEmpty,
                QuestionAuditSeverity.error),
          ]),
        ],
      );
      expect(_offenderIds(summary), <String>['dirty']);
      expect(summary.dirtyQuestionCount, 1);
      expect(summary.cleanQuestionCount, 1);
    });

    test('整批 report 里多个 questionId 按题展开（文档化边界）', () {
      final summary = QuestionAuditSummary.summarize(
        <QuestionAuditReport>[
          _report(<QuestionAuditFinding>[
            _finding('q1', QuestionAuditCodes.h1StemEmpty,
                QuestionAuditSeverity.error),
            _finding('q2', QuestionAuditCodes.h1StemTooShort,
                QuestionAuditSeverity.warning),
          ]),
        ],
      );
      expect(summary.questionCount, 1);
      expect(summary.dirtyQuestionCount, 1);
      expect(_offenderIds(summary), <String>['q1', 'q2']);
      expect(summary.codeCounts.length, 2);
    });
  });

  group('toJson 与确定性', () {
    test('summary toJson 键顺序固定', () {
      final json = QuestionAuditSummary.summarize(
        <QuestionAuditReport>[
          _report(<QuestionAuditFinding>[
            _finding('q1', QuestionAuditCodes.h1StemEmpty,
                QuestionAuditSeverity.error),
          ]),
        ],
      ).toJson();
      expect(json.keys.toList(), <String>[
        'question_count',
        'clean_question_count',
        'dirty_question_count',
        'clean_ratio',
        'findings_by_severity',
        'code_counts',
        'top_offenders',
        'truncated_offender_count',
        'is_empty',
        'is_clean',
      ]);
    });

    test('嵌套 codeCount / offender 的 toJson 键名', () {
      final summary = QuestionAuditSummary.summarize(
        <QuestionAuditReport>[
          _report(<QuestionAuditFinding>[
            _finding('q1', QuestionAuditCodes.h1StemEmpty,
                QuestionAuditSeverity.error),
          ]),
        ],
      );
      expect(
        summary.codeCounts.single.toJson().keys.toList(),
        <String>[
          'code',
          'severity',
          'finding_count',
          'question_count',
          'sample_question_ids',
        ],
      );
      expect(
        summary.topOffenders.single.toJson().keys.toList(),
        <String>[
          'question_id',
          'error_count',
          'warning_count',
          'info_count',
          'codes',
          'priority_score',
        ],
      );
    });

    test('clean_ratio 在 toJson 里四舍五入到 6 位', () {
      final json = QuestionAuditSummary.summarize(
        <QuestionAuditReport>[
          _cleanReport(),
          _cleanReport(),
          _cleanReport(),
          _report(<QuestionAuditFinding>[
            _finding('q1', QuestionAuditCodes.h1StemEmpty,
                QuestionAuditSeverity.error),
          ]),
        ],
      ).toJson();
      expect(json['clean_ratio'], 0.75);
      final third = QuestionAuditSummary.summarize(
        <QuestionAuditReport>[
          _cleanReport(),
          _report(<QuestionAuditFinding>[
            _finding('q1', QuestionAuditCodes.h1StemEmpty,
                QuestionAuditSeverity.error),
          ]),
          _report(<QuestionAuditFinding>[
            _finding('q2', QuestionAuditCodes.h1StemTooShort,
                QuestionAuditSeverity.warning),
          ]),
        ],
      ).toJson();
      expect(third['clean_ratio'], 0.333333);
    });

    test('两次调用的 JSON 逐字节相等', () {
      final reports = <QuestionAuditReport>[
        _cleanReport(),
        _report(<QuestionAuditFinding>[
          _finding('q1', 'z', QuestionAuditSeverity.error),
          _finding('q1', 'a', QuestionAuditSeverity.info),
        ]),
        _report(<QuestionAuditFinding>[
          _finding('q2', 'a', QuestionAuditSeverity.warning),
        ]),
      ];
      final first = QuestionAuditSummary.summarize(reports);
      final second = QuestionAuditSummary.summarize(reports);
      expect(jsonEncode(first.toJson()), jsonEncode(second.toJson()));
    });

    test('输入 report 顺序置换不改变输出', () {
      final reports = <QuestionAuditReport>[
        _cleanReport(),
        _report(<QuestionAuditFinding>[
          _finding('q1', 'b', QuestionAuditSeverity.error),
        ]),
        _report(<QuestionAuditFinding>[
          _finding('q2', 'a', QuestionAuditSeverity.warning),
        ]),
      ];
      final forward = QuestionAuditSummary.summarize(reports);
      final reversed = QuestionAuditSummary.summarize(
        reports.reversed,
      );
      expect(
        jsonEncode(forward.toJson()),
        jsonEncode(reversed.toJson()),
      );
    });
  });

  group('极端输入', () {
    test('1000 道干净题不抛且计数正确', () {
      final summary = QuestionAuditSummary.summarize(
        <QuestionAuditReport>[
          for (var i = 0; i < 1000; i++) _cleanReport(),
        ],
      );
      expect(summary.questionCount, 1000);
      expect(summary.cleanQuestionCount, 1000);
      expect(summary.cleanRatio, 1);
      expect(summary.isEmpty, isFalse);
    });

    test('1000 道各异 code 的脏题聚合不抛', () {
      final codes = <String>[
        QuestionAuditCodes.h1StemEmpty,
        QuestionAuditCodes.h2AnswerMissing,
        QuestionAuditCodes.localNoKnowledgePoints,
      ];
      final summary = QuestionAuditSummary.summarize(
        <QuestionAuditReport>[
          for (var i = 0; i < 1000; i++)
            _report(<QuestionAuditFinding>[
              _finding('q$i', codes[i % codes.length],
                  QuestionAuditSeverity.values[i % 3]),
            ]),
        ],
      );
      expect(summary.questionCount, 1000);
      expect(summary.dirtyQuestionCount, 1000);
      expect(summary.findingCount, 1000);
      expect(summary.topOffenders.length, 10);
      expect(summary.truncatedOffenderCount, 990);
    });

    test('25 道脏题默认只留前 10、截断 15', () {
      final summary = QuestionAuditSummary.summarize(
        <QuestionAuditReport>[
          for (var i = 0; i < 25; i++)
            _report(<QuestionAuditFinding>[
              _finding('q$i', QuestionAuditCodes.h1StemEmpty,
                  QuestionAuditSeverity.error),
            ]),
        ],
      );
      expect(summary.topOffenders.length, 10);
      expect(summary.truncatedOffenderCount, 15);
    });
  });
}
