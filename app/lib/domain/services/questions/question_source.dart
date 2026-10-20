/// 题目来源链接解析：纯逻辑（不联网、不读 DB、不碰 UI）。
///
/// 为什么要这一层：schema v26 的 questions 表已经有 sourceUrl / zujuanQuestionId /
/// zujuanBankId 三个来源字段（app/lib/data/database/tables.dart:1132-1151），但界面
/// 「点回去核对原题」不能直接把库里的字符串丢给打开器：
///  * 只有绝对 http(s) 链接可信；javascript: / data: / file: / mailto: / 相对路径
///    一律拒绝（库里的值可能是历史脏数据或手工粘贴），本文件返回 null 而不是猜。
///  * 组卷网题目详情页链接可以只用两个数字 id 重建，规则唯一权威在
///    app/lib/domain/services/zujuan/zujuan_link.dart:55 的 zujuanQuestionDetailUrl
///    （缺 id / 非纯数字返回 null），本文件不重复实现、也不在这里先猜数字。
///
/// 规范化口径（只做能证明的变换，不做「看起来更好」的改写）：
///  * scheme 与 host 小写；
///  * 去掉 fragment（# 之后的部分：站点锚点对「回到原题」没有意义）；
///  * 去掉默认端口（http:80、https:443）；非默认端口保留；
///  * path / query 逐字节保留（不 decode、不重排参数），空 path 不补「/」；
///  * 不升级/降级 scheme（http 仍是 http），不补 www、不补尾斜杠。
///
/// host 字段是规范化后的 host（小写、无端口、无 userInfo），组卷网判定为
/// zujuan.xkw.com 与其子域（*.zujuan.xkw.com）；其它合法 http(s) 来源照收、
/// isZujuan=false（以后可能有别的来源站）。
///
/// 确定性：同一输入永远同一结果；不抛异常（非法输入按「没有可用链接」处理）。
library;

import '../zujuan/zujuan_link.dart';

/// 组卷网主站 host（与 zujuan_link.dart 的 zujuanBaseUrl 一致，见该文件 :35）。
const String _zujuanHost = 'zujuan.xkw.com';

/// 一条可用于「点回去核对原题」的来源链接。
///
/// [fromStoredUrl] 区分链接是库存的 sourceUrl（true）还是用题目 id 重建的
/// （false）；[isZujuan] 表示 host 是否命中组卷网域名。
class QuestionSourceRef {
  const QuestionSourceRef({
    required this.url,
    required this.host,
    required this.fromStoredUrl,
    required this.isZujuan,
  });

  /// 规范化后的绝对 http(s) 链接。
  final String url;

  /// 规范化后的 host（小写、不含端口与 userInfo）。
  final String host;

  /// true = 来自库存 sourceUrl；false = 用 zujuanQuestionId / zujuanBankId 重建。
  final bool fromStoredUrl;

  /// host 是否命中组卷网（zujuan.xkw.com 或其子域）。
  final bool isZujuan;

  /// 给 UI / 日志用的浅序列化。
  Map<String, Object?> toJson() => <String, Object?>{
        'url': url,
        'host': host,
        'from_stored_url': fromStoredUrl,
        'is_zujuan': isZujuan,
      };

  @override
  bool operator ==(Object other) =>
      other is QuestionSourceRef &&
      other.url == url &&
      other.host == host &&
      other.fromStoredUrl == fromStoredUrl &&
      other.isZujuan == isZujuan;

  @override
  int get hashCode => Object.hash(url, host, fromStoredUrl, isZujuan);

  @override
  String toString() => 'QuestionSourceRef(url: $url, host: $host, '
      'fromStoredUrl: $fromStoredUrl, isZujuan: $isZujuan)';
}

/// 解析一条可用于「点回去核对原题」的来源链接；没有可信链接时返回 null。
///
/// 优先级：
///  1. [sourceUrl] 是合法绝对 http(s) 链接 → 规范化后采用（fromStoredUrl=true）；
///  2. 否则用 [zujuanBankId] + [zujuanQuestionId] 重建组卷网详情页
///     （fromStoredUrl=false、isZujuan=true）；
///  3. 都没有 → null（绝不编 URL）。
///
/// 非法/不可信的 [sourceUrl]（javascript:、data:、file:、mailto:、相对路径、
/// 解析失败、host 为空、非 http(s) scheme）按「没有可用链接」处理，不抛异常。
QuestionSourceRef? questionSourceFor({
  String? sourceUrl,
  String? zujuanQuestionId,
  String? zujuanBankId,
}) {
  final stored = _normalizeStoredUrl(sourceUrl);
  if (stored != null) {
    return QuestionSourceRef(
      url: stored.url,
      host: stored.host,
      fromStoredUrl: true,
      isZujuan: _isZujuanHost(stored.host),
    );
  }
  final rebuilt = zujuanQuestionDetailUrl(
    bankId: zujuanBankId,
    questionId: zujuanQuestionId,
  );
  if (rebuilt != null) {
    return QuestionSourceRef(
      url: rebuilt,
      host: _zujuanHost,
      fromStoredUrl: false,
      isZujuan: true,
    );
  }
  return null;
}

/// host 是否是组卷网主站或子域（大小写不敏感，输入应为小写 host）。
bool _isZujuanHost(String host) {
  return host == _zujuanHost || host.endsWith('.$_zujuanHost');
}

/// 规范化库存 sourceUrl；不可信/不可解析时返回 null。
({String url, String host})? _normalizeStoredUrl(String? raw) {
  final text = raw?.trim() ?? '';
  if (text.isEmpty) return null;
  final parsed = Uri.tryParse(text);
  if (parsed == null) return null;
  final scheme = parsed.scheme.toLowerCase();
  if (scheme != 'http' && scheme != 'https') return null;
  final host = parsed.host.toLowerCase();
  if (host.isEmpty) return null;
  // 只重建 scheme + authority（规范化）与原串的 path/query（逐字节保留），
  // 不整体 toString()：parsed.toString() 会重排/重编码，不能保证 path 原样。
  final separator = text.indexOf('://');
  if (separator < 0) return null;
  final authorityStart = separator + 3;
  var authorityEnd = text.length;
  for (var i = authorityStart; i < text.length; i++) {
    final unit = text.codeUnitAt(i);
    if (unit == 0x2F || unit == 0x3F || unit == 0x23) {
      // '/'、'?'、'#'
      authorityEnd = i;
      break;
    }
  }
  var tail = text.substring(authorityEnd);
  final fragmentIndex = tail.indexOf('#');
  if (fragmentIndex >= 0) tail = tail.substring(0, fragmentIndex);
  final defaultPort = scheme == 'http' ? 80 : 443;
  final keepPort = parsed.hasPort && parsed.port != defaultPort;
  final hostPart = host.contains(':') ? '[$host]' : host; // IPv6 字面量
  final userInfo = parsed.userInfo;
  final authority = userInfo.isEmpty ? hostPart : '$userInfo@$hostPart';
  final portPart = keepPort ? ':${parsed.port}' : '';
  return (url: '$scheme://$authority$portPart$tail', host: host);
}
