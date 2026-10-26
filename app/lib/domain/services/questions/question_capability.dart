/// 题库的跨科通用能力词表（A1–A10）。
///
/// 定义来源：`E:/FirsryOS/THREADRIPPER/handoff/2026-10-26-furnace-pipeline/FURNACE-PIPELINE-SPEC-v1.md`
/// 第 5.6 节（:404-425）的「编号 / 能力 / 一句话定义」三列；中文名与判定口径照抄原文，
/// 不改写含义。同表的「主要落点」「可判定训练动作」属于材料写作口径，本词表不携带。
///
/// 本文件是纯 Dart：不 import Flutter / drift / 任何数据库或实体类型，
/// 只提供能力词表、JSON 归一化与题型中文名映射。
library;

/// 跨科通用能力，枚举顺序即规格编号顺序（A1 → A10）。
enum QuestionCapability {
  /// A1 语言解码：词汇 / 句法 / 术语 / 文本结构。
  a1('A1', '语言解码', '词汇 / 句法 / 术语 / 文本结构'),

  /// A2 信息定位与提取：从材料找证据句 / 图表数据。
  a2('A2', '信息定位与提取', '从材料找证据句 / 图表数据'),

  /// A3 逻辑与论证：因果、充分必要、反例、归谬、削弱加强。
  a3('A3', '逻辑与论证', '因果、充分必要、反例、归谬、削弱加强'),

  /// A4 结构化建模：情境→方程 / 图式 / 模型。
  a4('A4', '结构化建模', '情境→方程 / 图式 / 模型'),

  /// A5 计算与估算：运算、量纲、有效数字、近似。
  a5('A5', '计算与估算', '运算、量纲、有效数字、近似'),

  /// A6 图表与图像：读图、图像→代数、趋势判断。
  a6('A6', '图表与图像', '读图、图像→代数、趋势判断'),

  /// A7 转化与等价：同义改写、换元、数形结合、选项↔原文。
  a7('A7', '转化与等价', '同义改写、换元、数形结合、选项↔原文'),

  /// A8 实验与证据设计：变量控制、对照、误差、方案评价。
  a8('A8', '实验与证据设计', '变量控制、对照、误差、方案评价'),

  /// A9 表达与压缩：概括、翻译、写作、讲清楚。
  a9('A9', '表达与压缩', '概括、翻译、写作、讲清楚'),

  /// A10 自我监控：检查、时间分配、边界条件。
  a10('A10', '自我监控', '检查、时间分配、边界条件');

  const QuestionCapability(this.code, this.labelZh, this.definitionZh);

  /// 规格里的稳定编号（`A1`…`A10`）；落库与跨层交换都用它，中文名只用于展示。
  final String code;

  /// 能力中文名（规格「能力」列原文）。
  final String labelZh;

  /// 一句话判定口径（规格「一句话定义」列原文）。
  final String definitionZh;

  /// 从编号解析能力：容忍首尾空白与大小写；未知编号或 null 返回 null。
  static QuestionCapability? fromCode(String? code) {
    final trimmed = code?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    final normalized = trimmed.toUpperCase();
    for (final capability in values) {
      if (capability.code == normalized) return capability;
    }
    return null;
  }
}

/// 把任意 JSON 形状（null、单个字符串、字符串数组）读成能力编号列表。
///
/// 规则（确定性、永不抛异常）：
/// * null → 空列表；
/// * 单个 String 视为一个编号（不做逗号 / 斜杠拆分）；
/// * Iterable 逐项读取，只接受 String，其余类型与非法编号直接丢弃；
/// * 按 [QuestionCapability.fromCode] 归一（去首尾空白、不分大小写）；
/// * 去重后按 A 序号升序（`A1` < `A2` < … < `A10`，注意 `A10` 排在 `A2` 之后）；
/// * 返回不可变列表，调用方拿到的顺序与输入顺序无关。
List<String> capabilityCodesFromJson(Object? raw) {
  final accepted = <QuestionCapability>{};
  void visit(Object? value) {
    if (value is! String) return;
    final capability = QuestionCapability.fromCode(value);
    if (capability != null) accepted.add(capability);
  }

  if (raw is Iterable) {
    for (final value in raw) {
      visit(value);
    }
  } else {
    visit(raw);
  }
  // Set 保持插入顺序，这里显式按编号重排，保证输入顺序不同也得到同一结果。
  final codes = accepted.map((capability) => capability.code).toList()
    ..sort(_compareCapabilityCode);
  return List<String>.unmodifiable(codes);
}

/// 写出能力编号列表：先按 [capabilityCodesFromJson] 归一（去重、丢弃非法、按 A 序）。
List<String> capabilityCodesToJson(List<String> codes) =>
    capabilityCodesFromJson(codes);

/// 题型 key → 中文标签。
///
/// 左侧取值沿用题库 `question_type` 列现有值（`app/lib/data/database/tables.dart:1217`）：
/// `single_choice` / `multi_choice` / `fill_blank` / `solution` / `open`。
/// 右侧中文名是展示用语：规格没有给题型中文名，这里按题面惯用叫法定为
/// 单选题 / 多选题 / 填空题 / 解答题 / 开放题。
const Map<String, String> kQuestionTypeLabelsZh = <String, String>{
  'single_choice': '单选题',
  'multi_choice': '多选题',
  'fill_blank': '填空题',
  'solution': '解答题',
  'open': '开放题',
};

/// 取题型中文标签：先 trim 再查 [kQuestionTypeLabelsZh]；未知 key 原样返回（含首尾空白）。
String questionTypeLabelZh(String questionType) {
  final trimmed = questionType.trim();
  return kQuestionTypeLabelsZh[trimmed] ?? questionType;
}

int _compareCapabilityCode(String a, String b) =>
    _capabilityIndex(a).compareTo(_capabilityIndex(b));

int _capabilityIndex(String code) {
  final capability = QuestionCapability.fromCode(code);
  return capability == null
      ? QuestionCapability.values.length
      : capability.index;
}
