/// 判分方式默认值与卡组覆盖解析（纯规则，不碰数据库）。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/features/anki/application/judge_mode_preference.dart';

void main() {
  group('默认自判（2026-11-02 口径）', () {
    test('没写过（NULL）⇒ self，老库不回填', () {
      expect(JudgeModePreference.fromStorage(null), JudgeModePreference.self);
    });

    test('未知字符串 ⇒ self（按默认处理，不报错）', () {
      expect(
        JudgeModePreference.fromStorage('written-by-a-future-build'),
        JudgeModePreference.self,
      );
    });

    test('用户明确选过的值原样保留', () {
      expect(
        JudgeModePreference.fromStorage('strict'),
        JudgeModePreference.strict,
      );
      expect(
        JudgeModePreference.fromStorage('lenient'),
        JudgeModePreference.lenient,
      );
      expect(
        JudgeModePreference.fromStorage('self'),
        JudgeModePreference.self,
      );
    });
  });

  group('卡组覆盖解析', () {
    const math = GroupJudgeModeRule(
      tagPath: '文化课/数学',
      mode: JudgeModePreference.strict,
    );
    const mathFunctions = GroupJudgeModeRule(
      tagPath: '文化课/数学/函数',
      mode: JudgeModePreference.self,
    );
    const chinese = GroupJudgeModeRule(
      tagPath: '文化课/语文',
      mode: JudgeModePreference.strict,
    );

    test('没有规则 ⇒ null（跟随全局）', () {
      expect(
        resolveGroupJudgeMode(
          knowledgePointTagPaths: const <String>['文化课/数学'],
          rules: const <GroupJudgeModeRule>[],
        ),
        isNull,
      );
    });

    test('命中卡组子树 ⇒ 用该组的判分方式', () {
      expect(
        resolveGroupJudgeMode(
          knowledgePointTagPaths: const <String>['文化课/数学'],
          rules: const <GroupJudgeModeRule>[math],
        ),
        JudgeModePreference.strict,
      );
    });

    test('最深匹配赢：数学/函数 压过 数学', () {
      expect(
        resolveGroupJudgeMode(
          knowledgePointTagPaths: const <String>['文化课/数学/函数'],
          rules: const <GroupJudgeModeRule>[math, mathFunctions],
        ),
        JudgeModePreference.self,
      );
    });

    test('不相关的子标签不误配（数学不覆盖数学/几何 之外的组）', () {
      expect(
        resolveGroupJudgeMode(
          knowledgePointTagPaths: const <String>['文化课/物理'],
          rules: const <GroupJudgeModeRule>[math, chinese],
        ),
        isNull,
      );
    });

    test('同深度多个匹配 ⇒ 路径字典序取第一条（确定性）', () {
      const a = GroupJudgeModeRule(
        tagPath: 'A/B',
        mode: JudgeModePreference.strict,
      );
      const b = GroupJudgeModeRule(
        tagPath: 'A/C',
        mode: JudgeModePreference.self,
      );
      final mode = resolveGroupJudgeMode(
        knowledgePointTagPaths: const <String>['A/B', 'A/C'],
        rules: const <GroupJudgeModeRule>[b, a],
      );
      // 两个组的路径同深度且都命中；按路径字典序 'A/B' 在前。
      expect(mode, JudgeModePreference.strict);
    });

    test('知识点没挂标签 ⇒ null', () {
      expect(
        resolveGroupJudgeMode(
          knowledgePointTagPaths: const <String>[],
          rules: const <GroupJudgeModeRule>[math],
        ),
        isNull,
      );
    });
  });
}
