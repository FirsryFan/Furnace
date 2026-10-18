/// 组卷网文本搜题：从题干抽取**候选检索词**（纯 Dart，确定性，不联网）。
///
/// 规则唯一权威（本文件是对它的逐条移植，改口径必须同步标准）：
/// D:\dsh-data\skills\zujuan-source-standards\scripts\keywords.mjs
/// 的 textLayerOnly / segments / isContent / anchoredCandidates /
/// diverseWindows / score / keywordsFor。
///
/// 为什么需要这一层（SKILL.md §6.2:213-242、references/url-grammar.md:219-221）：
///  * 组卷网搜索是**字符串匹配**而非语义检索；整段题干去搜必然匹配不上——
///    行内公式/结构式在站点是 SVG 图片，文本层里没有这些字符
///    （实测：含化学式 → 相似度 0.13~0.68、某题 0 结果；只放中文 → 0.67~0.91、10 条结果）；
///  * 两三个字去搜又太泛，返回一堆不相干的题。
///  * 所以只取「文本层真实存在」的连续片段，按内容词密度排序，一条不中换下一条
///    （每题 5~8 条候选；SKILL.md:238）。
///
/// 保留/剔除口径（与 skill 一致）：
///  * 剔除 $...$ 行内公式、Markdown 图片、〔…〕自定义标记（站点是图片/标记）；
///  * **保留**拉丁字母与数字：DNA/TdR/OD 在站点是正文文本，剥掉会把相邻中文接成
///    站点上不存在的串（keywords.mjs:48-52 的实测教训）；
///  * 标点当分隔符（不跨句读），候选长度 4–28（keywords.mjs:53-54, 63-69, 161-165）。
///
/// 已知局限（移植时**原样保留**，未擅自扩展）：领域词表 _domainWords 只覆盖
/// 生物学科（keywords.mjs:33-34 注释「其它学科可直接补词表」）。物理/化学/语文
/// 题干没有领域词锚点时走 diverseWindows 兜底窗口，候选质量依赖题干本身；
/// 要提升非生物学科命中率，应在标准侧扩词表后再同步本文件。
library;

// keywords.mjs:27-30 单字停用词，原样移植（出现在候选串首尾会稀释匹配信号）。
const String _stopWords = '的了是在和与及或等一这那有为对下列叙述错误的是也就都能可以所被把从到于并且但因为'
    '所以如果其中该其此这些那些什么怎么怎样如何请回答若要则而且并不没有有图图示如表所示';

// keywords.mjs:35-41 领域词，原样移植（顺序参与锚点扫描顺序，不要重排）。
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
  r'''[，。、；：？！（）()《》【】\-—–…·,.;:?!"'`~\s]+''',
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
/// * 最多 [maxCandidates] 条（maxCandidates <= 0 时返回空）；
/// * 无可用文本层片段（如纯公式题干、只有套话的短题干）时返回空；
/// * 同一输入永远返回同一结果（确定性，便于测试与埋点复现）。
List<String> extractZujuanKeywords(String stem, {int maxCandidates = 8}) {
  if (maxCandidates <= 0 || stem.isEmpty) return const <String>[];
  final bag = <String, double>{};

  void push(String word) {
    if (word.isEmpty || word.length < 4 || word.length > 28) return;
    // keywords.mjs:163 用 Number(score.toFixed(2))，这里保持同样精度，
    // 否则同分候选的稳定顺序会与 skill 不一致。
    final score = double.parse(_keywordScore(word).toStringAsFixed(2));
    final previous = bag[word];
    if (previous == null || previous < score) bag[word] = score;
  }

  for (final segment in _segments(stem)) {
    final anchored = _anchoredCandidates(segment);
    for (final word in anchored) {
      push(word);
    }
    if (anchored.isEmpty) {
      for (final word in _diverseWindows(segment)) {
        push(word);
      }
    }
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
      // JS Array.sort 稳定（ES2019）：同分保持首次入袋顺序。
      return firstSeen[a.key]!.compareTo(firstSeen[b.key]!);
    });

  final picked = <String>[];
  for (final entry in sorted) {
    if (picked.length >= maxCandidates) break;
    final word = entry.key;
    // keywords.mjs:180 互为子串的候选只留一个，保证候选彼此独立。
    final overlaps = picked.any(
      (kept) => kept.contains(word) || word.contains(kept),
    );
    if (overlaps) continue;
    picked.add(word);
  }
  return picked;
}

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
      .where((segment) => segment.length >= 4)
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

List<String> _anchoredCandidates(String segment) {
  final candidates = <String>[];
  for (final domain in _domainWords) {
    var from = 0;
    while (true) {
      final index = segment.indexOf(domain, from);
      if (index < 0) break;
      from = index + 1;
      var start = index;
      var end = index + domain.length;
      // 向左扩：允许越过「的」这类连接字，但最多 10 个字。
      var budget = 10;
      while (start > 0 && budget > 0) {
        budget -= 1;
        final character = segment[start - 1];
        if (!_isContent(character) && character != '的') break;
        start -= 1;
      }
      budget = 10;
      while (end < segment.length && budget > 0) {
        budget -= 1;
        final character = segment[end];
        if (!_isContent(character)) break;
        end += 1;
      }
      var window = segment.substring(start, end);
      // 修掉落在首尾的停用字（如「的xxx」）。
      window = window
          .replaceFirst(_leadingStopPattern, '')
          .replaceFirst(_trailingStopPattern, '');
      if (window.length >= 4 && window.length <= 24) {
        candidates.add(window);
      }
    }
  }
  return candidates;
}

List<String> _diverseWindows(String segment, {int limit = 3}) {
  final candidates = <_WindowCandidate>[];
  for (var length = 12; length >= 5; length--) {
    for (var start = 0; start + length <= segment.length; start++) {
      final word = segment.substring(start, start + length);
      if (!_isContent(word[0]) || !_isContent(word[word.length - 1])) {
        continue;
      }
      final uniqueRatio = word.runes.toSet().length / length;
      candidates.add(
        _WindowCandidate(
          word: word,
          score: uniqueRatio * 6 + (length >= 5 && length <= 14 ? 2 : 0),
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
    // JS 稳定排序下同分同起点时先插入的是更长窗口（外层 L 从 12 递减）。
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

double _keywordScore(String window) {
  final length = window.length;
  var score = _domainHits(window) * 4.0;
  if (length >= 5 && length <= 16) {
    score += 3;
  } else if (length > 20) {
    score -= 2;
  }
  final contentCount = window.runes
      .where((rune) => _isContent(String.fromCharCode(rune)))
      .length;
  score += (contentCount / length) * 5;
  score += (window.runes.toSet().length / length) * 3;
  return score;
}
