import 'dart:convert';

import 'package:drift/drift.dart';

import '../../domain/services/intake/handwriting_proposals.dart';
import '../database/database.dart';

/// 一条待确认产物在库里的样子：提案本体 + 用户是否已经确认过。
class HandwritingStoredProposal {
  const HandwritingStoredProposal({
    required this.proposal,
    this.appliedAt,
  });

  final HandwritingProposal proposal;

  /// 用户确认写库的时刻；`null` = 还没确认。
  final DateTime? appliedAt;

  bool get isApplied => appliedAt != null;
}

/// 一次整理的持久化结果。
class HandwritingStoredRun {
  const HandwritingStoredRun({
    required this.sourceRef,
    required this.analyzedAt,
    required this.proposals,
    this.rawReply,
    this.sourcePhotos = const <String>[],
  });

  final String sourceRef;
  final DateTime analyzedAt;
  final String? rawReply;
  final List<HandwritingStoredProposal> proposals;

  /// 多图/多页整理涉及的照片（相对路径，按用户选择顺序）。
  /// 空 = 单图整理，来源就是 [sourceRef]。
  final List<String> sourcePhotos;

  /// 一次整理是否来自多张照片。
  bool get isMulti => sourcePhotos.isNotEmpty;

  /// 给领域层 / 队列状态用的提案集合（按整理时的次序）。
  HandwritingProposalSet get proposalSet => HandwritingProposalSet(
        sourceRef: sourceRef,
        proposals: List<HandwritingProposal>.unmodifiable(
          proposals.map((stored) => stored.proposal),
        ),
      );

  /// 已经确认过的提案 id。
  Set<String> get appliedProposalIds => <String>{
        for (final stored in proposals)
          if (stored.isApplied) stored.proposal.id,
      };
}

/// 「拍照 → 四类待确认产物」的持久化（schema v13，
/// `docs/HANDWRITING_INTAKE_DESIGN.md` §4）。
///
/// 存在这一层的理由，是提案**不是可再生的缓存**：
///
///  * 用户的确认动作（`appliedAt`）本身是数据——同一张闪存卡确认两次就是两张卡；
///  * 照片还在磁盘上，但"我当时已经整理过了"没有别的办法记住：不落库的话，重启
///    之后队列退回"未整理"，用户白跑一次模型。
///
/// 一行提案的有效期由 [HandwritingIntakeRuns] 那张表兜着：**零提案也要有 run 行**，
/// 否则"整理过，但照片里没有可整理的东西"会被读成"从来没整理过"。
///
/// JSON 编解码只有一份：写用 `HandwritingProposal.toJson()`，读用
/// `HandwritingProposal.fromJson()`（领域层，和解析模型回复同一套严格口径）。
/// 这一层不另写反序列化——两套契约迟早会分叉。
class HandwritingProposalRepository {
  HandwritingProposalRepository(this._db);

  final AppDatabase _db;

  /// 写入一次整理结果。
  ///
  /// 同一张照片重新整理是**整批替换**，但已确认状态按内容保留：
  /// 新旧 `payloadJson` 逐字相同的提案，`appliedAt` 留着（它就是用户确认过的那条，
  /// 再确认一次会重复写库）；其余（包括 id 相同但内容变了的）一律清成"未确认"，
  /// 因为拿旧确认状态去覆盖新提案，等于把用户没确认过的东西标成已写库。
  Future<void> saveRun({
    required HandwritingProposalSet set,
    required DateTime analyzedAt,
    String? rawReply,
    List<String> sourcePhotos = const <String>[],
  }) async {
    final sourceRef = set.sourceRef;
    final now = analyzedAt.millisecondsSinceEpoch;
    final encodedPhotos =
        sourcePhotos.isEmpty ? null : jsonEncode(sourcePhotos);

    await _db.transaction(() async {
      final existing = await (_db.select(_db.handwritingProposals)
            ..where((row) => row.sourceRef.equals(sourceRef)))
          .get();
      final appliedByPayload = <String, DateTime?>{
        for (final row in existing)
          row.payloadJson: row.appliedAt == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(row.appliedAt!),
      };

      await (_db.delete(_db.handwritingProposals)
            ..where((row) => row.sourceRef.equals(sourceRef)))
          .go();

      for (var index = 0; index < set.proposals.length; index++) {
        final proposal = set.proposals[index];
        final payload = _encode(proposal, sourceRef);
        await _db.into(_db.handwritingProposals).insertOnConflictUpdate(
              HandwritingProposalsCompanion.insert(
                id: '$sourceRef#${proposal.id}',
                sourceRef: sourceRef,
                proposalId: proposal.id,
                sortIndex: index,
                kind: proposal.kind.storageKey,
                payloadJson: payload,
                appliedAt:
                    Value(appliedByPayload[payload]?.millisecondsSinceEpoch),
                createdAt: now,
                updatedAt: now,
              ),
            );
      }

      await _db.into(_db.handwritingIntakeRuns).insertOnConflictUpdate(
            HandwritingIntakeRunsCompanion.insert(
              sourceRef: sourceRef,
              analyzedAt: now,
              rawReply: Value(rawReply),
              createdAt: now,
              sourcePhotos: Value(encodedPhotos),
            ),
          );
    });
  }

  /// 所有整理过的照片，最近整理的在前。
  Future<List<HandwritingStoredRun>> runs() async {
    final runRows = await (_db.select(_db.handwritingIntakeRuns)
          ..orderBy([
            (row) => OrderingTerm.desc(row.analyzedAt),
            (row) => OrderingTerm.desc(row.sourceRef),
          ]))
        .get();
    if (runRows.isEmpty) {
      return const <HandwritingStoredRun>[];
    }

    final proposalRows = await (_db.select(_db.handwritingProposals)
          ..orderBy([
            (row) => OrderingTerm.asc(row.sourceRef),
            (row) => OrderingTerm.asc(row.sortIndex),
          ]))
        .get();
    final bySource = <String, List<HandwritingProposalRow>>{};
    for (final row in proposalRows) {
      bySource
          .putIfAbsent(row.sourceRef, () => <HandwritingProposalRow>[])
          .add(row);
    }

    return <HandwritingStoredRun>[
      for (final run in runRows)
        _decodeRun(
          sourceRef: run.sourceRef,
          analyzedAt: DateTime.fromMillisecondsSinceEpoch(run.analyzedAt),
          rawReply: run.rawReply,
          rows: bySource[run.sourceRef] ?? const <HandwritingProposalRow>[],
          sourcePhotos: _decodeSourcePhotos(run.sourcePhotos),
        ),
    ];
  }

  /// 某张照片的整理结果；没整理过返回 `null`。
  Future<HandwritingStoredRun?> runOf(String sourceRef) async {
    final run = await (_db.select(_db.handwritingIntakeRuns)
          ..where((row) => row.sourceRef.equals(sourceRef)))
        .getSingleOrNull();
    if (run == null) {
      return null;
    }
    final rows = await (_db.select(_db.handwritingProposals)
          ..where((row) => row.sourceRef.equals(sourceRef))
          ..orderBy([(row) => OrderingTerm.asc(row.sortIndex)]))
        .get();
    return _decodeRun(
      sourceRef: sourceRef,
      analyzedAt: DateTime.fromMillisecondsSinceEpoch(run.analyzedAt),
      rawReply: run.rawReply,
      rows: rows,
      sourcePhotos: _decodeSourcePhotos(run.sourcePhotos),
    );
  }

  /// 标记一条提案已确认（用户点过确认、且写库成功）。
  Future<void> markApplied({
    required String sourceRef,
    required String proposalId,
    required DateTime appliedAt,
  }) async {
    final stamp = appliedAt.millisecondsSinceEpoch;
    await (_db.update(_db.handwritingProposals)
          ..where((row) =>
              row.id.equals('$sourceRef#$proposalId') & row.appliedAt.isNull()))
        .write(
      HandwritingProposalsCompanion(
        appliedAt: Value(stamp),
        updatedAt: Value(stamp),
      ),
    );
  }

  /// 忘掉某张照片的整理结果（**只删提案与 run 行，照片本身不动**）。
  ///
  /// 这就是"重新整理一遍"的入口：用户觉得这次整理不对，可以先忘掉再跑。
  Future<void> deleteRun(String sourceRef) async {
    await _db.transaction(() async {
      await (_db.delete(_db.handwritingProposals)
            ..where((row) => row.sourceRef.equals(sourceRef)))
          .go();
      await (_db.delete(_db.handwritingIntakeRuns)
            ..where((row) => row.sourceRef.equals(sourceRef)))
          .go();
    });
  }

  /// 清掉所有整理记录（测试与"清空数据"用）。
  Future<void> deleteAll() async {
    await _db.transaction(() async {
      await _db.delete(_db.handwritingProposals).go();
      await _db.delete(_db.handwritingIntakeRuns).go();
    });
  }

  /// 提案 → 一行 JSON。`source_ref` 以 run 的来源为准：解析器交回的
  /// `source_ref` 可能为空，而这一行真正的来源就是这张照片。
  String _encode(HandwritingProposal proposal, String sourceRef) {
    final json = proposal.toJson();
    json['source_ref'] = sourceRef;
    json['id'] = proposal.id;
    return jsonEncode(json);
  }

  Map<String, Object?> _jsonDecode(String payload) {
    final decoded = jsonDecode(payload);
    if (decoded is! Map) {
      throw HandwritingProposalParseException(
        '库里的提案不是 JSON 对象：`$payload`',
      );
    }
    return Map<String, Object?>.from(decoded);
  }

  HandwritingStoredRun _decodeRun({
    required String sourceRef,
    required DateTime analyzedAt,
    required String? rawReply,
    required List<HandwritingProposalRow> rows,
    List<String> sourcePhotos = const <String>[],
  }) {
    return HandwritingStoredRun(
      sourceRef: sourceRef,
      analyzedAt: analyzedAt,
      rawReply: rawReply,
      sourcePhotos: sourcePhotos,
      proposals: List<HandwritingStoredProposal>.unmodifiable(
        rows.map(
          (row) => HandwritingStoredProposal(
            proposal: HandwritingProposal.fromJson(
              _jsonDecode(row.payloadJson),
            ),
            appliedAt: row.appliedAt == null
                ? null
                : DateTime.fromMillisecondsSinceEpoch(row.appliedAt!),
          ),
        ),
      ),
    );
  }

  /// 读回多图整理的照片清单。坏 JSON 容忍成空（单图语义），
  /// 不让一行坏数据把整条队列读崩。
  List<String> _decodeSourcePhotos(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return const <String>[];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return const <String>[];
      }
      return <String>[
        for (final item in decoded)
          if (item is String && item.trim().isNotEmpty) item,
      ];
    } on FormatException {
      return const <String>[];
    }
  }
}
