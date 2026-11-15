import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/ai_repository.dart';
import 'package:furnace/features/ai/domain/model_adapter.dart'
    show ReasoningEffort;

/// The model-parameter layer's contract (v46, MODEL-CONFIG-2026-11-15.md).
///
/// Three things must hold, and they are independent:
///
///  1. **Empty configuration = old behaviour.** NULL on every parameter
///     resolves to exactly the literal the code used before the layer existed
///     (reasoning 0.6 / 20 000, answer 0.2 / 3 000, verifier 0.2 / 3 000, no
///     `reasoning_effort`, verifier on the solver's model). This is what keeps
///     an upgrade from changing a single request.
///  2. **Chosen values survive a storage round-trip, NULLs stay NULL** - the
///     repository must not freeze today's defaults into the file.
///  3. **Out-of-range values are clamped**, so a hand-edited file cannot send a
///     temperature or `max_tokens` the API rejects.
void main() {
  group('AiConfig defaults keep the pre-v46 behaviour', () {
    const config = AiConfig(enabled: true, apiKey: 'sk-test');

    test('temperatures resolve to the old literals', () {
      expect(config.temperature, isNull);
      expect(config.effectiveTemperature, 0.6);
      expect(config.effectiveAnswerTemperature, 0.2);
      expect(config.effectiveVerifierTemperature, 0.2);
    });

    test('output budgets resolve to the old literals', () {
      expect(config.maxReasoningTokens, isNull);
      expect(config.effectiveMaxReasoningTokens, 20000);
      expect(config.answerReserveTokens, isNull);
      expect(config.effectiveAnswerReserveTokens, 3000);
    });

    test('no effort is configured, and the verifier uses the solver model', () {
      expect(config.reasoningEffort, isNull);
      expect(config.verifierEffort, isNull);
      expect(config.effectiveVerifierModel, AiConfig.defaultModel);
      expect(config.effectiveVerifierModel, config.effectiveModel);
    });

    test('a non-empty verifier model wins, blank falls back', () {
      const custom = AiConfig(
        enabled: true,
        verifierModel: ' deepseek-flash ',
      );
      expect(custom.effectiveVerifierModel, 'deepseek-flash');
      const blank = AiConfig(enabled: true, verifierModel: '   ');
      expect(blank.effectiveVerifierModel, AiConfig.defaultModel);
    });
  });

  group('resolution clamps into the documented ranges', () {
    test('temperature is clamped to 0..2, NaN falls back', () {
      expect(
        AiConfig.resolveTemperature(3, AiConfig.defaultTemperature),
        AiConfig.maxTemperature,
      );
      expect(
        AiConfig.resolveTemperature(-1, AiConfig.defaultTemperature),
        AiConfig.minTemperature,
      );
      expect(
        AiConfig.resolveTemperature(double.nan, AiConfig.defaultTemperature),
        AiConfig.defaultTemperature,
      );
      expect(
        AiConfig.resolveTemperature(1.25, AiConfig.defaultTemperature),
        1.25,
      );
    });

    test('output tokens are clamped to 1..393216', () {
      expect(AiConfig.resolveOutputTokens(0, 10), 1);
      expect(AiConfig.resolveOutputTokens(999999999, 10), 393216);
      expect(AiConfig.resolveOutputTokens(50000, 10), 50000);
      expect(AiConfig.resolveOutputTokens(null, 7), 7);
    });

    test('configured values flow through the effective getters', () {
      const config = AiConfig(
        enabled: true,
        temperature: 1.1,
        answerTemperature: 0.5,
        verifierTemperature: 0,
        maxReasoningTokens: 50000,
        answerReserveTokens: 800,
        reasoningEffort: ReasoningEffort.low,
        verifierEffort: ReasoningEffort.high,
      );
      expect(config.effectiveTemperature, 1.1);
      expect(config.effectiveAnswerTemperature, 0.5);
      expect(config.effectiveVerifierTemperature, 0);
      expect(config.effectiveMaxReasoningTokens, 50000);
      expect(config.effectiveAnswerReserveTokens, 800);
      expect(config.reasoningEffort, ReasoningEffort.low);
      expect(config.verifierEffort, ReasoningEffort.high);
    });
  });

  group('ReasoningEffort', () {
    test('stored ids parse, unknown and NULL parse to null', () {
      expect(ReasoningEffort.fromId('low'), ReasoningEffort.low);
      expect(ReasoningEffort.fromId('high'), ReasoningEffort.high);
      expect(ReasoningEffort.fromId('max'), ReasoningEffort.max);
      expect(ReasoningEffort.fromId(null), isNull);
      expect(ReasoningEffort.fromId(''), isNull);
      expect(ReasoningEffort.fromId('medium'), isNull,
          reason: '"medium" is accepted by the API but maps to "high"; this '
              'layer deliberately does not offer a distinct-looking value '
              'that behaves identically to another');
      expect(ReasoningEffort.fromId('max')!.wireValue, 'max');
    });
  });

  group('AiRepository storage round-trip', () {
    late AppDatabase db;
    late AiRepository repository;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repository = AiRepository(db);
    });

    tearDown(() => db.close());

    test('empty configuration writes NULLs, so defaults stay reachable', () async {
      await repository.saveConfig(
        const AiConfig(enabled: true, apiKey: 'sk-test'),
        fallbackLanguage: 'system',
      );
      final row = (await db.select(db.localSettings).get()).single;
      expect(row.aiReasoningEffort, isNull);
      expect(row.aiTemperature, isNull);
      expect(row.aiAnswerTemperature, isNull);
      expect(row.aiVerifierTemperature, isNull);
      expect(row.aiMaxReasoningTokens, isNull);
      expect(row.aiAnswerReserveTokens, isNull);
      expect(row.aiVerifierModel, isNull);
      expect(row.aiVerifierEffort, isNull);

      final config = await repository.getConfig();
      expect(config.effectiveTemperature, 0.6);
      expect(config.effectiveMaxReasoningTokens, 20000);
    });

    test('chosen values survive the round-trip', () async {
      await repository.saveConfig(
        const AiConfig(
          enabled: true,
          apiKey: 'sk-test',
          model: 'deepseek-flash',
          reasoningEffort: ReasoningEffort.low,
          temperature: 1.1,
          answerTemperature: 0.4,
          verifierTemperature: 0.0,
          maxReasoningTokens: 50000,
          answerReserveTokens: 1200,
          verifierModel: 'deepseek-v4-pro',
          verifierEffort: ReasoningEffort.max,
        ),
        fallbackLanguage: 'system',
      );
      final config = await repository.getConfig();
      expect(config.model, 'deepseek-flash');
      expect(config.reasoningEffort, ReasoningEffort.low);
      expect(config.temperature, 1.1);
      expect(config.answerTemperature, 0.4);
      expect(config.verifierTemperature, 0.0);
      expect(config.maxReasoningTokens, 50000);
      expect(config.answerReserveTokens, 1200);
      expect(config.verifierModel, 'deepseek-v4-pro');
      expect(config.verifierEffort, ReasoningEffort.max);
      expect(config.effectiveVerifierModel, 'deepseek-v4-pro');
    });

    test('out-of-range values are clamped on the way in', () async {
      await repository.saveConfig(
        const AiConfig(
          enabled: true,
          temperature: 9,
          answerTemperature: -2,
          verifierTemperature: 3,
          maxReasoningTokens: 0,
          answerReserveTokens: 999999999,
        ),
        fallbackLanguage: 'system',
      );
      final row = (await db.select(db.localSettings).get()).single;
      expect(row.aiTemperature, 2.0);
      expect(row.aiAnswerTemperature, 0.0);
      expect(row.aiVerifierTemperature, 2.0);
      expect(row.aiMaxReasoningTokens, 1);
      expect(row.aiAnswerReserveTokens, 393216);
    });

    test('copyWith carries every new field', () {
      const base = AiConfig(enabled: true);
      final copied = base.copyWith(
        reasoningEffort: ReasoningEffort.max,
        temperature: 1.3,
        answerTemperature: 0.1,
        verifierTemperature: 0.9,
        maxReasoningTokens: 40000,
        answerReserveTokens: 2000,
        verifierModel: 'other-model',
        verifierEffort: ReasoningEffort.low,
      );
      expect(copied.reasoningEffort, ReasoningEffort.max);
      expect(copied.temperature, 1.3);
      expect(copied.answerTemperature, 0.1);
      expect(copied.verifierTemperature, 0.9);
      expect(copied.maxReasoningTokens, 40000);
      expect(copied.answerReserveTokens, 2000);
      expect(copied.verifierModel, 'other-model');
      expect(copied.verifierEffort, ReasoningEffort.low);
      // Unrelated fields keep the old behaviour too.
      expect(base.copyWith().maxRounds, AiConfig.defaultMaxRounds);
    });

    test('a missing settings row still reads as AI off', () async {
      final config = await repository.getConfig();
      expect(config.enabled, isFalse);
      expect(config.isUsable, isFalse);
    });

    test('the insert path can still write the settings row from scratch',
        () async {
      await repository.saveConfig(
        const AiConfig(
          enabled: true,
          apiKey: 'sk-test',
          reasoningEffort: ReasoningEffort.high,
        ),
        fallbackLanguage: 'zh',
      );
      final rows = await db.select(db.localSettings).get();
      expect(rows, hasLength(1));
      expect(rows.single.language, 'zh');
      expect(rows.single.id, 1);
      expect(rows.single.aiReasoningEffort, 'high');
    });
  });
}
