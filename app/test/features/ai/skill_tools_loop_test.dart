/// What the agent loop does with a skill's declared tools.
///
/// Requirement: the same read of the skill directory that supplies the prompt
/// must supply the tools the model is offered, and a call must go through the
/// **normal** tool path - approval engine, `ai_actions` ledger, the conversation
/// - rather than a side door. These tests drive the real loop with a scripted
/// model, a real database and a real temporary skill directory, so what they
/// assert is what a user would get.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/ai_repository.dart';
import 'package:furnace/data/repositories/task_repository.dart';
import 'package:furnace/data/skill/skill_store.dart';
import 'package:furnace/domain/skill/skill_manifest.dart';
import 'package:furnace/features/ai/domain/agent_loop.dart';
import 'package:furnace/features/ai/domain/approval_engine.dart';
import 'package:furnace/features/ai/domain/tool_registry.dart';
import 'package:furnace/features/ai/infrastructure/fake_model_adapter.dart';
import 'package:furnace/features/ai/tools/task_tools.dart';

import '../../data/skill/skill_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory home;
  late AppDatabase db;
  late AiRepository repository;
  late SkillStore store;

  setUp(() {
    home = Directory.systemTemp.createTempSync('furnace_skill_loop');
    store = SkillStore(supportDirectory: () async => home);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repository = AiRepository(db);
  });

  tearDown(() async {
    await db.close();
    if (home.existsSync()) {
      home.deleteSync(recursive: true);
    }
  });

  /// A `.fskill` whose single tool runs a script that prints one JSON line.
  ///
  /// The script declares the one flag its tool schema describes, which is what
  /// makes `--subject` a legal argument: anything undeclared would be refused
  /// (that refusal has its own tests in `skill_runner_test.dart`).
  Uint8List skillPackage({String name = 'demo-skill'}) => buildSkillArchive(
        manifestJson: skillManifestJson(
          name: name,
          // No network and no host capability: those have their own refusals in
          // `skill_runner_test.dart`, and this fixture is about the routing.
          networkAllow: const [],
          permissions: const [],
          scripts: const [
            {
              'name': 'find_questions',
              'entry': 'scripts/find.mjs',
              'args': ['--subject'],
            },
          ],
        ),
        tools: {
          'find.json': skillToolJson(parameters: {
            'type': 'object',
            'properties': {
              'subject': {'type': 'string'},
            },
          }),
        },
        scripts: {
          'scripts/find.mjs': 'const argv = process.argv.slice(2);'
              'console.log(JSON.stringify({found: 1, argv}));\n',
        },
      );

  String toolNameFor(String skillName) => '${skillName}_find_questions';

  AgentLoop buildLoop(
    FakeModelAdapter adapter, {
    AiPermissionMode mode = AiPermissionMode.auto,
    SkillPlatform? platform = SkillPlatform.windows,
  }) =>
      AgentLoop(
        adapter: adapter,
        registry: ToolRegistry([QueryTasksTool(TaskRepository(db), db)]),
        approval: ApprovalEngine(mode: mode),
        repository: repository,
        db: db,
        skills: store,
        skillPlatform: platform,
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

  group('the tool list the model sees', () {
    test('an enabled skill contributes its declared tool', () async {
      await store.install(skillPackage());
      final adapter = FakeModelAdapter([FakeModelAdapter.answer('好')]);
      final loop = buildLoop(adapter);
      final conversation = await repository.createConversation();

      await settle(loop, () => loop.sendUserMessage(
          conversationId: conversation.id, text: 'hi'));

      final names = [for (final tool in adapter.requests.single.tools) tool.name];
      expect(names, contains(toolNameFor('demo-skill')));
      // The built-in tools are still there: skills add to the list, they do not
      // replace it.
      expect(names, contains('query_tasks'));
      final spec = adapter.requests.single.tools
          .firstWhere((tool) => tool.name == toolNameFor('demo-skill'));
      expect(spec.description, contains('scripts/find.mjs'));
      expect(spec.parameters['properties'], isA<Map>());
    });

    test('a disabled skill contributes neither tool nor prompt', () async {
      await store.install(skillPackage());
      await store.setEnabled('demo-skill', false);

      final adapter = FakeModelAdapter([FakeModelAdapter.answer('好')]);
      final loop = buildLoop(adapter);
      final conversation = await repository.createConversation();
      await settle(loop, () => loop.sendUserMessage(
          conversationId: conversation.id, text: 'hi'));

      final request = adapter.requests.single;
      expect([for (final tool in request.tools) tool.name],
          isNot(contains(toolNameFor('demo-skill'))));
      final system = request.messages.firstWhere((m) => m.role == 'system');
      expect(system.content, isNot(contains('demo-skill')),
          reason: 'the prompt and the tool list come from the same read');
    });

    test('on a platform without a Node runtime the tool is absent', () async {
      await store.install(skillPackage());
      final adapter = FakeModelAdapter([FakeModelAdapter.answer('好')]);
      final loop = buildLoop(adapter, platform: SkillPlatform.android);
      final conversation = await repository.createConversation();
      await settle(loop, () => loop.sendUserMessage(
          conversationId: conversation.id, text: 'hi'));

      final request = adapter.requests.single;
      expect([for (final tool in request.tools) tool.name],
          isNot(contains(toolNameFor('demo-skill'))),
          reason: '§5.5: absent, not failing when called');
      // Prompt-only skills keep working there, which is the other half of the
      // rule: the package still speaks to the model.
      final system = request.messages.firstWhere((m) => m.role == 'system');
      expect(system.content, contains('demo-skill'));
    });
  });

  group('a skill call goes through the normal tool path', () {
    test('it waits for the user, then runs and lands on the ledger', () async {
      await store.install(skillPackage());
      final adapter = FakeModelAdapter([
        FakeModelAdapter.callTool(
          toolNameFor('demo-skill'),
          {'subject': '物理'},
          id: 'call_skill',
        ),
        FakeModelAdapter.answer('找到了。'),
      ]);
      final loop = buildLoop(adapter);
      final conversation = await repository.createConversation();

      final pending = await settle(loop, () => loop.sendUserMessage(
          conversationId: conversation.id, text: '找几道物理题'));

      // Auto mode still asks: an unreversible skill script is never executed on
      // its own (spec §5.1 rule 2).
      expect(pending.hasPending, isTrue);
      final call = pending.pending.single;
      expect(call.decision.disposition, ToolDisposition.individualApproval);
      expect(call.decision.runsWithoutAsking, isFalse);
      expect(call.tool.name, toolNameFor('demo-skill'));

      // The proposal itself is already auditable, before anyone approved it.
      final proposed = await repository.listActions(conversation.id);
      expect(proposed.single.toolName, toolNameFor('demo-skill'));
      expect(proposed.single.risk, 'write');
      expect(proposed.single.argsJson, contains('物理'));
      expect(proposed.single.status, AiRepository.statusPending);

      final after = await settle(loop, () => loop.approvePending(conversation.id));
      expect(after.hasPending, isFalse);
      expect(after.executed, hasLength(1));
      expect(
        after.executed.single.result.ok,
        isTrue,
        reason: after.executed.single.summary,
      );

      // The ledger row the audit rule asks for: tool name, arguments, result,
      // risk - all in `ai_actions`, written by the loop and not by the runner.
      final actions = await repository.listActions(conversation.id);
      final action = actions.firstWhere((a) => a.toolCallId == 'call_skill');
      expect(action.status, AiRepository.statusExecuted);
      expect(action.risk, 'write');
      expect(action.argsJson, contains('物理'));
      final result = jsonDecode(action.resultJson!) as Map;
      expect(result['ok'], isTrue);
      final payload = result['result']! as Map;
      expect(payload['skill'], 'demo-skill');
      expect(payload['script'], 'scripts/find.mjs');
      expect(payload['exit_code'], 0);
      expect(payload['timed_out'], isFalse);
      expect(payload['stdout'], contains('"found":1'));
      // The argument the model sent reached the script as its own argv element:
      // the whole path runs, from the provider-facing declaration to a real
      // process, without an undeclared argument ever being possible.
      expect(payload['stdout'], contains('--subject'));
      expect(payload['stdout'], contains('物理'));

      // And the model was told what happened, in the turn it proposed.
      final reply = after.executed.single.result.toModelJson();
      expect(reply['ok'], isTrue);
      expect(reply['result'], isA<Map>());
    });

    test('a rejected skill call is recorded as rejected, and runs nothing',
        () async {
      await store.install(skillPackage());
      final adapter = FakeModelAdapter([
        FakeModelAdapter.callTool(
          toolNameFor('demo-skill'),
          {'subject': '物理'},
          id: 'call_skill',
        ),
      ]);
      final loop = buildLoop(adapter);
      final conversation = await repository.createConversation();

      await settle(loop, () => loop.sendUserMessage(
          conversationId: conversation.id, text: '找题'));
      final after = await settle(loop, () => loop.rejectPending(conversation.id));

      expect(after.executed, isEmpty);
      final actions = await repository.listActions(conversation.id);
      expect(actions.single.status, AiRepository.statusRejected);
    });

    test('a skill disabled between turns is unknown, not executed', () async {
      await store.install(skillPackage());
      await store.setEnabled('demo-skill', false);
      final adapter = FakeModelAdapter([
        // The model asks for a tool it saw in an earlier turn.
        FakeModelAdapter.callTool(toolNameFor('demo-skill'), const {}),
        FakeModelAdapter.answer('好'),
      ]);
      final loop = buildLoop(adapter);
      final conversation = await repository.createConversation();

      final state = await settle(loop, () => loop.sendUserMessage(
          conversationId: conversation.id, text: 'x'));

      expect(state.executed, isEmpty);
      final actions = await repository.listActions(conversation.id);
      expect(actions.single.status, AiRepository.statusFailed);
      expect(actions.single.resultJson, contains('未知工具 ${toolNameFor('demo-skill')}'));
    });
  });
}
