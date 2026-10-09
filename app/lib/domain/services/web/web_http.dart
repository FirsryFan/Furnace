/// The one HTTP call the `fetch_page` tool makes, with every rule that makes it
/// safe to expose to a model written down here rather than at the call site.
///
/// What this file deliberately does **not** do:
///
///  * it never sends credentials - no cookies, no `Authorization`, no
///    `HttpClient` credentials or proxy credentials. The point is to read a
///    public page, not to act as a logged-in browser: a page the user is signed
///    into must not be fetched as them, so the request carries an identifying
///    User-Agent and nothing else;
///  * it does not follow redirects automatically. `HttpClient` does that
///    silently; following them here, one hop at a time, is what lets the caller
///    see and bound the chain and what makes "redirected to an unexpected host"
///    reportable instead of invisible;
///  * it does not decide what a page *means*. It returns bytes, the decoder
///    decision and the metadata; extraction lives in `html_document.dart` and
///    presentation in `web_tools.dart`.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data' show BytesBuilder;

/// How many redirects one fetch may follow before giving up.
const int maxRedirects = 5;

/// How long one request may take, in total, before it is abandoned.
const Duration requestTimeout = Duration(seconds: 15);

/// The hard ceiling on a response body: 2 MiB.
///
/// A page the user asked about is a document; anything past this is not what
/// they want to read and is not worth the memory. Hitting the cap is reported,
/// never silently trimmed.
const int maxBodyBytes = 2 * 1024 * 1024;

/// Identifies this app to servers, instead of impersonating a browser.
///
/// Kept in step with `pubspec.yaml`'s version by hand; the point of the header
/// is honesty about who is calling, not exact version matching.
const String userAgent = 'Furnace/0.3.0 (+local assistant)';

/// Only these schemes may be fetched. Anything else is refused before a socket
/// is opened.
const Set<String> allowedSchemes = {'http', 'https'};

/// Decides whether a host may be contacted.
///
/// Returns null when the host is allowed, or a human-readable refusal otherwise.
/// It is a parameter of [WebFetcher] - and of the tool - so tests can point the
/// fetcher at an in-process `127.0.0.1` server while the production default
/// ([refuseNonPublicHost]) still refuses loopback. A bypass flag on the guard
/// itself would have made the guard meaningless in production.
typedef HostPolicy = String? Function(String host);

/// Refuses anything that is not a clearly public internet host.
///
/// This is the one genuinely dangerous thing a naive fetcher adds: without it
/// the model can be talked into probing the user's own machine and LAN
/// (`http://127.0.0.1:8080/admin`, `http://192.168.1.1/`, a cloud metadata
/// address) and the response would land in the conversation and in the ledger as
/// if it were a web page. The message names the host so a refusal cannot be
/// mistaken for a network failure.
String? refuseNonPublicHost(String host) {
  final value = host.trim().toLowerCase();
  final bare = value.startsWith('[') && value.endsWith(']')
      ? value.substring(1, value.length - 1)
      : value;
  if (bare.isEmpty) {
    return '地址里没有主机名';
  }
  if (bare == 'localhost' || bare.endsWith('.localhost')) {
    return '拒绝访问本机地址 `$host`：只允许公网 http/https 地址';
  }
  if (bare == '0.0.0.0' || bare == '::' || bare == '::1') {
    return '拒绝访问本机/未指定地址 `$host`：只允许公网 http/https 地址';
  }

  final v4 = _parseIpv4(bare);
  if (v4 != null) {
    final block = _privateIpv4Block(v4);
    if (block != null) {
      return '拒绝访问内网地址 `$host`（$block）：只允许公网 http/https 地址';
    }
    return null;
  }

  if (bare.contains(':')) {
    final bytes = _parseIpv6(bare);
    if (bytes != null) {
      final block = _privateIpv6Block(bytes);
      if (block != null) {
        return '拒绝访问内网地址 `$host`（$block）：只允许公网 http/https 地址';
      }
      return null;
    }
    // A colon in a host that is not a literal address: not something we can
    // check, so it is refused rather than guessed at.
    return '无法识别的主机名 `$host`：只允许公网 http/https 地址';
  }

  // A DNS name. Resolving it here would mean a second, unguarded connection and
  // a DNS-rebinding hole; the scheme/host checks above plus the ledger entry are
  // the guard for names, and that limit is stated rather than hidden.
  return null;
}

/// A redirect chain longer than [maxRedirects], or a redirect without a
/// `Location`.
class RedirectLimitException implements Exception {
  RedirectLimitException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// A host refused by the [HostPolicy] in force.
class RefusedHostException implements Exception {
  RefusedHostException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// One successful fetch: the bytes, plus everything the model should be told
/// about where they came from.
class WebFetchResult {
  const WebFetchResult({
    required this.bytes,
    required this.finalUrl,
    required this.contentType,
    required this.declaredCharset,
    required this.statusCode,
    required this.redirects,
    required this.bodyTruncated,
  });

  final List<int> bytes;

  /// The URL actually read, after redirects. Reported so a redirect to an
  /// unexpected host is visible in the transcript and the ledger.
  final String finalUrl;

  /// The `content-type` header, or '' when the server sent none.
  final String contentType;

  /// The `charset` parameter of [contentType] as declared, or null.
  final String? declaredCharset;

  final int statusCode;

  /// The redirect hops actually followed, in order.
  final List<String> redirects;

  /// True when the body hit [maxBodyBytes] and the tail was discarded.
  final bool bodyTruncated;
}

/// The charset decision for a response body, made once and reported.
///
/// Dart's `utf8`/`latin1` codecs are the only ones bundled, so a page declaring
/// `gb2312`/`gbk`/`shift_jis`/`big5` **cannot be transcoded** without a package
/// the project does not have. The rule is then: decode as latin1, which is
/// lossless byte-for-byte, and say so. Producing mojibake silently would be
/// worse than producing bytes the model can see are not text.
class CharsetDecision {
  const CharsetDecision({
    required this.encoding,
    required this.text,
    required this.declared,
    this.note,
  });

  /// The codec name actually used: `utf-8` or `latin1`.
  final String encoding;

  /// The decoded body.
  final String text;

  /// The charset the server declared, or null.
  final String? declared;

  /// Why this decoder was chosen, when that needs saying.
  final String? note;
}

/// Picks a decoder for [bytes] from the declared charset.
///
/// Recognised: everything that is really UTF-8 (`utf-8`, `utf8`, no declaration
/// at all) and everything Latin-1 (`latin1`, `iso-8859-1`, `latin-1`,
/// `windows-1252`, which is not identical to Latin-1 but is the same for the
/// bytes a page usually contains). Anything else falls back to latin1 with the
/// [`notTranscodedNote`] attached.
CharsetDecision decodeBody(List<int> bytes, String? declaredCharset) {
  final declared = declaredCharset?.trim().toLowerCase();
  if (declared == null || declared.isEmpty) {
    return CharsetDecision(
      encoding: 'utf-8',
      text: _decodeUtf8(bytes),
      declared: null,
    );
  }
  if (_utf8Names.contains(declared)) {
    return CharsetDecision(
      encoding: 'utf-8',
      text: _decodeUtf8(bytes),
      declared: declared,
    );
  }
  if (_latin1Names.contains(declared)) {
    return CharsetDecision(
      encoding: 'latin1',
      text: latin1.decode(bytes, allowInvalid: true),
      declared: declared,
    );
  }
  return CharsetDecision(
    encoding: 'latin1',
    text: latin1.decode(bytes, allowInvalid: true),
    declared: declared,
    note: notTranscodedNote(declared),
  );
}

/// The note attached when a declared charset cannot be transcoded.
String notTranscodedNote(String declared) =>
    '页面声明字符集为 `$declared`，Dart 没有内置对应的解码器，'
    '因此按 latin1 逐字节解码、**没有做转码**：'
    '非 ASCII 文本看起来会是乱码，这是如实报告而不是乱猜。';

/// Decodes UTF-8, allowing malformed bytes instead of throwing on a broken page.
String _decodeUtf8(List<int> bytes) =>
    utf8.decode(bytes, allowMalformed: true);

const Set<String> _utf8Names = {'utf-8', 'utf8', 'unicode-1-1-utf-8'};
const Set<String> _latin1Names = {
  'latin1',
  'latin-1',
  'iso-8859-1',
  'iso8859-1',
  'l1',
  'windows-1252',
  'cp1252',
};

/// Fetches one page, following redirects by hand.
///
/// The [client] is injected so a test can point at an in-process server (and so
/// the tool can be given a client with a fixed timeout); [hostPolicy] is
/// injected for the same reason - see [HostPolicy].
class WebFetcher {
  WebFetcher({
    HttpClient? client,
    this.timeout = requestTimeout,
    this.maxRedirectHops = maxRedirects,
    this.maxBytes = maxBodyBytes,
    this.hostPolicy = refuseNonPublicHost,
  }) : _client = client ?? _newClient();

  /// A client that follows no redirects and keeps no cookies of its own.
  static HttpClient _newClient() {
    final client = HttpClient();
    client.autoUncompress = true;
    return client;
  }

  final HttpClient _client;
  final Duration timeout;
  final int maxRedirectHops;

  /// The body cap in force for this fetcher. A parameter so a test can prove the
  /// truncation path with a small fixture instead of generating 2 MiB.
  final int maxBytes;

  final HostPolicy hostPolicy;

  /// Retrieves [url], or throws.
  ///
  /// Throws [RefusedHostException] for a refused host,
  /// [RedirectLimitException] for a chain longer than [maxRedirectHops], and
  /// lets socket/TLS/timeout exceptions through for the caller to turn into a
  /// tool error. The caller is `FetchPageTool.run`, which converts every one of
  /// them into a `ToolResult` - the model never sees an unhandled exception.
  Future<WebFetchResult> fetch(Uri url) async {
    final redirects = <String>[];
    var current = url;

    for (var hop = 0; hop <= maxRedirectHops; hop++) {
      final refused = hostPolicy(current.host);
      if (refused != null) {
        throw RefusedHostException(refused);
      }

      final response = await _open(current);
      final status = response.statusCode;

      if (_isRedirect(status)) {
        final location = response.headers.value(HttpHeaders.locationHeader);
        await _drain(response);
        if (location == null || location.trim().isEmpty) {
          throw RedirectLimitException(
            '服务器返回 $status 重定向，但没有给出 Location 头，无法继续。',
          );
        }
        final next = current.resolve(location.trim());
        if (!allowedSchemes.contains(next.scheme)) {
          throw RefusedHostException(
            '重定向到不支持的协议 `$next`：只允许 ${allowedSchemes.join(' / ')}',
          );
        }
        redirects.add(next.toString());
        current = next;
        continue;
      }

      final contentLength = _contentLength(response);
      final body = await readBodyCapped(response, maxBytes: maxBytes);
      final contentType = _contentTypeOf(response);
      return WebFetchResult(
        bytes: body.bytes,
        finalUrl: current.toString(),
        contentType: contentType,
        declaredCharset:
            charsetOfContentType(contentType) ?? _parsedCharset(response),
        statusCode: status,
        redirects: redirects,
        // A `content-length` past the cap is known before reading; otherwise the
        // reader reports what it stopped at.
        bodyTruncated: (contentLength != null && contentLength > maxBytes) ||
            body.truncated,
      );
    }

    throw RedirectLimitException(
      '重定向超过 $maxRedirectHops 次，已停止：${redirects.join(' -> ')}',
    );
  }

  Future<HttpClientResponse> _open(Uri url) async {
    final request = await _client.openUrl('GET', url).timeout(timeout);
    // Identity, not impersonation: no cookies, no Authorization, no credentials.
    request.headers.set(HttpHeaders.userAgentHeader, userAgent);
    request.headers.set(HttpHeaders.acceptHeader,
        'text/html,application/xhtml+xml,text/plain;q=0.9,*/*;q=0.5');
    request.followRedirects = false;
    return request.close().timeout(timeout);
  }

  /// Reads and discards a redirect body, so the connection can be reused.
  ///
  /// Failures here are deliberately ignored: the body of a redirect is not
  /// something the caller asked for, and losing it must not fail the fetch.
  Future<void> _drain(HttpClientResponse response) async {
    try {
      await response.drain<void>();
    } on Object {
      // A redirect we cannot drain is still a redirect we can follow.
    }
  }

  static bool _isRedirect(int status) =>
      status == HttpStatus.movedPermanently ||
      status == HttpStatus.found ||
      status == HttpStatus.seeOther ||
      status == HttpStatus.temporaryRedirect ||
      status == HttpStatus.permanentRedirect;

  /// The raw `content-type` header, or ''.
  ///
  /// Read as a string rather than through `headers.contentType` because a server
  /// is free to send a malformed value and that getter throws on one; a broken
  /// header should cost the model a charset hint, not the whole page.
  static String _contentTypeOf(HttpClientResponse response) {
    try {
      return response.headers.contentType?.toString() ?? '';
    } on FormatException {
      return response.headers.value(HttpHeaders.contentTypeHeader) ?? '';
    }
  }

  /// The charset as `HttpHeaders` parsed it, or null when it did not parse.
  static String? _parsedCharset(HttpClientResponse response) {
    try {
      return response.headers.contentType?.charset;
    } on FormatException {
      return null;
    }
  }

  static int? _contentLength(HttpClientResponse response) =>
      response.contentLength < 0 ? null : response.contentLength;
}

/// The outcome of reading a body under the cap.
class CappedBody {
  const CappedBody(this.bytes, this.truncated);

  final List<int> bytes;
  final bool truncated;
}

/// Reads at most [maxBodyBytes] of [response], reporting whether it stopped
/// early.
///
/// The cap is enforced while reading rather than after: a server that streams
/// gigabytes must not be able to make this process hold them first. The reader
/// also stops as soon as the server's own `content-length` is reached, because
/// some servers keep a keep-alive connection open past the body.
Future<CappedBody> readBodyCapped(
  HttpClientResponse response, {
  int maxBytes = maxBodyBytes,
}) async {
  final declared = response.contentLength < 0 ? null : response.contentLength;
  final wanted = declared != null && declared < maxBytes ? declared : maxBytes;

  final builder = BytesBuilder(copy: false);
  var truncated = declared != null && declared > maxBytes;

  await for (final chunk in response) {
    if (builder.length + chunk.length <= wanted) {
      builder.add(chunk);
    } else {
      final room = wanted - builder.length;
      if (room > 0) {
        builder.add(chunk.sublist(0, room));
      }
      truncated = true;
      break;
    }
    if (builder.length >= wanted) {
      break;
    }
  }
  return CappedBody(builder.takeBytes(), truncated);
}

/// Extracts the `charset` from a raw `content-type` header value.
///
/// Kept next to [decodeBody] because the two must agree on what a charset
/// parameter looks like; `HttpHeaders.contentType` already parses it, and this
/// exists for callers holding only the header string (and for tests).
String? charsetOfContentType(String? contentType) {
  if (contentType == null) {
    return null;
  }
  final match = RegExp(r'charset\s*=\s*"?([^";\s]+)"?', caseSensitive: false)
      .firstMatch(contentType);
  final value = match?.group(1)?.trim();
  return value == null || value.isEmpty ? null : value;
}

// -----------------------------------------------------------------------------
// Host classification.
// -----------------------------------------------------------------------------

/// Parses a dotted-quad IPv4 literal, or null when [host] is not one.
List<int>? _parseIpv4(String host) {
  final parts = host.split('.');
  if (parts.length != 4) {
    return null;
  }
  final bytes = <int>[];
  for (final part in parts) {
    if (part.isEmpty || part.length > 3 || !_isAsciiDigits(part)) {
      return null;
    }
    final value = int.parse(part);
    if (value > 255) {
      return null;
    }
    bytes.add(value);
  }
  return bytes;
}

bool _isAsciiDigits(String text) {
  for (var i = 0; i < text.length; i++) {
    final code = text.codeUnitAt(i);
    if (code < 0x30 || code > 0x39) {
      return false;
    }
  }
  return true;
}

/// The range name [address] falls in, or null when it is public.
///
/// The list is the one that matters for "can the model reach the user's own
/// machine or LAN": loopback, the three RFC 1918 blocks, link-local (including
/// the cloud metadata address 169.254.169.254), CGNAT, and the other reserved
/// blocks that are never a public web host.
String? _privateIpv4Block(List<int> address) {
  final a = address[0];
  final b = address[1];
  if (a == 0) {
    return '0.0.0.0/8';
  }
  if (a == 10) {
    return '10.0.0.0/8';
  }
  if (a == 127) {
    return '127.0.0.0/8';
  }
  if (a == 169 && b == 254) {
    return '169.254.0.0/16（含云元数据地址）';
  }
  if (a == 172 && b >= 16 && b <= 31) {
    return '172.16.0.0/12';
  }
  if (a == 192 && b == 168) {
    return '192.168.0.0/16';
  }
  if (a == 100 && b >= 64 && b <= 127) {
    return '100.64.0.0/10（运营商级 NAT）';
  }
  if (a == 192 && b == 0) {
    return '192.0.0.0/24（保留）';
  }
  if (a == 198 && (b == 18 || b == 19)) {
    return '198.18.0.0/15（基准测试）';
  }
  if (a >= 224) {
    return '组播/保留段';
  }
  return null;
}

/// Parses a bracketed IPv6 literal into its 16 bytes, or null.
///
/// Handles the `::` shorthand and a trailing dotted-quad (`::ffff:127.0.0.1`),
/// which is the form that would otherwise slip a loopback through.
List<int>? _parseIpv6(String host) {
  var text = host;
  // Strip a zone id (`fe80::1%eth0`).
  final percent = text.indexOf('%');
  if (percent >= 0) {
    text = text.substring(0, percent);
  }
  if (text.isEmpty) {
    return null;
  }

  final doubleColon = text.indexOf('::');
  String head;
  String tail;
  if (doubleColon < 0) {
    head = text;
    tail = '';
  } else {
    head = text.substring(0, doubleColon);
    tail = text.substring(doubleColon + 2);
    if (tail.contains('::')) {
      return null;
    }
  }

  final headGroups = _ipv6Groups(head);
  final tailGroups = _ipv6Groups(tail);
  if (headGroups == null || tailGroups == null) {
    return null;
  }

  final groups = <int>[];
  for (final group in headGroups) {
    groups.add(group);
  }
  if (doubleColon >= 0) {
    final missing = 8 - headGroups.length - tailGroups.length;
    if (missing < 0) {
      return null;
    }
    for (var i = 0; i < missing; i++) {
      groups.add(0);
    }
  }
  for (final group in tailGroups) {
    groups.add(group);
  }
  if (groups.length != 8) {
    return null;
  }

  final bytes = <int>[];
  for (final group in groups) {
    bytes
      ..add((group >> 8) & 0xFF)
      ..add(group & 0xFF);
  }
  return bytes;
}

/// Splits a colon-separated IPv6 piece into 16-bit groups.
///
/// Returns null for anything malformed, including a lone trailing colon that is
/// not part of `::`.
List<int>? _ipv6Groups(String piece) {
  if (piece.isEmpty) {
    return const [];
  }
  final parts = piece.split(':');
  final groups = <int>[];
  for (var i = 0; i < parts.length; i++) {
    final part = parts[i];
    if (part.contains('.')) {
      // A dotted-quad tail must be the last element.
      if (i != parts.length - 1) {
        return null;
      }
      final v4 = _parseIpv4(part);
      if (v4 == null) {
        return null;
      }
      groups
        ..add((v4[0] << 8) | v4[1])
        ..add((v4[2] << 8) | v4[3]);
      continue;
    }
    if (part.isEmpty || part.length > 4 || !_isHex(part)) {
      return null;
    }
    groups.add(int.parse(part, radix: 16));
  }
  return groups;
}

bool _isHex(String text) {
  for (var i = 0; i < text.length; i++) {
    final code = text.codeUnitAt(i);
    final isDigit = code >= 0x30 && code <= 0x39;
    final lower = code | 0x20;
    final isLetter = lower >= 0x61 && lower <= 0x66;
    if (!isDigit && !isLetter) {
      return false;
    }
  }
  return true;
}

/// The reserved range [address] falls in, or null when it is a public address.
String? _privateIpv6Block(List<int> address) {
  final allZero = address.every((byte) => byte == 0);
  if (allZero) {
    return '::（未指定地址）';
  }
  final loopback = address.sublist(0, 15).every((byte) => byte == 0) &&
      address[15] == 1;
  if (loopback) {
    return '::1（回环）';
  }
  // ::ffff:a.b.c.d - an IPv4 address wearing an IPv6 coat.
  final v4Mapped = address.sublist(0, 10).every((byte) => byte == 0) &&
      address[10] == 0xFF &&
      address[11] == 0xFF;
  if (v4Mapped) {
    final mapped = _privateIpv4Block(address.sublist(12));
    return mapped == null ? null : 'IPv4 映射地址 $mapped';
  }
  if (address[0] == 0xFE && (address[1] & 0xC0) == 0x80) {
    return 'fe80::/10（链路本地）';
  }
  if ((address[0] & 0xFE) == 0xFC) {
    return 'fc00::/7（唯一本地地址）';
  }
  if (address[0] == 0xFF) {
    return 'ff00::/8（组播）';
  }
  return null;
}
