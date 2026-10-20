/// 组卷网「改原题链接」输入解析：纯逻辑（不联网、不读 DB、不碰 UI）。
///
/// 用途：题目详情页要让用户改「原题链接」。用户可能粘整条 URL、粘
/// /10q35583902.html 这样的路径、粘 10q35583902.html 文件名，也可能粘别的站
/// 链接。本文件把这段输入解析成「可保存的来源链接 + 两个组卷网 id」；认不出
/// 时返回 null（UI 据此区分「没填」和「填错了」），绝不猜。
///
/// 规则唯一权威：
///  * 绝对 http(s) 链接的规范化（去 fragment、去默认端口、host 小写、拒绝
///    javascript:/data:/file:/mailto:/相对路径）复用
///    domain/services/questions/question_source.dart:89 的 questionSourceFor；
///  * 组卷网题目详情页 /<bankid>q<questionid>.html 的形状见
///    zujuan_link.dart:14-16 与 skill scripts/lib/extract.mjs:156；重建链接一律
///    走 zujuan_link.dart:55 的 zujuanQuestionDetailUrl（缺 id 返回 null，不猜）；
///  * q 路径识别正则与 zujuan_paper_extract.dart:190 的 _questionPattern 同规则
///    （前导边界非字母数字下划线，避免 /abcq123.html 被误认成题号）。
///
/// 口径（只做能证明的变换，不做「看起来更好」的改写）：
///  * 两端空白先 trim；URL 里的中文/空格不 decode、不改写；
///  * 组卷网 id 只从组卷网 host（含子域）的链接里抽；别的站链接只收 sourceUrl；
///  * 纯数字串、只有 bank 没有题号、只有题号没有 bank 的裸文本都不猜：
///    组卷网 id 两位都纯数字，猜错会指到别的题；
///  * 同一输入永远同一结果；任何输入都不抛异常（认不出返回 null）。
library;

import '../questions/question_source.dart';
import 'zujuan_link.dart';

/// 一条解析后的「改原题链接」输入。
///
/// 三个字段互相独立：[sourceUrl] 是规范化后的绝对 http(s) 链接（路径形状但缺
/// bank 时为 null）；[zujuanQuestionId] / [zujuanBankId] 是纯数字串，认不出时
/// 为 null。三者全 null 就是「没填/认不出」。
class ZujuanSourceInput {
  const ZujuanSourceInput({
    this.sourceUrl,
    this.zujuanQuestionId,
    this.zujuanBankId,
  });

  /// 规范化后的绝对 http(s) 链接；没有可用链接时 null。
  final String? sourceUrl;

  /// 组卷网题号（纯数字串）；认不出 null。
  final String? zujuanQuestionId;

  /// 组卷网 bank id（纯数字串）；认不出 null。
  final String? zujuanBankId;

  /// 三个字段是否都为空（等于「没解析到任何可用信息」）。
  bool get isEmpty =>
      sourceUrl == null && zujuanQuestionId == null && zujuanBankId == null;

  /// 给 UI / 日志 / AI 工具结果用的浅序列化；null 也写出（键固定）。
  Map<String, Object?> toJson() => <String, Object?>{
        'source_url': sourceUrl,
        'zujuan_question_id': zujuanQuestionId,
        'zujuan_bank_id': zujuanBankId,
      };

  @override
  bool operator ==(Object other) =>
      other is ZujuanSourceInput &&
      other.sourceUrl == sourceUrl &&
      other.zujuanQuestionId == zujuanQuestionId &&
      other.zujuanBankId == zujuanBankId;

  @override
  int get hashCode => Object.hash(sourceUrl, zujuanQuestionId, zujuanBankId);

  @override
  String toString() => 'ZujuanSourceInput(sourceUrl: $sourceUrl, '
      'zujuanQuestionId: $zujuanQuestionId, zujuanBankId: $zujuanBankId)';
}

/// 解析用户粘贴的「改原题链接」输入；认不出返回 null，永不抛异常。
///
/// 优先级：
///  1. 合法绝对 http(s) 链接 → 规范化后收 sourceUrl；只有 host 命中组卷网
///     （question_source.dart:119-121 的 isZujuan 口径，含 *.zujuan.xkw.com）
///     且 path（不含 query/fragment）命中题目详情页形状时才填两个 id；别的站
///     链接只收 sourceUrl、id 留 null（不猜：别的站的 q123.html 未必是组卷网题）；
///  2. 不以 http 开头的裸路径 / 文件名形状（可带一个前导 /）→ 视为组卷网题链，
///     用 zujuanQuestionDetailUrl 重建 sourceUrl；缺 bank 时 sourceUrl 为 null、
///     只填题号；
///  3. 其余（javascript:/data:/file:/mailto:/ftp:、相对普通路径、纯数字串等）
///     一律 null：认不出就当没填，不猜。
ZujuanSourceInput? parseZujuanSourceInput(String raw) {
  try {
    final text = raw.trim();
    if (text.isEmpty) return null;
    final ref = questionSourceFor(sourceUrl: text);
    if (ref != null) {
      if (!ref.isZujuan) return ZujuanSourceInput(sourceUrl: ref.url);
      final match = _questionInPathPattern.firstMatch(_pathOfUrl(ref.url));
      if (match == null) return ZujuanSourceInput(sourceUrl: ref.url);
      return ZujuanSourceInput(
        sourceUrl: ref.url,
        zujuanBankId: match.group(1),
        zujuanQuestionId: match.group(2),
      );
    }
    final bare = _barePathPattern.firstMatch(text);
    if (bare == null) return null;
    final bankId = bare.group(1);
    final questionId = bare.group(2);
    return ZujuanSourceInput(
      sourceUrl: zujuanQuestionDetailUrl(
        bankId: bankId,
        questionId: questionId,
      ),
      zujuanQuestionId: questionId,
      zujuanBankId: bankId,
    );
  } on Object {
    // 契约要求永不抛：解析器只做字符串判断，真出现意外输入按「认不出」处理。
    return null;
  }
}

/// 从规范化后的绝对 URL 里取 path 原文（不含 query/fragment，不 decode）。
///
/// 不直接用 Uri.path：那会做百分号解码，违反「不 decode、不改写」口径；
/// 这里只做分隔符扫描（与 question_source.dart:135-147 同一套扫描方式）。
String _pathOfUrl(String url) {
  final separator = url.indexOf('://');
  if (separator < 0) return '';
  final authorityStart = separator + 3;
  var first = url.length;
  for (var i = authorityStart; i < url.length; i++) {
    final unit = url.codeUnitAt(i);
    if (unit == _slashUnit || unit == _questionMarkUnit || unit == _hashUnit) {
      first = i;
      break;
    }
  }
  if (first >= url.length || url.codeUnitAt(first) != _slashUnit) return '';
  var end = url.length;
  for (var i = first; i < url.length; i++) {
    final unit = url.codeUnitAt(i);
    if (unit == _questionMarkUnit || unit == _hashUnit) {
      end = i;
      break;
    }
  }
  return url.substring(first, end);
}

const int _slashUnit = 0x2F;
const int _questionMarkUnit = 0x3F;
const int _hashUnit = 0x23;

/// path 里的题目详情页形状：可选的 bank 数字段 + q + 题号 + .html 后缀。
///
/// 与 zujuan_paper_extract.dart:190 的 _questionPattern 同规则：前导边界不能是
/// 字母数字下划线（防 /abcq123.html），大小写不敏感，.html 后缀防更长路径。
final RegExp _questionInPathPattern = RegExp(
  r'(?:^|[^0-9A-Za-z_])(?:([0-9]{1,6}))?q([0-9]{1,12})\.html',
  caseSensitive: false,
);

/// 裸路径 / 文件名的完整形状：可带一个前导 /，bank 段可缺。
///
/// 用整串锚定（^...$）而不是搜索：foo/10q123.html 这种带目录的普通路径、
/// 前后还有别的文字的输入都不算「用户粘了题链」，避免把正文片段当链接。
final RegExp _barePathPattern = RegExp(
  r'^/?([0-9]{1,6})?q([0-9]{1,12})\.html$',
  caseSensitive: false,
);
