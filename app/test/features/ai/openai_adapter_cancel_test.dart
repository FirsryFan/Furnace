import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/features/ai/domain/model_adapter.dart';
import 'package:furnace/features/ai/infrastructure/openai_compat_adapter.dart';

/// Stopping a turn has to end a stream that is blocked waiting for the next
/// chunk - otherwise the UI keeps its spinner until the provider times out.
/// Every provider here is a real loopback HTTP server, so these tests exercise
/// the actual socket and the SSE reader rather than a fake stream.
void main() {
  Future<void> until(bool Function() condition) async {
    for (var i = 0; i < 2000; i++) {
      if (condition()) {
        return;
      }
      await Future<void>.delayed(Duration.zero);
    }
    fail('condition was not reached');
  }

  String sse(Map<String, Object?> delta) {
    final payload = jsonEncode({
      'choices': [
        {
          'index': 0,
          'delta': delta,
          'finish_reason': null,
        },
      ],
    });
    return 'data: $payload\n\n';
  }

  OpenAiCompatAdapter adapterFor(int port) => OpenAiCompatAdapter(
        apiKey: 'test-key',
        baseUrl: 'http://127.0.0.1:$port',
        model: 'test-model',
        connectTimeout: const Duration(seconds: 5),
        requestTimeout: const Duration(seconds: 30),
      );

  test('reasoning and answer are separated, and a cancel ends the stream',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      final response = request.response;
      response.headers.contentType =
          ContentType('text', 'event-stream', charset: 'utf-8');
      response.bufferOutput = false;
      response.write(sse({'reasoning_content': '先想'}));
      response.write(sse({'content': '答案'}));
      await response.flush();
      // Deliberately go quiet here: a cancel must break out of this wait.
    });

    final adapter = adapterFor(server.port);
    final events = <ModelEvent>[];
    final done = Completer<void>();
    final subscription = adapter.runTurn(
      messages: const [ChatMessage.user('嗨')],
      tools: const <ModelToolSpec>[],
    ).listen(
      events.add,
      onDone: done.complete,
      onError: done.completeError,
    );
    await until(() => events.length >= 2);
    expect(events.whereType<ModelReasoningDelta>().single.text, '先想');
    expect(events.whereType<ModelTextDelta>().single.text, '答案');

    adapter.cancelActiveTurn();
    await done.future.timeout(const Duration(seconds: 5));
    await subscription.cancel();

    expect(events.whereType<ModelTurnCancelled>(), hasLength(1));
    expect(events.last, isA<ModelTurnCancelled>());
    expect(events.whereType<ModelFailure>(), isEmpty,
        reason: 'stopping is not a provider failure');
  });

  test('cancelling before the response starts ends the turn immediately',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final requestSeen = Completer<void>();
    server.listen((request) {
      // Headers are never written: the client is waiting on the response.
      if (!requestSeen.isCompleted) {
        requestSeen.complete();
      }
    });

    final adapter = adapterFor(server.port);
    final events = <ModelEvent>[];
    final done = Completer<void>();
    final subscription = adapter.runTurn(
      messages: const [ChatMessage.user('嗨')],
      tools: const <ModelToolSpec>[],
    ).listen(
      events.add,
      onDone: done.complete,
      onError: done.completeError,
    );
    await requestSeen.future;
    adapter.cancelActiveTurn();
    await done.future.timeout(const Duration(seconds: 5));
    await subscription.cancel();

    expect(events.whereType<ModelTurnCancelled>(), hasLength(1));
    expect(events.whereType<ModelFailure>(), isEmpty);
  });

  test('a new turn after a cancel is not poisoned by the old flag', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      final response = request.response;
      response.headers.contentType =
          ContentType('text', 'event-stream', charset: 'utf-8');
      response.bufferOutput = false;
      response.write(sse({'content': '答案'}));
      response.write('data: [DONE]\n\n');
      await response.close();
    });

    final adapter = adapterFor(server.port);
    // Cancelling while idle must not affect the turn that starts afterwards.
    adapter.cancelActiveTurn();
    final events = await adapter
        .runTurn(
          messages: const [ChatMessage.user('嗨')],
          tools: const <ModelToolSpec>[],
        )
        .toList()
        .timeout(const Duration(seconds: 5));

    expect(events.whereType<ModelTextDelta>().single.text, '答案');
    expect(events.whereType<ModelTurnCancelled>(), isEmpty);
    expect(events.whereType<ModelTurnDone>(), hasLength(1));
    expect(events.whereType<ModelFailure>(), isEmpty);
  });
}
