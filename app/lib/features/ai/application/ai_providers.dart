import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/app_database_provider.dart';
import '../../../data/repositories/ai_repository.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../data/skill/skill_store.dart';
import '../../../domain/services/cognitive/cognitive_model.dart';
import '../domain/agent_budget.dart';
import '../domain/agent_loop.dart';
import '../domain/agent_run.dart' as agent_run;
import '../domain/agent_run_sink.dart';
import '../domain/approval_engine.dart';
import '../domain/model_adapter.dart';
import '../domain/step_guard.dart';
import '../domain/student_solver.dart';
import '../domain/student_solver_context.dart';
import '../domain/tool_registry.dart';
import '../domain/verifier.dart';
import '../domain/vision_payload.dart';
import '../infrastructure/agent_run_store.dart';
import '../infrastructure/ai_attachment_store.dart';
import '../infrastructure/experience_store.dart';
import '../infrastructure/student_trace_store.dart';
import '../infrastructure/student_verifier.dart';
import 'ai_model_adapters.dart';
import '../../../domain/services/cognitive/preset_prior.dart';
import '../../student_preset/application/preset_selection.dart';
import 'conversation_runner.dart';
import 'student_mode_controller.dart';

/// Conversation, message and action storage (v6 tables).
final aiRepositoryProvider = Provider<AiRepository>((ref) {
  return AiRepository(ref.watch(appDatabaseProvider));
});

/// The AI configuration, read from the single-row settings table.
///
/// Everything in the AI feature depends on this: when the user has not set a
/// key, [aiConfigProvider] reports "not usable" and the conversation entry
/// point does not exist at all. That is what keeps the offline promise true
/// rather than aspirational - no key means no code path reaches the network.
final aiConfigProvider = FutureProvider<AiConfig>((ref) async {
  return ref.watch(aiRepositoryProvider).getConfig();
});

/// True when the AI surface should exist.
final aiEnabledProvider = Provider<bool>((ref) {
  return ref.watch(aiConfigProvider).valueOrNull?.isUsable ?? false;
});

/// The static tool list. Registered once; a tool is available because it is in
/// this list (AI_DESIGN §10 C2 - no plugin registry).
///
/// The list itself lives in [ToolRegistry.forApp] so that "is this tool
/// registered?" is answerable without a provider container; this callback only
/// supplies the dependencies. That is what keeps 用途 1's tool
/// (`evaluate_problem_fit`) reachable at runtime instead of dead code.
/// One shared context for the current turn's images. The loop writes; the
/// student tool reads, so a picture attached to the message reaches the solver
/// without putting base64 into a tool argument.
final studentSolverContextProvider = Provider<StudentSolverContext>((ref) {
  return StudentSolverContext();
});

final toolRegistryProvider = Provider<ToolRegistry>((ref) {
  return ToolRegistry.forApp(
    db: ref.watch(appDatabaseProvider),
    tasks: ref.watch(taskRepositoryProvider),
    blocks: ref.watch(timeBlockRepositoryProvider),
    anki: ref.watch(ankiRepositoryProvider),
    tags: ref.watch(tagRepositoryProvider),
    model: ref.watch(cognitiveModelProvider),
    studentSolver: ref.watch(studentSolverProvider),
    studentSolverContext: ref.watch(studentSolverContextProvider),
  );
});

/// The student-mode solver, bound to a separate pair of adapters so the
/// reasoning turn gets a larger budget and the finalizer gets a small reserve.
/// It is null when no usable model is configured, which keeps the offline
/// promise: no key means the tool is absent, not broken.
///
/// Both adapters are built by [AiModelAdapters] from the v46 model-parameter
/// layer; an untouched configuration resolves to the same 20 000/0.6 and
/// 3 000/0.2 pair this provider used to hard-code.
final studentSolverProvider = Provider<StudentSolver?>((ref) {
  final config = ref.watch(aiConfigProvider).valueOrNull;
  if (config == null || !config.isUsable) {
    return null;
  }
  final selection = ref.watch(presetSelectionProvider);
  final prior = PresetPrior.fromSelectionId(selection?.presetId);
  return StudentSolver(
    reasonAdapter: AiModelAdapters.solver(config),
    answerAdapter: AiModelAdapters.answer(config),
    systemPrompt: prior == null
        ? StudentSolver.defaultSystemPrompt
        : '${StudentSolver.defaultSystemPrompt}\n\n'
            '当前用户预设档位：${prior.band.label}。按这个档位的考场目标作答：'
            '不省略必要步骤，但不要引入超出该档位的额外理论；'
            '仍以题目条件和高中知识为准。',
  );
});

/// The student mode's independent content verifier, on its own adapter so the
/// verifier can use a different model and thinking effort from the solver.
///
/// With nothing configured it is the verifier the controller used to derive:
/// the solver's model, temperature 0.2, the 3 000-token answer reserve, and no
/// `reasoning_effort` field - the verifier was a fresh parameterless turn before
/// this provider existed, and an empty configuration must keep that.
final studentVerifierProvider = Provider<Verifier?>((ref) {
  final config = ref.watch(aiConfigProvider).valueOrNull;
  if (config == null || !config.isUsable) {
    return null;
  }
  return StudentVerifier(adapter: AiModelAdapters.verifier(config));
});

/// Where direct student-mode solves write their local trace.
///
/// A separate provider so a test can point it at a temporary directory without
/// touching the app-support tree; the default is the same store the tool uses.
final studentTraceStoreProvider = Provider<StudentTraceStore>((ref) {
  return StudentTraceStore();
});

/// 验证后经验库（设计文档 §5.5 / §12 Phase D）。
///
/// 与 [studentModeControllerProvider] 共用同一个数据库：学生 run 通过内容验证且
/// 过程无 blocker 时写一条 `agent_experiences`（cluster = student_exam，
/// action = verified_answer），provenance 记 run 与 verifier。经验只用于召回，
/// 不作为正确性来源（设计 §14）。
final experienceStoreProvider = Provider<ExperienceStore>((ref) {
  return ExperienceStore(
    repository: DriftExperienceRepository(ref.watch(appDatabaseProvider)),
  );
});

/// The direct student-mode entry point: the application-layer path that bypasses
/// the main [AgentLoop] entirely.
///
/// Null when no usable model is configured, for the same reason
/// [studentSolverProvider] is: no key means the path does not exist rather than
/// existing and failing. Callers get the direct path through
/// [conversationRunnerProvider], which routes by the session's preset.
///
/// It also carries the `agent_runs` / `agent_steps` / `agent_verifications` /
/// `agent_claims` recorder, so every student run leaves a DB audit trail (raw CoT
/// stays in the trace file, not in the database - design §5.6), plus the
/// [experienceStoreProvider] writer for verified runs (design §5.5).
final studentModeControllerProvider = Provider<StudentModeController?>((ref) {
  final solver = ref.watch(studentSolverProvider);
  final verifier = ref.watch(studentVerifierProvider);
  if (solver == null || verifier == null) {
    return null;
  }
  return StudentModeController(
    solver: solver,
    // 显式注入 verifier：它的模型/温度/预算/effort 来自 v46 模型参数层；
    // 空配置时与「从 answer adapter 推导」的旧行为完全一致。
    verifier: verifier,
    traceStore: ref.watch(studentTraceStoreProvider),
    recorder: AgentRunStoreRecorder(
      AgentRunStore(ref.watch(appDatabaseProvider)),
    ),
    experienceStore: ref.watch(experienceStoreProvider),
  );
});

/// The network adapter. Rebuilt whenever the configuration changes so a new key
/// or base URL takes effect without restarting the app.
///
/// See [AiModelAdapters.chat] for how the chat role uses the configured
/// thinking effort: `null` keeps the old request shape (no `reasoning_effort`),
/// a chosen level enables thinking mode for the main loop, which is why
/// [agentLoopProvider] turns on `echoReasoning` in the same case.
final modelAdapterProvider = Provider<ModelAdapter?>((ref) {
  final config = ref.watch(aiConfigProvider).valueOrNull;
  if (config == null || !config.isUsable) {
    return null;
  }
  return AiModelAdapters.chat(config);
});

/// The loop for one conversation.
///
/// Keyed by conversation id and disposed with it, because the loop holds the
/// turn state (pending approvals, executed calls) that belongs to exactly one
/// conversation.
final agentLoopProvider =
    Provider.family<AgentLoop?, String>((ref, conversationId) {
  final adapter = ref.watch(modelAdapterProvider);
  final config = ref.watch(aiConfigProvider).valueOrNull;
  if (adapter == null || config == null) {
    return null;
  }
  final loop = AgentLoop(
    adapter: adapter,
    registry: ref.watch(toolRegistryProvider),
    approval: ApprovalEngine(mode: config.permissionMode),
    repository: ref.watch(aiRepositoryProvider),
    db: ref.watch(appDatabaseProvider),
    attachments: ref.watch(aiAttachmentStoreProvider),
    studentContext: ref.watch(studentSolverContextProvider),
    skills: ref.watch(skillStoreProvider),
    // The user's tool-call budget. Read from the same configuration the
    // settings screen saves, so the slider there is what the loop actually
    // runs with - and so the telemetry panel's "used / cap" is the same cap.
    maxRounds: config.maxRounds,
    // Thinking mode is on exactly when the user chose a chat effort. A
    // tool-calling request in thinking mode has to replay the previous assistant
    // turn's `reasoning_content`; with no effort chosen nothing changes.
    echoReasoning: config.reasoningEffort != null,
    // 普通对话的 run/steps 审计（设计文档 §3.1/§7.1）：每个用户回合写一条
    // `agent_runs`，每个模型回合写一条 `agent_steps`。两个注入点都是可选的，
    // 直接构造 `AgentLoop` 时不传 = 旧行为；应用里总是接上。
    runSink: AgentRunStoreSink(AgentRunStore(ref.watch(appDatabaseProvider))),
    // chat budget（设计文档 §7.2）：普通对话没有 reasoning 预算，maxSteps 12，
    // completion 8192、无 answer reserve。学生 run 用自己的 composition budget，
    // 不经过这个 guard。
    stepGuard: StepGuard(budget: RunBudget.chat),
  );
  ref.onDispose(loop.dispose);
  return loop;
});

/// 把基础设施的 [AgentRunStore] 适配成主 loop 的 domain [AgentRunSink]。
///
/// 放在 application 层是为了守住依赖方向：`agent_loop.dart`（domain）只认识
/// [AgentRunSink]，数据库只在应用层接线进来。与 [AgentRunStoreRecorder] 分开
/// 是因为主对话只需要 run/step，学生 recorder 还带过程审计、验证与 claim 那些
/// 学生 composition 的类型。
class AgentRunStoreSink implements AgentRunSink {
  const AgentRunStoreSink(this._store);

  final AgentRunStore _store;

  @override
  Future<void> saveRun(agent_run.AgentRunState run) => _store.saveRun(run);

  @override
  Future<void> appendStep(agent_run.AgentStep step) => _store.saveStep(step);
}

/// The preset router for one conversation.
///
/// This is the bottom-layer send entry: it reads the conversation's recorded
/// agent preset and, for a student session, runs the isolated solver directly.
/// The main `AgentLoop` is only reached for a conversation whose preset is the
/// assistant one, which is what keeps student mode from being a tool of the
/// main agent. Null when no usable model is configured, same as the loop.
final conversationRunnerProvider =
    Provider.family<ConversationRunner?, String>((ref, conversationId) {
  final loop = ref.watch(agentLoopProvider(conversationId));
  if (loop == null) {
    return null;
  }
  return ConversationRunner(
    repository: ref.watch(aiRepositoryProvider),
    mainAgent: _AgentLoopStandardRunner(loop),
    studentMode: ref.watch(studentModeControllerProvider),
    attachments: ref.watch(aiAttachmentStoreProvider),
  );
});

/// Adapts `AgentLoop` to the runner's seam without making the student path
/// depend on it.
class _AgentLoopStandardRunner implements StandardAgentRunner {
  const _AgentLoopStandardRunner(this._loop);

  final AgentLoop _loop;

  @override
  Future<void> sendUserMessage({
    required String conversationId,
    required String text,
    List<PendingImage> images = const [],
  }) {
    return _loop.sendUserMessage(
      conversationId: conversationId,
      text: text,
      images: images,
    );
  }
}

/// The installed `.fskill` packages.
///
/// The install directory is the registry (docs/SKILL_FORMAT.md §7): skills are
/// files, not rows, so there is no table to query and nothing to migrate. One
/// instance for the whole app, because the settings card and the agent loop
/// must not disagree about which skills are enabled.
final skillStoreProvider = Provider<SkillStore>((ref) {
  return SkillStore();
});

/// What the settings card lists: every installed skill with its enabled flag.
///
/// A FutureProvider rather than a Stream: the store has no change stream to
/// watch (it is a directory, and the app is the only writer), so the card
/// invalidates this after each install/enable/remove instead of the store
/// growing a notifier it does not otherwise need.
final installedSkillsProvider = FutureProvider<List<InstalledSkill>>((ref) {
  return ref.watch(skillStoreProvider).list();
});

/// Where attached images are written and read back from.
///
/// A single instance for the whole app: the loop stores pictures with it and the
/// conversation view reads them through it, and two instances would mean two
/// ideas of where the files live.
final aiAttachmentStoreProvider = Provider<AiAttachmentStore>((ref) {
  return AiAttachmentStore(repository: ref.watch(aiRepositoryProvider));
});

/// The downscaler/re-encoder every picked or dropped image goes through.
///
/// A provider rather than a `const` inside the widget so a widget test can
/// supply a fake encoder: the real one decodes with `dart:ui`, whose futures do
/// not complete under the widget-test fake clock, and the drop behaviour can be
/// tested without manufacturing a real photo.
final visionImageEncoderProvider = Provider<VisionImageEncoder>((ref) {
  return const VisionImageEncoder();
});

/// Images attached to each message of a conversation, keyed by message id.
///
/// Resolved to absolute paths here rather than in the widget so a bubble can be
/// built synchronously; a missing file simply does not appear.
final messageImagesProvider = FutureProvider.family
    .autoDispose<Map<String, List<AiMessageImage>>, String>((ref, id) {
  return ref.watch(aiAttachmentStoreProvider).imagesForConversation(id);
});

/// The conversation list.
final conversationsProvider = FutureProvider((ref) async {
  return ref.watch(aiRepositoryProvider).listConversations();
});

/// Messages of one conversation.
final messagesProvider =
    FutureProvider.family((ref, String conversationId) async {
  return ref.watch(aiRepositoryProvider).listMessages(conversationId);
});

/// The newest recorded run of a conversation, or `null` when it never ran.
///
/// 底部指标条在读不到本轮内存态时（重开页面、刚切会话）用它显示已经落库的
/// `agent_runs` 记录：轮数与 token 是真实审计数据；缓存命中与上下文占用没有
/// 对应的持久化列（本次任务不允许改 schema），所以那两项仍然显示 `—`，而不是
/// 用 0 或估算值补上。
final latestAgentRunProvider =
    FutureProvider.family<agent_run.AgentRunState?, String>(
        (ref, String conversationId) async {
  final runs = await AgentRunStore(ref.watch(appDatabaseProvider))
      .recentRuns(conversationId: conversationId, limit: 1);
  return runs.isEmpty ? null : runs.first;
});
