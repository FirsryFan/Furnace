import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/features/anki/application/review_service.dart';

/// Judging an answer used to have exactly one answer: strict characters.
///
/// These are the three modes the practice screen offers, tested where the
/// verdict is actually produced, because "the screen offers a lenient button"
/// and "lenient grading accepts what a human accepts" are different claims.
void main() {
  group('strict mode keeps annotation 18 intact', () {
    test('nothing is normalised', () {
      expect(ReviewService.strictMatch('叶绿体', '叶绿体'), isTrue);
      expect(ReviewService.strictMatch('叶绿体', ' 叶绿体'), isFalse,
          reason: 'no whitespace trimming');
      expect(ReviewService.strictMatch('叶绿体', '叶 绿 体'), isFalse);
      expect(ReviewService.strictMatch('ATP', 'atp'), isFalse,
          reason: 'case matters for spelling practice');
      expect(ReviewService.strictMatch('ATP', 'ＡＴＰ'), isFalse,
          reason: 'full-width characters are different characters');
      expect(ReviewService.strictMatch('光合作用，场所', '光合作用,场所'), isFalse);
      expect(ReviewService.strictMatch('叶绿体', '叶绿休'), isFalse,
          reason: 'a typo is still a wrong answer in dictation');
    });

    test('every lenient acceptance below is a strict rejection', () {
      const pairs = [
        ['叶绿体', '叶 绿 体'],
        ['ATP', 'atp'],
        ['ATP', 'ＡＴＰ'],
        ['光合作用，场所', '光合作用,场所'],
        ['叶绿体。', '叶绿体'],
        ['叶绿体', '叶绿休'],
      ];
      for (final pair in pairs) {
        expect(ReviewService.strictMatch(pair[0], pair[1]), isFalse,
            reason: '${pair[0]} vs ${pair[1]}');
      }
    });
  });

  group('lenient mode accepts what a human would', () {
    test('whitespace, including inside the answer', () {
      expect(ReviewService.lenientMatch('叶绿体', ' 叶绿体 '), isTrue);
      expect(ReviewService.lenientMatch('叶绿体', '叶 绿 体'), isTrue);
      expect(ReviewService.lenientMatch('ATP', 'A T P'), isTrue);
    });

    test('case and full-width forms', () {
      expect(ReviewService.lenientMatch('ATP', 'atp'), isTrue);
      expect(ReviewService.lenientMatch('ATP', 'ＡＴＰ'), isTrue);
      expect(ReviewService.lenientMatch('abc', 'ABC'), isTrue);
    });

    test('Chinese and English punctuation', () {
      expect(ReviewService.lenientMatch('光合作用，场所', '光合作用,场所'), isTrue);
      expect(ReviewService.lenientMatch('叶绿体。', '叶绿体'), isTrue);
      expect(ReviewService.lenientMatch('叶绿体', '叶绿体!'), isTrue);
      expect(ReviewService.lenientMatch('（叶绿体）', '叶绿体'), isTrue);
    });

    test('a small typo budget, scaled to the answer length', () {
      expect(ReviewService.lenientMatch('叶绿体', '叶绿休'), isTrue);
      expect(
        ReviewService.lenientMatch('photosynthesis', 'photosinthesis'),
        isTrue,
      );
      expect(ReviewService.typoBudgetFor(1), 1);
      expect(ReviewService.typoBudgetFor(3), 1);
      expect(ReviewService.typoBudgetFor(11), 1);
      expect(ReviewService.typoBudgetFor(12), 2);
    });

    test('the typo budget never turns a different answer into a right one', () {
      expect(ReviewService.lenientMatch('叶绿体', '线粒体'), isFalse,
          reason: 'two wrong characters out of three is a different fact');
      expect(ReviewService.lenientMatch('光合作用', '呼吸作用'), isFalse);
      expect(ReviewService.lenientMatch('1/2', '0.5'), isFalse);
      expect(ReviewService.lenientMatch('叶绿体', '叶绿'), isFalse,
          reason: 'a missing character is not a typo');
      expect(ReviewService.lenientMatch('叶绿体', '叶绿体细胞'), isFalse);
      expect(ReviewService.lenientMatch('叶绿体', ''), isFalse);
      expect(ReviewService.lenientMatch('', '叶绿体'), isFalse);
    });

    test('normalisation is the documented one', () {
      expect(ReviewService.normalizeForLenient('Ａ ＴＰ。'), 'atp');
      expect(ReviewService.normalizeForLenient('光合作用，场所'), '光合作用场所');
      expect(
          ReviewService.normalizeForLenient('  Hello World  '), 'helloworld');
    });
  });

  group('a choice card is judged by option identity', () {
    const options = ['线粒体', '叶绿体', '细胞核'];

    test('the option the card names must be the option tapped', () {
      expect(
        ReviewService.mcqMatch(
          options: options,
          answer: '叶绿体',
          selected: '叶绿体',
        ),
        isTrue,
      );
      expect(
        ReviewService.mcqMatch(
          options: options,
          answer: '叶绿体',
          selected: '线粒体',
        ),
        isFalse,
      );
    });

    test('text is compared only as a choice, never leniently', () {
      expect(
        ReviewService.mcqMatch(
          options: options,
          answer: '叶绿体',
          selected: '叶绿休',
        ),
        isFalse,
        reason: 'a choice is right or wrong, there is no typo in tapping',
      );
      expect(
        ReviewService.mcqMatch(
          options: options,
          answer: ' 叶绿体 ',
          selected: '叶绿体',
        ),
        isTrue,
        reason: 'only the stored answer is normalised, not the tap',
      );
    });

    test('an answer written as a letter finds its option', () {
      const withLetters = ['A. 线粒体', 'B、叶绿体', 'C) 细胞核'];
      expect(
          ReviewService.correctOptionIndex(options: withLetters, answer: 'B'),
          1);
      expect(
          ReviewService.correctOptionIndex(options: withLetters, answer: 'c'),
          2);
      expect(
        ReviewService.mcqMatch(
          options: withLetters,
          answer: 'B',
          selected: 'B、叶绿体',
        ),
        isTrue,
      );
      expect(
        ReviewService.mcqMatch(
          options: withLetters,
          answer: 'B',
          selected: 'A. 线粒体',
        ),
        isFalse,
      );
    });

    test('an unjudgeable card asks the user instead of guessing', () {
      expect(
        ReviewService.mcqMatch(
          options: options,
          answer: '高尔基体',
          selected: '叶绿体',
        ),
        isNull,
        reason: 'the stored answer names no option',
      );
      expect(
        ReviewService.mcqMatch(
          options: const [],
          answer: '叶绿体',
          selected: '叶绿体',
        ),
        isNull,
      );
      expect(
        ReviewService.mcqMatch(
          options: options,
          answer: '叶绿体',
          selected: null,
        ),
        isNull,
      );
    });
  });
}
