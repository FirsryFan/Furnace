import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/features/ai/domain/claim.dart';
import 'package:furnace/features/ai/domain/reasoning_ledger.dart';

class _FakeChecker implements ClaimChecker {
  _FakeChecker();

  ClaimStatus status = ClaimStatus.verified;
  int calls = 0;
  final List<String> checkedIds = [];

  @override
  Future<ClaimCheckResult> check(
    Claim claim,
    List<Claim> dependencies,
  ) async {
    calls++;
    checkedIds.add(claim.id);
    return ClaimCheckResult(
      status: status,
      method: ClaimCheckMethod.deterministic,
      evidence: 'checked ${claim.id}',
    );
  }
}

Claim _claim(
  String id, {
  String? canonical,
  ClaimKind kind = ClaimKind.equation,
  List<ClaimRef> deps = const [],
  ClaimStatus status = ClaimStatus.proposed,
}) =>
    Claim(
      id: id,
      kind: kind,
      canonical: canonical ?? '$id=1',
      statement: '$id=1',
      deps: deps,
      status: status,
    );

Claim _given(String id) =>
    Claim.given(id: id, statement: 'given $id', canonical: 'given $id');

void main() {
  group('ClaimLedger.add', () {
    test('rejects unknown dependencies', () {
      final ledger = ClaimLedger();
      expect(
        () => ledger.add(
          _claim('b', deps: const [ClaimRef(claimId: 'missing', version: 1)]),
        ),
        throwsArgumentError,
      );
    });

    test('rejects duplicate ids and self-dependencies', () {
      final ledger = ClaimLedger();
      ledger.add(_claim('a'));
      expect(() => ledger.add(_claim('a')), throwsArgumentError);
      expect(
        () => ledger.add(
          _claim('b', deps: const [ClaimRef(claimId: 'b', version: 1)]),
        ),
        throwsArgumentError,
      );
    });

    test('enforces the claim budget instead of trimming silently', () {
      final ledger = ClaimLedger(maxClaims: 1);
      ledger.add(_claim('a'));
      expect(() => ledger.add(_claim('b')), throwsStateError);
    });

    test('mints unique ids', () {
      final ledger = ClaimLedger();
      final first = ledger.nextClaimId();
      ledger.add(_claim(first));
      final second = ledger.nextClaimId();
      expect(second, isNot(first));
    });
  });

  group('ClaimLedger check cache', () {
    test('same ClaimKey is checked only once', () async {
      final checker = _FakeChecker();
      final ledger = ClaimLedger(checker: checker);
      ledger.add(_claim('c1', canonical: 'x=1'));
      ledger.add(_claim('c2', canonical: 'x=1'));

      final first = await ledger.check('c1');
      expect(first.status, ClaimStatus.verified);
      expect(first.cached, isFalse);

      final second = await ledger.check('c2');
      expect(second.cached, isTrue);
      expect(checker.calls, 1);
      expect(ledger.checksExecuted, 1);
      expect(ledger['c2']!.status, ClaimStatus.verified);
    });

    test('a given claim needs no checker run', () async {
      final checker = _FakeChecker();
      final ledger = ClaimLedger(checker: checker);
      ledger.add(_given('a'));
      final result = await ledger.check('a');
      expect(result.status, ClaimStatus.given);
      expect(checker.calls, 0);
    });

    test('check without a checker throws instead of guessing', () async {
      final ledger = ClaimLedger();
      ledger.add(_claim('a'));
      await expectLater(ledger.check('a'), throwsStateError);
    });

    test('recordCheck caches an externally computed verdict', () async {
      final checker = _FakeChecker();
      final ledger = ClaimLedger(checker: checker);
      ledger.add(_claim('b'));
      ledger.recordCheck(
        'b',
        const ClaimCheckResult(
          status: ClaimStatus.verified,
          method: ClaimCheckMethod.symbolic,
          evidence: 'symbolic check',
        ),
      );
      final cached = await ledger.check('b');
      expect(cached.cached, isTrue);
      expect(checker.calls, 0);
      expect(ledger['b']!.checkMethod, ClaimCheckMethod.symbolic);
    });
  });

  group('ClaimLedger dependency invalidation', () {
    test('a premise change invalidates only the downstream cone', () async {
      final checker = _FakeChecker();
      final ledger = ClaimLedger(checker: checker);
      final a = _given('a');
      ledger
        ..add(a)
        ..add(_claim('b', deps: const [ClaimRef(claimId: 'a', version: 1)]))
        ..add(_claim('c', deps: const [ClaimRef(claimId: 'b', version: 1)]))
        ..add(_claim('d'));

      await ledger.check('b');
      await ledger.check('c');
      await ledger.check('d');
      expect(checker.calls, 3);

      // Re-checking a fresh claim is a cache hit.
      expect((await ledger.check('b')).cached, isTrue);
      expect(checker.calls, 3);

      // a: given -> verified changes its status, so b and c go stale.
      ledger.updateStatus('a', ClaimStatus.verified, evidence: 'premise ok');
      expect(ledger['b']!.version, 2);
      // c was already bumped once when b itself became verified, so it carries
      // two input changes; versions count changes, not recheck count.
      expect(ledger['c']!.version, 3);
      expect(ledger['d']!.version, 1);

      // Unrelated claim d keeps its cached result.
      expect((await ledger.check('d')).cached, isTrue);
      expect(checker.calls, 3);

      // b and c are re-checked exactly once each.
      expect((await ledger.check('b')).cached, isFalse);
      expect((await ledger.check('c')).cached, isFalse);
      expect(checker.calls, 5);
    });

    test('the key resolves live dependency versions, not stale edges',
        () async {
      final checker = _FakeChecker();
      final ledger = ClaimLedger(checker: checker);
      ledger
        ..add(_given('a'))
        ..add(_claim('b', deps: const [ClaimRef(claimId: 'a', version: 1)]));

      await ledger.check('b');
      expect(checker.calls, 1);
      expect(ledger['b']!.deps.single.version, 1);

      ledger.invalidate('a');
      expect(ledger['a']!.version, 2);
      expect(ledger['b']!.version, 2);

      await ledger.check('b');
      expect(checker.calls, 2);
    });

    test('invalidate returns the affected ids and drops their cache', () async {
      final ledger = ClaimLedger();
      ledger
        ..add(_claim('a'))
        ..add(_claim('b', deps: const [ClaimRef(claimId: 'a', version: 1)]))
        ..add(_claim('c', deps: const [ClaimRef(claimId: 'b', version: 1)]));

      expect(
        ledger.dependentsOf('a').map((claim) => claim.id),
        ['b'],
      );
      expect(
        ledger.transitiveDependentsOf('a').map((claim) => claim.id),
        ['b', 'c'],
      );
      final affected = ledger.invalidate('a');
      expect(affected, {'a', 'b', 'c'});
    });

    test('updateStatus drops the claim own cache entry', () async {
      final checker = _FakeChecker();
      final ledger = ClaimLedger(checker: checker);
      ledger.add(_claim('b'));
      await ledger.check('b');
      expect(checker.calls, 1);
      ledger.updateStatus('b', ClaimStatus.refuted, evidence: 'counterexample');
      await ledger.check('b');
      expect(checker.calls, 2);
    });
  });

  group('ClaimLedger final answer admissibility', () {
    test('only verified/given claims with admissible dependencies pass',
        () async {
      final checker = _FakeChecker();
      final ledger = ClaimLedger(checker: checker);
      ledger
        ..add(_given('a'))
        ..add(_claim('b', deps: const [ClaimRef(claimId: 'a', version: 1)]))
        ..add(_claim('proposed'))
        ..add(_claim('refuted', status: ClaimStatus.refuted))
        ..add(_claim('h', status: ClaimStatus.refuted))
        ..add(
          _claim(
            'g',
            status: ClaimStatus.verified,
            deps: const [ClaimRef(claimId: 'h', version: 1)],
          ),
        );

      await ledger.check('b');
      final answerable = ledger.finalAnswerClaims.map((claim) => claim.id);
      expect(answerable, ['a', 'b']);
      expect(ledger.dependenciesReady('g'), isFalse);
    });

    test('stale claims are excluded from the final answer', () async {
      final checker = _FakeChecker();
      final ledger = ClaimLedger(checker: checker);
      ledger
        ..add(_given('a'))
        ..add(_claim('b', deps: const [ClaimRef(claimId: 'a', version: 1)]));
      await ledger.check('b');
      expect(ledger.finalAnswerClaims, isNotEmpty);

      ledger.invalidate('a');
      expect(ledger['a']!.isFresh, isFalse);
      expect(ledger.finalAnswerClaims, isEmpty);
    });
  });

  group('ClaimLedger registration', () {
    test('merges an equivalent claim instead of adding a duplicate', () async {
      final ledger = ClaimLedger();
      final first = await ledger.register(_claim('c1', canonical: 'x=1'));
      final second = await ledger.register(_claim('c2', canonical: 'x=1'));
      expect(first.merged, isFalse);
      expect(second.merged, isTrue);
      expect(second.claim.id, 'c1');
      expect(ledger.length, 1);
    });

    test('keeps an unproven possible duplicate as its own claim', () async {
      final ledger = ClaimLedger();
      await ledger.register(
        _claim('c1', canonical: '小球在光滑水平面上做匀速圆周运动'),
      );
      final second = await ledger.register(
        _claim(
          'c2',
          canonical: '小球在光滑水平面上做匀速圆周运动且线速度指向圆心',
        ),
      );
      expect(second.merged, isFalse);
      expect(second.possiblyDuplicate, isTrue);
      expect(second.possibleDuplicateOf!.id, 'c1');
      expect(ledger.length, 2);
    });

    test('registering an existing id is a no-op, not a duplicate', () async {
      final ledger = ClaimLedger();
      final claim = _claim('c1', canonical: 'x=1');
      await ledger.register(claim);
      final again = await ledger.register(claim);
      expect(again.merged, isTrue);
      expect(ledger.length, 1);
    });
  });

  group('ClaimLedger summary', () {
    test('summary is structured and bounded', () async {
      final ledger = ClaimLedger();
      for (var i = 0; i < 15; i++) {
        ledger.add(_claim('c$i', status: ClaimStatus.verified));
      }
      final summary = ledger.summary(maxClaims: 5);
      expect(summary.claims.length, 5);
      expect(summary.total, 15);
      expect(summary.truncated, isTrue);
      expect(summary.toPromptText(), contains('[verified/equation]'));
    });
  });
}
