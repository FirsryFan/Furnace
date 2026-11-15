/// The `lookup_oald` tool: Furnace's one standard way to read a word's entry on
/// Oxford Learner's Dictionaries.
///
/// Why this is a tool and not "just let the model fetch the page": the site's
/// definition page is a large, fixed-shape document, and every promise the user
/// made about dictionary content depends on reading the *same* fields the same
/// way every time - headword, part of speech, pronunciations, senses with their
/// example sentences, word family, and the source URL. A model re-parsing HTML
/// per turn cannot guarantee that, and a model asked to "look it up" without a
/// tool quotes its own memory instead.
///
/// The user's rule for this content, enforced by what this file returns and by
/// what it refuses to do:
///
///  * **selective summary / deletion only.** The tool returns the page's own
///    definition text, examples, part of speech and phonetics (verbatim after
///    HTML text extraction); it drops senses it cannot read rather than filling
///    them in. It never rewrites, shortens into a new sentence, translates or
///    "polishes" a dictionary string, and the chat summary carries counts only -
///    not a rewritten definition.
///  * **context is a filter, not a paraphrase.** `context` picks a sense by word
///    overlap; the chosen sense is reported by index, and its text is unchanged.
///  * **failure is failure.** A 404, an anti-bot block page, a network error or a
///    changed page structure becomes a readable tool error; it never becomes an
///    invented definition. A recently cached real entry may be returned when the
///    live fetch fails, and then the result says `stale: true` with the fetch
///    error, because a cached page is evidence and a guess is not.
///
/// The cache is a file under `<appSupport>/oald_cache/<word>.json` (no database
/// schema, no content store): one small JSON record per headword holding the
/// parsed entry plus `fetched_at` / `source` / `source_url`. OALD text is
/// third-party copyrighted material; this is a local, personal lookup cache, not
/// a redistributable copy.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../data/storage/app_storage.dart';
import '../../../domain/services/dictionary/oald_entry.dart';
import '../../../domain/services/dictionary/oald_parser.dart';
import '../../../domain/services/web/html_document.dart';
import '../../../domain/services/web/web_http.dart';
import '../domain/ai_tool.dart';

/// Reads one OALD definition page and returns a structured, verbatim entry.
class OaldLookupTool extends AiTool {
  OaldLookupTool({
    WebFetcher? fetcher,
    Future<Directory> Function()? supportDirectory,
    DateTime Function()? clock,
    this.cacheTtl = defaultCacheTtl,
    Uri? baseUri,
  })  : _fetcher = fetcher ?? WebFetcher(),
        _supportDirectory = supportDirectory ?? AppStorage.supportDirectory,
        _clock = clock ?? DateTime.now,
        _baseUri = baseUri ?? oaldBaseUri;

  /// Stable tool name sent to the provider and used by the agent loop.
  static const String toolName = 'lookup_oald';

  /// Subdirectory of the app support directory holding the per-word cache.
  static const String cacheDirectoryName = 'oald_cache';

  /// How long a cached entry counts as fresh. A month is short enough that a
  /// revised sense eventually comes in, long enough that a vocabulary lesson
  /// does not re-download the same page for every sentence.
  static const Duration defaultCacheTtl = Duration(days: 30);

  /// One call - including the redirect chain - may not take longer than this.
  static const Duration overallTimeout = Duration(seconds: 25);

  /// Format version of the cache record. Bump when the JSON shape changes; an
  /// unknown version is treated as a miss instead of being half-read.
  static const int cacheVersion = 1;

  final WebFetcher _fetcher;
  final Future<Directory> Function() _supportDirectory;
  final DateTime Function() _clock;
  final Duration cacheTtl;
  final Uri _baseUri;

  @override
  String get name => toolName;

  @override
  String get description =>
      '查询一个英语单词/短语在 Oxford Learner\'s Dictionaries（OALD，牛津学习者词典）'
      '网页版里的**真实词条**：词头、词性、英式/美式音标与发音音频、英文释义、例句、词族、来源 URL。'
      '用在：用户问某个英文单词/短语是什么意思、怎么读、怎么用、有哪些词族，'
      '或者你要给一道英语题里的生词标注 OALD 依据时。'
      '**只作为查词来源，不生成释义**：返回的释义、例句、词性、音标都是 OALD 页面原文摘录；'
      '你只能**筛选/省略**（例如只讲某个义项、不列全部例句），'
      '**不能改写释义、例句或词性，也不能翻译后说成 OALD 原文**；中文讲解由你基于原文自己组织，'
      '但要保留英文原句与来源 URL。'
      'word 传单词（可带空格，如 `take off`）；有题干/句子时把句子放进 context，'
      '工具会按 context 与义项原文的词面重叠挑一个义项（只筛选，不改写）；'
      '也可以传 part_of_speech（verb/noun/adjective/adverb/...）作提示，与页面词性不一致时会明说。'
      '结果默认按单词缓存在本机 30 天；refresh: true 强制重新抓取。'
      '**页面没有这个词条、被网站反爬拦截（HTTP 403/429）、网络失败或页面结构变化时，'
      '会返回明确错误——这时不要凭记忆编造 OALD 释义或音标。**';

  @override
  Map<String, Object?> get parameters => {
        'type': 'object',
        'properties': {
          'word': {
            'type': 'string',
            'description': '要查的英语单词或短语，例如 `observe`、`take off`。'
                '大小写和空格会归一化成 OALD 的词条地址。',
          },
          'context': {
            'type': 'string',
            'description': '可选：这个词出现的那句话或题干。提供后工具按与释义/例句原文的词面重叠'
                '挑义项（只筛选，不改写原文）；没有重叠时会明确说未匹配，而不是猜。',
          },
          'part_of_speech': {
            'type': 'string',
            'description': '可选：期望的词性，如 verb / noun / adjective / adverb。'
                '仅作提示：页面词性与它不一致时结果会标出，不会自动切换到其它词性页面。',
          },
          'refresh': {
            'type': 'boolean',
            'description': '可选：true 时忽略本地缓存、重新抓取页面。默认 false。',
          },
        },
        'required': <String>['word'],
      };

  /// Reading is not a risk (D12 v2 has only write/destructive); this pairing is
  /// the same one every read tool uses so `ApprovalEngine` never asks per call.
  @override
  ToolRisk riskFor(String action) => ToolRisk.write;

  @override
  bool reversibleFor(String action) => true;

  @override
  bool get readOnly => true;

  @override
  bool get availableOnCurrentPlatform => true;

  @override
  Future<ToolResult> run(ToolInvocation invocation) async {
    final args = ToolArgs(invocation.arguments);
    final String requested;
    try {
      requested = args.requireString('word');
    } on ToolArgError catch (error) {
      return ToolResult.failure(error.message);
    }
    final slug = normalizeOaldWord(requested);
    if (slug == null) {
      return const ToolResult.failure(
        '`word` 里没有可用的英文字母或数字（只有标点/空白），无法组成 OALD 词条地址。'
        '请传一个真正的英文单词或短语。',
      );
    }
    final context = args.optString('context');
    final requestedPos = args.optString('part_of_speech');
    final refresh = args.optBool('refresh') ?? false;
    final now = _clock().toUtc();

    final cacheFile = await _cacheFile(slug);
    final cached = await _readCache(cacheFile);

    // A fresh cache entry is used without touching the network. `refresh` skips
    // this branch on purpose; a stale record is *kept* so it can still be the
    // fallback below when the live fetch fails.
    if (!refresh && cached != null && !cached.isStale(now, cacheTtl)) {
      return _entryResult(
        entry: cached.entry,
        fetchedAt: cached.fetchedAt,
        pageTitle: cached.pageTitle,
        requestedWord: requested,
        context: context,
        requestedPos: requestedPos,
        fromCache: true,
        cacheStatus: 'hit',
        stale: false,
        fetchError: null,
        extraNotes: const [],
      );
    }

    final url = buildOaldDefinitionUrl(slug, base: _baseUri);
    final notes = <String>[];
    try {
      final page = await _fetchEntry(url, requested, notes);
      final mismatch = _posMismatchNote(requestedPos, page.entry.partOfSpeech);
      if (page.cacheable) {
        final written = await _writeCache(cacheFile, page.entry, fetchedAt: now, pageTitle: page.pageTitle);
        if (!written) {
          notes.add('缓存写入失败：本次结果照常返回，但下次不会命中缓存。');
        }
      }
      if (page.finalUrl.toString() != url.toString()) {
        notes.add('OALD 把地址重定向到了 ${page.finalUrl}。');
      }
      return _entryResult(
        entry: page.entry,
        fetchedAt: now,
        pageTitle: page.pageTitle,
        requestedWord: requested,
        context: context,
        requestedPos: requestedPos,
        fromCache: false,
        cacheStatus: refresh ? 'refresh' : 'miss',
        stale: false,
        fetchError: null,
        extraNotes: [
          ...notes,
          if (mismatch != null) mismatch,
        ],
      );
    } on _OaldPageFailure catch (failure) {
      if (failure.allowStaleFallback && cached != null) {
        return _staleFallback(cached, requested, context, requestedPos, failure.message);
      }
      return ToolResult.failure(failure.message);
    } on Object catch (error) {
      final message = _describeFetchFailure(error);
      if (cached != null) {
        return _staleFallback(cached, requested, context, requestedPos, message);
      }
      return ToolResult.failure(
        '$message\n没有可用的本地缓存，**没有返回任何释义**——不要凭记忆编造 OALD 内容。',
      );
    }
  }

  /// Returns the page's real entry, or throws [_OaldPageFailure] when the page
  /// arrived but is not usable. Transport errors are left to [run], which turns
  /// both into the same stale-cache fallback.
  Future<_FetchedPage> _fetchEntry(
    Uri url,
    String requested,
    List<String> notes,
  ) async {
    final page = await _fetcher.fetch(url).timeout(overallTimeout);
    final status = page.statusCode;
    final sourceUrl = Uri.parse(page.finalUrl);

    if (status == HttpStatus.notFound) {
      throw _OaldPageFailure(
        'OALD 没有「$requested」这个词条（HTTP 404）：${page.finalUrl}。'
        '可能拼写不对或该词不在词典里。**不编造释义。**',
        allowStaleFallback: false,
      );
    }
    if (status == HttpStatus.forbidden ||
        status == HttpStatus.tooManyRequests ||
        status == HttpStatus.serviceUnavailable) {
      throw _OaldPageFailure(
        'OALD 拒绝了这次请求（HTTP $status）：${page.finalUrl}\n'
        '这通常是网站的反爬/Cloudflare 拦截，不是"这个词不存在"。'
        '**没有拿到页面，也没有任何释义可以报告；不要凭记忆编造。**'
        '可以稍后再试，或请用户提供词条页面文本。',
        allowStaleFallback: true,
      );
    }
    if (status < 200 || status >= 300) {
      throw _OaldPageFailure(
        'OALD 返回 HTTP $status：${page.finalUrl}。没有读到词条，不编造释义。',
        allowStaleFallback: true,
      );
    }
    if (page.bodyTruncated) {
      // A truncated page may be missing the tail of the entry, and caching it
      // would freeze that half-page for a month.
      notes.add('响应体被截断（超过 $maxBodyBytes 字节），页面尾部没有读到；'
          '本次结果没有写入缓存。');
    }

    final decoded = decodeBody(page.bytes, page.declaredCharset);
    if (decoded.note != null) {
      notes.add(decoded.note!);
    }
    final document = HtmlDocument.parse(decoded.text);
    final outcome = parseOaldDefinitionPage(
      document: document,
      sourceUrl: sourceUrl,
      requestedWord: requested,
    );
    notes.addAll(outcome.notes);
    final entry = outcome.entry;
    if (entry == null) {
      throw _OaldPageFailure(
        '${outcome.error ?? "OALD 页面没有解析出词条。"}\n'
        '来源：${page.finalUrl}（HTTP $status）。**不编造释义。**',
        allowStaleFallback: true,
      );
    }
    return _FetchedPage(
      entry: entry,
      finalUrl: sourceUrl,
      pageTitle: document.root.title,
      cacheable: !page.bodyTruncated,
    );
  }

  /// Returns a cached entry with every stale/mismatch fact spelled out.
  ToolResult _staleFallback(
    _OaldCacheRecord cached,
    String requested,
    String? context,
    String? requestedPos,
    String fetchError,
  ) {
    return _entryResult(
      entry: cached.entry,
      fetchedAt: cached.fetchedAt,
      pageTitle: cached.pageTitle,
      requestedWord: requested,
      context: context,
      requestedPos: requestedPos,
      fromCache: true,
      cacheStatus: 'stale_fallback',
      stale: true,
      fetchError: fetchError,
      extraNotes: [
        '联网失败，返回的是 ${_isoDate(cached.fetchedAt)} 抓取的缓存；'
            '它不是本次页面的最新内容，引用时请说明这是缓存。',
      ],
    );
  }

  /// The user-facing result of a successful (possibly cached) lookup.
  ToolResult _entryResult({
    required OaldEntry entry,
    required DateTime fetchedAt,
    String? pageTitle,
    required String requestedWord,
    required String? context,
    required String? requestedPos,
    required bool fromCache,
    required String cacheStatus,
    required bool stale,
    required String? fetchError,
    required List<String> extraNotes,
  }) {
    final selection = selectOaldSense(senses: entry.senses, context: context);
    final notes = <String>[
      if (entry.pronunciations.isEmpty)
        '页面没有可解析的音标（不影响释义与例句）。',
      if (entry.wordFamily.isEmpty)
        '页面没有 Word Family 面板，所以词族为空（不是工具推算的）。',
      if (entry.partOfSpeech == null) '页面没有可解析的词性。',
      ...extraNotes,
    ];
    final mismatch = _posMismatchNote(requestedPos, entry.partOfSpeech);
    if (mismatch != null && !notes.contains(mismatch)) {
      notes.add(mismatch);
    }
    // A definition URL can redirect to a different headword (OALD keeps some
    // word forms on another entry). Saying so is the difference between "this is
    // the page I read" and "this is the word you asked for".
    final requestedKey = _phraseKey(requestedWord);
    final entryKey = _phraseKey(entry.word);
    if (requestedKey.isNotEmpty &&
        entryKey.isNotEmpty &&
        requestedKey != entryKey) {
      notes.add('页面词头是「${entry.word}」，与请求的「$requestedWord」不同：'
          'OALD 可能把地址重定向到了另一个词条。引用时以页面词头和 source_url 为准。');
    }

    final senses = <Map<String, Object?>>[
      for (var i = 0; i < entry.senses.length; i++)
        {
          'index': i + 1,
          ...entry.senses[i].toJson(),
          'selected': selection.selectedIndex == i + 1,
          if (context != null && selection.scores.length == entry.senses.length)
            'context_score': selection.scores[i],
        },
    ];

    return ToolResult(
      ok: true,
      summary: _summary(
        entry: entry,
        selection: selection,
        fromCache: fromCache,
        stale: stale,
        fetchedAt: fetchedAt,
      ),
      modelResult: {
        'source': oaldSourceLabel,
        'source_url': entry.sourceUrl,
        if (pageTitle != null && pageTitle.isNotEmpty) 'page_title': pageTitle,
        'requested_word': requestedWord,
        'word': entry.word,
        'part_of_speech': entry.partOfSpeech,
        'pronunciations': [
          for (final pronunciation in entry.pronunciations)
            pronunciation.toJson(),
        ],
        'senses': senses,
        'word_family': [
          for (final member in entry.wordFamily) member.toJson(),
        ],
        'sense_selection': {
          'context_provided': context != null,
          if (context != null) 'context': context,
          'rule': selection.rule,
          'matched': selection.matched,
          'selected_index': selection.selectedIndex,
          if (selection.note != null) 'note': selection.note,
        },
        'fetched_at': fetchedAt.toIso8601String(),
        'from_cache': fromCache,
        'cache_status': cacheStatus,
        'stale': stale,
        if (fetchError != null) 'fetch_error': fetchError,
        'content_rule': 'OALD 原文摘录：只能筛选/省略，不得改写释义、例句、词性；'
            '引用时保留原文与 source_url。',
        if (notes.isNotEmpty) 'notes': notes,
      },
    );
  }

  /// One line for the chat card. Counts and provenance only - never a rewritten
  /// definition (that would be exactly the paraphrase this tool refuses).
  String _summary({
    required OaldEntry entry,
    required OaldSenseSelection selection,
    required bool fromCache,
    required bool stale,
    required DateTime fetchedAt,
  }) {
    final buffer = StringBuffer('OALD「${entry.word}」');
    if (entry.partOfSpeech != null) {
      buffer.write('（${entry.partOfSpeech}）');
    }
    buffer.write('：${entry.senses.length} 个义项');
    final exampleCount =
        entry.senses.fold<int>(0, (sum, sense) => sum + sense.examples.length);
    if (exampleCount > 0) {
      buffer.write('，$exampleCount 条例句');
    }
    if (entry.wordFamily.isNotEmpty) {
      buffer.write('，${entry.wordFamily.length} 个词族');
    }
    if (selection.matched) {
      buffer.write('，按 context 选中第 ${selection.selectedIndex} 个义项（原文未改）');
    } else if (selection.rule == 'no_match') {
      buffer.write('，context 未匹配到义项（未选，不猜）');
    } else {
      buffer.write('，未提供 context（未选义项）');
    }
    if (stale) {
      buffer.write('；联网失败，用的是 ${_isoDate(fetchedAt)} 的缓存');
    } else if (fromCache) {
      buffer.write('；缓存命中（${_isoDate(fetchedAt)}）');
    }
    return buffer.toString();
  }

  /// `<appSupport>/oald_cache/<slug>.json`.
  Future<File> _cacheFile(String slug) async {
    final support = await _supportDirectory();
    return File(p.join(support.path, cacheDirectoryName, '$slug.json'));
  }

  Future<_OaldCacheRecord?> _readCache(File file) async {
    try {
      if (!await file.exists()) {
        return null;
      }
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return null;
      }
      return _OaldCacheRecord.fromJson(decoded.cast<String, Object?>());
    } on FileSystemException {
      return null;
    } on FormatException {
      // A corrupt cache file is a miss, never a source of guesswork.
      return null;
    }
  }

  Future<bool> _writeCache(
    File file,
    OaldEntry entry, {
    required DateTime fetchedAt,
    String? pageTitle,
  }) async {
    try {
      await file.parent.create(recursive: true);
      await file.writeAsString(
        jsonEncode(_OaldCacheRecord(
          fetchedAt: fetchedAt,
          pageTitle: pageTitle,
          entry: entry,
        ).toJson()),
        flush: true,
      );
      return true;
    } on FileSystemException {
      return false;
    }
  }
}

/// One successfully fetched-and-parsed page, before it becomes a [ToolResult].
class _FetchedPage {
  const _FetchedPage({
    required this.entry,
    required this.finalUrl,
    required this.pageTitle,
    required this.cacheable,
  });

  final OaldEntry entry;
  final Uri finalUrl;
  final String pageTitle;

  /// False when the body was cut off, which also means "do not cache it".
  final bool cacheable;
}

/// A page that arrived but cannot be used, with the chat-visible reason.
///
/// [allowStaleFallback] distinguishes "the word does not exist" (404: a cached
/// entry is not a substitute) from "the site or the network failed" (403/5xx/
/// changed markup: a real cached entry is better than nothing, as long as it is
/// labelled stale).
class _OaldPageFailure implements Exception {
  _OaldPageFailure(this.message, {required this.allowStaleFallback});

  final String message;
  final bool allowStaleFallback;
}

/// The on-disk record: the parsed entry plus the facts needed to judge it later.
class _OaldCacheRecord {
  const _OaldCacheRecord({
    required this.fetchedAt,
    required this.entry,
    this.pageTitle,
  });

  final DateTime fetchedAt;
  final OaldEntry entry;
  final String? pageTitle;

  bool isStale(DateTime now, Duration ttl) {
    final age = now.difference(fetchedAt);
    // A clock that moved backwards must not make a record permanently fresh;
    // treating a negative age as stale forces one re-fetch, which is harmless.
    return age.isNegative || age > ttl;
  }

  Map<String, Object?> toJson() => {
        'version': OaldLookupTool.cacheVersion,
        'source': oaldSourceLabel,
        'source_host': oaldHost,
        'source_url': entry.sourceUrl,
        'word': entry.word,
        'fetched_at': fetchedAt.toIso8601String(),
        if (pageTitle != null) 'page_title': pageTitle,
        'entry': entry.toJson(),
      };

  static _OaldCacheRecord? fromJson(Map<String, Object?> raw) {
    if (raw['version'] != OaldLookupTool.cacheVersion) {
      return null;
    }
    final fetchedAt = DateTime.tryParse(raw['fetched_at']?.toString() ?? '');
    if (fetchedAt == null) {
      return null;
    }
    final entry = OaldEntry.fromJson(raw['entry']);
    if (entry == null) {
      return null;
    }
    final title = raw['page_title'];
    return _OaldCacheRecord(
      fetchedAt: fetchedAt.toUtc(),
      entry: entry,
      pageTitle: title is String && title.trim().isNotEmpty ? title.trim() : null,
    );
  }
}

/// The chat-visible reason a live fetch did not happen.
String _describeFetchFailure(Object error) {
  if (error is RefusedHostException) {
    return '拒绝访问该主机：${error.message}';
  }
  if (error is RedirectLimitException) {
    return '重定向异常：${error.message}';
  }
  if (error is TimeoutException) {
    return '请求 OALD 超时（超过 ${OaldLookupTool.overallTimeout.inSeconds} 秒），没有读到内容。';
  }
  if (error is SocketException) {
    return '网络连接失败：${error.message}';
  }
  if (error is HandshakeException) {
    return 'TLS 握手失败：${error.message}';
  }
  if (error is HttpException) {
    return 'HTTP 错误：${error.message}';
  }
  if (error is FormatException) {
    return '页面解码/地址格式错误：${error.message}';
  }
  return '抓取 OALD 失败：$error';
}

/// `2026-11-15` from a timestamp, for the summary line.
String _isoDate(DateTime value) {
  final local = value.toLocal();
  return '${local.year}-${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')}';
}

/// Requested-word comparison key: lower-case, punctuation to spaces, single
/// spaced, so 	ake off and 	ake-off compare equal.
String _phraseKey(String text) {
  var normalized = text.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ');
  normalized = normalized.replaceAll(RegExp(r'\s+'), ' ').trim();
  return normalized;
}

/// Compares the requested part of speech with the page's, returning a note when
/// they clearly disagree. No page is fetched twice: OALD keeps different parts of
/// speech on different entries, and pretending otherwise would be a guess.
String? _posMismatchNote(String? requested, String? actual) {
  if (requested == null) {
    return null;
  }
  final wanted = requested.trim().toLowerCase();
  if (wanted.isEmpty) {
    return null;
  }
  if (actual == null || actual.trim().isEmpty) {
    return '请求的词性是「$requested」，但页面里没有可解析的词性，无法核对。';
  }
  final got = actual.trim().toLowerCase();
  if (got == wanted || got.contains(wanted) || wanted.contains(got)) {
    return null;
  }
  return '词性不一致：请求的是「$requested」，OALD 这个页面是「$actual」。'
      '本工具按 URL 只读这一个词性页，没有替你切换到其它词性页面。';
}
