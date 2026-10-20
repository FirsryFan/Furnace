import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/package/question_pack_record.dart';
import 'package:furnace/domain/services/package/question_pack_selection.dart';

QuestionPackRecord packRecord({
  String stem = '题干',
  String subjectKey = 'math',
  String sourceLevel = 'exam',
  int? serialNo,
  List<String> tagPaths = const <String>[],
}) {
  return QuestionPackRecord(
    stem: stem,
    subjectKey: subjectKey,
    sourceLevel: sourceLevel,
    serialNo: serialNo,
    tagPaths: tagPaths,
  );
}

void main() {
  group('空选择与边界', () {
    test('空条件 isEmpty 为 true 且没有题号区间', () {
      const QuestionPackSelection selection = QuestionPackSelection();
      expect(selection.isEmpty, isTrue);
      expect(selection.hasSerialRange, isFalse);
    });

    test('空条件匹配全部记录', () {
      const QuestionPackSelection selection = QuestionPackSelection();
      expect(
        questionPackRecordMatchesSelection(packRecord(), selection),
        isTrue,
      );
      expect(
        questionPackRecordMatchesSelection(
          packRecord(subjectKey: '', sourceLevel: 'unknown'),
          selection,
        ),
        isTrue,
      );
      expect(
        questionPackRecordMatchesSelection(
            packRecord(serialNo: null), selection),
        isTrue,
      );
    });

    test('空条件不过滤 select', () {
      final List<QuestionPackRecord> records = <QuestionPackRecord>[
        packRecord(stem: '一'),
        packRecord(stem: '二'),
        packRecord(stem: '三'),
      ];
      final List<QuestionPackRecord> selected = selectQuestionPackRecords(
        records: records,
        selection: const QuestionPackSelection(),
      );
      expect(selected, records);
    });

    test('带空串的条件等于不约束', () {
      const QuestionPackSelection selection = QuestionPackSelection(
        subjectKeys: <String>{'  '},
        sourceLevels: <String>{''},
        tagPaths: <String>{'   '},
      );
      expect(
        questionPackRecordMatchesSelection(
          packRecord(subjectKey: 'physics', sourceLevel: 'textbook'),
          selection,
        ),
        isTrue,
      );
    });

    test('题号边界 0 让 isEmpty 为 false 但实际不约束', () {
      const QuestionPackSelection selection =
          QuestionPackSelection(serialFrom: 0);
      expect(selection.isEmpty, isFalse);
      expect(selection.hasSerialRange, isTrue);
      expect(
        questionPackRecordMatchesSelection(packRecord(serialNo: 99), selection),
        isTrue,
      );
      expect(
        questionPackRecordMatchesSelection(
            packRecord(serialNo: null), selection),
        isTrue,
      );
    });

    test('只给上界时 hasSerialRange 为 true', () {
      const QuestionPackSelection selection =
          QuestionPackSelection(serialTo: 5);
      expect(selection.hasSerialRange, isTrue);
      expect(selection.isEmpty, isFalse);
    });
  });

  group('学科与来源等级', () {
    test('学科单选命中', () {
      const QuestionPackSelection selection = QuestionPackSelection(
        subjectKeys: <String>{'math'},
      );
      expect(
        questionPackRecordMatchesSelection(
            packRecord(subjectKey: 'math'), selection),
        isTrue,
      );
    });

    test('学科单选不命中', () {
      const QuestionPackSelection selection = QuestionPackSelection(
        subjectKeys: <String>{'physics'},
      );
      expect(
        questionPackRecordMatchesSelection(
            packRecord(subjectKey: 'math'), selection),
        isFalse,
      );
    });

    test('学科比较区分大小写', () {
      const QuestionPackSelection selection = QuestionPackSelection(
        subjectKeys: <String>{'Math'},
      );
      expect(
        questionPackRecordMatchesSelection(
            packRecord(subjectKey: 'math'), selection),
        isFalse,
      );
    });

    test('学科与来源两边都 trim', () {
      const QuestionPackSelection selection = QuestionPackSelection(
        subjectKeys: <String>{' math '},
        sourceLevels: <String>{' exam '},
      );
      expect(
        questionPackRecordMatchesSelection(
          packRecord(subjectKey: 'math', sourceLevel: 'exam'),
          selection,
        ),
        isTrue,
      );
    });

    test('来源等级多选任一命中', () {
      const QuestionPackSelection selection = QuestionPackSelection(
        sourceLevels: <String>{'exam', 'textbook'},
      );
      expect(
        questionPackRecordMatchesSelection(
          packRecord(sourceLevel: 'textbook'),
          selection,
        ),
        isTrue,
      );
      expect(
        questionPackRecordMatchesSelection(
          packRecord(sourceLevel: 'unknown'),
          selection,
        ),
        isFalse,
      );
    });

    test('学科与来源等级是 AND', () {
      const QuestionPackSelection selection = QuestionPackSelection(
        subjectKeys: <String>{'math'},
        sourceLevels: <String>{'exam'},
      );
      expect(
        questionPackRecordMatchesSelection(
          packRecord(subjectKey: 'math', sourceLevel: 'exam'),
          selection,
        ),
        isTrue,
      );
      expect(
        questionPackRecordMatchesSelection(
          packRecord(subjectKey: 'math', sourceLevel: 'textbook'),
          selection,
        ),
        isFalse,
      );
    });

    test('未选维度不约束', () {
      const QuestionPackSelection selection = QuestionPackSelection(
        subjectKeys: <String>{'math'},
      );
      expect(
        questionPackRecordMatchesSelection(
          packRecord(subjectKey: 'math', sourceLevel: 'anything'),
          selection,
        ),
        isTrue,
      );
    });
  });

  group('标签路径', () {
    test('任一标签命中', () {
      const QuestionPackSelection selection = QuestionPackSelection(
        tagPaths: <String>{'物理', '数学/函数'},
      );
      final QuestionPackRecord record = packRecord(
        tagPaths: const <String>['数学', '数学/函数', '单调性'],
      );
      expect(questionPackRecordMatchesSelection(record, selection), isTrue);
    });

    test('标签两边 trim', () {
      const QuestionPackSelection selection = QuestionPackSelection(
        tagPaths: <String>{' 数学 '},
      );
      final QuestionPackRecord record = packRecord(
        tagPaths: const <String>['数学'],
      );
      expect(questionPackRecordMatchesSelection(record, selection), isTrue);
    });

    test('条件里的空串忽略', () {
      const QuestionPackSelection selection = QuestionPackSelection(
        tagPaths: <String>{'  '},
      );
      expect(
        questionPackRecordMatchesSelection(packRecord(), selection),
        isTrue,
      );
    });

    test('子串不算命中', () {
      const QuestionPackSelection selection = QuestionPackSelection(
        tagPaths: <String>{'数学'},
      );
      final QuestionPackRecord record = packRecord(
        tagPaths: const <String>['数学/函数'],
      );
      expect(questionPackRecordMatchesSelection(record, selection), isFalse);
    });

    test('记录没有标签时条件有标签不命中', () {
      const QuestionPackSelection selection = QuestionPackSelection(
        tagPaths: <String>{'数学'},
      );
      expect(
        questionPackRecordMatchesSelection(packRecord(), selection),
        isFalse,
      );
    });

    test('记录标签多于条件时命中一个即可', () {
      const QuestionPackSelection selection = QuestionPackSelection(
        tagPaths: <String>{'数学'},
      );
      final QuestionPackRecord record = packRecord(
        tagPaths: const <String>['数学', '语文', '英语'],
      );
      expect(questionPackRecordMatchesSelection(record, selection), isTrue);
    });
  });

  group('题号区间', () {
    test('区间包含两端', () {
      const QuestionPackSelection selection = QuestionPackSelection(
        serialFrom: 1,
        serialTo: 5,
      );
      expect(
        questionPackRecordMatchesSelection(packRecord(serialNo: 1), selection),
        isTrue,
      );
      expect(
        questionPackRecordMatchesSelection(packRecord(serialNo: 5), selection),
        isTrue,
      );
      expect(
        questionPackRecordMatchesSelection(packRecord(serialNo: 0), selection),
        isFalse,
      );
      expect(
        questionPackRecordMatchesSelection(packRecord(serialNo: 6), selection),
        isFalse,
      );
    });

    test('只给下界时按大于等于判断', () {
      const QuestionPackSelection selection =
          QuestionPackSelection(serialFrom: 3);
      expect(
        questionPackRecordMatchesSelection(packRecord(serialNo: 3), selection),
        isTrue,
      );
      expect(
        questionPackRecordMatchesSelection(packRecord(serialNo: 2), selection),
        isFalse,
      );
    });

    test('只给上界时按小于等于判断', () {
      const QuestionPackSelection selection =
          QuestionPackSelection(serialTo: 5);
      expect(
        questionPackRecordMatchesSelection(packRecord(serialNo: 1), selection),
        isTrue,
      );
      expect(
        questionPackRecordMatchesSelection(packRecord(serialNo: 5), selection),
        isTrue,
      );
      expect(
        questionPackRecordMatchesSelection(packRecord(serialNo: 6), selection),
        isFalse,
      );
    });

    test('没有题号且给了区间不命中', () {
      const QuestionPackSelection selection =
          QuestionPackSelection(serialFrom: 1);
      expect(
        questionPackRecordMatchesSelection(
            packRecord(serialNo: null), selection),
        isFalse,
      );
    });

    test('没有题号且没给区间命中', () {
      expect(
        questionPackRecordMatchesSelection(
          packRecord(serialNo: null),
          const QuestionPackSelection(),
        ),
        isTrue,
      );
    });

    test('反向区间交换归一', () {
      const QuestionPackSelection selection = QuestionPackSelection(
        serialFrom: 10,
        serialTo: 2,
      );
      for (final int? no in <int?>[2, 5, 10]) {
        expect(
          questionPackRecordMatchesSelection(
              packRecord(serialNo: no), selection),
          isTrue,
          reason: 'serialNo=$no',
        );
      }
      expect(
        questionPackRecordMatchesSelection(packRecord(serialNo: 1), selection),
        isFalse,
      );
      expect(
        questionPackRecordMatchesSelection(packRecord(serialNo: 11), selection),
        isFalse,
      );
    });

    test('下界 0 视为未给', () {
      const QuestionPackSelection selection = QuestionPackSelection(
        serialFrom: 0,
        serialTo: 3,
      );
      expect(
        questionPackRecordMatchesSelection(packRecord(serialNo: 1), selection),
        isTrue,
      );
      expect(
        questionPackRecordMatchesSelection(packRecord(serialNo: 3), selection),
        isTrue,
      );
      expect(
        questionPackRecordMatchesSelection(packRecord(serialNo: 4), selection),
        isFalse,
      );
    });

    test('负数边界视为未给', () {
      const QuestionPackSelection selection = QuestionPackSelection(
        serialFrom: -5,
        serialTo: -1,
      );
      expect(
        questionPackRecordMatchesSelection(
            packRecord(serialNo: null), selection),
        isTrue,
      );
      expect(
        questionPackRecordMatchesSelection(packRecord(serialNo: 99), selection),
        isTrue,
      );
    });

    test('两端都 0 等于不约束', () {
      const QuestionPackSelection selection = QuestionPackSelection(
        serialFrom: 0,
        serialTo: 0,
      );
      expect(selection.hasSerialRange, isTrue);
      expect(
        questionPackRecordMatchesSelection(
            packRecord(serialNo: null), selection),
        isTrue,
      );
      expect(
        questionPackRecordMatchesSelection(packRecord(serialNo: 7), selection),
        isTrue,
      );
    });

    test('题号与其它维度是 AND', () {
      const QuestionPackSelection selection = QuestionPackSelection(
        subjectKeys: <String>{'math'},
        serialFrom: 1,
        serialTo: 5,
      );
      expect(
        questionPackRecordMatchesSelection(
          packRecord(subjectKey: 'math', serialNo: 3),
          selection,
        ),
        isTrue,
      );
      expect(
        questionPackRecordMatchesSelection(
          packRecord(subjectKey: 'physics', serialNo: 3),
          selection,
        ),
        isFalse,
      );
      expect(
        questionPackRecordMatchesSelection(
          packRecord(subjectKey: 'math', serialNo: 9),
          selection,
        ),
        isFalse,
      );
    });
  });

  group('normalizeSerialBound', () {
    test('去掉前导零并 trim', () {
      expect(normalizeSerialBound('0012'), 12);
      expect(normalizeSerialBound(' 7 '), 7);
      expect(normalizeSerialBound('0'), 0);
      expect(normalizeSerialBound('000'), 0);
    });

    test('空输入返回 null', () {
      expect(normalizeSerialBound(null), isNull);
      expect(normalizeSerialBound(''), isNull);
      expect(normalizeSerialBound('   '), isNull);
    });

    test('非纯半角数字返回 null', () {
      for (final String raw in <String>[
        '12a',
        '1.5',
        '+3',
        '-3',
        '1 2',
        '１',
        '三',
      ]) {
        expect(normalizeSerialBound(raw), isNull, reason: raw);
      }
    });

    test('超出 int 范围返回 null', () {
      expect(normalizeSerialBound('999999999999999999999999999999'), isNull);
    });

    test('返回值可以直接接回筛选条件', () {
      final int? from = normalizeSerialBound('3');
      final int? to = normalizeSerialBound('5 ');
      final QuestionPackSelection selection = QuestionPackSelection(
        serialFrom: from,
        serialTo: to,
      );
      expect(from, 3);
      expect(to, 5);
      expect(
        questionPackRecordMatchesSelection(packRecord(serialNo: 4), selection),
        isTrue,
      );
      expect(
        questionPackRecordMatchesSelection(packRecord(serialNo: 6), selection),
        isFalse,
      );
    });
  });

  group('selectQuestionPackRecords', () {
    test('保持原顺序', () {
      final List<QuestionPackRecord> records = <QuestionPackRecord>[
        packRecord(stem: '一', serialNo: 1),
        packRecord(stem: '二', serialNo: 9),
        packRecord(stem: '三', serialNo: 2),
      ];
      final List<QuestionPackRecord> selected = selectQuestionPackRecords(
        records: records,
        selection: const QuestionPackSelection(serialFrom: 1, serialTo: 5),
      );
      expect(selected, <QuestionPackRecord>[records[0], records[2]]);
    });

    test('返回不可变列表', () {
      final List<QuestionPackRecord> selected = selectQuestionPackRecords(
        records: <QuestionPackRecord>[packRecord()],
        selection: const QuestionPackSelection(),
      );
      expect(() => selected.add(packRecord()), throwsUnsupportedError);
    });

    test('不修改入参列表', () {
      final List<QuestionPackRecord> records = <QuestionPackRecord>[
        packRecord(stem: '一', serialNo: 1),
        packRecord(stem: '二', serialNo: 9),
      ];
      final List<QuestionPackRecord> snapshot =
          List<QuestionPackRecord>.of(records);
      selectQuestionPackRecords(
        records: records,
        selection: const QuestionPackSelection(serialFrom: 1, serialTo: 5),
      );
      expect(records, snapshot);
    });

    test('空列表返回空', () {
      expect(
        selectQuestionPackRecords(
          records: const <QuestionPackRecord>[],
          selection: const QuestionPackSelection(),
        ),
        isEmpty,
      );
    });

    test('全部不命中返回空', () {
      final List<QuestionPackRecord> selected = selectQuestionPackRecords(
        records: <QuestionPackRecord>[
          packRecord(subjectKey: 'math'),
          packRecord(subjectKey: 'physics'),
        ],
        selection: const QuestionPackSelection(
          subjectKeys: <String>{'chemistry'},
        ),
      );
      expect(selected, isEmpty);
    });

    test('重复调用结果一致', () {
      final List<QuestionPackRecord> records = <QuestionPackRecord>[
        packRecord(stem: '一', serialNo: 1),
        packRecord(stem: '二', serialNo: 9),
      ];
      const QuestionPackSelection selection = QuestionPackSelection(
        serialFrom: 1,
        serialTo: 5,
      );
      final List<QuestionPackRecord> first = selectQuestionPackRecords(
        records: records,
        selection: selection,
      );
      final List<QuestionPackRecord> second = selectQuestionPackRecords(
        records: records,
        selection: selection,
      );
      expect(first, second);
    });
  });

  group('toJson 与值对象', () {
    test('toJson 键顺序固定', () {
      final Map<String, Object?> json = const QuestionPackSelection(
        subjectKeys: <String>{'math'},
        sourceLevels: <String>{'exam'},
        tagPaths: <String>{'数学'},
        serialFrom: 1,
        serialTo: 5,
      ).toJson();
      expect(
        json.keys.toList(),
        <String>[
          'subject_keys',
          'source_levels',
          'tag_paths',
          'serial_from',
          'serial_to',
        ],
      );
    });

    test('集合排序后输出且与插入顺序无关', () {
      const QuestionPackSelection first = QuestionPackSelection(
        subjectKeys: <String>{'z', 'a', 'm'},
        sourceLevels: <String>{'textbook', 'exam'},
        tagPaths: <String>{'语文', '数学'},
      );
      const QuestionPackSelection second = QuestionPackSelection(
        subjectKeys: <String>{'m', 'z', 'a'},
        sourceLevels: <String>{'exam', 'textbook'},
        tagPaths: <String>{'数学', '语文'},
      );
      expect(first.toJson(), second.toJson());
      expect(first.toJson()['subject_keys'], <String>['a', 'm', 'z']);
      expect(first.toJson()['source_levels'], <String>['exam', 'textbook']);
      expect(first.toJson()['tag_paths'], <String>['数学', '语文']);
    });

    test('toJson 的集合列表不可变', () {
      final Map<String, Object?> json =
          const QuestionPackSelection(subjectKeys: <String>{'math'}).toJson();
      final List<String> subjects = json['subject_keys']! as List<String>;
      expect(() => subjects.add('physics'), throwsUnsupportedError);
    });

    test('null 题号边界仍输出键', () {
      final Map<String, Object?> json = const QuestionPackSelection().toJson();
      expect(json.containsKey('serial_from'), isTrue);
      expect(json.containsKey('serial_to'), isTrue);
      expect(json['serial_from'], isNull);
      expect(json['serial_to'], isNull);
    });

    test('集合顺序不影响相等与 hashCode', () {
      const QuestionPackSelection first = QuestionPackSelection(
        subjectKeys: <String>{'b', 'a'},
      );
      const QuestionPackSelection second = QuestionPackSelection(
        subjectKeys: <String>{'a', 'b'},
      );
      expect(first, second);
      expect(first.hashCode, second.hashCode);
    });

    test('题号边界影响相等', () {
      const QuestionPackSelection first = QuestionPackSelection(serialFrom: 1);
      const QuestionPackSelection second = QuestionPackSelection(serialFrom: 2);
      expect(first == second, isFalse);
    });

    test('不同集合不相等', () {
      const QuestionPackSelection first = QuestionPackSelection(
        subjectKeys: <String>{'math'},
      );
      const QuestionPackSelection second = QuestionPackSelection(
        subjectKeys: <String>{'physics'},
      );
      expect(first == second, isFalse);
    });

    test('相等按原始集合内容，不做 trim 归一', () {
      const QuestionPackSelection untrimmed = QuestionPackSelection(
        subjectKeys: <String>{' math '},
      );
      const QuestionPackSelection trimmed = QuestionPackSelection(
        subjectKeys: <String>{'math'},
      );
      expect(untrimmed == trimmed, isFalse);
      expect(
        questionPackRecordMatchesSelection(
          packRecord(subjectKey: 'math'),
          untrimmed,
        ),
        isTrue,
      );
      expect(
        questionPackRecordMatchesSelection(
          packRecord(subjectKey: 'math'),
          trimmed,
        ),
        isTrue,
      );
    });

    test('toString 便于调试', () {
      const QuestionPackSelection selection = QuestionPackSelection(
        subjectKeys: <String>{'math'},
        serialFrom: 1,
      );
      final String text = selection.toString();
      expect(text, contains('QuestionPackSelection'));
      expect(text, contains('subjectKeys'));
      expect(text, contains('[math]'));
      expect(text, contains('serialFrom: 1'));
    });
  });

  group('字段判定与记录判定一致', () {
    test('学科命中时两种判定一致', () {
      final QuestionPackRecord record = packRecord(
        subjectKey: 'math',
        sourceLevel: 'exam',
        serialNo: 3,
        tagPaths: const <String>['数学/函数'],
      );
      const QuestionPackSelection selection = QuestionPackSelection(
        subjectKeys: <String>{' math '},
        serialFrom: 1,
        serialTo: 5,
      );
      expect(
        questionPackRecordMatchesSelection(record, selection),
        questionPackFieldsMatchSelection(
          subjectKey: record.subjectKey,
          sourceLevel: record.sourceLevel,
          serialNo: record.serialNo,
          tagPaths: record.tagPaths,
          selection: selection,
        ),
      );
    });

    test('来源不命中时两种判定一致', () {
      final QuestionPackRecord record = packRecord(
        sourceLevel: 'textbook',
        serialNo: 3,
      );
      const QuestionPackSelection selection = QuestionPackSelection(
        sourceLevels: <String>{'exam'},
      );
      expect(questionPackRecordMatchesSelection(record, selection), isFalse);
      expect(
        questionPackFieldsMatchSelection(
          subjectKey: record.subjectKey,
          sourceLevel: record.sourceLevel,
          serialNo: record.serialNo,
          tagPaths: record.tagPaths,
          selection: selection,
        ),
        isFalse,
      );
    });

    test('没有题号且区间存在时两种判定一致', () {
      final QuestionPackRecord record = packRecord(serialNo: null);
      const QuestionPackSelection selection =
          QuestionPackSelection(serialTo: 5);
      expect(questionPackRecordMatchesSelection(record, selection), isFalse);
      expect(
        questionPackFieldsMatchSelection(
          subjectKey: record.subjectKey,
          sourceLevel: record.sourceLevel,
          serialNo: record.serialNo,
          tagPaths: record.tagPaths,
          selection: selection,
        ),
        isFalse,
      );
    });

    test('空条件时两种判定一致', () {
      final QuestionPackRecord record = packRecord(
        subjectKey: '',
        sourceLevel: 'unknown',
        serialNo: null,
      );
      const QuestionPackSelection selection = QuestionPackSelection();
      expect(questionPackRecordMatchesSelection(record, selection), isTrue);
      expect(
        questionPackFieldsMatchSelection(
          subjectKey: record.subjectKey,
          sourceLevel: record.sourceLevel,
          serialNo: record.serialNo,
          tagPaths: record.tagPaths,
          selection: selection,
        ),
        isTrue,
      );
    });

    test('标签与题号组合两种判定一致', () {
      final QuestionPackRecord record = packRecord(
        serialNo: 4,
        tagPaths: const <String>['数学', '函数'],
      );
      const QuestionPackSelection selection = QuestionPackSelection(
        tagPaths: <String>{'物理', ' 函数 '},
        serialFrom: 1,
        serialTo: 3,
      );
      expect(questionPackRecordMatchesSelection(record, selection), isFalse);
      expect(
        questionPackFieldsMatchSelection(
          subjectKey: record.subjectKey,
          sourceLevel: record.sourceLevel,
          serialNo: record.serialNo,
          tagPaths: record.tagPaths,
          selection: selection,
        ),
        isFalse,
      );
    });
  });

  group('题号单边开放（回归）', () {
    List<QuestionPackRecord> threeRecords() {
      return <QuestionPackRecord>[
        packRecord(stem: '一', serialNo: 1),
        packRecord(stem: '二', serialNo: 2),
        packRecord(stem: '三', serialNo: 3),
      ];
    }

    List<int?> serialsOf(List<QuestionPackRecord> records) {
      return records
          .map((QuestionPackRecord record) => record.serialNo)
          .toList();
    }

    test('只给 serialFrom 时上界开放，命中 2 和 3', () {
      const QuestionPackSelection selection =
          QuestionPackSelection(serialFrom: 2);
      final List<QuestionPackRecord> selected = selectQuestionPackRecords(
        records: threeRecords(),
        selection: selection,
      );
      expect(serialsOf(selected), <int?>[2, 3]);
    });

    test('只给 serialTo 时下界开放，命中 1 和 2', () {
      const QuestionPackSelection selection =
          QuestionPackSelection(serialTo: 2);
      final List<QuestionPackRecord> selected = selectQuestionPackRecords(
        records: threeRecords(),
        selection: selection,
      );
      expect(serialsOf(selected), <int?>[1, 2]);
    });

    test('两端都给且反向时交换归一', () {
      const QuestionPackSelection selection =
          QuestionPackSelection(serialFrom: 3, serialTo: 2);
      final List<QuestionPackRecord> selected = selectQuestionPackRecords(
        records: threeRecords(),
        selection: selection,
      );
      expect(serialsOf(selected), <int?>[2, 3]);
    });

    test('只给 serialFrom 且题号为 null 不命中', () {
      const QuestionPackSelection selection =
          QuestionPackSelection(serialFrom: 2);
      expect(
        questionPackRecordMatchesSelection(
          packRecord(stem: '无题号'),
          selection,
        ),
        isFalse,
      );
      expect(
        questionPackRecordMatchesSelection(
          packRecord(stem: '有题号', serialNo: 2),
          selection,
        ),
        isTrue,
      );
      expect(
        questionPackRecordMatchesSelection(
          packRecord(stem: '有题号', serialNo: 1),
          selection,
        ),
        isFalse,
      );
    });

    test('边界 <=0 仍视为未给，不缩窄结果', () {
      const QuestionPackSelection fromZero =
          QuestionPackSelection(serialFrom: 0);
      expect(
        selectQuestionPackRecords(
          records: threeRecords(),
          selection: fromZero,
        ).length,
        3,
      );
      expect(
        questionPackRecordMatchesSelection(
          packRecord(stem: '无题号'),
          fromZero,
        ),
        isTrue,
      );
      const QuestionPackSelection toNegative =
          QuestionPackSelection(serialTo: -3);
      expect(
        selectQuestionPackRecords(
          records: threeRecords(),
          selection: toNegative,
        ).length,
        3,
      );
    });
  });
}
