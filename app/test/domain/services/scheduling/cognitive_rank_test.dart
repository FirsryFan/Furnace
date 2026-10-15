import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/scheduling/cognitive_rank.dart';

/// 认知排序档位的纯逻辑测试。
///
/// 重点不是"排序看起来对"，而是三件可以核对的事：
/// 1. **没输入时等于没开**——次序必须与 `baseIndex` 完全一致；
/// 2. **每个分数都能手算**——1.6 / 1.3 / 1.1 与 ±25% 的摆动是显式常数；
/// 3. **未标定写在输出里**——`toJson()` 的 `uncalibrated` 不许是 false。
void main() {
  CognitiveRankInputs inputs({
    double availability = 1,
    Map<String, CognitiveRankOrigin> origins = const {},
    Map<String, String> names = const {},
  }) =>
      CognitiveRankInputs(
        availability: availability,
        originByKnowledgePoint: origins,
        knowledgePointNames: names,
      );

  CognitiveRankOrigin origin(
    int hops, {
    CognitiveRankLink link = CognitiveRankLink.activity,
    String? via,
  }) =>
      CognitiveRankOrigin(hops: hops, link: link, viaKnowledgePointId: via);

  group('没输入时等于没开', () {
    test('空候选 → 空输出', () {
      final output = CognitiveRank.rank(
        candidates: const <CognitiveRankCandidate>[],
        inputs: CognitiveRankInputs.empty,
      );
      expect(output.isEmpty, isTrue);
      expect(output.ranked, isEmpty);
    });

    test('什么都不知道 → 次序就是 baseIndex 次序，分数全是 1.0', () {
      final output = CognitiveRank.rank(
        candidates: const <CognitiveRankCandidate>[
          CognitiveRankCandidate(taskId: 'c', baseIndex: 2),
          CognitiveRankCandidate(taskId: 'a', baseIndex: 0),
          CognitiveRankCandidate(taskId: 'b', baseIndex: 1),
        ],
        inputs: CognitiveRankInputs.empty,
      );

      expect(
        output.ranked.map((h) => h.taskId).toList(),
        <String>['a', 'b', 'c'],
      );
      for (final hit in output.ranked) {
        expect(hit.score, 1.0);
        expect(hit.reachability, 1.0);
        expect(hit.availabilityFactor, 1.0);
        expect(hit.movedUp, isFalse);
        expect(hit.reasonZh, contains('没有认知读数'));
      }
    });

    test('同一输入两次结果完全相同（排序不依赖 List.sort 的稳定性）', () {
      final candidates = <CognitiveRankCandidate>[
        for (var i = 0; i < 8; i += 1)
          CognitiveRankCandidate(taskId: 't$i', baseIndex: i, difficulty: 0.5),
      ];
      final first = CognitiveRank.rank(
        candidates: candidates,
        inputs: inputs(availability: 0.9),
      );
      final second = CognitiveRank.rank(
        candidates: candidates.reversed.toList(),
        inputs: inputs(availability: 0.9),
      );
      // 反向喂进去也必须得到同一张 `baseIndex` 次序（平手全靠 baseIndex/tying）。
      expect(
        first.ranked.map((h) => h.taskId).toList(),
        second.ranked.map((h) => h.taskId).toList(),
      );
    });
  });

  group('距离加成', () {
    test('0 / 1 / 2 跳分别值 1.6 / 1.3 / 1.1', () {
      expect(
        CognitiveRank.reachabilityOf(origin(0)),
        kCognitiveRankDistance0Boost,
      );
      expect(
        CognitiveRank.reachabilityOf(origin(1)),
        kCognitiveRankDistance1Boost,
      );
      expect(
        CognitiveRank.reachabilityOf(origin(2)),
        kCognitiveRankDistance2Boost,
      );
    });

    test('超过两跳或负数 → 够不着（1.0），不是"很远也加点分"', () {
      expect(CognitiveRank.reachabilityOf(origin(3)), 1.0);
      expect(CognitiveRank.reachabilityOf(origin(-1)), 1.0);
      expect(CognitiveRank.reachabilityOf(null), 1.0);
    });

    test('距离 0 的候选越过 baseIndex 更靠前的候选，并标 movedUp', () {
      final output = CognitiveRank.rank(
        candidates: <CognitiveRankCandidate>[
          const CognitiveRankCandidate(
            taskId: 'first',
            baseIndex: 0,
            knowledgePointIds: <String>['kp-far'],
          ),
          const CognitiveRankCandidate(
            taskId: 'second',
            baseIndex: 1,
            knowledgePointIds: <String>['kp-hot'],
          ),
        ],
        inputs: inputs(
          origins: <String, CognitiveRankOrigin>{'kp-hot': origin(0)},
        ),
      );

      expect(
        output.ranked.map((h) => h.taskId).toList(),
        <String>['second', 'first'],
      );
      expect(output.ranked.first.movedUp, isTrue);
      expect(output.ranked.first.score, kCognitiveRankDistance0Boost);
      expect(output.ranked.last.movedUp, isFalse);
      expect(output.ranked.last.reachability, 1.0);
    });

    test('多个知识点取最近的那个 origin', () {
      final output = CognitiveRank.rank(
        candidates: <CognitiveRankCandidate>[
          const CognitiveRankCandidate(
            taskId: 't',
            knowledgePointIds: <String>['kp-two-hops', 'kp-here'],
          ),
        ],
        inputs: inputs(
          origins: <String, CognitiveRankOrigin>{
            'kp-two-hops': origin(2),
            'kp-here': origin(0),
          },
        ),
      );

      final hit = output.ranked.single;
      expect(hit.reachability, kCognitiveRankDistance0Boost);
      expect(hit.origin!.hops, 0);
    });

    test('同跳数时加成相同，但理由行必须说清来源', () {
      final output = CognitiveRank.rank(
        candidates: <CognitiveRankCandidate>[
          const CognitiveRankCandidate(
            taskId: 'goal-side',
            knowledgePointIds: <String>['kp-goal'],
          ),
          const CognitiveRankCandidate(
            taskId: 'activity-side',
            knowledgePointIds: <String>['kp-act'],
          ),
        ],
        inputs: inputs(
          origins: <String, CognitiveRankOrigin>{
            'kp-goal': origin(1, link: CognitiveRankLink.goal, via: 'kp-g'),
            'kp-act': origin(1, link: CognitiveRankLink.activity, via: 'kp-a'),
          },
        ),
      );

      // 加成相同（同跳数）→ 平手，按 baseIndex（都是 0）→ 输入顺序。
      // 但理由行必须说清来源，因为这是"为什么现在做这个"的唯一解释。
      expect(
        output.ranked.map((h) => h.taskId).toList(),
        <String>['goal-side', 'activity-side'],
      );
      final reasons = <String, String>{
        for (final hit in output.ranked) hit.taskId: hit.reasonZh,
      };
      expect(reasons['activity-side'], contains('刚复习的'));
      expect(reasons['goal-side'], contains('离目标'));
    });

    test('一个候选挂两个同跳数的知识点时，activity 侧被选中作为 origin', () {
      final output = CognitiveRank.rank(
        candidates: const <CognitiveRankCandidate>[
          CognitiveRankCandidate(
            taskId: 't',
            knowledgePointIds: <String>['kp-goal', 'kp-act'],
          ),
        ],
        inputs: inputs(
          origins: <String, CognitiveRankOrigin>{
            'kp-goal': origin(1, link: CognitiveRankLink.goal, via: 'kp-g'),
            'kp-act': origin(1, link: CognitiveRankLink.activity, via: 'kp-a'),
          },
        ),
      );
      expect(output.ranked.single.origin!.link, CognitiveRankLink.activity);
      expect(output.ranked.single.reasonZh, contains('刚复习的'));
    });
  });

  group('精力分量（α × 难度）', () {
    test('注意力满、难度满 → 1.25；注意力零、难度满 → 0.75', () {
      final high = CognitiveRank.rank(
        candidates: <CognitiveRankCandidate>[
          const CognitiveRankCandidate(taskId: 'hard', difficulty: 1),
        ],
        inputs: inputs(availability: 1),
      ).ranked.single;
      final low = CognitiveRank.rank(
        candidates: <CognitiveRankCandidate>[
          const CognitiveRankCandidate(taskId: 'hard', difficulty: 1),
        ],
        inputs: inputs(availability: 0),
      ).ranked.single;

      expect(high.availabilityFactor, closeTo(1.25, 1e-12));
      expect(low.availabilityFactor, closeTo(0.75, 1e-12));
      expect(high.reasonZh, contains('适合做难的'));
      expect(low.reasonZh, contains('先做容易的'));
    });

    test('注意力高时，同距离的难任务排在容易任务之前', () {
      final output = CognitiveRank.rank(
        candidates: <CognitiveRankCandidate>[
          const CognitiveRankCandidate(
              taskId: 'easy', baseIndex: 0, difficulty: 0),
          const CognitiveRankCandidate(
              taskId: 'hard', baseIndex: 1, difficulty: 1),
        ],
        inputs: inputs(availability: 1),
      );
      expect(
        output.ranked.map((h) => h.taskId).toList(),
        <String>['hard', 'easy'],
      );
    });

    test('注意力低时反过来：容易任务先做', () {
      final output = CognitiveRank.rank(
        candidates: <CognitiveRankCandidate>[
          const CognitiveRankCandidate(
              taskId: 'hard', baseIndex: 0, difficulty: 1),
          const CognitiveRankCandidate(
              taskId: 'easy', baseIndex: 1, difficulty: 0),
        ],
        inputs: inputs(availability: 0),
      );
      expect(
        output.ranked.map((h) => h.taskId).toList(),
        <String>['easy', 'hard'],
      );
    });

    test('有距离、没难度读数 → 精力分量中性 1.0，理由行如实写缺的是哪一项', () {
      final hit = CognitiveRank.rank(
        candidates: const <CognitiveRankCandidate>[
          CognitiveRankCandidate(
              taskId: 't', knowledgePointIds: <String>['kp']),
        ],
        inputs: inputs(
          availability: 0,
          origins: <String, CognitiveRankOrigin>{'kp': origin(0)},
        ),
      ).ranked.single;

      expect(hit.availabilityFactor, 1.0);
      expect(hit.reachability, kCognitiveRankDistance0Boost);
      expect(hit.reasonZh, contains('缺难度读数'));
      // 距离这一项仍然在说话，不许被"缺读数"整句吞掉。
      expect(hit.reasonZh, contains('刚活动过'));
    });

    test('既没有距离也没有难度 → 理由行直说"没有认知读数"', () {
      final hit = CognitiveRank.rank(
        candidates: const <CognitiveRankCandidate>[
          CognitiveRankCandidate(taskId: 't'),
        ],
        inputs: inputs(availability: 0.2),
      ).ranked.single;

      expect(hit.availabilityFactor, 1.0);
      expect(hit.reasonZh, '没有认知读数，按默认次序');
    });

    test('注意力正好中性 0.5 → 有难度也不动摇次序，且理由行不提注意力', () {
      final output = CognitiveRank.rank(
        candidates: <CognitiveRankCandidate>[
          const CognitiveRankCandidate(
              taskId: 'a', baseIndex: 0, difficulty: 1),
          const CognitiveRankCandidate(
              taskId: 'b', baseIndex: 1, difficulty: 0),
        ],
        inputs: inputs(availability: 0.5),
      );
      expect(
        output.ranked.map((h) => h.taskId).toList(),
        <String>['a', 'b'],
      );
      expect(output.ranked.first.availabilityFactor, closeTo(1.0, 1e-12));
      expect(output.ranked.first.reasonZh, isNot(contains('注意力')));
    });

    test('越界的注意力被钳住（1.5 与 1.0 同效，-0.5 与 0.0 同效）', () {
      List<String> order(double availability) => CognitiveRank.rank(
            candidates: <CognitiveRankCandidate>[
              const CognitiveRankCandidate(
                  taskId: 'hard', baseIndex: 0, difficulty: 1),
              const CognitiveRankCandidate(
                  taskId: 'easy', baseIndex: 1, difficulty: 0),
            ],
            inputs: inputs(availability: availability),
          ).ranked.map((h) => h.taskId).toList();

      expect(order(1.5), order(1.0));
      expect(order(-0.5), order(0.0));
    });

    test('NaN 注意力按中性处理，不产生 NaN 分数', () {
      final output = CognitiveRank.rank(
        candidates: <CognitiveRankCandidate>[
          const CognitiveRankCandidate(
              taskId: 'a', baseIndex: 0, difficulty: 1),
          const CognitiveRankCandidate(
              taskId: 'b', baseIndex: 1, difficulty: 0),
        ],
        inputs: inputs(availability: double.nan),
      );
      expect(
        output.ranked.map((h) => h.taskId).toList(),
        <String>['a', 'b'],
      );
      for (final hit in output.ranked) {
        expect(hit.score.isNaN, isFalse);
        expect(hit.availabilityFactor, closeTo(1.0, 1e-12));
      }
    });

    test('分数可手算：距离 0 + 注意力满 + 难度满 → 1.6 × 1.25 = 2.0', () {
      final hit = CognitiveRank.rank(
        candidates: const <CognitiveRankCandidate>[
          CognitiveRankCandidate(
            taskId: 't',
            knowledgePointIds: <String>['kp'],
            difficulty: 1,
          ),
        ],
        inputs: inputs(
          origins: <String, CognitiveRankOrigin>{'kp': origin(0)},
        ),
      ).ranked.single;

      expect(hit.reachability, 1.6);
      expect(hit.availabilityFactor, 1.25);
      expect(hit.score, closeTo(2.0, 1e-12));
      expect(hit.reasonZh, contains('×1.6'));
      expect(hit.reasonZh, contains('适合做难的'));
    });
  });

  group('理由行与序列化', () {
    test('有名字就用名字，没名字就念 id（不编名字）', () {
      final output = CognitiveRank.rank(
        candidates: <CognitiveRankCandidate>[
          const CognitiveRankCandidate(
            taskId: 'named',
            knowledgePointIds: <String>['kp-1'],
          ),
          const CognitiveRankCandidate(
            taskId: 'unnamed',
            knowledgePointIds: <String>['kp-2'],
          ),
        ],
        inputs: inputs(
          origins: <String, CognitiveRankOrigin>{
            'kp-1': origin(1, via: 'kp-1'),
            'kp-2': origin(1, via: 'kp-2'),
          },
          names: <String, String>{'kp-1': '动量守恒'},
        ),
      );

      final reasons = <String, String>{
        for (final hit in output.ranked) hit.taskId: hit.reasonZh,
      };
      expect(reasons['named'], contains('「动量守恒」'));
      expect(reasons['unnamed'], contains('「kp-2」'));
    });

    test('toJson 带 uncalibrated=true、order 与逐条明细', () {
      final output = CognitiveRank.rank(
        candidates: <CognitiveRankCandidate>[
          const CognitiveRankCandidate(
            taskId: 't1',
            baseIndex: 1,
            knowledgePointIds: <String>['kp'],
            difficulty: 0.8,
          ),
          const CognitiveRankCandidate(taskId: 't2', baseIndex: 0),
        ],
        inputs: inputs(
          availability: 0.9,
          origins: <String, CognitiveRankOrigin>{'kp': origin(0)},
        ),
      );

      final json = output.toJson();
      expect(json['uncalibrated'], isTrue);
      expect(json['order'], <String>['t1', 't2']);
      final details = json['details']! as List<Object?>;
      expect(details.length, 2);
      final first = details.first! as Map<String, Object?>;
      expect(first['task_id'], 't1');
      expect(first['uncalibrated'], isTrue);
      expect(first['hops'], 0);
      expect(first['link'], 'activity');
      expect(first['score'], closeTo(1.6 * 1.12, 1e-6));
      expect(CognitiveRankHit.uncalibrated, isTrue);
    });

    test('reasonLines 让 UI 直接可用', () {
      final output = CognitiveRank.rank(
        candidates: const <CognitiveRankCandidate>[
          CognitiveRankCandidate(
              taskId: 't1', knowledgePointIds: <String>['kp']),
        ],
        inputs: inputs(
          origins: <String, CognitiveRankOrigin>{'kp': origin(0)},
        ),
      );
      expect(output.reasonLines.single, startsWith('t1：'));
      expect(output.reasonLines.single, contains('刚活动过'));
    });
  });
}
