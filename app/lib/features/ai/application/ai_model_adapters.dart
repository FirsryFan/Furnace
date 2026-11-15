import '../../../data/repositories/ai_repository.dart';
import '../infrastructure/openai_compat_adapter.dart';

/// Builds the four role-specific model adapters from one stored [AiConfig].
///
/// This is the application-layer half of the model-parameter layer
/// (v46 / MODEL-CONFIG-2026-11-15.md): the place that answers "which model,
/// temperature, output budget and reasoning effort does this role run with"
/// for chat, solver, answer-scribe and verifier. A provider only wires the
/// result, and a test can assert the mapping without building a provider tree
/// or opening a socket.
///
/// Every `effective*` value on [AiConfig] falls back to the literal this code
/// used before the layer existed, so a configuration that never chose a
/// parameter produces the same adapter (and therefore the same request body)
/// as the old build:
///
///     role      model            temperature  max_tokens  reasoning_effort
///     chat      effectiveModel   0.2 (adapter default)  none  configured
///     solver    effectiveModel   0.6          20 000       configured
///     answer    effectiveModel   0.2           3 000       none
///     verifier  effectiveModel   0.2           3 000       configured
///
/// The chat role takes the **user's configured effort**, and none when nothing
/// was chosen. That is a deliberate change from the v46 wiring (user
/// 2026-11-15, AI chat redesign): the thinking effort is now selectable next to
/// the send button, so it has to reach the chat request or the control would be
/// a decoration. Thinking mode with `tools` requires the previous assistant
/// turn's `reasoning_content` to be sent back - that is why
/// `AgentLoop.echoReasoning` exists and is enabled by the same configuration.
/// The answer-scribe turn stays effort-free: it is a transcription turn, not a
/// reasoning one.
class AiModelAdapters {
  const AiModelAdapters._();

  /// The main chat / agent-loop adapter. Keeps the adapter's shipped 0.2
  /// temperature, and sends the configured thinking effort when the user chose
  /// one (NULL = send no `reasoning_effort`, the old behaviour).
  static OpenAiCompatAdapter chat(AiConfig config) => OpenAiCompatAdapter(
        apiKey: config.apiKey!,
        baseUrl: config.effectiveBaseUrl,
        model: config.effectiveModel,
        reasoningEffort: config.reasoningEffort,
      );

  /// The student solver's reasoning turn: the large output budget, the
  /// reasoning temperature and the user's thinking effort.
  static OpenAiCompatAdapter solver(AiConfig config) => OpenAiCompatAdapter(
        apiKey: config.apiKey!,
        baseUrl: config.effectiveBaseUrl,
        model: config.effectiveModel,
        temperature: config.effectiveTemperature,
        maxTokens: config.effectiveMaxReasoningTokens,
        reasoningEffort: config.reasoningEffort,
      );

  /// The answer-scribe ("finalizer") turn: small reserve, low temperature, no
  /// effort field (the shipped behaviour; it is a transcription turn, not a
  /// reasoning one).
  static OpenAiCompatAdapter answer(AiConfig config) => OpenAiCompatAdapter(
        apiKey: config.apiKey!,
        baseUrl: config.effectiveBaseUrl,
        model: config.effectiveModel,
        temperature: config.effectiveAnswerTemperature,
        maxTokens: config.effectiveAnswerReserveTokens,
      );

  /// The independent content verifier turn: it may use its own model and its
  /// own effort, and shares the answer reserve so verification cannot spend a
  /// reasoning-sized budget on a JSON verdict.
  static OpenAiCompatAdapter verifier(AiConfig config) => OpenAiCompatAdapter(
        apiKey: config.apiKey!,
        baseUrl: config.effectiveBaseUrl,
        model: config.effectiveVerifierModel,
        temperature: config.effectiveVerifierTemperature,
        maxTokens: config.effectiveAnswerReserveTokens,
        reasoningEffort: config.verifierEffort,
      );
}
