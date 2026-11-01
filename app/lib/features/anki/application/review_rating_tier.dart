/// 7 档自判反馈：按钮 →（FSRS rating × MindNet 事件语义）的唯一映射点。
///
/// 用户 2026-11-02 的口径：闪存卡默认由用户自判，反馈分 7 档；档位既要决定
/// FSRS 排期，也要给 MindNet 一个不同的事件/数值。**这不是两套判断**：
///
///  * 算法侧：每一档映射到 [FsrsRating] 四档之一（Again/Hard/Good/Easy），由
///    `ReviewService.grade` 交给 FSRS 排期 —— 与自动判分走同一条写路径；
///  * MindNet 侧：成功档（1–3）按 `retrieval_success` 记；4/5 档是「部分想起 /
///    有印象」的失败，按 `retrieval_failure_feedback` 记并带 [closeness]；
///    6/7 档是裸失败，按 `lapse` 记。7 档之间的差别在模型侧是**事件类型与
///    closeness**，不是另一套 rating。
///
/// 全部映射常量**未标定**：它们是显式选定的粗映射（4/5 档的 closeness 是手选
/// 锚点，不是测量），标定后只改本文件。
///
/// 第 7 档「新的知识」在 MindNet 的正式事件是 `knowledge`（新建节点/第一次
/// 建模），那属于事件层；本片不改 schema，所以这里仍写成一次 review 的 lapse
/// （最短间隔回来），差别记在 [ReviewRatingMapping.isNewKnowledge]，等事件层
/// 接上后改成 knowledge 动作。
library;

import '../../../domain/services/srs/fsrs_scheduler.dart';

/// 用户自判的 7 档（顺序即界面顺序，与 `reviewRating*` 的 l10n 键一一对应）。
enum ReviewRatingTier {
  /// 1 完全熟练：已经会了，把下一次推送往后推。
  perfect,

  /// 2 比较熟练：正常推进。
  easy,

  /// 3 艰难想起。
  hard,

  /// 4 想起一部分。
  partial,

  /// 5 完全想不起来，但有一点印象。
  vague,

  /// 6 完全没有过印象。
  blank,

  /// 7 新的知识（第一次见）。
  newKnowledge,
}

/// 4 档「想起一部分」的 closeness 锚点（手选，未标定）。
const double kTierPartialCloseness = 0.6;

/// 5 档「有印象但没想起」的 closeness 锚点（手选，未标定）。
const double kTierVagueCloseness = 0.3;

/// 4/5 档与 6/7 档在 MindNet 侧的两种事件名。
const String kMindnetRetrievalSuccess = 'retrieval_success';
const String kMindnetFailureFeedback = 'retrieval_failure_feedback';
const String kMindnetLapse = 'lapse';

/// 一档的完整语义：给 FSRS 的 rating + 给 MindNet 的事件参数。
class ReviewRatingMapping {
  const ReviewRatingMapping({
    required this.tier,
    required this.fsrsRating,
    required this.remembered,
    required this.reviewedSolution,
    required this.closeness,
    required this.mindnetEvent,
    this.isNewKnowledge = false,
  });

  final ReviewRatingTier tier;

  /// 写进 `review_logs.rating_fsrs` 并交给 FSRS 排期的那一档。
  final FsrsRating fsrsRating;

  /// 算法侧的对错。false 时 `grade` 会强制 Again（见 `ReviewService.grade`），
  /// 这一档的 [fsrsRating] 只用于日志里的「用户本来选了什么」。
  final bool remembered;

  /// MindNet 的 `reviewed_solution`：失败之后是否对照过答案。6/7 档是裸失败。
  final bool reviewedSolution;

  /// MindNet 的 `closeness`（只在 [reviewedSolution] 为 true 时被模型读取）。
  final double closeness;

  /// 这一档在 MindNet 里对应的事件名（文档/测试用；实际事件由 `grade` 的
  /// `correct`/`reviewedSolution` 决定，两者必须一致——本表就是那个唯一映射）。
  final String mindnetEvent;

  /// 第 7 档：MindNet 的正式事件应是 `knowledge`，本片暂按 lapse 记。
  final bool isNewKnowledge;

  /// `ReviewService.grade` 需要的 `correct` 参数。
  bool get correct => remembered;

  bool get isFailure => !remembered;

  int get fsrsValue => fsrsRating.value;
}

/// 七档的固定映射表。确定性：就是一张常量表，没有条件分支。
const Map<ReviewRatingTier, ReviewRatingMapping> kReviewRatingMappings =
    <ReviewRatingTier, ReviewRatingMapping>{
  ReviewRatingTier.perfect: ReviewRatingMapping(
    tier: ReviewRatingTier.perfect,
    fsrsRating: FsrsRating.easy,
    remembered: true,
    reviewedSolution: false,
    closeness: 0.5,
    mindnetEvent: kMindnetRetrievalSuccess,
  ),
  ReviewRatingTier.easy: ReviewRatingMapping(
    tier: ReviewRatingTier.easy,
    fsrsRating: FsrsRating.good,
    remembered: true,
    reviewedSolution: false,
    closeness: 0.5,
    mindnetEvent: kMindnetRetrievalSuccess,
  ),
  ReviewRatingTier.hard: ReviewRatingMapping(
    tier: ReviewRatingTier.hard,
    fsrsRating: FsrsRating.hard,
    remembered: true,
    reviewedSolution: false,
    closeness: 0.5,
    mindnetEvent: kMindnetRetrievalSuccess,
  ),
  ReviewRatingTier.partial: ReviewRatingMapping(
    tier: ReviewRatingTier.partial,
    fsrsRating: FsrsRating.again,
    remembered: false,
    reviewedSolution: true,
    closeness: kTierPartialCloseness,
    mindnetEvent: kMindnetFailureFeedback,
  ),
  ReviewRatingTier.vague: ReviewRatingMapping(
    tier: ReviewRatingTier.vague,
    fsrsRating: FsrsRating.again,
    remembered: false,
    reviewedSolution: true,
    closeness: kTierVagueCloseness,
    mindnetEvent: kMindnetFailureFeedback,
  ),
  ReviewRatingTier.blank: ReviewRatingMapping(
    tier: ReviewRatingTier.blank,
    fsrsRating: FsrsRating.again,
    remembered: false,
    reviewedSolution: false,
    closeness: 0,
    mindnetEvent: kMindnetLapse,
  ),
  ReviewRatingTier.newKnowledge: ReviewRatingMapping(
    tier: ReviewRatingTier.newKnowledge,
    fsrsRating: FsrsRating.again,
    remembered: false,
    reviewedSolution: false,
    closeness: 0,
    mindnetEvent: kMindnetLapse,
    isNewKnowledge: true,
  ),
};

/// 查表（表完整，缺项是编译期不会发生的错误，所以直接 `!`）。
ReviewRatingMapping reviewRatingMappingOf(ReviewRatingTier tier) =>
    kReviewRatingMappings[tier]!;
