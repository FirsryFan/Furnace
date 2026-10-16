import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/ingest/run_executor.dart';
import 'package:furnace/domain/services/ingest/run_reading.dart';

/// 一条动作的痕迹：`delta` 就是引擎回报的那份增量。
RunActionTrace traceOf({
  String kind = 'review',
  Map<String, Object?> delta = const <String, Object?>{},
  String? error,
}) =>
    RunActionTrace(
      index: 0,
      kind: kind,
      mechanism: kind,
      summary: '一件做过的事',
      delta: delta,
      error: error,
    );

void main() {
  group('演练读数：把引擎回报的增量折成人话', () {
    test('记忆层那一段 R/S/D 摆成一行，认得出前后', () {
      final reading = traceReadingOf(traceOf(delta: const <String, Object?>{
        'mechanism': 'context.memory',
        'kind': 'review',
        'R_at_review': 0.42,
        'R_after': 0.78,
        'R0_after': 0.8,
        'S_after': 4.0,
        'Sigma_after': 0.8,
        'D_after': 5.0,
        'S_increase': 0.9,
      }));

      expect(reading, startsWith('记忆层读数（review）'));
      expect(reading, contains('R 0.42 → 0.78'));
      expect(reading, contains('S 4（+0.9）'));
      expect(reading, contains('R0 0.8'));
      expect(reading, contains('Σ 0.8'));
      expect(reading, contains('D 5'));
    });

    test('记忆层没回报复习时的 R 时，也照样说得出改成了什么', () {
      final reading = traceReadingOf(traceOf(delta: const <String, Object?>{
        'R_after': 0.9,
        'S_after': 2.5,
        'S_increase': -0.1,
      }));

      expect(reading, contains('R → 0.9'));
      expect(reading, contains('S 2.5（-0.1）'));
      expect(reading, isNot(contains('—')));
    });

    test('没装机制（空增量）就没有读数 —— 不编一行"看起来像变化"的话', () {
      expect(traceReadingOf(traceOf()), '');
    });

    test('这一条没跑成时也没有读数（人话在 text 里）', () {
      expect(
        traceReadingOf(traceOf(
          kind: 'review',
          delta: const <String, Object?>{'R_after': 0.9},
          error: '指向图里不存在的节点 "kp"',
        )),
        '',
      );
    });

    test('时间推进那一跑的读数：每个节点现在的可提取度 + 同步了几个', () {
      final reading = traceReadingOf(traceOf(
        kind: 'time',
        delta: const <String, Object?>{
          'synced_nodes': 2,
          'nodes': 2,
          'ms': <String, Object?>{'b': 0.65, 'a': 0.8},
        },
      ));

      expect(reading, '可提取度：a 0.8、b 0.65（同步 2/2 个）');
    });

    test('节点一多就只列前几个，剩下说出总数', () {
      final reading = traceReadingOf(traceOf(
        kind: 'time',
        delta: <String, Object?>{
          'synced_nodes': 5,
          'nodes': 5,
          'ms': <String, Object?>{
            'a': 0.1,
            'b': 0.2,
            'c': 0.3,
            'd': 0.4,
            'e': 0.5,
          },
        },
      ));

      expect(reading, contains('a 0.1、b 0.2、c 0.3、d 0.4'));
      expect(reading, contains('、…（共 5 个）'));
      expect(reading, isNot(contains('e 0.5')));
      expect(reading, contains('同步 5/5'));
    });

    test('扩散那一跑：起点、目标、轮次归零', () {
      final reading = traceReadingOf(traceOf(
        kind: 'goal',
        delta: const <String, Object?>{
          'starts': <String>['a', 'b'],
          'targets': <String>['c'],
          'rounds_reset': true,
        },
      ));

      expect(reading, '扩散：起点 a、b → 目标 c（轮次归零）');
    });

    test('扩散没给起点时说清用的是图里原来的', () {
      final reading = traceReadingOf(traceOf(
        kind: 'goal',
        delta: const <String, Object?>{
          'targets': <String>['c'],
        },
      ));

      expect(reading, contains('起点 （没给，用图里原来的）'));
    });

    test('新建节点：引擎回报的那个节点长什么样', () {
      final reading = traceReadingOf(traceOf(
        kind: 'knowledge',
        delta: const <String, Object?>{
          'added': 'node',
          'node': <String, Object?>{
            'id': 'kp',
            'name': '说过的一句话',
            'type': 'concept',
            'ms': 0.8,
          },
        },
      ));

      expect(reading, '新增节点 kp（说过的一句话 / concept / ms 0.8）');
    });

    test('新建边：两端与 ls', () {
      final reading = traceReadingOf(traceOf(
        kind: 'knowledge',
        delta: const <String, Object?>{
          'added': 'edge',
          'edge': <String, Object?>{
            'id': 'e_1_a_b',
            'from': 'a',
            'to': 'b',
            'ls': 0.8,
          },
        },
      ));

      expect(reading, '新增边 a → b（ls 0.8，e_1_a_b）');
    });

    test('认不出来的形状把键值列出来，不吞掉', () {
      final reading = traceReadingOf(traceOf(delta: const <String, Object?>{
        'something_new': 3,
        'list': <Object?>[1, 'x'],
      }));

      expect(reading, '增量：list=[1、x]、something_new=3');
    });

    test('小数留三位、去掉尾部零（0.800 → 0.8、3.000 → 3）', () {
      final reading = traceReadingOf(traceOf(delta: const <String, Object?>{
        'R_after': 0.8000,
        'S_after': 3.000,
        'S_increase': 0.12345,
      }));

      expect(reading, contains('R → 0.8'));
      expect(reading, contains('S 3（+0.123）'));
    });
  });
}
