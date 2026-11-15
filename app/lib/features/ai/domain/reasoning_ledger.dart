/// The claim DAG a reasoning run builds, with dependency versions, a check cache
/// and the rule that only settled support may enter the final answer.
///
/// Why a ledger and not ad-hoc state (design 搂7.4):
///
///   * **Check once per key.** A model that re-derives "m2/m1 = 7" five times
///     with unchanged inputs must not run five checks. [ClaimKey] is the
///     canonical proposition plus the current versions of its dependencies, so
///     a repeat is a cache hit, not a second run.
///   * **Invalidate downstream only.** If a premise changes, everything that
///     used it is stale, but unrelated claims are not. Version bumps walk the
///     dependent cone and drop exactly those cache entries; the rest of the
///     cache survives.
///   * **Admissibility.** The final answer may cite only `verified`/`given`
///     claims whose dependencies are also admissible and whose checks are still
///     fresh ([finalAnswerClaims]).
///
/// The ledger is storage-agnostic: it holds no Flutter or database types. The
/// schema v45 `agent_claims` table can persist [Claim.toJson] verbatim.
library;

import 'dart:collection';

import 'claim.dart';
import 'claim_matcher.dart';

/// The outcome of checking one claim.
class ClaimCheckResult {
  const ClaimCheckResult({
    required this.status,
    this.method,
    this.evidence,
    this.issues = const [],
    this.cached = false,
  });

  /// `verified`, `refuted` or `open` for a checker; `given` for a premise that
  /// is accepted without checking.
  final ClaimStatus status;

  /// How the status was established (`null` for a given premise).
  final ClaimCheckMethod? method;

  /// Human-readable evidence: checker output, numeric value, counter-example.
  final String? evidence;

  /// Problems found while checking (kept short; not the raw reasoning).
  final List<String> issues;

  /// Whether this result came from the cache instead of a checker run.
  final bool cached;

  ClaimCheckResult asCached() => ClaimCheckResult(
        status: status,
        method: method,
        evidence: evidence,
        issues: issues,
        cached: true,
      );

  Map<String, Object?> toJson() => {
        'status': status.id,
        'check_method': method?.id,
        'evidence': evidence,
        if (issues.isNotEmpty) 'issues': issues,
        'cached': cached,
      };
}

/// The only thing the ledger asks of a checker: given a claim and its current
/// dependencies, decide its status. Checks are deliberately outside the domain
/// code so the same ledger can be driven by a deterministic checker in tests, a
/// symbolic checker in the app, or a judge.
abstract interface class ClaimChecker {
  Future<ClaimCheckResult> check(Claim claim, List<Claim> dependencies);
}

/// The outcome of adding a claim through the matcher.
class ClaimRegistration {
  const ClaimRegistration({
    required this.claim,
    required this.merged,
    this.match,
  });

  /// The claim that now represents this proposition in the ledger: either the
  /// newly added claim, or the existing claim it was merged into.
  final Claim claim;

  /// Whether the claim was merged into an existing one (not added).
  final bool merged;

  /// How the matcher decided. `null` when there were no other claims.
  final ClaimMatch? match;

  /// Whether the matcher found a suspicious but unproven duplicate. The caller
  /// may count this (e.g. as a repeated-claim signal) without merging.
  bool get possiblyDuplicate => match?.possiblyDuplicate ?? false;

  /// The existing claim that looks like a possible duplicate, if any.
  Claim? get possibleDuplicateOf => possiblyDuplicate ? match?.matched : null;
}

class _CachedCheck {
  const _CachedCheck({
    required this.claimId,
    required this.canonical,
    required this.result,
  });

  final String claimId;
  final String canonical;
  final ClaimCheckResult result;
}

/// The claim DAG of one run with a check cache keyed by [ClaimKey].
///
/// Invariants:
///
///   * a claim's dependencies must already be in the ledger when it is added,
///     so the graph is a DAG by construction (no cycle check needed);
///   * claims are never removed during a run (the cap is a hard budget, not an
///     eviction policy), so dependency ids always resolve;
///   * [check] runs the checker at most once per [ClaimKey] while the inputs
///     are unchanged.
class ClaimLedger {
  ClaimLedger({
    ClaimMatcher? matcher,
    this.checker,
    this.maxClaims = 256,
    this.maxCacheEntries = 512,
  }) : _matcher = matcher ?? ClaimMatcher();

  /// Used by [register] to merge paraphrases. Defaults to a matcher with no
  /// LLM judge, so registration is deterministic and offline.
  final ClaimMatcher _matcher;

  /// Checker for [check]; `recordCheck` can be used instead when the status is
  /// computed elsewhere.
  final ClaimChecker? checker;

  /// Hard cap for one run. A reasoning run with more claims than this is out of
  /// budget, not silently truncated.
  final int maxClaims;

  /// Cache bound. Old keys are unreachable after a version bump anyway; this is
  /// only a memory guard for very long runs.
  final int maxCacheEntries;

  final LinkedHashMap<String, Claim> _claims = LinkedHashMap();
  final LinkedHashMap<ClaimKey, _CachedCheck> _cache = LinkedHashMap();
  int _nextId = 1;
  int _checksExecuted = 0;

  /// All claims in insertion order.
  Iterable<Claim> get claims => _claims.values;

  int get length => _claims.length;

  /// Number of checker invocations so far (cache hits excluded). Used by tests
  /// and by run metrics.
  int get checksExecuted => _checksExecuted;

  /// Number of live cache entries.
  int get cacheSize => _cache.length;

  bool contains(String claimId) => _claims.containsKey(claimId);

  Claim? operator [](String claimId) => _claims[claimId];

  /// A unique claim id within this ledger (for callers that do not mint ids).
  String nextClaimId() {
    while (_claims.containsKey('c$_nextId')) {
      _nextId++;
    }
    return 'c${_nextId++}';
  }

  /// Adds [claim] without matching it against the existing graph.
  ///
  /// The caller is responsible for the id; [register] is the normal entry point
  /// because it merges paraphrases first. Throws [ArgumentError] for an empty or
  /// duplicate id, a missing dependency, or a self-dependency, and [StateError]
  /// when the ledger is full.
  Claim add(Claim claim) {
    if (claim.id.isEmpty) {
      throw ArgumentError.value(claim.id, 'claim.id', 'must not be empty');
    }
    if (_claims.containsKey(claim.id)) {
      throw ArgumentError.value(claim.id, 'claim.id', 'already in ledger');
    }
    if (_claims.length >= maxClaims) {
      throw StateError('claim ledger is full ($maxClaims claims)');
    }
    for (final dep in claim.deps) {
      if (dep.claimId == claim.id) {
        throw ArgumentError('claim ${claim.id} cannot depend on itself');
      }
      if (!_claims.containsKey(dep.claimId)) {
        throw ArgumentError(
          'claim ${claim.id} depends on unknown claim ${dep.claimId}',
        );
      }
    }
    _claims[claim.id] = claim;
    return claim;
  }

  /// Merges [claim] into an existing equivalent claim when the matcher is
  /// confident, otherwise adds it.
  ///
  /// An unproven similarity never merges (design 搂10.7): the claim is added and
  /// the registration reports [ClaimRegistration.possiblyDuplicate].
  Future<ClaimRegistration> register(Claim claim) async {
    final existing = _claims[claim.id];
    if (existing != null) {
      return ClaimRegistration(claim: existing, merged: true);
    }
    final match = await _matcher.find(claim, _claims.values);
    final matched = match?.matched;
    if (match != null && match.merge && matched != null) {
      return ClaimRegistration(claim: matched, merged: true, match: match);
    }
    add(claim);
    return ClaimRegistration(claim: claim, merged: false, match: match);
  }

  /// Checks [claimId], reusing a cached result when the [ClaimKey] is unchanged.
  ///
  /// A `given` claim is admissible without a checker run. Otherwise [checker]
  /// must be configured; use [recordCheck] when the verdict comes from outside.
  Future<ClaimCheckResult> check(String claimId) async {
    final claim = _require(claimId);
    if (claim.kind == ClaimKind.given || claim.status == ClaimStatus.given) {
      claim.checkedVersion = claim.version;
      return const ClaimCheckResult(status: ClaimStatus.given);
    }
    final activeChecker = checker;
    if (activeChecker == null) {
      throw StateError('ClaimLedger.check called without a ClaimChecker');
    }
    final key = _keyFor(claim);
    final cached = _cache[key];
    if (cached != null && cached.canonical == claim.canonical) {
      return _apply(claim, cached.result.asCached(), key);
    }
    _checksExecuted++;
    final result = await activeChecker.check(claim, dependenciesOf(claimId));
    return _apply(claim, result, key);
  }

  /// Applies a check result computed elsewhere (e.g. a verifier or a symbolic
  /// engine) with the same caching/invalidation semantics as [check].
  ClaimCheckResult recordCheck(String claimId, ClaimCheckResult result) {
    final claim = _require(claimId);
    final key = _keyFor(claim);
    return _apply(claim, result, key);
  }

  /// Sets a status discovered outside a check (e.g. a premise refuted by a
  /// verifier or a decision the run commits to).
  ///
  /// The claim's own cache entry is dropped and every dependent is marked stale;
  /// unrelated claims keep their cache entries.
  void updateStatus(
    String claimId,
    ClaimStatus status, {
    String? evidence,
    ClaimCheckMethod? method,
  }) {
    final claim = _require(claimId);
    final unchanged = claim.status == status && claim.evidence == evidence;
    claim.status = status;
    claim.checkMethod = method ?? claim.checkMethod;
    claim.evidence = evidence ?? claim.evidence;
    claim.checkedVersion = claim.version;
    _dropCacheFor({claimId});
    if (!unchanged) {
      _invalidateDownstream(claimId);
    }
  }

  /// Marks [claimId] and its entire dependent cone stale: their versions are
  /// bumped and their cache entries are dropped. Returns the affected ids.
  ///
  /// This is what "渚濊禆鍙樺寲鍙け鏁堜笅娓? means concretely: unrelated claims are not
  /// touched, so their cache hits survive.
  Set<String> invalidate(String claimId) {
    final claim = _require(claimId);
    claim.version += 1;
    final affected = <String>{claimId};
    for (final dependent in transitiveDependentsOf(claimId)) {
      dependent.version += 1;
      affected.add(dependent.id);
    }
    _dropCacheFor(affected);
    return affected;
  }

  /// Direct dependents of [claimId] (claims that mention it in [Claim.deps]).
  List<Claim> dependentsOf(String claimId) => [
        for (final claim in _claims.values)
          if (claim.deps.any((dep) => dep.claimId == claimId)) claim,
      ];

  /// Transitive dependents, breadth-first and deterministic (insertion order).
  List<Claim> transitiveDependentsOf(String claimId) {
    final seen = <String>{claimId};
    final result = <Claim>[];
    final queue = Queue<String>()..add(claimId);
    while (queue.isNotEmpty) {
      final current = queue.removeFirst();
      for (final claim in _claims.values) {
        if (seen.contains(claim.id)) {
          continue;
        }
        if (claim.deps.any((dep) => dep.claimId == current)) {
          seen.add(claim.id);
          result.add(claim);
          queue.add(claim.id);
        }
      }
    }
    return result;
  }

  /// Current claims for [claimId]'s recorded dependencies.
  List<Claim> dependenciesOf(String claimId) {
    final claim = _require(claimId);
    return [for (final dep in claim.deps) _require(dep.claimId)];
  }

  /// Whether every dependency of [claimId] is admissible and fresh.
  bool dependenciesReady(String claimId) {
    for (final dependency in dependenciesOf(claimId)) {
      if (!dependency.isAdmissible || !dependency.isFresh) {
        return false;
      }
    }
    return true;
  }

  /// Claims that may support the final answer: admissible, fresh, and with all
  /// dependencies admissible and fresh too (design 搂7.4). A verified leaf whose
  /// premise was refuted is not included.
  List<Claim> get finalAnswerClaims => [
        for (final claim in _claims.values)
          if (claim.isAdmissible &&
              claim.isFresh &&
              dependenciesReady(claim.id))
            claim,
      ];

  /// Structured digest for a verifier (never the raw reasoning text).
  ClaimSummary summary({int maxClaims = 12}) =>
      ClaimSummary.of(_claims.values, maxClaims: maxClaims);

  void clear() {
    _claims.clear();
    _cache.clear();
    _checksExecuted = 0;
    _nextId = 1;
  }

  // ---------------------------------------------------------------------------
  // Internals.
  // ---------------------------------------------------------------------------

  Claim _require(String claimId) {
    final claim = _claims[claimId];
    if (claim == null) {
      throw ArgumentError.value(claimId, 'claimId', 'not in ledger');
    }
    return claim;
  }

  /// Cache identity: canonical proposition + *current* dependency versions.
  ///
  /// The claim's stored [Claim.deps] may be older; resolving live versions here
  /// is what makes a dependency change produce a cache miss even before the
  /// dependent is explicitly invalidated.
  ClaimKey _keyFor(Claim claim) => ClaimKey(
        canonicalHash: claim.canonicalHash,
        deps: [
          for (final dep in claim.deps)
            ClaimRef(
                claimId: dep.claimId, version: _require(dep.claimId).version),
        ],
      );

  ClaimCheckResult _apply(
    Claim claim,
    ClaimCheckResult result,
    ClaimKey key,
  ) {
    final previousStatus = claim.status;
    claim.status = result.status;
    claim.checkMethod = result.method ?? claim.checkMethod;
    claim.evidence = result.evidence ?? claim.evidence;
    claim.checkedVersion = claim.version;

    // Invalidate the dependent cone *before* inserting this claim's own cache
    // entry: the drop pass walks ids and would otherwise delete the entry that
    // this very check just produced.
    if (previousStatus != result.status) {
      _invalidateDownstream(claim.id);
    }

    if (!result.cached) {
      _cache[key] = _CachedCheck(
        claimId: claim.id,
        canonical: claim.canonical,
        result: result,
      );
      _trimCache();
    }
    return result;
  }

  void _invalidateDownstream(String claimId) {
    final affected = <String>{claimId};
    for (final dependent in transitiveDependentsOf(claimId)) {
      dependent.version += 1;
      affected.add(dependent.id);
    }
    _dropCacheFor(affected);
  }

  void _dropCacheFor(Set<String> claimIds) {
    _cache.removeWhere((_, value) => claimIds.contains(value.claimId));
  }

  void _trimCache() {
    while (_cache.length > maxCacheEntries) {
      _cache.remove(_cache.keys.first);
    }
  }
}
