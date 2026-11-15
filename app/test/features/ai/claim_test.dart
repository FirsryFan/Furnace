import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/features/ai/domain/claim.dart';

void main() {
  group('stableClaimHash', () {
    test('is deterministic and distinguishes different texts', () {
      expect(stableClaimHash('m2/m1=7'), stableClaimHash('m2/m1=7'));
      expect(stableClaimHash('m2/m1=7'), isNot(stableClaimHash('m2/m1=8')));
      expect(stableClaimHash('').length, 16);
    });
  });

  group('ClaimStatus', () {
    test('only verified and given are admissible in the final answer', () {
      expect(ClaimStatus.verified.isAdmissible, isTrue);
      expect(ClaimStatus.given.isAdmissible, isTrue);
      expect(ClaimStatus.proposed.isAdmissible, isFalse);
      expect(ClaimStatus.open.isAdmissible, isFalse);
      expect(ClaimStatus.refuted.isAdmissible, isFalse);
    });

    test('proposed/open are unsettled, verified/refuted/given are settled', () {
      expect(ClaimStatus.proposed.isSettled, isFalse);
      expect(ClaimStatus.open.isSettled, isFalse);
      expect(ClaimStatus.verified.isSettled, isTrue);
      expect(ClaimStatus.refuted.isSettled, isTrue);
      expect(ClaimStatus.given.isSettled, isTrue);
    });

    test('round-trips through storage ids', () {
      for (final status in ClaimStatus.values) {
        expect(ClaimStatus.fromId(status.id), status);
      }
      expect(ClaimStatus.fromId(null), ClaimStatus.proposed);
      expect(ClaimStatus.fromId('not-a-status'), ClaimStatus.proposed);
    });
  });

  group('Claim', () {
    test('given factory creates an admissible premise', () {
      final claim = Claim.given(
        id: 'q1',
        statement: '题目给定 m1 > 0',
      );
      expect(claim.kind, ClaimKind.given);
      expect(claim.status, ClaimStatus.given);
      expect(claim.isAdmissible, isTrue);
      expect(claim.canonical, '题目给定 m1 > 0');
      expect(claim.isFresh, isTrue);
    });

    test('json round-trip keeps status, deps and evidence', () {
      final claim = Claim(
        id: 'c2',
        kind: ClaimKind.equation,
        canonical: 'm2/m1=7',
        statement: 'm_2 / m_1 = 7',
        deps: const [ClaimRef(claimId: 'c1', version: 3)],
        status: ClaimStatus.verified,
        checkedVersion: 2,
        version: 2,
        evidence: '代入数值成立',
        checkMethod: ClaimCheckMethod.deterministic,
        createdAtMs: 1700000000000,
      );
      final restored = Claim.fromJson(claim.toJson());
      expect(restored, isNotNull);
      expect(restored!.id, claim.id);
      expect(restored.kind, claim.kind);
      expect(restored.canonical, claim.canonical);
      expect(restored.statement, claim.statement);
      expect(restored.status, claim.status);
      expect(restored.checkMethod, claim.checkMethod);
      expect(restored.checkedVersion, 2);
      expect(restored.version, 2);
      expect(restored.deps.single, const ClaimRef(claimId: 'c1', version: 3));
      expect(restored.evidence, '代入数值成立');
      expect(restored.createdAtMs, 1700000000000);
    });

    test('declared version below version is stale', () {
      final claim = Claim(
        id: 'c1',
        kind: ClaimKind.equation,
        canonical: 'x=1',
        statement: 'x=1',
        version: 4,
        checkedVersion: 3,
      );
      expect(claim.isFresh, isFalse);
    });
  });

  group('ClaimKey', () {
    test('dependency order does not matter', () {
      final a = ClaimKey(
        canonicalHash: 'abc',
        deps: const [
          ClaimRef(claimId: 'b', version: 2),
          ClaimRef(claimId: 'a', version: 1),
        ],
      );
      final b = ClaimKey(
        canonicalHash: 'abc',
        deps: const [
          ClaimRef(claimId: 'a', version: 1),
          ClaimRef(claimId: 'b', version: 2),
        ],
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('a dependency version change produces a different key', () {
      final before = ClaimKey(
        canonicalHash: 'abc',
        deps: const [ClaimRef(claimId: 'a', version: 1)],
      );
      final after = ClaimKey(
        canonicalHash: 'abc',
        deps: const [ClaimRef(claimId: 'a', version: 2)],
      );
      expect(before, isNot(after));
    });

    test('ClaimKey.of uses the claim canonical hash and its deps', () {
      final claim = Claim(
        id: 'c1',
        kind: ClaimKind.equation,
        canonical: 'x=1',
        statement: 'x=1',
        deps: const [ClaimRef(claimId: 'a', version: 5)],
      );
      final key = ClaimKey.of(claim);
      expect(key.canonicalHash, claim.canonicalHash);
      expect(key.depVersions, [('a', 5)]);
    });
  });

  group('ClaimSummary', () {
    Claim claim(String id, ClaimStatus status, {ClaimKind? kind}) => Claim(
          id: id,
          kind: kind ?? ClaimKind.equation,
          canonical: '$id=1',
          statement: '$id 的陈述',
          status: status,
        );

    test('orders admissible claims first and keeps evidence in the prompt', () {
      final summary = ClaimSummary.of([
        claim('proposed', ClaimStatus.proposed),
        claim('refuted', ClaimStatus.refuted),
        claim('verified', ClaimStatus.verified)..evidence = '数值代入成立',
        claim('given', ClaimStatus.given, kind: ClaimKind.given),
      ]);
      expect(summary.claims.first.id, 'verified');
      expect(
        summary.claims.map((claim) => claim.id),
        ['verified', 'given', 'refuted', 'proposed'],
      );
      final text = summary.toPromptText();
      expect(text, contains('[verified/equation]'));
      expect(text, contains('数值代入成立'));
      expect(text, contains('[given/given]'));
      expect(summary.toJson()['total'], 4);
    });

    test('truncates to maxClaims and marks it', () {
      final summary = ClaimSummary.of(
        [for (var i = 0; i < 20; i++) claim('c$i', ClaimStatus.verified)],
        maxClaims: 5,
      );
      expect(summary.claims.length, 5);
      expect(summary.total, 20);
      expect(summary.truncated, isTrue);
    });

    test('empty summary renders a stable placeholder', () {
      expect(const ClaimSummary.empty().toPromptText(), '（没有抽取到 claim）');
      expect(const ClaimSummary.empty().isEmpty, isTrue);
    });
  });
}
