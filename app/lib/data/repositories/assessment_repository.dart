import 'dart:convert';

import 'package:drift/drift.dart';

import '../../domain/services/cognitive/assessment_prior.dart';
import '../database/database.dart';
import '../ids.dart';

/// 测评层的持久化。schema v10 的三张表，`docs/ASSESSMENT_DESIGN.md` §5 / §7 的 M1b。
///
/// 三张表是三个不同的东西，故意不合并：
///
///  * `assessment_sessions` —— 一次测量什么时候发生、覆盖什么范围；
///  * `assessment_responses` —— **只追加**的步骤，证据本身；
///  * `cognitive_priors` —— 由前两者**推导**出来的先验，可以随时整表重算。
///
/// 最后一条是这个文件存在的理由：设计文档里"先验与观测分离"要成立，先验表就必须
/// 是派生的（同步三分类里它也是"派生（可重算）"）。所以只有 [rebuildPriors] 会写
/// 它，而且写之前整表清空——任何"手工往先验表里塞一行"的做法都会让这个性质失效。
class AssessmentRepository {
  AssessmentRepository(this._db);

  final AppDatabase _db;

  /// 步骤类型。写在这里一次，UI / 工具 / 测试说同一套词。
  static const String selfReportStep = 'self_report';
  static const String recallStep = 'recall';
  static const String objectiveStep = 'objective';

  /// 先验来源。首版只有自评与抽检两种信号，混合时记 `blended`。
  static const String selfSource = 'assessment:self';
  static const String objectiveSource = 'assessment:objective';
  static const String blendedSource = 'assessment:blended';

  /// 自评的取值范围（JOL）。与 `AssessmentPrior` 的校验保持一致。
  static const int minSelfRating = 0;
  static const int maxSelfRating = 5;

  // --- 会话 -----------------------------------------------------------------

  /// 开一轮测评，返回会话 id。
  ///
  /// [scopeTagIds] 存的是 tag id 而不是路径：`TagRepository` 改名会重写所有后代
  /// 的 `path`，路径存进来会在某次改名后指向别的组。
  Future<String> startSession({
    String subjectKey = '',
    List<String> scopeTagIds = const <String>[],
    Map<String, Object?>? budget,
    String? note,
    DateTime? now,
  }) async {
    final moment = now ?? DateTime.now();
    final id = Ids.next('as');
    final stamp = moment.millisecondsSinceEpoch;
    await _db.into(_db.assessmentSessions).insert(
          AssessmentSessionsCompanion.insert(
            id: id,
            subjectKey: Value(subjectKey),
            scopeTagIds: Value(jsonEncode(scopeTagIds)),
            budget: Value(budget == null ? null : jsonEncode(budget)),
            note: Value(note),
            startedAt: stamp,
            createdAt: stamp,
            updatedAt: stamp,
          ),
        );
    return id;
  }

  /// 关上这一轮。
  ///
  /// 已经关上就不动：结束时间是事实，第二次"结束"通常来自重复点击或重放，把事实
  /// 往后推会让"这轮做了多久"随点击漂移。要重开就显式删掉重来。
  Future<void> finishSession(String sessionId, {DateTime? now}) async {
    final moment = now ?? DateTime.now();
    await (_db.update(_db.assessmentSessions)
          ..where((t) => t.id.equals(sessionId) & t.finishedAt.isNull()))
        .write(
      AssessmentSessionsCompanion(
        finishedAt: Value(moment.millisecondsSinceEpoch),
        updatedAt: Value(moment.millisecondsSinceEpoch),
      ),
    );
  }

  Future<AssessmentSession?> session(String sessionId) =>
      (_db.select(_db.assessmentSessions)..where((t) => t.id.equals(sessionId)))
          .getSingleOrNull();

  /// 最近的若干轮，从新到旧。
  Future<List<AssessmentSession>> sessions({int limit = 20}) =>
      (_db.select(_db.assessmentSessions)
            ..orderBy([
              (t) => OrderingTerm.desc(t.startedAt),
              (t) => OrderingTerm.desc(t.id),
            ])
            ..limit(limit))
          .get();

  /// 删掉一轮，连同它的每一步。
  ///
  /// 级联只能在这里做：本项目的生成 schema **不带外键约束**（实测连 v2 就存在的
  /// `review_logs` 也没有，`references(...)` 只是意图声明），所以这不是"额外一道
  /// 保险"，而是唯一的一道。留下的孤儿步骤会继续被 [evidenceSince] 读成证据——
  /// 那等于删了测评却还在改先验。先验不跟着删：它是派生的，下一次 [rebuildPriors]
  /// 会把它重算掉（这也是"派生"的定义）。
  Future<void> deleteSession(String sessionId) async {
    await _db.transaction(() async {
      await (_db.delete(_db.assessmentResponses)
            ..where((t) => t.sessionId.equals(sessionId)))
          .go();
      await (_db.delete(_db.assessmentSessions)
            ..where((t) => t.id.equals(sessionId)))
          .go();
    });
  }

  // --- 步骤 -----------------------------------------------------------------

  /// 记一步，返回这一步的 id。
  ///
  /// 两道校验不是形式主义：一步若既没有 `selfRating` 也没有 `correct`，它就没有
  /// 任何证据，写进去只会让后来的读数多一个空洞的样本；而 `self_report` 没有自评、
  /// `objective` 没有判分，是调用方漏填，应该当场炸，而不是等到读数时才发现。
  Future<String> addStep({
    required String sessionId,
    required String stepKind,
    String? knowledgePointId,
    String? prompt,
    String? answer,
    bool? correct,
    int? selfRating,
    int? confidence,
    int? elapsedMs,
    String judgedBy = 'self',
    DateTime? now,
  }) async {
    if (selfRating != null &&
        (selfRating < minSelfRating || selfRating > maxSelfRating)) {
      throw ArgumentError(
          '自评必须在 $minSelfRating–$maxSelfRating 之间，实际 $selfRating');
    }
    if (stepKind == selfReportStep && selfRating == null) {
      throw ArgumentError('$selfReportStep 步骤必须带 selfRating');
    }
    if (stepKind == objectiveStep && correct == null) {
      throw ArgumentError('$objectiveStep 步骤必须带 correct');
    }
    if (selfRating == null && correct == null) {
      throw ArgumentError('这一步没有携带任何证据（selfRating 与 correct 都为空）');
    }
    final moment = now ?? DateTime.now();
    final id = Ids.next('ar');
    await _db.into(_db.assessmentResponses).insert(
          AssessmentResponsesCompanion.insert(
            id: id,
            sessionId: sessionId,
            stepKind: stepKind,
            knowledgePointId: Value(knowledgePointId),
            prompt: Value(prompt),
            answer: Value(answer),
            correct: Value(correct),
            selfRating: Value(selfRating),
            confidence: Value(confidence),
            elapsedMs: Value(elapsedMs),
            judgedBy: Value(judgedBy),
            createdAt: moment.millisecondsSinceEpoch,
          ),
        );
    return id;
  }

  /// 一轮里的所有步骤，按写入顺序。
  Future<List<AssessmentResponse>> steps(String sessionId) =>
      (_db.select(_db.assessmentResponses)
            ..where((t) => t.sessionId.equals(sessionId))
            ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
          .get();

  // --- 证据桥 ---------------------------------------------------------------

  /// 把一轮的步骤折成先验层能吃的证据。
  Future<List<AssessmentEvidence>> evidenceFor(String sessionId) async {
    final rows = await steps(sessionId);
    return _toEvidence(rows);
  }

  /// 把 [since] 之后（含）的所有步骤折成证据，按知识点聚合。
  ///
  /// 只读带知识点的步骤：没有知识点的步骤是整卷性提示（例如"这一轮测物理"），
  /// 折算成某个点的样本会凭空制造证据。
  Future<List<AssessmentEvidence>> evidenceSince(DateTime? since) async {
    final query = _db.select(_db.assessmentResponses)
      ..where((t) => t.knowledgePointId.isNotNull())
      ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]);
    if (since != null) {
      query.where((t) => t.createdAt.isBiggerOrEqualValue(
            since.millisecondsSinceEpoch,
          ));
    }
    return _toEvidence(await query.get());
  }

  List<AssessmentEvidence> _toEvidence(List<AssessmentResponse> rows) {
    final ids = <String>[];
    final seen = <String>{};
    final self = <String, int>{};
    final objective = <String, List<bool>>{};
    final elapsed = <String, int>{};
    for (final row in rows) {
      final kp = row.knowledgePointId;
      if (kp == null) {
        continue;
      }
      if (seen.add(kp)) {
        ids.add(kp);
      }
      // 同一个知识点在一次归并里可能被问多次：自评取最后一次（用户改过口径就是
      // 最新的口径），抽检逐题累积（那是样本量，不能只留最后一题）。
      if (row.selfRating != null) {
        self[kp] = row.selfRating!;
      }
      if (row.correct != null) {
        (objective[kp] ??= <bool>[]).add(row.correct!);
      }
      if (row.elapsedMs != null) {
        elapsed[kp] = row.elapsedMs!;
      }
    }
    return [
      for (final id in ids)
        AssessmentEvidence(
          knowledgePointId: id,
          selfRating: self[id],
          objectiveResults: objective[id] ?? const <bool>[],
          elapsedMs: elapsed[id],
        ),
    ];
  }

  // --- 先验 -----------------------------------------------------------------

  /// 从库里的证据重算全部先验，并返回这次读数。
  ///
  /// 先清空再写是**故意的**：先验是从证据推导出来的，证据变了（删了一轮、改了
  /// 自评）旧先验就必须消失。增量更新省下的那点时间，换来的是"库里躺着一行谁也
  /// 说不清来源的先验"。
  Future<AssessmentPriorReading> rebuildPriors({
    DateTime? since,
    DateTime? now,
  }) async {
    final evidence = await evidenceSince(since);
    final reading = AssessmentPrior.read(evidence: evidence);
    final moment = now ?? DateTime.now();
    await _db.transaction(() async {
      await _db.delete(_db.cognitivePriors).go();
      if (reading.estimates.isEmpty) {
        return;
      }
      await _db.batch((batch) {
        batch.insertAll(_db.cognitivePriors, [
          for (final estimate in reading.estimates)
            CognitivePriorsCompanion.insert(
              knowledgePointId: estimate.knowledgePointId,
              source: _sourceOf(estimate),
              r0: estimate.r0,
              d: Value(estimate.difficulty),
              fluency: Value(estimate.fluency),
              n: Value(estimate.n),
              // 设计文档 §2：首版全部未标定。写 1 必须是显式动作，而这里永远
              // 不写 1——真实数据标定是后来的事。
              calibrated: const Value(0),
              createdAt: moment.millisecondsSinceEpoch,
            ),
        ]);
      });
    });
    return reading;
  }

  String _sourceOf(AssessmentPriorEstimate estimate) {
    final hasSelf = estimate.fluency != null;
    final hasObjective = estimate.difficulty != null;
    if (hasSelf && hasObjective) {
      return blendedSource;
    }
    return hasObjective ? objectiveSource : selfSource;
  }

  /// 某些知识点的先验，按知识点 id 分组（同一 id 可能有多行来源）。
  Future<Map<String, List<CognitivePrior>>> priorsFor(
    Iterable<String> knowledgePointIds,
  ) async {
    final ids = knowledgePointIds.toSet().toList();
    if (ids.isEmpty) {
      return const <String, List<CognitivePrior>>{};
    }
    final rows = await (_db.select(_db.cognitivePriors)
          ..where((t) => t.knowledgePointId.isIn(ids)))
        .get();
    final grouped = <String, List<CognitivePrior>>{};
    for (final row in rows) {
      (grouped[row.knowledgePointId] ??= <CognitivePrior>[]).add(row);
    }
    return grouped;
  }

  /// 一个知识点的先验读数，合并多来源（[blendedSource] 优先，其次客观、自评）。
  ///
  /// 合并规则写在这里而不是散在 UI 里：先验不是观测，一个点最多只有一行值得看，
  /// 让每个调用方各挑一次必然会出现两种读数。
  Future<AssessmentPriorEstimate?> priorFor(String knowledgePointId) async {
    final rows = (await priorsFor([knowledgePointId]))[knowledgePointId];
    if (rows == null || rows.isEmpty) {
      return null;
    }
    return _mergePriors(rows);
  }

  /// 一批知识点的先验读数，每个 id 至多一条（同一套合并规则）。
  ///
  /// 批量版不只是省查询：读数页要一次展示几十个点，逐个调 [priorFor] 会让
  /// "哪个来源优先"在两处各写一遍。
  Future<Map<String, AssessmentPriorEstimate>> priorEstimatesFor(
    Iterable<String> knowledgePointIds,
  ) async {
    final grouped = await priorsFor(knowledgePointIds);
    return {
      for (final entry in grouped.entries) entry.key: _mergePriors(entry.value),
    };
  }

  AssessmentPriorEstimate _mergePriors(List<CognitivePrior> rows) {
    final order = <String>[blendedSource, objectiveSource, selfSource];
    rows.sort((a, b) {
      final ai = order.indexOf(a.source);
      final bi = order.indexOf(b.source);
      return (ai < 0 ? order.length : ai).compareTo(bi < 0 ? order.length : bi);
    });
    final row = rows.first;
    return AssessmentPriorEstimate(
      knowledgePointId: row.knowledgePointId,
      r0: row.r0,
      difficulty: row.d,
      fluency: row.fluency,
      n: row.n,
      // 置信度不在表里：它由 n 唯一决定（设计文档 §7 的 M1a 口径），存下来只会
      // 和 n 漂移。
      confidence: row.n / (row.n + AssessmentPrior.confidencePseudoCount),
      basis: <String>['prior:${row.source}'],
    );
  }

  /// 清掉先验（全部，或某个来源）。用于"先验想从零重来"。
  Future<int> clearPriors({String? source}) async {
    final stmt = _db.delete(_db.cognitivePriors);
    if (source != null) {
      stmt.where((t) => t.source.equals(source));
    }
    return stmt.go();
  }
}
