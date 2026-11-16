/// 内容验证的确定性外层：要求解答题保留【分支表】。
///
/// 这不是答案 oracle，也不能判断“分支是否列全”；它只做一件可机械判定的事：
/// 解答题的过程里必须出现【分支表】。缺失时判 `incomplete_sub_question`，让
/// StudentRun 的 repair 有机会补分支，而不是直接把“只写一支”的答案当通过。
///
/// 选择题/填空题不受影响；基础验证器的结论先执行，只有基础验证器 pass 时
/// 才做这一层检查。
library;

import '../domain/claim.dart';
import '../domain/model_adapter.dart';
import '../domain/student_answer_sheet.dart';
import '../domain/verifier.dart';

class BranchTableVerifier implements Verifier {
  BranchTableVerifier({required this.base});

  final Verifier base;

  static const String marker = '【分支表】';

  @override
  String get id => 'branch_table_${base.id}';

  @override
  VerifierKind get kind => base.kind;

  @override
  Future<Verification> verify({
    required String question,
    required StudentAnswerSheet answer,
    List<ChatImagePart> images = const [],
    required ClaimSummary claims,
  }) async {
    final baseResult = await base.verify(
      question: question,
      answer: answer,
      images: images,
      claims: claims,
    );
    if (baseResult.verdict != Verdict.pass) {
      return baseResult;
    }
    if (answer.kind != StudentQuestionKind.solution) {
      return baseResult;
    }
    final process = answer.process.trim();
    if (!process.contains(marker)) {
      return Verification.fail(
        failureType: FailureType.incompleteSubQuestion,
        issues: <String>[
          '解答题缺少【分支表】：无法确认所有合法分支都被列出。',
        ],
        evidence: <String, Object?>{
          'source': 'branch_table_verifier',
          'has_branch_table': false,
        },
      );
    }
    final branchCount = _branchCount(process);
    if (_resultHasAlternatives(answer.result) && branchCount < 2) {
      return Verification.fail(
        failureType: FailureType.incompleteSubQuestion,
        issues: <String>[
          '答案出现“或/∪”多分支，但【分支表】只识别到 $branchCount 条分支。',
        ],
        evidence: <String, Object?>{
          'source': 'branch_table_verifier',
          'has_branch_table': true,
          'branch_count': branchCount,
        },
      );
    }
    return baseResult;
  }

  static bool _resultHasAlternatives(String result) {
    final text = result.replaceAll(' ', '');
    return text.contains('或') || text.contains('∪') || text.contains(r'\cup');
  }

  static int _branchCount(String process) {
    final index = process.indexOf(marker);
    if (index < 0) return 0;
    final body = process.substring(index + marker.length);
    final markers = RegExp(r'(≤|≥|<|>|=|时|支|①|②|③|A\.|B\.|A、|B、)');
    var count = 0;
    for (final line in body.split(RegExp(r'[\n；;]'))) {
      if (line.trim().isEmpty) continue;
      if (markers.hasMatch(line)) count += 1;
    }
    return count;
  }
}
