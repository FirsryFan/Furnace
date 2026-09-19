import 'package:flutter_test/flutter_test.dart';
import 'package:knowflow/domain/services/cloze/diffusion_boost.dart';

void main() {
  // Tree:
  //   root
  //    |- a        (sibling of b)
  //    |- b
  //        |- b1   (child of b, sibling of b2)
  //        |- b2
  //            |- b2x  (grandchild)
  //    |- c        (distance 2 from b: b->root->c)
  final nodes = [
    const MindNodeInfo(id: 'root', parentId: null),
    const MindNodeInfo(id: 'a', parentId: 'root'),
    const MindNodeInfo(id: 'b', parentId: 'root'),
    const MindNodeInfo(id: 'b1', parentId: 'b'),
    const MindNodeInfo(id: 'b2', parentId: 'b'),
    const MindNodeInfo(id: 'b2x', parentId: 'b2'),
    const MindNodeInfo(id: 'c', parentId: 'root'),
  ];

  group('graph distance (parent-child and sibling edges)', () {
    test('same node is distance 0', () {
      expect(DiffusionBoost.distance(nodes, 'b', 'b'), 0);
    });

    test('parent-child is distance 1', () {
      expect(DiffusionBoost.distance(nodes, 'b', 'b1'), 1);
    });

    test('siblings are distance 1 (direct 兄弟)', () {
      expect(DiffusionBoost.distance(nodes, 'a', 'b'), 1);
      expect(DiffusionBoost.distance(nodes, 'b1', 'b2'), 1);
    });

    test('two hops counts as distance 2', () {
      expect(DiffusionBoost.distance(nodes, 'b1', 'b2x'), 2); // b1-b2-b2x
      expect(DiffusionBoost.distance(nodes, 'b1', 'c'), 2); // b1-b-c
    });
  });

  group('boost factors (spec 1.3.3)', () {
    test('distance 1 card gets x1.8', () {
      expect(
        DiffusionBoost.boostFactor(
            nodes: nodes, wrongNodeIds: const ['b'], candidateNodeId: 'b1'),
        1.8,
      );
      expect(
        DiffusionBoost.boostFactor(
            nodes: nodes, wrongNodeIds: const ['b'], candidateNodeId: 'a'),
        1.8,
      );
      // c shares the root with b: sibling edge -> distance 1.
      expect(
        DiffusionBoost.boostFactor(
            nodes: nodes, wrongNodeIds: const ['b'], candidateNodeId: 'c'),
        1.8,
      );
    });

    test('distance 2 card gets x1.3', () {
      expect(
        DiffusionBoost.boostFactor(
            nodes: nodes, wrongNodeIds: const ['b'], candidateNodeId: 'b2x'),
        1.3,
      );
      expect(
        DiffusionBoost.boostFactor(
            nodes: nodes, wrongNodeIds: const ['b1'], candidateNodeId: 'b2x'),
        1.3, // b1-b2-b2x
      );
    });

    test('distance 3+ or disconnected yields no boost (1.0)', () {
      final far = MindNodeInfo(id: 'far', parentId: 'b2x');
      final withFar = [...nodes, far];
      expect(
        DiffusionBoost.boostFactor(
            nodes: withFar,
            wrongNodeIds: const ['a'],
            candidateNodeId: 'far'),
        1.0,
      );
      expect(
        DiffusionBoost.boostFactor(
            nodes: nodes,
            wrongNodeIds: const ['a'],
            candidateNodeId: 'b2x'),
        1.0,
      );
    });

    test('closest source wins when several nodes are wrong', () {
      // b1 -> b2x = distance 2 (1.3); a -> b2x = 4 hops (no boost).
      expect(
        DiffusionBoost.boostFactor(
            nodes: nodes,
            wrongNodeIds: const ['b1', 'a'],
            candidateNodeId: 'b2x'),
        1.3,
      );
    });
  });
}
