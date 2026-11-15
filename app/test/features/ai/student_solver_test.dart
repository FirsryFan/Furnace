import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/features/ai/domain/model_adapter.dart';
import 'package:furnace/features/ai/domain/student_solver.dart';
import 'package:furnace/features/ai/infrastructure/fake_model_adapter.dart';

void main() {
  group('StudentSolver', () {
    test('returns the first answer and asks for no tools', () async {
      final adapter = FakeModelAdapter([
        [
          const ModelReasoningDelta('think'),
          const ModelTextDelta('a=g sinθ'),
          const ModelTurnDone(
            finishReason: 'stop',
            promptTokens: 100,
            completionTokens: 20,
          ),
        ],
      ]);
      final solver = StudentSolver(reasonAdapter: adapter);

      final result = await solver.solve(question: '题目');

      expect(result.ok, isTrue);
      expect(result.answer, 'a=g sinθ');
      expect(result.reasoning, 'think');
      expect(result.attempts, 1);
      expect(result.promptTokens, 100);
      expect(adapter.requests, hasLength(1));
      expect(adapter.requests.single.tools, isEmpty);
      expect(adapter.requests.single.messages.first.role, 'system');
      expect(adapter.requests.single.messages.last.role, 'user');
    });

    test('reserves an answer turn when reasoning hits the length limit',
        () async {
      final reason = FakeModelAdapter([
        [
          const ModelReasoningDelta('long draft'),
          const ModelTurnDone(finishReason: 'length', completionTokens: 100),
        ],
      ]);
      final answer = FakeModelAdapter([
        [
          const ModelTextDelta('final answer'),
          const ModelTurnDone(finishReason: 'stop', completionTokens: 5),
        ],
      ]);
      final solver = StudentSolver(
        reasonAdapter: reason,
        answerAdapter: answer,
      );

      final result = await solver.solve(question: '题目');

      expect(result.ok, isTrue);
      expect(result.answer, 'final answer');
      expect(result.attempts, 2);
      expect(answer.requests, hasLength(1));
      expect(
        answer.requests.single.messages.any(
          (message) => message.role == 'assistant',
        ),
        isTrue,
      );
      expect(result.reasoning, contains('long draft'));
    });

    test('reports failure when neither turn produces text', () async {
      final adapter = FakeModelAdapter([
        [const ModelFailure('network down')],
      ]);
      final solver = StudentSolver(reasonAdapter: adapter);

      final result = await solver.solve(question: '题目');

      expect(result.ok, isFalse);
      expect(result.answer, isEmpty);
      expect(result.error, isNotNull);
    });
  });
}
