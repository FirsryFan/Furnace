import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/dictionary/oald_entry.dart';
import 'package:furnace/domain/services/dictionary/oald_parser.dart';
import 'package:furnace/domain/services/web/html_document.dart';

import '../../../support/oald_fixtures.dart';

/// These tests pin the two promises the OALD tool makes about content:
///
///  * it reads the page's own strings - definitions, examples, labels, patterns
///    and grammar codes are compared **exactly**, because the rule is "select or
///    omit, never rewrite";
///  * it refuses when the page is not an entry - a block page, a spelling-
///    suggestion page, a search page or a changed layout becomes an explicit
///    failure instead of an invented definition.
///
/// The fixtures are trimmed copies of live OALD markup (see
/// `test/support/oald_fixtures.dart`), including the traps the real pages have:
/// verb-form pronunciations in a collapsed box, Extra Examples in a collapsed
/// box, idioms, and unrelated phrasal verbs.
void main() {
  final sourceUrl = Uri.parse(
    'https://www.oxfordlearnersdictionaries.com/definition/english/observe',
  );

  OaldParseOutcome parse(String html, {String requested = 'observe'}) =>
      parseOaldDefinitionPage(
        document: HtmlDocument.parse(html),
        sourceUrl: sourceUrl,
        requestedWord: requested,
      );

  group('normalizeOaldWord', () {
    test('lower-cases and turns spaces into OALD-style hyphens', () {
      expect(normalizeOaldWord('Observe'), 'observe');
      expect(normalizeOaldWord('  take off '), 'take-off');
      expect(normalizeOaldWord('mother-in-law'), 'mother-in-law');
      expect(normalizeOaldWord("o'clock"), 'o-clock');
      expect(normalizeOaldWord('well--known'), 'well-known');
    });

    test('refuses a word with nothing addressable in it', () {
      expect(normalizeOaldWord(''), isNull);
      expect(normalizeOaldWord('   '), isNull);
      expect(normalizeOaldWord('!!!'), isNull);
      expect(normalizeOaldWord('…'), isNull);
    });
  });

  group('buildOaldDefinitionUrl', () {
    test('builds the production definition URL on the one OALD host', () {
      final url = buildOaldDefinitionUrl('Observe');
      expect(
        url.toString(),
        'https://www.oxfordlearnersdictionaries.com/definition/english/observe',
      );
      expect(url.host, oaldHost);
    });

    test('a multi-word word becomes one path segment', () {
      final url = buildOaldDefinitionUrl('take off');
      expect(
        url.toString(),
        'https://www.oxfordlearnersdictionaries.com/definition/english/take-off',
      );
      expect(url.pathSegments, ['definition', 'english', 'take-off']);
    });

    test('an unaddressable word throws instead of producing a bad URL', () {
      expect(() => buildOaldDefinitionUrl('!!!'), throwsArgumentError);
    });

    test('the base is injectable for the fixture server', () {
      final url = buildOaldDefinitionUrl(
        'observe',
        base: Uri.parse('http://127.0.0.1:9999'),
      );
      expect(url.toString(), 'http://127.0.0.1:9999/definition/english/observe');
    });
  });

  group('parseOaldDefinitionPage', () {
    test('reads headword, part of speech and the headword pronunciation only',
        () {
      final outcome = parse(oaldObservePage);
      expect(outcome.ok, isTrue, reason: outcome.error);
      final entry = outcome.entry!;

      expect(entry.word, 'observe');
      expect(entry.partOfSpeech, 'verb');
      expect(entry.sourceUrl, sourceUrl.toString());
      expect(entry.pronunciations, hasLength(2));
      expect(entry.pronunciations[0].region, 'British');
      expect(entry.pronunciations[0].phonetic, '/əbˈzɜːv/');
      expect(
        entry.pronunciations[0].audioUrl,
        'https://www.oxfordlearnersdictionaries.com/media/observe__gb_2.ogg',
      );
      expect(entry.pronunciations[1].region, 'North American');
      expect(entry.pronunciations[1].phonetic, '/əbˈzɜːrv/');
      // The verb-form pronunciation sits in a `.collapse` box; it must not be
      // reported as a pronunciation of the headword.
      expect(
        entry.pronunciations.map((p) => p.phonetic),
        isNot(contains('/WRONG-VERB-FORM/')),
      );
    });

    test('definitions, examples, labels, patterns and grammar are word for word',
        () {
      final entry = parse(oaldObservePage).entry!;
      expect(entry.senses, hasLength(4));

      final first = entry.senses[0];
      expect(first.definition, 'to see or notice somebody/something');
      expect(first.examples, ['I observed a light in the distance.']);
      expect(first.grammar, ['[transitive]']);
      expect(first.labels, ['(formal)']);
      expect(first.patterns, ['observe somebody/something']);
      expect(first.domain, isNull);
      expect(first.pageSenseNumber, '1');
      // Extra Examples live in a `.collapse`; they are omitted on purpose.
      expect(
        first.examples,
        isNot(contains(
            'She was unaware that she was being observed from the window.')),
      );

      final third = entry.senses[2];
      expect(third.definition, 'to make a remark');
      expect(third.patterns, ['observe that…', '+ speech']);
      expect(third.labels, ['(formal)']);
      expect(entry.senses[3].definition, 'to obey rules, laws, etc.');
      expect(
        entry.senses[3].examples,
        contains('All drivers must observe the speed limit.'),
      );
    });

    test('sense groups carry their domain, and idioms stay out of the senses',
        () {
      final entry = parse(oaldHappyPage, requested: 'happy').entry!;
      expect(entry.word, 'happy');
      expect(entry.partOfSpeech, 'adjective');
      expect(entry.senses, hasLength(3), reason: 'two idioms must not count');
      expect(entry.senses[0].domain, 'feeling/giving pleasure');
      expect(entry.senses[1].domain, 'feeling/giving pleasure');
      expect(entry.senses[2].domain, 'at celebration');
      expect(
        entry.senses.map((sense) => sense.definition),
        isNot(contains('very happy')),
        reason: 'the idiom sense belongs to the idioms block',
      );
    });

    test('the live Word Family box becomes related words with their notes', () {
      final entry = parse(oaldHappyPage, requested: 'happy').entry!;
      expect(entry.wordFamily, hasLength(3));
      expect(entry.wordFamily[0].word, 'happy');
      expect(entry.wordFamily[0].partOfSpeech, 'adjective');
      expect(entry.wordFamily[0].note, '(≠ unhappy)');
      expect(entry.wordFamily[0].url, isNull);
      expect(entry.wordFamily[1].word, 'happily');
      expect(entry.wordFamily[1].partOfSpeech, 'adverb');
      expect(entry.wordFamily[2].word, 'happiness');
      expect(entry.wordFamily[2].partOfSpeech, 'noun');
    });

    test('a page without a Word Family box returns an empty list, never derived',
        () {
      final entry = parse(oaldObservePage).entry!;
      expect(entry.wordFamily, isEmpty);
    });

    test('a phrasal-verb page returns only the requested phrasal verb', () {
      final takeOff = parse(oaldTakeOffPage, requested: 'take off').entry!;
      expect(takeOff.word, 'take off');
      expect(takeOff.partOfSpeech, 'phrasal verb');
      expect(takeOff.senses, hasLength(2));
      expect(takeOff.senses[0].definition, 'to leave the ground and begin to fly');
      expect(takeOff.senses[1].definition,
          'to leave a place, especially in a hurry');
      expect(
        takeOff.senses.map((sense) => sense.definition),
        isNot(contains('to look or behave like an older member of your family')),
        reason: 'that sense belongs to take after, not take off',
      );

      final takeAfter =
          parse(oaldTakeOffPage, requested: 'take after').entry!;
      expect(takeAfter.senses, hasLength(1));
      expect(takeAfter.senses.single.definition,
          'to look or behave like an older member of your family');
    });

    test('a Cloudflare block page is a failure that says so', () {
      final outcome = parse(oaldBlockedPage);
      expect(outcome.ok, isFalse);
      expect(outcome.entry, isNull);
      expect(outcome.error, contains('反爬'));
      expect(outcome.error, contains('不要凭记忆编造'));
    });

    test('the spelling-suggestion page is a "no such word" failure', () {
      final outcome = parse(oaldSuggestionPage, requested: 'zzzznotaword');
      expect(outcome.ok, isFalse);
      expect(outcome.error, contains('没有「zzzznotaword」这个词条'));
      expect(outcome.error, contains('不编造释义'));
    });

    test('a page without an entry container is a failure', () {
      final outcome = parse(oaldPlainPage);
      expect(outcome.ok, isFalse);
      expect(outcome.error, contains('词条容器'));
    });

    test('an entry with no readable sense is a failure, not a stub', () {
      final outcome = parse(oaldNoSensesPage);
      expect(outcome.ok, isFalse);
      expect(outcome.error, contains('没有解析到任何义项'));
      expect(outcome.error, contains('不编造释义'));
    });
  });

  group('selectOaldSense', () {
    late List<OaldSense> senses;

    setUp(() {
      senses = parse(oaldObservePage).entry!.senses;
    });

    test('no context selects nothing and says so', () {
      final selection = selectOaldSense(senses: senses);
      expect(selection.rule, 'no_context');
      expect(selection.matched, isFalse);
      expect(selection.selectedIndex, isNull);
      expect(selection.note, contains('不替你选'));
      expect(selection.scores, [0, 0, 0, 0]);
    });

    test('a sentence about watching selects the watching sense', () {
      final selection = selectOaldSense(
        senses: senses,
        context: 'The police observed the crowd closely at the station.',
      );
      expect(selection.matched, isTrue);
      expect(selection.rule, 'context_overlap');
      expect(selection.selectedIndex, 2);
      expect(selection.scores[1], greaterThan(selection.scores[0]));
    });

    test('a sentence about the speed limit selects the obey sense', () {
      final selection = selectOaldSense(
        senses: senses,
        context: 'All drivers must observe the speed limit on the motorway.',
      );
      expect(selection.matched, isTrue);
      expect(selection.selectedIndex, 4);
      expect(selection.scores[3], greaterThan(selection.scores[0]));
    });

    test('a remark sentence selects the remark sense', () {
      final selection = selectOaldSense(
        senses: senses,
        context: 'She observed that it was getting late and left.',
      );
      expect(selection.matched, isTrue);
      expect(selection.selectedIndex, 3);
    });

    test('a context with no overlap selects nothing (no guessing)', () {
      final selection = selectOaldSense(
        senses: senses,
        context: 'The soup tasted salty and strange.',
      );
      expect(selection.matched, isFalse);
      expect(selection.rule, 'no_match');
      expect(selection.selectedIndex, isNull);
      expect(selection.note, contains('没有选义项'));
      expect(selection.scores, everyElement(0));
    });

    test('selection never edits the dictionary text it points at', () {
      final selection = selectOaldSense(
        senses: senses,
        context: 'The police observed the crowd closely at the station.',
      );
      final chosen = senses[selection.selectedIndex! - 1];
      expect(
        chosen.definition,
        'to watch somebody/something carefully, especially to learn more about them',
      );
      expect(chosen.examples, contains('The police observed the crowd closely.'));
    });
  });

  group('cache JSON', () {
    test('an entry survives toJson/fromJson unchanged', () {
      final entry = parse(oaldObservePage).entry!;
      final restored = OaldEntry.fromJson(entry.toJson());
      expect(restored, isNotNull);
      expect(restored!.word, entry.word);
      expect(restored.partOfSpeech, entry.partOfSpeech);
      expect(restored.sourceUrl, entry.sourceUrl);
      expect(restored.senses, hasLength(entry.senses.length));
      expect(restored.senses[0].definition, entry.senses[0].definition);
      expect(restored.senses[0].examples, entry.senses[0].examples);
      expect(restored.senses[0].labels, entry.senses[0].labels);
      expect(restored.senses[0].patterns, entry.senses[0].patterns);
      expect(restored.senses[0].pageSenseNumber, '1');
      expect(restored.pronunciations, hasLength(entry.pronunciations.length));
    });

    test('a word family item survives toJson/fromJson with its note', () {
      final entry = parse(oaldHappyPage, requested: 'happy').entry!;
      final restored = OaldEntry.fromJson(entry.toJson())!;
      expect(restored.wordFamily, hasLength(3));
      expect(restored.wordFamily.first.note, '(≠ unhappy)');
      expect(restored.wordFamily.first.partOfSpeech, 'adjective');
    });

    test('a corrupt or empty record is refused instead of half-read', () {
      expect(OaldEntry.fromJson(null), isNull);
      expect(OaldEntry.fromJson('not a map'), isNull);
      expect(OaldEntry.fromJson(<String, Object?>{}), isNull);
      expect(
        OaldEntry.fromJson(<String, Object?>{'word': 'x', 'source_url': 'y'}),
        isNull,
        reason: '没有 senses 的条目不能当作词条',
      );
    });
  });
}
