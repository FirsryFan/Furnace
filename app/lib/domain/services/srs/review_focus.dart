/// 考前把「未来 N 天内到期」的闪存卡提前到今天（用户 2026-10-26 提出：下周要
/// 考试，某些板块的内容要提前进复习）。
///
/// 纯逻辑：只决定**哪些卡要被拉、拉之前的 due_at 是多少**，不碰数据库、不看
/// FSRS 的 stability/difficulty。提前复习不修改记忆状态——真正作答时
/// `ReviewService.grade` 照常按「现在」重新排期（早复习天然得到更短的间隔），
/// 所以这里唯一的写动作是把 `due_at` 挪到今天。
///
/// 三条边界写死在这里，调用方（AI 工具）不再各判一次：
///  1. **新卡不拉**：`repetitions <= 0`（或 state 还是 new）表示从没复习过，
///     它不属于「到期」，拉了只会把新卡提前塞进今天；
///  2. **已经到期的不动**：`due_at == null`（NULL 在队列口径里就是现在到期）
///     或 `due_at <= now`，本来就会出现在今天的队列里；
///  3. **更远的不动**：超过 horizon 的卡不提前，否则「下周考试」会把一个学期
///     的卡全都拉进来。
library;

/// 一张卡的最小快照，字段与 `card_states` 对应（只取决定是否拉动所需的）。
class ReviewFocusCard {
  const ReviewFocusCard({
    required this.cardStateId,
    required this.knowledgePointId,
    required this.dueAt,
    required this.repetitions,
    required this.state,
  });

  final String cardStateId;
  final String knowledgePointId;

  /// 到期时间（epoch ms）。NULL 表示「现在就到期」，与
  /// `AnkiRepository.getDueCardStates` 的口径一致。
  final int? dueAt;

  /// 已作答次数：<= 0 表示从没复习过。
  final int repetitions;

  /// `card_states.state`（new / review / …），只用于给新卡判定兜底。
  final String state;
}

/// 一张要被提前的卡，带着它原来的到期时间（undo 与模型返回都用得到）。
class ReviewFocusPull {
  const ReviewFocusPull({
    required this.cardStateId,
    required this.knowledgePointId,
    required this.previousDueAt,
  });

  final String cardStateId;
  final String knowledgePointId;

  /// 拉之前的 `due_at`（一定非空：只有未来到期的卡才会被拉）。
  final int previousDueAt;
}

/// [planReviewFocus] 的结果：要拉的卡 + 各类没拉的卡的计数。
class ReviewFocusPlan {
  const ReviewFocusPlan({
    required this.pulled,
    required this.alreadyDue,
    required this.tooFar,
    required this.newCards,
    required this.beyondLimit,
    required this.total,
  });

  /// 会被提前到今天（并按原到期时间从近到远排序）的卡。
  final List<ReviewFocusPull> pulled;

  /// 已经在今天队列里的卡（`due_at` NULL 或 <= now）。
  final int alreadyDue;

  /// 超过 horizon、这次不动的卡。
  final int tooFar;

  /// 新卡（从没复习过），一律不拉。
  final int newCards;

  /// 符合条件但被 [planReviewFocus] 的 limit 截掉的卡。
  final int beyondLimit;

  /// 参与判断的卡总数（= pulled + alreadyDue + tooFar + newCards + beyondLimit）。
  final int total;

  bool get isEmpty => pulled.isEmpty;
}

/// 从 [cards] 里挑出「未来 [horizon] 内到期」的卡，按原到期时间从近到远排序。
///
/// [limit] 是单次最多拉多少张（防止一次把整库拉进来）；超出部分计入
/// [ReviewFocusPlan.beyondLimit]，调用方可以提示「还有 N 张没拉，可加大 limit」。
/// 排序在截断之前完成，所以被截掉的永远是**最晚到期**的那批。
ReviewFocusPlan planReviewFocus({
  required Iterable<ReviewFocusCard> cards,
  required DateTime now,
  Duration horizon = const Duration(days: 7),
  int limit = 500,
}) {
  if (limit < 0) {
    throw ArgumentError.value(limit, 'limit', '不能是负数');
  }
  final nowMs = now.millisecondsSinceEpoch;
  final horizonMs = nowMs + horizon.inMilliseconds;
  final candidates = <ReviewFocusPull>[];
  var alreadyDue = 0;
  var tooFar = 0;
  var newCards = 0;
  var total = 0;

  for (final card in cards) {
    total++;
    if (card.repetitions <= 0 || card.state == 'new') {
      newCards++;
      continue;
    }
    final due = card.dueAt;
    if (due == null || due <= nowMs) {
      alreadyDue++;
      continue;
    }
    if (due > horizonMs) {
      tooFar++;
      continue;
    }
    candidates.add(ReviewFocusPull(
      cardStateId: card.cardStateId,
      knowledgePointId: card.knowledgePointId,
      previousDueAt: due,
    ));
  }

  candidates.sort((a, b) {
    final byDue = a.previousDueAt.compareTo(b.previousDueAt);
    return byDue != 0 ? byDue : a.cardStateId.compareTo(b.cardStateId);
  });
  final take = candidates.length <= limit ? candidates.length : limit;
  return ReviewFocusPlan(
    pulled: List<ReviewFocusPull>.unmodifiable(candidates.take(take)),
    alreadyDue: alreadyDue,
    tooFar: tooFar,
    newCards: newCards,
    beyondLimit: candidates.length - take,
    total: total,
  );
}
