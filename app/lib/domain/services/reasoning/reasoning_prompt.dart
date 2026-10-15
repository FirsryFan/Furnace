/// 「AI 亲自解题并交出自述思维链」的提示词构造与严格解析。
///
/// 推理层的输入只有一样东西：**题目本身**。模型不允许出题——出题是另一条
/// 产品线的事，一旦让同一个模型既出题又解题，诊断出来的「卡点」就同时混进了
/// 出题偏差，无法归因。所以这里的提示词把「不得自造题目、不得改变题意」放在
/// 最高优先级，且测试会逐字检查这句话还在。
///
/// 输出侧是一份**严格的 JSON 契约**（见 [chainJsonContract]）：模型交回一条
/// 分步思维链，每步带一个来自 `CapabilityAction` 词表的 `actionType`。解析器
/// [parseChain] 负责把这坨文本变成结构化数据，并且：
///
/// * 容忍模型习惯性的 ```json 代码块和前后寒暄；
/// * 对结构性错误抛 [ReasoningParseException]（可 catch 的类型化异常），
///   让调用方能把「模型胡说」和「网络失败」分开处理；
/// * 对 `actionType` **不**抛错：未知 key 保留原始字符串并标记
///   [ParsedStep.knownAction] == false。词表是开放的，未知动作是信号而不是
///   事故——它恰好告诉我们模型在用我们还没建模的思考方式。
///
/// 纯 Dart：不 import drift、不 import 数据库、不 import Flutter widget。
library;

import 'dart:convert';

import 'package:furnace/domain/services/reasoning/capability_action.dart';
import 'package:furnace/features/ai/domain/model_adapter.dart';

/// 模型没有给出 `stuckRisk` 时使用的中性值。
///
/// 0.5 = 「不知道」，而不是 0 = 「不会卡」：缺失信息不该被当成好消息。
const double defaultStuckRisk = 0.5;

/// 解析器期待的 JSON 契约，**逐字**出现在提示词里，也逐字写进
/// `docs/REASONING_LAYER_DESIGN.md`。
///
/// 改这里就等于改协议：解析器、文档、以及将来入库的列名都要一起动。
const String chainJsonContract = '''
{
  "summary": "一句话概括整条思路",
  "steps": [
    {
      "index": 1,
      "goal": "这一步要达成的小目标",
      "actionType": "first_principles",
      "justification": "为什么这一步成立、为什么可以这么做",
      "checkMethod": "这一步做完后怎么自检（没有就写空字符串）",
      "stuckRisk": 0.5,
      "knowledgeHints": ["涉及的知识点或符号"]
    }
  ]
}''';

/// 构造「先解题、再拆链」的两条消息：`[system, user]`。
///
/// 参数：
/// * [questionStem] 题干原文。**原样**写进 user 消息，不做任何改写或摘要，
///   否则模型看到的东西就与我们要诊断的东西不是同一道题。
/// * [options] 选择题选项，按顺序传入；非选择题传空列表。
/// * [subjectKey] 学科轨道键，取值来自 [CapabilityAction.subjectKeys]。未知值
///   不会被拒绝，只会退化成原样输出，避免调用方因为一个枚举写错而整条链路挂掉。
/// * [capabilityCatalog] 本次提供给模型的能力动作词表，默认全表。传入子集可以
///   做对照实验（比如只给可迁移动作，看模型的 actionType 分布会不会变）。
List<ChatMessage> solveThenDecompose({
  required String questionStem,
  List<String> options = const <String>[],
  required String subjectKey,
  List<CapabilityAction> capabilityCatalog = CapabilityAction.catalog,
}) {
  final system = _buildSystemMessage(
    subjectKey: subjectKey,
    capabilityCatalog: capabilityCatalog,
  );
  final user = _buildUserMessage(questionStem: questionStem, options: options);
  return <ChatMessage>[system, user];
}

ChatMessage _buildSystemMessage({
  required String subjectKey,
  required List<CapabilityAction> capabilityCatalog,
}) {
  final buffer = StringBuffer()
    ..writeln('你是「炉」的解题推理引擎。你的唯一职责：亲自把用户给出的题目解出来，'
        '再把你自己的解题思路拆成一步一步的能力动作，供后续诊断学生卡在哪一步。')
    ..writeln()
    ..writeln('【不得违反的规则】')
    ..writeln('1. 禁止自造题目：不得改编、替换、补充、删减或另出任何新题，'
        '只解用户给出的这一道题。')
    ..writeln('2. 不得改变题意：题干里的条件、数值、问法一律照原样理解，'
        '不得换成你更熟悉的同类题。')
    ..writeln('3. 先真正解出答案，再交出自述思维链；思维链要写你实际是怎么想的，'
        '不要写事后包装的漂亮话。')
    ..writeln('4. 题目信息不足或有歧义时照实说明，并给出你能确定的步骤；'
        '不要为了凑步骤而编造。')
    ..writeln('5. 只输出一个 JSON 对象，不要输出任何解释性文字，'
        '也不要用 Markdown 代码块包裹。')
    ..writeln()
    ..writeln('【科目】$subjectKey（${_subjectLabelZh(subjectKey)}）')
    ..writeln()
    ..writeln('【能力动作词表】steps[].actionType 只能取下面这些 key，不得新造：')
    ..writeln(_renderCatalog(capabilityCatalog))
    ..writeln()
    ..writeln('【输出契约】严格按下面的结构输出 JSON：')
    ..writeln(chainJsonContract)
    ..writeln()
    ..writeln('【字段要求】')
    ..writeln('- summary：一句话概括整条思路。')
    ..writeln('- steps：按解题顺序排列的数组，至少 1 步，index 从 1 开始连续递增。')
    ..writeln('- actionType：必须精确等于词表里的某个 key（区分大小写与下划线）。')
    ..writeln('- stuckRisk：0 到 1 之间的小数，表示「学生最可能卡在这一步」的风险，'
        '不是「这一步有多难」。');
  return ChatMessage.system(buffer.toString().trimRight());
}

ChatMessage _buildUserMessage({
  required String questionStem,
  required List<String> options,
}) {
  final buffer = StringBuffer()
    ..writeln('【题目】')
    ..writeln(questionStem.trim());
  if (options.isNotEmpty) {
    buffer
      ..writeln()
      ..writeln('【选项】');
    for (var i = 0; i < options.length; i++) {
      buffer.writeln(_renderOption(i, options[i]));
    }
  }
  return ChatMessage.user(buffer.toString().trimRight());
}

String _subjectLabelZh(String subjectKey) =>
    CapabilityAction.subjectLabelsZh[subjectKey] ?? subjectKey;

String _renderCatalog(List<CapabilityAction> catalog) {
  if (catalog.isEmpty) {
    // 空词表是调用方的 bug，但提示词不该因此崩：说明白比抛异常更有用。
    return '（词表为空：请把 actionType 写成最贴近的英文 snake_case 描述，'
        '并在 justification 里解释这一步在做什么。）';
  }
  final buffer = StringBuffer();
  for (final action in catalog) {
    final tag = action.transferable ? '可迁移' : '领域特有';
    buffer.writeln('- ${action.key}（${action.labelZh}，$tag）：'
        '${action.descriptionZh}');
  }
  return buffer.toString().trimRight();
}

final RegExp _optionLabelPattern = RegExp(r'^[A-Za-z][.、．)）]');

String _renderOption(int index, String raw) {
  final text = raw.trim();
  if (_optionLabelPattern.hasMatch(text)) {
    return text;
  }
  final label = index < 26 ? String.fromCharCode(65 + index) : '${index + 1}';
  return '$label. $text';
}

/// 结构异常的类型化异常。
///
/// 单独一个类型是为了让调用方能把「模型回复不符合契约」（可重试、可记录）
/// 与「JSON 语法错误」「网络失败」区分开——三者该走不同的重试策略。
class ReasoningParseException implements Exception {
  const ReasoningParseException(this.message, {this.rawSnippet});

  final String message;

  /// 出错原文的截断片段，用于日志与人工排查。可能为 `null`。
  final String? rawSnippet;

  @override
  String toString() => rawSnippet == null
      ? 'ReasoningParseException: $message'
      : 'ReasoningParseException: $message（原文片段：$rawSnippet）';
}

/// 思维链里的一步。
class ParsedStep {
  const ParsedStep({
    required this.index,
    required this.goal,
    required this.actionType,
    required this.action,
    required this.justification,
    required this.checkMethod,
    required this.stuckRisk,
    required this.knowledgeHints,
  });

  /// 模型给的步号，从 1 开始。解析时要求它是整数，但**不**强制连续——
  /// 连续性由提示词约束；解析器负责报告事实，负责纠正的是上层。
  final int index;

  final String goal;

  /// 模型回复里的原始 actionType 字符串，永远保留（包括未知值）。
  final String actionType;

  /// [actionType] 在词表里查到的动作；未知时为 `null`。
  final CapabilityAction? action;

  final String justification;

  /// 模型声明的自检方式；模型没给时是空字符串。
  final String checkMethod;

  /// 学生卡在这一步的风险，0..1。
  final double stuckRisk;

  final List<String> knowledgeHints;

  /// [actionType] 是否是词表里的已知 key。
  bool get knownAction => action != null;

  Map<String, Object?> toJson() => <String, Object?>{
        'index': index,
        'goal': goal,
        'actionType': actionType,
        'knownAction': knownAction,
        'justification': justification,
        'checkMethod': checkMethod,
        'stuckRisk': stuckRisk,
        'knowledgeHints': knowledgeHints,
      };

  @override
  String toString() => 'ParsedStep($index, $actionType, risk=$stuckRisk)';
}

/// 一次完整的解题思维链。
class ParsedChain {
  const ParsedChain({required this.summary, required this.steps});

  /// 整条思路的一句话概括；模型没给时是空字符串。
  final String summary;

  /// 按模型给出的顺序排列的步骤，至少 1 步。
  final List<ParsedStep> steps;

  /// 从已经解码的 JSON 对象构造。入库读回来的数据可以走这条路，
  /// 校验规则与 [parseChain] 完全一致。
  factory ParsedChain.fromJson(Map<String, Object?> json) {
    final summaryRaw = json['summary'];
    if (summaryRaw != null && summaryRaw is! String) {
      throw const ReasoningParseException('summary 必须是字符串');
    }
    final stepsRaw = json['steps'];
    if (stepsRaw is! List) {
      throw const ReasoningParseException('steps 必须是数组，缺失或类型错误');
    }
    if (stepsRaw.isEmpty) {
      throw const ReasoningParseException('steps 为空：没有步骤的思维链无法用于诊断');
    }
    final steps = <ParsedStep>[];
    for (var i = 0; i < stepsRaw.length; i++) {
      steps.add(_parseStep(stepsRaw[i], i));
    }
    return ParsedChain(
      summary: (summaryRaw as String?)?.trim() ?? '',
      steps: steps,
    );
  }

  /// 把已经匹配上词表的动作去重后列出，用于「这条链用到了哪些能力动作」的统计。
  List<CapabilityAction> get usedActions {
    final seen = <String>{};
    final result = <CapabilityAction>[];
    for (final step in steps) {
      final action = step.action;
      if (action != null && seen.add(action.key)) {
        result.add(action);
      }
    }
    return result;
  }

  /// 未知动作的原始字符串集合，按出现顺序去重。
  List<String> get unknownActionTypes {
    final seen = <String>{};
    final result = <String>[];
    for (final step in steps) {
      if (!step.knownAction && seen.add(step.actionType)) {
        result.add(step.actionType);
      }
    }
    return result;
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'summary': summary,
        'steps': <Object?>[for (final step in steps) step.toJson()],
      };

  @override
  String toString() => 'ParsedChain(${steps.length} steps)';
}

/// 把模型的回复文本解析成 [ParsedChain]。
///
/// 容错与严格并存：
/// * 容忍 ```json 代码块、代码块前后的寒暄、以及 JSON 前后多余的散文；
/// * 空回复、找不到 JSON 对象、JSON 语法错误、steps 缺失/为空/类型错、
///   单个步骤缺 `goal`/`actionType` 或 `stuckRisk` 越界 —— 一律抛
///   [ReasoningParseException]；
/// * `actionType` 未知**不**抛错：保留原字符串并标记 `knownAction == false`。
ParsedChain parseChain(String modelReplyJson) {
  final body = _extractJsonObject(modelReplyJson);
  Object? decoded;
  try {
    decoded = jsonDecode(body);
  } on FormatException catch (error) {
    throw ReasoningParseException(
      'JSON 语法错误：${error.message}',
      rawSnippet: _snippet(body),
    );
  }
  if (decoded is! Map) {
    throw ReasoningParseException(
      '顶层必须是 JSON 对象，实际是 ${decoded.runtimeType}',
      rawSnippet: _snippet(body),
    );
  }
  return ParsedChain.fromJson(decoded.cast<String, Object?>());
}

String _extractJsonObject(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) {
    throw const ReasoningParseException('模型回复为空');
  }
  var text = trimmed;
  final fenced =
      RegExp(r'```[ \t]*(?:json)?[ \t]*\r?\n?([\s\S]*?)```').firstMatch(text);
  if (fenced != null) {
    text = fenced.group(1)!.trim();
  }
  final start = text.indexOf('{');
  final end = text.lastIndexOf('}');
  if (start < 0 || end <= start) {
    throw ReasoningParseException(
      '回复里找不到完整的 JSON 对象',
      rawSnippet: _snippet(text),
    );
  }
  return text.substring(start, end + 1);
}

ParsedStep _parseStep(Object? raw, int position) {
  if (raw is! Map) {
    throw ReasoningParseException(
      'steps[$position] 必须是对象，实际是 ${raw.runtimeType}',
    );
  }
  final map = raw.cast<String, Object?>();
  final path = 'steps[$position]';
  final actionType = _requireText(map['actionType'], '$path.actionType');
  return ParsedStep(
    index: _parseIndex(map['index'], path),
    goal: _requireText(map['goal'], '$path.goal'),
    actionType: actionType,
    action: CapabilityAction.byKey(actionType),
    justification: _optionalText(map['justification'], '$path.justification'),
    checkMethod: _optionalText(map['checkMethod'], '$path.checkMethod'),
    stuckRisk: _parseStuckRisk(map['stuckRisk'], path),
    knowledgeHints: _parseKnowledgeHints(map['knowledgeHints'], path),
  );
}

int _parseIndex(Object? value, String path) {
  if (value is int) {
    return value;
  }
  if (value is double && value == value.truncateToDouble()) {
    return value.toInt();
  }
  throw ReasoningParseException('$path 缺失或不是整数，实际是 $value');
}

String _requireText(Object? value, String path) {
  if (value is! String || value.trim().isEmpty) {
    throw ReasoningParseException('$path 缺失或不是非空字符串，实际是 $value');
  }
  return value.trim();
}

String _optionalText(Object? value, String path) {
  if (value == null) {
    return '';
  }
  if (value is! String) {
    throw ReasoningParseException('$path 必须是字符串，实际是 $value');
  }
  return value.trim();
}

double _parseStuckRisk(Object? value, String path) {
  if (value == null) {
    // 缺失按「不知道」处理，而不是整条链解析失败：这一项是估计值，
    // 不是结构字段，缺它不该毁掉整条思维链。
    return defaultStuckRisk;
  }
  if (value is! num) {
    throw ReasoningParseException('$path.stuckRisk 必须是数字，实际是 $value');
  }
  final risk = value.toDouble();
  if (risk.isNaN || risk < 0 || risk > 1) {
    throw ReasoningParseException('$path.stuckRisk 必须在 0..1 之间，实际是 $value');
  }
  return risk;
}

List<String> _parseKnowledgeHints(Object? value, String path) {
  if (value == null) {
    return const <String>[];
  }
  if (value is! List) {
    throw ReasoningParseException('$path.knowledgeHints 必须是数组，实际是 $value');
  }
  final hints = <String>[];
  for (final hint in value) {
    if (hint is! String) {
      throw ReasoningParseException(
        '$path.knowledgeHints 里必须都是字符串，实际含 ${hint.runtimeType}',
      );
    }
    final text = hint.trim();
    if (text.isNotEmpty) {
      hints.add(text);
    }
  }
  return hints;
}

String _snippet(String text) {
  final flat = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  return flat.length <= 120 ? flat : '${flat.substring(0, 120)}…';
}
