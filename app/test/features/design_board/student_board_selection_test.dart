// task-96：学生页按板块库选板结果（L0–L5）渲染的接线测试。
//
// 钉五件事：
// 1) asset 里的 `boardSelection` 等于真实 `LegacyBoardMapper` 对三份内容包的
//    输出（规则只有一份，不是 Python 复刻/单题硬编码）；
// 2) 简单题（物理）选板不含 L1 DAG/过程解析/卡点/分层提示；复杂题（数学/语文）有；
// 3) L2 诊断合并成一块、L3 顺序固定、L4 拆扩展资料/学科史、L5 不进正文；
// 4) 空板块不占位（没有“暂无”卡片）；
// 5) 旧 asset（没有 boardSelection）回落到旧布局，不让页面消失。
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/content/legacy_board_mapper.dart';
import 'package:furnace/features/design_board/domain/design_board.dart';
import 'package:furnace/features/design_board/presentation/content_sample_page.dart';

const String _contentStore = r'E:\Workspaces\agent-control'
    r'\10-projects\agent-control-plane\content-store';

const Map<String, List<String>> _packages = <String, List<String>>{
  'Q-PH0001': <String>[
    'physics\\Q-PH0001\\question.json',
    'physics\\Q-PH0001\\boards\\physics-board.json',
  ],
  'Q-MA0001': <String>[
    'math\\Q-MA0001\\question.json',
    'math\\Q-MA0001\\boards\\math-board.json',
  ],
  'Q-CH0001': <String>[
    'chinese\\Q-CH0001\\question.json',
    'chinese\\Q-CH0001\\boards\\chinese-board.json',
  ],
};

String? _missingPackage() {
  final missing = <String>[
    for (final entry in _packages.entries)
      if (entry.value.any(
        (relative) => !File('$_contentStore\\$relative').existsSync(),
      ))
        entry.key,
  ];
  return missing.isEmpty ? null : missing.join(',');
}

/// `LegacyBoardMapper` 选板结果 → asset 里 compact boardSelection 的形状。
Map<String, Object?> _expectedCompact(BoardSelection selection) =>
    <String, Object?>{
      'schema_version': selection.toJson()['schema_version'],
      'question_id': selection.questionId,
      'subject': selection.subject,
      'complexity': selection.complexity.code,
      'complexity_source': selection.complexitySource,
      'question_type': selection.questionType,
      'question_type_source': selection.questionTypeSource,
      'boards': <Map<String, Object?>>[
        for (final board in selection.boards)
          <String, Object?>{
            'board_id': board.boardId,
            'level': board.level.code,
            'order': board.order,
            'legacy_panel': board.legacyPanel,
            'item_count': board.itemCount,
          },
      ],
      'empty_boards': <Map<String, Object?>>[
        for (final gap in selection.emptyBoards)
          <String, Object?>{
            'board_id': gap.boardId,
            'level': gap.level.code,
            'reason': gap.reason,
          },
      ],
    };

StudentBoardEntry _entry(String id, String level, int order) =>
    StudentBoardEntry(
      boardId: id,
      level: level,
      order: order,
      legacyPanel: '',
      sourceRefs: const <String>[],
      itemCount: 1,
    );

StudentPanel _panel(
  String boardId,
  String level,
  int order,
  String title,
  List<String> items,
) =>
    StudentPanel(
      boardId: boardId,
      level: level,
      order: order,
      title: title,
      items: items,
    );

StudentAiAnswer _aiAnswer() => const StudentAiAnswer(
      answer: 'A',
      reasoning: '只受重力。',
      debate: '',
      note: '',
    );

StudentContent _studentContent(List<StudentPanel> panels) => StudentContent(
      stem: '一道合成测试题。',
      answer: 'A',
      solution: '',
      solutionNote: '',
      showSourceAnalysis: false,
      panels: panels,
      aiAnswer: _aiAnswer(),
    );

DesignBoardCard _card({
  required StudentContent content,
  StudentBoardSelection? selection,
  DagGraph? graph,
}) =>
    DesignBoardCard(
      id: 'Q-SYN01',
      title: '合成样例',
      subtitle: '',
      statusLabel: '',
      chips: const <String>[],
      lines: const <String>[],
      studentContent: content,
      boardSelection: selection,
      dagGraph: graph,
    );

Future<void> _pumpPage(WidgetTester tester, DesignBoardCard card) async {
  tester.view.physicalSize = const Size(1200, 5000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(home: ContentSamplePage(sample: card)));
  await tester.pumpAndSettle();
}

void main() {
  late DesignBoardData assetData;

  setUpAll(() async {
    assetData = DesignBoardData.decode(
      await File('assets/design_board.json').readAsString(),
    );
  });

  group('asset boardSelection 与 LegacyBoardMapper 一致（规则只有一份）', () {
    final missing = _missingPackage();
    test('三题 boardSelection 逐字段等于 mapper 输出', () {
      if (missing != null) {
        fail('内容包缺失：$missing');
      }
      final raw = jsonDecode(
        File('assets/design_board.json').readAsStringSync(),
      ) as Map<String, Object?>;
      final samples = (raw['realContentSamples'] as List<Object?>)
          .cast<Map<String, Object?>>();
      for (final entry in _packages.entries) {
        final question = jsonDecode(
          File('$_contentStore\\${entry.value[0]}').readAsStringSync(),
        ) as Map<String, Object?>;
        final board = jsonDecode(
          File('$_contentStore\\${entry.value[1]}').readAsStringSync(),
        ) as Map<String, Object?>;
        final selection = const LegacyBoardMapper().map(
          question: question,
          board: board,
        );
        final sample = samples.firstWhere(
          (item) => item['id'] == entry.key,
          orElse: () => throw StateError('asset 缺 ${entry.key}'),
        );
        expect(
          sample['boardSelection'],
          _expectedCompact(selection),
          reason:
              '${entry.key}: asset 的 boardSelection 不是 LegacyBoardMapper 的输出',
        );
      }
    });
  });

  group('学生页按选板渲染（真实三题）', () {
    DesignBoardCard sampleOf(String id) =>
        assetData.realContentSamples.firstWhere((sample) => sample.id == id);

    testWidgets('物理 simple：没有 DAG/过程解析/卡点/分层提示；L2 合一块', (tester) async {
      await _pumpPage(tester, sampleOf('Q-PH0001'));

      expect(find.text('Thinking DAG'), findsNothing);
      expect(find.byKey(const Key('dag-panel-Q-PH0001')), findsNothing);
      expect(find.textContaining('解析原文（据解析卷'), findsNothing);
      expect(find.byKey(const Key('solution-panel-Q-PH0001')), findsNothing);
      // L2 合并：一块“诊断”里给题眼/陷阱/错因，没有分层提示/卡点。
      expect(
        find.byKey(const Key('diagnostic-section-Q-PH0001')),
        findsOneWidget,
      );
      expect(find.text('题眼'), findsOneWidget);
      expect(find.text('陷阱/易错点'), findsOneWidget);
      expect(find.text('错因'), findsOneWidget);
      expect(find.text('分层提示'), findsNothing);
      expect(find.text('卡点'), findsNothing);
      // 空板块不占位。
      expect(find.text('同源题'), findsNothing);
      expect(find.text('学科史'), findsNothing);
      expect(find.textContaining('暂无'), findsNothing);
      // L5 元信息不进学生正文。
      expect(find.text('五维正向推导'), findsNothing);
    });

    testWidgets('数学/语文 complex：有 DAG；语文有解析原文与分层提示', (tester) async {
      await _pumpPage(tester, sampleOf('Q-MA0001'));

      expect(find.text('Thinking DAG'), findsOneWidget);
      expect(find.byKey(const Key('dag-panel-Q-MA0001')), findsOneWidget);
      // 数学 hints 空：诊断块里没有分层提示。
      expect(find.text('分层提示'), findsNothing);
      expect(find.text('卡点'), findsNothing);
      // 数学没有解析原文（非《高考试题分析》来源）。
      expect(find.byKey(const Key('solution-panel-Q-MA0001')), findsNothing);

      await _pumpPage(tester, sampleOf('Q-CH0001'));
      expect(find.text('Thinking DAG'), findsOneWidget);
      expect(find.text('分层提示'), findsOneWidget);
      expect(
        find.byKey(const Key('solution-panel-Q-CH0001')),
        findsOneWidget,
      );
    });
  });

  group('学生页按选板渲染（合成样例）', () {
    testWidgets('L4 拆扩展资料/学科史；被选但没内容的板块不占位', (tester) async {
      final card = _card(
        selection: StudentBoardSelection(
          schemaVersion: 'furnace.board-selection/1',
          questionId: 'Q-SYN01',
          subject: 'physics',
          complexity: 'complex',
          complexitySource: 'hints_ladder',
          questionType: 'concept',
          questionTypeSource: 'content_type_axes',
          boards: <StudentBoardEntry>[
            // l2_key_eye 被选中但内容为空 → 不应出现“诊断”块或“暂无”。
            _entry('l2_key_eye', 'L2', 30),
            _entry('l4_extension_material', 'L4', 50),
            _entry('l4_subject_history', 'L4', 51),
          ],
          emptyBoards: const <StudentBoardGap>[],
        ),
        content: _studentContent(<StudentPanel>[
          _panel('l4_extension_material', 'L4', 50, '扩展资料', <String>['扩展条目']),
          _panel('l4_subject_history', 'L4', 51, '学科史', <String>['学科史条目']),
        ]),
      );
      await _pumpPage(tester, card);

      expect(find.byKey(const Key('diagnostic-section-Q-SYN01')), findsNothing);
      expect(
          find.byKey(const Key('extension-section-Q-SYN01')), findsOneWidget);
      expect(
        find.byKey(const Key('subject-history-section-Q-SYN01')),
        findsOneWidget,
      );
      expect(find.text('扩展资料'), findsOneWidget);
      expect(find.text('学科史'), findsOneWidget);
      expect(find.textContaining('扩展条目'), findsOneWidget);
      expect(find.textContaining('学科史条目'), findsOneWidget);
      expect(find.textContaining('暂无'), findsNothing);
      // 没有选 l1 → 没有 DAG。
      expect(find.text('Thinking DAG'), findsNothing);
    });

    testWidgets('旧 asset（无 boardSelection）回落旧布局：DAG/分层提示/九板块', (tester) async {
      final card = _card(
        content: _studentContent(<StudentPanel>[
          _panel('', '', 0, '分层提示', <String>['第1级：提示']),
          _panel('', '', 0, '题眼', <String>['题眼条目']),
          _panel('', '', 0, '五维正向推导', <String>['五维条目']),
        ]),
        graph: const DagGraph(
          sourceMode: 'expert_authored',
          nodes: <DagNode>[
            DagNode(
              id: 'N1',
              kind: 'condition',
              role: '',
              label: '审题',
              body: '',
              stepType: '',
              formulas: <String>[],
              keyQuantities: <String>[],
              result: '',
            ),
          ],
          edges: <DagEdge>[],
          alternatePaths: <DagAlternatePath>[],
          successPath: <String>[],
          failedBranches: 0,
          failureBranches: <DagFailureBranch>[],
          note: '',
        ),
      );
      await _pumpPage(tester, card);

      // 旧布局保留：DAG 入口、分层提示卡、九板块块。
      expect(find.text('Thinking DAG'), findsOneWidget);
      expect(find.byKey(const Key('dag-panel-Q-SYN01')), findsOneWidget);
      expect(find.text('分层提示'), findsOneWidget);
      expect(find.text('九板块内容'), findsOneWidget);
      expect(find.text('题眼'), findsOneWidget);
      expect(find.text('五维正向推导'), findsOneWidget);
      // 旧布局没有新的分层块。
      expect(find.byKey(const Key('diagnostic-section-Q-SYN01')), findsNothing);
    });
  });
}
