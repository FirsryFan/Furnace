import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/export/omml/omml.dart';

final String _nbsp = String.fromCharCode(0x00a0);
final String _emSpace = String.fromCharCode(0x2003);
final String _combiningArrow = String.fromCharCode(0x20d7);
final String _combiningHat = String.fromCharCode(0x0302);
final String _combiningOverline = String.fromCharCode(0x0305);
final String _combiningUnderline = String.fromCharCode(0x0332);

String _compile(String tex, {int? sizeHalfPt}) =>
    compileLatexToOmml(tex, sizeHalfPt: sizeHalfPt);

void _expectError(String tex, {String? messagePart, int? position}) {
  try {
    _compile(tex);
    fail('expected LatexError for: $tex');
  } on LatexError catch (error) {
    if (messagePart != null) {
      expect(error.message, contains(messagePart));
    }
    if (position != null) {
      expect(error.position, position);
    }
  }
}

int _count(String source, String needle) {
  var count = 0;
  var index = source.indexOf(needle);
  while (index != -1) {
    count += 1;
    index = source.indexOf(needle, index + needle.length);
  }
  return count;
}

List<String> _runTexts(String xml) {
  final pattern = RegExp('<m:t xml:space="preserve">([^<]*)</m:t>');
  return pattern.allMatches(xml).map((match) => match.group(1) ?? '').toList();
}

String _allText(String xml) => _runTexts(xml).join();

void main() {
  group('compileLatexToOmml 基本结构', () {
    test('单个字母生成最小 OMML 片段', () {
      expect(
        _compile('x'),
        '<m:oMath><m:r><w:rPr><w:rFonts w:ascii="Cambria Math" '
        'w:hAnsi="Cambria Math" w:eastAsia="宋体"/></w:rPr>'
        '<m:t xml:space="preserve">x</m:t></m:r></m:oMath>',
      );
    });

    test('输出以 m:oMath 单根包裹且不重复声明命名空间', () {
      final xml = _compile('x+1');
      expect(xml, startsWith('<m:oMath>'));
      expect(xml, endsWith('</m:oMath>'));
      expect(_count(xml, '<m:oMath>'), 1);
      expect(xml, isNot(contains('xmlns:m')));
      expect(xml, isNot(contains('<?xml')));
    });

    test('同样的输入编译结果稳定', () {
      expect(_compile(r'\frac{a}{b}'), _compile(r'\frac{a}{b}'));
    });

    test('首尾空白被忽略', () {
      expect(_compile('  x  '), _compile('x'));
      expect(plainTextOfLatex('  x  '), 'x');
    });

    test('字体与 xml:space 属性齐全', () {
      final xml = _compile('x');
      expect(xml, contains('w:ascii="Cambria Math"'));
      expect(xml, contains('w:hAnsi="Cambria Math"'));
      expect(xml, contains('w:eastAsia="宋体"'));
      expect(xml, contains('<m:t xml:space="preserve">'));
    });

    test('空公式抛 LatexError（位置 0）', () {
      for (final tex in <String>['', '   ', '\t\n']) {
        expect(
          () => _compile(tex),
          throwsA(isA<LatexError>()
              .having((e) => e.message, 'message', '空公式')
              .having((e) => e.position, 'position', 0)),
        );
      }
    });

    test('中文与空格在同一文本 run 内', () {
      expect(_allText(_compile('质 量')), '质 量');
      expect(_runTexts(_compile('质 量')), <String>['质 量']);
    });
  });

  group('文本与转义', () {
    test('转义字符原样输出', () {
      expect(plainTextOfLatex(r'\$'), r'$');
      expect(plainTextOfLatex(r'\%'), '%');
      expect(plainTextOfLatex(r'\#'), '#');
      expect(plainTextOfLatex(r'\_'), '_');
      expect(plainTextOfLatex(r'\&'), '&');
      expect(plainTextOfLatex(r'\{'), '{');
      expect(plainTextOfLatex(r'\}'), '}');
    });

    test('XML 特殊字符被转义', () {
      final xml = _compile('a<b>c');
      expect(xml, contains('a&lt;b&gt;c'));
      expect(_allText(xml), 'a&lt;b&gt;c');
      // XML 输出必须转义；纯文本接口则保留原字符。
      expect(plainTextOfLatex('a<b>c'), 'a<b>c');
    });

    test('未转义的 & 明确报错而不是静默输出', () {
      _expectError('a&b', messagePart: '& 只能出现在');
    });

    test('原始美元符号是普通字符', () {
      expect(plainTextOfLatex(r'$5'), r'$5');
      expect(_allText(_compile(r'$5')), r'$5');
    });

    test('波浪号编译为不换行空格', () {
      expect(plainTextOfLatex('a~b'), 'a${_nbsp}b');
      expect(plainTextOfLatex(r'a\~b'), 'a${_nbsp}b');
    });

    test('间距命令', () {
      expect(plainTextOfLatex(r'a\,b'), 'a b');
      expect(plainTextOfLatex(r'a\;b'), 'a b');
      expect(plainTextOfLatex(r'a\:b'), 'a b');
      expect(plainTextOfLatex(r'a\!b'), 'ab');
      expect(plainTextOfLatex(r'a\quad b'), 'a$_emSpace b');
    });

    test('双反斜杠产生换行文本', () {
      expect(plainTextOfLatex(r'a\\b'), 'a\nb');
      expect(_allText(_compile(r'a\\b')), 'a\nb');
    });
  });

  group('上下标', () {
    test('上标', () {
      final xml = _compile('x^2');
      expect(xml, contains('<m:sSup><m:e>'));
      expect(xml, contains('<m:sup>'));
      expect(_allText(xml), 'x2');
    });

    test('下标', () {
      final xml = _compile('x_1');
      expect(xml, contains('<m:sSub><m:e>'));
      expect(xml, contains('<m:sub><m:r>'));
      expect(_allText(xml), 'x1');
    });

    test('同时上下标使用 sSubSup 且 sub 在 sup 前', () {
      final xml = _compile('x_1^2');
      expect(xml, contains('<m:sSubSup>'));
      expect(xml.indexOf('<m:sub>'), lessThan(xml.indexOf('<m:sup>')));
      expect(plainTextOfLatex('x_1^2'), 'x_{1}^{2}');
    });

    test('允许空基底并补空文本', () {
      expect(plainTextOfLatex('_1'), '_{1}');
      expect(plainTextOfLatex('^2'), '^{2}');
    });

    test('上标内容可带花括号', () {
      expect(_compile('x^{n+1}'), contains('n+1'));
      expect(plainTextOfLatex('x^{n+1}'), 'x^{n+1}');
    });

    test('重复上标/下标报错', () {
      _expectError('x^2^3', messagePart: '重复的上标');
      _expectError('x_1_2', messagePart: '重复的下标');
    });

    test('缺失上下标内容报错', () {
      _expectError('x^', messagePart: '缺少');
    });
  });

  group('分式', () {
    test('frac 生成 m:f / m:num / m:den', () {
      final xml = _compile(r'\frac{a}{b}');
      expect(xml, contains('<m:f><m:num>'));
      expect(xml, contains('</m:num><m:den>'));
      expect(xml, contains('</m:den></m:f>'));
      expect(plainTextOfLatex(r'\frac{a}{b}'), '(a)/(b)');
    });

    test('dfrac/tfrac/cfrac 与 frac 一致', () {
      for (final cmd in <String>['dfrac', 'tfrac', 'cfrac']) {
        expect(plainTextOfLatex('\\$cmd{a}{b}'), '(a)/(b)');
      }
    });

    test('分式可嵌套', () {
      expect(plainTextOfLatex(r'\frac{\frac{1}{2}}{3}'), '((1)/(2))/(3)');
    });

    test('分式缺少参数报错', () {
      _expectError(r'\frac', messagePart: '缺少');
      _expectError(r'\frac{1}', messagePart: '缺少');
    });

    test('参数可以是单个命令 token', () {
      expect(plainTextOfLatex(r'\frac\alpha\beta'), '(α)/(β)');
    });

    test('参数中的直立包装命令被递归读组', () {
      expect(plainTextOfLatex(r'\frac\mathrm{x}{y}'), '(x)/(y)');
    });
  });

  group('根号', () {
    test('平方根隐藏次数', () {
      final xml = _compile(r'\sqrt{x}');
      expect(xml,
          contains('<m:rad><m:radPr><m:degHide m:val="1"/></m:radPr><m:deg/>'));
      expect(xml, contains('<m:e>'));
      expect(plainTextOfLatex(r'\sqrt{x}'), '√(x)');
    });

    test('带方次的根号', () {
      final xml = _compile(r'\sqrt[3]{x}');
      expect(xml, contains('<m:rad><m:radPr/><m:deg>'));
      expect(xml, contains('3'));
      expect(plainTextOfLatex(r'\sqrt[3]{x}'), '√[3](x)');
    });

    test('缺少内容或方次右括号报错', () {
      _expectError(r'\sqrt', messagePart: '缺少');
      _expectError(r'\sqrt[3{x}', messagePart: '右方括号');
    });

    test('根号参数可嵌套分式', () {
      expect(plainTextOfLatex(r'\sqrt{\frac{1}{2}}'), '√((1)/(2))');
    });
  });

  group('定界符 left/right', () {
    test('圆括号定界符', () {
      final xml = _compile(r'\left( x \right)');
      expect(xml, contains('<m:d><m:dPr>'));
      expect(xml, contains('<m:begChr m:val="("/>'));
      expect(xml, contains('<m:endChr m:val=")"/>'));
      expect(xml, contains('<m:grow m:val="1"/>'));
      expect(plainTextOfLatex(r'\left( x \right)'), '( x )');
    });

    test('方括号与花括号定界符', () {
      expect(_compile(r'\left[ x \right]'), contains('<m:endChr m:val="]"/>'));
      expect(
          _compile(r'\left\{ x \right\}'), contains('<m:begChr m:val="{"/>'));
      expect(_compile(r'\left| x \right|'), contains('<m:begChr m:val="|"/>'));
    });

    test('点号定界符编译为空定界符', () {
      expect(_compile(r'\left. x \right|'), contains('<m:begChr m:val=""/>'));
      expect(plainTextOfLatex(r'\left. x \right|'), ' x |');
    });

    test('嵌套定界符可编译（参考实现此例会失败）', () {
      final xml = _compile(r'\left(\left[x\right]\right)');
      expect(_count(xml, '<m:d>'), 2);
      expect(plainTextOfLatex(r'\left(\left[x\right]\right)'), '([x])');
    });

    test('定界符后可接上下标', () {
      expect(_compile(r'\left(x\right)^2'), contains('<m:sSup>'));
    });

    test('单独的 right 报错', () {
      _expectError(r'\right)', messagePart: r'\right 没有与之配对的 \left');
    });

    test('未闭合的 left 报错', () {
      _expectError(r'\left( x', messagePart: '没有找到配对的');
    });

    test('未知定界符报错', () {
      _expectError(r'\left\foo x \right)', messagePart: '不认识的定界符');
    });
  });

  group('巨算符与函数', () {
    test('sum 生成 nary 且默认隐藏上下限', () {
      final xml = _compile(r'\sum');
      expect(xml, contains('<m:nary><m:naryPr><m:chr m:val="∑"/>'));
      expect(xml, contains('<m:limLoc m:val="subSup"/>'));
      expect(xml, contains('<m:supHide m:val="1"/>'));
      expect(xml, contains('<m:subHide m:val="1"/>'));
    });

    test('巨算符带上下限', () {
      final xml = _compile(r'\sum_{i=1}^{n}i');
      expect(xml, contains('<m:chr m:val="∑"/>'));
      expect(xml, contains('<m:sSubSup>'));
      expect(plainTextOfLatex(r'\sum_{i=1}^{n}i'), '∑_{i=1}^{n}i');
    });

    test('积分号', () {
      expect(_compile(r'\int_0^1x'), contains('<m:chr m:val="∫"/>'));
      expect(plainTextOfLatex(r'\int_0^1x'), '∫_{0}^{1}x');
    });

    test('函数名正体输出', () {
      final xml = _compile(r'\sin x');
      expect(xml, contains('<m:sty m:val="p"/>'));
      expect(plainTextOfLatex(r'\sin x'), 'sin x');
      expect(plainTextOfLatex(r'\lim'), 'lim');
      expect(plainTextOfLatex(r'\log_2 8'), 'log_{2} 8');
    });

    test('常用符号', () {
      expect(plainTextOfLatex(r'\alpha'), 'α');
      expect(plainTextOfLatex(r'\pi'), 'π');
      expect(plainTextOfLatex(r'\le'), '≤');
      expect(plainTextOfLatex(r'\rightarrow'), '→');
      expect(plainTextOfLatex(r'\infty'), '∞');
      expect(plainTextOfLatex(r'\times'), '×');
    });
  });

  group('包装命令', () {
    test('mathrm 直立', () {
      expect(_compile(r'\mathrm{ln}'), contains('<m:sty m:val="p"/>'));
      expect(plainTextOfLatex(r'\mathrm{ln}'), 'ln');
    });

    test('mathbf 加粗', () {
      final xml = _compile(r'\mathbf{v}');
      expect(xml, contains('<m:sty m:val="b"/>'));
      expect(xml, contains('<w:b/>'));
      expect(plainTextOfLatex(r'\mathbf{v}'), 'v');
    });

    test('mathit 斜体', () {
      final xml = _compile(r'\mathit{x}');
      expect(xml, contains('<m:sty m:val="i"/>'));
      expect(xml, contains('<w:i/>'));
    });

    test('text 内中文', () {
      expect(plainTextOfLatex(r'\text{质量}'), '质量');
      expect(_compile(r'\text{质量}'), contains('宋体'));
    });

    test('operatorname 正体', () {
      expect(plainTextOfLatex(r'\operatorname{arg}'), 'arg');
    });

    test('displaystyle 被丢弃，内容照常解析', () {
      expect(plainTextOfLatex(r'\displaystyle\frac{a}{b}'), '(a)/(b)');
    });

    test('label 被丢弃，花括号内容照常输出', () {
      expect(plainTextOfLatex(r'\label{a}b'), 'ab');
    });
  });

  group('重音与上下划线', () {
    test('vec 重音', () {
      final xml = _compile(r'\vec{a}');
      expect(
          xml, contains('<m:acc><m:accPr><m:chr m:val="$_combiningArrow"/>'));
      expect(plainTextOfLatex(r'\vec{a}'), 'a$_combiningArrow');
    });

    test('hat 重音', () {
      expect(plainTextOfLatex(r'\hat{x}'), 'x$_combiningHat');
    });

    test('上划线', () {
      final xml = _compile(r'\overline{AB}');
      expect(xml, contains('<m:bar><m:barPr><m:pos m:val="top"/>'));
      expect(plainTextOfLatex(r'\overline{AB}'), 'AB$_combiningOverline');
    });

    test('下划线', () {
      final xml = _compile(r'\underline{AB}');
      expect(xml, contains('<m:pos m:val="bot"/>'));
      expect(plainTextOfLatex(r'\underline{AB}'), 'AB$_combiningUnderline');
    });
  });

  group('矩阵与分段函数', () {
    test('pmatrix 按行列输出并外包圆括号', () {
      final xml = _compile(r'\begin{pmatrix}a&b\\c&d\end{pmatrix}');
      expect(xml, contains('<m:begChr m:val="("/>'));
      expect(xml, contains('<m:m>'));
      expect(_count(xml, '<m:mr>'), 2);
      // 4 个单元格各一个 m:e，外加外层 m:d 包裹 m:m 的 m:e 容器。
      expect(_count(xml, '<m:e>'), 5);
      expect(plainTextOfLatex(r'\begin{pmatrix}a&b\\c&d\end{pmatrix}'),
          '[a&b; c&d]');
    });

    test('bmatrix', () {
      final xml = _compile(r'\begin{bmatrix}1&2\end{bmatrix}');
      expect(xml, contains('<m:begChr m:val="["/>'));
      expect(xml, contains('<m:endChr m:val="]"/>'));
    });

    test('matrix 无定界符', () {
      expect(_compile(r'\begin{matrix}a\end{matrix}'),
          contains('<m:begChr m:val=""/>'));
    });

    test('cases 左花括号右空', () {
      final xml = _compile(r'\begin{cases}x&x>0\\-x&x<0\end{cases}');
      expect(xml, contains('<m:begChr m:val="{"/>'));
      expect(xml, contains('<m:endChr m:val=""/>'));
    });

    test('vmatrix 与 Vmatrix 定界符', () {
      expect(_compile(r'\begin{vmatrix}a\end{vmatrix}'),
          contains('<m:begChr m:val="|"/>'));
      expect(_compile(r'\begin{Vmatrix}a\end{Vmatrix}'),
          contains('m:begChr m:val="‖"'));
    });

    test('aligned 环境', () {
      expect(plainTextOfLatex(r'\begin{aligned}a&=b\\c&=d\end{aligned}'),
          '[a&=b; c&=d]');
    });

    test('列数不齐时右侧补空单元', () {
      final xml = _compile(r'\begin{matrix}a&b\\c\end{matrix}');
      // 4 个单元格（1 个补空）+ 外层 m:d 的 m:e 容器。
      expect(_count(xml, '<m:e>'), 5);
      expect(
          plainTextOfLatex(r'\begin{matrix}a&b\\c\end{matrix}'), '[a&b; c&]');
    });

    test('未知环境报错', () {
      _expectError(r'\begin{foo}a\end{foo}', messagePart: '暂不支持的 LaTeX 环境');
      _expectError(r'\begin{foo}a\end{foo}', messagePart: 'foo');
    });

    test('缺少 end 或 begin 报错', () {
      _expectError(r'\begin{matrix}a', messagePart: '没有对应的');
      _expectError(r'\end{matrix}', messagePart: r'\end 没有与之配对的');
    });

    test('空环境报错', () {
      _expectError(r'\begin{matrix}\end{matrix}', messagePart: '没有任何内容');
    });

    test('矩阵可嵌在分式里', () {
      expect(
        plainTextOfLatex(r'\frac{\begin{matrix}a\\b\end{matrix}}{2}'),
        '([a; b])/(2)',
      );
    });

    test('单元格里的命令照常解析', () {
      expect(plainTextOfLatex(r'\begin{matrix}\alpha&2\end{matrix}'), '[α&2]');
    });
  });

  group('字号 sizeHalfPt', () {
    test('给定字号时每个 run 带 w:sz 与 w:szCs', () {
      final xml = _compile('x', sizeHalfPt: 21);
      expect(xml, contains('<w:sz w:val="21"/><w:szCs w:val="21"/>'));
    });

    test('分式的分子分母 run 都带字号', () {
      final xml = _compile(r'\frac{a}{b}', sizeHalfPt: 24);
      expect(_count(xml, '<w:sz w:val="24"/>'), 2);
      expect(_count(xml, '<w:szCs w:val="24"/>'), 2);
    });

    test('不给字号时没有 w:sz', () {
      expect(_compile('x'), isNot(contains('<w:sz')));
    });
  });

  group('错误定位与信息', () {
    test('未知命令报位置与上下文', () {
      try {
        _compile(r'a+\foo');
        fail('expected LatexError');
      } on LatexError catch (error) {
        expect(error.message, contains(r'不支持的 LaTeX 命令：\foo'));
        expect(error.position, 2);
        expect(error.context, contains(r'\foo'));
      }
    });

    test('分式参数内的未知命令位置是整条公式的绝对下标', () {
      try {
        _compile(r'\frac{1}{\foo}');
        fail('expected LatexError');
      } on LatexError catch (error) {
        expect(error.message, contains(r'\foo'));
        expect(error.position, 9);
      }
    });

    test('孤立的反斜杠结尾报错', () {
      _expectError('x\\', messagePart: '孤立的反斜杠');
    });

    test('花括号不配对报错', () {
      _expectError('x{y', messagePart: '花括号不匹配');
      _expectError('x}', messagePart: '多余的花括号');
    });

    test('LatexError.toString 含信息', () {
      final error = LatexError('测试错误', position: 3, context: 'abc');
      expect(error.toString(), contains('测试错误'));
      expect(error.toString(), contains('3'));
      expect(error.toString(), contains('abc'));
    });
  });

  group('plainTextOfLatex 综合', () {
    test('空串返回空串', () {
      expect(plainTextOfLatex(''), '');
      expect(plainTextOfLatex('  '), '');
    });

    test('分式套根号', () {
      expect(
        plainTextOfLatex(r'\frac{\sqrt{x^2+1}}{2}'),
        '(√(x^{2}+1))/(2)',
      );
    });

    test('组合数', () {
      expect(plainTextOfLatex(r'\binom{n}{k}'), 'C(n,k)');
    });

    test('综合公式', () {
      expect(
        plainTextOfLatex(r'\frac{\alpha}{\beta}+\sqrt[3]{x}'),
        '(α)/(β)+√[3](x)',
      );
    });

    test('plainText 遇到语法错误也抛 LatexError', () {
      expect(() => plainTextOfLatex(r'\foo'), throwsA(isA<LatexError>()));
    });
  });

  group('supportedLatexCommands', () {
    test('包含常用命令', () {
      final commands = supportedLatexCommands();
      for (final name in <String>[
        'frac',
        'sqrt',
        'left',
        'right',
        'begin',
        'end',
        'binom',
        'alpha',
        'rightarrow',
        'sum',
        'int',
        'mathbf',
        'overline',
        'pmatrix',
        'text',
      ]) {
        expect(commands, contains(name), reason: name);
      }
    });

    test('包含单字符控制序列', () {
      final commands = supportedLatexCommands();
      for (final name in <String>['\\', '%', r'$', '#', '_', '&', '{', '}']) {
        expect(commands, contains(name), reason: name);
      }
    });

    test('不包含未知命令', () {
      final commands = supportedLatexCommands();
      expect(commands, isNot(contains('foo')));
      expect(commands, isNot(contains('undefined')));
      expect(commands, isNot(contains('mathbb')));
    });

    test('返回独立集合且规模合理', () {
      final first = supportedLatexCommands()..add('zzz');
      expect(first, contains('zzz'));
      expect(supportedLatexCommands(), isNot(contains('zzz')));
      expect(supportedLatexCommands().length, greaterThan(150));
    });
  });
}
