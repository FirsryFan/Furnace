import 'model_adapter.dart';
import 'student_answer_sheet.dart';

/// Which terminal state one student-mode solve reached.
enum StudentSolvePhase { answered, failed }

/// The result of one isolated student-mode solve.
///
/// The raw reasoning is kept in memory for the caller (the trace belongs to the
/// app, not to the model), but [toModelJson] deliberately omits it: feeding the
/// whole chain back into the conversation would double the token cost and make
/// the next turn treat old thinking as current evidence.
class StudentSolverResult {
  const StudentSolverResult({
    required this.phase,
    required this.answer,
    required this.answerSheet,
    required this.reasoning,
    required this.attempts,
    this.promptTokens,
    this.completionTokens,
    this.finishReason,
    this.error,
  });

  final StudentSolvePhase phase;
  final String answer;

  /// The same answer, parsed into the answer-sheet structure the caller needs:
  /// chosen option / final result / necessary working, never a bare essay.
  final StudentAnswerSheet answerSheet;

  /// Raw reasoning text from the reasoning turn(s). Kept for local trace only.
  final String reasoning;

  final int attempts;
  final int? promptTokens;
  final int? completionTokens;
  final String? finishReason;
  final String? error;

  bool get ok =>
      phase == StudentSolvePhase.answered && answer.trim().isNotEmpty;

  Map<String, Object?> toModelJson() => {
        'ok': ok,
        'answer': answer,
        'answer_sheet': answerSheet.toJson(),
        if (promptTokens != null) 'prompt_tokens': promptTokens,
        if (completionTokens != null) 'completion_tokens': completionTokens,
        if (finishReason != null) 'finish_reason': finishReason,
        'attempts': attempts,
        'reasoning_chars': reasoning.length,
        if (error != null) 'error': error,
      };
}

/// Runs a bounded, student-like solve with the same model adapter the app uses.
///
/// This is the Flutter-side counterpart of the Python `agent-core`: the model is
/// stateless; the local caller owns the prompt, the one-reading commit rule, the
/// answer reserve, and the trace.
class StudentSolver {
  StudentSolver({
    required this.reasonAdapter,
    this.answerAdapter,
    this.systemPrompt = defaultSystemPrompt,
    this.instructions = '',
  });

  final ModelAdapter reasonAdapter;

  /// Used only when the reasoning turn produced no usable answer. It must be
  /// configured with a small output budget; the reserve is what prevents the
  /// known failure where reasoning consumes the whole completion budget.
  final ModelAdapter? answerAdapter;

  final String systemPrompt;

  /// Optional content-specific answer convention supplied by the caller. The
  /// agent layer stays content-agnostic; the subject/paper policy lives here.
  final String instructions;

  static const String defaultSystemPrompt = '''
你是一名高三学生，正在考场做题。
你只能看到题目文字和题图，不能使用任何工具、文件、答案或解析。
读题后立即选定一个最自然的理解；如果发现题意有歧义，只允许写一句“我按……理解”，不得展开第二种解法，也不得把两种可能都列为答案。
最终答案只能给出一组。按题目要求作答：问大小就写大小，问方向就写方向，问矢量就写出矢量。
请把主要精力放在推导和最终答案上，思考过程尽量紧凑；最后完整写出各小问的答案。
若前面小问得到“A 或 B”等多个合法分支，后续每一问都必须逐个分支处理并说明取舍；不能只保留一个分支，除非明确写出排除理由。
每个最终答案/区间必须能由本小问前面写出的等式或不等式直接推出；不得在结尾引入前面没有出现的端点、数字或新条件。若推不出，明确写“未能确定”，不要填猜测值。
最多做一次自洽检查；不要反复自我怀疑，不要重开已定分支。

$answerSheetContract''';

  /// What the model must put on the answer sheet.
  ///
  /// This is a wire contract as much as a prompt: [StudentAnswerSheet.parse]
  /// reads exactly these markers, and every consumer of a solve (the direct
  /// student session, the compatibility tool, the trace) gets the parsed shape
  /// instead of having to guess where the answer is.
  static const String answerSheetContract = '''
输出只含答题卡内容（不是完整思维链，不写 meta 解释，不写“我在想/可能/也许”这类话）：
【题型】选择题 或 填空题 或 解答题（三选一）
【答案】最终结果。选择题先写选项字母，再写结果；填空题只写结果；解答题写出最终结论。
【过程】只有解答题写：写解题必需的步骤（列式、关键推导、结论），不要写完整推理草稿。''';

  static const String answerScribePrompt =
      '你是考场答题卡誊写员，只写答题卡。\n$answerSheetContract';

  String get _effectiveSystemPrompt {
    final extra = instructions.trim();
    return extra.isEmpty ? systemPrompt : '$systemPrompt\n\n$extra';
  }

  /// Solve [question] with at most one answer-reserve retry.
  Future<StudentSolverResult> solve({
    required String question,
    List<ChatImagePart> images = const [],
  }) async {
    final first = await _run(
      reasonAdapter,
      [
        ChatMessage.system(_effectiveSystemPrompt),
        ChatMessage.user(question, images: images),
      ],
    );

    if (first.text.trim().isNotEmpty && first.finishReason != 'length') {
      return StudentSolverResult(
        phase: StudentSolvePhase.answered,
        answer: first.text.trim(),
        answerSheet: StudentAnswerSheet.parse(first.text),
        reasoning: first.reasoning,
        attempts: 1,
        promptTokens: first.promptTokens,
        completionTokens: first.completionTokens,
        finishReason: first.finishReason,
      );
    }

    final draft = _tail(first.reasoning, 8000);
    final finalTurn = await _run(
      answerAdapter ?? reasonAdapter,
      [
        const ChatMessage.system(answerScribePrompt),
        ChatMessage.user(question, images: images),
        if (draft.isNotEmpty) ChatMessage.assistant(content: '草稿：\n$draft'),
        if (draft.isNotEmpty) const ChatMessage.user('根据上面的草稿，只写出最终答案；不要重新解题。'),
        if (draft.isEmpty) const ChatMessage.user('只写出最终答案；不要写推理过程。'),
      ],
    );

    final answer = finalTurn.text.trim();
    final reasoning = [first.reasoning, finalTurn.reasoning]
        .where((part) => part.trim().isNotEmpty)
        .join('\n\n');

    return StudentSolverResult(
      phase: answer.isEmpty
          ? StudentSolvePhase.failed
          : StudentSolvePhase.answered,
      answer: answer,
      answerSheet: StudentAnswerSheet.parse(answer),
      reasoning: reasoning,
      attempts: 2,
      promptTokens: _sum(first.promptTokens, finalTurn.promptTokens),
      completionTokens:
          _sum(first.completionTokens, finalTurn.completionTokens),
      finishReason: finalTurn.finishReason ?? first.finishReason,
      error: answer.isEmpty ? (finalTurn.error ?? 'no final answer') : null,
    );
  }

  Future<_TurnCapture> _run(
    ModelAdapter adapter,
    List<ChatMessage> messages,
  ) async {
    final text = StringBuffer();
    final reasoning = StringBuffer();
    int? promptTokens;
    int? completionTokens;
    String? finishReason;
    String? error;

    await for (final event
        in adapter.runTurn(messages: messages, tools: const [])) {
      if (event is ModelTextDelta) {
        text.write(event.text);
      } else if (event is ModelReasoningDelta) {
        reasoning.write(event.text);
      } else if (event is ModelTurnDone) {
        finishReason = event.finishReason;
        promptTokens = _sum(promptTokens, event.promptTokens);
        completionTokens = _sum(completionTokens, event.completionTokens);
      } else if (event is ModelFailure) {
        error = event.message;
      } else if (event is ModelTurnCancelled) {
        error = event.reason ?? 'cancelled';
      }
    }

    return _TurnCapture(
      text: text.toString(),
      reasoning: reasoning.toString(),
      promptTokens: promptTokens,
      completionTokens: completionTokens,
      finishReason: finishReason,
      error: error,
    );
  }

  static String _tail(String text, int max) {
    final value = text.trim();
    if (value.length <= max) {
      return value;
    }
    return value.substring(value.length - max);
  }

  static int? _sum(int? a, int? b) {
    if (a == null && b == null) {
      return null;
    }
    return (a ?? 0) + (b ?? 0);
  }
}

class _TurnCapture {
  const _TurnCapture({
    required this.text,
    required this.reasoning,
    this.promptTokens,
    this.completionTokens,
    this.finishReason,
    this.error,
  });

  final String text;
  final String reasoning;
  final int? promptTokens;
  final int? completionTokens;
  final String? finishReason;
  final String? error;
}
