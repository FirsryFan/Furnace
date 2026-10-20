import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/zujuan/zujuan_paste.dart';

/// 组卷网题面粘贴解析器（纯逻辑）的验收点：
///
///  * 输入形状来自 skill 的实测：详情页 DOM 没有选项（url-grammar.md:149-164），
///    完整题面只在列表页/卡片的 cardText body 里（bridge-protocol.md:43），
///    其中的强调标记已被 runsToPlain 转成〔加点〕/〔波浪线〕/〔着重号〕
///    （content.js:21、:69-81）。解析器要吃得下「题干 + 选项 + 答案/解析/知识点」
///    这类人工复制文本，而不假设固定模板；
///  * 失败一律降级不抛异常：空输入空列表，无结构文本给一条 isPartial 草稿草
///    （stem=原文、告警固定文案）；
///  * 同输入永远同输出（确定性）；解析不联网、不写库。
void main() {
  group('normalizeZujuanMarkers：站点标记归一', () {
    test('加点标记删除、被标记文字保留', () {
      expect(normalizeZujuanMarkers('〔加点〕防汛〔/加点〕工作到位'), '防汛工作到位');
    });

    test('波浪线与着重号混排都删除、文字按原顺序保留', () {
      expect(
        normalizeZujuanMarkers('〔波浪线〕舞台〔/波浪线〕与〔着重号〕重点〔/着重号〕'),
        '舞台与重点',
      );
    });

    test('孤立闭合标记也删除', () {
      expect(normalizeZujuanMarkers('前文〔/加点〕后文'), '前文后文');
    });

    test('不认识的〔…〕标记原样保留', () {
      expect(normalizeZujuanMarkers('第〔1〕步'), '第〔1〕步');
    });

    test('CRLF / 不间断空格 / 连续空白归一，首尾空行去掉', () {
      expect(
        normalizeZujuanMarkers('  第一行 \r\n\r\n第二\u00a0\u00a0行\t  '),
        '第一行\n\n第二 行',
      );
    });

    test('空输入与纯空白返回空串', () {
      expect(normalizeZujuanMarkers(''), '');
      expect(normalizeZujuanMarkers('   \r\n\t '), '');
    });
  });

  group('单题解析：题干', () {
    test('纯题干（含（　　）与特征词）→ 1 题、无选项、不 partial', () {
      const raw = '下列关于细胞结构与功能的叙述，正确的是（　　）';
      final question = onlyQuestion(raw);
      expect(question.ordinal, isNull);
      expect(question.stem, raw);
      expect(question.options, isEmpty);
      expect(question.answer, isNull);
      expect(question.isPartial, isFalse);
      expect(question.warnings, isEmpty);
    });

    test('行首序号 1． 剥离进 ordinal，不进题干', () {
      final question = onlyQuestion('1．下列关于细胞的说法正确的是（　　）');
      expect(question.ordinal, 1);
      expect(question.stem, '下列关于细胞的说法正确的是（　　）');
    });

    test('LaTeX 行内公式原样保留', () {
      const stem = r'已知 $a>0$，函数 $f(x)=\frac{a}{x}+x$，则（　　）';
      final question = onlyQuestion(stem);
      expect(question.stem, stem);
    });

    test('超长题干不截断', () {
      final body = '细胞的结构与功能' * 400;
      final raw = '阅读材料：$body（　　）';
      final question = onlyQuestion(raw);
      expect(question.stem.startsWith('阅读材料：'), isTrue);
      expect(question.stem.length, raw.length);
    });

    test('多行题干保留行内换行', () {
      const raw = '阅读下面的文字，完成题目。\n材料一：数字技术改变阅读方式。\n下列说法正确的是（　　）';
      final question = onlyQuestion(raw);
      expect(question.stem, raw);
    });

    test('题干里的〔波浪线〕标记被剥离、文字保留', () {
      final question = onlyQuestion('〔波浪线〕舞台上的动作〔/波浪线〕有何含意（　　）');
      expect(question.stem, '舞台上的动作有何含意（　　）');
    });
  });

  group('单题解析：选项', () {
    test('每个选项各占一行', () {
      final question = onlyQuestion('下列叙述正确的是（　　）\nA．甲\nB．乙\nC．丙\nD．丁');
      expect(question.stem, '下列叙述正确的是（　　）');
      expect(optionLabels(question), <String>['A', 'B', 'C', 'D']);
      expect(optionContents(question), <String>['甲', '乙', '丙', '丁']);
    });

    test('同一行内联四个选项', () {
      final question = onlyQuestion('下列叙述正确的是（　　）A．甲 B．乙 C．丙 D．丁');
      expect(question.stem, '下列叙述正确的是（　　）');
      expect(optionLabels(question), <String>['A', 'B', 'C', 'D']);
      expect(question.options[3].content, '丁');
    });

    test('选项跨行续写合并到上一选项', () {
      final question = onlyQuestion('下列叙述正确的是（　　）\nA．甲的说法\n仍然成立\nB．乙');
      expect(optionLabels(question), <String>['A', 'B']);
      expect(question.options[0].content, '甲的说法 仍然成立');
      expect(question.options[1].content, '乙');
    });

    test('题干里的「A、B两点」不误判为选项', () {
      const raw = '如图所示，A、B两点的电势差为（　　）';
      final question = onlyQuestion(raw);
      expect(question.options, isEmpty);
      expect(question.stem, raw);
    });

    test('选项用顿号分隔（A、B、…）也识别', () {
      final question = onlyQuestion('下列说法正确的是（　　）\nA、甲\nB、乙\nC、丙\nD、丁');
      expect(optionLabels(question), <String>['A', 'B', 'C', 'D']);
    });
  });

  group('单题解析：答案 / 解析 / 知识点 / 难度 / 出处', () {
    test('【答案】行抽进 answer', () {
      final question = onlyQuestion('下列关于酶的说法正确的是（　　）\n【答案】B');
      expect(question.answer, 'B');
      expect(question.stem, '下列关于酶的说法正确的是（　　）');
    });

    test('「答案：」全角冒号也识别', () {
      final question = onlyQuestion('关于细胞的说法（　　）\n答案：C');
      expect(question.answer, 'C');
    });

    test('【解析】多行保留换行，不污染答案', () {
      final question = onlyQuestion(
        '关于细胞的说法（　　）\n【解析】\n第一步：取导数\n第二步：求极值',
      );
      expect(question.solution, '第一步：取导数\n第二步：求极值');
      expect(question.answer, isNull);
    });

    test('【答案】与【解析】同一行', () {
      final question = onlyQuestion(
        '关于方程根的说法（　　）\n【答案】B【解析】因为判别式大于零，所以有两个交点',
      );
      expect(question.answer, 'B');
      expect(question.solution, '因为判别式大于零，所以有两个交点');
    });

    test('【知识点】按分隔符切分并去重', () {
      final question = onlyQuestion(
        '关于细胞的说法（　　）\n【知识点】细胞的结构、功能、遗传与进化、细胞的结构',
      );
      expect(question.knowledgePoints, <String>['细胞的结构', '功能', '遗传与进化']);
    });

    test('【难度】只识别、不落字段，也不进题干', () {
      final question = onlyQuestion('关于细胞的说法（　　）\n【难度】中等');
      expect(question.stem, '关于细胞的说法（　　）');
      expect(question.stem.contains('难度'), isFalse);
      expect(question.stem.contains('中等'), isFalse);
      expect(question.answer, isNull);
    });

    test('【出处】抽 sourceLabel / year / region', () {
      final question = onlyQuestion('关于细胞的说法（　　）\n【出处】2023年湖南卷');
      expect(question.sourceLabel, '2023年湖南卷');
      expect(question.year, 2023);
      expect(question.region, '湖南');
    });

    test('题干首部来源括号：抽年份地区并从题干剥离', () {
      final question = onlyQuestion('（2023·湖南·长沙·一模）关于细胞的说法（　　）');
      expect(question.sourceLabel, '2023·湖南·长沙·一模');
      expect(question.year, 2023);
      expect(question.region, '湖南');
      expect(question.stem, '关于细胞的说法（　　）');
    });

    test('题干末尾的来源括号也会剥离', () {
      final question = onlyQuestion('关于细胞的说法（　　）（2024届湖南省长沙市雅礼中学高三一模）');
      expect(question.sourceLabel, '2024届湖南省长沙市雅礼中学高三一模');
      expect(question.year, 2024);
      expect(question.region, '湖南');
      expect(question.stem, '关于细胞的说法（　　）');
    });

    test('没有答案/解析时两个字段都是 null，不告警', () {
      final question = onlyQuestion('关于细胞的说法（　　）');
      expect(question.answer, isNull);
      expect(question.solution, isNull);
      expect(question.warnings, isEmpty);
    });
  });

  group('多题解析：切分', () {
    test('行首序号连续 → 多题按序解析', () {
      const raw = '1．第一题（　　）\nA．甲\nB．乙\n2．第二题（　　）\nA．丙\nB．丁';
      final questions = parseZujuanPaste(raw);
      expect(questions, hasLength(2));
      expect(questions[0].ordinal, 1);
      expect(questions[1].ordinal, 2);
      expect(questions[0].stem, '第一题（　　）');
      expect(optionContents(questions[0]), <String>['甲', '乙']);
      expect(optionContents(questions[1]), <String>['丙', '丁']);
    });

    test('序号混用 1. / 2、 / （3） 仍按三题', () {
      const raw = '1. 第一题（　　）\nA．甲\nB．乙\n'
          '2、第二题（　　）\nA．丙\nB．丁\n'
          '（3）第三题（　　）\nA．戊\nB．己';
      final questions = parseZujuanPaste(raw);
      expect(questions, hasLength(3));
      expect(questions.map((question) => question.ordinal).toList(),
          <int>[1, 2, 3]);
      expect(questions[2].stem, '第三题（　　）');
    });

    test('空行分隔两道带选项题（无序号）', () {
      const raw = '第一题（　　）\nA．甲\nB．乙\n\n第二题（　　）\nA．丙\nB．丁';
      final questions = parseZujuanPaste(raw);
      expect(questions, hasLength(2));
      expect(questions[0].stem, '第一题（　　）');
      expect(questions[1].stem, '第二题（　　）');
    });

    test('（1）（2）各带选项 → 按两题切分', () {
      const raw = '（1）第一题（　　）\nA．甲\nB．乙\n（2）第二题（　　）\nA．丙\nB．丁';
      final questions = parseZujuanPaste(raw);
      expect(questions, hasLength(2));
      expect(questions[0].ordinal, 1);
      expect(questions[1].ordinal, 2);
    });

    test('（1）（2）无选项的解答题小问 → 视为一题不拆', () {
      const raw = '阅读材料，回答下列问题。\n（1）求函数的最小值。\n（2）求函数的单调区间。';
      final questions = parseZujuanPaste(raw);
      expect(questions, hasLength(1));
      expect(questions.single.stem, raw);
      expect(questions.single.ordinal, isNull);
    });

    test('解析里的 1. 2. 步骤编号不拆题', () {
      const raw = '1．下列关于函数的说法正确的是（　　）\nA．甲\nB．乙\nC．丙\nD．丁\n'
          '【解析】\n1. 第一步说明\n2. 第二步说明';
      final questions = parseZujuanPaste(raw);
      expect(questions, hasLength(1));
      expect(questions.single.ordinal, 1);
      expect(questions.single.solution, '1. 第一步说明\n2. 第二步说明');
    });

    test('序号不连续（1→3）不切分（保守口径）', () {
      const raw = '1．第一题（　　）\nA．甲\nB．乙\n3．第三题（　　）\nA．丙\nB．丁';
      final questions = parseZujuanPaste(raw);
      expect(questions, hasLength(1));
      expect(questions.single.ordinal, 1);
    });
  });

  group('组卷网 ID 与链接', () {
    test('10q123456.html → bankId / questionId / 详情页链接', () {
      final question = onlyQuestion('关于细胞的说法（　　）\n10q123456.html');
      expect(question.zujuanBankId, '10');
      expect(question.zujuanQuestionId, '123456');
      expect(question.sourceUrl, 'https://zujuan.xkw.com/10q123456.html');
      expect(question.warnings, isEmpty);
    });

    test('完整详情页 URL 原样保留 sourceUrl', () {
      final question = onlyQuestion(
        '关于细胞的说法（　　）\nhttps://zujuan.xkw.com/11q35414092.html',
      );
      expect(question.zujuanBankId, '11');
      expect(question.zujuanQuestionId, '35414092');
      expect(question.sourceUrl, 'https://zujuan.xkw.com/11q35414092.html');
    });

    test('只有 qid → 抽题目 ID，告警缺 bankId', () {
      final question =
          onlyQuestion('关于细胞的说法（　　）\nhttps://example.com/q?qid=654321');
      expect(question.zujuanQuestionId, '654321');
      expect(question.zujuanBankId, isNull);
      expect(question.sourceUrl, isNull);
      expect(question.warnings, contains('只识别到题目 ID，缺少 bankId，无法拼详情页链接'));
    });

    test('只有 bankid → 抽库 ID，告警缺题目 ID', () {
      final question =
          onlyQuestion('关于细胞的说法（　　）\nhttps://example.com/q?bankid=12');
      expect(question.zujuanBankId, '12');
      expect(question.zujuanQuestionId, isNull);
      expect(question.sourceUrl, isNull);
      expect(question.warnings, contains('只识别到 bankId，缺少题目 ID，无法拼详情页链接'));
    });

    test('只有组卷网 URL 没有 id：保留链接、不告警', () {
      final question = onlyQuestion(
        '关于细胞的说法（　　）\nhttps://zujuan.xkw.com/quessearch?keyword=abc',
      );
      expect(
          question.sourceUrl, 'https://zujuan.xkw.com/quessearch?keyword=abc');
      expect(question.zujuanQuestionId, isNull);
      expect(question.zujuanBankId, isNull);
      expect(question.warnings, isEmpty);
    });

    test('URL 后面的中文标点不进入 sourceUrl', () {
      final question =
          onlyQuestion('见 https://zujuan.xkw.com/10q123456.html，这是详情页');
      expect(question.sourceUrl, 'https://zujuan.xkw.com/10q123456.html');
    });
  });

  group('兜底与容错', () {
    test('空输入与纯空白 → 空列表', () {
      expect(parseZujuanPaste(''), isEmpty);
      expect(parseZujuanPaste('  \r\n\t '), isEmpty);
    });

    test('无结构文字 → 一条兜底草稿（原文作题干、固定告警、isPartial）', () {
      const raw = '这是一段随便复制来的文字，没有题目结构。';
      final question = onlyQuestion(raw);
      expect(question.stem, raw);
      expect(question.options, isEmpty);
      expect(question.answer, isNull);
      expect(question.warnings, <String>['未识别题目结构，已按单题处理']);
      expect(question.isPartial, isTrue);
    });

    test('只有【答案】行 → 题干为空，告警且 isPartial', () {
      final question = onlyQuestion('【答案】B');
      expect(question.answer, 'B');
      expect(question.warnings, contains('未识别到题干'));
      expect(question.isPartial, isTrue);
    });

    test('只有组卷网 URL 的兜底草稿仍保留 ID', () {
      final question = onlyQuestion('https://zujuan.xkw.com/10q123456.html');
      expect(question.stem, 'https://zujuan.xkw.com/10q123456.html');
      expect(question.zujuanQuestionId, '123456');
      expect(question.zujuanBankId, '10');
      expect(question.isPartial, isTrue);
    });

    test('脏输入不抛异常', () {
      const inputs = <String>[
        '（）】【',
        '1.',
        '\u0000\u0001',
        'A．',
        '【答案】',
        '（1）',
        '...'
      ];
      for (final input in inputs) {
        expect(() => parseZujuanPaste(input), returnsNormally);
      }
    });

    test('同输入两次解析逐字段一致（确定性）', () {
      const raw = '1．题一（　　）\nA．甲\nB．乙\n【答案】A\n'
          '2．题二（　　）\nA．丙\nB．丁';
      final first = parseZujuanPaste(raw);
      final second = parseZujuanPaste(raw);
      expect(first, hasLength(second.length));
      for (var index = 0; index < first.length; index++) {
        expectSameQuestion(first[index], second[index]);
      }
    });

    test('选项列表不可修改', () {
      final question = onlyQuestion('下列叙述正确的是（　　）\nA．甲\nB．乙');
      expect(
        () => question.options
            .add(const ZujuanPastedOption(label: 'C', content: '丙')),
        throwsUnsupportedError,
      );
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

void expectSameQuestion(
    ZujuanPastedQuestion actual, ZujuanPastedQuestion expected) {
  expect(actual.ordinal, expected.ordinal);
  expect(actual.stem, expected.stem);
  expect(optionLabels(actual), optionLabels(expected));
  expect(optionContents(actual), optionContents(expected));
  expect(actual.answer, expected.answer);
  expect(actual.solution, expected.solution);
  expect(actual.sourceLabel, expected.sourceLabel);
  expect(actual.year, expected.year);
  expect(actual.region, expected.region);
  expect(actual.knowledgePoints, expected.knowledgePoints);
  expect(actual.zujuanQuestionId, expected.zujuanQuestionId);
  expect(actual.zujuanBankId, expected.zujuanBankId);
  expect(actual.sourceUrl, expected.sourceUrl);
  expect(actual.warnings, expected.warnings);
  expect(actual.isPartial, expected.isPartial);
}
