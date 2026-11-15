import 'dart:convert';
import 'dart:io';

import 'package:furnace/features/ai/domain/model_adapter.dart';
import 'package:furnace/features/ai/domain/student_solver.dart';
import 'package:furnace/features/ai/infrastructure/openai_compat_adapter.dart';

/// Real-API smoke for the Flutter-side StudentSolver.
///
/// Run from `app/`:
///   dart run tool/student_solver_smoke.dart
///
/// This does not touch the app database or UI; it only proves that the Flutter
/// domain code can drive the same DeepSeek endpoint as the standalone Python
/// component, with a reasoning budget and a reserved answer turn.
Future<void> main() async {
  final keyFile = File('D:/dsh-data/.credentials.yaml');
  final keyMatch = RegExp(r'DEEPSEEK_API_KEY:\s*(sk-[A-Za-z0-9_-]+)')
      .firstMatch(await keyFile.readAsString());
  if (keyMatch == null) {
    stderr.writeln('no DEEPSEEK_API_KEY in credentials');
    exitCode = 2;
    return;
  }
  final apiKey = keyMatch.group(1)!;

  final question = await File(
    r'E:\Workspaces\Test\work\2025-sichuan-physics-q15\solver-input\question.md',
  ).readAsString();
  final imageBytes = await File(
    r'E:\Workspaces\Test\work\2025-sichuan-physics-q15\assets\q15-figure.png',
  ).readAsBytes();

  final solver = StudentSolver(
    reasonAdapter: OpenAiCompatAdapter(
      apiKey: apiKey,
      baseUrl: 'https://api.deepseek.com',
      model: 'deepseek-flash',
      maxTokens: 20000,
      temperature: 0.6,
    ),
    answerAdapter: OpenAiCompatAdapter(
      apiKey: apiKey,
      baseUrl: 'https://api.deepseek.com',
      model: 'deepseek-chat',
      maxTokens: 3000,
      temperature: 0.2,
    ),
  );

  final result = await solver.solve(
    question: question,
    images: [
      ChatImagePart(
        mime: 'image/png',
        base64: base64Encode(imageBytes),
      ),
    ],
  );

  stdout.writeln(jsonEncode(result.toModelJson()));
  stdout.writeln(jsonEncode({
    'answer': result.answer,
    'attempts': result.attempts,
  }));
}
