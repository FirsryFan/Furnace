import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/ai_repository.dart';
import 'package:furnace/data/repositories/anki_repository.dart';
import 'package:furnace/data/repositories/question_repository.dart';
import 'package:furnace/data/repositories/tag_repository.dart';
import 'package:furnace/data/repositories/task_repository.dart';
import 'package:furnace/data/repositories/time_block_repository.dart';
import 'package:furnace/features/ai/domain/ai_tool.dart';
import 'package:furnace/features/ai/domain/approval_engine.dart';
import 'package:furnace/features/ai/domain/tool_registry.dart';
import 'package:furnace/features/ai/tools/question_tools.dart';

/// `read_questions_by_serials` 是对话里「整卷题号批量读题」的工具面，验收点：
///
///  1. **只读**：一次调用不改任何表，`ApprovalEngine` 在任何权限模式下都不逐条询问；
///  2. **清单口径**：逗号/顿号/空白分隔、区间 `1..3`、`TR-00042`/`42` 写法、去重升序；
///  3. **摘要完整**：每个号在不在库，以及题号/学科/来源/题干摘要/有无答案/解析/
///     选项数/题干配图与答案/解析截图数；
///  4. **缺号如实报**：库里没有的号进 `missing`，坏段进 `rejected_segments`，
///     绝不生成题干；
///  5. 边界：缺参、整段认不出、`max_count` 截断与上限、注册表可达。
void main() {
  late AppDatabase db;
  late QuestionRepository questions;
  late TagRepository tags;
  late AnkiRepository anki;
  late ReadQuestionsBySerialsTool tool;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    questions = QuestionRepository(db);
    tags = TagRepository(db);
    anki = AnkiRepository(db);
    tool = ReadQuestionsBySerialsTool(db: db);
  });

  tearDown(() async {
    await db.close();
  });

  ToolInvocation invoke(Map<String, Object?> args) => ToolInvocation(
        toolName: tool.name,
        action: tool.name,
        arguments: args,
      );

  Future<Question> seedQuestion({
    required String stem,
    String? answer,
    String? solution,
    String subjectKey = '数学',
    String sourceLevel = 'gaokao',
    String sourceLabel = '',
    int? year,
    String? region,
    List<QuestionOptionDraft> options = const [],
  }) async {
    final ingested = await questions.ingest(
      QuestionDraft(
        stem: stem,
        answer: answer,
        solution: solution,
        subjectKey: subjectKey,
        sourceLevel: sourceLevel,
        sourceLabel: sourceLabel,
        year: year,
        region: region,
        options: options,
      ),
    );
    return ingested.question;
  }

  Future<void> seedAttachment({
    required String ownerId,
    String? role,
    String? id,
  }) async {
    await db.into(db.attachments).insert(
          AttachmentsCompanion.insert(
            id: id ?? 'att-$ownerId',
            ownerType: 'question',
            ownerId: ownerId,
            relPath: 'question_images/$ownerId/att/photo.png',
            mime: const Value('image/png'),
            role: Value(role),
            createdAt: 1,
          ),
        );
  }

  Map<String, Object?> modelOf(ToolResult result) =>
      result.modelResult! as Map<String, Object?>;

  List<Object?> serialsOf(ToolResult result) => [
        for (final row in modelOf(result)['questions']! as List)
          (row as Map<String, Object?>)['serial_no'],
      ];

  group('read-only by construction', () {
    test('ApprovalEngine never asks per call, in any mode', () {
      for (final mode in AiPermissionMode.values) {
        final decision =
            ApprovalEngine(mode: mode).forInvocation(tool, const {});
        expect(decision.risk, ToolRisk.write);
        expect(decision.reversible, isTrue);
        expect(
          decision.disposition,
          isNot(ToolDisposition.individualApproval),
          reason: 'mode ${mode.name} must not ask one by one for a read',
        );
      }
      expect(tool.readOnly, isTrue);
      expect(tool.riskFor(''), ToolRisk.write);
      expect(tool.reversibleFor(''), isTrue);
      expect(tool.availableOnCurrentPlatform, isTrue);
    });

    test('a call leaves every table untouched', () async {
      final first = await seedQuestion(stem: '第一道题', answer: 'A');
      await seedQuestion(stem: '第二道题');
      await seedAttachment(ownerId: first.id);

      Future<List<String>> snapshot() async {
        final questionRows = await db.select(db.questions).get();
        final optionRows = await db.select(db.questionOptions).get();
        final attachmentRows = await db.select(db.attachments).get();
        return [
          for (final row in questionRows)
            'q:${row.id}:${row.stem}:${row.updatedAt}',
          for (final row in optionRows) 'o:${row.id}:${row.content}',
          for (final row in attachmentRows) 'a:${row.id}:${row.relPath}',
        ];
      }

      final before = await snapshot();
      final result = await tool.run(invoke({'serials': '1..2'}));
      expect(result.ok, isTrue);
      expect(await snapshot(), before);
    });
  });

  group('清单口径', () {
    test('reads a single serial in TR-00002 form', () async {
      await seedQuestion(stem: '第一道题');
      final second = await seedQuestion(stem: '第二道题');

      final result = await tool.run(invoke({'serials': 'TR-00002'}));

      expect(result.ok, isTrue);
      final model = modelOf(result);
      expect(model['requested_count'], 1);
      expect(model['found_count'], 1);
      expect(model['missing_count'], 0);
      expect(model['truncated'], isFalse);
      final rows = model['questions']! as List;
      final row = rows.single as Map<String, Object?>;
      expect(row['serial_no'], 2);
      expect(row['serial_label'], 'TR-00002');
      expect(row['id'], second.id);
      expect(serialsOf(result), [2]);
    });

    test('expands ranges and keeps ascending order', () async {
      await seedQuestion(stem: '第一道题');
      await seedQuestion(stem: '第二道题');
      await seedQuestion(stem: '第三道题');

      final result = await tool.run(invoke({'serials': '1..3'}));

      expect(result.ok, isTrue);
      expect(serialsOf(result), [1, 2, 3]);
      expect(modelOf(result)['requested_count'], 3);
    });

    test('accepts commas, ideographic commas, spaces and dashes', () async {
      for (var index = 1; index <= 5; index++) {
        await seedQuestion(stem: '第 $index 道题');
      }

      final comma = await tool.run(invoke({'serials': '1、3，5'}));
      final dashed = await tool.run(invoke({'serials': '2-4'}));
      final spaces = await tool.run(invoke({'serials': '1 3 5'}));

      expect(comma.ok, isTrue);
      expect(serialsOf(comma), [1, 3, 5]);
      expect(dashed.ok, isTrue);
      expect(serialsOf(dashed), [2, 3, 4]);
      expect(spaces.ok, isTrue);
      expect(serialsOf(spaces), [1, 3, 5]);
    });

    test('dedupes repeated serials and normalizes case', () async {
      await seedQuestion(stem: '第一道题');
      await seedQuestion(stem: '第二道题');
      await seedQuestion(stem: '第三道题');

      final result =
          await tool.run(invoke({'serials': 'TR-00003, 1, 3, tr-1'}));

      expect(result.ok, isTrue);
      expect(modelOf(result)['requested_count'], 2);
      expect(serialsOf(result), [1, 3]);
    });
  });

  group('摘要', () {
    test('returns the fields the model needs to recognize a question',
        () async {
      final question = await seedQuestion(
        stem: '已知函数 f(x)=x^2，求单调区间。',
        answer: 'B',
        solution: '配方后看对称轴。',
        sourceLevel: 'provincial_diagnostic',
        sourceLabel: '2026 届高三上期末',
        year: 2026,
        region: '江苏',
        options: const [
          QuestionOptionDraft(label: 'A', content: '(-∞, 0]'),
          QuestionOptionDraft(label: 'B', content: '[0, +∞)'),
        ],
      );
      await seedAttachment(ownerId: question.id);

      final result = await tool.run(invoke({'serials': '1'}));
      final row = (modelOf(result)['questions']! as List).single
          as Map<String, Object?>;

      expect(row['id'], question.id);
      expect(row['subject'], '数学');
      expect(row['source_level_zh'], '省市诊断');
      expect(row['source_label'], '2026 届高三上期末');
      expect(row['year'], 2026);
      expect(row['region'], '江苏');
      expect(row['stem_preview'], '已知函数 f(x)=x^2，求单调区间。');
      expect(row['has_answer'], isTrue);
      expect(row['has_solution'], isTrue);
      expect(row['option_count'], 2);
      expect(row['image_count'], 1);
      expect(row['answer_image_count'], 0);
    });

    test('marks an empty shell as missing answer/solution/options', () async {
      await seedQuestion(stem: '只有题干的一道题');

      final result = await tool.run(invoke({'serials': '1'}));
      final row = (modelOf(result)['questions']! as List).single
          as Map<String, Object?>;

      expect(row['has_answer'], isFalse);
      expect(row['has_solution'], isFalse);
      expect(row['option_count'], 0);
      expect(row['image_count'], 0);
      expect(row['answer_image_count'], 0);
    });

    test('reports missing serials honestly, with labels', () async {
      for (var index = 1; index <= 4; index++) {
        await seedQuestion(stem: '第 $index 道题');
      }

      final result = await tool.run(invoke({'serials': '1..6'}));
      final model = modelOf(result);

      expect(result.ok, isTrue);
      expect(model['requested_count'], 6);
      expect(model['found_count'], 4);
      expect(model['missing_count'], 2);
      expect(model['missing'], ['TR-00005', 'TR-00006']);
      expect(result.summary, contains('缺 2 道'));
      expect(result.summary, contains('找到 4 道'));
      expect(result.summary, contains('我不会自己出题'));
    });

    test('says so when the library has none of the requested serials',
        () async {
      await seedQuestion(stem: '第一道题');

      final result = await tool.run(invoke({'serials': '99..100'}));

      expect(result.ok, isTrue);
      expect(modelOf(result)['found_count'], 0);
      expect(modelOf(result)['missing'], ['TR-00099', 'TR-00100']);
      expect(result.summary, contains('库里一道都没有'));
    });

    test('keeps unrecognized segments instead of guessing', () async {
      await seedQuestion(stem: '第一道题');
      await seedQuestion(stem: '第二道题');
      await seedQuestion(stem: '第三道题');

      final result = await tool.run(invoke({'serials': '1, 香蕉, 3'}));
      final model = modelOf(result);

      expect(result.ok, isTrue);
      expect(serialsOf(result), [1, 3]);
      expect(model['rejected_segments'], ['香蕉']);
      expect(result.summary, contains('没认出来'));
    });

    test('truncates over-long lists and says so', () async {
      for (var index = 1; index <= 3; index++) {
        await seedQuestion(stem: '第 $index 道题');
      }

      final result =
          await tool.run(invoke({'serials': '1..10', 'max_count': 2}));
      final model = modelOf(result);

      expect(result.ok, isTrue);
      expect(model['requested_count'], 2);
      expect(model['truncated'], isTrue);
      expect(serialsOf(result), [1, 2]);
      expect(result.summary, contains('只读了前 2 个'));
    });
  });

  group('边界', () {
    test('fails when serials is missing', () async {
      final result = await tool.run(invoke(const {}));

      expect(result.ok, isFalse);
      expect(result.error, contains('缺少题号清单'));
    });

    test('fails when no segment is a usable serial', () async {
      final result = await tool.run(invoke({'serials': '香蕉, 苹果'}));

      expect(result.ok, isFalse);
      expect(result.error, contains('没有可用的题号'));
    });

    test('max_count <= 0 falls back to the default instead of failing',
        () async {
      await seedQuestion(stem: '第一道题');
      await seedQuestion(stem: '第二道题');

      final result =
          await tool.run(invoke({'serials': '1..2', 'max_count': 0}));

      expect(result.ok, isTrue);
      expect(serialsOf(result), [1, 2]);
    });
  });

  group('配图分类（题干配图与答案/解析截图）', () {
    test('每行分别报题干配图数与答案/解析截图数', () async {
      final first = await seedQuestion(stem: '第一道题');
      final second = await seedQuestion(stem: '第二道题');
      // 旧行 role 为 NULL + 'stem' → 题干配图 2 张；'answer' → 答案截图 1 张。
      await seedAttachment(ownerId: first.id, id: 'att-first-null');
      await seedAttachment(
          ownerId: first.id, id: 'att-first-stem', role: 'stem');
      await seedAttachment(
        ownerId: first.id,
        id: 'att-first-answer',
        role: 'answer',
      );
      // 只有解析截图：题干配图 0、答案/解析截图 1。
      await seedAttachment(
        ownerId: second.id,
        id: 'att-second-solution',
        role: 'solution',
      );

      final result = await tool.run(invoke({'serials': '1..2'}));
      final rows = [
        for (final row in modelOf(result)['questions']! as List)
          row as Map<String, Object?>,
      ];

      expect(rows, hasLength(2));
      expect(rows[0]['image_count'], 2);
      expect(rows[0]['answer_image_count'], 1);
      expect(rows[1]['image_count'], 0);
      expect(rows[1]['answer_image_count'], 1);
    });

    test('没有附件时两个键都是 0（键始终存在）', () async {
      await seedQuestion(stem: '没配图的题');

      final result = await tool.run(invoke({'serials': '1'}));
      final row = (modelOf(result)['questions']! as List).single
          as Map<String, Object?>;

      expect(row['image_count'], 0);
      expect(row['answer_image_count'], 0);
      expect(
        row.keys,
        containsAll(<String>['image_count', 'answer_image_count']),
      );
    });
  });

  group('注册与 schema', () {
    test('is reachable in ToolRegistry.forApp and read-only', () {
      final registry = ToolRegistry.forApp(
        db: db,
        tasks: TaskRepository(db),
        blocks: TimeBlockRepository(db),
        anki: anki,
        tags: tags,
      );

      expect(registry.byName('read_questions_by_serials'),
          isA<ReadQuestionsBySerialsTool>());
      expect(
        registry.forCurrentPlatform.map((t) => t.name),
        contains('read_questions_by_serials'),
      );

      final spec = registry.modelSpecs.firstWhere((s) => s.name == tool.name);
      expect(spec.description, contains('只读'));
      expect(spec.parameters['type'], 'object');
      expect(spec.parameters['required'], contains('serials'));
      expect(
        (spec.parameters['properties']! as Map<String, Object?>).keys,
        containsAll(['serials', 'max_count']),
      );
      expect(
        ReadQuestionsBySerialsTool.defaultMaxCount,
        lessThanOrEqualTo(ReadQuestionsBySerialsTool.hardMaxCount),
      );
    });
  });
}
