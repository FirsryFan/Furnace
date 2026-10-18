/// 「AI 亲自解题 → 拆成能力动作 → 落库」这条管道（slice Q4）。
///
/// 用户的规则是硬的：**AI 不出题**。所以这条管道只做一件事——把用户给定的题目
/// 原样交给模型，让模型先真解出答案，再交出自述思维链；管道负责把回复解析成
/// 结构化步骤并落库（[QuestionRepository.saveChain]）。
///
/// 失败面的设计和成功面一样重要：
///  * 模型没配好（离线）→ 返回失败结果，**不抛异常**；
///  * 模型报了错 → 返回失败结果，并带上已经收到的原文片段；
///  * 回复不符合 JSON 契约（[ReasoningParseException]）→ 返回失败结果，附上原文
///    片段，让上层能决定是重试还是展示；
///  * 题目 id 不存在 → 返回 `notFound`。
///
/// 调用方拿到的是一个总是可用的 [ReasoningRunResult]，不需要 try/catch。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/question_repository.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../domain/services/reasoning/capability_action_overlay.dart';
import '../../../domain/services/reasoning/reasoning_prompt.dart';
import '../../ai/application/ai_providers.dart';
import '../../ai/domain/model_adapter.dart';
import 'capability_vocabulary_store.dart';

/// 一次解题拆链的结果。
class ReasoningRunResult {
  const ReasoningRunResult({
    required this.questionId,
    this.chain,
    this.chainId,
    this.failureReason,
    this.rawReply,
    this.savedSteps = 0,
  });

  /// 题目 id（`notFound` 时也带着，方便调用方回显）。
  final String questionId;

  /// 解析成功的思维链；失败时为 `null`。
  final ParsedChain? chain;

  /// 入库后的链 id；未入库（`save: false` 或失败）时为 `null`。
  final String? chainId;

  /// 失败原因；成功时为 `null`。
  final String? failureReason;

  /// 已经收到的模型原文；用于排查，可能为 `null`。
  final String? rawReply;

  /// 实际写进 `reasoning_steps` 的步数。
  final int savedSteps;

  bool get ok => failureReason == null && chain != null;

  bool get persisted => chainId != null;

  /// 题目不存在。
  factory ReasoningRunResult.notFound(String questionId) => ReasoningRunResult(
        questionId: questionId,
        failureReason: '题目不存在：$questionId',
      );

  /// 模型调用失败（含离线未配置）。
  factory ReasoningRunResult.modelFailure(
    String questionId,
    String reason, {
    String? rawReply,
  }) =>
      ReasoningRunResult(
        questionId: questionId,
        failureReason: reason,
        rawReply: rawReply,
      );

  /// 回复解析失败（结构不符合契约）。
  factory ReasoningRunResult.parseFailure(
    String questionId,
    ReasoningParseException error,
    String rawReply,
  ) =>
      ReasoningRunResult(
        questionId: questionId,
        failureReason: '模型回复不符合契约：${error.message}',
        rawReply: rawReply,
      );

  @override
  String toString() => ok
      ? 'ReasoningRunResult(ok, steps=$savedSteps, chainId=$chainId)'
      : 'ReasoningRunResult(failed: $failureReason)';
}

/// 管道本身。
///
/// 依赖是注入的（[repository] + [adapter]），所以测试不需要网络，也不需要
/// Riverpod 容器：`FakeModelAdapter` 直接塞进来就行。
class QuestionReasoningService {
  QuestionReasoningService({
    required QuestionRepository repository,
    required ModelAdapter? adapter,
    List<ModelToolSpec> tools = const <ModelToolSpec>[],
    Future<CapabilityActionOverlay> Function()? overlayLoader,
  })  : _repository = repository,
        _adapter = adapter,
        _tools = tools,
        _overlayLoader = overlayLoader;

  final QuestionRepository _repository;

  /// 唯一出网点；`null` 表示这台设备上没有可用模型（离线默认）。
  final ModelAdapter? _adapter;

  /// 传给模型的工具表。这一步不需要工具，默认空表——给空表比给一份用不上的
  /// 工具表更诚实：模型不会以为自己能做别的事。
  final List<ModelToolSpec> _tools;

  /// 每次解题前取一次用户词表；`null` 表示只用内置种子词表。
  ///
  /// 做成"取词表的函数"而不是在构造时读死，是因为词表可以随用户编辑而变化：
  /// 管道是长活对象（provider 只建一次），每次跑都该吃当前词表。词表读失败
  /// （数据库被换、JSON 坏到连宽容解析都救不回）**不**让解题失败——退回内置
  /// 词表，因为词表只影响"模型把动作归到哪一类"，不该挡住解出这道题。
  final Future<CapabilityActionOverlay> Function()? _overlayLoader;

  /// 取当前词表；没有 loader 或读取失败都退回空 overlay（= 内置词表）。
  Future<CapabilityActionOverlay> _loadOverlay() async {
    final loader = _overlayLoader;
    if (loader == null) {
      return CapabilityActionOverlay.empty;
    }
    try {
      return await loader();
    } on Object {
      return CapabilityActionOverlay.empty;
    }
  }

  /// 解一道题并（默认）把思维链落库。
  ///
  /// [modelId] 只写进 `reasoning_chains.model` 做溯源，不参与选模型——选谁由
  /// [ModelAdapter] 自己决定（`docs/AI_DESIGN.md` §3 D1）。
  Future<ReasoningRunResult> solveAndDecompose(
    String questionId, {
    String? modelId,
    bool save = true,
  }) async {
    final question = await _repository.byId(questionId);
    if (question == null) {
      return ReasoningRunResult.notFound(questionId);
    }

    final adapter = _adapter;
    if (adapter == null) {
      return ReasoningRunResult.modelFailure(
        questionId,
        '没有可用的模型适配器（离线或未配置）',
      );
    }

    final options = await _repository.optionsOf(questionId);
    // 当前生效词表：内置种子 + 用户自定义动作。提示词与解析器必须吃同一份
    // （`docs/REASONING_LAYER_DESIGN.md` §4），否则会出现"提示词允许、解析器
    // 不认识"的错位。取词表失败退回内置词表，不让它挡住解题。
    final catalog = (await _loadOverlay()).catalog;
    final messages = solveThenDecompose(
      questionStem: question.stem,
      options: <String>[
        for (final option in options)
          option.label.trim().isEmpty
              ? option.content
              : '${option.label}. ${option.content}',
      ],
      subjectKey: question.subjectKey,
      capabilityCatalog: catalog.actions,
    );

    final buffer = StringBuffer();
    String? failure;
    await for (final event in adapter.runTurn(
      messages: messages,
      tools: _tools,
    )) {
      switch (event) {
        case ModelTextDelta(:final text):
          buffer.write(text);
        case ModelFailure(:final message):
          failure = message;
        case ModelToolCall():
        case ModelTurnDone():
          break;
      }
    }

    final raw = buffer.toString();
    if (failure != null) {
      return ReasoningRunResult.modelFailure(
        questionId,
        '模型调用失败：$failure',
        rawReply: raw.isEmpty ? null : raw,
      );
    }

    final ParsedChain chain;
    try {
      chain = parseChain(raw, lookup: catalog.byKey);
    } on ReasoningParseException catch (error) {
      return ReasoningRunResult.parseFailure(questionId, error, raw);
    }

    if (!save) {
      return ReasoningRunResult(
        questionId: questionId,
        chain: chain,
        rawReply: raw,
      );
    }

    final chainId = await _repository.saveChain(
      questionId,
      ReasoningChainDraft(
        source: 'ai',
        model: modelId,
        summary: chain.summary,
        steps: <ReasoningStepDraft>[
          for (final step in chain.steps)
            ReasoningStepDraft(
              goal: step.goal,
              actionType: step.actionType,
              justification: step.justification,
              checkMethod: step.checkMethod,
              stuckRisk: step.stuckRisk,
              knowledgeHints: step.knowledgeHints,
            ),
        ],
      ),
    );

    return ReasoningRunResult(
      questionId: questionId,
      chain: chain,
      chainId: chainId,
      rawReply: raw,
      savedSteps: chain.steps.length,
    );
  }
}

/// App 默认管道：仓储来自数据库，适配器来自 AI 层（可能是 `null`）。
final questionReasoningServiceProvider =
    Provider<QuestionReasoningService>((ref) {
  // 词表从 `local_settings`（schema v25）读；保存词表后 invalidate
  // [capabilityActionOverlayProvider]，下一次解题即生效。
  final vocabulary = ref.watch(capabilityVocabularyStoreProvider);
  return QuestionReasoningService(
    repository: ref.watch(questionRepositoryProvider),
    adapter: ref.watch(modelAdapterProvider),
    overlayLoader: vocabulary.load,
  );
});
