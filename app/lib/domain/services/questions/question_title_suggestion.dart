/// 题名自动生成与校验（纯逻辑，不碰 Flutter / dart:io）。
///
/// 题目表新增可空的 `title` 后，拍照/组卷/粘贴进来的题大多没有题名。界面需要
/// 一个「够具体、能区分」的默认题名，这份逻辑只做这件事：从题干首个句子里取
/// 核心短语，按需拼上知识点或学科中文名，再按已有题名去重编号。
///
/// 口径：
/// * 只从题干/知识点/学科取词，绝不编造内容；题干为空或只剩图片占位时用兜底
///   题名「未命名题目」；
/// * 核心短语取题干首个句子（按 `。！？；` 与换行切；半角 `! ?` 不切，避免切断
///   阶乘、问号公式等）；先去掉开头的题号与括号来源（如「（2024·江苏）」「(1)」
///   「1.」），再删 Markdown 图片与「［图N］/[图N]/【图N】」占位；`$...$` 行内
///   公式保留内部文本、去掉 `$` 定界符；压缩连续空白；
/// * 拼装优先级：知识点 → 「知识点 · 核心短语」；无知识点但有学科 →
///   「学科中文 · 核心短语」；都没有 → 核心短语。总长不超过 [maxLength]；超长
///   先缩核心短语，再缩知识点；截断按标点优先、且不截断到半个括号；
/// * 去重：与已有题名按 [normalizeQuestionTitle] 归一后比较，冲突时追加「（2）」
///   「（3）」…直到不冲突（最多 99）；
/// * [suggestQuestionTitle] 的 `questionType` 目前只接收、不参与拼装（避免把英文
///   题型词塞进中文题名），留给后续按题型定制措辞。
library;

/// 兜底题名：题干为空或只剩图片占位时使用。
const String _kFallbackTitle = '未命名题目';

/// 学科键 → 中文名。键与 `CapabilityAction.subjectKeys` 对齐，另补英语/地理/
/// 政治三个常见学科；查不到的键直接用键本身（不硬编造中文名）。
const Map<String, String> _subjectLabelsZh = <String, String>{
  'math': '数学',
  'physics': '物理',
  'chemistry': '化学',
  'biology': '生物',
  'chinese': '语文',
  'english': '英语',
  'history': '历史',
  'geography': '地理',
  'politics': '政治',
  'informatics': '信息学竞赛',
  'qiangji': '强基计划',
};

/// 拼装时的分隔符：「 · 」（两侧各一个半角空格）。
const String _kTitleSeparator = ' · ';

/// 题干里图片占位的模式：「［图1］」「[图 1]」「【图2】」都认。
final RegExp _imagePlaceholderPattern = RegExp(
  r'[［\[【]\s*图\s*\d+\s*[］\]】]',
);

/// Markdown 图片：`![alt](url)`。
final RegExp _markdownImagePattern = RegExp(r'!\[[^\]]*\]\([^)]*\)');

/// 首句结束标点：全角句号/感叹号/问号/分号（不含半角，避免切断公式与阶乘）。
const Set<String> _sentenceEndChars = <String>{'。', '！', '？', '；'};

/// 截断核心短语时优先在这些标点处停。
const Set<String> _softBreakChars = <String>{
  '，',
  ',',
  '、',
  '：',
  ':',
  '；',
  ';',
};

/// 截断后从尾部去掉的装饰标点。
const Set<String> _trailingDecorationChars = <String>{
  '，',
  ',',
  '、',
  '。',
  '；',
  ';',
  '：',
  ':',
  '·',
  '-',
  '—',
  '！',
  '？',
};

/// 一个题名建议。
class QuestionTitleSuggestion {
  const QuestionTitleSuggestion({
    required this.title,
    required this.corePhrase,
    this.knowledgePoint,
    this.subjectLabel,
    this.usedKnowledgePoint = false,
    this.deduped = false,
  });

  /// 最终题名（已按 [suggestQuestionTitle] 的 `maxLength` 拼装、去重）。
  final String title;

  /// 核心短语（题干首个句子的净化版；兜底建议为空串）。
  final String corePhrase;

  /// 参与拼装的知识点名（规范化后）；没有则为 null。
  final String? knowledgePoint;

  /// 参与拼装的学科中文名；没有则为 null。
  final String? subjectLabel;

  /// 题名是否真的用到了知识点（被长度挤掉时为 false）。
  final bool usedKnowledgePoint;

  /// 是否因为与已有题名冲突而追加了编号。
  final bool deduped;

  @override
  String toString() {
    return 'QuestionTitleSuggestion(title: $title, corePhrase: $corePhrase, '
        'knowledgePoint: $knowledgePoint, subjectLabel: $subjectLabel, '
        'usedKnowledgePoint: $usedKnowledgePoint, deduped: $deduped)';
  }
}

/// 从题干生成题名建议。
///
/// [stem] 是题干原文；[knowledgePointNames] 按顺序取第一个非空项参与拼装；
/// [existingTitles] 用于去重；[maxLength] 是题名最大长度（按 runes 计，<= 0
/// 时按 1 处理）。
QuestionTitleSuggestion suggestQuestionTitle({
  required String stem,
  String? subjectKey,
  String? questionType,
  List<String> knowledgePointNames = const <String>[],
  List<String> existingTitles = const <String>[],
  int maxLength = 32,
}) {
  final int limit = maxLength < 1 ? 1 : maxLength;
  final String? knowledgePoint = _firstNonEmpty(knowledgePointNames);
  final String? subjectLabel = _subjectLabel(subjectKey);
  final String core = _corePhrase(stem, limit);
  if (core.isEmpty) {
    final String fallback =
        uniqueQuestionTitle(_kFallbackTitle, existingTitles);
    return QuestionTitleSuggestion(
      title: fallback,
      corePhrase: '',
      knowledgePoint: null,
      subjectLabel: null,
      deduped: fallback != _kFallbackTitle,
    );
  }

  String? prefix;
  if (knowledgePoint != null) {
    prefix = knowledgePoint;
  } else if (subjectLabel != null) {
    prefix = subjectLabel;
  }

  String coreFinal = core;
  String? prefixFinal = prefix;
  String base;
  if (prefixFinal == null) {
    coreFinal = _truncateBracketSafe(core, limit);
    base = coreFinal;
  } else {
    final int fullLength = _runesLength(prefixFinal) +
        _kTitleSeparator.length +
        _runesLength(coreFinal);
    if (fullLength > limit) {
      final int coreBudget =
          limit - _kTitleSeparator.length - _runesLength(prefixFinal);
      if (coreBudget >= 2) {
        coreFinal = _truncateBracketSafe(coreFinal, coreBudget);
      }
      final int afterCore = _runesLength(prefixFinal) +
          _kTitleSeparator.length +
          _runesLength(coreFinal);
      if (afterCore > limit) {
        final int prefixBudget =
            limit - _kTitleSeparator.length - _runesLength(coreFinal);
        if (prefixBudget >= 2) {
          prefixFinal = _truncateBracketSafe(prefixFinal, prefixBudget);
        } else {
          prefixFinal = null;
        }
      }
    }
    if (prefixFinal == null || prefixFinal.isEmpty || coreFinal.isEmpty) {
      prefixFinal = null;
      coreFinal = _truncateBracketSafe(core, limit);
      base = coreFinal;
    } else {
      base = prefixFinal + _kTitleSeparator + coreFinal;
    }
  }

  final String title = uniqueQuestionTitle(base, existingTitles);
  return QuestionTitleSuggestion(
    title: title,
    corePhrase: coreFinal,
    knowledgePoint: knowledgePoint,
    subjectLabel: subjectLabel,
    usedKnowledgePoint: knowledgePoint != null && prefixFinal != null,
    deduped: title != base,
  );
}

/// 规范化用户写过的题名：trim、压空白、去掉控制字符与换行；空串返回 null。
///
/// 换行/制表/控制字符统一变成单个空格再压缩，不会把两段文字粘在一起；不改动
/// 其它字符（标点、大小写、全角字母都保留）。
String? normalizeQuestionTitle(String? raw) {
  if (raw == null) {
    return null;
  }
  final StringBuffer buffer = StringBuffer();
  for (final int rune in raw.runes) {
    if (_isControlRune(rune)) {
      buffer.write(' ');
    } else {
      buffer.writeCharCode(rune);
    }
  }
  final String collapsed =
      buffer.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  return collapsed.isEmpty ? null : collapsed;
}

/// 题名是否可用：null/空白 false；规范化后长度 1..[maxLength]（按 runes 计）；
/// 含换行/制表/控制字符 false。
bool isValidQuestionTitle(String? raw, {int maxLength = 80}) {
  if (raw == null) {
    return false;
  }
  for (final int rune in raw.runes) {
    if (rune == 0x0A || rune == 0x0D || rune == 0x09) {
      return false;
    }
    if (_isControlRune(rune)) {
      return false;
    }
  }
  if (maxLength < 1) {
    return false;
  }
  final String? normalized = normalizeQuestionTitle(raw);
  if (normalized == null) {
    return false;
  }
  final int length = _runesLength(normalized);
  return length >= 1 && length <= maxLength;
}

/// 在 [existingTitles] 里给 [base] 找一个不冲突的题名。
///
/// 冲突判定按 [normalizeQuestionTitle] 归一（不区分英文大小写、全角空格当空格、
/// 连续空白压一个）。冲突时追加「（2）」「（3）」…直到不冲突；最多试到 99，
/// 99 个都被占用时返回「base（99）」（可能仍冲突，调用方需自行再校验）。
/// [base] 为空时先兜底成「未命名题目」。
String uniqueQuestionTitle(String base, Iterable<String> existingTitles) {
  final String normalizedBase = normalizeQuestionTitle(base) ?? _kFallbackTitle;
  final Set<String> used = <String>{};
  for (final String raw in existingTitles) {
    final String? normalized = normalizeQuestionTitle(raw);
    if (normalized != null) {
      used.add(_dedupKey(normalized));
    }
  }
  if (!used.contains(_dedupKey(normalizedBase))) {
    return normalizedBase;
  }
  for (int suffix = 2; suffix <= 99; suffix++) {
    final String candidate = '$normalizedBase（$suffix）';
    if (!used.contains(_dedupKey(candidate))) {
      return candidate;
    }
  }
  return '$normalizedBase（99）';
}

// ---------------------------------------------------------------------------
// 内部实现
// ---------------------------------------------------------------------------

String? _firstNonEmpty(List<String> values) {
  for (final String value in values) {
    final String? normalized = normalizeQuestionTitle(value);
    if (normalized != null) {
      return normalized;
    }
  }
  return null;
}

String? _subjectLabel(String? subjectKey) {
  if (subjectKey == null) {
    return null;
  }
  final String key = subjectKey.trim();
  if (key.isEmpty) {
    return null;
  }
  return _subjectLabelsZh[key] ?? key;
}

String _corePhrase(String stem, int limit) {
  String text = stem.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  text = text.replaceAll(_markdownImagePattern, ' ');
  text = text.replaceAll(_imagePlaceholderPattern, ' ');
  text = _stripLeadingDecorations(text);
  String phrase = _firstSentence(text);
  phrase = _stripFormulaDelimiters(phrase);
  phrase = phrase.replaceAll(RegExp(r'\s+'), ' ').trim();
  phrase = _trimTrailingDecoration(phrase);
  if (phrase.isEmpty) {
    return '';
  }
  if (_runesLength(phrase) > limit) {
    phrase = _truncateCorePhrase(phrase, limit);
  }
  return phrase;
}

/// 去掉开头的题号与括号来源（可叠加，如「1.（2024·江苏）计算…」）。
String _stripLeadingDecorations(String text) {
  String result = text;
  for (int round = 0; round < 8; round++) {
    final String before = result;
    result = result.replaceFirst(RegExp(r'^\s+'), '');
    result = result.replaceFirst(
      RegExp(r'^[（(]\s*(?:\d{1,3}|[一二三四五六七八九十百]{1,2})\s*[）)]\s*'),
      '',
    );
    result = result.replaceFirst(
      RegExp(r'^\d{1,3}\s*[.．、](?!\d)\s*'),
      '',
    );
    result = _stripLeadingSourceParens(result);
    if (result == before) {
      break;
    }
  }
  return result;
}

/// 若开头是「（…）」且括号内像来源（年份/地区/卷别），整段去掉。
String _stripLeadingSourceParens(String text) {
  if (text.isEmpty) {
    return text;
  }
  final String first = String.fromCharCode(text.runes.first);
  if (first != '（' && first != '(') {
    return text;
  }
  final List<int> runes = text.runes.toList();
  final String open = first;
  final String close = open == '（' ? '）' : ')';
  int closeIndex = -1;
  for (int i = 1; i < runes.length; i++) {
    if (String.fromCharCode(runes[i]) == close) {
      closeIndex = i;
      break;
    }
  }
  if (closeIndex < 0 || closeIndex > 40) {
    return text;
  }
  final String inner =
      String.fromCharCodes(runes.sublist(1, closeIndex)).trim();
  if (inner.isEmpty || !_looksLikeSource(inner)) {
    return text;
  }
  final String after = String.fromCharCodes(runes.sublist(closeIndex + 1));
  return after.replaceFirst(RegExp(r'^\s+'), '');
}

/// 括号内容是否像来源：年份、地区或卷别词。
bool _looksLikeSource(String inner) {
  if (RegExp(r'(?:19|20)\d{2}').hasMatch(inner)) {
    return true;
  }
  const List<String> tokens = <String>[
    '届',
    '年',
    '全国',
    '省',
    '市',
    '区',
    '县',
    '卷',
    '模拟',
    '真题',
    '期末',
    '期中',
    '月考',
    '联考',
    '高考',
    '中考',
    '预赛',
    '初赛',
    '复赛',
    '竞赛',
    '统考',
    '学业水平',
  ];
  for (final String token in tokens) {
    if (inner.contains(token)) {
      return true;
    }
  }
  return false;
}

String _firstSentence(String text) {
  final StringBuffer buffer = StringBuffer();
  for (final int rune in text.runes) {
    final String char = String.fromCharCode(rune);
    if (char == '\n' || _sentenceEndChars.contains(char)) {
      break;
    }
    buffer.writeCharCode(rune);
  }
  return buffer.toString();
}

/// 去掉成对 `$...$` / `$$...$$` 的定界符，保留内部文本；落单的 `$` 原样保留。
String _stripFormulaDelimiters(String text) {
  String result = text.replaceAllMapped(
    RegExp(r'\$\$([^$]*)\$\$'),
    (Match match) => match.group(1) ?? '',
  );
  result = result.replaceAllMapped(
    RegExp(r'\$([^$]*)\$'),
    (Match match) => match.group(1) ?? '',
  );
  return result;
}

String _trimTrailingDecoration(String text) {
  final List<int> runes = text.runes.toList();
  int end = runes.length;
  while (end > 0) {
    final String char = String.fromCharCode(runes[end - 1]);
    if (!_trailingDecorationChars.contains(char)) {
      break;
    }
    end--;
  }
  return String.fromCharCodes(runes.sublist(0, end)).trim();
}

/// 核心短语超长截断：优先在标点处停，再做括号安全回退。
String _truncateCorePhrase(String text, int limit) {
  final List<int> runes = text.runes.toList();
  if (runes.length <= limit) {
    return text;
  }
  final int minKeep = (limit + 1) ~/ 2;
  int cut = limit;
  for (int i = limit - 1; i >= minKeep - 1; i--) {
    final String char = String.fromCharCode(runes[i]);
    if (_softBreakChars.contains(char)) {
      cut = i;
      break;
    }
  }
  final String prefix = String.fromCharCodes(runes.sublist(0, cut));
  final String safe = _bracketSafe(prefix);
  if (safe.isNotEmpty) {
    return safe;
  }
  // 整段都在未闭合括号里时退化为硬截断，避免题名直接变成兜底。
  return _trimTrailingDecoration(String.fromCharCodes(runes.sublist(0, limit)));
}

/// 截断到 [limit] 个 runes，且不落在半个括号里（宁可早停）。
String _truncateBracketSafe(String text, int limit) {
  final List<int> runes = text.runes.toList();
  if (runes.length <= limit) {
    return _bracketSafe(text);
  }
  final String prefix = String.fromCharCodes(runes.sublist(0, limit));
  final String safe = _bracketSafe(prefix);
  if (safe.isNotEmpty) {
    return safe;
  }
  return _trimTrailingDecoration(prefix);
}

/// 如果 [text] 结尾停在未闭合括号里，退回到那个开括号之前（宁可早停）。
String _bracketSafe(String text) {
  final List<int> runes = text.runes.toList();
  final int cutIndex = _earliestUnclosedOpener(runes);
  final List<int> kept = cutIndex >= 0 ? runes.sublist(0, cutIndex) : runes;
  return _trimTrailingDecoration(String.fromCharCodes(kept));
}

/// 返回第一个未闭合开括号的下标；没有则 -1。
int _earliestUnclosedOpener(List<int> runes) {
  final Map<String, String> pairs = <String, String>{
    '（': '）',
    '(': ')',
    '[': ']',
    '［': '］',
    '【': '】',
    '{': '}',
  };
  final List<int> stack = <int>[];
  final List<String> expected = <String>[];
  for (int i = 0; i < runes.length; i++) {
    final String char = String.fromCharCode(runes[i]);
    final String? closer = pairs[char];
    if (closer != null) {
      stack.add(i);
      expected.add(closer);
      continue;
    }
    if (expected.isNotEmpty && char == expected.last) {
      stack.removeLast();
      expected.removeLast();
    }
  }
  return stack.isEmpty ? -1 : stack.first;
}

bool _isControlRune(int rune) {
  if (rune < 0x20) {
    return true;
  }
  if (rune == 0x7F) {
    return true;
  }
  return rune >= 0x80 && rune <= 0x9F;
}

String _dedupKey(String normalizedTitle) {
  return normalizedTitle.toLowerCase();
}

int _runesLength(String text) => text.runes.length;
