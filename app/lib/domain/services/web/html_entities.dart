/// HTML character references, decoded without a DOM library.
///
/// The app has no HTML/DOM package (`pubspec.yaml` has no `html`), so the web
/// reading tool brings its own scanner. This file is the smallest part of it:
/// turning `&amp;` into `&`.
///
/// **Scope, stated honestly**: this is the *common* subset of the HTML5 named
/// reference table, not the table itself (which has ~2200 entries and entities
/// that expand to two code points). The five that matter for text, plus
/// `&nbsp;`, plus every numeric reference, are here. An unknown named entity is
/// left exactly as written instead of being guessed at - emitting the wrong
/// character silently is worse than emitting the source text.
library;

/// Decodes the character references the scanner supports.
///
/// Recognised:
///
///  * named: `&amp;` `&lt;` `&gt;` `&quot;` `&#39;` `&apos;` `&nbsp;`
///    (the trailing `;` is optional for the five XML ones, matching how HTML5
///    parsers treat `&amp` at the end of a sentence);
///  * numeric decimal: `&#NN;` / `&#NN` (e.g. `&#20013;`);
///  * numeric hexadecimal: `&#xHH;` / `&#XHH;` (e.g. `&#x4E2D;`).
///
/// Anything else - an unknown name, a numeric reference that is not a valid or
/// non-surrogate code point - is returned unchanged. `&amp;` is always decoded
/// first so that `&amp;lt;` yields the literal text `&lt;` rather than `<`.
String decodeHtmlEntities(String input) {
  final firstAmp = input.indexOf('&');
  if (firstAmp < 0) {
    return input;
  }

  final out = StringBuffer();
  var index = 0;
  while (index < input.length) {
    final amp = input.indexOf('&', index);
    if (amp < 0) {
      out.write(input.substring(index));
      break;
    }
    out.write(input.substring(index, amp));

    final decoded = _entityAt(input, amp);
    if (decoded == null) {
      // Not a reference we know: keep the `&` and keep scanning after it, so a
      // page full of bare `&` characters stays readable.
      out.write('&');
      index = amp + 1;
      continue;
    }
    out.writeCharCode(decoded.codePoint);
    index = decoded.end;
  }
  return out.toString();
}

/// One recognised reference: the code point it stands for and the index just
/// past it in the source.
class _EntityMatch {
  const _EntityMatch(this.codePoint, this.end);

  final int codePoint;

  /// Where the caller should continue scanning.
  final int end;
}

/// Numeric references are at most `&#x10FFFF;` = 10 characters; the longest
/// name we accept is `nbsp` = 4. The bound exists so a pathological page full of
/// `&` characters cannot make the scanner walk far ahead each time.
const int _maxReferenceLength = 12;

_EntityMatch? _entityAt(String text, int amp) {
  final tail = text.substring(
    amp + 1,
    amp + 1 + _maxReferenceLength > text.length
        ? text.length
        : amp + 1 + _maxReferenceLength,
  );
  if (tail.isEmpty) {
    return null;
  }

  if (tail.codeUnitAt(0) == _hash) {
    return _numericAt(tail, amp);
  }
  return _namedAt(tail, amp);
}

/// `#NN;`, `#xHH;` and their semicolon-less forms.
_EntityMatch? _numericAt(String tail, int amp) {
  var i = 1;
  var radix = 10;
  if (i < tail.length &&
      (tail.codeUnitAt(i) == _lowerX || tail.codeUnitAt(i) == _upperX)) {
    radix = 16;
    i++;
  }
  final digitsStart = i;
  while (i < tail.length && _isDigitFor(tail.codeUnitAt(i), radix)) {
    i++;
  }
  if (i == digitsStart) {
    return null;
  }

  final codePoint = int.parse(tail.substring(digitsStart, i), radix: radix);
  final hasSemicolon = i < tail.length && tail.codeUnitAt(i) == _semicolon;
  return _validCodePoint(codePoint) == null
      ? null
      : _EntityMatch(codePoint, amp + 1 + i + (hasSemicolon ? 1 : 0));
}

/// The short list of named references the scanner knows.
_EntityMatch? _namedAt(String tail, int amp) {
  for (final name in _namedReferences.keys) {
    if (!tail.startsWith(name)) {
      continue;
    }
    final hasSemicolon = tail.length > name.length &&
        tail.codeUnitAt(name.length) == _semicolon;
    // The XML five are also recognised without their `;` (a very common
    // hand-written-page habit); the rest require it, because `&notin` must not
    // silently become `&not` + `in`.
    if (!hasSemicolon && !_semicolonOptional.contains(name)) {
      continue;
    }
    return _EntityMatch(
      _namedReferences[name]!,
      amp + 1 + name.length + (hasSemicolon ? 1 : 0),
    );
  }
  return null;
}

/// Returns the code point when it is one Dart can put in a string, else null.
///
/// `0` and the surrogate range are rejected because `String.fromCharCode` turns
/// them into replacement characters or broken halves.
int? _validCodePoint(int codePoint) {
  if (codePoint <= 0 || codePoint > 0x10FFFF) {
    return null;
  }
  if (codePoint >= 0xD800 && codePoint <= 0xDFFF) {
    return null;
  }
  return codePoint;
}

bool _isDigitFor(int codeUnit, int radix) {
  if (codeUnit >= _zero && codeUnit <= _nine) {
    return codeUnit - _zero < radix;
  }
  if (radix != 16) {
    return false;
  }
  final lower = codeUnit | 0x20; // ASCII fold: 'A' | 0x20 == 'a'
  return lower >= _lowerA && lower <= _lowerF;
}

/// The named references the scanner decodes.
///
/// The five XML entities that HTML inherits, plus `&nbsp;` (U+00A0) - the one
/// non-ASCII name that shows up constantly in copy-pasted pages. Note the keys
/// are bare names with no `&` and no `;`.
const Map<String, int> _namedReferences = {
  'amp': 0x26,
  'lt': 0x3C,
  'gt': 0x3E,
  'quot': 0x22,
  'apos': 0x27,
  'nbsp': 0xA0,
};

/// Names decoded even when the author left out the `;`.
const Set<String> _semicolonOptional = {'amp', 'lt', 'gt', 'quot', 'apos'};

const int _hash = 0x23; // '#'
const int _semicolon = 0x3B; // ';'
const int _lowerX = 0x78; // 'x'
const int _upperX = 0x58; // 'X'
const int _zero = 0x30; // '0'
const int _nine = 0x39; // '9'
const int _lowerA = 0x61; // 'a'
const int _lowerF = 0x66; // 'f'
