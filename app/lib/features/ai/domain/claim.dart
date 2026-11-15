/// Claims are the propositions a reasoning run settles while it works.
///
/// A long solve emits sentences like "因为匀速圆周运动，所以向心力大小不变" or
/// "m_2/m_1 = 7". Treating those as free text makes three things impossible:
///
///   * the same proposition reached twice cannot be recognised, so the run
///     re-derives it forever (the loop the process auditor must catch);
///   * a proposition whose dependencies changed cannot be marked stale, so a
///     refuted premise keeps feeding a finished answer;
///   * a verifier that is not allowed to read the raw chain of thought has no
///     structured input to judge.
///
/// This file is the shared vocabulary for those three consumers
/// (`ProcessAuditor`, `ClaimLedger`, `Verifier`). It owns no storage and no
/// matching: [ClaimKey] is an identity, [ClaimMatcher] in `claim_matcher.dart`
/// decides whether two wordings are the same proposition, and
/// `ClaimLedger` in `reasoning_ledger.dart` owns the DAG and the check cache.
///
/// Nothing here imports Flutter or a database, so the domain layer stays pure
/// and testable; the schema v45 `agent_claims` table stores the same fields
/// (`canonical`, `statement`, `deps_json`, `status`, `check_method`,
/// `checked_version`, `evidence`).
library;

/// Stable FNV-1a 64-bit hash, the same scheme the repository already uses for
/// content-addressed ids (`handwriting_proposal_service.dart`,
/// `multiSourceRefFor`).
///
/// This is an identity hash, not a cryptographic digest: [ClaimKey] equality
/// is used to cache checks inside one run, and a collision is additionally
/// guarded by comparing the canonical text itself (see `ClaimLedger`), so a
/// 64-bit hash is sufficient and keeps the domain dependency-free.
String stableClaimHash(String text) {
  var hash = 0xcbf29ce484222325 & 0x7FFFFFFFFFFFFFFF;
  for (final unit in text.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x100000001b3) & 0x7FFFFFFFFFFFFFFF;
  }
  return hash.toRadixString(16).padLeft(16, '0');
}

/// What kind of proposition a [Claim] is.
///
/// The ids match the design's `agent_claims.kind` comment:
/// `given/equation/decision/assumption/open`.
enum ClaimKind {
  /// A premise taken from the question statement (read off the diagram/text).
  /// Admissible in the final answer without being checked.
  given('given'),

  /// An equation or equality the run derived.
  equation('equation'),

  /// A branch/interpretation the run committed to ("选甲、乙两支").
  decision('decision'),

  /// An explicit modelling assumption ("忽略摩擦").
  assumption('assumption'),

  /// A question the run has not settled yet.
  open('open');

  const ClaimKind(this.id);

  /// Stable value written to storage and model JSON.
  final String id;

  static ClaimKind fromId(String? id) => switch (id) {
        'given' => ClaimKind.given,
        'equation' => ClaimKind.equation,
        'decision' => ClaimKind.decision,
        'open' => ClaimKind.open,
        _ => ClaimKind.assumption,
      };
}

/// The verification state of a [Claim].
///
/// The design's status comment lists `proposed/verified/refuted/open`; §7.4
/// additionally treats `given` as directly admissible, so it is a status here
/// as well. A premise is normally created with [ClaimKind.given] *and*
/// [ClaimStatus.given]; the two exist because the schema stores kind and status
/// in separate columns.
enum ClaimStatus {
  proposed('proposed'),
  given('given'),
  verified('verified'),
  refuted('refuted'),
  open('open');

  const ClaimStatus(this.id);

  /// Stable value written to storage.
  final String id;

  /// Whether the claim may appear in the final answer.
  ///
  /// Only `verified` and `given` qualify (design §7.4): a proposed claim is
  /// still being worked on, an open one is a question, and a refuted one is
  /// known false. [ClaimLedger.finalAnswerClaims] additionally requires every
  /// dependency to be admissible, so a verified leaf cannot drag a refuted
  /// premise into the answer.
  bool get isAdmissible =>
      this == ClaimStatus.verified || this == ClaimStatus.given;

  /// Whether the claim has a definite state at all (`proposed`/`open` do not).
  bool get isSettled => switch (this) {
        ClaimStatus.proposed || ClaimStatus.open => false,
        _ => true,
      };

  static ClaimStatus fromId(String? id) => switch (id) {
        'given' => ClaimStatus.given,
        'verified' => ClaimStatus.verified,
        'refuted' => ClaimStatus.refuted,
        'open' => ClaimStatus.open,
        _ => ClaimStatus.proposed,
      };
}

/// How a claim's status was established.
///
/// Mirrors `agent_claims.check_method`; `null` means "never checked".
enum ClaimCheckMethod {
  deterministic('deterministic'),
  symbolic('symbolic'),
  nli('nli'),
  judge('judge');

  const ClaimCheckMethod(this.id);

  final String id;

  static ClaimCheckMethod? fromId(String? id) => switch (id) {
        'deterministic' => ClaimCheckMethod.deterministic,
        'symbolic' => ClaimCheckMethod.symbolic,
        'nli' => ClaimCheckMethod.nli,
        'judge' => ClaimCheckMethod.judge,
        _ => null,
      };
}

/// A dependency edge: "this claim used version [version] of claim [claimId]".
///
/// The version is what makes invalidation precise: when a dependency changes,
/// only claims whose key mentions the old version become stale (design §7.4).
class ClaimRef {
  const ClaimRef({required this.claimId, required this.version});

  final String claimId;
  final int version;

  ClaimRef withVersion(int version) =>
      ClaimRef(claimId: claimId, version: version);

  Map<String, Object?> toJson() => {'id': claimId, 'version': version};

  static ClaimRef? fromJson(Object? json) {
    if (json is! Map) {
      return null;
    }
    final id = json['id'];
    final version = json['version'];
    if (id is! String || id.isEmpty || version is! int) {
      return null;
    }
    return ClaimRef(claimId: id, version: version);
  }

  @override
  bool operator ==(Object other) =>
      other is ClaimRef && other.claimId == claimId && other.version == version;

  @override
  int get hashCode => Object.hash(claimId, version);

  @override
  String toString() => '$claimId@$version';
}

/// One proposition in a reasoning run.
///
/// [canonical] is the normalized wording used for identity/matching
/// (`ClaimMatcher` produces it); [statement] is the model's original sentence,
/// kept for humans, evidence and the verifier summary. The mutable fields are
/// owned by `ClaimLedger`: callers add a claim, the ledger sets its status and
/// evidence, and a dependency change bumps [version].
class Claim {
  Claim({
    required this.id,
    required this.kind,
    required this.canonical,
    required this.statement,
    List<ClaimRef> deps = const [],
    this.status = ClaimStatus.proposed,
    this.checkedVersion = 0,
    this.version = 1,
    this.evidence,
    this.checkMethod,
    int? createdAtMs,
  })  : deps = List<ClaimRef>.unmodifiable(deps),
        createdAtMs = createdAtMs ?? DateTime.now().millisecondsSinceEpoch;

  /// A premise read off the question: admissible without being checked.
  factory Claim.given({
    required String id,
    required String statement,
    String? canonical,
    List<ClaimRef> deps = const [],
    String? evidence,
    int? createdAtMs,
  }) =>
      Claim(
        id: id,
        kind: ClaimKind.given,
        canonical: canonical ?? statement,
        statement: statement,
        deps: deps,
        status: ClaimStatus.given,
        // A premise is accepted on the strength of the question statement, so
        // it starts fresh; [ClaimLedger.invalidate] still makes it stale if its
        // inputs change later.
        checkedVersion: 1,
        evidence: evidence,
        createdAtMs: createdAtMs,
      );

  final String id;
  final ClaimKind kind;

  /// Normalized wording. Empty is allowed for a claim whose text could not be
  /// normalized; the ledger then keys it by [statement].
  final String canonical;

  /// The model's original sentence, used for human/verifier output.
  final String statement;

  /// Dependencies as they were recorded when the claim was added. The ledger
  /// re-resolves these ids to their *current* versions when it builds a
  /// [ClaimKey], so a stale edge never produces a false cache hit.
  final List<ClaimRef> deps;

  ClaimStatus status;
  int checkedVersion;

  /// Bumped when the claim or one of its dependencies changed in a way that can
  /// invalidate a check. [checkedVersion] < [version] means "needs rechecking".
  int version;

  /// Free-form evidence of the last check (checker output / numeric value).
  String? evidence;

  ClaimCheckMethod? checkMethod;

  final int createdAtMs;

  /// Stable identity used by [ClaimKey].
  String get canonicalHash => stableClaimHash(
      canonical.trim().isEmpty ? statement.trim() : canonical.trim());

  /// Whether this claim may appear in the final answer on its own terms.
  ///
  /// Dependency readiness is checked by the ledger, not here: a claim does not
  /// own the graph.
  bool get isAdmissible => status.isAdmissible;

  /// Whether the claim has a definite state (`proposed`/`open` do not).
  bool get isSettled => status.isSettled;

  /// Whether the last check still reflects the current dependency versions.
  bool get isFresh => checkedVersion >= version;

  ClaimRef get ref => ClaimRef(claimId: id, version: version);

  Claim copyWith({
    ClaimStatus? status,
    int? checkedVersion,
    int? version,
    String? evidence,
    ClaimCheckMethod? checkMethod,
  }) =>
      Claim(
        id: id,
        kind: kind,
        canonical: canonical,
        statement: statement,
        deps: deps,
        status: status ?? this.status,
        checkedVersion: checkedVersion ?? this.checkedVersion,
        version: version ?? this.version,
        evidence: evidence ?? this.evidence,
        checkMethod: checkMethod ?? this.checkMethod,
        createdAtMs: createdAtMs,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'kind': kind.id,
        'canonical': canonical,
        'statement': statement,
        'deps': [for (final dep in deps) dep.toJson()],
        'status': status.id,
        'check_method': checkMethod?.id,
        'checked_version': checkedVersion,
        'version': version,
        'evidence': evidence,
        'created_at': createdAtMs,
      };

  static Claim? fromJson(Object? json) {
    if (json is! Map) {
      return null;
    }
    final id = json['id'];
    final statement = json['statement'];
    if (id is! String || statement is! String) {
      return null;
    }
    final rawDeps = json['deps'];
    final deps = <ClaimRef>[
      if (rawDeps is List)
        for (final raw in rawDeps)
          if (ClaimRef.fromJson(raw) case final ref?) ref,
    ];
    final checkedVersion = json['checked_version'];
    final version = json['version'];
    final createdAt = json['created_at'];
    return Claim(
      id: id,
      kind: ClaimKind.fromId(json['kind'] as String?),
      canonical: (json['canonical'] as String?) ?? statement,
      statement: statement,
      deps: deps,
      status: ClaimStatus.fromId(json['status'] as String?),
      checkMethod: ClaimCheckMethod.fromId(json['check_method'] as String?),
      checkedVersion: checkedVersion is int ? checkedVersion : 0,
      version: version is int ? version : 1,
      evidence: json['evidence'] as String?,
      createdAtMs: createdAt is int ? createdAt : null,
    );
  }

  @override
  bool operator ==(Object other) => other is Claim && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Claim($id ${kind.id}/${status.id} "$statement")';
}

/// Identity of one check: the canonical proposition plus the versions of every
/// dependency it used.
///
/// Two checks with the same key must produce the same result, so the ledger
/// runs the checker once per key (design §7.4). The dependency versions are
/// sorted so `[a, b]` and `[b, a]` are the same key.
class ClaimKey {
  ClaimKey({required this.canonicalHash, required Iterable<ClaimRef> deps})
      : depVersions = List<(String, int)>.unmodifiable(
          (deps.map<(String, int)>((dep) => (dep.claimId, dep.version)).toList()
            ..sort(_compareVersions)),
        );

  /// Builds a key from the claim's recorded dependency edges.
  ///
  /// [`ClaimLedger`] uses a live variant that resolves the current dependency
  /// versions, so a bumped dependency always produces a different key.
  factory ClaimKey.of(Claim claim) => ClaimKey(
        canonicalHash: claim.canonicalHash,
        deps: claim.deps,
      );

  final String canonicalHash;
  final List<(String, int)> depVersions;

  static int _compareVersions((String, int) a, (String, int) b) {
    final byId = a.$1.compareTo(b.$1);
    return byId != 0 ? byId : a.$2.compareTo(b.$2);
  }

  @override
  bool operator ==(Object other) {
    if (other is! ClaimKey ||
        other.canonicalHash != canonicalHash ||
        other.depVersions.length != depVersions.length) {
      return false;
    }
    for (var i = 0; i < depVersions.length; i++) {
      if (other.depVersions[i] != depVersions[i]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(canonicalHash, Object.hashAll(depVersions));

  @override
  String toString() => 'ClaimKey($canonicalHash deps:${depVersions.join(',')})';
}

/// The structured digest of a reasoning run's claims.
///
/// This is what a content verifier is allowed to see instead of the raw chain
/// of thought (design §7.3/§7.4): status, statement and evidence, never the
/// solver's private deliberation. [toPromptText] is deliberately small and
/// stable so it can be embedded in a verifier prompt.
class ClaimSummary {
  ClaimSummary({
    required List<Claim> claims,
    int total = 0,
    this.truncated = false,
  })  : claims = List<Claim>.unmodifiable(claims),
        total = total == 0 ? claims.length : total;

  const ClaimSummary.empty()
      : claims = const <Claim>[],
        total = 0,
        truncated = false;

  /// Builds a summary ordered by usefulness to a verifier: admissible claims
  /// first (the answer's support), then refuted ones (possible wrong branches),
  /// then still-open claims, then the rest. At most [maxClaims] are kept.
  factory ClaimSummary.of(
    Iterable<Claim> claims, {
    int maxClaims = 12,
  }) {
    final ordered = <Claim>[];
    for (final status in const [
      ClaimStatus.verified,
      ClaimStatus.given,
      ClaimStatus.refuted,
      ClaimStatus.open,
      ClaimStatus.proposed,
    ]) {
      for (final claim in claims) {
        if (claim.status == status) {
          ordered.add(claim);
        }
      }
    }
    final truncated = ordered.length > maxClaims;
    final kept = truncated ? ordered.sublist(0, maxClaims) : ordered;
    return ClaimSummary(
      claims: kept,
      total: ordered.length,
      truncated: truncated,
    );
  }

  final List<Claim> claims;

  /// Number of claims before truncation.
  final int total;

  /// Whether some claims were dropped to keep the summary small.
  final bool truncated;

  bool get isEmpty => claims.isEmpty;

  List<Claim> get admissible => [
        for (final claim in claims)
          if (claim.isAdmissible) claim
      ];

  List<Claim> get unsettled => [
        for (final claim in claims)
          if (!claim.isSettled) claim
      ];

  Map<String, Object?> toJson() => {
        'total': total,
        'truncated': truncated,
        'claims': [for (final claim in claims) claim.toJson()],
      };

  /// Renders the summary for a verifier prompt.
  ///
  /// One line per claim: `- [status/kind] statement (evidence: ...)`. Status
  /// ids are kept in ASCII so a model reply can quote them unambiguously, and
  /// evidence is clipped so one noisy claim cannot dominate the prompt.
  String toPromptText({int maxChars = 1600}) {
    if (claims.isEmpty) {
      return '（没有抽取到 claim）';
    }
    final buffer = StringBuffer();
    for (final claim in claims) {
      final evidence = claim.evidence?.trim();
      final line = StringBuffer(
        '- [${claim.status.id}/${claim.kind.id}] ${claim.statement.trim()}',
      );
      if (evidence != null && evidence.isNotEmpty) {
        line.write('（依据：${_clip(evidence, 160)}）');
      }
      if (!claim.isFresh) {
        line.write('（依赖已变化，待复核）');
      }
      if (buffer.length + line.length + 1 > maxChars) {
        buffer.write('\n- …（另有 ${total - claims.indexOf(claim)} 条未列出）');
        break;
      }
      buffer
        ..write(line)
        ..write('\n');
    }
    if (truncated && buffer.toString().trim().isEmpty) {
      return '（claim 摘要已截断）';
    }
    return buffer.toString().trimRight();
  }

  static String _clip(String text, int maxChars) =>
      text.length <= maxChars ? text : '${text.substring(0, maxChars)}…';
}
