import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/content/board_library.dart';
import 'package:furnace/domain/services/content/legacy_board_mapper.dart';

/// 所有正文都带这个标记：用来证明输出只保留引用、不复制正文。
const String _bodyMarker = 'SECRET-BODY-MARKER';

Map<String, Object?> _question({
  String id = 'Q-T0001',
  String subject = 'physics',
  String carrier = 'mechanics',
  String task = 'compute',
  num? difficulty = 2,
  List<String> capabilityCodes = const <String>['A1'],
}) {
  return <String, Object?>{
    'id': id,
    'subject': subject,
    'stem': <String, Object?>{
      'text': '题干 $_bodyMarker',
      'format': 'markdown+latex',
    },
    'answer': <String, Object?>{
      'parts': <Object?>[
        <String, Object?>{'part': 'all', 'value': 'B', 'format': 'text'},
      ],
    },
    'solutions': <Object?>[
      <String, Object?>{
        'id': 'SOL-1',
        'kind': 'official_source',
        'body_md': '解析 $_bodyMarker',
      },
    ],
    'figures': <Object?>[
      <String, Object?>{'id': 'M-1', 'role': 'stem', 'path': 'fig.png'},
    ],
    'classification': <String, Object?>{
      'content_type': <String, Object?>{
        'code': 'TEST-CODE',
        'label': '测试题型',
        'axes': <String, Object?>{
          'carrier': carrier,
          'task': task,
          'thinking': <String>['forward'],
          'scope': 'single_point',
        },
        'paper_form': 'solution',
      },
      'capability': <Object?>[
        for (final code in capabilityCodes) <String, Object?>{'code': code},
      ],
      'knowledge': <Object?>[
        <String, Object?>{
          'node_id': 'kp-1',
          'label': '知识点',
          'role': 'primary',
          'source': 'manual',
        },
      ],
      'subquestions': <Object?>[],
    },
    'meta': <String, Object?>{
      'source_level': 'gaokao',
      'source_label': '测试来源',
      'year': 2025,
      'region': '全国一卷',
      'difficulty': difficulty == null
          ? <String, Object?>{}
          : <String, Object?>{
              'value': difficulty,
              'source': 'ai',
              'confidence': 0.35,
            },
    },
    'scoring': <String, Object?>{'total_points': 6, 'source': 'official'},
    'provenance': <String, Object?>{'version': 1},
  };
}

Map<String, Object?> _item(String id) => <String, Object?>{
      'id': id,
      'statement': '题眼正文 $_bodyMarker',
      'student_would_do': '学生会这样做 $_bodyMarker',
      'symptom': '症状 $_bodyMarker',
      'stem': '变式题干 $_bodyMarker',
      'prompt': '任务提示 $_bodyMarker',
      'what': '扩展正文 $_bodyMarker',
      'text': '提示正文 $_bodyMarker',
    };

Map<String, Object?> _board({
  String questionId = 'Q-T0001',
  bool dag = true,
  int dagNodes = 6,
  List<Map<String, Object?>> alternatePaths = const <Map<String, Object?>>[],
  List<Map<String, Object?>> failedBranches = const <Map<String, Object?>>[],
  int keyEye = 1,
  int traps = 1,
  int errorCauses = 1,
  int hintLevels = 0,
  int variants = 1,
  int extensions = 1,
  int extraTasks = 1,
  List<Map<String, Object?>> similarCandidates = const <Map<String, Object?>>[],
  List<String> fiveDimensionKeyNames = const <String>[
    'question_type',
    'exam_method',
    'setter_intent',
    'solution_path',
    'ability_training',
  ],
  Map<String, Object?>? subjectSpecific,
  List<Map<String, Object?>> omittedBoards = const <Map<String, Object?>>[],
  Map<String, Object?> extraTopLevel = const <String, Object?>{},
}) {
  return <String, Object?>{
    'schema_version': 'furnace.content.physics-board/1',
    'subject': 'physics',
    'question_id': questionId,
    'meta': <String, Object?>{
      'board_version': 2,
      'coverage': <String, Object?>{},
      'omitted_boards': omittedBoards,
      'invalidation_rule': 'test',
    },
    if (fiveDimensionKeyNames.isNotEmpty)
      'five_dimension': <String, Object?>{
        for (final key in fiveDimensionKeyNames)
          key: <String, Object?>{'claim': '五维正文 $_bodyMarker'},
      },
    'thinking_dag': <String, Object?>{
      'nodes': dag
          ? <Object?>[
              for (var index = 0; index < dagNodes; index++)
                <String, Object?>{
                  'id': 'N-T-$index',
                  'body': 'DAG 节点正文 $_bodyMarker',
                },
            ]
          : <Object?>[],
      'edges': <Object?>[],
      'success_path': dag
          ? <Object?>[
              for (var index = 0; index < dagNodes; index++) 'N-T-$index',
            ]
          : <Object?>[],
      'alternate_paths': alternatePaths,
      'failed_branches': failedBranches,
    },
    'key_eye': <String, Object?>{
      'items': <Object?>[
        for (var index = 0; index < keyEye; index++) _item('K-$index'),
      ],
    },
    'traps': <String, Object?>{
      'items': <Object?>[
        for (var index = 0; index < traps; index++) _item('T-$index'),
      ],
    },
    'hints': <String, Object?>{
      'policy': <String, Object?>{
        'only_hard': hintLevels > 0,
        'max_level': hintLevels,
      },
      'ladder': <Object?>[
        for (var index = 0; index < hintLevels; index++)
          <String, Object?>{
            'level': index + 1,
            'kind': 'direction',
            'text': '提示正文 $_bodyMarker',
            'reveals': <Object?>['N-T-0'],
            'unlock_rule': 'student_requests',
            'must_not_contain_answer': true,
          },
      ],
      'no_hint_note': hintLevels > 0 ? '提示不含答案' : '简单题不给提示',
    },
    'error_causes': <String, Object?>{
      'items': <Object?>[
        for (var index = 0; index < errorCauses; index++) _item('EC-$index'),
      ],
    },
    'variants': <String, Object?>{
      'items': <Object?>[
        for (var index = 0; index < variants; index++)
          <String, Object?>{
            'id': 'V-$index',
            'stem': '变式题干 $_bodyMarker',
            'related_questions': <String, Object?>{
              'candidates': index == 0 ? similarCandidates : <Object?>[],
              'search_scope': 'test',
              'status': similarCandidates.isEmpty ? 'searched_empty' : 'found',
            },
          },
      ],
    },
    'extensions': <String, Object?>{
      'items': <Object?>[
        for (var index = 0; index < extensions; index++) _item('X-$index'),
      ],
    },
    'extra_tasks': <String, Object?>{
      'items': <Object?>[
        for (var index = 0; index < extraTasks; index++) _item('AT-$index'),
      ],
    },
    if (subjectSpecific != null) 'subject_specific': subjectSpecific,
    ...extraTopLevel,
  };
}

List<String> _ids(BoardSelection selection) => selection.boardIds;

List<String> _idsAt(BoardSelection selection, BoardLevel level) => <String>[
      for (final board in selection.boardsAt(level)) board.boardId,
    ];

LegacyPanelDisposition _panel(BoardSelection selection, String panel) =>
    selection.panels.firstWhere((disposition) => disposition.panel == panel);

Map<String, Object?> _secondMethod() => <String, Object?>{
      'id': 'AP-T-01',
      'kind': 'second_method',
      'method_name': '第二解法',
      'node_ids': <Object?>['N-T-0', 'N-T-1'],
      'verdict': 'same_answer',
      'note': 'test',
    };

Map<String, Object?> _shortcutPath() => <String, Object?>{
      'id': 'AP-T-02',
      'kind': 'shortcut_path',
      'method_name': '省时顺序',
      'node_ids': <Object?>['N-T-0', 'N-T-1'],
      'verdict': 'same_answer',
      'note': 'test',
    };

Map<String, Object?> _candidate() => <String, Object?>{
      'id': 'Q-OTHER',
      'title': '同源题候选 $_bodyMarker',
    };

Map<String, Object?> _failedBranch() => <String, Object?>{
      'root': 'N-T-0',
      'dead_end': 'N-T-1',
      'why': '卡在这里 $_bodyMarker',
      'detected_at': 'test',
      'cost_note': 'test',
    };

Map<String, Object?> _fullBoard() => _board(
      alternatePaths: <Map<String, Object?>>[_secondMethod()],
      failedBranches: <Map<String, Object?>>[_failedBranch()],
      hintLevels: 2,
      similarCandidates: <Map<String, Object?>>[_candidate()],
      subjectSpecific: <String, Object?>{
        'modeling': <String, Object?>{'note': '学科板 $_bodyMarker'},
      },
    );

BoardSelection _mapFull({QuestionComplexity? complexity}) =>
    const LegacyBoardMapper().map(
      question: _question(task: 'compute'),
      board: _fullBoard(),
      complexity: complexity,
    );

void main() {
  group('内容题型四轴 → 粗粒度题型', () {
    test('task 直接映射的类别', () {
      expect(
        LegacyQuestionTypeMapping.fromContentTypeAxes(
          <String, Object?>{'task': 'prove'},
        ),
        BoardQuestionType.proof,
      );
      expect(
        LegacyQuestionTypeMapping.fromContentTypeAxes(
          <String, Object?>{'task': 'compute'},
        ),
        BoardQuestionType.calculation,
      );
      expect(
        LegacyQuestionTypeMapping.fromContentTypeAxes(
          <String, Object?>{'task': 'transform'},
        ),
        BoardQuestionType.derivation,
      );
      expect(
        LegacyQuestionTypeMapping.fromContentTypeAxes(
          <String, Object?>{'task': 'model'},
        ),
        BoardQuestionType.derivation,
      );
      expect(
        LegacyQuestionTypeMapping.fromContentTypeAxes(
          <String, Object?>{'task': 'explain'},
        ),
        BoardQuestionType.concept,
      );
      expect(
        LegacyQuestionTypeMapping.fromContentTypeAxes(
          <String, Object?>{'task': 'write'},
        ),
        BoardQuestionType.expression,
      );
      expect(
        LegacyQuestionTypeMapping.fromContentTypeAxes(
          <String, Object?>{'task': 'design'},
        ),
        BoardQuestionType.experiment,
      );
      for (final task in <String>['summarize', 'retrieve', 'translate']) {
        expect(
          LegacyQuestionTypeMapping.fromContentTypeAxes(
            <String, Object?>{'task': task},
          ),
          BoardQuestionType.reading,
          reason: task,
        );
      }
      for (final task in <String>['predict', 'diagnose']) {
        expect(
          LegacyQuestionTypeMapping.fromContentTypeAxes(
            <String, Object?>{'task': task},
          ),
          BoardQuestionType.concept,
          reason: task,
        );
      }
    });

    test('evaluate 按载体区分阅读与计算', () {
      expect(
        LegacyQuestionTypeMapping.fromContentTypeAxes(
          <String, Object?>{'task': 'evaluate', 'carrier': 'poetry'},
        ),
        BoardQuestionType.reading,
      );
      expect(
        LegacyQuestionTypeMapping.fromContentTypeAxes(
          <String, Object?>{'task': 'evaluate', 'carrier': 'other'},
        ),
        BoardQuestionType.calculation,
      );
    });

    test('大小写/空白容错；缺 task 或认不出返回 null（不猜）', () {
      expect(
        LegacyQuestionTypeMapping.fromContentTypeAxes(
          <String, Object?>{'task': ' EXPLAIN '},
        ),
        BoardQuestionType.concept,
      );
      expect(
        LegacyQuestionTypeMapping.fromContentTypeAxes(
          <String, Object?>{'task': 'evaluate', 'carrier': ' Poetry '},
        ),
        BoardQuestionType.reading,
      );
      expect(LegacyQuestionTypeMapping.fromContentTypeAxes(null), isNull);
      expect(
        LegacyQuestionTypeMapping.fromContentTypeAxes(
          <String, Object?>{'task': ''},
        ),
        isNull,
      );
      expect(
        LegacyQuestionTypeMapping.fromContentTypeAxes(
          <String, Object?>{'task': 'quantum_tea'},
        ),
        isNull,
      );
    });
  });

  group('复杂度推导 inferLegacyComplexity', () {
    test('没有任何复杂信号 → 简单（default_simple）', () {
      final decision = inferLegacyComplexity(
        question: _question(difficulty: 2),
        board: _board(alternatePaths: <Map<String, Object?>>[_shortcutPath()]),
      );
      expect(decision.complexity, QuestionComplexity.simple);
      expect(decision.source, LegacyComplexitySources.defaultSimple);
    });

    test('有分层提示 → 复杂（hints_ladder）', () {
      final decision = inferLegacyComplexity(
        question: _question(difficulty: 2),
        board: _board(hintLevels: 1),
      );
      expect(decision.complexity, QuestionComplexity.complex);
      expect(decision.source, LegacyComplexitySources.hintsLadder);
    });

    test('有第二解法 → 复杂（second_method）；只有 shortcut 不算', () {
      final second = inferLegacyComplexity(
        question: _question(difficulty: 2),
        board: _board(
          alternatePaths: <Map<String, Object?>>[_secondMethod()],
        ),
      );
      expect(second.complexity, QuestionComplexity.complex);
      expect(second.source, LegacyComplexitySources.secondMethod);

      final shortcut = inferLegacyComplexity(
        question: _question(difficulty: 2),
        board: _board(
          alternatePaths: <Map<String, Object?>>[_shortcutPath()],
        ),
      );
      expect(shortcut.complexity, QuestionComplexity.simple);
      expect(shortcut.source, LegacyComplexitySources.defaultSimple);
    });

    test('difficulty 阈值 4（1–10 刻度）→ 复杂；3 不触发', () {
      expect(
        inferLegacyComplexity(
          question: _question(difficulty: 4),
          board: _board(),
        ).source,
        LegacyComplexitySources.difficultyThreshold,
      );
      expect(
        inferLegacyComplexity(
          question: _question(difficulty: 10),
          board: _board(),
        ).complexity,
        QuestionComplexity.complex,
      );
      expect(
        inferLegacyComplexity(
          question: _question(difficulty: 3),
          board: _board(),
        ).complexity,
        QuestionComplexity.simple,
      );
    });

    test('没有 meta/difficulty 时按简单处理', () {
      final question = _question(difficulty: null);
      final decision = inferLegacyComplexity(
        question: question,
        board: _board(),
      );
      expect(decision.complexity, QuestionComplexity.simple);
      expect(decision.source, LegacyComplexitySources.defaultSimple);
    });
  });

  group('旧 9 板块 → L0–L5 全映射', () {
    test('复杂题全内容：14 条板块按层级/order 输出，L4 学科史缺来源', () {
      final selection = _mapFull();
      expect(
        _ids(selection),
        <String>[
          'l0_question_entity',
          'l1_thinking_dag',
          'l1_solution_walkthrough',
          'l1_multi_solution',
          'l2_key_eye',
          'l2_traps',
          'l2_error_causes',
          'l2_stuck_points',
          'l2_layered_hints',
          'l3_extra_tasks',
          'l3_variants',
          'l3_similar_questions',
          'l4_extension_material',
          'l5_meta',
        ],
      );
      expect(selection.complexity, QuestionComplexity.complex);
      expect(selection.complexitySource, LegacyComplexitySources.hintsLadder);
      expect(selection.questionType, BoardQuestionType.calculation);
      expect(
        selection.questionTypeSource,
        LegacyQuestionTypeSources.contentTypeAxes,
      );
      for (final board in selection.boards) {
        expect(board.order, greaterThan(0), reason: board.boardId);
        expect(board.itemCount, greaterThan(0), reason: board.boardId);
        expect(board.sourceRefs, isNotEmpty, reason: board.boardId);
      }
      expect(
        selection.emptyBoards.single.boardId,
        'l4_subject_history',
      );
      expect(
        selection.emptyBoards.single.reason,
        'no_legacy_source',
      );
      expect(_ids(selection).contains('l4_subject_history'), isFalse);
    });

    test('旧板块处理状态：映射/吸收/未映射全部记录', () {
      final selection = _mapFull();
      expect(_panel(selection, LegacyBoardPanels.thinkingDag).status,
          LegacyPanelStatus.mapped);
      expect(_panel(selection, LegacyBoardPanels.keyEye).status,
          LegacyPanelStatus.mapped);
      expect(_panel(selection, LegacyBoardPanels.traps).status,
          LegacyPanelStatus.mapped);
      expect(_panel(selection, LegacyBoardPanels.hints).status,
          LegacyPanelStatus.mapped);
      expect(_panel(selection, LegacyBoardPanels.errorCauses).status,
          LegacyPanelStatus.mapped);
      expect(_panel(selection, LegacyBoardPanels.variants).status,
          LegacyPanelStatus.mapped);
      expect(_panel(selection, LegacyBoardPanels.extensions).status,
          LegacyPanelStatus.mapped);
      expect(_panel(selection, LegacyBoardPanels.extraTasks).status,
          LegacyPanelStatus.mapped);
      expect(_panel(selection, LegacyBoardPanels.fiveDimension).status,
          LegacyPanelStatus.absorbed);
      expect(
        _panel(selection, LegacyBoardPanels.fiveDimension).targetBoardIds,
        <String>['l5_meta'],
      );
      expect(_panel(selection, LegacyBoardPanels.meta).status,
          LegacyPanelStatus.absorbed);
      expect(_panel(selection, LegacyBoardPanels.subjectSpecific).status,
          LegacyPanelStatus.unmapped);
    });

    test('每个新板块都记了旧板块来源；L0/L5 引用的文件与 pointer 正确', () {
      final selection = _mapFull();
      expect(selection.boardById('l0_question_entity')!.legacyPanel,
          LegacyBoardPanels.questionEntity);
      expect(selection.boardById('l2_key_eye')!.legacyPanel,
          LegacyBoardPanels.keyEye);
      expect(selection.boardById('l3_similar_questions')!.legacyPanel,
          LegacyBoardPanels.variants);
      expect(selection.boardById('l4_extension_material')!.legacyPanel,
          LegacyBoardPanels.extensions);
      expect(selection.boardById('l5_meta')!.legacyPanel,
          LegacyBoardPanels.fiveDimension);

      final l0Refs = selection.boardById('l0_question_entity')!.sourceRefs;
      expect(
        l0Refs,
        containsAll(<String>[
          'question.json#/stem',
          'question.json#/answer/parts',
          'question.json#/solutions',
          'question.json#/figures',
          'question.json#/scoring',
        ]),
      );
      final l5Refs = selection.boardById('l5_meta')!.sourceRefs;
      expect(
        l5Refs,
        containsAll(<String>[
          'boards/physics-board.json#/five_dimension',
          'question.json#/classification/content_type/axes',
          'question.json#/meta',
        ]),
      );
      expect(selection.boardById('l2_key_eye')!.sourceRefs,
          <String>['boards/physics-board.json#/key_eye/items']);
    });
  });

  group('L2 诊断合并', () {
    test('复杂题五条诊断同属 L2，顺序 题眼→陷阱→错因→卡点→提示', () {
      final selection = _mapFull();
      expect(
        _idsAt(selection, BoardLevel.l2),
        <String>[
          'l2_key_eye',
          'l2_traps',
          'l2_error_causes',
          'l2_stuck_points',
          'l2_layered_hints',
        ],
      );
      expect(
        selection.boardsAt(BoardLevel.l2).every(
              (board) => board.level == BoardLevel.l2,
            ),
        isTrue,
      );
    });

    test('简单题只保留三条常驻诊断，卡点/提示同属 L2 但不选', () {
      final selection = const LegacyBoardMapper().map(
        question: _question(task: 'compute'),
        board: _board(),
      );
      expect(selection.complexity, QuestionComplexity.simple);
      expect(
        _idsAt(selection, BoardLevel.l2),
        <String>['l2_key_eye', 'l2_traps', 'l2_error_causes'],
      );
    });
  });

  group('L3 训练顺序', () {
    test('额外任务 → 变式 → 同源题，顺序固定', () {
      final selection = _mapFull();
      final ids = _ids(selection);
      expect(
        _idsAt(selection, BoardLevel.l3),
        <String>['l3_extra_tasks', 'l3_variants', 'l3_similar_questions'],
      );
      expect(
          ids.indexOf('l3_extra_tasks'), lessThan(ids.indexOf('l3_variants')));
      expect(ids.indexOf('l3_variants'),
          lessThan(ids.indexOf('l3_similar_questions')));
    });

    test('同源题候选为空 → 不选，记 no_candidates；变式仍映射', () {
      final selection = const LegacyBoardMapper().map(
        question: _question(task: 'compute'),
        board: _board()..remove('extra_tasks'),
      );
      expect(
        _idsAt(selection, BoardLevel.l3),
        <String>['l3_variants'],
      );
      expect(
        selection.emptyBoards.any(
          (gap) =>
              gap.boardId == 'l3_similar_questions' &&
              gap.reason == 'no_candidates',
        ),
        isTrue,
      );
      expect(_panel(selection, LegacyBoardPanels.variants).status,
          LegacyPanelStatus.mapped);
    });

    test('没有训练内容 → L3 整段不出现（无占位）', () {
      final selection = const LegacyBoardMapper().map(
        question: _question(task: 'compute'),
        board: _board(variants: 0, extraTasks: 0),
      );
      expect(_idsAt(selection, BoardLevel.l3), isEmpty);
      expect(_panel(selection, LegacyBoardPanels.variants).status,
          LegacyPanelStatus.empty);
      expect(_panel(selection, LegacyBoardPanels.extraTasks).status,
          LegacyPanelStatus.empty);
    });
  });

  group('简单题不配 DAG / 过程解析，复杂题才配', () {
    test('简单题：无 L1、无卡点/提示，L3/L4 仍按内容给', () {
      final selection = const LegacyBoardMapper().map(
        question: _question(task: 'compute'),
        board: _board(
          alternatePaths: <Map<String, Object?>>[_shortcutPath()],
        ),
      );
      expect(selection.complexity, QuestionComplexity.simple);
      expect(_idsAt(selection, BoardLevel.l1), isEmpty);
      expect(_ids(selection), isNot(contains('l2_stuck_points')));
      expect(_ids(selection), isNot(contains('l2_layered_hints')));
      expect(
        _idsAt(selection, BoardLevel.l3),
        <String>['l3_extra_tasks', 'l3_variants'],
      );
      expect(
        _idsAt(selection, BoardLevel.l4),
        <String>['l4_extension_material'],
      );
      expect(_panel(selection, LegacyBoardPanels.thinkingDag).status,
          LegacyPanelStatus.notSelected);
      expect(_panel(selection, LegacyBoardPanels.hints).status,
          LegacyPanelStatus.empty);
    });

    test('复杂题（提示触发）：DAG + 过程解析 + 卡点 + 分层提示都出现', () {
      final selection = _mapFull();
      expect(
        _idsAt(selection, BoardLevel.l1),
        <String>[
          'l1_thinking_dag',
          'l1_solution_walkthrough',
          'l1_multi_solution',
        ],
      );
      expect(_ids(selection), contains('l2_stuck_points'));
      expect(_ids(selection), contains('l2_layered_hints'));
      final walkthrough = selection.boardById('l1_solution_walkthrough')!;
      expect(
        walkthrough.sourceRefs,
        <String>['boards/physics-board.json#/thinking_dag/success_path'],
      );
    });

    test('复杂题（第二解法触发）：DAG 与多解都出现', () {
      final selection = const LegacyBoardMapper().map(
        question: _question(task: 'compute'),
        board: _board(
          alternatePaths: <Map<String, Object?>>[_secondMethod()],
        ),
      );
      expect(selection.complexity, QuestionComplexity.complex);
      expect(selection.complexitySource, LegacyComplexitySources.secondMethod);
      expect(_ids(selection), contains('l1_thinking_dag'));
      expect(_ids(selection), contains('l1_multi_solution'));
    });

    test('显式 complexity 覆盖推导结果（simple 压掉 DAG）', () {
      final selection = _mapFull(complexity: QuestionComplexity.simple);
      expect(selection.complexity, QuestionComplexity.simple);
      expect(selection.complexitySource, LegacyComplexitySources.override);
      expect(_idsAt(selection, BoardLevel.l1), <String>['l1_multi_solution']);
      expect(_ids(selection), isNot(contains('l1_thinking_dag')));
      expect(_ids(selection), isNot(contains('l2_stuck_points')));
      expect(_ids(selection), isNot(contains('l2_layered_hints')));
    });

    test('显式 complexity 覆盖推导结果（complex 加上 DAG）', () {
      final selection = const LegacyBoardMapper().map(
        question: _question(task: 'compute'),
        board: _board(),
        complexity: QuestionComplexity.complex,
      );
      expect(selection.complexitySource, LegacyComplexitySources.override);
      expect(_ids(selection), contains('l1_thinking_dag'));
      expect(_ids(selection), contains('l1_solution_walkthrough'));
    });
  });

  group('一题多解：只认 second_method', () {
    test('shortcut_path 不算多解', () {
      final selection = const LegacyBoardMapper().map(
        question: _question(task: 'compute'),
        board: _board(
          alternatePaths: <Map<String, Object?>>[_shortcutPath()],
        ),
        complexity: QuestionComplexity.complex,
      );
      expect(_ids(selection), contains('l1_thinking_dag'));
      expect(_ids(selection), isNot(contains('l1_multi_solution')));
      expect(_panel(selection, LegacyBoardPanels.thinkingDag).status,
          LegacyPanelStatus.mapped);
    });

    test('阅读题即使有 second_method 也不配一题多解（题型限制）', () {
      final selection = const LegacyBoardMapper().map(
        question: _question(
          task: 'evaluate',
          carrier: 'poetry',
          subject: 'chinese',
        ),
        board: _board(
          alternatePaths: <Map<String, Object?>>[_secondMethod()],
        ),
      );
      expect(selection.questionType, BoardQuestionType.reading);
      expect(selection.complexity, QuestionComplexity.complex);
      expect(_ids(selection), contains('l1_thinking_dag'));
      expect(_ids(selection), isNot(contains('l1_multi_solution')));
    });
  });

  group('空板块不返回占位', () {
    test('所有旧板块为空：只剩 L0 + L5，空板块进 empty_boards', () {
      final selection = const LegacyBoardMapper().map(
        question: _question(task: 'compute'),
        board: _board(
          dag: false,
          keyEye: 0,
          traps: 0,
          errorCauses: 0,
          hintLevels: 0,
          variants: 0,
          extensions: 0,
          extraTasks: 0,
          fiveDimensionKeyNames: const <String>[],
        ),
      );
      expect(
        _ids(selection),
        <String>['l0_question_entity', 'l5_meta'],
      );
      expect(
        selection.emptyBoards.map((gap) => gap.boardId).toSet(),
        <String>{'l2_key_eye', 'l2_traps', 'l2_error_causes'},
      );
      for (final gap in selection.emptyBoards) {
        expect(gap.reason, 'empty_legacy_panel', reason: gap.boardId);
        expect(gap.note, contains('不返回占位'));
      }
      for (final panel in <String>[
        LegacyBoardPanels.thinkingDag,
        LegacyBoardPanels.keyEye,
        LegacyBoardPanels.traps,
        LegacyBoardPanels.hints,
        LegacyBoardPanels.errorCauses,
        LegacyBoardPanels.variants,
        LegacyBoardPanels.extensions,
        LegacyBoardPanels.extraTasks,
        LegacyBoardPanels.fiveDimension,
      ]) {
        expect(_panel(selection, panel).status, LegacyPanelStatus.empty,
            reason: panel);
      }
      expect(_panel(selection, LegacyBoardPanels.meta).status,
          LegacyPanelStatus.absorbed);
    });

    test('board 是空 Map 也能映射（只报空板块，不抛）', () {
      final selection = const LegacyBoardMapper().map(
        question: _question(task: 'compute'),
        board: const <String, Object?>{},
      );
      expect(
        _ids(selection),
        <String>['l0_question_entity', 'l5_meta'],
      );
      expect(selection.emptyBoards, isNotEmpty);
      expect(_panel(selection, LegacyBoardPanels.meta).status,
          LegacyPanelStatus.empty);
      expect(_panel(selection, LegacyBoardPanels.subjectSpecific).status,
          LegacyPanelStatus.empty);
    });
  });

  group('未知板块不猜映射', () {
    test('不认识的顶层键记为 unknown，不进 boards', () {
      final selection = const LegacyBoardMapper().map(
        question: _question(task: 'compute'),
        board: _board(
          extraTopLevel: <String, Object?>{
            'mystery_board': <String, Object?>{
              'items': <Object?>[_item('M-0')],
            },
          },
        ),
      );
      final unknown = _panel(selection, 'mystery_board');
      expect(unknown.status, LegacyPanelStatus.unknown);
      expect(unknown.note, contains('未猜测映射'));
      expect(_ids(selection).any((id) => id.contains('mystery')), isFalse);
    });
  });

  group('meta.omitted_boards 剪枝', () {
    test('被剪掉的旧板块不返回，也不造占位', () {
      final selection = const LegacyBoardMapper().map(
        question: _question(task: 'compute'),
        board: _board(
          omittedBoards: <Map<String, Object?>>[
            <String, Object?>{
              'board': 'traps',
              'reason': '测试剪掉',
            },
          ],
        ),
      );
      expect(_ids(selection), isNot(contains('l2_traps')));
      final traps = _panel(selection, LegacyBoardPanels.traps);
      expect(traps.status, LegacyPanelStatus.omitted);
      expect(traps.note, contains('测试剪掉'));
    });

    test('剪掉 thinking_dag 时 L1 三个板块一起不出现', () {
      final selection = const LegacyBoardMapper().map(
        question: _question(task: 'compute'),
        board: _board(
          hintLevels: 1,
          omittedBoards: <Map<String, Object?>>[
            <String, Object?>{'board': 'thinking_dag', 'reason': 'test'},
          ],
        ),
      );
      expect(_idsAt(selection, BoardLevel.l1), isEmpty);
      expect(_ids(selection), isNot(contains('l2_stuck_points')));
      expect(_panel(selection, LegacyBoardPanels.thinkingDag).status,
          LegacyPanelStatus.omitted);
    });

    test('剪掉 five_dimension 时 L5 仍在（L5 不是五维板块）', () {
      final selection = const LegacyBoardMapper().map(
        question: _question(task: 'compute'),
        board: _board(
          omittedBoards: <Map<String, Object?>>[
            <String, Object?>{'board': 'five_dimension', 'reason': 'test'},
          ],
        ),
      );
      expect(_ids(selection), contains('l5_meta'));
      expect(_panel(selection, LegacyBoardPanels.fiveDimension).status,
          LegacyPanelStatus.omitted);
      expect(selection.meta['five_dimension_keys'], isEmpty);
    });
  });

  group('五维不固定、转 L5 元信息', () {
    test('五维键数量随内容包变化，不硬编码五个', () {
      final selection = _mapFull();
      expect(
        selection.meta['five_dimension_keys'],
        <String>[
          'question_type',
          'exam_method',
          'setter_intent',
          'solution_path',
          'ability_training',
        ],
      );

      final three = const LegacyBoardMapper().map(
        question: _question(task: 'compute'),
        board: _board(
          fiveDimensionKeyNames: <String>[
            'question_type',
            'solution_path',
            'ability_training'
          ],
        ),
      );
      expect(
        three.meta['five_dimension_keys'],
        <String>['question_type', 'solution_path', 'ability_training'],
      );
      for (final selection in <BoardSelection>[_mapFull(), three]) {
        expect(
          _ids(selection).any((id) => id.contains('five')),
          isFalse,
          reason: '不能把五维加回成板块',
        );
      }
    });

    test('L5 元信息含四轴/能力码/难度/来源/板版本', () {
      final selection = _mapFull();
      final meta = selection.meta;
      expect(meta['content_type_code'], 'TEST-CODE');
      expect(meta['content_type_label'], '测试题型');
      expect(
        meta['content_type_axes'],
        <String, Object?>{
          'carrier': 'mechanics',
          'task': 'compute',
          'thinking': <String>['forward'],
          'scope': 'single_point',
        },
      );
      expect(meta['capability_codes'], <String>['A1']);
      expect(
        meta['difficulty'],
        <String, Object?>{
          'value': 2.0,
          'source': 'ai',
          'confidence': 0.35,
        },
      );
      expect(
        meta['source'],
        <String, Object?>{
          'level': 'gaokao',
          'label': '测试来源',
          'year': 2025,
          'region': '全国一卷',
        },
      );
      expect(meta['board_version'], 2);
      expect(selection.boards.last.boardId, 'l5_meta');
    });

    test('五维缺失时 L5 仍在，仍由四轴/meta 供给引用', () {
      final selection = const LegacyBoardMapper().map(
        question: _question(task: 'compute'),
        board: _board(fiveDimensionKeyNames: const <String>[]),
      );
      expect(selection.boardById('l5_meta'), isNotNull);
      expect(selection.meta['five_dimension_keys'], isEmpty);
      expect(_panel(selection, LegacyBoardPanels.fiveDimension).status,
          LegacyPanelStatus.empty);
    });
  });

  group('JSON 输出', () {
    test('toJson 键与值稳定；boards 带 id/level/order', () {
      final selection = _mapFull();
      final json = selection.toJson();
      expect(
        json.keys.toSet(),
        <String>{
          'schema_version',
          'question_id',
          'subject',
          'complexity',
          'complexity_source',
          'question_type',
          'question_type_source',
          'boards',
          'empty_boards',
          'panels',
          'meta',
        },
      );
      expect(json['schema_version'], kBoardSelectionSchemaVersion);
      expect(json['question_id'], 'Q-T0001');
      expect(json['subject'], 'physics');
      expect(json['complexity'], 'complex');
      final boards =
          (json['boards']! as List<Object?>).cast<Map<String, Object?>>();
      expect(boards.first['board_id'], 'l0_question_entity');
      expect(boards.first['level'], 'L0');
      expect(boards.first['order'], 10);
      expect(boards.last['board_id'], 'l5_meta');
      expect(boards.last['level'], 'L5');
      expect(boards.last['order'], 60);
      expect(
        boards.first.keys.toSet(),
        <String>{
          'board_id',
          'level',
          'order',
          'legacy_panel',
          'source_refs',
          'item_count',
        },
      );
    });

    test('toJsonString 可再 jsonDecode，且与 toJson 相等', () {
      final selection = _mapFull();
      expect(
        jsonDecode(selection.toJsonString()),
        selection.toJson(),
      );
    });

    test('输出不含正文：所有 source 正文标记都不出现', () {
      final selection = _mapFull();
      final json = selection.toJsonString();
      expect(json.contains(_bodyMarker), isFalse);
      expect(
          selection.toJson()['meta'].toString().contains(_bodyMarker), isFalse);
    });

    test('questionPath / boardPath 可指定，引用随之变化', () {
      final selection = const LegacyBoardMapper().map(
        question: _question(task: 'compute'),
        board: _fullBoard(),
        questionPath: 'pkg/question.json',
        boardPath: 'pkg/boards/physics-board.json',
      );
      expect(
        selection.boardById('l2_key_eye')!.sourceRefs,
        <String>['pkg/boards/physics-board.json#/key_eye/items'],
      );
      expect(
        selection.boardById('l0_question_entity')!.sourceRefs.first,
        'pkg/question.json#/stem',
      );
    });

    test('返回的列表/Map 不可修改', () {
      final selection = _mapFull();
      expect(
        () => selection.boards.add(selection.boards.first),
        throwsUnsupportedError,
      );
      expect(
        () => selection.boards.first.sourceRefs.add('x'),
        throwsUnsupportedError,
      );
      expect(
        () => selection.meta['x'] = 1,
        throwsUnsupportedError,
      );
    });
  });

  group('严格性', () {
    test('question.id / subject 缺失或空白抛 FormatException', () {
      expect(
        () => const LegacyBoardMapper().map(question: _question(id: '')),
        throwsFormatException,
      );
      expect(
        () => const LegacyBoardMapper().map(
          question: _question()..remove('id'),
        ),
        throwsFormatException,
      );
      expect(
        () => const LegacyBoardMapper().map(question: _question(subject: '  ')),
        throwsFormatException,
      );
    });

    test('board.question_id 与 question.id 不一致抛 FormatException', () {
      expect(
        () => const LegacyBoardMapper().map(
          question: _question(id: 'Q-T0001'),
          board: _board(questionId: 'Q-OTHER'),
        ),
        throwsFormatException,
      );
    });

    test('board 没有 question_id 字段时不抛', () {
      final board = _board();
      board.remove('question_id');
      final selection = const LegacyBoardMapper().map(
        question: _question(),
        board: board,
      );
      expect(selection.questionId, 'Q-T0001');
    });
  });
}
