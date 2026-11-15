import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/content/board_library.dart';
import 'package:furnace/domain/services/content/legacy_board_mapper.dart';

/// 真实内容包冒烟（task-95 / P2 D9 接线）：三份内容包（物理/数学/语文）走一遍
/// 旧 9 板块 → L0–L5 的映射，锁住三题的选板结果、空板块与未映射板块；同时把
/// 三题的 `BoardSelection` JSON 打出来（报告直接引用）。
///
/// 这是**实验/验收**测试，不是纯规则单测：它直接读工作区内容包的绝对路径，
/// 文件不在本机时整组 skip（与 `test/experiments/` 其它用例同口径）。纯规则
/// 单测在 `test/domain/services/content/legacy_board_mapper_test.dart`。
void main() {
  const contentStore = r'E:\Workspaces\agent-control'
      r'\10-projects\agent-control-plane\content-store';

  final packages = <String, List<String>>{
    'physics': <String>[
      '$contentStore\\physics\\Q-PH0001\\question.json',
      '$contentStore\\physics\\Q-PH0001\\boards\\physics-board.json',
    ],
    'math': <String>[
      '$contentStore\\math\\Q-MA0001\\question.json',
      '$contentStore\\math\\Q-MA0001\\boards\\math-board.json',
    ],
    'chinese': <String>[
      '$contentStore\\chinese\\Q-CH0001\\question.json',
      '$contentStore\\chinese\\Q-CH0001\\boards\\chinese-board.json',
    ],
  };

  final missing = <String>[
    for (final entry in packages.entries)
      if (!File(entry.value[0]).existsSync() ||
          !File(entry.value[1]).existsSync())
        entry.key,
  ];
  if (missing.isNotEmpty) {
    test('三份内容包不在本机，跳过真实内容冒烟', () {}, skip: 'missing: $missing');
    return;
  }

  final questions = <String, Map<String, Object?>>{
    for (final entry in packages.entries)
      entry.key: jsonDecode(File(entry.value[0]).readAsStringSync())
          as Map<String, Object?>,
  };
  final boards = <String, Map<String, Object?>>{
    for (final entry in packages.entries)
      entry.key: jsonDecode(File(entry.value[1]).readAsStringSync())
          as Map<String, Object?>,
  };
  final selections = <String, BoardSelection>{
    for (final entry in packages.entries)
      entry.key: const LegacyBoardMapper().map(
        question: questions[entry.key]!,
        board: boards[entry.key]!,
      ),
  };

  List<String> ids(BoardSelection selection) => selection.boardIds;

  test('物理 Q-PH0001：简单题，不配 DAG/过程解析；L3→L4 按内容给', () {
    final selection = selections['physics']!;
    expect(selection.questionId, 'Q-PH0001');
    expect(selection.subject, 'physics');
    expect(selection.complexity, QuestionComplexity.simple);
    expect(selection.complexitySource, LegacyComplexitySources.defaultSimple);
    expect(selection.questionType, 'concept');
    expect(selection.questionTypeSource,
        LegacyQuestionTypeSources.contentTypeAxes);
    expect(
      ids(selection),
      <String>[
        'l0_question_entity',
        'l2_key_eye',
        'l2_traps',
        'l2_error_causes',
        'l3_extra_tasks',
        'l3_variants',
        'l4_extension_material',
        'l5_meta',
      ],
    );
    // 简单题：L1 整段不出现，卡点/分层提示也不出现。
    expect(selection.boardsAt(BoardLevel.l1), isEmpty);
    expect(ids(selection), isNot(contains('l2_stuck_points')));
    expect(ids(selection), isNot(contains('l2_layered_hints')));
    // 空板块：同源题候选空、学科史没有旧来源；不是占位。
    expect(
      <String>[
        for (final gap in selection.emptyBoards) '${gap.boardId}:${gap.reason}',
      ],
      <String>[
        'l3_similar_questions:no_candidates',
        'l4_subject_history:no_legacy_source',
      ],
    );
    expect(_panel(selection, LegacyBoardPanels.thinkingDag).status,
        LegacyPanelStatus.notSelected);
    expect(_panel(selection, LegacyBoardPanels.hints).status,
        LegacyPanelStatus.empty);
    expect(_panel(selection, LegacyBoardPanels.fiveDimension).status,
        LegacyPanelStatus.absorbed);
    expect(_panel(selection, LegacyBoardPanels.subjectSpecific).status,
        LegacyPanelStatus.unmapped);
  });

  test('数学 Q-MA0001：第二解法→复杂；DAG/多解/训练/背景都有', () {
    final selection = selections['math']!;
    expect(selection.questionId, 'Q-MA0001');
    expect(selection.subject, 'math');
    expect(selection.complexity, QuestionComplexity.complex);
    expect(selection.complexitySource, LegacyComplexitySources.secondMethod);
    expect(selection.questionType, 'calculation');
    expect(
      ids(selection),
      <String>[
        'l0_question_entity',
        'l1_thinking_dag',
        'l1_solution_walkthrough',
        'l1_multi_solution',
        'l2_key_eye',
        'l2_traps',
        'l2_error_causes',
        'l3_extra_tasks',
        'l3_variants',
        'l4_extension_material',
        'l5_meta',
      ],
    );
    expect(
      <String>[
        for (final gap in selection.emptyBoards) '${gap.boardId}:${gap.reason}',
      ],
      <String>[
        'l2_stuck_points:empty_legacy_panel',
        'l2_layered_hints:empty_legacy_panel',
        'l3_similar_questions:no_candidates',
        'l4_subject_history:no_legacy_source',
      ],
    );
    expect(_panel(selection, LegacyBoardPanels.thinkingDag).status,
        LegacyPanelStatus.mapped);
    expect(_panel(selection, LegacyBoardPanels.hints).status,
        LegacyPanelStatus.empty);
    expect(_panel(selection, LegacyBoardPanels.variants).status,
        LegacyPanelStatus.mapped);
    expect(_panel(selection, LegacyBoardPanels.extensions).status,
        LegacyPanelStatus.mapped);
  });

  test('语文 Q-CH0001：分层提示→复杂；阅读题不配一题多解', () {
    final selection = selections['chinese']!;
    expect(selection.questionId, 'Q-CH0001');
    expect(selection.subject, 'chinese');
    expect(selection.complexity, QuestionComplexity.complex);
    expect(selection.complexitySource, LegacyComplexitySources.hintsLadder);
    expect(selection.questionType, 'reading');
    expect(
      ids(selection),
      <String>[
        'l0_question_entity',
        'l1_thinking_dag',
        'l1_solution_walkthrough',
        'l2_key_eye',
        'l2_traps',
        'l2_error_causes',
        'l2_layered_hints',
        'l3_extra_tasks',
        'l3_variants',
        'l4_extension_material',
        'l5_meta',
      ],
    );
    // 旧板里的“另一种读法”是 unverified_alternative_reading，不算多解。
    expect(ids(selection), isNot(contains('l1_multi_solution')));
    expect(
      <String>[
        for (final gap in selection.emptyBoards) '${gap.boardId}:${gap.reason}',
      ],
      <String>[
        'l2_stuck_points:empty_legacy_panel',
        'l3_similar_questions:no_candidates',
        'l4_subject_history:no_legacy_source',
      ],
    );
    expect(_panel(selection, LegacyBoardPanels.hints).status,
        LegacyPanelStatus.mapped);
    expect(_panel(selection, LegacyBoardPanels.thinkingDag).status,
        LegacyPanelStatus.mapped);
  });

  test('三题都只带引用：源正文不出现在 selection JSON 里', () {
    for (final subject in packages.keys) {
      final selection = selections[subject]!;
      final board = boards[subject]!;
      final question = questions[subject]!;
      final json = selection.toJsonString();
      final samples = <String?>[
        _nested(question, <String>['stem', 'text'])?.toString(),
        _nested(board, <String>['key_eye', 'items', '0', 'statement'])
            ?.toString(),
        _nested(board, <String>['traps', 'items', '0', 'student_would_do'])
            ?.toString(),
        _nested(board, <String>['extensions', 'items', '0', 'what'])
            ?.toString(),
        _nested(board, <String>['thinking_dag', 'nodes', '0', 'body'])
            ?.toString(),
      ];
      for (final sample in samples) {
        expect(sample, isNotNull);
        final text = sample!;
        expect(text.length, greaterThan(20), reason: subject);
        expect(json.contains(text), isFalse, reason: '$subject 复制了正文');
      }
    }
  });

  test('三题：五维吸收进 L5（动态键），学科专属板未映射', () {
    for (final subject in packages.keys) {
      final selection = selections[subject]!;
      final fiveKeys = selection.meta['five_dimension_keys']! as List<Object?>;
      expect(fiveKeys, hasLength(5), reason: subject);
      expect(
        fiveKeys,
        <String>[
          'question_type',
          'exam_method',
          'setter_intent',
          'solution_path',
          'ability_training',
        ],
        reason: subject,
      );
      expect(
        ids(selection).any((id) => id.contains('five')),
        isFalse,
        reason: subject,
      );
      expect(_panel(selection, LegacyBoardPanels.fiveDimension).status,
          LegacyPanelStatus.absorbed);
      expect(_panel(selection, LegacyBoardPanels.subjectSpecific).status,
          LegacyPanelStatus.unmapped);
      final axes = selection.meta['content_type_axes'];
      expect(axes, isA<Map<String, Object?>>(), reason: subject);
      expect(
        (axes! as Map<String, Object?>)['scope'],
        'single_point',
        reason: subject,
      );
    }
  });

  test('三题 selection JSON（demo 输出）', () {
    for (final subject in packages.keys) {
      final encoded = const JsonEncoder.withIndent('  ')
          .convert(selections[subject]!.toJson());
      // 打印给 `flutter test` 的 demo 输出/报告引用；断言只是防止空输出。
      // ignore: avoid_print
      print('=== LEGACY BOARD SELECTION $subject ===\n$encoded');
      expect(encoded.length, greaterThan(500));
    }
  });
}

LegacyPanelDisposition _panel(BoardSelection selection, String panel) =>
    selection.panels.firstWhere((disposition) => disposition.panel == panel);

Object? _nested(Map<String, Object?> json, List<String> path) {
  Object? current = json;
  for (final segment in path) {
    if (current is Map<String, Object?>) {
      current = current[segment];
    } else if (current is Map) {
      current = current[segment];
    } else if (current is List) {
      final index = int.tryParse(segment);
      if (index == null || index < 0 || index >= current.length) {
        return null;
      }
      current = current[index];
    } else {
      return null;
    }
  }
  return current;
}
