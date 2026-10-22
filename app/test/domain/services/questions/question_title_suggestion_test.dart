/// 题名自动生成与校验的单元测试（纯 Dart，不依赖 Flutter widget）。
///
/// 覆盖 8 组：首句提取、开头装饰与来源、公式定界符、图片占位、
/// 知识点/学科拼装、长度截断、去重编号、normalize/isValid/确定性。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/questions/question_title_suggestion.dart';

void main() {
  group('首句提取', () {
    test('在全角句号处切出首句', () {
      final QuestionTitleSuggestion suggestion = suggestQuestionTitle(
        stem: '计算 1+1 的值。第二问：求 2+2。',
      );
      expect(suggestion.corePhrase, '计算 1+1 的值');
      expect(suggestion.title, '计算 1+1 的值');
    });

    test('在全角分号处切出首句', () {
      final QuestionTitleSuggestion suggestion = suggestQuestionTitle(
        stem: '已知 a=1；求 b 的值。',
      );
      expect(suggestion.corePhrase, '已知 a=1');
    });

    test('在换行处切出首句', () {
      final QuestionTitleSuggestion suggestion = suggestQuestionTitle(
        stem: '第一行是题干\n第二行是选项',
      );
      expect(suggestion.corePhrase, '第一行是题干');
    });

    test('半角感叹号与问号不切句', () {
      final QuestionTitleSuggestion suggestion = suggestQuestionTitle(
        stem: '求 5! 的值? 再看看',
      );
      expect(suggestion.corePhrase, '求 5! 的值? 再看看');
    });

    test('题干为空或纯空白时用兜底题名', () {
      final QuestionTitleSuggestion blank = suggestQuestionTitle(
        stem: '   \n\t ',
      );
      expect(blank.corePhrase, '');
      expect(blank.title, '未命名题目');
      expect(blank.deduped, isFalse);
    });
  });

  group('开头装饰与来源', () {
    test('去掉半角题号与点号', () {
      final QuestionTitleSuggestion suggestion = suggestQuestionTitle(
        stem: r'1. 计算 $x+1$',
      );
      expect(suggestion.corePhrase, '计算 x+1');
    });

    test('去掉括号题号', () {
      final suggestion = suggestQuestionTitle(stem: '(1) 求导');
      expect(suggestion.corePhrase, '求导');
    });

    test('去掉全角括号题号', () {
      final suggestion = suggestQuestionTitle(stem: '（1）化简');
      expect(suggestion.corePhrase, '化简');
    });

    test('去掉全角题号与全角点号', () {
      final suggestion = suggestQuestionTitle(stem: '12．求值');
      expect(suggestion.corePhrase, '求值');
    });

    test('去掉开头的年份地区来源括号', () {
      final suggestion = suggestQuestionTitle(stem: '（2024·江苏）计算 3+2');
      expect(suggestion.corePhrase, '计算 3+2');
    });

    test('来源括号独占一行时连同换行一起去掉', () {
      final suggestion = suggestQuestionTitle(
        stem: '（2023·全国乙卷）\n已知函数 f(x)=x',
      );
      expect(suggestion.corePhrase, '已知函数 f(x)=x');
    });

    test('开头括号不是来源时保留', () {
      final suggestion = suggestQuestionTitle(stem: '（x>0）计算 y');
      expect(suggestion.corePhrase, '（x>0）计算 y');
    });

    test('小数开头的题干不会被误当题号', () {
      final suggestion = suggestQuestionTitle(stem: '2.5 米长的绳子');
      expect(suggestion.corePhrase, '2.5 米长的绳子');
    });
  });

  group('公式定界符', () {
    test('行内公式去掉单美元定界符', () {
      final suggestion = suggestQuestionTitle(
        stem: r'计算 $x^2+1$ 的值',
      );
      expect(suggestion.corePhrase, '计算 x^2+1 的值');
      expect(suggestion.title, '计算 x^2+1 的值');
    });

    test('块公式去掉双美元定界符', () {
      final suggestion = suggestQuestionTitle(stem: r'已知 $$a+b$$ 为定值');
      expect(suggestion.corePhrase, '已知 a+b 为定值');
    });

    test('落单的美元符号原样保留', () {
      final suggestion = suggestQuestionTitle(stem: r'价格 $5 元');
      expect(suggestion.corePhrase, r'价格 $5 元');
    });

    test('公式内部文本保留反斜杠命令', () {
      final suggestion = suggestQuestionTitle(stem: r'$\frac{1}{2}$ 是多少');
      expect(suggestion.corePhrase, r'\frac{1}{2} 是多少');
    });
  });

  group('图片占位', () {
    test('去掉方括号图占位', () {
      final suggestion = suggestQuestionTitle(stem: '［图1］求面积');
      expect(suggestion.corePhrase, '求面积');
    });

    test('去掉半角方括号图占位与空格', () {
      final suggestion = suggestQuestionTitle(stem: '[图 2] 已知 a=1');
      expect(suggestion.corePhrase, '已知 a=1');
    });

    test('去掉全角方头括号图占位', () {
      final suggestion = suggestQuestionTitle(stem: '【图3】如图所示');
      expect(suggestion.corePhrase, '如图所示');
    });

    test('去掉 Markdown 图片', () {
      final suggestion = suggestQuestionTitle(
        stem: '![示意图](http://example.com/a.png) 计算周长',
      );
      expect(suggestion.corePhrase, '计算周长');
    });

    test('只有图占位时整题兜底', () {
      final suggestion = suggestQuestionTitle(stem: '［图1］');
      expect(suggestion.corePhrase, '');
      expect(suggestion.title, '未命名题目');
      expect(suggestion.knowledgePoint, isNull);
      expect(suggestion.subjectLabel, isNull);
    });

    test('只有图占位且兜底名已被占用时编号', () {
      final suggestion = suggestQuestionTitle(
        stem: '［图1］',
        existingTitles: const <String>['未命名题目'],
      );
      expect(suggestion.title, '未命名题目（2）');
      expect(suggestion.deduped, isTrue);
    });
  });

  group('知识点与学科拼装', () {
    test('知识点优先拼在核心短语前', () {
      final suggestion = suggestQuestionTitle(
        stem: '在直角三角形中，若两直角边为3和4，求斜边。',
        knowledgePointNames: const <String>['勾股定理'],
      );
      expect(
        suggestion.title,
        '勾股定理 · 在直角三角形中，若两直角边为3和4，求斜边',
      );
      expect(suggestion.knowledgePoint, '勾股定理');
      expect(suggestion.usedKnowledgePoint, isTrue);
      expect(suggestion.subjectLabel, isNull);
    });

    test('没有知识点时用学科中文名', () {
      final suggestion = suggestQuestionTitle(
        stem: '求函数 y=x^2 的导数',
        subjectKey: 'math',
      );
      expect(suggestion.title, '数学 · 求函数 y=x^2 的导数');
      expect(suggestion.subjectLabel, '数学');
      expect(suggestion.knowledgePoint, isNull);
      expect(suggestion.usedKnowledgePoint, isFalse);
    });

    test('未知学科键直接使用键本身', () {
      final suggestion = suggestQuestionTitle(
        stem: '求函数 y=x^2 的导数',
        subjectKey: 'astronomy',
      );
      expect(suggestion.title, 'astronomy · 求函数 y=x^2 的导数');
      expect(suggestion.subjectLabel, 'astronomy');
    });

    test('知识点优先于学科，但学科仍如实记录', () {
      final suggestion = suggestQuestionTitle(
        stem: '求值',
        subjectKey: 'math',
        knowledgePointNames: const <String>['勾股定理'],
      );
      expect(suggestion.title, '勾股定理 · 求值');
      expect(suggestion.knowledgePoint, '勾股定理');
      expect(suggestion.subjectLabel, '数学');
      expect(suggestion.usedKnowledgePoint, isTrue);
    });

    test('跳过空知识点取第一个非空项', () {
      final suggestion = suggestQuestionTitle(
        stem: '求函数 y=x^2 的导数',
        knowledgePointNames: const <String>['  ', '函数'],
      );
      expect(suggestion.knowledgePoint, '函数');
      expect(suggestion.title, '函数 · 求函数 y=x^2 的导数');
    });

    test('知识点名会做规范化', () {
      final suggestion = suggestQuestionTitle(
        stem: '求值',
        knowledgePointNames: const <String>['  勾股定理  '],
      );
      expect(suggestion.knowledgePoint, '勾股定理');
    });

    test('长度不够时知识点被挤掉并标记未使用', () {
      final suggestion = suggestQuestionTitle(
        stem: '计算斜边长',
        knowledgePointNames: const <String>['勾股定理'],
        maxLength: 8,
      );
      expect(suggestion.title, '计算斜边长');
      expect(suggestion.knowledgePoint, '勾股定理');
      expect(suggestion.usedKnowledgePoint, isFalse);
      expect(suggestion.corePhrase, '计算斜边长');
    });

    test('总长超限先缩核心短语再拼知识点', () {
      final suggestion = suggestQuestionTitle(
        stem: '求外心坐标',
        knowledgePointNames: const <String>['三角形的五心与相关性质'],
        maxLength: 16,
      );
      expect(suggestion.title, '三角形的五心与相关性质 · 求外');
      expect(suggestion.corePhrase, '求外');
      expect(suggestion.usedKnowledgePoint, isTrue);
    });
  });

  group('长度截断', () {
    test('超过 maxLength 的核心短语被截断', () {
      final suggestion = suggestQuestionTitle(
        stem: '计算下列各式的值并说明理由',
        maxLength: 5,
      );
      expect(suggestion.title, '计算下列各');
      expect(suggestion.corePhrase.runes.length, 5);
    });

    test('截断优先停在标点处', () {
      final suggestion = suggestQuestionTitle(
        stem: '已知条件，求未知量',
        maxLength: 6,
      );
      expect(suggestion.corePhrase, '已知条件');
    });

    test('截断不落在未闭合括号里', () {
      final suggestion = suggestQuestionTitle(
        stem: '已知（甲，乙，丙，丁）丁',
        maxLength: 6,
      );
      expect(suggestion.corePhrase, '已知');
    });

    test('括号已闭合时照常截断', () {
      final suggestion = suggestQuestionTitle(
        stem: '（括号）后面的内容很多',
        maxLength: 8,
      );
      expect(suggestion.corePhrase, '（括号）后面的内');
      expect(suggestion.corePhrase.runes.length, 8);
    });

    test('maxLength 小于 1 时按 1 处理', () {
      final zero = suggestQuestionTitle(stem: '计算', maxLength: 0);
      final negative = suggestQuestionTitle(stem: '计算', maxLength: -3);
      expect(zero.title, '计');
      expect(negative.title, '计');
    });

    test('默认上限 32 个字符', () {
      final suggestion = suggestQuestionTitle(stem: '甲' * 50);
      expect(suggestion.title.runes.length, 32);
      expect(suggestion.title, '甲' * 32);
      expect(suggestion.corePhrase.runes.length, 32);
    });

    test('未超长时核心短语原样保留', () {
      final suggestion = suggestQuestionTitle(
        stem: '计算 1+1 的值',
        maxLength: 20,
      );
      expect(suggestion.corePhrase, '计算 1+1 的值');
      expect(suggestion.title, '计算 1+1 的值');
    });

    test('maxLength 足够大时保留 50 字题干', () {
      final String stem = '${'甲' * 50}。后面';
      final suggestion = suggestQuestionTitle(stem: stem, maxLength: 100);
      expect(suggestion.title.runes.length, 50);
      expect(suggestion.corePhrase, '甲' * 50);
    });
  });

  group('去重编号', () {
    test('与已有题名冲突时追加（2）', () {
      final suggestion = suggestQuestionTitle(
        stem: '计算 5+5 的值。',
        existingTitles: const <String>['计算 5+5 的值'],
      );
      expect(suggestion.corePhrase, '计算 5+5 的值');
      expect(suggestion.title, '计算 5+5 的值（2）');
      expect(suggestion.deduped, isTrue);
    });

    test('英文大小写视为同一个题名', () {
      final suggestion = suggestQuestionTitle(
        stem: 'X',
        existingTitles: const <String>['x'],
      );
      expect(suggestion.title, 'X（2）');
      expect(suggestion.deduped, isTrue);
    });

    test('全角空格与空白差异归一后算冲突', () {
      final suggestion = suggestQuestionTitle(
        stem: '计算',
        existingTitles: const <String>['　计算　'],
      );
      expect(suggestion.title, '计算（2）');
    });

    test('不冲突时保留原名且 deduped=false', () {
      final suggestion = suggestQuestionTitle(stem: '求面积');
      expect(suggestion.title, '求面积');
      expect(suggestion.corePhrase, '求面积');
      expect(suggestion.deduped, isFalse);
    });

    test('99 个编号都被占用时返回（99）', () {
      final List<String> existing = <String>[
        't',
        for (int suffix = 2; suffix <= 99; suffix++) 't（$suffix）',
      ];
      final suggestion = suggestQuestionTitle(
        stem: 't',
        existingTitles: existing,
      );
      expect(suggestion.title, 't（99）');
      expect(suggestion.deduped, isTrue);
    });

    test('uniqueQuestionTitle 对空白 base 兜底', () {
      expect(uniqueQuestionTitle('', const <String>[]), '未命名题目');
      expect(
        uniqueQuestionTitle('  ', const <String>['未命名题目']),
        '未命名题目（2）',
      );
    });

    test('uniqueQuestionTitle 会去掉 base 两端空白', () {
      expect(uniqueQuestionTitle('  计算  ', const <String>[]), '计算');
    });
  });

  group('normalize / isValid / 确定性', () {
    test('normalizeQuestionTitle 空输入返回 null', () {
      expect(normalizeQuestionTitle(null), isNull);
      expect(normalizeQuestionTitle(''), isNull);
      expect(normalizeQuestionTitle('   '), isNull);
    });

    test('normalizeQuestionTitle 压空白并去换行与制表', () {
      expect(normalizeQuestionTitle('  a \n\t b  '), 'a b');
      expect(normalizeQuestionTitle('全角　空格'), '全角 空格');
    });

    test('normalizeQuestionTitle 把控制字符变成空格', () {
      final String raw = 'a${String.fromCharCode(1)}b';
      expect(normalizeQuestionTitle(raw), 'a b');
    });

    test('isValidQuestionTitle 拒绝空值与换行制表控制字符', () {
      expect(isValidQuestionTitle(null), isFalse);
      expect(isValidQuestionTitle(''), isFalse);
      expect(isValidQuestionTitle('   '), isFalse);
      expect(isValidQuestionTitle('a\nb'), isFalse);
      expect(isValidQuestionTitle('a\tb'), isFalse);
      expect(
        isValidQuestionTitle('a${String.fromCharCode(1)}b'),
        isFalse,
      );
    });

    test('isValidQuestionTitle 按 maxLength 判定边界', () {
      expect(isValidQuestionTitle('abcd', maxLength: 4), isTrue);
      expect(isValidQuestionTitle('abcd', maxLength: 3), isFalse);
      expect(isValidQuestionTitle('abcd', maxLength: 0), isFalse);
      expect(isValidQuestionTitle('abcd'), isTrue);
    });

    test('isValidQuestionTitle 接受正常中文题名', () {
      expect(isValidQuestionTitle('正常题名'), isTrue);
      expect(isValidQuestionTitle(' 正常题名 '), isTrue);
    });

    test('同样输入两次生成结果完全一致', () {
      final QuestionTitleSuggestion first = suggestQuestionTitle(
        stem: '计算 1+1 的值',
        knowledgePointNames: const <String>['算术'],
        maxLength: 12,
      );
      final QuestionTitleSuggestion second = suggestQuestionTitle(
        stem: '计算 1+1 的值',
        knowledgePointNames: const <String>['算术'],
        maxLength: 12,
      );
      expect(second.title, first.title);
      expect(second.corePhrase, first.corePhrase);
      expect(second.usedKnowledgePoint, first.usedKnowledgePoint);
      expect(second.deduped, first.deduped);
    });

    test('questionType 目前不影响题名', () {
      final without = suggestQuestionTitle(stem: '求面积');
      final withType = suggestQuestionTitle(
        stem: '求面积',
        questionType: 'choice',
      );
      expect(withType.title, without.title);
      expect(withType.corePhrase, without.corePhrase);
    });

    test('无知识点无学科时可选字段为空且 usedKnowledgePoint=false', () {
      final suggestion = suggestQuestionTitle(stem: '计算 1+1 的值');
      expect(suggestion.knowledgePoint, isNull);
      expect(suggestion.subjectLabel, isNull);
      expect(suggestion.usedKnowledgePoint, isFalse);
      expect(suggestion.deduped, isFalse);
      expect(suggestion.corePhrase, suggestion.title);
    });
  });
}
