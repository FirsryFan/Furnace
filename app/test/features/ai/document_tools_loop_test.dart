// The registry entry and the agent-loop side of `create_document`.
//
// Two things only a running loop can show:
//
//   * the tool is registered as a `write` that claims to be `reversible`, which
//     is what lets the approval engine run it without asking (AI_DESIGN D13b);
//   * the undo switch in `agent_loop.dart` reaches this tool, so the file really
//     disappears when the user clicks 撤销.
//
// The loop builds its own tool instance and its undo helper resolves the app
// support directory itself, so the `path_provider` method channel is mocked to
// point both of them at a temp directory instead of the real app data folder.
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/ai_repository.dart';
import 'package:furnace/data/repositories/anki_repository.dart';
import 'package:furnace/data/repositories/tag_repository.dart';
import 'package:furnace/data/repositories/task_repository.dart';
import 'package:furnace/data/repositories/time_block_repository.dart';
import 'package:furnace/features/ai/domain/agent_loop.dart';
import 'package:furnace/features/ai/domain/ai_tool.dart';
import 'package:furnace/features/ai/domain/approval_engine.dart';
import 'package:furnace/features/ai/domain/tool_registry.dart';
import 'package:furnace/features/ai/infrastructure/fake_model_adapter.dart';
import 'package:furnace/features/ai/tools/document_tools.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugins.flutter.io/path_provider');

  late Directory supportDir;
  late AppDatabase db;
  late AiRepository repository;

  setUp(() {
    supportDir = Directory.systemTemp.createTempSync('furnace_documents_loop_');
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repository = AiRepository(db);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      channel,
      (call) async => call.method == 'getApplicationSupportDirectory'
          ? supportDir.path
          : null,
    );
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await db.close();
    if (supportDir.existsSync()) {
      supportDir.deleteSync(recursive: true);
    }
  });

  Directory documentsDir() =>
      Directory(p.join(supportDir.path, CreateDocumentTool.directoryName));

  List<File> filesIn(Directory dir) =>
      dir.existsSync() ? dir.listSync().whereType<File>().toList() : const [];

  group('registration and classification', () {
    test('it is a registered write that claims to be reversible', () {
      final registry = ToolRegistry.forApp(
        db: db,
        tasks: TaskRepository(db),
        blocks: TimeBlockRepository(db),
        anki: AnkiRepository(db),
        tags: TagRepository(db),
      );

      final registered = registry.byName(CreateDocumentTool.toolName);
      expect(registered, isA<CreateDocumentTool>());
      expect(
        registry.modelSpecs.map((spec) => spec.name),
        contains(CreateDocumentTool.toolName),
      );
      // The reversibility claim is what allows automatic execution at all
      // (D13b), so it is asserted rather than assumed.
      expect(registered!.riskFor(CreateDocumentTool.toolName), ToolRisk.write);
      expect(registered.reversibleFor(CreateDocumentTool.toolName), isTrue);
      expect(registered.readOnly, isFalse,
          reason: 'writing a file is not a read');
      expect(registered.availableOnCurrentPlatform, isTrue);
    });
  });

  group('through the agent loop', () {
    AgentLoop buildLoop(FakeModelAdapter adapter) => AgentLoop(
          adapter: adapter,
          // The default tool, exactly as the app builds it, so what this test
          // undoes is the same object the real registry holds.
          registry: ToolRegistry([CreateDocumentTool()]),
          approval: const ApprovalEngine(mode: AiPermissionMode.auto),
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

    test('the model is told about documents and can see the tool', () async {
      final adapter = FakeModelAdapter([FakeModelAdapter.answer('好。')]);
      final loop = buildLoop(adapter);
      final conversation = await repository.createConversation();

      await settle(
        loop,
        () => loop.sendUserMessage(conversationId: conversation.id, text: '你好'),
      );

      final first = adapter.requests.first;
      final system = first.messages
          .firstWhere((message) => message.role == 'system')
          .content!;
      // The rule is what keeps the model from answering "已发送给你" after a
      // tool that only wrote a file on this machine.
      expect(system, contains(CreateDocumentTool.toolName));
      expect(system, contains('不要声称已经发送'));
      expect(
        first.tools.map((spec) => spec.name),
        contains(CreateDocumentTool.toolName),
        reason: 'a rule about a tool the model cannot see is useless',
      );
    });

    test('auto mode writes the file, shows the path, and undo removes it',
        () async {
      const content = '# 复习提纲\n\n- 第一点\n';
      final adapter = FakeModelAdapter([
        FakeModelAdapter.callTool(
          CreateDocumentTool.toolName,
          {'title': '复习提纲', 'content': content},
          id: 'call_document',
        ),
        FakeModelAdapter.answer('已生成文档。'),
      ]);
      final loop = buildLoop(adapter);
      final conversation = await repository.createConversation();

      final state = await settle(
        loop,
        () => loop.sendUserMessage(
          conversationId: conversation.id,
          text: '把刚才的东西生成一份文档',
        ),
      );

      // write + reversible means no confirmation in auto mode (D12 v2).
      expect(state.hasPending, isFalse);
      final executed = state.executed.single;
      expect(executed.result.ok, isTrue);

      final path = (executed.result.modelResult! as Map)['path'] as String;
      expect(p.dirname(path), documentsDir().path);
      expect(File(path).readAsStringSync(), content);
      expect(executed.result.summary, contains(path),
          reason: 'the chat card is where the user copies the path from');

      await settle(
        loop,
        () => loop.undoExecuted(conversation.id, executed.actionId),
      );

      expect(File(path).existsSync(), isFalse,
          reason: 'the undo switch in agent_loop must reach this tool');
      expect(filesIn(documentsDir()), isEmpty);
    });
  });
}
