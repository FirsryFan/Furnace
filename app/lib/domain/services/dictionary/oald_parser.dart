/// Reads an Oxford Learner's Dictionaries definition page into [OaldEntry].
///
/// **What this parser may and may not do** (the user's rule for this tool):
///
///  * it **selects** - one entry out of a page that may also list idioms or other
///    phrasal verbs, one sense out of several, one Word Family panel;
///  * it **omits** - extra-example boxes, collocation boxes, idioms, unrelated
///    phrasal verbs. A sense with no readable definition is dropped rather than
///    filled in;
///  * it **never rewrites** - [OaldSense.definition], examples, labels, patterns,
///    grammar codes, the part of speech and the phonetics are the page's own
///    strings, decoded from HTML but not reworded, shortened into new sentences,
///    translated or re-cased. The one normalisation is the one any reader does:
///    HTML entity decoding and whitespace collapsing
///    (`HtmlDocument.extractElementText`).
///
/// **The selectors below are from the live site, not from memory.** The page
/// structure was inspected on 2026-11-15 with `curl`/Dart fetches of
/// `definition/english/observe`, `happy`, `beauty`, `take-off_1` and a 404 page,
/// saved under the control workspace's `.work/oald-evidence/` (`observe`,
/// `happy`, `take-off_1` were fetched and parsed by the app's own HTTP stack, so
/// this is the markup the tool really sees). The shapes that matter:
///
/// ```
/// #entryContent > .entry
///   .top-container > .top-g > .webtop
///     h1.headword, span.pos, span.phonetics > .phons_br/.phons_n_am > .phon
///     .collapse [unbox=wordfamily] > .body > ul > li > span.p > span.wfw/.wfp/.wfo
///   ol.senses_multiple                       (main senses; li.sense)
///   span.shcut-g > h2.shcut + li.sense       (sense groups)
///   span.pv-g > .top-container .webtop span.pv + ol (other phrasal verbs)
///   div.idioms > span.idm-g > .webtop .idm + ol.sense_single (idioms)
/// ```
///
/// A page that no longer matches is reported as "could not parse"; it never
/// falls back to guessing a definition.
library;

import '../web/html_document.dart';
import 'oald_entry.dart';

/// The result of reading one page: an entry, or the reason there is none.
class OaldParseOutcome {
  const OaldParseOutcome.entry(this.entry, {this.notes = const []}) : error = null;

  const OaldParseOutcome.failure(this.error, {this.notes = const []})
      : entry = null;

  final OaldEntry? entry;
  final String? error;
  final List<String> notes;

  bool get ok => entry != null;
}

/// How the tool picked one sense among several.
///
/// [rule] is a stable machine value (`context_overlap`, `no_context`,
/// `no_match`); [note] is the sentence shown in the tool result. Selection only
/// *filters* - the chosen [OaldSense] keeps the page's own wording.
class OaldSenseSelection {
  const OaldSenseSelection({
    required this.rule,
    required this.matched,
    this.selectedIndex,
    this.note,
    this.scores = const [],
  });

  /// `1`-based index into the entry's sense list; null when nothing was picked.
  final int? selectedIndex;

  /// True only when a context was given **and** it overlapped a sense.
  final bool matched;

  /// `context_overlap` / `no_context` / `no_match`.
  final String rule;

  final String? note;

  /// Per-sense context score, aligned with the sense list (all zeros when no
  /// context was given).
  final List<int> scores;
}

/// Parses [document] into an entry, or explains why it could not.
OaldParseOutcome parseOaldDefinitionPage({
  required HtmlDocument document,
  required Uri sourceUrl,
  required String requestedWord,
}) {
  final notes = <String>[
    if (document.nodesTruncated)
      '页面标签数量超过扫描上限 ${HtmlDocument.defaultMaxNodes}，尾部标记没有解析。',
  ];

  // Cloudflare's block page arrives with 403 and is handled by the tool; if one
  // ever arrives with 200, name it instead of reporting "could not parse".
  if (_looksLikeAntiBotPage(document)) {
    return OaldParseOutcome.failure(
      '返回的是网站的反爬/拦截页面（Cloudflare `Attention Required` 一类），'
      '不是 OALD 词条页。请稍后再试或改用用户提供的文本，**不要凭记忆编造释义**。',
      notes: notes,
    );
  }
  if (_looksLikeSuggestionPage(document)) {
    return OaldParseOutcome.failure(
      'OALD 没有「$requestedWord」这个词条（返回的是"拼写是否正确"的建议页）。'
      '不编造释义。',
      notes: notes,
    );
  }

  final entryRoot = _entryRoot(document);
  if (entryRoot == null) {
    return OaldParseOutcome.failure(
      '页面里没有词条容器（`#entryContent .entry`），不像 OALD 词条页；'
      '页面结构可能变了。不编造释义。',
      notes: notes,
    );
  }

  final header = _mainHeader(document, entryRoot);
  if (header == null) {
    return OaldParseOutcome.failure(
      '页面里没有词条头部（`.webtop` + 非空 `.headword`），'
      '不像 OALD 词条页；页面结构可能变了。不编造释义。',
      notes: notes,
    );
  }

  final word = _optionalText(document, _firstWithClass(header, 'headword'));
  if (word == null || word.isEmpty) {
    return OaldParseOutcome.failure(
      '页面里没有读到词头（`.headword`），页面结构可能变了。不编造释义。',
      notes: notes,
    );
  }

  final partOfSpeech = _optionalText(document, _firstWithClass(header, 'pos'));
  final pronunciations = _parsePronunciations(document, header);
  final senses = _parseSenses(
    document: document,
    entryRoot: entryRoot,
    header: header,
    requestedWord: requestedWord,
    notes: notes,
  );
  if (senses.isEmpty) {
    return OaldParseOutcome.failure(
      '页面里没有解析到任何义项（`.sense` + `.def` 结构可能变了）。'
      '为了不编造释义，这次查询按失败上报。',
      notes: notes,
    );
  }
  final wordFamily = _parseWordFamily(document, sourceUrl);

  return OaldParseOutcome.entry(
    OaldEntry(
      word: word,
      sourceUrl: sourceUrl.toString(),
      partOfSpeech: partOfSpeech,
      pronunciations: pronunciations,
      senses: senses,
      wordFamily: wordFamily,
    ),
    notes: notes,
  );
}

/// Picks one sense from [senses] by word overlap with [context].
///
/// This is a **filter**, not a summary: the returned index points at a sense
/// that keeps the dictionary's own definition. The scoring is deliberately
/// simple and explainable (so a wrong pick can be argued with, and a test can
/// pin it):
///
///  * context words found in the definition: 3 points each;
///  * context words found in an example sentence: 2 points each;
///  * context words found in the grammar / label / pattern / domain text:
///    2 points each;
///  * an example sentence that appears inside the context (or the reverse, for
///    a context of at least three words) as a phrase: 5 points;
///  * common function words are ignored (`the`, `to`, `of`, ...), because every
///    definition contains them and they would score everything equally.
///
/// No context -> nothing is selected (`no_context`): the caller chooses from the
/// complete list rather than being told a "main" meaning the page never
/// singled out. Context with no overlap -> `no_match` with a null index, because
/// picking the first sense anyway would be a guess.
OaldSenseSelection selectOaldSense({
  required List<OaldSense> senses,
  String? context,
}) {
  final scores = List<int>.filled(senses.length, 0);
  final trimmedContext = context?.trim() ?? '';
  if (trimmedContext.isEmpty) {
    return OaldSenseSelection(
      rule: 'no_context',
      matched: false,
      note: '没有提供 context：返回全部义项，不替你选义项。',
      scores: List<int>.filled(senses.length, 0),
    );
  }

  final contextTokens = _contentTokens(trimmedContext);
  final normalizedContext = _normalizeForPhrase(trimmedContext);

  for (var i = 0; i < senses.length; i++) {
    final sense = senses[i];
    final definitionTokens = _contentTokens(sense.definition);
    final exampleTokens = <String>{
      for (final example in sense.examples) ..._contentTokens(example),
    };
    final metaTokens = <String>{
      ..._contentTokens(sense.grammar.join(' ')),
      ..._contentTokens(sense.labels.join(' ')),
      ..._contentTokens(sense.patterns.join(' ')),
      ..._contentTokens(sense.domain ?? ''),
    };

    var score = 0;
    for (final token in contextTokens) {
      if (definitionTokens.contains(token)) {
        score += 3;
      }
      if (exampleTokens.contains(token)) {
        score += 2;
      }
      if (metaTokens.contains(token)) {
        score += 2;
      }
    }

    // A whole example reused inside the user's sentence is the strongest signal
    // there is; phrase containment is checked both ways so "the police observed
    // the crowd" matches an example of "police observed the crowd".
    for (final example in sense.examples) {
      final normalizedExample = _normalizeForPhrase(example);
      if (normalizedExample.length >= 8 &&
          (normalizedContext.contains(normalizedExample) ||
              (contextTokens.length >= 3 &&
                  normalizedExample.contains(normalizedContext)))) {
        score += 5;
        break;
      }
    }
    scores[i] = score;
  }

  var bestIndex = -1;
  var bestScore = 0;
  for (var i = 0; i < scores.length; i++) {
    if (scores[i] > bestScore) {
      bestScore = scores[i];
      bestIndex = i;
    }
  }

  if (bestIndex < 0) {
    return OaldSenseSelection(
      rule: 'no_match',
      matched: false,
      note: 'context 与任何一个义项的释义、例句、标签都没有可匹配的词，'
          '所以没有选义项（不猜）。已返回全部义项供你自己判断。',
      scores: scores,
    );
  }

  return OaldSenseSelection(
    rule: 'context_overlap',
    matched: true,
    selectedIndex: bestIndex + 1,
    note: '按 context 与义项原文的词面重叠选中第 ${bestIndex + 1} 个义项'
        '（只做筛选，义项原文未改动）。',
    scores: scores,
  );
}

/// True when the page is a Cloudflare-style block page rather than an entry.
bool _looksLikeAntiBotPage(HtmlDocument document) {
  final title = document.root.title.toLowerCase();
  final text = document.extractText(document.root, maxChars: 2000).toLowerCase();
  return title.contains('attention required') ||
      text.contains('you have been blocked') ||
      (text.contains('enable cookies') && text.contains('cloudflare'));
}

/// True when the page is OALD's "did you spell it correctly?" suggestion page.
bool _looksLikeSuggestionPage(HtmlDocument document) {
  final title = document.root.title.toLowerCase();
  return title.contains('did you spell it correctly') ||
      title.contains('alternative spellings');
}

// -----------------------------------------------------------------------------
// Entry / header selection.
// -----------------------------------------------------------------------------

/// The main entry container: `#entryContent` then its first `.entry`, or the
/// first `.entry` on the page.
HtmlNode? _entryRoot(HtmlDocument document) {
  final content = _firstWithId(document.root, 'entryContent');
  if (content != null) {
    final entry = _firstWithClass(content, 'entry');
    return entry ?? content;
  }
  return _firstWithClass(document.root, 'entry');
}

/// The entry's own header: a `.webtop` with a non-empty `.headword` that is not
/// inside a phrasal-verb group (`.pv-g`) or an idiom (`.idm-g`).
///
/// On a phrasal-verb page (`take-off_1`) OALD lists the phrasal verb's own
/// header first and then other phrasal verbs of the same base verb in `.pv-g`
/// groups, each with its own (empty-headword) `.webtop`; the first qualifying
/// header is the one the page is about.
HtmlNode? _mainHeader(HtmlDocument document, HtmlNode entryRoot) {
  for (final webtop in _elementsWithClass(entryRoot, 'webtop')) {
    if (_hasAncestorClass(webtop, const {'pv-g', 'idm-g', 'idioms'}, stopAt: entryRoot)) {
      continue;
    }
    final headword = _firstWithClass(webtop, 'headword');
    final text = _optionalText(document, headword);
    if (text != null && text.isNotEmpty) {
      return webtop;
    }
  }
  return null;
}

// -----------------------------------------------------------------------------
// Entry parts.
// -----------------------------------------------------------------------------

List<OaldPronunciation> _parsePronunciations(HtmlDocument document, HtmlNode header) {
  // The headword's pronunciation is the first `.phonetics` that is not inside a
  // collapsed box: verb forms and related entries also carry `.phonetics`, and
  // reading those as the headword's pronunciation would invent IPA the headword
  // does not have.
  HtmlNode? phonetics;
  for (final candidate in _elementsWithClass(header, 'phonetics')) {
    if (_hasAncestorClass(candidate, const {'collapse'}, stopAt: header)) {
      continue;
    }
    phonetics = candidate;
    break;
  }
  if (phonetics == null) {
    return const [];
  }

  final out = <OaldPronunciation>[];
  final seen = <String>{};

  void add({String? region, String? phonetic, String? audio}) {
    if (phonetic == null && audio == null) {
      return;
    }
    final key = '${region ?? ''}|${phonetic ?? ''}|${audio ?? ''}';
    if (!seen.add(key)) {
      return;
    }
    out.add(OaldPronunciation(
      region: region,
      phonetic: phonetic,
      audioUrl: audio,
    ));
  }

  // Shape 1: labelled region containers (`.phons_br` / `.phons_n_am`), which is
  // how the page itself says which pronunciation is which.
  final regionContainers = _descendantElements(phonetics).where((node) {
    final classes = node.classNames;
    return classes.contains('phons_br') ||
        classes.contains('phons_n_am') ||
        _attribute(node, 'geo') == 'br' ||
        _attribute(node, 'geo') == 'n_am';
  }).toList();
  for (final container in regionContainers) {
    add(
      region: _regionOf(container),
      phonetic: _optionalText(document, _firstWithClass(container, 'phon')),
      audio: _audioOf(container),
    );
  }

  // Shape 2: `.phon` without a labelled container. Region stays null unless an
  // ancestor states it - the order of two phonetics is not proof of BrE/NAmE.
  if (out.isEmpty) {
    for (final phon in _elementsWithClass(phonetics, 'phon')) {
      add(
        region: _regionOf(phon),
        phonetic: _optionalText(document, phon),
        audio: _audioOf(phon.parent ?? phonetics),
      );
    }
  }
  return out;
}

String? _regionOf(HtmlNode node) {
  HtmlNode? current = node;
  while (current != null) {
    final classes = current.classNames;
    final geo = _attribute(current, 'geo');
    if (classes.contains('phons_br') || geo == 'br') {
      return 'British';
    }
    if (classes.contains('phons_n_am') || geo == 'n_am') {
      return 'North American';
    }
    current = current.parent;
  }
  return null;
}

/// The audio URL a pronunciation container advertises (`data-src-ogg` first,
/// then `data-src-mp3`), returned as the page wrote it.
String? _audioOf(HtmlNode container) {
  final candidates = <HtmlNode>[
    container,
    ..._descendantElements(container),
  ];
  for (final node in candidates) {
    final ogg = _attribute(node, 'data-src-ogg');
    if (ogg != null) {
      return ogg;
    }
  }
  for (final node in candidates) {
    final mp3 = _attribute(node, 'data-src-mp3');
    if (mp3 != null) {
      return mp3;
    }
  }
  return null;
}

List<OaldSense> _parseSenses({
  required HtmlDocument document,
  required HtmlNode entryRoot,
  required HtmlNode header,
  required String requestedWord,
  required List<String> notes,
}) {
  final senseLists = _selectSenseLists(
    document: document,
    entryRoot: entryRoot,
    header: header,
    requestedWord: requestedWord,
    notes: notes,
  );

  final senseNodes = <HtmlNode>[];
  for (final list in senseLists) {
    final inner = _elementsWithClass(list, 'sense').toList();
    if (inner.isEmpty && _firstWithClass(list, 'def') != null) {
      // A `.sense_single` list can hold the definition on the wrapper itself.
      senseNodes.add(list);
    } else {
      senseNodes.addAll(inner);
    }
  }

  final senses = <OaldSense>[];
  var skipped = 0;
  final seenNodes = <HtmlNode>{};
  for (final senseNode in senseNodes) {
    if (!seenNodes.add(senseNode)) {
      continue;
    }
    final definition = _optionalText(document, _firstWithClass(senseNode, 'def'));
    if (definition == null) {
      // Dropping is allowed; inventing is not.
      skipped++;
      continue;
    }
    senses.add(OaldSense(
      definition: definition,
      examples: _examplesOf(document, senseNode),
      grammar: _textsOf(
        document,
        senseNode,
        'grammar',
        // The patterns box repeats grammar inside `.collapse`; the sense's own
        // code is outside it.
        skipCollapsed: true,
      ),
      labels: _textsOf(document, senseNode, 'labels', skipCollapsed: false),
      patterns: _textsOf(document, senseNode, 'cf', skipCollapsed: true),
      domain: _domainOf(document, senseNode),
      pageSenseNumber: _attribute(senseNode, 'sensenum'),
    ));
  }
  if (skipped > 0) {
    notes.add('有 $skipped 个义项块没有可读的 `.def` 释义，已跳过（不补写）。');
  }
  return senses;
}

/// Chooses which `ol.senses_multiple` / `ol.sense_single` lists belong to the
/// requested word.
///
///  * normal entries: the lists not inside `.idioms` and not inside `.pv-g`;
///  * phrasal-verb pages: the `.pv-g` group whose `.pv` text matches the
///    requested word (the page groups several phrasal verbs of the base verb);
///  * a phrasal-verb page whose main headword matches the request but whose
///    `.pv` text does not: the first group (the page's own headword).
List<HtmlNode> _selectSenseLists({
  required HtmlDocument document,
  required HtmlNode entryRoot,
  required HtmlNode header,
  required String requestedWord,
  required List<String> notes,
}) {
  final lists = _descendantElements(entryRoot).where((node) {
    final classes = node.classNames;
    return node.tag == 'ol' &&
        (classes.contains('senses_multiple') || classes.contains('sense_single')) &&
        !_hasAncestorClass(node, const {'idioms', 'idm-g'}, stopAt: entryRoot);
  }).toList();

  final pvGroups = _elementsWithClass(entryRoot, 'pv-g').toList();
  if (pvGroups.isEmpty) {
    return lists;
  }

  final requestedKey = _phraseKey(requestedWord);
  String? headwordKey;
  final headword = _firstWithClass(header, 'headword');
  if (headword != null) {
    final text = _optionalText(document, headword);
    headwordKey = text == null ? null : _phraseKey(text);
  }

  HtmlNode? bestGroup;
  for (final group in pvGroups) {
    final pv = _firstWithClass(group, 'pv');
    final text = _optionalText(document, pv);
    if (text == null) {
      continue;
    }
    final key = _phraseKey(text);
    if (key == requestedKey) {
      bestGroup = group;
      break;
    }
    // The page's own headword is the fallback only when the request *is* that
    // headword (a URL that resolved to this entry); otherwise "take after" must
    // not be answered with the "take off" group just because it comes first.
    if (requestedKey.isNotEmpty &&
        requestedKey == headwordKey &&
        key == headwordKey) {
      bestGroup ??= group;
    }
  }

  if (bestGroup == null) {
    notes.add('页面有多个短语动词分组，但没有匹配到「$requestedWord」；'
        '按页面的第一个分组返回。引用时请核对 source_url。');
    return _senseListsIn(pvGroups.first);
  }
  final groupLists = _senseListsIn(bestGroup);
  if (groupLists.isEmpty) {
    notes.add('这个词条页有多个短语动词分组，但匹配到的分组里没有义项列表。');
    return lists;
  }
  return groupLists;
}

/// Sense lists directly reachable from [scope].
List<HtmlNode> _senseListsIn(HtmlNode scope) => _descendantElements(scope)
    .where((node) {
      final classes = node.classNames;
      return node.tag == 'ol' &&
          (classes.contains('senses_multiple') || classes.contains('sense_single'));
    })
    .toList();

/// Example sentences under [senseNode] that are the sense's own examples.
///
/// Extra Examples / Oxford Collocations / Synonyms boxes live in a `.collapse`
/// inside the sense; they are deliberately omitted (the user's rule allows
/// selective deletion) because they can multiply one sense into twenty lines.
List<String> _examplesOf(HtmlDocument document, HtmlNode senseNode) {
  final examples = <String>[];
  final seen = <String>{};
  for (final container in _elementsWithClass(senseNode, 'examples')) {
    if (_hasAncestorClass(container, const {'collapse'}, stopAt: senseNode) ||
        _hasAncestorClass(container, const {'idioms', 'idm-g'}, stopAt: senseNode)) {
      continue;
    }
    for (final node in _descendantElements(container)) {
      final isExample = node.classNames.contains('x') || node.classNames.contains('unx');
      if (!isExample || _nearestSense(node) != senseNode) {
        continue;
      }
      final text = _optionalText(document, node);
      if (text == null || text.isEmpty || !seen.add(text)) {
        continue;
      }
      examples.add(text);
    }
  }
  return examples;
}

/// Texts of descendant elements carrying [className] that belong to [senseNode].
List<String> _textsOf(
  HtmlDocument document,
  HtmlNode senseNode,
  String className, {
  required bool skipCollapsed,
}) {
  final out = <String>[];
  for (final node in _elementsWithClass(senseNode, className)) {
    if (_nearestSense(node) != senseNode) {
      continue;
    }
    if (skipCollapsed &&
        _hasAncestorClass(node, const {'collapse', 'patterns'}, stopAt: senseNode)) {
      continue;
    }
    final text = _optionalText(document, node);
    if (text != null && !out.contains(text)) {
      out.add(text);
    }
  }
  return out;
}

/// The semantic-domain shortcut (`shcut`) that groups this sense, if any.
String? _domainOf(HtmlDocument document, HtmlNode senseNode) {
  HtmlNode? current = senseNode.parent;
  while (current != null) {
    if (current.classNames.contains('shcut-g')) {
      return _optionalText(document, _firstWithClass(current, 'shcut'));
    }
    current = current.parent;
  }
  return null;
}

// -----------------------------------------------------------------------------
// Word Family.
// -----------------------------------------------------------------------------

/// Related forms from the page's Word Family panel.
///
/// The live site's panel is `<div class="collapse"><span class="unbox"
/// unbox="wordfamily"><span class="box_title">Word Family</span><span
/// class="body"><ul><li><span class="p"><span class="wfw">happy</span> <span
/// class="wfp">adjective</span> <span class="wfo">(≠ unhappy)</span>...` - no
/// links, and it is inside the entry's `.webtop`.
///
/// Older shapes (a `wordfampanel` class, a `dt`/`dd` side panel, a heading with
/// links) are still accepted, but nothing is derived from the headword: no panel
/// on the page means an empty list, because a word like `observe` must not get
/// `observation` appended by the app.
List<OaldWordFamilyItem> _parseWordFamily(HtmlDocument document, Uri sourceUrl) {
  final items = <OaldWordFamilyItem>[];
  final seen = <String>{};

  void addItem({
    required String word,
    String? partOfSpeech,
    String? note,
    String? url,
  }) {
    if (!seen.add('${word.toLowerCase()}|${partOfSpeech ?? ''}')) {
      return;
    }
    items.add(OaldWordFamilyItem(
      word: word,
      partOfSpeech: partOfSpeech,
      note: note,
      url: url,
    ));
  }

  // Live shape: the `unbox="wordfamily"` box with `.wfw` / `.wfp` / `.wfo`.
  final panels = _descendantElements(document.root)
      .where((node) =>
          (_attribute(node, 'unbox') ?? '').toLowerCase().contains('wordfamily'))
      .toList();
  for (final panel in panels) {
    for (final wordNode in _elementsWithClass(panel, 'wfw')) {
      final word = _optionalText(document, wordNode);
      if (word == null) {
        continue;
      }
      final item = _wordFamilyRowFor(wordNode, panel);
      addItem(
        word: word,
        partOfSpeech: item == null ? null : _optionalText(document, _firstWithClass(item, 'wfp')),
        note: item == null ? null : _optionalText(document, _firstWithClass(item, 'wfo')),
        url: _linkUrlOf(wordNode, sourceUrl),
      );
    }
  }
  if (items.isNotEmpty) {
    return items;
  }

  return items;
}


/// The `li`/`.p` row that carries a `.wfw` word, for its `.wfp`/`.wfo` siblings.
HtmlNode? _wordFamilyRowFor(HtmlNode wordNode, HtmlNode panel) {
  HtmlNode? current = wordNode.parent;
  while (current != null && !identical(current, panel)) {
    if (current.tag == 'li' || current.classNames.contains('p')) {
      return current;
    }
    current = current.parent;
  }
  return null;
}

/// The URL a Word Family entry links to, when the page links it.
String? _linkUrlOf(HtmlNode wordNode, Uri sourceUrl) {
  HtmlNode? current = wordNode;
  while (current != null) {
    if (current.tag == 'a') {
      return _resolveUrl(sourceUrl, _attribute(current, 'href'));
    }
    current = current.parent;
  }
  return null;
}


String? _resolveUrl(Uri sourceUrl, String? href) {
  if (href == null || href.trim().isEmpty) {
    return null;
  }
  final resolved = sourceUrl.resolve(href.trim());
  if (resolved.scheme != 'http' && resolved.scheme != 'https') {
    return null;
  }
  return resolved.toString();
}

// -----------------------------------------------------------------------------
// Text and node helpers.
// -----------------------------------------------------------------------------


String? _optionalText(HtmlDocument document, HtmlNode? node) {
  if (node == null) {
    return null;
  }
  final text = document.extractElementText(node, maxChars: 2000);
  return text.isEmpty ? null : text;
}


HtmlNode? _firstWithClass(HtmlNode root, String className) {
  for (final node in _descendantElements(root)) {
    if (node.classNames.contains(className)) {
      return node;
    }
  }
  return null;
}

HtmlNode? _firstWithId(HtmlNode root, String id) {
  for (final node in _descendantElements(root)) {
    if (_attribute(node, 'id') == id) {
      return node;
    }
  }
  return null;
}

Iterable<HtmlNode> _elementsWithClass(HtmlNode root, String className) =>
    _descendantElements(root).where((node) => node.classNames.contains(className));

String? _attribute(HtmlNode node, String name) {
  final value = node.attribute(name);
  return value == null || value.trim().isEmpty ? null : value.trim();
}

HtmlNode? _nearestSense(HtmlNode node) {
  HtmlNode? current = node.parent;
  while (current != null) {
    if (current.classNames.contains('sense') ||
        current.classNames.contains('sense_single')) {
      return current;
    }
    current = current.parent;
  }
  return null;
}

bool _hasAncestorClass(
  HtmlNode node,
  Set<String> classes, {
  required HtmlNode stopAt,
}) {
  HtmlNode? current = node.parent;
  while (current != null) {
    if (current.classNames.any(classes.contains)) {
      return true;
    }
    if (identical(current, stopAt)) {
      return false;
    }
    current = current.parent;
  }
  return false;
}

/// Every element below [root], in document order (root itself excluded).
Iterable<HtmlNode> _descendantElements(HtmlNode root) sync* {
  for (final child in root.children) {
    if (!child.isElement) {
      continue;
    }
    yield child;
    yield* _descendantElements(child);
  }
}

// -----------------------------------------------------------------------------
// Context matching.
// -----------------------------------------------------------------------------

/// Function words that appear in almost every definition; counting them would
/// make every sense score the same.
const Set<String> _stopWords = {
  'a', 'about', 'after', 'all', 'also', 'an', 'and', 'any', 'are', 'as', 'at',
  'be', 'been', 'before', 'being', 'but', 'by', 'can', 'could', 'do', 'does',
  'did', 'for', 'from', 'had', 'has', 'have', 'he', 'her', 'here', 'him', 'his',
  'how', 'i', 'if', 'in', 'into', 'is', 'it', 'its', 'may', 'might', 'more',
  'most', 'must', 'my', 'no', 'not', 'of', 'on', 'or', 'other', 'our', 'out',
  'over', 'shall', 'she', 'should', 'so', 'some', 'such', 'than', 'that', 'the',
  'their', 'them', 'then', 'there', 'these', 'they', 'this', 'those', 'to',
  'too', 'under', 'up', 'us', 'very', 'was', 'we', 'were', 'what', 'when',
  'which', 'while', 'who', 'whom', 'why', 'will', 'with', 'would', 'you',
  'your',
};

/// Lower-case content words. Punctuation is removed for matching only; the
/// stored dictionary text is untouched.
Set<String> _contentTokens(String text) {
  final out = <String>{};
  for (final raw in text.toLowerCase().split(RegExp(r"[^a-z0-9']+"))) {
    final token = raw.replaceAll(RegExp(r"^'+|'+$"), '');
    if (token.isEmpty || _stopWords.contains(token) || token.length < 2) {
      continue;
    }
    out.add(token);
  }
  return out;
}

/// A phrase form used for containment checks and for matching a requested word
/// to a phrasal-verb group: lower-case, punctuation to spaces, single-spaced.
String _normalizeForPhrase(String text) {
  var normalized = text.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ');
  normalized = normalized.replaceAll(RegExp(r'\s+'), ' ').trim();
  return normalized;
}

/// Requested-word/phrasal-verb comparison key (hyphen and space are equal).
String _phraseKey(String text) => _normalizeForPhrase(text);
