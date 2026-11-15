import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/repositories/ai_repository.dart';
import 'package:furnace/features/ai/application/ai_model_adapters.dart';
import 'package:furnace/features/ai/domain/model_adapter.dart'
    show ReasoningEffort;
import 'package:furnace/features/ai/infrastructure/openai_compat_adapter.dart';

/// The role -> adapter mapping of the model-parameter layer.
///
/// `AiModelAdapters` is where "which model / temperature / output budget /
/// reasoning effort does this turn run with" is decided. These tests pin the
/// two ends that matter:
///
///  * an untouched [AiConfig] produces exactly the adapter the pre-v46 code
///    produced (the same numbers that used to be literals in `ai_providers`);
///  * an explicit configuration reaches the intended role and only that role
///    (the answer-scribe stays effort-free because it is a transcription turn);
///  * the chat role carries the configured effort since 2026-11-15, when the
///    effort became selectable next to the send button - `AgentLoop.echoReasoning`
///    covers the `reasoning_content` half that thinking mode with tools needs.
void main() {
  OpenAiCompatAdapter asAdapter(Object adapter) =>
      adapter as OpenAiCompatAdapter;

  group('empty configuration keeps the shipped adapters', () {
    const config = AiConfig(enabled: true, apiKey: 'sk-test');

    test('chat: default model, shipped 0.2, no effort', () {
      final adapter = asAdapter(AiModelAdapters.chat(config));
      expect(adapter.apiKey, 'sk-test');
      expect(adapter.model, AiConfig.defaultModel);
      expect(adapter.temperature, 0.2);
      expect(adapter.maxTokens, isNull);
      expect(adapter.reasoningEffort, isNull);
    });

    test('solver: 0.6 / 20 000, no effort (the old literals)', () {
      final adapter = asAdapter(AiModelAdapters.solver(config));
      expect(adapter.temperature, 0.6);
      expect(adapter.maxTokens, 20000);
      expect(adapter.reasoningEffort, isNull);
    });

    test('answer: 0.2 / 3 000, no effort (the old literals)', () {
      final adapter = asAdapter(AiModelAdapters.answer(config));
      expect(adapter.temperature, 0.2);
      expect(adapter.maxTokens, 3000);
      expect(adapter.reasoningEffort, isNull);
    });

    test('verifier: same model, 0.2 / 3 000, no effort', () {
      final adapter = asAdapter(AiModelAdapters.verifier(config));
      expect(adapter.model, AiConfig.defaultModel);
      expect(adapter.temperature, 0.2);
      expect(adapter.maxTokens, 3000);
      expect(adapter.reasoningEffort, isNull);
    });
  });

  group('explicit configuration reaches its own role', () {
    const config = AiConfig(
      enabled: true,
      apiKey: 'sk-test',
      baseUrl: 'https://example.test/',
      model: 'deepseek-flash',
      reasoningEffort: ReasoningEffort.low,
      temperature: 1.2,
      answerTemperature: 0.35,
      verifierTemperature: 0.0,
      maxReasoningTokens: 50000,
      answerReserveTokens: 1500,
      verifierModel: 'deepseek-v4-pro',
      verifierEffort: ReasoningEffort.max,
    );

    test('base URL is normalised for every role', () {
      for (final adapter in [
        AiModelAdapters.chat(config),
        AiModelAdapters.solver(config),
        AiModelAdapters.answer(config),
        AiModelAdapters.verifier(config),
      ]) {
        expect(adapter.baseUrl, 'https://example.test');
      }
    });

    test('solver gets the reasoning effort and the large budget', () {
      final adapter = asAdapter(AiModelAdapters.solver(config));
      expect(adapter.model, 'deepseek-flash');
      expect(adapter.reasoningEffort, ReasoningEffort.low);
      expect(adapter.temperature, 1.2);
      expect(adapter.maxTokens, 50000);
    });

    test('answer turn gets its own temperature, no effort', () {
      final adapter = asAdapter(AiModelAdapters.answer(config));
      expect(adapter.temperature, 0.35);
      expect(adapter.maxTokens, 1500);
      expect(adapter.reasoningEffort, isNull);
    });

    test('verifier gets its own model, temperature, effort and reserve', () {
      final adapter = asAdapter(AiModelAdapters.verifier(config));
      expect(adapter.model, 'deepseek-v4-pro');
      expect(adapter.temperature, 0.0);
      expect(adapter.maxTokens, 1500);
      expect(adapter.reasoningEffort, ReasoningEffort.max);
    });

    test('chat gets the configured effort too', () {
      final adapter = asAdapter(AiModelAdapters.chat(config));
      expect(adapter.model, 'deepseek-flash');
      // 2026-11-15 AI chat redesign: the effort is selectable next to the send
      // button, so it has to reach the chat request. The loop replays
      // `reasoning_content` when this is set (AgentLoop.echoReasoning), which is
      // what thinking mode with tools requires.
      expect(adapter.reasoningEffort, ReasoningEffort.low);
    });
  });
}
