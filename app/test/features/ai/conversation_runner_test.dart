import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/ai_repository.dart';
import 'package:furnace/features/ai/application/conversation_runner.dart';
import 'package:furnace/features/ai/application/student_mode_controller.dart';
import 'package:furnace/features/ai/domain/agent_loop.dart';
import 'package:furnace/features/ai/domain/agent_preset.dart';
import 'package:furnace/features/ai/domain/approval_engine.dart';
import 'package:furnace/features/ai/domain/model_adapter.dart';
import 'package:furnace/features/ai/domain/student_answer_sheet.dart';
import 'package:furnace/features/ai/domain/student_run.dart';
import 'package:furnace/features/ai/domain/student_solver.dart';
import 'package:furnace/features/ai/domain/tool_registry.dart';
import 'package:furnace/features/ai/domain/verifier.dart';
import 'package:furnace/features/ai/infrastructure/agent_run_store.dart';
import 'package:furnace/features/ai/infrastructure/ai_attachment_store.dart';
import 'package:furnace/features/ai/infrastructure/fake_model_adapter.dart';
import 'package:furnace/features/ai/infrastructure/student_trace_store.dart';

/// The preset router: which path a message takes, and the proof that the
/// student preset never reaches the main agent.
///
/// The student cases use a main-agent runner that **throws if called**, so a
/// routing regression fails loudly instead of being invisible behind an empty
/// request list. The student preset now runs the `StudentRun` state machine
/// (design §3.2): one solve turn + one content-verification turn, then the
/// answer sheet and the run/steps/verifications rows are persisted.
void main() {
  late AppDatabase db;
  late AiRepository repository;
  late FakeModelAdapter studentAdapter;
  late StudentModeController studentMode;
  late Directory tempDir;

  /// solve 回合：直接写出一份结构化答案卡。
  List<ModelEvent> solveTurn() => [
        const ModelTextDelta(
          '【题型】解答题\n'
          '【答案】(1) g sinθ\n'
          '【过程】由牛顿第二定律得 a=g sinθ。',
        ),
        const ModelTurnDone(
          finishReason: 'stop',
          promptTokens: 120,
          completionTokens: 30,
        ),
      ];

  /// 内容验证回合：独立模型调用返回 pass。
  List<ModelEvent> verifierPassTurn() => [
        const ModelTextDelta(
          '{"verdict":"pass","issues":[],"evidence":{"checked":true},"confidence":0.9}',
        ),
        const ModelTurnDone(finishReason: 'stop', completionTokens: 12),
      ];

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repository = AiRepository(db);
    studentAdapter = FakeModelAdapter([
      solveTurn(),
      verifierPassTurn(),
    ]);
    tempDir = await Directory.systemTemp.createTemp('furnace-preset-run-');
    studentMode = StudentModeController(
      solver: StudentSolver(reasonAdapter: studentAdapter),
      traceStore: const _StubTraceStore(),
      recorder: AgentRunStoreRecorder(AgentRunStore(db)),
    );
  });

  tearDown(() async {
    await db.close();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('startStudentSession', () {
    test('creates a student-preset session and answers without the main agent',
        () async {
      final mainAgent = _ExplodingMainAgent();
      final runner = ConversationRunner(
        repository: repository,
        mainAgent: mainAgent,
        studentMode: studentMode,
      );

      final result = await runner.startStudentSession(
        question: '求加速度',
        subagentPreset: SubagentPreset.studentSolver,
      );

      // The routing proof: the main-agent runner was never reached.
      expect(mainAgent.calls, 0);

      // A top-level student session was created with the preset recorded.
      final conversation =
          await repository.getConversation(result.userMessage.conversationId);
      expect(conversation, isNotNull);
      expect(conversation!.agentPresetId, 'student_solver');
      expect(conversation.subagentPresetId, 'student_solver');

      // The student pipeline ran: one solve turn + one verification turn,
      // both with no tools.
      expect(studentAdapter.requests, hasLength(2));
      expect(studentAdapter.requests.first.tools, isEmpty);
      expect(studentAdapter.requests.last.tools, isEmpty);
      expect(
        studentAdapter.requests.first.messages.last.content,
        '求加速度',
        reason: 'the question is the solve turn input',
      );
      expect(
        studentAdapter.requests.last.messages.last.content,
        contains('候选答案卡'),
        reason: 'the second turn is the independent content verifier',
      );

      // The result carries the structured answer sheet and the state machine.
      expect(result.usedStudentSolver, isTrue);
      expect(result.studentOutcome!.ok, isTrue);
      expect(result.studentOutcome!.verified, isTrue);
      expect(result.studentOutcome!.answerSheet.kind,
          StudentQuestionKind.solution);
      expect(result.studentOutcome!.answerSheet.process, contains('牛顿第二定律'));
      expect(result.studentRun, isNotNull);
      expect(result.studentRun!.stages, [
        StudentRunStage.solving,
        StudentRunStage.auditing,
        StudentRunStage.verifying,
        StudentRunStage.finalized,
      ]);
      expect(result.studentRun!.verdict, Verdict.pass);
      expect(result.studentRun!.repairCount, 0);

      // The session is now non-blank: preset locked, and the answer stored as
      // the answer sheet (not the raw model text / not a reasoning dump).
      expect(result.presets.locked, isTrue);
      final messages = await repository.listMessages(conversation.id);
      expect(messages.map((m) => m.role),
          [AiRepository.roleUser, AiRepository.roleAssistant]);
      expect(messages.first.content, '求加速度');
      expect(messages.last.content, contains('【题型】'));
      expect(messages.last.content, contains('【答案】'));
      expect(messages.last.content, contains('【过程】'));

      // DB: one run row with the structured answer sheet; raw answer text is
      // not persisted (design §5.1), the trace path is.
      final run = (await db.select(db.agentRuns).get()).single;
      expect(run.presetId, 'student_solver');
      expect(run.mode, 'student');
      expect(run.status, 'answered');
      expect(run.phase, 'present');
      expect(run.conversationId, conversation.id);
      expect(run.steps, 1);
      expect(run.verifierVerdict, 'pass');
      expect(run.answerSheetJson, isNotNull);
      expect(run.answerSheetJson, contains('"result"'));
      expect(run.answerSheetJson, isNot(contains('"raw"')));
      expect(run.tracePath, contains('student_solver_traces'));
      expect(run.processReportJson, isNotNull);
      expect(run.endedAt, isNotNull);

      // DB: model step + process audit + content verification.
      final steps = await db.select(db.agentSteps).get();
      expect(steps.map((step) => step.kind), containsAll(['model', 'verify']));
      expect(steps.where((step) => step.kind == 'model'), hasLength(1));

      final verifications = await db.select(db.agentVerifications).get();
      expect(verifications, hasLength(2));
      final content = verifications
          .singleWhere((row) => row.kind == VerifierKind.content.id);
      expect(content.verdict, 'pass');
      expect(content.independent, isTrue);
      expect(content.verifier, 'student_independent_v1');
      final process = verifications
          .singleWhere((row) => row.kind == VerifierKind.process.id);
      expect(process.independent, isFalse);
      expect(process.verifier, AgentRunStore.processAuditorId);
    });

    test('the session preset is immutable after the first run', () async {
      final runner = ConversationRunner(
        repository: repository,
        mainAgent: _ExplodingMainAgent(),
        studentMode: studentMode,
      );
      final result = await runner.startStudentSession(question: '题目');

      await expectLater(
        repository.setConversationPresets(
          conversationId: result.userMessage.conversationId,
          agentPreset: AgentPreset.assistant,
        ),
        throwsA(isA<ConversationPresetsLockedException>()),
      );
      expect(
        (await repository.getConversation(result.userMessage.conversationId))!
            .agentPresetChoice,
        AgentPreset.studentSolver,
      );
    });

    test('refuses to run a student session with no solver configured',
        () async {
      final runner = ConversationRunner(
        repository: repository,
        mainAgent: _ExplodingMainAgent(),
      );

      expect(
        () => runner.startStudentSession(question: '题目'),
        throwsA(isA<StateError>()),
      );
    });

    test('a verifier fail/unknown is never silently marked verified',
        () async {
      final adapter = FakeModelAdapter([
        solveTurn(),
        [
          const ModelTextDelta(
            '{"verdict":"unknown","issues":["信息不足，无法判断"],"confidence":0.1}',
          ),
          const ModelTurnDone(finishReason: 'stop'),
        ],
      ]);
      final controller = StudentModeController(
        solver: StudentSolver(reasonAdapter: adapter),
        traceStore: const _StubTraceStore(),
        recorder: AgentRunStoreRecorder(AgentRunStore(db)),
      );
      final runner = ConversationRunner(
        repository: repository,
        mainAgent: _ExplodingMainAgent(),
        studentMode: controller,
      );

      final result = await runner.startStudentSession(question: '题目');

      expect(result.studentRun!.verdict, Verdict.unknown);
      expect(result.studentOutcome!.verified, isFalse);
      expect(result.studentOutcome!.ok, isTrue,
          reason: 'the answer sheet is still kept even when unverified');
      final run = (await db.select(db.agentRuns).get()).single;
      expect(run.verifierVerdict, 'unknown');
      expect(run.status, 'answered');
      expect(run.answerSheetJson, contains('"result"'));
    });
  });

  group('sendUserMessage routing', () {
    test('a student-preset conversation answers directly', () async {
      final conversation = await repository.createConversation(
        agentPreset: AgentPreset.studentSolver,
      );
      final mainAgent = _ExplodingMainAgent();
      final runner = ConversationRunner(
        repository: repository,
        mainAgent: mainAgent,
        studentMode: studentMode,
      );

      final result = await runner.sendUserMessage(
        conversationId: conversation.id,
        text: '看图作答',
      );

      expect(mainAgent.calls, 0);
      expect(result.usedStudentSolver, isTrue);
      expect(result.studentRun, isNotNull);
      expect(studentAdapter.requests, hasLength(2));
      expect((await repository.listMessages(conversation.id)), hasLength(2));
      expect((await db.select(db.agentRuns).get()), hasLength(1));
    });

    test('an assistant-preset conversation goes to the main agent', () async {
      final conversation = await repository.createConversation();
      final mainAgent = _RecordingMainAgent(repository);
      final runner = ConversationRunner(
        repository: repository,
        mainAgent: mainAgent,
        studentMode: studentMode,
      );

      final result = await runner.sendUserMessage(
        conversationId: conversation.id,
        text: '普通消息',
      );

      expect(mainAgent.texts, ['普通消息']);
      expect(studentAdapter.requests, isEmpty,
          reason: 'the student solver must not run for the assistant preset');
      expect(result.usedStudentSolver, isFalse);
      expect(result.studentRun, isNull);
      expect(result.presets.agent, AgentPreset.assistant);
      expect(result.presets.locked, isTrue);
      expect(await db.select(db.agentRuns).get(), isEmpty,
          reason: 'the chat path is not instrumented by this task');
    });

    test('the main agent loop itself refuses a student-preset conversation',
        () async {
      // Defence in depth: even if a future caller wires the chat page straight
      // to AgentLoop, a student-preset session must not be answered by it.
      final conversation = await repository.createConversation(
        agentPreset: AgentPreset.studentSolver,
      );
      final loopAdapter = FakeModelAdapter([
        FakeModelAdapter.answer('主 agent 不应该回答'),
      ]);
      final loop = AgentLoop(
        adapter: loopAdapter,
        registry: ToolRegistry(const []),
        approval: const ApprovalEngine(mode: AiPermissionMode.plan),
        repository: repository,
        db: db,
      );
      addTearDown(loop.dispose);

      await loop.sendUserMessage(
        conversationId: conversation.id,
        text: '题目',
      );

      expect(loopAdapter.requests, isEmpty);
      expect(loop.state.error, contains('学生模式'));
      expect(await repository.listMessages(conversation.id), isEmpty,
          reason: 'the refused turn must not persist the question');
    });
  });

  group('images', () {
    test('a student session passes the attached picture to the solver',
        () async {
      final store = AiAttachmentStore(
        repository: repository,
        supportDirectory: () async => tempDir,
      );
      const relPath = 'ai_attachments/q.png';
      final file = File('${tempDir.path}/ai_attachments/q.png')
        ..createSync(recursive: true)
        ..writeAsBytesSync([1, 2, 3, 4]);
      final pending = PendingImage(
        relPath: relPath,
        absolutePath: file.path,
        mime: 'image/png',
        width: 10,
        height: 10,
      );
      final runner = ConversationRunner(
        repository: repository,
        mainAgent: _ExplodingMainAgent(),
        studentMode: studentMode,
        attachments: store,
      );

      final result = await runner.startStudentSession(
        question: '',
        images: [pending],
      );

      expect(result.studentOutcome!.imageCount, 1);
      expect(studentAdapter.requests, hasLength(2));
      expect(
        studentAdapter.requests.first.messages.last.images,
        hasLength(1),
        reason: 'the user never describes the figure in text; it is sent',
      );
      // The picture is registered against the message it arrived with, so the
      // conversation still owns it.
      expect(
        await repository.listMessageAttachments(result.userMessage.id),
        hasLength(1),
      );
    });
  });
}

/// A main-agent runner that must never be called by the student path.
class _ExplodingMainAgent implements StandardAgentRunner {
  int calls = 0;

  @override
  Future<void> sendUserMessage({
    required String conversationId,
    required String text,
    List<PendingImage> images = const [],
  }) async {
    calls++;
    throw StateError(
      'the main agent runner must not be called for the student preset',
    );
  }
}

/// A main-agent stand-in that behaves like the real loop's persistence step.
class _RecordingMainAgent implements StandardAgentRunner {
  _RecordingMainAgent(this._repository);

  final AiRepository _repository;
  final List<String> texts = [];

  @override
  Future<void> sendUserMessage({
    required String conversationId,
    required String text,
    List<PendingImage> images = const [],
  }) async {
    texts.add(text);
    await _repository.addMessage(
      conversationId: conversationId,
      role: AiRepository.roleUser,
      content: text,
    );
    await _repository.addMessage(
      conversationId: conversationId,
      role: AiRepository.roleAssistant,
      content: '主对话回答',
    );
  }
}

/// Reports a trace path without touching the disk; the real write is covered by
/// `student_mode_controller_test.dart`.
class _StubTraceStore implements StudentTraceStore {
  const _StubTraceStore();

  @override
  Future<String> save({
    required String question,
    required StudentSolverResult result,
    String? questionId,
  }) async {
    return '/virtual/student_solver_traces/trace.json';
  }
}
