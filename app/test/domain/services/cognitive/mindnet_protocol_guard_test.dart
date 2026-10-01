// Guards the Furnace copy of the MindNet conformance snapshot.
//
// If MindNet regenerates `conformance/mindnet_vectors.json` and somebody copies
// it in, this test fails and prints both sides - so "we pinned a snapshot" stops
// being a promise and becomes a check.
//
// Deliberately *not* covered here: whether MindNet's implementation still
// matches MindNet's own file. That is what `node tools/conformance.js --check`
// does, and it normalises the commit away, so it cannot see our copy drift.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/cognitive/mindnet_protocol.dart';

const _fixturePath = 'test/fixtures/mindnet_vectors.json';

void main() {
  test('the fixture exists and is the file this protocol was written against',
      () {
    final file = File(_fixturePath);
    expect(file.existsSync(), isTrue,
        reason: 'missing $_fixturePath: the conformance snapshot is part of the '
            'repository, not a build artefact');
  });

  group('frozen snapshot', () {
    late Map<String, Object?> fixture;

    setUpAll(() {
      fixture = jsonDecode(File(_fixturePath).readAsStringSync())
          as Map<String, Object?>;
    });

    test('protocol string matches', () {
      expect(
        fixture['protocol'],
        MindNetProtocol.conformanceProtocol,
        reason: 'protocol drift: fixture says ${fixture['protocol']}, '
            'MindNetProtocol says ${MindNetProtocol.conformanceProtocol}',
      );
    });

    test('generated_from.commit matches the pinned commit', () {
      final generated = fixture['generated_from'] as Map<String, Object?>;
      expect(
        generated['commit'],
        MindNetProtocol.frozenSnapshotCommit,
        reason: 'snapshot drift: fixture was generated from '
            '${generated['commit']}, MindNetProtocol pins '
            '${MindNetProtocol.frozenSnapshotCommit}. Re-run the tierA/tierB '
            'conformance tests before updating the constant.',
      );
      // `package_version` is deliberately NOT asserted here (reviewer finding,
      // accepted as low): the contract is the protocol string plus this commit
      // (§6.6), and MindNet's own `--check` normalises only the commit. Pinning
      // the npm version would turn a cosmetic `alpha.1 -> alpha.2` bump into a
      // red guard that no party treats as a contract. The constant stays for
      // forensics.
    });

    test('tolerances match, and the exact-comparison list is unchanged', () {
      final tolerances = fixture['tolerances'] as Map<String, Object?>;
      expect((tolerances['rel'] as num).toDouble(),
          MindNetProtocol.floatRelTolerance);
      expect((tolerances['abs'] as num).toDouble(),
          MindNetProtocol.floatAbsTolerance);
      expect(tolerances['rounded_decimals'], MindNetProtocol.roundedDecimals);
      expect(
        (tolerances['must_be_exact'] as List).cast<String>(),
        MindNetProtocol.mustBeExact,
        reason: 'a field moving in or out of the "exact" set changes what the '
            'conformance tests are allowed to forgive',
      );
    });

    test('both tiers are present with the ids the tests refer to', () {
      final tierA = (fixture['tierA'] as List).cast<Map<String, Object?>>();
      final tierB = (fixture['tierB'] as List).cast<Map<String, Object?>>();
      expect(tierA, isNotEmpty);
      expect(tierB, isNotEmpty);
      expect(tierA.first['id'], 'A01-constants');
      expect(tierB.first['id'], 'B01-fast-layer-chain-5-rounds');
    });
  });
}
