/// 拍照 → 手写整理的「四类待确认产物」提案（`docs/QUESTION_BANK_DESIGN.md` §7.3–§7.4）。
///
/// 这条通路整理一张照片，产出四种**待确认**的东西：
/// ① 补充标签（挂到既有标签树）② 闪存卡（进复习队列前先确认）③ MindNet 知识点节点
/// ④ 题目草稿（照片本身就是题目时；用户逐个确认后才会入库）。
/// 用户的口径是「确认前不写库」，所以这一层只产出**提案**：模型看完照片后交回
/// 一份严格的 JSON，解析器把它变成结构化的 [HandwritingProposal] 列表，写库是
/// 上层（`features/questions/application/handwriting_proposal_service.dart`）在
/// 用户逐个确认时才做的事。
///
/// 三条纪律写在提示词里，也写在测试里：
///  * **只整理、不编造**：照片里没有的信息不许出现；不确定的地方降低
///    `confidence` 并写进 `rationale`，而不是猜一个像样的答案。
///  * **题目只誊写**：题干/选项/答案/解析必须是照片原文；不改写题意、不补全
///    缺失选项、不做题判对错。看不清就降 `confidence`，没有答案/解析就省略字段。
///  * **题干里的内联选项会确定性抽出**：选项直接写在题干里（「A．… B．…」）时，
///    解析层抽成结构化 `options`；`fields.stem` 存剥离后的题面、`fields.stem_original`
///    保留原题面（追溯用）。抽不出就原样保留、不猜、不抛异常。
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

/// 四类待确认产物。`storageKey` 是模型看到的键，`labelZh` 只给人看。
enum HandwritingProposalKind {
  tag('tag', '标签'),
  knowledgePoint('knowledge_point', '知识点'),
  flashcard('flashcard', '闪存卡'),
  question('question', '题目');

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

/// 题目提案里的一个选项。
///
/// 只誊写照片里本来就有选项：照片没有选项（纯文字题、解答题）时整个 `options`
/// 字段省略，**不**替模型补齐。label 归一成单个大写字母（`trim` + `toUpperCase`），
/// 内容 `trim` 后必须非空——空选项说明模型没看清，宁可报错也不入库一个空壳。
class HandwritingOptionDraft {
  const HandwritingOptionDraft({
    required this.label,
    required this.content,
  });

  /// 单个大写字母 A-Z。
  final String label;

  /// 选项正文（照片原文，不改写）。
  final String content;

  /// 从 [toJson] 的输出还原（持久化用）。
  ///
  /// 与解析模型回复同一套严格口径：label 不是单个字母、content 为空都抛
  /// [HandwritingProposalParseException]。[path] 只用于错误文案里的字段路径。
  factory HandwritingOptionDraft.fromJson(
    Map<String, Object?> json, {
    String path = 'options',
  }) {
    final rawLabel = json['label']?.toString() ?? '';
    final label = rawLabel.trim().toUpperCase();
    if (!_optionLabelPattern.hasMatch(label)) {
      throw HandwritingProposalParseException(
        '`$path.label` 不合法：`$rawLabel`。label 必须是单个大写字母 A-Z',
      );
    }
    final content = json['content']?.toString().trim() ?? '';
    if (content.isEmpty) {
      throw HandwritingProposalParseException(
        '`$path.content` 为空：选项内容必须来自照片',
      );
    }
    return HandwritingOptionDraft(label: label, content: content);
  }

  Map<String, Object?> toJson() => {
        'label': label,
        'content': content,
      };
}

final RegExp _optionLabelPattern = RegExp(r'^[A-Z]$');

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
    this.options = const <HandwritingOptionDraft>[],
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

  /// 仅题目有：选项列表（可以为空 = 纯文字题/解答题；非空时 A、B、C… 连续）。
  ///
  /// 解析/读回路径都传 [List.unmodifiable]；直接 `const` 构造时调用方自己保证
  /// 不修改传入列表（与 [cards] 同一约定）。
  final List<HandwritingOptionDraft> options;

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
        if (options.isNotEmpty)
          'options': [for (final option in options) option.toJson()],
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
    },
    {
      "kind": "question",
      "title": "第 3 题（动量守恒）",
      "rationale": "照片这一页就是一道完整的选择题，题干/选项/答案/解析都拍到了",
      "confidence": 0.83,
      "fields": {
        "stem": "照片里的题干原文（含小问），原样誊写",
        "answer": "照片里给出的答案",
        "solution": "照片里给出的解析"
      },
      "options": [
        {"label": "A", "content": "选项 A 的照片原文"},
        {"label": "B", "content": "选项 B 的照片原文"},
        {"label": "C", "content": "选项 C 的照片原文"},
        {"label": "D", "content": "选项 D 的照片原文"}
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
5. 四种 kind 只允许：tag / knowledge_point / flashcard / question。
6. 题目提案（kind=question）只做誊写：题干/选项/答案/解析必须来自照片原文，
   不改写题意、不补全缺失选项、不做题、不判断对错；看不清就在 rationale 写明
   并降低 confidence；照片里没有答案/解析就省略对应字段，绝不自己解题补上。

已有的标签路径（parent_path 只能从中选，空字符串表示新建顶层标签）：
$tags

已有的知识点标题（不要重复建点）：
$points

只输出 JSON，不要解释、不要 Markdown 代码块之外的东西。契约：
$handwritingProposalJsonContract''';

  final userText = '''
这是一张手写/纸质材料的照片，文件名：$fileName。
请把它整理成四类待确认产物（标签 / 知识点 / 闪存卡 / 题目），按契约交回 JSON。''';

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
  final rawOptions = entry['options'];
  var options = _parseOptions(rawOptions, index, kind);
  if (kind == HandwritingProposalKind.question && rawOptions == null) {
    // 模型没给 options 时，从题面里确定性抽内联选项。失败（抽不出 / 不连续）
    // 就原样保留题面，不猜、不抛异常——宁可让用户看到「无选项」，也不能把
    // 正文里的「A、B两点」误当选项。
    final stem = fields['stem'];
    if (stem != null) {
      final extraction = extractInlineOptions(stem);
      if (extraction.succeeded) {
        // 预览与入库都读 fields.stem，所以这里存剥离后的题面；原题面另存一份
        // 供追溯（旧三类产物与无内联选项的题目不会出现这个键，输出逐字节不变）。
        fields['stem'] = extraction.stem;
        fields['stem_original'] = stem;
        options = extraction.options;
      }
    }
  }
  _requireFields(kind, fields, index);

  return HandwritingProposal(
    id: id,
    kind: kind,
    titleZh: title,
    rationaleZh: entry['rationale']?.toString().trim() ?? '',
    confidence: _parseConfidence(entry['confidence'], index),
    fields: Map<String, String>.unmodifiable(fields),
    cards: List<HandwritingCardDraft>.unmodifiable(cards),
    options: List<HandwritingOptionDraft>.unmodifiable(options),
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

/// 解析题目选项：只有 question 允许；出现就必须是 1..26 条、label 从 A 连续。
///
/// 缺省（照片里没有选项）合法；空数组不合法——模型给了 `options: []` 说明它
/// 要么没看清、要么在凑字段，两种都不该被静默接受。
List<HandwritingOptionDraft> _parseOptions(
  Object? raw,
  int index,
  HandwritingProposalKind kind,
) {
  if (kind != HandwritingProposalKind.question) {
    if (raw != null) {
      throw HandwritingProposalParseException(
        '`proposals[$index]`（${kind.storageKey}）不该有 options',
      );
    }
    return const <HandwritingOptionDraft>[];
  }
  if (raw == null) {
    return const <HandwritingOptionDraft>[];
  }
  if (raw is! List) {
    throw HandwritingProposalParseException(
      '`proposals[$index].options` 不是数组',
    );
  }
  if (raw.isEmpty) {
    throw HandwritingProposalParseException(
      '`proposals[$index]`（question）的 options 是空数组：照片里有选项才写，没有就省略',
    );
  }
  if (raw.length > 26) {
    throw HandwritingProposalParseException(
      '`proposals[$index].options` 最多 26 条（实际 ${raw.length} 条）',
    );
  }
  final options = <HandwritingOptionDraft>[];
  for (var i = 0; i < raw.length; i++) {
    final entry = raw[i];
    if (entry is! Map) {
      throw HandwritingProposalParseException(
        '`proposals[$index].options[$i]` 不是对象',
      );
    }
    options.add(HandwritingOptionDraft.fromJson(
      Map<String, Object?>.from(entry),
      path: 'proposals[$index].options[$i]',
    ));
  }
  final expected = <String>[];
  for (var i = 0; i < options.length; i++) {
    expected.add(String.fromCharCode(65 + i));
  }
  final labels = options.map((option) => option.label).toList();
  final duplicate = _firstDuplicate(labels);
  if (duplicate != null) {
    throw HandwritingProposalParseException(
      '`proposals[$index].options` label 重复：`$duplicate`',
    );
  }
  for (var i = 0; i < options.length; i++) {
    if (options[i].label != expected[i]) {
      throw HandwritingProposalParseException(
        '`proposals[$index].options[$i].label` 应为 `${expected[i]}`（选项要按 A、B、C… 连续）',
      );
    }
  }
  return options;
}

String? _firstDuplicate(List<String> values) {
  final seen = <String>{};
  for (final value in values) {
    if (!seen.add(value)) {
      return value;
    }
  }
  return null;
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
    case HandwritingProposalKind.question:
      _require(fields, 'stem', kind, index, hint: '题面必须来自照片，不能留空');
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

// ---------------------------------------------------------------------------
// 题干内联选项抽取
// ---------------------------------------------------------------------------

/// 从题面里抽取内联选项的结果。
///
/// [options] 非空即抽取成功；失败时 [failureReason] 是一句可直接显示的中文原因，
/// [stem] 原样返回调用方传入的文本（**不猜、不抛异常**）。成功时：
///  * [stem] = 第一个选项标记之前的文本（只去掉首尾空白，内部换行与 `$...$`
///    公式原样保留）；
///  * [options] 的 label 已归一成半角大写 A-Z，content 是标记之间文本的 trim。
class InlineOptionExtraction {
  const InlineOptionExtraction({
    required this.stem,
    required this.options,
    this.failureReason,
  });

  /// 成功：剥离选项后的题面；失败：调用方传入的原文本。
  final String stem;

  /// 成功：A 起连续的选项；失败：空列表（不猜部分结果）。
  final List<HandwritingOptionDraft> options;

  /// 成功为 null；失败是一句中文原因。
  final String? failureReason;

  /// 是否抽到了至少两个连续的选项。
  bool get succeeded => options.isNotEmpty;
}

/// 从题干文本里确定性抽取「A．… B．…」这类内联选项。
///
/// 规则（与题目的「只誊写、不编造」一致）：
///  1. 只认**行首/段首**的选项标记（允许行首缩进）；同一行里连续写多个选项时，
///     后续标记必须紧跟在同一行上一个已识别标记之后（「A．甲 B．乙」可以，
///     「已知 A．甲」里的 A 不算——那更像正文）。
///  2. 字母认半角 A-Z 与全角 Ａ-Ｚ；分隔符认 `.` `．` `、` `)` `）` `:` `：`。
///  3. `$...$`、`$$...$$`、`\(...\)`、`\[...\]` 公式区间内的字母不参与识别；
///     `【答案】` / `答案：` / `【解析】` 等答案解析行的整行都不参与；
///     答案解析行也不会被算进最后一个选项的内容。
///  4. 必须至少 2 个选项、字母从 A 起连续、不重复、不跳号。同一段文本里取
///     「第一段以 A 起、至少 2 个连续标记」的链当选项，所以题干里行首的
///     「A、B两点」这种枚举（只有一个 A 是选项标记）不会被误当选项链，
///     它会留在题面里；链后若又出现更大的字母（跳号）或重复字母则整体判失败。
///  5. 已知限制：题面和选项写在**同一行**、且第一个选项标记不在行首时
///     （如「题干（ ）A．甲 B．乙」）不抽——只认行首/段首起步的选项；
///     宁可让用户看到「无选项」，也不把正文里的字母当选项。
///
/// 纯函数：同一输入永远同一输出；不抛异常。
InlineOptionExtraction extractInlineOptions(String raw) {
  if (raw.trim().isEmpty) {
    return InlineOptionExtraction(
      stem: raw,
      options: const <HandwritingOptionDraft>[],
      failureReason: '题面是空的，没有可抽取的内容',
    );
  }

  final formulaMask = _buildFormulaMask(raw);
  final answerStarts = _answerLineStarts(raw);
  final answerMask = _buildAnswerLineMask(raw, answerStarts);
  final scanUnits = List<int>.filled(raw.length, _spaceUnit);
  for (var i = 0; i < raw.length; i++) {
    if (!formulaMask[i] && !answerMask[i]) {
      scanUnits[i] = raw.codeUnitAt(i);
    }
  }
  final scan = String.fromCharCodes(scanUnits);

  final candidates = <_InlineMarker>[];
  for (final match in _inlineOptionPattern.allMatches(scan)) {
    final letterUnit = match.group(1)!.codeUnitAt(0);
    final letterIndex = letterUnit >= _fullWidthUpperA
        ? letterUnit - _fullWidthUpperA
        : letterUnit - _upperA;
    final start = match.start;
    final lineStart = _lineStartIndexOf(raw, start);
    final atLineStart = _isIndentOnly(raw, lineStart, start);
    var inlineAfterPrevious = false;
    if (!atLineStart && candidates.isNotEmpty && start > 0) {
      final previous = candidates.last;
      inlineAfterPrevious = _isInlineSpaceUnit(raw.codeUnitAt(start - 1)) &&
          _lineStartIndexOf(raw, previous.start) == lineStart;
    }
    if (!atLineStart && !inlineAfterPrevious) {
      continue;
    }
    candidates.add(_InlineMarker(
      start: start,
      end: match.end,
      letterIndex: letterIndex,
    ));
  }

  if (candidates.isEmpty) {
    return InlineOptionExtraction(
      stem: raw,
      options: const <HandwritingOptionDraft>[],
      failureReason: '没找到行首或段首的选项标记',
    );
  }

  // 取「第一段以 A 起、至少 2 个连续标记」的链：题干里的行首枚举（如
  // 「A、B两点」）可能先出现一个孤立的 A，真正的选项从后面某个 A 才开始。
  var bestStart = -1;
  var bestLength = 0;
  for (var i = 0; i < candidates.length; i++) {
    if (candidates[i].letterIndex != 0) {
      continue;
    }
    var end = i;
    var expected = 1;
    while (end + 1 < candidates.length &&
        candidates[end + 1].letterIndex == expected) {
      end += 1;
      expected += 1;
    }
    final runLength = end - i + 1;
    if (runLength >= 2) {
      bestStart = i;
      bestLength = runLength;
      break;
    }
    if (bestStart < 0) {
      bestStart = i;
      bestLength = runLength;
    }
  }

  if (bestStart < 0) {
    final first = candidates.first.letter;
    return InlineOptionExtraction(
      stem: raw,
      options: const <HandwritingOptionDraft>[],
      failureReason: '选项必须从 A 开始，第一个标记是「$first」（选项要按 A、B、C… 连续）',
    );
  }

  if (bestLength < 2) {
    return InlineOptionExtraction(
      stem: raw,
      options: const <HandwritingOptionDraft>[],
      failureReason: _describeShortRun(candidates, bestStart),
    );
  }

  final lastIndex = bestStart + bestLength - 1;
  final tailIndex = lastIndex + 1;
  if (tailIndex < candidates.length) {
    final tail = candidates[tailIndex];
    final lastLetterIndex = candidates[lastIndex].letterIndex;
    if (tail.letterIndex <= lastLetterIndex) {
      return InlineOptionExtraction(
        stem: raw,
        options: const <HandwritingOptionDraft>[],
        failureReason: '选项字母重复：「${tail.letter}」出现了不止一次',
      );
    }
    if (tail.letterIndex > lastLetterIndex) {
      final missing = <String>[];
      for (var index = lastLetterIndex + 1; index < tail.letterIndex; index++) {
        missing.add(String.fromCharCode(_upperA + index));
      }
      final missingLabel = missing.map((letter) => '「$letter」').join('、');
      return InlineOptionExtraction(
        stem: raw,
        options: const <HandwritingOptionDraft>[],
        failureReason:
            '选项字母不连续：「${candidates[lastIndex].letter}」之后直接是「${tail.letter}」，'
            '缺少$missingLabel（选项要按 A、B、C… 连续）',
      );
    }
  }

  final stem = raw.substring(0, candidates[bestStart].start).trim();
  if (stem.isEmpty) {
    return InlineOptionExtraction(
      stem: raw,
      options: const <HandwritingOptionDraft>[],
      failureReason: '选项标记前面没有题干：抽出的选项不能没有题面',
    );
  }

  final options = <HandwritingOptionDraft>[];
  for (var i = bestStart; i <= lastIndex; i++) {
    final marker = candidates[i];
    var contentEnd = raw.length;
    if (i + 1 < candidates.length) {
      contentEnd = candidates[i + 1].start;
    }
    final answerStart = _firstAnswerLineStartAfter(answerStarts, marker.end);
    if (answerStart != null && answerStart < contentEnd) {
      contentEnd = answerStart;
    }
    final content = raw.substring(marker.end, contentEnd).trim();
    if (content.isEmpty) {
      return InlineOptionExtraction(
        stem: raw,
        options: const <HandwritingOptionDraft>[],
        failureReason: '选项「${marker.letter}」的内容为空：标记后面没有文字',
      );
    }
    options.add(HandwritingOptionDraft(
      label: marker.letter,
      content: content,
    ));
  }

  return InlineOptionExtraction(
    stem: stem,
    options: List<HandwritingOptionDraft>.unmodifiable(options),
  );
}

const int _spaceUnit = 0x20;
const int _tabUnit = 0x09;
const int _ideographicSpaceUnit = 0x3000;
const int _lineBreakUnit = 0x0A;
const int _dollarUnit = 0x24;
const int _backslashUnit = 0x5C;
const int _openParenUnit = 0x28;
const int _openBracketUnit = 0x5B;
const int _upperA = 0x41;
const int _fullWidthUpperA = 0xFF21;

final String _lineBreakText = String.fromCharCode(_lineBreakUnit);

final RegExp _inlineOptionPattern = RegExp('([A-ZＡ-Ｚ])([.．、)）:：])');

bool _isInlineSpaceUnit(int unit) {
  return unit == _spaceUnit ||
      unit == _tabUnit ||
      unit == _ideographicSpaceUnit;
}

/// 一个候选选项标记：字母 + 分隔符，位置按 UTF-16 code unit 计。
class _InlineMarker {
  const _InlineMarker({
    required this.start,
    required this.end,
    required this.letterIndex,
  });

  final int start;
  final int end;
  final int letterIndex;

  String get letter => String.fromCharCode(_upperA + letterIndex);
}

int _lineStartIndexOf(String raw, int index) {
  var i = index - 1;
  while (i >= 0) {
    if (raw.codeUnitAt(i) == _lineBreakUnit) {
      return i + 1;
    }
    i -= 1;
  }
  return 0;
}

bool _isIndentOnly(String raw, int lineStart, int index) {
  for (var i = lineStart; i < index; i++) {
    if (!_isInlineSpaceUnit(raw.codeUnitAt(i))) {
      return false;
    }
  }
  return true;
}

List<bool> _buildFormulaMask(String raw) {
  final mask = List<bool>.filled(raw.length, false);
  var i = 0;
  while (i < raw.length) {
    final unit = raw.codeUnitAt(i);
    if (unit == _backslashUnit && i + 1 < raw.length) {
      final next = raw.codeUnitAt(i + 1);
      if (next == _openParenUnit) {
        i = _maskUntilDelimiter(raw, mask, i, _openParenUnit);
        continue;
      }
      if (next == _openBracketUnit) {
        i = _maskUntilDelimiter(raw, mask, i, _openBracketUnit);
        continue;
      }
      i += 2;
      continue;
    }
    if (unit != _dollarUnit) {
      i += 1;
      continue;
    }
    if (i + 1 < raw.length && raw.codeUnitAt(i + 1) == _dollarUnit) {
      final close = raw.indexOf(r'$$', i + 2);
      final end = close < 0 ? raw.length : close + 2;
      _fillMask(mask, i, end);
      i = end;
      continue;
    }
    final close = _indexOfUnescapedDollar(raw, i + 1);
    if (close < 0) {
      // 落单的 `$`（多半是价格这类正文）不当作公式起点，避免掩掉后面的选项。
      i += 1;
      continue;
    }
    _fillMask(mask, i, close + 1);
    i = close + 1;
  }
  return mask;
}

/// 掩掉从 [start] 起的 `\(...\)` / `\[...\]`；返回掩码结束位置。
int _maskUntilDelimiter(String raw, List<bool> mask, int start, int openUnit) {
  final closeUnit = openUnit == _openParenUnit ? 0x29 : 0x5D;
  var i = start + 2;
  while (i < raw.length) {
    if (raw.codeUnitAt(i) == closeUnit &&
        raw.codeUnitAt(i - 1) == _backslashUnit) {
      final end = i + 1;
      _fillMask(mask, start, end);
      return end;
    }
    i += 1;
  }
  _fillMask(mask, start, raw.length);
  return raw.length;
}

int _indexOfUnescapedDollar(String raw, int from) {
  var i = from;
  while (i < raw.length) {
    final unit = raw.codeUnitAt(i);
    if (unit == _backslashUnit) {
      i += 2;
      continue;
    }
    if (unit == _dollarUnit) {
      return i;
    }
    i += 1;
  }
  return -1;
}

void _fillMask(List<bool> mask, int start, int end) {
  final safeEnd = end > mask.length ? mask.length : end;
  for (var i = start; i < safeEnd; i++) {
    mask[i] = true;
  }
}

const List<String> _answerLinePrefixes = <String>[
  '【答案】',
  '【解析】',
  '【详解】',
  '【解答】',
  '【分析】',
  '【点评】',
  '【点睛】',
  '【点拨】',
  '答案：',
  '答案:',
  '解析：',
  '解析:',
  '详解：',
  '详解:',
  '解答：',
  '解答:',
  '分析：',
  '分析:',
];

bool _looksLikeAnswerLine(String trimmedLine) {
  for (final prefix in _answerLinePrefixes) {
    if (trimmedLine.startsWith(prefix)) {
      return true;
    }
  }
  return false;
}

/// 每一条答案解析行的起始下标（行内容会被整行掩掉，选项内容也不吞它们）。
List<int> _answerLineStarts(String raw) {
  final starts = <int>[];
  var start = 0;
  while (start < raw.length) {
    var end = raw.indexOf(_lineBreakText, start);
    if (end < 0) {
      end = raw.length;
    }
    final trimmed = raw.substring(start, end).trim();
    if (_looksLikeAnswerLine(trimmed)) {
      starts.add(start);
    }
    if (end >= raw.length) {
      break;
    }
    start = end + 1;
  }
  return starts;
}

List<bool> _buildAnswerLineMask(String raw, List<int> starts) {
  final mask = List<bool>.filled(raw.length, false);
  for (final start in starts) {
    var end = raw.indexOf(_lineBreakText, start);
    if (end < 0) {
      end = raw.length;
    }
    _fillMask(mask, start, end);
  }
  return mask;
}

int? _firstAnswerLineStartAfter(List<int> starts, int position) {
  for (final start in starts) {
    if (start >= position) {
      return start;
    }
  }
  return null;
}

String _describeShortRun(List<_InlineMarker> candidates, int startIndex) {
  if (startIndex + 1 >= candidates.length) {
    return '至少需要 2 个选项（现在只有 1 个「${candidates[startIndex].letter}」）';
  }
  final next = candidates[startIndex + 1];
  if (next.letterIndex == 0) {
    return '选项字母重复：「A」出现了不止一次';
  }
  final missing = <String>[];
  for (var index = 1; index < next.letterIndex; index++) {
    missing.add(String.fromCharCode(_upperA + index));
  }
  final missingLabel = missing.isEmpty
      ? ''
      : '，缺少${missing.map((letter) => '「$letter」').join('、')}';
  return '选项字母不连续：「A」之后直接是「${next.letter}」$missingLabel'
      '（选项要按 A、B、C… 连续）';
}
