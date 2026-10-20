import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/ai_repository.dart';
import 'package:furnace/data/repositories/anki_repository.dart';
import 'package:furnace/data/repositories/question_repository.dart';
import 'package:furnace/data/repositories/tag_repository.dart';
import 'package:furnace/domain/services/questions/question_number.dart';
import 'package:furnace/features/ai/domain/ai_tool.dart';
import 'package:furnace/features/ai/domain/approval_engine.dart';
import 'package:furnace/features/ai/tools/question_tools.dart';

/// `read_question` 是对话里「读题」的工具面，验收点：
///
///  1. **只读**：一次调用不改任何表，`ApprovalEngine` 在任何权限模式下都不逐条询问；
///  2. **只读库里已有的题**：按 `question_id` 或题号（TR-00042 / 42）定位，
///     库里没有就如实说没有，绝不生成题干；
///  3. **内容完整**：题干/选项顺序/答案/解析/知识点/最新解题链动作/题干配图与答案截图数；
///  4. 边界：缺参、坏题号、查无此号、无编号题、没有答案/解析的脏行。
void main() {
  late AppDatabase db;
  late QuestionRepository questions;
  late TagRepository tags;
  late AnkiRepository anki;
  late ReadQuestionTool tool;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    questions = QuestionRepository(db);
    tags = TagRepository(db);
    anki = AnkiRepository(db);
    tool = ReadQuestionTool(db: db);
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
    double? difficulty,
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
        difficulty: difficulty,
        options: options,
      ),
    );
    return ingested.question;
  }

  Future<String> seedKnowledgePoint(String title) async =>
      (await anki.createKnowledgePoint(title: title, content: '')).id;

  Future<void> link({
    required String questionId,
    required String pointId,
    required String tagName,
  }) async {
    final tagId = (await tags.createTag(name: tagName)).id;
    await tags.addTagToObject(
      tagId: tagId,
      objectType: 'knowledge_point',
      objectId: pointId,
    );
    await tags.addTagToObject(
      tagId: tagId,
      objectType: 'question',
      objectId: questionId,
    );
  }

  Future<void> seedChain({
    required String questionId,
    required List<String> actionTypes,
  }) async {
    await questions.saveChain(
      questionId,
      ReasoningChainDraft(
        model: 'test-model',
        summary: '测试链',
        steps: [
          for (var index = 0; index < actionTypes.length; index++)
            ReasoningStepDraft(
              goal: '第 ${index + 1} 步',
              actionType: actionTypes[index],
            ),
        ],
      ),
    );
  }

  Future<void> seedAttachment({
    required String id,
    required String ownerType,
    required String ownerId,
    String? role,
  }) async {
    await db.into(db.attachments).insert(
          AttachmentsCompanion.insert(
            id: id,
            ownerType: ownerType,
            ownerId: ownerId,
            relPath: 'question_images/$ownerId/$id/photo.png',
            mime: const Value('image/png'),
            role: Value(role),
            createdAt: 1,
          ),
        );
  }

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
      final pointId = await seedKnowledgePoint('函数单调性');
      final question = await seedQuestion(stem: '讨论函数的单调区间。');
      await link(
        questionId: question.id,
        pointId: pointId,
        tagName: '函数单调性',
      );
      await seedChain(
        questionId: question.id,
        actionTypes: ['classify_discussion'],
      );
      await seedAttachment(
        id: 'att-1',
        ownerType: 'question',
        ownerId: question.id,
      );

      Future<List<String>> snapshot() async {
        final questionRows = await db.select(db.questions).get();
        final chainRows = await db.select(db.reasoningChains).get();
        final stepRows = await db.select(db.reasoningSteps).get();
        final tagRows = await db.select(db.tags).get();
        final linkRows = await db.select(db.objectTags).get();
        final attachmentRows = await db.select(db.attachments).get();
        return [
          for (final row in questionRows)
            'q:${row.id}:${row.stem}:${row.updatedAt}',
          for (final row in chainRows) 'c:${row.id}:${row.createdAt}',
          for (final row in stepRows) 's:${row.id}:${row.actionType}',
          for (final row in tagRows) 't:${row.id}:${row.name}',
          for (final row in linkRows)
            'l:${row.tagId}:${row.objectType}:${row.objectId}',
          for (final row in attachmentRows) 'a:${row.id}:${row.relPath}',
        ];
      }

      final before = await snapshot();
      final result = await tool.run(invoke({'question_id': question.id}));
      expect(result.ok, isTrue);
      expect(await snapshot(), before);
    });
  });

  group('定位：question_id / 题号', () {
    test('reads by serial text TR-00002', () async {
      await seedQuestion(stem: '第一道题');
      final second = await seedQuestion(stem: '第二道题');

      final result = await tool.run(invoke({'serial': 'TR-00002'}));

      expect(result.ok, isTrue);
      final model = result.modelResult! as Map<String, Object?>;
      expect(model['serial_no'], 2);
      expect(model['serial_label'], 'TR-00002');
      expect(model['stem'], second.stem);
    });

    test('accepts bare number and lowercase prefix', () async {
      await seedQuestion(stem: '第一道题');
      final second = await seedQuestion(stem: '第二道题');

      final bare = await tool.run(invoke({'serial': '2'}));
      final lower = await tool.run(invoke({'serial': 'tr-2'}));

      expect(bare.ok, isTrue);
      expect(lower.ok, isTrue);
      expect(
        (bare.modelResult! as Map<String, Object?>)['id'],
        second.id,
      );
      expect(
        (lower.modelResult! as Map<String, Object?>)['id'],
        second.id,
      );
    });

    test('question_id wins when both are given', () async {
      final first = await seedQuestion(stem: '第一道题');
      await seedQuestion(stem: '第二道题');

      final result = await tool.run(
        invoke({'question_id': first.id, 'serial': 'TR-00002'}),
      );

      expect(result.ok, isTrue);
      expect(
        (result.modelResult! as Map<String, Object?>)['id'],
        first.id,
      );
    });

    test('fails when neither locator is given', () async {
      final result = await tool.run(invoke(const {}));

      expect(result.ok, isFalse);
      expect(result.error, contains('缺少题目定位'));
    });

    test('fails on an unreadable serial', () async {
      final result = await tool.run(invoke({'serial': 'abc'}));

      expect(result.ok, isFalse);
      expect(result.error, contains('读不出题号'));
    });

    test('fails on an unknown serial', () async {
      await seedQuestion(stem: '只有一道题');

      final result = await tool.run(invoke({'serial': '999'}));

      expect(result.ok, isFalse);
      expect(result.error, contains('TR-00999'));
      expect(result.error, contains('没有题号'));
    });

    test('fails on an unknown question id', () async {
      final result = await tool.run(invoke({'question_id': 'q-missing'}));

      expect(result.ok, isFalse);
      expect(result.error, contains('没有 id'));
    });

    test('reports an unnumbered question as unnumbered', () async {
      await db.into(db.questions).insert(
            QuestionsCompanion.insert(
              id: 'q-no-serial',
              stem: '手工录进来、没有编号的题',
              createdAt: 1,
              updatedAt: 1,
            ),
          );

      final result = await tool.run(invoke({'question_id': 'q-no-serial'}));

      expect(result.ok, isTrue);
      final model = result.modelResult! as Map<String, Object?>;
      expect(model['serial_no'], isNull);
      expect(model['serial_label'], kUnnumberedQuestionLabel);
    });
  });

  group('content', () {
    test('returns the full question and keeps option order', () async {
      final question = await seedQuestion(
        stem: '已知函数 f(x)=x^2，求单调区间。',
        answer: 'B',
        solution: '由导数可判断单调性。',
        sourceLabel: '2026 届高三上期末',
        year: 2026,
        region: '江苏',
        difficulty: 6.5,
        options: const [
          QuestionOptionDraft(
            label: 'A',
            content: '在 R 上单调递增',
            sortOrder: 3,
          ),
          QuestionOptionDraft(
            label: 'B',
            content: '在负半轴递减、正半轴递增',
            isCorrect: true,
            sortOrder: 1,
          ),
          QuestionOptionDraft(
            label: 'C',
            content: '在 R 上单调递减',
            sortOrder: 2,
          ),
        ],
      );

      final result = await tool.run(invoke({'question_id': question.id}));

      expect(result.ok, isTrue);
      final model = result.modelResult! as Map<String, Object?>;
      expect(model['stem'], '已知函数 f(x)=x^2，求单调区间。');
      expect(model['answer'], 'B');
      expect(model['solution'], '由导数可判断单调性。');
      expect(model['subject_key'], '数学');
      expect(model['source_level'], 'gaokao');
      expect(model['source_label'], '2026 届高三上期末');
      expect(model['year'], 2026);
      expect(model['region'], '江苏');
      expect(model['difficulty'], 6.5);
      expect(model['state'], 'structured');
      final options = model['options']! as List<Object?>;
      expect(options, hasLength(3));
      expect(
        [
          for (final option in options)
            (option! as Map<String, Object?>)['label'],
        ],
        ['B', 'C', 'A'],
        reason: '按 sortOrder 升序，不是录入顺序',
      );
      final correct = options
          .cast<Map<String, Object?>>()
          .singleWhere((option) => option['is_correct'] == true);
      expect(correct['label'], 'B');
      expect(result.summary, contains('3 个选项'));
      expect(result.summary, contains('答案 B'));
      expect(result.summary, contains('解析'));
    });

    test('reports knowledge points with their names', () async {
      final question = await seedQuestion(stem: '讨论函数单调性。');
      final first = await seedKnowledgePoint('函数单调性');
      final second = await seedKnowledgePoint('导数的应用');
      await link(
        questionId: question.id,
        pointId: first,
        tagName: '函数单调性',
      );
      await link(
        questionId: question.id,
        pointId: second,
        tagName: '导数的应用',
      );

      final result = await tool.run(invoke({'question_id': question.id}));

      expect(result.ok, isTrue);
      final model = result.modelResult! as Map<String, Object?>;
      expect(
        (model['knowledge_point_ids']! as List<Object?>).toSet(),
        {first, second},
      );
      final points = (model['knowledge_points']! as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(
        {for (final point in points) point['id']: point['title']},
        {first: '函数单调性', second: '导数的应用'},
      );
      expect(result.summary, contains('知识点 2 个'));
      expect(result.summary, contains('函数单调性'));
    });

    test('reports the latest chain action types', () async {
      final question = await seedQuestion(stem: '分类讨论并求值。');
      await seedChain(
        questionId: question.id,
        actionTypes: ['classify_discussion', 'check_extremes'],
      );

      final result = await tool.run(invoke({'question_id': question.id}));

      expect(result.ok, isTrue);
      final model = result.modelResult! as Map<String, Object?>;
      expect(model['action_types'], ['classify_discussion', 'check_extremes']);
      expect(
        model['action_labels_zh'],
        hasLength(2),
      );
      expect(result.summary, contains('最新解题链动作 2 个'));
    });

    test('counts only this question images', () async {
      final question = await seedQuestion(stem: '看图求面积。');
      await seedAttachment(
        id: 'att-1',
        ownerType: 'question',
        ownerId: question.id,
      );
      await seedAttachment(
        id: 'att-2',
        ownerType: 'question',
        ownerId: question.id,
      );
      await seedAttachment(
        id: 'att-other',
        ownerType: 'ai_message',
        ownerId: question.id,
      );

      final result = await tool.run(invoke({'question_id': question.id}));

      expect(result.ok, isTrue);
      final model = result.modelResult! as Map<String, Object?>;
      expect(model['image_count'], 2);
      expect(model['answer_image_count'], 0);
      expect(result.summary, contains('配图 2 张'));
    });

    test('says so when answer and solution are missing', () async {
      final question = await seedQuestion(stem: '还没整理答案的题。');

      final result = await tool.run(invoke({'question_id': question.id}));

      expect(result.ok, isTrue);
      final model = result.modelResult! as Map<String, Object?>;
      expect(model['answer'], isNull);
      expect(model['solution'], isNull);
      expect(model['image_count'], 0);
      expect(model['answer_image_count'], 0);
      expect(result.summary, contains('库里没存答案'));
      expect(result.summary, contains('没存解析'));
    });
  });

  group('配图分类（题干配图与答案/解析截图）', () {
    test('按 role 分开计数，题干配图与答案截图互不混算', () async {
      final question = await seedQuestion(stem: '看图求面积。');
      // 旧行 role 为 NULL → 题干配图；'stem' 同桶。
      await seedAttachment(
        id: 'att-null-1',
        ownerType: 'question',
        ownerId: question.id,
      );
      await seedAttachment(
        id: 'att-null-2',
        ownerType: 'question',
        ownerId: question.id,
      );
      await seedAttachment(
        id: 'att-stem',
        ownerType: 'question',
        ownerId: question.id,
        role: 'stem',
      );
      // 'answer' / 'solution' → 答案/解析截图桶。
      await seedAttachment(
        id: 'att-answer',
        ownerType: 'question',
        ownerId: question.id,
        role: 'answer',
      );
      await seedAttachment(
        id: 'att-solution',
        ownerType: 'question',
        ownerId: question.id,
        role: 'solution',
      );
      // 不是这个题主（ownerType 不同）的截图不计。
      await seedAttachment(
        id: 'att-ai-answer',
        ownerType: 'ai_message',
        ownerId: question.id,
        role: 'answer',
      );

      final result = await tool.run(invoke({'question_id': question.id}));

      expect(result.ok, isTrue);
      final model = result.modelResult! as Map<String, Object?>;
      expect(model['image_count'], 3);
      expect(model['answer_image_count'], 2);
      expect(result.summary, contains('配图 3 张'));
      expect(result.summary, contains('答案/解析截图 2 张'));
    });

    test('只有答案截图时 image_count 为 0，摘要不提「配图」', () async {
      final question = await seedQuestion(stem: '答案只存了截图。');
      await seedAttachment(
        id: 'att-answer-only',
        ownerType: 'question',
        ownerId: question.id,
        role: 'answer',
      );

      final result = await tool.run(invoke({'question_id': question.id}));

      expect(result.ok, isTrue);
      final model = result.modelResult! as Map<String, Object?>;
      expect(model['image_count'], 0);
      expect(model['answer_image_count'], 1);
      expect(result.summary, contains('答案/解析截图 1 张'));
      expect(result.summary, isNot(contains('配图 ')));
    });

    test('未知 role 两桶都不计，只数其它可用角色', () async {
      final question = await seedQuestion(stem: '以后新增的角色。');
      await seedAttachment(
        id: 'att-future',
        ownerType: 'question',
        ownerId: question.id,
        role: 'future_role',
      );
      await seedAttachment(
        id: 'att-stem',
        ownerType: 'question',
        ownerId: question.id,
        role: 'stem',
      );

      final result = await tool.run(invoke({'question_id': question.id}));

      expect(result.ok, isTrue);
      final model = result.modelResult! as Map<String, Object?>;
      expect(model['image_count'], 1);
      expect(model['answer_image_count'], 0);
      expect(result.summary, contains('配图 1 张'));
      expect(result.summary, isNot(contains('截图')));
    });
  });
}
