import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/ai_repository.dart';
import 'package:furnace/data/repositories/anki_repository.dart';
import 'package:furnace/data/repositories/review_plan_repository.dart';
import 'package:furnace/data/repositories/tag_repository.dart';
import 'package:furnace/features/ai/domain/agent_loop.dart';
import 'package:furnace/features/ai/domain/approval_engine.dart';
import 'package:furnace/features/ai/domain/model_adapter.dart';
import 'package:furnace/features/ai/domain/tool_registry.dart';
import 'package:furnace/features/ai/infrastructure/fake_model_adapter.dart';
import 'package:furnace/features/ai/tools/card_group_tools.dart';

/// The two card-group tools are writes, and every write the model makes has to be
/// undoable through the same ledger UI the other tools use. `card_group_tools_test`
/// covers the tools themselves; this file covers the loop wiring: a missing
/// `_isCreate`/`_deleteCreated` case would leave the link or the plan behind even
/// though the tool reports "已撤销".
void main() {
  late AppDatabase db;
  late TagRepository tags;
  late AnkiRepository anki;
  late AiRepository repository;
  late ToolRegistry registry;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    tags = TagRepository(db);
    anki = AnkiRepository(db);
    repository = AiRepository(db);
    registry = ToolRegistry([
      LinkCardTagsTool(db: db, anki: anki, tags: tags),
      ManageReviewPlanTool(
        tags: tags,
        plans: ReviewPlanRepository(db, anki),
      ),
    ]);
  });

  tearDown(() async {
    await db.close();
  });

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

  /// Runs one user turn scripted by [turns] and returns what the loop settled on.
  Future<({AgentTurnState state, String conversationId, AgentLoop loop})>
      runTurn(List<List<ModelEvent>> turns) async {
    final loop = AgentLoop(
      adapter: FakeModelAdapter(turns),
      registry: registry,
      approval: const ApprovalEngine(mode: AiPermissionMode.auto),
      repository: repository,
      db: db,
    );
    final conversation = await repository.createConversation();
    final state = await settle(
      loop,
      () => loop.sendUserMessage(conversationId: conversation.id, text: 'x'),
    );
    return (state: state, conversationId: conversation.id, loop: loop);
  }

  group('link_card_tags through the loop', () {
    test('the links land and undo removes exactly them', () async {
      await tags.createTag(name: '生物');
      final one = await anki.createKnowledgePoint(title: '细胞膜', content: '正文');
      final two = await anki.createKnowledgePoint(title: '细胞核', content: '正文');

      final turn = await runTurn([
        FakeModelAdapter.callTool('link_card_tags', {
          'tag': '生物',
          'card_ids': [one.id, two.id],
        }),
        FakeModelAdapter.answer('挂好了。'),
      ]);

      expect(turn.state.executed.single.result.ok, isTrue);
      expect(await db.select(db.objectTags).get(), hasLength(2));

      await settle(
        turn.loop,
        () => turn.loop.undoExecuted(
          turn.conversationId,
          turn.state.executed.single.actionId,
        ),
      );
      expect(
        await db.select(db.objectTags).get(),
        isEmpty,
        reason: 'undo of link_card_tags must remove the links it added',
      );
    });

    test('a dry-run preview leaves nothing for undo to do', () async {
      await tags.createTag(name: '生物');
      await anki.createKnowledgePoint(title: '细胞膜', content: '正文');

      final turn = await runTurn([
        FakeModelAdapter.callTool(
            'link_card_tags', {'from_source_paths': true}),
        FakeModelAdapter.answer('先看看。'),
      ]);

      expect(turn.state.executed.single.result.ok, isTrue);
      expect(await db.select(db.objectTags).get(), isEmpty);
      // No write happened, so the ledger records no undo snapshot.
      expect(turn.state.executed.single.result.afterJson, isNull);
    });
  });

  group('manage_review_plan through the loop', () {
    test('the plan is set, and undo clears a first-time plan', () async {
      await tags.createTag(name: '生物');

      final turn = await runTurn([
        FakeModelAdapter.callTool('manage_review_plan', {
          'action': 'set',
          'tag': '生物',
          'new_cards_per_day': 20,
          'review_cards_per_day': 0,
        }),
        FakeModelAdapter.answer('设好了。'),
      ]);

      expect(turn.state.executed.single.result.ok, isTrue);
      var plans = await ReviewPlanRepository(db, anki).groupPlans();
      expect(plans.single.newCardsPerDay, 20);

      await settle(
        turn.loop,
        () => turn.loop.undoExecuted(
          turn.conversationId,
          turn.state.executed.single.actionId,
        ),
      );
      plans = await ReviewPlanRepository(db, anki).groupPlans();
      expect(plans, isEmpty, reason: 'no plan existed before this call');
    });
  });
}
