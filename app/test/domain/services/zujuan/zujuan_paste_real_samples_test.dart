import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/zujuan/zujuan_paste.dart';

/// task-76：用真实组卷网页面文本形态（改写/合成的长样本，不整段复制题库原文）
/// 加固粘贴解析器的验收点：
///
///  * 题号：12. / 12．/ （12）/ 第 12 题；
///  * 选项：A. / A．/ A、/ A) / A）；同行、分行、跨行；
///  * 答案标记：【答案】/ 答案：/ 故选：B / 故选B / 【解析】【详解】【点睛】；
///  * 多选答案：AB / A、B / A,B / A B；
///  * 分值：（6分）/（本小题满分12分）剥离并写进 score；
///  * 板块标题（一、选择题 / 第Ⅰ卷）与试卷标题不进题干；
///  * 裸来源行（2026届高三上期末 / 2026·江苏·模拟）抽来源；
///  * 图片占位（[图片]/（图略）/图1）告警提示人工补图；
///  * 选项编号异常（不从 A 起 / 缺号 / 重复 / 内容为空）给中文原因且不混进题干；
///  * 行内公式 $...$ 与 \\(...\\) 原样保留。
void main() {
  group('题号形态', () {
    test('阿拉伯数字加顿号 12．', () {
      final question = onlyQuestion(
        '12．题干文字（　　）\nA．甲\nB．乙',
      );
      expect(question.ordinal, 12);
      expect(question.stem, '题干文字（　　）');
      expect(optionLabels(question), <String>['A', 'B']);
    });

    test('阿拉伯数字加点 12.', () {
      final question = onlyQuestion(
        '12. 题干文字（　　）\nA．甲\nB．乙',
      );
      expect(question.ordinal, 12);
      expect(question.stem, '题干文字（　　）');
    });

    test('括号序号（12）', () {
      final question = onlyQuestion(
        '（12）题干文字（　　）\nA．甲\nB．乙',
      );
      expect(question.ordinal, 12);
      expect(question.stem, '题干文字（　　）');
    });

    test('第 12 题', () {
      final question = onlyQuestion(
        '第 12 题 题干文字（　　）\nA．甲\nB．乙',
      );
      expect(question.ordinal, 12);
      expect(question.stem, '题干文字（　　）');
    });

    test('两道「第 N 题」按序号切分', () {
      const raw = '第 1 题 第一题（　　）\nA．甲\nB．乙\n'
          '第 2 题 第二题（　　）\nA．丙\nB．丁';
      final questions = parseZujuanPaste(raw);
      expect(questions, hasLength(2));
      expect(
          questions.map((question) => question.ordinal).toList(), <int>[1, 2]);
      expect(questions[0].stem, '第一题（　　）');
      expect(questions[1].stem, '第二题（　　）');
      expect(optionContents(questions[0]), <String>['甲', '乙']);
    });
  });

  group('选项分隔符与布局', () {
    test('A) 半角右括号', () {
      final question = onlyQuestion(
        '题干（　　）\nA) 甲\nB) 乙\nC) 丙\nD) 丁',
      );
      expect(optionLabels(question), <String>['A', 'B', 'C', 'D']);
      expect(optionContents(question), <String>['甲', '乙', '丙', '丁']);
    });

    test('A）全角右括号', () {
      final question = onlyQuestion('题干（　　）\nA）甲\nB）乙');
      expect(optionLabels(question), <String>['A', 'B']);
      expect(optionContents(question), <String>['甲', '乙']);
    });

    test('同一行混用 A. / A、/ A) / A）', () {
      final question = onlyQuestion(
        '题干（　　）A. 甲 B、乙 C) 丙 D）丁',
      );
      expect(optionLabels(question), <String>['A', 'B', 'C', 'D']);
      expect(optionContents(question), <String>['甲', '乙', '丙', '丁']);
    });

    test('选项分两行书写（A B 一行、C D 一行）', () {
      final question = onlyQuestion(
        '题干（　　）\nA．甲 B．乙\nC．丙 D．丁',
      );
      expect(optionLabels(question), <String>['A', 'B', 'C', 'D']);
    });

    test('选项跨行续写保留公式', () {
      final question = onlyQuestion(
        '题干（　　）\nA．甲 \$a+b\$\nB．乙',
      );
      expect(optionLabels(question), <String>['A', 'B']);
      expect(question.options[0].content, r'甲 $a+b$');
      expect(question.options[1].content, '乙');
    });
  });

  group('答案与解析标记', () {
    test('【答案】多选字母原样保留', () {
      final question = onlyQuestion('题干（　　）\nA．甲\nB．乙\n【答案】AB');
      expect(question.answer, 'AB');
      expect(question.solution, isNull);
    });

    test('答案：全角冒号', () {
      final question = onlyQuestion('题干（　　）\n答案：C');
      expect(question.answer, 'C');
    });

    test('题干区「故选：B」只当答案标记、不进题干', () {
      final question = onlyQuestion('关于说法的判断（　　）\n故选：B');
      expect(question.answer, 'B');
      expect(question.stem, '关于说法的判断（　　）');
      expect(question.warnings, isEmpty);
      expect(question.isPartial, isFalse);
    });

    test('题干区「故选B」无冒号也识别', () {
      final question = onlyQuestion('关于说法的判断（　　）\n故选B');
      expect(question.answer, 'B');
      expect(question.stem, '关于说法的判断（　　）');
    });

    test('解析里的「故选」抽出答案、解析原文保留', () {
      final question = onlyQuestion(
        '题干（　　）\nA．甲\nB．乙\n【解析】\n由条件计算得 2+2=4，故选：B。',
      );
      expect(question.answer, 'B');
      expect(question.solution, contains('故选：B。'));
    });

    test('【答案】与解析「故选」不一致时告警', () {
      final question = onlyQuestion(
        '题干（　　）\n【答案】C\n【解析】\n计算后故选：B。',
      );
      expect(question.answer, 'C');
      expect(warningsStartingWith(question.warnings, '「故选」与【答案】不一致'), isTrue);
    });

    test('【详解】与【点睛】都进解析', () {
      final question = onlyQuestion(
        '题干（　　）\n【详解】第一步：代入。\n【点睛】本题考察函数性质。',
      );
      expect(question.solution, '第一步：代入。\n本题考察函数性质。');
    });

    test('【答案】标记后没内容 → 留空并告警，不猜', () {
      final question = onlyQuestion(
        '题干（　　）\n【答案】【解析】由条件可知选 C',
      );
      expect(question.answer, isNull);
      expect(question.solution, '由条件可知选 C');
      expect(question.warnings, contains('【答案】标记存在但答案内容为空，请人工核对'));
    });
  });

  group('多选题答案写法', () {
    test('答案：A、B', () {
      expect(onlyQuestion('题干（　　）\n答案：A、B').answer, 'A、B');
    });
    test('答案：A,B', () {
      expect(onlyQuestion('题干（　　）\n答案：A,B').answer, 'A,B');
    });
    test('答案：AB', () {
      expect(onlyQuestion('题干（　　）\n答案：AB').answer, 'AB');
    });
    test('答案：A B', () {
      expect(onlyQuestion('题干（　　）\n答案：A B').answer, 'A B');
    });
  });

  group('分值尾注', () {
    test('题干末尾（6分）剥离并读出 6 分', () {
      final question = onlyQuestion(
        '已知函数 f(x)=x+1，则 f(2)=（ ）（6分）\nA．3\nB．4',
      );
      expect(question.score, 6.0);
      expect(question.stem, '已知函数 f(x)=x+1，则 f(2)=（ ）');
      expect(question.stem.contains('6分'), isFalse);
    });

    test('分值单独一行（12分）不留在题干', () {
      final question = onlyQuestion('题干（　　）\n（12分）\nA．甲\nB．乙');
      expect(question.score, 12.0);
      expect(question.stem, '题干（　　）');
    });

    test('行首（本小题满分12分）剥离', () {
      final question = onlyQuestion(
        '（本小题满分12分）已知函数 f(x)=x，求 f(2)（　　）\nA．1\nB．2',
      );
      expect(question.score, 12.0);
      expect(question.stem, '已知函数 f(x)=x，求 f(2)（　　）');
    });

    test('没有分值 → score 为 null', () {
      final question = onlyQuestion('题干（　　）\nA．甲');
      expect(question.score, isNull);
    });
  });

  group('板块标题与试卷信息', () {
    test('「一、选择题」不进题干', () {
      final question = onlyQuestion('一、选择题\n1．题干（　　）\nA．甲\nB．乙');
      expect(question.ordinal, 1);
      expect(question.stem, '题干（　　）');
    });

    test('两道题中间插入的「二、填空题」不进题干', () {
      const raw = '一、选择题\n1．第一题（　　）\nA．甲\nB．乙\n'
          '二、填空题\n2．第二题（　　）\nA．丙\nB．丁';
      final questions = parseZujuanPaste(raw);
      expect(questions, hasLength(2));
      expect(questions[0].stem, '第一题（　　）');
      expect(questions[1].stem, '第二题（　　）');
    });

    test('「第Ⅰ卷」不进题干', () {
      final question = onlyQuestion('第Ⅰ卷\n1．题干（　　）\nA．甲\nB．乙');
      expect(question.stem, '题干（　　）');
    });

    test('试卷标题行不进题干', () {
      final question = onlyQuestion(
        '2024年普通高等学校招生全国统一考试（新高考Ⅰ卷）\n1．题干（　　）\nA．甲\nB．乙',
      );
      expect(question.stem, '题干（　　）');
      expect(question.stem.contains('全国统一考试'), isFalse);
    });
  });

  group('裸来源行', () {
    test('「2026届高三上期末」抽来源', () {
      final question = onlyQuestion('2026届高三上期末\n1．题干（　　）\nA．甲\nB．乙');
      expect(question.sourceLabel, '2026届高三上期末');
      expect(question.year, 2026);
      expect(question.stem, '题干（　　）');
    });

    test('「2026·江苏·模拟」抽来源与地区', () {
      final question = onlyQuestion('2026·江苏·模拟\n1．题干（　　）\nA．甲\nB．乙');
      expect(question.sourceLabel, '2026·江苏·模拟');
      expect(question.region, '江苏');
      expect(question.stem, '题干（　　）');
    });

    test('单独一行括号来源去掉括号', () {
      final question = onlyQuestion('（2023·湖南·长沙·一模）\n1．题干（　　）\nA．甲\nB．乙');
      expect(question.sourceLabel, '2023·湖南·长沙·一模');
      expect(question.year, 2023);
      expect(question.region, '湖南');
      expect(question.stem, '题干（　　）');
    });
  });

  group('图片占位', () {
    test('[图片] 提示人工补图（非结构告警）', () {
      final question = onlyQuestion('题干前的[图片]说明（　　）\nA．甲\nB．乙');
      expect(warningsContain(question.warnings, '图片占位'), isTrue);
      expect(question.isPartial, isFalse);
    });

    test('（图略）提示人工补图', () {
      final question = onlyQuestion('根据（图略）判断（　　）\nA．甲\nB．乙');
      expect(warningsContain(question.warnings, '图片占位'), isTrue);
    });

    test('图1 图注提示人工补图', () {
      final question = onlyQuestion('根据图1可知（　　）\nA．甲\nB．乙');
      expect(warningsContain(question.warnings, '图片占位'), isTrue);
    });
  });

  group('行内公式', () {
    test(r'$...$ 原样保留', () {
      const raw = r'已知 $f(x)=\frac{1}{x}$，则（　　）';
      expect(onlyQuestion(raw).stem, raw);
    });

    test(r'\(...\) 原样保留', () {
      const raw = r'已知 \(a>0\)，函数（　　）';
      expect(onlyQuestion(raw).stem, raw);
    });
  });

  group('选项编号异常：给明确中文原因', () {
    test('选项从 B 起 → 告警且不猜', () {
      final question = onlyQuestion('题干（　　）\nB．甲\nC．乙');
      expect(question.options, isEmpty);
      expect(question.stem, '题干（　　）');
      expect(warningsStartingWith(question.warnings, '选项编号不是从 A 开始'), isTrue);
      expect(question.isPartial, isTrue);
    });

    test('选项缺号 → 已认出的选项保留、缺号告警', () {
      final question = onlyQuestion('题干（　　）\nA．甲\nC．丙');
      expect(optionLabels(question), <String>['A']);
      expect(warningsStartingWith(question.warnings, '选项缺号'), isTrue);
      expect(question.isPartial, isTrue);
    });

    test('选项重复 → 重复行不并进上一选项', () {
      final question = onlyQuestion('题干（　　）\nA．甲\nA．乙');
      expect(optionLabels(question), <String>['A']);
      expect(question.options.single.content, '甲');
      expect(warningsStartingWith(question.warnings, '选项编号重复'), isTrue);
    });

    test('选项内容为空 → 告警', () {
      final question = onlyQuestion('题干（　　）\nA．\nB．乙');
      expect(warningsStartingWith(question.warnings, '选项内容为空'), isTrue);
      expect(question.isPartial, isTrue);
    });

    test('A 前夹着别的标签 → 整行跳过不混进题干', () {
      final question = onlyQuestion('题干（　　）\nC．丙 A．甲\nB．乙');
      expect(question.stem, '题干（　　）');
      expect(question.stem.contains('C．丙'), isFalse);
      expect(question.stem.contains('A．甲'), isFalse);
      expect(warningsStartingWith(question.warnings, '选项编号不是从 A 开始'), isTrue);
    });
  });

  group('混合真实长样本', () {
    test('两题：来源+板块+分值+内联选项+答案+解析+故选', () {
      const raw = '2026届高三上期末\n一、选择题\n'
          '1．已知函数 \$f(x)=x^2+1\$，则 \$f(2)\$ 的值是（　　）（5分）\n'
          'A．3 B．4\nC．5 D．6\n【答案】C\n'
          '【解析】把 \$x=2\$ 代入得 \$f(2)=5\$，故选：C。\n'
          '2．下列关于细胞的说法，正确的是（　　）\n'
          'A．甲\nB．乙\nC．丙\nD．丁\n【答案】D\n【解析】略。';
      final questions = parseZujuanPaste(raw);
      expect(questions, hasLength(2));
      final first = questions[0];
      expect(first.ordinal, 1);
      expect(first.stem, contains('已知函数'));
      expect(first.stem.contains('5分'), isFalse);
      expect(first.score, 5.0);
      expect(first.sourceLabel, '2026届高三上期末');
      expect(optionLabels(first), <String>['A', 'B', 'C', 'D']);
      expect(optionContents(first), <String>['3', '4', '5', '6']);
      expect(first.answer, 'C');
      expect(first.solution, contains('故选：C。'));
      final second = questions[1];
      expect(second.ordinal, 2);
      expect(second.stem, '下列关于细胞的说法，正确的是（　　）');
      expect(second.answer, 'D');
      expect(second.solution, '略。');
    });

    test('两题：第 N 题+板块+多选答案+图片提示', () {
      const raw = '第 1 题 阅读材料，回答下列问题（　　）\n'
          'A．选项甲 B．选项乙\nC．选项丙 D．选项丁\n'
          '【答案】AB\n【解析】由材料可知 A、B 正确，故选：AB。\n'
          '二、填空题\n第 2 题 如图所示，图像中的曲线（　　）\n'
          'A．甲 B．乙\n【答案】A';
      final questions = parseZujuanPaste(raw);
      expect(questions, hasLength(2));
      expect(questions[0].ordinal, 1);
      expect(questionStems(questions), <String>[
        '阅读材料，回答下列问题（　　）',
        '如图所示，图像中的曲线（　　）',
      ]);
      expect(questions[0].answer, 'AB');
      expect(questions[0].solution, contains('故选：AB。'));
      expect(questions[1].answer, 'A');
      expect(warningsContain(questions[1].warnings, '图片占位'), isTrue);
    });

    test('无序号错题：分值+答案+解析不混进题干', () {
      const raw = '关于速度与加速度的关系，下列说法正确的是（　　）（4分）\n'
          'A．速度越大，加速度越大\nB．速度变化越快，加速度越大\n'
          'C．加速度为零，速度一定为零\nD．加速度方向与速度方向一定相同\n'
          '【答案】B\n【解析】加速度是速度变化率，故选：B。';
      final question = onlyQuestion(raw);
      expect(question.ordinal, isNull);
      expect(question.score, 4.0);
      expect(question.stem, '关于速度与加速度的关系，下列说法正确的是（　　）');
      expect(optionLabels(question), <String>['A', 'B', 'C', 'D']);
      expect(question.answer, 'B');
      expect(question.solution, contains('故选：B。'));
      expect(question.warnings, isEmpty);
      expect(question.isPartial, isFalse);
    });
  });
}

ZujuanPastedQuestion onlyQuestion(String raw) {
  final questions = parseZujuanPaste(raw);
  expect(questions, hasLength(1));
  return questions.single;
}

List<String> optionLabels(ZujuanPastedQuestion question) {
  return question.options.map((option) => option.label).toList(growable: false);
}

List<String> optionContents(ZujuanPastedQuestion question) {
  return question.options
      .map((option) => option.content)
      .toList(growable: false);
}

List<String> questionStems(List<ZujuanPastedQuestion> questions) {
  return questions.map((question) => question.stem).toList(growable: false);
}

bool warningsStartingWith(List<String> warnings, String prefix) {
  return warnings.any((warning) => warning.startsWith(prefix));
}

bool warningsContain(List<String> warnings, String text) {
  return warnings.any((warning) => warning.contains(text));
}
