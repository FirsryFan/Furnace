/// 思维链质量体检的读表函数（纯 Dart + Riverpod）+ 三个 provider。
///
/// 为什么单独一个文件：19 条判据全在
/// domain/services/reasoning/chain_quality.dart（纯逻辑，不碰 drift），
/// 这里只负责把 ReasoningChains / ReasoningSteps 拼成体检输入。分工与
/// chain_insights_reader.dart / question_audit_reader.dart 一致。
///
/// 已知动作标记：ReasoningSteps 表里没有 knownAction 列，入库时解析器判出的
/// knownAction 也没有落库。这里一律传 knownAction: null——体检层会按**当前**
/// 词表（内置 + 用户编辑过的 overlay）重新判定 known，快照只用于发现过期标记，
/// 没有快照就不产生 stale_known_action_flag。
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/state/data_revision.dart';
import '../../../data/database/app_database_provider.dart';
import '../../../data/database/database.dart';
import '../../../domain/services/reasoning/capability_action_overlay.dart';
import '../../../domain/services/reasoning/chain_quality.dart';
import 'capability_vocabulary_store.dart';

/// 一次体检读取的快照：投影后的链 + 读表时的异常计数。
class ChainQualityCorpus {
  /// 构造快照；chains 会被复制成不可变列表。
  const ChainQualityCorpus({
    required this.chains,
    this.orphanStepCount = 0,
    this.invalidKnowledgeHintsSteps = 0,
  });

  /// 全部链（含没有步骤的链：链可以先建、步骤后补）。
  final List<ChainQualityChainInput> chains;

  /// chainId 在 reasoning_chains 里找不到的步骤行数。
  final int orphanStepCount;

  /// knowledgeHints 不是合法 JSON 数组、读作空列表的步骤行数。
  final int invalidKnowledgeHintsSteps;

  /// 链数。
  int get chainCount => chains.length;

  /// 步骤总数（只算挂在链上的）。
  int get stepCount {
    var total = 0;
    for (final chain in chains) {
      total += chain.steps.length;
    }
    return total;
  }

  /// 没有任何链。
  bool get isEmpty => chains.isEmpty;
}

/// 读一次全库，拼出体检输入。
///
/// 顺序：链按 createdAt 升序、同时间按 id 升序；链内步骤按 idx 升序、同 idx
/// 按 id 升序——与 chain_insights_reader.dart 同口径，保证同一条链重复读得到同一份输入。
Future<ChainQualityCorpus> readChainQualityCorpus(AppDatabase db) async {
  final chainRows = await db.select(db.reasoningChains).get();
  final stepRows = await db.select(db.reasoningSteps).get();

  final stepsByChain = <String, List<ReasoningStep>>{};
  for (final row in stepRows) {
    (stepsByChain[row.chainId] ??= <ReasoningStep>[]).add(row);
  }

  final chainIds = <String>{for (final row in chainRows) row.id};
  var orphanStepCount = 0;
  for (final row in stepRows) {
    if (!chainIds.contains(row.chainId)) orphanStepCount++;
  }

  final orderedChains = List<ReasoningChain>.of(chainRows)
    ..sort((a, b) {
      final byTime = a.createdAt.compareTo(b.createdAt);
      return byTime != 0 ? byTime : a.id.compareTo(b.id);
    });

  var invalidKnowledgeHintsSteps = 0;
  final chains = <ChainQualityChainInput>[];
  for (final chain in orderedChains) {
    final rows = stepsByChain[chain.id] ?? const <ReasoningStep>[];
    final orderedSteps = List<ReasoningStep>.of(rows)
      ..sort((a, b) {
        final byIdx = a.idx.compareTo(b.idx);
        return byIdx != 0 ? byIdx : a.id.compareTo(b.id);
      });
    final steps = <ChainQualityStepInput>[];
    for (final row in orderedSteps) {
      final hints = _parseKnowledgeHints(row.knowledgeHints);
      if (hints == null) invalidKnowledgeHintsSteps++;
      steps.add(
        ChainQualityStepInput(
          actionType: row.actionType,
          index: row.idx,
          stuckRisk: row.stuckRisk,
          knownAction: null,
          justification: _blankToNull(row.justification),
          checkMethod: _blankToNull(row.checkMethod),
          knowledgeHints: hints ?? const <String>[],
        ),
      );
    }
    chains.add(
      ChainQualityChainInput(
        chainId: chain.id,
        questionId: chain.questionId,
        steps: List<ChainQualityStepInput>.unmodifiable(steps),
      ),
    );
  }

  return ChainQualityCorpus(
    chains: List<ChainQualityChainInput>.unmodifiable(chains),
    orphanStepCount: orphanStepCount,
    invalidKnowledgeHintsSteps: invalidKnowledgeHintsSteps,
  );
}

/// 数据库里的空串/纯空白读作「没写」。
String? _blankToNull(String raw) {
  final text = raw.trim();
  return text.isEmpty ? null : text;
}

/// 解析 ReasoningSteps.knowledgeHints 的 JSON 数组文本。
///
/// 返回 null = 这段文本不是合法 JSON 数组（调用方计一次无效并读作空）；
/// 返回空列表 = 合法但没内容。非法项/空白项丢弃，不因一个脏元素丢掉整行。
List<String>? _parseKnowledgeHints(String raw) {
  final text = raw.trim();
  if (text.isEmpty || text == '[]') return const <String>[];
  Object? decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException {
    return null;
  }
  if (decoded is! List) return null;
  final hints = <String>[];
  for (final item in decoded) {
    if (item is String) {
      final trimmed = item.trim();
      if (trimmed.isNotEmpty) hints.add(trimmed);
    }
  }
  return List<String>.unmodifiable(hints);
}

/// 全库思维链的体检输入快照。
final chainQualityCorpusProvider =
    FutureProvider<ChainQualityCorpus>((ref) async {
  ref.watchDatabaseRevision();
  final db = ref.watch(appDatabaseProvider);
  return readChainQualityCorpus(db);
});

/// 全库思维链的质量体检报告（按当前词表判定 known/custom/unknown）。
///
/// 词表读取失败时退回内置词表继续体检：用户自定义词表坏掉只影响
/// known 判定，不影响链级/步级判据。
final chainQualityReportProvider =
    FutureProvider<ChainQualityReport>((ref) async {
  final corpus = await ref.watch(chainQualityCorpusProvider.future);
  var overlay = CapabilityActionOverlay.empty;
  try {
    overlay = await ref.watch(capabilityActionOverlayProvider.future);
  } on Object {
    overlay = CapabilityActionOverlay.empty;
  }
  return ChainQualityAudit.audit(corpus.chains, catalog: overlay.catalog);
});

/// 单题质量体检：只审计这道题的链，供题目详情页用。
///
/// 与全库报告同一口径（同一份 corpus、同一份词表），只是先过滤
/// questionId；没有链时返回空报告，不当成错误。
final chainQualityForQuestionProvider =
    FutureProvider.family<ChainQualityReport, String>((ref, questionId) async {
  final corpus = await ref.watch(chainQualityCorpusProvider.future);
  final chains = <ChainQualityChainInput>[
    for (final chain in corpus.chains)
      if (chain.questionId == questionId) chain,
  ];
  if (chains.isEmpty) return ChainQualityReport.empty();
  var overlay = CapabilityActionOverlay.empty;
  try {
    overlay = await ref.watch(capabilityActionOverlayProvider.future);
  } on Object {
    overlay = CapabilityActionOverlay.empty;
  }
  return ChainQualityAudit.audit(chains, catalog: overlay.catalog);
});
