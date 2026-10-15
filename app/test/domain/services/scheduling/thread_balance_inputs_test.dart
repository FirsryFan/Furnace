import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/scheduling/domain_balance.dart';
import 'package:furnace/domain/services/scheduling/thread_balance_inputs.dart';

void main() {
  ObjectTagLink kp(String tagId, String id) =>
      ObjectTagLink(tagId: tagId, objectType: 'knowledge_point', objectId: id);

  ObjectTagLink task(String tagId, String id) =>
      ObjectTagLink(tagId: tagId, objectType: 'task', objectId: id);

  group('task -> knowledge point resolution (shared tag)', () {
    test('a task and a knowledge point on the same tag are linked', () {
      final resolved = TaskKnowledgePointResolver.resolveFromTagLinks([
        task('t-math', 'task-1'),
        kp('t-math', 'kp-derivative'),
      ]);

      expect(resolved.keys.toList(), ['task-1']);
      expect(resolved['task-1'], ['kp-derivative']);
    });

    test('several tags add up (union, never intersection)', () {
      final resolved = TaskKnowledgePointResolver.resolveFromTagLinks([
        task('t-math', 'task-1'),
        task('t-func', 'task-1'),
        kp('t-math', 'kp-derivative'),
        kp('t-func', 'kp-monotonic'),
      ]);

      expect(resolved['task-1'], ['kp-derivative', 'kp-monotonic']);
    });

    test('a task whose tag carries no knowledge point is omitted', () {
      final resolved = TaskKnowledgePointResolver.resolveFromTagLinks([
        task('t-math', 'task-1'),
        kp('t-physics', 'kp-kinematics'), // different tag, different task
      ]);

      expect(resolved, isEmpty);
    });

    test('only task and knowledge_point link types are read', () {
      final resolved = TaskKnowledgePointResolver.resolveFromTagLinks([
        const ObjectTagLink(
            tagId: 't-math',
            objectType: 'card_template',
            objectId: 'template-1'),
        kp('t-math', 'kp-derivative'),
        const ObjectTagLink(
            tagId: 't-math', objectType: 'mind_map', objectId: 'map-1'),
      ]);

      // The template and the mind map are ignored: no task is linked.
      expect(resolved, isEmpty);
    });

    test('duplicate links collapse and the result is sorted', () {
      final resolved = TaskKnowledgePointResolver.resolveFromTagLinks([
        task('t-b', 'task-b'),
        task('t-a', 'task-a'),
        kp('t-b', 'kp-2'),
        kp('t-b', 'kp-2'),
        kp('t-a', 'kp-1'),
      ]);

      expect(resolved.keys.toList(), ['task-a', 'task-b']);
      expect(resolved['task-a'], ['kp-1']);
      expect(resolved['task-b'], ['kp-2']);
    });

    test('input order does not change the output', () {
      final forward = TaskKnowledgePointResolver.resolveFromTagLinks([
        task('t-a', 'task-a'),
        task('t-b', 'task-b'),
        kp('t-b', 'kp-2'),
        kp('t-a', 'kp-1'),
      ]);
      final reversed = TaskKnowledgePointResolver.resolveFromTagLinks([
        kp('t-a', 'kp-1'),
        kp('t-b', 'kp-2'),
        task('t-b', 'task-b'),
        task('t-a', 'task-a'),
      ]);

      expect(forward.keys.toList(), reversed.keys.toList());
      expect(forward['task-a'], reversed['task-a']);
      expect(forward['task-b'], reversed['task-b']);
    });

    test('blank tag / object ids are ignored instead of throwing', () {
      final resolved = TaskKnowledgePointResolver.resolveFromTagLinks([
        task('  ', 'task-1'),
        task('t-math', ''),
        task('t-math', 'task-1'),
        kp('t-math', ' kp-derivative '),
      ]);

      expect(resolved, {
        'task-1': ['kp-derivative']
      });
    });
  });

  group('ThreadBalanceInputs (defaults are "know nothing")', () {
    test('empty inputs carry no data and say so', () {
      const inputs = ThreadBalanceInputs.empty;

      expect(inputs.isEmpty, isTrue);
      expect(inputs.hasData, isFalse);
      expect(inputs.taskKnowledgePoints, isEmpty);
      expect(inputs.readings, isEmpty);
      expect(inputs.tags, isEmpty);
      expect(inputs.taskTagLinks, isEmpty);
      expect(inputs.windowSlots, null);
      expect(inputs.weights.effectiveness, const DomainBalanceWeights().effectiveness);
      expect(inputs.tuning.neutral, const EffectivenessTuning().neutral);
    });

    test('one piece of data makes it non-empty, copyWith can replace it', () {
      final inputs = const ThreadBalanceInputs().copyWith(
        taskKnowledgePoints: {
          'task-1': ['kp-1']
        },
      );

      expect(inputs.hasData, isTrue);
      expect(inputs.isEmpty, isFalse);
      expect(inputs.describe(), contains('tasks=1'));
      expect(inputs.readings, isEmpty);
    });
  });
}
