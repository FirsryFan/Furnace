/// 题库总览的数据版本绑定点：`readQuestionLibrary` 是读表函数（AI 工具也能用），
/// 这个文件只负责「听数据库版本 + 调它」。
///
/// 读多少由「筛选是否生效」决定：不筛选只读前 [kQuestionLibraryOverviewLimit]
/// 题（长库不至于一次画几千行），筛选生效读全库（`limit: 0`）——否则第 500
/// 题之后的题永远筛不到。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/state/data_revision.dart';
import '../../../data/database/app_database_provider.dart';
import '../../../domain/services/questions/question_readiness.dart';
import 'question_library_reader.dart';

export 'question_library_reader.dart'
    show
        QuestionLibraryEntry,
        QuestionLibraryImage,
        QuestionLibrarySnapshot,
        kQuestionLibraryAnswerRole,
        kQuestionLibrarySolutionRole,
        kQuestionLibraryStemRole,
        readQuestionLibrary;

export '../../../domain/services/questions/question_readiness.dart'
    show
        QuestionCompletenessPolicy,
        QuestionPendingReason,
        QuestionPendingStats,
        QuestionReadiness,
        evaluateQuestionReadiness,
        questionPendingStats;

/// 不筛选时题库页一次读多少题（超过这个数 `snapshot.truncated` 为真）。
const int kQuestionLibraryOverviewLimit = 500;

/// 题库页默认的完整性判据：**答案与解析都为空的题不进主题库**，
/// 改由「待处理题目」入口列（见 `question_pending_page.dart`）。
const QuestionCompletenessPolicy kQuestionLibraryPolicy =
    QuestionCompletenessPolicy.hidePending;

/// 题库页该按哪个上限读表：筛选生效时 `0`（不限），否则
/// [kQuestionLibraryOverviewLimit]。
///
/// 单独抽成函数是为了让测试能直接钉住「未筛选 500 / 筛选全库」这两条读表实参。
int questionLibraryReadLimit({required bool filterActive}) =>
    filterActive ? 0 : kQuestionLibraryOverviewLimit;

/// 题库总览（不筛选）：一次读前 500 题 + 题名 + 标签路径 + 图片清单。
///
/// `watchDatabaseRevision` 让「刚收了一道题 / 刚改了题名 / 刚删了图」立刻反映到
/// 列表；默认上限 [kQuestionLibraryOverviewLimit] 行，超了 `snapshot.truncated`
/// 为真。
final questionLibraryOverviewProvider =
    FutureProvider.autoDispose<QuestionLibrarySnapshot>((ref) async {
  ref.watchDatabaseRevision();
  return readQuestionLibrary(
    ref.watch(appDatabaseProvider),
    limit: questionLibraryReadLimit(filterActive: false),
    policy: kQuestionLibraryPolicy,
  );
});

/// 题库总览（筛选生效）：读全库，宁可慢一点也要筛得全。
final questionLibraryFullProvider =
    FutureProvider.autoDispose<QuestionLibrarySnapshot>((ref) async {
  ref.watchDatabaseRevision();
  return readQuestionLibrary(
    ref.watch(appDatabaseProvider),
    limit: questionLibraryReadLimit(filterActive: true),
    policy: kQuestionLibraryPolicy,
  );
});

/// 「待处理题目」数据源：只列缺答案/解析（以及配图，若判据要求）的题。
///
/// 排序与主题库一致（updatedAt 降序）；不限条数——这个入口本来就是为了把
/// 待处理题**全部**处理掉，截断反而藏问题。
final questionPendingLibraryProvider =
    FutureProvider.autoDispose<QuestionLibrarySnapshot>((ref) async {
  ref.watchDatabaseRevision();
  return readQuestionLibrary(
    ref.watch(appDatabaseProvider),
    limit: 0,
    policy: kQuestionLibraryPolicy,
    pendingOnly: true,
  );
});

/// 待处理统计（数量 + 按原因分项），供题库页入口与待处理页共用。
final questionPendingStatsProvider =
    FutureProvider.autoDispose<QuestionPendingStats>((ref) async {
  final snapshot = await ref.watch(questionPendingLibraryProvider.future);
  return questionPendingStats(
    <QuestionReadiness>[for (final entry in snapshot.entries) entry.readiness],
  );
});

/// 按「当前有没有筛选」选一档总览：筛选生效用 [questionLibraryFullProvider]，
/// 否则用 [questionLibraryOverviewProvider]。页面只 watch 这一个 provider，
/// 切换筛选条件时自动换档。
final questionLibrarySnapshotProvider =
    FutureProvider.autoDispose.family<QuestionLibrarySnapshot, bool>(
  (ref, filterActive) {
    final source = filterActive
        ? questionLibraryFullProvider
        : questionLibraryOverviewProvider;
    return ref.watch(source.future);
  },
);
