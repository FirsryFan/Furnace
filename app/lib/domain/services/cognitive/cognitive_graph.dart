/// Projects Furnace's tag tree onto MindNet's cognitive graph.
///
/// The mapping is the one agreed in `docs/MINDNET_CONTRACT.md` §6.4 and
/// adopted in §8.2 item 3:
///
/// * **a tag is a node** - `name` is the tag name, `type` stays `knowledge`
///   (the contract says the other types only change the procedural-gain
///   exponent, and `knowledge` is fine to start with);
/// * **an edge is a *cue*, not containment** - `A -> B` means "thinking of A
///   brings B to mind" (strictly directed; the contract notes there is no
///   automatic reverse, only an explicit edge). That is why a parent/child
///   pair is projected **one way only**, and why the sibling rule has to pick
///   a direction at all: one of the two has to be the one you are likely to be
///   thinking of;
/// * **parents point at children** (`parent -> child`), and **siblings point
///   from the more important one to the less important one**, with a
///   deterministic tie-break (see [CognitiveGraph.fromTags]).
///
/// ## Why the direction is a real decision, not a detail
///
/// The fast layer's drive is `sum over in-edges of al * ms * ls`
/// (§6.4): only *incoming* edges light a node up. So the direction of an edge
/// is exactly "which of these two do I expect the student to be thinking
/// about" - reversing a pair silently changes which one can be reached at all.
///
/// ## Two parameters that are [未标定 / NOT CALIBRATED]
///
/// The contract is blunt about this (§6.4): there is **no calibration source**
/// for edge weights. [CognitiveGraph.defaultParentChildLs] and
/// [CognitiveGraph.defaultSiblingLs] sit inside the ranges the contract
/// suggests (parent/child `0.6-0.8`, siblings `0.3-0.5`) and nothing more.
/// They are constructor parameters rather than constants sprinkled through
/// call sites, per §6.6/§8.2 item 7 - but no amount of plumbing makes them
/// measured. Two further facts belong next to that warning:
///
/// * `ls` does **not** learn: MindNet's feedback only moves `S` / `D` (§6.4);
/// * `weight` (a node's importance) is *not* memory strength, and `ms` *is*
///   - mixing the two up is the easy mistake here (§6.4).
///
/// ## `ms` is required, because MindNet silently defaults it
///
/// A node's `ms` is not an optional decoration. MindNet's `Node` constructor
/// turns a *missing* `ms` into `0.8` (`src/model.js:50`), and the memory layer
/// then reads that number as the item's encoding ceiling the first time it
/// builds state for the node (`mechanisms/memory.dsr.js:90`:
/// `R0 = min(1, node.ms)`, also falling back to `0.8`). To MindNet, "the caller
/// forgot to pass one" and "the caller meant 0.8" are therefore the same input
/// - and that silently contradicts the review flow's own reading, where a row
/// with a known stability and a NULL `encoding_strength` is `R0 = 1.0`
/// (D2; `dsr_card_state.dart:67`). One card, two encoding ceilings.
///
/// So the projection **requires the map** ([CognitiveGraph.fromTags]'s `ms`
/// parameter) and requires every [CognitiveNode] to state its `ms`: forgetting
/// it does not compile. A tag with no entry is honestly "no memory state was
/// provided" - the node says so ([CognitiveNode.ms] is null and the JSON key is
/// left out), and [CognitiveGraph.nodesWithoutMs] names every such node. A
/// caller that actually wants MindNet's fallback has to ask for it, with
/// [CognitiveGraph.mindNetDefaultMs].
///
/// What the value should be: the **encoding ceiling `R0`**, i.e.
/// `CognitiveModel.modelReadingOf(row).r0`. MindNet reads `ms` as `R0` when it
/// builds its own state, and its state export writes `ms: bag.R0` back out
/// (`src/io/run.js:387`), so the ceiling is the number both sides already
/// agree on. Once the fast layer runs it rewrites `node.ms` with the current
/// retrievability on every sync (`mechanisms/memory.dsr.js:113`) - that is the
/// engine's business, not something to pre-compute here.
///
/// ## Determinism
///
/// The same tags always produce byte-identical output: nodes are sorted by id,
/// edges come out parent/child first then siblings, each group sorted by id.
/// That matters because MindNet accumulates `drive` **in edge-array order**
/// (a different order is only ~1e-16 apart, but "only 1e-16" is not good
/// enough for a per-round conformance diff - see §6.2).
///
/// This file is deliberately free of clocks, repositories and Flutter: the
/// projection is a pure function of plain values, so it can be reused and
/// tested without a database. The single import from the data layer is the
/// `Tag` row type behind [CognitiveTag.fromTag], which exists so a caller can
/// hand a query result straight in instead of re-deriving the mapping.
library;

import '../../../data/database/database.dart';

/// One tag-tree row, reduced to what the projection needs.
///
/// A subset of the `Tags` table rather than the table itself, so the projection
/// can be called with plain values in tests and does not need a repository.
/// [CognitiveTag.fromTag] converts a real row.
class CognitiveTag {
  const CognitiveTag({
    required this.id,
    required this.name,
    this.parentId,
    this.path,
    this.type = 'knowledge',
  });

  /// Builds the projection input from a stored tag row.
  ///
  /// Both the tree link ([Tag.parentId]) and the cached full path
  /// ([Tag.path]) are carried over: the link is authoritative, the path is the
  /// fallback used when a row's link is missing or dangling (see
  /// [CognitiveGraph.fromTags]).
  factory CognitiveTag.fromTag(Tag row) => CognitiveTag(
        id: row.id,
        name: row.name,
        parentId: row.parentId,
        path: row.path,
      );

  final String id;
  final String name;

  /// Parent tag id, or null for a top-level tag.
  final String? parentId;

  /// Cached full path (`文化课/学科/语文`), used only as a fallback for
  /// [parentId].
  final String? path;

  /// MindNet node type: `knowledge` / `logic` / `technique` (§6.4). A tag is
  /// knowledge unless the caller knows better.
  final String type;
}

/// One node of the projected graph, in MindNet's input shape.
class CognitiveNode {
  const CognitiveNode({
    required this.id,
    required this.name,
    this.type = 'knowledge',
    required this.ms,
    this.weight,
  });

  final String id;
  final String name;
  final String type;

  /// MindNet's node memory strength `ms` - **required on purpose**.
  ///
  /// MindNet turns a *missing* `ms` into `0.8` (`src/model.js:50`) and the
  /// memory layer then reads that as the encoding ceiling
  /// (`mechanisms/memory.dsr.js:90`), so omitting the value is not "unknown"
  /// over there: it is a claim of `0.8`, which would disagree with the review
  /// flow's own reading of the same card (D2: known stability plus NULL
  /// `encoding_strength` is `R0 = 1.0`). So the caller states it - the card's
  /// ceiling, or an explicit `null` meaning "no memory state provided" (those
  /// nodes are listed by [CognitiveGraph.nodesWithoutMs]). Pass
  /// [CognitiveGraph.mindNetDefaultMs] only if MindNet's fallback is really
  /// what you mean.
  ///
  /// A legal value is finite and inside `[0, 1]` - exactly what MindNet
  /// validates (`src/io/run.js`). A stored `0.0` is legal and is **data**
  /// ("fully forgotten"), unlike a missing key. Anything else is dropped to
  /// `null` here rather than forwarded to poison the drive sums.
  ///
  /// **Never rely on MindNet's default here: pass `ms` explicitly.** A node
  /// without the key is read as [CognitiveGraph.mindNetDefaultMs] by MindNet
  /// (`src/model.js:50`), which is not a number this side measured and would
  /// put the same card at a different encoding ceiling than the review flow
  /// sees (D2).
  final double? ms;

  /// Importance / influence, used by MindNet's KC impact and by the sibling
  /// edge direction. **Not** memory strength (§6.4). `null` means "not
  /// supplied"; [CognitiveGraph.fromTags] fills 1.0 rather than leaving a hole.
  final double? weight;

  /// MindNet's node shape.
  ///
  /// `ms` is written only when it is known, because MindNet's input format has
  /// no way to say "null": an omitted key means MindNet substitutes
  /// [CognitiveGraph.mindNetDefaultMs] (`src/model.js:50`). That substitution is
  /// invisible from here, which is why [CognitiveGraph.nodesWithoutMs] exists -
  /// it is the record of what the projection did not say.
  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'type': type,
        if (ms != null) 'ms': ms,
        if (weight != null) 'weight': weight,
      };

  static CognitiveNode fromJson(Map<String, Object?> json) => CognitiveNode(
        id: json['id']! as String,
        name: (json['name'] as String?) ?? json['id']! as String,
        type: (json['type'] as String?) ?? 'knowledge',
        ms: (json['ms'] as num?)?.toDouble(),
        weight: (json['weight'] as num?)?.toDouble(),
      );
}

/// One directed cue: "thinking of [from] brings [to] to mind" with strength
/// [ls].
class CognitiveEdge {
  const CognitiveEdge({
    required this.id,
    required this.from,
    required this.to,
    required this.ls,
  });

  /// Stable, derived from the endpoints - MindNet only needs an identifier,
  /// and a derived one keeps a re-projection diffable.
  final String id;
  final String from;
  final String to;

  /// Link strength, **[未标定 / NOT CALIBRATED]** - see the library doc.
  final double ls;

  Map<String, Object?> toJson() => {
        'id': id,
        'from': from,
        'to': to,
        'ls': ls,
      };

  static CognitiveEdge fromJson(Map<String, Object?> json) => CognitiveEdge(
        id: json['id']! as String,
        from: json['from']! as String,
        to: json['to']! as String,
        ls: (json['ls'] as num?)?.toDouble() ?? 0,
      );
}

/// The projected graph: exactly MindNet's input `{nodes, edges}`.
class CognitiveGraph {
  const CognitiveGraph({this.nodes = const [], this.edges = const []});

  final List<CognitiveNode> nodes;
  final List<CognitiveEdge> edges;

  /// `ls` for a parent -> child cue. **[未标定 / NOT CALIBRATED]**: the contract
  /// suggests 0.6-0.8 and states there is no source to calibrate from (§6.4).
  static const double defaultParentChildLs = 0.7;

  /// `ls` for a sibling cue. **[未标定 / NOT CALIBRATED]**: the contract
  /// suggests 0.3-0.5 and states there is no source to calibrate from (§6.4).
  static const double defaultSiblingLs = 0.4;

  /// Weight given to a tag with no entry in the importance map. MindNet's
  /// default node weight is 1 (`src/model.js`, `example/graph.json`), and 1.0
  /// is also what "no information" should mean for a *weight* - unlike `ms`,
  /// where the honest answer is to say nothing at all.
  static const double defaultWeight = 1.0;

  /// What MindNet itself substitutes for a node with no `ms`
  /// (`src/model.js:50`), which the memory layer then reads as the encoding
  /// ceiling (`mechanisms/memory.dsr.js:90`).
  ///
  /// It is a named constant rather than an implicit default: the projection
  /// never applies it on its own, because the same card is `R0 = 1.0` on the
  /// review flow's side (D2). A caller that genuinely wants MindNet's fallback
  /// passes this value explicitly, which keeps "we chose 0.8" distinguishable
  /// from "nobody told us".
  static const double mindNetDefaultMs = 0.8;

  /// The ids of nodes whose `ms` nobody provided, in node order.
  ///
  /// These are the nodes MindNet will quietly read as
  /// [mindNetDefaultMs] - the one place that gap is visible from this side.
  /// An empty list means every node states a memory strength.
  List<String> get nodesWithoutMs => [
        for (final node in nodes)
          if (node.ms == null) node.id,
      ];

  /// Projects a tag tree into a cognitive graph.
  ///
  /// Rules, in full:
  ///
  /// 1. Every tag becomes a node; nodes are sorted by id.
  /// 2. **Parent -> child** edge, `ls = parentChildLs` (default
  ///    [defaultParentChildLs], [未标定]).
  /// 3. A tag's parent is its `parentId` when that id is present in [tags];
  ///    otherwise it is derived from `path` (the sibling of the tag whose
  ///    `path` is this one's path minus its last segment); otherwise the tag
  ///    is treated as top level. Links to ids that are not in [tags] are
  ///    dropped rather than invented, and a self-link is ignored.
  /// 4. **Sibling edges**: every pair of tags sharing the same effective
  ///    parent (including "no parent" - top-level tags are siblings of each
  ///    other, which is the same rule `DiffusionBoost.distance` uses and the
  ///    reason §6.4 points at it). One directed edge per pair, from the higher
  ///    importance to the lower, ties broken by id ascending so the result
  ///    never depends on input order. `ls = siblingLs` (default
  ///    [defaultSiblingLs], [未标定]).
  /// 5. [weight] comes from [importance]; a tag missing there gets
  ///    [defaultWeight].
  /// 6. [ms] is the encoding ceiling per tag id (see the library doc: the value
  ///    should come from `CognitiveModel.modelReadingOf(row).r0`). The map is
  ///    **required** so that leaving it out cannot compile, and a tag with no
  ///    entry gets `ms == null` - "no memory state provided", which is a
  ///    different fact from a legal `0.0` and a different fact from an explicit
  ///    [mindNetDefaultMs]. Such nodes are listed by [nodesWithoutMs]. A value
  ///    that is not a legal memory strength (finite, within `[0, 1]`, the range
  ///    MindNet validates in `src/io/run.js`) is likewise left as `null` rather
  ///    than forwarded.
  ///
  ///    **Callers must supply `ms` explicitly and must not rely on MindNet's
  ///    default.** When a node carries no `ms` key, MindNet silently uses
  ///    [mindNetDefaultMs] (`src/model.js:50`) - a number this side never
  ///    measured, and one that would contradict the review flow's own reading
  ///    of the same card (D2). The "not provided" state is deliberately
  ///    observable from here: the key is absent from [toJson] and the id is in
  ///    [nodesWithoutMs].
  ///
  /// A caveat worth knowing before projecting a very flat tree: rule 4 is
  /// quadratic in a sibling group, and §6.4's fan-out dilution (`fan_k`) is
  /// **off by default**, so one parent with hundreds of children would produce
  /// a large, undiluted clique. Split such a parent, or pass it through the
  /// contract's `fan_k` when tierB grows that knob.
  static CognitiveGraph fromTags({
    required List<CognitiveTag> tags,
    required Map<String, double> ms,
    Map<String, double> importance = const {},
    double parentChildLs = defaultParentChildLs,
    double siblingLs = defaultSiblingLs,
  }) {
    // Duplicate ids cannot happen in a database-backed tag list; if they do,
    // the first one wins so the projection stays a function of its input.
    final byId = <String, CognitiveTag>{};
    for (final tag in tags) {
      byId.putIfAbsent(tag.id, () => tag);
    }
    final byPath = <String, CognitiveTag>{};
    for (final tag in byId.values) {
      final path = tag.path;
      if (path != null && path.isNotEmpty) {
        byPath.putIfAbsent(path, () => tag);
      }
    }

    String? effectiveParent(CognitiveTag tag) {
      final explicit = tag.parentId;
      if (explicit != null &&
          explicit.isNotEmpty &&
          explicit != tag.id &&
          byId.containsKey(explicit)) {
        return explicit;
      }
      final path = tag.path;
      if (path == null) {
        return null;
      }
      final cut = path.lastIndexOf('/');
      if (cut <= 0) {
        return null;
      }
      final parent = byPath[path.substring(0, cut)];
      if (parent == null || parent.id == tag.id) {
        return null;
      }
      return parent.id;
    }

    final ordered = byId.values.toList()..sort((a, b) => a.id.compareTo(b.id));
    final nodes = <CognitiveNode>[
      for (final tag in ordered)
        CognitiveNode(
          id: tag.id,
          name: tag.name,
          type: tag.type,
          ms: _legalMs(ms[tag.id]),
          weight: importance[tag.id] ?? defaultWeight,
        ),
    ];

    final parentEdges = <CognitiveEdge>[];
    // Insertion order follows the id-sorted node order, so the sibling groups
    // and the pairs inside them are deterministic too.
    final childrenOf = <String?, List<CognitiveTag>>{};
    for (final tag in ordered) {
      final parent = effectiveParent(tag);
      childrenOf.putIfAbsent(parent, () => <CognitiveTag>[]).add(tag);
      if (parent != null) {
        parentEdges.add(CognitiveEdge(
          id: 'pc:$parent->${tag.id}',
          from: parent,
          to: tag.id,
          ls: parentChildLs,
        ));
      }
    }

    final siblingEdges = <CognitiveEdge>[];
    for (final siblings in childrenOf.values) {
      if (siblings.length < 2) {
        continue;
      }
      // Higher importance first; equal importance keeps the id-sorted order
      // from above, which is the documented tie-break.
      final ranked = [...siblings]..sort((a, b) {
          final wa = importance[a.id] ?? defaultWeight;
          final wb = importance[b.id] ?? defaultWeight;
          final byWeight = wb.compareTo(wa);
          return byWeight != 0 ? byWeight : a.id.compareTo(b.id);
        });
      for (var i = 0; i < ranked.length; i++) {
        for (var j = i + 1; j < ranked.length; j++) {
          siblingEdges.add(CognitiveEdge(
            id: 'sib:${ranked[i].id}->${ranked[j].id}',
            from: ranked[i].id,
            to: ranked[j].id,
            ls: siblingLs,
          ));
        }
      }
    }

    return CognitiveGraph(
      nodes: nodes,
      edges: [...parentEdges, ...siblingEdges],
    );
  }

  /// MindNet's graph input format: `{ "nodes": [...], "edges": [...] }`.
  Map<String, Object?> toJson() => {
        'nodes': [for (final node in nodes) node.toJson()],
        'edges': [for (final edge in edges) edge.toJson()],
      };

  static CognitiveGraph fromJson(Map<String, Object?> json) => CognitiveGraph(
        nodes: [
          for (final node in (json['nodes'] as List?) ?? const [])
            if (node is Map) CognitiveNode.fromJson(node.cast<String, Object?>()),
        ],
        edges: [
          for (final edge in (json['edges'] as List?) ?? const [])
            if (edge is Map) CognitiveEdge.fromJson(edge.cast<String, Object?>()),
        ],
      );

  CognitiveNode? nodeById(String id) {
    for (final node in nodes) {
      if (node.id == id) {
        return node;
      }
    }
    return null;
  }

  /// A memory strength MindNet will accept, or null when it is not one.
  ///
  /// MindNet's own input validation flags an `ms` that is not finite or lies
  /// outside `[0, 1]` (`src/io/run.js`); carrying such a value into the graph
  /// would poison every drive sum that reads it, so the field is dropped and
  /// MindNet's documented fallback applies (§6.3) instead of a number nobody
  /// can interpret.
  static double? _legalMs(double? value) {
    if (value == null || !value.isFinite || value < 0 || value > 1) {
      return null;
    }
    return value;
  }
}
