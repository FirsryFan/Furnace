import '../../../data/repositories/anki_repository.dart';

class AnkiStats {
  const AnkiStats({
    required this.knowledgePointCount,
    required this.templateCount,
    required this.dueCardCount,
    required this.reviewCount7d,
    required this.reviewCounts7d,
  });

  final int knowledgePointCount;
  final int templateCount;
  final int dueCardCount;
  final int reviewCount7d;
  final List<int> reviewCounts7d;
}

/// Loads simple review statistics for the management page.
class AnkiStatsService {
  AnkiStatsService(this._repository);

  final AnkiRepository _repository;

  Future<AnkiStats> load() async {
    final kps = await _repository.getKnowledgePoints();
    final templates = await _repository.getAllTemplates();
    final dueStates = await _repository.getDueCardStates(
      DateTime.now().millisecondsSinceEpoch,
    );
    final weekAgo = DateTime.now()
        .subtract(const Duration(days: 7))
        .millisecondsSinceEpoch;
    final reviewCount7d = await _repository.countReviewsSince(weekAgo);
    final reviewCounts7d = await _repository.getReviewCountsPerDay(7);
    return AnkiStats(
      knowledgePointCount: kps.length,
      templateCount: templates.length,
      dueCardCount: dueStates.length,
      reviewCount7d: reviewCount7d,
      reviewCounts7d: reviewCounts7d,
    );
  }
}
