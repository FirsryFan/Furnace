import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/anki_repository.dart';
import 'package:furnace/data/repositories/tag_repository.dart';
import 'package:furnace/data/repositories/task_repository.dart';
import 'package:furnace/data/repositories/time_block_repository.dart';
import 'package:furnace/domain/services/web/web_http.dart';
import 'package:furnace/features/ai/domain/ai_tool.dart';
import 'package:furnace/features/ai/domain/tool_registry.dart';
import 'package:furnace/features/ai/tools/web_tools.dart';

/// `fetch_page` is the only tool that talks to a machine the app does not own, so
/// these tests are about the boundary, not the happy path:
///
///  * no credentials of any kind leave the process, and the User-Agent says who
///    is calling;
///  * private/loopback/link-local hosts are refused by the production policy;
///  * every failure (bad scheme, 404, redirect loop, dead port, unsupported
///    selector) is a **tool error the model can read**, never an empty success and
///    never an unhandled exception;
///  * the caps (redirects, bytes, characters) are enforced *and reported*.
///
/// **These tests never touch the real internet.** Every request is served by an
/// `HttpServer` bound to `127.0.0.1:0`, which the production host policy would
/// refuse - so the fixtures inject a fetcher whose policy allows loopback, and a
/// separate group proves the production default still refuses it.
void main() {
  late HttpServer server;
  late int port;

  /// Requests the fixture server saw, so header rules can be asserted after the
  /// fact. Cleared per test.
  late List<HttpHeaders> seenHeaders;
  late List<String> seenMethods;

  /// The fixture page: a small link list with titles, plus the awkward shapes.
  const linkListPage = '''
<!doctype html>
<html lang="zh">
<head>
  <meta charset="utf-8">
  <title>阅读清单</title>
  <style>body { color: #111; }</style>
  <script>var x = 1; if (x < 2) { console.log("</b> not a tag"); }</script>
</head>
<body>
  <h1>我的清单</h1>
  <p>三段文字 &amp; 一个实体：1 &lt; 2 &#20013;&#x6587;&nbsp;结束。</p>
  <ul class="links">
    <li><a class="link" href="/one" data-kind="doc">第一 &amp; 篇</a></li>
    <li><a class="link" href="/two" data-kind="doc">第二篇</a></li>
    <li><a class="link" href="/three">第三篇</a></li>
    <li><a class="link external" href="/four" target="_blank" rel="noopener">第四篇</a></li>
    <li><a class="link" href="/five">第五篇</a></li>
    <li><a class="link" href="/six">第六篇</a></li>
    <li><a class="link" href="/seven">第七篇</a></li>
  </ul>
  <img class="thumb" src="/p.png" alt="封面" width="12">
  <form action="/search"><input type="text" name="q" value="初始" placeholder="搜索"></form>
</body>
</html>''';

  setUp(() async {
    seenHeaders = [];
    seenMethods = [];
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    port = server.port;
    server.listen((request) async {
      seenHeaders.add(request.headers);
      seenMethods.add(request.method);
      final path = request.uri.path;
      final response = request.response;

      if (path == '/links') {
        response.headers.contentType =
            ContentType('text', 'html', charset: 'utf-8');
        response.write(linkListPage);
      } else if (path == '/many') {
        // More matches than `maxLimit`, so the clamp is provable.
        response.headers.contentType =
            ContentType('text', 'html', charset: 'utf-8');
        final links = [
          for (var i = 1; i <= 25; i++)
            '<a class="item" href="/n/$i">第 $i 条</a>',
        ].join();
        response.write('<html><body><div class="list">$links</div></body></html>');
      } else if (path == '/r/1') {
        response.statusCode = HttpStatus.movedPermanently;
        response.headers.set(HttpHeaders.locationHeader, '/r/2');
      } else if (path == '/r/2') {
        response.statusCode = HttpStatus.found;
        response.headers.set(HttpHeaders.locationHeader, '/r/3');
      } else if (path == '/r/3') {
        response.statusCode = HttpStatus.seeOther;
        response.headers.set(HttpHeaders.locationHeader, '/final');
      } else if (path == '/final') {
        response.headers.contentType =
            ContentType('text', 'html', charset: 'utf-8');
        response.write('<html><head><title>终点</title></head>'
            '<body><p>arrived</p></body></html>');
      } else if (path == '/loop') {
        response.statusCode = HttpStatus.found;
        response.headers.set(HttpHeaders.locationHeader, '/loop');
      } else if (path == '/missing') {
        response.statusCode = HttpStatus.notFound;
        response.headers.contentType =
            ContentType('text', 'html', charset: 'utf-8');
        response.write('<html><body>not here</body></html>');
      } else if (path == '/latin1') {
        response.headers.contentType =
            ContentType('text', 'html', charset: 'iso-8859-1');
        response.add(latin1.encode('<html><body><p>caf\u00e9</p></body></html>'));
      } else if (path == '/gbk') {
        // A declared charset Dart has no codec for. The bytes are whatever a GBK
        // page would send; the point is that they are NOT silently transcoded and
        // NOT presented as if they were.
        response.headers.contentType =
            ContentType('text', 'html', charset: 'gb2312');
        response.add(const [0xD6, 0xD0, 0xCE, 0xC4, 0x0A, 0xB2, 0xE2, 0xCA, 0xD4]);
      } else if (path == '/redirect-to-gbk') {
        response.statusCode = HttpStatus.found;
        response.headers.set(HttpHeaders.locationHeader, '/gbk');
      } else if (path == '/big') {
        response.headers.contentType =
            ContentType('text', 'html', charset: 'utf-8');
        response.headers.contentLength = 400 * 1024;
        response.write('<html><body><p>HEAD-MARKER</p>');
        response.add(List<int>.filled(400 * 1024 - 100, 0x61));
        response.write('TAIL-MARKER</p></body></html>');
      } else if (path == '/empty') {
        response.headers.contentType =
            ContentType('text', 'html', charset: 'utf-8');
        response.write('<html><head><title>No Content</title></head>'
            '<body></body></html>');
      } else {
        response.statusCode = HttpStatus.notFound;
        response.write('nope');
      }
      await response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
  });

  /// A tool wired to the fixture server.
  ///
  /// [bodyByteLimit] is injectable so the truncation path can be exercised with a
  /// small fixture instead of generating 2 MiB; the 2 MiB default itself is
  /// asserted separately as a constant.
  FetchPageTool toolWith({int bodyByteLimit = maxBodyBytes}) => FetchPageTool(
        bodyByteLimit: bodyByteLimit,
        fetcher: WebFetcher(
          maxBytes: bodyByteLimit,
          // The test server is on loopback, which `refuseNonPublicHost` refuses
          // by design. The bypass lives here, in the test, not in the policy.
          hostPolicy: (_) => null,
        ),
      );

  ToolInvocation invoke(Map<String, Object?> arguments) => ToolInvocation(
        toolName: 'fetch_page',
        action: 'fetch_page',
        arguments: arguments,
      );

  String url(String path) => 'http://127.0.0.1:$port$path';

  Map<String, Object?> resultOf(ToolResult result) =>
      (result.modelResult! as Map).cast<String, Object?>();

  List<Map<String, Object?>> elementsOf(ToolResult result) => [
        for (final entry in resultOf(result)['elements']! as List)
          (entry as Map).cast<String, Object?>(),
      ];

  group('tool contract', () {
    test('name, availability and read-only risk match the read tools', () {
      final tool = toolWith();
      expect(tool.name, 'fetch_page');
      expect(tool.availableOnCurrentPlatform, isTrue);
      // Identical to query_tasks / evaluate_problem_fit: ToolRisk has no
      // read-only variant, and the neutral write + reversible pair is what keeps
      // ApprovalEngine from asking per call.
      expect(tool.riskFor('fetch_page'), ToolRisk.write);
      expect(tool.reversibleFor('fetch_page'), isTrue);
    });

    test('the schema declares url as required and the two optional knobs', () {
      final parameters = toolWith().parameters;
      expect(parameters['type'], 'object');
      final properties = (parameters['properties']! as Map).cast<String, Object?>();
      expect(properties.keys, containsAll(['url', 'selector', 'limit']));
      expect(parameters['required'], ['url']);
      expect((properties['url']! as Map)['type'], 'string');
      expect((properties['selector']! as Map)['type'], 'string');
      expect((properties['limit']! as Map)['type'], 'integer');
      // The caps the model is told about must be the caps the tool enforces.
      expect(FetchPageTool.defaultLimit, 5);
      expect(FetchPageTool.maxLimit, 20);
      expect(FetchPageTool.maxTextChars, 8000);
    });

    test('the description says when to use it and that it is http/https only',
        () {
      final description = toolWith().description;
      expect(description, contains('selector'));
      expect(description, contains('http/https'));
      expect(description, contains('只读'));
      // The unsupported combinator list must be in the description: the model
      // has to know not to send `>`.
      expect(description, contains('不支持'));
      expect(description, contains('nth-child'));
    });

    test('it is registered in the app tool list, first, with its schema', () {
      // The app's own list, assembled the way the provider assembles it: a tool
      // that is missing here is unreachable by the model (AI_DESIGN C2), i.e.
      // dead code. Registered first so the model sees it before the local tools.
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final registry = ToolRegistry.forApp(
        db: db,
        tasks: TaskRepository(db),
        blocks: TimeBlockRepository(db),
        anki: AnkiRepository(db),
        tags: TagRepository(db),
      );

      expect(registry.byName('fetch_page'), isA<FetchPageTool>());
      expect(registry.forCurrentPlatform.first.name, 'fetch_page');
      final spec =
          registry.modelSpecs.firstWhere((s) => s.name == 'fetch_page');
      expect(spec.description, contains('http/https'));
      expect(spec.parameters['type'], 'object');
      expect(spec.parameters['required'], ['url']);
      final properties =
          (spec.parameters['properties']! as Map).cast<String, Object?>();
      expect(properties.keys.toSet(), {'url', 'selector', 'limit'});
      // …and the pre-existing tools are still registered.
      expect(registry.byName('query_tasks'), isNotNull);
      expect(registry.byName('manage_task'), isNotNull);
      expect(registry.byName('evaluate_problem_fit'), isNotNull);
    });
  });

  group('plain text result', () {
    test('returns the title and readable text, without script or style', () async {
      final result = await toolWith().run(invoke({'url': url('/links')}));

      expect(result.ok, isTrue);
      final data = resultOf(result);
      expect(data['title'], '阅读清单');
      final text = data['text']! as String;
      expect(text, contains('我的清单'));
      expect(text, contains('结束'));
      // Entities decoded, whitespace collapsed.
      expect(text, contains('三段文字 & 一个实体：1 < 2 中文 结束。'));
      // Script and style content is gone; their *markup* must not survive either.
      expect(text, isNot(contains('console.log')));
      expect(text, isNot(contains('color:')));
      expect(text, isNot(contains('not a tag')));
      expect(data['text_truncated'], isFalse);
      expect(data['max_text_chars'], 8000);
      expect(data['status'], 200);
      expect(data['charset'], 'utf-8');
      expect(data['final_url'], url('/links'));
      expect(data['body_truncated'], isFalse);
    });

    test('a page with no readable text still succeeds with a title', () async {
      final result = await toolWith().run(invoke({'url': url('/empty')}));
      expect(result.ok, isTrue);
      final data = resultOf(result);
      expect(data['title'], 'No Content');
      expect(data['text'], '');
    });

    test('the returned text is capped with an explicit marker', () async {
      // A 12k-character body served in-process, so the character cap is provable
      // without a 2 MiB fixture.
      final server2 = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server2.listen((request) async {
        request.response.headers.contentType =
            ContentType('text', 'html', charset: 'utf-8');
        request.response.write('<html><body><p>${'字' * 12000}</p></body></html>');
        await request.response.close();
      });
      addTearDown(() => server2.close(force: true));

      final result = await toolWith().run(
        invoke({'url': 'http://127.0.0.1:${server2.port}/long'}),
      );

      expect(result.ok, isTrue);
      final data = resultOf(result);
      final text = data['text']! as String;
      expect(data['text_truncated'], isTrue);
      expect(text.length, lessThanOrEqualTo(FetchPageTool.maxTextChars));
      expect(text, contains('[截断：'));
    });
  });

  group('selectors', () {
    test('each supported form picks the right elements out of a link list',
        () async {
      final tool = toolWith();

      Future<List<Map<String, Object?>>> select(String selector) async {
        final result = await tool.run(
          invoke({'url': url('/links'), 'selector': selector}),
        );
        expect(result.ok, isTrue, reason: 'selector `$selector`');
        return elementsOf(result);
      }

      expect((await select('a')).length, 5);
      expect((await select('.link')).length, 5);
      expect((await select('a.link')).length, 5);
      expect((await select('.link.external')).length, 1);
      expect((await select('#none')).length, 0);
      expect((await select('ul.links li')).length, 5);
      expect((await select('body ul.links a.link')).length, 5);
      // Attribute presence and equality, on a real page.
      expect((await select('[data-kind]')).length, 2);
      expect((await select('[data-kind="doc"]')).length, 2);
      expect((await select('a[data-kind=doc]')).length, 2);
      // A tag with no matches is a miss, not an error.
      expect((await select('table')).length, 0);
    });

    test('a match carries index/tag/id/class/text and the useful attributes',
        () async {
      final result = await toolWith().run(
        invoke({'url': url('/links'), 'selector': 'a.link'}),
      );
      expect(result.ok, isTrue);
      final elements = elementsOf(result);

      final first = elements.first;
      expect(first['index'], 0);
      expect(first['tag'], 'a');
      // `class` is the class attribute, not a list; `id` is omitted when absent.
      expect(first['class'], 'link');
      expect(first.containsKey('id'), isFalse);
      expect(first['text'], '第一 & 篇');
      expect(first['href'], '/one');
      // The link attribute set, so unrelated attributes are not noise.
      final external = elements.firstWhere((e) => e['href'] == '/four');
      expect(external['class'], 'link external');
      expect(external['target'], '_blank');
      expect(external['rel'], 'noopener');
      // The first element with `data-kind` also exposes it (it is in the link set?
      // no: `data-*` is not in the a-set, so it must NOT appear).
      expect(first.containsKey('data-kind'), isFalse);

      final imgResult = await toolWith().run(
        invoke({'url': url('/links'), 'selector': 'img'}),
      );
      expect(resultOf(imgResult)['returned'], 1);
      final image = elementsOf(imgResult).single;
      expect(image['src'], '/p.png');
      expect(image['alt'], '封面');
      expect(image['width'], '12');
    });

    test('a form field exposes name/value and the field attributes', () async {
      final result = await toolWith().run(
        invoke({'url': url('/links'), 'selector': 'input'}),
      );
      final field = elementsOf(result).single;
      expect(field['name'], 'q');
      expect(field['value'], '初始');
      expect(field['placeholder'], '搜索');
      expect(field['type'], 'text');
    });

    test('id and class are reported when the element has them', () async {
      final result = await toolWith().run(
        invoke({'url': url('/links'), 'selector': 'ul.links'}),
      );
      final list = elementsOf(result).single;
      expect(list['tag'], 'ul');
      expect(list['class'], 'links');
    });

    test('matchCount is the total and returned reflects the limit', () async {
      final result = await toolWith().run(
        invoke({'url': url('/links'), 'selector': 'a.link', 'limit': 3}),
      );
      expect(result.ok, isTrue);
      final data = resultOf(result);
      expect(data['matchCount'], 7);
      expect(data['returned'], 3);
      expect(data['truncated'], isTrue);
      // The indexes are positions in the returned slice.
      expect(elementsOf(result).map((e) => e['index']), [0, 1, 2]);
      expect(elementsOf(result).map((e) => e['text']),
          ['第一 & 篇', '第二篇', '第三篇']);
    });

    test('limit defaults to 5 and is clamped to the documented maximum',
        () async {
      final dflt = await toolWith().run(
        invoke({'url': url('/many'), 'selector': 'a.item'}),
      );
      expect(resultOf(dflt)['returned'], FetchPageTool.defaultLimit);
      expect(resultOf(dflt)['matchCount'], 25);

      // `maxLimit` is only observable when the page has more matches than that,
      // so this uses the 25-link fixture rather than the five-link one.
      final clamped = await toolWith().run(
        invoke({'url': url('/many'), 'selector': 'a.item', 'limit': 500}),
      );
      expect(resultOf(clamped)['returned'], FetchPageTool.maxLimit);
      expect(resultOf(clamped)['matchCount'], 25);
      expect(resultOf(clamped)['truncated'], isTrue);

      final tooSmall = await toolWith().run(
        invoke({'url': url('/links'), 'selector': 'a.link', 'limit': 0}),
      );
      expect(resultOf(tooSmall)['returned'], 1);
    });

    test('a complete selector miss is a success with an empty list', () async {
      final result = await toolWith().run(
        invoke({'url': url('/links'), 'selector': '.definitely-not-here'}),
      );
      expect(result.ok, isTrue);
      final data = resultOf(result);
      expect(data['matchCount'], 0);
      expect(data['returned'], 0);
      expect(data['truncated'], isFalse);
      expect(elementsOf(result), isEmpty);
    });

    test('unsupported selector syntax names the offending token', () async {
      final tool = toolWith();
      final cases = {
        'div > p': '>',
        'a + b': '+',
        'a ~ b': '~',
        'p:first-child': ':',
        '*': '*',
        'a, b': ',',
        '[class~="link"]': '~=',
        '[href^="http"]': '^=',
        '[href\$=".png"]': '\$=',
        '[href*="x"]': '*=',
      };
      for (final entry in cases.entries) {
        final result = await tool.run(
          invoke({'url': url('/links'), 'selector': entry.key}),
        );
        expect(result.ok, isFalse, reason: 'selector `${entry.key}`');
        expect(result.error, contains('不支持'), reason: entry.key);
        expect(result.error, contains(entry.value), reason: entry.key);
      }
      // Refused before any request: a bad selector must not cost a download.
      expect(seenHeaders, isEmpty);
    });

    test('a malformed selector is refused as well', () async {
      for (final selector in ['div[', 'div.', '[=x]']) {
        final result = await toolWith().run(
          invoke({'url': url('/links'), 'selector': selector}),
        );
        expect(result.ok, isFalse, reason: 'selector `$selector`');
        expect(result.error, isNotNull);
      }
    });

    test('a blank selector falls back to the whole-page text result', () async {
      // `ToolArgs.optString` normalises '' and '   ' to null, which is the
      // documented behaviour for every optional argument in this layer, so a
      // blank selector reads the page rather than failing the call.
      final result = await toolWith().run(
        invoke({'url': url('/links'), 'selector': '   '}),
      );
      expect(result.ok, isTrue);
      expect(resultOf(result).containsKey('text'), isTrue);
      expect(resultOf(result).containsKey('elements'), isFalse);
    });
  });

  group('network rules', () {
    test('only http and https are accepted', () async {
      final tool = toolWith();
      for (final bad in [
        'file:///etc/passwd',
        'file:///C:/Users/me/secrets.txt',
        'ftp://example.com/x',
        'data:text/html,<b>x</b>',
        'javascript:alert(1)',
        'example.com/no-scheme',
      ]) {
        final result = await tool.run(invoke({'url': bad}));
        expect(result.ok, isFalse, reason: bad);
        expect(result.error, contains('http'), reason: bad);
      }
      // None of these reached the network.
      expect(seenMethods, isEmpty);
    });

    test('a missing url is a readable argument error', () async {
      final result = await toolWith().run(invoke({}));
      expect(result.ok, isFalse);
      expect(result.error, contains('url'));
    });

    test('a redirect chain is followed and every hop is reported', () async {
      final result = await toolWith().run(invoke({'url': url('/r/1')}));
      expect(result.ok, isTrue);
      final data = resultOf(result);
      expect(data['final_url'], url('/final'));
      expect(data['status'], 200);
      expect(data['redirects'],
          [url('/r/2'), url('/r/3'), url('/final')]);
      expect(data['text'], contains('arrived'));
      expect(data['title'], '终点');
      // 301 -> 302 -> 303 -> 200, three hops, each a GET.
      expect(seenMethods, everyElement('GET'));
    });

    test('more than five redirects is an error, not an infinite loop',
        () async {
      final result = await toolWith().run(invoke({'url': url('/loop')}));
      expect(result.ok, isFalse);
      expect(result.error, contains('重定向'));
      expect(result.error, contains('5'));
      // Bounded: initial request plus the five allowed hops.
      expect(seenMethods.length, 6);
    });

    test('a fetch that starts on a refused host never opens a socket', () async {
      final result = await FetchPageTool(
        fetcher: WebFetcher(hostPolicy: refuseNonPublicHost),
      ).run(invoke({'url': url('/links')}));
      expect(result.ok, isFalse);
      expect(result.error, contains('127.0.0.1'));
      expect(seenMethods, isEmpty);
    });

    test('a non-2xx status is an error that includes the status code', () async {
      final result = await toolWith().run(invoke({'url': url('/missing')}));
      expect(result.ok, isFalse);
      expect(result.error, contains('404'));
      expect(result.summary, contains('404'));
      expect(result.modelResult, isNull);
    });

    test('a network exception becomes a tool error carrying its message',
        () async {
      // A port nothing is listening on: a real SocketException, not a fake.
      final deadServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final deadPort = deadServer.port;
      await deadServer.close(force: true);

      final result = await toolWith().run(
        invoke({'url': 'http://127.0.0.1:$deadPort/x'}),
      );
      expect(result.ok, isFalse);
      expect(result.error, contains('网络连接失败'));
      expect(result.error!.length, greaterThan('网络连接失败：'.length));
    });

    test('the timeout and redirect caps are the documented ones', () {
      expect(requestTimeout, const Duration(seconds: 15));
      expect(maxRedirects, 5);
      // The whole call is bounded too, so a slow chain cannot hold a turn open.
      expect(FetchPageTool.overallTimeout.inSeconds, greaterThan(15));
    });

    test('a body past the cap is truncated and says so', () async {
      const smallCap = 64 * 1024;
      final result = await toolWith(bodyByteLimit: smallCap)
          .run(invoke({'url': url('/big')}));

      expect(result.ok, isTrue);
      final data = resultOf(result);
      expect(data['body_truncated'], isTrue);
      expect(data['body_bytes'] as int, lessThanOrEqualTo(smallCap));
      final text = data['text']! as String;
      expect(text, contains('HEAD-MARKER'));
      expect(text, isNot(contains('TAIL-MARKER')));
      final notes = data['notes']! as List;
      expect(notes.join(' '), contains('页面尾部没有读到'));
      expect(notes.join(' '), contains('KB'));
    });

    test('the production body cap is 2 MiB', () {
      // The constant the brief pins, asserted directly so the check does not
      // depend on generating a 2 MiB fixture.
      expect(maxBodyBytes, 2 * 1024 * 1024);
      expect(toolWith().bodyByteLimit, 2 * 1024 * 1024);
    });

    test('it sends an identifying User-Agent and no credentials', () async {
      final result = await toolWith().run(invoke({'url': url('/links')}));
      expect(result.ok, isTrue);

      final headers = seenHeaders.single;
      expect(seenMethods.single, 'GET');
      expect(headers.value(HttpHeaders.userAgentHeader), userAgent);
      expect(userAgent, contains('Furnace'));
      // None of these may ever be sent: a page the user is logged into must not
      // be fetched as them.
      expect(headers.value(HttpHeaders.authorizationHeader), isNull);
      expect(headers.value(HttpHeaders.cookieHeader), isNull);
      expect(headers.value(HttpHeaders.proxyAuthorizationHeader), isNull);
      // The fetch is not a form post and carries no body.
      expect(headers.value(HttpHeaders.contentTypeHeader), isNull);
      expect(seenHeaders.single.value('x-api-key'), isNull);
    });
  });

  group('charset', () {
    test('a declared utf-8 charset decodes correctly', () async {
      final result = await toolWith().run(invoke({'url': url('/links')}));
      final data = resultOf(result);
      expect(data['charset'], 'utf-8');
      expect(data['declared_charset'], 'utf-8');
    });

    test('a declared latin1 charset is honoured', () async {
      final result = await toolWith().run(invoke({'url': url('/latin1')}));
      expect(result.ok, isTrue);
      final data = resultOf(result);
      expect(data['charset'], 'latin1');
      expect(data['declared_charset'], 'iso-8859-1');
      // Decoded as latin1, so the é survives exactly.
      expect(data['text'], contains('café'));
    });

    test('an undecodable charset is reported, not silently mojibaked', () async {
      final result = await toolWith().run(invoke({'url': url('/gbk')}));
      expect(result.ok, isTrue);
      final data = resultOf(result);
      expect(data['charset'], 'latin1');
      expect(data['declared_charset'], 'gb2312');
      final notes = (data['notes']! as List).join(' ');
      expect(notes, contains('gb2312'));
      expect(notes, contains('没有做转码'));
    });

    test('the declared charset survives a redirect', () async {
      final result =
          await toolWith().run(invoke({'url': url('/redirect-to-gbk')}));
      expect(result.ok, isTrue);
      final data = resultOf(result);
      expect(data['declared_charset'], 'gb2312');
      expect(data['final_url'], url('/gbk'));
      expect((data['notes']! as List).join(' '), contains('没有做转码'));
    });

    test('charsetOfContentType reads the parameter the way decodeBody does',
        () {
      expect(charsetOfContentType('text/html; charset=utf-8'), 'utf-8');
      expect(charsetOfContentType('text/html;charset="GB2312"'), 'GB2312');
      expect(charsetOfContentType('text/html'), isNull);
      expect(charsetOfContentType(null), isNull);
    });
  });

  group('private host refusal (the production policy)', () {
    test('loopback, private ranges and the unspecified address are refused',
        () {
      final refused = [
        'localhost',
        'sub.localhost',
        '127.0.0.1',
        '127.1.2.3',
        '0.0.0.0',
        '10.0.0.1',
        '10.255.255.254',
        '172.16.0.1',
        '172.31.255.255',
        '192.168.0.1',
        '192.168.1.1',
        '169.254.169.254',
        '100.64.0.1',
        '198.18.0.1',
        '::1',
        '[::1]',
        'fe80::1',
        'fe80::1%eth0',
        'fc00::1',
        'fd12:3456::1',
        '::ffff:127.0.0.1',
        '224.0.0.1',
      ];
      for (final host in refused) {
        final message = refuseNonPublicHost(host);
        expect(message, isNotNull, reason: 'host `$host` must be refused');
        // A refusal must name the host so it cannot be read as a network failure.
        expect(message, contains(host.replaceAll('[', '').replaceAll(']', '')),
            reason: 'host `$host`');
      }
    });

    test('public hostnames and addresses are allowed', () {
      for (final host in [
        'example.com',
        'www.example.com',
        'api.deepseek.com',
        '8.8.8.8',
        '1.1.1.1',
        '172.32.0.1',
        '2001:4860:4860::8888',
      ]) {
        expect(refuseNonPublicHost(host), isNull, reason: 'host `$host`');
      }
    });

    test('an empty host is refused', () {
      expect(refuseNonPublicHost(''), isNotNull);
    });
  });

  group('malformed markup from the network is survivable', () {
    test('a page of broken HTML still yields text', () async {
      final server2 = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server2.listen((request) async {
        request.response.headers.contentType =
            ContentType('text', 'html', charset: 'utf-8');
        request.response.write('<p>one<p>two<div>three</span>');
        await request.response.close();
      });
      addTearDown(() => server2.close(force: true));

      final result = await toolWith()
          .run(invoke({'url': 'http://127.0.0.1:${server2.port}/x'}));
      expect(result.ok, isTrue);
      expect(resultOf(result)['text'], contains('one'));
      expect(resultOf(result)['text'], contains('three'));
    });
  });
}
