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
import 'package:furnace/features/ai/tools/oald_lookup_tool.dart';
import 'package:furnace/features/ai/tools/web_tools.dart';

import '../../support/oald_fixtures.dart';

/// `lookup_oald` is the app's standard dictionary reader, so these tests are
/// about the things a chat user actually depends on:
///
///  * the returned definition/example text is the page's text, exactly (select
///    or omit, never rewrite);
///  * a context picks a sense without changing it, and a context that matches
///    nothing says so instead of guessing;
///  * the file cache works, is keyed by word, is fresh/`refresh`-able, and a
///    failed live fetch can fall back to a cached real entry **only** with an
///    explicit `stale` flag;
///  * 404 / 403 anti-bot / suggestion page / unparsable page / dead network are
///    readable failures with no `modelResult` - the "do not invent a definition"
///    rule.
///
/// The HTTP fixtures are served by an in-process `HttpServer` on 127.0.0.1 (the
/// production host policy refuses loopback, so the tests inject a permissive
/// fetcher, exactly like `web_tools_test.dart`). The HTML comes from
/// `test/support/oald_fixtures.dart`, trimmed from live OALD pages. No test
/// touches the real app-support directory.
void main() {
  late HttpServer server;
  late int port;
  late Directory supportDirectory;
  late List<String> requestedPaths;

  final fixedNow = DateTime.utc(2026, 11, 15, 12);

  setUp(() async {
    requestedPaths = [];
    supportDirectory = await Directory.systemTemp.createTemp('furnace_oald_');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    port = server.port;
    server.listen((request) async {
      requestedPaths.add(request.uri.path);
      final path = request.uri.path;
      final response = request.response;
      if (path == '/definition/english/observe') {
        response.headers.contentType =
            ContentType('text', 'html', charset: 'utf-8');
        response.write(oaldObservePage);
      } else if (path == '/definition/english/happy') {
        response.headers.contentType =
            ContentType('text', 'html', charset: 'utf-8');
        response.write(oaldHappyPage);
      } else if (path == '/definition/english/take-off') {
        response.headers.contentType =
            ContentType('text', 'html', charset: 'utf-8');
        response.write(oaldTakeOffPage);
      } else if (path == '/definition/english/nosuchword') {
        response.statusCode = HttpStatus.notFound;
        response.write('not here');
      } else if (path == '/definition/english/blocked') {
        response.statusCode = HttpStatus.forbidden;
        response.headers.contentType =
            ContentType('text', 'html', charset: 'utf-8');
        response.write(oaldBlockedPage);
      } else if (path == '/definition/english/searchpage') {
        response.headers.contentType =
            ContentType('text', 'html', charset: 'utf-8');
        response.write(oaldSuggestionPage);
      } else if (path == '/definition/english/plainpage') {
        response.headers.contentType =
            ContentType('text', 'html', charset: 'utf-8');
        response.write(oaldPlainPage);
      } else {
        response.statusCode = HttpStatus.notFound;
        response.write('nope');
      }
      await response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
    if (supportDirectory.existsSync()) {
      await supportDirectory.delete(recursive: true);
    }
  });

  OaldLookupTool toolWith({
    Uri? baseUri,
    Duration cacheTtl = OaldLookupTool.defaultCacheTtl,
    DateTime? now,
  }) =>
      OaldLookupTool(
        baseUri: baseUri ?? Uri.parse('http://127.0.0.1:$port'),
        supportDirectory: () async => supportDirectory,
        clock: () => now ?? fixedNow,
        cacheTtl: cacheTtl,
        fetcher: WebFetcher(
          // The fixture server is loopback, which the production policy refuses
          // by design. The bypass lives in the test.
          hostPolicy: (_) => null,
        ),
      );

  ToolInvocation invoke(Map<String, Object?> arguments) => ToolInvocation(
        toolName: OaldLookupTool.toolName,
        action: OaldLookupTool.toolName,
        arguments: arguments,
      );

  Map<String, Object?> resultOf(ToolResult result) =>
      (result.modelResult! as Map).cast<String, Object?>();

  List<Map<String, Object?>> sensesOf(ToolResult result) => [
        for (final sense in resultOf(result)['senses']! as List)
          (sense as Map).cast<String, Object?>(),
      ];

  List<Map<String, Object?>> familyOf(ToolResult result) => [
        for (final member in resultOf(result)['word_family']! as List)
          (member as Map).cast<String, Object?>(),
      ];

  File cacheFile(String word) => File(
        '${supportDirectory.path}${Platform.pathSeparator}'
        '${OaldLookupTool.cacheDirectoryName}${Platform.pathSeparator}$word.json',
      );

  Future<Map<String, Object?>> cacheJson(String word) async =>
      (jsonDecode(await cacheFile(word).readAsString()) as Map)
          .cast<String, Object?>();

  group('tool contract', () {
    test('name, schema, risk and read-only flags match the read tools', () {
      final tool = toolWith();
      expect(tool.name, 'lookup_oald');
      expect(tool.availableOnCurrentPlatform, isTrue);
      expect(tool.supportedPlatforms, AiToolPlatform.all);
      expect(tool.riskFor('lookup_oald'), ToolRisk.write);
      expect(tool.reversibleFor('lookup_oald'), isTrue);
      expect(tool.readOnly, isTrue);

      final parameters = tool.parameters;
      expect(parameters['type'], 'object');
      final properties =
          (parameters['properties']! as Map).cast<String, Object?>();
      expect(
        properties.keys.toSet(),
        {'word', 'context', 'part_of_speech', 'refresh'},
      );
      expect(parameters['required'], ['word']);
      expect((properties['word']! as Map)['type'], 'string');
      expect((properties['context']! as Map)['type'], 'string');
      expect((properties['refresh']! as Map)['type'], 'boolean');
    });

    test('the description says "source only, no generated definitions"', () {
      final description = toolWith().description;
      expect(description, contains('只作为查词来源'));
      expect(description, contains('不生成释义'));
      expect(description, contains('不能改写释义'));
      expect(description, contains('反爬'));
      expect(description, contains('不要凭记忆编造'));
      expect(description, contains('Oxford Learner'));
    });

    test('it is registered in the app tool list', () {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final registry = ToolRegistry.forApp(
        db: db,
        tasks: TaskRepository(db),
        blocks: TimeBlockRepository(db),
        anki: AnkiRepository(db),
        tags: TagRepository(db),
      );

      expect(registry.byName('lookup_oald'), isA<OaldLookupTool>());
      expect(registry.isReadOnly('lookup_oald'), isTrue);
      final spec =
          registry.modelSpecs.firstWhere((s) => s.name == 'lookup_oald');
      expect(spec.parameters['required'], ['word']);
      expect(spec.description, contains('只作为查词来源'));
      // The existing network tool is still registered and still first.
      expect(registry.byName('fetch_page'), isA<FetchPageTool>());
      expect(registry.forCurrentPlatform.first.name, 'fetch_page');
    });
  });

  group('structured entry', () {
    test('returns the live-shaped page fields, with verbatim definitions',
        () async {
      final result = await toolWith().run(invoke({'word': 'Observe'}));
      expect(result.ok, isTrue, reason: result.error);
      final data = resultOf(result);

      expect(data['word'], 'observe');
      expect(data['part_of_speech'], 'verb');
      expect(
        data['source_url'],
        'http://127.0.0.1:$port/definition/english/observe',
      );
      expect(data['source'], contains('Oxford'));
      expect(data['page_title'], contains('observe verb'));
      expect(data['from_cache'], isFalse);
      expect(data['stale'], isFalse);
      expect(data['cache_status'], 'miss');
      expect(DateTime.tryParse(data['fetched_at']! as String), isNotNull);
      expect(data['content_rule'], contains('不得改写'));
      expect(requestedPaths, ['/definition/english/observe']);

      final senses = sensesOf(result);
      expect(senses, hasLength(4));
      // Exact equality on purpose: the "never rewrite" contract.
      expect(
        senses[0]['definition'],
        'to see or notice somebody/something',
      );
      expect(senses[0]['examples'], ['I observed a light in the distance.']);
      expect(senses[0]['labels'], ['(formal)']);
      expect(senses[0]['patterns'], ['observe somebody/something']);
      expect(senses[0]['grammar'], ['[transitive]']);
      expect(senses[0]['page_sense_number'], '1');
      expect(senses[0]['index'], 1);
      expect(senses[0]['selected'], isFalse);
      expect(senses[1]['definition'],
          'to watch somebody/something carefully, especially to learn more about them');
      expect(senses[1]['selected'], isFalse);

      expect(data['pronunciations'], hasLength(2));
      final family = familyOf(result);
      expect(family, isEmpty, reason: 'observe 页面没有 Word Family 面板');
    });

    test('the Word Family box is surfaced with its notes', () async {
      final result = await toolWith().run(invoke({'word': 'happy'}));
      expect(result.ok, isTrue, reason: result.error);
      final family = familyOf(result);
      expect(family, hasLength(3));
      expect(family[0]['word'], 'happy');
      expect(family[0]['part_of_speech'], 'adjective');
      expect(family[0]['note'], '(≠ unhappy)');
      expect(family[1]['word'], 'happily');
      // Idioms are not main senses; the happy page has one idioms block.
      expect(sensesOf(result), hasLength(3));
      expect(
        sensesOf(result).map((sense) => sense['definition']),
        isNot(contains('very happy')),
      );
    });

    test('a phrasal-verb page returns only the matching phrasal verb', () async {
      final result = await toolWith().run(invoke({'word': 'Take Off'}));
      expect(result.ok, isTrue, reason: result.error);
      expect(requestedPaths, ['/definition/english/take-off']);
      final data = resultOf(result);
      expect(data['word'], 'take off');
      expect(data['part_of_speech'], 'phrasal verb');
      final senses = sensesOf(result);
      expect(senses, hasLength(2));
      expect(senses[0]['definition'], 'to leave the ground and begin to fly');
      expect(
        senses.map((sense) => sense['definition']),
        isNot(contains('to look or behave like an older member of your family')),
      );
    });

    test('no context selects no sense and says so', () async {
      final result = await toolWith().run(invoke({'word': 'observe'}));
      final selection =
          (resultOf(result)['sense_selection']! as Map).cast<String, Object?>();
      expect(selection['rule'], 'no_context');
      expect(selection['matched'], isFalse);
      expect(selection['selected_index'], isNull);
      expect(selection['note'], contains('不替你选'));
    });

    test('a context selects the matching sense by index, text unchanged',
        () async {
      final result = await toolWith().run(invoke({
        'word': 'observe',
        'context': 'All drivers must observe the speed limit on the motorway.',
      }));
      expect(result.ok, isTrue, reason: result.error);
      final selection =
          (resultOf(result)['sense_selection']! as Map).cast<String, Object?>();
      expect(selection['matched'], isTrue);
      expect(selection['rule'], 'context_overlap');
      expect(selection['selected_index'], 4);
      final senses = sensesOf(result);
      expect(senses[3]['selected'], isTrue);
      expect(senses[3]['definition'], 'to obey rules, laws, etc.');
      expect(
        senses[3]['examples'],
        contains('All drivers must observe the speed limit.'),
      );
    });

    test('a context with no overlap selects nothing (no guessing)', () async {
      final result = await toolWith().run(invoke({
        'word': 'observe',
        'context': 'The soup tasted salty and strange.',
      }));
      final selection =
          (resultOf(result)['sense_selection']! as Map).cast<String, Object?>();
      expect(selection['rule'], 'no_match');
      expect(selection['matched'], isFalse);
      expect(selection['selected_index'], isNull);
      expect(selection['note'], contains('没有选义项'));
      expect(sensesOf(result).any((sense) => sense['selected'] == true), isFalse);
    });

    test('a part-of-speech mismatch is reported, not silently switched',
        () async {
      final result = await toolWith().run(invoke({
        'word': 'observe',
        'part_of_speech': 'noun',
      }));
      expect(result.ok, isTrue);
      final notes = (resultOf(result)['notes']! as List).join(' ');
      expect(notes, contains('词性不一致'));
      expect(notes, contains('verb'));
      expect(requestedPaths, hasLength(1));
    });

    test('page text is HTML-decoded but not reworded', () async {
      // The fixture's `.def` contains a typographic apostrophe (`…`) and the
      // `happy` definition a semicolon; both must survive verbatim.
      final result = await toolWith().run(invoke({'word': 'happy'}));
      expect(
        sensesOf(result)[0]['definition'],
        'feeling or showing pleasure; pleased',
      );
    });
  });

  group('cache', () {
    test('the first lookup writes a cache record with source and fetched_at',
        () async {
      await toolWith().run(invoke({'word': 'observe'}));
      expect(cacheFile('observe').existsSync(), isTrue);
      final json = await cacheJson('observe');
      expect(json['version'], OaldLookupTool.cacheVersion);
      expect(json['source'], contains('Oxford'));
      expect(json['source_url'], contains('/definition/english/observe'));
      expect(json['word'], 'observe');
      expect(json['page_title'], contains('observe verb'));
      expect(DateTime.tryParse(json['fetched_at']! as String), fixedNow);
      final entry = (json['entry']! as Map).cast<String, Object?>();
      expect(entry['part_of_speech'], 'verb');
      expect((entry['senses']! as List), hasLength(4));
    });

    test('a second lookup inside the TTL is served from the cache', () async {
      final tool = toolWith();
      final first = await tool.run(invoke({'word': 'observe'}));
      expect(first.ok, isTrue);
      expect(requestedPaths, hasLength(1));

      final second = await tool.run(invoke({'word': 'observe'}));
      expect(second.ok, isTrue);
      expect(requestedPaths, hasLength(1), reason: '缓存命中不应联网');
      final data = resultOf(second);
      expect(data['from_cache'], isTrue);
      expect(data['cache_status'], 'hit');
      expect(data['stale'], isFalse);
      expect(data['fetched_at'], resultOf(first)['fetched_at']);
      expect(data['page_title'], contains('observe verb'));
      expect(second.summary, contains('缓存命中'));
      expect(
        sensesOf(second)[0]['definition'],
        'to see or notice somebody/something',
      );
    });

    test('refresh: true bypasses a fresh cache and re-fetches', () async {
      final tool = toolWith();
      await tool.run(invoke({'word': 'observe'}));
      expect(requestedPaths, hasLength(1));

      final refreshed = await tool.run(invoke({
        'word': 'observe',
        'refresh': true,
      }));
      expect(refreshed.ok, isTrue);
      expect(requestedPaths, hasLength(2));
      expect(resultOf(refreshed)['cache_status'], 'refresh');
      expect(resultOf(refreshed)['from_cache'], isFalse);
    });

    test('a corrupt cache file is a miss, not a source of text', () async {
      final file = cacheFile('observe');
      await file.parent.create(recursive: true);
      await file.writeAsString('{not valid json');

      final result = await toolWith().run(invoke({'word': 'observe'}));
      expect(result.ok, isTrue);
      expect(requestedPaths, hasLength(1), reason: '损坏缓存应重新抓取');
      expect(resultOf(result)['from_cache'], isFalse);
      expect(sensesOf(result).first['definition'], contains('to see or notice'));
    });

    test('an expired cache plus a dead network returns the cache as stale',
        () async {
      final priming = toolWith(now: fixedNow);
      final primed = await priming.run(invoke({'word': 'observe'}));
      expect(primed.ok, isTrue);
      final primedFetchedAt = resultOf(primed)['fetched_at'];

      // A port nothing listens on: a real SocketException.
      final deadServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final deadPort = deadServer.port;
      await deadServer.close(force: true);

      final offline = toolWith(
        baseUri: Uri.parse('http://127.0.0.1:$deadPort'),
        cacheTtl: Duration.zero,
        now: fixedNow.add(const Duration(seconds: 1)),
      );
      final result = await offline.run(invoke({'word': 'observe'}));

      expect(result.ok, isTrue, reason: '有真实缓存时应返回缓存而不是空');
      final data = resultOf(result);
      expect(data['from_cache'], isTrue);
      expect(data['stale'], isTrue);
      expect(data['cache_status'], 'stale_fallback');
      expect(data['fetched_at'], primedFetchedAt);
      expect(data['fetch_error'], contains('网络连接失败'));
      expect(result.summary, contains('联网失败'));
      expect(result.summary, contains('缓存'));
      final notes = (data['notes']! as List).join(' ');
      expect(notes, contains('缓存'));
      expect(
        sensesOf(result)[0]['definition'],
        'to see or notice somebody/something',
      );
    });
  });

  group('failures never invent a definition', () {
    test('404 is an explicit "no such entry", with no modelResult', () async {
      final result = await toolWith().run(invoke({'word': 'nosuchword'}));
      expect(result.ok, isFalse);
      expect(result.modelResult, isNull);
      expect(result.error, contains('404'));
      expect(result.error, contains('没有'));
      expect(result.error, contains('不编造释义'));
      expect(cacheFile('nosuchword').existsSync(), isFalse);
    });

    test('a 403 anti-bot page is an explicit refusal, not an empty entry',
        () async {
      final result = await toolWith().run(invoke({'word': 'blocked'}));
      expect(result.ok, isFalse);
      expect(result.modelResult, isNull);
      expect(result.error, contains('403'));
      expect(result.error, contains('反爬'));
      expect(result.error, contains('不要凭记忆编造'));
    });

    test('a 200 spelling-suggestion page is an explicit "no such word"',
        () async {
      final result = await toolWith().run(invoke({'word': 'searchpage'}));
      expect(result.ok, isFalse);
      expect(result.modelResult, isNull);
      expect(result.error, contains('拼写是否正确'));
      expect(result.error, contains('不编造释义'));
    });

    test('a 200 page that is not an entry is an explicit parse failure',
        () async {
      final result = await toolWith().run(invoke({'word': 'plainpage'}));
      expect(result.ok, isFalse);
      expect(result.modelResult, isNull);
      expect(result.error, contains('词条容器'));
      expect(result.error, contains('不编造释义'));
    });

    test('a network failure is an explicit error when there is no cache',
        () async {
      final deadServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final deadPort = deadServer.port;
      await deadServer.close(force: true);

      final result = await toolWith(
        baseUri: Uri.parse('http://127.0.0.1:$deadPort'),
      ).run(invoke({'word': 'observe'}));
      expect(result.ok, isFalse);
      expect(result.modelResult, isNull);
      expect(result.error, contains('网络连接失败'));
      expect(result.error, contains('不要凭记忆编造'));
    });

    test('a missing or unusable word is a readable argument error', () async {
      final missing = await toolWith().run(invoke({}));
      expect(missing.ok, isFalse);
      expect(missing.error, contains('word'));

      final punctuation = await toolWith().run(invoke({'word': '!!!'}));
      expect(punctuation.ok, isFalse);
      expect(punctuation.error, contains('英文字母'));
      expect(requestedPaths, isEmpty, reason: '坏参数不应联网');
    });
  });
}
