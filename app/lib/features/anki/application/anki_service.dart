import '../../../data/repositories/anki_repository.dart';
import '../../../domain/services/srs/sm2_scheduler.dart';

/// Application service that connects the Anki repository with the SM-2
/// scheduler.
class AnkiService {
  AnkiService(this._repository);

  final AnkiRepository _repository;

  /// Records a review for [cardTemplateId] using [rating].
  ///
  /// Creates a CardState on first review, updates the SM-2 scheduling fields,
  /// and writes a ReviewLog entry.
  Future<void> reviewCard({
    required String cardTemplateId,
    required SrsRating rating,
    required DateTime now,
  }) async {
    final state = await _repository.getOrCreateCardState(cardTemplateId);

    // Use the provided review time for scheduling.
    final result = Sm2Scheduler.review(
      current: SrsState(
        repetitions: state.repetitions,
        easeFactor: state.ease,
        intervalDays: state.intervalDays,
        dueAt: state.dueAt == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(state.dueAt!),
      ),
      rating: rating,
      now: now,
    );

    await _repository.updateCardState(
      state.id,
      dueAt: result.nextDueAt.millisecondsSinceEpoch,
      intervalDays: result.state.intervalDays,
      ease: result.state.easeFactor,
      repetitions: result.state.repetitions,
      lapses: rating == SrsRating.forgot ? state.lapses + 1 : state.lapses,
      state: _stateName(result.state.repetitions),
      lastReviewedAt: now.millisecondsSinceEpoch,
    );

    await _repository.addReviewLog(
      cardStateId: state.id,
      cardTemplateId: cardTemplateId,
      rating: rating.index,
      reviewedAt: now.millisecondsSinceEpoch,
    );
  }

  String _stateName(int repetitions) {
    if (repetitions == 0) {
      return 'learning';
    }
    if (repetitions < 2) {
      return 'learning';
    }
    return 'review';
  }
}
