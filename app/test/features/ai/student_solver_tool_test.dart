import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/question_repository.dart';
import 'package:furnace/features/ai/domain/ai_tool.dart';
import 'package:furnace/features/ai/domain/model_adapter.dart';
import 'package:furnace/features/ai/domain/student_solver.dart';
import 'package:furnace/features/ai/domain/student_solver_context.dart';
import 'package:furnace/features/ai/infrastructure/fake_model_adapter.dart';
import 'package:furnace/features/ai/infrastructure/student_trace_store.dart';
import 'package:furnace/features/ai/tools/student_solver_tool.dart';
import 'package:furnace/features/questions/data/question_media_store.dart';

void main() {
  group('SolveQuestionAsStudentTool', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    test('returns the answer as a read-only tool result', () async {
      final adapter = FakeModelAdapter([
        [
          const ModelTextDelta('m2/m1=7'),
          const ModelTurnDone(finishReason: 'stop', completionTokens: 8),
        ],
      ]);
      final tool = SolveQuestionAsStudentTool(
        StudentSolver(reasonAdapter: adapter),
      );

      final result = await tool.run(ToolInvocation(
        toolName: tool.name,
        action: tool.name,
        arguments: {'question': '题目'},
      ));

      expect(tool.readOnly, isTrue);
      expect(result.ok, isTrue);
      expect(result.summary, contains('m2/m1=7'));
      expect(result.modelResult, isA<Map<String, Object?>>());
      expect(
        (result.modelResult! as Map<String, Object?>)['answer'],
        'm2/m1=7',
      );
    });

    test('rejects a missing question', () async {
      final adapter = FakeModelAdapter([
        [const ModelTextDelta('x')],
      ]);
      final tool = SolveQuestionAsStudentTool(
        StudentSolver(reasonAdapter: adapter),
      );

      expect(
        () => tool.run(ToolInvocation(
          toolName: tool.name,
          action: tool.name,
          arguments: const {},
        )),
        throwsA(isA<ToolArgError>()),
      );
    });

    test('reads the stem from the question library by id', () async {
      final repository = QuestionRepository(db);
      final question = (await repository.ingest(
        const QuestionDraft(stem: '请解 1+1，只写答案。'),
      ))
          .question;
      final adapter = FakeModelAdapter([
        [
          const ModelTextDelta('2'),
          const ModelTurnDone(finishReason: 'stop'),
        ],
      ]);
      final tool = SolveQuestionAsStudentTool(
        StudentSolver(reasonAdapter: adapter),
        database: db,
      );

      final result = await tool.run(ToolInvocation(
        toolName: tool.name,
        action: tool.name,
        arguments: {'question_id': question.id},
      ));

      expect(result.ok, isTrue);
      expect(adapter.requests.single.messages.last.content, contains('请解 1+1'));
    });

    test('passes stored stem images to the solver', () async {
      final temp = await Directory.systemTemp.createTemp('furnace-student-');
      addTearDown(() => temp.delete(recursive: true));
      final repository = QuestionRepository(db);
      final question = (await repository.ingest(
        const QuestionDraft(stem: '看图作答。'),
      ))
          .question;
      final store = QuestionMediaStore(
        database: db,
        supportDirectory: () async => temp,
      );
      await store.save(
        questionId: question.id,
        fileName: 'stem.png',
        bytes: Uint8List.fromList([1, 2, 3, 4]),
        mime: 'image/png',
      );
      final adapter = FakeModelAdapter([
        [
          const ModelTextDelta('ok'),
          const ModelTurnDone(finishReason: 'stop'),
        ],
      ]);
      final tool = SolveQuestionAsStudentTool(
        StudentSolver(reasonAdapter: adapter),
        database: db,
        mediaStore: store,
      );

      await tool.run(ToolInvocation(
        toolName: tool.name,
        action: tool.name,
        arguments: {'question_id': question.id},
      ));

      expect(adapter.requests.single.messages.last.images, isNotEmpty);
    });

    test('uses the current turn image context for a text question', () async {
      final context = StudentSolverContext()
        ..setImages([
          const ChatImagePart(mime: 'image/png', base64: 'aW1n'),
        ]);
      final adapter = FakeModelAdapter([
        [
          const ModelTextDelta('ok'),
          const ModelTurnDone(finishReason: 'stop'),
        ],
      ]);
      final tool = SolveQuestionAsStudentTool(
        StudentSolver(reasonAdapter: adapter),
        context: context,
      );

      await tool.run(ToolInvocation(
        toolName: tool.name,
        action: tool.name,
        arguments: {'question': '看图作答'},
      ));

      expect(adapter.requests.single.messages.last.images, isNotEmpty);
    });

    test('writes a local trace with the raw reasoning', () async {
      final temp = await Directory.systemTemp.createTemp('furnace-trace-');
      addTearDown(() => temp.delete(recursive: true));
      final adapter = FakeModelAdapter([
        [
          const ModelReasoningDelta('raw reasoning'),
          const ModelTextDelta('answer'),
          const ModelTurnDone(finishReason: 'stop'),
        ],
      ]);
      final tool = SolveQuestionAsStudentTool(
        StudentSolver(reasonAdapter: adapter),
        traceStore: StudentTraceStore(
          supportDirectory: () async => temp,
        ),
      );

      final result = await tool.run(ToolInvocation(
        toolName: tool.name,
        action: tool.name,
        arguments: {'question': '题目'},
      ));

      final path =
          (result.modelResult! as Map<String, Object?>)['trace_path'] as String;
      final trace = File(path);
      expect(await trace.exists(), isTrue);
      expect(await trace.readAsString(), contains('raw reasoning'));
    });
  });
}
