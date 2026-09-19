/// DiffusionBoost - Mindnet graph-diffusion boost (spec 1.3.3 / GAP D12).
///
/// When a card is answered wrong, the knowledge points whose Mindnet nodes
/// sit within graph distance <= 2 of the wrong card's nodes get a draw
/// weight boost (x1.8 at distance 1, x1.3 at distance 2) that decays after
/// 3 draw cycles (handled by BoostEntries in the repository layer).
///
/// Graph edges: parent-child and sibling-sibling ("direct parent/child or
/// sibling" = distance 1).
library;

class MindNodeInfo {
  const MindNodeInfo({required this.id, this.parentId});

  final String id;
  final String? parentId;
}

abstract final class DiffusionBoost {
  /// Graph distance between [a] and [b], or null when disconnected.
  ///
  /// [nodes] may be a subtree fragment of one map; connectivity is derived
  /// from parent links plus sibling links within the same parent.
  static int? distance(
      List<MindNodeInfo> nodes, String a, String b) {
    if (a == b) {
      return 0;
    }
    final byId = {for (final n in nodes) n.id: n};
    final parentOf = {for (final n in nodes) n.id: n.parentId};
    final childrenOf = <String?, List<String>>{};
    for (final n in nodes) {
      childrenOf.putIfAbsent(n.parentId, () => []).add(n.id);
    }
    final siblingsOf = <String, List<String>>{};
    for (final entry in childrenOf.entries) {
      for (final id in entry.value) {
        siblingsOf[id] = [for (final other in entry.value) if (other != id) other];
      }
    }

    // BFS over undirected edges: parent <-> child, sibling <-> sibling.
    final queue = <String>[a];
    final dist = <String, int>{a: 0};
    while (queue.isNotEmpty) {
      final current = queue.removeAt(0);
      final next = <String>{
        if (parentOf[current] != null) parentOf[current]!,
        for (final c in childrenOf[current] ?? const <String>[]) c,
        ...?siblingsOf[current],
      };
      for (final neighbor in next) {
        if (!byId.containsKey(neighbor) || dist.containsKey(neighbor)) {
          continue;
        }
        final d = dist[current]! + 1;
        dist[neighbor] = d;
        if (neighbor == b) {
          return d;
        }
        queue.add(neighbor);
      }
    }
    return null;
  }

  /// Boost factor for [candidateId] given the (possibly multiple) nodes of
  /// the card that was answered wrong. Returns 1.0 (no boost) when the
  /// distance is > 2 or the candidate is disconnected.
  static double boostFactor({
    required List<MindNodeInfo> nodes,
    required List<String> wrongNodeIds,
    required String candidateNodeId,
  }) {
    var best = 1.0;
    for (final source in wrongNodeIds) {
      final d = distance(nodes, source, candidateNodeId);
      if (d == null) {
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
}
