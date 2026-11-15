import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../data/storage/app_storage.dart';
import '../domain/student_solver.dart';

/// Writes one student-solver trace to the app support tree.
///
/// The trace contains the raw reasoning, the final answer, usage and the
/// dashboard question, because that is what later review needs. It is a local
/// artifact only; nothing here is sent anywhere.
class StudentTraceStore {
  StudentTraceStore({
    Future<Directory> Function()? supportDirectory,
  }) : _supportDirectory = supportDirectory ?? AppStorage.supportDirectory;

  final Future<Directory> Function() _supportDirectory;

  static const String directoryName = 'student_solver_traces';

  Future<String> save({
    required String question,
    required StudentSolverResult result,
    String? questionId,
  }) async {
    final root = await _supportDirectory();
    final directory = Directory(p.join(root.path, directoryName));
    await directory.create(recursive: true);
    final stamp = DateTime.now()
        .toUtc()
        .toIso8601String()
        .replaceAll(RegExp(r'[:.]'), '-');
    final file = File(p.join(directory.path, '$stamp.json'));
    await file.writeAsString(
      const JsonEncoder.withIndent(' ').convert({
        'schema': 'furnace.student_solver_trace/1',
        'created_at': DateTime.now().toUtc().toIso8601String(),
        if (questionId != null) 'question_id': questionId,
        'question': question,
        'answer': result.answer,
        'answer_sheet': result.answerSheet.toJson(),
        'reasoning': result.reasoning,
        'phase': result.phase.name,
        'attempts': result.attempts,
        'prompt_tokens': result.promptTokens,
        'completion_tokens': result.completionTokens,
        'finish_reason': result.finishReason,
        'error': result.error,
      }),
      flush: true,
    );
    return file.path;
  }
}
