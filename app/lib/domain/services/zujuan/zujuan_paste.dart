/// 组卷网题面**粘贴文本**解析器：纯逻辑（不联网、不读 DB、不碰 UI）。
///
/// 为什么需要这一层（规则与站点证据见 D:\dsh-data\skills\zujuan-source-standards）：
///  * 题目详情页 /<bankid>q<id>.html 的 DOM 里没有选项：站点内联脚本直接执行
///    $(".quesdiv .exam-item__opt").remove();，skill 的 extract 在详情页拿到的
///    optRuns 恒为空（references/url-grammar.md:149-164）。所以详情页只能读到
///    题干（残缺）+【答案】/【解析】；完整选项只在列表页/搜索结果页卡片里。
///  * 卡片的完整题面由扩展 content.js 的 cardText 返回 body
///    （references/bridge-protocol.md:43、content.js:492-547），不限长度；
///    其中站点自定义标记 <t>/<wave>/<dot> 已被 runsToPlain 转成
///    〔加点〕…〔/加点〕/〔波浪线〕…〔/波浪线〕/〔着重号〕…〔/着重号〕
///    （content.js:21、:69-81；url-grammar.md:166-190）。
///  * 所以 App 侧「定点找题」的闭环是：生成筛选链接（zujuan_link.dart）→
///    浏览器里找到题、复制卡片题面与详情页答案 → 粘贴回 App → 本文件把文本
///    解析成题目草稿 → 人工确认后入库。本文件只负责最后一步的纯文本解析。
///
/// 解析口径（务实、容错优先）：
///  * 题目边界：行首数字序号（1. / 1．/ 1、/ (1) / （1））连续递增处优先；
///    没有可用序号时按空行分段，只有「上一题已完成」或「下一段像新题开头」
///    才切分（宁可少切，不把一题切碎）。
///  * 题干/选项：行首或行内的 A. / A、/ A． 标签（A-H）抽选项；同一行多个选项、
///    每个选项跨行续写都支持。认选项时要求从 A 连续递增，避免把题干里的
///    「A、B 两点」误当选项。
///  * 元数据：【答案】【解析】【详解】【解答】【分析】【知识点】【考点】【难度】
///    【出处】【来源】【题型】【专题】以及「答案：」「解析：」等行内标签；
///    答案与解析保留原文换行，知识点按、，,；;空白切分去重；难度/题型/专题
///    只识别、不落字段（题目草稿契约里没有对应字段，也绝不混进题干）。
///  * 来源与年份：题首或题干首行末尾的括号（如（2023·湖南·长沙·一模）/
///    （2024届湖南省长沙市…））以及【出处】行，抽 sourceLabel / year / region。
///  * 组卷网 ID：文本里出现 10q123456.html、10q123456、qid=123456、
///    bankid=10 或组卷网详情页 URL 时，抽 zujuanQuestionId / zujuanBankId /
///    sourceUrl；两个 ID 齐全且没抓到 URL 时用 zujuanQuestionId 拼详情页链接。
///  * 兜底：整段文本没有任何题目结构（无序号/选项/元数据/（　）括号/题面特征词）
///    时，整段作为一个题目草稿（stem=原文），警告「未识别题目结构，已按单题处理」，
///    isPartial=true。永不抛异常；同一输入永远同一结果（无随机、无 DateTime.now）。
///
/// 已知局限（有意保留，接线时按需提示人工核对）：
///  * 纯文本里分不清「解答题的小题号 (1)(2)」和「多题序号 (1)(2)」：
///    只有各段带选项/答案/（　）括号时才按多题切分，否则视为同一题的小问。
///  * 题干里没有序号、也没有（　）括号/选项/元数据的两段纯文字会被当成一题。
///  * 来源括号只认题首、题干首行末尾、以及【出处】/【来源】行；夹在中间的不动。
///  * 【答案】在未登录页读不到是站点限制（SKILL.md:167），解析器只能如实留空。
library;

import 'zujuan_link.dart';

// ---------------------------------------------------------------------------
// 常量
// ---------------------------------------------------------------------------

/// 题目序号上限（更大的数字视为正文里的年份等，不做拆分）。
const int _maxOrdinal = 999;

/// 整段文本里没有任何题目结构时给单题草稿的告警。
const String _warningUnrecognizedStructure = '未识别题目结构，已按单题处理';

/// 能识别出元数据但题干为空时的告警。
const String _warningEmptyStem = '未识别到题干';

/// 只识别到题目 ID、缺 bankId 时无法拼详情页链接的告警。
const String _warningQuestionIdWithoutBankId = '只识别到题目 ID，缺少 bankId，无法拼详情页链接';

/// 只识别到 bankId、缺题目 ID 时的告警。
const String _warningBankIdWithoutQuestionId = '只识别到 bankId，缺少题目 ID，无法拼详情页链接';

/// 结构类告警：出现任意一条即 isPartial == true，入库前必须人工看。
const Set<String> _structuralWarnings = <String>{
  _warningUnrecognizedStructure,
  _warningEmptyStem,
};

const List<String> _answerLabels = <String>['答案'];

const List<String> _solutionLabels = <String>[
  '解析',
  '详解',
  '解答',
  '分析',
  '点评',
  '点睛'
];

const List<String> _knowledgePointLabels = <String>['知识点', '考点'];

const List<String> _difficultyLabels = <String>['难度系数', '难度'];

const List<String> _sourceLabels = <String>['出处', '来源'];

const List<String> _ignoredLabels = <String>['题型', '专题'];

/// 题面特征词：兜底判定「这段文本是否像一道题」用，只放强特征词。
const List<String> _questionWords = <String>[
  '下列',
  '正确',
  '错误',
  '说法',
  '叙述',
  '如图',
  '材料',
  '阅读',
  '回答',
  '求',
  '已知',
  '计算',
  '选择',
  '填空',
  '判断',
  '解释',
  '分析',
  '简述',
  '写出',
  '画出',
  '证明',
];

/// 来源括号里的强特征词（出现即认为是来源，而不是题干里的普通括号）。
const List<String> _sourceMarkers = <String>[
  '届',
  '高考',
  '模拟',
  '联考',
  '统考',
  '调研',
  '学业水平',
  '质量检测',
  '适应性',
  '真题',
  '月考',
  '期中',
  '期末',
  '一模',
  '二模',
  '三模',
  '名校',
  '联盟',
  '考试',
  '试题',
  '试卷',
  '卷',
];

/// 来源片段里不是地区名的词（按「·」切段后跳过）。
const Set<String> _nonRegionSegments = <String>{
  '一模',
  '二模',
  '三模',
  '模拟',
  '高考',
  '真题',
  '联考',
  '统考',
  '调研',
  '质检',
  '月考',
  '期中',
  '期末',
  '学业水平',
  '适应性',
  '试题',
  '试卷',
  '名校',
  '联盟',
  '考试',
};

final RegExp _newlinePattern = RegExp(r'\r\n|\r|\n');
final RegExp _horizontalSpacePattern = RegExp(r'[ \t]+');
final RegExp _markerTagPattern = RegExp(r'〔\s*/?\s*(?:加点|波浪线|着重号)\s*〕');
final RegExp _strongOrdinalPattern =
    RegExp(r'^\s*(\d{1,3})\s*(?:[.．](?!\d)|、)\s*');
final RegExp _weakOrdinalPattern = RegExp(r'^\s*[（(]\s*(\d{1,3})\s*[)）]\s*');
final RegExp _answerBracketPattern = RegExp(r'[（(][\s\u3000]*[)）]');
final RegExp _trailingAnswerBracketPattern = RegExp(r'[（(][\s\u3000]*[)）]\s*$');
final RegExp _leadingSourcePattern = RegExp(r'^[（(]([^（）()]{2,80})[)）]\s*');
final RegExp _trailingSourcePattern = RegExp(r'[（(]([^（）()]{2,80})[)）]\s*$');
final RegExp _yearInTextPattern = RegExp(r'(?:19|20)\d{2}');
final RegExp _optionLabelPattern = RegExp(r'([A-H])\s*[.．、:：]');
final RegExp _enumeratedLetterPattern = RegExp(r'^[B-H]');
final RegExp _urlPattern = RegExp(r'https?://[^\s<>"“”‘’()（）《》，。；：！？、]+');
final RegExp _detailPathPattern = RegExp(r'/(?:(\d{1,4}))?q(\d{3,})\.html');
final RegExp _bankQuestionTokenPattern =
    RegExp(r'(?:^|[^0-9A-Za-z])(\d{1,4})q(\d{3,})(?![0-9])');
final RegExp _queryQuestionIdPattern = RegExp(
  r'(?:^|[?&\s])(?:qid|questionid|question_id)\s*[=:]\s*(\d{3,})',
  caseSensitive: false,
);
final RegExp _queryBankIdPattern = RegExp(
  r'(?:^|[?&\s])(?:bankid|bank_id)\s*[=:]\s*(\d{1,4})',
  caseSensitive: false,
);
final RegExp _knowledgeSeparatorPattern = RegExp(r'[、，,；;／/\s]+');
final RegExp _regionSeparatorPattern = RegExp(r'[·・•|/／\s]+');
final RegExp _yearSuffixPattern = RegExp(r'((?:19|20)\d{2})\s*(?:届|年|[·・])');
final RegExp _bareYearPattern = RegExp(r'(?:^|[^0-9])((?:19|20)\d{2})(?!\d)');
final RegExp _fourDigitYearOnlyPattern = RegExp(r'^(?:19|20)\d{2}$');
final RegExp _administrationRegionPattern =
    RegExp(r'([\u4e00-\u9fa5]{2,4})(省|市|自治区)');
final RegExp _volumeRegionPattern = RegExp(r'([\u4e00-\u9fa5]{2,4})卷');
final RegExp _hanRegionSegmentPattern = RegExp(r'^[\u4e00-\u9fa5]{2,4}$');
final RegExp _trailingPunctuationPattern = RegExp(r'[.,;:!?]+$');

/// 元数据标签的「或」拼接（长的放前面，避免 难度 抢先匹配 难度系数）。
final String _metadataLabelAlternation = <String>[
  ..._answerLabels,
  ..._solutionLabels,
  ..._knowledgePointLabels,
  ..._difficultyLabels,
  ..._sourceLabels,
  ..._ignoredLabels,
].join('|');

final RegExp _bracketMetadataPattern = RegExp(
  '【\\s*('
  '$_metadataLabelAlternation'
  ')\\s*】',
);

final RegExp _bareMetadataPattern = RegExp(
  '(?:^|[\\s】）)])(('
  '$_metadataLabelAlternation'
  '))\\s*[:：]',
);

final RegExp _bareMetadataSpacePattern = RegExp(
  '^(答案|解析|详解|解答|分析|点评|点睛|知识点|考点|难度系数|难度|出处|来源|题型|专题)[\\s　]+',
);

// ---------------------------------------------------------------------------
// 公开 API
// ---------------------------------------------------------------------------

/// 一个粘贴解析出的选项（label 为 A-H 的大写字母，content 已 trim）。
class ZujuanPastedOption {
  const ZujuanPastedOption({required this.label, required this.content});

  /// 选项字母：A-H（大写）。
  final String label;

  /// 选项内容（不含字母与分隔符；跨行内容用空格拼接）。
  final String content;
}

/// 一条从粘贴文本解析出的题目草稿（纯数据，入库前仍需人工确认）。
class ZujuanPastedQuestion {
  ZujuanPastedQuestion({
    this.ordinal,
    required this.stem,
    List<ZujuanPastedOption> options = const <ZujuanPastedOption>[],
    this.answer,
    this.solution,
    this.sourceLabel,
    this.year,
    this.region,
    List<String> knowledgePoints = const <String>[],
    this.zujuanQuestionId,
    this.zujuanBankId,
    this.sourceUrl,
    List<String> warnings = const <String>[],
  })  : options = List<ZujuanPastedOption>.unmodifiable(options),
        knowledgePoints = List<String>.unmodifiable(knowledgePoints),
        warnings = List<String>.unmodifiable(warnings);

  /// 文本里识别出的题号（1 起；识别不到为 null）。
  final int? ordinal;

  /// 题干（去掉序号、来源括号与识别出的元数据行；题干内部换行保留）。
  final String stem;

  /// 选项（按 A、B、C… 顺序；没有选项的题型为空列表）。
  final List<ZujuanPastedOption> options;

  /// 【答案】内容（多行原样保留；未登录页读不到时为 null）。
  final String? answer;

  /// 【解析】/【详解】/【解答】等内容（多行原样保留）。
  final String? solution;

  /// 来源（如 2024届湖南省长沙市雅礼中学高三一模 / 2023·湖南·长沙·一模）。
  final String? sourceLabel;

  /// 从来源里抽出的 4 位年份（识别不到为 null，不猜）。
  final int? year;

  /// 从来源里抽出的地区（如 湖南；识别不到为 null，不猜）。
  final String? region;

  /// 知识点（按出现顺序去重）。
  final List<String> knowledgePoints;

  /// 组卷网题目 ID（纯数字串，原样保留）。
  final String? zujuanQuestionId;

  /// 组卷网学科库 ID（bankId，纯数字串）。
  final String? zujuanBankId;

  /// 组卷网链接（抓到的原链接，或由两个 ID 拼出的详情页链接）。
  final String? sourceUrl;

  /// 解析告警（中文、确定性顺序；结构类告警会让 [isPartial] 为 true）。
  final List<String> warnings;

  /// 结构是否不完整（题干为空 / 整段兜底 / 未识别到题干）→ 入库前必须人工看。
  bool get isPartial {
    if (stem.trim().isEmpty) return true;
    for (final warning in warnings) {
      if (_structuralWarnings.contains(warning)) return true;
    }
    return false;
  }
}

/// 把一段粘贴文本解析成题目草稿列表（永不抛异常；同一输入永远同一结果）。
///
/// * 空输入/纯空白输入返回空列表；
/// * 能识别出多题时按原顺序返回多条；
/// * 什么都识别不出时返回 1 条兜底草稿（stem=原文、isPartial=true）；
/// * 只做纯文本解析：不联网、不查重、不写库。
List<ZujuanPastedQuestion> parseZujuanPaste(String raw) {
  if (raw.trim().isEmpty) return const <ZujuanPastedQuestion>[];
  final normalized = _normalizeNewlines(raw);
  final lines =
      normalized.split('\n').map(_cleanInputLine).toList(growable: false);
  final blocks = _splitQuestionBlocks(lines);
  final questions = <ZujuanPastedQuestion>[];
  for (final block in blocks) {
    if (block.isEmpty) continue;
    questions.add(_BlockParser(block).parse());
  }
  if (questions.isEmpty) return const <ZujuanPastedQuestion>[];
  return List<ZujuanPastedQuestion>.unmodifiable(questions);
}

/// 把组卷网标记归一成人可读文本（确定性；同一输入永远同一结果）。
///
/// 组卷网用非标准标签表达强调（content.js:21 的 MARKER_TAGS）：
/// <t> = 加点、<wave> = 波浪线、<dot> = 着重号；扩展的 runsToPlain 已把成对标记
/// 转成 〔加点〕…〔/加点〕 等形式（content.js:69-81、url-grammar.md:166-190）。
/// 本函数删除这六种标记标签、**保留被标记的文字**（波浪线/加点在纯文本里没有
/// 可保留的排版语义），同时把 CRLF 归一成 LF、不间断空格换成普通空格、行内连续
/// 空白折叠成一个空格、每行 trim、去掉首尾空行。
///
/// 不认识的〔…〕标记（例如题库正文自带的〔1〕）原样保留，不误删。
String normalizeZujuanMarkers(String raw) {
  if (raw.trim().isEmpty) return '';
  final normalized = _normalizeNewlines(raw).replaceAll('\u00a0', ' ');
  final lines = <String>[];
  for (final sourceLine in normalized.split('\n')) {
    final line = sourceLine
        .replaceAll(_markerTagPattern, '')
        .replaceAll(_horizontalSpacePattern, ' ')
        .trim();
    lines.add(line);
  }
  while (lines.isNotEmpty && lines.first.isEmpty) {
    lines.removeAt(0);
  }
  while (lines.isNotEmpty && lines.last.isEmpty) {
    lines.removeLast();
  }
  return lines.join('\n');
}

// ---------------------------------------------------------------------------
// 输入归一与题目切分
// ---------------------------------------------------------------------------

String _normalizeNewlines(String raw) => raw.replaceAll(_newlinePattern, '\n');

String _cleanInputLine(String raw) {
  return raw
      .replaceAll('\u00a0', ' ')
      .replaceAll(_markerTagPattern, '')
      .replaceAll(_horizontalSpacePattern, ' ')
      .trim();
}

List<List<String>> _splitQuestionBlocks(List<String> lines) {
  final starts = _ordinalSplitStarts(lines);
  if (starts.length >= 2) {
    final blocks = _blocksFromStarts(lines, starts);
    if (blocks.length >= 2) return blocks;
  }
  return _blankLineBlocks(lines);
}

List<int> _ordinalSplitStarts(List<String> lines) {
  final candidates = _ordinalCandidates(lines);
  if (candidates.length < 2) return const <int>[];
  final accepted = <_OrdinalCandidate>[];
  for (var index = 0; index < candidates.length; index++) {
    final candidate = candidates[index];
    final end = index + 1 < candidates.length
        ? candidates[index + 1].lineIndex
        : lines.length;
    if (candidate.lineIndex < end &&
        _hasStrongQuestionSignal(lines.sublist(candidate.lineIndex, end))) {
      accepted.add(candidate);
    }
  }
  if (accepted.length < 2) return const <int>[];
  for (var index = 1; index < accepted.length; index++) {
    if (accepted[index].ordinal != accepted[index - 1].ordinal + 1) {
      return const <int>[];
    }
  }
  return accepted
      .map((candidate) => candidate.lineIndex)
      .toList(growable: false);
}

List<_OrdinalCandidate> _ordinalCandidates(List<String> lines) {
  final candidates = <_OrdinalCandidate>[];
  for (var index = 0; index < lines.length; index++) {
    final line = lines[index];
    if (line.isEmpty) continue;
    final strong = _strongOrdinalPattern.firstMatch(line);
    if (strong != null) {
      final ordinal = int.parse(strong.group(1)!);
      if (ordinal <= _maxOrdinal) {
        candidates.add(_OrdinalCandidate(
            lineIndex: index, ordinal: ordinal, strong: true));
      }
      continue;
    }
    final weak = _weakOrdinalPattern.firstMatch(line);
    if (weak != null) {
      final ordinal = int.parse(weak.group(1)!);
      if (ordinal <= _maxOrdinal) {
        candidates.add(_OrdinalCandidate(
            lineIndex: index, ordinal: ordinal, strong: false));
      }
    }
  }
  return candidates;
}

List<List<String>> _blocksFromStarts(List<String> lines, List<int> starts) {
  final sorted = starts.toSet().toList()..sort();
  final firstStart = sorted.first;
  final boundaries = <int>[0];
  for (final start in sorted) {
    if (start == firstStart && firstStart > 0) continue;
    if (start > 0) boundaries.add(start);
  }
  boundaries.sort();
  final blocks = <List<String>>[];
  for (var index = 0; index < boundaries.length; index++) {
    final start = boundaries[index];
    final end =
        index + 1 < boundaries.length ? boundaries[index + 1] : lines.length;
    var from = start;
    var to = end;
    while (from < to && lines[from].isEmpty) {
      from++;
    }
    while (to > from && lines[to - 1].isEmpty) {
      to--;
    }
    if (from < to) blocks.add(lines.sublist(from, to));
  }
  return blocks;
}

List<List<String>> _blankLineBlocks(List<String> lines) {
  final paragraphs = <List<String>>[];
  var current = <String>[];
  for (final line in lines) {
    if (line.isEmpty) {
      if (current.isNotEmpty) {
        paragraphs.add(current);
        current = <String>[];
      }
      continue;
    }
    current.add(line);
  }
  if (current.isNotEmpty) paragraphs.add(current);
  if (paragraphs.length <= 1) return paragraphs;
  final blocks = <List<String>>[];
  for (final paragraph in paragraphs) {
    if (blocks.isEmpty) {
      blocks.add(List<String>.from(paragraph));
      continue;
    }
    final currentBlock = blocks.last;
    if (_isContinuationParagraph(paragraph)) {
      currentBlock.addAll(paragraph);
      continue;
    }
    if (_endsCompletedQuestion(currentBlock) ||
        (_hasStrongQuestionSignal(currentBlock) &&
            _looksLikeNewQuestionParagraph(paragraph))) {
      blocks.add(List<String>.from(paragraph));
    } else {
      currentBlock.addAll(paragraph);
    }
  }
  return blocks;
}

bool _isContinuationParagraph(List<String> paragraph) {
  if (paragraph.isEmpty) return false;
  final first = paragraph.first;
  if (first.isEmpty) return false;
  final metadata = _metadataPieces(first);
  if (metadata != null && metadata.length > 1 && metadata.first.text.isEmpty) {
    return true;
  }
  final hits = _optionLabelHits(first);
  return hits.isNotEmpty && hits.first.start == 0;
}

bool _endsCompletedQuestion(List<String> block) {
  for (var index = block.length - 1; index >= 0; index--) {
    final line = block[index];
    if (line.isEmpty) continue;
    if (_optionLabelHits(line).isNotEmpty) return true;
    if (_metadataPieces(line) != null) return true;
    return false;
  }
  return false;
}

bool _looksLikeNewQuestionParagraph(List<String> paragraph) {
  if (paragraph.isEmpty) return false;
  final first = paragraph.first;
  if (first.isEmpty) return false;
  if (_matchOrdinal(first) != null) return true;
  if (_consumeLeadingSource(first) != null) return true;
  if (_trailingAnswerBracketPattern.hasMatch(first)) return true;
  return first.endsWith('？') || first.endsWith('?');
}

bool _hasStrongQuestionSignal(List<String> lines) {
  for (final line in lines) {
    if (line.isEmpty) continue;
    if (_answerBracketPattern.hasMatch(line)) return true;
    if (_metadataPieces(line) != null) return true;
    if (_optionLabelHits(line).isNotEmpty) return true;
  }
  return false;
}

// ---------------------------------------------------------------------------
// 行级识别
// ---------------------------------------------------------------------------

_OrdinalMatch? _matchOrdinal(String line) {
  final strong = _strongOrdinalPattern.firstMatch(line);
  if (strong != null) {
    final ordinal = int.parse(strong.group(1)!);
    if (ordinal <= _maxOrdinal) {
      return _OrdinalMatch(ordinal: ordinal, ordinalEnd: strong.end);
    }
  }
  final weak = _weakOrdinalPattern.firstMatch(line);
  if (weak != null) {
    final ordinal = int.parse(weak.group(1)!);
    if (ordinal <= _maxOrdinal) {
      return _OrdinalMatch(ordinal: ordinal, ordinalEnd: weak.end);
    }
  }
  return null;
}

_LeadingSource? _consumeLeadingSource(String line) {
  final match = _leadingSourcePattern.firstMatch(line);
  if (match == null) return null;
  final candidate = match.group(1)!.trim();
  if (!_looksLikeSource(candidate)) return null;
  return _LeadingSource(
      source: candidate, rest: line.substring(match.end).trim());
}

bool _looksLikeSource(String candidate) {
  final text = candidate.trim();
  if (text.length < 2 || text.length > 80) return false;
  if (_yearInTextPattern.hasMatch(text) &&
      (text.contains('届') ||
          text.contains('年') ||
          text.contains('·') ||
          text.contains('・') ||
          text.contains('高考') ||
          text.contains('模拟') ||
          text.contains('卷'))) {
    return true;
  }
  for (final marker in _sourceMarkers) {
    if (text.contains(marker)) return true;
  }
  return false;
}

bool _looksLikeQuestionText(String text) {
  if (text.isEmpty) return false;
  if (_answerBracketPattern.hasMatch(text)) return true;
  for (final word in _questionWords) {
    if (text.contains(word)) return true;
  }
  return false;
}

bool _startsWithEnumeratedLetter(String content) {
  return _enumeratedLetterPattern.hasMatch(content);
}

List<_LabelHit> _optionLabelHits(String line) {
  final hits = <_LabelHit>[];
  for (final match in _optionLabelPattern.allMatches(line)) {
    if (!_isOptionBoundary(line, match.start)) continue;
    hits.add(_LabelHit(
      letter: match.group(1)!,
      start: match.start,
      contentStart: match.end,
    ));
  }
  return hits;
}

bool _isOptionBoundary(String line, int index) {
  if (index <= 0) return true;
  final previous = line[index - 1];
  return previous == ' ' ||
      previous == '\t' ||
      previous == '　' ||
      previous == '）' ||
      previous == ')' ||
      previous == '】' ||
      previous == ']' ||
      previous == '>' ||
      previous == '；' ||
      previous == ';' ||
      previous == '，' ||
      previous == ',' ||
      previous == '：' ||
      previous == ':';
}

List<_MetadataPiece>? _metadataPieces(String line) {
  final marks = <_MetadataMark>[];
  for (final match in _bracketMetadataPattern.allMatches(line)) {
    marks.add(_MetadataMark(
        start: match.start, end: match.end, label: match.group(1)!));
  }
  for (final match in _bareMetadataPattern.allMatches(line)) {
    final label = match.group(1)!;
    final labelStart = match.end - 1 - label.length;
    if (marks
        .any((mark) => labelStart >= mark.start && labelStart < mark.end)) {
      continue;
    }
    marks.add(_MetadataMark(start: labelStart, end: match.end, label: label));
  }
  for (final match in _bareMetadataSpacePattern.allMatches(line)) {
    if (marks.any((mark) => mark.start == 0)) continue;
    marks.add(_MetadataMark(start: 0, end: match.end, label: match.group(1)!));
  }
  if (marks.isEmpty) return null;
  marks.sort((a, b) => a.start.compareTo(b.start));
  final unique = <_MetadataMark>[];
  for (final mark in marks) {
    if (unique.isNotEmpty && mark.start < unique.last.end) continue;
    unique.add(mark);
  }
  final pieces = <_MetadataPiece>[];
  pieces.add(_MetadataPiece(
      label: null, text: line.substring(0, unique.first.start).trim()));
  for (var index = 0; index < unique.length; index++) {
    final contentEnd =
        index + 1 < unique.length ? unique[index + 1].start : line.length;
    pieces.add(_MetadataPiece(
      label: unique[index].label,
      text: line.substring(unique[index].end, contentEnd).trim(),
    ));
  }
  return pieces;
}

// ---------------------------------------------------------------------------
// 年份 / 地区 / ID
// ---------------------------------------------------------------------------

int? _yearOf(String text, {bool allowBareYear = false}) {
  final withSuffix = _yearSuffixPattern.firstMatch(text);
  if (withSuffix != null) return int.parse(withSuffix.group(1)!);
  if (!allowBareYear) return null;
  final bare = _bareYearPattern.firstMatch(text);
  return bare == null ? null : int.parse(bare.group(1)!);
}

String? _regionOf(String label) {
  final explicit = _administrationRegionPattern.firstMatch(label);
  if (explicit != null) {
    final region = _stripYearPrefix(explicit.group(1)!);
    if (region.length >= 2) return region;
  }
  for (final segment in label.split(_regionSeparatorPattern)) {
    final trimmed = segment.trim();
    if (trimmed.isEmpty) continue;
    if (_fourDigitYearOnlyPattern.hasMatch(trimmed)) continue;
    if (trimmed.contains('届') || trimmed.contains('年')) continue;
    if (_nonRegionSegments.contains(trimmed)) continue;
    if (_hanRegionSegmentPattern.hasMatch(trimmed)) return trimmed;
  }
  final volume = _volumeRegionPattern.firstMatch(label);
  if (volume != null) {
    final region = _stripYearPrefix(volume.group(1)!);
    if (region.length >= 2) return region;
  }
  return null;
}

String _stripYearPrefix(String value) {
  var region = value;
  while (region.isNotEmpty && (region[0] == '届' || region[0] == '年')) {
    region = region.substring(1);
  }
  return region;
}

_YearRegion _extractYearRegion(String? sourceLabel, String raw) {
  int? year;
  String? region;
  if (sourceLabel != null) {
    year = _yearOf(sourceLabel, allowBareYear: true);
    region = _regionOf(sourceLabel);
  }
  year ??= _yearOf(raw);
  return _YearRegion(year: year, region: region);
}

_ExtractedIds _extractIds(String raw) {
  String? questionId;
  String? bankId;
  String? sourceUrl;
  for (final match in _urlPattern.allMatches(raw)) {
    var url = match.group(0)!;
    url = url.replaceFirst(_trailingPunctuationPattern, '');
    final isZujuan = url.contains('zujuan.xkw.com') || url.contains('xkw.com');
    if (!isZujuan) continue;
    sourceUrl ??= url;
    final detail = _detailPathPattern.firstMatch(url);
    if (detail != null) {
      bankId ??= detail.group(1);
      questionId ??= detail.group(2);
    }
  }
  final token = _bankQuestionTokenPattern.firstMatch(raw);
  if (token != null) {
    bankId ??= token.group(1);
    questionId ??= token.group(2);
  }
  questionId ??= _queryQuestionIdPattern.firstMatch(raw)?.group(1);
  bankId ??= _queryBankIdPattern.firstMatch(raw)?.group(1);
  if (sourceUrl == null && bankId != null && questionId != null) {
    sourceUrl = zujuanQuestionDetailUrl(bankId: bankId, questionId: questionId);
  }
  final warnings = <String>[];
  if (sourceUrl == null) {
    if (questionId != null && bankId == null) {
      warnings.add(_warningQuestionIdWithoutBankId);
    }
    if (bankId != null && questionId == null) {
      warnings.add(_warningBankIdWithoutQuestionId);
    }
  }
  return _ExtractedIds(
    questionId: questionId,
    bankId: bankId,
    sourceUrl: sourceUrl,
    warnings: warnings,
  );
}

// ---------------------------------------------------------------------------
// 单题解析
// ---------------------------------------------------------------------------

class _BlockParser {
  _BlockParser(this._lines);

  final List<String> _lines;

  int? _ordinal;
  String? _sourceLabel;
  final List<String> _stemLines = <String>[];
  final List<_OptionBuilder> _optionBuilders = <_OptionBuilder>[];
  final List<String> _answerLines = <String>[];
  final List<String> _solutionLines = <String>[];
  final List<String> _knowledgePointLines = <String>[];
  _Target _target = _Target.stem;
  int? _expectedOptionCodeUnit;
  bool _metadataFound = false;
  bool _sourceFound = false;

  ZujuanPastedQuestion parse() {
    for (var index = 0; index < _lines.length; index++) {
      final line = _lines[index];
      if (line.isEmpty) {
        _onBlankLine();
        continue;
      }
      var content = line;
      if (index == 0) {
        final ordinalMatch = _matchOrdinal(content);
        if (ordinalMatch != null) {
          _ordinal = ordinalMatch.ordinal;
          content = content.substring(ordinalMatch.ordinalEnd).trim();
        }
        if (content.isEmpty) continue;
        final leadingSource = _consumeLeadingSource(content);
        if (leadingSource != null) {
          _sourceLabel = leadingSource.source;
          _sourceFound = true;
          content = leadingSource.rest;
          if (content.isEmpty) continue;
        }
      }
      final metadata = _metadataPieces(content);
      if (metadata != null) {
        _applyMetadata(metadata);
        continue;
      }
      if (_target == _Target.stem || _target == _Target.option) {
        final optionLine = _parseOptionLine(content, index);
        if (optionLine != null) {
          _applyOptionLine(optionLine);
          continue;
        }
      }
      _appendContent(content);
    }
    return _build();
  }

  void _onBlankLine() {
    if (_target == _Target.stem) {
      if (_stemLines.isNotEmpty && _stemLines.last.isNotEmpty) {
        _stemLines.add('');
      }
    } else if (_target == _Target.answer) {
      if (_answerLines.isNotEmpty && _answerLines.last.isNotEmpty) {
        _answerLines.add('');
      }
    } else if (_target == _Target.solution) {
      if (_solutionLines.isNotEmpty && _solutionLines.last.isNotEmpty) {
        _solutionLines.add('');
      }
    }
  }

  void _applyMetadata(List<_MetadataPiece> pieces) {
    for (final piece in pieces) {
      final label = piece.label;
      if (label == null) {
        _appendContent(piece.text);
        continue;
      }
      _metadataFound = true;
      _target = _targetOfLabel(label);
      _appendContent(piece.text);
    }
  }

  _Target _targetOfLabel(String label) {
    if (_answerLabels.contains(label)) return _Target.answer;
    if (_solutionLabels.contains(label)) return _Target.solution;
    if (_knowledgePointLabels.contains(label)) return _Target.knowledgePoints;
    if (_sourceLabels.contains(label)) return _Target.source;
    return _Target.ignored;
  }

  void _appendContent(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    if (_target == _Target.stem) {
      _stemLines.add(trimmed);
      return;
    }
    if (_target == _Target.answer) {
      _answerLines.add(trimmed);
      return;
    }
    if (_target == _Target.solution) {
      _solutionLines.add(trimmed);
      return;
    }
    if (_target == _Target.knowledgePoints) {
      _knowledgePointLines.add(trimmed);
      return;
    }
    if (_target == _Target.source) {
      _sourceFound = true;
      final current = _sourceLabel;
      if (current == null || current.isEmpty) {
        _sourceLabel = trimmed;
      } else if (current != trimmed) {
        _sourceLabel = '$current $trimmed';
      }
      return;
    }
    if (_target == _Target.option) {
      if (_optionBuilders.isEmpty) {
        _stemLines.add(trimmed);
      } else {
        _optionBuilders.last.append(trimmed);
      }
    }
  }

  _OptionLine? _parseOptionLine(String line, int index) {
    final hits = _optionLabelHits(line);
    if (hits.isEmpty) return null;
    final expectedCodeUnit = _expectedOptionCodeUnit;
    if (expectedCodeUnit != null) {
      final expectedLetter = String.fromCharCode(expectedCodeUnit);
      final startIndex = hits.indexWhere((hit) => hit.letter == expectedLetter);
      if (startIndex < 0) return null;
      final used = <_LabelHit>[];
      var codeUnit = expectedCodeUnit;
      for (var hitIndex = startIndex; hitIndex < hits.length; hitIndex++) {
        if (hits[hitIndex].letter.codeUnitAt(0) != codeUnit) break;
        used.add(hits[hitIndex]);
        codeUnit += 1;
      }
      final options = <ZujuanPastedOption>[];
      for (var usedIndex = 0; usedIndex < used.length; usedIndex++) {
        final contentEnd = usedIndex + 1 < used.length
            ? used[usedIndex + 1].start
            : line.length;
        options.add(ZujuanPastedOption(
          label: used[usedIndex].letter,
          content:
              line.substring(used[usedIndex].contentStart, contentEnd).trim(),
        ));
      }
      return _OptionLine(
        prefix: line.substring(0, hits[startIndex].start).trim(),
        options: options,
        lastLetter: used.last.letter,
      );
    }
    _LabelHit? firstHit;
    var runLength = 0;
    for (var hitIndex = 0; hitIndex < hits.length; hitIndex++) {
      if (hits[hitIndex].letter != 'A') continue;
      var length = 1;
      for (var nextIndex = hitIndex + 1; nextIndex < hits.length; nextIndex++) {
        if (hits[nextIndex].letter.codeUnitAt(0) ==
            hits[nextIndex - 1].letter.codeUnitAt(0) + 1) {
          length += 1;
        } else {
          break;
        }
      }
      if (length > runLength) {
        runLength = length;
        firstHit = hits[hitIndex];
      }
    }
    if (firstHit == null) return null;
    final prefix = line.substring(0, firstHit.start).trim();
    final firstHitIndex = hits.indexOf(firstHit);
    if (runLength < 2) {
      final nextLetter = _nextOptionLetter(index);
      final contentAfterLabel = line.substring(firstHit.contentStart).trim();
      if (nextLetter != 'B') {
        if (prefix.isNotEmpty) return null;
        if (_startsWithEnumeratedLetter(contentAfterLabel)) return null;
      }
    }
    final options = <ZujuanPastedOption>[];
    var codeUnit = firstHit.letter.codeUnitAt(0);
    var hitIndex = firstHitIndex;
    while (hitIndex < hits.length &&
        hits[hitIndex].letter.codeUnitAt(0) == codeUnit) {
      final hasNext = hitIndex + 1 < hits.length &&
          hits[hitIndex + 1].letter.codeUnitAt(0) == codeUnit + 1;
      final contentEnd = hasNext ? hits[hitIndex + 1].start : line.length;
      options.add(ZujuanPastedOption(
        label: hits[hitIndex].letter,
        content: line.substring(hits[hitIndex].contentStart, contentEnd).trim(),
      ));
      codeUnit += 1;
      hitIndex += 1;
    }
    return _OptionLine(
      prefix: prefix,
      options: options,
      lastLetter: options.last.label,
    );
  }

  String? _nextOptionLetter(int lineIndex) {
    for (var index = lineIndex + 1; index < _lines.length; index++) {
      final line = _lines[index];
      if (line.isEmpty) continue;
      final hits = _optionLabelHits(line);
      if (hits.isEmpty) return null;
      return hits.first.letter;
    }
    return null;
  }

  void _applyOptionLine(_OptionLine line) {
    if (line.prefix.isNotEmpty) {
      _appendContent(line.prefix);
    }
    for (final option in line.options) {
      _optionBuilders.add(_OptionBuilder(option.label, option.content));
    }
    _target = _Target.option;
    _expectedOptionCodeUnit = line.lastLetter.codeUnitAt(0) + 1;
  }

  void _stripTrailingSourceFromFirstStemLine() {
    if (_stemLines.isEmpty) return;
    final first = _stemLines.first;
    final match = _trailingSourcePattern.firstMatch(first);
    if (match == null) return;
    final candidate = match.group(1)!.trim();
    if (!_looksLikeSource(candidate)) return;
    _sourceLabel ??= candidate;
    _sourceFound = true;
    final stripped = first.substring(0, match.start).trim();
    if (stripped.isEmpty) {
      _stemLines.removeAt(0);
    } else {
      _stemLines[0] = stripped;
    }
  }

  String _normalizeStem() {
    final cleaned = <String>[];
    for (final line in _stemLines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        if (cleaned.isNotEmpty && cleaned.last.isNotEmpty) cleaned.add('');
        continue;
      }
      cleaned.add(trimmed);
    }
    while (cleaned.isNotEmpty && cleaned.first.isEmpty) {
      cleaned.removeAt(0);
    }
    while (cleaned.isNotEmpty && cleaned.last.isEmpty) {
      cleaned.removeLast();
    }
    return cleaned.join('\n').trim();
  }

  String? _joinOrNull(List<String> lines) {
    final joined = lines.join('\n').trim();
    return joined.isEmpty ? null : joined;
  }

  List<String> _splitKnowledgePoints(List<String> lines) {
    final points = <String>[];
    for (final line in lines) {
      for (final piece in line.split(_knowledgeSeparatorPattern)) {
        final point = piece.trim();
        if (point.isEmpty) continue;
        if (!points.contains(point)) points.add(point);
      }
    }
    return List<String>.unmodifiable(points);
  }

  ZujuanPastedQuestion _build() {
    _stripTrailingSourceFromFirstStemLine();
    var stem = _normalizeStem();
    final raw = _lines.join('\n').trim();
    final ids = _extractIds(raw);
    final yearRegion = _extractYearRegion(_sourceLabel, raw);
    final options = <ZujuanPastedOption>[];
    for (final builder in _optionBuilders) {
      options.add(ZujuanPastedOption(
          label: builder.label, content: builder.content.trim()));
    }
    final recognized = _ordinal != null ||
        options.isNotEmpty ||
        _metadataFound ||
        _sourceFound ||
        _looksLikeQuestionText(stem);
    if (!recognized) {
      return ZujuanPastedQuestion(
        ordinal: _ordinal,
        stem: raw,
        zujuanQuestionId: ids.questionId,
        zujuanBankId: ids.bankId,
        sourceUrl: ids.sourceUrl,
        warnings: <String>[_warningUnrecognizedStructure],
      );
    }
    final warnings = <String>[];
    if (stem.isEmpty) {
      stem = raw;
      warnings.add(_warningEmptyStem);
    }
    warnings.addAll(ids.warnings);
    return ZujuanPastedQuestion(
      ordinal: _ordinal,
      stem: stem,
      options: options,
      answer: _joinOrNull(_answerLines),
      solution: _joinOrNull(_solutionLines),
      sourceLabel: _sourceLabel,
      year: yearRegion.year,
      region: yearRegion.region,
      knowledgePoints: _splitKnowledgePoints(_knowledgePointLines),
      zujuanQuestionId: ids.questionId,
      zujuanBankId: ids.bankId,
      sourceUrl: ids.sourceUrl,
      warnings: warnings,
    );
  }
}

// ---------------------------------------------------------------------------
// 私有数据类
// ---------------------------------------------------------------------------

enum _Target {
  stem,
  option,
  answer,
  solution,
  knowledgePoints,
  source,
  ignored
}

class _OrdinalCandidate {
  const _OrdinalCandidate(
      {required this.lineIndex, required this.ordinal, required this.strong});

  final int lineIndex;
  final int ordinal;
  final bool strong;
}

class _OrdinalMatch {
  const _OrdinalMatch({required this.ordinal, required this.ordinalEnd});

  final int ordinal;
  final int ordinalEnd;
}

class _LeadingSource {
  const _LeadingSource({required this.source, required this.rest});

  final String source;
  final String rest;
}

class _LabelHit {
  const _LabelHit(
      {required this.letter, required this.start, required this.contentStart});

  final String letter;
  final int start;
  final int contentStart;
}

class _OptionLine {
  const _OptionLine(
      {required this.prefix, required this.options, required this.lastLetter});

  final String prefix;
  final List<ZujuanPastedOption> options;
  final String lastLetter;
}

class _OptionBuilder {
  _OptionBuilder(this.label, String initialContent) {
    if (initialContent.isNotEmpty) _content.write(initialContent);
  }

  final String label;
  final StringBuffer _content = StringBuffer();

  String get content => _content.toString();

  void append(String text) {
    if (text.isEmpty) return;
    if (_content.isNotEmpty) _content.write(' ');
    _content.write(text);
  }
}

class _MetadataMark {
  const _MetadataMark(
      {required this.start, required this.end, required this.label});

  final int start;
  final int end;
  final String label;
}

class _MetadataPiece {
  const _MetadataPiece({required this.label, required this.text});

  final String? label;
  final String text;
}

class _ExtractedIds {
  const _ExtractedIds({
    required this.questionId,
    required this.bankId,
    required this.sourceUrl,
    required this.warnings,
  });

  final String? questionId;
  final String? bankId;
  final String? sourceUrl;
  final List<String> warnings;
}

class _YearRegion {
  const _YearRegion({required this.year, required this.region});

  final int? year;
  final String? region;
}
