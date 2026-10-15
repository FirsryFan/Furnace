/// 认知排序档位：用"现在脑子里有什么"和"现在还剩多少注意力"重排候选任务。
///
/// 这是 `docs/MINDNET_ROADMAP.md` §2-D 剩下的那一半。段落 A（`ThreadRanker`
/// 的硬约束加权）与段落 B（`DomainBalanceRanker` 的领域均衡 + 有效性）都已经在
/// `thread_rank_service.dart` 里跑了，但两者都不看 α(τ)，也不看"刚复习/刚做错的
/// 节点"和"目标节点"。这一层补的就是这三样：
///
/// * **α(τ)**（[CognitiveRankInputs.availability]）：`StudyRhythm.read` 给的警觉
///   读数。它不是"精力条"，是同一套节律门（`rhythm_gate.dart`）算出来的可用性，
///   而且是**未标定代理**——`t_on` 由既有学习日志推导，本应用没有会话计时器。
/// * **刚活动节点**（[CognitiveRankOrigin.link] = [CognitiveRankLink.activity]）：
///   刚复习、刚读过（`exposure`）、刚做错的那些知识点。
/// * **目标节点**（[CognitiveRankLink.goal]）：线程当前目标所指向的知识点。
///
/// ## 这一层只做排序，不做判断
///
/// 输入是"距离"而不是图本身：调用方负责把标签树/图上的距离算好
/// （`CognitiveGraph`、`DiffusionBoost` 都在各自文件里做这件事），这里只消费
/// `知识点 id -> (跳数, 来源)`。这样纯逻辑可测，也不需要把图搬进来。
///
/// ## 全部 [未标定] —— 而且**不是** D12 的那几个数
///
/// [kCognitiveRankDistance0Boost] / [kCognitiveRankDistance1Boost] /
/// [kCognitiveRankDistance2Boost] 与 [kCognitiveRankAvailabilityStrength] 都**没有
/// 标定来源**：它们是显式选定的粗映射，集中放在文件顶部，标定之后只改这一处。
///
/// 特别注意它们**不等于** `diffusion_boost.dart` 里 D12 的 `1.8 / 1.3`：那一组是
/// "答错之后给关联卡片加抽卡权重"（`MINDNET_CONTRACT` §6.5 / D5），答对/答错不是
/// 同一回事，把两组数混用会让人以为这里有测量。两处的常量名字刻意不同。
///
/// 同理，本档位的输出**不得**被摆到模型的诊断旁边当成同一种陈述：它用的是代理
/// 读数与规范里的粗映射，模型给的是 R/S 轨迹。两者可以不一致，不一致不是 bug。
///
/// ## 什么时候这一层等于没开
///
/// 没有 origin、也没有难度的候选，`score` 全是 1.0，[CognitiveRank.rank] 就退化成
/// "按 `baseIndex` 原样返回"。这条性质被测试钉住（见
/// `test/domain/services/scheduling/cognitive_rank_test.dart`）：接线之后忘了喂
/// 输入，用户看到的仍然是原来的次序，而不是一个悄悄乱掉的列表。
library;

/// 知识点就是"刚活动/目标"本身时的加成。
///
/// [未标定]：显式选定的粗映射，不是测量值。见库 doc。
const double kCognitiveRankDistance0Boost = 1.6;

/// 图距离 1 跳的加成。[未标定]，同上。
const double kCognitiveRankDistance1Boost = 1.3;

/// 图距离 2 跳的加成。[未标定]，同上。
const double kCognitiveRankDistance2Boost = 1.1;

/// 精力分量的最大摆动（±25%）。
///
/// `availabilityFactor = 1 ± kCognitiveRankAvailabilityStrength`：注意力高时给
/// 难的加分、给容易的减分，注意力低时反过来。[未标定]。
const double kCognitiveRankAvailabilityStrength = 0.25;

/// 超过这个跳数就算"够不着"（等于没有加成）。
const int kCognitiveRankMaxHops = 2;

/// 一个知识点为什么会进这一档位。
enum CognitiveRankLink {
  /// 刚复习 / 刚读过 / 刚做错。
  activity,

  /// 目标节点（线程当前目标指向的知识点）。
  goal,
}

/// 一个知识点相对"现在脑子里/目标"的位置。
class CognitiveRankOrigin {
  const CognitiveRankOrigin({
    required this.hops,
    required this.link,
    this.viaKnowledgePointId,
  });

  /// 图距离：0 = 就是它自己，1 / 2 = [kCognitiveRankMaxHops] 以内。
  final int hops;

  /// 它是怎么被够到的。
  final CognitiveRankLink link;

  /// 通过哪个知识点够到的（理由行要说"离刚复习的「X」1 跳"）。
  ///
  /// [hops] == 0 时它就是自己，可以为 null。
  final String? viaKnowledgePointId;

  Map<String, Object?> toJson() => <String, Object?>{
        'hops': hops,
        'link': link.name,
        'via': viaKnowledgePointId,
      };
}

/// 排序需要的全部外部输入。
///
/// [originByKnowledgePoint] 由调用方算好（标签树上的距离 + 目标/活动来源）。
/// 默认值是"什么都不知道"：没有 origin、没有名字、注意力按中性算。
class CognitiveRankInputs {
  const CognitiveRankInputs({
    required this.availability,
    this.originByKnowledgePoint = const <String, CognitiveRankOrigin>{},
    this.knowledgePointNames = const <String, String>{},
  });

  /// α(τ) 读数，0..1。NaN 或越界按中性/边界处理（见 [CognitiveRank.rank]）。
  final double availability;

  /// 知识点 id → 它相对"刚活动/目标"的位置。
  final Map<String, CognitiveRankOrigin> originByKnowledgePoint;

  /// 知识点 id → 显示名，只给理由行说话用；缺了就如实念 id，不编名字。
  final Map<String, String> knowledgePointNames;

  /// "什么都不知道"的输入。
  static const CognitiveRankInputs empty = CognitiveRankInputs(availability: 1);
}

/// 一个候选任务。
class CognitiveRankCandidate {
  const CognitiveRankCandidate({
    required this.taskId,
    this.knowledgePointIds = const <String>[],
    this.difficulty,
    this.baseIndex = 0,
  });

  final String taskId;

  /// 这张任务挂在哪些知识点上（取最近的那个 origin）。
  final List<String> knowledgePointIds;

  /// 难度代理，0..1（1 = 最难）。null = 没有读数。
  ///
  /// 现在唯一的来源是测评先验的编码上限（`KnowledgePointReading.priorR0`，
  /// 越小越弱）换算，但那是调用方的事：这里只认一个 0..1 的数。
  final double? difficulty;

  /// 段落 B 里的原始次序（0 = 最前）。平手时用它保持稳定。
  final int baseIndex;
}

/// 一条排好序的结果。
class CognitiveRankHit {
  const CognitiveRankHit({
    required this.taskId,
    required this.score,
    required this.reachability,
    required this.availabilityFactor,
    required this.baseIndex,
    required this.movedUp,
    required this.reasonZh,
    this.origin,
  });

  final String taskId;

  /// `reachability * availabilityFactor`。
  final double score;

  /// 图距离加成（1.0 表示够不着）。
  final double reachability;

  /// 精力加成（1.0 表示没有难度读数，或注意力正好中性）。
  final double availabilityFactor;

  /// 它原来在段落 B 里的位置。
  final int baseIndex;

  /// 比原来更靠前了吗（UI 用它决定要不要解释一句）。
  final bool movedUp;

  final CognitiveRankOrigin? origin;

  /// 一句中文理由，最多两段。
  final String reasonZh;

  /// 本档位整体未标定 —— 序列化时如实写出去，别让下游以为这是测量。
  static const bool uncalibrated = true;

  Map<String, Object?> toJson() => <String, Object?>{
        'task_id': taskId,
        'score': _round6(score),
        'reachability': _round6(reachability),
        'availability_factor': _round6(availabilityFactor),
        'base_index': baseIndex,
        'moved_up': movedUp,
        'hops': origin?.hops,
        'link': origin?.link.name,
        'uncalibrated': uncalibrated,
        'reason_zh': reasonZh,
      };
}

/// 一次认知排序的结果。
class CognitiveRankOutput {
  const CognitiveRankOutput({required this.ranked});

  final List<CognitiveRankHit> ranked;

  bool get isEmpty => ranked.isEmpty;

  /// 序号和理由，给 UI / payload 用。
  List<String> get reasonLines => <String>[
        for (final hit in ranked) '${hit.taskId}：${hit.reasonZh}',
      ];

  Map<String, Object?> toJson() => <String, Object?>{
        'order': <String>[for (final hit in ranked) hit.taskId],
        'uncalibrated': CognitiveRankHit.uncalibrated,
        'details': <Map<String, Object?>>[
          for (final hit in ranked) hit.toJson()
        ],
      };
}

/// 纯函数入口。**没有一步碰数据库**。
abstract final class CognitiveRank {
  /// 按认知输入重排 [candidates]。
  ///
  /// * `score = reachability * availabilityFactor`，降序；
  /// * 平手时按 `baseIndex` 升序（保持段落 B 的相对次序），再按输入顺序，最后按
  ///   `taskId` 升序 —— 显式写完是因为 `List.sort` 不保证稳定；
  /// * 难度读数为 null 的候选，精力分量取 1.0（中性），理由行如实写"缺读数"；
  /// * `availability` 是 NaN 时按中性处理；越界钳到 `[0, 1]`。
  static CognitiveRankOutput rank({
    required List<CognitiveRankCandidate> candidates,
    required CognitiveRankInputs inputs,
  }) {
    if (candidates.isEmpty) {
      return const CognitiveRankOutput(ranked: <CognitiveRankHit>[]);
    }
    final double alpha = _alphaOf(inputs.availability);

    final rows = <_Row>[];
    for (var index = 0; index < candidates.length; index += 1) {
      final candidate = candidates[index];
      final origin = _nearestOrigin(candidate, inputs);
      final reachability = _reachabilityOf(origin?.hops);
      final difficulty =
          candidate.difficulty == null ? null : _clamp01(candidate.difficulty!);
      final availabilityFactor = difficulty == null
          ? 1.0
          : 1.0 +
              kCognitiveRankAvailabilityStrength *
                  (2 * (alpha * difficulty + (1 - alpha) * (1 - difficulty)) -
                      1);
      rows.add(
        _Row(
          candidate: candidate,
          origin: origin,
          reachability: reachability,
          availabilityFactor: availabilityFactor,
          score: reachability * availabilityFactor,
          inputIndex: index,
        ),
      );
    }

    rows.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) {
        return byScore;
      }
      final byBase = a.candidate.baseIndex.compareTo(b.candidate.baseIndex);
      if (byBase != 0) {
        return byBase;
      }
      final byInput = a.inputIndex.compareTo(b.inputIndex);
      if (byInput != 0) {
        return byInput;
      }
      return a.candidate.taskId.compareTo(b.candidate.taskId);
    });

    final ranked = <CognitiveRankHit>[];
    for (var position = 0; position < rows.length; position += 1) {
      final row = rows[position];
      ranked.add(
        CognitiveRankHit(
          taskId: row.candidate.taskId,
          score: row.score,
          reachability: row.reachability,
          availabilityFactor: row.availabilityFactor,
          baseIndex: row.candidate.baseIndex,
          movedUp: position < row.candidate.baseIndex,
          origin: row.origin,
          reasonZh: _reasonFor(
            candidate: row.candidate,
            origin: row.origin,
            availabilityFactor: row.availabilityFactor,
            alpha: alpha,
            names: inputs.knowledgePointNames,
          ),
        ),
      );
    }
    return CognitiveRankOutput(ranked: ranked);
  }

  /// 一个 origin 值多少加成（够不着 = 1.0）。
  static double reachabilityOf(CognitiveRankOrigin? origin) =>
      _reachabilityOf(origin?.hops);

  static double _reachabilityOf(int? hops) {
    if (hops == null || hops > kCognitiveRankMaxHops || hops < 0) {
      return 1.0;
    }
    return switch (hops) {
      0 => kCognitiveRankDistance0Boost,
      1 => kCognitiveRankDistance1Boost,
      _ => kCognitiveRankDistance2Boost,
    };
  }

  /// 候选最近的 origin：跳数最小，同跳数时 `activity` 优先于 `goal`
  /// （"刚做错"比"目标附近"更该立刻做），再按知识点 id 稳定排序。
  static CognitiveRankOrigin? _nearestOrigin(
    CognitiveRankCandidate candidate,
    CognitiveRankInputs inputs,
  ) {
    CognitiveRankOrigin? best;
    for (final id in candidate.knowledgePointIds) {
      final origin = inputs.originByKnowledgePoint[id];
      if (origin == null) {
        continue;
      }
      if (_isBetter(origin, best)) {
        best = origin;
      }
    }
    return best;
  }

  static bool _isBetter(
      CognitiveRankOrigin candidate, CognitiveRankOrigin? best) {
    if (best == null) {
      return true;
    }
    if (candidate.hops != best.hops) {
      return candidate.hops < best.hops;
    }
    if (candidate.link != best.link) {
      return candidate.link == CognitiveRankLink.activity;
    }
    final a = candidate.viaKnowledgePointId ?? '';
    final b = best.viaKnowledgePointId ?? '';
    return a.compareTo(b) < 0;
  }

  static double _alphaOf(double availability) {
    if (availability.isNaN) {
      return 0.5;
    }
    return _clamp01(availability);
  }

  static double _clamp01(double value) {
    if (value.isNaN) {
      return 0.0;
    }
    if (value < 0) {
      return 0.0;
    }
    if (value > 1) {
      return 1.0;
    }
    return value;
  }

  static String _reasonFor({
    required CognitiveRankCandidate candidate,
    required CognitiveRankOrigin? origin,
    required double availabilityFactor,
    required double alpha,
    required Map<String, String> names,
  }) {
    final clauses = <String>[];
    if (origin != null) {
      clauses.add(_originClause(origin, names));
      if (candidate.difficulty == null) {
        // 只缺难度：距离这一项还在起作用，如实说清缺的是哪一项。
        clauses.add('缺难度读数，精力这一项按中性算');
      } else if (availabilityFactor != 1.0) {
        clauses.add(_availabilityClause(alpha, candidate.difficulty!));
      }
    } else if (candidate.difficulty == null) {
      clauses.add('没有认知读数，按默认次序');
    } else if (availabilityFactor != 1.0) {
      clauses.add(_availabilityClause(alpha, candidate.difficulty!));
    }
    return clauses.join('；');
  }

  static String _originClause(
      CognitiveRankOrigin origin, Map<String, String> names) {
    final boost = _reachabilityOf(origin.hops);
    final tag = '×${_trim(boost)}';
    if (origin.hops == 0) {
      return origin.link == CognitiveRankLink.goal
          ? '就是当前目标（$tag）'
          : '刚活动过（$tag）';
    }
    final via = origin.viaKnowledgePointId;
    final label = via == null ? null : (names[via] ?? via); // 没有名字就念 id，不编。
    final whence = origin.link == CognitiveRankLink.goal ? '目标' : '刚复习的';
    if (label == null) {
      return '离$whence ${origin.hops} 跳（$tag）';
    }
    return '离$whence「$label」${origin.hops} 跳（$tag）';
  }

  static String _availabilityClause(double alpha, double difficulty) {
    final percent = (alpha * 100).round();
    if (alpha >= 0.7) {
      return '注意力 $percent%，适合做难的';
    }
    if (alpha <= 0.35) {
      return '注意力 $percent%，先做容易的';
    }
    return '注意力 $percent%，难易都还行';
  }

  /// `1.0` / `1.6` 这样的短写法（`1.6000000000000001` 不要出现在理由行里）。
  static String _trim(double value) {
    final text = value.toStringAsFixed(2);
    if (text.endsWith('00')) {
      return text.substring(0, text.length - 3);
    }
    if (text.endsWith('0')) {
      return text.substring(0, text.length - 1);
    }
    return text;
  }
}

class _Row {
  const _Row({
    required this.candidate,
    required this.origin,
    required this.reachability,
    required this.availabilityFactor,
    required this.score,
    required this.inputIndex,
  });

  final CognitiveRankCandidate candidate;
  final CognitiveRankOrigin? origin;
  final double reachability;
  final double availabilityFactor;
  final double score;
  final int inputIndex;
}

double _round6(double value) => (value * 1000000).roundToDouble() / 1000000;
