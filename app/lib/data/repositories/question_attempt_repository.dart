import 'dart:convert';

import 'package:drift/drift.dart';

import '../../domain/services/questions/attempt_history.dart';
import '../database/database.dart';
import '../ids.dart';

/// 题目「自测作答」记录的存储（schema v32，轮次一百五十五）。
///
/// 只追加：一次提交一行，不更新也不覆盖。**只存判分成功的作答**——空选、
/// 非客观题这类"没有可判"的提交不该落库，否则"做过几次"会被误触污染。
///
/// 读侧返回的 [QuestionAttemptEntry] 与领域层一致；排序在 SQL 与领域层各做一次，
/// 两处口径必须相同（attemptedAt 降序，同一毫秒按 id 升序）。
class QuestionAttemptRepository {
  QuestionAttemptRepository(this._db);

  final AppDatabase _db;

  /// 记一次判分成功的作答，返回新行 id。
  Future<String> record({
    required String questionId,
    required Iterable<String> selectedLabels,
    required bool isCorrect,
    DateTime? now,
  }) async {
    final id = Ids.next('qa');
    final millis = (now ?? DateTime.now()).millisecondsSinceEpoch;
    await _db.into(_db.questionAttempts).insert(
          QuestionAttemptsCompanion.insert(
            id: id,
            questionId: questionId,
            selectedLabels: Value(encodeSelectedLabels(selectedLabels)),
            isCorrect: isCorrect,
            attemptedAt: millis,
          ),
        );
    return id;
  }

  /// 一道题的作答历史，**新→旧**（同毫秒按 id 升序）。没有记录时返回空表。
  ///
  /// [limit] 是保护上限（默认 200，足够覆盖"同一道题被反复自测"的正常使用）；
  /// 传 0 或负数直接返回空表，不要先去数据库拿一行再丢掉。
  Future<List<QuestionAttemptEntry>> historyFor(
    String questionId, {
    int limit = 200,
  }) async {
    if (limit <= 0) {
      return const <QuestionAttemptEntry>[];
    }
    final rows = await (_db.select(_db.questionAttempts)
          ..where((t) => t.questionId.equals(questionId))
          ..orderBy([
            (t) => OrderingTerm.desc(t.attemptedAt),
            (t) => OrderingTerm.asc(t.id),
          ])
          ..limit(limit))
        .get();
    return <QuestionAttemptEntry>[
      for (final row in rows)
        QuestionAttemptEntry(
          id: row.id,
          questionId: row.questionId,
          isCorrect: row.isCorrect,
          attemptedAt: DateTime.fromMillisecondsSinceEpoch(row.attemptedAt),
        ),
    ];
  }

  /// 删一道题的全部作答记录（删题事务里显式调用；本项目没有外键级联）。
  Future<int> deleteForQuestion(String questionId) {
    return (_db.delete(_db.questionAttempts)
          ..where((t) => t.questionId.equals(questionId)))
        .go();
  }

  /// 全部作答记录条数（设置页「学习数据」显示与"0 条禁用"判断用）。
  Future<int> countAll() async {
    final count = _db.questionAttempts.id.count();
    final query = _db.selectOnly(_db.questionAttempts)..addColumns([count]);
    return query.map((row) => row.read(count) ?? 0).getSingle();
  }

  /// 清空全部题的作答记录，返回删除行数（设置页确认后调用；不可撤销）。
  ///
  /// 只清 [QuestionAttempts]；题目、标签、闪存卡复习日志都不动。清完题库里的
  /// "错过"筛选与"错 N 次"徽标会随之消失（它们都是这个表的派生结果）。
  Future<int> deleteAll() => _db.delete(_db.questionAttempts).go();

  /// 勾选 label 的落库形状：JSON 数组文本（trim → 大写 → 去空 → 去重 → 升序）。
  ///
  /// 归一化放在这里而不是调用方：界面传进来的是用户点出来的 label，可能带空格、
  /// 大小写不同；存进去的形状不一致，"同一次作答"在库里就会长成两行不同样子。
  static String encodeSelectedLabels(Iterable<String> labels) {
    final normalized = <String>{};
    for (final label in labels) {
      final value = label.trim().toUpperCase();
      if (value.isNotEmpty) {
        normalized.add(value);
      }
    }
    final sorted = normalized.toList()..sort();
    return jsonEncode(sorted);
  }
}
