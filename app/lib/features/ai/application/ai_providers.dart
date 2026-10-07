import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/app_database_provider.dart';
import '../../../data/repositories/ai_repository.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../data/skill/skill_store.dart';
import '../../../domain/services/cognitive/cognitive_model.dart';
import '../domain/agent_loop.dart';
import '../domain/approval_engine.dart';
import '../domain/model_adapter.dart';
import '../domain/tool_registry.dart';
import '../infrastructure/ai_attachment_store.dart';
import '../infrastructure/openai_compat_adapter.dart';

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
final toolRegistryProvider = Provider<ToolRegistry>((ref) {
  return ToolRegistry.forApp(
    db: ref.watch(appDatabaseProvider),
    tasks: ref.watch(taskRepositoryProvider),
    blocks: ref.watch(timeBlockRepositoryProvider),
    anki: ref.watch(ankiRepositoryProvider),
    tags: ref.watch(tagRepositoryProvider),
    model: ref.watch(cognitiveModelProvider),
  );
});

/// The network adapter. Rebuilt whenever the configuration changes so a new key
/// or base URL takes effect without restarting the app.
final modelAdapterProvider = Provider<ModelAdapter?>((ref) {
  final config = ref.watch(aiConfigProvider).valueOrNull;
  if (config == null || !config.isUsable) {
    return null;
  }
  return OpenAiCompatAdapter(
    apiKey: config.apiKey!,
    baseUrl: config.effectiveBaseUrl,
    model: config.effectiveModel,
  );
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
    skills: ref.watch(skillStoreProvider),
  );
  ref.onDispose(loop.dispose);
  return loop;
});

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
