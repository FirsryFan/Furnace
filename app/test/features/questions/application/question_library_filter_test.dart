/// 题库筛选纯逻辑的单元测试。
///
/// 覆盖 9 组：空筛选、学科、标签子树、文字、题号、错题本、组合、
/// copyWith/相等性、过滤列表与健壮性。全部纯 Dart 构造
/// [QuestionLibraryEntry] 假数据，不读库。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/features/questions/application/question_library_filter.dart';
import 'package:furnace/features/questions/application/question_library_reader.dart';

void main() {
  group('空筛选', () {
    test('默认构造是空筛选', () {
      const QuestionLibraryFilter filter = QuestionLibraryFilter();
      expect(filter.isEmpty, isTrue);
      expect(filter.isNotEmpty, isFalse);
      expect(filter.subjectKey, '');
      expect(filter.tagPaths, isEmpty);
      expect(filter.text, '');
    });

    test('只有空白输入也是空筛选', () {
      const QuestionLibraryFilter filter = QuestionLibraryFilter(
        subjectKey: '  ',
        tagPaths: <String>{' ', ''},
        text: '\t ',
      );
      expect(filter.isEmpty, isTrue);
    });

    test('空筛选命中任意题', () {
      const QuestionLibraryFilter filter = QuestionLibraryFilter();
      expect(questionLibraryEntryMatches(_entry(), filter), isTrue);
      expect(
        questionLibraryEntryMatches(
          _entry(serialNo: null, title: '', subjectKey: 'physics'),
          filter,
        ),
        isTrue,
      );
    });

    test('空筛选返回全部条目且保序', () {
      final List<QuestionLibraryEntry> entries = <QuestionLibraryEntry>[
        _entry(questionId: 'q3'),
        _entry(questionId: 'q1'),
        _entry(questionId: 'q2'),
      ];
      final List<QuestionLibraryEntry> result = filterQuestionLibraryEntries(
        entries,
        const QuestionLibraryFilter(),
      );
      expect(_ids(result), <String>['q3', 'q1', 'q2']);
    });

    test('空筛选结果不可变', () {
      final List<QuestionLibraryEntry> result = filterQuestionLibraryEntries(
        <QuestionLibraryEntry>[_entry()],
        const QuestionLibraryFilter(),
      );
      expect(
          () => result.add(_entry(questionId: 'q2')), throwsUnsupportedError);
    });

    test('空条目返回空列表', () {
      final List<QuestionLibraryEntry> result = filterQuestionLibraryEntries(
        const <QuestionLibraryEntry>[],
        const QuestionLibraryFilter(),
      );
      expect(result, isEmpty);
      expect(() => result.add(_entry()), throwsUnsupportedError);
    });
  });

  group('学科', () {
    test('学科精确命中', () {
      const QuestionLibraryFilter filter =
          QuestionLibraryFilter(subjectKey: 'math');
      expect(questionLibraryEntryMatches(_entry(subjectKey: 'math'), filter),
          isTrue);
      expect(questionLibraryEntryMatches(_entry(subjectKey: 'physics'), filter),
          isFalse);
    });

    test('学科比较大小写敏感', () {
      const QuestionLibraryFilter filter =
          QuestionLibraryFilter(subjectKey: 'math');
      expect(
        questionLibraryEntryMatches(_entry(subjectKey: 'Math'), filter),
        isFalse,
      );
    });

    test('筛选学科先 trim 再比较', () {
      const QuestionLibraryFilter filter =
          QuestionLibraryFilter(subjectKey: ' math ');
      expect(questionLibraryEntryMatches(_entry(subjectKey: 'math'), filter),
          isTrue);
    });

    test('题目学科本身不做 trim，严格相等', () {
      const QuestionLibraryFilter filter =
          QuestionLibraryFilter(subjectKey: 'math');
      expect(
        questionLibraryEntryMatches(_entry(subjectKey: ' math '), filter),
        isFalse,
      );
    });

    test('空学科不限', () {
      const QuestionLibraryFilter filter =
          QuestionLibraryFilter(subjectKey: '');
      expect(questionLibraryEntryMatches(_entry(subjectKey: 'physics'), filter),
          isTrue);
    });

    test('空白学科不限', () {
      const QuestionLibraryFilter filter =
          QuestionLibraryFilter(subjectKey: '   ');
      expect(questionLibraryEntryMatches(_entry(subjectKey: 'physics'), filter),
          isTrue);
    });

    test('学科不命中时即使文字命中也不通过', () {
      const QuestionLibraryFilter filter = QuestionLibraryFilter(
        subjectKey: 'math',
        text: '函数',
      );
      final QuestionLibraryEntry entry = _entry(
        subjectKey: 'physics',
        stem: '函数单调性',
      );
      expect(questionLibraryEntryMatches(entry, filter), isFalse);
    });
  });

  group('标签子树', () {
    const QuestionLibraryFilter subjectFilter = QuestionLibraryFilter(
      tagPaths: <String>{'文化课/学科'},
    );

    test('标签精确保留命中', () {
      const QuestionLibraryFilter filter = QuestionLibraryFilter(
        tagPaths: <String>{'文化课/学科/数学'},
      );
      expect(
        questionLibraryEntryMatches(
          _entry(tagPaths: const <String>['文化课/学科/数学']),
          filter,
        ),
        isTrue,
      );
    });

    test('直接子标签命中父路径', () {
      expect(
        questionLibraryEntryMatches(
          _entry(tagPaths: const <String>['文化课/学科/数学']),
          subjectFilter,
        ),
        isTrue,
      );
    });

    test('多层子孙标签也命中', () {
      expect(
        questionLibraryEntryMatches(
          _entry(tagPaths: const <String>['文化课/学科/数学/函数']),
          subjectFilter,
        ),
        isTrue,
      );
    });

    test('反方向不成立：筛子路径，题只挂父路径', () {
      const QuestionLibraryFilter filter = QuestionLibraryFilter(
        tagPaths: <String>{'文化课/学科/数学'},
      );
      expect(
        questionLibraryEntryMatches(
          _entry(tagPaths: const <String>['文化课/学科']),
          filter,
        ),
        isFalse,
      );
    });

    test('多选标签是 ANY', () {
      const QuestionLibraryFilter filter = QuestionLibraryFilter(
        tagPaths: <String>{'文化课/语文', '文化课/学科/数学'},
      );
      expect(
        questionLibraryEntryMatches(
          _entry(tagPaths: const <String>['文化课/学科/数学']),
          filter,
        ),
        isTrue,
      );
    });

    test('空集不限标签', () {
      const QuestionLibraryFilter filter = QuestionLibraryFilter(
        tagPaths: <String>{},
      );
      expect(
        questionLibraryEntryMatches(
          _entry(tagPaths: const <String>['文化课/学科/数学']),
          filter,
        ),
        isTrue,
      );
    });

    test('空白标签项视为空集', () {
      const QuestionLibraryFilter filter = QuestionLibraryFilter(
        tagPaths: <String>{' ', ''},
      );
      expect(filter.isEmpty, isTrue);
      expect(questionLibraryEntryMatches(_entry(), filter), isTrue);
    });

    test('标签路径大小写敏感', () {
      const QuestionLibraryFilter filter = QuestionLibraryFilter(
        tagPaths: <String>{'Math'},
      );
      expect(
        questionLibraryEntryMatches(
          _entry(tagPaths: const <String>['Math']),
          filter,
        ),
        isTrue,
      );
      expect(
        questionLibraryEntryMatches(
          _entry(tagPaths: const <String>['math']),
          filter,
        ),
        isFalse,
      );
    });

    test('筛选路径与题目路径都 trim', () {
      const QuestionLibraryFilter filter = QuestionLibraryFilter(
        tagPaths: <String>{' 文化课/学科 '},
      );
      expect(
        questionLibraryEntryMatches(
          _entry(tagPaths: const <String>['文化课/学科/数学 ']),
          filter,
        ),
        isTrue,
      );
    });

    test('前缀相似的路径不算子树命中', () {
      expect(
        questionLibraryEntryMatches(
          _entry(tagPaths: const <String>['文化课/学科群']),
          subjectFilter,
        ),
        isFalse,
      );
    });

    test('题目任一标签命中即可', () {
      expect(
        questionLibraryEntryMatches(
          _entry(tagPaths: const <String>['文化课/方法', '文化课/学科/数学']),
          subjectFilter,
        ),
        isTrue,
      );
    });
  });

  group('文字', () {
    test('命中题名', () {
      const QuestionLibraryFilter filter = QuestionLibraryFilter(text: '函数');
      expect(
        questionLibraryEntryMatches(
          _entry(title: '二次函数求最值', subjectKey: 'physics'),
          filter,
        ),
        isTrue,
      );
    });

    test('命中题干', () {
      const QuestionLibraryFilter filter = QuestionLibraryFilter(text: '单调');
      expect(
        questionLibraryEntryMatches(
          _entry(stem: '已知函数在区间上单调递增', subjectKey: 'physics'),
          filter,
        ),
        isTrue,
      );
    });

    test('命中题号标签（未编号）', () {
      const QuestionLibraryFilter filter = QuestionLibraryFilter(text: '未编号');
      expect(
        questionLibraryEntryMatches(_entry(serialNo: null, stem: '无关'), filter),
        isTrue,
      );
    });

    test('命中学科键', () {
      const QuestionLibraryFilter filter =
          QuestionLibraryFilter(text: 'physics');
      expect(
        questionLibraryEntryMatches(_entry(subjectKey: 'physics'), filter),
        isTrue,
      );
    });

    test('命中来源标签', () {
      const QuestionLibraryFilter filter = QuestionLibraryFilter(text: '江苏');
      expect(
        questionLibraryEntryMatches(
          _entry(sourceLabel: '2024 江苏期末', subjectKey: 'physics'),
          filter,
        ),
        isTrue,
      );
    });

    test('命中标签路径', () {
      const QuestionLibraryFilter filter = QuestionLibraryFilter(text: '学科');
      expect(
        questionLibraryEntryMatches(
          _entry(tagPaths: const <String>['文化课/学科/数学']),
          filter,
        ),
        isTrue,
      );
    });

    test('大小写不敏感子串', () {
      const QuestionLibraryFilter filter =
          QuestionLibraryFilter(text: 'quadratic');
      expect(
        questionLibraryEntryMatches(
          _entry(title: 'Quadratic Function', subjectKey: 'physics'),
          filter,
        ),
        isTrue,
      );
    });

    test('没有命中返回 false', () {
      const QuestionLibraryFilter filter =
          QuestionLibraryFilter(text: '不存在的关键词');
      expect(
        questionLibraryEntryMatches(_entry(subjectKey: 'physics'), filter),
        isFalse,
      );
    });

    test('空白文字不限', () {
      const QuestionLibraryFilter filter = QuestionLibraryFilter(text: '   ');
      expect(questionLibraryEntryMatches(_entry(), filter), isTrue);
    });

    test('没有题名也不崩', () {
      const QuestionLibraryFilter filter = QuestionLibraryFilter(text: 'xyz');
      expect(
        questionLibraryEntryMatches(
          _entry(title: null, stem: '默认题干', subjectKey: 'physics'),
          filter,
        ),
        isFalse,
      );
    });

    test('题干里的 LaTeX 原样可搜', () {
      const QuestionLibraryFilter filter =
          QuestionLibraryFilter(text: r'$x^2$');
      expect(
        questionLibraryEntryMatches(
          _entry(stem: r'设 $x^2$ 在区间上成立', subjectKey: 'physics'),
          filter,
        ),
        isTrue,
      );
    });
  });

  group('题号', () {
    test('TR-42 命中', () {
      expect(
        questionLibraryEntryMatches(
          _entry(serialNo: 42, subjectKey: 'physics'),
          const QuestionLibraryFilter(text: 'TR-42'),
        ),
        isTrue,
      );
    });

    test('小写 tr-42 命中', () {
      expect(
        questionLibraryEntryMatches(
          _entry(serialNo: 42, subjectKey: 'physics'),
          const QuestionLibraryFilter(text: 'tr-42'),
        ),
        isTrue,
      );
    });

    test('#42 命中', () {
      expect(
        questionLibraryEntryMatches(
          _entry(serialNo: 42, subjectKey: 'physics'),
          const QuestionLibraryFilter(text: '#42'),
        ),
        isTrue,
      );
    });

    test('裸数字 42 命中题号', () {
      expect(
        questionLibraryEntryMatches(
          _entry(serialNo: 42, subjectKey: 'physics'),
          const QuestionLibraryFilter(text: '42'),
        ),
        isTrue,
      );
    });

    test('全角数字题号命中', () {
      expect(
        questionLibraryEntryMatches(
          _entry(serialNo: 42, subjectKey: 'physics'),
          const QuestionLibraryFilter(text: '４２'),
        ),
        isTrue,
      );
    });

    test('题号不匹配且文字也不命中返回 false', () {
      expect(
        questionLibraryEntryMatches(
          _entry(serialNo: 7, stem: '默认题干', subjectKey: 'physics'),
          const QuestionLibraryFilter(text: 'TR-42'),
        ),
        isFalse,
      );
    });

    test('未编号的题不命中题号', () {
      expect(
        questionLibraryEntryMatches(
          _entry(serialNo: null, stem: '默认题干', subjectKey: 'physics'),
          const QuestionLibraryFilter(text: '42'),
        ),
        isFalse,
      );
    });

    test('题号命中优先于其它字段', () {
      expect(
        questionLibraryEntryMatches(
          _entry(
              serialNo: 42, title: '无关题名', stem: '无关题干', subjectKey: 'physics'),
          const QuestionLibraryFilter(text: 'TR-42'),
        ),
        isTrue,
      );
    });

    test('数字没命中题号时回落成文字子串', () {
      expect(
        questionLibraryEntryMatches(
          _entry(serialNo: 7, stem: '全班共 42 人', subjectKey: 'physics'),
          const QuestionLibraryFilter(text: '42'),
        ),
        isTrue,
      );
    });
  });

  group('组合', () {
    const QuestionLibraryFilter filter = QuestionLibraryFilter(
      subjectKey: 'math',
      tagPaths: <String>{'文化课/学科'},
      text: '函数',
    );

    test('学科 + 标签 + 文字全中', () {
      expect(
        questionLibraryEntryMatches(
          _entry(
            subjectKey: 'math',
            stem: '函数的单调性',
            tagPaths: const <String>['文化课/学科/数学'],
          ),
          filter,
        ),
        isTrue,
      );
    });

    test('学科不中则整条不中', () {
      expect(
        questionLibraryEntryMatches(
          _entry(
            subjectKey: 'physics',
            stem: '函数的单调性',
            tagPaths: const <String>['文化课/学科/物理'],
          ),
          filter,
        ),
        isFalse,
      );
    });

    test('标签不中则整条不中', () {
      expect(
        questionLibraryEntryMatches(
          _entry(subjectKey: 'math', stem: '函数的单调性'),
          filter,
        ),
        isFalse,
      );
    });

    test('文字不中则整条不中', () {
      expect(
        questionLibraryEntryMatches(
          _entry(
            subjectKey: 'math',
            stem: '集合的运算',
            tagPaths: const <String>['文化课/学科/数学'],
          ),
          filter,
        ),
        isFalse,
      );
    });
  });

  group('copyWith / 相等性 / toString', () {
    test('copyWith 替换学科', () {
      const QuestionLibraryFilter base =
          QuestionLibraryFilter(tagPaths: <String>{'a'}, text: 'x');
      final QuestionLibraryFilter copy = base.copyWith(subjectKey: 'math');
      expect(copy.subjectKey, 'math');
      expect(copy.tagPaths, <String>{'a'});
      expect(copy.text, 'x');
    });

    test('copyWith 替换标签集合', () {
      const QuestionLibraryFilter base =
          QuestionLibraryFilter(subjectKey: 'math');
      final QuestionLibraryFilter copy = base.copyWith(tagPaths: <String>{'b'});
      expect(copy.subjectKey, 'math');
      expect(copy.tagPaths, <String>{'b'});
      expect(copy.text, '');
    });

    test('copyWith 替换文字', () {
      const QuestionLibraryFilter base =
          QuestionLibraryFilter(subjectKey: 'math', tagPaths: <String>{'a'});
      final QuestionLibraryFilter copy = base.copyWith(text: '函数');
      expect(copy.text, '函数');
      expect(copy.subjectKey, 'math');
      expect(copy.tagPaths, <String>{'a'});
    });

    test('copyWith 无参结果与原对象相等', () {
      const QuestionLibraryFilter base = QuestionLibraryFilter(
        subjectKey: 'math',
        tagPaths: <String>{'a', 'b'},
        text: 'x',
      );
      expect(base.copyWith(), base);
      expect(base.copyWith().hashCode, base.hashCode);
    });

    test('标签集合顺序不同仍相等且 hashCode 相同', () {
      const QuestionLibraryFilter a = QuestionLibraryFilter(
        subjectKey: 'math',
        tagPaths: <String>{'a', 'b'},
        text: 'x',
      );
      const QuestionLibraryFilter b = QuestionLibraryFilter(
        subjectKey: 'math',
        tagPaths: <String>{'b', 'a'},
        text: 'x',
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('字段不同则不相等', () {
      expect(
        const QuestionLibraryFilter(subjectKey: 'math'),
        isNot(const QuestionLibraryFilter(subjectKey: 'physics')),
      );
      expect(
        const QuestionLibraryFilter(text: 'a'),
        isNot(const QuestionLibraryFilter(text: 'b')),
      );
      expect(
        const QuestionLibraryFilter(tagPaths: <String>{'a'}),
        isNot(const QuestionLibraryFilter(tagPaths: <String>{'b'})),
      );
    });

    test('toString 含条件内容', () {
      const QuestionLibraryFilter filter = QuestionLibraryFilter(
        subjectKey: 'math',
        tagPaths: <String>{'a'},
        text: '函数',
      );
      final String text = filter.toString();
      expect(text, contains('QuestionLibraryFilter'));
      expect(text, contains('math'));
      expect(text, contains('函数'));
    });

    test('empty 常量与默认构造相等', () {
      expect(QuestionLibraryFilter.empty, const QuestionLibraryFilter());
      expect(QuestionLibraryFilter.empty.isEmpty, isTrue);
    });
  });

  group('过滤列表与健壮性', () {
    test('非空筛选返回命中项且保序', () {
      final List<QuestionLibraryEntry> entries = <QuestionLibraryEntry>[
        _entry(questionId: 'q3', subjectKey: 'math'),
        _entry(questionId: 'q1', subjectKey: 'physics'),
        _entry(questionId: 'q2', subjectKey: 'math'),
      ];
      final List<QuestionLibraryEntry> result = filterQuestionLibraryEntries(
        entries,
        const QuestionLibraryFilter(subjectKey: 'math'),
      );
      expect(_ids(result), <String>['q3', 'q2']);
    });

    test('非空筛选结果不可变', () {
      final List<QuestionLibraryEntry> result = filterQuestionLibraryEntries(
        <QuestionLibraryEntry>[_entry()],
        const QuestionLibraryFilter(subjectKey: 'math'),
      );
      expect(result, isNotEmpty);
      expect(() => result.removeAt(0), throwsUnsupportedError);
    });

    test('空输入与空白筛选不抛', () {
      expect(
        () => filterQuestionLibraryEntries(
          const <QuestionLibraryEntry>[],
          const QuestionLibraryFilter(subjectKey: '  '),
        ),
        returnsNormally,
      );
    });

    test('怪异输入不抛且结果稳定', () {
      final QuestionLibraryEntry weird = _entry(
        questionId: 'q🧪',
        serialNo: null,
        title: '',
        stem: '题干里有 emoji 🧪 与　全角空格 ' * 3,
        subjectKey: 'math',
        sourceLabel: '',
        tagPaths: const <String>['', ' 文化课/学科 '],
      );
      const QuestionLibraryFilter filter = QuestionLibraryFilter(
        tagPaths: <String>{' 文化课/学科 '},
        text: '🧪',
      );
      bool? first;
      expect(
        () => first = questionLibraryEntryMatches(weird, filter),
        returnsNormally,
      );
      expect(first, isTrue);
      expect(questionLibraryEntryMatches(weird, filter), first);
    });

    test('同一输入重复调用结果一致', () {
      final List<QuestionLibraryEntry> entries = <QuestionLibraryEntry>[
        _entry(questionId: 'q1', title: '二次函数'),
        _entry(questionId: 'q2', subjectKey: 'physics'),
      ];
      const QuestionLibraryFilter filter = QuestionLibraryFilter(
        subjectKey: 'math',
        text: '函数',
      );
      expect(
        _ids(filterQuestionLibraryEntries(entries, filter)),
        _ids(filterQuestionLibraryEntries(entries, filter)),
      );
    });

    test('条目字段为空串时不崩', () {
      final QuestionLibraryEntry entry = _entry(
        title: null,
        stem: '',
        subjectKey: '',
        sourceLabel: '',
        tagPaths: const <String>[''],
      );
      expect(
        questionLibraryEntryMatches(
          entry,
          const QuestionLibraryFilter(text: 'x'),
        ),
        isFalse,
      );
      expect(
        questionLibraryEntryMatches(entry, QuestionLibraryFilter.empty),
        isTrue,
      );
    });
  });

  group('错题本', () {
    test('onlyWrong: true 只留答错过的题，且保序', () {
      final List<QuestionLibraryEntry> entries = <QuestionLibraryEntry>[
        _entry(questionId: 'q3', wrongAttemptCount: 2),
        _entry(questionId: 'q1'),
        _entry(questionId: 'q2', wrongAttemptCount: 1),
        _entry(questionId: 'q4', wrongAttemptCount: 5),
      ];
      final List<QuestionLibraryEntry> result = filterQuestionLibraryEntries(
        entries,
        const QuestionLibraryFilter(onlyWrong: true),
      );
      expect(_ids(result), <String>['q3', 'q2', 'q4']);
      expect(result.every((entry) => entry.hasWrongAttempt), isTrue);
    });

    test('onlyWrong: false（默认）时答错与没答错的题都在', () {
      final List<QuestionLibraryEntry> entries = <QuestionLibraryEntry>[
        _entry(questionId: 'q1', wrongAttemptCount: 3),
        _entry(questionId: 'q2'),
      ];
      final List<QuestionLibraryEntry> result = filterQuestionLibraryEntries(
        entries,
        const QuestionLibraryFilter(),
      );
      expect(_ids(result), <String>['q1', 'q2']);
      expect(
        questionLibraryEntryMatches(entries[1], const QuestionLibraryFilter()),
        isTrue,
      );
    });

    test('onlyWrong 单独就构成有效筛选，默认构造仍是空筛选', () {
      const QuestionLibraryFilter wrongOnly =
          QuestionLibraryFilter(onlyWrong: true);
      expect(wrongOnly.isEmpty, isFalse);
      expect(wrongOnly.isNotEmpty, isTrue);
      expect(const QuestionLibraryFilter().isEmpty, isTrue);
      expect(const QuestionLibraryFilter(onlyWrong: false).isEmpty, isTrue);
    });

    test('hasWrongAttempt 由 wrongAttemptCount 派生', () {
      expect(_entry(wrongAttemptCount: 0).hasWrongAttempt, isFalse);
      expect(_entry(wrongAttemptCount: 1).hasWrongAttempt, isTrue);
      expect(_entry(wrongAttemptCount: 7).hasWrongAttempt, isTrue);
    });

    test('与学科 AND：两者都满足才命中', () {
      const QuestionLibraryFilter filter =
          QuestionLibraryFilter(subjectKey: 'math', onlyWrong: true);
      expect(
        questionLibraryEntryMatches(_entry(subjectKey: 'math'), filter),
        isFalse,
        reason: '学科命中但没答错过',
      );
      expect(
        questionLibraryEntryMatches(
          _entry(subjectKey: 'physics', wrongAttemptCount: 2),
          filter,
        ),
        isFalse,
        reason: '答错过但学科不匹配',
      );
      expect(
        questionLibraryEntryMatches(
          _entry(subjectKey: 'math', wrongAttemptCount: 2),
          filter,
        ),
        isTrue,
      );
    });

    test('与标签 AND：标签子树命中且答错过才通过', () {
      const QuestionLibraryFilter filter = QuestionLibraryFilter(
        tagPaths: <String>{'文化课/学科'},
        onlyWrong: true,
      );
      expect(
        questionLibraryEntryMatches(
          _entry(tagPaths: const <String>['文化课/学科/数学']),
          filter,
        ),
        isFalse,
        reason: '标签命中但没答错过',
      );
      expect(
        questionLibraryEntryMatches(_entry(wrongAttemptCount: 1), filter),
        isFalse,
        reason: '答错过但没有命中标签',
      );
      expect(
        questionLibraryEntryMatches(
          _entry(
            wrongAttemptCount: 1,
            tagPaths: const <String>['文化课/学科/数学'],
          ),
          filter,
        ),
        isTrue,
      );
    });

    test('与文字 AND：搜到的答错题命中，没答错的不命中', () {
      const QuestionLibraryFilter filter =
          QuestionLibraryFilter(text: '函数', onlyWrong: true);
      expect(
        questionLibraryEntryMatches(
          _entry(title: '二次函数', wrongAttemptCount: 1),
          filter,
        ),
        isTrue,
      );
      expect(
        questionLibraryEntryMatches(
          _entry(title: '二次函数'),
          filter,
        ),
        isFalse,
        reason: '文字命中但没答错过',
      );
      expect(
        questionLibraryEntryMatches(
          _entry(title: '集合', wrongAttemptCount: 1),
          filter,
        ),
        isFalse,
        reason: '答错过但文字不命中',
      );
    });

    test('copyWith 只改 onlyWrong，无参 copyWith 保留原值', () {
      const QuestionLibraryFilter base = QuestionLibraryFilter(
        subjectKey: 'math',
        tagPaths: <String>{'a'},
        text: '函数',
      );
      final QuestionLibraryFilter copy = base.copyWith(onlyWrong: true);
      expect(copy.onlyWrong, isTrue);
      expect(copy.subjectKey, 'math');
      expect(copy.tagPaths, <String>{'a'});
      expect(copy.text, '函数');
      expect(base.copyWith().onlyWrong, isFalse);
      expect(copy.copyWith().onlyWrong, isTrue);
      expect(base.copyWith(onlyWrong: false), base);
    });

    test('相等性与 hashCode 把 onlyWrong 算进去', () {
      const QuestionLibraryFilter on =
          QuestionLibraryFilter(subjectKey: 'math', onlyWrong: true);
      const QuestionLibraryFilter onAgain =
          QuestionLibraryFilter(subjectKey: 'math', onlyWrong: true);
      const QuestionLibraryFilter off =
          QuestionLibraryFilter(subjectKey: 'math');
      expect(on, onAgain);
      expect(on.hashCode, onAgain.hashCode);
      expect(on, isNot(off));
      expect(
        QuestionLibraryFilter.empty,
        const QuestionLibraryFilter(onlyWrong: false),
      );
    });

    test('toString 含 onlyWrong', () {
      expect(
        const QuestionLibraryFilter(onlyWrong: true).toString(),
        contains('onlyWrong: true'),
      );
      expect(
        const QuestionLibraryFilter().toString(),
        contains('onlyWrong: false'),
      );
    });

    test('onlyWrong 过滤结果条数正确且不可变', () {
      final List<QuestionLibraryEntry> entries = <QuestionLibraryEntry>[
        _entry(questionId: 'q1', wrongAttemptCount: 2),
        _entry(questionId: 'q2'),
        _entry(questionId: 'q3', wrongAttemptCount: 1),
      ];
      final List<QuestionLibraryEntry> result = filterQuestionLibraryEntries(
        entries,
        const QuestionLibraryFilter(onlyWrong: true),
      );
      expect(result.length, 2);
      expect(_ids(result), <String>['q1', 'q3']);
      expect(
        () => result.add(_entry(questionId: 'q9')),
        throwsUnsupportedError,
      );
      expect(() => result.removeAt(0), throwsUnsupportedError);
    });

    test('没有答错题时返回空列表且不抛', () {
      final List<QuestionLibraryEntry> result = filterQuestionLibraryEntries(
        <QuestionLibraryEntry>[_entry(), _entry(questionId: 'q2')],
        const QuestionLibraryFilter(onlyWrong: true),
      );
      expect(result, isEmpty);
      expect(
        filterQuestionLibraryEntries(
          const <QuestionLibraryEntry>[],
          const QuestionLibraryFilter(onlyWrong: true),
        ),
        isEmpty,
      );
    });
  });
}

QuestionLibraryEntry _entry({
  String questionId = 'q1',
  int? serialNo = 1,
  String? title,
  String stem = '默认题干',
  String subjectKey = 'math',
  String sourceLabel = '某校月考',
  List<String> tagPaths = const <String>[],
  int wrongAttemptCount = 0,
}) {
  return QuestionLibraryEntry(
    questionId: questionId,
    serialNo: serialNo,
    title: title,
    stem: stem,
    subjectKey: subjectKey,
    sourceLevel: 'school',
    sourceLabel: sourceLabel,
    tagPaths: tagPaths,
    wrongAttemptCount: wrongAttemptCount,
  );
}

List<String> _ids(List<QuestionLibraryEntry> entries) => <String>[
      for (final QuestionLibraryEntry entry in entries) entry.questionId
    ];
