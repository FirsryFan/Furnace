import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/repository_providers.dart';
import '../../../domain/services/srs/review_retention.dart';

/// The review-spacing choice shown in 复习偏好 (schema v36, 轮次一百七十五).
///
/// Reads the stored target retention and maps it to the closest of the three
/// named choices; a null (never picked) or out-of-range value becomes 标准
/// (0.85) through [ReviewSpacing.fromRetention] — the same normalization the
/// review engine applies when it schedules, so the UI cannot show one thing and
/// the scheduler use another.
final reviewRetentionProvider =
    FutureProvider.autoDispose<ReviewSpacing>((ref) async {
  final repository = ref.watch(settingsRepositoryProvider);
  return ReviewSpacing.fromRetention(await repository.getReviewRetention());
});

/// Persists [spacing] and refreshes the provider the preferences card watches.
///
/// A write failure is left to the caller: the card has no snackbar of its own
/// and the stored value simply stays what it was, which is the honest outcome.
Future<void> selectReviewSpacing(WidgetRef ref, ReviewSpacing spacing) async {
  final repository = ref.read(settingsRepositoryProvider);
  await repository.updateReviewRetention(spacing.retention);
  try {
    ref.invalidate(reviewRetentionProvider);
  } on StateError {
    // The dialog was closed while the write was in flight; the next open reads
    // the stored value anyway.
  }
}
