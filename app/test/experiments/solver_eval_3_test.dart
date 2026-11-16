import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/features/ai/domain/student_solver.dart';
import 'package:furnace/features/ai/infrastructure/openai_compat_adapter.dart';

/// 3-question smoke eval for the legacy direct StudentSolver.
///
/// Not part of the normal suite; it performs paid API calls and writes evidence
/// to the agent-control workspace. It deliberately does NOT assert correctness:
/// the point is to record what the solver actually produced.
void main() {
  test('3-question solver eval', () async {
    final keyFile = File('D:/dsh-data/.credentials.yaml');
    if (!keyFile.existsSync()) {
      markTestSkipped('no DeepSeek credentials');
      return;
    }
    final match = RegExp(r'DEEPSEEK_API_KEY:\s*(sk-[A-Za-z0-9_-]+)')
        .firstMatch(keyFile.readAsStringSync());
    if (match == null) {
      markTestSkipped('no DEEPSEEK_API_KEY');
      return;
    }
    final dataset = jsonDecode(File(
      r'E:\Workspaces\agent-control\10-projects\agent-control-plane\solver-eval-3-2026-11-17.json',
    ).readAsStringSync()) as Map<String, Object?>;
    final items = (dataset['items'] as List).cast<Map<String, Object?>>();

    final solver = StudentSolver(
      reasonAdapter: OpenAiCompatAdapter(
        apiKey: match.group(1)!,
        baseUrl: 'https://api.deepseek.com',
        model: 'deepseek-flash',
        maxTokens: 12000,
        temperature: 0.4,
      ),
      answerAdapter: OpenAiCompatAdapter(
        apiKey: match.group(1)!,
        baseUrl: 'https://api.deepseek.com',
        model: 'deepseek-chat',
        maxTokens: 2000,
        temperature: 0.2,
      ),
    );

    final results = <Map<String, Object?>>[];
    for (final item in items) {
      final sw = Stopwatch()..start();
      final result = await solver.solve(question: item['question'] as String);
      sw.stop();
      results.add(<String, Object?>{
        'subject': item['subject'],
        'tr': item['tr'],
        'answer': result.answer,
        'ok': result.ok,
        'attempts': result.attempts,
        'elapsed_ms': sw.elapsedMilliseconds,
        'reference_answer': item['reference_answer'],
      });
    }

    final out = File(
      r'E:\Workspaces\agent-control\10-projects\agent-control-plane\solver-eval-3-result-2026-11-17.json',
    );
    out.writeAsStringSync(
      const JsonEncoder.withIndent(' ').convert(results),
    );
    // ignore: avoid_print
    print(jsonEncode(results));
  }, timeout: const Timeout(Duration(minutes: 20)));
}
