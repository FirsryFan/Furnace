/// 收题页的仓储/存储 provider（`docs/QUESTION_BANK_DESIGN.md` §6 收题入口 B）。
///
/// 只放在 presentation 下：`questionRepositoryProvider` 与
/// `appDatabaseProvider` 都是既有的、冻结的 provider（前者在
/// `data/repositories/repository_providers.dart`，后者在
/// `data/database/app_database_provider.dart`），这里只做"本页需要什么"的组装，
/// 以及让测试能替换 app support 目录。
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/state/data_revision.dart';
import '../../../data/database/app_database_provider.dart';
import '../../../data/database/database.dart';
import '../../../data/repositories/repository_providers.dart';
import '../data/handwriting_intake_store.dart';

/// app support 目录。单独成一个 provider，测试才能把它指到临时目录，
/// 不去碰真实的 app 数据目录。
final questionIntakeSupportDirectoryProvider =
    Provider<Future<Directory> Function()>((ref) {
  return getApplicationSupportDirectory;
});

/// 拍照/选图落到哪个 store。
///
/// 单一实例：页面写、清单读，两个实例就是两套"文件在哪儿"的想法。
final handwritingIntakeStoreProvider = Provider<HandwritingIntakeStore>((ref) {
  return HandwritingIntakeStore(
    database: ref.watch(appDatabaseProvider),
    supportDirectory: ref.watch(questionIntakeSupportDirectoryProvider),
  );
});

/// 待整理图片清单。写库会走 `DbWriteInterceptor` → `DataChangeBus`，所以这里
/// 只需要 watch 一下 revision 就能自动刷新，不需要页面手动 invalidate。
final pendingHandwritingImagesProvider =
    FutureProvider<List<PendingHandwritingImage>>((ref) {
  ref.watchDatabaseRevision();
  return ref.watch(handwritingIntakeStoreProvider).pending();
});

/// 题库列表的筛选条件。
class QuestionLibraryFilter {
  const QuestionLibraryFilter({
    this.subjectKey,
    this.sourceLevel,
    this.state,
    this.stemContains,
  });

  final String? subjectKey;
  final String? sourceLevel;
  final String? state;
  final String? stemContains;

  bool get isEmpty =>
      (subjectKey == null || subjectKey!.isEmpty) &&
      (sourceLevel == null || sourceLevel!.isEmpty) &&
      (state == null || state!.isEmpty) &&
      (stemContains == null || stemContains!.isEmpty);

  QuestionLibraryFilter copyWith({
    String? subjectKey,
    String? sourceLevel,
    String? state,
    String? stemContains,
    bool clearSubject = false,
    bool clearSourceLevel = false,
    bool clearState = false,
    bool clearStem = false,
  }) {
    // `null` 在这些字段上是"不筛"，不是"保持原值"，所以要一个显式清空开关：
    // 否则用户把学科选回"全部"时，旧的学科会留在筛选里。
    return QuestionLibraryFilter(
      subjectKey: clearSubject ? null : (subjectKey ?? this.subjectKey),
      sourceLevel: clearSourceLevel ? null : (sourceLevel ?? this.sourceLevel),
      state: clearState ? null : (state ?? this.state),
      stemContains: clearStem ? null : (stemContains ?? this.stemContains),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is QuestionLibraryFilter &&
      other.subjectKey == subjectKey &&
      other.sourceLevel == sourceLevel &&
      other.state == state &&
      other.stemContains == stemContains;

  @override
  int get hashCode => Object.hash(subjectKey, sourceLevel, state, stemContains);
}

final questionLibraryFilterProvider =
    StateProvider<QuestionLibraryFilter>((ref) => const QuestionLibraryFilter());

/// 题目 + 它自己的选项数量。
class QuestionListEntry {
  const QuestionListEntry({required this.question, required this.optionCount});

  final Question question;
  final int optionCount;
}

/// 题库列表。有条目上限，超出的部分在这一页看不到（页面上明说）。
const int questionLibraryLimit = 200;

/// 一条题在列表里就是一行：题干 + 选项数。一次把选项计数读出来，列表里就不用
/// 为每行再查一次库。
final questionLibraryProvider = FutureProvider<List<QuestionListEntry>>((ref) async {
  ref.watchDatabaseRevision();
  final repository = ref.watch(questionRepositoryProvider);
  final filter = ref.watch(questionLibraryFilterProvider);

  final List<Question> rows;
  if (filter.isEmpty) {
    // 没筛选时按时间倒序（`all`），这是"刚收进来的在最前面"的顺序。
    rows = await repository.all(limit: questionLibraryLimit);
  } else {
    rows = await repository.search(
      subjectKey: filter.subjectKey,
      sourceLevels:
          filter.sourceLevel == null ? null : {filter.sourceLevel!},
      states: filter.state == null ? null : {filter.state!},
      stemContains: filter.stemContains,
      limit: questionLibraryLimit,
    );
  }

  final entries = <QuestionListEntry>[];
  for (final question in rows) {
    entries.add(QuestionListEntry(
      question: question,
      optionCount: (await repository.optionsOf(question.id)).length,
    ));
  }
  return entries;
});
