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

/// One message handed to the provider.
class ChatMessage {
  const ChatMessage({
    required this.role,
    this.content,
    this.toolCallId,
    this.toolCalls = const [],
  });

  const ChatMessage.user(String this.content)
      : role = 'user',
        toolCallId = null,
        toolCalls = const [];

  const ChatMessage.system(String this.content)
      : role = 'system',
        toolCallId = null,
        toolCalls = const [];

  /// A tool result being handed back. [toolCallId] must match the id the model
  /// produced, or the provider rejects the request.
  const ChatMessage.tool(String this.content, {required String this.toolCallId})
      : role = 'tool',
        toolCalls = const [];

  /// An assistant turn: text and/or tool calls.
  const ChatMessage.assistant({this.content, this.toolCalls = const []})
      : role = 'assistant',
        toolCallId = null;

  /// `system` | `user` | `assistant` | `tool`.
  final String role;
  final String? content;
  final String? toolCallId;
  final List<ToolCallRequest> toolCalls;

  Map<String, Object?> toJson() => {
        'role': role,
        if (content != null) 'content': content,
        if (toolCallId != null) 'tool_call_id': toolCallId,
        if (toolCalls.isNotEmpty)
          'tool_calls': [for (final call in toolCalls) call.toJson()],
      };
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

/// What a single turn can emit.
sealed class ModelEvent {
  const ModelEvent();
}

/// Incremental assistant text.
class ModelTextDelta extends ModelEvent {
  const ModelTextDelta(this.text);
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
  const ModelTurnDone({this.finishReason, this.promptTokens, this.completionTokens});

  final String? finishReason;
  final int? promptTokens;
  final int? completionTokens;
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
  Stream<ModelEvent> runTurn({
    required List<ChatMessage> messages,
    required List<ModelToolSpec> tools,
  });
}
