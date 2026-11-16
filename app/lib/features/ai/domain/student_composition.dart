/// 学生 preset 的静态 composition（设计文档 §4 与 §2.2）。
///
/// 学生模式不是主 `AgentLoop` 的一种「角色 prompt」，而是一条**独立的运行
/// 组合**：单独的预算（20k reasoning + 3k answer reserve）、没有工具、单独的
/// 提示词、固定的一次 repair 与一次（repair 后再一次）内容验证。把这些数字和
/// 文本集中在一个不可变的 composition 里，而不是散落在 controller / prompt /
/// budget 三处，是为了让「学生 preset 到底由什么构成」只有一个答案——
/// `StudentRun` 只消费它，不自己发明默认值。
///
/// 这个文件属于 domain：不 import Flutter，不 import infrastructure，也不碰
/// 数据库。composition 是静态注册的（设计文档 §4.1），不入库、不存版本 hash：
/// 会话里只存 preset id，恢复时解析当前定义。
///
/// **硬约束（测试里是断言，不是口号）**：提示词不得含任何题目答案提示——
/// 具体题目的质量比、区间、分支数、临界判据，以及「官方/标准答案」口径。
/// [examStudentPrompt] / [answerScribePrompt] / [repairPrompt] 全部是通用考场
/// 指令，连数字都不出现；`student_composition_test.dart` 用「无 ASCII 数字 +
/// 无禁用短语」两条机械断言把它钉住。
library;

import 'agent_budget.dart';
import 'agent_run.dart';
import 'student_solver.dart' show StudentSolver;

/// 学生 preset 的 composition（设计文档 §4.2 的 `StudentComposition`）。
///
/// 出厂实例是 [standard]；测试可以构造自己的实例覆盖 budget / prompt，但
/// 「学生 preset 有一个 composition」这件事不变。
class StudentComposition {
  const StudentComposition({
    this.id = 'student_solver',
    this.label = '学生模式',
    this.mode = AgentMode.student,
    required this.systemPrompt,
    required this.answerScribePrompt,
    required this.repairPrompt,
    this.budget = RunBudget.student,
    this.toolNames = const <String>[],
    this.answerContract = StudentSolver.answerSheetContract,
  });

  /// 出厂学生 composition：20k reasoning + 3k answer reserve，最多一次 repair、
  /// 最多一次（repair 后一次）内容验证，没有工具。
  static const StudentComposition standard = StudentComposition(
    systemPrompt: examStudentPrompt,
    answerScribePrompt: defaultAnswerScribePrompt,
    repairPrompt: defaultRepairPrompt,
  );

  /// 稳定 preset id（落库用；与 [AgentPreset.studentSolver] 的 id 相同）。
  final String id;

  /// 人可读标签（只用于展示/日志）。
  final String label;

  /// 运行模式：学生模式一律 [AgentMode.student]。
  final AgentMode mode;

  /// 学生 person + 考场规则 + 答案卡契约（solve 阶段的 system prompt）。
  final String systemPrompt;

  /// 答案誊写员 prompt：reasoning 回合没产出可用答案时，用 3k reserve 只写
  /// 答题卡，不重新解题。
  final String answerScribePrompt;

  /// repair prompt：内容验证判 fail 后，只按检查意见修正答题卡。
  final String repairPrompt;

  /// 预算。`RunBudget.student` 是 20k/3k/1 repair/1 verifier 的出厂值。
  final RunBudget budget;

  /// 工具列表。学生模式**没有工具**，这里是空的，不是「还没配」。
  final List<String> toolNames;

  /// 答案卡 wire contract（与 `StudentSolver.answerSheetContract` 同一份文本，
  /// 保证新老路径解析的是同一个格式）。
  final String answerContract;

  /// reasoning token 预算（设计文档 §2.2 的 20k）。
  int get reasonBudgetTokens => budget.maxReasoningTokens ?? 0;

  /// 留给答案的 token 数（设计文档 §2.2 的 3k）。
  int get answerReserveTokens => budget.answerReserveTokens;

  /// 最多 repair 次数（出厂 1）。
  int get maxRepair => budget.maxRepair;

  /// 基础内容验证次数（出厂 1）。
  int get maxVerifierCalls => budget.maxVerifierCalls;

  /// 一次运行里内容验证的**总**上限：基础一次 + repair 后复验一次（设计文档
  /// §3.2「repair 后可复用同一 verifier 一次，总上限 2 次」）。基础次数为 0 时
  /// 视为关闭验证，repair 也不再触发复验。
  int get maxTotalVerifierCalls =>
      budget.maxVerifierCalls <= 0 ? 0 : budget.maxVerifierCalls + budget.maxRepair;

  /// 学生模式是否使用工具（恒为 false；留给测试与全局层做断言）。
  bool get usesTools => toolNames.isNotEmpty;

  /// 考场学生 person + 规则 + 答案卡契约。
  ///
  /// 只有通用指令：读题、选定一种理解、最多一次自洽检查、按答题卡格式输出。
  /// 不含任何题目专属答案、分支、临界判据或「官方答案」口径。
  static const String examStudentPrompt = '''
你是一名具备完整推理能力的高三学生，正在考场做题。
你只能看到题目文字和题图，不能使用任何工具、文件、答案或解析。
“高中生”只限制你的知识范围和考场行为：只使用高中阶段允许的知识，不使用大学知识降维、不使用计算器；它**不限制你的推理能力**，不要故意降智、省略必要推导、或为了“像学生”而漏掉题目条件。
先完整读题，明确每个小问的条件、临界情形和可能分支；对每个情形按高中知识严谨推导，最后只提交一个自洽的答案。
在【过程】开头先写【分支表】：逐小问列出所有合法分支/取舍；然后每个分支都要处理，不能只写一支。
若前面小问得到“A 或 B”等多个合法分支，后续每一问都必须逐个分支处理并说明取舍；不能只保留一个分支，除非明确写出排除理由。
每个最终答案/区间必须能由本小问前面写出的等式或不等式直接推出；不得在结尾引入前面没有出现的端点、数字或新条件。若推不出，明确写“未能确定”，不要填猜测值。
允许必要的自洽检查：发现矛盾就回到具体步骤修正；不要反复怀疑已经验证过的结论，也不要重开已经定下的分支。
推导完成后，只把答题卡的内容写出来；不要写 meta 解释。

答案卡格式：
${StudentSolver.answerSheetContract}''';

  /// 誊写员 prompt：reasoning 阶段没写出可用答案时，只把已有结果写成答题卡。
  static const String defaultAnswerScribePrompt = '''
你是考场答题卡誊写员。只写答题卡，不重新解题，不写 meta 解释，不写「我在想 / 可能 / 也许」这类话。

答案卡格式：
${StudentSolver.answerSheetContract}''';

  /// repair prompt：内容验证判 fail 后，只按检查意见修正答案卡。
  static const String defaultRepairPrompt = '''
你是同一名高三学生，正在考场做同一道题。你写好的答案卡被独立检查指出了问题。
只按检查意见修正答案卡；不要推翻没有被指出、且已经定下的部分；不要写新的推理草稿，也不要解释检查意见。
修正后的输出仍然只能是答题卡。

答案卡格式：
${StudentSolver.answerSheetContract}''';

  @override
  String toString() => 'StudentComposition($id, mode: ${mode.id}, '
      'tools: ${toolNames.length}, repair: $maxRepair, '
      'verifier: $maxVerifierCalls)';
}
