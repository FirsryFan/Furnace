/// 组卷网文本搜题：从题干抽取**候选检索词**（纯 Dart，确定性，不联网）。
///
/// 口径来源：用户 2026-10-25 反馈「检索词太短、多为 5–14 字」，要求
///  * 理科（数学/物理/化学/生物）15–30 字；
///  * 文科（语文/英语/历史/政治/地理）20–40 字，且每条**严格短于题干**；
///  * 题干本身短于目标下限时，回退为「尽量长的合法子串」（≥4 字），不硬凑长度。
///
/// ⚠️ 与标准侧已分歧（待标准侧同步）：D:\dsh-data\skills\zujuan-source-standards\scripts\keywords.mjs
/// 仍是旧的 4–28 字口径。本文件**不再逐条移植**它；清洗规则、锚点词表与评分骨架
/// 仍沿用该脚本（textLayerOnly / segments / anchoredCandidates / diverseWindows /
/// score），差的只是目标长度带与短题干回退策略。下次改口径先改这段注释与下面的
/// 四个长度常量，再补 app/test/domain/services/zujuan/ 下的测试。
///
/// 为什么需要这一层（SKILL.md §6.2:213-242、references/url-grammar.md:219-221）：
///  * 组卷网搜索是**字符串匹配**而非语义检索；整段题干去搜必然匹配不上——
///    行内公式/结构式在站点是 SVG 图片，文本层里没有这些字符
///    （实测：含化学式 → 相似度 0.13~0.68、某题 0 结果；只放中文 → 0.67~0.91、10 条结果）；
///  * 两三个字去搜太泛；5–14 字仍偏短、命中率不稳，所以按学科带把窗口拉到
///    15–30 / 20–40 字；
///  * 候选必须是**清洗后题干里真实存在的连续子串**：站点按字符匹配，跨公式或
///    跨句读拼接出来的串在站点上不存在，只会 0 结果。
///
/// 保留/剔除口径（沿用标准侧）：
///  * 剔除 $...$ 行内公式、Markdown 图片、〔…〕自定义标记（站点是图片/标记）；
///  * **保留**拉丁字母与数字：DNA/TdR/OD 在站点是正文文本，剥掉会把相邻中文接成
///    站点上不存在的串（keywords.mjs:48-52 的实测教训）；
///  * 标点当分隔符（不跨句读）。
///
/// 已知局限：领域词表 _domainWords 只覆盖生物学科（keywords.mjs:33-34 注释
/// 「其它学科可直接补词表」）。物理/化学/语文题干没有锚点时走滑窗兜底，
/// 候选质量依赖题干本身；要提升非生物学科命中率应在标准侧扩词表后同步。
library;

/// 检索词长度带：理科 vs 文科（口径见 library doc）。
enum ZujuanSubjectBand { science, humanities }

/// 理科候选检索词目标长度下限（含）。
const int kZujuanScienceMinLength = 15;

/// 理科候选检索词目标长度上限（含）。
const int kZujuanScienceMaxLength = 30;

/// 文科候选检索词目标长度下限（含）。
const int kZujuanHumanitiesMinLength = 20;

/// 文科候选检索词目标长度上限（含）。
const int kZujuanHumanitiesMaxLength = 40;

/// 候选检索词的最短长度：低于它基本没有匹配信号，宁可不返回。
const int _minCandidateLength = 4;

/// 由题库学科键判定长度带。
///
/// * science：math / physics / chemistry / biology；
/// * humanities：chinese / english / history / politics / geography；
/// * null / 空白 / 其它键（informatics、qiangji、未知）→ science：
///   未知学科宁可按更宽松的理科口径给 15–30 字，短于下限时同样会回退。
ZujuanSubjectBand zujuanSubjectBandFor(String? subjectKey) {
  final key = (subjectKey ?? '').trim().toLowerCase();
  switch (key) {
    case 'chinese':
    case 'english':
    case 'history':
    case 'politics':
    case 'geography':
      return ZujuanSubjectBand.humanities;
  }
  return ZujuanSubjectBand.science;
}

// keywords.mjs:27-30 单字停用词，原样沿用（出现在候选串首尾会稀释匹配信号）。
const String _stopWords = '的了是在和与及或等一这那有为对下列叙述错误的是也就都能可以所被把从到于并且但因为'
    '所以如果其中该其此这些那些什么怎么怎样如何请回答若要则而且并不没有有图图示如表所示';

// keywords.mjs:35-41 领域词，原样沿用（顺序参与锚点扫描顺序，不要重排）。
const List<String> _domainWords = <String>[
  '酶',
  '素',
  '基因',
  '细胞',
  '染色体',
  '遗传',
  '培养基',
  '杂交',
  '表型',
  '电泳',
  '探针',
  '菌',
  '蛋白质',
  '分子',
  '反应',
  '代谢',
  '分裂',
  '突变',
  '纯合',
  '杂合',
  '显性',
  '隐性',
  '转录',
  '翻译',
  '表达',
  '载体',
  '质粒',
  '引物',
  '序列',
  '种群',
  '群落',
  '生态',
  '免疫',
  '呼吸',
  '光合',
  '自噬',
  '凋亡',
  '信号',
  '通路',
  '受体',
  '实验',
  '浓度',
  '溶液',
  '曲线',
  '图谱',
  '结构',
  '功能',
  '调节',
  '合成',
  '降解',
];

// keywords.mjs:55-61 清洗规则：公式/图片/〔〕标记 → 分隔符；标点/空白串 → 分隔符。
final RegExp _inlineFormulaPattern = RegExp(r'\$[^$\n]*\$');
final RegExp _markdownImagePattern = RegExp(r'!\[[^\]]*\]\([^)]*\)');
final RegExp _customMarkerPattern = RegExp('〔[^〕]*〕');
// 原文类含 ASCII 双/单引号的重复项，这里去重后等价；\- 是字面量连字符，\s 是空白。
final RegExp _punctuationPattern = RegExp(
  r'''[，。、；：？！（）()《》【】\-—–…·,.;:?!"'~\s]+''',
);

final RegExp _latinOrDigitPattern = RegExp(r'[A-Za-z0-9]');
final RegExp _hanPattern = RegExp(r'[\u4e00-\u9fa5]');
final RegExp _leadingStopPattern = RegExp('^[$_stopWords]+');
final RegExp _trailingStopPattern = RegExp('[$_stopWords]+\$');

/// 一条窗口候选（diverseWindows 的排序中间结果）。
class _WindowCandidate {
  const _WindowCandidate({
    required this.word,
    required this.score,
    required this.start,
    required this.length,
  });

  final String word;
  final double score;
  final int start;
  final int length;
}

/// 从题干抽取候选检索词，按建议尝试顺序（内容词密度降序）返回。
///
/// * [band] 决定目标长度带（见 [ZujuanSubjectBand]）；
/// * 最多 [maxCandidates] 条（maxCandidates <= 0 时返回空）；
/// * 每条候选都是清洗后某一连续段（或段内连续窗口）的原文子串，不跨公式/标点拼接；
/// * 文科档每条严格短于题干（题干只剩 4–5 字时无法再短，放宽为不超过题干长度）；
/// * 题干短于目标下限时回退为「尽量长的合法子串」（≥4 字），不返回空；
/// * 同一输入永远返回同一结果（确定性，便于测试与埋点复现）。
List<String> extractZujuanKeywords(
  String stem, {
  int maxCandidates = 8,
  ZujuanSubjectBand band = ZujuanSubjectBand.science,
}) {
  if (maxCandidates <= 0) return const <String>[];
  final trimmedStem = stem.trim();
  if (trimmedStem.isEmpty) return const <String>[];

  final stemLength = trimmedStem.length;
  final bandMin = band == ZujuanSubjectBand.science
      ? kZujuanScienceMinLength
      : kZujuanHumanitiesMinLength;
  final bandMax = band == ZujuanSubjectBand.science
      ? kZujuanScienceMaxLength
      : kZujuanHumanitiesMaxLength;

  // 候选长度硬上限：不超过题干；文科还要严格短于题干（题干 ≤5 字时放宽）。
  var upper = bandMax < stemLength ? bandMax : stemLength;
  if (band == ZujuanSubjectBand.humanities &&
      stemLength - 1 >= _minCandidateLength) {
    final strictShorter = stemLength - 1;
    if (strictShorter < upper) upper = strictShorter;
  }
  if (upper < _minCandidateLength) return const <String>[];

  // 软下限：只在低于它时扣分，不做硬过滤（短题干回退允许更短）。
  final lower = bandMin <= upper ? bandMin : upper;
  final bag = <String, double>{};

  void push(String word) {
    if (word.length < _minCandidateLength || word.length > upper) return;
    // 用 toFixed(2) 同精度，避免同分候选的稳定顺序被浮点噪声打乱。
    final score = double.parse(
      _keywordScore(word, minLength: lower, maxLength: upper)
          .toStringAsFixed(2),
    );
    final previous = bag[word];
    if (previous == null || previous < score) bag[word] = score;
  }

  for (final segment in _segments(stem)) {
    final targetUpper = segment.length < upper ? segment.length : upper;
    if (targetUpper < _minCandidateLength) continue;

    final anchored = _anchoredCandidates(
      segment,
      targetUpper: targetUpper,
      lower: lower,
    );
    if (anchored.isNotEmpty) {
      for (final word in anchored) {
        push(word);
      }
      continue;
    }

    final windowed = _diverseWindows(
      segment,
      maxLength: targetUpper,
      minLength: lower,
    );
    if (windowed.isNotEmpty) {
      for (final word in windowed) {
        push(word);
      }
      continue;
    }

    // 段太短，凑不出目标区间：回退为尽量长的合法子串，不返回空。
    final fallback = _fallbackCandidate(
      segment,
      upper: targetUpper,
      lower: lower,
    );
    if (fallback != null) push(fallback);
  }

  final entries = bag.entries.toList(growable: false);
  final firstSeen = <String, int>{};
  for (var i = 0; i < entries.length; i++) {
    firstSeen[entries[i].key] = i;
  }
  final sorted = entries.toList()
    ..sort((a, b) {
      final byScore = b.value.compareTo(a.value);
      if (byScore != 0) return byScore;
      // 同分保持首次入袋顺序（确定性）。
      return firstSeen[a.key]!.compareTo(firstSeen[b.key]!);
    });

  final picked = <String>[];
  for (final entry in sorted) {
    if (picked.length >= maxCandidates) break;
    final word = entry.key;
    var overlapsIndex = -1;
    for (var i = 0; i < picked.length; i++) {
      final kept = picked[i];
      if (kept.contains(word) || word.contains(kept)) {
        overlapsIndex = i;
        break;
      }
    }
    if (overlapsIndex < 0) {
      picked.add(word);
      continue;
    }
    // 互为子串只留一个：落回目标区间的长候选优先（长串匹配信号更强）。
    final kept = picked[overlapsIndex];
    final wordInRange = _isInRange(word, lower, upper);
    final keptInRange = _isInRange(kept, lower, upper);
    if (wordInRange && !keptInRange && word.length > kept.length) {
      picked[overlapsIndex] = word;
    }
  }
  return picked;
}

bool _isInRange(String word, int lower, int upper) =>
    word.length >= lower && word.length <= upper;

String _textLayerOnly(String input) {
  return input
      .replaceAll(_inlineFormulaPattern, '\u0000')
      .replaceAll(_markdownImagePattern, '\u0000')
      .replaceAll(_customMarkerPattern, '\u0000')
      .replaceAll(_punctuationPattern, '\u0000');
}

List<String> _segments(String text) {
  return _textLayerOnly(text)
      .split('\u0000')
      .map((segment) => segment.trim())
      .where((segment) => segment.length >= _minCandidateLength)
      .toList(growable: false);
}

bool _isContent(String character) {
  if (_latinOrDigitPattern.hasMatch(character)) return true;
  return _hanPattern.hasMatch(character) && !_stopWords.contains(character);
}

int _domainHits(String window) {
  var hits = 0;
  for (final word in _domainWords) {
    if (window.contains(word)) hits += 1;
  }
  return hits;
}

/// 锚点候选：以领域词为种子向左右扩到目标长度（同一段内，可越过「的」等连接字；
/// 锚点扩不够时继续在同段内取字）。
List<String> _anchoredCandidates(
  String segment, {
  required int targetUpper,
  required int lower,
}) {
  final candidates = <String>[];
  for (final domain in _domainWords) {
    var from = 0;
    while (true) {
      final index = segment.indexOf(domain, from);
      if (index < 0) break;
      from = index + 1;
      final window = _expandAroundAnchor(
        segment,
        anchorStart: index,
        anchorLength: domain.length,
        targetLength: targetUpper,
        lower: lower,
      );
      if (window != null) candidates.add(window);
    }
  }
  return candidates;
}

String? _expandAroundAnchor(
  String segment, {
  required int anchorStart,
  required int anchorLength,
  required int targetLength,
  required int lower,
}) {
  final segmentLength = segment.length;
  if (targetLength < _minCandidateLength ||
      segmentLength < _minCandidateLength) {
    return null;
  }
  final wanted = targetLength < segmentLength ? targetLength : segmentLength;
  // 以锚点为中心向左右扩；越界就整体平移回段内（不跨段）。
  var start = anchorStart - ((wanted - anchorLength) ~/ 2);
  final maxStart = segmentLength - wanted;
  if (start > maxStart) start = maxStart;
  if (start < 0) start = 0;
  final word = segment.substring(start, start + wanted);
  return _fitCandidate(word, lower: lower);
}

/// 去掉首尾停用字；去掉后太短或掉出目标区间时宁可退回原串
/// （原串仍是题干真实子串，只是两端多了「的/是」这类字）。
String _fitCandidate(String word, {required int lower}) {
  final trimmed = word
      .replaceFirst(_leadingStopPattern, '')
      .replaceFirst(_trailingStopPattern, '');
  if (trimmed.length < _minCandidateLength) return word;
  if (trimmed.length < lower && word.length >= lower) return word;
  return trimmed;
}

/// 无锚点段：滑窗（窗口长从目标上限递减到目标下限），按内容字密度/去重比例挑，
/// 非重叠取前 [limit] 条。
List<String> _diverseWindows(
  String segment, {
  required int maxLength,
  required int minLength,
  int limit = 3,
}) {
  final shortest =
      minLength < _minCandidateLength ? _minCandidateLength : minLength;
  final candidates = <_WindowCandidate>[];
  for (var length = maxLength; length >= shortest; length--) {
    for (var start = 0; start + length <= segment.length; start++) {
      final word = segment.substring(start, start + length);
      if (!_isContent(word[0]) || !_isContent(word[word.length - 1])) {
        continue;
      }
      final contentRatio = word.runes
              .where((rune) => _isContent(String.fromCharCode(rune)))
              .length /
          length;
      final uniqueRatio = word.runes.toSet().length / length;
      candidates.add(
        _WindowCandidate(
          word: word,
          score: 4.0 + contentRatio * 5 + uniqueRatio * 3,
          start: start,
          length: length,
        ),
      );
    }
  }
  candidates.sort((a, b) {
    final byScore = b.score.compareTo(a.score);
    if (byScore != 0) return byScore;
    if (a.start != b.start) return a.start.compareTo(b.start);
    // 同分同起点时先取更长窗口（外层长度从大到小递减）。
    return b.length.compareTo(a.length);
  });
  final picked = <String>[];
  final used = <_WindowCandidate>[];
  for (final candidate in candidates) {
    if (picked.length >= limit) break;
    final overlaps = used.any(
      (u) =>
          candidate.start < u.start + u.length &&
          u.start < candidate.start + candidate.length,
    );
    if (overlaps) continue;
    picked.add(candidate.word);
    used.add(candidate);
  }
  return picked;
}

/// 短段/短题干回退：尽量长（不超过 [upper]）的合法子串，去停用字后仍 ≥4 字；
/// 若窗口下没有候选，至少返回整段本身（题干 ≥4 字时保证不返回空）。
String? _fallbackCandidate(
  String segment, {
  required int upper,
  required int lower,
}) {
  final limit = segment.length < upper ? segment.length : upper;
  if (limit < _minCandidateLength) return null;
  final whole = segment.length <= upper ? segment : segment.substring(0, limit);
  final fitted = _fitCandidate(whole, lower: lower);
  if (fitted.length > upper) return fitted.substring(0, upper);
  return fitted;
}

double _keywordScore(
  String window, {
  required int minLength,
  required int maxLength,
}) {
  final length = window.length;
  var score = _domainHits(window) * 4.0;
  // 落在目标区间内加分；低于下限按每字扣分；超过上限也按每字扣分。
  if (length >= minLength && length <= maxLength) {
    score += 6;
  } else if (length < minLength) {
    score -= (minLength - length) * 0.5;
  } else {
    score -= (length - maxLength) * 0.5;
  }
  final contentCount = window.runes
      .where((rune) => _isContent(String.fromCharCode(rune)))
      .length;
  score += (contentCount / length) * 5;
  score += (window.runes.toSet().length / length) * 3;
  return score;
}
