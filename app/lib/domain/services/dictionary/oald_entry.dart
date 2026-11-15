/// The data the OALD lookup tool returns: one Oxford Learner's Dictionaries
/// entry, split into the fields the agent is allowed to use.
///
/// **Evidence rule for everything in here: the text is the page's text.** The
/// user's rule for this tool is "select or omit, never rewrite": a definition,
/// an example, a part of speech and a phonetic are stored exactly as the page
/// spells them (after the HTML text extraction every reader of a page performs:
/// entity decoding and whitespace collapsing). Nothing in this file paraphrases,
/// shortens (beyond an explicit truncation marker), translates or re-cases a
/// dictionary string. That is why the model-facing result says "OALD 原文摘录"
/// and why the chat-side summary only reports counts, never a rewritten
/// definition.
///
/// The OALD page itself is third-party copyrighted content: the on-disk cache is
/// a local lookup cache, not a redistributable copy
/// (`docs/...` and `OALD-TOOL-2026-11-15.md` in the control workspace state the
/// limits). Keeping the data model verbatim also keeps the "source" honest:
/// whoever reads the entry can check it against [OaldEntry.sourceUrl].
library;

/// Where an entry came from. Shown to the model and the user on every result.
const String oaldSourceLabel = "Oxford Learner's Dictionaries (OALD)";

/// The only host this tool reads. Kept as a constant (not derived) so a URL
/// built for a word can never point anywhere else.
const String oaldHost = 'www.oxfordlearnersdictionaries.com';

/// The base every definition URL is built on.
final Uri oaldBaseUri = Uri.https(oaldHost, '/');

/// Turns a word a model was given into the path segment OALD uses.
///
/// The rules, and why each exists:
///
///  * lower-case and trim - OALD paths are lower-case (`observe`, not `Observe`);
///  * whitespace, apostrophes, punctuation and underscores become `-`, so
///    `take off` becomes `take-off` and `o'clock` becomes `o-clock` (the same
///    spelling family OALD uses for hyphenated headwords);
///  * repeated `-` collapse to one, and leading/trailing `-` are dropped;
///  * only `a-z`, `0-9` and `-` survive - that is what makes the result safe
///    both as a URL path segment and as a cache file name (no `/`, no `..`);
///  * an empty result returns null: the tool must refuse a "word" that is only
///    punctuation instead of inventing a URL.
///
/// The transformation is deliberately mechanical and lossy. A word whose
/// diacritics were stripped (`café` -> `caf`) will not find the entry; the tool
/// reports "not found" rather than guessing a different word.
String? normalizeOaldWord(String raw) {
  final lower = raw.trim().toLowerCase();
  if (lower.isEmpty) {
    return null;
  }
  final buffer = StringBuffer();
  var pendingDash = false;
  for (var i = 0; i < lower.length; i++) {
    final code = lower.codeUnitAt(i);
    final isLetter = code >= 0x61 && code <= 0x7a;
    final isDigit = code >= 0x30 && code <= 0x39;
    if (isLetter || isDigit) {
      if (pendingDash && buffer.isNotEmpty) {
        buffer.write('-');
      }
      pendingDash = false;
      buffer.writeCharCode(code);
      continue;
    }
    // Anything that is not an ASCII letter or digit is a separator. The dash is
    // already the separator OALD uses, so it is not written twice.
    pendingDash = true;
  }
  final slug = buffer.toString();
  return slug.isEmpty ? null : slug;
}

/// The definition URL for [word] under [base] (the site root by default).
///
/// [base] is injectable only so the tests can point the tool at an in-process
/// fixture server; production passes nothing and gets the one OALD host.
Uri buildOaldDefinitionUrl(String word, {Uri? base}) {
  final slug = normalizeOaldWord(word);
  if (slug == null) {
    throw ArgumentError.value(word, 'word', 'no letters or digits to build a URL from');
  }
  final root = base ?? oaldBaseUri;
  return root.replace(
    pathSegments: [
      ...root.pathSegments.where((segment) => segment.isNotEmpty),
      'definition',
      'english',
      slug,
    ],
  );
}

/// One pronunciation as the page writes it.
class OaldPronunciation {
  const OaldPronunciation({
    this.region,
    this.phonetic,
    this.audioUrl,
  });

  /// `British` / `North American`, or null when the page did not say which.
  ///
  /// Never guessed from order: a page with one unlabelled phonetic produces one
  /// pronunciation with a null region, because naming a region it did not state
  /// would be inventing a fact about the entry.
  final String? region;

  /// The IPA string exactly as printed (`/əbˈzɜːv/`), or null.
  final String? phonetic;

  /// The audio file URL the page advertises, or null.
  final String? audioUrl;

  bool get isEmpty => phonetic == null && audioUrl == null;

  Map<String, Object?> toJson() => {
        if (region != null) 'region': region,
        if (phonetic != null) 'phonetic': phonetic,
        if (audioUrl != null) 'audio_url': audioUrl,
      };

  static OaldPronunciation? fromJson(Object? raw) {
    final map = _asMap(raw);
    if (map == null) {
      return null;
    }
    final phonetic = _asString(map['phonetic']);
    final audio = _asString(map['audio_url']);
    if (phonetic == null && audio == null) {
      return null;
    }
    return OaldPronunciation(
      region: _asString(map['region']),
      phonetic: phonetic,
      audioUrl: audio,
    );
  }
}

/// One numbered sense of the entry, verbatim.
class OaldSense {
  const OaldSense({
    required this.definition,
    this.examples = const [],
    this.grammar = const [],
    this.labels = const [],
    this.patterns = const [],
    this.domain,
    this.pageSenseNumber,
  });

  /// The English definition exactly as printed (this is the field the user
  /// reads; it is never reworded, shortened or translated).
  final String definition;

  /// Example sentences exactly as printed, in page order.
  final List<String> examples;

  /// Grammar codes as printed, e.g. `[transitive]`, `[countable]`.
  final List<String> grammar;

  /// Register/subject labels as printed, e.g. `(formal)`, `(informal)`.
  final List<String> labels;

  /// The page's syntactic patterns for this sense, as printed, e.g.
  /// `observe somebody/something`, `+ speech`.
  final List<String> patterns;

  /// The semantic-domain shortcut when the page groups senses under one
  /// (`shcut`), e.g. `feeling/giving pleasure`; null when not grouped.
  final String? domain;

  /// The page's own sense number (`sensenum` attribute), when it has one.
  /// Kept separate from the list position because ids/numbering are the page's
  /// facts, not ours.
  final String? pageSenseNumber;

  bool get isEmpty => definition.isEmpty;

  Map<String, Object?> toJson() => {
        'definition': definition,
        if (examples.isNotEmpty) 'examples': examples,
        if (grammar.isNotEmpty) 'grammar': grammar,
        if (labels.isNotEmpty) 'labels': labels,
        if (patterns.isNotEmpty) 'patterns': patterns,
        if (domain != null) 'domain': domain,
        if (pageSenseNumber != null) 'page_sense_number': pageSenseNumber,
      };

  static OaldSense? fromJson(Object? raw) {
    final map = _asMap(raw);
    if (map == null) {
      return null;
    }
    final definition = _asString(map['definition']);
    if (definition == null || definition.isEmpty) {
      return null;
    }
    return OaldSense(
      definition: definition,
      examples: _asStringList(map['examples']),
      grammar: _asStringList(map['grammar']),
      labels: _asStringList(map['labels']),
      patterns: _asStringList(map['patterns']),
      domain: _asString(map['domain']),
      pageSenseNumber: _asString(map['page_sense_number']),
    );
  }
}

/// One word in the page's Word Family panel.
class OaldWordFamilyItem {
  const OaldWordFamilyItem({
    required this.word,
    this.partOfSpeech,
    this.note,
    this.url,
  });

  /// The related word as printed.
  final String word;

  /// Its part of speech as printed next to the word, when the page shows one.
  final String? partOfSpeech;

  /// The page's own parenthetical note for the member (`(≠ unhappy)`), when
  /// shown. Verbatim, never interpreted.
  final String? note;

  /// Absolute URL of the related entry, when the page links it.
  final String? url;

  Map<String, Object?> toJson() => {
        'word': word,
        if (partOfSpeech != null) 'part_of_speech': partOfSpeech,
        if (note != null) 'note': note,
        if (url != null) 'url': url,
      };

  static OaldWordFamilyItem? fromJson(Object? raw) {
    final map = _asMap(raw);
    if (map == null) {
      return null;
    }
    final word = _asString(map['word']);
    if (word == null || word.isEmpty) {
      return null;
    }
    return OaldWordFamilyItem(
      word: word,
      partOfSpeech: _asString(map['part_of_speech']),
      note: _asString(map['note']),
      url: _asString(map['url']),
    );
  }
}

/// One parsed OALD entry.
class OaldEntry {
  const OaldEntry({
    required this.word,
    required this.sourceUrl,
    this.partOfSpeech,
    this.pronunciations = const [],
    this.senses = const [],
    this.wordFamily = const [],
  });

  /// The headword exactly as printed on the page (not the requested spelling).
  final String word;

  /// The entry URL the text came from. Every result carries it so a definition
  /// can always be checked against its source.
  final String sourceUrl;

  /// The page's part of speech exactly as printed (`verb`, `noun`, ...), or null.
  final String? partOfSpeech;

  final List<OaldPronunciation> pronunciations;
  final List<OaldSense> senses;

  /// Related forms from the page's Word Family panel; empty when the page has
  /// none. Never derived from the headword by the app.
  final List<OaldWordFamilyItem> wordFamily;

  Map<String, Object?> toJson() => {
        'word': word,
        'source_url': sourceUrl,
        if (partOfSpeech != null) 'part_of_speech': partOfSpeech,
        if (pronunciations.isNotEmpty)
          'pronunciations': [
            for (final pronunciation in pronunciations) pronunciation.toJson(),
          ],
        'senses': [for (final sense in senses) sense.toJson()],
        if (wordFamily.isNotEmpty)
          'word_family': [for (final item in wordFamily) item.toJson()],
      };

  /// Reads a cache record back. Returns null for anything that is not a usable
  /// entry, so a corrupt cache file is a cache miss and never a source of made-up
  /// data.
  static OaldEntry? fromJson(Object? raw) {
    final map = _asMap(raw);
    if (map == null) {
      return null;
    }
    final word = _asString(map['word']);
    final sourceUrl = _asString(map['source_url']);
    if (word == null || word.isEmpty || sourceUrl == null || sourceUrl.isEmpty) {
      return null;
    }
    final senses = <OaldSense>[];
    for (final item in _asList(map['senses'])) {
      final sense = OaldSense.fromJson(item);
      if (sense != null) {
        senses.add(sense);
      }
    }
    if (senses.isEmpty) {
      return null;
    }
    final pronunciations = <OaldPronunciation>[];
    for (final item in _asList(map['pronunciations'])) {
      final pronunciation = OaldPronunciation.fromJson(item);
      if (pronunciation != null) {
        pronunciations.add(pronunciation);
      }
    }
    final family = <OaldWordFamilyItem>[];
    for (final item in _asList(map['word_family'])) {
      final member = OaldWordFamilyItem.fromJson(item);
      if (member != null) {
        family.add(member);
      }
    }
    return OaldEntry(
      word: word,
      sourceUrl: sourceUrl,
      partOfSpeech: _asString(map['part_of_speech']),
      pronunciations: pronunciations,
      senses: senses,
      wordFamily: family,
    );
  }
}

// -----------------------------------------------------------------------------
// JSON helpers.
//
// Deliberately tolerant: a cache file written by an older build (or edited by
// hand) must degrade to "miss/empty field", never throw in the middle of a
// lookup. A malformed *entry* is still refused by [OaldEntry.fromJson].
// -----------------------------------------------------------------------------

Map<String, Object?>? _asMap(Object? raw) {
  if (raw is Map<String, Object?>) {
    return raw;
  }
  if (raw is Map) {
    return raw.cast<String, Object?>();
  }
  return null;
}

List<Object?> _asList(Object? raw) => raw is List ? raw : const [];

String? _asString(Object? raw) {
  if (raw is String) {
    final trimmed = raw.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
  if (raw == null) {
    return null;
  }
  final text = raw.toString().trim();
  return text.isEmpty ? null : text;
}

List<String> _asStringList(Object? raw) {
  if (raw is! List) {
    return const [];
  }
  final out = <String>[];
  for (final item in raw) {
    final text = _asString(item);
    if (text != null) {
      out.add(text);
    }
  }
  return out;
}
