import 'dart:convert';

/// A tool the model may call, in the shape the provider expects.
///
/// This is only the *declaration* - the provider-facing half. Executing a call
/// is the tool registry's job (`features/ai/domain/ai_tool.dart`), because the
/// registry needs risk levels, reversibility and platform gating that the
/// provider must never see.
class ModelToolSpec {
  const ModelToolSpec({
    required this.name,
    required this.description,
    required this.parameters,
  });

  final String name;
  final String description;

  /// JSON Schema for the arguments. Must be a `type: object` schema with a
  /// `properties` map, because that is what the Chat Completion API accepts.
  final Map<String, Object?> parameters;

  Map<String, Object?> toJson() => {
        'type': 'function',
        'function': {
          'name': name,
          'description': description,
          'parameters': parameters,
        },
      };
}

/// One image attached to a user message, already downscaled and re-encoded.
///
/// The Chat Completion API has no separate upload step: a local image travels
/// inside the request body as a base64 `data:` URL in an `image_url` content
/// part. That is why this carries [base64] rather than a path - by the time the
/// message is built the bytes have to be in the JSON.
class ChatImagePart {
  const ChatImagePart({required this.mime, required this.base64});

  /// `image/png` (what the vision encoder always produces).
  final String mime;

  /// Base64 of the encoded image, without the `data:` prefix.
  final String base64;

  Map<String, Object?> toJson() => {
        'type': 'image_url',
        'image_url': {'url': 'data:$mime;base64,$base64'},
      };
}

/// One message handed to the provider.
class ChatMessage {
  const ChatMessage({
    required this.role,
    this.content,
    this.images = const [],
    this.toolCallId,
    this.toolCalls = const [],
  });

  const ChatMessage.user(String this.content, {this.images = const []})
      : role = 'user',
        toolCallId = null,
        toolCalls = const [];

  const ChatMessage.system(String this.content)
      : role = 'system',
        images = const [],
        toolCallId = null,
        toolCalls = const [];

  /// A tool result being handed back. [toolCallId] must match the id the model
  /// produced, or the provider rejects the request.
  const ChatMessage.tool(String this.content, {required String this.toolCallId})
      : role = 'tool',
        images = const [],
        toolCalls = const [];

  /// An assistant turn: text and/or tool calls.
  const ChatMessage.assistant({this.content, this.toolCalls = const []})
      : role = 'assistant',
        images = const [],
        toolCallId = null;

  /// `system` | `user` | `assistant` | `tool`.
  final String role;
  final String? content;

  /// Images attached to this message. Empty for every message that is not a
  /// user turn carrying a photo, which is what keeps the text-only wire shape
  /// byte-for-byte what it was before images existed.
  final List<ChatImagePart> images;

  final String? toolCallId;
  final List<ToolCallRequest> toolCalls;

  /// The provider's `content` field.
  ///
  /// A message without images sends the plain string - the Chat Completion API
  /// accepts that everywhere, and a text-only turn must not start looking like a
  /// multimodal one. Once images are attached it has to become the part list
  /// (`text` first, then one `image_url` per image), because that is the only
  /// shape that can carry an image.
  Object? get contentParts {
    if (images.isEmpty) {
      return content;
    }
    return <Object?>[
      if (content != null && content!.isNotEmpty)
        {'type': 'text', 'text': content},
      for (final image in images) image.toJson(),
    ];
  }

  Map<String, Object?> toJson() {
    final parts = contentParts;
    return {
      'role': role,
      if (parts != null) 'content': parts,
      if (toolCallId != null) 'tool_call_id': toolCallId,
      if (toolCalls.isNotEmpty)
        'tool_calls': [for (final call in toolCalls) call.toJson()],
    };
  }
}

/// A tool call the model asked for. [arguments] is already decoded; the raw
/// text is kept alongside it so a parse failure can be reported verbatim.
class ToolCallRequest {
  const ToolCallRequest({
    required this.id,
    required this.name,
    required this.rawArguments,
    required this.arguments,
    this.parseError,
  });

  final String id;
  final String name;
  final String rawArguments;
  final Map<String, Object?> arguments;

  /// Non-null when the arguments were not valid JSON. The call is still
  /// reported - the agent loop turns this into a tool result the model can
  /// learn from, instead of throwing away the turn.
  final String? parseError;

  factory ToolCallRequest.fromJson(Map<String, Object?> json) {
    final function = (json['function'] as Map?)?.cast<String, Object?>() ?? {};
    final raw = (function['arguments'] as String?) ?? '';
    Map<String, Object?> parsed = const {};
    String? error;
    if (raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          parsed = decoded.cast<String, Object?>();
        } else {
          error = 'arguments is not a JSON object';
        }
      } on FormatException catch (e) {
        error = 'arguments is not valid JSON: ${e.message}';
      }
    }
    return ToolCallRequest(
      id: (json['id'] as String?) ?? '',
      name: (function['name'] as String?) ?? '',
      rawArguments: raw,
      arguments: parsed,
      parseError: error,
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'type': 'function',
        'function': {'name': name, 'arguments': rawArguments},
      };
}

/// What one round-trip reported about its own token use.
///
/// A separate object from [ModelTurnDone] because "the round finished" and "the
/// round told us what it cost" are different facts: a stream can end without a
/// usage block (an older endpoint, a proxy that strips it, a truncated stream),
/// and a caller has to be able to tell that apart from a genuine zero.
class ModelUsage {
  const ModelUsage({
    required this.promptTokens,
    required this.completionTokens,
    this.cacheHitPromptTokens,
    this.cacheMissPromptTokens,
  });

  /// Total prompt tokens for this round, cache hits included.
  final int promptTokens;

  /// Tokens the model generated in this round.
  final int completionTokens;

  /// DeepSeek-compatible prompt-cache accounting: how much of the prompt was
  /// served from the provider's cache, and how much had to be processed.
  ///
  /// `null` - not `0` - when the endpoint did not report them, because "this
  /// server never tells us" and "nothing was cached" are different answers and
  /// only one of them is a measurement.
  final int? cacheHitPromptTokens;
  final int? cacheMissPromptTokens;
}

/// What a single turn can emit.
///
/// Deliberately `abstract` rather than `sealed`: this union grows additively
/// ([ModelReasoningDelta], [ModelTurnCancelled]) and several services outside
/// this feature also switch over it. A new event has to be ignorable by a
/// consumer that predates it, so the hierarchy stays open; every consumer in
/// this feature still handles each event explicitly.
abstract class ModelEvent {
  const ModelEvent();
}

/// Incremental assistant text - the answer, and the only text that may be
/// persisted as the assistant message's content.
class ModelTextDelta extends ModelEvent {
  const ModelTextDelta(this.text);
  final String text;
}

/// Incremental chain-of-thought / thinking text from a reasoning-capable
/// model (`delta.reasoning_content`, `delta.reasoning`, or a `reasoning` /
/// `thinking` content part).
///
/// A separate channel from [ModelTextDelta] on purpose: thinking is not the
/// answer. It is never written to `AiMessages.content` and never sent back to
/// the provider; the UI may show it, and a consumer that does not care simply
/// ignores this event.
class ModelReasoningDelta extends ModelEvent {
  const ModelReasoningDelta(this.text);

  /// This fragment of reasoning text (not accumulated - the consumer adds it
  /// up if it wants the whole chain).
  final String text;
}

/// A completed tool call the model wants executed. Emitted once the provider
/// has finished streaming that call.
class ModelToolCall extends ModelEvent {
  const ModelToolCall(this.call);
  final ToolCallRequest call;
}

/// The end of the turn.
class ModelTurnDone extends ModelEvent {
  const ModelTurnDone({
    this.finishReason,
    this.promptTokens,
    this.completionTokens,
    this.cacheHitPromptTokens,
    this.cacheMissPromptTokens,
    this.generationDuration,
  });

  final String? finishReason;
  final int? promptTokens;
  final int? completionTokens;

  /// See [ModelUsage.cacheHitPromptTokens].
  final int? cacheHitPromptTokens;

  /// See [ModelUsage.cacheMissPromptTokens].
  final int? cacheMissPromptTokens;

  /// How long the generation itself took, measured by the adapter with a
  /// stopwatch started when the request went out and stopped when the stream
  /// ended.
  ///
  /// Deliberately *not* the length of the model round-trip as the agent loop
  /// sees it: that span also contains history building, the skill-directory
  /// read and tool execution, none of which is generation. Subtracting nothing
  /// and dividing by it would report a rate that depends on how long a tool
  /// happened to run, so the loop prefers this figure and only falls back to its
  /// own stopwatch (over the same span) when an adapter reports none.
  final Duration? generationDuration;

  /// The usage this round reported, or `null` when it reported none.
  ///
  /// Note that [generationDuration] can be present without usage: a round can be
  /// timed without knowing how many tokens it produced.
  ModelUsage? get usage {
    if (promptTokens == null && completionTokens == null) {
      return null;
    }
    return ModelUsage(
      promptTokens: promptTokens ?? 0,
      completionTokens: completionTokens ?? 0,
      cacheHitPromptTokens: cacheHitPromptTokens,
      cacheMissPromptTokens: cacheMissPromptTokens,
    );
  }
}

/// The user interrupted the turn and the adapter has already stopped.
///
/// Emitted at most once per turn, last, and the stream ends immediately after
/// it. [ModelTurnDone] is *not* emitted for a cancelled turn: 「stopped early」
/// and 「finished」 are different facts, and the caller keeps whatever
/// [ModelTextDelta]s it already received - a partial answer is still an
/// answer.
class ModelTurnCancelled extends ModelEvent {
  const ModelTurnCancelled({this.reason});

  /// Why the turn stopped, for display. null when the caller only needs to
  /// know that it stopped.
  final String? reason;
}

/// A recoverable failure. Delivered as an event rather than thrown so the UI
/// can show it inside the conversation instead of losing the turn.
class ModelFailure extends ModelEvent {
  const ModelFailure(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
}

/// Talks to one model provider.
///
/// Implementations must never be reached unless the user configured a key: the
/// whole app is offline by default and this is the ONLY place that opens a
/// socket (docs/AI_DESIGN.md §3 D1).
abstract class ModelAdapter {
  /// Runs one turn. The stream must always terminate, including on failure.
  ///
  /// An adapter that supports interruption additionally implements
  /// [CancellableModelAdapter]; callers stop it through
  /// [ModelAdapterCancellation.cancelActiveTurn] and never by type-checking.
  Stream<ModelEvent> runTurn({
    required List<ChatMessage> messages,
    required List<ModelToolSpec> tools,
  });
}

/// Optional capability: an adapter that can abort the turn in flight.
///
/// Kept as its own interface instead of a member with a default body on
/// [ModelAdapter], because 'implements ModelAdapter' requires every member
/// even when it has a body: adding one there would break every existing
/// implementation and test double for a capability most of them do not have.
/// Empty streams and scripted fakes stay compatible untouched; the agent loop
/// reaches this through [ModelAdapterCancellation.cancelActiveTurn].
abstract interface class CancellableModelAdapter implements ModelAdapter {
  /// Stops the turn currently in flight. Idempotent; a no-op when idle.
  ///
  /// Contract: after this returns, the stream [ModelAdapter.runTurn] handed
  /// out must terminate promptly - normally after a [ModelTurnCancelled]
  /// event - and must never hang waiting for more bytes.
  void cancelActiveTurn();
}

/// The cancellation entry point for any [ModelAdapter].
///
/// A no-op for adapters that do not implement [CancellableModelAdapter], so a
/// caller can always ask an adapter to stop without first checking its
/// concrete type.
extension ModelAdapterCancellation on ModelAdapter {
  void cancelActiveTurn() {
    final self = this;
    if (self is CancellableModelAdapter) {
      self.cancelActiveTurn();
    }
  }
}
