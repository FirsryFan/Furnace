import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/features/ai/domain/agent_preset.dart';
import 'package:furnace/features/ai/domain/agent_run.dart';
import 'package:furnace/features/ai/domain/student_answer_sheet.dart';
import 'package:furnace/features/ai/domain/student_composition.dart';
import 'package:furnace/features/ai/domain/student_solver.dart';

/// 学生 preset 的 composition（设计文档 §4.2）。
///
/// 两组断言：
///
///  1. 结构：id / mode / 20k + 3k / 无工具 / 最多一次 repair / 一次验证；
///  2. **硬约束**：提示词不得含任何题目答案提示。用「无 ASCII/全角数字 + 无
///     禁用口径」两条机械规则钉住——写在注释里的「禁止」是靠不住的，数字出现
///     在 prompt 里就说明有人把题目内容漏进去了。
void main() {
  group('StudentComposition 结构', () {
    test('出厂学生 composition：id / mode / 20k+3k / 无工具 / repair 1 次', () {
      const composition = StudentComposition.standard;
      expect(composition.id, 'student_solver');
      expect(composition.label, '学生模式');
      expect(composition.mode, AgentMode.student);
      expect(composition.usesTools, isFalse);
      expect(composition.toolNames, isEmpty);
      expect(composition.reasonBudgetTokens, 20000);
      expect(composition.answerReserveTokens, 3000);
      expect(composition.maxRepair, 1);
      expect(composition.maxVerifierCalls, 1);
      // 设计 §3.2：基础一次 + repair 后复验一次，总上限 2。
      expect(composition.maxTotalVerifierCalls, 2);
      // reasoning 与答案共享同一个 output 预算。
      expect(composition.budget.maxCompletionTokens, 23000);
      expect(composition.budget.maxReasoningTokens, 20000);
      expect(composition.budget.answerReserveTokens, 3000);
      // 解析契约与老路径同一份文本，保证答题卡格式不会分叉。
      expect(composition.answerContract, StudentSolver.answerSheetContract);
    });

    test('mode 与预设 id 与全局枚举对齐', () {
      const composition = StudentComposition.standard;
      expect(composition.mode.id, 'student');
      expect(composition.id, AgentPreset.studentSolver.id);
    });
  });

  group('prompt 不含题目答案提示（硬约束）', () {
    const prompts = <String, String>{
      'systemPrompt': StudentComposition.examStudentPrompt,
      'answerScribePrompt': StudentComposition.defaultAnswerScribePrompt,
      'repairPrompt': StudentComposition.defaultRepairPrompt,
    };

    /// 具体题目的答案/分支/临界判据与「官方口径」措辞。
    ///
    /// 注意 `解析` 只出现在「不能使用解析」的**禁令**里（考场规则），所以不在
    /// 禁用列表；`【答案】` 是答题卡标记，也不是提示。
    const forbidden = <String>[
      '官方答案',
      '标准答案',
      '参考答案',
      '正确答案',
      '答案.md',
      'answer.md',
      'm2/m1',
      'm_2/m_1',
      '17/2',
      '两支',
      '两支均',
      '不要求与de相交',
      '质量比',
      '临界值',
      '临界条件',
      'instructions',
    ];

    for (final entry in prompts.entries) {
      test('${entry.key}：没有任何数字', () {
        // 任何数字都可能泄漏「16 / 7 / 12」这类答案；通用考场指令不需要数字。
        expect(
          RegExp(r'[0-9０１２３４５６７８９]').hasMatch(entry.value),
          isFalse,
          reason: '${entry.key} 出现了数字，可能把题目答案漏进了 prompt',
        );
      });

      test('${entry.key}：没有禁用口径', () {
        for (final phrase in forbidden) {
          expect(
            entry.value.contains(phrase),
            isFalse,
            reason: '${entry.key} 含禁用短语「$phrase」',
          );
        }
      });
    }

    test('通用考场规则与答题卡契约仍然在', () {
      const prompt = StudentComposition.examStudentPrompt;
      expect(prompt, contains('高三学生'));
      expect(prompt, contains('不能使用任何工具'));
      // “高中生”是行为/知识范围约束，不是降智指令。
      expect(prompt, contains('不限制你的推理能力'));
      expect(prompt, contains('不使用大学知识'));
      // 答题卡三标记必须来自同一份契约，解析器才认得出。
      expect(prompt, contains(StudentAnswerSheet.kindMarker));
      expect(prompt, contains(StudentAnswerSheet.answerMarker));
      expect(prompt, contains(StudentAnswerSheet.processMarker));
    });
  });
}
