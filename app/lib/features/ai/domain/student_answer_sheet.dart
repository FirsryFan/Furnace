/// The structure the student solver must answer with: what is on the answer
/// sheet, not a free-form essay.
///
/// Why this exists: a student-mode solve used to return whatever text the model
/// produced, so a caller (the tool, the direct path, later review tooling) had
/// to guess where the final answer was and whether the text was reasoning or
/// meta-commentary. The solver now asks the model for three marked sections and
/// this class parses them into typed fields:
///
///   * choice   - the option letters plus the final answer text;
///   * fillIn   - just the final result;
///   * solution - the final result plus the necessary working.
///
/// The raw text is kept in [raw] for the trace, and [structured] says whether
/// the model actually emitted the markers. A model that ignores the format is
/// still wrapped in this structure (as an unstructured solution) instead of
/// leaking a bare string through the typed output.
library;

/// What kind of answer sheet a solve produced.
///
/// The stored [id] is the stable value written to traces and model JSON; the
/// [label] is the Chinese word the solver prompt uses for the same thing.
enum StudentQuestionKind {
  choice('choice', '选择题'),
  fillIn('fill_in', '填空题'),
  solution('solution', '解答题');

  const StudentQuestionKind(this.id, this.label);

  final String id;
  final String label;

  static StudentQuestionKind? fromLabel(String? label) {
    final value = label?.trim() ?? '';
    if (value.isEmpty) {
      return null;
    }
    final lower = value.toLowerCase();
    if (value.contains('选择') || lower.contains('choice')) {
      return StudentQuestionKind.choice;
    }
    if (value.contains('填空') || lower.contains('fill')) {
      return StudentQuestionKind.fillIn;
    }
    if (value.contains('解答') ||
        value.contains('计算') ||
        value.contains('证明') ||
        lower.contains('solution')) {
      return StudentQuestionKind.solution;
    }
    return null;
  }

  static StudentQuestionKind fromId(String? id) => switch (id) {
        'choice' => StudentQuestionKind.choice,
        'fill_in' => StudentQuestionKind.fillIn,
        _ => StudentQuestionKind.solution,
      };
}

/// One parsed answer sheet.
class StudentAnswerSheet {
  const StudentAnswerSheet({
    required this.kind,
    required this.raw,
    required this.result,
    this.choice,
    this.process = '',
    this.structured = false,
  });

  /// The sheet a failed solve produces: empty, but still typed.
  factory StudentAnswerSheet.failed(String raw) {
    return StudentAnswerSheet(
      kind: StudentQuestionKind.solution,
      raw: raw,
      result: '',
    );
  }

  /// Parses the solver's answer text into the answer-sheet shape.
  ///
  /// The markers are the contract in `StudentSolver.answerSheetContract` (and
  /// the default system prompt):
  ///
  /// ```
  /// 【题型】选择题 | 填空题 | 解答题
  /// 【答案】...
  /// 【过程】...      (only for 解答题)
  /// ```
  ///
  /// A model that ignores the markers still gets a typed sheet: [structured] is
  /// false, the whole text becomes the result, and the kind falls back to
  /// [StudentQuestionKind.solution]. Nothing is dropped, so a non-conforming
  /// answer is visible rather than silently mis-parsed.
  factory StudentAnswerSheet.parse(String raw) {
    final text = raw.trim();
    final kindLabel = _section(text, kindMarker);
    final answerText = _section(text, answerMarker);
    final processText = _section(text, processMarker) ?? '';
    final hasMarkers =
        kindLabel != null || answerText != null || processText.isNotEmpty;

    if (!hasMarkers) {
      return StudentAnswerSheet(
        kind: StudentQuestionKind.solution,
        raw: text,
        result: text,
      );
    }

    final kind = StudentQuestionKind.fromLabel(kindLabel) ??
        (processText.isNotEmpty
            ? StudentQuestionKind.solution
            : StudentQuestionKind.fillIn);
    final result = answerText ?? processText;
    return StudentAnswerSheet(
      kind: kind,
      raw: text,
      result: result,
      choice:
          kind == StudentQuestionKind.choice ? _leadingChoice(result) : null,
      process: processText,
      structured: answerText != null || kindLabel != null,
    );
  }

  static const String kindMarker = '【题型】';
  static const String answerMarker = '【答案】';
  static const String processMarker = '【过程】';

  final StudentQuestionKind kind;

  /// The model's complete text, kept for the local trace.
  final String raw;

  /// The final result written on the answer sheet. For a choice question this
  /// is the full answer text, so the chosen option is not lost even when the
  /// option letters cannot be split off.
  final String result;

  /// The option letters of a choice question (`B`, `AC`), or null for other
  /// kinds and when the answer does not start with option letters.
  final String? choice;

  /// The necessary working of a solution question. Deliberately not the model's
  /// full chain of thought: the prompt asks for steps, not deliberation.
  final String process;

  /// Whether the model actually used the marker format.
  final bool structured;

  bool get isEmpty => result.trim().isEmpty && process.trim().isEmpty;

  /// Renders the sheet back to the marker format, e.g. for persisting it as the
  /// assistant message of a student-mode conversation.
  String toPlainText() {
    final buffer = StringBuffer()
      ..writeln('$kindMarker${kind.label}')
      ..write('$answerMarker$result');
    if (process.trim().isNotEmpty) {
      buffer
        ..writeln()
        ..write('$processMarker$process');
    }
    return buffer.toString();
  }

  Map<String, Object?> toJson() => {
        'kind': kind.id,
        'kind_label': kind.label,
        'choice': choice,
        'result': result,
        'process': process,
        'structured': structured,
        'raw': raw,
      };

  static String? _section(String text, String marker) {
    final index = text.indexOf(marker);
    if (index < 0) {
      return null;
    }
    final start = index + marker.length;
    var end = text.length;
    for (final other in const [kindMarker, answerMarker, processMarker]) {
      final at = text.indexOf(other, start);
      if (at >= 0 && at < end) {
        end = at;
      }
    }
    return text.substring(start, end).trim();
  }

  /// The option letters at the start of a choice-question answer.
  ///
  /// Deliberately a narrow heuristic (`B`, `A、C`, `AC`): a choice answer that
  /// does not start with option letters simply leaves [choice] null while
  /// [result] still carries the model's exact text.
  static String? _leadingChoice(String answer) {
    final match =
        RegExp(r'^[（(]?\s*([A-H](?:\s*[、,，]?\s*[A-H])*)').firstMatch(answer);
    if (match == null) {
      return null;
    }
    final letters = match.group(1)!.replaceAll(RegExp(r'[\s、,，]'), '');
    return letters.isEmpty ? null : letters;
  }
}
