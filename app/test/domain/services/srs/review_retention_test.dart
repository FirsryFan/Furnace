import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/srs/review_retention.dart';

/// 复习间隔的目标保持率（schema v36，轮次一百七十五）：用户反馈的「间隔太短」
/// 靠把 FSRS 的 requestRetention 从写死的 0.9 改成可选的 0.80/0.85/0.90 解决。
/// 这些用例锁住两件事：三点映射是单调的（越低=间隔越长），坏值永远回落到出厂值。
void main() {
  group('normalizeReviewRetention', () {
    test('null / NaN / 无穷回落到出厂 0.85', () {
      expect(normalizeReviewRetention(null), kDefaultReviewRetention);
      expect(normalizeReviewRetention(double.nan), kDefaultReviewRetention);
      expect(
          normalizeReviewRetention(double.infinity), kDefaultReviewRetention);
      expect(normalizeReviewRetention(double.negativeInfinity),
          kDefaultReviewRetention);
    });

    test('合法值原样保留，不被拍平成三个预设', () {
      expect(normalizeReviewRetention(0.82), 0.82);
      expect(normalizeReviewRetention(0.87), 0.87);
      expect(normalizeReviewRetention(0.85), kDefaultReviewRetention);
    });

    test('越界值夹到 0.75..0.95', () {
      expect(normalizeReviewRetention(-3), kReviewRetentionMin);
      expect(normalizeReviewRetention(0.1), kReviewRetentionMin);
      expect(normalizeReviewRetention(0.999), kReviewRetentionMax);
      expect(normalizeReviewRetention(100), kReviewRetentionMax);
    });
  });

  group('ReviewSpacing', () {
    test('三个挡位的保持率是 0.80 / 0.85 / 0.90', () {
      expect(ReviewSpacing.longer.retention, 0.80);
      expect(ReviewSpacing.standard.retention, 0.85);
      expect(ReviewSpacing.shorter.retention, 0.90);
      expect(kDefaultReviewRetention, ReviewSpacing.standard.retention);
    });

    test('保持率越低，间隔越长：三点严格单调', () {
      expect(ReviewSpacing.longer.retention,
          lessThan(ReviewSpacing.standard.retention));
      expect(ReviewSpacing.standard.retention,
          lessThan(ReviewSpacing.shorter.retention));
    });

    test('fromRetention 在三个值上精确往返', () {
      for (final spacing in ReviewSpacing.values) {
        expect(ReviewSpacing.fromRetention(spacing.retention), spacing);
      }
    });

    test('fromRetention 对未挑选/坏值回落标准', () {
      expect(ReviewSpacing.fromRetention(null), ReviewSpacing.standard);
      expect(ReviewSpacing.fromRetention(double.nan), ReviewSpacing.standard);
      expect(ReviewSpacing.fromRetention(0.2), ReviewSpacing.longer,
          reason: '夹到 0.75 后仍在 更长 一侧');
    });

    test('fromRetention 落在中点两侧就近取', () {
      // 0.80 与 0.85 的中点是 0.825：低于它读作 更长，高于/等于它读作 标准。
      expect(ReviewSpacing.fromRetention(0.82), ReviewSpacing.longer);
      expect(ReviewSpacing.fromRetention(0.83), ReviewSpacing.standard);
      // 0.85 与 0.90 的中点是 0.875。
      expect(ReviewSpacing.fromRetention(0.87), ReviewSpacing.standard);
      expect(ReviewSpacing.fromRetention(0.88), ReviewSpacing.shorter);
    });

    test('未来细分的合法值也落在一个挡位上，不会空显示', () {
      expect(ReviewSpacing.fromRetention(0.755), ReviewSpacing.longer);
      expect(ReviewSpacing.fromRetention(0.945), ReviewSpacing.shorter);
    });
  });
}
