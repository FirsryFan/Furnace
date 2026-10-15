/// The production [RetentionProbe]: "what is this node's retrievability at hour
/// `u`?" answered by the DSR memory layer that `memory.dsr` installs.
///
/// Why this file exists: the counterfactual planner (`fast_diagnosis.dart`) can
/// price a `retention` instruction - "review this, how much does it buy by
/// tomorrow?" - only if somebody can answer that question. Retention is tierA's
/// math (`memoryDsr.retrievabilityOf`, ported as `DsrMemory` in
/// `domain/services/srs/dsr_memory.dart`), not the fast layer's, so the planner
/// takes it as a callback and this is the callback.
///
/// The reference semantics are `mechanisms/memory.dsr.js`'s lazy `ensureState`
/// plus `synced()`; the bag, its initialisation from `ms` and that side effect
/// live in [FastEngine.dsrStateOf]/[FastEngine.dsrRetrievabilityOf], so this
/// probe and [FastEngine.review] cannot drift apart. The conformance test keeps
/// its own copy of the same math on purpose: it is a reference to compare
/// against, and it must not start agreeing with production by construction.
///
/// [FastNode.ms] is only a fallback: it carries the model's current
/// retrievability, so a lazy `ensureState` from it gives `R0 = ms`, `S = legacy_k
/// * R0` and the default `D`. A caller that knows the real card state should
/// seed the bag first ([seedDsrState]) - otherwise this is a "prior" price, not
/// the card's own.
library;

import '../srs/dsr_memory.dart';
import 'fast_diagnosis.dart';
import 'fast_engine.dart';

/// Builds a [RetentionProbe] backed by the DSR memory layer.
///
/// Pass the engine's own parameters (`engine.memoryParams`) when the counterfactual
/// runs on a `memory.dsr`-installed engine, so "before" and "after" are priced
/// with the same constants the review used; passing null (or nothing) means "the
/// engine's defaults", which is what an engine built without an explicit
/// `memoryParams` is using.
///
/// Returns null for a node that is not in the graph: an unknown id must not be
/// priced as "zero gain" (the planner distinguishes null from 0 and says so).
RetentionProbe dsrRetentionProbe({DsrParams? params}) {
  final effective = params ?? const DsrParams();
  return (engine, nodeId, u) {
    final node = engine.graph.nodes[nodeId];
    if (node == null) {
      return null;
    }
    return FastEngine.dsrRetrievabilityOf(node, u: u, params: effective);
  };
}

/// Puts a known card state into the node's memory bag, so a later probe reads
/// the card instead of a guess derived from `ms`.
///
/// This is the seam the conformance test's reference probe documents ("the
/// integration task is expected to wire the *real* card state here"); today's
/// callers still hand over a tierA prior, so this exists for the caller that
/// has more than one number to give.
void seedDsrState(FastNode node, DsrState state) {
  node.m[FastEngine.memoryBagKey] = state.toJson();
}
