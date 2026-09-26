import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:furnace/l10n/app_localizations.dart';

import '../../../data/database/database.dart';
import '../../../data/repositories/ai_repository.dart';
import '../application/ai_providers.dart';
import '../domain/agent_loop.dart';
import '../domain/ai_tool.dart';
import '../domain/approval_engine.dart';

/// The AI conversation screen.
///
/// Design decisions this implements (docs/AI_DESIGN.md):
///
///  * **D15** the conversation is a first-class destination, not a button
///    sprinkled next to existing input fields.
///  * **D16** there is exactly one AI entry point, so a capability never has
///    two places to trigger it and two sets of state.
///  * The approval list is part of the message flow: the user sees what the
///    model wants to do, in the conversation, before anything happens.
class AiChatPage extends ConsumerStatefulWidget {
  const AiChatPage({super.key, this.onOpenSettings});

  /// Called when the user asks to configure the AI. The shell supplies this so
  /// the navigation stays in one place instead of the page owning routes.
  final VoidCallback? onOpenSettings;

  @override
  ConsumerState<AiChatPage> createState() => _AiChatPageState();
}

class _AiChatPageState extends ConsumerState<AiChatPage> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  String? _conversationId;
  AgentLoop? _loop;
  StreamSubscription<AgentTurnState>? _subscription;
  AgentTurnState _turn = const AgentTurnState();

  @override
  void dispose() {
    _subscription?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Binds to a conversation and starts listening to its loop.
  ///
  /// Rebuilt whenever the id changes because the loop owns per-conversation
  /// state (pending approvals, executed calls).
  void _attach(String conversationId) {
    if (_conversationId == conversationId) {
      return;
    }
    _subscription?.cancel();
    _conversationId = conversationId;
    final loop = ref.read(agentLoopProvider(conversationId));
    _loop = loop;
    _turn = loop?.state ?? const AgentTurnState();
    _subscription = loop?.states.listen((state) {
      if (mounted) {
        setState(() => _turn = state);
        _scrollToEnd();
      }
    });
    setState(() {});
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    final loop = _loop;
    final id = _conversationId;
    if (text.isEmpty || loop == null || id == null) {
      return;
    }
    _input.clear();
    await loop.sendUserMessage(conversationId: id, text: text);
    ref.invalidate(messagesProvider(id));
  }

  Future<void> _approve() async {
    final loop = _loop;
    final id = _conversationId;
    if (loop == null || id == null) {
      return;
    }
    await loop.approvePending(id);
    ref.invalidate(messagesProvider(id));
  }

  Future<void> _reject() async {
    final loop = _loop;
    final id = _conversationId;
    if (loop == null || id == null) {
      return;
    }
    await loop.rejectPending(id);
    ref.invalidate(messagesProvider(id));
  }

  Future<void> _undo(String actionId) async {
    final loop = _loop;
    final id = _conversationId;
    if (loop == null || id == null) {
      return;
    }
    await loop.undoExecuted(id, actionId);
    // Undoing changes user data, so the screens that show it must reload.
    ref.invalidate(messagesProvider(id));
  }

  Future<void> _newConversation() async {
    final repository = ref.read(aiRepositoryProvider);
    final created = await repository.createConversation();
    ref.invalidate(conversationsProvider);
    _attach(created.id);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final config = ref.watch(aiConfigProvider);

    // No key configured: the surface does not exist. This is the same state the
    // app is in before the feature was added, which is what keeps "offline by
    // default" a property rather than a claim.
    if (!(config.valueOrNull?.isUsable ?? false)) {
      return _NotConfigured(
        l10n: l10n,
        loading: config.isLoading,
        onOpenSettings: widget.onOpenSettings,
      );
    }

    final conversations = ref.watch(conversationsProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.aiTitle),
        actions: [
          IconButton(
            tooltip: l10n.aiNewConversation,
            icon: const Icon(Icons.add_comment_outlined),
            onPressed: _newConversation,
          ),
          if (_conversationId != null)
            IconButton(
              tooltip: l10n.aiDeleteConversation,
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _confirmDelete(l10n),
            ),
        ],
      ),
      body: conversations.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (list) {
          if (list.isEmpty) {
            return _EmptyConversation(
              l10n: l10n,
              onCreate: _newConversation,
              onOpen: (id) => _attach(id),
            );
          }
          // Default to the newest conversation, which is what a returning user
          // expects, without an extra click.
          if (_conversationId == null ||
              !list.any((c) => c.id == _conversationId)) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                _attach(list.first.id);
              }
            });
          }
          return Row(
            children: [
              if (MediaQuery.of(context).size.width >= 900)
                _ConversationList(
                  conversations: list,
                  selectedId: _conversationId,
                  onSelect: _attach,
                  l10n: l10n,
                ),
              if (MediaQuery.of(context).size.width >= 900)
                const VerticalDivider(width: 1),
              Expanded(child: _buildConversation(l10n, list)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildConversation(
      AppLocalizations l10n, List<AiConversation> conversations) {
    final id = _conversationId;
    if (id == null) {
      return _EmptyConversation(
        l10n: l10n,
        onCreate: _newConversation,
        onOpen: _attach,
      );
    }
    final messages = ref.watch(messagesProvider(id));
    final config = ref.watch(aiConfigProvider).valueOrNull;

    return Column(
      children: [
        if (config?.permissionMode == AiPermissionMode.auto)
          _ModeBanner(l10n: l10n),
        Expanded(
          child: messages.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('$e')),
            data: (rows) => ListView(
              controller: _scroll,
              padding: const EdgeInsets.all(16),
              children: [
                if (rows.isEmpty && _turn.streamingText.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 48),
                    child: Center(
                      child: Text(
                        l10n.aiEmptyHint,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ),
                  ),
                for (final row in rows)
                  if (row.role != AiRepository.roleTool &&
                      row.role != AiRepository.roleSystem)
                    _MessageBubble(row: row),
                if (_turn.streamingText.isNotEmpty)
                  _MessageBubble.streaming(_turn.streamingText),
                for (final call in _turn.executed)
                  _ExecutedTile(
                    call: call,
                    l10n: l10n,
                    onUndo: call.result.isUndoable
                        ? () => _undo(call.actionId)
                        : null,
                  ),
              ],
            ),
          ),
        ),
        if (_turn.error != null) _ErrorBanner(text: _turn.error!),
        if (_turn.hasPending)
          _ApprovalPanel(
            pending: _turn.pending,
            l10n: l10n,
            onApprove: _approve,
            onReject: _reject,
          ),
        if (_turn.generating)
          const LinearProgressIndicator(minHeight: 2),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    minLines: 1,
                    maxLines: 5,
                    textInputAction: TextInputAction.send,
                    enabled: !_turn.generating && !_turn.hasPending,
                    onSubmitted: (_) => _send(),
                    decoration: InputDecoration(
                      hintText: l10n.aiInputHint,
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  tooltip: l10n.aiSend,
                  onPressed: (_turn.generating || _turn.hasPending) ? null : _send,
                  icon: const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _confirmDelete(AppLocalizations l10n) async {
    final id = _conversationId;
    if (id == null) {
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.aiDeleteConversation),
        content: Text(l10n.aiDeleteConversationConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.commonDelete),
          ),
        ],
      ),
    );
    if (ok != true) {
      return;
    }
    _subscription?.cancel();
    await ref.read(aiRepositoryProvider).deleteConversation(id);
    setState(() {
      _conversationId = null;
      _loop = null;
      _turn = const AgentTurnState();
    });
    ref.invalidate(conversationsProvider);
  }
}

/// Shown when no key is configured. Explains why the screen is empty instead of
/// offering a disabled input box.
class _NotConfigured extends StatelessWidget {
  const _NotConfigured({
    required this.l10n,
    required this.loading,
    this.onOpenSettings,
  });

  final AppLocalizations l10n;
  final bool loading;
  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(title: Text(l10n.aiTitle)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.smart_toy_outlined,
                  size: 56, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 16),
              Text(l10n.aiNotConfigured,
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(l10n.aiNotConfiguredHint, textAlign: TextAlign.center),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: onOpenSettings,
                child: Text(l10n.aiGoToSettings),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyConversation extends StatelessWidget {
  const _EmptyConversation({
    required this.l10n,
    required this.onCreate,
    required this.onOpen,
  });

  final AppLocalizations l10n;
  final Future<void> Function() onCreate;
  final void Function(String) onOpen;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.forum_outlined,
              size: 56, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 12),
          Text(l10n.aiEmptyHint, textAlign: TextAlign.center),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: onCreate,
            icon: const Icon(Icons.add),
            label: Text(l10n.aiNewConversation),
          ),
        ],
      ),
    );
  }
}

class _ConversationList extends StatelessWidget {
  const _ConversationList({
    required this.conversations,
    required this.selectedId,
    required this.onSelect,
    required this.l10n,
  });

  final List<AiConversation> conversations;
  final String? selectedId;
  final void Function(String) onSelect;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 240,
      child: ListView(
        children: [
          for (final c in conversations)
            ListTile(
              dense: true,
              selected: c.id == selectedId,
              leading: const Icon(Icons.chat_bubble_outline, size: 18),
              title: Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: () => onSelect(c.id),
            ),
        ],
      ),
    );
  }
}

/// A persistent reminder that writes are happening without per-action consent.
/// The user chose this, so it is a reminder rather than a warning.
class _ModeBanner extends StatelessWidget {
  const _ModeBanner({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            Icon(Icons.bolt, size: 16, color: scheme.onSecondaryContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                l10n.settingsAiPermissionAuto,
                style: TextStyle(fontSize: 12, color: scheme.onSecondaryContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.row})
      : streaming = false,
        _streamText = '';

  const _MessageBubble.streaming(String text)
      : row = null,
        streaming = true,
        _streamText = text;

  final AiMessage? row;
  final bool streaming;
  final String _streamText;

  String get _text => streaming ? _streamText : (row?.content ?? '');
  bool get _isUser => !streaming && row?.role == AiRepository.roleUser;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: _isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: const BoxConstraints(maxWidth: 560),
        decoration: BoxDecoration(
          color: _isUser ? scheme.primaryContainer : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
        ),
        child: SelectableText(_text),
      ),
    );
  }
}

/// One already-executed call, with its undo affordance.
class _ExecutedTile extends StatelessWidget {
  const _ExecutedTile({
    required this.call,
    required this.l10n,
    required this.onUndo,
  });

  final ExecutedCall call;
  final AppLocalizations l10n;
  final VoidCallback? onUndo;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ok = call.result.ok;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        dense: true,
        leading: Icon(
          call.undone
              ? Icons.undo
              : (ok ? Icons.check_circle_outline : Icons.error_outline),
          color: call.undone
              ? scheme.outline
              : (ok ? scheme.primary : scheme.error),
        ),
        title: Text(call.undone ? l10n.aiUndone : call.summary),
        subtitle: Text(
          '${l10n.aiAutoExecuted} · ${call.toolName}',
          style: const TextStyle(fontSize: 11),
        ),
        trailing: (onUndo != null && !call.undone)
            ? TextButton(onPressed: onUndo, child: Text(l10n.aiUndo))
            : null,
      ),
    );
  }
}

/// The batch approval list: what the model wants to do, before it happens.
class _ApprovalPanel extends StatelessWidget {
  const _ApprovalPanel({
    required this.pending,
    required this.l10n,
    required this.onApprove,
    required this.onReject,
  });

  final List<PendingCall> pending;
  final AppLocalizations l10n;
  final Future<void> Function() onApprove;
  final Future<void> Function() onReject;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final needsOwnConfirm =
        pending.where((p) => p.decision.disposition == ToolDisposition.individualApproval);
    return Material(
      color: scheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.aiPendingTitle,
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            for (final item in pending)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Icon(
                      item.decision.risk == ToolRisk.destructive
                          ? Icons.warning_amber
                          : Icons.build_outlined,
                      size: 16,
                      color: item.decision.risk == ToolRisk.destructive
                          ? scheme.error
                          : scheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${item.tool.name} · ${item.title}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (item.decision.disposition ==
                        ToolDisposition.individualApproval)
                      Text(l10n.aiNeedsConfirm,
                          style: TextStyle(fontSize: 11, color: scheme.error)),
                  ],
                ),
              ),
            if (needsOwnConfirm.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  l10n.settingsAiPermissionHint,
                  style: TextStyle(fontSize: 11, color: scheme.outline),
                ),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: onApprove,
                  icon: const Icon(Icons.play_arrow),
                  label: Text(l10n.aiApproveAll),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: onReject,
                  icon: const Icon(Icons.close),
                  label: Text(l10n.aiRejectAll),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Icon(Icons.error_outline, size: 18, color: scheme.onErrorContainer),
            const SizedBox(width: 8),
            Expanded(
              child: SelectableText(
                text,
                style: TextStyle(color: scheme.onErrorContainer, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
