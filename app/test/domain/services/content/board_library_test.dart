import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/content/board_library.dart';

/// 默认按「复杂题 + 计算题 + 没有额外事实」选板（简写）。
List<BoardDefinition> _select({
  String questionType = BoardQuestionType.calculation,
  QuestionComplexity complexity = QuestionComplexity.complex,
  bool hasMultipleSolutions = false,
  bool hasUpperKnowledge = false,
  bool hasTraining = false,
}) {
  return selectBoards(
    questionType: questionType,
    complexity: complexity,
    hasMultipleSolutions: hasMultipleSolutions,
    hasUpperKnowledge: hasUpperKnowledge,
    hasTraining: hasTraining,
  );
}

List<String> _ids(Iterable<BoardDefinition> boards) =>
    <String>[for (final board in boards) board.id];

List<String> _idsAt(List<BoardDefinition> boards, BoardLevel level) =>
    _ids(boards.where((board) => board.level == level));

void main() {
  group('BoardLevel 层级', () {
    test('L0–L5 六个层级，顺序与编码固定', () {
      expect(BoardLevel.values, hasLength(6));
      expect(
        <String>[for (final level in BoardLevel.values) level.code],
        <String>['L0', 'L1', 'L2', 'L3', 'L4', 'L5'],
      );
      expect(
        <String>[for (final level in BoardLevel.values) level.label],
        <String>['题目本体', '过程结构', '诊断（合并）', '训练（由近及远）', '背景', '元信息'],
      );
    });

    test('tryFromCode 大小写/空白容错，认不出返回 null', () {
      for (final level in BoardLevel.values) {
        expect(BoardLevel.tryFromCode(level.code), level);
        expect(BoardLevel.tryFromCode(' ${level.code.toLowerCase()} '), level);
      }
      for (final code in const <String?>['L6', 'L', '', '  ', null]) {
        expect(BoardLevel.tryFromCode(code), isNull, reason: '$code');
      }
    });

    test('每一层在目录里都至少有一个条目', () {
      for (final level in BoardLevel.values) {
        expect(boardsForLevel(level), isNotEmpty, reason: level.code);
      }
    });
  });

  group('QuestionComplexity / BoardTrigger 编码', () {
    test('复杂度编码 simple/complex，认不出返回 null', () {
      expect(QuestionComplexity.simple.code, 'simple');
      expect(QuestionComplexity.complex.code, 'complex');
      expect(QuestionComplexity.tryFromCode(' COMPLEX '),
          QuestionComplexity.complex);
      expect(QuestionComplexity.tryFromCode('medium'), isNull);
    });

    test('触发条件编码稳定，认不出返回 null', () {
      expect(
        <String>[for (final trigger in BoardTrigger.values) trigger.code],
        <String>[
          'always',
          'complex_only',
          'multiple_solutions',
          'upper_knowledge',
          'training',
        ],
      );
      for (final trigger in BoardTrigger.values) {
        expect(BoardTrigger.tryFromCode(trigger.code), trigger);
      }
      expect(BoardTrigger.tryFromCode('sometimes'), isNull);
    });
  });

  group('catalog 板块目录', () {
    test('id 唯一且非空，目录按（层级, order）升序', () {
      final ids = _ids(kBoardCatalog);
      expect(ids.toSet(), hasLength(ids.length), reason: 'id 重复');
      expect(ids.any((id) => id.trim().isEmpty), isFalse);
      for (var index = 1; index < kBoardCatalog.length; index++) {
        final previous = kBoardCatalog[index - 1];
        final current = kBoardCatalog[index];
        final previousKey = previous.level.index * 1000 + previous.order;
        final currentKey = current.level.index * 1000 + current.order;
        expect(currentKey, greaterThanOrEqualTo(previousKey),
            reason: '${previous.id} -> ${current.id}');
      }
    });

    test('层级数量与 L0–L5 分布固定（15 条）', () {
      expect(kBoardCatalog, hasLength(15));
      expect(boardsForLevel(BoardLevel.l0), hasLength(1));
      expect(boardsForLevel(BoardLevel.l1), hasLength(3));
      expect(boardsForLevel(BoardLevel.l2), hasLength(5));
      expect(boardsForLevel(BoardLevel.l3), hasLength(3));
      expect(boardsForLevel(BoardLevel.l4), hasLength(2));
      expect(boardsForLevel(BoardLevel.l5), hasLength(1));
      expect(
          _idsAt(kBoardCatalog, BoardLevel.l0), <String>['l0_question_entity']);
    });

    test('L1 三条：DAG / 过程解析 / 一题多解，前者只复杂题', () {
      final l1 = boardsForLevel(BoardLevel.l1);
      expect(
        _ids(l1),
        <String>[
          'l1_thinking_dag',
          'l1_solution_walkthrough',
          'l1_multi_solution',
        ],
      );
      expect(findBoard('l1_thinking_dag')!.trigger, BoardTrigger.complexOnly);
      expect(findBoard('l1_solution_walkthrough')!.trigger,
          BoardTrigger.complexOnly);
      expect(findBoard('l1_multi_solution')!.trigger,
          BoardTrigger.multipleSolutions);
    });

    test('L2 合并：五条诊断同一个层级', () {
      final l2 = boardsForLevel(BoardLevel.l2);
      expect(
        _ids(l2),
        <String>[
          'l2_key_eye',
          'l2_traps',
          'l2_error_causes',
          'l2_stuck_points',
          'l2_layered_hints',
        ],
      );
      expect(l2.every((board) => board.level == BoardLevel.l2), isTrue);
    });

    test('L3 由近及远：额外任务 → 变式 → 同源题', () {
      final l3 = boardsForLevel(BoardLevel.l3);
      expect(
        _ids(l3),
        <String>[
          'l3_extra_tasks',
          'l3_variants',
          'l3_similar_questions',
        ],
      );
      expect(
          l3.every((board) => board.trigger == BoardTrigger.training), isTrue);
      final orders = <int>[for (final board in l3) board.order];
      expect(orders, orderedEquals(<int>[...orders]..sort()));
    });

    test('L4 两个子类：扩展资料 / 学科史', () {
      final l4 = boardsForLevel(BoardLevel.l4);
      expect(
        _ids(l4),
        <String>['l4_extension_material', 'l4_subject_history'],
      );
      expect(l4.every((board) => board.trigger == BoardTrigger.upperKnowledge),
          isTrue);
    });

    test('L5 只有元信息一条，且不进学生视图', () {
      final l5 = boardsForLevel(BoardLevel.l5);
      expect(_ids(l5), <String>['l5_meta']);
      expect(l5.single.studentVisible, isFalse);
      expect(l5.single.required, isTrue);
    });

    test('五维不再固定成五字段/板块', () {
      expect(FiveDimensionPolicy.fixedFields, isFalse);
      expect(FiveDimensionPolicy.contentTypeAxes,
          <String>['carrier', 'task', 'thinking', 'scope']);
      expect(FiveDimensionPolicy.note, contains('不固定'));
      // 目录里没有 five_dimension 板块（也没有五维字样）。
      for (final board in kBoardCatalog) {
        expect(board.id.contains('five_dimension'), isFalse, reason: board.id);
        expect(board.id.contains('five'), isFalse, reason: board.id);
        expect(board.name.contains('五维'), isFalse, reason: board.name);
      }
    });

    test('findBoard / boardsForLevel 查不到时返回空/null，不猜', () {
      expect(findBoard('l3_variants')?.name, '变式');
      expect(findBoard('nope'), isNull);
      expect(findBoard('   '), isNull);
      expect(boardsForLevel(BoardLevel.values.last), hasLength(1));
    });
  });

  group('selectBoards 简单题', () {
    test('简单题不配 DAG/过程解析，只留本体+诊断+元信息', () {
      final selection = _select(complexity: QuestionComplexity.simple);
      expect(
        _ids(selection),
        <String>[
          'l0_question_entity',
          'l2_key_eye',
          'l2_traps',
          'l2_error_causes',
          'l5_meta',
        ],
      );
      expect(selection.where((board) => board.level == BoardLevel.l1), isEmpty);
    });

    test('简单题不出现卡点/分层提示（依赖过程结构）', () {
      final ids = _ids(_select(complexity: QuestionComplexity.simple));
      expect(ids, isNot(contains('l2_stuck_points')));
      expect(ids, isNot(contains('l2_layered_hints')));
    });

    test('简单题没有训练/背景事实时 L3/L4 整段不出现（无占位）', () {
      final selection = _select(complexity: QuestionComplexity.simple);
      expect(_idsAt(selection, BoardLevel.l3), isEmpty);
      expect(_idsAt(selection, BoardLevel.l4), isEmpty);
    });

    test('简单题即使有一题多解也只加多解，不加 DAG/过程解析', () {
      final selection = _select(
        complexity: QuestionComplexity.simple,
        hasMultipleSolutions: true,
      );
      final ids = _ids(selection);
      expect(ids, contains('l1_multi_solution'));
      expect(ids, isNot(contains('l1_thinking_dag')));
      expect(ids, isNot(contains('l1_solution_walkthrough')));
    });
  });

  group('selectBoards 复杂题 / DAG', () {
    test('复杂题才配 DAG 与过程解析', () {
      final complex = _ids(_select());
      expect(
        complex,
        containsAll(<String>['l1_thinking_dag', 'l1_solution_walkthrough']),
      );
      final simple = _ids(_select(complexity: QuestionComplexity.simple));
      expect(simple, isNot(contains('l1_thinking_dag')));
      expect(simple, isNot(contains('l1_solution_walkthrough')));
    });

    test('一题多解只在检测到多解时出现', () {
      expect(
        _ids(_select(hasMultipleSolutions: false)),
        isNot(contains('l1_multi_solution')),
      );
      expect(
        _ids(_select(hasMultipleSolutions: true)),
        contains('l1_multi_solution'),
      );
    });

    test('一题多解受题型限制：阅读题不配（不适用不返回）', () {
      final reading = _select(
        questionType: BoardQuestionType.reading,
        hasMultipleSolutions: true,
      );
      expect(_ids(reading), isNot(contains('l1_multi_solution')));
      // 同一次选择里 DAG/过程解析仍按复杂题给出。
      expect(_ids(reading), contains('l1_thinking_dag'));
    });

    test('复杂题全选满时目录 15 条全部出现（多解对计算题适用）', () {
      final selection = _select(
        hasMultipleSolutions: true,
        hasUpperKnowledge: true,
        hasTraining: true,
      );
      expect(_ids(selection), orderedEquals(_ids(kBoardCatalog)));
    });
  });

  group('L2 合并与分组', () {
    test('复杂题五条诊断同组，简单题三条', () {
      final complex = groupBoardsByLevel(_select());
      expect(_idsAt(complex[BoardLevel.l2]!, BoardLevel.l2), hasLength(5));

      final simple = groupBoardsByLevel(
        _select(complexity: QuestionComplexity.simple),
      );
      expect(
        _ids(simple[BoardLevel.l2]!),
        <String>['l2_key_eye', 'l2_traps', 'l2_error_causes'],
      );
    });

    test('分组键按层级顺序出现，不出现空层', () {
      final grouped = groupBoardsByLevel(_select());
      expect(
        grouped.keys.toList(),
        <BoardLevel>[
          BoardLevel.l0,
          BoardLevel.l1,
          BoardLevel.l2,
          BoardLevel.l5,
        ],
      );
      expect(grouped.values.every((boards) => boards.isNotEmpty), isTrue);
    });
  });

  group('L3 训练顺序', () {
    test('额外任务 → 变式 → 同源题，顺序固定', () {
      final selection = _select(hasTraining: true);
      expect(
        _idsAt(selection, BoardLevel.l3),
        <String>[
          'l3_extra_tasks',
          'l3_variants',
          'l3_similar_questions',
        ],
      );
      final ids = _ids(selection);
      expect(
          ids.indexOf('l3_extra_tasks'), lessThan(ids.indexOf('l3_variants')));
      expect(
        ids.indexOf('l3_variants'),
        lessThan(ids.indexOf('l3_similar_questions')),
      );
    });

    test('没有训练事实时不出 L3（不造占位）', () {
      expect(_idsAt(_select(hasTraining: false), BoardLevel.l3), isEmpty);
    });

    test('L3 位于 L2 之后、L4/L5 之前', () {
      final ids = _ids(
        _select(hasTraining: true, hasUpperKnowledge: true),
      );
      final lastL2 = ids.indexOf('l2_layered_hints');
      final firstL3 = ids.indexOf('l3_extra_tasks');
      final lastL3 = ids.indexOf('l3_similar_questions');
      final firstL4 = ids.indexOf('l4_extension_material');
      final l5 = ids.indexOf('l5_meta');
      expect(lastL2, lessThan(firstL3));
      expect(lastL3, lessThan(firstL4));
      expect(firstL4, lessThan(l5));
    });
  });

  group('L4 背景子类', () {
    test('有上位知识时两个子类都给，扩展资料在学科史前', () {
      final selection = _select(hasUpperKnowledge: true);
      expect(
        _idsAt(selection, BoardLevel.l4),
        <String>['l4_extension_material', 'l4_subject_history'],
      );
    });

    test('没有上位知识时两个子类都不出现', () {
      expect(_idsAt(_select(hasUpperKnowledge: false), BoardLevel.l4), isEmpty);
    });

    test('学科史说明里写死不记人名年代', () {
      expect(findBoard('l4_subject_history')!.description, contains('不记人名年代'));
    });
  });

  group('L5 元信息', () {
    test('非空题型的选择里元信息总在最后', () {
      for (final complexity in QuestionComplexity.values) {
        final ids = _ids(_select(complexity: complexity));
        expect(ids.last, 'l5_meta', reason: complexity.code);
      }
    });

    test('L5 不参与学生视图', () {
      expect(findBoard('l5_meta')!.studentVisible, isFalse);
    });
  });

  group('空/不适用不返回占位', () {
    test('题型为空/空白直接返回空表', () {
      expect(_select(questionType: ''), isEmpty);
      expect(_select(questionType: '   '), isEmpty);
    });

    test('认不出的题型仍按「对所有题型适用」的条目选，不硬配题型限定板块', () {
      final selection = _select(
        questionType: 'quantum_tea',
        hasMultipleSolutions: true,
      );
      final ids = _ids(selection);
      expect(ids, contains('l0_question_entity'));
      expect(ids, contains('l5_meta'));
      expect(ids, isNot(contains('l1_multi_solution')));
    });

    test('返回的是不可修改列表', () {
      final selection = _select();
      expect(() => selection.add(kBoardCatalog.first), throwsUnsupportedError);
      expect(() => boardsForLevel(BoardLevel.l4).add(kBoardCatalog.first),
          throwsUnsupportedError);
    });
  });

  group('JSON roundtrip', () {
    test('单条定义 toJson → fromJson 还原且相等', () {
      for (final board in kBoardCatalog) {
        final restored = BoardDefinition.fromJson(board.toJson());
        expect(restored, board, reason: board.id);
        expect(restored.hashCode, board.hashCode, reason: board.id);
      }
    });

    test('toJson 使用稳定 snake_case 键', () {
      final json = findBoard('l1_multi_solution')!.toJson();
      expect(
        json.keys.toSet(),
        <String>{
          'id',
          'name',
          'level',
          'description',
          'applicable_question_types',
          'required',
          'student_visible',
          'order',
          'trigger',
        },
      );
      expect(json['level'], 'L1');
      expect(json['trigger'], 'multiple_solutions');
      expect(json['applicable_question_types'],
          <String>['calculation', 'derivation', 'proof']);
    });

    test('目录 JSON 字符串 roundtrip 保持顺序与字段', () {
      final encoded = encodeBoardCatalogJson();
      expect(jsonDecode(encoded), isA<List<dynamic>>());
      final decoded = decodeBoardCatalogJson(encoded);
      expect(decoded, orderedEquals(kBoardCatalog));
    });

    test('Map 列表 roundtrip 同样成立', () {
      final decoded = decodeBoardCatalog(encodeBoardCatalog());
      expect(decoded, orderedEquals(kBoardCatalog));
    });

    test('可选字段缺省：只需要 id/name/level/description/order', () {
      final board = BoardDefinition.fromJson(<String, Object?>{
        'id': 'x',
        'name': 'X',
        'level': 'L2',
        'description': '测试',
        'order': 7,
      });
      expect(board.level, BoardLevel.l2);
      expect(board.applicableQuestionTypes, isEmpty);
      expect(board.required, isFalse);
      expect(board.studentVisible, isTrue);
      expect(board.trigger, BoardTrigger.always);
    });

    test('非法 JSON 一律抛 FormatException，不静默降级', () {
      Map<String, Object?> valid() => <String, Object?>{
            'id': 'x',
            'name': 'X',
            'level': 'L2',
            'description': '测试',
            'order': 7,
          };

      expect(() => BoardDefinition.fromJson(null), throwsFormatException);
      expect(() => BoardDefinition.fromJson(<String, Object?>{}),
          throwsFormatException);
      expect(
        () => BoardDefinition.fromJson(<String, Object?>{...valid(), 'id': ''}),
        throwsFormatException,
      );
      expect(
        () => BoardDefinition.fromJson(
            <String, Object?>{...valid(), 'level': 'L9'}),
        throwsFormatException,
      );
      expect(
        () => BoardDefinition.fromJson(
            <String, Object?>{...valid(), 'trigger': 'sometimes'}),
        throwsFormatException,
      );
      expect(
        () => BoardDefinition.fromJson(
            <String, Object?>{...valid(), 'order': -1}),
        throwsFormatException,
      );
      expect(
        () => BoardDefinition.fromJson(
            <String, Object?>{...valid(), 'order': '7'}),
        throwsFormatException,
      );
      expect(
        () => BoardDefinition.fromJson(<String, Object?>{
          ...valid(),
          'applicable_question_types': 'calculation',
        }),
        throwsFormatException,
      );
      expect(
        () => BoardDefinition.fromJson(
            <String, Object?>{...valid(), 'student_visible': 'yes'}),
        throwsFormatException,
      );
    });

    test('matching by level: 目录 JSON 不认非数组输入', () {
      expect(
          () => decodeBoardCatalog(<String, Object?>{}), throwsFormatException);
      expect(() => decodeBoardCatalog('not a list'), throwsFormatException);
      expect(() => decodeBoardCatalogJson('{'), throwsFormatException);
    });

    test('目录里单项非法时报出索引', () {
      final bad = <Map<String, Object?>>[...encodeBoardCatalog()];
      bad[3] = <String, Object?>{...bad[3], 'level': 'L9'};
      expect(
        () => decodeBoardCatalog(bad),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('第 3 项'),
          ),
        ),
      );
    });
  });

  group('BoardDefinition 相等性', () {
    test('字段相同相等，适用题型不同不相等', () {
      const base = BoardDefinition(
        id: 'a',
        name: 'A',
        level: BoardLevel.l2,
        description: '描述',
        order: 30,
      );
      const same = BoardDefinition(
        id: 'a',
        name: 'A',
        level: BoardLevel.l2,
        description: '描述',
        order: 30,
      );
      const differentTypes = BoardDefinition(
        id: 'a',
        name: 'A',
        level: BoardLevel.l2,
        description: '描述',
        applicableQuestionTypes: <String>['calculation'],
        order: 30,
      );
      expect(base, same);
      expect(base.hashCode, same.hashCode);
      expect(base == differentTypes, isFalse);
    });

    test('appliesTo：空适用题型=全部；空白题型一律不适用', () {
      final all = findBoard('l5_meta')!;
      expect(all.appliesTo('calculation'), isTrue);
      expect(all.appliesTo('whatever'), isTrue);
      expect(all.appliesTo(''), isFalse);

      final multi = findBoard('l1_multi_solution')!;
      expect(multi.appliesTo(' CALCULATION '), isTrue);
      expect(multi.appliesTo('reading'), isFalse);
    });
  });
}
