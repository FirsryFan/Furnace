import 'dart:async';

import '../domain/model_adapter.dart';

/// A scripted model, for tests and for driving the agent loop without a
/// network.
///
/// Why this exists as a first-class adapter rather than a test double: the
/// agent loop, the approval engine and the tool layer are where the interesting
/// behaviour lives, and none of them should require a paid API call to verify.
/// Every one of those gets tested against this.
class FakeModelAdapter implements ModelAdapter {
  FakeModelAdapter(this.turns);

  /// One entry per `runTurn` call, in order. When the calls run out, the last
  /// turn is repeated - an agent loop that overruns is a bug worth surfacing as
  /// repeated output rather than a hang.
  final List<List<ModelEvent>> turns;

  /// Every request the loop made, so a test can assert on what the model was
  /// actually shown (message history, tool list).
  final List<FakeTurnRequest> requests = [];

  int _index = 0;

  @override
  Stream<ModelEvent> runTurn({
    required List<ChatMessage> messages,
    required List<ModelToolSpec> tools,
  }) async* {
    requests.add(FakeTurnRequest(
      messages: List.unmodifiable(messages),
      tools: List.unmodifiable(tools),
    ));
    if (turns.isEmpty) {
      yield const ModelTurnDone(finishReason: 'stop');
      return;
    }
    final turn = turns[_index < turns.length ? _index : turns.length - 1];
    _index++;
    for (final event in turn) {
      yield event;
    }
  }

  /// Convenience for the common "the model just answers" case.
  static List<ModelEvent> answer(String text) => [
        ModelTextDelta(text),
        const ModelTurnDone(finishReason: 'stop'),
      ];

  /// Convenience for "the model asks for one tool call".
  static List<ModelEvent> callTool(
    String name,
    Map<String, Object?> arguments, {
    String id = 'call_1',
    String? say,
  }) =>
      [
        if (say != null) ModelTextDelta(say),
        ModelToolCall(ToolCallRequest(
          id: id,
          name: name,
          rawArguments: _encode(arguments),
          arguments: arguments,
        )),
        const ModelTurnDone(finishReason: 'tool_calls'),
      ];

  /// Convenience for a call whose arguments could not be parsed - the loop must
  /// hand the parse error back to the model rather than crashing.
  static List<ModelEvent> callToolWithBadArguments(
    String name, {
    String raw = '{"action": ',
    String id = 'call_bad',
  }) =>
      [
        ModelToolCall(ToolCallRequest(
          id: id,
          name: name,
          rawArguments: raw,
          arguments: const {},
          parseError: '工具参数不是合法 JSON',
        )),
        const ModelTurnDone(finishReason: 'tool_calls'),
      ];

  static List<ModelEvent> failure(String message, {int? statusCode}) => [
        ModelFailure(message, statusCode: statusCode),
      ];

  static String _encode(Map<String, Object?> arguments) {
    // Minimal encoder: the fake never needs to be byte-identical to the
    // provider, only round-trippable.
    final parts = arguments.entries
        .map((e) => '"${e.key}": ${e.value is String ? '"${e.value}"' : e.value}');
    return '{${parts.join(', ')}}';
  }
}

/// What the loop asked for in one turn.
class FakeTurnRequest {
  const FakeTurnRequest({required this.messages, required this.tools});

  final List<ChatMessage> messages;
  final List<ModelToolSpec> tools;
}
