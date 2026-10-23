/// 自测作答统计：由「判分成功的作答条数」与「其中答对的条数」派生出的只读视图。
///
/// 只做纯计算：不落库、不依赖 Flutter 或数据层。百分比 [QuestionAttemptStats.percent]
/// 四舍五入到 0..100；还没有任何判分成功的作答（[QuestionAttemptStats.isEmpty]）时
/// 返回 0，调用方应先看 [QuestionAttemptStats.isEmpty] 再决定是否显示百分比。
library;

/// 一道题（或一组题）的自测统计。
///
/// [total] 是判分成功的作答总条数（没判分的不算），[correct] 是其中答对的条数。
/// 构造时用 assert 保证 `0 <= correct <= total`；违反时在 debug/测试环境抛
/// [AssertionError]，release 环境不做检查。
class QuestionAttemptStats {
  const QuestionAttemptStats({required this.total, required this.correct})
      : assert(total >= 0, 'total 不能为负数'),
        assert(correct >= 0, 'correct 不能为负数'),
        assert(correct <= total, 'correct 不能大于 total');

  /// 没有作答记录时的常量（total 0 / correct 0）。
  static const QuestionAttemptStats empty =
      QuestionAttemptStats(total: 0, correct: 0);

  /// 判分成功的作答总条数。
  final int total;

  /// 其中答对的条数。
  final int correct;

  /// 答错的条数（total - correct）。
  int get incorrect => total - correct;

  /// 还没有任何判分成功的作答。
  bool get isEmpty => total == 0;

  /// 至少有一条判分成功的作答。
  bool get isNotEmpty => total > 0;

  /// 正确率百分比，0..100 四舍五入；[total] 为 0 时返回 0（不是 NaN）。
  int get percent => total == 0 ? 0 : ((correct * 100) / total).round();
}
