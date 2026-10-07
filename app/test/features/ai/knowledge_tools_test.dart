// The write half of "look at this photo and make me 背诵卡片".
//
// The claims worth testing are the ones that decide whether the user ends up
// with usable cards:
//
//   * one knowledge point per call, and one card template per requested card,
//     with the card states that make them reviewable at all;
//   * a call with no usable card still leaves the user something to review, or
//     fails *before* creating anything;
//   * a bad call is a readable tool error and touches nothing;
//   * under 按计划 mode nothing is written until the user approves, and the
//     result can be undone afterwards.
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/ai_repository.dart';
import 'package:furnace/data/repositories/anki_repository.dart';
import 'package:furnace/domain/services/cloze/cloze_generator.dart';
import 'package:furnace/features/ai/domain/agent_loop.dart';
import 'package:furnace/features/ai/domain/ai_tool.dart';
import 'package:furnace/features/ai/domain/approval_engine.dart';
import 'package:furnace/features/ai/domain/tool_registry.dart';
import 'package:furnace/features/ai/infrastructure/fake_model_adapter.dart';
import 'package:furnace/features/ai/tools/knowledge_tools.dart';

void main() {
  late AppDatabase db;
  late AnkiRepository anki;
  late CreateKnowledgeCardsTool tool;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    anki = AnkiRepository(db);
    tool = CreateKnowledgeCardsTool(anki);
  });

  tearDown(() async {
    await db.close();
  });

  ToolInvocation invoke(Map<String, Object?> args) => ToolInvocation(
        toolName: CreateKnowledgeCardsTool.toolName,
        action: CreateKnowledgeCardsTool.toolName,
        arguments: args,
      );

  Future<List<CardTemplate>> storedTemplates() async {
    final points = await anki.getKnowledgePoints();
    if (points.isEmpty) {
      return const [];
    }
    return anki.getTemplatesForKnowledgePoint(points.single.id);
  }

  group('risk and reversibility', () {
    test('it is a write that claims to be reversible', () {
      // The reversibility claim is what allows automatic execution at all
      // (AI_DESIGN D13b), so it is asserted rather than assumed.
      expect(tool.riskFor(CreateKnowledgeCardsTool.toolName), ToolRisk.write);
      expect(tool.reversibleFor(CreateKnowledgeCardsTool.toolName), isTrue);
      expect(tool.availableOnCurrentPlatform, isTrue);
    });

    test('the description tells the model when to use it', () {
      // The photo-to-cards flow depends on the model choosing this tool, so the
      // description has to name the situation and the language rule.
      expect(tool.description, contains('照片'));
      expect(tool.description, contains('背诵卡片'));
      expect(tool.description, contains('语言'));
    });
  });

  group('happy path', () {
    test('it creates exactly one knowledge point and one card per request',
        () async {
      final result = await tool.run(invoke({
        'title': '光合作用的光反应',
        'content': '光反应在类囊体薄膜上进行，产物是 ATP 和 NADPH。',
        'source': '课本 P32',
        'cards': [
          {
            'question': '光反应在哪里进行？',
            'answer': '类囊体薄膜',
            'type': 'fill_blank',
          },
          {
            'question': '光反应的产物是什么？',
            'answer': 'ATP 和 NADPH',
          },
        ],
      }));

      expect(result.ok, isTrue);
      final points = await anki.getKnowledgePoints();
      expect(points, hasLength(1));
      expect(points.single.title, '光合作用的光反应');
      expect(points.single.content, contains('类囊体'));
      expect(points.single.source, '课本 P32');

      final templates = await storedTemplates();
      expect(templates.map((t) => t.type), ['fill_blank', 'essay'],
          reason: 'an omitted type is a question/answer pair (大题)');
      expect(templates.map((t) => t.question), [
        '光反应在哪里进行？',
        '光反应的产物是什么？',
      ]);
      expect(templates.first.clozeTemplate, '光反应在哪里进行？',
          reason: 'a fill_blank needs its cloze text, or review cannot render it');

      // Every card must have a state, or it is invisible to the review queue -
      // i.e. the user would see cards that never come up.
      for (final template in templates) {
        final states = await (db.select(db.cardStates)
              ..where((t) => t.cardTemplateId.equals(template.id)))
            .get();
        expect(states, hasLength(1));
      }
    });

    test('the result names the ids the model can refer to later', () async {
      final result = await tool.run(invoke({
        'title': '细胞',
        'content': '细胞是生命活动的基本单位。',
        'cards': [
          {'question': '生命活动的基本单位是？', 'answer': '细胞'},
        ],
      }));

      final payload = result.modelResult as Map<String, Object?>;
      final point = (await anki.getKnowledgePoints()).single;
      expect(payload['knowledge_point_id'], point.id);
      expect(payload['card_count'], 1);
      final ids = [
        for (final card in payload['cards'] as List) (card as Map)['id'],
      ];
      expect(ids, [(await storedTemplates()).single.id]);
    });
  });

  group('the auto-generated fallback', () {
    test('no cards means a fill-blank card made from the content', () async {
      final result = await tool.run(invoke({
        'title': '细胞',
        'content': '细胞是生命活动的基本单位。',
      }));

      expect(result.ok, isTrue);
      final templates = await storedTemplates();
      expect(templates, hasLength(1));
      expect(templates.single.type, 'fill_blank');
      expect(templates.single.question, contains(ClozeGenerator.blankMarker));
      expect(templates.single.answer, isNotEmpty);
      expect((result.modelResult as Map)['auto_generated_card'], isTrue);
    });

    test('content with nothing to blank out fails before creating anything',
        () async {
      // The important half of this test is the second assertion: a knowledge
      // point with no card can never be reviewed, so refusing must not leave one
      // behind.
      final result = await tool.run(invoke({
        'title': 'T',
        'content': 'plain text without a pattern',
      }));

      expect(result.ok, isFalse);
      expect(result.error, contains('cards'));
      expect(await anki.getKnowledgePoints(), isEmpty);
      expect(await db.select(db.cardTemplates).get(), isEmpty);
    });
  });

  group('bad arguments touch nothing', () {
    test('a missing title is a readable failure', () async {
      final result = await tool.run(invoke({'content': 'x'}));
      expect(result.ok, isFalse);
      expect(result.error, contains('title'));
      expect(await anki.getKnowledgePoints(), isEmpty);
    });

    test('cards that are not a list are refused', () async {
      final result = await tool.run(invoke({
        'title': 'T',
        'content': 'C',
        'cards': 'not-a-list',
      }));
      expect(result.ok, isFalse);
      expect(result.error, contains('数组'));
      expect(await anki.getKnowledgePoints(), isEmpty);
    });

    test('a card missing its answer is named by index, and nothing is written',
        () async {
      final result = await tool.run(invoke({
        'title': 'T',
        'content': 'C',
        'cards': [
          {'question': 'ok', 'answer': 'ok'},
          {'question': 'missing answer'},
        ],
      }));
      expect(result.ok, isFalse);
      expect(result.error, contains('cards[1]'));
      expect(await anki.getKnowledgePoints(), isEmpty,
          reason: 'the first card was valid but the call as a whole was not - a '
              'partial write would make "2 cards created" a lie');
    });

    test('an unknown card type lists what is allowed', () async {
      final result = await tool.run(invoke({
        'title': 'T',
        'content': 'C',
        'cards': [
          {'question': 'q', 'answer': 'a', 'type': 'telepathy'},
        ],
      }));
      expect(result.ok, isFalse);
      expect(result.error, contains('fill_blank'));
      expect(await anki.getKnowledgePoints(), isEmpty);
    });
  });

  group('through the agent loop', () {
    late AiRepository repository;
    late ToolRegistry registry;

    setUp(() {
      repository = AiRepository(db);
      registry = ToolRegistry([CreateKnowledgeCardsTool(anki)]);
    });

    AgentLoop buildLoop(
      FakeModelAdapter adapter, {
      AiPermissionMode mode = AiPermissionMode.auto,
    }) =>
        AgentLoop(
          adapter: adapter,
          registry: registry,
          approval: ApprovalEngine(mode: mode),
          repository: repository,
          db: db,
        );

    Future<AgentTurnState> settle(
      AgentLoop loop,
      Future<void> Function() action,
    ) async {
      final states = <AgentTurnState>[];
      final sub = loop.states.listen(states.add);
      await action();
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      return states.isEmpty ? loop.state : states.last;
    }

    test('plan mode waits for the approval before writing', () async {
      final adapter = FakeModelAdapter([
        FakeModelAdapter.callTool(
          CreateKnowledgeCardsTool.toolName,
          {
            'title': '等确认',
            'content': '细胞是生命活动的基本单位。',
          },
          id: 'call_cards',
        ),
        FakeModelAdapter.answer('做好了。'),
      ]);
      final loop = buildLoop(adapter, mode: AiPermissionMode.plan);
      final conversation = await repository.createConversation();

      final pending = await settle(
        loop,
        () => loop.sendUserMessage(
          conversationId: conversation.id,
          text: '把这张照片做成背诵卡片',
        ),
      );

      expect(pending.hasPending, isTrue);
      expect(pending.pending.single.tool.name,
          CreateKnowledgeCardsTool.toolName);
      expect(pending.pending.single.decision.disposition.name, 'batchApproval');
      expect(await anki.getKnowledgePoints(), isEmpty,
          reason: 'nothing may be written before the user approves');

      final done = await settle(
        loop,
        () => loop.approvePending(conversation.id),
      );

      expect(done.hasPending, isFalse);
      final templates = await storedTemplates();
      expect(templates, hasLength(1));
      expect(templates.single.type, 'fill_blank');
    });

    test('an executed call can be undone, cards and states included', () async {
      final adapter = FakeModelAdapter([
        FakeModelAdapter.callTool(
          CreateKnowledgeCardsTool.toolName,
          {
            'title': '可撤销',
            'content': '细胞是生命活动的基本单位。',
            'cards': [
              {'question': '基本单位？', 'answer': '细胞'},
            ],
          },
        ),
        FakeModelAdapter.answer('好了。'),
      ]);
      final loop = buildLoop(adapter);
      final conversation = await repository.createConversation();

      final state = await settle(
        loop,
        () => loop.sendUserMessage(
          conversationId: conversation.id,
          text: '做成卡片',
        ),
      );

      final executed = state.executed.single;
      expect(executed.result.ok, isTrue);
      expect(executed.result.isUndoable, isTrue,
          reason: 'the UI only offers undo when the ledger holds a snapshot');
      expect(await anki.getKnowledgePoints(), hasLength(1));

      await settle(
        loop,
        () => loop.undoExecuted(conversation.id, executed.actionId),
      );

      expect(await anki.getKnowledgePoints(), isEmpty);
      expect(await db.select(db.cardTemplates).get(), isEmpty);
      expect(await db.select(db.cardStates).get(), isEmpty);
    });

    test('a rejected call leaves the database alone and tells the model',
        () async {
      final adapter = FakeModelAdapter([
        FakeModelAdapter.callTool(
          CreateKnowledgeCardsTool.toolName,
          {'title': '别建', 'content': '细胞是生命活动的基本单位。'},
          id: 'call_cards',
        ),
        FakeModelAdapter.answer('好，不建了。'),
      ]);
      final loop = buildLoop(adapter, mode: AiPermissionMode.plan);
      final conversation = await repository.createConversation();

      await settle(
        loop,
        () => loop.sendUserMessage(conversationId: conversation.id, text: 'x'),
      );
      await settle(loop, () => loop.rejectPending(conversation.id));

      expect(await anki.getKnowledgePoints(), isEmpty);
      final reply = (await repository.listMessages(conversation.id))
          .lastWhere((m) => m.role == AiRepository.roleTool);
      expect(reply.content, contains('拒绝'));
    });
  });

  group('the undo helper', () {
    test('it refuses a snapshot with no knowledge point id', () async {
      expect(
        await deleteCreatedKnowledgeCards(db, const {'template_ids': []}),
        isFalse,
      );
      expect(
        await deleteCreatedKnowledgeCards(db, const {}),
        isFalse,
      );
    });

    test('it removes a point created by hand with its state rows', () async {
      final point = await anki.createKnowledgePoint(
        title: '手写的',
        content: '细胞是生命活动的基本单位。',
      );
      final template = await anki.createTemplate(
        knowledgePointId: point.id,
        type: 'essay',
        question: 'q',
        answer: 'a',
      );
      final state = await anki.getOrCreateCardState(template.id);
      await db.into(db.reviewLogs).insert(
            ReviewLogsCompanion.insert(
              id: 'log-1',
              cardStateId: state.id,
              cardTemplateId: Value(template.id),
              rating: 2,
              reviewedAt: 1,
              createdAt: 1,
            ),
          );

      final removed = await deleteCreatedKnowledgeCards(db, {
        'knowledge_point_id': point.id,
        'template_ids': [template.id],
      });

      expect(removed, isTrue);
      expect(await anki.getKnowledgePoints(), isEmpty);
      expect(await db.select(db.cardTemplates).get(), isEmpty);
      expect(await db.select(db.cardStates).get(), isEmpty);
      expect(await db.select(db.reviewLogs).get(), isEmpty,
          reason: 'a leftover review log would point at a card that is gone');
    });
  });
}
