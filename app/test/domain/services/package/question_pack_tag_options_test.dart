import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/package/question_pack_tag_options.dart';

List<String> pathsOf(List<QuestionPackTagPathOption> options) {
  return options
      .map((QuestionPackTagPathOption option) => option.path)
      .toList();
}

bool selectedOf(List<QuestionPackTagPathOption> options, String path) {
  return options
      .firstWhere((QuestionPackTagPathOption option) => option.path == path)
      .selected;
}

void main() {
  group('normalizeQuestionPackTagPath', () {
    test('null 返回 null', () {
      expect(normalizeQuestionPackTagPath(null), isNull);
    });

    test('空白串返回 null', () {
      expect(normalizeQuestionPackTagPath(''), isNull);
      expect(normalizeQuestionPackTagPath('   '), isNull);
      expect(normalizeQuestionPackTagPath('\t\n'), isNull);
    });

    test('去掉两端空白', () {
      expect(normalizeQuestionPackTagPath('  数学/函数  '), '数学/函数');
    });

    test('全角空格也去掉', () {
      expect(normalizeQuestionPackTagPath('\u3000数学/函数\u3000'), '数学/函数');
    });

    test('内部连续空白不压缩', () {
      expect(normalizeQuestionPackTagPath(' 数学  /  函数 '), '数学  /  函数');
    });

    test('普通路径原样返回', () {
      expect(normalizeQuestionPackTagPath('数学/函数/单调性'), '数学/函数/单调性');
    });
  });

  group('selectedQuestionPackTagPaths', () {
    test('空输入返回空集合', () {
      expect(selectedQuestionPackTagPaths(const <String>[]), isEmpty);
    });

    test('trim 并丢掉空串', () {
      final Set<String> selected = selectedQuestionPackTagPaths(
        <String>[' 数学 ', '', '  ', '函数'],
      );
      expect(selected, <String>{'数学', '函数'});
    });

    test('去重', () {
      final Set<String> selected = selectedQuestionPackTagPaths(
        <String>['数学', ' 数学 ', '数学'],
      );
      expect(selected, <String>{'数学'});
    });

    test('返回不可变集合', () {
      final Set<String> selected = selectedQuestionPackTagPaths(
        <String>['数学'],
      );
      expect(() => selected.add('函数'), throwsUnsupportedError);
    });

    test('区分大小写', () {
      final Set<String> selected = selectedQuestionPackTagPaths(
        <String>['Math', 'math'],
      );
      expect(selected, <String>{'Math', 'math'});
    });
  });

  group('选项生成', () {
    test('空输入返回空列表', () {
      expect(questionPackTagPathOptions(tagPaths: const <String>[]), isEmpty);
    });

    test('丢弃空白和空串路径', () {
      final List<QuestionPackTagPathOption> options =
          questionPackTagPathOptions(
        tagPaths: <String>['', '  ', '数学'],
      );
      expect(pathsOf(options), <String>['数学']);
    });

    test('按归一后的路径去重且首次出现为准', () {
      final List<QuestionPackTagPathOption> options =
          questionPackTagPathOptions(
        tagPaths: <String>['b', 'a', ' b ', 'a'],
        questionCountByPath: const <String, int>{'a': 1, 'b': 2},
      );
      expect(pathsOf(options), <String>['b', 'a']);
      expect(
        options
            .firstWhere(
                (QuestionPackTagPathOption option) => option.path == 'b')
            .questionCount,
        2,
      );
    });

    test('缺失计数按 0', () {
      final List<QuestionPackTagPathOption> options =
          questionPackTagPathOptions(tagPaths: <String>['数学']);
      expect(options.single.questionCount, 0);
    });

    test('负数计数归 0', () {
      final List<QuestionPackTagPathOption> options =
          questionPackTagPathOptions(
        tagPaths: <String>['数学'],
        questionCountByPath: const <String, int>{'数学': -5},
      );
      expect(options.single.questionCount, 0);
    });

    test('返回不可变列表', () {
      final List<QuestionPackTagPathOption> options =
          questionPackTagPathOptions(tagPaths: <String>['数学']);
      expect(
        () => options.add(
          const QuestionPackTagPathOption(path: '函数', questionCount: 0),
        ),
        throwsUnsupportedError,
      );
    });

    test('路径区分大小写不合并', () {
      final List<QuestionPackTagPathOption> options =
          questionPackTagPathOptions(tagPaths: <String>['Math', 'math']);
      expect(pathsOf(options), <String>['Math', 'math']);
    });
  });

  group('排序', () {
    test('先按题目数降序', () {
      final List<QuestionPackTagPathOption> options =
          questionPackTagPathOptions(
        tagPaths: <String>['a', 'b', 'c'],
        questionCountByPath: const <String, int>{'a': 1, 'b': 3, 'c': 2},
      );
      expect(pathsOf(options), <String>['b', 'c', 'a']);
    });

    test('题目数相同时按路径 compareTo 升序', () {
      final List<QuestionPackTagPathOption> options =
          questionPackTagPathOptions(
        tagPaths: <String>['b', 'a', 'c'],
        questionCountByPath: const <String, int>{'a': 2, 'b': 2, 'c': 2},
      );
      expect(pathsOf(options), <String>['a', 'b', 'c']);
    });

    test('比较按代码单元，与语言无关（大写先于小写）', () {
      final List<QuestionPackTagPathOption> options =
          questionPackTagPathOptions(
        tagPaths: <String>['a', 'Z'],
        questionCountByPath: const <String, int>{'a': 1, 'Z': 1},
      );
      expect(pathsOf(options), <String>['Z', 'a']);
    });

    test('零计数排在最后', () {
      final List<QuestionPackTagPathOption> options =
          questionPackTagPathOptions(
        tagPaths: <String>['零', '有'],
        questionCountByPath: const <String, int>{'有': 1},
      );
      expect(pathsOf(options), <String>['有', '零']);
    });

    test('输入顺序不影响排序结果', () {
      final List<QuestionPackTagPathOption> first = questionPackTagPathOptions(
        tagPaths: <String>['a', 'b', 'c'],
        questionCountByPath: const <String, int>{'a': 1, 'c': 2},
      );
      final List<QuestionPackTagPathOption> second = questionPackTagPathOptions(
        tagPaths: <String>['c', 'a', 'b'],
        questionCountByPath: const <String, int>{'a': 1, 'c': 2},
      );
      expect(pathsOf(first), pathsOf(second));
      expect(pathsOf(first), <String>['c', 'a', 'b']);
    });
  });

  group('selected 行为', () {
    test('selected 用 trim 后精确匹配', () {
      final List<QuestionPackTagPathOption> options =
          questionPackTagPathOptions(
        tagPaths: <String>['数学', '函数'],
        selectedPaths: <String>{' 数学 '},
      );
      expect(selectedOf(options, '数学'), isTrue);
      expect(selectedOf(options, '函数'), isFalse);
    });

    test('selected 不改变排序', () {
      final List<QuestionPackTagPathOption> options =
          questionPackTagPathOptions(
        tagPaths: <String>['a', 'b'],
        questionCountByPath: const <String, int>{'a': 5, 'b': 1},
        selectedPaths: <String>{'b'},
      );
      expect(pathsOf(options), <String>['a', 'b']);
      expect(selectedOf(options, 'b'), isTrue);
    });

    test('selected 超出 maxOptionCount 仍保留', () {
      final List<QuestionPackTagPathOption> options =
          questionPackTagPathOptions(
        tagPaths: <String>['a', 'b', 'c'],
        questionCountByPath: const <String, int>{'a': 5, 'b': 3, 'c': 1},
        selectedPaths: <String>{'c'},
        maxOptionCount: 1,
      );
      expect(pathsOf(options), <String>['a', 'c']);
      expect(selectedOf(options, 'c'), isTrue);
    });

    test('maxOptionCount <= 0 时只保留 selected', () {
      final List<QuestionPackTagPathOption> options =
          questionPackTagPathOptions(
        tagPaths: <String>['a', 'b', 'c'],
        selectedPaths: <String>{'b'},
        maxOptionCount: 0,
      );
      expect(pathsOf(options), <String>['b']);
    });

    test('maxOptionCount < 0 且无 selected 时返回空', () {
      final List<QuestionPackTagPathOption> options =
          questionPackTagPathOptions(
        tagPaths: <String>['a', 'b'],
        maxOptionCount: -1,
      );
      expect(options, isEmpty);
    });

    test('selected 里不在 tagPaths 的路径不凭空生成选项', () {
      final List<QuestionPackTagPathOption> options =
          questionPackTagPathOptions(
        tagPaths: <String>['a'],
        selectedPaths: <String>{'不存在'},
      );
      expect(pathsOf(options), <String>['a']);
      expect(selectedOf(options, 'a'), isFalse);
    });

    test('selected 区分大小写', () {
      final List<QuestionPackTagPathOption> options =
          questionPackTagPathOptions(
        tagPaths: <String>['math'],
        selectedPaths: <String>{'MATH'},
      );
      expect(selectedOf(options, 'math'), isFalse);
    });
  });

  group('maxOptionCount', () {
    test('截断到上限', () {
      final List<QuestionPackTagPathOption> options =
          questionPackTagPathOptions(
        tagPaths: <String>['a', 'b', 'c', 'd', 'e'],
        questionCountByPath: const <String, int>{
          'a': 5,
          'b': 4,
          'c': 3,
          'd': 2,
          'e': 1,
        },
        maxOptionCount: 2,
      );
      expect(pathsOf(options), <String>['a', 'b']);
    });

    test('上限大于总数时返回全部', () {
      final List<QuestionPackTagPathOption> options =
          questionPackTagPathOptions(
        tagPaths: <String>['a', 'b'],
        maxOptionCount: 10,
      );
      expect(options.length, 2);
    });

    test('默认上限 200', () {
      final List<String> many = List<String>.generate(
        205,
        (int index) => 'tag-$index',
      );
      final List<QuestionPackTagPathOption> options =
          questionPackTagPathOptions(tagPaths: many);
      expect(options.length, 200);
    });
  });

  group('值对象', () {
    test('toJson 键顺序固定', () {
      const QuestionPackTagPathOption option = QuestionPackTagPathOption(
        path: '数学/函数',
        questionCount: 3,
        selected: true,
      );
      expect(
        option.toJson().keys.toList(),
        <String>['path', 'question_count', 'selected'],
      );
    });

    test('toJson 输出字段值', () {
      const QuestionPackTagPathOption option = QuestionPackTagPathOption(
        path: '数学',
        questionCount: 0,
      );
      expect(option.toJson(), <String, Object?>{
        'path': '数学',
        'question_count': 0,
        'selected': false,
      });
    });

    test('相同值相等且 hashCode 一致', () {
      const QuestionPackTagPathOption first = QuestionPackTagPathOption(
        path: '数学',
        questionCount: 2,
        selected: true,
      );
      const QuestionPackTagPathOption second = QuestionPackTagPathOption(
        path: '数学',
        questionCount: 2,
        selected: true,
      );
      expect(first, second);
      expect(first.hashCode, second.hashCode);
    });

    test('selected 不同不相等', () {
      const QuestionPackTagPathOption first = QuestionPackTagPathOption(
        path: '数学',
        questionCount: 2,
      );
      const QuestionPackTagPathOption second = QuestionPackTagPathOption(
        path: '数学',
        questionCount: 2,
        selected: true,
      );
      expect(first == second, isFalse);
    });

    test('questionCount 不同不相等', () {
      const QuestionPackTagPathOption first = QuestionPackTagPathOption(
        path: '数学',
        questionCount: 1,
      );
      const QuestionPackTagPathOption second = QuestionPackTagPathOption(
        path: '数学',
        questionCount: 2,
      );
      expect(first == second, isFalse);
    });

    test('toString 含路径、计数与选中状态', () {
      const QuestionPackTagPathOption option = QuestionPackTagPathOption(
        path: '数学',
        questionCount: 7,
        selected: true,
      );
      final String text = option.toString();
      expect(text, contains('数学'));
      expect(text, contains('7'));
      expect(text, contains('selected'));
    });
  });

  group('weight 与 isEmpty', () {
    test('weight 等于题目数', () {
      const QuestionPackTagPathOption option = QuestionPackTagPathOption(
        path: '数学',
        questionCount: 42,
      );
      expect(option.weight, 42);
    });

    test('正常构造的选项不为空', () {
      const QuestionPackTagPathOption option = QuestionPackTagPathOption(
        path: '数学',
        questionCount: 0,
      );
      expect(option.isEmpty, isFalse);
    });

    test('空白路径手动构造时 isEmpty 为 true', () {
      const QuestionPackTagPathOption option = QuestionPackTagPathOption(
        path: '   ',
        questionCount: 0,
      );
      expect(option.isEmpty, isTrue);
    });

    test('const 构造可直接用于常量', () {
      const QuestionPackTagPathOption option = QuestionPackTagPathOption(
        path: '数学',
        questionCount: 1,
      );
      expect(option.toJson()['path'], '数学');
    });
  });
}
