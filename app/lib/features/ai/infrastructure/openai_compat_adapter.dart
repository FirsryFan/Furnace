import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../domain/model_adapter.dart';
import 'sse_assembler.dart';

/// Talks to any OpenAI-compatible chat-completions endpoint.
///
/// DeepSeek's API is the target, and it follows the OpenAI shape exactly
/// (`tools: [{type: function, function: {...}}]`, `message.tool_calls[]`,
/// `{role: tool, tool_call_id, content}`; verified against DeepSeek's own docs).
/// Writing it against the compatible shape rather than a DeepSeek-specific one
/// means a local or third-party endpoint is a base-URL change.
///
/// The model half of the app's network egress.
///
/// There is exactly one other egress point - the read-only `fetch_page` tool
/// (`features/ai/tools/web_tools.dart`, rules in `domain/services/web/web_http.dart`)
/// - and `docs/AI_DESIGN.md` D1 rule 2 was amended on 2026-10-02 to say so. Both
/// are reachable only while the AI surface exists, i.e. only after the user has
/// configured their own endpoint.
class OpenAiCompatAdapter implements CancellableModelAdapter {
  OpenAiCompatAdapter({
    required this.apiKey,
    required this.baseUrl,
    required this.model,
    HttpClient? client,
    this.temperature = 0.2,
    this.connectTimeout = const Duration(seconds: 20),
    this.requestTimeout = const Duration(minutes: 3),
  }) : _client = client ?? HttpClient() {
    _client.connectionTimeout = connectTimeout;
  }

  final String apiKey;
  final String baseUrl;
  final String model;
  final double temperature;
  final Duration connectTimeout;
  final Duration requestTimeout;
  final HttpClient _client;

  /// The request whose response is currently streaming, so [cancelActiveTurn]
  /// can abort a socket that is not delivering. Null between turns.
  HttpClientRequest? _activeRequest;

  /// The line iterator currently being drained, so a cancel can end a pending
  /// read at once instead of waiting for the next byte to arrive.
  StreamIterator<String>? _activeLines;

  /// Set by [cancelActiveTurn] for the turn in flight and cleared when a new
  /// turn starts. Every place the stream can block checks it before deciding
  /// whether an ending means a failure or a cancellation.
  bool _cancelRequested = false;

  /// Stops the turn in flight: pending read first, then the socket.
  ///
  /// Idempotent and safe to call when idle. The abort is the backstop: on the
  /// platforms this app targets, cancelling the line iterator ends a pending
  /// read but does not necessarily tear down the TCP connection under it.
  @override
  void cancelActiveTurn() {
    if (_cancelRequested) {
      return;
    }
    _cancelRequested = true;
    final lines = _activeLines;
    _activeLines = null;
    if (lines != null) {
      unawaited(lines.cancel().catchError((Object _) {}));
    }
    final request = _activeRequest;
    _activeRequest = null;
    if (request != null) {
      try {
        request.abort();
      } catch (_) {
        // Aborting an already-finished request is harmless; the only thing
        // that matters is that nothing is left waiting.
      }
    }
  }

  /// Tool calls stream in fragments; [StreamAssembler] owns the reassembly
  /// rules and is tested on its own.
  static const String _sseDataPrefix = 'data: ';
  static const String _sseDone = '[DONE]';

  @override
  Stream<ModelEvent> runTurn({
    required List<ChatMessage> messages,
    required List<ModelToolSpec> tools,
  }) async* {
    _cancelRequested = false;
    HttpClientRequest request;
    HttpClientResponse response;
    // Times the generation only: started when the request goes out and stopped
    // when the stream ends, so the loop's own work around this call (reading
    // skills, rebuilding the history, running tools) is not inside it. That is
    // the denominator the panel divides completion tokens by.
    final generationWatch = Stopwatch();
    try {
      request = await _client
          .postUrl(Uri.parse('$baseUrl/chat/completions'))
          .timeout(connectTimeout);
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $apiKey');
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      request.headers.set(HttpHeaders.acceptHeader, 'text/event-stream');

      final body = jsonEncode({
        'model': model,
        'messages': [for (final m in messages) m.toJson()],
        if (tools.isNotEmpty) 'tools': [for (final t in tools) t.toJson()],
        'stream': true,
        // Without this the streamed response carries no `usage` at all on
        // DeepSeek and OpenAI: the token counts are only sent when the caller
        // opts in. The turn/usage panel would then have nothing measured to
        // show, so the opt-in is part of the feature rather than an extra.
        'stream_options': {'include_usage': true},
        if (tools.isNotEmpty) 'tool_choice': 'auto',
        'temperature': temperature,
      });
      request.add(utf8.encode(body));
      _activeRequest = request;
      generationWatch.start();
      if (_cancelRequested) {
        // Cancelled while the request was being built: never wait for a
        // response we already know is going to be thrown away.
        _activeRequest = null;
        yield const ModelTurnCancelled();
        return;
      }
      response = await request.close().timeout(requestTimeout);
    } on TimeoutException {
      if (_cancelRequested) {
        yield const ModelTurnCancelled();
        return;
      }
      yield const ModelFailure('请求超时：模型服务没有在预期时间内响应。');
      return;
    } on SocketException catch (e) {
      if (_cancelRequested) {
        yield const ModelTurnCancelled();
        return;
      }
      yield ModelFailure('无法连接模型服务：${e.message}（检查网络与 Base URL）');
      return;
    } on HandshakeException catch (e) {
      if (_cancelRequested) {
        yield const ModelTurnCancelled();
        return;
      }
      yield ModelFailure('TLS 握手失败：${e.message}');
      return;
    } on HttpException catch (e) {
      if (_cancelRequested) {
        yield const ModelTurnCancelled();
        return;
      }
      yield ModelFailure('HTTP 错误：${e.message}');
      return;
    }

    if (response.statusCode != 200) {
      // The provider explains itself in the body; showing a bare status code
      // would leave the user guessing about a bad key or model name.
      final text = await _readAll(response);
      yield ModelFailure(
        _explainStatus(response.statusCode, text),
        statusCode: response.statusCode,
      );
      return;
    }

    final assembler = StreamAssembler();
    final lines =
        response.transform(utf8.decoder).transform(const LineSplitter());
    // A StreamIterator rather than an await for: a cancel must be able to end
    // a read that is already waiting for the next line. Cancelling the
    // iterator completes a pending moveNext with false, and aborting the
    // request is the backstop for a socket that stops delivering instead.
    final iterator = StreamIterator<String>(lines.timeout(requestTimeout));
    _activeLines = iterator;
    var cancelled = _cancelRequested;

    try {
      while (!cancelled && await iterator.moveNext()) {
        if (_cancelRequested) {
          cancelled = true;
          break;
        }
        final line = iterator.current;
        if (line.isEmpty) {
          continue;
        }
        if (!line.startsWith(_sseDataPrefix)) {
          // event:/id:/comment lines carry nothing we need.
          continue;
        }
        final payload = line.substring(_sseDataPrefix.length).trim();
        if (payload == _sseDone) {
          break;
        }

        Map<String, Object?> chunk;
        try {
          final decoded = jsonDecode(payload);
          if (decoded is! Map) {
            continue;
          }
          chunk = decoded.cast<String, Object?>();
        } on FormatException {
          // A malformed chunk must not kill an otherwise good turn.
          continue;
        }

        for (final event in assembler.consume(chunk)) {
          yield event;
        }
      }
    } on TimeoutException {
      if (_cancelRequested) {
        yield const ModelTurnCancelled();
        return;
      }
      // Yield whatever completed calls we already have before reporting: a
      // half-streamed tool call is useless, but the text is not.
      yield const ModelFailure('流式响应超时。');
      return;
    } on HttpException catch (e) {
      if (_cancelRequested) {
        yield const ModelTurnCancelled();
        return;
      }
      yield ModelFailure('流式响应中断：${e.message}');
      return;
    } on SocketException {
      if (_cancelRequested) {
        yield const ModelTurnCancelled();
        return;
      }
      yield const ModelFailure('流式连接中断：网络已断开。');
      return;
    } on Exception {
      if (_cancelRequested) {
        yield const ModelTurnCancelled();
        return;
      }
      rethrow;
    } finally {
      _activeLines = null;
      _activeRequest = null;
      unawaited(iterator.cancel().catchError((Object _) {}));
    }

    if (cancelled || _cancelRequested) {
      yield const ModelTurnCancelled();
      return;
    }

    generationWatch.stop();
    for (final event in assembler.finish(
      generationDuration: generationWatch.elapsed,
    )) {
      yield event;
    }
  }

  Future<String> _readAll(HttpClientResponse response) async {
    try {
      return await response.transform(utf8.decoder).join();
    } catch (_) {
      return '';
    }
  }

  /// Turns a provider error body into something the user can act on.
  String _explainStatus(int status, String body) {
    String? detail;
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final error = decoded['error'];
        if (error is Map && error['message'] is String) {
          detail = error['message'] as String;
        } else if (decoded['message'] is String) {
          detail = decoded['message'] as String;
        }
      }
    } on FormatException {
      detail = body.trim().isEmpty ? null : body.trim();
    }
    final hint = switch (status) {
      401 || 403 => 'API key 可能无效或没有权限。',
      404 => 'Base URL 或模型名可能不对。',
      429 => '触发限流或余额不足。',
      >= 500 => '模型服务端错误。',
      _ => null,
    };
    final buffer = StringBuffer('模型服务返回 $status');
    if (detail != null && detail.isNotEmpty) {
      buffer.write('：$detail');
    }
    if (hint != null) {
      buffer.write('（$hint）');
    }
    return buffer.toString();
  }

  void close() => _client.close(force: true);
}
