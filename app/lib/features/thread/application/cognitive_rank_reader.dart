import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/app_database_provider.dart';
import '../../../data/database/database.dart';
import '../../../data/repositories/anki_repository.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../data/repositories/tag_repository.dart';
import '../../../data/repositories/thread_state_repository.dart';
import '../../../domain/services/cloze/diffusion_boost.dart';
import '../../../domain/services/scheduling/cognitive_rank_inputs.dart';
import 'study_rhythm_reader.dart';

/// 往后看多久算"刚活动过"。
///
/// [未标定] 12 小时是个代理，不是测量：`StudyRhythm` 的坐段断裂阈值是 15 分钟，
/// 但"刚刚复习过这个知识点"对接下来做什么的影响显然比 15 分钟长。取一个能跨过
/// 一次午休、又不至于把昨天的事算成"刚做过"的窗口，并把数写在这里而不是散在查询里。
const Duration kCognitiveRankActivityWindow = Duration(hours: 12);

/// 每一侧最多取多少条日志来还原"最近活动"。
///
/// 这只是上限，不是承诺：活动列表按时间倒序取前 N 条，超出的更早活动本来就不该
/// 影响"现在做什么"。
const int kCognitiveRankActivityLimit = 40;

/// 知识点挂在 `object_tags` 上的 object_type。
///
/// 与 `review_service.dart` / `anki_manage_page.dart` 写入时用的值必须一致；写错
/// 这里不会报错，只会让认知排序永远看不到知识点的标签（静默失效），所以它是常量
/// 并有测试钉住。
const String kCognitiveRankKnowledgePointObjectType = 'knowledge_point';

/// 把数据库里的素材读成 [CognitiveRankSeed]。
///
/// 这是这一层唯一的 IO 点：`CognitiveRankWiring` 是纯函数，"什么算刚活动""标签树
/// 长什么样"这类问题全部在这里回答，读出来的每一个字段都是**已经存在的事实**
/// （目标节点来自 `ThreadState.goalNodeId`，活动来自 `review_logs` /
/// `exposure_logs` → `card_states.knowledge_point_id`），没有一个是这里推断的。
class CognitiveRankSeedReader {
  CognitiveRankSeedReader(
    this._db,
    this._anki,
    this._tags,
    this._threadStates,
    this._rhythm,
  );

  final AppDatabase _db;
  final AnkiRepository _anki;
  final TagRepository _tags;
  final ThreadStateRepository _threadStates;
  final StudyRhythmReader _rhythm;

  Future<CognitiveRankSeed> read({required DateTime now}) async {
    final rhythm = await _rhythm.read(now: now);
    final state = await _threadStates.getState();
    final tags = await _tags.getAllTags();
    final active = await _recentKnowledgePointIds(now);
    final tagIdsByKnowledgePoint = await _knowledgePointTagIds();
    final names = await _knowledgePointNames();
    return CognitiveRankSeed(
      // 提示关掉 = 没有读数；没有读数 = 中性 1（`CognitiveRank` 会把它变成
      // "精力这一项不动摇"），而不是 0，也不是一个编出来的数字。
      availability: rhythm.reading?.availability ?? 1,
      // 顺序显式排定：`Tags` 的默认顺序是插入顺序，换个库就换个结果。
      tagNodes: <MindNodeInfo>[
        for (final tag in tags)
          MindNodeInfo(id: tag.id, parentId: tag.parentId),
      ]..sort((a, b) => a.id.compareTo(b.id)),
      goalNodeId: state?.goalNodeId,
      activeKnowledgePointIds: active,
      knowledgePointTagIds: tagIdsByKnowledgePoint,
      knowledgePointNames: names,
    );
  }

  /// 最近活动落在哪些知识点上，按"最近"排序、去重。
  ///
  /// 日志表指向 `card_states`，知识点在 `card_states.knowledge_point_id` 上，
  /// 所以这里必然多一跳；跳数不改变"哪条更近"，排序仍在日志的时间戳上做。
  Future<List<String>> _recentKnowledgePointIds(DateTime now) async {
    final cutoff =
        now.subtract(kCognitiveRankActivityWindow).millisecondsSinceEpoch;
    final reviews = await (_db.select(_db.reviewLogs)
          ..where((t) => t.reviewedAt.isBiggerOrEqualValue(cutoff))
          ..orderBy([(t) => OrderingTerm.desc(t.reviewedAt)])
          ..limit(kCognitiveRankActivityLimit))
        .get();
    final exposures = await (_db.select(_db.exposureLogs)
          ..where((t) => t.exposedAt.isBiggerOrEqualValue(cutoff))
          ..orderBy([(t) => OrderingTerm.desc(t.exposedAt)])
          ..limit(kCognitiveRankActivityLimit))
        .get();
    final ordered = <({int at, String stateId})>[
      for (final row in reviews) (at: row.reviewedAt, stateId: row.cardStateId),
      for (final row in exposures)
        (at: row.exposedAt, stateId: row.cardStateId),
    ]..sort((a, b) {
        final byTime = b.at.compareTo(a.at);
        // 同一毫秒的两条日志也要有确定次序：`List.sort` 不保证稳定。
        return byTime != 0 ? byTime : a.stateId.compareTo(b.stateId);
      });
    if (ordered.isEmpty) {
      return const <String>[];
    }
    final states = await (_db.select(_db.cardStates)
          ..where((t) => t.id.isIn(ordered.map((e) => e.stateId).toSet())))
        .get();
    final knowledgePointByState = <String, String>{
      for (final row in states)
        if (row.knowledgePointId != null) row.id: row.knowledgePointId!,
    };
    final result = <String>[];
    for (final entry in ordered) {
      final knowledgePointId = knowledgePointByState[entry.stateId];
      if (knowledgePointId == null || result.contains(knowledgePointId)) {
        continue;
      }
      result.add(knowledgePointId);
    }
    return result;
  }

  /// 知识点 → 它挂着的标签 id（每个列表排过序）。
  ///
  /// 任务标签（`object_type = 'task'`）在这里**不算数**：认知排序算的是知识点在
  /// 标签树上的位置，任务自己的标签不是树上的节点。
  Future<Map<String, List<String>>> _knowledgePointTagIds() async {
    final links = await (_db.select(_db.objectTags)
          ..where(
            (t) => t.objectType.equals(kCognitiveRankKnowledgePointObjectType),
          ))
        .get();
    final grouped = <String, List<String>>{};
    for (final link in links) {
      grouped.putIfAbsent(link.objectId, () => <String>[]).add(link.tagId);
    }
    for (final ids in grouped.values) {
      ids.sort();
    }
    return grouped;
  }

  /// 知识点 → 显示名，理由行说话用（"离刚复习的『光合作用』1 跳"）。
  Future<Map<String, String>> _knowledgePointNames() async {
    final points = await _anki.getKnowledgePoints();
    return <String, String>{for (final point in points) point.id: point.title};
  }
}

final cognitiveRankSeedReaderProvider =
    Provider<CognitiveRankSeedReader>((ref) {
  return CognitiveRankSeedReader(
    ref.watch(appDatabaseProvider),
    ref.watch(ankiRepositoryProvider),
    ref.watch(tagRepositoryProvider),
    ref.watch(threadStateRepositoryProvider),
    ref.watch(studyRhythmReaderProvider),
  );
});
