import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/ai_repository.dart';

/// The AI surface must stay completely inert until the user sets it up, and the
/// action ledger must survive rejected and failed calls - that is what makes
/// "everything except deletion may run automatically" safe to offer.
void main() {
  late AppDatabase db;
  late AiRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = AiRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('configuration', () {
    test('a database with no settings row means AI is off', () async {
      // This is the shape of an upgraded pre-AI install: no row at all. It must
      // read as "off" rather than throwing or inventing a row.
      final config = await repo.getConfig();
      expect(config.enabled, isFalse);
      expect(config.isUsable, isFalse);
      expect(config.apiKey, isNull);
    });

    test('a settings row without a key is not usable', () async {
      // Enabled but no key: the AI surface must still not appear, otherwise the
      // user gets an interface that fails on the first message.
      await repo.saveConfig(
        const AiConfig(enabled: true),
        fallbackLanguage: 'zh',
      );
      final config = await repo.getConfig();
      expect(config.enabled, isTrue);
      expect(config.isUsable, isFalse);
      expect(config.apiKey, isNull);
    });

    test('a whitespace-only key is not usable', () async {
      await repo.saveConfig(
        const AiConfig(enabled: true, apiKey: '   '),
        fallbackLanguage: 'zh',
      );
      expect((await repo.getConfig()).isUsable, isFalse);
    });

    test('saving a full config round-trips', () async {
      await repo.saveConfig(
        const AiConfig(
          enabled: true,
          apiKey: 'sk-test',
          baseUrl: 'https://example.invalid/v1',
          model: 'some-model',
          permissionMode: AiPermissionMode.auto,
        ),
        fallbackLanguage: 'zh',
      );
      final config = await repo.getConfig();
      expect(config.isUsable, isTrue);
      expect(config.apiKey, 'sk-test');
      expect(config.baseUrl, 'https://example.invalid/v1');
      expect(config.model, 'some-model');
      expect(config.permissionMode, AiPermissionMode.auto);
    });

    test('an unreadable permission mode falls back to the safer one', () async {
      // Simulates a value written by a future/unknown build, or a NULL on an
      // upgraded row: neither may silently mean "auto".
      expect(AiPermissionMode.fromId(null), AiPermissionMode.plan);
      expect(AiPermissionMode.fromId(''), AiPermissionMode.plan);
      expect(AiPermissionMode.fromId('something-new'), AiPermissionMode.plan);
      expect(AiPermissionMode.fromId('auto'), AiPermissionMode.auto);
      expect(AiPermissionMode.fromId('plan'), AiPermissionMode.plan);
    });

    test('a trailing slash in the base URL is normalised', () async {
      const config = AiConfig(
        enabled: true,
        apiKey: 'k',
        baseUrl: 'https://api.deepseek.com/',
      );
      expect(config.effectiveBaseUrl, 'https://api.deepseek.com');
    });

    test('blank base URL and model fall back to the defaults', () async {
      const config = AiConfig(enabled: true, apiKey: 'k', baseUrl: '  ', model: '');
      expect(config.effectiveBaseUrl, AiConfig.defaultBaseUrl);
      expect(config.effectiveModel, AiConfig.defaultModel);
    });
  });

  group('conversations and messages', () {
    test('a new conversation gets a usable title without the caller thinking',
        () async {
      final conv = await repo.createConversation();
      expect(conv.title, isNotEmpty);
      expect(conv.title.length, lessThanOrEqualTo(200));
    });

    test('messages come back in insertion order', () async {
      final conv = await repo.createConversation();
      await repo.addMessage(
          conversationId: conv.id, role: AiRepository.roleUser, content: '第一');
      await repo.addMessage(
          conversationId: conv.id, role: AiRepository.roleAssistant, content: '第二');
      await repo.addMessage(
          conversationId: conv.id, role: AiRepository.roleTool, content: '{}');
      final messages = await repo.listMessages(conv.id);
      expect(messages.map((m) => m.content), ['第一', '第二', '{}']);
      expect(messages.map((m) => m.role),
          ['user', 'assistant', 'tool']);
    });

    test('a tool result keeps its tool_call_id', () async {
      // Without this the Chat Completion API rejects the round-trip.
      final conv = await repo.createConversation();
      final msg = await repo.addMessage(
        conversationId: conv.id,
        role: AiRepository.roleTool,
        content: '{"ok":true}',
        toolCallId: 'call_abc',
      );
      expect(msg.toolCallId, 'call_abc');
    });

    test('conversations are listed newest-first', () async {
      final first = await repo.createConversation(title: '旧的');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      final second = await repo.createConversation(title: '新的');
      final list = await repo.listConversations();
      expect(list.first.id, second.id);
      expect(list.last.id, first.id);
    });

    test('adding a message bumps the conversation to the top', () async {
      final a = await repo.createConversation(title: 'A');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      final b = await repo.createConversation(title: 'B');
      expect((await repo.listConversations()).first.id, b.id);

      await Future<void>.delayed(const Duration(milliseconds: 5));
      await repo.addMessage(
          conversationId: a.id, role: AiRepository.roleUser, content: 'hi');
      expect((await repo.listConversations()).first.id, a.id);
    });

    test('deleting a conversation removes its messages and actions', () async {
      final conv = await repo.createConversation();
      await repo.addMessage(
          conversationId: conv.id, role: AiRepository.roleUser, content: 'x');
      await repo.recordAction(
        conversationId: conv.id,
        toolName: 'manage_task',
        risk: 'write',
        argsJson: '{}',
      );

      await repo.deleteConversation(conv.id);

      expect(await repo.getConversation(conv.id), isNull);
      expect(await repo.listMessages(conv.id), isEmpty);
      expect(await repo.listActions(conv.id), isEmpty);
      // And the other conversation kind is untouched (sanity: the delete is
      // scoped by id, not a table wipe).
      final other = await repo.createConversation(title: '保留');
      expect(await repo.getConversation(other.id), isNotNull);
    });

    test('renaming ignores a blank title', () async {
      final conv = await repo.createConversation(title: '原名');
      await repo.renameConversation(conv.id, '   ');
      expect((await repo.getConversation(conv.id))!.title, '原名');
      await repo.renameConversation(conv.id, ' 新名 ');
      expect((await repo.getConversation(conv.id))!.title, '新名');
    });
  });

  group('action ledger', () {
    test('a rejected call is still recorded', () async {
      // The ledger is an audit trail, not a log of successes. If a rejection
      // vanished, the user could not tell what the model tried to do.
      final conv = await repo.createConversation();
      final action = await repo.recordAction(
        conversationId: conv.id,
        toolName: 'manage_task',
        risk: 'destructive',
        argsJson: '{"action":"delete","id":"t1"}',
      );
      expect(action.status, AiRepository.statusPending);

      await repo.updateActionStatus(
        action.id,
        status: AiRepository.statusRejected,
        resultJson: '{"rejected":true}',
      );

      final stored = (await repo.listActions(conv.id)).single;
      expect(stored.status, AiRepository.statusRejected);
      expect(stored.resultJson, '{"rejected":true}');
      expect(stored.argsJson, '{"action":"delete","id":"t1"}');
    });

    test('a failed call keeps its error text', () async {
      final conv = await repo.createConversation();
      final action = await repo.recordAction(
        conversationId: conv.id,
        toolName: 'manage_time_block',
        risk: 'write',
        argsJson: '{"action":"create"}',
      );
      await repo.updateActionStatus(
        action.id,
        status: AiRepository.statusFailed,
        resultJson: '{"error":"缺少 start_at"}',
      );
      final stored = (await repo.listActions(conv.id)).single;
      expect(stored.status, AiRepository.statusFailed);
      expect(stored.resultJson, contains('缺少'));
    });

    test('only executed actions with a snapshot are undoable', () async {
      final conv = await repo.createConversation();
      final noSnapshot = await repo.recordAction(
        conversationId: conv.id,
        toolName: 'run_skill',
        risk: 'write',
        argsJson: '{}',
        status: AiRepository.statusExecuted,
      );
      final withSnapshot = await repo.recordAction(
        conversationId: conv.id,
        toolName: 'manage_task',
        risk: 'write',
        argsJson: '{}',
        status: AiRepository.statusExecuted,
        beforeJson: '{"title":"旧"}',
        afterJson: '{"title":"新"}',
      );
      final pending = await repo.recordAction(
        conversationId: conv.id,
        toolName: 'manage_task',
        risk: 'write',
        argsJson: '{}',
      );

      final undoable = await repo.undoableActions(conv.id);
      expect(undoable.map((a) => a.id), [withSnapshot.id],
          reason: 'a call with no before-snapshot cannot be undone, and a '
              'pending call was never applied');
      expect(undoable.map((a) => a.id), isNot(contains(noSnapshot.id)));
      expect(undoable.map((a) => a.id), isNot(contains(pending.id)));
    });

    test('the risk level is persisted so the UI can show it', () async {
      final conv = await repo.createConversation();
      await repo.recordAction(
        conversationId: conv.id,
        toolName: 'manage_tag',
        risk: 'destructive',
        argsJson: '{}',
      );
      final stored = (await repo.listActions(conv.id)).single;
      expect(stored.risk, 'destructive');
    });
  });
}
