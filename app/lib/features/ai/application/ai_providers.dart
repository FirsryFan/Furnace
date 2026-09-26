import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/app_database_provider.dart';
import '../../../data/repositories/ai_repository.dart';
import '../../../data/repositories/repository_providers.dart';
import '../domain/agent_loop.dart';
import '../domain/approval_engine.dart';
import '../domain/model_adapter.dart';
import '../domain/tool_registry.dart';
import '../infrastructure/openai_compat_adapter.dart';
import '../tools/schedule_tools.dart';
import '../tools/task_tools.dart';

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
final toolRegistryProvider = Provider<ToolRegistry>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final tasks = ref.watch(taskRepositoryProvider);
  final blocks = ref.watch(timeBlockRepositoryProvider);
  return ToolRegistry([
    QueryTasksTool(tasks, db),
    ManageTaskTool(tasks, db),
    QueryScheduleTool(blocks),
    ManageTimeBlockTool(blocks, db),
  ]);
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
  );
  ref.onDispose(loop.dispose);
  return loop;
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
