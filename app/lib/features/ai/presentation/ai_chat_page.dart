import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
// Key events and the hardware keyboard state: `material.dart` re-exports the
// text-input enums but not the key classes this page handles.
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:furnace/l10n/app_localizations.dart';

import '../../../data/database/database.dart';
import '../../../data/repositories/ai_repository.dart';
import '../application/ai_providers.dart';
import '../domain/agent_loop.dart';
import 'widgets/turn_usage_panel.dart';
import '../domain/ai_tool.dart';
import '../domain/approval_engine.dart';
import '../domain/vision_payload.dart';
import '../infrastructure/ai_attachment_store.dart';
import 'ai_message_markup.dart';

/// 已落库的 tool 调用记录，按 toolCallId 就能对上持久化的 tool 消息。
///
/// 页面用它做两件事：把历史 `roleTool` 行渲染成结果块（[AiActionRecord] 提供
/// 工具名与撤销条件），以及把同一调用的内存态 [_ExecutedTile] 藏起来——一次调用
/// 只显示一次。未落库的调用不会出现在这里，所以还在跑的 turn 不受影响。
final _conversationActionsProvider =
    FutureProvider.family<List<AiActionRecord>, String>((ref, conversationId) {
  return ref.watch(aiRepositoryProvider).listCommittedActions(conversationId);
});

/// Widget-test anchors for the three controls that only exist because a turn
/// can be watched and stopped. Public so the test and the widgets cannot drift
/// apart; the page itself never has to look them up.
const Key aiReasoningPanelKey = Key('ai-reasoning-panel');
const Key aiStopButtonKey = Key('ai-stop-button');
const Key aiCancelledLabelKey = Key('ai-cancelled-label');

/// One folded reasoning header per history message, keyed by the
/// `ai_messages.id` the text was stored on.
///
/// [aiReasoningPanelKey] is the live turn's panel and disappears with the next
/// turn; this one is built from `AiMessage.reasoning`, so a test can reopen the
/// conversation and still find it.
Key aiHistoryReasoningKey(String messageId) =>
    ValueKey<String>('ai-history-reasoning-$messageId');

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

  /// The three controls a widget test has to find without matching on a
  /// localised label. Public so the test and the widget cannot drift apart.
  static const Key sidebarToggleKey = ValueKey<String>('aiSidebarToggle');
  static const Key sidebarKey = ValueKey<String>('aiConversationSidebar');
  static const Key inputResizeHandleKey =
      ValueKey<String>('aiInputResizeHandle');

  @override
  ConsumerState<AiChatPage> createState() => _AiChatPageState();
}

class _AiChatPageState extends ConsumerState<AiChatPage> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  String? _conversationId;
  AgentLoop? _loop;
  StreamSubscription<AgentTurnState>? _subscription;

  /// What the running/last turn cost. Owned here rather than read from the loop
  /// on every build: the loop clears its usage when the next message starts, and
  /// a panel that blanked out at that moment would be useless as a summary.
  final TurnUsageNotifier _usage = TurnUsageNotifier();
  AgentTurnState _turn = const AgentTurnState();

  /// 刚打开、还没滚动到底的对话 id。
  ///
  /// 打开已有对话时要等消息加载完再滚一次到底（否则长对话从顶部开始），但只滚
  /// 一次：每次 rebuild 都强制跳会把正在翻历史的用户拽回底部。
  String? _pendingInitialScrollConversationId;

  /// Images picked but not yet sent. They are already files on disk (that is
  /// what makes the thumbnail work without holding megabytes in memory); the
  /// database rows only appear once the message they belong to exists.
  final List<PendingImage> _pendingImages = [];

  /// True while a picked photo is being decoded, downscaled and written.
  bool _preparingImages = false;

  /// Below this width the conversation list would squeeze the thread rather than
  /// sit beside it, so it is not offered at all - and neither is the toggle that
  /// shows it, because a button that cannot do anything is worse than no button.
  static const double _sidebarBreakpoint = 900;

  /// Whether the conversation list is expanded.
  ///
  /// Held in the page state, which survives every rebuild this screen causes
  /// (each provider change rebuilds it): collapsing the list and then having it
  /// spring back on the next message would be worse than not offering the
  /// toggle.
  bool _sidebarOpen = true;

  /// Height of the message box in text lines, and the range the drag handle
  /// allows.
  ///
  /// Lines rather than pixels because that is the unit the user sees, and
  /// because [TextField] turns a line count into the right pixel height from the
  /// real text metrics - so the box stays correct at any text scale.
  static const int _minInputLines = 1;
  static const int _maxInputLines = 12;
  static const int _defaultInputLines = 3;
  int _inputLines = _defaultInputLines;

  /// How far a drag has to travel to add or remove one line.
  ///
  /// Approximate on purpose: this only maps pointer travel onto a line count,
  /// while the rendered height comes from the field's own metrics. Being a few
  /// pixels off changes how far the handle must be dragged, never where it ends
  /// up.
  static const double _dragPixelsPerLine = 24;

  /// Line count when the current drag started, and the total distance it has
  /// moved. Measuring the drag from its start (rather than summing per-update
  /// deltas) is what keeps the ends honest: dragging past a limit and back
  /// returns to the limit immediately instead of first paying off an overshoot.
  int _dragStartLines = _defaultInputLines;
  double _dragDistance = 0;

  /// The one encoder the screen uses. Limits live in the class so the size cap
  /// is a property of the feature, not a number sprinkled in the UI.
  static const VisionImageEncoder _encoder = VisionImageEncoder();

  @override
  void dispose() {
    _subscription?.cancel();
    _input.dispose();
    _scroll.dispose();
    _usage.dispose();
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
    // 消息加载完后滚到底一次（新对话与打开已有对话同一条路径）。
    _pendingInitialScrollConversationId = conversationId;
    final loop = ref.read(agentLoopProvider(conversationId));
    _loop = loop;
    _turn = loop?.state ?? const AgentTurnState();
    _subscription = loop?.states.listen((state) {
      if (mounted) {
        setState(() => _turn = state);
        _scrollToEnd();
      }
    });
    _usage.attach(states: loop?.states, initial: _turn);
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

  /// 对话第一次有消息时滚到底，且只做一次。
  ///
  /// 流式回复与提交新消息走 [_scrollToEnd]；这里是「打开一个已有对话」的入口：
  /// 没有它，长对话从顶部开始，用户得自己翻到今天。只在下一次仍然指向同一个对话
  /// 时生效，然后立刻清掉标记，所以后续 rebuild（侧栏开关、provider 变化）不会把
  /// 正在看历史的用户拽回底部。
  void _scheduleInitialScroll(String conversationId) {
    if (_pendingInitialScrollConversationId != conversationId) {
      return;
    }
    _pendingInitialScrollConversationId = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _conversationId != conversationId) {
        return;
      }
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    final loop = _loop;
    final id = _conversationId;
    if ((text.isEmpty && _pendingImages.isEmpty) ||
        loop == null ||
        id == null) {
      return;
    }
    if (_turn.generating || _turn.hasPending || _preparingImages) {
      // The send button is disabled in these states, and the keyboard has to be
      // refused for the same reason rather than trusting the disabled widget:
      // the loop drops a message sent while it is busy, and by then `_input` has
      // already been cleared below - the user's text would vanish unsent.
      return;
    }
    final images = List<PendingImage>.from(_pendingImages);
    _input.clear();
    // The loop registers the images against the message it is about to write, so
    // they are persisted before the model is asked anything. They stay in the
    // strip until that has happened: if the send is refused, the user still has
    // them and can try again instead of hunting for the file twice.
    await loop.sendUserMessage(conversationId: id, text: text, images: images);
    if (mounted) {
      setState(_pendingImages.clear);
    }
    _invalidateConversation(id);
  }

  /// Stops the turn in flight.
  ///
  /// The loop keeps whatever answer text already arrived (the streaming bubble
  /// goes on showing it) and flags the state as cancelled, which is how the
  /// page says "stopped" instead of pretending the answer is complete. Safe to
  /// call twice: a cancel is idempotent in the loop, and a turn waiting for
  /// approval is dropped by the same call.
  void _stop() => _loop?.cancel();

  /// Picks one or more images, downscales them, and stages them for the next
  /// message.
  ///
  /// Failures are answered per image instead of aborting the batch: one
  /// unsupported file must not throw away the three good ones next to it.
  Future<void> _pickImages() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final store = ref.read(aiAttachmentStoreProvider);
    try {
      final picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['png', 'jpg', 'jpeg', 'webp', 'gif'],
      );
      if (picked.isEmpty) {
        return;
      }
      setState(() => _preparingImages = true);
      for (final file in picked) {
        final result = await _encoder.encode(await file.readAsBytes());
        switch (result) {
          case VisionImageRejected(:final code):
            messenger.showSnackBar(
              SnackBar(content: Text(aiImageFailureText(l10n, code))),
            );
          case VisionImageReady():
            final saved = await store.save(result);
            if (!mounted) {
              return;
            }
            setState(() => _pendingImages.add(saved));
        }
      }
    } catch (error) {
      // A picker that cannot open (missing platform implementation, revoked
      // permission) must say so rather than leaving the button dead.
      messenger.showSnackBar(
        SnackBar(content: Text('${l10n.aiAttachImage}: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _preparingImages = false);
      }
    }
  }

  /// Drops a staged image, file included - nothing references it yet, and an
  /// unregistered file would never be cleaned up by anything else.
  void _removePending(PendingImage image) {
    setState(() => _pendingImages.remove(image));
    unawaited(ref.read(aiAttachmentStoreProvider).deleteFiles([image.relPath]));
  }

  void _invalidateConversation(String id) {
    ref.invalidate(messagesProvider(id));
    ref.invalidate(messageImagesProvider(id));
    // 历史 tool 行靠这张表显示工具名与撤销：每次 turn 提交/撤销都会变。
    ref.invalidate(_conversationActionsProvider(id));
  }

  /// Which key sends and which one breaks the line.
  ///
  /// **Enter sends; Shift+Enter and Ctrl+Enter insert a line break.** That keeps
  /// the one-keystroke send the box already had, and makes an explicit line
  /// break possible at all - the old field allowed five lines but offered no way
  /// to ask for one. The send button stays where it was, so sending never
  /// requires the keyboard.
  ///
  /// The combination is decided here rather than left to the platform's
  /// text-input action, because that action is a single "done" result: it cannot
  /// tell Shift+Enter from Enter, and on desktop embedders it is the engine, not
  /// this widget, that produces it. `TextInputAction.send` is still set on the
  /// field, so the engine's own path arrives at the same [_send].
  KeyEventResult _onInputKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key != LogicalKeyboardKey.enter &&
        key != LogicalKeyboardKey.numpadEnter) {
      return KeyEventResult.ignored;
    }
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isShiftPressed || keyboard.isControlPressed) {
      _insertLineBreak();
    } else {
      _send();
    }
    return KeyEventResult.handled;
  }

  /// Inserts a newline at the caret, leaving the caret after it.
  ///
  /// Written into the controller instead of leaving the key unhandled and hoping
  /// the platform inserts the character: a widget test has no platform
  /// text-input bridge at all, and "it breaks the line on most machines" is a
  /// worse contract than one that always does.
  void _insertLineBreak() {
    final value = _input.value;
    final text = value.text;
    final selection = value.selection;
    // A field that has never been focused has no valid selection; appending is
    // the only sensible place then.
    final start = selection.isValid ? selection.start : text.length;
    final end = selection.isValid ? selection.end : text.length;
    _input.value = value.copyWith(
      text: text.replaceRange(start, end, '\n'),
      selection: TextSelection.collapsed(offset: start + 1),
      composing: TextRange.empty,
    );
  }

  /// Remembers the height a drag starts from.
  void _resizeInputStart() {
    _dragStartLines = _inputLines;
    _dragDistance = 0;
  }

  /// Resizes the message box: one line per [_dragPixelsPerLine] dragged.
  ///
  /// Dragging **up** grows the box (`dy` is negative then), which is the direction
  /// the handle points; dragging down shrinks it. A pure sum is kept in
  /// [_dragDistance] so passing a limit and coming back returns at once.
  void _resizeInput(double dy) {
    _dragDistance -= dy;
    // Truncation toward zero gives the same feel up and down, and the limits
    // clamp rather than wrap: a drag that runs past the maximum simply stops,
    // and reversing it comes back at once.
    final moved = (_dragDistance / _dragPixelsPerLine).truncate();
    final target =
        (_dragStartLines + moved).clamp(_minInputLines, _maxInputLines);
    if (target != _inputLines) {
      setState(() => _inputLines = target);
    }
  }

  void _toggleSidebar() => setState(() => _sidebarOpen = !_sidebarOpen);

  Future<void> _approve() async {
    final loop = _loop;
    final id = _conversationId;
    if (loop == null || id == null) {
      return;
    }
    await loop.approvePending(id);
    _invalidateConversation(id);
  }

  Future<void> _reject() async {
    final loop = _loop;
    final id = _conversationId;
    if (loop == null || id == null) {
      return;
    }
    await loop.rejectPending(id);
    _invalidateConversation(id);
  }

  Future<void> _undo(String actionId) async {
    final loop = _loop;
    final id = _conversationId;
    if (loop == null || id == null) {
      return;
    }
    await loop.undoExecuted(id, actionId);
    // Undoing changes user data, so the screens that show it must reload.
    _invalidateConversation(id);
  }

  /// 历史 tool 行的撤销回调：只有执行成功且带快照的调用才真的能撤。
  ///
  /// 还在内存里的调用由 [_ExecutedTile] 提供撤销；这一条服务的是重新打开页面后
  /// 从数据库读回来的调用——它们不在 [AgentLoop] 的内存状态里，所以实际执行依赖
  /// loop 能按数据库记录撤销（见 agent_loop.dart 的 undoExecuted）。
  VoidCallback? _undoFor(AiActionRecord? action) {
    if (action == null ||
        action.status != AiRepository.statusExecuted ||
        (action.beforeJson == null && action.afterJson == null)) {
      return null;
    }
    return () => _undo(action.id);
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
    // Resolved once, here, so the toggle and the list it controls can never
    // disagree about whether the list is offered at this width.
    final hasSidebar = MediaQuery.sizeOf(context).width >= _sidebarBreakpoint;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.aiTitle),
        actions: [
          if (hasSidebar)
            IconButton(
              key: AiChatPage.sidebarToggleKey,
              tooltip: _sidebarOpen
                  ? l10n.aiHideConversationList
                  : l10n.aiShowConversationList,
              icon: Icon(_sidebarOpen
                  ? Icons.vertical_split
                  : Icons.vertical_split_outlined),
              onPressed: _toggleSidebar,
            ),
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
              if (hasSidebar)
                AnimatedSize(
                  // The space is animated rather than the list itself: the list
                  // is swapped in and out (a hidden list must not keep
                  // rebuilding), and this makes the swap read as a slide.
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeInOut,
                  alignment: Alignment.centerLeft,
                  child: _sidebarOpen
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _ConversationList(
                              key: AiChatPage.sidebarKey,
                              conversations: list,
                              selectedId: _conversationId,
                              onSelect: _attach,
                              l10n: l10n,
                            ),
                            const VerticalDivider(width: 1),
                          ],
                        )
                      : const SizedBox(width: 0),
                ),
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
    // 已落库的工具调用：历史 tool 行靠它对上工具名/撤销，并与内存态去重。
    final actions = ref.watch(_conversationActionsProvider(id));
    // Absolute paths, resolved outside the widget so the bubbles stay
    // synchronous; a conversation whose files are gone simply shows no pictures.
    final imagesByMessage = ref.watch(messageImagesProvider(id)).valueOrNull ??
        const <String, List<AiMessageImage>>{};
    final config = ref.watch(aiConfigProvider).valueOrNull;

    return Column(
      children: [
        if (config?.permissionMode == AiPermissionMode.auto)
          _ModeBanner(l10n: l10n),
        Expanded(
          child: messages.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('$e')),
            data: (rows) {
              // 消息到了才滚：这一步必须发生在第一帧布局之后，见方法注释。
              _scheduleInitialScroll(id);
              final actionsByToolCall = <String, AiActionRecord>{
                for (final action
                    in actions.valueOrNull ?? const <AiActionRecord>[])
                  if (action.toolCallId != null &&
                      action.toolCallId!.isNotEmpty)
                    action.toolCallId!: action,
              };
              // 同一个调用只显示一次：已落库的 tool 行已经能显示结果，内存态就藏起来。
              final persistedCallIds = <String>{
                for (final row in rows)
                  if (row.role == AiRepository.roleTool &&
                      row.toolCallId != null)
                    row.toolCallId!,
              };
              final persistedActionIds = <String>{
                for (final action in actionsByToolCall.values)
                  if (persistedCallIds.contains(action.toolCallId)) action.id,
              };
              // A stopped turn's partial answer is kept in `streamingText` by
              // the loop *and* written to the database, so the reloaded history
              // would show the same text twice. The streaming bubble already
              // renders it; hide that one echo until the next turn resets the
              // state.
              String? cancelledEchoId;
              if (_turn.cancelled && _turn.streamingText.isNotEmpty) {
                for (final row in rows.reversed) {
                  if (row.role == AiRepository.roleAssistant &&
                      row.content == _turn.streamingText) {
                    cancelledEchoId = row.id;
                    break;
                  }
                }
              }
              // v39 起思考过程随助手消息一起落库：一轮结束后 reload 回来的
              // 历史行已经自带折叠块，流式面板再画一次就会出现两个「思考过程」。
              // 同一段思考已经在历史里时，只保留历史行里的那个。
              final streamingReasoning = _turn.reasoningText.trim();
              final streamingReasoningPersisted =
                  streamingReasoning.isNotEmpty &&
                      rows.any((row) =>
                          row.role == AiRepository.roleAssistant &&
                          (row.reasoning?.trim() ?? '') == streamingReasoning);
              return ListView(
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
                    if (row.role == AiRepository.roleTool)
                      _ToolResultTile(
                        row: row,
                        l10n: l10n,
                        action: actionsByToolCall[row.toolCallId],
                        onUndo: _undoFor(actionsByToolCall[row.toolCallId]),
                      )
                    else if (row.role != AiRepository.roleSystem &&
                        row.id != cancelledEchoId)
                      _MessageBubble(
                        row: row,
                        images: imagesByMessage[row.id] ?? const [],
                      ),
                  // The thinking comes before the answer it produced. It is not
                  // part of the history: the loop resets it when the next turn
                  // starts, so nothing here is cached by the page.
                  if (streamingReasoning.isNotEmpty &&
                      !streamingReasoningPersisted)
                    _ReasoningPanel(
                      text: _turn.reasoningText,
                      generating: _turn.generating,
                      l10n: l10n,
                    ),
                  if (_turn.streamingText.isNotEmpty)
                    _MessageBubble.streaming(_turn.streamingText),
                  for (final call in _turn.executed)
                    if (!persistedActionIds.contains(call.actionId))
                      _ExecutedTile(
                        call: call,
                        l10n: l10n,
                        onUndo: call.result.isUndoable
                            ? () => _undo(call.actionId)
                            : null,
                      ),
                  if (_turn.cancelled) _CancelledLabel(l10n: l10n),
                ],
              );
            },
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
        if (_turn.generating) const LinearProgressIndicator(minHeight: 2),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_pendingImages.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final image in _pendingImages)
                          _StagedImage(
                            image: image,
                            removeLabel: l10n.aiRemoveImage,
                            onRemove: () => _removePending(image),
                          ),
                      ],
                    ),
                  ),
                // The drag handle, and the one place the key behaviour is
                // documented for the user: which key sends and which breaks the
                // line is a convention, and a convention nobody can see is a
                // support question.
                Row(
                  children: [
                    Expanded(
                      child: _InputResizeHandle(
                        key: AiChatPage.inputResizeHandleKey,
                        tooltip: l10n.aiInputResizeHandle,
                        onDragStart: _resizeInputStart,
                        onDragUpdate: _resizeInput,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        l10n.aiInputKeyHint,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).colorScheme.outline,
                        ),
                      ),
                    ),
                  ],
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    IconButton(
                      tooltip: l10n.aiAttachImage,
                      onPressed: (_turn.generating ||
                              _turn.hasPending ||
                              _preparingImages)
                          ? null
                          : _pickImages,
                      icon: _preparingImages
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.add_photo_alternate_outlined),
                    ),
                    Expanded(
                      child: Focus(
                        // Sits above the field in the focus chain, so it decides
                        // Enter and Shift+Enter before any platform default.
                        onKeyEvent: _onInputKey,
                        child: TextField(
                          controller: _input,
                          // minLines == maxLines: the box keeps the height the
                          // user chose with the handle above, and scrolls inside
                          // itself once the text needs more room, instead of
                          // growing and pushing the conversation away.
                          minLines: _inputLines,
                          maxLines: _inputLines,
                          keyboardType: TextInputType.multiline,
                          // The engine's own "send" for the Enter key, so the
                          // desktop text-input path and [_onInputKey] agree.
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
                    ),
                    const SizedBox(width: 8),
                    // One slot, two meanings: while a turn is in flight (or
                    // waiting for approval) stopping it is the useful action,
                    // and a disabled send button would leave the user no way
                    // out. A pending batch is dropped by the same cancel.
                    if (_turn.generating || _turn.hasPending)
                      IconButton.filled(
                        key: aiStopButtonKey,
                        tooltip: l10n.aiStopTooltip,
                        onPressed: _stop,
                        icon: const Icon(Icons.stop),
                      )
                    else
                      IconButton.filled(
                        tooltip: l10n.aiSend,
                        onPressed: _preparingImages ? null : _send,
                        icon: const Icon(Icons.send),
                      ),
                  ],
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
    // Files before rows: the paths are read from the rows the delete removes.
    await ref.read(aiAttachmentStoreProvider).deleteConversationFiles(id);
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
    super.key,
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
              title:
                  Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: () => onSelect(c.id),
            ),
        ],
      ),
    );
  }
}

/// The drag strip above the message box.
///
/// It carries its own gesture recognizer and sits outside the message list, so a
/// vertical drag here resizes the box and can never be read as a scroll of the
/// conversation - which is the whole reason it is a separate widget instead of a
/// decoration inside the field.
///
/// The *whole* strip is the target, not only the pill: a four-pixel line is a
/// poor thing to ask a mouse to hit. The line count needs no label here - the
/// box itself shows it by changing height - so the handle explains itself with a
/// tooltip and a resize cursor.
class _InputResizeHandle extends StatelessWidget {
  const _InputResizeHandle({
    super.key,
    required this.tooltip,
    required this.onDragStart,
    required this.onDragUpdate,
  });

  final String tooltip;
  final VoidCallback onDragStart;
  final ValueChanged<double> onDragUpdate;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeUpDown,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragStart: (_) => onDragStart(),
          onVerticalDragUpdate: (details) => onDragUpdate(details.delta.dy),
          child: SizedBox(
            height: 14,
            child: Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: scheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
        ),
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
                style:
                    TextStyle(fontSize: 12, color: scheme.onSecondaryContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The model's thinking, rendered live above the answer it produces.
///
/// Expanded while the turn runs (that is the interesting part to watch), then
/// folded away once the answer arrives so the answer keeps the visual weight.
/// The user can reopen it; the next turn clears the state, so nothing here is
/// history.
class _ReasoningPanel extends StatefulWidget {
  const _ReasoningPanel({
    required this.text,
    required this.generating,
    required this.l10n,
  });

  final String text;
  final bool generating;
  final AppLocalizations l10n;

  @override
  State<_ReasoningPanel> createState() => _ReasoningPanelState();
}

class _ReasoningPanelState extends State<_ReasoningPanel> {
  late bool _expanded = widget.generating;

  @override
  void didUpdateWidget(covariant _ReasoningPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Fold the moment the turn ends, even if the user had collapsed it while
    // it was still thinking: an answer has arrived and the thinking is no
    // longer what they are reading.
    if (oldWidget.generating && !widget.generating) {
      setState(() => _expanded = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = widget.l10n;
    final expanded = _expanded;
    return Padding(
      key: aiReasoningPanelKey,
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: () => setState(() => _expanded = !expanded),
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.psychology_outlined,
                      size: 16,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      l10n.aiReasoningTitle,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (widget.generating) ...[
                      const SizedBox(width: 8),
                      Text(
                        l10n.aiReasoningGenerating,
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontSize: 11,
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ],
                    const Spacer(),
                    Icon(
                      expanded ? Icons.expand_less : Icons.expand_more,
                      size: 18,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
            if (expanded)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                child: SelectableText(
                  widget.text,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The model's thinking that was persisted **with an assistant message**.
///
/// Unlike [_ReasoningPanel], which only exists for the turn that is generating,
/// this block is rebuilt from `AiMessage.reasoning` every time the conversation
/// is opened. It is folded by default — after a reload the answer is what the
/// user came back for — and each message remembers its own fold state.
class _HistoryReasoningBlock extends StatefulWidget {
  const _HistoryReasoningBlock({
    required this.messageId,
    required this.text,
    required this.l10n,
  });

  /// `ai_messages.id` this thinking belongs to; the header key is built from it
  /// so the test can address one copy in a list of many.
  final String messageId;

  /// Non-empty, trimmed text. Callers filter NULL / blank reasoning out before
  /// building this widget.
  final String text;

  final AppLocalizations l10n;

  @override
  State<_HistoryReasoningBlock> createState() => _HistoryReasoningBlockState();
}

class _HistoryReasoningBlockState extends State<_HistoryReasoningBlock> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              key: aiHistoryReasoningKey(widget.messageId),
              onTap: () => setState(() => _expanded = !_expanded),
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    Icon(
                      Icons.psychology_outlined,
                      size: 16,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      widget.l10n.aiReasoningTitle,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const Spacer(),
                    // 历史消息没有「生成中」状态，箭头就是唯一的展开提示。
                    Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more,
                      size: 18,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
            if (_expanded)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                child: SelectableText(
                  widget.text,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A quiet "stopped" note under a cancelled answer.
///
/// Deliberately not an error: the user stopped it on purpose and the partial
/// answer above is still worth reading, so this is a neutral marker instead of
/// [_ErrorBanner].
class _CancelledLabel extends StatelessWidget {
  const _CancelledLabel({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      key: aiCancelledLabelKey,
      padding: const EdgeInsets.fromLTRB(4, 2, 0, 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.stop_circle_outlined,
              size: 14,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(width: 6),
            Text(
              l10n.aiCancelledLabel,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.row, this.images = const []})
      : streaming = false,
        _streamText = '';

  const _MessageBubble.streaming(String text)
      : row = null,
        images = const [],
        streaming = true,
        _streamText = text;

  final AiMessage? row;

  /// Images stored for this message, if any. Empty for every text-only turn.
  final List<AiMessageImage> images;

  final bool streaming;
  final String _streamText;

  String get _text => streaming ? _streamText : (row?.content ?? '');
  bool get _isUser => !streaming && row?.role == AiRepository.roleUser;

  /// The chain of thought persisted with this row, or null when there is
  /// nothing worth folding. A streaming bubble never shows this: its thinking
  /// lives in the live panel, and the loop writes it to the database when the
  /// turn ends.
  String? get _historyReasoning {
    if (streaming) {
      return null;
    }
    final reasoning = row?.reasoning;
    if (reasoning == null || reasoning.trim().isEmpty) {
      return null;
    }
    return reasoning.trim();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final historyReasoning = _historyReasoning;
    return Align(
      alignment: _isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: const BoxConstraints(maxWidth: 560),
        decoration: BoxDecoration(
          color: _isUser
              ? scheme.primaryContainer
              : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // History keeps the model's thinking, folded: it sits above the
            // answer that it produced, exactly where the live panel was.
            if (historyReasoning != null)
              _HistoryReasoningBlock(
                messageId: row!.id,
                text: historyReasoning,
                l10n: AppLocalizations.of(context),
              ),
            // The picture itself, never a text rendering of its bytes: the
            // stored message holds the prompt text only.
            if (images.isNotEmpty)
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final image in images) _MessageImage(image: image),
                ],
              ),
            if (_text.isNotEmpty) AiMessageBody(text: _text, isUser: _isUser),
          ],
        ),
      ),
    );
  }
}

/// One image inside a message bubble; tapping it opens it large enough to read.
class _MessageImage extends StatelessWidget {
  const _MessageImage({required this.image});

  final AiMessageImage image;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => showDialog<void>(
        context: context,
        builder: (context) => Dialog(
          child: InteractiveViewer(
            maxScale: 8,
            child: Image.file(File(image.absolutePath)),
          ),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.file(
          File(image.absolutePath),
          width: 160,
          height: 160,
          fit: BoxFit.cover,
        ),
      ),
    );
  }
}

/// A picked image waiting to be sent, with its remove affordance.
class _StagedImage extends StatelessWidget {
  const _StagedImage({
    required this.image,
    required this.removeLabel,
    required this.onRemove,
  });

  final PendingImage image;
  final String removeLabel;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 72,
      height: 72,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.file(File(image.absolutePath), fit: BoxFit.cover),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: IconButton(
              tooltip: removeLabel,
              iconSize: 18,
              visualDensity: VisualDensity.compact,
              onPressed: onRemove,
              icon: const Icon(Icons.cancel),
            ),
          ),
        ],
      ),
    );
  }
}

/// The user-facing text for an image the encoder refused.
///
/// Kept next to the screen that shows it: the encoder detects the failure, but
/// it is a domain object and deliberately knows nothing about localisation.
String aiImageFailureText(AppLocalizations l10n, ImageFailureCode code) =>
    switch (code) {
      ImageFailureCode.tooLarge => l10n.aiImageTooLarge,
      ImageFailureCode.unreadable => l10n.aiImageUnreadable,
    };

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

/// One tool call that is already written into the conversation, as a result block.
///
/// Before this existed, reopening a conversation dropped every `roleTool` row on
/// the floor (the list skipped them and only in-memory [_ExecutedTile]s were
/// shown), so a turn looked as if the model had answered without doing anything.
/// The payload is the same JSON the loop gave the model: `summary`, `ok`,
/// `error`, and the full result under `result`. The summary is shown at all
/// times, the raw payload only on request, because a result can be huge.
class _ToolResultTile extends StatefulWidget {
  const _ToolResultTile({
    required this.row,
    required this.l10n,
    required this.onUndo,
    this.action,
  });

  final AiMessage row;
  final AppLocalizations l10n;
  final AiActionRecord? action;
  final VoidCallback? onUndo;

  @override
  State<_ToolResultTile> createState() => _ToolResultTileState();
}

class _ToolResultTileState extends State<_ToolResultTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    final scheme = Theme.of(context).colorScheme;
    final payload = _ToolResultPayload.parse(widget.row.content);
    // Rejected after the fact means the user undid it; the original tool payload
    // still says ok, so the action status is the only place that knows.
    final undone = widget.action?.status == AiRepository.statusRejected;
    final failed = !undone && payload.ok == false;
    final title = undone
        ? l10n.aiUndone
        : ((failed ? (payload.error ?? payload.summary) : payload.summary) ??
            payload.raw.split('\n').first);
    final toolName = widget.action?.toolName;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => _expanded = !_expanded),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    undone
                        ? Icons.undo
                        : (failed
                            ? Icons.error_outline
                            : Icons.check_circle_outline),
                    size: 20,
                    color: undone
                        ? scheme.outline
                        : (failed ? scheme.error : scheme.primary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title.isEmpty ? l10n.aiAutoExecuted : title,
                          style: TextStyle(
                            color: failed ? scheme.error : null,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          toolName == null
                              ? l10n.aiAutoExecuted
                              : '${l10n.aiAutoExecuted} · $toolName',
                          style: const TextStyle(fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  if (widget.onUndo != null && !undone)
                    TextButton(
                      onPressed: widget.onUndo,
                      child: Text(l10n.aiUndo),
                    )
                  else
                    Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more,
                      size: 20,
                      color: scheme.outline,
                    ),
                ],
              ),
              if (_expanded) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: SelectableText(
                    payload.raw,
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The decoded contents of a persisted `tool` message.
///
/// The loop writes [ToolResult.toModelJson], so a row normally looks like
/// `{"ok":true,"summary":"…","result":…}`. Anything else (an older row, a tool
/// that returned a non-JSON string) is still shown raw instead of hidden.
class _ToolResultPayload {
  const _ToolResultPayload({
    required this.raw,
    this.ok,
    this.summary,
    this.error,
  });

  final String raw;
  final bool? ok;
  final String? summary;
  final String? error;

  static _ToolResultPayload parse(String? content) {
    final raw = content ?? '';
    if (raw.isEmpty) {
      return const _ToolResultPayload(raw: '');
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        final ok = decoded['ok'];
        final summary = decoded['summary'];
        final error = decoded['error'];
        return _ToolResultPayload(
          raw: raw,
          ok: ok is bool ? ok : null,
          summary:
              summary is String && summary.trim().isNotEmpty ? summary : null,
          error: error is String && error.trim().isNotEmpty ? error : null,
        );
      }
    } on FormatException {
      // Not JSON: fall through and show the text as-is.
    }
    return _ToolResultPayload(raw: raw);
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
    final needsOwnConfirm = pending.where(
        (p) => p.decision.disposition == ToolDisposition.individualApproval);
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
