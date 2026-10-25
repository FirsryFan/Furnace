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
/// Two text channels are assembled, never mixed: the answer (text) and the
/// model's thinking (reasoning). Only the answer may become the persisted
/// assistant message; thinking is exposed separately so the UI can show it
/// while it streams and the loop can drop it afterwards.
///
/// Pure logic on purpose: no sockets, no timers. That is what makes the
/// streaming path testable without a network.
class StreamAssembler {
  final Map<int, PartialToolCall> _calls = {};
  final StringBuffer _text = StringBuffer();
  final StringBuffer _reasoning = StringBuffer();
  String? _finishReason;
  int? _promptTokens;
  int? _completionTokens;
  int? _cacheHitPromptTokens;
  int? _cacheMissPromptTokens;

  /// The assistant text (the answer) accumulated so far.
  String get text => _text.toString();

  /// The reasoning / thinking text accumulated so far.
  ///
  /// Empty when the provider sends none, which is the normal case for
  /// non-reasoning models.
  String get reasoning => _reasoning.toString();

  String? get finishReason => _finishReason;
  int? get promptTokens => _promptTokens;
  int? get completionTokens => _completionTokens;
  int? get cacheHitPromptTokens => _cacheHitPromptTokens;
  int? get cacheMissPromptTokens => _cacheMissPromptTokens;

  /// Consumes one decoded SSE chunk and returns the events it completes.
  List<ModelEvent> consume(Map<String, Object?> chunk) {
    final events = <ModelEvent>[];

    final usage = chunk['usage'];
    if (usage is Map) {
      _promptTokens =
          (usage['prompt_tokens'] as num?)?.toInt() ?? _promptTokens;
      _completionTokens =
          (usage['completion_tokens'] as num?)?.toInt() ?? _completionTokens;
      // DeepSeek's cache accounting. Only assigned when the key is actually
      // present: `?? _cacheHitPromptTokens` would be wrong here, because a
      // provider that omits the key must leave the value unknown rather than
      // carry the previous round's number forward as if it were measured.
      final cacheHit = usage['prompt_cache_hit_tokens'];
      if (cacheHit is num) {
        _cacheHitPromptTokens = cacheHit.toInt();
      }
      final cacheMiss = usage['prompt_cache_miss_tokens'];
      if (cacheMiss is num) {
        _cacheMissPromptTokens = cacheMiss.toInt();
      }
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

    // Thinking first: it is generated before the answer, so a consumer that
    // renders both in arrival order gets a sane transcript. A provider that
    // sends neither key leaves this loop empty and the rest byte-identical.
    for (final fragment in _reasoningFragments(delta)) {
      _reasoning.write(fragment);
      events.add(ModelReasoningDelta(fragment));
    }

    final content = delta['content'];
    if (content is String && content.isNotEmpty) {
      _text.write(content);
      events.add(ModelTextDelta(content));
    } else if (content is List) {
      // Some providers send content as an array of typed parts instead of a
      // plain string; previously every part was dropped silently, which lost
      // the whole answer. Reasoning summaries can arrive this way too.
      for (final raw in content) {
        if (raw is! Map) {
          continue;
        }
        final part = raw.cast<String, Object?>();
        final text = _partText(part);
        if (text == null) {
          continue;
        }
        if (_isReasoningPart(part)) {
          _reasoning.write(text);
          events.add(ModelReasoningDelta(text));
        } else {
          _text.write(text);
          events.add(ModelTextDelta(text));
        }
      }
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

  /// The reasoning text carried by one delta, in report order.
  ///
  /// Three shapes are in the wild and a given provider uses one of them:
  /// reasoning_content (DeepSeek), reasoning as a string, and reasoning as an
  /// object with the text under one of a few keys. Typed content parts are
  /// handled where the content itself is read.
  List<String> _reasoningFragments(Map<String, Object?> delta) {
    final fragments = <String>[];
    final direct = delta['reasoning_content'];
    if (direct is String && direct.isNotEmpty) {
      fragments.add(direct);
    }
    final reasoning = delta['reasoning'];
    if (reasoning is String && reasoning.isNotEmpty) {
      fragments.add(reasoning);
    } else if (reasoning is Map) {
      final text = _firstNonEmptyString(
        reasoning.cast<String, Object?>(),
        const ['text', 'reasoning', 'thinking', 'content'],
      );
      if (text != null) {
        fragments.add(text);
      }
    }
    return fragments;
  }

  /// The text of one typed content part, or null when it carries none.
  static String? _partText(Map<String, Object?> part) {
    return _firstNonEmptyString(
      part,
      const ['text', 'content', 'reasoning', 'thinking', 'reasoning_content'],
    );
  }

  /// Part types that carry thinking rather than answer text.
  static const Set<String> _reasoningPartTypes = <String>{
    'reasoning',
    'reasoning_content',
    'thinking',
    'thought',
  };

  static bool _isReasoningPart(Map<String, Object?> part) {
    final type = part['type'];
    if (type is String && _reasoningPartTypes.contains(type)) {
      return true;
    }
    // Untyped summary parts from providers that omit type but carry a
    // dedicated key. A plain text part has neither key, so it is unaffected.
    return part['reasoning_content'] is String ||
        part['thinking'] is String ||
        part['reasoning'] is String;
  }

  static String? _firstNonEmptyString(
    Map<String, Object?> map,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = map[key];
      if (value is String && value.isNotEmpty) {
        return value;
      }
    }
    return null;
  }

  /// Emits every assembled tool call, then the turn-end event.
  ///
  /// [generationDuration] is supplied by the caller rather than measured here,
  /// because this class is pure logic with no clock: the adapter that owns the
  /// socket times the request and hands the figure in.
  List<ModelEvent> finish({Duration? generationDuration}) {
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
      cacheHitPromptTokens: _cacheHitPromptTokens,
      cacheMissPromptTokens: _cacheMissPromptTokens,
      generationDuration: generationDuration,
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
