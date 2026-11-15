/// 确定性 Normalizer：纯规则做 LaTeX/Unicode/单位/符号规范化。
///
/// 只用于**匹配**（n-gram、答案覆盖、锚点/分支覆盖），不修改来源：每个
/// [NormalizedStep] 都保留原始 [TraceStep]（rawText/sourceHash 不变）。规范
/// 化是幂等的：`normalize(normalize(x)) == normalize(x)`（测试断言）。
///
/// 规则（全部确定性，无模型调用）：
///
///  * LaTeX：`\frac{a}{b}` → `(a)/(b)`、`\sqrt{x}` → `sqrt(x)`、`\leq` → `<=`、
///    `\geq` → `>=`、`\neq` → `!=`、希腊字母/函数名转 ASCII、去掉 `\left/\right`
///    与数学定界符；
///  * Unicode：全角数字/字母/标点转 ASCII，`≤ ≥ ≠ × ÷ − ² ³ ·` 等转 ASCII；
///  * 单位：上标转 `^n`（`m/s²` → `m/s^2`），去掉所有空白；
///  * 去掉 `$`、`\(`、`$$…$$` 等定界符。
library;

import 'trace_parser.dart';

/// 一步的 raw + normalized 两份文本。
class NormalizedStep {
  const NormalizedStep({required this.traceStep, required this.normalized});

  /// 原始步骤（raw 文本 + 偏移 + hash，未被改写）。
  final TraceStep traceStep;

  /// 归一化文本；只用于匹配。
  final String normalized;

  String get stepId => traceStep.id;

  String get sourceHash => traceStep.sourceHash;

  Map<String, Object?> toJson() => {
        'id': traceStep.id,
        'source_start': traceStep.sourceStart,
        'source_end': traceStep.sourceEnd,
        'source_hash': traceStep.sourceHash,
        'raw_text': traceStep.rawText,
        'normalized': normalized,
      };
}

/// 纯规则规范化器。
class Normalizer {
  const Normalizer();

  /// 已知单位词表（长的在前，便于单位抽取；全部小写敏感保留原大小写）。
  static const List<String> knownUnits = <String>[
    'm/s^2',
    'm/s',
    'km/h',
    'kg',
    'mg',
    'cm',
    'mm',
    'km',
    'ms',
    'min',
    'mol',
    'mL',
    'degC',
    'deg',
    'ohm',
    'Pa',
    'Hz',
    'rad',
    'N',
    'J',
    'W',
    'V',
    'A',
    'C',
    'K',
    'L',
    'g',
    'h',
    's',
    'm',
  ];

  static final RegExp _unitPattern = _buildUnitPattern();

  static RegExp _buildUnitPattern() {
    final ordered = <String>[...knownUnits]
      ..sort((a, b) => b.length - a.length);
    return RegExp(
      '(?<![A-Za-z_])(${ordered.map(RegExp.escape).join('|')})(?![A-Za-z0-9^_])',
    );
  }

  /// 从已归一化文本里抽单位 token（去重、保持出现顺序）。
  ///
  /// 先把下标 token（`_1`、`_x`）替换成 `_`，避免把 `m_1g` 里的 `g` 误当克：
  /// 单位边界只认「前面不是字母/下划线、后面不是字母/数字/上标/下划线」。
  static List<String> unitsIn(String normalized) {
    final text = normalized.replaceAll(RegExp(r'_[0-9A-Za-z]+'), '_');
    final found = <String>{};
    for (final match in _unitPattern.allMatches(text)) {
      final unit = match.group(1);
      if (unit != null) {
        found.add(unit);
      }
    }
    return found.toList();
  }

  /// 保守 token 估算：按字符数（中文≈1 token/字）；只用于预算，不精确分词。
  static int estimateTokens(String text) => text.runes.length;

  /// 规范化一段文本；幂等。
  String normalize(String raw) {
    var text = raw;

    // 1. LaTeX 结构（先处理会吞掉后续命令的前缀）。
    text = text.replaceAll(r'\left', '').replaceAll(r'\right', '');
    text = text.replaceAllMapped(
      RegExp(r'\\(?:d?frac)\s*\{([^{}]*)\}\s*\{([^{}]*)\}'),
      (match) => '(${match[1]})/(${match[2]})',
    );
    text = text.replaceAllMapped(
      RegExp(r'\\sqrt\s*\{([^{}]*)\}'),
      (match) => 'sqrt(${match[1]})',
    );
    text = text.replaceAllMapped(
      RegExp(r'\\text\s*\{([^{}]*)\}'),
      (match) => match[1] ?? '',
    );
    // 字体命令只是包装，去掉命令保留内容。
    text = text.replaceAll(
      RegExp(r'\\(?:mathrm|mathbf|mathit|mathsf|mathtt)\s*'),
      '',
    );

    // 2. 已知命令（长的在前，避免 `\le` 吃掉 `\leq`）。
    const commands = <String, String>{
      r'\leq': '<=',
      r'\geq': '>=',
      r'\neq': '!=',
      r'\le': '<=',
      r'\ge': '>=',
      r'\ne': '!=',
      r'\lt': '<',
      r'\gt': '>',
      r'\cdot': '*',
      r'\times': '*',
      r'\ast': '*',
      r'\div': '/',
      r'\pm': '+-',
      r'\infty': 'inf',
      r'\pi': 'pi',
      r'\theta': 'theta',
      r'\alpha': 'alpha',
      r'\beta': 'beta',
      r'\gamma': 'gamma',
      r'\lambda': 'lambda',
      r'\mu': 'mu',
      r'\omega': 'omega',
      r'\Delta': 'Delta',
      r'\delta': 'delta',
      r'\rho': 'rho',
      r'\phi': 'phi',
      r'\varphi': 'varphi',
      r'\epsilon': 'epsilon',
      r'\varepsilon': 'varepsilon',
      r'\sum': 'sum',
      r'\int': 'int',
      r'\sin': 'sin',
      r'\cos': 'cos',
      r'\tan': 'tan',
      r'\ln': 'ln',
      r'\log': 'log',
      r'\max': 'max',
      r'\min': 'min',
      r'\{': '{',
      r'\}': '}',
      r'\%': '%',
      r'\quad': ' ',
      r'\qquad': ' ',
      r'\;': '',
      r'\!': '',
      r'\,': '',
      r'\\': ' ',
    };
    for (final entry in commands.entries) {
      text = text.replaceAll(entry.key, entry.value);
    }

    // 3. 剩余反斜杠：未知命令保留命令名（只用于匹配），孤立反斜杠删掉。
    text = text.replaceAllMapped(
      RegExp(r'\\([A-Za-z]+)'),
      (match) => match[1] ?? '',
    );
    text = text.replaceAll(r'\', '');

    // 4. Unicode 规范化（全角、数学符号、上标/单位点号）。
    for (final entry in _unicodeMap.entries) {
      text = text.replaceAll(entry.key, entry.value);
    }

    // 5. 数学定界符与残留花括号。
    text = text.replaceAll(r'$', '');
    text = text.replaceAllMapped(
      RegExp(r'\{([^{}]*)\}'),
      (match) => match[1] ?? '',
    );

    // 6. 去掉所有空白（匹配用；raw 仍保留在 TraceStep 里）。
    text = text.replaceAll(RegExp(r'\s+'), '');

    return text;
  }

  /// 规范化一个 trace 步骤（保留 raw 原样）。
  NormalizedStep normalizeStep(TraceStep step) =>
      NormalizedStep(traceStep: step, normalized: normalize(step.rawText));

  static final Map<String, String> _unicodeMap = _buildUnicodeMap();

  static Map<String, String> _buildUnicodeMap() {
    final map = <String, String>{
      '，': ',',
      '。': '.',
      '；': ';',
      '：': ':',
      '？': '?',
      '！': '!',
      '（': '(',
      '）': ')',
      '【': '[',
      '】': ']',
      '“': '"',
      '”': '"',
      '‘': "'",
      '’': "'",
      '、': ',',
      '—': '-',
      '–': '-',
      '−': '-',
      '×': '*',
      '÷': '/',
      '≤': '<=',
      '≥': '>=',
      '≠': '!=',
      '≈': '~=',
      '∈': 'in',
      '∪': 'union',
      '∩': 'intersect',
      '√': 'sqrt',
      '·': '*',
      '°C': 'degC',
      '℃': 'degC',
      '°': 'deg',
      '％': '%',
      '＄': r'$',
      '＆': '&',
      '＋': '+',
      '－': '-',
      '＝': '=',
      '＜': '<',
      '＞': '>',
      '／': '/',
      '＿': '_',
      '｛': '{',
      '｝': '}',
      '［': '[',
      '］': ']',
      '｜': '|',
      '＇': "'",
      '　': ' ',
      '¹': '^1',
      '²': '^2',
      '³': '^3',
    };
    for (var i = 0; i < 10; i++) {
      map[String.fromCharCode(0xFF10 + i)] = '$i';
    }
    for (var i = 0; i < 26; i++) {
      map[String.fromCharCode(0xFF21 + i)] = String.fromCharCode(0x41 + i);
      map[String.fromCharCode(0xFF41 + i)] = String.fromCharCode(0x61 + i);
    }
    return map;
  }
}
