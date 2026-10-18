/// 思维链洞察的读表函数（纯 Dart，不依赖 Riverpod）+ 两个 provider。
///
/// 为什么单独一个文件：聚合口径全在
/// domain/services/reasoning/chain_insights.dart（纯逻辑，不碰 drift），
/// 这里只负责把 ReasoningChains / ReasoningSteps 拼成聚合输入。分工与
/// question_audit_reader.dart 一致。
///
/// 已知动作标记：ReasoningSteps 表里没有 knownAction 列，入库时解析器判出的
/// knownAction 也没有落库。这里一律传 knownAction: null，让聚合层按**当前**
/// 词表（内置 + 用户编辑过的 overlay）重新判定——用户改词表后旧标记本来就会
/// 过期，重判比猜快照更可信。
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/state/data_revision.dart';
import '../../../data/database/app_database_provider.dart';
import '../../../data/database/database.dart';
import '../../../domain/services/reasoning/capability_action_overlay.dart';
import '../../../domain/services/reasoning/chain_insights.dart';
import 'capability_vocabulary_store.dart';

/// 一次洞察读取的快照：投影后的链 + 读表时的异常计数。
class ChainInsightCorpus {
  const ChainInsightCorpus({
    required this.chains,
    this.orphanStepCount = 0,
    this.invalidKnowledgeHintsSteps = 0,
  });

  /// 全部链（含没有步骤的链：链可以先建、步骤后补）。
  final List<ChainInsightChain> chains;

  /// chainId 在 reasoning_chains 里找不到的步骤行数。
  final int orphanStepCount;

  /// knowledgeHints 不是合法 JSON 数组、读作空列表的步骤行数。
  final int invalidKnowledgeHintsSteps;

  int get chainCount => chains.length;

  int get stepCount {
    var total = 0;
    for (final chain in chains) {
      total += chain.steps.length;
    }
    return total;
  }

  bool get isEmpty => chains.isEmpty;
}

/// 读一次全库，拼出洞察聚合输入。
///
/// 顺序：链按 createdAt 升序、同时间按 id 升序；链内步骤按 idx 升序、同 idx
/// 按 id 升序。聚合层自己也有确定性排序，这里只保证「读出来就是稳定序」，
/// 让同一条链重复读、跨设备读得到同一份输入。
Future<ChainInsightCorpus> readChainInsightCorpus(AppDatabase db) async {
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
  final chains = <ChainInsightChain>[];
  for (final chain in orderedChains) {
    final rows = stepsByChain[chain.id] ?? const <ReasoningStep>[];
    final orderedSteps = List<ReasoningStep>.of(rows)
      ..sort((a, b) {
        final byIdx = a.idx.compareTo(b.idx);
        return byIdx != 0 ? byIdx : a.id.compareTo(b.id);
      });
    final steps = <ChainInsightStep>[];
    for (final row in orderedSteps) {
      final hints = _parseKnowledgeHints(row.knowledgeHints);
      if (hints == null) invalidKnowledgeHintsSteps++;
      steps.add(
        ChainInsightStep(
          actionType: row.actionType,
          index: row.idx,
          stuckRisk: row.stuckRisk,
          knownAction: null,
          knowledgeHints: hints ?? const <String>[],
          occurredAt: DateTime.fromMillisecondsSinceEpoch(row.createdAt),
        ),
      );
    }
    chains.add(
      ChainInsightChain(
        chainId: chain.id,
        questionId: chain.questionId,
        steps: List<ChainInsightStep>.unmodifiable(steps),
        occurredAt: DateTime.fromMillisecondsSinceEpoch(chain.createdAt),
      ),
    );
  }

  return ChainInsightCorpus(
    chains: List<ChainInsightChain>.unmodifiable(chains),
    orphanStepCount: orphanStepCount,
    invalidKnowledgeHintsSteps: invalidKnowledgeHintsSteps,
  );
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

/// 全库思维链的聚合输入快照。
final chainInsightCorpusProvider =
    FutureProvider<ChainInsightCorpus>((ref) async {
  ref.watchDatabaseRevision();
  final db = ref.watch(appDatabaseProvider);
  return readChainInsightCorpus(db);
});

/// 全库思维链的洞察读数（按当前词表判定 known/custom/unknown）。
///
/// 词表读取失败时退回内置词表继续聚合，不阻塞洞察页——用户自定义词表坏掉
/// 只影响 known/custom 的判定，不影响步数与卡点读数。
final chainInsightsProvider = FutureProvider<ChainInsights>((ref) async {
  final corpus = await ref.watch(chainInsightCorpusProvider.future);
  var overlay = CapabilityActionOverlay.empty;
  try {
    overlay = await ref.watch(capabilityActionOverlayProvider.future);
  } on Object {
    overlay = CapabilityActionOverlay.empty;
  }
  return ChainInsights.aggregate(
    chains: corpus.chains,
    catalog: overlay.catalog,
  );
});
