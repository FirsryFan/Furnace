// LIVE harness 第二阶段 — 把闪存卡内容包（chemistry/english）写进真实 Furnace 库。
//
// 它不在 test/ 下，永远不会进常规套件。显式运行：
//
//   cd E:/Projects/Furnace/app
//   FURNACE_LIVE_CONTENT=dry flutter test live/load_content_test.dart
//   FURNACE_LIVE_CONTENT=1 FURNACE_LIVE_CONTENT_CONFIRMED=1 flutter test live/load_content_test.dart
//
// dry 模式：只读 JSON + 用 sqlite3 只读查真实库，出映射/计划报告，绝不写库。
// real 模式：先备份真实库，再写 knowledge_points / card_templates / cloze_slots /
// card_states / object_tags / tags（缺的 deckPath 节点）/ knowledge_edges。
//
// 纪律：不联网；只写上面这些表；写前备份失败即中止；幂等键见各写入点注释。
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/anki_repository.dart';
import 'package:furnace/data/repositories/tag_repository.dart';
import 'package:furnace/domain/services/scheduling/thread_balance_inputs.dart'
    show kKnowledgePointObjectType;
import 'package:sqlite3/sqlite3.dart' as sql;

const String _liveFlag = 'FURNACE_LIVE_CONTENT';
const String _confirmFlag = 'FURNACE_LIVE_CONTENT_CONFIRMED';
const String _contentDirPath = r'E:\Workspaces\Furnace\00-inbox\content';
const String _backupDirPath = r'E:\Workspaces\Furnace\00-inbox\backup-20261102';
const String _reportDirPath = r'E:\Workspaces\Furnace\00-inbox';

const Map<String, String> _capabilityTagPath = <String, String>{
  'A1': '能力/语言解码A1',
  'A2': '能力/信息定位A2',
  'A3': '能力/逻辑论证A3',
  'A4': '能力/结构化建模A4',
  'A5': '能力/计算估算A5',
  'A6': '能力/图表图像A6',
  'A7': '能力/转化等价A7',
  'A8': '能力/实验设计A8',
  'A9': '能力/表达压缩A9',
  'A10': '能力/自我监控A10',
};

const Map<String, String> _subjectRootTag = <String, String>{
  'chemistry': '化学',
  'english': '英语',
  'biology': '生物',
  'chinese': '语文',
  'math': '数学',
  'physics': '物理',
};

/// 第二阶段补挂标签用：stage-1 遗留的 39 个知识点基本都是生物词面。
const List<String> _biologyHintKeywords = <String>[
  '细胞',
  '原生质',
  '被动运输',
  '主动运输',
  '胞吞',
  '胞吐',
  '渗透',
  '膜',
  '酶',
  '催化',
  '活化能',
  '能量',
  '呼吸',
  '光合',
  '光反应',
  '暗反应',
  'ATP',
  '分裂',
  '间期',
  '有丝',
  '无丝',
  '减数',
  '联会',
  '四分体',
  '染色体',
  'DNA',
  'RNA',
  '转录',
  '翻译',
  '复制',
  '密码子',
  '基因',
  '遗传',
  '分离',
  '自由组合',
  '测交',
  '自交',
  '杂交',
  '亲本',
  '子代',
  '性状',
  '显性',
  '隐性',
  '纯合',
  '杂合',
  '假说',
  '演绎',
  '对照',
  '变量',
  '代谢',
  '物质',
  '信息',
  '种群',
  '群落',
  '生态',
  '营养',
  '食物',
  '土壤',
  '肥料',
  '粮食',
  '储藏',
  '伤口',
  '敷料',
  '酿酒',
  '发酵',
  '菌',
  '病毒',
  '免疫',
  '激素',
  '神经',
  '调节',
  '稳态',
  '环境',
  '适应',
  '进化',
  '物种',
  '多样性',
  '生命',
  '统一体',
  '结构',
];

String _two(int value) => value.toString().padLeft(2, '0');

String _stampOf(DateTime time) =>
    time.year.toString() +
    _two(time.month) +
    _two(time.day) +
    '-' +
    _two(time.hour) +
    _two(time.minute) +
    _two(time.second);

Map<String, Object?> _asMap(Object? raw) {
  if (raw is Map) {
    return raw.cast<String, Object?>();
  }
  return <String, Object?>{};
}

List<Object?> _asList(Object? raw) => raw is List ? raw : const <Object?>[];

String _str(Object? raw) => raw == null ? '' : raw.toString().trim();

String? _optStr(Object? raw) {
  final text = _str(raw);
  return text.isEmpty ? null : text;
}

String _reqString(
  Map<String, Object?> json,
  String key,
  String context,
  List<String> errors,
) {
  final value = _str(json[key]);
  if (value.isEmpty) {
    errors.add(context + '：缺少非空字段 ' + key);
  }
  return value;
}

// ---------------------------------------------------------------------------
// 内容包模型（与 chemistry-README.md §2 的 11 个必需键一致）
// ---------------------------------------------------------------------------

class ContentOption {
  const ContentOption(this.label, this.text);
  final String label;
  final String text;
}

class ContentChoice {
  const ContentChoice(this.options, this.correct);
  final List<ContentOption> options;
  final List<String> correct;
}

class ContentEdge {
  const ContentEdge(this.to, this.relation, this.source);
  final String to;
  final String relation;
  final String source;
}

class ContentMindPoint {
  const ContentMindPoint(this.title, this.summary, this.edges);
  final String title;
  final String summary;
  final List<ContentEdge> edges;
}

class ContentCard {
  const ContentCard({
    required this.id,
    required this.deckPath,
    required this.title,
    required this.bodyMarkdown,
    required this.clozeText,
    required this.choices,
    required this.answerSummary,
    required this.references,
    required this.tags,
    required this.capability,
    required this.knowledgePoints,
  });

  final String id;
  final String deckPath;
  final String title;
  final String bodyMarkdown;
  final String? clozeText;
  final ContentChoice? choices;
  final String answerSummary;
  final List<Map<String, String>> references;
  final List<String> tags;
  final List<String> capability;
  final List<ContentMindPoint> knowledgePoints;
}

class ContentDeck {
  const ContentDeck({
    required this.subject,
    required this.deckRoot,
    required this.cards,
    required this.fileLabel,
    required this.sourceDir,
    required this.generatedAt,
  });

  final String subject;
  final String deckRoot;
  final List<ContentCard> cards;
  final String fileLabel;
  final String sourceDir;
  final String generatedAt;
}

class ClozeBlank {
  const ClozeBlank(this.index, this.answer, this.start, this.length);
  final int index;
  final String answer;
  final int start;
  final int length;
  String get slotKey => 'c' + index.toString();
}

({String content, List<ClozeBlank> blanks}) inlineCloze(String clozeText) {
  final pattern = RegExp(r'\{\{c([0-9]+)::([^}]*)\}\}');
  final buffer = StringBuffer();
  final blanks = <ClozeBlank>[];
  var cursor = 0;
  var index = 0;
  for (final match in pattern.allMatches(clozeText)) {
    index += 1;
    buffer.write(clozeText.substring(cursor, match.start));
    final answer = match.group(2) ?? '';
    final start = buffer.length;
    buffer.write(answer);
    blanks.add(ClozeBlank(index, answer, start, answer.length));
    cursor = match.end;
  }
  buffer.write(clozeText.substring(cursor));
  return (content: buffer.toString(), blanks: blanks);
}

String blankedCloze(String clozeText) {
  return clozeText.replaceAll(RegExp(r'\{\{c[0-9]+::[^}]*\}\}'), '___');
}

const Set<String> _allowedRelations = <String>{
  'prerequisite',
  'related',
  'contrast',
  'application',
  'part_of',
};

ContentDeck parseDeck(
  Map<String, Object?> json,
  String fileLabel,
  List<String> errors,
) {
  final version = json['version'];
  if (version != 1) {
    errors.add(fileLabel + '：version 不是 1（实际 ' + _str(version) + '）');
  }
  final subject = _reqString(json, 'subject', fileLabel, errors);
  final deckRoot = _reqString(json, 'deckRoot', fileLabel, errors);
  final cardsRaw = _asList(json['cards']);
  if (cardsRaw.isEmpty) {
    errors.add(fileLabel + '：cards 为空');
  }
  final seenIds = <String>{};
  final cards = <ContentCard>[];
  for (var i = 0; i < cardsRaw.length; i += 1) {
    final raw = _asMap(cardsRaw[i]);
    final context = fileLabel + ' cards[' + i.toString() + ']';
    final id = _reqString(raw, 'id', context, errors);
    if (id.isNotEmpty && !seenIds.add(id)) {
      errors.add(context + '：id 重复 ' + id);
    }
    final deckPath = _reqString(raw, 'deckPath', context, errors);
    if (deckPath.isNotEmpty &&
        deckPath != deckRoot &&
        !deckPath.startsWith(deckRoot + '/')) {
      errors.add(context + '：deckPath 不在 ' + deckRoot + ' 下（' + deckPath + '）');
    }
    final title = _reqString(raw, 'title', context, errors);
    final bodyMarkdown = _reqString(raw, 'bodyMarkdown', context, errors);
    final answerSummary = _reqString(raw, 'answerSummary', context, errors);
    final clozeText = _optStr(raw['clozeText']);
    ContentChoice? choices;
    final rawChoices = raw['choices'];
    if (rawChoices != null) {
      final choiceMap = _asMap(rawChoices);
      final options = <ContentOption>[];
      var optionError = false;
      for (final item in _asList(choiceMap['options'])) {
        final optionMap = _asMap(item);
        final label = _str(optionMap['label']);
        final text = _str(optionMap['text']);
        if (label.isEmpty || text.isEmpty) {
          errors.add(context + '：choices.options 缺少 label/text');
          optionError = true;
          continue;
        }
        options.add(ContentOption(label, text));
      }
      final correct = <String>[
        for (final item in _asList(choiceMap['correct'])) _str(item),
      ];
      if (!optionError) {
        if (options.length < 2) {
          errors.add(context + '：选择题选项少于 2 个');
        }
        final labels = <String>{for (final option in options) option.label};
        for (final label in correct) {
          if (!labels.contains(label)) {
            errors.add(context + '：correct 里的 ' + label + ' 不在选项中');
          }
        }
        if (correct.isEmpty) {
          errors.add(context + '：选择题没有 correct');
        }
        choices = ContentChoice(options, correct);
      }
    }
    final references = <Map<String, String>>[];
    for (final item in _asList(raw['references'])) {
      final map = _asMap(item);
      final sourceFile = _str(map['sourceFile']);
      final locator = _str(map['locator']);
      if (sourceFile.isEmpty || locator.isEmpty) {
        errors.add(context + '：references 必须是 {sourceFile, locator}');
        continue;
      }
      references.add(<String, String>{
        'sourceFile': sourceFile,
        'locator': locator,
      });
    }
    if (references.isEmpty) {
      errors.add(context + '：references 为空');
    }
    final tags = <String>[
      for (final item in _asList(raw['tags']))
        if (_str(item).isNotEmpty) _str(item),
    ];
    if (tags.isEmpty) {
      errors.add(context + '：tags 为空');
    }
    final capability = <String>[
      for (final item in _asList(raw['capability']))
        if (_str(item).isNotEmpty) _str(item),
    ];
    for (final code in capability) {
      if (!_capabilityTagPath.containsKey(code)) {
        errors.add(context + '：能力代码不在 A1–A10：' + code);
      }
    }
    final mindPoints = <ContentMindPoint>[];
    for (final item in _asList(raw['knowledgePoints'])) {
      final map = _asMap(item);
      final kpTitle = _str(map['title']);
      if (kpTitle.isEmpty) {
        errors.add(context + '：knowledgePoints[].title 为空');
        continue;
      }
      final edges = <ContentEdge>[];
      for (final edgeRaw in _asList(map['edges'])) {
        final edge = _asMap(edgeRaw);
        final to = _str(edge['to']);
        final relation = _str(edge['relation']);
        final source = _str(edge['source']);
        if (to.isEmpty) {
          errors.add(context + '：edge.to 为空');
          continue;
        }
        if (!_allowedRelations.contains(relation)) {
          errors.add(context + '：edge.relation 非法 ' + relation);
          continue;
        }
        edges.add(ContentEdge(to, relation, source));
      }
      mindPoints.add(ContentMindPoint(kpTitle, _str(map['summary']), edges));
    }
    if (mindPoints.isEmpty) {
      errors.add(context + '：knowledgePoints 为空');
    }
    cards.add(ContentCard(
      id: id,
      deckPath: deckPath,
      title: title,
      bodyMarkdown: bodyMarkdown,
      clozeText: clozeText,
      choices: choices,
      answerSummary: answerSummary,
      references: references,
      tags: tags,
      capability: capability,
      knowledgePoints: mindPoints,
    ));
  }
  final knownTitles = <String>{
    for (final card in cards)
      for (final point in card.knowledgePoints) point.title,
  };
  for (final card in cards) {
    for (final point in card.knowledgePoints) {
      for (final edge in point.edges) {
        if (!knownTitles.contains(edge.to)) {
          errors.add(fileLabel + '：' + card.id + ' 的边指向未定义知识点 ' + edge.to);
        }
      }
    }
  }
  return ContentDeck(
    subject: subject,
    deckRoot: deckRoot,
    cards: cards,
    fileLabel: fileLabel,
    sourceDir: _str(json['sourceDir']),
    generatedAt: _str(json['generatedAt']),
  );
}

String cardTypeOf(ContentCard card) {
  if (card.choices != null) {
    return 'mcq';
  }
  final cloze = card.clozeText;
  if (cloze != null && cloze.trim().isNotEmpty) {
    // 多空卡不写「a / b」拼接答案去喂机器判分：保持 essay 自判，
    // 题干仍用挖空句、答案仍是 answerSummary，可自判。cloze_slots 照写。
    return clozeBlankCountOf(card) == 1 ? 'fill_blank' : 'essay';
  }
  return 'essay';
}

int clozeBlankCountOf(ContentCard card) {
  final cloze = card.clozeText;
  if (cloze == null || cloze.trim().isEmpty) {
    return 0;
  }
  return inlineCloze(cloze).blanks.length;
}

String referenceSummary(ContentCard card) {
  final parts = <String>[];
  for (final reference in card.references) {
    parts.add(reference['sourceFile']! + ' @ ' + reference['locator']!);
  }
  final joined = parts.join(' ; ');
  if (joined.length <= 600) {
    return joined;
  }
  return joined.substring(0, 600);
}

// ---------------------------------------------------------------------------
// 计划 / 报告
// ---------------------------------------------------------------------------

Map<String, Object?> buildPlan({
  required List<ContentDeck> decks,
  required Set<String> existingTagPaths,
  required Set<String> existingKpExternalIds,
  required int existingKpCount,
  required List<({String id, String title})> untaggedKnowledgePoints,
}) {
  final missingTagPaths = <String>{};
  final deckPathMapping = <Map<String, Object?>>[];
  final perSubject = <String, Object?>{};
  final edgeKeys = <String>{};
  final edgeCountByRelation = <String, int>{};
  final tagPathSet = <String>{};
  var cardsTotal = 0;
  var mcqCards = 0;
  var clozeCards = 0;
  var essayCards = 0;
  var blankSlots = 0;
  var multiBlankCards = 0;
  var mindNodeCount = 0;
  var cardKpExists = 0;
  final multiBlankCardIds = <String>[];

  for (final deck in decks) {
    final cardsByDeck = <String, int>{};
    final subjectNodes = <String, String>{};
    final rootTag = _subjectRootTag[deck.subject] ?? deck.deckRoot;
    var subjectCards = 0;
    var subjectEdges = 0;
    for (final card in deck.cards) {
      subjectCards += 1;
      cardsTotal += 1;
      cardsByDeck[card.deckPath] = (cardsByDeck[card.deckPath] ?? 0) + 1;
      final type = cardTypeOf(card);
      if (type == 'mcq') {
        mcqCards += 1;
      } else if (type == 'fill_blank') {
        clozeCards += 1;
      } else {
        essayCards += 1;
      }
      final paths = <String>{card.deckPath, ...card.tags};
      for (final code in card.capability) {
        final capabilityPath = _capabilityTagPath[code];
        if (capabilityPath != null) {
          paths.add(capabilityPath);
        }
      }
      for (final path in paths) {
        if (tagPathSet.add(path) && !existingTagPaths.contains(path)) {
          missingTagPaths.add(path);
        }
      }
      if (card.clozeText != null) {
        final inlined = inlineCloze(card.clozeText!);
        blankSlots += inlined.blanks.length;
        if (inlined.blanks.length > 1) {
          multiBlankCards += 1;
          multiBlankCardIds.add(card.id);
        }
      }
      if (existingKpExternalIds.contains(card.id)) {
        cardKpExists += 1;
      }
      for (final point in card.knowledgePoints) {
        final current = subjectNodes[point.title] ?? '';
        if (point.summary.length > current.length) {
          subjectNodes[point.title] = point.summary;
        }
        for (final edge in point.edges) {
          subjectEdges += 1;
          final key = deck.subject + '|' + point.title + '|' + edge.to;
          if (edgeKeys.add(key)) {
            edgeCountByRelation[edge.relation] =
                (edgeCountByRelation[edge.relation] ?? 0) + 1;
          }
        }
      }
    }
    mindNodeCount += subjectNodes.length;
    var existingNodes = 0;
    for (final title in subjectNodes.keys) {
      if (existingKpExternalIds
          .contains('mindnet:' + deck.subject + ':' + title)) {
        existingNodes += 1;
      }
    }
    perSubject[deck.subject] = <String, Object?>{
      'file': deck.fileLabel,
      'deck_root': deck.deckRoot,
      'subject_root_tag': rootTag,
      'cards': subjectCards,
      'cards_by_deck_path': cardsByDeck,
      'mind_node_titles': subjectNodes.length,
      'mind_nodes_already_present': existingNodes,
      'mind_edges_raw': subjectEdges,
    };
    for (final deckPath in cardsByDeck.keys) {
      deckPathMapping.add(<String, Object?>{
        'subject': deck.subject,
        'deck_path': deckPath,
        'tag_path': deckPath,
        'parent_root': rootTag,
        'already_exists': existingTagPaths.contains(deckPath),
        'action': existingTagPaths.contains(deckPath) ? 'reuse' : 'create',
      });
    }
  }

  final leftoverAttach = <Map<String, Object?>>[];
  final leftoverStillUnmapped = <String>[];
  final leftoverBySubject = <String, int>{};
  for (final kp in untaggedKnowledgePoints) {
    final subject = classifyLeftoverKp(kp.title);
    if (subject == null) {
      leftoverStillUnmapped.add(kp.title);
      continue;
    }
    leftoverBySubject[subject] = (leftoverBySubject[subject] ?? 0) + 1;
    leftoverAttach.add(<String, Object?>{
      'title': kp.title,
      'subject': subject,
      'tag_path': _subjectRootTag[subject],
    });
  }

  final newCardKps = cardsTotal - cardKpExists;
  return <String, Object?>{
    'cards_total': cardsTotal,
    'cards_by_type': <String, int>{
      'mcq': mcqCards,
      'fill_blank': clozeCards,
      'essay': essayCards,
    },
    'cloze_blank_slots': blankSlots,
    'cards_with_multiple_blanks': multiBlankCards,
    'multi_blank_card_ids': multiBlankCardIds,
    'card_knowledge_points_new': newCardKps,
    'card_knowledge_points_already_present': cardKpExists,
    'mind_node_count': mindNodeCount,
    'mind_edge_count_dedup': edgeKeys.length,
    'mind_edge_count_by_relation': edgeCountByRelation,
    'tag_paths_needed': tagPathSet.length,
    'tag_paths_missing': missingTagPaths.toList()..sort(),
    'tag_paths_missing_count': missingTagPaths.length,
    'deck_path_mapping': deckPathMapping,
    'per_subject': perSubject,
    'predicted_knowledge_points_after':
        existingKpCount + newCardKps + mindNodeCount,
    'leftover_untagged_knowledge_points': untaggedKnowledgePoints.length,
    'leftover_will_attach': leftoverAttach.length,
    'leftover_attach_by_subject': leftoverBySubject,
    'leftover_still_unmapped': leftoverStillUnmapped.length,
    'leftover_still_unmapped_samples': leftoverStillUnmapped.take(40).toList(),
    'leftover_attach_samples': leftoverAttach.take(80).toList(),
  };
}

String? classifyLeftoverKp(String title) {
  var hits = 0;
  for (final keyword in _biologyHintKeywords) {
    if (title.contains(keyword)) {
      hits += 1;
    }
  }
  if (hits > 0) {
    return 'biology';
  }
  return null;
}

void writeReport({
  required File jsonFile,
  required File mdFile,
  required Map<String, Object?> report,
}) {
  jsonFile.writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(report),
    encoding: utf8,
  );
  final buffer = StringBuffer()
    ..writeln('# 闪存卡内容导入报告（stage-2）')
    ..writeln()
    ..writeln('- 生成时间：' + _str(report['generated_at']))
    ..writeln('- 模式：' + _str(report['mode']))
    ..writeln('- 真实库：' + _str(report['live_db']))
    ..writeln('- 备份：' + _str(report['backup']))
    ..writeln('- 结构自检错误数：' + _str(report['validation_errors_count']))
    ..writeln()
    ..writeln('## 1. 输入')
    ..writeln();
  for (final input in _asList(report['inputs'])) {
    final map = _asMap(input);
    buffer.writeln('- ' +
        _str(map['file']) +
        '：subject=' +
        _str(map['subject']) +
        '，cards=' +
        _str(map['cards']) +
        '，deckRoot=' +
        _str(map['deck_root']));
  }
  buffer
    ..writeln()
    ..writeln('## 2. 计划与映射')
    ..writeln()
    ..writeln('~~~json')
    ..writeln(const JsonEncoder.withIndent('  ').convert(report['plan']))
    ..writeln('~~~')
    ..writeln()
    ..writeln('## 3. 执行结果')
    ..writeln()
    ..writeln('~~~json')
    ..writeln(const JsonEncoder.withIndent('  ').convert(report['result']))
    ..writeln('~~~')
    ..writeln()
    ..writeln('## 4. 写库后统计')
    ..writeln()
    ..writeln('~~~json')
    ..writeln(const JsonEncoder.withIndent('  ').convert(report['after']))
    ..writeln('~~~')
    ..writeln()
    ..writeln('## 4b. 多空卡清单（essay 自判，不做「a / b」机器拼接）')
    ..writeln();
  final multiBlankIds = _asList(report['multi_blank_card_ids']);
  if (multiBlankIds.isEmpty) {
    buffer.writeln('- 无');
  } else {
    buffer.writeln('- 共 ' + multiBlankIds.length.toString() + ' 张：');
    for (final id in multiBlankIds) {
      buffer.writeln('  - ' + id.toString());
    }
  }
  buffer
    ..writeln()
    ..writeln('## 5. 错误 / 风险');
  final errorList = _asList(report['errors']);
  if (errorList.isEmpty) {
    buffer.writeln('- 无');
  } else {
    for (final error in errorList) {
      buffer.writeln('- ' + error.toString());
    }
  }
  mdFile.writeAsStringSync(buffer.toString(), encoding: utf8);
}

// ---------------------------------------------------------------------------
// 只读现状（dry-run 用 sqlite3，不触发迁移）
// ---------------------------------------------------------------------------

Map<String, Object?> readExistingState(String dbPath) {
  final db = sql.sqlite3.open(dbPath, mode: sql.OpenMode.readOnly);
  try {
    final state = <String, Object?>{};
    state['user_version'] =
        db.select('PRAGMA user_version').first['user_version'];
    state['knowledge_points'] =
        db.select('SELECT COUNT(*) AS c FROM knowledge_points').first['c'];
    state['card_templates'] =
        db.select('SELECT COUNT(*) AS c FROM card_templates').first['c'];
    state['cloze_slots'] =
        db.select('SELECT COUNT(*) AS c FROM cloze_slots').first['c'];
    state['card_states'] =
        db.select('SELECT COUNT(*) AS c FROM card_states').first['c'];
    state['tags'] = db.select('SELECT COUNT(*) AS c FROM tags').first['c'];
    state['object_tags'] =
        db.select('SELECT COUNT(*) AS c FROM object_tags').first['c'];
    state['knowledge_edges'] =
        db.select('SELECT COUNT(*) AS c FROM knowledge_edges').first['c'];
    state['tag_paths'] = <String>{
      for (final row
          in db.select('SELECT path FROM tags WHERE path IS NOT NULL'))
        _str(row['path']),
    };
    state['kp_external_ids'] = <String>{
      for (final row in db.select(
          'SELECT external_id FROM knowledge_points WHERE external_id IS NOT NULL'))
        _str(row['external_id']),
    };
    state['untagged_knowledge_points'] = <({String id, String title})>[
      for (final row in db.select('''
        SELECT kp.id AS id, kp.title AS title FROM knowledge_points kp
        WHERE NOT EXISTS (
          SELECT 1 FROM object_tags ot
          WHERE ot.object_type = 'knowledge_point' AND ot.object_id = kp.id
        )
        ORDER BY kp.title
      ''')) (id: _str(row['id']), title: _str(row['title'])),
    ];
    return state;
  } finally {
    db.dispose();
  }
}

// ---------------------------------------------------------------------------
// 写库实现（real 模式）
// ---------------------------------------------------------------------------

Future<String> ensureTagPath(
  TagRepository tags,
  String path,
  Map<String, String> cache,
) async {
  final cached = cache[path];
  if (cached != null) {
    return cached;
  }
  final existing = await tags.getTagByPath(path);
  if (existing != null) {
    cache[path] = existing.id;
    return existing.id;
  }
  final segments = path.split('/');
  String? parentId;
  var current = '';
  for (final segment in segments) {
    current = current.isEmpty ? segment : current + '/' + segment;
    final known = cache[current];
    if (known != null) {
      parentId = known;
      continue;
    }
    final found = await tags.getTagByPath(current);
    if (found != null) {
      cache[current] = found.id;
      parentId = found.id;
      continue;
    }
    final created = await tags.createTag(name: segment, parentId: parentId);
    cache[current] = created.id;
    parentId = created.id;
  }
  return parentId!;
}

Future<KnowledgePoint?> findKpByExternalId(
  AppDatabase db,
  String externalId,
) {
  return (db.select(db.knowledgePoints)
        ..where((t) => t.externalId.equals(externalId)))
      .getSingleOrNull();
}

Future<CardTemplate?> findTemplateByExternalId(
  AppDatabase db,
  String externalId,
) {
  return (db.select(db.cardTemplates)
        ..where((t) => t.externalId.equals(externalId)))
      .getSingleOrNull();
}

String _mcqAnswerOf(ContentCard card) {
  final choice = card.choices!;
  if (choice.correct.isEmpty) {
    return card.answerSummary;
  }
  final wanted = choice.correct.first;
  for (final option in choice.options) {
    if (option.label == wanted) {
      return option.label + '. ' + option.text;
    }
  }
  return card.answerSummary;
}

Future<Map<String, Object?>> writeContent({
  required List<ContentDeck> decks,
  required AppDatabase db,
}) async {
  final anki = AnkiRepository(db);
  final tags = TagRepository(db);
  final tagCache = <String, String>{};
  var cardKpsCreated = 0;
  var cardKpsUpdated = 0;
  var templatesCreated = 0;
  var templatesUpdated = 0;
  var cardStatesTouched = 0;
  var clozeSlotRows = 0;
  var tagLinksAdded = 0;
  var mindNodesCreated = 0;
  var mindNodesUpdated = 0;
  var edgesCreated = 0;
  var edgesSkipped = 0;
  var leftoverAttached = 0;
  var leftoverStillUnmapped = 0;
  final multiBlankCardIds = <String>[];
  final templateTypeCounts = <String, int>{};

  final existingTagsBefore = (await tags.getAllTags()).length;
  final tagLinksByTag = <String, List<String>>{};

  final neededTagPaths = <String>{};
  for (final deck in decks) {
    neededTagPaths.add(deck.deckRoot);
    for (final card in deck.cards) {
      neededTagPaths.addAll(card.tags);
      neededTagPaths.add(card.deckPath);
      for (final code in card.capability) {
        final path = _capabilityTagPath[code];
        if (path != null) {
          neededTagPaths.add(path);
        }
      }
    }
  }
  for (final path in neededTagPaths.toList()..sort()) {
    await ensureTagPath(tags, path, tagCache);
  }
  var tagsCreated = (await tags.getAllTags()).length - existingTagsBefore;

  for (final deck in decks) {
    for (final card in deck.cards) {
      final type = cardTypeOf(card);
      if (clozeBlankCountOf(card) > 1) {
        multiBlankCardIds.add(card.id);
      }
      templateTypeCounts[type] = (templateTypeCounts[type] ?? 0) + 1;
      final inlined =
          card.clozeText == null ? null : inlineCloze(card.clozeText!);
      final kpContent = inlined == null ? card.bodyMarkdown : inlined.content;
      var kp = await findKpByExternalId(db, card.id);
      if (kp == null) {
        kp = await anki.createKnowledgePoint(
          title: card.title,
          content: kpContent,
          source: referenceSummary(card),
          externalId: card.id,
        );
        cardKpsCreated += 1;
      } else {
        await anki.updateKnowledgePoint(
          kp.id,
          title: card.title,
          content: kpContent,
          source: referenceSummary(card),
        );
        cardKpsUpdated += 1;
      }

      final tagIds = <String>{};
      final tagPaths = <String>[
        card.deckPath,
        ...card.tags,
        for (final code in card.capability)
          if (_capabilityTagPath[code] != null) _capabilityTagPath[code]!,
      ];
      for (final path in tagPaths) {
        var tagId = tagCache[path];
        tagId ??= await ensureTagPath(tags, path, tagCache);
        tagIds.add(tagId);
      }
      for (final tagId in tagIds) {
        tagLinksByTag.putIfAbsent(tagId, () => <String>[]).add(kp.id);
      }

      final templateExternalId = card.id + ':tpl';
      String question;
      String answer;
      List<String> options = const <String>[];
      String? clozeTemplate;
      if (type == 'mcq') {
        final choice = card.choices!;
        options = <String>[
          for (final option in choice.options)
            option.label + '. ' + option.text,
        ];
        question = card.bodyMarkdown;
        answer = _mcqAnswerOf(card);
      } else if (type == 'fill_blank') {
        // 只有单空卡走 fill_blank 的机器判分：answer 就是那一个空的答案。
        question = blankedCloze(card.clozeText!);
        clozeTemplate = question;
        final blanks = inlined == null ? const <ClozeBlank>[] : inlined.blanks;
        answer = blanks.isEmpty ? card.answerSummary : blanks.single.answer;
      } else {
        // 多空挖空卡 / 纯问答卡：essay 自判，题干保留挖空句，答案是 answerSummary。
        question = card.clozeText == null
            ? card.bodyMarkdown
            : blankedCloze(card.clozeText!);
        answer = card.answerSummary;
      }
      var template = await findTemplateByExternalId(db, templateExternalId);
      if (template == null) {
        template = await anki.createTemplate(
          knowledgePointId: kp.id,
          type: type,
          question: question,
          answer: answer,
          options: options,
          clozeTemplate: clozeTemplate,
          externalId: templateExternalId,
        );
        templatesCreated += 1;
      } else {
        await anki.updateTemplate(
          template.id,
          type: type,
          question: question,
          answer: answer,
          options: options,
          clozeTemplate: clozeTemplate,
        );
        templatesUpdated += 1;
      }
      await anki.getOrCreateCardState(template.id);
      cardStatesTouched += 1;

      if (inlined != null) {
        for (final blank in inlined.blanks) {
          await anki.createClozeSlot(
            knowledgePointId: kp.id,
            slotKey: blank.slotKey,
            definition: jsonEncode(<String, int>{
              'start': blank.start,
              'length': blank.length,
            }),
          );
          clozeSlotRows += 1;
        }
      }
    }
  }

  for (final entry in tagLinksByTag.entries) {
    tagLinksAdded += await tags.addTagToObjects(
      tagId: entry.key,
      objectIds: <String>{...entry.value},
      objectType: kKnowledgePointObjectType,
    );
  }

  final now = DateTime.now().millisecondsSinceEpoch;
  for (final deck in decks) {
    final nodeSummaries = <String, String>{};
    for (final card in deck.cards) {
      for (final point in card.knowledgePoints) {
        final current = nodeSummaries[point.title] ?? '';
        if (point.summary.length > current.length) {
          nodeSummaries[point.title] = point.summary;
        }
      }
    }
    for (final entry in nodeSummaries.entries) {
      final externalId = 'mindnet:' + deck.subject + ':' + entry.key;
      final node = await findKpByExternalId(db, externalId);
      if (node == null) {
        await anki.createKnowledgePoint(
          title: entry.key,
          content: entry.value,
          source: 'cards-content:' + deck.subject,
          externalId: externalId,
        );
        mindNodesCreated += 1;
      } else {
        await anki.updateKnowledgePoint(
          node.id,
          title: entry.key,
          content: entry.value,
        );
        mindNodesUpdated += 1;
      }
    }
    final seenEdges = <String>{};
    for (final card in deck.cards) {
      for (final point in card.knowledgePoints) {
        final fromId = 'mindnet:' + deck.subject + ':' + point.title;
        for (final edge in point.edges) {
          final toId = 'mindnet:' + deck.subject + ':' + edge.to;
          final edgeId = 'e_' + fromId + '__' + toId;
          if (!seenEdges.add(edgeId)) {
            edgesSkipped += 1;
            continue;
          }
          final existing = await (db.select(db.knowledgeEdges)
                ..where((t) => t.id.equals(edgeId)))
              .getSingleOrNull();
          if (existing != null) {
            edgesSkipped += 1;
            continue;
          }
          await db.into(db.knowledgeEdges).insert(
                KnowledgeEdgesCompanion.insert(
                  id: edgeId,
                  fromId: fromId,
                  toId: toId,
                  origin: edge.relation,
                  batchId: const Value<String?>('cards-content-v1'),
                  source: Value<String?>(
                    edge.source.isEmpty ? null : edge.source,
                  ),
                  createdAt: now,
                  updatedAt: now,
                ),
              );
          edgesCreated += 1;
        }
      }
    }
  }

  final allLinks = await db.select(db.objectTags).get();
  final taggedKpIds = <String>{
    for (final link in allLinks)
      if (link.objectType == kKnowledgePointObjectType) link.objectId,
  };
  final allKps = await db.select(db.knowledgePoints).get();
  final leftoverBySubject = <String, List<String>>{};
  for (final kp in allKps) {
    if (taggedKpIds.contains(kp.id)) {
      continue;
    }
    final subject = classifyLeftoverKp(kp.title);
    if (subject == null) {
      leftoverStillUnmapped += 1;
      continue;
    }
    leftoverBySubject.putIfAbsent(subject, () => <String>[]).add(kp.id);
  }
  for (final entry in leftoverBySubject.entries) {
    final path = _subjectRootTag[entry.key];
    if (path == null) {
      continue;
    }
    var tagId = tagCache[path];
    tagId ??= await ensureTagPath(tags, path, tagCache);
    leftoverAttached += await tags.addTagToObjects(
      tagId: tagId,
      objectIds: entry.value,
      objectType: kKnowledgePointObjectType,
    );
  }

  final edgeOrigins = <String, int>{};
  for (final row in await db.select(db.knowledgeEdges).get()) {
    edgeOrigins[row.origin] = (edgeOrigins[row.origin] ?? 0) + 1;
  }
  final linksByType = <String, int>{};
  for (final link in await db.select(db.objectTags).get()) {
    linksByType[link.objectType] = (linksByType[link.objectType] ?? 0) + 1;
  }
  final after = <String, Object?>{
    'knowledge_points': (await db.select(db.knowledgePoints).get()).length,
    'card_templates': (await db.select(db.cardTemplates).get()).length,
    'cloze_slots': (await db.select(db.clozeSlots).get()).length,
    'card_states': (await db.select(db.cardStates).get()).length,
    'tags': (await db.select(db.tags).get()).length,
    'object_tags': (await db.select(db.objectTags).get()).length,
    'knowledge_edges': (await db.select(db.knowledgeEdges).get()).length,
    'knowledge_edges_by_origin': edgeOrigins,
    'object_tags_by_type': linksByType,
  };
  return <String, Object?>{
    'existing_tags_before': existingTagsBefore,
    'tags_created': tagsCreated,
    'card_knowledge_points_created': cardKpsCreated,
    'card_knowledge_points_updated': cardKpsUpdated,
    'card_templates_created': templatesCreated,
    'card_templates_updated': templatesUpdated,
    'card_states_touched': cardStatesTouched,
    'cloze_slots_written': clozeSlotRows,
    'tag_links_added': tagLinksAdded,
    'mind_nodes_created': mindNodesCreated,
    'mind_nodes_updated': mindNodesUpdated,
    'mind_edges_created': edgesCreated,
    'mind_edges_skipped': edgesSkipped,
    'leftover_kp_attached': leftoverAttached,
    'leftover_kp_still_unmapped': leftoverStillUnmapped,
    'multi_blank_card_ids': multiBlankCardIds,
    'template_type_counts': templateTypeCounts,
    'after': after,
  };
}

Future<File> backupLiveDb(File liveDb) async {
  final backupDir = Directory(_backupDirPath);
  await backupDir.create(recursive: true);
  final target = File(
    backupDir.path +
        Platform.pathSeparator +
        'furnace-before-content-' +
        _stampOf(DateTime.now()) +
        '.db',
  );
  await liveDb.copy(target.path);
  final sourceLength = await liveDb.length();
  final targetLength = await target.length();
  if (sourceLength != targetLength) {
    throw StateError(
      '备份大小不一致：source=' +
          sourceLength.toString() +
          ' backup=' +
          targetLength.toString(),
    );
  }
  return target;
}

void main() {
  final mode = Platform.environment[_liveFlag];
  final enabled = mode == 'dry' || mode == '1';

  test(
    'live stage-2: cards into knowledge points/templates/cloze/states + tags + MindNet edges',
    () async {
      if (!enabled) {
        // ignore: avoid_print
        print('skipped: set ' +
            _liveFlag +
            '=dry (plan only) or =1 + ' +
            _confirmFlag +
            '=1 (real writes)');
        return;
      }
      final dryRun = mode == 'dry';
      final confirmed = Platform.environment[_confirmFlag] == '1';
      if (!dryRun && !confirmed) {
        fail('真实写库需要同时设置 ' + _confirmFlag + '=1（等 Lead 信号）');
      }
      void say(Object? message) => print(message); // ignore: avoid_print

      final appData = Platform.environment['APPDATA'];
      if (appData == null || appData.isEmpty) {
        fail('APPDATA 不存在，无法定位真实库');
      }
      final liveDb = File(appData + r'\FirsryFan\Furnace\furnace.db');
      if (!liveDb.existsSync()) {
        fail('真实库不存在：' + liveDb.path);
      }

      final startedAt = DateTime.now();
      final errors = <String>[];
      final decks = <ContentDeck>[];
      final contentDir = Directory(_contentDirPath);
      for (final pair in <({String file, String subject})>[
        (file: 'chemistry-cards.json', subject: 'chemistry'),
        (file: 'english-cards.json', subject: 'english'),
      ]) {
        final file = File(contentDir.path + Platform.pathSeparator + pair.file);
        if (!file.existsSync()) {
          if (dryRun) {
            say('WAITING ' + pair.file + ' 不存在，先跳过该科');
            continue;
          }
          fail('缺少内容包：' + file.path);
        }
        final json =
            _asMap(jsonDecode(await file.readAsString(encoding: utf8)));
        final deck = parseDeck(json, pair.file, errors);
        if (deck.subject != pair.subject) {
          errors.add(pair.file + '：subject=' + deck.subject + ' 与预期不符');
        }
        decks.add(deck);
      }
      if (decks.isEmpty) {
        fail('没有可用的内容包（dry-run 至少需要 chemistry-cards.json）');
      }
      say('CONTENT_DECKS ' +
          decks
              .map((deck) => deck.subject + ':' + deck.cards.length.toString())
              .join(', '));

      final existing = readExistingState(liveDb.path);
      final plan = buildPlan(
        decks: decks,
        existingTagPaths: existing['tag_paths']! as Set<String>,
        existingKpExternalIds: existing['kp_external_ids']! as Set<String>,
        existingKpCount: existing['knowledge_points']! as int,
        untaggedKnowledgePoints: existing['untagged_knowledge_points']!
            as List<({String id, String title})>,
      );
      say('PLAN cards=' +
          _str(plan['cards_total']) +
          ' mind_nodes=' +
          _str(plan['mind_node_count']) +
          ' edges=' +
          _str(plan['mind_edge_count_dedup']) +
          ' missing_tags=' +
          _str(plan['tag_paths_missing_count']));

      final report = <String, Object?>{
        'generated_at': DateTime.now().toIso8601String(),
        'mode': dryRun ? 'dry' : 'real',
        'live_db': liveDb.path,
        'backup': '',
        'inputs': <Map<String, Object?>>[
          for (final deck in decks)
            <String, Object?>{
              'file': deck.fileLabel,
              'subject': deck.subject,
              'deck_root': deck.deckRoot,
              'cards': deck.cards.length,
              'source_dir': deck.sourceDir,
              'generated_at': deck.generatedAt,
            },
        ],
        'existing': <String, Object?>{
          'user_version': existing['user_version'],
          'knowledge_points': existing['knowledge_points'],
          'card_templates': existing['card_templates'],
          'cloze_slots': existing['cloze_slots'],
          'card_states': existing['card_states'],
          'tags': existing['tags'],
          'object_tags': existing['object_tags'],
          'knowledge_edges': existing['knowledge_edges'],
        },
        'validation_errors_count': errors.length,
        'validation_errors': errors.take(100).toList(),
        'plan': plan,
        'result': <String, Object?>{},
        'after': <String, Object?>{},
        'errors': <Object?>[],
      };

      final baseName = _stampOf(startedAt) + (dryRun ? '-dryrun' : '');
      final jsonFile =
          File(_reportDirPath + r'\load-content-report-' + baseName + '.json');
      final mdFile =
          File(_reportDirPath + r'\load-content-report-' + baseName + '.md');

      if (errors.isNotEmpty) {
        writeReport(jsonFile: jsonFile, mdFile: mdFile, report: report);
        fail('内容包结构自检失败（' + errors.length.toString() + ' 条），详见 ' + mdFile.path);
      }

      if (dryRun) {
        report['backup'] = '（dry-run 未备份、未写库）';
        report['multi_blank_card_ids'] =
            plan['multi_blank_card_ids'] ?? <Object?>[];
        writeReport(jsonFile: jsonFile, mdFile: mdFile, report: report);
        say('REPORT ' + mdFile.path);
        say('SUMMARY_DRY ' + jsonEncode(plan));
        return;
      }

      final backup = await backupLiveDb(liveDb);
      report['backup'] = backup.path;
      say('BACKUP ' + backup.path + ' bytes=' + backup.lengthSync().toString());
      final db = AppDatabase.forTesting(NativeDatabase(liveDb));
      try {
        final version =
            (await db.customSelect('PRAGMA user_version').getSingle())
                .data
                .values
                .first;
        say('REAL_DB_OPENED user_version=' + version.toString());
        expect(version, 43, reason: '真实库不是 v43，中止');
        final result = await writeContent(decks: decks, db: db);
        report['result'] = result;
        report['after'] = result['after'];
        report['errors'] = result['errors'] ?? <Object?>[];
        report['multi_blank_card_ids'] =
            result['multi_blank_card_ids'] ?? <Object?>[];
        say('WRITE_DONE ' + jsonEncode(result));
      } finally {
        await db.close();
      }
      writeReport(jsonFile: jsonFile, mdFile: mdFile, report: report);
      say('REPORT ' + mdFile.path);
    },
    timeout: const Timeout(Duration(minutes: 20)),
  );
}
