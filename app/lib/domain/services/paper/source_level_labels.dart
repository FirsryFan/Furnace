/// 题目来源档位（`Questions.sourceLevel`）的中文名。
///
/// 组卷（`paper_composer.dart`）和相似题（`similar_questions.dart`）共用同一张
/// 对照表：同一份题库在两个入口必须显示同一个名字，不能一边叫「高考真题」、
/// 一边叫「gaokao」。词表外的 key 原样返回（不隐藏未知来源）。
library;

/// 来源档位 key → 中文名；未知 key 原样返回（先 trim）。
String sourceLevelLabel(String key) {
  final cleaned = key.trim();
  return switch (cleaned) {
    'gaokao' => '高考真题',
    'provincial_diagnostic' => '省市诊断',
    'elite_school' => '名校测试',
    'school' => '校内题',
    'personal' => '自建题',
    _ => cleaned,
  };
}
