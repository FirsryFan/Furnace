/// LaTeX 子集 → OMML（Word 原生公式）编译器。
///
/// 移植自 paper-composer skill 的参考实现 omml.py（773 行，权威口径），
/// 供 .docx 导出时把行内公式写成 Word **原生可编辑公式**，而不是图片或原始
/// LaTeX 文本。输入是一段不含首尾 $ 的 LaTeX，输出是 <m:oMath>...</m:oMath>
/// 片段；word/document.xml 根元素已声明 xmlns:m，所以这里不重复声明命名空间。
///
/// 与 omml.py 的关键差别（有意为之，均为加固，不改变正常公式的输出）：
///
/// 1. 错误位置是绝对下标：参考实现里 \frac{..}{..} 等参数被当成独立字符串
///    再解析，报错位置相对参数而不是整条公式；本移植把子解析器的偏移一路带下去，
///    LatexError.position 始终是整条（trim 后）公式里的下标，context 也从整条
///    公式截取。测试与人工排错都靠这两个字段。
/// 2. 嵌套 \left...\right 可用：参考实现的扫描器碰到内层 \left 时会把内层
///    \right 误当外层结束符（\left(\left[x\right]\right) 直接解析失败）。
///    这里扫描时对内层 \left 计数配对，嵌套定界符能正确编译。
/// 3. 支持波浪号间距：~（以及 \~）编译成不换行空格 U+00A0；参考实现的间距表
///    里没有它，会把 ~ 当普通字符原样输出。
/// 4. 未使用的结构辅助函数 _ctrl、Seq 的 upto 参数没有搬（死代码）。
/// 5. 错误文案里的 omml.py 改成 omml.dart。
///
/// 不支持的构造（会抛 LatexError，不会静默退化）：\middle 多段定界符、
/// \over/\atop/\choose、未知环境、未知命令、未知定界符、花括号不配对、
/// 空的上下标参数等。
library;

/// 编译/解析 LaTeX 失败。
///
/// [position] 是出错字符在**去掉首尾空白后的输入**里的下标（从 0 起；可能为
/// null 表示没有具体位置）；[context] 是出错位置前后各 24 个字符的片段，用
/// “…” 标出被截断的一侧，便于人工定位。
class LatexError implements Exception {
  LatexError(this.message, {this.position, this.context});

  /// 人话错误说明，例如 不支持的 LaTeX 命令：\foo。
  final String message;

  /// 出错字符在输入里的下标。
  final int? position;

  /// 出错位置附近的原始片段。
  final String? context;

  @override
  String toString() {
    final at = position;
    if (at == null) {
      return 'LatexError: $message';
    }
    final around = context;
    if (around == null) {
      return 'LatexError: $message ｜ 位置 $at';
    }
    return 'LatexError: $message ｜ 位置 $at ｜ 上下文：$around';
  }
}

/// 把一段 LaTeX（不含首尾 $）编译成 <m:oMath>...</m:oMath>。
///
/// [sizeHalfPt] 是半磅为单位的字号（21 = 10.5pt）。给了之后每个公式 run 都带
/// w:sz/w:szCs（OMML 不继承段落字号，不给会与正文不同号、把行高顶开）；
/// 不给则用 Word 默认数学字号。空公式/未知控制序列/括号不配对抛 [LatexError]。
String compileLatexToOmml(String tex, {int? sizeHalfPt}) {
  final source = tex.trim();
  if (source.isEmpty) {
    throw LatexError('空公式', position: 0, context: '');
  }
  final tree = _Parser(source).parseSeq();
  final out = StringBuffer();
  _emit(tree, out, sizeHalfPt);
  return '<m:oMath>$out</m:oMath>';
}

/// 调试/预检用：把公式摊平成可见文本（不含 XML）。
///
/// 与 omml.py 的 plain_text 一致：分式 (分子)/(分母)、根号 √(被开方数)、
/// 上下标 X_{下标} / X^{上标}、矩阵按行用 ; 分列用 &。语法错误同样抛
/// [LatexError]（空串例外，返回空串）。
String plainTextOfLatex(String tex) {
  final source = tex.trim();
  final tree = _Parser(source).parseSeq();
  return _plainText(tree);
}

/// 本编译器认识的全部命令名（不含反斜杠），供预检统计覆盖率。
///
/// 包含 left/right/begin/end/binom/alpha/rightarrow/sum 等，也包含 \、%、$、
/// #、_、&、{、} 这些单字符控制序列（转义用）。
Set<String> supportedLatexCommands() {
  return <String>{
    ..._symbols.keys,
    ..._functionNames,
    ..._delims.keys,
    ..._spaces.keys,
    ..._uprightCommands,
    ..._boldCommands,
    ..._italicCommands,
    ..._ignoredWrappers,
    ..._fracCommands,
    ..._rootCommands,
    ..._bigCommands.keys,
    ..._accents.keys,
    ..._environments,
    'left',
    'right',
    'begin',
    'end',
    'binom',
    'dbinom',
    'tbinom',
    '\\',
    '%',
    r'$',
    '#',
    '_',
    '&',
    '{',
    '}',
  };
}

// ------------------------------------------------------------------ 字体常量

/// Word 数学区默认字体；公式 run 显式指定，避免落到主题字体上。
const String _mathFont = 'Cambria Math';

/// 公式里的中文（\text{...}）必须给 eastAsia，否则 Word 退默认中文字体。
const String _eastAsiaFont = '宋体';

// ------------------------------------------------ 不可见/组合字符（避免手敲）

final String _noBreakSpace = String.fromCharCode(0x00a0);
final String _emSpace = String.fromCharCode(0x2003);
final String _enSpace = String.fromCharCode(0x2002);
final String _fourPerEmSpace = String.fromCharCode(0x2005);
final String _thinSpace = String.fromCharCode(0x2009);
final String _combiningArrow = String.fromCharCode(0x20d7);
final String _combiningHat = String.fromCharCode(0x0302);
final String _combiningBar = String.fromCharCode(0x0304);
final String _combiningOverline = String.fromCharCode(0x0305);
final String _combiningTilde = String.fromCharCode(0x0303);
final String _combiningDot = String.fromCharCode(0x0307);
final String _combiningDiaeresis = String.fromCharCode(0x0308);
final String _combiningUnderline = String.fromCharCode(0x0332);

// -------------------------------------------------------------- 命令 -> Unicode

/// 普通符号：直接拼进当前文本 run。
const Map<String, String> _symbols = <String, String>{
  // 箭头与平衡
  'rightarrow': '→', 'to': '→', 'leftarrow': '←', 'gets': '←',
  'leftrightarrow': '↔', 'Rightarrow': '⇒', 'Leftarrow': '⇐',
  'Leftrightarrow': '⇔', 'longrightarrow': '⟶', 'longleftarrow': '⟵',
  'longleftrightarrow': '⟷', 'mapsto': '↦', 'uparrow': '↑',
  'downarrow': '↓', 'rightleftharpoons': '⇌', 'leftrightharpoons': '⇌',
  'rightleftarrows': '⇄', 'leftrightarrows': '⇆', 'right arrow': '→',
  'implies': '⟹', 'iff': '⟺',
  // 二元运算
  'pm': '±', 'mp': '∓', 'times': '×', 'div': '÷', 'cdot': '⋅',
  'ast': '∗', 'star': '⋆', 'bullet': '∙', 'circ': '∘',
  'oplus': '⊕', 'ominus': '⊖', 'otimes': '⊗', 'cup': '∪',
  'cap': '∩', 'setminus': '∖', 'wedge': '∧', 'vee': '∨',
  // 关系
  'le': '≤', 'leq': '≤', 'ge': '≥', 'geq': '≥', 'ne': '≠',
  'neq': '≠', 'approx': '≈', 'equiv': '≡', 'sim': '∼',
  'simeq': '≃', 'cong': '≅', 'propto': '∝', 'll': '≪',
  'gg': '≫', 'subset': '⊂', 'subseteq': '⊆', 'supset': '⊃',
  'supseteq': '⊇', 'in': '∈', 'notin': '∉', 'ni': '∋',
  'perp': '⊥', 'parallel': '∥', 'angle': '∠', 'triangle': '△',
  // 其他常用
  'infty': '∞', 'partial': '∂', 'nabla': '∇', 'forall': '∀',
  'exists': '∃', 'nexists': '∄', 'neg': '¬', 'lnot': '¬',
  'emptyset': '∅', 'varnothing': '∅', 'therefore': '∴',
  'because': '∵', 'degree': '°', 'checkmark': '✓',
  'prime': '′', 'ldots': '…', 'cdots': '⋯', 'dots': '…',
  'vdots': '⋮', 'ddots': '⋱', 'square': '□', 'blacksquare': '■',
  // 希腊字母（小写）
  'alpha': 'α', 'beta': 'β', 'gamma': 'γ', 'delta': 'δ',
  'epsilon': 'ε', 'varepsilon': 'ε', 'zeta': 'ζ', 'eta': 'η',
  'theta': 'θ', 'vartheta': 'ϑ', 'iota': 'ι', 'kappa': 'κ',
  'lambda': 'λ', 'mu': 'μ', 'nu': 'ν', 'xi': 'ξ', 'pi': 'π',
  'varpi': 'ϖ', 'rho': 'ρ', 'sigma': 'σ', 'tau': 'τ',
  'upsilon': 'υ', 'phi': 'ϕ', 'varphi': 'φ', 'chi': 'χ',
  'psi': 'ψ', 'omega': 'ω',
  // 希腊字母（大写）
  'Gamma': 'Γ', 'Delta': 'Δ', 'Theta': 'Θ', 'Lambda': 'Λ',
  'Xi': 'Ξ', 'Pi': 'Π', 'Sigma': 'Σ', 'Upsilon': 'Υ',
  'Phi': 'Φ', 'Psi': 'Ψ', 'Omega': 'Ω',
};

/// 需要正体排版、没有参数的函数名（直接输出名字，不读参数）。
const Set<String> _functionNames = <String>{
  'sin',
  'cos',
  'tan',
  'cot',
  'sec',
  'csc',
  'arcsin',
  'arccos',
  'arctan',
  'sinh',
  'cosh',
  'tanh',
  'log',
  'ln',
  'lg',
  'exp',
  'lim',
  'limsup',
  'liminf',
  'max',
  'min',
  'sup',
  'inf',
  'det',
  'dim',
  'ker',
  'deg',
  'gcd',
  'mod',
  'bmod',
  'pmod',
  'arg',
  'Pr',
};

/// \left / \right 后面允许出现的定界符（命令名或单字符 -> 实际字符）。
const Map<String, String> _delims = <String, String>{
  '(': '(',
  ')': ')',
  '[': '[',
  ']': ']',
  '{': '{',
  '}': '}',
  '|': '|',
  '.': '',
  '/': '/',
  '<': '⟨',
  '>': '⟩',
  'langle': '⟨',
  'rangle': '⟩',
  'lbrace': '{',
  'rbrace': '}',
  'vert': '|',
  'Vert': '‖',
  'lvert': '|',
  'rvert': '|',
  'lVert': '‖',
  'rVert': '‖',
  'lfloor': '⌊',
  'rfloor': '⌋',
  'lceil': '⌈',
  'rceil': '⌉',
  'backslash': '\\',
  'uparrow': '↑',
  'downarrow': '↓',
  'updownarrow': '↕',
};

/// 间距命令 -> 实际空白；缺省（如 \!）删掉间距。
///
/// ~ / \~ 是不换行空格，属于本移植相对 omml.py 增加的条目。
final Map<String, String> _spaces = <String, String>{
  ' ': ' ',
  ',': ' ',
  ';': ' ',
  ':': ' ',
  '!': '',
  'quad': _emSpace,
  'qquad': _emSpace + _emSpace,
  'enspace': _enSpace,
  'thinspace': _thinSpace,
  'hspace': '',
  'medspace': _fourPerEmSpace,
  'thickspace': _fourPerEmSpace,
  '~': _noBreakSpace,
};

/// 直立（m:sty val="p"）包装命令。
const Set<String> _uprightCommands = <String>{
  'mathrm',
  'text',
  'textrm',
  'textup',
  'operatorname',
  'mbox',
};

/// 加粗包装命令（内容整体 bold，同时写 m:sty b 与 w:b）。
const Set<String> _boldCommands = <String>{
  'mathbf',
  'boldsymbol',
  'bm',
  'textbf',
};

/// 斜体包装命令。
const Set<String> _italicCommands = <String>{'mathit', 'textit'};

/// 集合/逻辑修饰：直接丢掉命令本身，内容照常解析。
const Set<String> _ignoredWrappers = <String>{
  'displaystyle',
  'textstyle',
  'scriptstyle',
  'limits',
  'nolimits',
  'mathstrut',
  'strut',
  'ensuremath',
  'label',
  'tag',
};

/// 分式命令。
const Set<String> _fracCommands = <String>{'frac', 'dfrac', 'tfrac', 'cfrac'};

/// 根号命令。
const Set<String> _rootCommands = <String>{'sqrt'};

/// 巨算符命令 -> 符号字符。
const Map<String, String> _bigCommands = <String, String>{
  'int': '∫',
  'iint': '∬',
  'iiint': '∭',
  'oint': '∮',
  'sum': '∑',
  'prod': '∏',
  'coprod': '∐',
  'bigcup': '⋃',
  'bigcap': '⋂',
};

/// 重音/上下划线命令 -> 组合字符（overline/underline 单独走 m:bar）。
final Map<String, String> _accents = <String, String>{
  'vec': _combiningArrow,
  'hat': _combiningHat,
  'bar': _combiningBar,
  'overline': _combiningOverline,
  'tilde': _combiningTilde,
  'dot': _combiningDot,
  'ddot': _combiningDiaeresis,
  'widehat': _combiningHat,
  'widetilde': _combiningTilde,
  'underline': _combiningUnderline,
};

/// 认识的矩阵/多行环境。
const Set<String> _environments = <String>{
  'matrix',
  'pmatrix',
  'bmatrix',
  'vmatrix',
  'Vmatrix',
  'cases',
  'array',
  'aligned',
  'align',
  'split',
  'gathered',
  'smallmatrix',
};

/// 环境 -> (左定界符, 右定界符)；没列出的环境不外包定界符。
(String, String) _matrixDelims(String env) {
  switch (env) {
    case 'pmatrix':
      return ('(', ')');
    case 'bmatrix':
      return ('[', ']');
    case 'vmatrix':
      return ('|', '|');
    case 'Vmatrix':
      return ('‖', '‖');
    case 'cases':
      return ('{', '');
    default:
      return ('', '');
  }
}

// ------------------------------------------------------------------------ 节点

/// 语法树节点。私有 sealed 类：编译器只在自己的解析器/输出器之间用它。
sealed class _Node {
  const _Node();
}

/// 一串节点。
class _Seq extends _Node {
  const _Seq(this.kids);

  final List<_Node> kids;
}

/// 一段可见文本。
class _Text extends _Node {
  const _Text(this.s,
      {this.upright = false, this.bold = false, this.italic = false});

  final String s;
  final bool upright;
  final bool bold;
  final bool italic;
}

/// 上下标：base_{sub}^{sup}。
class _Script extends _Node {
  const _Script(this.base, {this.sub, this.sup});

  final _Node base;
  final _Seq? sub;
  final _Seq? sup;
}

/// 分式。
class _Frac extends _Node {
  const _Frac(this.num, this.den);

  final _Seq num;
  final _Seq den;
}

/// 根号（degree 为 null 表示平方根）。
class _Root extends _Node {
  const _Root(this.radicand, {this.degree});

  final _Seq radicand;
  final _Seq? degree;
}

/// \left...\right 定界符包裹。
class _Delim extends _Node {
  const _Delim(this.left, this.right, this.kids);

  final String left;
  final String right;
  final _Seq kids;
}

/// 重音。
class _Accent extends _Node {
  const _Accent(this.char, this.kids);

  final String char;
  final _Seq kids;
}

/// 上划线/下划线。
class _Bar extends _Node {
  const _Bar({required this.top, required this.kids});

  final bool top;
  final _Seq kids;
}

/// 巨算符（上下限由外层 _Script 包裹，节点本身不存上下限）。
class _Big extends _Node {
  const _Big(this.char);

  final String char;
}

/// 矩阵类环境：行 x 列。
class _Matrix extends _Node {
  _Matrix(this.rows, this.env)
      : left = _matrixDelims(env).$1,
        right = _matrixDelims(env).$2;

  final List<List<_Seq>> rows;
  final String env;
  final String left;
  final String right;
}

/// 组合数。
class _Binom extends _Node {
  const _Binom(this.top, this.bottom);

  final _Seq top;
  final _Seq bottom;
}

// ---------------------------------------------------------------------- 解析器

/// 递归下降解析器。
///
/// 每个子解析器都带 [offset]（它在原始输入里的起点），这样 [LatexError.position]
/// 始终是整条公式的绝对下标；[source] 是整条公式（trim 后），用于截取上下文。
class _Parser {
  _Parser(
    String tex, {
    this.offset = 0,
    String? source,
    this.upright = false,
    this.bold = false,
    this.italic = false,
  })  : tex = tex,
        _source = source ?? tex;

  final String tex;
  final int offset;
  final String _source;
  final bool upright;
  final bool bold;
  final bool italic;

  /// 当前解析位置（相对 [tex]）。
  int i = 0;

  bool _eof() => i >= tex.length;

  String _peek() => i < tex.length ? tex[i] : '';

  void _skipWs() {
    while (!_eof()) {
      final c = tex[i];
      if (c != ' ' && c != '\t' && c != '\n') {
        return;
      }
      i += 1;
    }
  }

  static bool _isAsciiLetter(String c) {
    final unit = c.codeUnitAt(0);
    return (unit >= 0x41 && unit <= 0x5a) || (unit >= 0x61 && unit <= 0x7a);
  }

  Never _fail(String message, [int? position]) {
    final local = position ?? i;
    final absolute = offset + local;
    throw LatexError(message,
        position: absolute, context: _contextOf(_source, absolute));
  }

  static String _contextOf(String source, int position) {
    var lo = position - 24;
    if (lo < 0) {
      lo = 0;
    }
    var hi = position + 24;
    if (hi < 0) {
      hi = 0;
    }
    if (hi > source.length) {
      hi = source.length;
    }
    if (lo > hi) {
      lo = hi;
    }
    final prefix = lo > 0 ? '…' : '';
    final suffix = hi < source.length ? '…' : '';
    return prefix + source.substring(lo, hi) + suffix;
  }

  /// 读一个控制序列名（不含反斜杠）；两个反斜杠、反斜杠加标点之类返回那个单字符。
  String _readCmd() {
    final start = i;
    i += 1;
    if (_eof()) {
      _fail('公式以孤立的反斜杠结尾', start);
    }
    final c = tex[i];
    if (!_isAsciiLetter(c)) {
      i += 1;
      return c;
    }
    var j = i;
    while (j < tex.length && _isAsciiLetter(tex[j])) {
      j += 1;
    }
    final name = tex.substring(i, j);
    i = j;
    return name;
  }

  /// 读一个花括号组（也接受单个 token），返回原始串与它在当前 tex 里的起点。
  ({String raw, int rawStart}) _readGroup([String what = '参数']) {
    _skipWs();
    if (_eof()) {
      _fail('缺少$what：公式意外结束');
    }
    if (_peek() == '{') {
      return _readGroupAt();
    }
    if (_peek() == '\\') {
      final start = i;
      final name = _readCmd();
      if (_uprightCommands.contains(name) ||
          _boldCommands.contains(name) ||
          _italicCommands.contains(name)) {
        return _readGroup(what);
      }
      return (raw: '\\$name', rawStart: start);
    }
    final start = i;
    i += 1;
    return (raw: tex[start], rawStart: start);
  }

  /// 当前位置是左花括号，读出一个完整花括号组。
  ({String raw, int rawStart}) _readGroupAt() {
    final start = i;
    var depth = 0;
    var j = i;
    while (j < tex.length) {
      final c = tex[j];
      if (c == '{') {
        depth += 1;
      } else if (c == '}') {
        depth -= 1;
        if (depth == 0) {
          break;
        }
      }
      j += 1;
    }
    if (j >= tex.length) {
      final globalStart = offset + start;
      _fail('花括号不匹配：缺少右花括号（从位置 $globalStart 开始）', start);
    }
    final raw = tex.substring(i + 1, j);
    final rawStart = i + 1;
    i = j + 1;
    return (raw: raw, rawStart: rawStart);
  }

  _Parser _subParser(
    String raw, {
    int rawStart = 0,
    bool? upright,
    bool? bold,
    bool? italic,
  }) {
    return _Parser(
      raw,
      offset: offset + rawStart,
      source: _source,
      upright: upright ?? this.upright,
      bold: bold ?? this.bold,
      italic: italic ?? this.italic,
    );
  }

  /// 解析到输入结束；顶层出现右花括号 / & 报错。
  _Seq parseSeq() {
    final kids = <_Node>[];
    final buf = <String>[];

    void flush() {
      if (buf.isNotEmpty) {
        kids.add(
            _Text(buf.join(), upright: upright, bold: bold, italic: italic));
        buf.clear();
      }
    }

    while (!_eof()) {
      final c = tex[i];
      if (c == '}') {
        _fail('多余的花括号');
      }
      if (c == '\\') {
        _handleCommand(kids, buf, flush);
        continue;
      }
      if (c == '{') {
        flush();
        final group = _readGroupAt();
        kids.add(_subParser(group.raw, rawStart: group.rawStart).parseSeq());
        continue;
      }
      if (c == '^' || c == '_') {
        flush();
        _attachScript(kids);
        continue;
      }
      if (c == '&') {
        _fail('& 只能出现在矩阵/分段函数环境里');
      }
      if (c == '~') {
        buf.add(_noBreakSpace);
        i += 1;
        continue;
      }
      buf.add(c);
      i += 1;
    }
    flush();
    return _Seq(kids);
  }

  /// 把 ^ / _ 作用到前一个节点上（没有前一个节点时给空文本当基底）。
  void _attachScript(List<_Node> kids) {
    _Seq? sub;
    _Seq? sup;
    while (!_eof() && (tex[i] == '^' || tex[i] == '_')) {
      final kind = tex[i];
      i += 1;
      final group = _readGroup('上下标');
      final node = _subParser(group.raw, rawStart: group.rawStart).parseSeq();
      if (kind == '^') {
        if (sup != null) {
          _fail('重复的上标');
        }
        sup = node;
      } else {
        if (sub != null) {
          _fail('重复的下标');
        }
        sub = node;
      }
    }
    final base =
        kids.isNotEmpty ? kids.removeLast() : _Text('', upright: upright);
    kids.add(_Script(base, sub: sub, sup: sup));
  }

  void _handleCommand(
      List<_Node> kids, List<String> buf, void Function() flush) {
    final start = i;
    final name = _readCmd();

    // 换行 / 行分隔
    if (name == '\\') {
      flush();
      kids.add(_Text('\n', upright: upright));
      return;
    }

    // 间距
    final spacing = _spaces[name];
    if (spacing != null) {
      buf.add(spacing);
      return;
    }

    // 转义字符
    if (name == '%' ||
        name == r'$' ||
        name == '#' ||
        name == '_' ||
        name == '&' ||
        name == '{' ||
        name == '}') {
      buf.add(name);
      return;
    }

    // 直立 / 加粗 / 斜体包装
    if (_uprightCommands.contains(name)) {
      final group = _readGroup('\\$name 的内容');
      flush();
      kids.add(_subParser(group.raw, rawStart: group.rawStart, upright: true)
          .parseSeq());
      return;
    }
    if (_boldCommands.contains(name)) {
      final group = _readGroup('\\$name 的内容');
      flush();
      kids.add(_subParser(group.raw, rawStart: group.rawStart, bold: true)
          .parseSeq());
      return;
    }
    if (_italicCommands.contains(name)) {
      final group = _readGroup('\\$name 的内容');
      flush();
      kids.add(_subParser(group.raw, rawStart: group.rawStart, italic: true)
          .parseSeq());
      return;
    }
    if (_ignoredWrappers.contains(name)) {
      return;
    }

    // 分式 / 根号 / 组合
    if (_fracCommands.contains(name)) {
      final num = _readGroup('\\$name 的分子');
      final den = _readGroup('\\$name 的分母');
      flush();
      kids.add(_Frac(
        _subParser(num.raw, rawStart: num.rawStart).parseSeq(),
        _subParser(den.raw, rawStart: den.rawStart).parseSeq(),
      ));
      return;
    }
    if (_rootCommands.contains(name)) {
      _Seq? degree;
      if (_peek() == '[') {
        final close = tex.indexOf(']', i);
        if (close == -1) {
          _fail('根号的方次缺少右方括号', start);
        }
        final degreeStart = i + 1;
        degree =
            _subParser(tex.substring(degreeStart, close), rawStart: degreeStart)
                .parseSeq();
        i = close + 1;
      }
      final group = _readGroup('\\sqrt 的内容');
      flush();
      kids.add(_Root(
        _subParser(group.raw, rawStart: group.rawStart).parseSeq(),
        degree: degree,
      ));
      return;
    }
    if (name == 'binom' || name == 'dbinom' || name == 'tbinom') {
      final top = _readGroup('\\binom 的上项');
      final bottom = _readGroup('\\binom 的下项');
      flush();
      kids.add(_Binom(
        _subParser(top.raw, rawStart: top.rawStart).parseSeq(),
        _subParser(bottom.raw, rawStart: bottom.rawStart).parseSeq(),
      ));
      return;
    }

    // 定界符
    if (name == 'left') {
      flush();
      kids.add(_parseLeftRight(start));
      return;
    }
    if (name == 'right') {
      _fail('\\right 没有与之配对的 \\left', start);
    }

    // 巨算符
    final bigChar = _bigCommands[name];
    if (bigChar != null) {
      flush();
      kids.add(_Big(bigChar));
      return;
    }

    // 重音 / 上下划线
    final accent = _accents[name];
    if (accent != null) {
      final group = _readGroup('\\$name 的内容');
      flush();
      final inner = _subParser(group.raw, rawStart: group.rawStart).parseSeq();
      if (name == 'overline') {
        kids.add(_Bar(top: true, kids: inner));
      } else if (name == 'underline') {
        kids.add(_Bar(top: false, kids: inner));
      } else {
        kids.add(_Accent(accent, inner));
      }
      return;
    }

    // 矩阵 / 分段函数
    if (name == 'begin') {
      final envRaw = _readGroup('\\begin 的环境名').raw.trim();
      if (!_environments.contains(envRaw)) {
        _fail(
          '暂不支持的 LaTeX 环境：$envRaw（支持：${_environments.join('、')}）',
          start,
        );
      }
      final body = _readEnvironment(envRaw, start);
      flush();
      kids.add(_Matrix(
        _parseMatrixBody(body.body, body.bodyStart, envRaw),
        envRaw,
      ));
      return;
    }
    if (name == 'end') {
      _fail('\\end 没有与之配对的 \\begin', start);
    }

    // 函数名
    if (_functionNames.contains(name)) {
      flush();
      kids.add(_Text(name, upright: true));
      return;
    }

    // 普通符号
    final symbol = _symbols[name];
    if (symbol != null) {
      buf.add(symbol);
      return;
    }

    _fail(
      '不支持的 LaTeX 命令：\\$name（若确属必要，请在 omml.dart 的 _symbols/_functionNames 里补充，或改为纯文本）',
      start,
    );
  }

  /// 从当前位置扫描到配对的右定界符命令（也接受 middle，按右定界符处理）。
  ///
  /// 花括号深度感知：组内的命令交给组解析器，不能被当结束符。与参考实现不同，
  /// 这里还统计内层 left 的数量，嵌套定界符时把 right 配给内层。
  ({String innerRaw, String stopCommand, int rawStart}) _scanToMatchingRight(
      int start) {
    var depth = 0;
    var nestedLeft = 0;
    var j = i;
    while (j < tex.length) {
      final c = tex[j];
      if (c == '{') {
        depth += 1;
        j += 1;
        continue;
      }
      if (c == '}') {
        depth -= 1;
        if (depth < 0) {
          _fail('花括号不匹配：多出的右花括号', j);
        }
        j += 1;
        continue;
      }
      if (c == '\\' && depth == 0) {
        var k = j + 1;
        while (k < tex.length && _isAsciiLetter(tex[k])) {
          k += 1;
        }
        final String word;
        if (k > j + 1) {
          word = tex.substring(j + 1, k);
        } else if (j + 2 <= tex.length) {
          word = tex.substring(j + 1, j + 2);
        } else {
          word = '';
        }
        if (word == 'left') {
          nestedLeft += 1;
          j = k > j + 1 ? k : j + 2;
          continue;
        }
        if (word == 'right' || word == 'middle') {
          if (nestedLeft > 0) {
            if (word == 'right') {
              nestedLeft -= 1;
            }
            j = k;
            continue;
          }
          return (
            innerRaw: tex.substring(i, j),
            stopCommand: word,
            rawStart: i
          );
        }
        if (word == 'over' || word == 'atop' || word == 'choose') {
          _fail('暂不支持 \\$word（请改用 \\frac 或 \\binom）', j);
        }
        j = k > j + 1 ? k : j + 2;
        continue;
      }
      j += 1;
    }
    _fail('\\left 没有找到配对的 \\right', start);
  }

  _Delim _parseLeftRight(int start) {
    final left = _readDelim('\\left');
    final scan = _scanToMatchingRight(start);
    final innerStart = scan.rawStart;
    i += scan.innerRaw.length;
    final inner = _subParser(scan.innerRaw, rawStart: innerStart).parseSeq();
    _readCmd();
    final right = _readDelim('\\${scan.stopCommand}');
    return _Delim(left, right, inner);
  }

  String _readDelim(String who) {
    _skipWs();
    if (_eof()) {
      _fail('$who 后面缺少定界符');
    }
    final c = _peek();
    if (c == '\\') {
      final name = _readCmd();
      final delim = _delims[name];
      if (delim == null) {
        _fail('$who 后面不认识的定界符：\\$name');
      }
      return delim;
    }
    final delim = _delims[c];
    if (delim == null) {
      _fail('$who 后面不认识的定界符：$c');
    }
    i += 1;
    return delim;
  }

  ({String body, int bodyStart}) _readEnvironment(String env, int start) {
    final pattern = RegExp(r'\\end\s*\{\s*' + RegExp.escape(env) + r'\s*\}');
    final match = pattern.firstMatch(tex.substring(i));
    if (match == null) {
      _fail('\\begin{$env} 没有对应的 \\end{$env}', start);
    }
    final bodyStart = i;
    final body = tex.substring(i, i + match.start);
    i = i + match.end;
    return (body: body, bodyStart: bodyStart);
  }

  List<List<_Seq>> _parseMatrixBody(String body, int bodyStart, String env) {
    final rows = <List<_Seq>>[];
    var cursor = 0;
    while (true) {
      final split = body.indexOf(r'\\', cursor);
      final rowEnd = split < 0 ? body.length : split;
      final rowRaw = body.substring(cursor, rowEnd);
      if (rowRaw.trim().isNotEmpty) {
        final row = <_Seq>[];
        var cellStart = 0;
        while (true) {
          final amp = rowRaw.indexOf('&', cellStart);
          final cellEnd = amp < 0 ? rowRaw.length : amp;
          final cellRaw = rowRaw.substring(cellStart, cellEnd);
          row.add(_subParser(
            cellRaw,
            rawStart: bodyStart + cursor + cellStart,
          ).parseSeq());
          if (amp < 0) {
            break;
          }
          cellStart = amp + 1;
        }
        rows.add(row);
      }
      if (split < 0) {
        break;
      }
      cursor = split + 2;
    }
    if (rows.isEmpty) {
      _fail('\\begin{$env} 里没有任何内容');
    }
    var width = 0;
    for (final row in rows) {
      if (row.length > width) {
        width = row.length;
      }
    }
    for (final row in rows) {
      while (row.length < width) {
        row.add(const _Seq(<_Node>[]));
      }
    }
    return rows;
  }
}

// -------------------------------------------------------------------- 编译输出

String _xmlEscape(String text) {
  return text
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
}

/// 一个数学 run：m:rPr（样式）+ w:rPr（字体/字号）+ m:t。
String _mRun(
  String text, {
  bool upright = false,
  bool bold = false,
  bool italic = false,
  int? sizeHalfPt,
}) {
  final rpr = StringBuffer();
  if (upright) {
    rpr.write('<m:sty m:val="p"/>');
  } else if (bold) {
    rpr.write('<m:sty m:val="b"/>');
  } else if (italic) {
    rpr.write('<m:sty m:val="i"/>');
  }
  final wrpr = StringBuffer(
    '<w:rPr><w:rFonts w:ascii="$_mathFont" w:hAnsi="$_mathFont" w:eastAsia="$_eastAsiaFont"/>',
  );
  if (bold) {
    wrpr.write('<w:b/>');
  }
  if (italic) {
    wrpr.write('<w:i/>');
  }
  if (sizeHalfPt != null) {
    final halfPt = sizeHalfPt.toString();
    wrpr.write('<w:sz w:val="$halfPt"/>');
    wrpr.write('<w:szCs w:val="$halfPt"/>');
  }
  wrpr.write('</w:rPr>');
  final rprXml = rpr.isEmpty ? '' : '<m:rPr>$rpr</m:rPr>';
  return '<m:r>$rprXml$wrpr<m:t xml:space="preserve">${_xmlEscape(text)}</m:t></m:r>';
}

void _emit(_Node node, StringBuffer out, int? sizeHalfPt) {
  switch (node) {
    case _Seq():
      for (final kid in node.kids) {
        _emit(kid, out, sizeHalfPt);
      }
    case _Text():
      if (node.s.isNotEmpty) {
        out.write(_mRun(
          node.s,
          upright: node.upright,
          bold: node.bold,
          italic: node.italic,
          sizeHalfPt: sizeHalfPt,
        ));
      }
    case _Script():
      final sub = node.sub;
      final sup = node.sup;
      final String tag;
      if (sub != null && sup != null) {
        tag = 'm:sSubSup';
      } else if (sub != null) {
        tag = 'm:sSub';
      } else {
        tag = 'm:sSup';
      }
      out.write('<$tag><m:e>');
      _emit(node.base, out, sizeHalfPt);
      out.write('</m:e>');
      if (sub != null) {
        out.write('<m:sub>');
        _emit(sub, out, sizeHalfPt);
        out.write('</m:sub>');
      }
      if (sup != null) {
        out.write('<m:sup>');
        _emit(sup, out, sizeHalfPt);
        out.write('</m:sup>');
      }
      out.write('</$tag>');
    case _Frac():
      out.write('<m:f><m:num>');
      _emit(node.num, out, sizeHalfPt);
      out.write('</m:num><m:den>');
      _emit(node.den, out, sizeHalfPt);
      out.write('</m:den></m:f>');
    case _Root():
      final degree = node.degree;
      if (degree == null) {
        out.write(
            '<m:rad><m:radPr><m:degHide m:val="1"/></m:radPr><m:deg/><m:e>');
      } else {
        out.write('<m:rad><m:radPr/><m:deg>');
        _emit(degree, out, sizeHalfPt);
        out.write('</m:deg><m:e>');
      }
      _emit(node.radicand, out, sizeHalfPt);
      out.write('</m:e></m:rad>');
    case _Delim():
      out.write(
          '<m:d><m:dPr><m:begChr m:val="${_xmlEscape(node.left)}"/><m:endChr m:val="${_xmlEscape(node.right)}"/><m:grow m:val="1"/></m:dPr><m:e>');
      _emit(node.kids, out, sizeHalfPt);
      out.write('</m:e></m:d>');
    case _Bar():
      final pos = node.top ? 'top' : 'bot';
      out.write('<m:bar><m:barPr><m:pos m:val="$pos"/></m:barPr><m:e>');
      _emit(node.kids, out, sizeHalfPt);
      out.write('</m:e></m:bar>');
    case _Accent():
      out.write(
          '<m:acc><m:accPr><m:chr m:val="${_xmlEscape(node.char)}"/></m:accPr><m:e>');
      _emit(node.kids, out, sizeHalfPt);
      out.write('</m:e></m:acc>');
    case _Big():
      out.write(
          '<m:nary><m:naryPr><m:chr m:val="${_xmlEscape(node.char)}"/><m:limLoc m:val="subSup"/><m:supHide m:val="1"/><m:subHide m:val="1"/></m:naryPr><m:sub></m:sub><m:sup></m:sup><m:e/></m:nary>');
    case _Binom():
      out.write('<m:d><m:dPr><m:begChr m:val="("/><m:endChr m:val=")"/>'
          '<m:grow m:val="1"/></m:dPr><m:e><m:f><m:num>');
      _emit(node.top, out, sizeHalfPt);
      out.write('</m:num><m:den>');
      _emit(node.bottom, out, sizeHalfPt);
      out.write('</m:den></m:f></m:e></m:d>');
    case _Matrix():
      out.write(
          '<m:d><m:dPr><m:begChr m:val="${_xmlEscape(node.left)}"/><m:endChr m:val="${_xmlEscape(node.right)}"/><m:grow m:val="1"/></m:dPr><m:e><m:m>');
      for (final row in node.rows) {
        out.write('<m:mr>');
        for (final cell in row) {
          out.write('<m:e>');
          _emit(cell, out, sizeHalfPt);
          out.write('</m:e>');
        }
        out.write('</m:mr>');
      }
      out.write('</m:m></m:e></m:d>');
  }
}

// ------------------------------------------------------------------ 调试/预检

String _plainText(_Node? node) {
  if (node == null) {
    return '';
  }
  switch (node) {
    case _Seq():
      final out = StringBuffer();
      for (final kid in node.kids) {
        out.write(_plainText(kid));
      }
      return out.toString();
    case _Text():
      return node.s;
    case _Script():
      var s = _plainText(node.base);
      final sub = node.sub;
      final sup = node.sup;
      if (sub != null) {
        s = '${s}_{${_plainText(sub)}}';
      }
      if (sup != null) {
        s = '$s^{${_plainText(sup)}}';
      }
      return s;
    case _Frac():
      return '(${_plainText(node.num)})/(${_plainText(node.den)})';
    case _Root():
      final degree = node.degree;
      final deg = degree == null ? '' : '[${_plainText(degree)}]';
      return '√$deg(${_plainText(node.radicand)})';
    case _Delim():
      return node.left + _plainText(node.kids) + node.right;
    case _Bar():
      return _plainText(node.kids) +
          (node.top ? _combiningOverline : _combiningUnderline);
    case _Accent():
      return _plainText(node.kids) + node.char;
    case _Big():
      return node.char;
    case _Binom():
      return 'C(${_plainText(node.top)},${_plainText(node.bottom)})';
    case _Matrix():
      final rows = <String>[];
      for (final row in node.rows) {
        final cells = <String>[];
        for (final cell in row) {
          cells.add(_plainText(cell));
        }
        rows.add(cells.join('&'));
      }
      return '[${rows.join('; ')}]';
  }
}
