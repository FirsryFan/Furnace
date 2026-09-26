import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/features/ai/domain/model_adapter.dart';
import 'package:furnace/features/ai/infrastructure/sse_assembler.dart';

/// Streamed tool calls arrive sharded. If the reassembly rules are wrong the
/// failure is silent - the arguments come out as truncated JSON - so every rule
/// here is pinned by a test rather than verified by hand once.
void main() {
  Map<String, Object?> chunk(Object? delta, {String? finish, Object? usage}) => {
        'choices': [
          {'index': 0, 'delta': delta, 'finish_reason': finish},
        ],
        if (usage != null) 'usage': usage,
      };

  /// The shape DeepSeek/OpenAI actually send for a tool call, sharded.
  List<Map<String, Object?>> shardedToolCallChunks() => [
        chunk({
          'role': 'assistant',
          'content': null,
          'tool_calls': [
            {
              'index': 0,
              'id': 'call_abc',
              'type': 'function',
              'function': {'name': 'manage_task', 'arguments': ''},
            }
          ],
        }),
        chunk({
          'tool_calls': [
            {
              'index': 0,
              'function': {'arguments': '{"act'},
            }
          ],
        }),
        chunk({
          'tool_calls': [
            {
              'index': 0,
              'function': {'arguments': 'ion":"cre'},
            }
          ],
        }),
        chunk({
          'tool_calls': [
            {
              'index': 0,
              'function': {'arguments': 'ate","title":"作业"}'},
            }
          ],
        }),
        chunk(const {}, finish: 'tool_calls'),
      ];

  group('text', () {
    test('deltas are emitted and also accumulated', () {
      final a = StreamAssembler();
      expect(a.consume(chunk({'content': '你'})), hasLength(1));
      a.consume(chunk({'content': '好'}));
      final events = a.consume(chunk({'content': '！'}));
      expect((events.single as ModelTextDelta).text, '！');
      expect(a.text, '你好！');
    });

    test('an empty content fragment emits nothing', () {
      // Providers send `content: ""` alongside tool calls; treating that as a
      // delta would sprinkle empty text events through the UI.
      final a = StreamAssembler();
      expect(a.consume(chunk({'content': ''})), isEmpty);
      expect(a.text, isEmpty);
    });

    test('a null content fragment emits nothing', () {
      final a = StreamAssembler();
      expect(a.consume(chunk({'content': null})), isEmpty);
    });
  });

  group('tool calls', () {
    test('sharded arguments are concatenated into valid JSON', () {
      final a = StreamAssembler();
      for (final c in shardedToolCallChunks()) {
        a.consume(c);
      }
      final events = a.finish();
      final call = events.whereType<ModelToolCall>().single;
      expect(call.call.id, 'call_abc');
      expect(call.call.name, 'manage_task');
      expect(call.call.parseError, isNull);
      expect(call.call.arguments, {'action': 'create', 'title': '作业'});
      // The raw text must be the concatenation, not just the last fragment.
      expect(call.call.rawArguments, '{"action":"create","title":"作业"}');
    });

    test('the turn-end event is always the last event', () {
      final a = StreamAssembler();
      for (final c in shardedToolCallChunks()) {
        a.consume(c);
      }
      final events = a.finish();
      expect(events.last, isA<ModelTurnDone>());
      expect((events.last as ModelTurnDone).finishReason, 'tool_calls');
    });

    test('two parallel calls keep their own arguments', () {
      // The index is what separates them; conflating them would merge two
      // different tasks into one.
      final a = StreamAssembler();
      a.consume(chunk({
        'tool_calls': [
          {
            'index': 0,
            'id': 'c0',
            'function': {'name': 'manage_task', 'arguments': '{"action":"create"}'}
          },
          {
            'index': 1,
            'id': 'c1',
            'function': {'name': 'query_tasks', 'arguments': '{"status":"todo"}'}
          },
        ],
      }));
      final calls =
          a.finish().whereType<ModelToolCall>().map((e) => e.call).toList();
      expect(calls, hasLength(2));
      expect(calls[0].name, 'manage_task');
      expect(calls[0].arguments, {'action': 'create'});
      expect(calls[1].name, 'query_tasks');
      expect(calls[1].arguments, {'status': 'todo'});
    });

    test('calls are emitted in index order even if fragments interleave', () {
      final a = StreamAssembler();
      a.consume(chunk({
        'tool_calls': [
          {'index': 1, 'id': 'c1', 'function': {'name': 'second', 'arguments': '{'}}
        ],
      }));
      a.consume(chunk({
        'tool_calls': [
          {'index': 0, 'id': 'c0', 'function': {'name': 'first', 'arguments': '{'}}
        ],
      }));
      a.consume(chunk({
        'tool_calls': [
          {'index': 1, 'function': {'arguments': '}'}},
        ],
      }));
      a.consume(chunk({
        'tool_calls': [
          {'index': 0, 'function': {'arguments': '}'}},
        ],
      }));
      final names =
          a.finish().whereType<ModelToolCall>().map((e) => e.call.name).toList();
      expect(names, ['first', 'second']);
    });

    test('a repeated id fragment does not get concatenated', () {
      // Some providers resend `id` on every fragment. Appending would produce
      // "call_abccall_abc", which the provider then rejects on the tool result.
      final a = StreamAssembler();
      a.consume(chunk({
        'tool_calls': [
          {'index': 0, 'id': 'call_x', 'function': {'name': 'manage_task', 'arguments': ''}}
        ],
      }));
      a.consume(chunk({
        'tool_calls': [
          {'index': 0, 'id': 'call_x', 'function': {'arguments': '{}'}}
        ],
      }));
      final call = a.finish().whereType<ModelToolCall>().single.call;
      expect(call.id, 'call_x');
      expect(call.arguments, isEmpty);
    });

    test('a repeated name fragment does not get concatenated', () {
      final a = StreamAssembler();
      a.consume(chunk({
        'tool_calls': [
          {'index': 0, 'id': 'c', 'function': {'name': 'manage_task', 'arguments': ''}}
        ],
      }));
      a.consume(chunk({
        'tool_calls': [
          {'index': 0, 'function': {'name': 'manage_task', 'arguments': '{}'}}
        ],
      }));
      expect(a.finish().whereType<ModelToolCall>().single.call.name, 'manage_task');
    });

    test('empty arguments mean a no-argument tool, not an error', () {
      final a = StreamAssembler();
      a.consume(chunk({
        'tool_calls': [
          {'index': 0, 'id': 'c', 'function': {'name': 'list_skills', 'arguments': ''}}
        ],
      }));
      final call = a.finish().whereType<ModelToolCall>().single.call;
      expect(call.parseError, isNull);
      expect(call.arguments, isEmpty);
    });

    test('malformed arguments are reported, not thrown', () {
      // The loop turns this into a tool result so the model can retry. Throwing
      // would lose the whole turn.
      final a = StreamAssembler();
      a.consume(chunk({
        'tool_calls': [
          {'index': 0, 'id': 'c', 'function': {'name': 'manage_task', 'arguments': '{"action": '}}
        ],
      }));
      final call = a.finish().whereType<ModelToolCall>().single.call;
      expect(call.parseError, isNotNull);
      expect(call.rawArguments, '{"action": ');
      expect(call.arguments, isEmpty);
      // The name survives, so the loop can still name the tool in the error.
      expect(call.name, 'manage_task');
    });

    test('arguments that are valid JSON but not an object are reported', () {
      final a = StreamAssembler();
      a.consume(chunk({
        'tool_calls': [
          {'index': 0, 'id': 'c', 'function': {'name': 'x', 'arguments': '[1,2]'}}
        ],
      }));
      expect(a.finish().whereType<ModelToolCall>().single.call.parseError, isNotNull);
    });

    test('a nameless call is dropped rather than reported', () {
      final a = StreamAssembler();
      a.consume(chunk({
        'tool_calls': [
          {'index': 0, 'id': 'c', 'function': {'arguments': '{}'}}
        ],
      }));
      expect(a.finish().whereType<ModelToolCall>(), isEmpty);
    });

    test('a missing index still separates successive calls', () {
      // Defensive: if a provider omits `index`, the fallback must not collapse
      // every call into slot 0.
      final a = StreamAssembler();
      a.consume(chunk({
        'tool_calls': [
          {'id': 'a', 'function': {'name': 'first', 'arguments': '{}'}}
        ],
      }));
      a.consume(chunk({
        'tool_calls': [
          {'id': 'b', 'function': {'name': 'second', 'arguments': '{}'}}
        ],
      }));
      final names =
          a.finish().whereType<ModelToolCall>().map((e) => e.call.name).toList();
      expect(names, ['first', 'second']);
    });
  });

  group('shape tolerance', () {
    test('a chunk with no choices is ignored', () {
      final a = StreamAssembler();
      expect(a.consume(const {}), isEmpty);
      expect(a.consume(const {'choices': []}), isEmpty);
    });

    test('a chunk with no delta is ignored but still records finish_reason', () {
      final a = StreamAssembler();
      expect(a.consume(chunk(null, finish: 'stop')), isEmpty);
      expect((a.finish().last as ModelTurnDone).finishReason, 'stop');
    });

    test('usage is picked up whenever it arrives', () {
      final a = StreamAssembler();
      a.consume(chunk(const {}, usage: const {'prompt_tokens': 12, 'completion_tokens': 7}));
      final done = a.finish().last as ModelTurnDone;
      expect(done.promptTokens, 12);
      expect(done.completionTokens, 7);
    });

    test('finish() on an empty stream still ends the turn', () {
      // The loop relies on this: a stream that produced nothing must not hang.
      final events = StreamAssembler().finish();
      expect(events, hasLength(1));
      expect(events.single, isA<ModelTurnDone>());
    });
  });

  group('request serialisation', () {
    test('a tool spec is wrapped in the OpenAI function shape', () {
      const spec = ModelToolSpec(
        name: 'manage_task',
        description: '创建或修改任务',
        parameters: {
          'type': 'object',
          'properties': {
            'action': {'type': 'string', 'enum': ['create', 'update']},
          },
          'required': ['action'],
        },
      );
      final json = jsonDecode(jsonEncode(spec.toJson())) as Map<String, Object?>;
      expect(json['type'], 'function');
      final function = json['function'] as Map<String, Object?>;
      expect(function['name'], 'manage_task');
      expect(function['description'], '创建或修改任务');
      expect((function['parameters'] as Map)['required'], ['action']);
    });

    test('a tool message carries the tool_call_id and no name field', () {
      const message = ChatMessage.tool('{"ok":true}', toolCallId: 'call_1');
      final json = message.toJson();
      expect(json['role'], 'tool');
      expect(json['tool_call_id'], 'call_1');
      expect(json['content'], '{"ok":true}');
    });

    test('an assistant message with tool calls omits an empty content field', () {
      const message = ChatMessage.assistant(
        toolCalls: [
          ToolCallRequest(
            id: 'call_1',
            name: 'manage_task',
            rawArguments: '{}',
            arguments: {},
          ),
        ],
      );
      final json = message.toJson();
      expect(json.containsKey('content'), isFalse);
      final calls = json['tool_calls'] as List;
      expect((calls.single as Map)['id'], 'call_1');
      expect(((calls.single as Map)['function'] as Map)['name'], 'manage_task');
    });

    test('parsing a tool call from provider JSON tolerates bad arguments', () {
      final call = ToolCallRequest.fromJson({
        'id': 'c1',
        'function': {'name': 'x', 'arguments': 'not json'},
      });
      expect(call.parseError, isNotNull);
      expect(call.rawArguments, 'not json');
    });

    test('parsing a tool call with a JSON array argument reports an error', () {
      final call = ToolCallRequest.fromJson({
        'id': 'c1',
        'function': {'name': 'x', 'arguments': '[1]'},
      });
      expect(call.parseError, isNotNull);
    });
  });
}
