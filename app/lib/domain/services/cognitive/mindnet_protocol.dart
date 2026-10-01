/// The Furnace side of the MindNet integration protocol, frozen in code.
///
/// The contract is **not** the npm version number (MINDNET_CONTRACT §6.6). It is
/// two things:
///
/// * the conformance file's own protocol string and its tolerances;
/// * the exact MindNet commit that file was generated from.
///
/// Those live here as constants so the guard test
/// (`test/domain/services/cognitive/mindnet_protocol_guard_test.dart`) can fail
/// the moment the fixture changes underneath us. A promise in a document can rot
/// silently; a constant plus a test cannot.
///
/// Scope note: this guards the **Furnace copy** of the snapshot. MindNet's own
/// `node tools/conformance.js --check` compares MindNet's implementation against
/// MindNet's conformance file and normalises `generated_from.commit` away
/// (`tools/conformance.js:284`), so it says nothing about our copy. Two
/// different guards for two different jobs.
abstract final class MindNetProtocol {
  /// The protocol string carried by `test/fixtures/mindnet_vectors.json`.
  ///
  /// Measured, not assumed: `j.protocol === "mindnet.conformance/1"`.
  static const String conformanceProtocol = 'mindnet.conformance/1';

  /// `generated_from.commit` of the frozen snapshot.
  ///
  /// The contract document's §8 (written 2026-09-25) names `c624884`, but the
  /// snapshot actually in the repository was generated from this commit - the
  /// two differ, and the file is the authority. §9 records the correction.
  static const String frozenSnapshotCommit =
      'ace605d9778e8641957c570c1e58049ca82e4a01';

  /// `generated_from.package_version` - informational only, never a contract.
  static const String snapshotPackageVersion = '2.0.0-alpha.1';

  /// Relative error tolerated on floats, from the fixture's `tolerances.rel`.
  static const double floatRelTolerance = 1e-12;

  /// Absolute floor for the same comparison, from `tolerances.abs`.
  static const double floatAbsTolerance = 1e-15;

  /// Decimals used for the human-readable comparison (`tolerances.rounded_decimals`).
  static const int roundedDecimals = 6;

  /// Fields that must match exactly - sets and enums, never floats.
  static const List<String> mustBeExact = <String>[
    'admitted',
    'focus',
    'outcompeted',
    'conscious',
    'subconscious',
    'states[].state_after',
    'kind',
  ];

  /// The MindNet clock is hours since the Unix epoch; tierA and tierB both take
  /// it. Kept next to the other frozen facts because getting it wrong is silent
  /// (see `DsrCardState.read`'s doc comment).
  static const String clockUnit = 'hours since the Unix epoch';
}
