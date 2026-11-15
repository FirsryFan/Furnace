import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/ai_repository.dart';
import 'package:furnace/features/ai/domain/agent_loop.dart';
import 'package:furnace/features/ai/domain/approval_engine.dart';
import 'package:furnace/features/ai/domain/model_adapter.dart';
import 'package:furnace/features/ai/domain/tool_registry.dart';
import 'package:furnace/features/ai/infrastructure/fake_model_adapter.dart';

/// 思考模式与 `reasoning_content` 的接线（用户 2026-11-15 第 9 点）。
///
/// 选择 effort 会在请求里发送 `reasoning_effort`，同时把主 loop 切到思考模式；
/// 带 `tools` 的思考模式要求历史里的助手消息带回 `reasoning_content`，否则
/// provider 会拒绝请求。这两件事必须一起成立，所以要钉住：
///
///  * [ChatMessage] 没有思考时**不出现** `reasoning_content` 字段（默认请求体
///    与旧版一致）；
///  * `AgentLoop.echoReasoning` 打开时，库里已存的思考会回到历史；关闭时不回。
void main() {
  group('ChatMessage.reasoning_content', () {
    test('没有思考时不出现字段', () {
      const message = ChatMessage.assistant(content: '答案');
      expect(message.toJson().containsKey('reasoning_content'), isFalse);
      expect(message.toJson()['content'], '答案');
    });

    test('有思考时字段原文出现', () {
      const message = ChatMessage.assistant(
        content: '答案',
        reasoningContent: '先算动量',
      );
      expect(message.toJson()['reasoning_content'], '先算动量');
    });

    test('空串不带字段（空字段只会被 provider 读错）', () {
      const message = ChatMessage.assistant(content: '答案', reasoningContent: '');
      expect(message.toJson().containsKey('reasoning_content'), isFalse);
    });
  });

  group('AgentLoop 历史里的思考回传', () {
    late AppDatabase db;
    late AiRepository repository;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repository = AiRepository(db);
    });

    tearDown(() => db.close());

    /// 造一段历史：用户问 + 助手带思考回答，然后让 loop 再发一条消息。
    Future<List<ChatMessage>> historySeenByModel({required bool echo}) async {
      final conversation = await repository.createConversation();
      await repository.addMessage(
        conversationId: conversation.id,
        role: AiRepository.roleUser,
        content: '在吗',
      );
      await repository.addMessage(
        conversationId: conversation.id,
        role: AiRepository.roleAssistant,
        content: '在的',
        reasoning: '我先确认一下',
      );
      final adapter = FakeModelAdapter([FakeModelAdapter.answer('好的')]);
      final loop = AgentLoop(
        adapter: adapter,
        registry: ToolRegistry([]),
        approval: const ApprovalEngine(mode: AiPermissionMode.auto),
        repository: repository,
        db: db,
        echoReasoning: echo,
      );
      await loop.sendUserMessage(
        conversationId: conversation.id,
        text: '继续',
      );
      return adapter.requests.first.messages;
    }

    test('echoReasoning 打开：历史助手消息带回思考', () async {
      final messages = await historySeenByModel(echo: true);
      final assistant = messages.firstWhere(
        (message) =>
            message.role == 'assistant' && message.content == '在的',
      );
      expect(assistant.reasoningContent, '我先确认一下');
      expect(assistant.toJson()['reasoning_content'], '我先确认一下');
    });

    test('echoReasoning 关闭：历史与旧版请求体一致', () async {
      final messages = await historySeenByModel(echo: false);
      final assistant = messages.firstWhere(
        (message) =>
            message.role == 'assistant' && message.content == '在的',
      );
      expect(assistant.reasoningContent, isNull);
      expect(assistant.toJson().containsKey('reasoning_content'), isFalse);
    });
  });
}
