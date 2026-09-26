import 'dart:convert';

import '../domain/model_adapter.dart';

/// Reassembles a streamed chat completion into whole events.
///
/// The awkward part is tool calls. The provider shards them: each fragment
/// carries an `index`, and `function.arguments` must be **concatenated per
/// index**, while `id` and `function.name` usually arrive only on the first
/// fragment (and some providers resend them on every fragment). Getting this
/// wrong produces silently truncated JSON arguments - a tool call that looks
/// fine until it fails to parse - so the rules are explicit here and directly
/// tested.
///
/// Pure logic on purpose: no sockets, no timers. That is what makes the
/// streaming path testable without a network.
class StreamAssembler {
  final Map<int, PartialToolCall> _calls = {};
  final StringBuffer _text = StringBuffer();
  String? _finishReason;
  int? _promptTokens;
  int? _completionTokens;

  /// The assistant text accumulated so far.
  String get text => _text.toString();

  String? get finishReason => _finishReason;
  int? get promptTokens => _promptTokens;
  int? get completionTokens => _completionTokens;

  /// Consumes one decoded SSE chunk and returns the events it completes.
  List<ModelEvent> consume(Map<String, Object?> chunk) {
    final events = <ModelEvent>[];

    final usage = chunk['usage'];
    if (usage is Map) {
      _promptTokens =
          (usage['prompt_tokens'] as num?)?.toInt() ?? _promptTokens;
      _completionTokens =
          (usage['completion_tokens'] as num?)?.toInt() ?? _completionTokens;
    }

    final choices = chunk['choices'];
    if (choices is! List || choices.isEmpty) {
      return events;
    }
    final choice = (choices.first as Map).cast<String, Object?>();
    _finishReason = (choice['finish_reason'] as String?) ?? _finishReason;

    final delta = (choice['delta'] as Map?)?.cast<String, Object?>();
    if (delta == null) {
      return events;
    }

    final content = delta['content'];
    if (content is String && content.isNotEmpty) {
      _text.write(content);
      events.add(ModelTextDelta(content));
    }

    final toolCalls = delta['tool_calls'];
    if (toolCalls is List) {
      for (final raw in toolCalls) {
        if (raw is! Map) {
          continue;
        }
        final map = raw.cast<String, Object?>();
        // A missing index means the provider is not sharding. Falling back to
        // the current call count keeps such providers working instead of
        // collapsing every call into index 0.
        final index = (map['index'] as num?)?.toInt() ?? _calls.length;
        _calls.putIfAbsent(index, () => PartialToolCall(index)).absorb(map);
      }
    }

    return events;
  }

  /// Emits every assembled tool call, then the turn-end event.
  List<ModelEvent> finish() {
    final events = <ModelEvent>[];
    final ordered = _calls.keys.toList()..sort();
    for (final index in ordered) {
      final call = _calls[index]!;
      if (call.name.isEmpty) {
        // A call with no name can be neither executed nor reported back in a
        // way the model can use. Dropping it beats sending an unnamed result.
        continue;
      }
      events.add(ModelToolCall(call.toRequest()));
    }
    events.add(ModelTurnDone(
      finishReason: _finishReason,
      promptTokens: _promptTokens,
      completionTokens: _completionTokens,
    ));
    return events;
  }
}

/// One tool call being assembled from fragments.
class PartialToolCall {
  PartialToolCall(this.index);

  final int index;
  String id = '';
  String name = '';
  final StringBuffer arguments = StringBuffer();

  void absorb(Map<String, Object?> fragment) {
    final idFragment = fragment['id'];
    if (idFragment is String && idFragment.isNotEmpty && id.isEmpty) {
      // Only the first non-empty id wins: providers that resend it on every
      // fragment would otherwise get it concatenated into nonsense.
      id = idFragment;
    }

    final function = (fragment['function'] as Map?)?.cast<String, Object?>();
    if (function == null) {
      return;
    }
    final nameFragment = function['name'];
    if (nameFragment is String && nameFragment.isNotEmpty && name.isEmpty) {
      name = nameFragment;
    }
    final argsFragment = function['arguments'];
    if (argsFragment is String) {
      arguments.write(argsFragment);
    }
  }

  ToolCallRequest toRequest() {
    final raw = arguments.toString();
    Map<String, Object?> parsed = const {};
    String? error;
    if (raw.trim().isEmpty) {
      // Not an error: a no-argument tool legitimately sends `{}` or nothing.
      parsed = const {};
    } else {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          parsed = decoded.cast<String, Object?>();
        } else {
          error = '工具参数不是 JSON 对象';
        }
      } on FormatException catch (e) {
        error = '工具参数不是合法 JSON：${e.message}';
      }
    }
    return ToolCallRequest(
      id: id.isEmpty ? 'call_$index' : id,
      name: name,
      rawArguments: raw,
      arguments: parsed,
      parseError: error,
    );
  }
}
