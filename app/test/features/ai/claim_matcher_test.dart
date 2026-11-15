import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/features/ai/domain/claim.dart';
import 'package:furnace/features/ai/domain/claim_matcher.dart';

Claim _claim(String text, {String? id}) => Claim(
      id: id ?? 'claim-$text',
      kind: ClaimKind.assumption,
      canonical: text,
      statement: text,
    );

class _FakeJudge implements ClaimJudge {
  _FakeJudge(this.verdict);

  final bool? verdict;
  int calls = 0;

  @override
  Future<bool?> sameProposition(Claim a, Claim b) async {
    calls++;
    return verdict;
  }
}

void main() {
  group('ClaimTextNormalizer', () {
    test('folds unicode subscripts, spaces and punctuation', () {
      expect(
        ClaimTextNormalizer.normalize('因此，m₂/m₁ = 7。'),
        'm2/m1=7',
      );
    });

    test('folds LaTeX fractions and subscripts', () {
      expect(
        ClaimTextNormalizer.normalize(r'\frac{m_2}{m_1} = 7'),
        '(m2)/(m1)=7',
      );
    });

    test('normalizes copula and degree unit', () {
      expect(
        ClaimTextNormalizer.normalize('三角形内角和为180度'),
        '三角形内角和=180°',
      );
      expect(
        ClaimTextNormalizer.normalize('三角形内角和是180°'),
        '三角形内角和=180°',
      );
    });

    test('maps direction synonym families onto one canonical word', () {
      expect(
        ClaimTextNormalizer.normalize('温度升高'),
        ClaimTextNormalizer.normalize('温度增大'),
      );
      expect(
        ClaimTextNormalizer.normalize('温度降低'),
        ClaimTextNormalizer.normalize('温度减小'),
      );
    });

    test('drops a leading discourse marker', () {
      expect(
        ClaimTextNormalizer.normalize('因为小球做匀速圆周运动'),
        '小球做匀速圆周运动',
      );
    });

    test('normalizes ratio colons to division', () {
      expect(ClaimTextNormalizer.normalize('m2：m1 = 7'), 'm2/m1=7');
    });
  });

  group('ClaimMatcher tiers', () {
    test('exact canonical text merges at the exact tier', () async {
      final matcher = ClaimMatcher();
      final result = await matcher.match(
        _claim('m2/m1=7'),
        _claim('m2/m1=7', id: 'other'),
      );
      expect(result.merge, isTrue);
      expect(result.tier, ClaimMatchTier.exact);
      expect(result.possiblyDuplicate, isFalse);
    });

    test('wordings identical after normalization merge', () async {
      final matcher = ClaimMatcher();
      final result = await matcher.match(
        _claim('m₂/m₁ = 7'),
        _claim('m_2/m_1=7', id: 'other'),
      );
      expect(result.merge, isTrue);
      expect(result.tier, ClaimMatchTier.normalized);
    });

    test('copula/unit synonyms merge after normalization', () async {
      final matcher = ClaimMatcher();
      final result = await matcher.match(
        _claim('三角形内角和为180度'),
        _claim('三角形内角和是180°', id: 'other'),
      );
      expect(result.merge, isTrue);
      expect(result.tier, ClaimMatchTier.normalized);
    });

    test('symmetric relation operands merge at the structured tier', () async {
      final matcher = ClaimMatcher();
      final result = await matcher.match(
        _claim('7=m2/m1'),
        _claim('m2/m1=7', id: 'other'),
      );
      expect(result.merge, isTrue);
      expect(result.tier, ClaimMatchTier.structured);
    });

    test('LaTeX fraction is equivalent through the math AST', () async {
      final matcher = ClaimMatcher();
      final result = await matcher.match(
        _claim(r'\frac{m_2}{m_1}=7'),
        _claim('m2/m1=7', id: 'other'),
      );
      expect(result.merge, isTrue);
      expect(result.tier, ClaimMatchTier.math);
    });

    test('scaled equation and divided equation are the same claim', () async {
      final matcher = ClaimMatcher();
      final result = await matcher.match(
        _claim('m2=7m1'),
        _claim('m2/m1=7', id: 'other'),
      );
      expect(result.merge, isTrue);
      expect(result.tier, ClaimMatchTier.math);
    });

    test('decimal and fraction values are equivalent', () async {
      final matcher = ClaimMatcher();
      final result = await matcher.match(
        _claim('x=0.5'),
        _claim('x=1/2', id: 'other'),
      );
      expect(result.merge, isTrue);
      expect(result.tier, ClaimMatchTier.math);
    });

    test('inequality chain order does not matter', () async {
      final matcher = ClaimMatcher();
      final result = await matcher.match(
        _claim('17/2≤E_{k0}≤12'),
        _claim('12≥E_{k0}≥17/2', id: 'other'),
      );
      expect(result.merge, isTrue);
      expect(result.tier, ClaimMatchTier.math);
    });

    test('commutative math is equivalent through the AST', () async {
      final mathA = CanonicalMathClaim.parse('a=b+c');
      final mathB = CanonicalMathClaim.parse('a=c+b');
      expect(mathA, isNotNull);
      expect(mathB, isNotNull);
      expect(mathA!.key, mathB!.key);
      final matcher = ClaimMatcher();
      final result = await matcher.match(
        _claim('a=b+c'),
        _claim('a=c+b', id: 'other'),
      );
      expect(result.merge, isTrue);
      expect(result.tier, ClaimMatchTier.math);
    });
  });

  group('ClaimMatcher refuses uncertain matches', () {
    test('different numeric literal is a definite difference', () async {
      final matcher = ClaimMatcher();
      final result = await matcher.match(
        _claim('3x=6'),
        _claim('3x=7', id: 'other'),
      );
      expect(result.merge, isFalse);
      expect(result.possiblyDuplicate, isFalse);
      expect(result.reason, contains('numeric literals differ'));
    });

    test('opposite polarity words are a definite difference', () async {
      final matcher = ClaimMatcher();
      final result = await matcher.match(
        _claim('电场方向由高电势指向低电势'),
        _claim('电场方向由低电势指向高电势', id: 'other'),
      );
      expect(result.merge, isFalse);
      expect(result.possiblyDuplicate, isFalse);
      expect(result.reason, contains('polarity words differ'));
    });

    test('a longer paraphrase is kept apart as possibly duplicate', () async {
      final matcher = ClaimMatcher();
      final result = await matcher.match(
        _claim('小球在光滑水平面上做匀速圆周运动'),
        _claim('小球在光滑水平面上做匀速圆周运动且线速度指向圆心', id: 'other'),
      );
      expect(result.merge, isFalse);
      expect(result.possiblyDuplicate, isTrue);
      expect(result.tier, ClaimMatchTier.none);
    });

    test('unrelated statements do not merge', () async {
      final matcher = ClaimMatcher();
      final result = await matcher.match(
        _claim('牛顿第一定律'),
        _claim('细胞膜具有选择透过性', id: 'other'),
      );
      expect(result.merge, isFalse);
      expect(result.possiblyDuplicate, isFalse);
      expect(result.tier, ClaimMatchTier.none);
    });

    test('same tokens in different order are not merged as a token bag',
        () async {
      final matcher = ClaimMatcher();
      final result = await matcher.match(
        _claim('a=b-c'),
        _claim('a=c-b', id: 'other'),
      );
      expect(result.merge, isFalse);
      expect(result.possiblyDuplicate, isFalse);
    });
  });

  group('ClaimMatcher optional judge', () {
    final left = _claim('小球在光滑水平面上做匀速圆周运动');
    final right = _claim(
      '小球在光滑水平面上做匀速圆周运动且线速度指向圆心',
      id: 'other',
    );

    test('judge confirms same proposition', () async {
      final judge = _FakeJudge(true);
      final matcher = ClaimMatcher(judge: judge);
      final result = await matcher.match(left, right);
      expect(result.merge, isTrue);
      expect(result.tier, ClaimMatchTier.judge);
      expect(judge.calls, 1);
    });

    test('judge rejection keeps claims apart', () async {
      final judge = _FakeJudge(false);
      final matcher = ClaimMatcher(judge: judge);
      final result = await matcher.match(left, right);
      expect(result.merge, isFalse);
      expect(result.possiblyDuplicate, isFalse);
      expect(result.reason, contains('judge rejected'));
    });

    test('judge abstention leaves the pair as possibly duplicate', () async {
      final judge = _FakeJudge(null);
      final matcher = ClaimMatcher(judge: judge);
      final result = await matcher.match(left, right);
      expect(result.merge, isFalse);
      expect(result.possiblyDuplicate, isTrue);
      expect(judge.calls, 1);
    });

    test('judge is not consulted for definite differences', () async {
      final judge = _FakeJudge(true);
      final matcher = ClaimMatcher(judge: judge);
      final result = await matcher.match(
        _claim('3x=6'),
        _claim('3x=7', id: 'other'),
      );
      expect(result.merge, isFalse);
      expect(judge.calls, 0);
    });
  });

  group('ClaimMatcher.find', () {
    test('returns null when there are no candidates', () async {
      final matcher = ClaimMatcher();
      expect(await matcher.find(_claim('x=1'), const []), isNull);
    });

    test('picks the merged candidate over a weaker one', () async {
      final matcher = ClaimMatcher();
      final result = await matcher.find(
        _claim('m2/m1=7'),
        [
          _claim('m2/m1=8', id: 'wrong'),
          _claim('m2/m1=7', id: 'right'),
        ],
      );
      expect(result, isNotNull);
      expect(result!.merge, isTrue);
      expect(result.matched!.id, 'right');
    });

    test('uses the judge at most once, for the best uncertain candidate',
        () async {
      final judge = _FakeJudge(true);
      final matcher = ClaimMatcher(judge: judge);
      final result = await matcher.find(
        _claim('小球在光滑水平面上做匀速圆周运动'),
        [
          _claim(
            '小球在光滑水平面上做匀速圆周运动且线速度指向圆心',
            id: 'similar',
          ),
          _claim('牛顿第一定律', id: 'unrelated'),
        ],
      );
      expect(result, isNotNull);
      expect(result!.merge, isTrue);
      expect(judge.calls, 1);
    });
  });
}
