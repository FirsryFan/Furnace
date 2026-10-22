/// 题库总览的数据版本绑定点：`readQuestionLibrary` 是读表函数（AI 工具也能用），
/// 这个文件只负责「听数据库版本 + 调它」。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/state/data_revision.dart';
import '../../../data/database/app_database_provider.dart';
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

/// 题库总览：一次读全题目 + 题名 + 标签路径 + 图片清单。
///
/// `watchDatabaseRevision` 让「刚收了一道题 / 刚改了题名 / 刚删了图」立刻反映到
/// 列表；默认上限 500 行，超了 `snapshot.truncated` 为真。
final questionLibraryOverviewProvider =
    FutureProvider.autoDispose<QuestionLibrarySnapshot>((ref) async {
  ref.watchDatabaseRevision();
  return readQuestionLibrary(ref.watch(appDatabaseProvider));
});
