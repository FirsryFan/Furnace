import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/ai_repository.dart';
import 'package:furnace/features/ai/application/conversation_runner.dart';
import 'package:furnace/features/ai/application/student_mode_controller.dart';
import 'package:furnace/features/ai/domain/student_solver.dart';
import 'package:furnace/features/ai/infrastructure/ai_attachment_store.dart';
import 'package:furnace/features/ai/infrastructure/openai_compat_adapter.dart';
import 'package:furnace/features/ai/infrastructure/student_trace_store.dart';

/// One real-API run of the new direct student preset.
///
/// Run:
///   flutter test test/experiments/student_mode_experiment_test.dart
///
/// It is not part of the normal `test/features/ai` suite; it performs paid API
/// calls and writes a metrics JSON next to this file (or to
/// STUDENT_EXPERIMENT_OUT).
void main() {
  test('direct student preset experiment', () async {
    final keyFile = File('D:/dsh-data/.credentials.yaml');
    if (!keyFile.existsSync()) {
      markTestSkipped('no DeepSeek credentials');
      return;
    }
    final keyMatch = RegExp(r'DEEPSEEK_API_KEY:\s*(sk-[A-Za-z0-9_-]+)')
        .firstMatch(keyFile.readAsStringSync());
    if (keyMatch == null) {
      markTestSkipped('no DEEPSEEK_API_KEY');
      return;
    }
    final apiKey = keyMatch.group(1)!;

    final question = File(
      r'E:\Workspaces\Test\work\2025-sichuan-physics-q15\solver-input\question.md',
    ).readAsStringSync();
    final imageBytes = File(
      r'E:\Workspaces\Test\work\2025-sichuan-physics-q15\assets\q15-figure.png',
    ).readAsBytesSync();

    final temp = Directory.systemTemp.createTempSync('furnace-student-exp-');
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    try {
      final repository = AiRepository(db);
      final attachments = AiAttachmentStore(
        repository: repository,
        supportDirectory: () async => temp,
      );
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
      final controller = StudentModeController(
        solver: solver,
        traceStore: StudentTraceStore(supportDirectory: () async => temp),
      );
      final runner = ConversationRunner(
        repository: repository,
        mainAgent: _ExplodingMainAgent(),
        studentMode: controller,
        attachments: attachments,
      );

      const imageRel = 'q15.png';
      File('${temp.path}/$imageRel').writeAsBytesSync(imageBytes);
      final pending = PendingImage(
        relPath: imageRel,
        absolutePath: '${temp.path}/$imageRel',
        mime: 'image/png',
        width: 1,
        height: 1,
      );

      final runs = int.tryParse(
            Platform.environment['STUDENT_EXPERIMENT_RUNS'] ?? '1',
          ) ??
          1;
      final metricsList = <Map<String, Object?>>[];
      for (var i = 0; i < runs; i++) {
        final stopwatch = Stopwatch()..start();
        final result = await runner.startStudentSession(
          question: question,
          images: [pending],
          title: 'Q15 student experiment $i',
        );
        stopwatch.stop();

        final outcome = result.studentOutcome!;
        final metrics = <String, Object?>{
          'run': i + 1,
          'architecture': 'furnace-direct-student-preset',
          'model': 'deepseek-flash',
          'question': '2025 Sichuan Physics Q15',
          'elapsed_ms': stopwatch.elapsedMilliseconds,
          'used_student_solver': result.usedStudentSolver,
          'used_student_run': outcome.usedStudentRun,
          'verified': outcome.verified,
          'verdict': outcome.studentRun?.verdict.id,
          'student_stage': outcome.studentRun?.stage.id,
          'verifier_calls': outcome.studentRun?.verifierCalls,
          'repair_count': outcome.studentRun?.repairCount,
          'process_flags': outcome.studentRun?.processAudit?.report.flags,
          'process_blocked': outcome.studentRun?.processAudit?.blocker?.id,
          'stop_reason': outcome.studentRun?.run.stopReason?.id,
          'verification_evidence': outcome.studentRun?.verification?.evidence,
          'main_agent_called': false,
          'ok': outcome.ok,
          'attempts': outcome.result.attempts,
          'prompt_tokens': outcome.result.promptTokens,
          'completion_tokens': outcome.result.completionTokens,
          'reasoning_chars': outcome.result.reasoning.length,
          'answer_chars': outcome.result.answer.length,
          'answer_sheet': outcome.result.answerSheet.toJson(),
          'trace_path': outcome.tracePath,
          'assistant_message': result.assistantMessage?.id,
          'preset': result.presets.agent.id,
          'locked': result.presets.locked,
        };
        metricsList.add(metrics);
        // ignore: avoid_print
        print(const JsonEncoder.withIndent(' ').convert(metrics));
        expect(outcome.ok, isTrue);
        expect(result.usedStudentSolver, isTrue);
        expect(result.presets.agent.id, 'student_solver');
      }
      final outPath = Platform.environment['STUDENT_EXPERIMENT_OUT'] ??
          r'E:\Workspaces\agent-control\10-projects\agent-control-plane\student-mode-experiment-result.json';
      File(outPath).writeAsStringSync(
        const JsonEncoder.withIndent(' ').convert(metricsList),
      );
    } finally {
      await db.close();
      if (temp.existsSync()) {
        temp.deleteSync(recursive: true);
      }
    }
  }, timeout: const Timeout(Duration(minutes: 20)));
}

class _ExplodingMainAgent implements StandardAgentRunner {
  @override
  Future<void> sendUserMessage({
    required String conversationId,
    required String text,
    List<PendingImage> images = const [],
  }) async {
    throw StateError('main agent was called in a student preset experiment');
  }
}
