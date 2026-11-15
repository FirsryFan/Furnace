import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/features/ai/domain/model_adapter.dart';
import 'package:furnace/features/ai/infrastructure/openai_compat_adapter.dart';

/// What the adapter actually puts on the wire.
///
/// The parameter layer is only real if the request body changes: these tests
/// run a real loopback `HttpServer`, capture the JSON body, and assert on the
/// parsed map - not on the adapter's fields.
///
/// The default assertion is the compatibility one: an adapter with no
/// reasoning effort and the shipped temperature sends **no**
/// `reasoning_effort` and **no** `max_tokens` key at all. That is the request
/// the app sent before the parameter layer existed, and an empty configuration
/// must keep it.
void main() {
  Future<Map<String, Object?>> capturedBody({
    double temperature = 0.2,
    int? maxTokens,
    ReasoningEffort? reasoningEffort,
    String model = 'test-model',
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final captured = Completer<Map<String, Object?>>();
    server.listen((request) async {
      final raw = await request
          .cast<List<int>>()
          .transform(utf8.decoder)
          .join();
      final decoded = jsonDecode(raw);
      if (!captured.isCompleted) {
        captured.complete((decoded as Map).cast<String, Object?>());
      }
      final response = request.response;
      response.headers.contentType =
          ContentType('text', 'event-stream', charset: 'utf-8');
      response.bufferOutput = false;
      response.write(
        'data: {"choices":[{"index":0,"delta":{"content":"ok"},'
        '"finish_reason":null}]}\n\n',
      );
      response.write('data: [DONE]\n\n');
      await response.close();
    });

    final adapter = OpenAiCompatAdapter(
      apiKey: 'test-key',
      baseUrl: 'http://127.0.0.1:${server.port}',
      model: model,
      temperature: temperature,
      maxTokens: maxTokens,
      reasoningEffort: reasoningEffort,
      connectTimeout: const Duration(seconds: 5),
      requestTimeout: const Duration(seconds: 30),
    );
    final events = await adapter
        .runTurn(
          messages: const [ChatMessage.user('嗨')],
          tools: const <ModelToolSpec>[],
        )
        .toList()
        .timeout(const Duration(seconds: 10));
    adapter.close();
    // The request must still complete normally; a body assertion is worthless
    // if the turn failed before the server answered.
    expect(events.whereType<ModelFailure>(), isEmpty);
    expect(events.whereType<ModelTurnDone>(), hasLength(1));
    return captured.future;
  }

  test('default adapter sends no reasoning_effort and no max_tokens', () async {
    final body = await capturedBody();

    expect(body['model'], 'test-model');
    expect(body['stream'], isTrue);
    expect(body['temperature'], 0.2);
    expect(body.containsKey('reasoning_effort'), isFalse,
        reason: 'an empty configuration must send the pre-v46 request body');
    expect(body.containsKey('max_tokens'), isFalse);
    expect(body['stream_options'], {'include_usage': true});
  });

  test('an explicit effort, temperature and max_tokens reach the body',
      () async {
    final body = await capturedBody(
      temperature: 0.7,
      maxTokens: 1234,
      reasoningEffort: ReasoningEffort.high,
    );

    expect(body['temperature'], 0.7);
    expect(body['max_tokens'], 1234);
    expect(body['reasoning_effort'], 'high');
  });

  test('every offered effort level is sent as its documented wire value',
      () async {
    for (final effort in ReasoningEffort.values) {
      final body = await capturedBody(reasoningEffort: effort);
      expect(body['reasoning_effort'], effort.wireValue,
          reason: '${effort.name} must be sent verbatim');
    }
  });
}
