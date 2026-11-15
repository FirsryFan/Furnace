import 'dart:convert';

import '../../../data/database/database.dart';
import '../../../data/repositories/question_repository.dart';
import '../../questions/data/question_media_store.dart';
import '../domain/ai_tool.dart';
import '../domain/model_adapter.dart';
import '../domain/student_solver.dart';
import '../domain/student_solver_context.dart';
import '../infrastructure/student_trace_store.dart';

/// Runs the app's isolated student-mode solver and returns its answer.
///
/// This is deliberately a tool, not a hidden second agent loop: the normal AI
/// conversation can ask for it when the user wants a clean, exam-style answer
/// instead of an explanation. It has no access to the question's stored answer
/// or solution — it receives only the stem and the stem images.
class SolveQuestionAsStudentTool extends AiTool {
  SolveQuestionAsStudentTool(
    this._solver, {
    AppDatabase? database,
    QuestionMediaStore? mediaStore,
    StudentTraceStore? traceStore,
    StudentSolverContext? context,
  })  : _database = database,
        _mediaStore = mediaStore ??
            (database == null ? null : QuestionMediaStore(database: database)),
        _traceStore = traceStore,
        _context = context;

  final StudentSolver _solver;
  final AppDatabase? _database;
  final QuestionMediaStore? _mediaStore;
  final StudentTraceStore? _traceStore;
  final StudentSolverContext? _context;

  static const String toolName = 'solve_question_as_student';

  @override
  String get name => toolName;

  @override
  String get description =>
      '用「学生模式」独立做一道题：只给题目文字/题干图，不给答案/解析，要求一次选定理解、只给最终答案，并按预算保留答案输出。'
      '适用于用户说「按学生方式做一遍 / 只要答案 / 别讲解 / 模拟考场」时。'
      '可以传 `question_id`（从题库读题干和题干图）或 `question`（直接给题面）。'
      '只读；不写库、不改题库；不返回完整思维链，只返回答案与用量摘要。';

  @override
  Map<String, Object?> get parameters => {
        'type': 'object',
        'properties': {
          'question_id': {
            'type': 'string',
            'description': '题库题目 id（TR-xxxxx）。给了它就从库里读题干与题干图。',
          },
          'question': {
            'type': 'string',
            'description': '直接给完整题目文字（可含小问）。不要附带答案或解析。',
          },
        },
        'required': <String>[],
      };

  @override
  ToolRisk riskFor(String action) => ToolRisk.write; // unused: no actions

  @override
  bool reversibleFor(String action) => true;

  @override
  bool get readOnly => true;

  @override
  bool get availableOnCurrentPlatform => true;

  @override
  Future<ToolResult> run(ToolInvocation invocation) async {
    final args = ToolArgs(invocation.arguments);
    final questionId = args.optString('question_id');
    var question = args.optString('question');
    final images = <ChatImagePart>[];

    if (questionId != null) {
      final db = _database;
      if (db == null) {
        throw ToolArgError('当前工具没有题库连接，不能按 question_id 读题');
      }
      final row = await QuestionRepository(db).byId(questionId);
      if (row == null) {
        return ToolResult.failure('题库里没有 id 为 `$questionId` 的题');
      }
      question = row.stem;
      final store = _mediaStore;
      if (store == null) {
        throw ToolArgError('当前工具没有题目图片存储，不能按 question_id 读图');
      }
      final stemImages = await store.list(row.id, role: QuestionImageRole.stem);
      for (final image in stemImages) {
        final bytes = await store.readBytes(image.relPath);
        if (bytes == null) {
          continue;
        }
        images.add(ChatImagePart(
          mime: image.mime ?? 'image/png',
          base64: base64Encode(bytes),
        ));
      }
    }

    if (question == null || question.trim().isEmpty) {
      throw ToolArgError('必须给 `question_id` 或 `question`');
    }
    if (questionId == null && _context != null) {
      images.addAll(_context.images);
    }

    final result = await _solver.solve(question: question, images: images);
    final payload = Map<String, Object?>.from(result.toModelJson());
    final traceStore = _traceStore;
    if (traceStore != null) {
      try {
        payload['trace_path'] = await traceStore.save(
          question: question,
          questionId: questionId,
          result: result,
        );
      } catch (error) {
        payload['trace_error'] = error.toString();
      }
    }

    if (!result.ok) {
      return ToolResult(
        ok: false,
        summary: '学生模式没有给出最终答案',
        modelResult: payload,
        error: result.error ?? 'no final answer',
      );
    }

    return ToolResult(
      ok: true,
      summary: '学生模式已作答：${_oneLine(result.answer)}',
      modelResult: payload,
    );
  }

  static String _oneLine(String text) {
    final value = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return value.length <= 120 ? value : '${value.substring(0, 120)}…';
  }
}
