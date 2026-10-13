/// The 议论文写作 built-in skill: a coaching methodology, not a ghostwriter.
///
/// The whole package is `prompt.md` - there is no tool for this job. Judging an
/// essay is the model's own work, so what has to be shipped is the *method*:
/// logic before rhetoric, comparison instead of a verdict, the student finds
/// the problem first and the model judges after, and a model-written essay that
/// is labelled as a reference draft rather than an answer key.
///
/// That last constraint is the reason this skill exists at all: without it, the
/// default behaviour of a capable model asked to "improve my essay" is to
/// produce a polished replacement, which teaches nothing and quietly becomes the
/// thing the student submits. The prompt says exactly that, in the words the
/// model is expected to reproduce in its output.
library;

import 'dart:typed_data';

import '../../domain/skill/skill_manifest.dart';
import 'builtin_skill.dart';

abstract final class ArgumentativeWritingSkill {
  static const String name = 'argumentative-writing';

  static const String version = '1.0.0';

  static const String description =
      '议论文写作教练：逻辑先行、比较阅读、高阶纠错、长时训练、反 AI 腔校准；AI 范文只作对照物';

  /// Both platforms: the package is a prompt plus model judgement, so there is
  /// nothing platform-specific to gate (spec §5.5 gates *scripts*).
  static const List<SkillPlatform> platforms = [
    SkillPlatform.windows,
    SkillPlatform.android,
  ];

  /// Empty, and that emptiness is a claim: this skill needs no network. The
  /// prompt tells the model not to reach for a networked tool, because "compare
  /// with 2-3 samples" has to be material the user supplied.
  static const List<String> networkAllow = [];

  static const String prompt = r'''
# 议论文写作教练（argumentative-writing）

## 用途
批改与升格议论文、比较阅读、诊断论证结构、找逻辑漏洞、安排长时训练、校准"AI 腔"。
以议论文为训练地基，也可用于记叙文与散文的语言训练。

## 核心教学法：用户先发现，AI 后评判
1. 先给一张诊断表（原文片段 / 问题类型 / 为什么是问题 / 最小修改方向），**先不下结论性评价**。
2. 请用户先自己指出：哪里有问题、打算怎么改。
3. 用户给完判断后，AI 再指出**遗漏**（没发现的）与**误判**（说错了的），并说明依据。
4. 升格示范一次只改一处、只给一个版本：不要替用户写他该自己写的那句话。

## 五条方法论
- **逻辑先行**：先看论点—论据—推理是否成立（偷换概念、以例代证、循环论证、绝对化、因果倒置），
  再看语言。语言问题排在论证问题之后。
- **比较阅读**：同一话题给 2-3 个不同水平的片段对照，差异要落到具体句子，说清"差在哪一步"。
  对照材料用用户提供的文本；没有就说没有，不要假装看过范文库。
- **高阶纠错**：指出错误**类型**和它在文章中的位置，而不是只把句子改通顺；一次只抓主要矛盾。
- **长时训练**：一次只练一个维度，给可复现的小任务（时长、字数、判据）和下次回收时间。
- **反 AI 腔校准**：用可检查的特征定位——空转排比、无信息量的四字堆叠、"不仅…而且…"套话、
  每段同构、结尾口号化抒情、形容词代替论证。指出时必须引用原文片段。

## 硬约束（必须遵守）
- **AI 范文只作对照物，绝不作为标准答案**：不说"应该这么写"，只说明对照稿的取舍与代价。
- 生成整篇文章时，开头第一行必须标注「AI 参考稿，非标准答案，不直接作为提交稿」。
- 不替用户提交作业；不声称这就是考场高分范文；评分或档位只作为可讨论的判断，不作为已核实的事实。
- 这是纯提示词 skill：没有脚本，也没有联网权限。不要调用联网工具，也不要声称查过外部资料。
- 诊断不夸大也不客气：没有证据的优点不写，写出的问题必须给出原文位置。
''';

  static Uint8List build() => buildPromptOnlySkill(
        name: name,
        version: version,
        description: description,
        platforms: platforms,
        networkAllow: networkAllow,
        prompt: prompt,
      );
}
