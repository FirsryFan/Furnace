import 'dart:async';
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

  Future<void> _send() async {
    final text = _input.text.trim();
    final loop = _loop;
    final id = _conversationId;
    if ((text.isEmpty && _pendingImages.isEmpty) || loop == null || id == null) {
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
  void _resizeInput(double dy) {
    _dragDistance += dy;
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
    final hasSidebar =
        MediaQuery.sizeOf(context).width >= _sidebarBreakpoint;
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
    // Absolute paths, resolved outside the widget so the bubbles stay
    // synchronous; a conversation whose files are gone simply shows no pictures.
    final imagesByMessage =
        ref.watch(messageImagesProvider(id)).valueOrNull ??
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
                    _MessageBubble(
                      row: row,
                      images: imagesByMessage[row.id] ?? const [],
                    ),
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
                    IconButton.filled(
                      tooltip: l10n.aiSend,
                      onPressed: (_turn.generating ||
                              _turn.hasPending ||
                              _preparingImages)
                          ? null
                          : _send,
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
              title: Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis),
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
