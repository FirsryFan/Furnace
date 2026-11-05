/// The Oxford dictionary lookup built-in skill: how to answer "what does this
/// English word mean" from the Oxford Learner's Dictionaries website.
///
/// **Why a skill rather than a tool.** The app cannot scrape a dictionary
/// through a special-purpose API: the only network primitive it has is
/// `fetch_page` (GET, no cookies, no login, no scripting). What the model needs
/// is the *procedure* - which site, which URL, how to keep the answer short, and
/// what it is forbidden to claim - so the package is prompt-only, exactly like
/// the other two built-ins.
///
/// **Why this file exists in the repository (versioned install).** The canonical
/// install is still an ordinary `.fskill` under `<appSupport>/skills/`; this
/// class only makes the same package ship inside the app, so a fresh install
/// (or a new app version) can offer it from the skills card instead of asking
/// the user to find a file. The package name matches the locally installed
/// `oed-dictionary`, so installing it replaces that directory wholesale rather
/// than creating a second dictionary skill.
///
/// The prompt is deliberately under 4 KB: it travels in every request of every
/// turn (`SkillPrompt` caps the whole section at 64 KB), so it is an index into
/// the procedure, not a dictionary.
library;

import 'dart:typed_data';

import '../../domain/skill/skill_manifest.dart';
import 'builtin_skill.dart';

abstract final class OedDictionarySkill {
  /// Same name as the locally installed data skill, so one dictionary exists.
  static const String name = 'oed-dictionary';

  /// Bumped when the source URL or the output contract changes: the user can
  /// tell an installed copy (`<skills>/oed-dictionary/manifest.json`) from the
  /// version the app ships.
  static const String version = '1.1.0';

  static const String description =
      '查英语单词时只使用 Oxford Learner\'s Dictionaries 网页版；输出简洁词条，不贴整页，不先查闪存卡';

  /// Both platforms, because the package is a prompt over `fetch_page`, which
  /// is a built-in tool available everywhere (spec §5.5 gates *scripts* only).
  static const List<SkillPlatform> platforms = [
    SkillPlatform.windows,
    SkillPlatform.android,
  ];

  /// Exactly the domain named in the prompt. An allow-list wider than what the
  /// instructions need would be consent the user never meaningfully gave.
  static const List<String> networkAllow = [
    'www.oxfordlearnersdictionaries.com',
  ];

  static const String prompt = r'''
# 牛津查词（oed-dictionary）

## 触发与路由
用户说「查单词 / 查词典 / 这个词什么意思 / 释义 / 音标 / 用法 / 例句」时用本 skill。
**不要先查闪存卡，也不要先调用 query_content**：查词是查公开词典，不是查用户自己的库。
只有用户明确问「我的卡里 / 复习里 / 题库里有没有这个词」时，才去查本地闪存卡。

## 来源（唯一）
只用 Oxford Learner's Dictionaries 网页版：https://www.oxfordlearnersdictionaries.com/
站内搜索：https://www.oxfordlearnersdictionaries.com/search/dictionary/?q=<urlencode(word)>
能直接打开词条页时用页面实际链接；**不要猜内部接口**，不要登录、不使用 cookie。
**不许**用 Cambridge、Merriam-Webster 或模型记忆冒充牛津词典原文；也不许把 OED.com
（付费《牛津英语词典》）与本词典混为一谈。

## 工具用法（fetch_page 是只读 GET）
1. 先搜词，拿到词条页 URL；再抓词条页。
2. 抓取时优先用 selector 只取词条区域（如 `.entry`、`.webtop`、`#main` 这类包含词头与释义的容器，
   以页面实际结构为准），不要整页倾倒。
3. 整页正文时把 max_chars 降到 800–1500；不要用默认 8000 把整页塞进上下文。
4. 只要词条关键信息，不要 HTML、不要脚本、不要导航文本。

## 输出（简洁，中文讲解）
1. 词头、英式/美式音标、词性；
2. 2–4 个最相关义项，每条一句中文解释 + 一个英文搭配或例句；
3. 常见固定搭配/短语；
4. 易混词或考试用法（简短）。
**总输出不超过 12 行**，不贴整页原文，不输出几千字。

## 失败与禁止
- 页面被登录墙/脚本挡住、没有返回词条时，直说「Oxford 页面未返回词条」并给出 URL，
  不要用模型记忆冒充词典内容。
- 不把其它词典结果说成 Oxford；不编造音标、义项、例句。
- 不先调用 query_content/闪存卡（除非用户明确问自己的卡）。
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
