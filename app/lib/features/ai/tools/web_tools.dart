/// The `fetch_page` tool: read a web page, or pull specific elements out of it.
///
/// **Why this one tool is allowed to open a socket.** `docs/AI_DESIGN.md` D1
/// rule 2 says network egress lives in the model adapter alone, and
/// `openai_compat_adapter.dart` says the same in its first line. This tool is a
/// deliberate, documented exception: the user asked for "let it browse the web
/// and grab elements", which cannot be done from the adapter, and the rule's
/// purpose - "turning the AI off returns the app to exactly what it was" - still
/// holds, because a tool is only reachable from a running agent turn.
///
/// What keeps the exception narrow, all of it enforced in `web_http.dart`:
///
///  * **GET only**, with an identifying User-Agent and **no** cookies, no
///    `Authorization`, no credentials of any kind: a page the user is logged into
///    must not be read as them;
///  * **private/loopback/link-local hosts are refused** by default, so the model
///    cannot be argued into probing the user's own machine or LAN;
///  * redirects are followed by hand, capped, and every hop is reported;
///  * 15 s timeout, 2 MiB body cap, non-2xx is an error rather than an empty
///    success.
///
/// The tool is **read-only** in the sense the rest of the layer uses: it has no
/// `action`, changes no local data, and returns
/// `ToolRisk.write` + `reversibleFor == true` exactly like [QueryTasksTool],
/// which is the combination `ApprovalEngine` never asks per call about. See the
/// same comment in `task_tools.dart` and `cognitive_tools.dart` - `ToolRisk` has
/// no read-only variant on purpose (D12 v2).
library;

import 'dart:async';
import 'dart:io';

import '../../../domain/services/web/html_document.dart';
import '../../../domain/services/web/web_http.dart';
import '../domain/ai_tool.dart';

/// Fetches one page and returns either its text or the elements a selector picks
/// out.
class FetchPageTool extends AiTool {
  FetchPageTool({
    HttpClient? client,
    WebFetcher? fetcher,
    this.bodyByteLimit = maxBodyBytes,
  }) : _fetcher = fetcher ??
            WebFetcher(
              client: client,
              // The 2 MiB cap (or a smaller one a test asks for) is enforced in
              // the fetcher while the body streams in.
              maxBytes: bodyByteLimit,
              // The fixture server in the tests lives on 127.0.0.1, which the
              // production policy refuses; the tests pass a fetcher with a
              // permissive policy instead of the policy having a bypass flag
              // that production code could also use.
              hostPolicy: refuseNonPublicHost,
            );

  final WebFetcher _fetcher;

  /// The body cap in force, echoed into the model result so a truncated page is
  /// visible from the transcript alone.
  final int bodyByteLimit;

  /// How many matches come back when the model does not say.
  static const int defaultLimit = 5;

  /// The ceiling on [limit]. Twenty matches is already a lot of page for one
  /// turn; past that the model should narrow the selector instead.
  static const int maxLimit = 20;

  /// The cap on a page-wide text answer. Enough for a long article's opening,
  /// small enough that a tool result cannot crowd out the conversation.
  static const int maxTextChars = 8000;

  /// A tool call may not run longer than this, including every redirect hop.
  static const Duration overallTimeout = Duration(seconds: 25);

  @override
  String get name => 'fetch_page';

  @override
  String get description =>
      '抓取一个网页并读取内容。用在：用户贴了一个链接让你看、让你上网查某件事、'
      '或者问页面里某个具体部分（那时用 selector 精确取元素）。'
      '**只支持 http/https**（file:// 等一律拒绝），只做 GET，不发送任何 cookie 或登录凭据。'
      '不给 selector 时返回标题 + 正文纯文本（脚本/样式已去掉，HTML 实体已解码，'
      '连续空白已折叠）'
      '，正文最多 $maxTextChars 字符，被截断时会明确标注。'
      '给 selector 时返回匹配到的元素列表：每个元素的 index/tag/id/class/text/属性'
      '（a 给 href，img 给 src/alt，表单给 value/name，其余标签给全部属性），'
      '外加 selector / matchCount（总命中数）/ returned（本次返回数）。'
      '选择器只支持这一小撮语法：类型 `div`、id `#main`、类 `.item`、类型+类 `div.item`、'
      '多类 `.a.b`、属性存在 `[data-x]`、属性相等 `[name="q"]`（引号可省）、'
      '以及空格分隔的后代组合 `main .item a`。'
      '**不支持** `>` `+` `~`、`:伪类`、`nth-child`、`*`、逗号列表，'
      '也不支持除 `=` 以外的属性运算符（`~= |= ^= \$= *=`）——'
      '出现这些会直接报错并指出是哪个符号，不会假装"没有匹配"。'
      '页面抓不到、状态码非 2xx、地址被拒绝时返回错误（含状态码/原因），不是空结果。'
      '这是只读操作，不改任何本地数据。';

  @override
  Map<String, Object?> get parameters => {
        'type': 'object',
        'properties': {
          'url': {
            'type': 'string',
            'description': '要抓取的完整地址，必须以 http:// 或 https:// 开头',
          },
          'selector': {
            'type': 'string',
            'description':
                '可选。只取页面里匹配该选择器的元素。支持：`div`、`#main`、`.item`、'
                    '`div.item`、`.a.b`、`[data-x]`、`[name="q"]`、空格分隔的后代组合'
                    '（如 `main .item a`）。不支持 `>` `+` `~` `:伪类` `*` 逗号列表'
                    '及除 `=` 外的属性运算符。',
          },
          'limit': {
            'type': 'integer',
            'description': '最多返回几个匹配元素，默认 $defaultLimit，上限 $maxLimit',
          },
        },
        'required': <String>['url'],
      };

  /// Reading is not a risk (D12 v2 has only write/destructive) and this tool has
  /// no action, so the neutral `write` + reversible `true` is the pairing that
  /// keeps `ApprovalEngine` from asking per call. Identical to
  /// [QueryTasksTool.riskFor].
  @override
  ToolRisk riskFor(String action) => ToolRisk.write; // unused: no actions

  @override
  bool reversibleFor(String action) => true;

  @override
  bool get readOnly => true;

  @override
  bool get availableOnCurrentPlatform => true;

  @override
  Future<ToolResult> run(ToolInvocation invocation) async {
    try {
      return await _run(invocation);
    } on ToolArgError catch (e) {
      // A bad argument is the model's mistake and must come back as text it can
      // correct, not as a thrown exception that loses the turn.
      return ToolResult.failure(e.message);
    } on SelectorSyntaxException catch (e) {
      return ToolResult.failure(e.message);
    } on RefusedHostException catch (e) {
      return ToolResult.failure(e.message);
    } on RedirectLimitException catch (e) {
      return ToolResult.failure(e.message);
    } on TimeoutException catch (e) {
      return ToolResult.failure(
        '抓取超时（超过 ${overallTimeout.inSeconds} 秒）：${e.message ?? ''}'.trim(),
      );
    } on SocketException catch (e) {
      return ToolResult.failure('网络连接失败：${e.message}');
    } on HandshakeException catch (e) {
      return ToolResult.failure('TLS 握手失败：${e.message}');
    } on HttpException catch (e) {
      return ToolResult.failure('HTTP 错误：${e.message}');
    } on FormatException catch (e) {
      return ToolResult.failure('地址格式不对：${e.message}');
    } on Object catch (e) {
      // Anything else still has to be a tool error: the model can decide what to
      // do with a message, and it cannot do anything with an unhandled throw.
      return ToolResult.failure('抓取失败：$e');
    }
  }

  Future<ToolResult> _run(ToolInvocation invocation) async {
    final args = ToolArgs(invocation.arguments);

    // A selector outside the supported subset is refused **before** any network
    // work: there is no point downloading a page to answer a question the tool
    // cannot parse, and it makes the failure independent of connectivity.
    final selector = args.optString('selector');
    if (selector != null) {
      parseSelector(selector);
    }

    final urlText = args.requireString('url');
    final parsed = Uri.tryParse(urlText);
    if (parsed == null) {
      return ToolResult.failure('不是合法的地址：`$urlText`');
    }
    if (!allowedSchemes.contains(parsed.scheme.toLowerCase())) {
      return ToolResult.failure(
        '只支持 http/https，拒绝抓取 `$urlText`'
        '${parsed.scheme.isEmpty ? '（缺少协议前缀）' : '（协议是 `${parsed.scheme}`）'}。'
        'file:// 、ftp:// 等本地或其它协议一律不支持。',
      );
    }

    final limit = (args.optInt('limit') ?? defaultLimit).clamp(1, maxLimit);

    return _fetchWithinBudget(parsed, selector: selector, limit: limit);
  }

  /// Applies [overallTimeout] around the redirected fetch.
  ///
  /// `WebFetcher` bounds each individual request; this bounds the whole call
  /// including every hop, so a server that redirects slowly cannot hold a turn
  /// open indefinitely.
  Future<ToolResult> _fetchWithinBudget(
    Uri url, {
    required String? selector,
    required int limit,
  }) async {
    final result = await _fetcher.fetch(url).timeout(overallTimeout);
    final page = result;

    if (page.statusCode < 200 || page.statusCode >= 300) {
      return ToolResult.failure(
        '页面返回 HTTP ${page.statusCode}：${page.finalUrl}',
        summary: '抓取失败：HTTP ${page.statusCode}',
      );
    }

    // The body cap is already enforced while reading; a page whose declared
    // length is past the cap is refused outright rather than analysed, because a
    // document that large is not what the user asked to read.
    if (page.bytes.length > bodyByteLimit) {
      return ToolResult.failure(
        '页面超过 ${_describeBytes(bodyByteLimit)}，已放弃（未下载完）。'
        '可以换更具体的页面或让用户直接贴内容。',
      );
    }

    final decision = decodeBody(page.bytes, page.declaredCharset);
    final document = HtmlDocument.parse(decision.text);
    final notes = <String>[
      if (page.bodyTruncated)
        '响应体超过 ${_describeBytes(bodyByteLimit)}，只读取了前 '
            '${_describeBytes(page.bytes.length)}，页面尾部没有读到。',
      if (decision.note != null) decision.note!,
      if (document.nodesTruncated)
        '页面标签数量超过扫描上限 ${HtmlDocument.defaultMaxNodes}，尾部标签没有解析。',
    ];

    final base = <String, Object?>{
      'url': url.toString(),
      'final_url': page.finalUrl,
      'status': page.statusCode,
      if (page.redirects.isNotEmpty) 'redirects': page.redirects,
      'content_type': page.contentType,
      'charset': decision.encoding,
      if (decision.declared != null) 'declared_charset': decision.declared,
      'body_truncated': page.bodyTruncated,
      'body_bytes': page.bytes.length,
      if (notes.isNotEmpty) 'notes': notes,
    };

    if (selector == null) {
      return _textResult(
        document: document,
        base: base,
        page: page,
        notes: notes,
      );
    }
    return _selectorResult(
      document: document,
      base: base,
      selector: selector,
      limit: limit,
      notes: notes,
    );
  }

  ToolResult _textResult({
    required HtmlDocument document,
    required Map<String, Object?> base,
    required WebFetchResult page,
    required List<String> notes,
  }) {
    final title = document.root.title;
    final text = document.extractText(document.root, maxChars: maxTextChars);
    final textTruncated = text.contains('[截断：');

    return ToolResult(
      ok: true,
      summary: title.isEmpty
          ? '已读取页面（${_describeBytes(page.bytes.length)}文本，无标题）'
          : '已读取页面「$title」',
      modelResult: {
        ...base,
        'title': title,
        'text': text,
        'text_truncated': textTruncated,
        'max_text_chars': maxTextChars,
      },
    );
  }

  ToolResult _selectorResult({
    required HtmlDocument document,
    required Map<String, Object?> base,
    required String selector,
    required int limit,
    required List<String> notes,
  }) {
    final matches = document.select(selector);
    final returned = matches.take(limit).toList();

    return ToolResult(
      ok: true,
      summary: matches.isEmpty
          ? '选择器 `$selector` 在页面里没有匹配到任何元素'
          : '选择器 `$selector` 命中 ${matches.length} 个元素，返回前 ${returned.length} 个',
      modelResult: {
        ...base,
        'title': document.root.title,
        'selector': selector,
        // Total found vs. how many came back under `limit`: without both, the
        // model cannot tell "the page has 3 links" from "I only asked for 3".
        'matchCount': matches.length,
        'returned': returned.length,
        'truncated': matches.length > returned.length,
        'limit': limit,
        'elements': [
          for (var i = 0; i < returned.length; i++)
            document.matchJson(returned[i], index: i),
        ],
      },
    );
  }

  /// A byte count in the units a person reads, for summaries and errors.
  static String _describeBytes(int bytes) {
    if (bytes >= 1024 * 1024) {
      final mib = bytes / (1024 * 1024);
      return '${mib.toStringAsFixed(mib == mib.roundToDouble() ? 0 : 1)} MB';
    }
    if (bytes >= 1024) {
      final kib = bytes / 1024;
      return '${kib.toStringAsFixed(kib == kib.roundToDouble() ? 0 : 1)} KB';
    }
    return '$bytes 字节';
  }
}
