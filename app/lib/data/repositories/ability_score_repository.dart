import 'dart:convert';

import 'package:drift/drift.dart';

import '../../domain/services/cognitive/ability_assessment.dart';
import '../database/database.dart';
import '../ids.dart';

/// 一次能力测量的读侧快照（schema v38，轮次一百七十七）。
///
/// 与库里的 [AbilityScoreRow] 分开：这里把 `ability_key` 翻成域层枚举、把
/// `metrics_json` 解成 Map，界面不用自己解析 JSON。
class AbilityScoreEntry {
  const AbilityScoreEntry({
    required this.id,
    required this.key,
    required this.score,
    required this.metrics,
    required this.capturedAt,
  });

  final String id;
  final AbilityKey key;

  /// 0–100（写库前已 clamp，读回来的就是界面上显示的分数）。
  final double score;

  /// 小测原始指标（反应毫秒样本、最长记忆长度、答对数……）。没存就是空表。
  final Map<String, Object?> metrics;

  final DateTime capturedAt;
}

/// 能力测评分数的存储（schema v38，轮次一百七十七，
/// `docs/REVIEW_FEEDBACK.md` 第 8 条）。
///
/// 只追加：同一项能力测几次就是几行。读侧按 `capturedAt` 降序、同一毫秒按 id
/// 降序（后写的 id 更大，所以「最新」稳定）。与 `assessment_*`/`cognitive_priors`
/// 完全分开：那是知识点先验，这里不读也不写它们。
class AbilityScoreRepository {
  AbilityScoreRepository(this._db);

  final AppDatabase _db;

  /// 记一项能力的一次测量，返回新行 id。
  ///
  /// [score] 在这里 clamp 到 0–100：域层已经夹过一遍，存储侧再夹一次是为了
  /// 挡住绕过域层直接写库的调用点，让「库里的分数一定在 0–100」成为表级事实。
  /// [metrics] 为空写 NULL，不写 `{}`——「没有指标」与「指标是空对象」不是一回事。
  Future<String> record({
    required AbilityKey key,
    required double score,
    Map<String, Object?> metrics = const <String, Object?>{},
    DateTime? now,
  }) async {
    final id = Ids.next('ab');
    final millis = (now ?? DateTime.now()).millisecondsSinceEpoch;
    await _db.into(_db.abilityScores).insert(
          AbilityScoresCompanion.insert(
            id: id,
            abilityKey: key.code,
            score: score.clamp(0, 100).toDouble(),
            metricsJson: Value(metrics.isEmpty ? null : jsonEncode(metrics)),
            capturedAt: millis,
          ),
        );
    return id;
  }

  /// 某一项能力的历史，**新→旧**。没有记录返回空表。
  ///
  /// [limit] 是保护上限（默认 50：够画趋势，不该把几千行读进内存）；传 0 或
  /// 负数直接返回空表，不要先去数据库拿一行再丢掉。
  Future<List<AbilityScoreEntry>> historyFor(
    AbilityKey key, {
    int limit = 50,
  }) async {
    if (limit <= 0) {
      return const <AbilityScoreEntry>[];
    }
    final rows = await (_db.select(_db.abilityScores)
          ..where((t) => t.abilityKey.equals(key.code))
          ..orderBy([
            (t) => OrderingTerm.desc(t.capturedAt),
            (t) => OrderingTerm.desc(t.id),
          ])
          ..limit(limit))
        .get();
    return <AbilityScoreEntry>[for (final row in rows) _entry(row)];
  }

  /// 每项能力**最近一次**分数（画像页读的就是这个）。没测过的能力不出现在表里。
  ///
  /// 一次查询取全集再在内存里挑第一行：能力只有四项、行数也被单机使用限制，
  /// 比逐项发一条「取最新」的 SQL 更少往返。
  Future<Map<AbilityKey, AbilityScoreEntry>> latestByAbility() async {
    final rows = await (_db.select(_db.abilityScores)
          ..orderBy([
            (t) => OrderingTerm.desc(t.capturedAt),
            (t) => OrderingTerm.desc(t.id),
          ]))
        .get();
    final latest = <AbilityKey, AbilityScoreEntry>{};
    for (final row in rows) {
      final key = AbilityKey.fromCode(row.abilityKey);
      if (key == null) {
        // 旧版本/手工改库留下的未知 code：跳过，不让它把画像页整页打挂。
        continue;
      }
      latest.putIfAbsent(key, () => _entry(row));
    }
    return latest;
  }

  /// 某一项能力一共测过几次。
  Future<int> countFor(AbilityKey key) async {
    final count = _db.abilityScores.id.count();
    final query = _db.selectOnly(_db.abilityScores)
      ..addColumns([count])
      ..where(_db.abilityScores.abilityKey.equals(key.code));
    return query.map((row) => row.read(count) ?? 0).getSingle();
  }

  /// 全部测量条数（设置页/调试用）。
  Future<int> countAll() async {
    final count = _db.abilityScores.id.count();
    final query = _db.selectOnly(_db.abilityScores)..addColumns([count]);
    return query.map((row) => row.read(count) ?? 0).getSingle();
  }

  /// 清空全部能力分数，返回删除行数（不可撤销）。
  Future<int> deleteAll() => _db.delete(_db.abilityScores).go();

  AbilityScoreEntry _entry(AbilityScoreRow row) {
    return AbilityScoreEntry(
      id: row.id,
      key: AbilityKey.fromCode(row.abilityKey) ?? AbilityKey.reactionSpeed,
      score: row.score,
      metrics: _decodeMetrics(row.metricsJson),
      capturedAt: DateTime.fromMillisecondsSinceEpoch(row.capturedAt),
    );
  }

  /// `metrics_json` 的解码：坏 JSON/非对象一律读成空表——画像页只需要分数，
  /// 不该因为一行旧指标写坏就整页报错。
  static Map<String, Object?> _decodeMetrics(String? raw) {
    if (raw == null || raw.isEmpty) {
      return const <String, Object?>{};
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return <String, Object?>{
          for (final entry in decoded.entries) '${entry.key}': entry.value,
        };
      }
    } on FormatException {
      return const <String, Object?>{};
    }
    return const <String, Object?>{};
  }
}
