/// TagDiffusion - the graph-diffusion boost, rebuilt on the TAG TREE.
///
/// Background: the original design (spec 1.3.3 / GAP D12) diffused over the
/// Mindnet node graph. The user merged Mindnet into the tag system
/// (blueprint 2.8, annotation 9), so the graph IS the tag tree now: a tag's
/// parent is its path minus the last segment, and distance keeps the same
/// meaning the spec gave it:
///   distance 1 = parent/child or siblings ("直接父子/兄弟")
///   distance 2 = grandparent/grandchild or cousins
/// Boost factors are unchanged: x1.8 at distance 1, x1.3 at distance 2.
///
/// This keeps the promised behaviour while removing the dependency on a node
/// graph that no longer exists as a user-facing concept.
library;

import 'package:meta/meta.dart';

/// A tag node in the tree, identified by its full path.
@immutable
class TagNodeInfo {
  const TagNodeInfo({required this.path});

  /// Full path, e.g. `文化课/数学/函数`.
  final String path;

  String? get parent {
    final index = path.lastIndexOf('/');
    return index < 0 ? null : path.substring(0, index);
  }

  String get leaf {
    final index = path.lastIndexOf('/');
    return index < 0 ? path : path.substring(index + 1);
  }

  List<String> get segments =>
      path.split('/').where((s) => s.isNotEmpty).toList();
}

abstract final class TagDiffusion {
  /// Graph distance between two tag paths in the tree, where edges are
  /// parent-child AND sibling-sibling (same semantics as the Mindnet graph
  /// the spec described). Returns null when the two are unrelated.
  static int? distance(String a, String b) {
    if (a == b) {
      return 0;
    }
    final segsA = _segments(a);
    final segsB = _segments(b);
    if (segsA.isEmpty || segsB.isEmpty) {
      return null;
    }
    // Shared ancestor depth.
    var shared = 0;
    final limit = segsA.length < segsB.length ? segsA.length : segsB.length;
    while (shared < limit && segsA[shared] == segsB[shared]) {
      shared++;
    }
    if (shared == 0) {
      // Different roots: unrelated.
      return null;
    }
    final upA = segsA.length - shared; // steps up from a to the common node
    final downB = segsB.length - shared; // steps down to b
    if (upA >= 1 && downB >= 1 && upA + downB == 2) {
      // a and b are distinct children of the same node -> siblings.
      return 1;
    }
    return upA + downB;
  }

  /// Boost factor for [candidatePath] when [wrongPaths] were answered wrong
  /// at graph distance <= 2. Returns 1.0 when nothing applies.
  static double boostFactor({
    required List<String> wrongPaths,
    required String candidatePath,
  }) {
    var best = 1.0;
    for (final wrong in wrongPaths) {
      final d = distance(wrong, candidatePath);
      if (d == null || d == 0) {
        continue;
      }
      if (d == 1) {
        return 1.8;
      }
      if (d == 2 && best < 1.3) {
        best = 1.3;
      }
    }
    return best;
  }

  /// The distance used for the ledger line (1 or 2), or null.
  static int? ledgerDistance({
    required List<String> wrongPaths,
    required String candidatePath,
  }) {
    int? best;
    for (final wrong in wrongPaths) {
      final d = distance(wrong, candidatePath);
      if (d == null || d == 0) {
        continue;
      }
      if (d <= 2 && (best == null || d < best)) {
        best = d;
      }
    }
    return best;
  }

  static List<String> _segments(String path) =>
      path.split('/').where((s) => s.isNotEmpty).toList();
}
