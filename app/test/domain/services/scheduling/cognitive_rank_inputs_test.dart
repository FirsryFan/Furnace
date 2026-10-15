import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/cloze/diffusion_boost.dart';
import 'package:furnace/domain/services/scheduling/cognitive_rank.dart';
import 'package:furnace/domain/services/scheduling/cognitive_rank_inputs.dart';

/// 手搭的标签树，边与 `DiffusionBoost` 一致（父↔子、同父兄弟都算 1 跳）：
///
/// ```
/// phi ── mech  ── (兄弟) mech2 ── sub ── far
/// ```
///
/// 从 `mech` 出发的距离：`mech` 0、`phi` / `mech2` 1、`sub` 2、`far` 3。
const List<MindNodeInfo> _nodes = <MindNodeInfo>[
  MindNodeInfo(id: 'phi'),
  MindNodeInfo(id: 'mech', parentId: 'phi'),
  MindNodeInfo(id: 'mech2', parentId: 'phi'),
  MindNodeInfo(id: 'sub', parentId: 'mech2'),
  MindNodeInfo(id: 'far', parentId: 'sub'),
];

CognitiveRankSeed _seed({
  double availability = 1,
  String? goalNodeId,
  List<String> active = const <String>[],
  Map<String, List<String>> tagIds = const <String, List<String>>{},
  Map<String, String> names = const <String, String>{},
  List<MindNodeInfo>? nodes,
}) {
  return CognitiveRankSeed(
    availability: availability,
    tagNodes: nodes ?? _nodes,
    goalNodeId: goalNodeId,
    activeKnowledgePointIds: active,
    knowledgePointTagIds: tagIds,
    knowledgePointNames: names,
  );
}

CognitiveRankOrigin? _originFor(
  CognitiveRankInputs inputs,
  String knowledgePointId,
) =>
    inputs.originByKnowledgePoint[knowledgePointId];

void main() {
  group('CognitiveRankWiring.build', () {
    test('没有起点时等于没开：一个 origin 都不写，次序原样', () {
      final inputs = CognitiveRankWiring.build(
        seed: _seed(tagIds: const {
          'kp1': ['mech']
        }),
        candidates: const [
          CognitiveRankCandidate(taskId: 't1', knowledgePointIds: ['kp1']),
          CognitiveRankCandidate(taskId: 't2', baseIndex: 1),
        ],
      );

      expect(inputs.originByKnowledgePoint, isEmpty);
      final output = CognitiveRank.rank(
        candidates: const [
          CognitiveRankCandidate(taskId: 't1', knowledgePointIds: ['kp1']),
          CognitiveRankCandidate(taskId: 't2', baseIndex: 1),
        ],
        inputs: inputs,
      );
      expect(
        output.ranked.map((hit) => hit.taskId).toList(),
        <String>['t1', 't2'],
      );
      expect(output.ranked.every((hit) => hit.score == 1.0), isTrue);
    });

    test('目标标签就是知识点自己的标签：0 跳 + goal', () {
      final inputs = CognitiveRankWiring.build(
        seed: _seed(goalNodeId: 'mech', tagIds: const {
          'kp1': ['mech']
        }),
        candidates: const [
          CognitiveRankCandidate(taskId: 't1', knowledgePointIds: ['kp1']),
        ],
      );

      final origin = _originFor(inputs, 'kp1')!;
      expect(origin.hops, 0);
      expect(origin.link, CognitiveRankLink.goal);
    });

    test('刚活动的知识点自己的标签：0 跳 + activity', () {
      final inputs = CognitiveRankWiring.build(
        seed: _seed(
          active: const ['kp1'],
          tagIds: const {
            'kp1': ['mech']
          },
        ),
        candidates: const [
          CognitiveRankCandidate(taskId: 't1', knowledgePointIds: ['kp1']),
        ],
      );

      final origin = _originFor(inputs, 'kp1')!;
      expect(origin.hops, 0);
      expect(origin.link, CognitiveRankLink.activity);
      expect(origin.viaKnowledgePointId, 'kp1');
    });

    test('1 跳：同父兄弟算 1 跳，via 是那个刚活动的知识点', () {
      final inputs = CognitiveRankWiring.build(
        seed: _seed(
          active: const ['a'],
          tagIds: const {
            'a': ['mech'],
            'b': ['mech2'],
          },
        ),
        candidates: const [
          CognitiveRankCandidate(taskId: 't1', knowledgePointIds: ['b']),
        ],
      );

      final origin = _originFor(inputs, 'b')!;
      expect(origin.hops, 1);
      expect(origin.link, CognitiveRankLink.activity);
      expect(origin.viaKnowledgePointId, 'a');
    });

    test('2 跳以内还在：mech → sub', () {
      final inputs = CognitiveRankWiring.build(
        seed: _seed(
          active: const ['a'],
          tagIds: const {
            'a': ['mech'],
            'b': ['sub'],
          },
        ),
        candidates: const [
          CognitiveRankCandidate(taskId: 't1', knowledgePointIds: ['b']),
        ],
      );

      expect(_originFor(inputs, 'b')!.hops, 2);
    });

    test('3 跳够不着：不写 origin，而不是写一条"很远"', () {
      final inputs = CognitiveRankWiring.build(
        seed: _seed(
          active: const ['a'],
          tagIds: const {
            'a': ['mech'],
            'b': ['far'],
          },
        ),
        candidates: const [
          CognitiveRankCandidate(taskId: 't1', knowledgePointIds: ['b']),
        ],
      );

      expect(inputs.originByKnowledgePoint, isEmpty);
    });

    test('标签不在图上（或图是空的）：不写 origin', () {
      final inputs = CognitiveRankWiring.build(
        seed: _seed(
          active: const ['a'],
          tagIds: const {
            'a': ['mech'],
            'b': ['ghost'],
          },
        ),
        candidates: const [
          CognitiveRankCandidate(taskId: 't1', knowledgePointIds: ['b']),
        ],
      );
      expect(inputs.originByKnowledgePoint, isEmpty);

      final emptyGraph = CognitiveRankWiring.build(
        seed: _seed(
          active: const ['a'],
          nodes: const <MindNodeInfo>[],
          tagIds: const {
            'a': ['mech'],
            'b': ['mech'],
          },
        ),
        candidates: const [
          CognitiveRankCandidate(taskId: 't1', knowledgePointIds: ['b']),
        ],
      );
      expect(emptyGraph.originByKnowledgePoint, isEmpty);
    });

    test('候选知识点没有标签：不写 origin', () {
      final inputs = CognitiveRankWiring.build(
        seed: _seed(active: const [
          'a'
        ], tagIds: const {
          'a': ['mech']
        }),
        candidates: const [
          CognitiveRankCandidate(taskId: 't1', knowledgePointIds: ['b']),
        ],
      );

      expect(inputs.originByKnowledgePoint, isEmpty);
    });

    test('同跳数时刚活动优先于目标', () {
      final inputs = CognitiveRankWiring.build(
        seed: _seed(
          goalNodeId: 'mech2',
          active: const ['a'],
          tagIds: const {
            'a': ['mech'],
            'b': ['phi'],
          },
        ),
        candidates: const [
          CognitiveRankCandidate(taskId: 't1', knowledgePointIds: ['b']),
        ],
      );

      final origin = _originFor(inputs, 'b')!;
      expect(origin.hops, 1);
      expect(origin.link, CognitiveRankLink.activity);
      expect(origin.viaKnowledgePointId, 'a');
    });

    test('目标更近时用目标', () {
      final inputs = CognitiveRankWiring.build(
        seed: _seed(
          goalNodeId: 'sub',
          active: const ['a'],
          tagIds: const {
            'a': ['far'],
            'b': ['mech2'],
          },
        ),
        candidates: const [
          CognitiveRankCandidate(taskId: 't1', knowledgePointIds: ['b']),
        ],
      );

      final origin = _originFor(inputs, 'b')!;
      expect(origin.hops, 1);
      expect(origin.link, CognitiveRankLink.goal);
    });

    test('候选挂多个标签时取最近的一个', () {
      final inputs = CognitiveRankWiring.build(
        seed: _seed(
          active: const ['a'],
          tagIds: const {
            'a': ['mech'],
            'b': ['far', 'mech2'],
          },
        ),
        candidates: const [
          CognitiveRankCandidate(taskId: 't1', knowledgePointIds: ['b']),
        ],
      );

      expect(_originFor(inputs, 'b')!.hops, 1);
    });

    test('多个活动知识点时取最近的那一个，via 说清是谁', () {
      final inputs = CognitiveRankWiring.build(
        seed: _seed(
          active: const ['a', 'b'],
          tagIds: const {
            'a': ['far'],
            'b': ['mech'],
            'c': ['mech2'],
          },
        ),
        candidates: const [
          CognitiveRankCandidate(taskId: 't1', knowledgePointIds: ['c']),
        ],
      );

      final origin = _originFor(inputs, 'c')!;
      expect(origin.hops, 1);
      expect(origin.viaKnowledgePointId, 'b');
    });

    test('结果与输入顺序无关（确定）', () {
      const tagIds = {
        'a': ['far'],
        'b': ['mech2', 'phi'],
        'c': ['sub'],
      };
      final first = CognitiveRankWiring.build(
        seed: _seed(
          active: const ['a', 'b'],
          tagIds: tagIds,
        ),
        candidates: const [
          CognitiveRankCandidate(taskId: 't1', knowledgePointIds: ['c']),
        ],
      );
      final second = CognitiveRankWiring.build(
        seed: _seed(
          active: const ['b', 'a'],
          nodes: _nodes.reversed.toList(),
          tagIds: {
            'c': ['sub'],
            'b': ['phi', 'mech2'],
            'a': ['far'],
          },
        ),
        candidates: const [
          CognitiveRankCandidate(taskId: 't1', knowledgePointIds: ['c']),
        ],
      );

      final a = _originFor(first, 'c')!;
      final b = _originFor(second, 'c')!;
      expect(b.hops, a.hops);
      expect(b.link, a.link);
      expect(b.viaKnowledgePointId, a.viaKnowledgePointId);
    });

    test('名字与 α 透传：接上之后排序真的会动', () {
      final inputs = CognitiveRankWiring.build(
        seed: _seed(
          availability: 0.3,
          active: const ['kp-active'],
          tagIds: const {
            'kp-active': ['mech'],
            'kp-cold': ['mech2'],
          },
          names: const {'kp-active': '动量守恒'},
        ),
        candidates: const [
          CognitiveRankCandidate(
            taskId: 'cold',
            knowledgePointIds: ['kp-cold'],
            difficulty: 1,
          ),
          CognitiveRankCandidate(
            taskId: 'active',
            knowledgePointIds: ['kp-active'],
            difficulty: 1,
            baseIndex: 1,
          ),
        ],
      );

      expect(inputs.availability, 0.3);
      expect(inputs.knowledgePointNames['kp-active'], '动量守恒');

      final output = CognitiveRank.rank(
        candidates: const [
          CognitiveRankCandidate(
            taskId: 'cold',
            knowledgePointIds: ['kp-cold'],
            difficulty: 1,
          ),
          CognitiveRankCandidate(
            taskId: 'active',
            knowledgePointIds: ['kp-active'],
            difficulty: 1,
            baseIndex: 1,
          ),
        ],
        inputs: inputs,
      );

      expect(output.ranked.first.taskId, 'active');
      expect(output.ranked.first.movedUp, isTrue);
      // 注意力低（α=0.3）时难的减分：1.6 × (1 − 0.25 × 0.4) = 1.44。
      expect(output.ranked.first.score, closeTo(1.6 * 0.9, 1e-9));
      // 0 跳那一档只说"刚活动过"，名字出现在 1 跳的句子里：也就是那个"冷"的知识点。
      final cold = output.ranked.firstWhere((hit) => hit.taskId == 'cold');
      expect(cold.score, closeTo(1.3 * 0.9, 1e-9));
      expect(cold.reasonZh, contains('动量守恒'));
    });

    test('没有候选时不报错', () {
      final inputs = CognitiveRankWiring.build(
        seed: _seed(active: const [
          'a'
        ], tagIds: const {
          'a': ['mech']
        }),
        candidates: const <CognitiveRankCandidate>[],
      );

      expect(inputs.originByKnowledgePoint, isEmpty);
      expect(CognitiveRank.rank(candidates: const [], inputs: inputs).isEmpty,
          isTrue);
    });
  });
}
