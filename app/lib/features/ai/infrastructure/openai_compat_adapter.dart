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
/// This is the only class in the app that opens a network connection.
class OpenAiCompatAdapter implements ModelAdapter {
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

  /// Tool calls stream in fragments; [StreamAssembler] owns the reassembly
  /// rules and is tested on its own.
  static const String _sseDataPrefix = 'data: ';
  static const String _sseDone = '[DONE]';

  @override
  Stream<ModelEvent> runTurn({
    required List<ChatMessage> messages,
    required List<ModelToolSpec> tools,
  }) async* {
    HttpClientRequest request;
    HttpClientResponse response;
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
        if (tools.isNotEmpty) 'tool_choice': 'auto',
        'temperature': temperature,
      });
      request.add(utf8.encode(body));
      response = await request.close().timeout(requestTimeout);
    } on TimeoutException {
      yield const ModelFailure('请求超时：模型服务没有在预期时间内响应。');
      return;
    } on SocketException catch (e) {
      yield ModelFailure('无法连接模型服务：${e.message}（检查网络与 Base URL）');
      return;
    } on HandshakeException catch (e) {
      yield ModelFailure('TLS 握手失败：${e.message}');
      return;
    } on HttpException catch (e) {
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
    final lines = response
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    try {
      await for (final line in lines.timeout(requestTimeout)) {
        if (line.isEmpty) {
          continue;
        }
        if (!line.startsWith(_sseDataPrefix)) {
          // `event:`/`id:`/comment lines carry nothing we need.
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
      // Yield whatever completed calls we already have before reporting: a
      // half-streamed tool call is useless, but the text is not.
      yield const ModelFailure('流式响应超时。');
      return;
    } on HttpException catch (e) {
      yield ModelFailure('流式响应中断：${e.message}');
      return;
    }

    for (final event in assembler.finish()) {
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
