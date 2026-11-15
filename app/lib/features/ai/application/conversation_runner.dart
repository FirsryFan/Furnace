import 'dart:convert';

import '../../../data/database/database.dart';
import '../../../data/repositories/ai_repository.dart';
import '../domain/agent_preset.dart';
import '../domain/model_adapter.dart';
import '../domain/student_run.dart';
import '../infrastructure/ai_attachment_store.dart';
import 'student_mode_controller.dart';

/// What runs the main-agent preset.
///
/// In the app this is a one-line adapter over the main agent loop; tests supply a spy,
/// which is how "the student preset never calls the main agent" is proved at
/// the routing level instead of by inspecting a database.
abstract interface class StandardAgentRunner {
  Future<void> sendUserMessage({
    required String conversationId,
    required String text,
    List<PendingImage> images,
  });
}

/// The result of routing one user message to its preset.
class ConversationRunResult {
  const ConversationRunResult({
    required this.presets,
    required this.userMessage,
    this.assistantMessage,
    this.studentOutcome,
    this.studentRun,
  });

  /// The preset state of the session after the run. [ConversationPresetState.locked]
  /// is true because the run wrote a message.
  final ConversationPresetState presets;

  final AiMessage userMessage;
  final AiMessage? assistantMessage;

  /// Non-null only when the student preset answered.
  final StudentModeOutcome? studentOutcome;

  /// The student state machine's own result (path, verdict, repair count).
  /// Null for the main-agent preset.
  final StudentRunResult? studentRun;

  bool get usedStudentSolver => studentOutcome != null;
}

/// Routes a user message according to the session's recorded preset.
///
/// DSH semantics this implements (see `docs/AI_PRESETS.md`):
///
///  * the preset is chosen on a **blank** session and is immutable from its
///    first message/run on;
///  * the student preset is a **top-level session preset**, not a tool of the
///    main agent: it runs the isolated `StudentRun` state machine (solve →
///    answer → process audit → content verify → repair ≤ 1 → finalize) and the
///    main agent loop is never constructed for it. The legacy direct
///    `StudentSolver` call remains reachable through
///    `StudentModeController.solve` for compatibility/baseline, but the preset
///    itself uses `StudentModeController.runStudent`;
///  * a subagent preset is fixed when the subagent session is created (recorded
///    on that session), and is recorded next to the agent preset here;
///  * no preset definition/version/hash is persisted - the id alone is stored,
///    and restoring resolves the current definition of the same id.
class ConversationRunner {
  ConversationRunner({
    required AiRepository repository,
    required StandardAgentRunner mainAgent,
    StudentModeController? studentMode,
    AiAttachmentStore? attachments,
  })  : _repository = repository,
        _mainAgent = mainAgent,
        _studentMode = studentMode,
        _attachments = attachments;

  final AiRepository _repository;
  final StandardAgentRunner _mainAgent;

  /// Null when no usable model is configured; a student session without it is a
  /// wiring error and refuses to run rather than silently answering nothing.
  final StudentModeController? _studentMode;

  /// Needed to read (and, for a student turn, register) attached pictures.
  final AiAttachmentStore? _attachments;

  /// Starts a top-level **student-mode session** and solves [question] in it.
  ///
  /// This is the direct student path: the session is created with
  /// [AgentPreset.studentSolver] while blank, and the answer comes from the
  /// isolated `StudentRun` state machine. No main agent loop is constructed, no
  /// tool registry is consulted, and the main agent never sees the question or
  /// the answer.
  Future<ConversationRunResult> startStudentSession({
    required String question,
    List<PendingImage> images = const [],
    SubagentPreset? subagentPreset,
    String? title,
  }) async {
    final conversation = await _repository.createConversation(
      title: title,
      agentPreset: AgentPreset.studentSolver,
      subagentPreset: subagentPreset,
    );
    return _runStudent(conversation, question, images);
  }

  /// Sends one message to an existing session, routed by its preset.
  ///
  /// The preset is read from the session rather than passed by the caller: once
  /// the session has started, changing it is rejected by
  /// [AiRepository.setConversationPresets], so the choice made before the
  /// conversation cannot be silently revised mid-run.
  Future<ConversationRunResult> sendUserMessage({
    required String conversationId,
    required String text,
    List<PendingImage> images = const [],
  }) async {
    final conversation = await _repository.getConversation(conversationId);
    if (conversation == null) {
      throw ArgumentError.value(
        conversationId,
        'conversationId',
        'unknown conversation',
      );
    }
    if (conversation.runsMainAgent) {
      final trimmed = text.trim();
      if (trimmed.isEmpty && images.isEmpty) {
        throw ArgumentError('a message needs text or an image');
      }
      await _mainAgent.sendUserMessage(
        conversationId: conversationId,
        text: text,
        images: images,
      );
      final messages = await _repository.listMessages(conversationId);
      return ConversationRunResult(
        presets: await _presetState(conversation),
        userMessage: messages.lastWhere(
          (message) => message.role == AiRepository.roleUser,
        ),
      );
    }
    return _runStudent(conversation, text, images);
  }

  Future<ConversationRunResult> _runStudent(
    AiConversation conversation,
    String question,
    List<PendingImage> images,
  ) async {
    final trimmed = question.trim();
    if (trimmed.isEmpty && images.isEmpty) {
      throw ArgumentError('a student-mode question needs text or an image');
    }
    final controller = _studentMode;
    if (controller == null) {
      throw StateError(
        'the conversation uses the student preset but no student solver is '
        'configured',
      );
    }
    final store = _attachments;
    if (images.isNotEmpty && store == null) {
      throw StateError(
        'the student preset was given images but no attachment store is '
        'configured',
      );
    }

    // The pictures travel to the solver itself; the user never has to describe
    // the figure in text.
    final parts = <ChatImagePart>[];
    for (final image in images) {
      final bytes = await store!.readBytes(image.relPath);
      if (bytes == null) {
        continue;
      }
      parts.add(ChatImagePart(mime: image.mime, base64: base64Encode(bytes)));
    }

    // Persist the question first: this is what makes the session non-blank and
    // therefore what locks its preset. The main agent's history builder is
    // never called for this conversation.
    final userMessage = await _repository.addMessage(
      conversationId: conversation.id,
      role: AiRepository.roleUser,
      content: trimmed.isEmpty ? null : trimmed,
    );
    if (images.isNotEmpty) {
      await store!.register(userMessage.id, images);
    }

    final outcome = await controller.runStudent(
      question: trimmed,
      images: parts,
      conversationId: conversation.id,
    );
    AiMessage? assistantMessage;
    if (outcome.ok) {
      // The answer sheet, not the raw model text: the session stores exactly
      // what is on the answer sheet (result, option, necessary working).
      assistantMessage = await _repository.addMessage(
        conversationId: conversation.id,
        role: AiRepository.roleAssistant,
        content: outcome.answerSheet.toPlainText(),
      );
    }
    return ConversationRunResult(
      presets: await _presetState(conversation),
      userMessage: userMessage,
      assistantMessage: assistantMessage,
      studentOutcome: outcome,
      studentRun: outcome.studentRun,
    );
  }

  Future<ConversationPresetState> _presetState(
    AiConversation conversation,
  ) async {
    return (await _repository.presetStateFor(conversation.id)) ??
        ConversationPresetState(
          agent: conversation.agentPresetChoice,
          subagent: conversation.subagentPresetChoice,
          locked: true,
        );
  }
}
