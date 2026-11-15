import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/ai_repository.dart';
import 'package:furnace/features/ai/domain/agent_preset.dart';

/// Persistence + lock semantics for the agent/subagent preset of a session.
///
/// DSH semantics being pinned here:
///  * the preset is selected while the session is blank;
///  * it is immutable from the first message/run on;
///  * only the id is stored - there is no version, hash or definition snapshot,
///    and a NULL (row written before presets existed) reads as the shipped
///    default.
void main() {
  late AppDatabase db;
  late AiRepository repository;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repository = AiRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('createConversation', () {
    test('records the selected agent and subagent presets', () async {
      final conversation = await repository.createConversation(
        agentPreset: AgentPreset.studentSolver,
        subagentPreset: SubagentPreset.studentSolver,
      );

      expect(conversation.agentPresetId, 'student_solver');
      expect(conversation.subagentPresetId, 'student_solver');

      final state = await repository.presetStateFor(conversation.id);
      expect(state, isNotNull);
      expect(state!.agent, AgentPreset.studentSolver);
      expect(state.subagent, SubagentPreset.studentSolver);
      expect(state.isStudentMode, isTrue);
      expect(state.locked, isFalse);
    });

    test('defaults to the assistant preset and an inherited subagent',
        () async {
      final conversation = await repository.createConversation();

      expect(conversation.agentPresetId, AgentPreset.assistant.id);
      expect(conversation.subagentPresetId, isNull);
      final state = await repository.presetStateFor(conversation.id);
      expect(state!.agent, AgentPreset.assistant);
      expect(state.subagent, SubagentPreset.inherit);
      expect(state.locked, isFalse);
    });
  });

  group('setConversationPresets', () {
    test('can re-compose a blank session', () async {
      final conversation = await repository.createConversation();

      await repository.setConversationPresets(
        conversationId: conversation.id,
        agentPreset: AgentPreset.studentSolver,
      );

      final state = await repository.presetStateFor(conversation.id);
      expect(state!.agent, AgentPreset.studentSolver);
      expect(state.subagent, SubagentPreset.inherit);
      expect(state.locked, isFalse,
          reason:
              'selecting a preset is not a run; the session is still blank');
    });

    test('leaves the untouched side of the pair unchanged', () async {
      final conversation = await repository.createConversation(
        subagentPreset: SubagentPreset.studentSolver,
      );

      await repository.setConversationPresets(
        conversationId: conversation.id,
        agentPreset: AgentPreset.studentSolver,
      );

      final state = await repository.presetStateFor(conversation.id);
      expect(state!.subagent, SubagentPreset.studentSolver);
    });

    test('throws after the first message: the preset is immutable', () async {
      final conversation = await repository.createConversation();
      await repository.addMessage(
        conversationId: conversation.id,
        role: AiRepository.roleUser,
        content: '开始',
      );

      await expectLater(
        repository.setConversationPresets(
          conversationId: conversation.id,
          agentPreset: AgentPreset.studentSolver,
        ),
        throwsA(isA<ConversationPresetsLockedException>()),
      );

      // The stored preset did not change.
      final row = await repository.getConversation(conversation.id);
      expect(row!.agentPresetChoice, AgentPreset.assistant);
      expect(
          (await repository.presetStateFor(conversation.id))!.locked, isTrue);
    });

    test('rejects an unknown conversation', () async {
      expect(
        () => repository.setConversationPresets(
          conversationId: 'conv_missing',
          agentPreset: AgentPreset.studentSolver,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('legacy and unknown ids', () {
    test('a NULL preset column reads as assistant / inherit', () async {
      // What a conversation written before v44 looks like.
      await db.into(db.aiConversations).insert(
            AiConversationsCompanion.insert(
              id: 'conv_legacy',
              title: '旧对话',
              createdAt: 1,
              updatedAt: 1,
            ),
          );

      final state = await repository.presetStateFor('conv_legacy');
      expect(state!.agent, AgentPreset.assistant);
      expect(state.subagent, SubagentPreset.inherit);
      expect(state.locked, isFalse);
    });

    test('unknown stored ids fall back to the shipped defaults', () {
      expect(AgentPreset.fromId(null), AgentPreset.assistant);
      expect(AgentPreset.fromId('no_such_preset'), AgentPreset.assistant);
      expect(AgentPreset.fromId('student_solver'), AgentPreset.studentSolver);

      expect(SubagentPreset.fromId(null), SubagentPreset.inherit);
      expect(SubagentPreset.fromId('no_such_preset'), SubagentPreset.inherit);
      expect(SubagentPreset.fromId('student_solver'),
          SubagentPreset.studentSolver);
    });
  });
}
