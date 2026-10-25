/// 组卷网（zujuan.xkw.com）链接与检索词候选：纯逻辑（不联网、不读 DB、不碰 UI）。
///
/// 规则唯一权威：D:\dsh-data\skills\zujuan-source-standards。
/// 本文件所有 URL 形状/编码都来自该 skill 的实测与源码，不凭记忆猜：
///
///  * **文本搜题**（唯一可用的文本入口，references/url-grammar.md:19、208-217）：
///    https://zujuan.xkw.com/quessearch?keyword=<base64>&intent=question&b=0&urlSource=0
///    - keyword = UTF-8 的**标准 base64**（不是 URL-safe；含 + / =），再整体百分号编码。
///      源码 scripts/bridge.mjs:148-151：
///      const b64 = Buffer.from(String(query),'utf8').toString('base64');
///      ...?keyword=${encodeURIComponent(b64)}&intent=question&b=${offset}&urlSource=0
///      ⇒ + → %2B、/ → %2F、= → %3D（先 base64 再 urlencode，顺序不能反）。
///    - intent 必须是 question；intent=book 会取回别的题（SKILL.md:256）。
///  * **题目详情页** /<bankid>q<questionid>.html（url-grammar.md:16）：
///    skill 自己的拼法见 scripts/lib/extract.mjs:156：
///    (detailRoot && bankid && questionid ? `/${bankid}q${questionid}.html` : null)。
///  * **试卷详情页** /<bankid>p<paperid>.html（url-grammar.md:15；
///    实例 /10p3076310.html 见 SKILL.md:140、scripts/paper.mjs:10）。
///    skill 里试卷链接是从卡片 a.ques-src 的 href **原样取得**（paper.mjs:10），
///    没有默认 bankid ⇒ 本文件缺 bankId 也返回 null，不猜：猜错会拼出别的学科，
///    而站点按 bankId cookie 过滤、错学科静默 0 条（SKILL.md:196-211 的实测事故）。
///
/// ⚠️ 学科限制：搜索与详情页都按当前学科（bankId cookie）过滤。链接只负责把
/// 用户带到页面，**学科要用户自己确认**（同上事故：连搜 19 条检索式全部 0 结果，
/// 其实是学科不对）。UI 接线时应提示用户先切到对应学科。
///
/// 检索词候选抽取规则见 zujuan_keywords.dart：按学科带取长度（理科 15–30 /
/// 文科 20–40 且短于题干，口径来自用户 2026-10-25 反馈），与标准侧
/// scripts/keywords.mjs 的旧 4–28 口径已分歧、待标准侧同步。
library;

import 'dart:convert';

import 'zujuan_keywords.dart';

/// 组卷网主站基址（url-grammar.md:9）。
const String zujuanBaseUrl = 'https://zujuan.xkw.com';

/// 把 [keyword] 拼成组卷网文本搜题链接（规则见 library doc）。
///
/// 编码是「UTF-8 → 标准 base64 → 百分号编码」，**不是** URL-safe base64，
/// 也不是直接 urlencode 原文（bridge.mjs:148-151：直接 urlencode 会搜不到）。
String zujuanSearchUrl(String keyword) {
  final encoded = base64Encode(utf8.encode(keyword));
  return '$zujuanBaseUrl/quessearch'
      '?keyword=${Uri.encodeComponent(encoded)}'
      '&intent=question'
      '&b=0'
      '&urlSource=0';
}

/// 题目详情页绝对链接（https://zujuan.xkw.com/<bankid>q<questionid>.html）。
///
/// 缺 [bankId] 或 [questionId]（null/空白/非纯数字）时返回 null，不猜：
/// skill 侧同样要求 id 存在才拼（scripts/lib/extract.mjs:156）。站点实测 id 为
/// 纯数字（如 10q35583902、11q35414092）；两端空白会先 trim。
String? zujuanQuestionDetailUrl({String? bankId, String? questionId}) {
  final bank = _normalizeNumericId(bankId);
  final question = _normalizeNumericId(questionId);
  if (bank == null || question == null) return null;
  return '$zujuanBaseUrl/${bank}q$question.html';
}

/// 试卷详情页绝对链接（https://zujuan.xkw.com/<bankid>p<paperid>.html）。
///
/// 缺 [paperId]（null/空白/非纯数字）返回 null；**缺 [bankId] 也返回 null**——
/// skill 里试卷链接是从卡片 href 原样取得的（scripts/paper.mjs:10），没有默认
/// bankid，这里不猜（错学科会静默 0 条，见 library doc）。
String? zujuanPaperDetailUrl({String? paperId, String? bankId}) {
  final paper = _normalizeNumericId(paperId);
  final bank = _normalizeNumericId(bankId);
  if (paper == null || bank == null) return null;
  return '$zujuanBaseUrl/${bank}p$paper.html';
}

final RegExp _numericIdPattern = RegExp(r'^[0-9]+$');

String? _normalizeNumericId(String? raw) {
  final trimmed = raw?.trim() ?? '';
  if (trimmed.isEmpty || !_numericIdPattern.hasMatch(trimmed)) return null;
  return trimmed;
}

/// 一条「检索词 + 可直接打开的文本搜题链接」候选。
class ZujuanSearchCandidate {
  const ZujuanSearchCandidate({required this.keyword, required this.url});

  /// 从题干抽出的连续文本片段（站点文本层真实存在的串）。
  final String keyword;

  /// 由 [zujuanSearchUrl] 生成的绝对链接。
  final String url;

  /// 给 UI / 日志用的浅序列化。
  Map<String, String> toJson() => <String, String>{
        'keyword': keyword,
        'url': url,
      };

  @override
  bool operator ==(Object other) =>
      other is ZujuanSearchCandidate &&
      other.keyword == keyword &&
      other.url == url;

  @override
  int get hashCode => Object.hash(keyword, url);

  @override
  String toString() => 'ZujuanSearchCandidate(keyword: $keyword, url: $url)';
}

/// 从题干抽 1..[maxCandidates] 条候选检索词。
///
/// [band] 决定目标长度带（理科 15–30 / 文科 20–40 且短于题干）；默认理科，
/// 与旧行为兼容。规则见 zujuan_keywords.dart 的 library doc 与已知局限。
List<String> zujuanKeywordCandidates(
  String stem, {
  int maxCandidates = 8,
  ZujuanSubjectBand band = ZujuanSubjectBand.science,
}) {
  return extractZujuanKeywords(
    stem,
    maxCandidates: maxCandidates,
    band: band,
  );
}

/// 从题干抽候选检索词并逐条带上文本搜题链接（UI 复制/打开用）。
///
/// [band] 透传给 [zujuanKeywordCandidates]：调用方应按题目学科传入
/// [zujuanSubjectBandFor] 的结果。
List<ZujuanSearchCandidate> zujuanSearchCandidates(
  String stem, {
  int maxCandidates = 8,
  ZujuanSubjectBand band = ZujuanSubjectBand.science,
}) {
  return zujuanKeywordCandidates(
    stem,
    maxCandidates: maxCandidates,
    band: band,
  )
      .map(
        (keyword) => ZujuanSearchCandidate(
          keyword: keyword,
          url: zujuanSearchUrl(keyword),
        ),
      )
      .toList(growable: false);
}
