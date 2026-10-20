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
import '../../../domain/services/questions/question_search_plan.dart';
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
    this.serialNos = const <int>[],
    this.serialFallbackStem,
  });

  final String? subjectKey;
  final String? sourceLevel;
  final String? state;

  /// 题干关键字（LIKE）。混合输入时是认不出的文字（由
  /// `parseQuestionSearchPlan` 决定），纯题号输入时为空。
  final String? stemContains;

  /// 搜索框输入读出来的题号（`TR-42` → 42、`2-5` → 2,3,4,5）。有值时先
  /// 按号精确搜（见 [questionLibraryProvider]）；空清单表示不按号筛。
  final List<int> serialNos;

  /// 纯题号输入的原文（trim 后）。题号一个都没命中时用它回落成题干 LIKE
  /// 搜索——旧行为：用户敲的数字也可能只出现在题干里，或者只是记错了号。
  /// 混合输入 / 纯题干输入时为 null。
  final String? serialFallbackStem;

  bool get isEmpty =>
      (subjectKey == null || subjectKey!.isEmpty) &&
      (sourceLevel == null || sourceLevel!.isEmpty) &&
      (state == null || state!.isEmpty) &&
      (stemContains == null || stemContains!.isEmpty) &&
      serialNos.isEmpty;

  /// 是否带了题干关键字（空串不算）。
  bool get hasStemFilter => stemContains != null && stemContains!.isNotEmpty;

  QuestionLibraryFilter copyWith({
    String? subjectKey,
    String? sourceLevel,
    String? state,
    String? stemContains,
    List<int>? serialNos,
    String? serialFallbackStem,
    bool clearSubject = false,
    bool clearSourceLevel = false,
    bool clearState = false,
    bool clearStem = false,
    bool clearSerialNos = false,
    bool clearSerialFallbackStem = false,
  }) {
    // `null` 在这些字段上是"不筛"，不是"保持原值"，所以要一个显式清空开关：
    // 否则用户把学科选回"全部"时，旧的学科会留在筛选里。
    return QuestionLibraryFilter(
      subjectKey: clearSubject ? null : (subjectKey ?? this.subjectKey),
      sourceLevel: clearSourceLevel ? null : (sourceLevel ?? this.sourceLevel),
      state: clearState ? null : (state ?? this.state),
      stemContains: clearStem ? null : (stemContains ?? this.stemContains),
      serialNos: clearSerialNos ? const <int>[] : (serialNos ?? this.serialNos),
      // 回落原文只对纯题号输入有意义：清题号时一起清，避免留下上一轮的文本。
      serialFallbackStem: clearSerialNos || clearSerialFallbackStem
          ? null
          : (serialFallbackStem ?? this.serialFallbackStem),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is QuestionLibraryFilter &&
      other.subjectKey == subjectKey &&
      other.sourceLevel == sourceLevel &&
      other.state == state &&
      other.stemContains == stemContains &&
      _sameIntList(other.serialNos, serialNos) &&
      other.serialFallbackStem == serialFallbackStem;

  @override
  int get hashCode => Object.hash(
        subjectKey,
        sourceLevel,
        state,
        stemContains,
        Object.hashAll(serialNos),
        serialFallbackStem,
      );
}

bool _sameIntList(List<int> a, List<int> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// 一次搜索输入的解析结果。
///
/// 语义来自 domain 层 [parseQuestionSearchPlan]：一次输入可以同时带多个题号
/// 与题干关键字；「像题号但坏掉的区间」放进 [rejectedSegments]（本页不提示，
/// 只保留给日志/调用方），[truncated] 表示题号超过上限被截断。页面只读
/// [stemContains] / [serialNos]，通过 [questionLibraryFilterForSearch] 落到
/// 筛选条件里。
class QuestionLibrarySearchQuery {
  const QuestionLibrarySearchQuery({
    this.raw = '',
    this.stemContains,
    this.serialNos = const <int>[],
    this.rejectedSegments = const <String>[],
    this.truncated = false,
  });

  /// 调用方原始输入（回显 / 题号没命中时回落用）。
  final String raw;

  final String? stemContains;
  final List<int> serialNos;
  final List<String> rejectedSegments;
  final bool truncated;

  /// 两者都没有：不触发搜索（空 / 纯空白输入）。
  bool get isEmpty => (stemContains ?? '').isEmpty && serialNos.isEmpty;

  /// 纯题号输入（没有题干关键字）：题号 0 命中时回落到题干搜。
  bool get isSerialOnly => serialNos.isNotEmpty && (stemContains ?? '').isEmpty;

  int get serialCount => serialNos.length;
}

/// 解析题库搜索框的输入。
///
/// 多题号、区间、题干关键字的分流规则都在 domain 层
/// [parseQuestionSearchPlan]（`question_search_plan.dart`）：界面层只做转发，
/// 不自己写正则、不自己拆区间。
QuestionLibrarySearchQuery parseQuestionLibrarySearch(String input) {
  final plan = parseQuestionSearchPlan(input);
  return QuestionLibrarySearchQuery(
    raw: plan.raw,
    stemContains: plan.stemContains,
    serialNos: plan.serialNos,
    rejectedSegments: plan.rejectedSegments,
    truncated: plan.truncated,
  );
}

/// 用搜索框文本更新筛选条件：[current] 的学科/来源/状态保留。
///
/// 题号与题干可以同时写进筛选（混合输入各取一半）；纯题号输入额外保留原文
/// 作为「号没命中」时的题干回落条件。
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
    serialNos: query.serialNos,
    serialFallbackStem: query.isSerialOnly ? query.raw.trim() : null,
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
  } else if (filter.serialNos.isNotEmpty && filter.hasStemFilter) {
    // 混合搜索 = 并集：题号命中在前、题干命中在后，按 id 去重；两边各自保持
    // 仓储返回序（同一个 id 只留第一次出现的那一行）。
    final bySerial = await search(serialNos: filter.serialNos.toSet());
    final byStem = await search(stemContains: filter.stemContains);
    final seen = <String>{};
    rows = <Question>[
      for (final question in <Question>[...bySerial, ...byStem])
        if (seen.add(question.id)) question,
    ];
  } else if (filter.serialNos.isNotEmpty) {
    // 纯题号/区间：先按号精确命中。号一个都没命中就回落成题干搜：用户敲的
    // 数字可能只出现在题干里，也可能只是记错了号——给空列表不如给线索。
    final bySerial = await search(serialNos: filter.serialNos.toSet());
    final fallback = filter.serialFallbackStem;
    rows = bySerial.isEmpty && fallback != null && fallback.isNotEmpty
        ? await search(stemContains: fallback)
        : bySerial;
  } else if (filter.hasStemFilter) {
    rows = await search(stemContains: filter.stemContains);
  } else {
    // 只选了学科/来源/状态 chip：仓储层不带题干与题号条件。
    rows = await search();
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
