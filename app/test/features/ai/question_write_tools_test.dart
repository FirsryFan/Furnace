import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/question_repository.dart';
import 'package:furnace/data/repositories/tag_repository.dart';
import 'package:furnace/features/ai/domain/ai_tool.dart';
import 'package:furnace/features/ai/tools/question_write_tools.dart';

/// `create_questions` 是「AI 收题」的写工具面，验收点：
///
///  1. **照抄入库**：模型给的字段原样落库；没给的答案 / 解析留空；
///     subject_key 缺省用 other、question_type 缺省 solution、source_level 缺省 unknown；
///  2. **textFormat 只认 markdown**：传 markdown 落库为 markdown，其余落 plain（列存 null）；
///  3. **重复题不报错**：同指纹第二次入库 created=false，撤销只删本次新建的题；
///  4. **标签失败不拖垮录题**：解析不了的标签进 ignored_tags，题照样入库；
///  5. **参数错误整批不写**：缺 questions / 缺 stem / 选项缺字段 / 超过 100 道都不入库。
void main() {
  late AppDatabase db;
  late QuestionRepository questions;
  late TagRepository tags;
  late CreateQuestionsTool tool;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    questions = QuestionRepository(db);
    tags = TagRepository(db);
    tool = CreateQuestionsTool(db: db, tags: tags);
  });

  tearDown(() async {
    await db.close();
  });

  ToolInvocation invoke(Map<String, Object?> arguments) => ToolInvocation(
        toolName: tool.name,
        action: tool.name,
        arguments: arguments,
      );

  Map<String, Object?> item(Map<String, Object?> fields) => <String, Object?>{
        'stem': '题干',
        ...fields,
      };

  Future<ToolResult> create(List<Map<String, Object?>> items) =>
      tool.run(invoke(<String, Object?>{'questions': items}));

  Future<Question> onlyQuestion() async => (await questions.all()).single;

  Map<String, Object?> modelOf(ToolResult result) =>
      result.modelResult! as Map<String, Object?>;

  List<Map<String, Object?>> resultItems(ToolResult result) {
    final model = modelOf(result);
    return (model['questions']! as List).cast<Map<String, Object?>>();
  }

  group('元信息与 schema', () {
    test('工具名 / 风险 / 平台与可撤销标记', () {
      expect(CreateQuestionsTool.toolName, 'create_questions');
      expect(tool.name, 'create_questions');
      expect(tool.riskFor(''), ToolRisk.write);
      expect(tool.reversibleFor(''), isTrue);
      expect(tool.availableOnCurrentPlatform, isTrue);
    });

    test('description 写明清题纪律与 textFormat 口径', () {
      final description = tool.description;
      expect(description, contains('逐字誊写'));
      expect(description, contains('不改编'));
      expect(description, contains('留空'));
      expect(description, contains('markdown'));
      expect(description, contains('other'));
      expect(description, contains('query_content'));
      expect(description, contains('created=false'));
    });

    test('parameters schema 结构完整', () {
      final parameters = tool.parameters;
      expect(parameters['type'], 'object');
      final properties = parameters['properties']! as Map<String, Object?>;
      final questions = properties['questions']! as Map<String, Object?>;
      expect(questions['type'], 'array');
      expect(questions['description'], contains('100'));
      final items = questions['items']! as Map<String, Object?>;
      expect(items['type'], 'object');
      final itemProperties = items['properties']! as Map<String, Object?>;
      expect(
        itemProperties.keys.toSet(),
        containsAll(<String>[
          'stem',
          'answer',
          'solution',
          'options',
          'subject_key',
          'question_type',
          'source_level',
          'source_label',
          'year',
          'region',
          'difficulty',
          'trap_note',
          'text_format',
          'tags',
        ]),
      );
      final questionType =
          itemProperties['question_type']! as Map<String, Object?>;
      expect(
        questionType['enum'],
        ['single_choice', 'multi_choice', 'fill_blank', 'solution', 'open'],
      );
      final textFormat = itemProperties['text_format']! as Map<String, Object?>;
      expect(textFormat['enum'], ['plain', 'markdown']);
      expect(parameters['required'], contains('questions'));
    });
  });

  group('入库字段', () {
    test('最小题：缺省字段按工具口径补齐', () async {
      final result = await create(<Map<String, Object?>>[
        item(<String, Object?>{'stem': '1+1=?'}),
      ]);
      expect(result.ok, isTrue);
      expect(result.summary, '已录入 1 道题（其中 0 道题库已有）');
      final model = modelOf(result);
      expect(model['created'], 1);
      expect(model['existing'], 0);

      final row = await onlyQuestion();
      expect(row.stem, '1+1=?');
      expect(row.answer, isNull);
      expect(row.solution, isNull);
      expect(row.subjectKey, 'other');
      expect(row.questionType, 'solution');
      expect(row.sourceLevel, 'unknown');
      expect(row.sourceLabel, '');
      expect(row.textFormat, isNull);
      expect(row.origin, 'manual');
      expect(row.serialNo, 1);
    });

    test('全字段题原样落库，textFormat=markdown', () async {
      final result = await create(<Map<String, Object?>>[
        item(<String, Object?>{
          'stem': '已知函数 f(x)=x^2',
          'answer': '2',
          'solution': '求导后代入',
          'subject_key': 'math',
          'question_type': 'single_choice',
          'source_level': 'gaokao',
          'source_label': '2023 湖南高考',
          'year': 2023,
          'region': '湖南',
          'difficulty': 0.8,
          'trap_note': '注意定义域',
          'text_format': 'markdown',
        }),
      ]);
      expect(result.ok, isTrue);
      final row = await onlyQuestion();
      expect(row.stem, '已知函数 f(x)=x^2');
      expect(row.answer, '2');
      expect(row.solution, '求导后代入');
      expect(row.subjectKey, 'math');
      expect(row.questionType, 'single_choice');
      expect(row.sourceLevel, 'gaokao');
      expect(row.sourceLabel, '2023 湖南高考');
      expect(row.year, 2023);
      expect(row.region, '湖南');
      expect(row.difficulty, closeTo(0.8, 1e-9));
      expect(row.trapNote, '注意定义域');
      expect(row.textFormat, 'markdown');
    });

    test('text_format 非 markdown 一律落 plain（列存 null）', () async {
      await create(<Map<String, Object?>>[
        item(<String, Object?>{'stem': '甲题', 'text_format': 'rich_text'}),
        item(<String, Object?>{'stem': '乙题', 'text_format': 'plain'}),
      ]);
      final rows = await questions.all();
      expect(rows, hasLength(2));
      expect(rows.every((row) => row.textFormat == null), isTrue);
    });

    test('数字字符串也能解析 year / difficulty', () async {
      await create(<Map<String, Object?>>[
        item(<String, Object?>{
          'stem': '数值解析题',
          'year': '2022',
          'difficulty': '0.35',
        }),
      ]);
      final row = await onlyQuestion();
      expect(row.year, 2022);
      expect(row.difficulty, closeTo(0.35, 1e-9));
    });

    test('多题按传入顺序分配递增题号', () async {
      final result = await create(<Map<String, Object?>>[
        item(<String, Object?>{'stem': '第一题'}),
        item(<String, Object?>{'stem': '第二题'}),
      ]);
      expect(result.ok, isTrue);
      final items = resultItems(result);
      expect(items, hasLength(2));
      expect(items[0]['index'], 0);
      expect(items[1]['index'], 1);
      expect(items[0]['serial_no'], 1);
      expect(items[1]['serial_no'], 2);
      expect(items[0]['question_id'], isNot(items[1]['question_id']));
      expect(modelOf(result)['created'], 2);
    });
  });

  group('选项落库', () {
    test('选择题选项按序入库，is_correct 生效', () async {
      final result = await create(<Map<String, Object?>>[
        item(<String, Object?>{
          'stem': '选择题题干',
          'question_type': 'single_choice',
          'options': <Map<String, Object?>>[
            <String, Object?>{
              'label': 'A',
              'content': '选项甲',
              'is_correct': true,
            },
            <String, Object?>{'label': 'B', 'content': '选项乙'},
          ],
        }),
      ]);
      expect(result.ok, isTrue);
      final questionId = resultItems(result).single['question_id']! as String;
      final options = await questions.optionsOf(questionId);
      expect(options, hasLength(2));
      expect(options[0].label, 'A');
      expect(options[0].content, '选项甲');
      expect(options[0].isCorrect, isTrue);
      expect(options[0].sortOrder, 0);
      expect(options[1].label, 'B');
      expect(options[1].content, '选项乙');
      expect(options[1].isCorrect, isFalse);
      expect(options[1].sortOrder, 1);
    });

    test('is_correct 字符串与数字也解析', () async {
      final result = await create(<Map<String, Object?>>[
        item(<String, Object?>{
          'stem': '选项布尔解析',
          'options': <Map<String, Object?>>[
            <String, Object?>{
              'label': 'A',
              'content': '甲',
              'is_correct': 'true',
            },
            <String, Object?>{
              'label': 'B',
              'content': '乙',
              'is_correct': 1,
            },
          ],
        }),
      ]);
      expect(result.ok, isTrue);
      final questionId = resultItems(result).single['question_id']! as String;
      final options = await questions.optionsOf(questionId);
      expect(options[0].isCorrect, isTrue);
      expect(options[1].isCorrect, isTrue);
    });
  });

  group('去重与撤销', () {
    test('同一次调用里的重复题 created=false', () async {
      final result = await create(<Map<String, Object?>>[
        item(<String, Object?>{'stem': '重复题'}),
        item(<String, Object?>{'stem': ' 重复题 '}),
      ]);
      expect(result.ok, isTrue);
      expect(result.summary, '已录入 2 道题（其中 1 道题库已有）');
      final items = resultItems(result);
      expect(items[0]['created'], isTrue);
      expect(items[1]['created'], isFalse);
      expect(
        items[0]['question_id'],
        items[1]['question_id'],
        reason: '重复题返回既有题目 id',
      );
      expect(await questions.all(), hasLength(1));
      expect(modelOf(result)['created'], 1);
      expect(modelOf(result)['existing'], 1);
    });

    test('跨调用重复题不新建', () async {
      final first = await create(<Map<String, Object?>>[
        item(<String, Object?>{'stem': '跨调用重复'}),
      ]);
      final second = await create(<Map<String, Object?>>[
        item(<String, Object?>{'stem': '跨调用重复'}),
      ]);
      expect(first.ok, isTrue);
      expect(second.ok, isTrue);
      expect(modelOf(second)['created'], 0);
      expect(modelOf(second)['existing'], 1);
      expect(await questions.all(), hasLength(1));
      final after = jsonDecode(second.afterJson!) as Map<String, Object?>;
      expect((after['created_ids']! as List), isEmpty);
      expect(after['question_ids'], hasLength(1));
    });

    test('afterJson 只把新建题放进 created_ids', () async {
      final seeded = await questions.ingest(
        const QuestionDraft(stem: '库里已有的题'),
      );
      final result = await create(<Map<String, Object?>>[
        item(<String, Object?>{'stem': '本次新题'}),
        item(<String, Object?>{'stem': '库里已有的题'}),
      ]);
      expect(result.ok, isTrue);
      expect(result.beforeJson, isNull);
      expect(result.afterJson, isNotNull);
      final after = jsonDecode(result.afterJson!) as Map<String, Object?>;
      expect(after.keys.toSet(), <String>{'question_ids', 'created_ids'});
      final createdIds = after['created_ids']! as List;
      final questionIds = after['question_ids']! as List;
      expect(createdIds, hasLength(1));
      expect(questionIds, hasLength(2));
      expect(createdIds.single, isNot(seeded.question.id));
      expect(questionIds, contains(seeded.question.id));
      expect(result.isUndoable, isTrue);
    });
  });

  group('标签解析', () {
    test('按标签 id 与名称解析成功', () async {
      final tag = await tags.createTag(name: '函数');
      final result = await create(<Map<String, Object?>>[
        item(<String, Object?>{
          'stem': '按 id 挂标签',
          'tags': <String>[tag.id],
        }),
        item(<String, Object?>{
          'stem': '按名字挂标签',
          'tags': <String>['函数'],
        }),
      ]);
      expect(result.ok, isTrue);
      final items = resultItems(result);
      for (final item in items) {
        final ids = await questions.tagIdsOf(item['question_id']! as String);
        expect(ids, <String>[tag.id]);
      }
      expect(modelOf(result).containsKey('ignored_tags'), isFalse);
    });

    test('单个字符串形式的 tags 同样解析', () async {
      final tag = await tags.createTag(name: '数列');
      final result = await create(<Map<String, Object?>>[
        item(<String, Object?>{'stem': '单标签写法', 'tags': tag.id}),
      ]);
      expect(result.ok, isTrue);
      final questionId = resultItems(result).single['question_id']! as String;
      expect(await questions.tagIdsOf(questionId), <String>[tag.id]);
    });

    test('标签解析失败只记录，不阻断入库', () async {
      final result = await create(<Map<String, Object?>>[
        item(<String, Object?>{
          'stem': '标签写错的题',
          'tags': <String>['不存在/路径'],
        }),
      ]);
      expect(result.ok, isTrue);
      final model = modelOf(result);
      expect(model['ignored_tags'], <String>['不存在/路径']);
      final questionId = resultItems(result).single['question_id']! as String;
      expect(await questions.tagIdsOf(questionId), isEmpty);
      expect(await onlyQuestion().then((row) => row.stem), '标签写错的题');
    });
  });

  group('参数校验（整批不写库）', () {
    test('缺 questions', () async {
      final result = await tool.run(invoke(const <String, Object?>{}));
      expect(result.ok, isFalse);
      expect(result.error, contains('questions'));
      expect(result.summary, contains('questions'));
      expect(result.afterJson, isNull);
      expect(await questions.all(), isEmpty);
    });

    test('questions 为空数组', () async {
      final result = await create(const <Map<String, Object?>>[]);
      expect(result.ok, isFalse);
      expect(result.error, contains('questions'));
    });

    test('questions 不是数组', () async {
      final result = await tool.run(
        invoke(<String, Object?>{'questions': '一道题'}),
      );
      expect(result.ok, isFalse);
      expect(result.error, contains('questions'));
    });

    test('数组元素不是对象', () async {
      final result = await tool.run(
        invoke(<String, Object?>{
          'questions': <Object?>['一道题'],
        }),
      );
      expect(result.ok, isFalse);
      expect(result.error, contains('第 1 个元素'));
    });

    test('第 2 道题缺 stem 时整批不写', () async {
      final result = await create(<Map<String, Object?>>[
        item(<String, Object?>{'stem': '合法题'}),
        <String, Object?>{'answer': '没有题干'},
      ]);
      expect(result.ok, isFalse);
      expect(result.error, contains('第 2 道题'));
      expect(result.error, contains('stem'));
      expect(await questions.all(), isEmpty);
    });

    test('空白 stem 视为缺失', () async {
      final result = await create(<Map<String, Object?>>[
        item(<String, Object?>{'stem': '   '}),
      ]);
      expect(result.ok, isFalse);
      expect(result.error, contains('stem'));
      expect(await questions.all(), isEmpty);
    });

    test('options 不是数组或选项缺字段时报错', () async {
      final notList = await create(<Map<String, Object?>>[
        item(<String, Object?>{'stem': '选项不是数组', 'options': 'A. 甲'}),
      ]);
      expect(notList.ok, isFalse);
      expect(notList.error, contains('options'));

      final missingLabel = await create(<Map<String, Object?>>[
        item(<String, Object?>{
          'stem': '选项缺 label',
          'options': <Map<String, Object?>>[
            <String, Object?>{'content': '只有内容'},
          ],
        }),
      ]);
      expect(missingLabel.ok, isFalse);
      expect(missingLabel.error, contains('label'));
      expect(await questions.all(), isEmpty);
    });

    test('超过单次上限 100 道时拒绝', () async {
      final items = <Map<String, Object?>>[
        for (var i = 0; i < CreateQuestionsTool.maxQuestionsPerCall + 1; i++)
          item(<String, Object?>{'stem': '批量题 $i'}),
      ];
      final result = await create(items);
      expect(result.ok, isFalse);
      expect(result.error, contains('100'));
      expect(await questions.all(), isEmpty);
    });
  });

  group('返回结构', () {
    test('modelResult 与每题字段结构', () async {
      final result = await create(<Map<String, Object?>>[
        item(<String, Object?>{'stem': '返回结构题'}),
      ]);
      final model = modelOf(result);
      expect(model.keys.toSet(), <String>{'created', 'existing', 'questions'});
      final items = resultItems(result);
      expect(
        items.single.keys.toSet(),
        <String>{'index', 'question_id', 'serial_no', 'created'},
      );
      expect(items.single['index'], 0);
      expect(items.single['created'], isTrue);
      expect(items.single['question_id'], isA<String>());
      expect(items.single['serial_no'], 1);
      final modelJson = result.toModelJson();
      expect(modelJson['ok'], isTrue);
      expect(modelJson['result'], model);
    });
  });
}
