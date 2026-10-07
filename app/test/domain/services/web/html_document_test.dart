import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/web/html_document.dart';

/// The scanner is the part of `fetch_page` most likely to be quietly wrong, so
/// these tests are about its two jobs and its two promises:
///
///  1. **text**: script/style content is gone, entities are decoded, whitespace is
///     collapsed, blocks do not run words together;
///  2. **selection**: the documented subset matches, and anything outside it is
///     *refused by name* instead of returning an empty list;
///  3. malformed markup does not throw (it is a scanner, not a browser);
///  4. every cap is reported (`nodesTruncated`, the truncation markers).
void main() {
  String textOf(String html) {
    final document = HtmlDocument.parse(html);
    return document.extractText(document.root);
  }

  List<Map<String, Object?>> matchRows(String html, String selector) {
    final document = HtmlDocument.parse(html);
    final matches = document.select(selector);
    return [
      for (var i = 0; i < matches.length; i++)
        document.matchJson(matches[i], index: i),
    ];
  }

  group('text extraction', () {
    test('drops script and style content entirely', () {
      const html = '''
<html><head>
  <style>.a { color: red; content: "x"; }</style>
  <script>var a = 1; if (a < 2) { document.write("<b>no</b>"); }</script>
</head><body>
  <p>Hello world</p>
</body></html>''';
      final text = textOf(html);
      expect(text, 'Hello world');
      expect(text, isNot(contains('var a')));
      expect(text, isNot(contains('color: red')));
      expect(text, isNot(contains('document.write')));
    });

    test('skips head/title/noscript/template as well as script/style', () {
      const html = '''
<html><head><title>My Title</title><meta name="x" content="y"></head>
<body><template><p>tpl</p></template><noscript>enable js</noscript><p>Body</p></body>
</html>''';
      final text = textOf(html);
      expect(text, 'Body');
      expect(text, isNot(contains('My Title')));
      expect(text, isNot(contains('tpl')));
      expect(text, isNot(contains('enable js')));
    });

    test('decodes entities in text', () {
      expect(
        textOf('<p>Tom &amp; Jerry: 1 &lt; 2 &gt; 0, &quot;quoted&quot;, '
            'it&#39;s &#20013;&#x6587;&nbsp;end</p>'),
        'Tom & Jerry: 1 < 2 > 0, "quoted", it\'s 中文 end',
      );
    });

    test('collapses runs of whitespace, newlines and nbsp', () {
      final text = textOf('<p>one\n\n   two\t\tthree&nbsp;&nbsp;four  </p>');
      expect(text, 'one two three four');
    });

    test('block boundaries keep words apart', () {
      // Without block spacing this becomes "FirstSecond".
      expect(textOf('<p>First</p><p>Second</p>'), 'First Second');
      expect(textOf('<ul><li>a</li><li>b</li></ul>'), 'a b');
      expect(textOf('A<br>B'), 'A B');
    });

    test('inline elements do not insert spaces', () {
      expect(textOf('<p>Hello <b>world</b>!</p>'), 'Hello world!');
      expect(textOf('<p>a<b>b</b>c</p>'), 'abc');
    });

    test('the title is read from the raw-title element, not its children', () {
      final document = HtmlDocument.parse(
        '<html><head><title>  A &amp; B   Title </title></head><body>x</body></html>',
      );
      expect(document.root.title, 'A & B Title');
    });

    test('a page with no title yields an empty string', () {
      expect(HtmlDocument.parse('<p>hi</p>').root.title, '');
    });

    test('a comment is not text', () {
      expect(textOf('<p>before<!-- hidden -->after</p>'), 'beforeafter');
    });

    test('an attribute value containing > does not break the tag scan', () {
      expect(
        textOf('<a href="http://x/?a=1>2" title="t">link</a> text'),
        'link text',
      );
    });

    test('long text is truncated at the cap with an explicit marker', () {
      final document = HtmlDocument.parse('<p>${'字' * 20000}</p>');
      final text = document.extractText(document.root, maxChars: 8000);
      expect(text.length, lessThanOrEqualTo(8000));
      expect(text, contains('[截断：'));
      expect(text, contains('8000'));
    });

    test('text under the cap is returned untouched and unmarked', () {
      final document = HtmlDocument.parse('<p>short</p>');
      expect(document.extractText(document.root, maxChars: 8000), 'short');
    });
  });

  group('malformed markup does not throw', () {
    test('a stray less-than sign is text', () {
      expect(textOf('<p>2 < 3 and 4 > 1</p>'), '2 < 3 and 4 > 1');
    });

    test('a tag the source never closes keeps its content as text', () {
      // `_findOpenTags` gives up at an unterminated `<`, so the tail is read as
      // text at the point the tag scan stopped. The point of the case is that
      // neither parsing nor extraction throws, not that browsers would agree.
      expect(textOf('<p>hello<div'), 'hello<div');
    });

    test('an unfinished tag at the end of input', () {
      expect(textOf('<p>hello</'), 'hello</');
    });

    test('a missing close tag keeps later text reachable', () {
      expect(textOf('<div><p>one<p>two</div>'), 'one two');
    });

    test('stray close tags are ignored', () {
      expect(textOf('</div><p>text</p></span>'), 'text');
    });
  });

  group('selector subset', () {
    const page = '''
<html><head><title>Links</title></head><body>
<main id="main">
  <div class="container">
    <a class="item lead" href="/a" data-kind="doc">A &amp; one</a>
    <a class="item" href="/b" data-kind="doc">B two</a>
    <a class="item" href="/c">C three</a>
    <p class="item note" data-kind="note">D four</p>
    <img class="item" src="/i.png" alt="an image" width="10">
    <input type="text" name="q" value="hello" placeholder="search">
  </div>
  <section><a href="/deep">deep link</a></section>
</main>
</body></html>''';

    test('type', () {
      final rows = matchRows(page, 'a');
      expect(rows.length, 4);
      expect(rows.first['href'], '/a');
      expect(rows[3]['text'], 'deep link');
    });

    test('id', () {
      expect(matchRows(page, '#main').length, 1);
      final rows = matchRows(page, 'main#main');
      expect(rows.length, 1);
      expect(rows.single['tag'], 'main');
    });

    test('class', () {
      expect(matchRows(page, '.item').length, 5);
      expect(matchRows(page, '.lead').length, 1);
    });

    test('type + class', () {
      final rows = matchRows(page, 'a.item');
      expect(rows.length, 3);
      expect(rows.map((r) => r['href']), ['/a', '/b', '/c']);
    });

    test('several classes means the element has all of them', () {
      final rows = matchRows(page, '.item.lead');
      expect(rows.length, 1);
      expect(rows.single['href'], '/a');
      expect(matchRows(page, '.item.note').length, 1);
      expect(matchRows(page, '.item.missing').length, 0);
    });

    test('attribute presence', () {
      // Three elements carry `data-kind`: two links and the paragraph. The image
      // and the input do not.
      expect(matchRows(page, '[data-kind]').length, 3);
      expect(matchRows(page, '[placeholder]').length, 1);
    });

    test('attribute equality, quotes optional', () {
      expect(matchRows(page, '[name="q"]').length, 1);
      expect(matchRows(page, '[name=q]').length, 1);
      expect(matchRows(page, "[name='q']").length, 1);
      expect(matchRows(page, '[data-kind="doc"]').length, 2);
      expect(matchRows(page, '[data-kind=nope]').length, 0);
    });

    test('attribute presence combined with a tag', () {
      expect(matchRows(page, 'a[data-kind]').length, 2);
      expect(matchRows(page, 'input[name="q"]').length, 1);
    });

    test('descendant combinator', () {
      expect(matchRows(page, 'main .item').length, 5);
      expect(matchRows(page, 'main a').length, 4);
      expect(matchRows(page, '.container a.item').length, 3);
      expect(matchRows(page, 'main section a').length, 1);
      // The first step must be an ancestor: an `a` contains no `main`.
      expect(matchRows(page, 'a main').length, 0);
      expect(matchRows(page, 'section main').length, 0);
    });

    test('several steps and compound steps together', () {
      expect(matchRows(page, 'main .container a.item[data-kind]').length, 2);
      expect(matchRows(page, 'main div.container .item.lead').length, 1);
    });

    test('a complete miss is an empty list, not an error', () {
      expect(matchRows(page, '.does-not-exist'), isEmpty);
      expect(matchRows(page, '#nope'), isEmpty);
      expect(matchRows(page, 'table tr td'), isEmpty);
    });
  });

  group('selector subset: refused syntax names the token', () {
    void refuses(String selector, String token) {
      expect(
        () => HtmlDocument.parse('<p>x</p>').select(selector),
        throwsA(
          isA<SelectorSyntaxException>().having(
            (e) => e.message,
            'message',
            allOf(contains(token), contains('不支持')),
          ),
        ),
        reason: 'selector `$selector` should be refused naming `$token`',
      );
    }

    test('child, sibling and general-sibling combinators', () {
      refuses('div > p', '>');
      refuses('div + p', '+');
      refuses('div ~ p', '~');
    });

    test('pseudo-classes and nth-child', () {
      refuses('p:first-child', ':');
      refuses('li:nth-child(2)', ':');
    });

    test('universal selector and selector lists', () {
      refuses('*', '*');
      refuses('div *', '*');
      refuses('a, b', ',');
    });

    test('attribute operators other than =', () {
      refuses('[class~="item"]', '~=');
      refuses('[lang|="en"]', '|');
      refuses('[href^="http"]', '^=');
      refuses('[href\$=".pdf"]', '\$=');
      refuses('[href*="x"]', '*=');
    });

    test('a malformed selector that is not a token either', () {
      expect(
        () => HtmlDocument.parse('<p>x</p>').select('div['),
        throwsA(isA<SelectorSyntaxException>()),
      );
      expect(
        () => HtmlDocument.parse('<p>x</p>').select('div.'),
        throwsA(isA<SelectorSyntaxException>()),
      );
      expect(
        () => HtmlDocument.parse('<p>x</p>').select('div!'),
        throwsA(isA<SelectorSyntaxException>()),
      );
      expect(
        () => HtmlDocument.parse('<p>x</p>').select('   '),
        throwsA(isA<SelectorSyntaxException>()),
      );
    });
  });

  group('match rows', () {
    const page = '''
<div id="a" class="x y" data-k="v"><span>Text &amp; more</span></div>
<a href="/l" target="_blank" rel="noopener" data-z="1">Link</a>
<img src="/p.png" alt="alt text" width="4" height="5">
<input type="text" name="q" value="v" placeholder="p" required>
<custom-thing foo="bar" baz="qux">custom</custom-thing>''';

    test('id, class and text are reported', () {
      final row = matchRows(page, '#a').single;
      expect(row['index'], 0);
      expect(row['tag'], 'div');
      expect(row['id'], 'a');
      expect(row['class'], 'x y');
      expect(row['text'], 'Text & more');
    });

    test('id and class are omitted when absent', () {
      final row = matchRows(page, 'a').single;
      expect(row.containsKey('id'), isFalse);
      expect(row.containsKey('class'), isFalse);
    });

    test('a link gets its href and link attributes only', () {
      final row = matchRows(page, 'a').single;
      expect(row['href'], '/l');
      expect(row['target'], '_blank');
      expect(row['rel'], 'noopener');
      // The useful set for a link excludes unrelated attributes.
      expect(row.containsKey('data-z'), isFalse);
    });

    test('an image gets src, alt and dimensions', () {
      final row = matchRows(page, 'img').single;
      expect(row['src'], '/p.png');
      expect(row['alt'], 'alt text');
      expect(row['width'], '4');
      expect(row['height'], '5');
    });

    test('a form field gets name, value and placeholder', () {
      final row = matchRows(page, 'input').single;
      expect(row['name'], 'q');
      expect(row['value'], 'v');
      expect(row['placeholder'], 'p');
      expect(row['type'], 'text');
      expect(row.containsKey('required'), isTrue);
      expect(row['required'], '');
    });

    test('an unknown tag exposes all of its attributes', () {
      final row = matchRows(page, 'custom-thing').single;
      expect(row['foo'], 'bar');
      expect(row['baz'], 'qux');
      expect(row['text'], 'custom');
    });

    test('per-element text is capped with a marker', () {
      final document = HtmlDocument.parse('<div class="big">${'x' * 900}</div>');
      final row = document.matchJson(document.select('.big').single, index: 0);
      final text = row['text']! as String;
      expect(text.length, lessThanOrEqualTo(500));
      expect(text, endsWith('[截断]'));
    });

    test('index follows the returned order', () {
      final rows = matchRows('<i>a</i><i>b</i><i>c</i>', 'i');
      expect(rows.map((r) => r['index']), [0, 1, 2]);
      expect(rows.map((r) => r['text']), ['a', 'b', 'c']);
    });
  });

  group('bounds are reported, never silent', () {
    test('the node cap sets nodesTruncated', () {
      final html = '<p>x</p>' * 100;
      final document = HtmlDocument.parse(html, maxNodes: 10);
      expect(document.nodesTruncated, isTrue);
      expect(document.elements().length, lessThan(100));
    });

    test('a page under the cap is not marked truncated', () {
      final document = HtmlDocument.parse('<p>x</p>' * 5, maxNodes: 100);
      expect(document.nodesTruncated, isFalse);
    });

    test('deep nesting does not blow the stack', () {
      final html = '${'<div>' * 3000}deep${'</div>' * 3000}';
      final document = HtmlDocument.parse(html);
      // The point is only that parsing and walking both complete.
      expect(document.extractText(document.root), contains('deep'));
    });

    test('elements() walks a wide page', () {
      final document = HtmlDocument.parse('<div><span>a</span><span>b</span></div>');
      expect(document.elements().map((e) => e.tag), ['div', 'span', 'span']);
      // `e.text` is null for an element; the text lives in its text children.
      expect(
        document
            .select('div span')
            .map((e) => document.extractElementText(e))
            .toList(),
        ['a', 'b'],
      );
    });
  });
}
