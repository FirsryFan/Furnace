/// 组卷网「试卷详情页」粘贴文本抽取：纯逻辑（不联网、不解析答案、不碰 UI）。
///
/// 用途：用户把组卷网试卷详情页整页内容/HTML 粘进来，一次拿到这套卷子的题目
/// 清单（[ZujuanPaperExtract.questionIds]），再用本地库按题号批量读取。
///
/// 识别口径（只认站点真实 URL 形状，不凭标题猜）：
///  * 试卷标识：`/<bankdigits>p<paperdigits>.html`（例 /10p3076310.html，
///    形状来自 zujuan_link.dart:17-21 的 library doc / scripts/paper.mjs:10）。
///    只有 `p<paperdigits>.html` 时 paperId 有值、bankId 为 null（不猜学科）。
///  * 题目标识：`q<digits>.html`，可带 bank 前缀 `/<bankdigits>q<id>.html`
///    （zujuan_link.dart:14-16 / scripts/lib/extract.mjs:156）。
///    非数字的「假 bank」（如 /abcq123.html）不算题号，避免把脏文本当链接。
///  * 链接生成一律走 zujuan_link.dart:55 的 zujuanQuestionDetailUrl，不手拼：
///    该 helper 缺 bankId/非纯数字会返回 null，本文件对拿不到 bank 的题号跳过
///    对应链接（questionLinks 是 questionIds 的同序子集）并给 warning。
///  * title 只认同页 HTML 的 <title> 内文本，其次 <h1>；都没有就是 null，
///    不从文件名/正文猜「某某试卷」。
///
/// 已知边界：
///  * 题目顺序 = 页面文本里 q 链接出现顺序（不是卷面印刷序号）；
///  * 只去重、不重排；最多保留 [kZujuanMaxExtractedQuestions] 道，超出置
///    [ZujuanPaperExtract.truncated] 并给 warning，不静默丢；
///  * 不校验域名（粘贴内容可能来自缓存/其它站点，但只提取 q/p 形状的数字标
///    识）；不做网络请求、不解析答案（答案要登录，属另一路径）；
///  * 同一输入永远同一结果；任何输入都不抛异常，空输入返回空结果。
library;

import 'zujuan_link.dart';

/// 单次抽取最多收录的题目数（超出部分不静默丢，truncated=true + warning）。
const int kZujuanMaxExtractedQuestions = 200;

/// 从粘贴文本里抽出的整卷清单。
///
/// [questionLinks] 与 [questionIds] 同序：某个题号生成不出链接时跳过，
/// 因此 [questionLinks] 可能比 [questionIds] 短（见 [warnings] 的原因说明）。
class ZujuanPaperExtract {
  const ZujuanPaperExtract({
    this.paperId,
    this.bankId,
    this.title,
    this.questionIds = const [],
    this.questionLinks = const [],
    this.warnings = const [],
    this.truncated = false,
  });

  /// 试卷数字 id（例 /10p3076310.html → 3076310）；没找到为 null。
  final String? paperId;

  /// 试卷所属 bank 数字 id（例 → 10）；只给了 p 链接时为 null。
  final String? bankId;

  /// <title> 或 <h1> 的纯文本；都没有为 null。
  final String? title;

  /// 按出现顺序去重后的题号（纯数字 int），最多 [kZujuanMaxExtractedQuestions] 个。
  final List<int> questionIds;

  /// 与 [questionIds] 同序的题目详情页链接（可能更短，见类 doc）。
  final List<String> questionLinks;

  /// 中文提示（没有找到题目链接 / 找到 X 个题目链接 / 重复题号已去重 /
  /// 超过 200 道只取前 200 道 / 缺少 bankId 等）。顺序稳定。
  final List<String> warnings;

  /// 题号超过上限被截断时为 true。
  final bool truncated;

  /// 是否什么也没抽到（无试卷编号、无标题、无题号）。
  bool get isEmpty => paperId == null && title == null && questionIds.isEmpty;

  /// 收录的题目数。
  int get questionCount => questionIds.length;

  /// 给 UI / 工具结果 / 日志用的浅序列化。
  Map<String, Object?> toJson() => <String, Object?>{
        'paper_id': paperId,
        'bank_id': bankId,
        'title': title,
        'question_ids': questionIds,
        'question_links': questionLinks,
        'warnings': warnings,
        'truncated': truncated,
      };

  @override
  bool operator ==(Object other) =>
      other is ZujuanPaperExtract &&
      other.paperId == paperId &&
      other.bankId == bankId &&
      other.title == title &&
      _listEquals(other.questionIds, questionIds) &&
      _listEquals(other.questionLinks, questionLinks) &&
      _listEquals(other.warnings, warnings) &&
      other.truncated == truncated;

  @override
  int get hashCode => Object.hash(
        paperId,
        bankId,
        title,
        Object.hashAll(questionIds),
        Object.hashAll(questionLinks),
        Object.hashAll(warnings),
        truncated,
      );

  @override
  String toString() => 'ZujuanPaperExtract(paperId: $paperId, bankId: $bankId, '
      'title: $title, questionIds: $questionIds, '
      'questionLinks: $questionLinks, warnings: $warnings, '
      'truncated: $truncated)';
}

/// 从任意粘贴文本（HTML 或纯文本）抽取整卷清单；永不抛异常。
ZujuanPaperExtract parseZujuanPaperText(String raw) {
  final paperMatch = _paperPattern.firstMatch(raw);
  final paperId = paperMatch?.group(2);
  final bankId = paperMatch?.group(1);
  final title = _extractTitle(raw);

  final questionIds = <int>[];
  final bankByQuestionId = <int, String?>{};
  final seen = <int>{};
  var duplicateFound = false;
  var truncated = false;
  for (final match in _questionPattern.allMatches(raw)) {
    final id = int.tryParse(match.group(2)!);
    if (id == null) continue; // 正则已保证数字；防御性
    if (!seen.add(id)) {
      duplicateFound = true;
      continue;
    }
    if (questionIds.length >= kZujuanMaxExtractedQuestions) {
      truncated = true;
      continue;
    }
    questionIds.add(id);
    bankByQuestionId[id] = match.group(1);
  }

  final questionLinks = <String>[];
  for (final id in questionIds) {
    final questionBank = bankByQuestionId[id] ?? bankId;
    final link = zujuanQuestionDetailUrl(
      bankId: questionBank,
      questionId: '$id',
    );
    if (link != null) questionLinks.add(link);
  }

  final warnings = <String>[];
  if (paperId == null) {
    warnings.add('没有找到试卷编号（形如 /10p3076310.html）');
  }
  if (questionIds.isEmpty) {
    warnings.add('没有找到题目链接');
  } else {
    if (duplicateFound) warnings.add('重复题号已去重');
    if (truncated) warnings.add('超过 200 道，只取前 200 道');
    final skipped = questionIds.length - questionLinks.length;
    if (skipped > 0) {
      warnings.add('有 $skipped 个题号缺少 bankId，未生成链接');
    }
    warnings.add('找到 ${questionIds.length} 个题目链接');
  }

  return ZujuanPaperExtract(
    paperId: paperId,
    bankId: bankId,
    title: title,
    questionIds: List<int>.unmodifiable(questionIds),
    questionLinks: List<String>.unmodifiable(questionLinks),
    warnings: List<String>.unmodifiable(warnings),
    truncated: truncated,
  );
}

/// `/<bankdigits>p<paperdigits>.html`；bank 段可缺。
///
/// 前导边界非字母数字下划线，避免把 `x10p3076310.html` 里的片段当试卷编号；
/// 后缀 `\.html` 保证不会把更长路径（如 `.htmlx`）误认。
final RegExp _paperPattern = RegExp(
  r'(?:^|[^0-9A-Za-z_])(?:([0-9]{1,6}))?p([0-9]{1,12})\.html',
  caseSensitive: false,
);

/// `/<bankdigits>q<questiondigits>.html`；bank 段可缺。
final RegExp _questionPattern = RegExp(
  r'(?:^|[^0-9A-Za-z_])(?:([0-9]{1,6}))?q([0-9]{1,12})\.html',
  caseSensitive: false,
);

/// 取 <title> 内文本，其次 <h1>；都空/没有返回 null。
String? _extractTitle(String raw) {
  for (final pattern in <RegExp>[_titlePattern, _h1Pattern]) {
    for (final match in pattern.allMatches(raw)) {
      final text = _cleanElementText(match.group(1)!);
      if (text != null) return text;
    }
  }
  return null;
}

final RegExp _titlePattern = RegExp(
  r'<title\b[^>]*>([\s\S]*?)</title\s*>',
  caseSensitive: false,
);

final RegExp _h1Pattern = RegExp(
  r'<h1\b[^>]*>([\s\S]*?)</h1\s*>',
  caseSensitive: false,
);

/// 元素内文本清洗：去内嵌标签、解常见 HTML 实体、折叠空白；全空返回 null。
String? _cleanElementText(String inner) {
  var text = inner.replaceAll(_tagPattern, ' ');
  text = _decodeBasicEntities(text);
  text = text.replaceAll(_whitespacePattern, ' ').trim();
  return text.isEmpty ? null : text;
}

final RegExp _tagPattern = RegExp(r'<[^>]*>');
final RegExp _whitespacePattern = RegExp(r'[\s\u3000]+');
final RegExp _numericDecimalEntityPattern = RegExp(r'&#([0-9]{1,7});');
final RegExp _numericHexEntityPattern = RegExp(r'&#[xX]([0-9a-fA-F]{1,6});');

/// 只解常见实体（标题里实际会遇到的几种 + 数字实体），其它原样保留。
String _decodeBasicEntities(String text) {
  var decoded = text
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&apos;', "'");
  decoded = decoded.replaceAllMapped(_numericDecimalEntityPattern, (match) {
    return _codePointToString(int.tryParse(match.group(1)!));
  });
  decoded = decoded.replaceAllMapped(_numericHexEntityPattern, (match) {
    return _codePointToString(int.tryParse(match.group(1)!, radix: 16));
  });
  return decoded;
}

String _codePointToString(int? codePoint) {
  if (codePoint == null || codePoint <= 0 || codePoint > 0x10FFFF) {
    return '';
  }
  return String.fromCharCode(codePoint);
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
