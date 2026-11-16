import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/features/ai/domain/model_adapter.dart';
import 'package:furnace/features/ai/domain/student_solver.dart';
import 'package:furnace/features/ai/infrastructure/openai_compat_adapter.dart';

/// Oracle-driven repair experiment for the multi-branch physics Q15.
///
/// Not part of the normal suite. It performs paid API calls and writes evidence.
void main() {
  test('physics Q15 oracle repair', () async {
    final keyFile = File('D:/dsh-data/.credentials.yaml');
    final match = keyFile.existsSync()
        ? RegExp(r'DEEPSEEK_API_KEY:\s*(sk-[A-Za-z0-9_-]+)')
            .firstMatch(keyFile.readAsStringSync())
        : null;
    if (match == null) {
      markTestSkipped('no DEEPSEEK_API_KEY');
      return;
    }
    final question = File(
      r'E:\Workspaces\Test\work\2025-sichuan-physics-q15\solver-input\question.md',
    ).readAsStringSync();
    final imageBytes = File(
      r'E:\Workspaces\Test\work\2025-sichuan-physics-q15\assets\q15-figure.png',
    ).readAsBytesSync();
    final image = ChatImagePart(mime: 'image/png', base64: base64Encode(imageBytes));

    StudentSolver make({String? extra}) => StudentSolver(
          reasonAdapter: OpenAiCompatAdapter(
            apiKey: match.group(1)!,
            baseUrl: 'https://api.deepseek.com',
            model: 'deepseek-flash',
            maxTokens: 20000,
            temperature: 0.4,
          ),
          answerAdapter: OpenAiCompatAdapter(
            apiKey: match.group(1)!,
            baseUrl: 'https://api.deepseek.com',
            model: 'deepseek-chat',
            maxTokens: 3000,
            temperature: 0.2,
          ),
          systemPrompt: extra == null
              ? StudentSolver.defaultSystemPrompt
              : '${StudentSolver.defaultSystemPrompt}\n\n$extra',
        );

    final first = await make().solve(question: question, images: <ChatImagePart>[image]);
    final firstHasBoth = _hasBothBranches(first.answer);
    StudentSolverResult? repaired;
    if (!firstHasBoth) {
      repaired = await make(
        extra: '上一轮第(3)问没有把 m2/m1≤1 与 m2/m1=7 两支分别写成条件；'
            '请先列分支表，再逐支给出 Ek0 条件，不能只写一支。',
      ).solve(question: question, images: <ChatImagePart>[image]);
    }

    final result = <String, Object?>{
      'question': '2025 Sichuan physics Q15',
      'first_ok': first.ok,
      'first_has_both_branches': firstHasBoth,
      'first_answer': first.answer,
      'first_attempts': first.attempts,
      'repaired': repaired == null
          ? null
          : <String, Object?>{
              'ok': repaired.ok,
              'has_both_branches': _hasBothBranches(repaired.answer),
              'answer': repaired.answer,
              'attempts': repaired.attempts,
            },
    };
    final out = File(
      r'E:\Workspaces\agent-control\10-projects\agent-control-plane\oracle-repair-q15-result-2026-11-17.json',
    );
    out.writeAsStringSync(const JsonEncoder.withIndent(' ').convert(result));
    // ignore: avoid_print
    print(jsonEncode(result));
  }, timeout: const Timeout(Duration(minutes: 20)));
}

bool _hasBothBranches(String answer) {
  final text = answer.replaceAll(' ', '');
  final hasLe = text.contains(r'\le1') ||
      text.contains('≤1') ||
      text.contains('<=1');
  final hasEq = text.contains('=7');
  return hasLe && hasEq;
}
