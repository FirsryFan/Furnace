/// 7 档自判 →（FSRS rating × MindNet 事件语义）映射的验收点。
///
/// 用户要的是「反馈分 7 档，区分算法与 MindNet 语义」：这一层是唯一映射点，
/// 所以每个档位的两侧数值都钉死，改一个数就必须改一次测试。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/srs/fsrs_scheduler.dart';
import 'package:furnace/features/anki/application/review_rating_tier.dart';

void main() {
  test('7 档齐全，表与枚举一一对应', () {
    expect(kReviewRatingMappings, hasLength(7));
    for (final tier in ReviewRatingTier.values) {
      final mapping = reviewRatingMappingOf(tier);
      expect(mapping.tier, tier, reason: '表项自己知道是哪一档');
    }
  });

  test('成功三档：1 完全熟练 → Easy / 2 比较熟练 → Good / 3 艰难想起 → Hard', () {
    final perfect = reviewRatingMappingOf(ReviewRatingTier.perfect);
    final easy = reviewRatingMappingOf(ReviewRatingTier.easy);
    final hard = reviewRatingMappingOf(ReviewRatingTier.hard);

    expect(perfect.fsrsRating, FsrsRating.easy);
    expect(easy.fsrsRating, FsrsRating.good);
    expect(hard.fsrsRating, FsrsRating.hard);
    for (final mapping in <ReviewRatingMapping>[perfect, easy, hard]) {
      expect(mapping.correct, isTrue);
      expect(mapping.reviewedSolution, isFalse);
      expect(mapping.mindnetEvent, kMindnetRetrievalSuccess);
      expect(mapping.isFailure, isFalse);
      expect(mapping.isNewKnowledge, isFalse);
    }
    // 完全熟练必须比比较熟练推得更远（Easy > Good > Hard 的数值序）。
    expect(perfect.fsrsValue, greaterThan(easy.fsrsValue));
    expect(easy.fsrsValue, greaterThan(hard.fsrsValue));
  });

  test('4/5 档：部分想起/有印象 ⇒ 失败但带 closeness（failure_feedback）', () {
    final partial = reviewRatingMappingOf(ReviewRatingTier.partial);
    final vague = reviewRatingMappingOf(ReviewRatingTier.vague);

    for (final mapping in <ReviewRatingMapping>[partial, vague]) {
      expect(mapping.correct, isFalse);
      expect(mapping.fsrsRating, FsrsRating.again);
      expect(mapping.reviewedSolution, isTrue, reason: '这两档是「看了答案还能认出来」的失败');
      expect(mapping.mindnetEvent, kMindnetFailureFeedback);
    }
    expect(partial.closeness, kTierPartialCloseness);
    expect(vague.closeness, kTierVagueCloseness);
    expect(partial.closeness, greaterThan(vague.closeness),
        reason: '想起一部分比只有印象更接近成功');
  });

  test('6/7 档：完全没印象/新知识 ⇒ 裸失败（lapse）', () {
    final blank = reviewRatingMappingOf(ReviewRatingTier.blank);
    final fresh = reviewRatingMappingOf(ReviewRatingTier.newKnowledge);

    for (final mapping in <ReviewRatingMapping>[blank, fresh]) {
      expect(mapping.correct, isFalse);
      expect(mapping.fsrsRating, FsrsRating.again);
      expect(mapping.reviewedSolution, isFalse, reason: '裸失败不冒充「读过答案的失败」');
      expect(mapping.mindnetEvent, kMindnetLapse);
    }
    expect(blank.isNewKnowledge, isFalse);
    expect(fresh.isNewKnowledge, isTrue,
        reason: '第 7 档的 knowledge 语义要能被上层认出来（事件层将来用）');
  });

  test('四档失败在算法侧都落到 Again，差别只在 MindNet 侧', () {
    for (final tier in <ReviewRatingTier>[
      ReviewRatingTier.partial,
      ReviewRatingTier.vague,
      ReviewRatingTier.blank,
      ReviewRatingTier.newKnowledge,
    ]) {
      expect(reviewRatingMappingOf(tier).fsrsRating, FsrsRating.again);
    }
  });
}
