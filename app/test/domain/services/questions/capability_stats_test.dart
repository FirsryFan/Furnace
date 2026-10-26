import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/questions/capability_stats.dart';

CapabilityAttempt attempt({
  String questionId = 'q1',
  String questionType = 'single_choice',
  List<String> capabilities = const <String>['A1'],
  QuestionResult result = QuestionResult.correct,
  int seconds = 0,
}) {
  return CapabilityAttempt(
    questionId: questionId,
    questionType: questionType,
    capabilities: capabilities,
    result: result,
    timeSpentSeconds: seconds,
  );
}

void expectCounts(
  ResultCounts counts, {
  int attempts = 0,
  int correct = 0,
  int incorrect = 0,
  int partial = 0,
}) {
  expect(counts.attempts, attempts, reason: 'attempts');
  expect(counts.correct, correct, reason: 'correct');
  expect(counts.incorrect, incorrect, reason: 'incorrect');
  expect(counts.partial, partial, reason: 'partial');
  expect(counts.isEmpty, attempts == 0, reason: 'isEmpty');
}

void main() {
  group('QuestionResult 结果枚举', () {
    test('英文标准写法', () {
      expect(QuestionResult.fromCode('correct'), QuestionResult.correct);
      expect(QuestionResult.fromCode('incorrect'), QuestionResult.incorrect);
      expect(QuestionResult.fromCode('partial'), QuestionResult.partial);
    });

    test('中文与别名、大小写与空白', () {
      expect(QuestionResult.fromCode(' 对 '), QuestionResult.correct);
      expect(QuestionResult.fromCode('RIGHT'), QuestionResult.correct);
      expect(QuestionResult.fromCode('正确'), QuestionResult.correct);
      expect(QuestionResult.fromCode('错误'), QuestionResult.incorrect);
      expect(QuestionResult.fromCode('wrong'), QuestionResult.incorrect);
      expect(QuestionResult.fromCode(' Partial '), QuestionResult.partial);
      expect(QuestionResult.fromCode('部分正确'), QuestionResult.partial);
    });

    test('未知或空返回 null', () {
      expect(QuestionResult.fromCode(null), isNull);
      expect(QuestionResult.fromCode(''), isNull);
      expect(QuestionResult.fromCode('   '), isNull);
      expect(QuestionResult.fromCode('半对'), isNull);
    });

    test('三个结果的中文标签', () {
      expect(QuestionResult.correct.labelZh, '对');
      expect(QuestionResult.incorrect.labelZh, '错');
      expect(QuestionResult.partial.labelZh, '部分对');
    });
  });

  group('ResultCounts 计数与正确率', () {
    test('空计数没有正确率', () {
      const counts = ResultCounts.empty;
      expectCounts(counts);
      expect(counts.accuracy01, isNull);
      expect(counts.weightedAccuracy01, isNull);
      expect(counts.isNotEmpty, isFalse);
    });

    test('严格正确率不算部分对，加权正确率按半分', () {
      const counts = ResultCounts(
        attempts: 4,
        correct: 2,
        incorrect: 1,
        partial: 1,
      );
      expectCounts(counts, attempts: 4, correct: 2, incorrect: 1, partial: 1);
      expect(counts.accuracy01, 0.5);
      expect(counts.weightedAccuracy01, 0.625);
    });

    test('只有部分对时严格正确率为 0，加权为 0.5', () {
      const counts = ResultCounts(attempts: 1, partial: 1);
      expect(counts.accuracy01, 0.0);
      expect(counts.weightedAccuracy01, 0.5);
    });

    test('全对与全错', () {
      expect(
        const ResultCounts(attempts: 2, correct: 2).accuracy01,
        1.0,
      );
      expect(
        const ResultCounts(attempts: 2, incorrect: 2).accuracy01,
        0.0,
      );
    });
  });

  group('CapabilityAttempt 归一化', () {
    test('题型去空白、能力去重排序、负时长夹 0', () {
      final record = attempt(
        questionType: ' single_choice ',
        capabilities: const <String>['a3', 'A1', 'A3', 'X'],
        seconds: -30,
      );
      expect(record.questionType, 'single_choice');
      expect(record.capabilities, const <String>['A1', 'A3']);
      expect(record.timeSpentSeconds, 0);
      expect(record.result, QuestionResult.correct);
    });

    test('默认没有能力标签，非法能力被丢弃', () {
      expect(attempt(capabilities: const <String>[]).capabilities, isEmpty);
      expect(
        attempt(capabilities: const <String>['X', 'A2']).capabilities,
        const <String>['A2'],
      );
    });

    test('能力列表不可修改', () {
      final record = attempt();
      expect(() => record.capabilities.add('A2'), throwsUnsupportedError);
    });
  });

  group('空输入报告', () {
    test('空记录返回空报告且不抛异常', () {
      final report = CapabilityStatsReport.of(const <CapabilityAttempt>[]);
      expect(report.isEmpty, isTrue);
      expect(report.isNotEmpty, isFalse);
      expect(report.attemptCount, 0);
      expect(report.distinctQuestionCount, 0);
      expect(report.totalTimeSpentSeconds, 0);
      expect(report.unattributedAttemptCount, 0);
      expect(report.overall, isA<ResultCounts>());
      expectCounts(report.overall);
      expect(report.accuracy01, isNull);
      expect(report.capabilities, isEmpty);
      expect(report.questionTypes, isEmpty);
      expect(report.crossTable, isEmpty);
      expect(report.weakest(), isEmpty);
      expect(report.pointFor('A1'), isNull);
      expect(report.minSamplesForConclusion, 3);
    });
  });

  group('整体统计', () {
    test('单条全对', () {
      final report = CapabilityStatsReport.of(<CapabilityAttempt>[attempt()]);
      expect(report.attemptCount, 1);
      expect(report.accuracy01, 1.0);
      expectCounts(report.overall, attempts: 1, correct: 1);
    });

    test('没有能力标签的记录计入整体与题型但不计入能力点', () {
      final report = CapabilityStatsReport.of(<CapabilityAttempt>[
        attempt(capabilities: const <String>[]),
      ]);
      expect(report.attemptCount, 1);
      expect(report.unattributedAttemptCount, 1);
      expect(report.overall.attempts, 1);
      expect(report.capabilities, isEmpty);
      expect(report.questionTypes, hasLength(1));
      expect(report.questionTypes.single.counts.attempts, 1);
      expect(report.crossTable['single_choice'], isEmpty);
    });

    test('一题挂多个能力时每个能力各记一次', () {
      final report = CapabilityStatsReport.of(<CapabilityAttempt>[
        attempt(capabilities: const <String>['A1', 'A3']),
      ]);
      expect(report.overall.attempts, 1);
      expect(report.distinctQuestionCount, 1);
      expect(report.pointFor('A1')!.counts.attempts, 1);
      expect(report.pointFor('A3')!.counts.attempts, 1);
    });

    test('每能力点正确率与顺序', () {
      final report = CapabilityStatsReport.of(<CapabilityAttempt>[
        attempt(capabilities: const <String>['A3']),
        attempt(capabilities: const <String>['A1']),
        attempt(
          capabilities: const <String>['A1'],
          result: QuestionResult.incorrect,
        ),
      ]);
      expect(
        report.capabilities.map((point) => point.code).toList(),
        const <String>['A1', 'A3'],
      );
      expect(report.pointFor('A1')!.accuracy01, 0.5);
      expect(report.pointFor('A1')!.counts.attempts, 2);
      expect(report.pointFor('A3')!.accuracy01, 1.0);
    });

    test('能力点的严格正确率与加权正确率', () {
      final report = CapabilityStatsReport.of(<CapabilityAttempt>[
        attempt(
            capabilities: const <String>['A2'], result: QuestionResult.partial),
      ]);
      final point = report.pointFor('A2')!;
      expect(point.accuracy01, 0.0);
      expect(point.weightedAccuracy01, 0.5);
      expect(point.counts.partial, 1);
      expect(point.labelZh, '信息定位与提取');
      expect(point.definitionZh, '从材料找证据句 / 图表数据');
    });
  });

  group('每题型统计', () {
    test('题型正确率、中文标签与排序', () {
      final report = CapabilityStatsReport.of(<CapabilityAttempt>[
        attempt(questionType: 'solution', result: QuestionResult.incorrect),
        attempt(questionType: 'single_choice'),
        attempt(
          questionType: 'single_choice',
          result: QuestionResult.incorrect,
        ),
      ]);
      expect(
        report.questionTypes.map((stats) => stats.questionType).toList(),
        const <String>['single_choice', 'solution'],
      );
      final singleChoice = report.questionTypes[0];
      expect(singleChoice.labelZh, '单选题');
      expect(singleChoice.accuracy01, 0.5);
      expect(singleChoice.counts.attempts, 2);
      final solution = report.questionTypes[1];
      expect(solution.labelZh, '解答题');
      expect(solution.accuracy01, 0.0);
    });

    test('未知题型中文标签原样返回', () {
      final report = CapabilityStatsReport.of(<CapabilityAttempt>[
        attempt(questionType: 'judge'),
      ]);
      expect(report.questionTypes.single.labelZh, 'judge');
    });

    test('题型首尾空白在构造时归一', () {
      final report = CapabilityStatsReport.of(<CapabilityAttempt>[
        attempt(questionType: ' single_choice '),
      ]);
      expect(report.questionTypes.single.questionType, 'single_choice');
    });
  });

  group('T×A 交叉表', () {
    test('交叉表按题型 key 与 A 序号排序', () {
      final report = CapabilityStatsReport.of(<CapabilityAttempt>[
        attempt(questionType: 'solution', capabilities: const <String>['A10']),
        attempt(
            questionType: 'single_choice', capabilities: const <String>['A3']),
        attempt(
          questionType: 'single_choice',
          capabilities: const <String>['A1'],
          result: QuestionResult.incorrect,
        ),
        attempt(
          questionType: 'solution',
          capabilities: const <String>['A2'],
          result: QuestionResult.incorrect,
        ),
      ]);
      expect(
        report.crossTable.keys.toList(),
        const <String>['single_choice', 'solution'],
      );
      expect(
        report.crossTable['single_choice']!.keys.toList(),
        const <String>['A1', 'A3'],
      );
      expect(
        report.crossTable['solution']!.keys.toList(),
        const <String>['A2', 'A10'],
      );
    });

    test('交叉格子计数正确', () {
      final report = CapabilityStatsReport.of(<CapabilityAttempt>[
        attempt(
            questionType: 'single_choice', capabilities: const <String>['A1']),
        attempt(
          questionType: 'solution',
          capabilities: const <String>['A1'],
          result: QuestionResult.incorrect,
        ),
      ]);
      final singleChoiceA1 = report.crossTable['single_choice']!['A1']!;
      expectCounts(singleChoiceA1, attempts: 1, correct: 1);
      final solutionA1 = report.crossTable['solution']!['A1']!;
      expectCounts(solutionA1, attempts: 1, incorrect: 1);
    });

    test('没有能力标签的记录不产生交叉格子', () {
      final report = CapabilityStatsReport.of(<CapabilityAttempt>[
        attempt(capabilities: const <String>['X']),
      ]);
      expect(report.unattributedAttemptCount, 1);
      expect(report.overall.attempts, 1);
      expect(report.capabilities, isEmpty);
      expect(report.crossTable['single_choice'], isEmpty);
    });

    test('交叉表外层与内层都不可修改', () {
      final report = CapabilityStatsReport.of(<CapabilityAttempt>[attempt()]);
      expect(
        () {
          report.crossTable['single_choice']!['A1'] = ResultCounts.empty;
        },
        throwsUnsupportedError,
      );
      expect(
        () {
          report.crossTable['judge'] = const <String, ResultCounts>{};
        },
        throwsUnsupportedError,
      );
    });

    test('能力点反向视图按题型排序', () {
      final report = CapabilityStatsReport.of(<CapabilityAttempt>[
        attempt(questionType: 'solution', capabilities: const <String>['A1']),
        attempt(questionType: 'fill_blank', capabilities: const <String>['A1']),
      ]);
      final point = report.pointFor('A1')!;
      expect(
        point.byQuestionType.keys.toList(),
        const <String>['fill_blank', 'solution'],
      );
      expect(point.byQuestionType['solution']!.attempts, 1);
    });
  });

  group('去重题目数与用时', () {
    test('相同 questionId 只算一个，空白 id 不计', () {
      final report = CapabilityStatsReport.of(<CapabilityAttempt>[
        attempt(questionId: ' q1 '),
        attempt(questionId: 'q1'),
        attempt(questionId: '   '),
      ]);
      expect(report.distinctQuestionCount, 1);
      expect(report.attemptCount, 3);
    });

    test('总用时累加非负值', () {
      final report = CapabilityStatsReport.of(<CapabilityAttempt>[
        attempt(seconds: 30),
        attempt(seconds: 15),
        attempt(seconds: -5),
      ]);
      expect(report.totalTimeSpentSeconds, 45);
    });
  });

  group('weakest 最弱能力点', () {
    test('空输入返回空列表', () {
      final report = CapabilityStatsReport.of(const <CapabilityAttempt>[]);
      expect(report.weakest(), isEmpty);
      expect(report.weakest(limit: 5), isEmpty);
    });

    test('样本充足的排在样本不足之前', () {
      final report = CapabilityStatsReport.of(<CapabilityAttempt>[
        attempt(
            capabilities: const <String>['A2'],
            result: QuestionResult.incorrect),
        attempt(capabilities: const <String>['A5']),
        attempt(
          capabilities: const <String>['A5'],
          result: QuestionResult.incorrect,
        ),
        attempt(
          capabilities: const <String>['A5'],
          result: QuestionResult.incorrect,
        ),
      ]);
      final ranked = report.weakest();
      expect(ranked.map((point) => point.code).toList(),
          const <String>['A5', 'A2']);
      expect(ranked[0].hasEnoughSamples, isTrue);
      expect(ranked[0].accuracy01, closeTo(1 / 3, 1e-9));
      expect(ranked[1].hasEnoughSamples, isFalse);
      expect(ranked[1].counts.attempts, 1);
      expect(ranked[1].accuracy01, 0.0);
    });

    test('正确率相同按次数降序', () {
      final report = CapabilityStatsReport.of(<CapabilityAttempt>[
        attempt(capabilities: const <String>['A1']),
        attempt(capabilities: const <String>['A1']),
        attempt(
            capabilities: const <String>['A1'],
            result: QuestionResult.incorrect),
        attempt(
            capabilities: const <String>['A1'],
            result: QuestionResult.incorrect),
        for (var i = 0; i < 3; i++) attempt(capabilities: const <String>['A3']),
        for (var i = 0; i < 3; i++)
          attempt(
              capabilities: const <String>['A3'],
              result: QuestionResult.incorrect),
      ]);
      final ranked = report.weakest();
      expect(ranked.map((point) => point.code).toList(),
          const <String>['A3', 'A1']);
      expect(ranked[0].counts.attempts, 6);
      expect(ranked[1].counts.attempts, 4);
    });

    test('正确率与次数都相同按 A 序号升序', () {
      final report = CapabilityStatsReport.of(<CapabilityAttempt>[
        attempt(capabilities: const <String>['A3']),
        attempt(capabilities: const <String>['A3']),
        attempt(
            capabilities: const <String>['A3'],
            result: QuestionResult.incorrect),
        attempt(
            capabilities: const <String>['A3'],
            result: QuestionResult.incorrect),
        attempt(capabilities: const <String>['A1']),
        attempt(capabilities: const <String>['A1']),
        attempt(
            capabilities: const <String>['A1'],
            result: QuestionResult.incorrect),
        attempt(
            capabilities: const <String>['A1'],
            result: QuestionResult.incorrect),
      ]);
      final ranked = report.weakest();
      expect(ranked.map((point) => point.code).toList(),
          const <String>['A1', 'A3']);
    });

    test('limit 生效且不超过可用能力点', () {
      final report = CapabilityStatsReport.of(<CapabilityAttempt>[
        attempt(capabilities: const <String>['A1']),
        attempt(
            capabilities: const <String>['A1'],
            result: QuestionResult.incorrect),
        attempt(
            capabilities: const <String>['A1'],
            result: QuestionResult.incorrect),
        attempt(
            capabilities: const <String>['A1'],
            result: QuestionResult.incorrect),
        attempt(capabilities: const <String>['A2']),
        attempt(capabilities: const <String>['A2']),
        attempt(
            capabilities: const <String>['A2'],
            result: QuestionResult.incorrect),
        attempt(
            capabilities: const <String>['A2'],
            result: QuestionResult.incorrect),
        attempt(capabilities: const <String>['A3']),
        attempt(capabilities: const <String>['A3']),
        attempt(capabilities: const <String>['A3']),
        attempt(
            capabilities: const <String>['A3'],
            result: QuestionResult.incorrect),
        attempt(capabilities: const <String>['A4']),
        attempt(capabilities: const <String>['A4']),
        attempt(capabilities: const <String>['A4']),
        attempt(capabilities: const <String>['A4']),
      ]);
      expect(
        report.weakest(limit: 2).map((point) => point.code).toList(),
        const <String>['A1', 'A2'],
      );
      expect(report.weakest(limit: 0), isEmpty);
      expect(report.weakest(limit: -1), isEmpty);
      expect(report.weakest(limit: 99), hasLength(4));
    });

    test('minSamplesForConclusion 参与是否够样本的判断', () {
      final attempts = <CapabilityAttempt>[
        attempt(capabilities: const <String>['A1']),
        attempt(capabilities: const <String>['A1']),
        attempt(
            capabilities: const <String>['A1'],
            result: QuestionResult.incorrect),
        attempt(
            capabilities: const <String>['A1'],
            result: QuestionResult.incorrect),
      ];
      expect(
        CapabilityStatsReport.of(
          attempts,
          minSamplesForConclusion: 1,
        ).pointFor('A1')!.hasEnoughSamples,
        isTrue,
      );
      expect(
        CapabilityStatsReport.of(
          attempts,
          minSamplesForConclusion: 5,
        ).pointFor('A1')!.hasEnoughSamples,
        isFalse,
      );
      expect(
        CapabilityStatsReport.of(
          attempts,
          minSamplesForConclusion: 0,
        ).minSamplesForConclusion,
        1,
      );
    });

    test('全对且样本不足时仍按次数与 A 序列出', () {
      final report = CapabilityStatsReport.of(<CapabilityAttempt>[
        attempt(capabilities: const <String>['A3']),
        attempt(capabilities: const <String>['A1']),
      ]);
      final ranked = report.weakest();
      expect(ranked.map((point) => point.code).toList(),
          const <String>['A1', 'A3']);
      expect(ranked.every((point) => !point.hasEnoughSamples), isTrue);
      expect(ranked.every((point) => point.accuracy01 == 1.0), isTrue);
    });
  });

  group('pointFor 与确定性', () {
    test('pointFor 支持小写编号，未知返回 null', () {
      final report = CapabilityStatsReport.of(<CapabilityAttempt>[attempt()]);
      expect(report.pointFor('a1'), isNotNull);
      expect(report.pointFor('A1')!.code, 'A1');
      expect(report.pointFor('A9'), isNull);
      expect(report.pointFor('X'), isNull);
      expect(report.pointFor(''), isNull);
    });

    test('输入顺序不影响报告，重复调用结果一致', () {
      final records = <CapabilityAttempt>[
        attempt(capabilities: const <String>['A1', 'A3']),
        attempt(
          questionType: 'solution',
          capabilities: const <String>['A1'],
          result: QuestionResult.incorrect,
        ),
        attempt(questionType: 'fill_blank', capabilities: const <String>['A2']),
      ];
      final forward = CapabilityStatsReport.of(records);
      final backward = CapabilityStatsReport.of(records.reversed.toList());
      expect(forward.attemptCount, backward.attemptCount);
      expect(forward.distinctQuestionCount, backward.distinctQuestionCount);
      expect(forward.overall.attempts, backward.overall.attempts);
      expect(forward.overall.correct, backward.overall.correct);
      expect(
        forward.capabilities.map((point) => point.code).toList(),
        backward.capabilities.map((point) => point.code).toList(),
      );
      expect(
        forward.crossTable['single_choice']!['A1']!.attempts,
        backward.crossTable['single_choice']!['A1']!.attempts,
      );
      expect(
        forward.weakest().map((point) => point.code).toList(),
        backward.weakest().map((point) => point.code).toList(),
      );
      final again = CapabilityStatsReport.of(records);
      expect(again.overall.attempts, forward.overall.attempts);
      expect(
        again.weakest().map((point) => point.code).toList(),
        forward.weakest().map((point) => point.code).toList(),
      );
    });

    test('报告能力列表不可修改', () {
      final report = CapabilityStatsReport.of(<CapabilityAttempt>[attempt()]);
      expect(
        () => report.capabilities.add(report.capabilities.first),
        throwsUnsupportedError,
      );
      expect(
        () => report.questionTypes.add(report.questionTypes.first),
        throwsUnsupportedError,
      );
    });
  });
}
