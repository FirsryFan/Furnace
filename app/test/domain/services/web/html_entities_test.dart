import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/web/html_entities.dart';

/// Entity decoding is small enough to look obviously correct, which is exactly
/// why it gets its own file: `&amp;lt;` decoding to `<` instead of `&lt;`, or an
/// unknown entity silently becoming a replacement character, would be invisible
/// in a page-text assertion.
void main() {
  group('named references', () {
    test('the six names the scanner knows are decoded', () {
      expect(decodeHtmlEntities('a &amp; b'), 'a & b');
      expect(decodeHtmlEntities('1 &lt; 2'), '1 < 2');
      expect(decodeHtmlEntities('3 &gt; 2'), '3 > 2');
      expect(decodeHtmlEntities('&quot;q&quot;'), '"q"');
      expect(decodeHtmlEntities('&#39;s'), "'s");
      expect(decodeHtmlEntities('&apos;s'), "'s");
      expect(decodeHtmlEntities('a&nbsp;b'), 'a\u00A0b');
    });

    test('the XML five also decode without a semicolon', () {
      expect(decodeHtmlEntities('a &amp b'), 'a & b');
      expect(decodeHtmlEntities('1 &lt 2'), '1 < 2');
      expect(decodeHtmlEntities('end &gt'), 'end >');
    });

    test('&nbsp; requires its semicolon, unlike the XML five', () {
      // `&nbsp` without `;` is not a reference, and guessing would be worse
      // than leaving the source text alone.
      expect(decodeHtmlEntities('a&nbspb'), 'a&nbspb');
    });

    test('an unknown name is left exactly as written', () {
      expect(decodeHtmlEntities('&copy; 2024'), '&copy; 2024');
      expect(decodeHtmlEntities('&notanentity;'), '&notanentity;');
      // `&notin` must not silently become `&not` + `in`.
      expect(decodeHtmlEntities('a&notin;b'), 'a&notin;b');
    });

    test('a bare ampersand is harmless', () {
      expect(decodeHtmlEntities('Tom & Jerry & Co'), 'Tom & Jerry & Co');
      expect(decodeHtmlEntities('100% &'), '100% &');
      expect(decodeHtmlEntities('&'), '&');
      expect(decodeHtmlEntities(''), '');
    });

    test('double-decoding does not happen', () {
      // The escaped literal must survive as text: this is the difference between
      // "a page that shows &lt;" and "a page that shows <".
      expect(decodeHtmlEntities('&amp;lt;'), '&lt;');
      expect(decodeHtmlEntities('&amp;amp;'), '&amp;');
    });
  });

  group('numeric references', () {
    test('decimal, with and without the semicolon', () {
      expect(decodeHtmlEntities('&#65;&#66;'), 'AB');
      expect(decodeHtmlEntities('&#20013;&#25991;'), '中文');
      expect(decodeHtmlEntities('&#65'), 'A');
    });

    test('hexadecimal, lower and upper case marker', () {
      expect(decodeHtmlEntities('&#x41;&#x42;'), 'AB');
      expect(decodeHtmlEntities('&#x4E2D;&#x6587;'), '中文');
      expect(decodeHtmlEntities('&#X4E2D;'), '中');
      expect(decodeHtmlEntities('&#x41'), 'A');
    });

    test('a non-BMP code point survives as one character', () {
      expect(decodeHtmlEntities('&#x1F600;'), '\u{1F600}');
    });

    test('invalid numbers are left alone rather than guessed', () {
      expect(decodeHtmlEntities('&#0;'), '&#0;');
      expect(decodeHtmlEntities('&#xD800;'), '&#xD800;'); // lone surrogate
      expect(decodeHtmlEntities('&#1114112;'), '&#1114112;'); // past U+10FFFF
      expect(decodeHtmlEntities('&#;'), '&#;');
      expect(decodeHtmlEntities('&#xZZ;'), '&#xZZ;');
    });
  });

  test('surrounding text and several references in one run', () {
    // The literal quote characters around the entities are source text and must
    // survive; only the references are replaced.
    expect(
      decodeHtmlEntities('<p>Tom &amp; Jerry: "&#39;hi&#39;" &lt;3</p>'),
      '<p>Tom & Jerry: "\'hi\'" <3</p>',
    );
  });
}
