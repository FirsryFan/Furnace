import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/features/assessment/application/assessment_engine.dart';
import 'package:furnace/features/assessment/application/stimulus_generators.dart';
import 'package:furnace/features/assessment/application/task_registry.dart';
import 'package:furnace/features/assessment/domain/assessment_models.dart';

/// 引擎是评测的时钟与判分器：这些测试钉死「先进先出、先呈现才计时、
/// 超时按 no-go 算、response 归一化」四条，UI 只能照着它用。
void main() {
  AssessmentTaskConfig taskOf(String taskId) => defaultAssessmentTask(taskId)!;

  AssessmentTaskConfig customTask({
    required String taskId,
    required AssessmentTaskType taskType,
    required Map<String, Object?> config,
  }) =>
      AssessmentTaskConfig(
        taskId: taskId,
        displayName: '自定义任务',
        taskType: taskType,
        estimatedDurationSeconds: 30,
        config: config,
        producedMetrics: const <String>[MetricNames.rtMedian],
        qualityChecks: const <String>[],
      );

  AssessmentRunEngine engineFor(
    String taskId, {
    int seed = 11,
    DateTime? startedAt,
  }) =>
      AssessmentRunEngine(
        task: taskOf(taskId),
        seed: seed,
        startedAt: startedAt ?? DateTime(2026, 1, 1),
      );

  group('构造与队列', () {
    test('构造即生成与生成器一致的队列，停在第 0 个未呈现的 trial', () {
      final task = taskOf(AssessmentTaskIds.fastSimpleI);
      final engine = AssessmentRunEngine(
        task: task,
        seed: 3,
        startedAt: DateTime(2026, 1, 1),
      );
      final expectedTrials = generatePlannedTrials(task: task, seed: 3);
      expect(
        <Object?>[for (final trial in engine.trials) trial.toJson()],
        <Object?>[for (final trial in expectedTrials) trial.toJson()],
      );
      expect(engine.current, same(engine.trials.first));
      expect(engine.trialIndex, 0);
      expect(engine.isFinished, isFalse);
      expect(engine.isPracticePhase, isTrue);
      expect(
        engine.awaitingResponse,
        isFalse,
        reason: '还没 markShown，RT 没有起点',
      );
      expect(engine.recorded, isEmpty);
    });

    test('同 seed 两个引擎队列一致，不同 seed 不同', () {
      List<Object?> serialized(AssessmentRunEngine engine) =>
          <Object?>[for (final trial in engine.trials) trial.toJson()];
      expect(
        serialized(engineFor(AssessmentTaskIds.fastSimpleI, seed: 9)),
        serialized(engineFor(AssessmentTaskIds.fastSimpleI, seed: 9)),
      );
      expect(
        serialized(engineFor(AssessmentTaskIds.fastSimpleI, seed: 9)),
        isNot(serialized(engineFor(AssessmentTaskIds.fastSimpleI, seed: 10))),
      );
    });

    test('单 trial 任务答完即 finished，之后的调用抛 StateError', () {
      final engine = AssessmentRunEngine(
        task: customTask(
          taskId: 'single_trial',
          taskType: AssessmentTaskType.choiceReaction,
          config: const <String, Object?>{
            'trials': 1,
            'practice_trials': 0,
            'options': <String>['circle', 'square'],
          },
        ),
        seed: 1,
        startedAt: DateTime(2026, 1, 1),
      );
      final start = DateTime(2026, 1, 1, 9);
      expect(engine.trials, hasLength(1));
      expect(engine.isFinished, isFalse);
      engine.markShown(start);
      engine.submit(response: engine.current!.expectedResponse, at: start);
      expect(engine.isFinished, isTrue);
      expect(engine.current, isNull);
      expect(engine.isPracticePhase, isFalse);
      expect(() => engine.markShown(start), throwsStateError);
      expect(
        () => engine.submit(response: 'circle', at: start),
        throwsStateError,
      );
    });
  });

  group('作答与 RT', () {
    test('markShown 后才能作答；RT 从 markShown 算到提交', () {
      final engine = engineFor(AssessmentTaskIds.fastSimpleI);
      final start = DateTime(2026, 1, 1, 9);
      engine.markShown(start);
      expect(engine.awaitingResponse, isTrue);
      final expected = engine.current!.expectedResponse! as String;
      final result = engine.submit(
        response: expected,
        at: start.add(const Duration(milliseconds: 250)),
      );
      expect(result.rtMs, 250);
      expect(result.correct, isTrue);
      expect(result.trialIndex, 0);
      expect(result.isPractice, isTrue);
      expect(result.response, <String, Object?>{'choice': expected});
      expect(engine.recorded, hasLength(1));
      expect(engine.trialIndex, 1);
      expect(engine.current, same(engine.trials[1]));
      expect(engine.awaitingResponse, isFalse);
    });

    test('未 markShown 就 submit 抛 StateError', () {
      final engine = engineFor(AssessmentTaskIds.fastSimpleI);
      expect(
        () => engine.submit(response: 'circle', at: DateTime(2026, 1, 1)),
        throwsStateError,
      );
      expect(engine.recorded, isEmpty);
      expect(engine.trialIndex, 0);
    });

    test('提交时间早于 markShown 时 RT 归零，不产生负值', () {
      final engine = engineFor(AssessmentTaskIds.fastSimpleI);
      final start = DateTime(2026, 1, 1, 9);
      engine.markShown(start);
      final result = engine.submit(
        response: engine.current!.expectedResponse,
        at: start.subtract(const Duration(milliseconds: 90)),
      );
      expect(result.rtMs, 0);
    });

    test('再次 markShown 会把 RT 起点重置到最新一次', () {
      final engine = engineFor(AssessmentTaskIds.fastSimpleI);
      final start = DateTime(2026, 1, 1, 9);
      engine.markShown(start);
      engine.markShown(start.add(const Duration(milliseconds: 500)));
      final result = engine.submit(
        response: engine.current!.expectedResponse,
        at: start.add(const Duration(milliseconds: 700)),
      );
      expect(result.rtMs, 200);
    });

    test('答错判 correct=false，choice 用字符串或 Map 传入都能判', () {
      final engine = engineFor(AssessmentTaskIds.fastSimpleI);
      final start = DateTime(2026, 1, 1, 9);
      engine.markShown(start);
      final expected = engine.current!.expectedResponse! as String;
      final wrong = expected == 'circle' ? 'square' : 'circle';
      final first = engine.submit(response: wrong, at: start);
      expect(first.correct, isFalse);
      // 第二张用 Map 形式提交正确 choice。
      engine.markShown(start);
      final secondExpected = engine.current!.expectedResponse! as String;
      final second = engine.submit(
        response: <String, Object?>{'choice': secondExpected},
        at: start.add(const Duration(milliseconds: 100)),
      );
      expect(second.correct, isTrue);
      expect(second.response, <String, Object?>{'choice': secondExpected});
    });
  });

  group('练习阶段', () {
    test('前 8 张是练习，提交完才进正式阶段', () {
      final engine = engineFor(AssessmentTaskIds.fastSimpleI);
      final start = DateTime(2026, 1, 1, 9);
      final practiceCount = taskOf(AssessmentTaskIds.fastSimpleI)
          .config['practice_trials']! as int;
      expect(practiceCount, 8);
      for (var index = 0; index < practiceCount; index++) {
        expect(engine.isPracticePhase, isTrue);
        engine.markShown(start);
        final trial = engine.current!;
        final result = engine.submit(
          response: trial.expectedResponse,
          at: start,
        );
        expect(result.isPractice, isTrue);
        expect(result.stimulus, trial.stimulus);
      }
      expect(engine.trialIndex, practiceCount);
      expect(engine.isPracticePhase, isFalse);
      expect(engine.recorded, hasLength(practiceCount));
      expect(engine.recorded.every((result) => result.isMeasured), isFalse);
    });
  });
  group('超时', () {
    AssessmentRunEngine singleChoiceEngine() => AssessmentRunEngine(
          task: customTask(
            taskId: 'single_choice',
            taskType: AssessmentTaskType.choiceReaction,
            config: const <String, Object?>{
              'trials': 1,
              'practice_trials': 0,
              'options': <String>['circle', 'square'],
            },
          ),
          seed: 4,
          startedAt: DateTime(2026, 1, 1),
        );

    AssessmentRunEngine singleGoNogoEngine({required double goRatio}) =>
        AssessmentRunEngine(
          task: customTask(
            taskId: 'single_go_nogo',
            taskType: AssessmentTaskType.goNogo,
            config: <String, Object?>{
              'trials': 1,
              'practice_trials': 0,
              'go_ratio': goRatio,
              'response_window_ms': 1500,
            },
          ),
          seed: 4,
          startedAt: DateTime(2026, 1, 1),
        );

    test('no-go 不点算正确：correct=true 且没有 RT', () {
      final engine = singleGoNogoEngine(goRatio: 0);
      final start = DateTime(2026, 1, 1, 9);
      expect(engine.current!.expectedResponse, isFalse);
      engine.markShown(start);
      final result = engine.submitTimeout(
        at: start.add(const Duration(milliseconds: 1500)),
      );
      expect(result.correct, isTrue);
      expect(result.rtMs, isNull);
      expect(result.response, isEmpty);
      expect(engine.isFinished, isTrue);
    });

    test('该点没点算错误（go trial 超时）', () {
      final engine = singleGoNogoEngine(goRatio: 1);
      final start = DateTime(2026, 1, 1, 9);
      expect(engine.current!.expectedResponse, isTrue);
      engine.markShown(start);
      final result = engine.submitTimeout(at: start);
      expect(result.correct, isFalse);
      expect(result.rtMs, isNull);
    });

    test('选择题超时一律算错', () {
      final engine = singleChoiceEngine();
      final start = DateTime(2026, 1, 1, 9);
      engine.markShown(start);
      final result = engine.submitTimeout(at: start);
      expect(result.correct, isFalse);
      expect(result.rtMs, isNull);
      expect(result.response, isEmpty);
    });

    test('超时前也必须 markShown', () {
      final engine = singleChoiceEngine();
      expect(
        () => engine.submitTimeout(at: DateTime(2026, 1, 1)),
        throwsStateError,
      );
    });

    test('超时后队列前进；全部做完后再操作抛 StateError', () {
      final engine = singleChoiceEngine();
      final start = DateTime(2026, 1, 1, 9);
      engine.markShown(start);
      engine.submitTimeout(at: start);
      expect(engine.isFinished, isTrue);
      expect(engine.current, isNull);
      expect(engine.recorded, hasLength(1));
      expect(() => engine.markShown(start), throwsStateError);
      expect(
        () => engine.submit(response: 'circle', at: start),
        throwsStateError,
      );
      expect(() => engine.submitTimeout(at: start), throwsStateError);
    });
  });

  group('Bool 与序列判分', () {
    test('go/no-go 的 bool 作答归一化成 pressed', () {
      final engine = AssessmentRunEngine(
        task: customTask(
          taskId: 'single_go',
          taskType: AssessmentTaskType.goNogo,
          config: const <String, Object?>{
            'trials': 1,
            'practice_trials': 0,
            'go_ratio': 1.0,
          },
        ),
        seed: 2,
        startedAt: DateTime(2026, 1, 1),
      );
      final start = DateTime(2026, 1, 1, 9);
      engine.markShown(start);
      final result = engine.submit(
        response: true,
        at: start.add(const Duration(milliseconds: 300)),
      );
      expect(result.correct, isTrue);
      expect(result.response, <String, Object?>{'pressed': true});
    });

    test('字符串 tap / withhold 也能判 go/no-go', () {
      final engine = AssessmentRunEngine(
        task: customTask(
          taskId: 'single_go_string',
          taskType: AssessmentTaskType.goNogo,
          config: const <String, Object?>{
            'trials': 1,
            'practice_trials': 0,
            'go_ratio': 1.0,
          },
        ),
        seed: 2,
        startedAt: DateTime(2026, 1, 1),
      );
      final start = DateTime(2026, 1, 1, 9);
      engine.markShown(start);
      final result = engine.submit(response: 'tap', at: start);
      expect(result.correct, isTrue);
      expect(result.response, <String, Object?>{'choice': 'tap'});
    });

    test('digit_span 的答案是倒序字符串', () {
      final engine = engineFor(AssessmentTaskIds.digitSpanBackward);
      final start = DateTime(2026, 1, 1, 9);
      final trial = engine.current!;
      final expected = trial.expectedResponse! as String;
      final digits = (trial.stimulus['digits']! as List).cast<int>();
      expect(expected, digits.reversed.join());
      engine.markShown(start);
      final result = engine.submit(response: expected, at: start);
      expect(result.correct, isTrue);
    });
  });
  group('不可变与结构', () {
    test('trials 与 recorded 对外只读', () {
      final engine = engineFor(AssessmentTaskIds.fastSimpleI);
      expect(
        () => engine.trials.add(engine.trials.first),
        throwsUnsupportedError,
      );
      final start = DateTime(2026, 1, 1, 9);
      engine.markShown(start);
      engine.submit(response: engine.current!.expectedResponse, at: start);
      expect(
        () => engine.recorded.add(engine.recorded.first),
        throwsUnsupportedError,
      );
    });

    test('TrialResult 带着原 trial 的 blockIndex / stimulus / isPractice', () {
      final engine = engineFor(AssessmentTaskIds.fatigueBlock);
      final start = DateTime(2026, 1, 1, 9);
      final trial = engine.current!;
      engine.markShown(start);
      final result = engine.submit(response: true, at: start);
      expect(result.trialIndex, trial.trialIndex);
      expect(result.blockIndex, trial.blockIndex);
      expect(result.stimulus, trial.stimulus);
      expect(result.isPractice, trial.isPractice);
      expect(result.timestamp, start);
    });
  });
}
