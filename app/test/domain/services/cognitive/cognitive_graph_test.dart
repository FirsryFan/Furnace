import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/domain/services/cognitive/cognitive_graph.dart';

/// Tests for the tag-tree -> cognitive-graph projection.
///
/// The projection is the only place where Furnace decides what the model sees,
/// so every rule in `CognitiveGraph.fromTags`'s contract is pinned here: the
/// direction of each edge, the two **[未标定]** weights, the sibling tie-break,
/// and the two "absence is not zero" rules (`ms` unknown, `weight` defaulted).
void main() {
  /// A stored tag row, for the adapter test.
  Tag tagOf(
    String id,
    String name, {
    String? parentId,
    String? path,
  }) =>
      Tag(
        id: id,
        name: name,
        parentId: parentId,
        path: path,
        createdAt: 1,
        updatedAt: 1,
      );

  /// The projection's input value. The projection takes [CognitiveTag] rather
  /// than a drift row, so it stays usable without a database.
  CognitiveTag ctag(
    String id,
    String name, {
    String? parentId,
    String? path,
    String type = 'knowledge',
  }) =>
      CognitiveTag(
        id: id,
        name: name,
        parentId: parentId,
        path: path,
        type: type,
      );

  /// Every edge as `from->to`, in the order the graph holds them. Order is
  /// part of the contract: MindNet accumulates `drive` in edge-array order.
  List<String> shapes(CognitiveGraph graph) =>
      [for (final edge in graph.edges) '${edge.from}->${edge.to}'];

  /// The projection with **no memory strengths supplied**.
  ///
  /// `ms` is a required parameter now (the A2 ruling: a missing `ms` is not
  /// "unknown" inside MindNet, it is MindNet's own 0.8), so every test that is
  /// about edges rather than about memory strengths says "none" explicitly
  /// here. The tests that are about `ms` call `CognitiveGraph.fromTags`
  /// directly instead.
  CognitiveGraph graphOf({
    required List<CognitiveTag> tags,
    Map<String, double> importance = const {},
    Map<String, double> ms = const {},
    double parentChildLs = CognitiveGraph.defaultParentChildLs,
    double siblingLs = CognitiveGraph.defaultSiblingLs,
  }) =>
      CognitiveGraph.fromTags(
        tags: tags,
        ms: ms,
        importance: importance,
        parentChildLs: parentChildLs,
        siblingLs: siblingLs,
      );

  group('shape of the projection', () {
    test('an empty tag tree projects to an empty graph', () {
      final graph = graphOf(tags: const []);
      expect(graph.nodes, isEmpty);
      expect(graph.edges, isEmpty);
      expect(graph.toJson(), {'nodes': [], 'edges': []});
    });

    test('a single tag is one node, no edges, and no invented ms', () {
      final graph = graphOf(
        tags: [ctag('a', '力学', path: '力学')],
      );
      expect(graph.nodes, hasLength(1));
      expect(graph.edges, isEmpty);

      final node = graph.nodes.single;
      expect(node.id, 'a');
      expect(node.name, '力学');
      expect(node.type, 'knowledge');
      expect(node.ms, isNull,
          reason: 'an unknown memory strength must stay unknown');
      expect(node.weight, CognitiveGraph.defaultWeight,
          reason: 'a node with no importance entry defaults to 1.0 - unlike '
              'ms, "no information" for a weight has an honest value');

      final json = graph.toJson();
      final encoded = (json['nodes']! as List).single as Map<String, Object?>;
      expect(encoded.containsKey('ms'), isFalse,
          reason: 'the key is left out entirely: MindNet reads a missing ms as '
              'its own default (src/model.js:50), while 0 would mean "fully '
              'forgotten" and starve every edge leaving this node');
      expect(graph.nodesWithoutMs, ['a'],
          reason: 'the omission is recorded rather than left implicit');
      expect(encoded['weight'], 1.0);
      expect(encoded['type'], 'knowledge');
    });

    test('the emitted JSON is exactly MindNet\'s input shape', () {
      final graph = graphOf(
        tags: [
          ctag('p', '父', path: '父'),
          ctag('c', '子', parentId: 'p', path: '父/子'),
        ],
        ms: {'p': 0.8, 'c': 0.42},
        importance: {'p': 3.0},
      );
      final json = graph.toJson();

      expect(json.keys.toSet(), {'nodes', 'edges'});
      final nodes = (json['nodes']! as List).cast<Map<String, Object?>>();
      final parent = nodes.firstWhere((n) => n['id'] == 'p');
      expect(parent.keys.toSet(), {'id', 'name', 'type', 'ms', 'weight'});
      expect(parent['ms'], 0.8);
      expect(parent['weight'], 3.0);
      final child = nodes.firstWhere((n) => n['id'] == 'c');
      expect(child['weight'], CognitiveGraph.defaultWeight,
          reason: 'no importance entry for this one');
      final edge = (json['edges']! as List).single as Map<String, Object?>;
      expect(edge.keys.toSet(), {'id', 'from', 'to', 'ls'});
      expect(edge['id'], 'pc:p->c');
      expect(edge['from'], 'p');
      expect(edge['to'], 'c');
      expect(edge['ls'], CognitiveGraph.defaultParentChildLs);
    });

    test('a projected graph round-trips through JSON', () {
      final graph = graphOf(
        tags: [
          ctag('p', '父', path: '父'),
          ctag('c', '子', parentId: 'p', path: '父/子'),
        ],
        ms: {'c': 0.5},
      );
      final restored = CognitiveGraph.fromJson(graph.toJson());

      expect(restored.nodes.map((n) => n.id).toList(), ['c', 'p']);
      expect(shapes(restored), shapes(graph));
      expect(restored.nodeById('c')!.ms, 0.5);
      expect(restored.nodeById('p')!.ms, isNull);
    });
  });

  group('parent/child edges', () {
    test('one edge, parent to child, and never the reverse', () {
      final graph = graphOf(
        tags: [
          ctag('p', '父', path: '父'),
          ctag('c', '子', parentId: 'p', path: '父/子'),
        ],
      );
      expect(shapes(graph), ['p->c'],
          reason: 'the model has no automatic reverse edge (contract 6.4): '
              'A -> B is a *cue*, "thinking of A brings B to mind", so the '
              'direction decides who can be reached at all');
      expect(graph.edges.single.id, 'pc:p->c');
      expect(graph.edges.single.ls, CognitiveGraph.defaultParentChildLs);
    });

    test('parent/child and sibling weights are parameters, not constants', () {
      final graph = graphOf(
        tags: [
          ctag('p', '父', path: '父'),
          ctag('c1', '子1', parentId: 'p', path: '父/子1'),
          ctag('c2', '子2', parentId: 'p', path: '父/子2'),
        ],
        parentChildLs: 0.65,
        siblingLs: 0.35,
      );
      for (final edge in graph.edges) {
        expect(edge.ls, edge.id.startsWith('pc:') ? 0.65 : 0.35);
      }
      expect(graph.edges, hasLength(3),
          reason: 'two parent/child edges plus one sibling pair');
    });

    test('a parent id that is not in the list is dropped, not invented', () {
      final graph = graphOf(
        tags: [ctag('c', '子', parentId: 'missing', path: '子')],
      );
      expect(graph.nodes, hasLength(1));
      expect(graph.edges, isEmpty);
      expect(graph.nodeById('c')!.name, '子');
    });

    test('a missing parent link is recovered from the cached path', () {
      // Rows imported before the link existed still carry their full path, and
      // the tree the user sees is the path. The link wins when it is usable;
      // the path is the fallback, not a second opinion.
      final graph = graphOf(
        tags: [
          ctag('p', '父', path: '父'),
          ctag('c', '子', path: '父/子'),
        ],
      );
      expect(shapes(graph), ['p->c']);
    });

    test('an explicit link wins over the path', () {
      final graph = graphOf(
        tags: [
          ctag('p1', '父1', path: '父1'),
          ctag('p2', '父2', path: '父2'),
          ctag('c', '子', parentId: 'p2', path: '父1/子'),
        ],
      );
      final parentEdges =
          graph.edges.where((e) => e.id.startsWith('pc:')).toList();
      expect([for (final e in parentEdges) '${e.from}->${e.to}'], ['p2->c'],
          reason: 'the link is authoritative; the path is only read when the '
              'link is absent or dangling');
    });

    test('a tag that claims itself as its parent gets no self-loop', () {
      final graph = graphOf(
        tags: [ctag('a', '甲', parentId: 'a', path: '甲')],
      );
      expect(graph.edges, isEmpty);
    });
  });

  group('sibling edges', () {
    test('direction follows importance, ties follow the id ascending', () {
      final graph = graphOf(
        tags: [
          ctag('p', '父', path: '父'),
          ctag('s1', '兄', parentId: 'p', path: '父/兄'),
          ctag('s2', '弟', parentId: 'p', path: '父/弟'),
          ctag('s3', '妹', parentId: 'p', path: '父/妹'),
        ],
        importance: {'s1': 0.9, 's2': 0.9, 's3': 0.1},
      );

      expect(shapes(graph), ['p->s1', 'p->s2', 'p->s3', 's1->s2', 's1->s3', 's2->s3'],
          reason: 's1 and s2 are equally important so the id breaks the tie '
              '(s1 -> s2); s3 is the least important so it is only ever the '
              'target');
      for (final edge in graph.edges.where((e) => e.id.startsWith('sib:'))) {
        expect(edge.ls, CognitiveGraph.defaultSiblingLs);
      }
    });

    test('ties resolve by id even when the input order is reversed', () {
      final forward = graphOf(
        tags: [
          ctag('p', '父', path: '父'),
          ctag('a', '甲', parentId: 'p', path: '父/甲'),
          ctag('b', '乙', parentId: 'p', path: '父/乙'),
        ],
      );
      final reversed = graphOf(
        tags: [
          ctag('b', '乙', parentId: 'p', path: '父/乙'),
          ctag('a', '甲', parentId: 'p', path: '父/甲'),
          ctag('p', '父', path: '父'),
        ],
      );
      expect(shapes(forward), ['p->a', 'p->b', 'a->b']);
      expect(shapes(reversed), shapes(forward),
          reason: 'the projection is a function of the tag set, not of the '
              'order a query happened to return');
      expect([for (final n in reversed.nodes) n.id], ['a', 'b', 'p']);
    });

    test('an unlisted sibling outweighs a listed one at the 1.0 default', () {
      final graph = graphOf(
        tags: [
          ctag('p', '父', path: '父'),
          ctag('a', '甲', parentId: 'p', path: '父/甲'),
          ctag('b', '乙', parentId: 'p', path: '父/乙'),
        ],
        importance: {'a': 0.5},
      );
      expect(shapes(graph), ['p->a', 'p->b', 'b->a'],
          reason: 'a tag with no importance entry gets the 1.0 default, so it '
              'outweighs an explicit 0.5 - the default is a value, not "last"');
    });

    test('top-level tags are siblings of each other', () {
      // Same rule DiffusionBoost.distance uses (children of the same parent,
      // including "no parent"), which is the implementation 6.4 points at when
      // it says sibling edges already work in this app's scenario.
      final graph = graphOf(
        tags: [
          ctag('r1', '文化课', path: '文化课'),
          ctag('r2', '竞赛', path: '竞赛'),
        ],
      );
      expect(shapes(graph), ['r1->r2']);
      expect(graph.edges.single.ls, CognitiveGraph.defaultSiblingLs);
    });

    test('a childless, single-child parent contributes no sibling pair', () {
      final graph = graphOf(
        tags: [
          ctag('p', '父', path: '父'),
          ctag('c', '独子', parentId: 'p', path: '父/独子'),
        ],
      );
      expect(graph.edges.where((e) => e.id.startsWith('sib:')), isEmpty);
    });

    test('parent/child edges come first, then the sibling groups', () {
      final graph = graphOf(
        tags: [
          ctag('p2', '父2', path: '父2'),
          ctag('p1', '父1', path: '父1'),
          ctag('x2', 'X2', parentId: 'p2', path: '父2/X2'),
          ctag('x1', 'X1', parentId: 'p2', path: '父2/X1'),
          ctag('y', 'Y', parentId: 'p1', path: '父1/Y'),
        ],
      );
      // Node order is by id (p1, p2, x1, x2, y), so the sibling groups appear in
      // the order their parent was first seen: roots (p1, p2), then p2's
      // children, then p1's. Every part of that is derived, never declared.
      expect(shapes(graph), [
        'p2->x1',
        'p2->x2',
        'p1->y',
        'p1->p2',
        'x1->x2',
      ]);
    });
  });

  group('ms and weight are two different things', () {
    test('a supplied ms is carried through, including a legal zero', () {
      final graph = graphOf(
        tags: [
          ctag('a', '甲', path: '甲'),
          ctag('b', '乙', path: '乙'),
        ],
        ms: {'a': 0.0, 'b': 0.42},
      );
      expect(graph.nodeById('a')!.ms, 0.0,
          reason: 'an explicit 0.0 is a legal memory strength meaning "fully '
              'forgotten", so it is written; only a *missing* ms is omitted');
      expect(graph.nodeById('b')!.ms, 0.42);
    });

    test('an illegal ms is dropped instead of poisoning the drive sum', () {
      // src/io/run.js rejects ms outside [0, 1] or non-finite; carrying such a
      // value into the graph would corrupt every contribution that reads it.
      final graph = graphOf(
        tags: [
          ctag('hi', '高', path: '高'),
          ctag('neg', '负', path: '负'),
          ctag('nan', '非数', path: '非数'),
        ],
        ms: {'hi': 1.5, 'neg': -0.1, 'nan': double.nan},
      );
      for (final node in graph.nodes) {
        expect(node.ms, isNull);
      }
    });

    test('importance becomes the node weight, never the memory strength', () {
      final graph = graphOf(
        tags: [ctag('a', '甲', path: '甲')],
        importance: {'a': 4.2},
        ms: {'a': 0.3},
      );
      expect(graph.nodeById('a')!.weight, 4.2);
      expect(graph.nodeById('a')!.ms, 0.3);
    });

    test('a tag with no ms entry is marked, never given MindNet\'s 0.8', () {
      // The A2 defect this pins: MindNet turns a missing `ms` into 0.8
      // (src/model.js:50) and the memory layer reads it as the encoding ceiling
      // (mechanisms/memory.dsr.js:90). If the projection let that happen
      // silently, one card would have R0 = 0.8 here and R0 = 1.0 on the review
      // flow's side (D2). So the projection says "nobody provided one" instead.
      final graph = CognitiveGraph.fromTags(
        tags: [
          ctag('a', '甲', path: '甲'),
          ctag('b', '乙', path: '乙'),
        ],
        ms: const {'b': 0.55},
        importance: const {},
      );

      expect(graph.nodeById('a')!.ms, isNull,
          reason: 'absent is absent: not 0.0, not MindNet\'s 0.8');
      expect(graph.nodesWithoutMs, ['a'],
          reason: 'and the gap is recorded where a caller can see it');
      final emitted = (graph.toJson()['nodes']! as List)
          .cast<Map<String, Object?>>()
          .firstWhere((node) => node['id'] == 'a');
      expect(emitted.containsKey('ms'), isFalse);
      expect(emitted['weight'], CognitiveGraph.defaultWeight);

      expect(CognitiveGraph.mindNetDefaultMs, 0.8,
          reason: 'the fallback is named so the two decisions are not the same '
              'decision');
    });

    test('an explicit fallback is distinguishable from "not provided"', () {
      final silent = CognitiveGraph.fromTags(
        tags: [ctag('a', '甲', path: '甲')],
        ms: const {},
        importance: const {},
      );
      final explicit = CognitiveGraph.fromTags(
        tags: [ctag('a', '甲', path: '甲')],
        ms: const {'a': CognitiveGraph.mindNetDefaultMs},
        importance: const {},
      );

      expect(silent.nodeById('a')!.ms, isNull);
      expect(silent.nodesWithoutMs, ['a']);
      expect(explicit.nodeById('a')!.ms, 0.8);
      expect(explicit.nodesWithoutMs, isEmpty,
          reason: 'same number on MindNet\'s side, different fact on ours - '
              'which is exactly why the caller has to choose');
      expect(
        (explicit.toJson()['nodes']! as List).single,
        containsPair('ms', 0.8),
      );
    });

    test('a graph with every node stated has no gaps to report', () {
      final graph = CognitiveGraph.fromTags(
        tags: [
          ctag('a', '甲', path: '甲'),
          ctag('b', '乙', path: '乙'),
        ],
        ms: const {'a': 1.0, 'b': 0.0},
        importance: const {},
      );
      expect(graph.nodesWithoutMs, isEmpty,
          reason: 'a legal stored 0.0 is data, not a gap');
    });
  });

  group('adapting a stored row', () {
    test('CognitiveTag carries the link and the cached path', () {
      final stored = tagOf('c', '子', parentId: 'p', path: '父/子');
      final input = CognitiveTag.fromTag(stored);
      expect(input.id, 'c');
      expect(input.name, '子');
      expect(input.parentId, 'p');
      expect(input.path, '父/子');
      expect(input.type, 'knowledge');

      final graph = graphOf(tags: [input]);
      expect(graph.nodes.single.type, 'knowledge');
    });

    test('the node type is carried through when it is set', () {
      final graph = graphOf(
        tags: [
          const CognitiveTag(id: 'a', name: '方法', type: 'technique'),
        ],
      );
      expect(graph.nodes.single.type, 'technique');
      expect(graph.toJson()['nodes'], [
        {'id': 'a', 'name': '方法', 'type': 'technique', 'weight': 1.0},
      ]);
    });
  });
}
