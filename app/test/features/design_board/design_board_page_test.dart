// 通宵 task-25：设计/内容板块（只读）。
//
// 这里钉三件事：
// 1) 本地 JSON asset 存在、在 30-50 条之间、五层齐全、每条字段不缺、状态只用
//    四个桶（已落地/审核中/否定/待完善），且能力矩阵/内容 schema 缺失时明确
//    显示"数据未完成"而不是伪造；
// 2) 页面按五层分组渲染名字/类型/状态/用户评价，展开能看到机制摘要；
// 3) 设置页有一行只读入口，点开就是这一页。
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/features/design_board/data/design_board_repository.dart';
import 'package:furnace/features/design_board/domain/design_board.dart';
import 'package:furnace/features/design_board/presentation/content_sample_page.dart';
import 'package:furnace/features/design_board/presentation/developer_info_page.dart';
import 'package:furnace/features/design_board/presentation/design_board_page.dart';
import 'package:furnace/features/settings/presentation/settings_page.dart';
import 'package:furnace/l10n/app_localizations.dart';

class _FakeSource implements DesignBoardSource {
  _FakeSource(this.data);

  final DesignBoardData data;

  @override
  Future<DesignBoardData> load() async => data;
}

class _FailingSource implements DesignBoardSource {
  @override
  Future<DesignBoardData> load() async =>
      throw const FormatException('测试用损坏数据');
}

Future<DesignBoardData> _loadAsset() async {
  final file = File('assets/design_board.json');
  expect(
    await file.exists(),
    isTrue,
    reason: '本地 asset 必须存在：assets/design_board.json',
  );
  return DesignBoardData.decode(await file.readAsString());
}

/// Kahn 拓扑排序：内容包的 Thinking DAG 必须无环（learner-review P0）。
bool _isAcyclic(DagGraph graph) {
  final indegree = <String, int>{for (final node in graph.nodes) node.id: 0};
  final adjacency = <String, List<String>>{
    for (final node in graph.nodes) node.id: <String>[],
  };
  for (final edge in graph.edges) {
    if (!indegree.containsKey(edge.from) || !indegree.containsKey(edge.to)) {
      continue;
    }
    adjacency[edge.from]!.add(edge.to);
    indegree[edge.to] = indegree[edge.to]! + 1;
  }
  final ready = <String>[
    for (final entry in indegree.entries)
      if (entry.value == 0) entry.key,
  ];
  var visited = 0;
  while (ready.isNotEmpty) {
    final node = ready.removeLast();
    visited++;
    for (final target in adjacency[node]!) {
      indegree[target] = indegree[target]! - 1;
      if (indegree[target] == 0) {
        ready.add(target);
      }
    }
  }
  return visited == graph.nodes.length;
}

/// 收集 JSON 子树里的所有字符串（用于逐字符串扫描学生页投影）。
void _collectStrings(Object? value, List<String> out) {
  if (value is String) {
    out.add(value);
  } else if (value is List) {
    for (final item in value) {
      _collectStrings(item, out);
    }
  } else if (value is Map) {
    for (final item in value.values) {
      _collectStrings(item, out);
    }
  }
}

void main() {
  // 真实文件 IO 不能在 testWidgets 的 fake-async 区里 await（会永不完成），
  // 所以在 setUpAll 里读一次，widget test 直接复用。
  late DesignBoardData assetData;

  setUpAll(() async {
    assetData = await _loadAsset();
  });

  group('design_board.json asset', () {
    test('30-50 条、五层齐全、字段不缺、状态只有四个桶', () async {
      final data = assetData;

      expect(data.entries.length, inInclusiveRange(30, 50));
      expect(
        data.layers.map((layer) => layer.id).toList(),
        <String>['L1', 'L2-A', 'L2-B', 'L2-C', 'L3'],
      );
      for (final layer in data.layers) {
        expect(
          data.entriesOf(layer.id),
          isNotEmpty,
          reason: '${layer.id} 分组不能为空',
        );
      }

      for (final entry in data.entries) {
        expect(entry.id, matches(RegExp(r'^[A-Z]{1,2}\d?-\d{2}$')));
        expect(entry.name, isNotEmpty, reason: entry.id);
        expect(entry.layer, isNotEmpty, reason: entry.id);
        expect(
          DesignBoardData.statusOrder,
          contains(entry.status),
          reason: '${entry.id} 的状态 ${entry.status} 不在四个桶内',
        );
        expect(entry.statusRaw, isNotEmpty, reason: entry.id);
        expect(entry.userEval, isNotEmpty, reason: entry.id);
        expect(entry.summary, isNotEmpty, reason: entry.id);
        expect(entry.mechanism, isNotEmpty, reason: entry.id);
        expect(entry.evidence, isNotEmpty, reason: entry.id);
      }

      final counts = data.statusCounts;
      for (final status in DesignBoardData.statusOrder) {
        expect(
          counts[status],
          greaterThan(0),
          reason: '状态 $status 至少要有一条，否则筛选项没有意义',
        );
      }
    });

    test('文件保持在精简范围（不是把 190KB 参考库塞进 asset）', () async {
      final size = await File('assets/design_board.json').length();
      // task-96 给三题加了 boardSelection（L0–L5 选板结果，约 4KB）；仍是精简
      // 快照，远小于 190KB 的参考库。
      expect(size, lessThan(160 * 1024));
    });

    test('能力矩阵卡片接真实数据：measured/preset/unknown 分开，不伪造精度', () async {
      final data = assetData;
      expect(
        data.abilityMatrix,
        isNotNull,
        reason: 'task-48 的能力矩阵 UI 数据应接到卡片',
      );
      final abilityChips = data.abilityMatrix!.chips.join('|');
      expect(abilityChips, contains('measured 22'));
      expect(abilityChips, contains('preset 7'));
      expect(abilityChips, contains('unknown 549'));
      expect(abilityChips, contains('absent 0'));
      expect(abilityChips, contains('图覆盖 0'));
      final abilityLines = data.abilityMatrix!.lines.join('\n');
      // measured / preset / unknown 数量分开显示。
      expect(abilityLines, contains('measured 22（19 知识点 + 3 元能力）'));
      expect(abilityLines, contains('preset 7'));
      expect(abilityLines, contains('unknown 549'));
      // 3 个实测元能力值 + 区间/n。
      expect(abilityLines, contains('3 个实测元能力'));
      expect(abilityLines, contains('加工速度 -0.223±0.577（n=2'));
      expect(abilityLines, contains('抑制控制 +1.917±0.707（n=1'));
      expect(abilityLines, contains('抗干扰 -3.000±0.707（n=1'));
      // 知识点示例：含 95% 区间与证据数。
      expect(abilityLines, contains('95% ['));
      expect(abilityLines, contains('n_obs=3'));
      // 549 unknown：只显示证据不足，不显示假精确。
      expect(abilityLines, contains('549 个知识点为 unknown'));
      expect(abilityLines, contains('证据不足'));
      expect(abilityLines, contains('不能当 0/50%'));
      // 三题 ability map 摘要。
      expect(abilityLines, contains('三题 ability map 摘要'));
      for (final qid in <String>['Q-PH0001', 'Q-MA0001', 'Q-CH0001']) {
        expect(abilityLines, contains(qid));
      }
      expect(abilityLines, contains('审核 pending'));
      // warnings：图覆盖 0、内容节点→产品 KP 0 映射、错因 0。
      expect(abilityLines, contains('19 个真实复习 KP 图上覆盖 = 0'));
      expect(abilityLines, contains('产品 568 KP 映射 0'));
      expect(abilityLines, contains('错因 0'));
      // 不得声称能力矩阵已验证有效。
      expect(abilityLines, isNot(contains('能力矩阵已验证有效')));
      expect(abilityLines, isNot(contains('已验证能力矩阵有效')));
      expect(
        data.abilityMatrix!.subtitle,
        contains('ability-matrix-ui.json'),
      );

      expect(
        data.contentSchema,
        isNotNull,
        reason: 'task-23 的 schema 已交付，应展示真实只读示例卡',
      );
      expect(data.contentSchema!.chips, contains('Thinking DAG'));
      expect(data.contentSchema!.chips, contains('题眼'));
      expect(data.contentSchema!.lines, isNotEmpty);
      expect(
        data.contentSchema!.subtitle,
        contains('CONTENT-ORGANIZATION-SCHEMA-2026-11-15.md'),
      );
    });

    test('真实内容样品：物理 Q-PH0001 + 数学 Q-MA0001 + 语文 Q-CH0001 三张精简快照', () async {
      final data = assetData;
      expect(data.realContentSamples.length, 3);
      final physics = data.realContentSamples.firstWhere(
        (sample) => sample.title.contains('Q-PH0001'),
      );
      final math = data.realContentSamples.firstWhere(
        (sample) => sample.title.contains('Q-MA0001'),
      );
      final chinese = data.realContentSamples.firstWhere(
        (sample) => sample.title.contains('Q-CH0001'),
      );
      for (final sample in [physics, math, chinese]) {
        expect(sample.id, isNotEmpty, reason: '详情页入口 key 依赖 id');
        expect(sample.expandable, isTrue, reason: '真实样品卡要求可展开');
        final chips = sample.chips.join('|');
        expect(chips, contains('答案来自 Source'));
        expect(chips, contains('未独立审核'));
        expect(chips, contains('private_study_only'));
        final lines = sample.lines.join('\n');
        expect(lines, contains('B_independently_verified'));
        expect(lines, contains('PACKAGE VALID'));
        expect(lines, contains('private_study_only'));
        expect(lines.length, lessThan(4000));
        // 详情页结构化内容：题干 / 答案 / DAG / 板块 / 校验 / 限制。
        final titles = sample.detailSections.map((s) => s.title).join('|');
        expect(titles, contains('题干'));
        expect(titles, contains('答案与信任'));
        expect(titles, contains('Thinking DAG'));
        expect(titles, contains('9 个公共板块摘要'));
        expect(titles, contains('校验'));
        expect(titles, contains('限制'));
        for (final section in sample.detailSections) {
          expect(section.items, isNotEmpty, reason: section.title);
        }
      }
      // 物理卡：DAG 节点/边数写在详情快照里（与 asset 的 dagGraph 一致）。
      final physicsDag = physics.dagGraph!;
      expect(
        physics.lines.join('\n'),
        contains(
            '${physicsDag.nodes.length} 节点 / ${physicsDag.edges.length} 边'),
      );
      final stemLine = physics.lines.firstWhere(
        (line) => line.startsWith('题干（短片段）'),
      );
      expect(stemLine.length, lessThan(220));

      // 数学卡：16 条 OMML、PACKAGE VALID、无渲染 oracle；不得声称公式全对。
      final mathLines = math.lines.join('\n');
      expect(mathLines, contains('16 条 OMML'));
      expect(mathLines, contains('无渲染 oracle'));
      expect(
        mathLines,
        contains(
          '${math.dagGraph!.nodes.length} 节点 / '
          '${math.dagGraph!.edges.length} 边',
        ),
      );
      expect(mathLines, contains('PACKAGE VALID'));
      expect(mathLines, contains('4/5 被拒'));
      expect(mathLines, isNot(contains('公式全对')));
      expect(mathLines, isNot(contains('公式全部正确')));

      // 语文卡：DAG 8/8；无官方评分细则（0 命中）；分点分值是 AI 均分；不冒充官方。
      final chineseLines = chinese.lines.join('\n');
      expect(
        chineseLines,
        contains(
          '${chinese.dagGraph!.nodes.length} 节点 / '
          '${chinese.dagGraph!.edges.length} 边',
        ),
      );
      expect(chineseLines, contains('Source 全文 0 命中'));
      expect(chineseLines, contains('2/2/2 的分值是 AI 均分'));
      expect(chineseLines, contains('scoring.source=ai_derived'));
      expect(chineseLines, contains('human_review_required'));
      expect(chineseLines, contains('未独立审核'));
      expect(chineseLines, contains('PACKAGE VALID'));
      expect(chineseLines, contains('0 处 official_rubric'));
      expect(chineseLines, isNot(contains('official_rubric，verified=true')));
    });

    test('Problem State 区块：三题都有、数量与 problem JSON 一致、decisions 全 proposed',
        () async {
      final data = assetData;
      const expected = <String, Map<String, int>>{
        'Q-PH0001': {
          'facts': 8,
          'assumptions': 5,
          'decisions': 4,
          'unknowns': 7,
          'artifacts': 6,
          'more': 2,
          'verified': 7,
          'reported': 1,
          'proposed': 4,
        },
        'Q-MA0001': {
          'facts': 8,
          'assumptions': 5,
          'decisions': 4,
          'unknowns': 8,
          'artifacts': 5,
          'more': 3,
          'verified': 7,
          'reported': 1,
          'proposed': 4,
        },
        'Q-CH0001': {
          'facts': 9,
          'assumptions': 6,
          'decisions': 5,
          'unknowns': 9,
          'artifacts': 4,
          'more': 4,
          'verified': 8,
          'reported': 1,
          'proposed': 5,
        },
      };
      for (final sample in data.realContentSamples) {
        final state = sample.problemState;
        expect(state, isNotNull, reason: '${sample.id} 应有 Problem State 区块');
        final want = expected[sample.id]!;
        expect(state!.facts, want['facts'], reason: sample.id);
        expect(state.assumptions, want['assumptions'], reason: sample.id);
        expect(state.decisions, want['decisions'], reason: sample.id);
        expect(state.unknowns, want['unknowns'], reason: sample.id);
        expect(state.artifacts, want['artifacts'], reason: sample.id);
        expect(state.factTrustVerified, want['verified'], reason: sample.id);
        expect(state.factTrustReported, want['reported'], reason: sample.id);
        // 决策全部 proposed，没有审批事件（accepted/rejected 均为 0）。
        expect(state.decisionsAllProposed, isTrue, reason: sample.id);
        expect(state.decisionsProposed, want['proposed'], reason: sample.id);
        expect(state.decisionsAccepted, 0, reason: sample.id);
        expect(state.decisionsRejected, 0, reason: sample.id);
        // unknowns 最多展示 5 条，其余用 +N 表示。
        expect(state.unknownsShown.length, 5, reason: sample.id);
        expect(state.unknownsMore, want['more'], reason: sample.id);
        expect(state.oracleKind, 'deterministic', reason: sample.id);
        expect(state.budgetNull, isTrue, reason: sample.id);
        expect(state.note, contains('材料快照'), reason: sample.id);
        expect(state.note, contains('未审批'), reason: sample.id);
        expect(state.note, isNot(contains('已批准')), reason: sample.id);
        expect(state.note, isNot(contains('已接受')), reason: sample.id);
      }
    });

    test('Thinking DAG 数据：无环、success_path 可达、节点是短节点（公式/关键量/结论）', () async {
      for (final sample in assetData.realContentSamples) {
        final dag = sample.dagGraph;
        expect(dag, isNotNull, reason: '${sample.id} 应有 DAG 导图数据');
        expect(_isAcyclic(dag!), isTrue, reason: '${sample.id} DAG 必须无环');
        expect(dag.nodes.length, greaterThanOrEqualTo(6), reason: sample.id);
        expect(dag.edges, isNotEmpty, reason: sample.id);
        expect(
          dag.successPath.length,
          greaterThanOrEqualTo(3),
          reason: sample.id,
        );
        final ids = dag.nodes.map((node) => node.id).toSet();
        for (final id in dag.successPath) {
          expect(ids, contains(id), reason: '${sample.id}/$id');
        }
        for (final path in dag.alternatePaths) {
          expect(path.methodName, isNotEmpty, reason: sample.id);
          for (final id in path.nodeIds) {
            expect(ids, contains(id), reason: '${sample.id}/alt/$id');
          }
        }
        expect(
          dag.failureBranches.length,
          dag.failedBranches,
          reason: sample.id,
        );
        expect(dag.sourceMode, isNotEmpty, reason: sample.id);
        expect(dag.alternatePaths, isNotEmpty, reason: sample.id);
        // 学生数据不带“AI 整理/未独立审核/无语义校验”这类报告腔（开发者页才有）。
        expect(dag.note, isEmpty, reason: sample.id);
        // 短节点（前代思路图形态）：有标签，并且至少含公式/关键量/结论之一。
        for (final node in dag.nodes) {
          expect(node.label, isNotEmpty, reason: '${sample.id}/${node.id}');
          expect(
            node.formulas.isNotEmpty ||
                node.keyQuantities.isNotEmpty ||
                node.result.isNotEmpty,
            isTrue,
            reason: '${sample.id}/${node.id} 应至少含公式/关键量/结论之一',
          );
        }
        // 物理是简单题：DAG 应短。
        if (sample.id == 'Q-PH0001') {
          expect(
            dag.nodes.length,
            lessThanOrEqualTo(8),
            reason: '简单题的 DAG 不应长',
          );
        }
      }
    });

    test('学生视图数据：按板块库选配（简单题无 L1/提示；复杂题有）+ 【AI】+ 解析可见性', () async {
      // 物理：简单题（concept/单选）→ L1 DAG/过程解析/卡点/提示都不选；
      // L2 只留题眼/陷阱/错因；L3 额外任务→变式；L4 扩展资料；L5 不进正文。
      const simplePanels = <String>[
        'l2_key_eye',
        'l2_traps',
        'l2_error_causes',
        'l3_extra_tasks',
        'l3_variants',
        'l4_extension_material',
      ];
      const layerRank = <String, int>{
        'L0': 0,
        'L1': 1,
        'L2': 2,
        'L3': 3,
        'L4': 4,
        'L5': 5,
      };
      for (final sample in assetData.realContentSamples) {
        final content = sample.studentContent;
        expect(content, isNotNull, reason: '${sample.id} 应有学生视图数据');
        expect(content!.stem, isNotEmpty, reason: sample.id);
        expect(content.answer, isNotEmpty, reason: sample.id);

        // 选板结果：来自 LegacyBoardMapper（asset 只放学生页需要的字段）。
        final selection = sample.boardSelection;
        expect(selection, isNotNull, reason: '${sample.id} 应有 boardSelection');
        expect(selection!.schemaVersion, 'furnace.board-selection/1');
        expect(selection.questionId, sample.id);
        expect(selection.boards, isNotEmpty, reason: sample.id);
        expect(selection.boards.first.boardId, 'l0_question_entity',
            reason: '${sample.id}/L0 在前');
        expect(selection.boards.last.boardId, 'l5_meta',
            reason: '${sample.id}/L5 最后（选板结果，不进正文）');
        var previousRank = -1;
        for (final board in selection.boards) {
          final rank = layerRank[board.level]! * 1000 + board.order;
          expect(rank, greaterThanOrEqualTo(previousRank),
              reason: '${sample.id}/${board.boardId} 选板顺序');
          previousRank = rank;
        }

        // panels 只含被选中的 L2–L4 板块，按选板顺序；空板块/占位不出现。
        expect(content.panels, isNotEmpty, reason: sample.id);
        for (final panel in content.panels) {
          expect(panel.boardId, isNotEmpty,
              reason: '${sample.id}/${panel.title} 缺 boardId');
          expect(selection.hasBoard(panel.boardId), isTrue,
              reason: '${sample.id}/${panel.boardId} 没被选却出现在学生页');
          expect(layerRank[panel.level]!, inInclusiveRange(2, 4),
              reason: '${sample.id}/${panel.boardId} 只投影 L2–L4');
          expect(panel.order, greaterThan(0), reason: panel.boardId);
          expect(panel.items, isNotEmpty,
              reason: '${sample.id}/${panel.title}');
          for (final item in panel.items) {
            expect(item, isNotEmpty, reason: '${sample.id}/${panel.title}');
            expect(item, isNot(startsWith('暂无')),
                reason: '${sample.id}/${panel.title} 空板块不占位');
          }
        }
        // L5 元信息（旧五维）不进学生正文。
        for (final panel in content.panels) {
          expect(panel.boardId, isNot('l5_meta'));
          expect(panel.title, isNot('五维正向推导'));
        }
        // L3 顺序固定：额外任务(40) → 变式(41) →（同源题 42，空则不占位）。
        final l3 =
            content.panels.where((panel) => panel.level == 'L3').toList();
        expect(l3, isNotEmpty, reason: sample.id);
        for (var i = 1; i < l3.length; i++) {
          expect(l3[i].order, greaterThan(l3[i - 1].order),
              reason: '${sample.id}/L3 顺序');
        }
        expect(l3.first.boardId, 'l3_extra_tasks', reason: sample.id);
        expect(
          l3.any((panel) => panel.boardId == 'l3_similar_questions'),
          isFalse,
          reason: '${sample.id}/同源题候选空 → 不占位',
        );

        if (sample.id == 'Q-PH0001') {
          // 物理：简单题；L1 整段不选，提示/卡点也不选。
          expect(selection.complexity, 'simple', reason: sample.id);
          expect(selection.complexitySource, 'default_simple');
          for (final boardId in <String>[
            'l1_thinking_dag',
            'l1_solution_walkthrough',
            'l2_stuck_points',
            'l2_layered_hints',
          ]) {
            expect(selection.hasBoard(boardId), isFalse,
                reason: '$boardId 是复杂题才配的板块');
          }
          expect(
            content.panels.map((panel) => panel.boardId).toList(),
            simplePanels,
            reason: '物理简单题的学生页板块',
          );
          expect(
            selection.emptyBoards.map((gap) => gap.boardId),
            containsAll(<String>['l3_similar_questions', 'l4_subject_history']),
          );
        } else {
          // 数学/语文：复杂题 → 选 Thinking DAG + 过程解析。
          expect(selection.complexity, 'complex', reason: sample.id);
          expect(
            selection.hasBoard('l1_thinking_dag'),
            isTrue,
            reason: sample.id,
          );
          expect(
            selection.hasBoard('l1_solution_walkthrough'),
            isTrue,
            reason: sample.id,
          );
          expect(
            content.panels.map((panel) => panel.boardId).toList(),
            <String>[
              'l2_key_eye',
              'l2_traps',
              'l2_error_causes',
              if (sample.id == 'Q-CH0001') 'l2_layered_hints',
              'l3_extra_tasks',
              'l3_variants',
              'l4_extension_material',
            ],
            reason: '${sample.id} 的学生页板块',
          );
          expect(
            selection.emptyBoards.map((gap) => gap.boardId),
            contains('l4_subject_history'),
          );
        }
        // 数学 hints 为空 → 落进 empty_boards，不占位。
        if (sample.id == 'Q-MA0001') {
          expect(
            selection.emptyBoards
                .firstWhere((gap) => gap.boardId == 'l2_layered_hints')
                .reason,
            'empty_legacy_panel',
          );
        }

        // 只有《高考试题分析》来源（语文）在选板含过程解析时显示解析原文。
        if (sample.id == 'Q-CH0001') {
          expect(content.showSourceAnalysis, isTrue, reason: sample.id);
          expect(content.solution, isNotEmpty, reason: sample.id);
          expect(content.solutionNote, contains('高考试题分析'), reason: sample.id);
        } else {
          expect(content.showSourceAnalysis, isFalse, reason: sample.id);
          expect(content.solution, isEmpty, reason: sample.id);
          expect(content.solutionNote, isEmpty, reason: sample.id);
        }
        expect(content.aiAnswer.answer, isNotEmpty, reason: sample.id);
        expect(content.aiAnswer.reasoning, isNotEmpty, reason: sample.id);
        expect(content.aiAnswer.debate, isNotEmpty, reason: sample.id);
        // 报告腔（AI/非官方/未独立审核）只留开发者页：学生数据里不带说明。
        expect(content.aiAnswer.note, isEmpty, reason: sample.id);
        // 上位知识全文块：有内容、不截断（不以省略号收尾）。
        expect(content.upperKnowledge, isNotEmpty, reason: sample.id);
        for (final knowledge in content.upperKnowledge) {
          expect(knowledge.title, isNotEmpty, reason: sample.id);
          expect(knowledge.what, isNotEmpty, reason: sample.id);
          expect(knowledge.why, isNotEmpty, reason: sample.id);
          expect(knowledge.how, isNotEmpty, reason: sample.id);
          expect(knowledge.buildSteps, isNotEmpty, reason: sample.id);
          expect(
            knowledge.what.endsWith('…'),
            isFalse,
            reason: '${sample.id}/上位知识 what 被截断',
          );
          expect(
            knowledge.why.endsWith('…'),
            isFalse,
            reason: '${sample.id}/上位知识 why 被截断',
          );
        }
      }
    });

    test('学生页投影干净：报告腔/开发者术语/“无附图”不进学生内容', () async {
      final raw = jsonDecode(
        await File('assets/design_board.json').readAsString(),
      ) as Map<String, Object?>;
      const forbidden = <String>[
        'trust',
        'hash',
        'sha256',
        'evidence',
        '盲解',
        '内容包',
        'Source',
        'success_path',
        'expert_authored',
        'board.',
        '无附图',
        '机械估算',
        '答题区行数',
        '渲染 oracle',
        '预留',
        '固定 16 行',
        '未独立审核',
        '未经独立审核',
        '没有语义校验',
        'AI 整理',
        '非官方',
      ];
      final samples = (raw['realContentSamples'] as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(samples.length, 3);
      for (final sample in samples) {
        final id = sample['id'] as String;
        final studentContent =
            sample['studentContent']! as Map<String, Object?>;
        // sourceMode 是数据枚举（页面不渲染）；其余字段逐字符串扫描。
        final dagGraph = Map<String, Object?>.from(
          sample['dagGraph']! as Map<String, Object?>,
        )..remove('sourceMode');
        for (final entry in <String, Object?>{
          'studentContent': studentContent,
          'dagGraph': dagGraph,
        }.entries) {
          final strings = <String>[];
          _collectStrings(entry.value, strings);
          for (final text in strings) {
            for (final token in forbidden) {
              expect(
                text,
                isNot(contains(token)),
                reason: '$id/${entry.key} 含 "$token"：'
                    '${text.length > 40 ? text.substring(0, 40) : text}',
              );
            }
          }
        }
        // 图有/无逻辑 + 选择/解答答题区规则在数据层也成立。
        final figures = studentContent['figures']! as List<Object?>;
        expect(figures, isEmpty, reason: '内容包三题 figures=[]，不写“无附图”');
        final kind = studentContent['responseKind'] as String;
        final heightMm =
            (studentContent['answerAreaHeightMm'] as num).toDouble();
        if (id == 'Q-PH0001') {
          expect(kind, 'choice', reason: id);
          expect(heightMm, 0, reason: '$id 是单选题，不给答题区');
        } else {
          expect(kind, 'solution', reason: id);
          // 解答题给空白答题框，高度按分值：6 分 70–90 mm，12 分 120–150 mm。
          if (id == 'Q-CH0001') {
            expect(heightMm, inInclusiveRange(70, 90),
                reason: '$id 是 6 分解答题，答题框高度应在 70–90 mm');
          } else {
            expect(heightMm, inInclusiveRange(120, 150),
                reason: '$id 无分值、按 2 小问估 12 分，高度应在 120–150 mm');
          }
        }
      }
    });

    testWidgets('题干有图就显示（有图渲染图 + 图注），没图不写“无附图”', (tester) async {
      const sample = DesignBoardCard(
        id: 'Q-TEST01',
        title: '测试题',
        subtitle: '',
        statusLabel: '',
        chips: <String>[],
        lines: <String>[],
        studentContent: StudentContent(
          stem: '如图，一物体做平抛运动。',
          answer: 'B',
          solution: '',
          solutionNote: '',
          showSourceAnalysis: false,
          panels: <StudentPanel>[],
          aiAnswer: StudentAiAnswer(
            answer: 'B',
            reasoning: '只受重力。',
            debate: '',
            note: '',
          ),
          figures: <StudentFigure>[
            StudentFigure(
              id: 'F-1',
              caption: '图1 平抛轨迹',
              path: 'assets/figures/not-bundled-in-test.png',
            ),
          ],
          responseKind: 'solution',
          answerAreaHeightMm: 80,
        ),
      );
      await tester.pumpWidget(
        const MaterialApp(home: ContentSamplePage(sample: sample)),
      );
      await tester.pump();
      // 有图：渲染图块 + 图注（即使测试环境未打包图片，errorBuilder 也不崩）。
      expect(find.byKey(const Key('figure-Q-TEST01')), findsOneWidget);
      expect(find.text('图1 平抛轨迹'), findsOneWidget);
      expect(find.textContaining('无附图'), findsNothing);
      // 解答题有答题区；选择/填空没有（数据层由 needsAnswerArea 决定）。
      expect(find.text('答题区'), findsOneWidget);
      expect(find.byKey(const Key('answer-area-Q-TEST01')), findsOneWidget);
      // 答题区是**空白边框**：一个带边框、无子组件的容器；不画横线、不写行数。
      final boxFinder = find.byKey(const Key('answer-area-Q-TEST01'));
      final box = tester.widget<Container>(boxFinder);
      final decoration = box.decoration! as BoxDecoration;
      expect(decoration.border, isNotNull, reason: '答题区应有可见边框');
      expect(box.child, isNull, reason: '答题区是空白框，不画横线也不塞说明文字');
      expect(
        tester.getSize(boxFinder).height,
        closeTo(80 * 96 / 25.4, 0.5),
        reason: '80 mm 空白框按 96dpi 换算高度',
      );
      expect(sample.studentContent!.needsAnswerArea, isTrue);
    });

    test('decode 拒绝非对象 JSON', () {
      expect(
        () => DesignBoardData.decode('[]'),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('DesignBoardPage', () {
    testWidgets('按五层分组渲染名字 / 类型 / 状态 / 用户评价，展开显示机制', (
      tester,
    ) async {
      final data = assetData;
      tester.view.physicalSize = const Size(1400, 12000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(home: DesignBoardPage(source: _FakeSource(data))),
      );
      await tester.pumpAndSettle();

      expect(find.text('设计与内容板块'), findsOneWidget);
      for (final layer in data.layers) {
        expect(find.text(layer.label), findsOneWidget);
      }
      // 能力矩阵（task-48 真实数据）与内容 schema（task-23）都是真实只读卡片。
      expect(find.text('能力矩阵（真实数据，2026-11-15）'), findsOneWidget);
      expect(find.text('内容 schema 示例（L2-B / L2-C）'), findsOneWidget);
      expect(find.text('数据未完成'), findsNothing);
      expect(find.text('题眼'), findsOneWidget);

      final first = data.entries.first;
      expect(find.text(first.name), findsOneWidget);
      expect(
        find.textContaining('类型 ${first.layer}'),
        findsWidgets,
        reason: '每条要显示类型',
      );
      expect(find.textContaining('用户评价：'), findsWidgets);

      await tester.tap(find.byKey(Key('design-entry-${first.id}')));
      await tester.pumpAndSettle();
      expect(find.text('机制摘要'), findsWidgets);
      expect(find.text('机制明细'), findsWidgets);
      expect(find.textContaining(first.summary), findsWidgets);
    });

    testWidgets('真实内容样品：物理 + 数学 + 语文并列，展开语文卡看评分边界', (tester) async {
      final data = assetData;
      tester.view.physicalSize = const Size(1400, 4000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(home: DesignBoardPage(source: _FakeSource(data))),
      );
      await tester.pumpAndSettle();

      expect(find.text('真实内容样品（Q-PH0001）'), findsOneWidget);
      expect(find.text('真实内容样品（Q-MA0001）'), findsOneWidget);
      expect(find.text('真实内容样品（Q-CH0001）'), findsOneWidget);
      // 三条警告在折叠状态都可见，不用先展开。
      expect(find.textContaining('答案来自 Source'), findsWidgets);
      expect(find.textContaining('未独立审核'), findsWidgets);
      expect(find.textContaining('private_study_only'), findsWidgets);
      // 语文卡：无官方评分细则 + 分值 AI 均分的警告在折叠时可见。
      expect(find.textContaining('无官方评分细则'), findsWidgets);
      expect(find.textContaining('分值是 AI 均分'), findsWidgets);
      // 详细快照折叠时不渲染。
      expect(find.textContaining('PACKAGE VALID'), findsNothing);
      expect(find.textContaining('52/52'), findsNothing);

      await tester.tap(find.text('真实内容样品（Q-CH0001）'));
      await tester.pumpAndSettle();

      expect(find.textContaining('PACKAGE VALID'), findsOneWidget);
      expect(find.textContaining('52/52'), findsOneWidget);
      expect(find.textContaining('NOT-CAUGHT'), findsOneWidget);
      expect(find.textContaining('official_rubric'), findsOneWidget);
      expect(find.textContaining('Source 全文 0 命中'), findsOneWidget);
      expect(find.textContaining('公式全对'), findsNothing);
      expect(find.textContaining('公式全部正确'), findsNothing);
    });

    testWidgets('有示例卡片时原样展示（能力维度 / 题目板块）', (tester) async {
      const data = DesignBoardData(
        sourceDocument: 'FURNACE-DESIGN-REFERENCE-2026-11-15.md',
        sourceNote: '',
        layers: <DesignLayer>[
          DesignLayer(id: 'L2-A', label: 'L2-A 系统教育逻辑', description: '测试层'),
        ],
        entries: <DesignEntry>[
          DesignEntry(
            id: 'K-01',
            name: 'MIRT / Q-matrix',
            layer: 'L2-A',
            status: '待完善',
            statusRaw: 'Affirmed',
            userVerdict: '肯定',
            userEval: '用户判定：肯定。「测试引用」',
            summary: '测试摘要',
            mechanism: '作用：测试',
            evidence: 'A3',
            paper: '',
          ),
        ],
        abilityMatrix: DesignBoardCard(
          title: '能力矩阵示例',
          subtitle: '知识维度 + 元能力维度',
          statusLabel: '示例',
          chips: <String>['逻辑', '运算', '空间'],
          lines: <String>['维度来自测试 fixture，不是产品数据'],
        ),
        contentSchema: null,
        unfinished: <String, String>{'contentSchema': '数据未完成：测试'},
      );
      await tester.pumpWidget(
        MaterialApp(home: DesignBoardPage(source: _FakeSource(data))),
      );
      await tester.pumpAndSettle();

      expect(find.text('能力矩阵示例'), findsOneWidget);
      expect(find.text('逻辑'), findsOneWidget);
      expect(find.text('运算'), findsOneWidget);
      expect(find.text('空间'), findsOneWidget);
      expect(find.textContaining('测试 fixture'), findsOneWidget);
      // 缺一块时仍然回落到"数据未完成"，而不是静默消失。
      expect(find.textContaining('数据未完成：测试'), findsOneWidget);
    });

    testWidgets('读取失败时显示错误和重试，不伪造内容', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: DesignBoardPage(source: _FailingSource())),
      );
      await tester.pumpAndSettle();

      expect(find.text('本地数据读取失败'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });

  group('ContentSamplePage（学生视图）', () {
    testWidgets('学生视图：按板块库选配渲染（简单题无 DAG；复杂题有），无报告腔', (tester) async {
      final data = assetData;
      tester.view.physicalSize = const Size(1200, 16000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(home: DesignBoardPage(source: _FakeSource(data))),
      );
      await tester.pumpAndSettle();

      const checks = <String,
          ({String stemHint, String answerHint, bool solution, bool dag})>{
        // 物理是简单题（单选题）⇒ 不给答题区，也没有 DAG；数学/语文是复杂
        // 解答题 ⇒ 给答题区，并且选板含 Thinking DAG。
        'Q-PH0001': (
          stemHint: '平抛',
          answerHint: 'B',
          solution: false,
          dag: false,
        ),
        'Q-MA0001': (
          stemHint: '列联表',
          answerHint: '9/10',
          solution: true,
          dag: true,
        ),
        'Q-CH0001': (
          stemHint: '袍色',
          answerHint: '以砚喻人',
          solution: true,
          dag: true,
        ),
      };
      for (final entry in checks.entries) {
        await tester.tap(find.byKey(Key('open-sample-${entry.key}')));
        await tester.pumpAndSettle();
        expect(find.text('题目详情'), findsOneWidget);
        expect(find.textContaining(entry.value.stemHint), findsWidgets);
        // 题目册规则：选择/填空无答题区；解答题给空白答题框（无横线、无行数说明）。
        expect(
          find.text('答题区'),
          entry.value.solution ? findsOneWidget : findsNothing,
          reason: '${entry.key}/答题区',
        );
        expect(
          find.byKey(Key('answer-area-${entry.key}')),
          entry.value.solution ? findsOneWidget : findsNothing,
          reason: entry.key,
        );
        if (entry.value.solution) {
          final box = tester.widget<Container>(
            find.byKey(Key('answer-area-${entry.key}')),
          );
          expect(
            (box.decoration! as BoxDecoration).border,
            isNotNull,
            reason: '${entry.key}/答题区应有边框',
          );
          expect(box.child, isNull, reason: '${entry.key}/答题区是空白框，不画横线');
        }
        // 三题都没有图：不渲染图块，也不写“无附图”。
        expect(find.byKey(Key('figure-${entry.key}')), findsNothing,
            reason: entry.key);
        expect(find.textContaining('无附图'), findsNothing, reason: entry.key);
        // 旧的“做题区”提示文案已删除（不再是报告腔/开发者说明）。
        expect(find.text('做题区'), findsNothing, reason: entry.key);
        expect(find.textContaining('先在纸上独立作答'), findsNothing,
            reason: entry.key);
        // 答案默认折叠：先做题再看答案（learner-review P0）。
        expect(find.byKey(Key('answer-panel-${entry.key}')), findsOneWidget);
        expect(
          find.byKey(Key('answer-content-${entry.key}')),
          findsNothing,
        );
        await tester.tap(find.byKey(Key('answer-panel-${entry.key}')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(Key('answer-content-${entry.key}')),
          findsOneWidget,
        );
        expect(find.textContaining(entry.value.answerHint), findsWidgets);
        // DAG：按选板渲染 —— 简单题没有入口；复杂题默认折叠、可展开。
        if (entry.value.dag) {
          expect(find.text('Thinking DAG'), findsOneWidget, reason: entry.key);
          expect(find.byKey(Key('dag-panel-${entry.key}')), findsOneWidget);
          expect(find.byKey(Key('dag-flow-${entry.key}')), findsNothing);
          await tester.tap(find.byKey(Key('dag-panel-${entry.key}')));
          await tester.pumpAndSettle();
          expect(find.byKey(Key('dag-flow-${entry.key}')), findsOneWidget);
          // 节点是短节点 + 公式/关键量/结论，不渲染整段正文。
          expect(find.textContaining('关键量：'), findsWidgets);
          expect(find.textContaining('结论：'), findsWidgets);
          // 复杂题的 DAG 旁支（数学第二解法 / 语文另一种读法）在 DAG 里给。
          expect(find.textContaining('另一条路'), findsOneWidget);
        } else {
          // 简单题：没有 DAG 入口，也没有“另一条路/排除支”。
          expect(find.text('Thinking DAG'), findsNothing, reason: entry.key);
          expect(find.byKey(Key('dag-panel-${entry.key}')), findsNothing);
          expect(
            find.textContaining('另一条路'),
            findsNothing,
            reason: entry.key,
          );
          expect(find.textContaining('排除支'), findsNothing, reason: entry.key);
        }
        // 解析原文：只有《高考试题分析》来源（语文）+ 选板含过程解析。
        if (entry.key == 'Q-CH0001') {
          expect(find.text('解析原文（据解析卷，对完答案再看）'), findsOneWidget);
          expect(
            find.byKey(Key('solution-content-${entry.key}')),
            findsNothing,
          );
          await tester.tap(find.byKey(Key('solution-panel-${entry.key}')));
          await tester.pumpAndSettle();
          expect(
            find.byKey(Key('solution-content-${entry.key}')),
            findsOneWidget,
          );
          expect(find.textContaining('高考试题分析'), findsWidgets);
        } else {
          // 非《高考试题分析》来源不单独显示解析原文（DAG 即解析）。
          expect(find.textContaining('解析原文（据解析卷'), findsNothing);
          expect(
            find.byKey(Key('solution-panel-${entry.key}')),
            findsNothing,
          );
        }
        // L2 诊断层：题眼/陷阱/错因/（复杂题的）分层提示合并成一块。
        expect(
            find.byKey(Key('diagnostic-section-${entry.key}')), findsOneWidget);
        expect(find.text('诊断'), findsOneWidget);
        expect(find.text('题眼'), findsOneWidget);
        expect(find.text('陷阱/易错点'), findsOneWidget);
        expect(find.text('错因'), findsOneWidget);
        if (entry.key == 'Q-CH0001') {
          expect(find.text('分层提示'), findsOneWidget, reason: entry.key);
        } else {
          // 简单题不给提示；数学 hints 空 → 空板块不占位。
          expect(find.text('分层提示'), findsNothing, reason: entry.key);
        }
        // 三题 failed_branches 都空：卡点不占位（选板也不会选）。
        expect(find.text('卡点'), findsNothing, reason: entry.key);
        // L3 训练层：额外任务 → 变式 → 同源题（候选空 → 不占位）。
        expect(
            find.byKey(Key('training-section-${entry.key}')), findsOneWidget);
        expect(find.text('训练（由近及远）'), findsOneWidget);
        expect(find.text('额外任务'), findsOneWidget);
        expect(find.text('变式'), findsOneWidget);
        expect(find.text('同源题'), findsNothing);
        expect(
          tester.getTopLeft(find.text('额外任务')).dy,
          lessThan(tester.getTopLeft(find.text('变式')).dy),
          reason: '${entry.key}/L3 顺序：额外任务在变式之前',
        );
        // L4 背景层拆两块：扩展资料有；学科史旧内容没来源 → 不占位。
        expect(
            find.byKey(Key('extension-section-${entry.key}')), findsOneWidget);
        expect(find.text('扩展资料'), findsOneWidget);
        expect(find.text('学科史'), findsNothing, reason: entry.key);
        // L5 元信息不进学生正文；空板块不写“暂无”占位。
        expect(find.text('五维正向推导'), findsNothing, reason: entry.key);
        expect(find.text('九板块内容'), findsNothing, reason: entry.key);
        expect(find.textContaining('暂无'), findsNothing, reason: entry.key);
        // 旧的“其余板块见上方”解释文案也不存在。
        expect(
          find.textContaining('Thinking DAG 与分层提示见上方'),
          findsNothing,
        );
        // 【AI】只出现在版块标题末尾；正文不再加 AI/非官方标记。
        expect(find.text('另一种答案与理由【AI】'), findsOneWidget);
        expect(find.textContaining('【AI】'), findsOneWidget);
        expect(find.text('答案'), findsWidgets);
        expect(find.text('为什么这样想'), findsOneWidget);
        expect(find.text('请你判断'), findsOneWidget);
        expect(find.text('你同意吗？哪一步有问题？'), findsOneWidget);
        expect(find.textContaining('AI 答案'), findsNothing);
        expect(find.textContaining('非官方'), findsNothing);
        for (final panel in <String>[
          '题眼',
          '陷阱/易错点',
          '错因',
          '变式',
          '扩展资料',
          '额外任务',
        ]) {
          expect(find.text(panel), findsWidgets, reason: '${entry.key}/$panel');
        }
        // 上位知识用全文块渲染（不是 240 字摘要）：数据里的前 30 字要能在页面找到。
        final sampleForEntry = data.realContentSamples.firstWhere(
          (item) => item.id == entry.key,
        );
        final knowledge = sampleForEntry.studentContent!.upperKnowledge.first;
        expect(knowledge.what.length, greaterThan(30), reason: entry.key);
        expect(
          find.textContaining(knowledge.what.substring(0, 30)),
          findsWidgets,
          reason: '${entry.key}/上位知识全文块',
        );
        // 学生页不出现开发者元数据与报告腔。
        for (final forbidden in <String>[
          'trust',
          'hash',
          'answer_source',
          'sha256',
          'evidence',
          '只读',
          '必要文本',
          '来源与证据',
          '非官方',
          '盲解',
          '主链',
          '内容包已记',
          '没有语义校验',
          '个逻辑节点',
          '默认折叠',
          '无附图',
          '答题区行数',
          '机械估算',
          '渲染 oracle',
          '未独立审核',
          '未经独立审核',
          'AI 整理',
        ]) {
          expect(
            find.textContaining(forbidden),
            findsNothing,
            reason: '${entry.key}/$forbidden',
          );
        }
        // 无横向滚动（打印友好）。
        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is SingleChildScrollView &&
                widget.scrollDirection == Axis.horizontal,
          ),
          findsNothing,
          reason: entry.key,
        );
        expect(
          find.byKey(Key('open-developer-info-${entry.key}')),
          findsOneWidget,
        );
        Navigator.of(tester.element(find.byType(ContentSamplePage))).pop();
        await tester.pumpAndSettle();
      }
    });

    testWidgets('开发者信息页保留 trust/hash/来源/Problem State', (tester) async {
      final data = assetData;
      tester.view.physicalSize = const Size(1200, 9000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(home: DesignBoardPage(source: _FakeSource(data))),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('open-sample-Q-PH0001')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('open-developer-info-Q-PH0001')));
      await tester.pumpAndSettle();

      expect(find.byType(DeveloperInfoPage), findsOneWidget);
      expect(find.text('开发者信息（只读）'), findsOneWidget);
      expect(find.textContaining('official_trust'), findsWidgets);
      expect(find.textContaining('PACKAGE VALID'), findsWidgets);
      expect(find.text('Problem State（只读）'), findsOneWidget);
      expect(find.text('来源与证据'), findsOneWidget);

      Navigator.of(tester.element(find.byType(DeveloperInfoPage))).pop();
      await tester.pumpAndSettle();
      expect(find.byType(DeveloperInfoPage), findsNothing);
    });

    testWidgets('DAG 纵向逻辑 flowchart：语义标签、无横向滚动、分支纵向展开', (
      tester,
    ) async {
      final data = assetData;
      tester.view.physicalSize = const Size(1200, 9000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(home: DesignBoardPage(source: _FakeSource(data))),
      );
      await tester.pumpAndSettle();

      // 物理（简单题，选板不含 L1）：学生页没有 DAG 入口。
      await tester.tap(find.byKey(const Key('open-sample-Q-PH0001')));
      await tester.pumpAndSettle();
      expect(find.text('Thinking DAG'), findsNothing);
      expect(find.byKey(const Key('dag-panel-Q-PH0001')), findsNothing);
      expect(find.byKey(const Key('dag-flow-Q-PH0001')), findsNothing);
      Navigator.of(tester.element(find.byType(ContentSamplePage))).pop();
      await tester.pumpAndSettle();

      // 数学（复杂题）：DAG 默认折叠；展开后语义标签可读、无横向滚动。
      await tester.tap(find.byKey(const Key('open-sample-Q-MA0001')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('dag-flow-Q-MA0001')), findsNothing);
      await tester.tap(find.byKey(const Key('dag-panel-Q-MA0001')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('dag-flow-Q-MA0001')), findsOneWidget);
      // 短节点：节点整段正文不再渲染到学生页（正文只留在数据里）。
      expect(find.textContaining('盲解'), findsNothing);
      for (final label in <String>[
        '审题',
        '建模',
        '验证/排除',
        '结论',
        '计算',
      ]) {
        expect(find.text(label), findsWidgets, reason: label);
      }
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is SingleChildScrollView &&
              widget.scrollDirection == Axis.horizontal,
        ),
        findsNothing,
      );
      // 数学：N-MA-03 / N-MA-04 同层 => 分支纵向展开。
      expect(find.text('└ 分支'), findsWidgets);
    });
  });

  group('设置页入口', () {
    testWidgets('设置页有"设计与内容板块"入口，点开是只读板块', (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      tester.view.physicalSize = const Size(1200, 6000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [appDatabaseProvider.overrideWithValue(db)],
          child: const MaterialApp(
            locale: Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: SettingsPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 2026-11-15 设置页重构：设计板块属于开发者分区，默认折叠。
      expect(find.byKey(settingsDesignBoardTileKey), findsNothing);
      await tester.tap(find.byKey(settingsDeveloperToggleKey));
      await tester.pumpAndSettle();

      final tileFinder = find.byKey(settingsDesignBoardTileKey);
      expect(tileFinder, findsOneWidget);
      expect(find.text('设计与内容板块'), findsOneWidget);

      // 直接调用 tile 的 onTap（列表很长，键盘命中测试不稳定）；这仍然验证
      // "入口 → Navigator.push → DesignBoardPage" 这条线。
      tester.widget<ListTile>(tileFinder).onTap!();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(DesignBoardPage), findsOneWidget);
      // 该页默认从 rootBundle 读 asset，测试环境里加载不保证完成，圆形进度条
      // 会一直排帧；所以不用 pumpAndSettle，而是弹回设置页再 settle。
      Navigator.of(tester.element(find.byType(DesignBoardPage))).pop();
      await tester.pumpAndSettle();
      expect(find.byType(DesignBoardPage), findsNothing);
    });
  });
}
