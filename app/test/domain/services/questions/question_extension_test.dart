import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/questions/question_extension.dart';

QuestionExtensionRow _row(
  String id, {
  String? zujuan,
  String? extensionOf,
  int? serial,
}) =>
    QuestionExtensionRow(
      questionId: id,
      zujuanQuestionId: zujuan,
      extensionOfZujuanQuestionId: extensionOf,
      serialNo: serial,
    );

List<String> _extensionIds(QuestionExtensionIndex index, String parentId) =>
    <String>[
      for (final QuestionExtensionLink link in index.extensionsOf(parentId))
        link.extensionQuestionId,
    ];

List<QuestionExtensionProblemKind> _kindsFor(
  QuestionExtensionIndex index,
  String questionId,
) =>
    <QuestionExtensionProblemKind>[
      for (final QuestionExtensionProblem problem
          in index.problemsFor(questionId))
        problem.kind,
    ];

QuestionExtensionProblem _problemOf(
  QuestionExtensionIndex index,
  String questionId,
  QuestionExtensionProblemKind kind,
) =>
    index.problemsFor(questionId).firstWhere(
          (QuestionExtensionProblem problem) => problem.kind == kind,
        );

void main() {
  group('buildQuestionExtensionIndex 基本关联', () {
    test('空输入返回空索引', () {
      final QuestionExtensionIndex index = buildQuestionExtensionIndex(
        const <QuestionExtensionRow>[],
      );
      expect(index.isEmpty, isTrue);
      expect(index.isNotEmpty, isFalse);
      expect(index.parentCount, 0);
      expect(index.extensionCount, 0);
      expect(index.hasProblems, isFalse);
      expect(index.problems, isEmpty);
      expect(index.extensionsOf('q-x'), isEmpty);
      expect(index.extensionQuestionIdsOf('q-x'), isEmpty);
      expect(index.parentQuestionIdOf('q-x'), isNull);
      expect(index.isExtension('q-x'), isFalse);
      expect(index.problemsFor('q-x'), isEmpty);
      expect(index.toString(), contains('parents: 0'));
    });

    test('母题到扩展题、扩展题到母题双向可查', () {
      final QuestionExtensionIndex index = buildQuestionExtensionIndex(
        <QuestionExtensionRow>[
          _row('q-parent', zujuan: 'Z-P'),
          _row('q-ext', zujuan: 'Z-E', extensionOf: 'Z-P', serial: 1),
        ],
      );
      expect(index.isEmpty, isFalse);
      expect(index.parentCount, 1);
      expect(index.extensionCount, 1);
      expect(index.hasProblems, isFalse);
      final List<QuestionExtensionLink> links = index.extensionsOf('q-parent');
      expect(links, hasLength(1));
      expect(
        links.single,
        const QuestionExtensionLink(
          parentQuestionId: 'q-parent',
          extensionQuestionId: 'q-ext',
        ),
      );
      expect(index.parentQuestionIdOf('q-ext'), 'q-parent');
      expect(index.parentQuestionIdOf('q-parent'), isNull);
      expect(index.isExtension('q-ext'), isTrue);
      expect(index.isExtension('q-parent'), isFalse);
      expect(index.extensionQuestionIdsOf('q-parent'), <String>['q-ext']);
    });

    test('独立题不进索引', () {
      final QuestionExtensionIndex index = buildQuestionExtensionIndex(
        <QuestionExtensionRow>[
          _row('q-parent', zujuan: 'Z-P'),
          _row('q-alone', zujuan: 'Z-A'),
        ],
      );
      expect(index.isEmpty, isTrue);
      expect(index.parentQuestionIdOf('q-alone'), isNull);
      expect(index.extensionsOf('q-alone'), isEmpty);
      expect(index.hasProblems, isFalse);
    });

    test('链式关联：每条边单独可查', () {
      final QuestionExtensionIndex index = buildQuestionExtensionIndex(
        <QuestionExtensionRow>[
          _row('q-a', zujuan: 'Z-A'),
          _row('q-b', zujuan: 'Z-B', extensionOf: 'Z-A', serial: 2),
          _row('q-c', zujuan: 'Z-C', extensionOf: 'Z-B', serial: 1),
        ],
      );
      expect(index.parentCount, 2);
      expect(index.extensionCount, 2);
      expect(_extensionIds(index, 'q-a'), <String>['q-b']);
      expect(_extensionIds(index, 'q-b'), <String>['q-c']);
      expect(index.parentQuestionIdOf('q-b'), 'q-a');
      expect(index.parentQuestionIdOf('q-c'), 'q-b');
      expect(index.hasProblems, isFalse);
    });

    test('母题自身也是扩展题时仍可继续当母题', () {
      final QuestionExtensionIndex index = buildQuestionExtensionIndex(
        <QuestionExtensionRow>[
          _row('q-a', zujuan: 'Z-A'),
          _row('q-b', zujuan: 'Z-B', extensionOf: 'Z-A'),
          _row('q-c', zujuan: 'Z-C', extensionOf: 'Z-B'),
        ],
      );
      expect(index.isExtension('q-b'), isTrue);
      expect(index.extensionsOf('q-b'), hasLength(1));
      expect(index.parentQuestionIdOf('q-b'), 'q-a');
      expect(index.parentQuestionIdOf('q-c'), 'q-b');
    });
  });

  group('扩展题排序', () {
    test('按 serialNo 升序', () {
      final QuestionExtensionIndex index = buildQuestionExtensionIndex(
        <QuestionExtensionRow>[
          _row('q-parent', zujuan: 'Z-P'),
          _row('q-late', zujuan: 'Z-3', extensionOf: 'Z-P', serial: 30),
          _row('q-early', zujuan: 'Z-1', extensionOf: 'Z-P', serial: 10),
          _row('q-middle', zujuan: 'Z-2', extensionOf: 'Z-P', serial: 20),
        ],
      );
      expect(
        _extensionIds(index, 'q-parent'),
        <String>['q-early', 'q-middle', 'q-late'],
      );
    });

    test('缺号排在有号之后并保持输入顺序', () {
      final QuestionExtensionIndex index = buildQuestionExtensionIndex(
        <QuestionExtensionRow>[
          _row('q-parent', zujuan: 'Z-P'),
          _row('q-null-1', zujuan: 'Z-N1', extensionOf: 'Z-P'),
          _row('q-five', zujuan: 'Z-5', extensionOf: 'Z-P', serial: 5),
          _row('q-null-2', zujuan: 'Z-N2', extensionOf: 'Z-P'),
        ],
      );
      expect(
        _extensionIds(index, 'q-parent'),
        <String>['q-five', 'q-null-1', 'q-null-2'],
      );
    });

    test('serialNo 为 0 或负数视为没有号', () {
      final QuestionExtensionIndex index = buildQuestionExtensionIndex(
        <QuestionExtensionRow>[
          _row('q-parent', zujuan: 'Z-P'),
          _row('q-zero', zujuan: 'Z-0', extensionOf: 'Z-P', serial: 0),
          _row('q-negative', zujuan: 'Z-NEG', extensionOf: 'Z-P', serial: -3),
          _row('q-five', zujuan: 'Z-5', extensionOf: 'Z-P', serial: 5),
        ],
      );
      expect(
        _extensionIds(index, 'q-parent'),
        <String>['q-five', 'q-zero', 'q-negative'],
      );
    });

    test('同号按输入顺序', () {
      final QuestionExtensionIndex index = buildQuestionExtensionIndex(
        <QuestionExtensionRow>[
          _row('q-parent', zujuan: 'Z-P'),
          _row('q-first', zujuan: 'Z-1', extensionOf: 'Z-P', serial: 5),
          _row('q-second', zujuan: 'Z-2', extensionOf: 'Z-P', serial: 5),
        ],
      );
      expect(
        _extensionIds(index, 'q-parent'),
        <String>['q-first', 'q-second'],
      );
    });

    test('输入顺序打乱后结果不变', () {
      final List<QuestionExtensionRow> rows = <QuestionExtensionRow>[
        _row('q-parent', zujuan: 'Z-P'),
        _row('q-a', zujuan: 'Z-A', extensionOf: 'Z-P', serial: 30),
        _row('q-b', zujuan: 'Z-B', extensionOf: 'Z-P', serial: 10),
        _row('q-c', zujuan: 'Z-C', extensionOf: 'Z-P'),
      ];
      final QuestionExtensionIndex forward = buildQuestionExtensionIndex(rows);
      final QuestionExtensionIndex backward =
          buildQuestionExtensionIndex(rows.reversed);
      expect(
        _extensionIds(forward, 'q-parent'),
        _extensionIds(backward, 'q-parent'),
      );
      expect(
        _extensionIds(forward, 'q-parent'),
        <String>['q-b', 'q-a', 'q-c'],
      );
      expect(forward.parentCount, backward.parentCount);
      expect(forward.extensionCount, backward.extensionCount);
    });
  });

  group('防御：自指、成环、悬空、重复', () {
    test('自指只记 selfReference，不建关联', () {
      final QuestionExtensionIndex index = buildQuestionExtensionIndex(
        <QuestionExtensionRow>[
          _row('q-self', zujuan: 'Z-SELF', extensionOf: 'Z-SELF'),
        ],
      );
      expect(index.isEmpty, isTrue);
      expect(_kindsFor(index, 'q-self'), <QuestionExtensionProblemKind>[
        QuestionExtensionProblemKind.selfReference,
      ]);
      final QuestionExtensionProblem problem = _problemOf(
        index,
        'q-self',
        QuestionExtensionProblemKind.selfReference,
      );
      expect(problem.details['zujuan_question_id'], 'Z-SELF');
      expect(problem.details['input_index'], '0');
      expect(problem.reasonZh, contains('Z-SELF'));
      expect(index.parentQuestionIdOf('q-self'), isNull);
    });

    test('两题互指成环：环上每条记 mutualReference 且不建关联', () {
      final QuestionExtensionIndex index = buildQuestionExtensionIndex(
        <QuestionExtensionRow>[
          _row('q-a', zujuan: 'Z-A', extensionOf: 'Z-B'),
          _row('q-b', zujuan: 'Z-B', extensionOf: 'Z-A'),
        ],
      );
      expect(index.isEmpty, isTrue);
      expect(index.extensionCount, 0);
      expect(_kindsFor(index, 'q-a'), <QuestionExtensionProblemKind>[
        QuestionExtensionProblemKind.mutualReference,
      ]);
      expect(_kindsFor(index, 'q-b'), <QuestionExtensionProblemKind>[
        QuestionExtensionProblemKind.mutualReference,
      ]);
      final QuestionExtensionProblem problemA = _problemOf(
        index,
        'q-a',
        QuestionExtensionProblemKind.mutualReference,
      );
      final QuestionExtensionProblem problemB = _problemOf(
        index,
        'q-b',
        QuestionExtensionProblemKind.mutualReference,
      );
      expect(problemA.details['cycle'], 'q-a → q-b → q-a');
      expect(problemB.details['cycle'], problemA.details['cycle']);
      expect(problemA.reasonZh, contains('q-a → q-b → q-a'));
      expect(problemA.reasonZh, contains('成环'));
    });

    test('三题成环：三条边都不算且文案从最小 id 开始', () {
      final QuestionExtensionIndex index = buildQuestionExtensionIndex(
        <QuestionExtensionRow>[
          _row('q-c', zujuan: 'Z-C', extensionOf: 'Z-A'),
          _row('q-a', zujuan: 'Z-A', extensionOf: 'Z-B'),
          _row('q-b', zujuan: 'Z-B', extensionOf: 'Z-C'),
        ],
      );
      expect(index.isEmpty, isTrue);
      expect(index.problems, hasLength(3));
      for (final String id in <String>['q-a', 'q-b', 'q-c']) {
        expect(_kindsFor(index, id), <QuestionExtensionProblemKind>[
          QuestionExtensionProblemKind.mutualReference,
        ]);
        final QuestionExtensionProblem problem = _problemOf(
          index,
          id,
          QuestionExtensionProblemKind.mutualReference,
        );
        expect(problem.details['cycle'], 'q-a → q-b → q-c → q-a');
      }
    });

    test('环外扩展题记 invalidParent（父在环上）', () {
      final QuestionExtensionIndex index = buildQuestionExtensionIndex(
        <QuestionExtensionRow>[
          _row('q-x', zujuan: 'Z-X', extensionOf: 'Z-A'),
          _row('q-a', zujuan: 'Z-A', extensionOf: 'Z-B'),
          _row('q-b', zujuan: 'Z-B', extensionOf: 'Z-A'),
        ],
      );
      expect(index.isEmpty, isTrue);
      expect(_kindsFor(index, 'q-x'), <QuestionExtensionProblemKind>[
        QuestionExtensionProblemKind.invalidParent,
      ]);
      final QuestionExtensionProblem problem = _problemOf(
        index,
        'q-x',
        QuestionExtensionProblemKind.invalidParent,
      );
      expect(problem.details['parent_question_id'], 'q-a');
      expect(problem.details['parent_state'], 'cycle');
      expect(problem.reasonZh, contains('q-a'));
    });

    test('多级无效沿父链传递（不递归）', () {
      final QuestionExtensionIndex index = buildQuestionExtensionIndex(
        <QuestionExtensionRow>[
          _row('q-x', zujuan: 'Z-X', extensionOf: 'Z-Y'),
          _row('q-y', zujuan: 'Z-Y', extensionOf: 'Z-A'),
          _row('q-a', zujuan: 'Z-A', extensionOf: 'Z-B'),
          _row('q-b', zujuan: 'Z-B', extensionOf: 'Z-A'),
        ],
      );
      expect(index.isEmpty, isTrue);
      expect(_kindsFor(index, 'q-x'), <QuestionExtensionProblemKind>[
        QuestionExtensionProblemKind.invalidParent,
      ]);
      expect(_kindsFor(index, 'q-y'), <QuestionExtensionProblemKind>[
        QuestionExtensionProblemKind.invalidParent,
      ]);
      expect(
        _problemOf(index, 'q-x', QuestionExtensionProblemKind.invalidParent)
            .details['parent_question_id'],
        'q-y',
      );
      expect(
        _problemOf(index, 'q-x', QuestionExtensionProblemKind.invalidParent)
            .details['parent_state'],
        'invalid',
      );
      expect(
        _problemOf(index, 'q-y', QuestionExtensionProblemKind.invalidParent)
            .details['parent_state'],
        'cycle',
      );
    });

    test('悬空母题题号', () {
      final QuestionExtensionIndex index = buildQuestionExtensionIndex(
        <QuestionExtensionRow>[
          _row('q-orphan', zujuan: 'Z-E', extensionOf: 'Z-missing'),
        ],
      );
      expect(index.isEmpty, isTrue);
      expect(_kindsFor(index, 'q-orphan'), <QuestionExtensionProblemKind>[
        QuestionExtensionProblemKind.danglingParent,
      ]);
      final QuestionExtensionProblem problem = _problemOf(
        index,
        'q-orphan',
        QuestionExtensionProblemKind.danglingParent,
      );
      expect(problem.details['extension_of'], 'Z-missing');
      expect(problem.reasonZh, contains('Z-missing'));
    });

    test('空白 extension_of 视为独立题', () {
      final QuestionExtensionIndex index = buildQuestionExtensionIndex(
        <QuestionExtensionRow>[
          _row('q-parent', zujuan: 'Z-P', extensionOf: '   '),
          _row('q-ext', zujuan: 'Z-E', extensionOf: 'Z-P'),
        ],
      );
      expect(index.hasProblems, isFalse);
      expect(_extensionIds(index, 'q-parent'), <String>['q-ext']);
    });

    test('重复题目 id 只认第一条', () {
      final QuestionExtensionIndex index = buildQuestionExtensionIndex(
        <QuestionExtensionRow>[
          _row('q-a', zujuan: 'Z-A'),
          _row('q-ext', zujuan: 'Z-E', extensionOf: 'Z-A'),
          _row('q-a', zujuan: 'Z-B'),
        ],
      );
      expect(_kindsFor(index, 'q-a'), <QuestionExtensionProblemKind>[
        QuestionExtensionProblemKind.duplicateQuestionId,
      ]);
      final QuestionExtensionProblem problem = _problemOf(
        index,
        'q-a',
        QuestionExtensionProblemKind.duplicateQuestionId,
      );
      expect(problem.details['input_index'], '2');
      expect(problem.details['kept_input_index'], '0');
      expect(_extensionIds(index, 'q-a'), <String>['q-ext']);
      expect(index.extensionCount, 1);
    });

    test('重复组卷网题号整行跳过，扩展题挂到第一条', () {
      final QuestionExtensionIndex index = buildQuestionExtensionIndex(
        <QuestionExtensionRow>[
          _row('q-first', zujuan: 'Z-shared'),
          _row('q-second', zujuan: 'Z-shared'),
          _row('q-ext', zujuan: 'Z-E', extensionOf: 'Z-shared'),
        ],
      );
      expect(_kindsFor(index, 'q-second'), <QuestionExtensionProblemKind>[
        QuestionExtensionProblemKind.duplicateZujuanQuestionId,
      ]);
      final QuestionExtensionProblem problem = _problemOf(
        index,
        'q-second',
        QuestionExtensionProblemKind.duplicateZujuanQuestionId,
      );
      expect(problem.details['zujuan_question_id'], 'Z-shared');
      expect(problem.details['first_question_id'], 'q-first');
      expect(_extensionIds(index, 'q-first'), <String>['q-ext']);
      expect(index.parentQuestionIdOf('q-second'), isNull);
      expect(index.extensionsOf('q-second'), isEmpty);
    });

    test('空白题目 id 进问题清单', () {
      final QuestionExtensionIndex index = buildQuestionExtensionIndex(
        <QuestionExtensionRow>[
          _row('   ', zujuan: 'Z-blank'),
        ],
      );
      expect(index.isEmpty, isTrue);
      final QuestionExtensionProblem problem = index.problems.single;
      expect(problem.questionId, '');
      expect(problem.kind, QuestionExtensionProblemKind.missingQuestionId);
      expect(problem.details['input_index'], '0');
    });

    test('两百个节点首尾相连成环也不爆栈', () {
      const int count = 200;
      final List<QuestionExtensionRow> rows = <QuestionExtensionRow>[
        for (int i = 0; i < count; i++)
          _row(
            'q-$i',
            zujuan: 'Z-$i',
            extensionOf: 'Z-${(i + 1) % count}',
          ),
      ];
      late QuestionExtensionIndex index;
      expect(
        () => index = buildQuestionExtensionIndex(rows),
        returnsNormally,
      );
      expect(index.isEmpty, isTrue);
      expect(index.problems, hasLength(count));
      for (final QuestionExtensionProblem problem in index.problems) {
        expect(
          problem.kind,
          QuestionExtensionProblemKind.mutualReference,
        );
      }
    });

    test('两百个节点长链也能迭代走完', () {
      const int count = 200;
      final List<QuestionExtensionRow> rows = <QuestionExtensionRow>[
        for (int i = 0; i < count - 1; i++)
          _row(
            'q-$i',
            zujuan: 'Z-$i',
            extensionOf: 'Z-${i + 1}',
            serial: i,
          ),
        _row('q-${count - 1}', zujuan: 'Z-${count - 1}'),
      ];
      final QuestionExtensionIndex index = buildQuestionExtensionIndex(rows);
      expect(index.hasProblems, isFalse);
      expect(index.parentCount, count - 1);
      expect(index.extensionCount, count - 1);
      expect(index.parentQuestionIdOf('q-0'), 'q-1');
      expect(index.parentQuestionIdOf('q-${count - 2}'), 'q-${count - 1}');
    });
  });

  group('问题清单排序与结构', () {
    test('按题目 id、问题类型固定排序', () {
      final QuestionExtensionIndex index = buildQuestionExtensionIndex(
        <QuestionExtensionRow>[
          _row('q-c', zujuan: 'Z-C', extensionOf: 'Z-nope'),
          _row('q-a', zujuan: 'Z-A', extensionOf: 'Z-A'),
          _row('q-b', zujuan: 'Z-A'),
          _row(''),
        ],
      );
      expect(
        <String>[
          for (final QuestionExtensionProblem p in index.problems) p.questionId
        ],
        <String>['', 'q-a', 'q-b', 'q-c'],
      );
      expect(
        <QuestionExtensionProblemKind>[
          for (final QuestionExtensionProblem p in index.problems) p.kind,
        ],
        <QuestionExtensionProblemKind>[
          QuestionExtensionProblemKind.missingQuestionId,
          QuestionExtensionProblemKind.selfReference,
          QuestionExtensionProblemKind.duplicateZujuanQuestionId,
          QuestionExtensionProblemKind.danglingParent,
        ],
      );
    });

    test('同一题目的多个问题按类型枚举顺序排序', () {
      final QuestionExtensionIndex index = buildQuestionExtensionIndex(
        <QuestionExtensionRow>[
          _row('q-a', zujuan: 'Z-A', extensionOf: 'Z-A'),
          _row('q-a', zujuan: 'Z-B'),
        ],
      );
      expect(_kindsFor(index, 'q-a'), <QuestionExtensionProblemKind>[
        QuestionExtensionProblemKind.duplicateQuestionId,
        QuestionExtensionProblemKind.selfReference,
      ]);
    });

    test('问题清单不含重复项', () {
      final QuestionExtensionIndex index = buildQuestionExtensionIndex(
        <QuestionExtensionRow>[
          _row('q-a', zujuan: 'Z-A', extensionOf: 'Z-B'),
          _row('q-b', zujuan: 'Z-B', extensionOf: 'Z-A'),
          _row('q-c', zujuan: 'Z-C', extensionOf: 'Z-missing'),
          _row('q-d', zujuan: 'Z-C'),
          _row('q-e', zujuan: 'Z-E', extensionOf: 'Z-E'),
        ],
      );
      final Set<String> seen = <String>{};
      for (final QuestionExtensionProblem problem in index.problems) {
        final String key = '${problem.questionId}'
            '|${problem.kind.code}'
            '|${problem.reasonZh}'
            '|${problem.details}';
        expect(seen.add(key), isTrue, reason: key);
      }
    });

    test('查询方法归一化空白', () {
      final QuestionExtensionIndex index = buildQuestionExtensionIndex(
        <QuestionExtensionRow>[
          _row('q-a', zujuan: 'Z-A'),
          _row('q-b', zujuan: 'Z-B', extensionOf: 'Z-A'),
          _row('q-d', zujuan: 'Z-D', extensionOf: 'Z-missing'),
        ],
      );
      expect(index.extensionsOf('  q-a  '), hasLength(1));
      expect(index.extensionQuestionIdsOf('q-a'), <String>['q-b']);
      expect(index.parentQuestionIdOf('  q-b  '), 'q-a');
      expect(index.problemsFor('  q-d  '), hasLength(1));
      expect(index.extensionsOf(''), isEmpty);
      expect(index.extensionQuestionIdsOf('   '), isEmpty);
      expect(index.parentQuestionIdOf('   '), isNull);
      expect(index.problemsFor('   '), isEmpty);
    });

    test('toJson 使用小写蛇形键', () {
      final QuestionExtensionIndex index = buildQuestionExtensionIndex(
        <QuestionExtensionRow>[
          _row('q-a', zujuan: 'Z-A'),
          _row('q-b', zujuan: 'Z-B', extensionOf: 'Z-A'),
          _row('q-d', zujuan: 'Z-D', extensionOf: 'Z-missing'),
        ],
      );
      final QuestionExtensionLink link = index.extensionsOf('q-a').single;
      expect(link.toJson(), <String, Object?>{
        'parent_question_id': 'q-a',
        'extension_question_id': 'q-b',
      });
      final QuestionExtensionProblem problem = index.problems.single;
      expect(problem.toJson(), <String, Object?>{
        'question_id': 'q-d',
        'kind': 'dangling_parent',
        'reason_zh': problem.reasonZh,
        'details': <String, String>{
          'extension_of': 'Z-missing',
          'input_index': '2',
        },
      });
      expect(problem.kind.code, 'dangling_parent');
      expect(problem.toString(), contains('dangling_parent'));
    });

    test('索引与问题集合不可变', () {
      final QuestionExtensionIndex index = buildQuestionExtensionIndex(
        <QuestionExtensionRow>[
          _row('q-a', zujuan: 'Z-A'),
          _row('q-b', zujuan: 'Z-B', extensionOf: 'Z-A'),
          _row('q-d', zujuan: 'Z-D', extensionOf: 'Z-missing'),
        ],
      );
      expect(() => index.problems.clear(), throwsUnsupportedError);
      expect(
        () => index.extensionsByParentQuestionId.clear(),
        throwsUnsupportedError,
      );
      expect(
        () => index.parentQuestionIdOfExtension['q-x'] = 'q-y',
        throwsUnsupportedError,
      );
      expect(() => index.extensionsOf('q-a').clear(), throwsUnsupportedError);
      expect(
        () => index.extensionQuestionIdsOf('q-a').clear(),
        throwsUnsupportedError,
      );
      expect(() => index.problemsFor('q-d').clear(), throwsUnsupportedError);
      expect(
        () => index.problems.single.details['extra'] = 'x',
        throwsUnsupportedError,
      );
    });

    test('脏数据不抛异常', () {
      expect(
        () => buildQuestionExtensionIndex(<QuestionExtensionRow>[
          _row('', zujuan: '', extensionOf: ''),
          _row('  ', zujuan: '   ', extensionOf: '  '),
          _row('q-a', zujuan: null, extensionOf: null, serial: -1),
          _row('q-a', zujuan: ' Z-A ', extensionOf: ' Z-B ', serial: 0),
          _row('q-b', zujuan: 'Z-B', extensionOf: ' Z-A '),
        ]),
        returnsNormally,
      );
    });
  });
}
