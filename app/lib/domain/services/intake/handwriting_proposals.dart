/// 拍照 → 手写整理的「三类待确认产物」提案（`docs/QUESTION_BANK_DESIGN.md` §7.3–§7.4）。
///
/// 这条通路的产物**不是题目**，而是一张照片整理出来的三样东西：
/// ① 补充标签（挂到既有标签树）② 闪存卡（进复习队列前先确认）③ MindNet 知识点节点。
/// 用户的口径是「确认前不写库」，所以这一层只产出**提案**：模型看完照片后交回
/// 一份严格的 JSON，解析器把它变成结构化的 [HandwritingProposal] 列表，写库是
/// 上层（`features/questions/application/handwriting_proposal_service.dart`）在
/// 用户逐个确认时才做的事。
///
/// 三条纪律写在提示词里，也写在测试里：
///  * **只整理、不编造**：照片里没有的信息不许出现；不确定的地方降低
///    `confidence` 并写进 `rationale`，而不是猜一个像样的答案。
///  * **只挂不改**：标签只能挂到**已有**路径下（`parent_path`），或作为新叶子；
///    不许在整理照片时顺手重构标签树。
///  * **闪存卡必须带卡片**：没有 question/answer 的闪存卡进不了复习队列，所以
///    解析器直接拒收（而不是留一张空壳知识点）。
///
/// 纯 Dart：不 import drift、不 import 数据库、不 import Flutter widget。
/// 唯一的外部依赖是 [ChatMessage]（与 `reasoning_prompt.dart` 同一条先例，
/// 协议只存在于一处）。
library;

import 'dart:convert';

import 'package:furnace/features/ai/domain/model_adapter.dart';

/// 三类待确认产物。`storageKey` 是模型看到的键，`labelZh` 只给人看。
enum HandwritingProposalKind {
  tag('tag', '标签'),
  knowledgePoint('knowledge_point', '知识点'),
  flashcard('flashcard', '闪存卡');

  const HandwritingProposalKind(this.storageKey, this.labelZh);

  /// JSON 契约里的取值。
  final String storageKey;

  /// 界面上的中文名。
  final String labelZh;

  /// 未知名返回 `null`——调用方决定是拒收还是记录，不做静默降级。
  static HandwritingProposalKind? byKey(String? key) {
    final clean = key?.trim();
    if (clean == null || clean.isEmpty) {
      return null;
    }
    for (final kind in values) {
      if (kind.storageKey == clean) {
        return kind;
      }
    }
    return null;
  }

  /// 供错误文案列出可用取值。
  static String get keysLabel =>
      values.map((kind) => kind.storageKey).join(' / ');
}

/// 闪存卡提案里的一张卡片。
///
/// 题型沿用知识模块已有的三种（与 `CreateKnowledgeCardsTool.cardTypes` 一致）；
/// 未知题型**不改写**成默认值，而是解析失败——把选择题悄悄变成填空题，用户看到
/// 的卡片就不是他确认过的那张。
class HandwritingCardDraft {
  const HandwritingCardDraft({
    required this.question,
    required this.answer,
    this.type = 'essay',
  });

  final String question;
  final String answer;
  final String type;

  /// 从 [toJson] 的输出还原（持久化用）。
  ///
  /// 与解析模型回复同一套严格口径：缺 question/answer 或题型不在册就抛
  /// [HandwritingProposalParseException]。库里存坏一张卡片时宁可报错，也不把
  /// 它悄悄降级成默认题型——用户确认过的题型不能被改写。
  factory HandwritingCardDraft.fromJson(Map<String, Object?> json) {
    final question = json['question']?.toString().trim() ?? '';
    final answer = json['answer']?.toString().trim() ?? '';
    if (question.isEmpty || answer.isEmpty) {
      throw const HandwritingProposalParseException('卡片缺少 question 或 answer');
    }
    final type = json['type']?.toString().trim() ?? '';
    final resolved = type.isEmpty ? 'essay' : type;
    if (!_cardTypes.contains(resolved)) {
      throw HandwritingProposalParseException(
        '卡片 type 未知：`$resolved`。可用：${_cardTypes.join(' / ')}',
      );
    }
    return HandwritingCardDraft(
      question: question,
      answer: answer,
      type: resolved,
    );
  }

  Map<String, Object?> toJson() => {
        'question': question,
        'answer': answer,
        'type': type,
      };
}

/// 一条待确认产物。
class HandwritingProposal {
  const HandwritingProposal({
    required this.id,
    required this.kind,
    required this.titleZh,
    this.rationaleZh = '',
    this.confidence = defaultProposalConfidence,
    this.fields = const <String, String>{},
    this.cards = const <HandwritingCardDraft>[],
    this.sourceRef = '',
  });

  /// 集合内唯一、确定性（由 kind + 序号生成；同一次解析必得同一 id）。
  final String id;

  final HandwritingProposalKind kind;

  /// 一行标题（标签名 / 知识点标题 / 闪存卡标题）。
  final String titleZh;

  /// 为什么建议它——显示给用户的就是这一行，**不重写**。
  final String rationaleZh;

  /// 0..1；缺失取 [defaultProposalConfidence]（中性），不当作"很确定"。
  final double confidence;

  /// 其余字段，键与 JSON 契约一致（如 `parent_path` / `content`）。
  final Map<String, String> fields;

  /// 仅闪存卡有：卡片列表（至少一张）。
  final List<HandwritingCardDraft> cards;

  /// 来源照片的相对路径（`handwriting_intake/...`），用于回显与重跑。
  final String sourceRef;

  /// 从 [toJson] 的输出还原（持久化用）。
  ///
  /// 与解析模型回复同一套严格口径：`kind`/`id`/`title` 缺一不可，`fields`、
  /// `cards` 结构不对照样抛异常。存储层读回坏行时**不能**静默跳过——那会让
  /// 用户看到"整理过了"却少了一条自己确认过的产物。
  factory HandwritingProposal.fromJson(
    Map<String, Object?> json, {
    int index = 0,
  }) {
    final kind = HandwritingProposalKind.byKey(json['kind']?.toString());
    if (kind == null) {
      final raw = json['kind']?.toString().trim() ?? '';
      throw HandwritingProposalParseException(
        '`proposals[$index].kind` 未知：`$raw`。可用：${HandwritingProposalKind.keysLabel}',
      );
    }
    final id = json['id']?.toString().trim() ?? '';
    if (id.isEmpty) {
      throw HandwritingProposalParseException(
        '`proposals[$index]`（${kind.storageKey}）缺少 id',
      );
    }
    return _proposalFrom(json, index, kind, id: id);
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'kind': kind.storageKey,
        'title': titleZh,
        'rationale': rationaleZh,
        'confidence': confidence,
        'fields': fields,
        if (cards.isNotEmpty)
          'cards': [for (final card in cards) card.toJson()],
        'source_ref': sourceRef,
      };

  @override
  String toString() => 'HandwritingProposal(${kind.storageKey}, $id, $titleZh, '
      'confidence=${confidence.toStringAsFixed(2)})';
}

/// 缺失 `confidence` 时的中性值：0.5 = 「不知道」，不是 1.0 = 「很确定」。
const double defaultProposalConfidence = 0.5;

/// 一次整理的全部提案。
///
/// 解析是**严格**的：结构性错误一律抛 [HandwritingProposalParseException]，
/// 不做"扔掉坏条目、留下好条目"的静默降级——悄悄少写一条，用户以为整理完了，
/// 比直接报错更糟。所以这里没有"被丢弃条目"的字段。
class HandwritingProposalSet {
  const HandwritingProposalSet({
    required this.sourceRef,
    required this.proposals,
  });

  final String sourceRef;
  final List<HandwritingProposal> proposals;

  bool get isEmpty => proposals.isEmpty;

  /// 从 [toJson] 的输出还原（持久化用）。
  factory HandwritingProposalSet.fromJson(Map<String, Object?> json) {
    final raw = json['proposals'];
    if (raw is! List) {
      throw const HandwritingProposalParseException(
        '缺少 `proposals` 数组（没有可整理的内容时也要交回空数组）',
      );
    }
    final proposals = <HandwritingProposal>[];
    for (var i = 0; i < raw.length; i++) {
      final entry = raw[i];
      if (entry is! Map) {
        throw HandwritingProposalParseException('`proposals[$i]` 不是对象');
      }
      proposals.add(
        HandwritingProposal.fromJson(Map<String, Object?>.from(entry),
            index: i),
      );
    }
    return HandwritingProposalSet(
      sourceRef: json['source_ref']?.toString() ?? '',
      proposals: List<HandwritingProposal>.unmodifiable(proposals),
    );
  }

  int countOf(HandwritingProposalKind kind) =>
      proposals.where((proposal) => proposal.kind == kind).length;

  Map<String, Object?> toJson() => {
        'source_ref': sourceRef,
        'proposals': [for (final proposal in proposals) proposal.toJson()],
      };
}

/// 回复不符合契约。可 catch 的类型化异常——调用方要能把「模型胡说」和
/// 「网络失败」分开处理（与 [ReasoningParseException] 同一口径）。
class HandwritingProposalParseException implements Exception {
  const HandwritingProposalParseException(this.message);

  final String message;

  @override
  String toString() => 'HandwritingProposalParseException: $message';
}

/// 解析器期待的 JSON 契约，**逐字**出现在提示词里。
///
/// 改这里就等于改协议：解析器、提示词、文档要一起动。
const String handwritingProposalJsonContract = '''
{
  "proposals": [
    {
      "kind": "tag",
      "title": "动量守恒",
      "rationale": "照片里反复出现这个词，标签树里没有",
      "confidence": 0.8,
      "fields": {"parent_path": "文化课/物理/力学", "description": "照片里的定义"}
    },
    {
      "kind": "knowledge_point",
      "title": "动量守恒的条件",
      "rationale": "照片第 3 段在讲这个点",
      "confidence": 0.7,
      "fields": {"content": "把照片里那段原文整理后的内容", "tag_path": "文化课/物理/力学/动量守恒"}
    },
    {
      "kind": "flashcard",
      "title": "动量守恒",
      "rationale": "这一页值得做成背诵卡片",
      "confidence": 0.8,
      "fields": {"content": "整理后的正文（可被挖空的关键信息）", "source": "照片：hw-xxx.png"},
      "cards": [
        {"question": "动量守恒的条件是什么？", "answer": "系统所受合外力为零。", "type": "essay"}
      ]
    }
  ]
}''';

/// 构造「看照片 → 交回三类产物提案」的两条消息：`[system, user]`。
///
/// 参数：
/// * [fileName] 照片文件名，写进 user 消息，让模型的 `source` 字段有据可依。
/// * [mime]、[base64] 图片本体（已经是 base64，不含 `data:` 前缀）。
/// * [existingTagPaths] 标签树里已有的路径（POSIX 分隔），写进 system 消息，
///   让模型优先挂到已有路径下而不是造一棵新树。
/// * [existingKnowledgePointTitles] 已有知识点标题，避免重复建点。
List<ChatMessage> handwritingProposalMessages({
  required String fileName,
  required String mime,
  required String base64,
  List<String> existingTagPaths = const <String>[],
  List<String> existingKnowledgePointTitles = const <String>[],
}) {
  final tags = _bullets(existingTagPaths, fallback: '（标签树现在还是空的）');
  final points = _bullets(existingKnowledgePointTitles, fallback: '（还没有知识点）');

  final system = '''
你是一个「手写/纸质材料整理员」。用户给你一张照片，你要把它整理成**待确认的产物提案**，
交回一份 JSON。用户会逐条确认后才会写进数据库，所以你的任务是把照片看懂、说清楚，
**不是**替用户决定。

铁律（违反任何一条，这次整理就是失败的）：
1. 只整理照片里**真实存在**的内容。照片里没有的信息一律不许写出来——不要补充定义、
   不要补全例题、不要用常识填空。看不清的地方就降低 confidence 并在 rationale 里说明"看不清"。
2. 你不做题、不出题、不改写题意。照片里的题目原样引用即可。
3. 标签只能挂到**已有**路径下（fields.parent_path 用下面列出的路径之一），
   或者作为新的顶层叶子；不要为了整理这张照片重构标签树。
4. 闪存卡必须给出 cards（至少一张），question/answer 都必须是照片里的内容；
   答案要能在不看照片时独立读懂（不要写"如上图"）。
5. 三种 kind 只允许：tag / knowledge_point / flashcard。

已有的标签路径（parent_path 只能从中选，空字符串表示新建顶层标签）：
$tags

已有的知识点标题（不要重复建点）：
$points

只输出 JSON，不要解释、不要 Markdown 代码块之外的东西。契约：
$handwritingProposalJsonContract''';

  final userText = '''
这是一张手写/纸质材料的照片，文件名：$fileName。
请把它整理成三类待确认产物（标签 / 知识点 / 闪存卡），按契约交回 JSON。''';

  return <ChatMessage>[
    ChatMessage.system(system),
    ChatMessage.user(
      userText,
      images: <ChatImagePart>[ChatImagePart(mime: mime, base64: base64)],
    ),
  ];
}

/// 解析模型回复。
///
/// 容忍 ```json 代码块与前后寒暄；对**结构性错误**抛
/// [HandwritingProposalParseException]。空提案列表（`{"proposals": []}`）是合法
/// 结果——照片里没有可整理的东西也是一种诚实回答。
HandwritingProposalSet parseHandwritingProposals(
  String raw, {
  required String sourceRef,
}) {
  final object = _extractJsonObject(raw);
  if (object == null) {
    throw const HandwritingProposalParseException('回复里找不到 JSON 对象');
  }

  final decoded = _decodeObject(object);
  final rawProposals = decoded['proposals'];
  if (rawProposals is! List) {
    throw const HandwritingProposalParseException(
      '缺少 `proposals` 数组（没有可整理的内容时也要交回空数组）',
    );
  }

  final proposals = <HandwritingProposal>[];
  for (var i = 0; i < rawProposals.length; i++) {
    final entry = rawProposals[i];
    if (entry is! Map) {
      throw HandwritingProposalParseException('`proposals[$i]` 不是对象');
    }
    proposals.add(_parseOne(Map<String, Object?>.from(entry), i));
  }

  return HandwritingProposalSet(
    sourceRef: sourceRef,
    proposals: List<HandwritingProposal>.unmodifiable(proposals),
  );
}

HandwritingProposal _parseOne(Map<String, Object?> entry, int index) {
  final kind = HandwritingProposalKind.byKey(entry['kind']?.toString());
  if (kind == null) {
    final raw = entry['kind']?.toString().trim() ?? '';
    throw HandwritingProposalParseException(
      '`proposals[$index].kind` 未知：`$raw`。可用：${HandwritingProposalKind.keysLabel}',
    );
  }
  return _proposalFrom(entry, index, kind, id: '${kind.storageKey}-$index');
}

/// 解析模型回复与从库里还原**共用**的那一段：`kind` 已定、`id` 已定，
/// 只负责剩下的字段校验。两处分开写迟早会出现"模型回复严、库里读回松"的裂缝。
HandwritingProposal _proposalFrom(
  Map<String, Object?> entry,
  int index,
  HandwritingProposalKind kind, {
  required String id,
}) {
  final title = entry['title']?.toString().trim() ?? '';
  if (title.isEmpty) {
    throw HandwritingProposalParseException(
      '`proposals[$index]`（${kind.storageKey}）缺少 title',
    );
  }

  final fields = <String, String>{};
  final rawFields = entry['fields'];
  if (rawFields != null) {
    if (rawFields is! Map) {
      throw HandwritingProposalParseException(
        '`proposals[$index].fields` 不是对象',
      );
    }
    for (final field in rawFields.entries) {
      final value = field.value?.toString().trim() ?? '';
      if (value.isNotEmpty) {
        fields[field.key.toString()] = value;
      }
    }
  }

  final cards = _parseCards(entry['cards'], index, kind);
  _requireFields(kind, fields, index);

  return HandwritingProposal(
    id: id,
    kind: kind,
    titleZh: title,
    rationaleZh: entry['rationale']?.toString().trim() ?? '',
    confidence: _parseConfidence(entry['confidence'], index),
    fields: Map<String, String>.unmodifiable(fields),
    cards: List<HandwritingCardDraft>.unmodifiable(cards),
    sourceRef: entry['source_ref']?.toString().trim() ?? '',
  );
}

List<HandwritingCardDraft> _parseCards(
  Object? raw,
  int index,
  HandwritingProposalKind kind,
) {
  if (kind != HandwritingProposalKind.flashcard) {
    if (raw != null) {
      throw HandwritingProposalParseException(
        '`proposals[$index]`（${kind.storageKey}）不该有 cards',
      );
    }
    return const <HandwritingCardDraft>[];
  }

  if (raw is! List || raw.isEmpty) {
    throw HandwritingProposalParseException(
      '`proposals[$index]` 是闪存卡但没有 cards：没有 question/answer 的卡片进不了复习队列',
    );
  }

  final cards = <HandwritingCardDraft>[];
  for (var i = 0; i < raw.length; i++) {
    final entry = raw[i];
    if (entry is! Map) {
      throw HandwritingProposalParseException(
        '`proposals[$index].cards[$i]` 不是对象',
      );
    }
    final question = entry['question']?.toString().trim() ?? '';
    final answer = entry['answer']?.toString().trim() ?? '';
    if (question.isEmpty || answer.isEmpty) {
      throw HandwritingProposalParseException(
        '`proposals[$index].cards[$i]` 缺少 question 或 answer',
      );
    }
    final type = entry['type']?.toString().trim() ?? '';
    final resolved = type.isEmpty ? 'essay' : type;
    if (!_cardTypes.contains(resolved)) {
      throw HandwritingProposalParseException(
        '`proposals[$index].cards[$i].type` 未知：`$resolved`。可用：${_cardTypes.join(' / ')}',
      );
    }
    cards.add(HandwritingCardDraft(
      question: question,
      answer: answer,
      type: resolved,
    ));
  }
  return cards;
}

/// 与 `CreateKnowledgeCardsTool.cardTypes` 同一组取值。
const Set<String> _cardTypes = <String>{'fill_blank', 'mcq', 'essay'};

void _requireFields(
  HandwritingProposalKind kind,
  Map<String, String> fields,
  int index,
) {
  switch (kind) {
    case HandwritingProposalKind.tag:
      return;
    case HandwritingProposalKind.knowledgePoint:
      _require(fields, 'content', kind, index, hint: '知识点的正文必须来自照片，不能留空');
    case HandwritingProposalKind.flashcard:
      _require(fields, 'content', kind, index, hint: '闪存卡正文是以后挖空的依据，必须来自照片');
  }
}

void _require(
  Map<String, String> fields,
  String key,
  HandwritingProposalKind kind,
  int index, {
  required String hint,
}) {
  if ((fields[key] ?? '').trim().isEmpty) {
    throw HandwritingProposalParseException(
      '`proposals[$index]`（${kind.storageKey}）缺少 fields.$key：$hint',
    );
  }
}

double _parseConfidence(Object? raw, int index) {
  if (raw == null) {
    return defaultProposalConfidence;
  }
  final value = raw is num ? raw.toDouble() : double.tryParse('$raw');
  if (value == null || value.isNaN) {
    throw HandwritingProposalParseException(
      '`proposals[$index].confidence` 不是数字：`$raw`',
    );
  }
  return value.clamp(0.0, 1.0).toDouble();
}

/// 找到回复里最外层的 `{...}`；没有就返回 `null`。
String? _extractJsonObject(String raw) {
  final start = raw.indexOf('{');
  final end = raw.lastIndexOf('}');
  if (start < 0 || end <= start) {
    return null;
  }
  return raw.substring(start, end + 1);
}

Map<String, Object?> _decodeObject(String text) {
  final Object? decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException catch (error) {
    throw HandwritingProposalParseException('JSON 解析失败：${error.message}');
  }
  if (decoded is! Map) {
    throw const HandwritingProposalParseException('回复的 JSON 顶层不是对象');
  }
  return Map<String, Object?>.from(decoded);
}

String _bullets(List<String> items, {required String fallback}) {
  if (items.isEmpty) {
    return fallback;
  }
  final head = items.take(60).map((item) => '- $item').join('\n');
  if (items.length <= 60) {
    return head;
  }
  return '$head\n- （还有 ${items.length - 60} 条省略）';
}
