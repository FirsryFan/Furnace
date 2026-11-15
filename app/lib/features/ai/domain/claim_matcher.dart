/// Layered claim matching without embeddings, local models or network calls.
///
/// A reasoning run says the same thing in different words: `m_2/m_1 = 7`,
/// `\frac{m_2}{m_1}=7`, `m2：m1 = 7`, `7 = m2/m1`. Exact hashing catches none of
/// that, and a local embedding model is explicitly out of scope (design §10 and
/// §14). This matcher therefore walks a conservative ladder:
///
///   1. exact canonical text (plus a hash guard);
///   2. normalized text (LaTeX/full-width/subscript folding, discourse-prefix
///      stripping, a small hand-curated synonym dictionary, ratio/degree and
///      copula normalization);
///   3. structured fields (top-level relation + operands, symmetric relation
///      operands sorted);
///   4. lexical / character n-gram similarity, gated by a "hard signature"
///      (numeric literals, relation symbols, negation words, polarity words);
///   5. a tiny math AST: expressions over rationals, equations and inequality
///      chains compared up to a non-zero scalar factor;
///   6. an optional [ClaimJudge] that only answers "same proposition?" — never
///      "true or false" (design §10.6).
///
/// The default is **not merging** when a tier is not confident. A pair that
/// looks similar but cannot be proven the same is reported as
/// [ClaimMatch.possiblyDuplicate], and the caller keeps both claims. This is
/// deliberate: a false merge silently deletes a distinct proposition, while a
/// missed merge only costs a duplicate check.
///
/// Known boundary (do not overclaim): a paraphrase with no shared words cannot
/// be matched without semantics. That is the documented limit of the design.
library;

import 'claim.dart';

/// Which rung of the ladder decided a match.
enum ClaimMatchTier {
  /// Not the same proposition (no rung matched).
  none,

  /// Identical canonical text.
  exact,

  /// Identical after normalization.
  normalized,

  /// Same relation and operands (`A = B` vs `B = A`).
  structured,

  /// Lexical / character n-gram similarity above the merge threshold.
  lexical,

  /// Proven equivalent by the math AST / numeric equivalence.
  math,

  /// The optional judge said "same proposition".
  judge,
}

/// The result of comparing two claims.
class ClaimMatch {
  const ClaimMatch({
    required this.tier,
    required this.merge,
    required this.possiblyDuplicate,
    required this.score,
    required this.reason,
    this.matched,
  });

  /// Nothing was compared.
  const ClaimMatch.none()
      : tier = ClaimMatchTier.none,
        merge = false,
        possiblyDuplicate = false,
        score = 0,
        reason = 'no candidate',
        matched = null;

  /// The candidate this result is about (`null` only for [ClaimMatch.none]).
  final Claim? matched;

  final ClaimMatchTier tier;

  /// Whether the two claims should be merged into one.
  final bool merge;

  /// Whether the pair looks similar but was deliberately **not** merged
  /// (design §10.7). The caller should keep both claims and may surface this.
  final bool possiblyDuplicate;

  /// Similarity in `[0, 1]`; meaningful mainly for the lexical rung.
  final double score;

  /// Human-readable explanation, used by tests and trace logs.
  final String reason;

  /// Whether this is a definite "not the same" rather than a weak one.
  bool get isDifferent => !merge && !possiblyDuplicate;

  @override
  String toString() =>
      'ClaimMatch(${tier.name} merge=$merge possible=$possiblyDuplicate '
      'score=${score.toStringAsFixed(3)} $reason)';
}

/// Optional last-rung judge: only decides whether two claims state the same
/// proposition. It must not decide whether the proposition is *true*; content
/// truth belongs to the verifier (design §10.6, §7.4).
///
/// Returning `null` means "no judgement" (abstain); the matcher then keeps the
/// pair unmerged and marks it [ClaimMatch.possiblyDuplicate].
abstract interface class ClaimJudge {
  Future<bool?> sameProposition(Claim a, Claim b);
}

/// Matches claims by the layered scheme described in the library docs.
class ClaimMatcher {
  ClaimMatcher({
    this.judge,
    this.mergeThreshold = 0.90,
    this.possiblyThreshold = 0.55,
  });

  /// Optional sixth rung. No judge is configured by default: the matcher must
  /// stay useful (and deterministic) without an LLM call.
  final ClaimJudge? judge;

  /// Lexical similarity at or above this merges without the judge.
  final double mergeThreshold;

  /// Lexical similarity at or above this is worth reporting as a possible
  /// duplicate (never merged on its own).
  final double possiblyThreshold;

  /// Compares two claims, using the judge when the pair is uncertain.
  Future<ClaimMatch> match(Claim a, Claim b) => _match(a, b, allowJudge: true);

  /// Finds the best match of [claim] among [candidates].
  ///
  /// Returns `null` only when there is nothing to compare. Otherwise the best
  /// candidate result is returned; [ClaimMatch.merge] says whether the caller
  /// should reuse [ClaimMatch.matched] instead of adding [claim]. The judge is
  /// consulted at most once, and only for the best uncertain candidate.
  Future<ClaimMatch?> find(Claim claim, Iterable<Claim> candidates) async {
    ClaimMatch? best;
    for (final candidate in candidates) {
      if (candidate.id == claim.id) {
        continue;
      }
      final result = await _match(claim, candidate, allowJudge: false);
      if (best == null || _isBetter(result, best)) {
        best = result;
      }
    }
    if (best == null) {
      return null;
    }
    if (best.merge) {
      return best;
    }
    final judgedCandidate = best.matched;
    if (best.possiblyDuplicate && judge != null && judgedCandidate != null) {
      return _match(claim, judgedCandidate, allowJudge: true);
    }
    return best;
  }

  /// Lexical similarity between two texts (normalized first). Exposed so
  /// callers/tests can inspect why a pair landed where it did.
  static double lexicalSimilarity(String a, String b) => _similarity(
        ClaimTextNormalizer.normalize(a),
        ClaimTextNormalizer.normalize(b),
      );

  Future<ClaimMatch> _match(
    Claim a,
    Claim b, {
    required bool allowJudge,
  }) async {
    // 1. exact canonical text (the hash equality is a cheap pre-filter; the
    //    text equality itself is the evidence, so a hash collision cannot
    //    merge two different claims).
    final textA = _textOf(a);
    final textB = _textOf(b);
    if (textA.isNotEmpty &&
        a.canonicalHash == b.canonicalHash &&
        textA == textB) {
      return ClaimMatch(
        matched: b,
        tier: ClaimMatchTier.exact,
        merge: true,
        possiblyDuplicate: false,
        score: 1,
        reason: 'identical canonical text',
      );
    }

    // 2. normalized text.
    final normA = ClaimTextNormalizer.normalize(textA);
    final normB = ClaimTextNormalizer.normalize(textB);
    if (normA.isNotEmpty && normA == normB) {
      return ClaimMatch(
        matched: b,
        tier: ClaimMatchTier.normalized,
        merge: true,
        possiblyDuplicate: false,
        score: 1,
        reason: 'identical after normalization',
      );
    }

    // 3. structured relation/operands.
    final structureA = _structureOf(normA);
    final structureB = _structureOf(normB);
    if (structureA != null && structureB != null && structureA == structureB) {
      return ClaimMatch(
        matched: b,
        tier: ClaimMatchTier.structured,
        merge: true,
        possiblyDuplicate: false,
        score: 0.97,
        reason: 'same relation and operands ($structureA)',
      );
    }

    // 4. lexical / character n-gram similarity, gated so that a number,
    //    relation, negation or polarity difference can never merge.
    final similarity = _similarity(normA, normB);
    final hardDifference = _hardDifference(normA, normB);
    if (hardDifference == null && similarity >= mergeThreshold) {
      return ClaimMatch(
        matched: b,
        tier: ClaimMatchTier.lexical,
        merge: true,
        possiblyDuplicate: false,
        score: similarity,
        reason: 'lexical similarity ${similarity.toStringAsFixed(3)} '
            '>= ${mergeThreshold.toStringAsFixed(2)} '
            'with identical hard signature',
      );
    }

    // 5. math AST / numeric equivalence.
    final mathA = CanonicalMathClaim.parse(textA);
    final mathB = CanonicalMathClaim.parse(textB);
    if (mathA != null && mathB != null && mathA.key == mathB.key) {
      return ClaimMatch(
        matched: b,
        tier: ClaimMatchTier.math,
        merge: true,
        possiblyDuplicate: false,
        score: 0.95,
        reason: 'equivalent math claim (${mathA.key})',
      );
    }

    // 6. uncertain -> optional judge.
    final uncertain = similarity >= possiblyThreshold;
    if (hardDifference == null && uncertain) {
      if (allowJudge && judge != null) {
        final verdict = await judge!.sameProposition(a, b);
        if (verdict == true) {
          return ClaimMatch(
            matched: b,
            tier: ClaimMatchTier.judge,
            merge: true,
            possiblyDuplicate: false,
            score: similarity,
            reason: 'judge confirmed same proposition',
          );
        }
        if (verdict == false) {
          return ClaimMatch(
            matched: b,
            tier: ClaimMatchTier.none,
            merge: false,
            possiblyDuplicate: false,
            score: similarity,
            reason: 'judge rejected same-proposition match',
          );
        }
      }
      return ClaimMatch(
        matched: b,
        tier: ClaimMatchTier.none,
        merge: false,
        possiblyDuplicate: true,
        score: similarity,
        reason: 'similar (${similarity.toStringAsFixed(3)}) but not proven '
            'the same; not merged',
      );
    }

    if (hardDifference != null) {
      return ClaimMatch(
        matched: b,
        tier: ClaimMatchTier.none,
        merge: false,
        possiblyDuplicate: false,
        score: similarity,
        reason: 'definitely different: $hardDifference',
      );
    }

    return ClaimMatch(
      matched: b,
      tier: ClaimMatchTier.none,
      merge: false,
      possiblyDuplicate: false,
      score: similarity,
      reason: 'low similarity ${similarity.toStringAsFixed(3)}',
    );
  }

  static bool _isBetter(ClaimMatch candidate, ClaimMatch current) {
    if (candidate.merge != current.merge) {
      return candidate.merge;
    }
    if (candidate.possiblyDuplicate != current.possiblyDuplicate) {
      return candidate.possiblyDuplicate;
    }
    return candidate.score > current.score;
  }

  static String _textOf(Claim claim) {
    final canonical = claim.canonical.trim();
    return canonical.isEmpty ? claim.statement.trim() : canonical;
  }
}

/// Normalization shared by the matcher and by callers that want to store a
/// normalized `Claim.canonical`.
///
/// It is intentionally pure string work: no tokenizer model, no dictionary
/// beyond the small curated synonym table below. Everything here is a total
/// function (never throws) because claims come from free model text.
class ClaimTextNormalizer {
  ClaimTextNormalizer._();

  /// Normalizes a claim sentence into the canonical form used for matching.
  ///
  /// Steps, in order: LaTeX wrappers/fractions/subscripts; full-width digits,
  /// letters and operators; Greek macro names; lower-casing; leading discourse
  /// markers; the small synonym table; ratio colons; `度` after a number;
  /// removal of spaces/quotes/list punctuation. Parentheses and arithmetic
  /// symbols are kept because the math AST needs them.
  static String normalize(String input) {
    var text = input.trim();
    if (text.isEmpty) {
      return '';
    }
    text = _foldLatex(text);
    text = _foldWidth(text);
    text = text.toLowerCase();
    text = _stripDiscoursePrefix(text);
    text = _applySynonyms(text);
    text = _foldRatioColons(text);
    text = _foldDegree(text);
    // ASCII '.' is kept: it is the decimal separator the math AST needs; a
    // trailing sentence dot is removed separately. Chinese punctuation and
    // spaces carry no meaning for matching.
    text = text.replaceAll(
      RegExp(r'''[\s，,、；;。！!？?'"“”‘’\[\]{}]'''),
      '',
    );
    while (text.endsWith('.')) {
      text = text.substring(0, text.length - 1);
    }
    return text;
  }

  /// Lists the canonical polarity/direction words after [normalize] has mapped
  /// synonym families onto them. Used to build the hard signature.
  static const List<String> polarityTerms = [
    '增大',
    '减小',
    '加速',
    '减速',
    '吸热',
    '放热',
    '正比',
    '反比',
    '顺时针',
    '逆时针',
    '相同',
    '相反',
    '向上',
    '向下',
    '向左',
    '向右',
    '伸长',
    '缩短',
    '膨胀',
    '压缩',
    '变亮',
    '变暗',
    '正确',
    '错误',
    '高',
    '低',
    '大',
    '小',
    '正',
    '负',
    '前',
    '后',
    '里',
    '外',
  ];

  /// Negation markers counted by the hard signature.
  static const List<String> negationTerms = [
    '没有',
    '无法',
    '不能',
    '未能',
    '不',
    '非',
    '否',
    '无',
    '未',
  ];

  // ---------------------------------------------------------------------------
  // LaTeX / unicode folding.
  // ---------------------------------------------------------------------------

  static String _foldLatex(String text) {
    var out = text;

    // \frac{a}{b} / \dfrac / \tfrac -> (a)/(b). Bounded because nested
    // fractions are rare in a claim and unbounded recursion is not worth it.
    final fraction = RegExp(r'\\[dt]?frac\s*\{([^{}]*)\}\s*\{([^{}]*)\}');
    for (var i = 0; i < 3; i++) {
      if (!fraction.hasMatch(out)) {
        break;
      }
      out = out.replaceAllMapped(
        fraction,
        (match) => '(${match[1]})/(${match[2]})',
      );
    }

    // Superscripts keep parentheses so x^{n+1} stays parseable; subscripts are
    // folded to identifier characters (m_2 -> m2, E_{k0} -> ek0).
    out = out.replaceAllMapped(
      RegExp(r'\^\{([^{}]*)\}'),
      (match) => '^(${match[1]})',
    );
    out = out.replaceAllMapped(
      RegExp(r'_\{([^{}]*)\}'),
      (match) => match[1]!,
    );
    out = out.replaceAllMapped(
      RegExp(r'_([A-Za-z0-9]+)'),
      (match) => match[1]!,
    );

    out = out.replaceAll(
      RegExp(
          r'\\(?:left|right|displaystyle|textstyle|text|mathrm|operatorname)\s*'),
      '',
    );
    out = out.replaceAll(RegExp(r'\\[,;:! ]'), '');

    const greek = <String, String>{
      r'\pi': 'pi',
      r'\alpha': 'alpha',
      r'\beta': 'beta',
      r'\gamma': 'gamma',
      r'\delta': 'delta',
      r'\epsilon': 'epsilon',
      r'\varepsilon': 'epsilon',
      r'\eta': 'eta',
      r'\theta': 'theta',
      r'\lambda': 'lambda',
      r'\mu': 'mu',
      r'\rho': 'rho',
      r'\sigma': 'sigma',
      r'\tau': 'tau',
      r'\phi': 'phi',
      r'\varphi': 'phi',
      r'\omega': 'omega',
      r'\Delta': 'delta',
    };
    greek.forEach((macro, name) {
      out = out.replaceAll(macro, name);
    });

    // Remaining unknown commands lose their backslash rather than leaking it
    // into the canonical text.
    out = out.replaceAll(RegExp(r'\\[A-Za-z]+'), '');
    // Braces that survived \frac expansion act as grouping.
    out = out.replaceAll('{', '(').replaceAll('}', ')');
    return out;
  }

  static String _foldWidth(String text) {
    final buffer = StringBuffer();
    for (final rune in text.runes) {
      if (rune >= 0xFF01 && rune <= 0xFF5E) {
        buffer.writeCharCode(rune - 0xFEE0);
        continue;
      }
      if (rune == 0x3000) {
        continue;
      }
      if (rune == 0x2212 || rune == 0x2013 || rune == 0x2014) {
        buffer.write('-'); // minus sign, en dash, em dash
        continue;
      }
      if (rune == 0x00D7 || rune == 0x22C5 || rune == 0x00B7) {
        buffer.write('*'); // multiplication sign, dot operator, middle dot
        continue;
      }
      if (rune == 0x00F7) {
        buffer.write('/'); // division sign
        continue;
      }
      if (rune == 0x2264 || rune == 0x2266) {
        buffer.write('≤');
        continue;
      }
      if (rune == 0x2265 || rune == 0x2267) {
        buffer.write('≥');
        continue;
      }
      if (rune == 0x2260) {
        buffer.write('≠');
        continue;
      }
      if (rune == 0x2248) {
        buffer.write('≈');
        continue;
      }
      if (rune == 0x00B2) {
        buffer.write('^2');
        continue;
      }
      if (rune == 0x00B3) {
        buffer.write('^3');
        continue;
      }
      if (rune == 0x00B9) {
        buffer.write('^1');
        continue;
      }
      if (rune == 0x2070) {
        buffer.write('^0');
        continue;
      }
      if (rune >= 0x2074 && rune <= 0x2079) {
        buffer.write('^${rune - 0x2070}');
        continue;
      }
      if (rune == 0x207A) {
        buffer.write('^+');
        continue;
      }
      if (rune == 0x207B) {
        buffer.write('^-');
        continue;
      }
      if (rune >= 0x2080 && rune <= 0x2089) {
        // Unicode subscript digits.
        buffer.writeCharCode(0x30 + (rune - 0x2080));
        continue;
      }
      buffer.writeCharCode(rune);
    }
    return buffer.toString();
  }

  static const List<String> _discoursePrefixes = [
    '也就是说',
    '需要注意的是',
    '可以看出',
    '注意到',
    '综上所述',
    '综上',
    '总之',
    '因此',
    '所以',
    '因为',
    '由于',
    '于是',
    '从而',
    '由此',
    '进而',
    '那么',
    '可得',
  ];

  static String _stripDiscoursePrefix(String text) {
    var out = text;
    var changed = true;
    while (changed) {
      changed = false;
      for (final prefix in _discoursePrefixes) {
        if (out.startsWith(prefix)) {
          out = out.substring(prefix.length);
          changed = true;
          break;
        }
      }
    }
    return out;
  }

  /// Small hand-curated synonym table: discourse connectives, copulas and the
  /// direction families used by the polarity guard. Longest key first so
  /// `大于等于` is not eaten by `大于`, and `因为` before `为`.
  static const Map<String, String> _synonyms = {
    '大于等于': '≥',
    '小于等于': '≤',
    '当且仅当': 'iff',
    '等价于': 'iff',
    '不等于': '≠',
    '大于': '>',
    '小于': '<',
    '等于': '=',
    '因为': '由于',
    '所以': '因此',
    '因此': '因此',
    '于是': '因此',
    '从而': '因此',
    '由此': '因此',
    '进而': '因此',
    '那么': '因此',
    '并且': '且',
    '或者': '或',
    '以及': '且',
    '为': '=',
    '是': '=',
    // Direction families: the polarity guard compares canonical direction
    // words, so "增加/升高/上升" become one term and their opposites another.
    '增加': '增大',
    '升高': '增大',
    '上升': '增大',
    '提高': '增大',
    '变大': '增大',
    '减少': '减小',
    '降低': '减小',
    '下降': '减小',
    '变小': '减小',
    '一致': '相同',
  };

  static String _applySynonyms(String text) {
    final keys = _synonyms.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    final buffer = StringBuffer();
    var index = 0;
    outer:
    while (index < text.length) {
      for (final key in keys) {
        if (text.startsWith(key, index)) {
          buffer.write(_synonyms[key]);
          index += key.length;
          continue outer;
        }
      }
      buffer.write(text[index]);
      index++;
    }
    return buffer.toString();
  }

  static String _foldRatioColons(String text) {
    final buffer = StringBuffer();
    for (var i = 0; i < text.length; i++) {
      final char = text[i];
      if (char == ':' || char == '：') {
        final before = i == 0 ? '' : text[i - 1];
        final after = i + 1 < text.length ? text[i + 1] : '';
        if (_isAsciiAlnum(before) && _isAsciiAlnum(after)) {
          buffer.write('/');
        }
        // Otherwise it is prose punctuation; dropping it is handled by the
        // final punctuation pass.
        continue;
      }
      buffer.write(char);
    }
    return buffer.toString();
  }

  static String _foldDegree(String text) {
    final buffer = StringBuffer();
    for (var i = 0; i < text.length; i++) {
      final char = text[i];
      if (char == '度' && i > 0 && _isAsciiAlnum(text[i - 1])) {
        buffer.write('°');
      } else {
        buffer.write(char);
      }
    }
    return buffer.toString();
  }

  static bool _isAsciiAlnum(String char) {
    if (char.isEmpty) {
      return false;
    }
    final code = char.codeUnitAt(0);
    return (code >= 0x30 && code <= 0x39) ||
        (code >= 0x41 && code <= 0x5A) ||
        (code >= 0x61 && code <= 0x7A);
  }
}

/// A math claim normalized to a set of constraints.
///
/// A constraint is a top-level relation plus a polynomial moved to one side
/// (`lhs - rhs`), normalized up to a non-zero scalar. This makes
/// `m2 = 7 m1` and `m2 / m1 = 7` the same claim (the denominator is cleared
/// for equalities), and `17/2 ≤ E ≤ 12` the same as `12 ≥ E ≥ 17/2`.
///
/// Deliberately small: linear/polynomial expressions with `+ - * / ^` over
/// rational numbers, no functions, no trigonometry, no units. Anything outside
/// that subset returns `null` and the pair falls back to "do not merge".
class CanonicalMathClaim {
  const CanonicalMathClaim(this.constraints);

  /// Sorted canonical constraints, e.g. `['≤|1+-2/17*ek0', ...]`.
  final List<String> constraints;

  String get key => constraints.join(';');

  static CanonicalMathClaim? parse(String text) {
    final math = _mathText(text);
    if (math.isEmpty || math.length > 400) {
      return null;
    }
    final split = _splitTopLevelRelations(math);
    if (split == null) {
      return null;
    }
    final atoms = <String>[];
    for (var i = 0; i < split.relations.length; i++) {
      final atom = _constraintOf(
        split.segments[i],
        split.relations[i],
        split.segments[i + 1],
      );
      if (atom == null) {
        return null;
      }
      atoms.add(atom);
    }
    atoms.sort();
    return CanonicalMathClaim(List<String>.unmodifiable(atoms));
  }

  static String _mathText(String text) {
    var out = ClaimTextNormalizer.normalize(text);
    out = out.replaceAll('°', '').replaceAll('%', '');
    return out;
  }

  static String? _constraintOf(
    String lhsText,
    String relation,
    String rhsText,
  ) {
    _Rat lhs;
    _Rat rhs;
    try {
      lhs = _ExpressionParser.parse(lhsText);
      rhs = _ExpressionParser.parse(rhsText);
    } on FormatException {
      return null;
    }
    final canonicalRelation = _canonicalRelation(relation);
    _Rat difference;
    try {
      difference = lhs.sub(rhs);
    } on FormatException {
      return null;
    }

    if (canonicalRelation == '=' ||
        canonicalRelation == '≠' ||
        canonicalRelation == '≈') {
      // f = 0 (and f ≠ 0 / f ≈ 0) are invariant under multiplying f by any
      // non-zero scalar. [difference] is already the rational value of
      // lhs - rhs; its zeros are exactly the zeros of its numerator, so a
      // variable denominator needs no further handling here.
      final polynomial = difference.num;
      if (polynomial.isZeroValue) {
        return '$canonicalRelation|0';
      }
      return '$canonicalRelation|${polynomial.normalizedKey()}';
    }

    // Inequalities: multiplying by a denominator of unknown sign would flip
    // the relation unpredictably, so only constant denominators are accepted.
    final denominator = difference.den;
    final constant = denominator.constantValue;
    if (constant == null) {
      return null;
    }
    var ratio = constant;
    var poly = difference.num;
    if (ratio.sign < 0) {
      poly = poly.neg();
      ratio = -ratio;
    }
    poly = poly.scale(ratio.inverse);
    final flip = poly.leadingSign() < 0;
    if (flip) {
      poly = poly.neg();
    }
    return '${flip ? _flipRelation(canonicalRelation) : canonicalRelation}'
        '|${poly.normalizedKey()}';
  }

  static String _canonicalRelation(String relation) => switch (relation) {
        '==' => '=',
        '!=' => '≠',
        '<=' => '≤',
        '>=' => '≥',
        _ => relation,
      };

  static String _flipRelation(String relation) => switch (relation) {
        '<' => '>',
        '>' => '<',
        '≤' => '≥',
        '≥' => '≤',
        _ => relation,
      };
}

// -----------------------------------------------------------------------------
// Internals: structure / similarity / hard signature.
// -----------------------------------------------------------------------------

class _Split {
  const _Split(this.segments, this.relations);

  final List<String> segments;
  final List<String> relations;
}

/// Splits a normalized string at top-level relation operators. Returns `null`
/// when there is no relation, adjacent/empty operands, or unbalanced parens.
_Split? _splitTopLevelRelations(String text) {
  final segments = <String>[];
  final relations = <String>[];
  var depth = 0;
  var start = 0;
  var index = 0;
  while (index < text.length) {
    final char = text[index];
    if (char == '(') {
      depth++;
      index++;
      continue;
    }
    if (char == ')') {
      depth--;
      if (depth < 0) {
        return null;
      }
      index++;
      continue;
    }
    if (depth != 0) {
      index++;
      continue;
    }
    final relation = _relationAt(text, index);
    if (relation == null) {
      index++;
      continue;
    }
    final operand = text.substring(start, index);
    if (operand.isEmpty) {
      return null;
    }
    segments.add(operand);
    relations.add(relation.$1);
    index += relation.$2;
    start = index;
  }
  if (depth != 0 || relations.isEmpty) {
    return null;
  }
  final tail = text.substring(start);
  if (tail.isEmpty) {
    return null;
  }
  segments.add(tail);
  return _Split(segments, relations);
}

(String, int)? _relationAt(String text, int index) {
  final two = index + 1 < text.length ? text.substring(index, index + 2) : '';
  switch (two) {
    case '<=':
      return ('<=', 2);
    case '>=':
      return ('>=', 2);
    case '==':
      return ('==', 2);
    case '!=':
      return ('!=', 2);
  }
  const singles = '=<>≤≥≠≈';
  if (singles.contains(text[index])) {
    return (text[index], 1);
  }
  return null;
}

String? _structureOf(String normalized) {
  final split = _splitTopLevelRelations(normalized);
  if (split == null || split.segments.length != 2) {
    return null;
  }
  final relation = CanonicalMathClaim._canonicalRelation(split.relations.first);
  final left = split.segments[0];
  final right = split.segments[1];
  if (left.isEmpty || right.isEmpty) {
    return null;
  }
  if (relation == '=' ||
      relation == '≠' ||
      relation == '≈' ||
      relation == 'iff') {
    final operands = <String>[left, right]..sort();
    return '$relation|${operands[0]}|${operands[1]}';
  }
  return '$relation|$left|$right';
}

List<String> _tokensOf(String text) {
  const mathSymbols = '+-*/^=<>≤≥≠≈()';
  final tokens = <String>[];
  final buffer = StringBuffer();
  void flush() {
    if (buffer.isNotEmpty) {
      tokens.add(buffer.toString());
      buffer.clear();
    }
  }

  for (final rune in text.runes) {
    if (_isAsciiWordRune(rune)) {
      buffer.writeCharCode(rune);
      continue;
    }
    final char = String.fromCharCode(rune);
    if (mathSymbols.contains(char)) {
      // Operators are tokens too: "x+y=5" and "x*y=5" must not look identical
      // just because they share every letter and number.
      flush();
      tokens.add(char);
      continue;
    }
    flush();
    if (_isCjkRune(rune)) {
      tokens.add(char);
    }
  }
  flush();
  return tokens;
}

Set<String> _bigramsOf(String text) {
  final runes = text.runes.toList();
  if (runes.isEmpty) {
    return <String>{};
  }
  if (runes.length == 1) {
    return {String.fromCharCode(runes.first)};
  }
  final grams = <String>{};
  for (var i = 0; i + 1 < runes.length; i++) {
    grams.add(String.fromCharCodes([runes[i], runes[i + 1]]));
  }
  return grams;
}

double _similarity(String normalizedA, String normalizedB) {
  if (normalizedA.isEmpty || normalizedB.isEmpty) {
    return 0;
  }
  if (normalizedA == normalizedB) {
    return 1;
  }
  final a = _tokensOf(normalizedA).toSet();
  final b = _tokensOf(normalizedB).toSet();
  final union = a.union(b).length;
  final jaccard = union == 0 ? 0.0 : a.intersection(b).length / union;

  final gramsA = _bigramsOf(normalizedA);
  final gramsB = _bigramsOf(normalizedB);
  final gramUnion = gramsA.union(gramsB).length;
  final dice = gramUnion == 0
      ? 0.0
      : 2 *
          gramsA.intersection(gramsB).length /
          (gramsA.length + gramsB.length);
  // Both the token bag and the character order must agree. Taking the max would
  // merge `a=b-c` with `a=c-b` (same tokens, reversed operands), which is a
  // different proposition; the math tier is where commutativity may be proven.
  return jaccard < dice ? jaccard : dice;
}

/// Returns a human-readable reason when two normalized texts differ in a way
/// that is *evidence* they are not the same proposition: different numeric
/// literals, different relation symbols, opposite polarity words, or different
/// negation. `null` means "no hard difference", i.e. possibly the same.
String? _hardDifference(String normalizedA, String normalizedB) {
  final numbersA = _numberSignature(normalizedA);
  final numbersB = _numberSignature(normalizedB);
  if (numbersA != numbersB) {
    return 'numeric literals differ [$numbersA] vs [$numbersB]';
  }
  final relationsA = _relationSignature(normalizedA);
  final relationsB = _relationSignature(normalizedB);
  if (relationsA != relationsB) {
    return 'relation symbols differ [$relationsA] vs [$relationsB]';
  }
  final polarityA = _polaritySignature(normalizedA);
  final polarityB = _polaritySignature(normalizedB);
  if (polarityA != polarityB) {
    return 'polarity words differ [$polarityA] vs [$polarityB]';
  }
  final negationA = _negationSignature(normalizedA);
  final negationB = _negationSignature(normalizedB);
  if (negationA != negationB) {
    return 'negation differs [$negationA] vs [$negationB]';
  }
  return null;
}

String _numberSignature(String text) {
  final numbers = <String>[];
  var index = 0;
  while (index < text.length) {
    final char = text[index];
    if (_isAsciiDigit(char) &&
        (index == 0 || !_isAsciiIdentifierChar(text[index - 1]))) {
      var end = index;
      while (end < text.length && _isAsciiDigit(text[end])) {
        end++;
      }
      if (end + 1 < text.length &&
          text[end] == '.' &&
          _isAsciiDigit(text[end + 1])) {
        end++;
        while (end < text.length && _isAsciiDigit(text[end])) {
          end++;
        }
      }
      numbers.add(_canonicalNumber(text.substring(index, end)));
      index = end;
      continue;
    }
    index++;
  }
  numbers.sort();
  return numbers.join(',');
}

String _canonicalNumber(String raw) {
  if (!raw.contains('.')) {
    final trimmed = raw.replaceFirst(RegExp(r'^0+(?=\d)'), '');
    return trimmed;
  }
  var text = raw.replaceFirst(RegExp(r'0+$'), '');
  if (text.endsWith('.')) {
    text = text.substring(0, text.length - 1);
  }
  text = text.replaceFirst(RegExp(r'^0+(?=\d)'), '');
  return text;
}

String _relationSignature(String text) {
  final relations = <String>[];
  var index = 0;
  while (index < text.length) {
    final relation = _relationAt(text, index);
    if (relation != null) {
      relations.add(relation.$1);
      index += relation.$2;
      continue;
    }
    index++;
  }
  relations.sort();
  return relations.join(',');
}

String _polaritySignature(String text) {
  final terms = [...ClaimTextNormalizer.polarityTerms]
    ..sort((a, b) => b.length.compareTo(a.length));
  final signature = <String>[];
  var index = 0;
  outer:
  while (index < text.length) {
    for (final term in terms) {
      if (text.startsWith(term, index)) {
        signature.add(term);
        index += term.length;
        continue outer;
      }
    }
    index++;
  }
  return signature.join(',');
}

String _negationSignature(String text) {
  final terms = [...ClaimTextNormalizer.negationTerms]
    ..sort((a, b) => b.length.compareTo(a.length));
  final matches = <String>[];
  var index = 0;
  outer:
  while (index < text.length) {
    for (final term in terms) {
      if (text.startsWith(term, index)) {
        matches.add(term);
        index += term.length;
        continue outer;
      }
    }
    index++;
  }
  matches.sort();
  return matches.join(',');
}

bool _isAsciiDigit(String char) =>
    char.isNotEmpty && char.codeUnitAt(0) >= 0x30 && char.codeUnitAt(0) <= 0x39;

bool _isAsciiWordRune(int rune) =>
    (rune >= 0x30 && rune <= 0x39) ||
    (rune >= 0x41 && rune <= 0x5A) ||
    (rune >= 0x61 && rune <= 0x7A);

bool _isCjkRune(int rune) =>
    (rune >= 0x4E00 && rune <= 0x9FFF) || (rune >= 0x3400 && rune <= 0x4DBF);

/// Whether a character belongs to an ASCII identifier name (`m2`, `x_1`).
/// CJK characters are deliberately excluded here: `第1步` contains a real
/// numeric literal, while `m2` is a subscript.
bool _isAsciiIdentifierChar(String char) {
  if (char.isEmpty) {
    return false;
  }
  final rune = char.codeUnitAt(0);
  return _isAsciiWordRune(rune) || rune == 0x5F;
}

// -----------------------------------------------------------------------------
// Math expression parser: rational polynomials over variables.
// -----------------------------------------------------------------------------

/// Exact rational number.
class _Q {
  factory _Q(int numerator, int denominator) {
    if (denominator == 0) {
      throw const FormatException('zero denominator');
    }
    var n = numerator;
    var d = denominator;
    if (d < 0) {
      n = -n;
      d = -d;
    }
    final divisor = _gcd(n.abs(), d);
    return _Q._(n ~/ divisor, d ~/ divisor);
  }

  const _Q._(this.n, this.d);

  factory _Q.fromDecimal(String text) {
    final dot = text.indexOf('.');
    if (dot < 0) {
      return _Q(int.parse(text), 1);
    }
    final whole = text.substring(0, dot);
    final fraction = text.substring(dot + 1);
    final denominator = _pow10(fraction.length);
    final numerator = int.parse(whole.isEmpty ? '0' : whole) * denominator +
        int.parse(fraction.isEmpty ? '0' : fraction);
    return _Q(numerator, denominator);
  }

  final int n;
  final int d;

  static const _Q zero = _Q._(0, 1);
  static const _Q one = _Q._(1, 1);

  bool get isZero => n == 0;

  int get sign => n.sign;

  _Q operator +(_Q other) => _Q(n * other.d + other.n * d, d * other.d);

  _Q operator -(_Q other) => _Q(n * other.d - other.n * d, d * other.d);

  _Q operator *(_Q other) => _Q(n * other.n, d * other.d);

  _Q operator /(_Q other) {
    if (other.isZero) {
      throw const FormatException('division by zero');
    }
    return _Q(n * other.d, d * other.n);
  }

  _Q operator -() => _Q(-n, d);

  _Q get inverse => _Q(d, n);

  String get label => d == 1 ? '$n' : '$n/$d';

  static int _gcd(int a, int b) {
    while (b != 0) {
      final remainder = a % b;
      a = b;
      b = remainder;
    }
    return a == 0 ? 1 : a;
  }

  static int _pow10(int exponent) {
    var value = 1;
    for (var i = 0; i < exponent; i++) {
      value *= 10;
    }
    return value;
  }
}

/// A monomial: variable powers with a canonical string key.
class _Mono {
  _Mono(Map<String, int> powers)
      : powers = Map<String, int>.unmodifiable(_normalizedPowers(powers)),
        key = _keyOf(_normalizedPowers(powers));

  final Map<String, int> powers;
  final String key;

  static final _Mono one = _Mono(const {});

  static Map<String, int> _normalizedPowers(Map<String, int> powers) {
    final result = <String, int>{};
    powers.forEach((name, exponent) {
      if (exponent != 0) {
        result[name] = exponent;
      }
    });
    return result;
  }

  static String _keyOf(Map<String, int> powers) {
    final names = powers.keys.toList()..sort();
    final parts = <String>[];
    for (final name in names) {
      final exponent = powers[name]!;
      parts.add(exponent == 1 ? name : '$name^$exponent');
    }
    return parts.join('*');
  }

  _Mono multiply(_Mono other) {
    final result = <String, int>{...powers};
    other.powers.forEach((name, exponent) {
      result[name] = (result[name] ?? 0) + exponent;
    });
    if (result.length > 32) {
      throw const FormatException('monomial too large');
    }
    return _Mono(result);
  }

  _Mono pow(int exponent) {
    if (exponent < 0) {
      throw const FormatException('negative monomial power');
    }
    var result = _Mono.one;
    for (var i = 0; i < exponent; i++) {
      result = result.multiply(this);
    }
    return result;
  }

  @override
  bool operator ==(Object other) => other is _Mono && other.key == key;

  @override
  int get hashCode => key.hashCode;

  @override
  String toString() => key;
}

/// A polynomial over rationals: monomial -> coefficient.
class _Poly {
  _Poly([Map<_Mono, _Q>? terms])
      : terms = Map<_Mono, _Q>.unmodifiable(_clean(terms ?? const {}));

  factory _Poly.constant(_Q value) =>
      value.isZero ? _Poly() : _Poly({_Mono.one: value});

  factory _Poly.variable(String name) => _Poly({
        _Mono({name: 1}): _Q.one
      });

  final Map<_Mono, _Q> terms;

  static Map<_Mono, _Q> _clean(Map<_Mono, _Q> terms) {
    final result = <_Mono, _Q>{};
    terms.forEach((monomial, coefficient) {
      if (!coefficient.isZero) {
        result[monomial] = coefficient;
      }
    });
    return result;
  }

  bool get isZeroValue => terms.isEmpty;

  /// The value when this polynomial is a non-zero constant, else null.
  _Q? get constantValue {
    if (terms.length != 1) {
      return null;
    }
    final entry = terms.entries.first;
    return entry.key.key.isEmpty ? entry.value : null;
  }

  _Poly add(_Poly other) {
    final result = <_Mono, _Q>{...terms};
    other.terms.forEach((monomial, coefficient) {
      result[monomial] = (result[monomial] ?? _Q.zero) + coefficient;
    });
    return _Poly(result);
  }

  _Poly neg() => _Poly({
        for (final entry in terms.entries) entry.key: -entry.value,
      });

  _Poly sub(_Poly other) => add(other.neg());

  _Poly scale(_Q factor) => _Poly({
        for (final entry in terms.entries) entry.key: entry.value * factor,
      });

  _Poly multiply(_Poly other) {
    if (terms.length * other.terms.length > 4096) {
      throw const FormatException('polynomial expansion too large');
    }
    final result = <_Mono, _Q>{};
    terms.forEach((leftMono, leftCoefficient) {
      other.terms.forEach((rightMono, rightCoefficient) {
        final monomial = leftMono.multiply(rightMono);
        result[monomial] =
            (result[monomial] ?? _Q.zero) + leftCoefficient * rightCoefficient;
      });
    });
    return _Poly(result);
  }

  _Poly pow(int exponent) {
    var result = _Poly.constant(_Q.one);
    for (var i = 0; i < exponent; i++) {
      result = result.multiply(this);
    }
    return result;
  }

  int leadingSign() {
    if (terms.isEmpty) {
      return 0;
    }
    final entry = _sortedEntries().first;
    return entry.value.sign;
  }

  /// Canonical key independent of a non-zero scalar factor.
  String normalizedKey() {
    if (terms.isEmpty) {
      return '0';
    }
    final entries = _sortedEntries();
    final lead = entries.first.value;
    final parts = <String>[];
    for (final entry in entries) {
      final coefficient = entry.value / lead;
      final key = entry.key.key;
      final monoPart = key.isEmpty ? '1' : key;
      if (coefficient.d == 1 && coefficient.n == 1) {
        parts.add(monoPart);
      } else {
        parts.add('${coefficient.label}*$monoPart');
      }
    }
    return parts.join('+');
  }

  List<MapEntry<_Mono, _Q>> _sortedEntries() {
    final entries = terms.entries.toList()
      ..sort((a, b) => a.key.key.compareTo(b.key.key));
    return entries;
  }
}

/// A rational function: numerator / denominator polynomials.
class _Rat {
  factory _Rat(_Poly numerator, [_Poly? denominator]) {
    final den = denominator ?? _Poly.constant(_Q.one);
    if (den.isZeroValue) {
      throw const FormatException('zero denominator polynomial');
    }
    if (numerator.isZeroValue) {
      return _Rat._(_Poly(), _Poly.constant(_Q.one));
    }
    final constant = den.constantValue;
    if (constant != null) {
      return _Rat._(numerator.scale(constant.inverse), _Poly.constant(_Q.one));
    }
    return _Rat._(numerator, den);
  }

  const _Rat._(this.num, this.den);

  final _Poly num;
  final _Poly den;

  static _Rat constant(_Q value) => _Rat(_Poly.constant(value));

  static _Rat variable(String name) => _Rat(_Poly.variable(name));

  _Rat add(_Rat other) => _Rat(
        num.multiply(other.den).add(other.num.multiply(den)),
        den.multiply(other.den),
      );

  _Rat neg() => _Rat(num.neg(), den);

  _Rat sub(_Rat other) => add(other.neg());

  _Rat multiply(_Rat other) =>
      _Rat(num.multiply(other.num), den.multiply(other.den));

  _Rat divide(_Rat other) {
    if (other.num.isZeroValue) {
      throw const FormatException('division by zero');
    }
    return _Rat(num.multiply(other.den), den.multiply(other.num));
  }

  _Rat pow(int exponent) {
    if (exponent == 0) {
      return constant(_Q.one);
    }
    if (exponent < 0) {
      return constant(_Q.one).divide(pow(-exponent));
    }
    var result = constant(_Q.one);
    for (var i = 0; i < exponent; i++) {
      result = result.multiply(this);
    }
    return result;
  }
}

class _Token {
  const _Token(this.kind, this.text);

  final String kind; // num | id | op | '(' | ')'
  final String text;
}

List<_Token> _tokenizeMath(String text) {
  final tokens = <_Token>[];
  var index = 0;
  while (index < text.length) {
    final char = text[index];
    if (_isAsciiDigit(char)) {
      var end = index;
      while (end < text.length && _isAsciiDigit(text[end])) {
        end++;
      }
      if (end + 1 < text.length &&
          text[end] == '.' &&
          _isAsciiDigit(text[end + 1])) {
        end++;
        while (end < text.length && _isAsciiDigit(text[end])) {
          end++;
        }
      }
      tokens.add(_Token('num', text.substring(index, end)));
      index = end;
      continue;
    }
    if (_isIdentifierStart(char)) {
      var end = index;
      while (end < text.length && _isIdentifierPart(text[end])) {
        end++;
      }
      tokens.add(_Token('id', text.substring(index, end)));
      index = end;
      continue;
    }
    if ('+-*/^'.contains(char)) {
      tokens.add(_Token('op', char));
      index++;
      continue;
    }
    if (char == '(') {
      tokens.add(const _Token('(', '('));
      index++;
      continue;
    }
    if (char == ')') {
      tokens.add(const _Token(')', ')'));
      index++;
      continue;
    }
    throw const FormatException('unexpected character');
  }
  return tokens;
}

bool _isIdentifierStart(String char) {
  if (char.isEmpty) {
    return false;
  }
  final rune = char.codeUnitAt(0);
  return (rune >= 0x41 && rune <= 0x5A) ||
      (rune >= 0x61 && rune <= 0x7A) ||
      _isCjkRune(rune);
}

bool _isIdentifierPart(String char) {
  if (char.isEmpty) {
    return false;
  }
  final rune = char.codeUnitAt(0);
  return _isIdentifierStart(char) ||
      _isAsciiDigit(char) ||
      rune == 0x5F ||
      (rune >= 0x0300 && rune <= 0x036F);
}

class _ExpressionParser {
  _ExpressionParser(this.tokens);

  static _Rat parse(String text) {
    final tokens = _tokenizeMath(text);
    if (tokens.isEmpty) {
      throw const FormatException('empty expression');
    }
    return _ExpressionParser(tokens).parseExpression();
  }

  final List<_Token> tokens;
  int position = 0;

  _Token get _current =>
      position < tokens.length ? tokens[position] : const _Token('end', '');

  _Rat parseExpression() {
    final value = _parseExpression();
    if (position != tokens.length) {
      throw const FormatException('trailing tokens');
    }
    return value;
  }

  _Rat _parseExpression() {
    var value = _parseTerm();
    while (true) {
      if (_matchOperator('+')) {
        value = value.add(_parseTerm());
      } else if (_matchOperator('-')) {
        value = value.sub(_parseTerm());
      } else {
        return value;
      }
    }
  }

  _Rat _parseTerm() {
    var value = _parseUnary();
    while (true) {
      if (_matchOperator('*')) {
        value = value.multiply(_parseUnary());
      } else if (_matchOperator('/')) {
        value = value.divide(_parseUnary());
      } else if (_startsFactor()) {
        value = value.multiply(_parseUnary());
      } else {
        return value;
      }
    }
  }

  bool _startsFactor() {
    final token = _current;
    return token.kind == 'num' || token.kind == 'id' || token.kind == '(';
  }

  _Rat _parseUnary() {
    if (_matchOperator('-')) {
      return _parseUnary().neg();
    }
    if (_matchOperator('+')) {
      return _parseUnary();
    }
    return _parsePower();
  }

  _Rat _parsePower() {
    var base = _parsePrimary();
    while (_matchOperator('^')) {
      final exponent = _parseExponent();
      base = base.pow(exponent);
    }
    return base;
  }

  int _parseExponent() {
    var sign = 1;
    if (_matchOperator('-')) {
      sign = -1;
    } else if (_matchOperator('+')) {
      sign = 1;
    }
    final token = _current;
    if (token.kind == '(') {
      position++;
      final inner = _parseExpression();
      if (_current.kind != ')') {
        throw const FormatException('missing ) after exponent');
      }
      position++;
      final constant = inner.num.constantValue;
      if (constant == null || constant.d != 1) {
        throw const FormatException('non-integer exponent');
      }
      final exponent = sign * constant.n;
      if (exponent.abs() > 16) {
        throw const FormatException('exponent too large');
      }
      return exponent;
    }
    if (token.kind != 'num' || token.text.contains('.')) {
      throw const FormatException('non-integer exponent');
    }
    position++;
    final exponent = sign * int.parse(token.text);
    if (exponent.abs() > 16) {
      throw const FormatException('exponent too large');
    }
    return exponent;
  }

  _Rat _parsePrimary() {
    final token = _current;
    if (token.kind == 'num') {
      position++;
      return _Rat.constant(_Q.fromDecimal(token.text));
    }
    if (token.kind == 'id') {
      position++;
      // Function call syntax (sin(x), log(x)) is deliberately unsupported: the
      // AST would need function semantics to be sound, and guessing is worse
      // than refusing to merge.
      if (_current.kind == '(') {
        throw const FormatException('functions are not supported');
      }
      return _Rat.variable(token.text);
    }
    if (token.kind == '(') {
      position++;
      final value = _parseExpression();
      if (_current.kind != ')') {
        throw const FormatException('missing )');
      }
      position++;
      return value;
    }
    throw const FormatException('unexpected token');
  }

  bool _matchOperator(String operator) {
    final token = _current;
    if (token.kind == 'op' && token.text == operator) {
      position++;
      return true;
    }
    return false;
  }
}
