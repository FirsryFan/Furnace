/// Experience storage for the global agent layer (design §5.5, Phase D).
///
/// Two hard rules from the design are enforced here, not just documented:
///
///   * **Only verified experience is written.** [ExperienceStore.record] takes
///     a [Claim] and refuses anything whose status is not
///     [ClaimStatus.verified]. A proposed/refuted/open claim never becomes a
///     "lesson".
///   * **Every record carries provenance and is revocable.** A record needs the
///     run id and the verifier id that justified it, has a monotonically
///     increasing [ExperienceRecord.version], and a revoked record keeps its row
///     with `revoked_at` set (history is auditable; [recall] skips it).
///
/// The store is deliberately repository-shaped: persistence is an interface so
/// the domain-facing rules above can be tested without a database, and the Drift
/// implementation ([DriftExperienceRepository]) stays a thin mapping onto the
/// v45 `agent_experiences` table. This file does not own that table and does not
/// change it; the columns are exactly the fields of [ExperienceRecord].
///
/// Experience is **not** a correctness source (design §14): nothing here feeds
/// the final answer, and [recall] returns evidence for prompts/ranking only.
library;

import 'package:drift/drift.dart';

import '../../../data/database/database.dart';
import '../domain/claim.dart';

/// One persisted experience row (`agent_experiences`).
class ExperienceRecord {
  const ExperienceRecord({
    required this.id,
    required this.cluster,
    required this.stateKey,
    required this.action,
    required this.reward,
    required this.createdAt,
    this.provenanceRunId,
    this.provenanceVerifierId,
    this.version = 1,
    this.revokedAt,
  });

  final String id;

  /// What family of task this experience belongs to (e.g. `student_solver`).
  final String cluster;

  /// What state it was recorded in; part of the recall key.
  final String stateKey;

  /// What action/response the experience suggests.
  final String action;

  /// Validation signal. Not truth: the design forbids using experience as a
  /// correctness oracle.
  final double reward;

  final String? provenanceRunId;
  final String? provenanceVerifierId;

  /// Incremented each time the same `(cluster, stateKey, action)` is validated
  /// again; a revoked row is never updated, a new version is inserted instead.
  final int version;

  /// Milliseconds since epoch; non-null means this row is revoked.
  final int? revokedAt;

  final int createdAt;

  bool get revoked => revokedAt != null;

  ExperienceRecord copyWith({
    double? reward,
    String? provenanceRunId,
    String? provenanceVerifierId,
    int? version,
    int? revokedAt,
    int? createdAt,
  }) =>
      ExperienceRecord(
        id: id,
        cluster: cluster,
        stateKey: stateKey,
        action: action,
        reward: reward ?? this.reward,
        provenanceRunId: provenanceRunId ?? this.provenanceRunId,
        provenanceVerifierId: provenanceVerifierId ?? this.provenanceVerifierId,
        version: version ?? this.version,
        revokedAt: revokedAt ?? this.revokedAt,
        createdAt: createdAt ?? this.createdAt,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'cluster': cluster,
        'state_key': stateKey,
        'action': action,
        'reward': reward,
        'provenance_run_id': provenanceRunId,
        'provenance_verifier_id': provenanceVerifierId,
        'version': version,
        'revoked_at': revokedAt,
        'created_at': createdAt,
      };

  static ExperienceRecord? fromJson(Object? json) {
    if (json is! Map) {
      return null;
    }
    final id = json['id'];
    final cluster = json['cluster'];
    final stateKey = json['state_key'];
    final action = json['action'];
    final reward = json['reward'];
    final createdAt = json['created_at'];
    if (id is! String ||
        cluster is! String ||
        stateKey is! String ||
        action is! String ||
        reward is! num ||
        createdAt is! int) {
      return null;
    }
    final version = json['version'];
    final revokedAt = json['revoked_at'];
    return ExperienceRecord(
      id: id,
      cluster: cluster,
      stateKey: stateKey,
      action: action,
      reward: reward.toDouble(),
      provenanceRunId: json['provenance_run_id'] as String?,
      provenanceVerifierId: json['provenance_verifier_id'] as String?,
      version: version is int ? version : 1,
      revokedAt: revokedAt is int ? revokedAt : null,
      createdAt: createdAt,
    );
  }

  @override
  String toString() => 'ExperienceRecord($id $cluster/$stateKey v$version '
      'reward=${reward.toStringAsFixed(2)}'
      '${revoked ? ' revoked' : ''})';
}

/// Storage boundary for experiences.
///
/// Kept minimal so the schema owner can implement it with Drift without this
/// file importing the database (design §6.3 dependency direction: infrastructure
/// may implement repository interfaces, domain does not). The store treats it as
/// the single source of truth and never keeps a shadow copy.
abstract interface class ExperienceRepository {
  Future<void> insert(ExperienceRecord record);

  Future<ExperienceRecord?> findById(String id);

  /// Updates an existing row (id must exist).
  Future<ExperienceRecord> update(ExperienceRecord record);

  /// Rows in [cluster], optionally narrowed to one [stateKey]. Revoked rows are
  /// excluded unless [includeRevoked] is true.
  Future<List<ExperienceRecord>> findByCluster(
    String cluster, {
    String? stateKey,
    bool includeRevoked = false,
  });
}

/// Non-persistent implementation used by tests and as the fallback while the v45
/// table is not available yet.
///
/// It is a fake, not a degraded production store: nothing in the app depends on
/// it surviving a restart, and [ExperienceStore] does not pretend it does.
class InMemoryExperienceRepository implements ExperienceRepository {
  final Map<String, ExperienceRecord> _rows = {};

  @override
  Future<void> insert(ExperienceRecord record) async {
    if (_rows.containsKey(record.id)) {
      throw StateError('experience ${record.id} already exists');
    }
    _rows[record.id] = record;
  }

  @override
  Future<ExperienceRecord?> findById(String id) async => _rows[id];

  @override
  Future<ExperienceRecord> update(ExperienceRecord record) async {
    if (!_rows.containsKey(record.id)) {
      throw StateError('experience ${record.id} does not exist');
    }
    _rows[record.id] = record;
    return record;
  }

  @override
  Future<List<ExperienceRecord>> findByCluster(
    String cluster, {
    String? stateKey,
    bool includeRevoked = false,
  }) async =>
      [
        for (final row in _rows.values)
          if (row.cluster == cluster &&
              (stateKey == null || row.stateKey == stateKey) &&
              (includeRevoked || !row.revoked))
            row,
      ];

  /// Testing/audit helper: every row, including revoked ones.
  List<ExperienceRecord> get allRows => List<ExperienceRecord>.unmodifiable(
        _rows.values,
      );
}

/// Drift-backed implementation of [ExperienceRepository] for the v45
/// `agent_experiences` table (design §5.5).
///
/// It is a pure mapping: the table is owned by the schema work, and every column
/// here has a 1:1 counterpart in [ExperienceRecord]. Reads exclude revoked rows
/// by default at the SQL level; the store applies the same rule again so a fake
/// implementation and this one behave identically.
class DriftExperienceRepository implements ExperienceRepository {
  DriftExperienceRepository(this._db);

  final AppDatabase _db;

  @override
  Future<void> insert(ExperienceRecord record) async {
    await _db.into(_db.agentExperiences).insert(_toCompanion(record));
  }

  @override
  Future<ExperienceRecord?> findById(String id) async {
    final row = await (_db.select(_db.agentExperiences)
          ..where((table) => table.id.equals(id)))
        .getSingleOrNull();
    return row == null ? null : _fromRow(row);
  }

  @override
  Future<ExperienceRecord> update(ExperienceRecord record) async {
    final updated = await (_db.update(_db.agentExperiences)
          ..where((table) => table.id.equals(record.id)))
        .write(_toCompanion(record));
    if (updated == 0) {
      throw StateError('experience ${record.id} does not exist');
    }
    return record;
  }

  @override
  Future<List<ExperienceRecord>> findByCluster(
    String cluster, {
    String? stateKey,
    bool includeRevoked = false,
  }) async {
    final rows = await (_db.select(_db.agentExperiences)
          ..where((table) {
            var predicate = table.cluster.equals(cluster);
            if (stateKey != null) {
              predicate = predicate & table.stateKey.equals(stateKey);
            }
            if (!includeRevoked) {
              predicate = predicate & table.revokedAt.isNull();
            }
            return predicate;
          }))
        .get();
    return [for (final row in rows) _fromRow(row)];
  }

  AgentExperiencesCompanion _toCompanion(ExperienceRecord record) =>
      AgentExperiencesCompanion(
        id: Value(record.id),
        cluster: Value(record.cluster),
        stateKey: Value(record.stateKey),
        action: Value(record.action),
        reward: Value(record.reward),
        provenanceRunId: Value(record.provenanceRunId),
        provenanceVerifierId: Value(record.provenanceVerifierId),
        version: Value(record.version),
        revokedAt: Value(record.revokedAt),
        createdAt: Value(record.createdAt),
      );

  ExperienceRecord _fromRow(AgentExperienceRow row) => ExperienceRecord(
        id: row.id,
        cluster: row.cluster,
        stateKey: row.stateKey,
        action: row.action,
        reward: row.reward,
        provenanceRunId: row.provenanceRunId,
        provenanceVerifierId: row.provenanceVerifierId,
        version: row.version,
        revokedAt: row.revokedAt,
        createdAt: row.createdAt,
      );
}

/// Why an experience was refused.
enum ExperienceRejectionReason {
  /// The source claim is not `verified`; only verified experience is written.
  notVerified,

  /// No run id: the record could not be traced back to a run.
  missingProvenance,

  /// No verifier id: the record could not be traced back to a verdict.
  missingVerifier,

  /// `cluster`, `stateKey`, `action` or `id` was blank.
  emptyField,

  /// Reward was NaN/infinite.
  invalidReward,
}

/// The result of trying to record an experience.
class ExperienceAdmission {
  const ExperienceAdmission.accepted(this.record) : rejection = null;

  const ExperienceAdmission.rejected(this.rejection) : record = null;

  final ExperienceRecord? record;
  final ExperienceRejectionReason? rejection;

  bool get accepted => record != null;

  @override
  String toString() => accepted
      ? 'ExperienceAdmission.accepted($record)'
      : 'ExperienceAdmission.rejected(${rejection?.name})';
}

/// Validating experience writer/reader.
///
/// Only [record] is a write path and it can only be reached with a verified
/// claim. [recall] is a read helper; it deliberately does not rank by "truth",
/// only by reward/version, and the caller must not treat it as evidence of
/// correctness.
class ExperienceStore {
  ExperienceStore({required this.repository});

  final ExperienceRepository repository;

  int _generatedIds = 0;

  /// Records [claim] as an experience, if and only if it is verified.
  ///
  /// Re-recording the same `(cluster, stateKey, action)` while an active row
  /// exists updates that row with `version + 1` and the new provenance; if only
  /// revoked rows exist, a new row with `version = max + 1` is inserted so the
  /// revocation history stays intact.
  Future<ExperienceAdmission> record({
    required Claim claim,
    required String cluster,
    required String stateKey,
    required String action,
    required String provenanceRunId,
    required String provenanceVerifierId,
    double reward = 1.0,
    String? id,
    int? nowMs,
  }) async {
    if (claim.status != ClaimStatus.verified) {
      return const ExperienceAdmission.rejected(
        ExperienceRejectionReason.notVerified,
      );
    }
    if (provenanceRunId.trim().isEmpty) {
      return const ExperienceAdmission.rejected(
        ExperienceRejectionReason.missingProvenance,
      );
    }
    if (provenanceVerifierId.trim().isEmpty) {
      return const ExperienceAdmission.rejected(
        ExperienceRejectionReason.missingVerifier,
      );
    }
    if (cluster.trim().isEmpty ||
        stateKey.trim().isEmpty ||
        action.trim().isEmpty) {
      return const ExperienceAdmission.rejected(
        ExperienceRejectionReason.emptyField,
      );
    }
    if (!reward.isFinite) {
      return const ExperienceAdmission.rejected(
        ExperienceRejectionReason.invalidReward,
      );
    }

    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    final history = (await repository.findByCluster(
      cluster,
      stateKey: stateKey,
      includeRevoked: true,
    ))
        .where((row) => row.action == action)
        .toList();

    ExperienceRecord? active;
    var maxVersion = 0;
    for (final row in history) {
      if (row.version > maxVersion) {
        maxVersion = row.version;
      }
      if (!row.revoked) {
        active = row;
      }
    }

    if (active != null) {
      final updated = active.copyWith(
        reward: reward,
        provenanceRunId: provenanceRunId,
        provenanceVerifierId: provenanceVerifierId,
        version: active.version + 1,
      );
      await repository.update(updated);
      return ExperienceAdmission.accepted(updated);
    }

    final recordId = (id != null && id.trim().isNotEmpty)
        ? id
        : 'exp_${now}_${_generatedIds++}';
    final record = ExperienceRecord(
      id: recordId,
      cluster: cluster,
      stateKey: stateKey,
      action: action,
      reward: reward,
      provenanceRunId: provenanceRunId,
      provenanceVerifierId: provenanceVerifierId,
      version: maxVersion + 1,
      createdAt: now,
    );
    await repository.insert(record);
    return ExperienceAdmission.accepted(record);
  }

  /// Active (non-revoked) experiences for the recall key, best first.
  Future<List<ExperienceRecord>> recall({
    required String cluster,
    required String stateKey,
  }) async {
    final rows = await repository.findByCluster(cluster, stateKey: stateKey);
    final result = [
      for (final row in rows)
        if (!row.revoked) row,
    ];
    result.sort((a, b) {
      final byReward = b.reward.compareTo(a.reward);
      if (byReward != 0) {
        return byReward;
      }
      return b.version.compareTo(a.version);
    });
    return result;
  }

  /// Revokes one experience row: `revoked_at` is set and the row is kept.
  ///
  /// Returns `false` when the id is unknown or already revoked, so callers can
  /// distinguish "nothing to revoke" from success.
  Future<bool> revoke(String id, {int? nowMs}) async {
    final record = await repository.findById(id);
    if (record == null || record.revoked) {
      return false;
    }
    final updated = record.copyWith(
      revokedAt: nowMs ?? DateTime.now().millisecondsSinceEpoch,
    );
    await repository.update(updated);
    return true;
  }

  Future<ExperienceRecord?> find(String id) => repository.findById(id);
}
