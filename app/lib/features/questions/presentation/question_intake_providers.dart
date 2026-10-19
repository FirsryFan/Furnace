/// 收题页的仓储/存储 provider（`docs/QUESTION_BANK_DESIGN.md` §6 收题入口 B）。
///
/// 只放在 presentation 下：`questionRepositoryProvider` 与
/// `appDatabaseProvider` 都是既有的、冻结的 provider（前者在
/// `data/repositories/repository_providers.dart`，后者在
/// `data/database/app_database_provider.dart`），这里只做"本页需要什么"的组装。
///
/// 「照片落在哪儿」的两个 provider（support 目录 + store）已经下移到
/// `application/handwriting_proposal_service.dart`：整理服务（拍照 → 三类待确认
/// 产物，§7.3）和这一页共用**同一个** store——两个实例就是两套"文件在哪儿"的
/// 想法。这里用 `export` 原样转发，页面与测试的 import 路径不变。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/state/data_revision.dart';
import '../../../data/database/database.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../domain/services/questions/question_number.dart';
import '../../../domain/services/questions/question_number_query.dart';
import '../application/handwriting_proposal_service.dart';
import '../data/handwriting_intake_store.dart';

export '../application/handwriting_proposal_service.dart'
    show handwritingIntakeStoreProvider, questionIntakeSupportDirectoryProvider;

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
    this.serialNo,
  });

  final String? subjectKey;
  final String? sourceLevel;
  final String? state;

  /// 题干关键字（LIKE）。搜索框的原文也留在这里：输入读得出题号时，它同时是
  /// 题号一个都没命中后的回落条件。
  final String? stemContains;

  /// 搜索框输入读出来的题号（`TR-42` → 42）。有值时先按号精确搜（见
  /// [questionLibraryProvider]）；读不出号码时为 null，只按题干搜。
  final int? serialNo;

  bool get isEmpty =>
      (subjectKey == null || subjectKey!.isEmpty) &&
      (sourceLevel == null || sourceLevel!.isEmpty) &&
      (state == null || state!.isEmpty) &&
      (stemContains == null || stemContains!.isEmpty) &&
      serialNo == null;

  QuestionLibraryFilter copyWith({
    String? subjectKey,
    String? sourceLevel,
    String? state,
    String? stemContains,
    int? serialNo,
    bool clearSubject = false,
    bool clearSourceLevel = false,
    bool clearState = false,
    bool clearStem = false,
    bool clearSerialNo = false,
  }) {
    // `null` 在这些字段上是"不筛"，不是"保持原值"，所以要一个显式清空开关：
    // 否则用户把学科选回"全部"时，旧的学科会留在筛选里。
    return QuestionLibraryFilter(
      subjectKey: clearSubject ? null : (subjectKey ?? this.subjectKey),
      sourceLevel: clearSourceLevel ? null : (sourceLevel ?? this.sourceLevel),
      state: clearState ? null : (state ?? this.state),
      stemContains: clearStem ? null : (stemContains ?? this.stemContains),
      serialNo: clearSerialNo ? null : (serialNo ?? this.serialNo),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is QuestionLibraryFilter &&
      other.subjectKey == subjectKey &&
      other.sourceLevel == sourceLevel &&
      other.state == state &&
      other.stemContains == stemContains &&
      other.serialNo == serialNo;

  @override
  int get hashCode =>
      Object.hash(subjectKey, sourceLevel, state, stemContains, serialNo);
}

/// 一次搜索输入的解析结果：能读成题号就带上 [serialNo]，同时保留文本用于
/// 题号一个都没命中时回落到题干搜。
class QuestionLibrarySearchQuery {
  const QuestionLibrarySearchQuery({this.stemContains, this.serialNo});

  final String? stemContains;
  final int? serialNo;

  bool get isEmpty => (stemContains ?? '').isEmpty && serialNo == null;
}

/// 解析题库搜索框的输入。
///
/// 号码规则分两层，界面层不自己写正则：
/// 1. 先走 [parseQuestionNumberQuery]（`question_number_query.dart`，v24 起
///    题号检索的规范入口：`TR-00042` / `tr-42` / `#7` / `＃７` / 全角数字都认）；
/// 2. 读不出时**回退**旧的 [tryParseQuestionSerial]：新解析器更严格（纯数字位数
///    上限、`0` 拒绝等），旧写法如 `00042` / 超长前导零数字仍要能按号检索。
///
/// 两层都读不出号码时整段文本就是题干关键字（[stemContains] 始终保留原文）。
QuestionLibrarySearchQuery parseQuestionLibrarySearch(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) {
    return const QuestionLibrarySearchQuery();
  }
  return QuestionLibrarySearchQuery(
    stemContains: trimmed,
    serialNo: _parseSearchSerialNo(trimmed),
  );
}

/// 搜索输入 → 题号：新解析器优先，旧解析器兜底（兼容老输入）。
int? _parseSearchSerialNo(String trimmed) {
  final query = parseQuestionNumberQuery(trimmed);
  if (query != null) return query.serialNo;
  return tryParseQuestionSerial(trimmed);
}

/// 用搜索框文本更新筛选条件：[current] 的学科/来源/状态保留。
///
/// 题号与题干同时写进筛选：provider 先按号搜、没命中再按题干搜，用户不用
/// 记自己刚才敲的是号码还是关键词。
QuestionLibraryFilter questionLibraryFilterForSearch(
  QuestionLibraryFilter current,
  String input,
) {
  final query = parseQuestionLibrarySearch(input);
  return QuestionLibraryFilter(
    subjectKey: current.subjectKey,
    sourceLevel: current.sourceLevel,
    state: current.state,
    stemContains: query.stemContains,
    serialNo: query.serialNo,
  );
}

final questionLibraryFilterProvider = StateProvider<QuestionLibraryFilter>(
    (ref) => const QuestionLibraryFilter());

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
final questionLibraryProvider =
    FutureProvider<List<QuestionListEntry>>((ref) async {
  ref.watchDatabaseRevision();
  final repository = ref.watch(questionRepositoryProvider);
  final filter = ref.watch(questionLibraryFilterProvider);

  Future<List<Question>> search({
    Set<int>? serialNos,
    String? stemContains,
  }) {
    return repository.search(
      subjectKey: filter.subjectKey,
      sourceLevels: filter.sourceLevel == null ? null : {filter.sourceLevel!},
      states: filter.state == null ? null : {filter.state!},
      serialNos: serialNos,
      stemContains: stemContains,
      limit: questionLibraryLimit,
    );
  }

  final List<Question> rows;
  if (filter.isEmpty) {
    // 没筛选时按时间倒序（`all`），这是"刚收进来的在最前面"的顺序。
    rows = await repository.all(limit: questionLibraryLimit);
  } else if (filter.serialNo != null) {
    // 搜索框的输入读得出题号：先按号精确命中（`TR-42` 与 `42` 等价）。
    final bySerial = await search(serialNos: {filter.serialNo!});
    // 号一个都没命中就回落成题干搜：用户敲的数字可能只出现在题干里，也可能
    // 只是记错了号——这时给空列表不如把他真正想找的题干搜出来。
    rows = bySerial.isEmpty
        ? await search(stemContains: filter.stemContains)
        : bySerial;
  } else {
    rows = await search(stemContains: filter.stemContains);
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
