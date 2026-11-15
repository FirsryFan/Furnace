import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/ai_repository.dart';
import 'package:furnace/features/ai/application/ai_providers.dart';
import 'package:furnace/features/ai/application/ai_settings_notifier.dart';
import 'package:furnace/features/ai/domain/claim.dart';
import 'package:furnace/features/ai/domain/model_adapter.dart'
    show ReasoningEffort;
import 'package:furnace/features/ai/infrastructure/experience_store.dart';
import 'package:furnace/features/ai/infrastructure/openai_compat_adapter.dart';
import 'package:furnace/features/ai/infrastructure/student_verifier.dart';

/// Provider wiring for the AI feature.
///
/// Covered here:
///
///  * `experienceStoreProvider` 注册的是写 v45 `agent_experiences` 的 Drift 仓储，
///    写一条经验会真的落到表里（不是内存影子实现）；
///  * the v46 model-parameter layer reaches the adapters the providers hand out:
///    an empty configuration keeps the old 0.6/20k, 0.2/3k, 0.2/3k adapters and
///    the chat adapter sends no reasoning effort (MODEL-CONFIG-2026-11-15.md);
///  * 保存设置（AI 设置页）不会顺手清掉直接写库的模型参数。
void main() {
  Future<ProviderContainer> containerWithConfig(AiConfig config) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    await AiRepository(database)
        .saveConfig(config, fallbackLanguage: 'system');
    final container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(database)],
    );
    addTearDown(container.dispose);
    addTearDown(database.close);
    await container.read(aiConfigProvider.future);
    return container;
  }

  OpenAiCompatAdapter chatAdapterOf(ProviderContainer container) =>
      container.read(modelAdapterProvider) as OpenAiCompatAdapter;

  test('experienceStoreProvider 注册 DriftExperienceRepository 并写 v45 表',
      () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    final container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(database)],
    );
    addTearDown(container.dispose);
    addTearDown(database.close);

    final store = container.read(experienceStoreProvider);
    expect(store, isA<ExperienceStore>());
    expect(store.repository, isA<DriftExperienceRepository>());

    final admission = await store.record(
      claim: Claim(
        id: 'student-answer-q1',
        kind: ClaimKind.decision,
        canonical: 'μ=0.5',
        statement: 'μ=0.5',
        status: ClaimStatus.verified,
        checkedVersion: 1,
        evidence: '内容验证 pass',
        createdAtMs: 0,
      ),
      cluster: 'student_exam',
      stateKey: 'q-abc',
      action: 'verified_answer',
      reward: 1.0,
      provenanceRunId: 'run-1',
      provenanceVerifierId: 'student_independent_v1',
      nowMs: 1700000000000,
    );

    expect(admission.accepted, isTrue);
    final rows = await database.select(database.agentExperiences).get();
    expect(rows, hasLength(1));
    expect(rows.single.cluster, 'student_exam');
    expect(rows.single.action, 'verified_answer');
    expect(rows.single.provenanceRunId, 'run-1');
    expect(rows.single.provenanceVerifierId, 'student_independent_v1');
    expect(rows.single.reward, 1.0);
    expect(rows.single.version, 1);
    expect(rows.single.revokedAt, isNull);
  });

  test('an empty model-parameter config keeps the pre-v46 adapters', () async {
    final container = await containerWithConfig(
      const AiConfig(enabled: true, apiKey: 'sk-test'),
    );

    final solver = container.read(studentSolverProvider)!;
    final reason = solver.reasonAdapter as OpenAiCompatAdapter;
    final answer = solver.answerAdapter! as OpenAiCompatAdapter;
    expect(reason.temperature, 0.6);
    expect(reason.maxTokens, 20000);
    expect(reason.reasoningEffort, isNull);
    expect(answer.temperature, 0.2);
    expect(answer.maxTokens, 3000);
    expect(answer.reasoningEffort, isNull);

    final verifier =
        container.read(studentVerifierProvider) as StudentVerifier;
    final verifierAdapter = verifier.adapter as OpenAiCompatAdapter;
    expect(verifierAdapter.model, AiConfig.defaultModel);
    expect(verifierAdapter.temperature, 0.2);
    expect(verifierAdapter.maxTokens, 3000);
    expect(verifierAdapter.reasoningEffort, isNull);

    final chat = chatAdapterOf(container);
    expect(chat.temperature, 0.2);
    expect(chat.reasoningEffort, isNull);

    expect(container.read(studentModeControllerProvider), isNotNull);
  });

  test('configured parameters reach solve, answer and verifier adapters',
      () async {
    final container = await containerWithConfig(
      const AiConfig(
        enabled: true,
        apiKey: 'sk-test',
        model: 'deepseek-flash',
        reasoningEffort: ReasoningEffort.low,
        temperature: 1.2,
        answerTemperature: 0.35,
        verifierTemperature: 0.0,
        maxReasoningTokens: 50000,
        answerReserveTokens: 1500,
        verifierModel: 'deepseek-v4-pro',
        verifierEffort: ReasoningEffort.max,
      ),
    );

    final solver = container.read(studentSolverProvider)!;
    final reason = solver.reasonAdapter as OpenAiCompatAdapter;
    final answer = solver.answerAdapter! as OpenAiCompatAdapter;
    expect(reason.model, 'deepseek-flash');
    expect(reason.reasoningEffort, ReasoningEffort.low);
    expect(reason.temperature, 1.2);
    expect(reason.maxTokens, 50000);
    expect(answer.temperature, 0.35);
    expect(answer.maxTokens, 1500);
    expect(answer.reasoningEffort, isNull);

    final verifier =
        container.read(studentVerifierProvider) as StudentVerifier;
    final verifierAdapter = verifier.adapter as OpenAiCompatAdapter;
    expect(verifierAdapter.model, 'deepseek-v4-pro');
    expect(verifierAdapter.reasoningEffort, ReasoningEffort.max);
    expect(verifierAdapter.temperature, 0.0);
    expect(verifierAdapter.maxTokens, 1500);

    // 2026-11-15 AI chat redesign: the effort is selectable in the composer, so
    // the chat adapter carries it (and the loop echoes reasoning_content).
    expect(chatAdapterOf(container).reasoningEffort, ReasoningEffort.low);
  });

  test('no usable key means the student providers are absent', () async {
    final container = await containerWithConfig(
      const AiConfig(enabled: true, apiKey: '   '),
    );
    expect(container.read(studentSolverProvider), isNull);
    expect(container.read(studentVerifierProvider), isNull);
    expect(container.read(studentModeControllerProvider), isNull);
    expect(container.read(modelAdapterProvider), isNull);
  });

  test('saving the settings screen keeps model parameters stored directly',
      () async {
    final container = await containerWithConfig(
      const AiConfig(
        enabled: true,
        apiKey: 'sk-test',
        model: 'deepseek-flash',
        reasoningEffort: ReasoningEffort.low,
        temperature: 1.2,
        answerTemperature: 0.35,
        verifierTemperature: 0.0,
        maxReasoningTokens: 50000,
        answerReserveTokens: 1500,
        verifierModel: 'deepseek-v4-pro',
        verifierEffort: ReasoningEffort.max,
      ),
    );

    // What the settings page hands over: no model-parameter controls, so every
    // new field is NULL there.
    await container.read(aiSettingsControllerProvider).save(
          const AiConfig(
            enabled: true,
            apiKey: '  sk-new  ',
            baseUrl: '',
            model: '',
            permissionMode: AiPermissionMode.auto,
            maxRounds: 50,
          ),
        );

    final stored = await container.read(aiConfigProvider.future);
    expect(stored.apiKey, 'sk-new', reason: 'blank handling still applies');
    expect(stored.model, isNull);
    expect(stored.permissionMode, AiPermissionMode.auto);
    expect(stored.maxRounds, 50);
    expect(stored.reasoningEffort, ReasoningEffort.low);
    expect(stored.temperature, 1.2);
    expect(stored.answerTemperature, 0.35);
    expect(stored.verifierTemperature, 0.0);
    expect(stored.maxReasoningTokens, 50000);
    expect(stored.answerReserveTokens, 1500);
    expect(stored.verifierModel, 'deepseek-v4-pro');
    expect(stored.verifierEffort, ReasoningEffort.max);
  });
}
