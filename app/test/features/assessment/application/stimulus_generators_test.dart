import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/features/assessment/application/stimulus_generators.dart';
import 'package:furnace/features/assessment/application/task_registry.dart';
import 'package:furnace/features/assessment/domain/assessment_models.dart';

/// 刺激生成器的验收标准：**确定性**（同 seed 逐 trial 相同）、**练习先行**、
/// **试次数与配置一致**、**每个任务的刺激/期望反应形态正确**。
///
/// 这些断言刻意钉具体值（比例、阶梯、类型），因为随机序列一旦漂移，评测的
/// 历史数据就不可比——不是「大概随机就行」。
void main() {
  AssessmentTaskConfig taskOf(String taskId) {
    final task = defaultAssessmentTask(taskId);
    expect(task, isNotNull, reason: '注册表缺少任务 $taskId');
    return task!;
  }

  List<PlannedTrial> generate(String taskId, {int seed = 7}) =>
      generatePlannedTrials(task: taskOf(taskId), seed: seed);

  List<PlannedTrial> measuredOnly(String taskId, {int seed = 7}) =>
      generate(taskId, seed: seed).where((trial) => !trial.isPractice).toList();

  List<Object?> serialized(List<PlannedTrial> trials) =>
      <Object?>[for (final trial in trials) trial.toJson()];

  group('确定性', () {
    test('同一个 seed 生成完全相同的 trial 序列', () {
      for (final taskId in AssessmentTaskIds.all) {
        expect(
          serialized(generate(taskId, seed: 42)),
          equals(serialized(generate(taskId, seed: 42))),
          reason: '$taskId 同 seed 的结果不稳定',
        );
      }
    });

    test('不同 seed 产生不同刺激（不把 seed 当摆设）', () {
      for (final taskId in <String>[
        AssessmentTaskIds.fastSimpleI,
        AssessmentTaskIds.goNogo,
        AssessmentTaskIds.stroopCrosslang,
        AssessmentTaskIds.taskSwitching,
      ]) {
        expect(
          serialized(generate(taskId, seed: 1)),
          isNot(equals(serialized(generate(taskId, seed: 2)))),
          reason: '$taskId 换 seed 刺激没变',
        );
      }
    });
  });

  group('练习先行与试次数', () {
    test('练习 trial 全部排在最前且标 isPractice', () {
      for (final taskId in AssessmentTaskIds.all) {
        final trials = generate(taskId);
        var seenMeasured = false;
        for (final trial in trials) {
          if (!trial.isPractice) {
            seenMeasured = true;
          } else {
            expect(seenMeasured, isFalse,
                reason: '$taskId 的练习 trial 出现在正式 trial 之后');
          }
        }
      }
    });

    test('trialIndex 是 0..n-1 的连续序列', () {
      for (final taskId in AssessmentTaskIds.all) {
        final trials = generate(taskId);
        expect(
          <int>[for (final trial in trials) trial.trialIndex],
          <int>[for (var index = 0; index < trials.length; index++) index],
          reason: '$taskId 的 trialIndex 不连续',
        );
      }
    });

    test('总 trial 数 = 练习数 + 正式数（逐任务钉住）', () {
      const expectedTotal = <String, int>{
        AssessmentTaskIds.fastSimpleI: 38,
        AssessmentTaskIds.fastSimpleIi: 38,
        AssessmentTaskIds.fastSimpleIii: 38,
        AssessmentTaskIds.goNogo: 78,
        AssessmentTaskIds.digitSpanBackward: 14,
        AssessmentTaskIds.nBack2: 68,
        AssessmentTaskIds.stroopCrosslang: 56,
        AssessmentTaskIds.taskSwitching: 78,
        AssessmentTaskIds.fatigueBlock: 93,
        AssessmentTaskIds.decisionFatigue: 80,
      };
      for (final entry in expectedTotal.entries) {
        expect(generate(entry.key), hasLength(entry.value),
            reason: '${entry.key} 的 trial 数不对');
      }
    });

    test('练习 trial 复用正式 trial 的刺激（不是另一套）', () {
      final trials = generate(AssessmentTaskIds.fastSimpleI);
      final practiceCount = taskOf(AssessmentTaskIds.fastSimpleI)
          .config['practice_trials']! as int;
      for (var index = 0; index < practiceCount; index++) {
        expect(trials[index].stimulus, trials[practiceCount + index].stimulus);
        expect(
          trials[index].expectedResponse,
          trials[practiceCount + index].expectedResponse,
        );
      }
    });
  });

  group('fast_simple_task_i（图形分类）', () {
    test('圆/方各半，期望值就是图形本身', () {
      final trials = measuredOnly(AssessmentTaskIds.fastSimpleI);
      final shapes = <String>[
        for (final trial in trials) trial.stimulus['shape']! as String,
      ];
      expect(shapes.where((s) => s == 'circle'), hasLength(15));
      expect(shapes.where((s) => s == 'square'), hasLength(15));
      for (final trial in trials) {
        expect(trial.stimulus['options'], <String>['circle', 'square']);
        expect(trial.expectedResponse, trial.stimulus['shape']);
        expect(trial.condition['shape'], trial.stimulus['shape']);
      }
    });
  });

  group('fast_simple_task_ii（计算分类）', () {
    test('算式的和决定 yes/no，左右数字与和自洽', () {
      final trials = measuredOnly(AssessmentTaskIds.fastSimpleIi);
      for (final trial in trials) {
        final left = trial.stimulus['left']! as int;
        final right = trial.stimulus['right']! as int;
        final sum = trial.stimulus['sum']! as int;
        expect(left + right, sum);
        expect(sum, greaterThan(0));
        expect(trial.stimulus['expression'], '$left + $right');
        expect(trial.expectedResponse, sum > 6 ? 'yes' : 'no');
        expect(trial.stimulus['options'], <String>['yes', 'no']);
      }
    });

    test('大于 6 与不大于 6 的 trial 各半', () {
      final trials = measuredOnly(AssessmentTaskIds.fastSimpleIi);
      final greater =
          trials.where((trial) => trial.expectedResponse == 'yes').length;
      expect(greater, trials.length ~/ 2);
    });
  });

  group('fast_simple_task_iii（同异判断）', () {
    test('左右图形相同则 same，否则 different', () {
      final trials = measuredOnly(AssessmentTaskIds.fastSimpleIii);
      for (final trial in trials) {
        final left = trial.stimulus['left_shape'];
        final right = trial.stimulus['right_shape'];
        expect(trial.expectedResponse, left == right ? 'same' : 'different');
      }
      expect(trials.where((t) => t.expectedResponse == 'same'), hasLength(15));
    });
  });

  group('go_nogo', () {
    test('Go 比例 0.7，圆=点、方=不点', () {
      final trials = measuredOnly(AssessmentTaskIds.goNogo);
      final goTrials =
          trials.where((trial) => trial.expectedResponse == true).toList();
      expect(goTrials, hasLength(49));
      for (final trial in trials) {
        final shape = trial.stimulus['shape']! as String;
        expect(trial.expectedResponse, shape == 'circle');
        expect(trial.stimulus['options'], <String>['tap', 'withhold']);
        expect(trial.condition['should_tap'], trial.expectedResponse);
      }
    });
  });

  group('digit_span_backward', () {
    test('3..9 每个长度各 2 次，倒背答案正确', () {
      final trials = measuredOnly(AssessmentTaskIds.digitSpanBackward);
      expect(trials, hasLength(14));
      final lengths = <int>[];
      for (final trial in trials) {
        final digits = (trial.stimulus['digits']! as List).cast<int>();
        final length = trial.stimulus['length']! as int;
        lengths.add(length);
        expect(digits, hasLength(length));
        expect(length, greaterThanOrEqualTo(3));
        expect(length, lessThanOrEqualTo(9));
        expect(digits.first, inInclusiveRange(1, 9));
        for (final digit in digits) {
          expect(digit, inInclusiveRange(0, 9));
        }
        expect(trial.expectedResponse, digits.reversed.join());
      }
      for (var length = 3; length <= 9; length++) {
        expect(lengths.where((value) => value == length), hasLength(2));
      }
    });
  });
  group('n_back_2', () {
    test('前 n 个无匹配，其中约 35% 匹配且匹配定义正确', () {
      final trials = measuredOnly(AssessmentTaskIds.nBack2);
      expect(trials.take(2).every((trial) => trial.expectedResponse == false),
          isTrue);
      final matches = <int>[];
      for (var index = 0; index < trials.length; index++) {
        final trial = trials[index];
        final sequence = (trial.stimulus['sequence']! as List).cast<String>();
        expect(sequence, hasLength(index + 1));
        final expected = index >= 2 && sequence[index] == sequence[index - 2];
        expect(trial.expectedResponse, expected);
        if (expected) matches.add(index);
      }
      final ratio = matches.length / (trials.length - 2);
      expect(ratio, greaterThanOrEqualTo(0.2));
      expect(ratio, lessThanOrEqualTo(0.5));
    });
  });

  group('stroop_crosslang', () {
    test('三类比例、钓鱼中英混搭，期望是字体颜色', () {
      final trials = measuredOnly(AssessmentTaskIds.stroopCrosslang);
      final kinds = <String, int>{};
      for (final trial in trials) {
        final kind = trial.condition['kind']! as String;
        kinds[kind] = (kinds[kind] ?? 0) + 1;
        final ink = trial.stimulus['ink']! as String;
        expect(ink, anyOf('red', 'blue'));
        expect(trial.expectedResponse, ink);
        expect(trial.stimulus['options'], <String>['red', 'blue']);
        final word = trial.stimulus['word']! as String;
        switch (kind) {
          case 'congruent':
            expect(word, anyOf('红', '蓝'));
            expect(trial.condition['word_ink'], ink);
            break;
          case 'conflict':
            expect(word, anyOf('红', '蓝'));
            expect(trial.condition['word_ink'], isNot(ink));
            break;
          case 'fish':
            expect(word, anyOf('RED', 'BLUE'));
            expect(trial.condition['word_ink'], ink);
            break;
        }
      }
      expect(kinds['congruent'], 22);
      expect(kinds['conflict'], 15);
      expect(kinds['fish'], 13);
    });
  });

  group('task_switching', () {
    test('线索切换时换规则，期望值跟随当前线索', () {
      final trials = measuredOnly(AssessmentTaskIds.taskSwitching);
      var switches = 0;
      var repeats = 0;
      String? previousCue;
      for (final trial in trials) {
        final cue = trial.stimulus['cue']! as String;
        final switched = trial.condition['switched']! as bool;
        if (previousCue != null) {
          expect(switched, cue != previousCue);
          if (switched) {
            switches++;
          } else {
            repeats++;
          }
        }
        if (cue == 'parity') {
          // 奇偶线索给的是数字，大小写线索给的是字母。
          final number = trial.stimulus['value']! as int;
          expect(trial.expectedResponse, number.isOdd ? 'odd' : 'even');
        } else {
          final value = trial.stimulus['value']! as String;
          expect(
            trial.expectedResponse,
            value == value.toUpperCase() ? 'upper' : 'lower',
          );
        }
        previousCue = cue;
      }
      expect(switches, greaterThan(0));
      expect(repeats, greaterThan(0));
    });
  });

  group('fatigue_block', () {
    test('3 段 x 30 trial，块序号递增且期望全为按键', () {
      final trials = measuredOnly(AssessmentTaskIds.fatigueBlock);
      expect(trials, hasLength(90));
      final blocks = <int>{};
      for (var index = 0; index < trials.length; index++) {
        final trial = trials[index];
        final blockIndex = trial.blockIndex;
        blocks.add(blockIndex);
        expect(blockIndex, index ~/ 30);
        expect(trial.condition['block_index'], blockIndex);
        expect(trial.condition['trial_in_block'], index % 30);
        expect(trial.expectedResponse, true);
      }
      expect(blocks, <int>{0, 1, 2});
    });
  });

  group('decision_fatigue', () {
    test('两个数字不相等，期望是较大的一侧', () {
      final trials = measuredOnly(AssessmentTaskIds.decisionFatigue);
      for (final trial in trials) {
        final left = trial.stimulus['left']! as int;
        final right = trial.stimulus['right']! as int;
        expect(left, isNot(right));
        expect(trial.expectedResponse, left > right ? 'left' : 'right');
      }
    });
  });

  group('TaskRunParameters 与兜底', () {
    test('fromConfig 解析契约键，缺失键用默认值', () {
      final params = TaskRunParameters.fromConfig(<String, Object?>{
        'trials': 12,
        'practice_trials': 3,
        'isi_min_ms': 400,
        'isi_max_ms': 900,
        'response_window_ms': 1234,
        'options': <Object?>['a', ' b ', 3],
        'go_ratio': 0.6,
        'n': 3,
        'match_ratio': 0.4,
        'lengths': <Object?>[2, 3],
      });
      expect(params.trials, 12);
      expect(params.practiceTrials, 3);
      expect(params.isiMinMs, 400);
      expect(params.isiMaxMs, 900);
      expect(params.responseWindowMs, 1234);
      expect(params.options, <String>['a', 'b']);
      expect(params.goRatio, 0.6);
      expect(params.n, 3);
      expect(params.matchRatio, 0.4);
      expect(params.digitSpanLengths, <int>[2, 3]);
      expect(params.blocks, 1);
      expect(params.digitSpanStartLength, 3);
    });

    test('坏配置不抛异常：类型不对走默认值，负数块数回退', () {
      final params = TaskRunParameters.fromConfig(<String, Object?>{
        'trials': 'many',
        'blocks': -3,
        'options': 'circle',
        'lengths': <Object?>['x'],
      });
      expect(params.trials, 0);
      expect(params.blocks, 1);
      expect(params.options, isEmpty);
      expect(params.digitSpanLengths, <int>[3, 4, 5, 6, 7, 8, 9]);
    });

    test('未知 taskId 按 taskType 兜底，而不是返回空队列', () {
      final trials = generatePlannedTrials(
        task: const AssessmentTaskConfig(
          taskId: 'custom_fast',
          displayName: '自定义',
          taskType: AssessmentTaskType.choiceReaction,
          estimatedDurationSeconds: 60,
          config: <String, Object?>{
            'trials': 5,
            'practice_trials': 1,
            'options': <String>['circle', 'square'],
          },
          producedMetrics: <String>[MetricNames.rtMedian],
          qualityChecks: <String>[],
        ),
        seed: 5,
      );
      expect(trials, hasLength(6));
      expect(trials.first.isPractice, isTrue);
    });

    test('返回的 trial 列表不可变', () {
      final trials = generate(AssessmentTaskIds.fastSimpleI);
      expect(
        () => trials.add(trials.first),
        throwsUnsupportedError,
      );
    });
  });
}
