// ignore_for_file: prefer_interpolation_to_compose_strings
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:drift/drift.dart' show OrderingMode, OrderingTerm;
import 'package:path/path.dart' as p;

import '../../../data/database/database.dart';
import '../../../data/repositories/ai_repository.dart';
import '../../../data/storage/app_storage.dart';
import '../../ai/domain/model_adapter.dart';
import '../../ai/infrastructure/openai_compat_adapter.dart';
import '../../ai/domain/vision_payload.dart';
import '../application/paper_tree_svg.dart';

/// 一道被选进题单的题目：题干截图、答案截图与题库记录。
class PaperQuestionPick {
  const PaperQuestionPick({
    required this.question,
    required this.stemPath,
    required this.answerPath,
  });

  final Question question;
  final String stemPath;
  final String answerPath;
}

/// 生成结果：文档路径、树目录、实际用到的题。
class PaperGenerationResult {
  const PaperGenerationResult({
    required this.markdownPath,
    required this.treeDirectory,
    required this.picks,
  });

  final String markdownPath;
  final String treeDirectory;
  final List<PaperQuestionPick> picks;
}

class PaperGenerationException implements Exception {
  PaperGenerationException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// 用 Furnace 内置 AI（视觉 + 文本）生成一份 6 题题单。
///
/// 流程：本地题库选题（每科 2 题，排除题单历史）→ 逐题把题干图 + 答案图交给
/// 多模态模型 → 模型返回结构化 JSON（题目/判断点/完整答案/思维树/易错/扩展）→
/// 应用把树渲染为 SVG、拼成单个 Markdown 合集。AI 负责理解题与写内容；排版、
/// 树图、文件写入由应用完成，避免模型自由发挥格式。
class PaperGeneratorService {
  PaperGeneratorService({
    required AppDatabase db,
    required AiConfig config,
    ModelAdapter? adapter,
    VisionImageEncoder? encoder,
    Future<Directory> Function()? supportDirectory,
    Future<Directory> Function()? documentsDirectory,
    this.questionConcurrency = 3,
  })  : _db = db,
        _config = config,
        _adapter = adapter ??
            OpenAiCompatAdapter(
              apiKey: config.apiKey!,
              baseUrl: config.effectiveBaseUrl,
              model: config.effectiveModel,
              maxTokens: 20000,
              requestTimeout: const Duration(minutes: 4),
            ),
        _encoder = encoder ?? const VisionImageEncoder(),
        _supportDirectory = supportDirectory ?? AppStorage.supportDirectory,
        _documentsDirectory =
            documentsDirectory ?? AppStorage.documentsDirectory;

  final AppDatabase _db;
  final AiConfig _config;
  final ModelAdapter _adapter;
  final VisionImageEncoder _encoder;
  final Future<Directory> Function() _supportDirectory;
  final Future<Directory> Function() _documentsDirectory;

  /// 同时向模型发几道题。串行 6 题要等 10–20 分钟；3 路并发把等待压到约一半。
  /// 不担心 token 成本，但也不无上限地打爆服务端。
  final int questionConcurrency;

  static const List<String> subjects = <String>[
    'physics',
    'math',
    'chinese',
    'english',
  ];
  static const Map<String, String> subjectLabels = <String, String>{
    'physics': '物理',
    'math': '数学',
    'chinese': '语文',
    'english': '英语',
  };
  static const String historyFileName = 'paper_history.json';

  /// 生成一份题单；onProgress 用来把「正在做第几题」显示在页面上。
  Future<PaperGenerationResult> generate({
    required DateTime date,
    int perSubject = 2,
    void Function(String message)? onProgress,
  }) async {
    if (!_config.isUsable) {
      throw PaperGenerationException('还没有配置可用的 AI key：请先到 设置 → AI 填好 key 与模型。');
    }
    final picks = await _pickQuestions(perSubject: perSubject);
    if (picks.length < subjects.length * perSubject) {
      throw PaperGenerationException('题库里可用的题不足：需要 4 科 × ' +
          perSubject.toString() +
          ' 题，目前只找到 ' +
          picks.length.toString() +
          ' 题（题干图和答案图都要有）。');
    }
    final dateText = _dateText(date);
    final documents = await _documentsDirectory();
    final root = Directory(p.join(documents.path, '题单-' + dateText));
    final treesDir = Directory(p.join(root.path, 'trees'));
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
    await treesDir.create(recursive: true);

    final support = await _supportDirectory();
    final markdown = StringBuffer();
    markdown.writeln('# 题单 · ' + dateText);
    markdown.writeln();
    markdown.writeln(
        '> 由 Furnace 内置 AI 生成；先做题，再看答案。每题按学习需要组织：题目 → 先做提示 → 答案 → 思维树 → 易错点/命题视角 → 扩展 → 能力点。');
    markdown.writeln();

    // 6 道题的模型请求并行发出（默认 3 路），不要一道一道串行等。
    // 每道题的内容完全独立；文件写入与 Markdown 拼装仍在全部内容回来后串行做，
    // 避免并发写同一文档。
    final contents = <String, Map<String, Object?>>{};
    var nextIndex = 0;
    var finished = 0;
    final workersCount = math.min(questionConcurrency, picks.length);
    final workers = <Future<void>>[];
    for (var w = 0; w < workersCount; w++) {
      workers.add(() async {
        while (true) {
          final index = nextIndex;
          nextIndex++;
          if (index >= picks.length) {
            return;
          }
          final pick = picks[index];
          final json = await _askForQuestion(pick, support, onProgress);
          contents[pick.question.id] = json;
          finished++;
          onProgress?.call('已完成 ' +
              finished.toString() +
              '/' +
              picks.length.toString() +
              ' 题');
        }
      }());
    }
    onProgress?.call('已提交 ' +
        picks.length.toString() +
        ' 题，最多 ' +
        workersCount.toString() +
        ' 题并行…');
    await Future.wait(workers);

    var treeIndex = 0;
    for (final subject in subjects) {
      markdown.writeln('# ' + subjectLabels[subject]!);
      markdown.writeln();
      final subjectPicks =
          picks.where((pick) => pick.question.subjectKey == subject).toList();
      for (var i = 0; i < subjectPicks.length; i++) {
        final pick = subjectPicks[i];
        final json = contents[pick.question.id]!;
        final trees =
            (json['trees'] is List) ? json['trees'] as List : const <Object?>[];
        final treeImages = <String>[];
        for (final tree in trees) {
          if (tree is! Map) {
            continue;
          }
          treeIndex++;
          final name = 'tree-' + treeIndex.toString().padLeft(2, '0') + '.svg';
          final file = File(p.join(treesDir.path, name));
          await file
              .writeAsString(PaperTreeSvg.render(tree.cast<String, Object?>()));
          treeImages.add(name);
        }
        final section = _section(
          index: i + 1,
          subject: subjectLabels[subject]!,
          pick: pick,
          json: json,
          treeNames: treeImages,
        );
        markdown.writeln(section);
        markdown.writeln();
      }
    }

    final mdFile = File(p.join(root.path, '题单-' + dateText + '.md'));
    await mdFile.writeAsString(markdown.toString());
    await _remember(picks.map((pick) => pick.question.id).toList());
    onProgress?.call('完成：' + mdFile.path);
    return PaperGenerationResult(
      markdownPath: mdFile.path,
      treeDirectory: treesDir.path,
      picks: picks,
    );
  }

  static bool _isWritingTask(String? stem) {
    if (stem == null || stem.isEmpty) {
      return false;
    }
    return RegExp(r'写一篇文章|不少于800字|自拟标题|写一篇作文|作文题|请写一篇').hasMatch(stem);
  }

  static bool _isEnglishWritingTask(String? stem) {
    if (stem == null || stem.isEmpty) {
      return false;
    }
    return RegExp(r'书面表达|写一篇|作文|词左右|100词|80词|应用文写作').hasMatch(stem);
  }

  Future<List<PaperQuestionPick>> _pickQuestions(
      {required int perSubject}) async {
    final support = await _supportDirectory();
    final history = await _loadHistory();
    final picks = <PaperQuestionPick>[];
    for (final subject in subjects) {
      final rows = await (_db.select(_db.questions)
            ..where((t) => t.subjectKey.equals(subject))
            ..orderBy(<OrderingTerm Function(dynamic)>[
              (t) =>
                  OrderingTerm(expression: t.serialNo, mode: OrderingMode.desc),
            ])
            ..limit(80))
          .get();
      final ids = rows.map((q) => q.id).toList();
      final attachments = ids.isEmpty
          ? const <Attachment>[]
          : await (_db.select(_db.attachments)
                ..where((a) => a.ownerType.equals('question'))
                ..where((a) => a.ownerId.isIn(ids)))
              .get();
      String? pathOf(String questionId, String role) {
        for (final a in attachments) {
          if (a.ownerId == questionId && a.role == role) {
            return a.relPath;
          }
        }
        return null;
      }

      // 质量优先的初筛：
      // * 语文写作题（作文）没有可对照的官方答案，也不是“成熟题目”的形态，排除；
      // * 数学/物理优先大题（solution），选择题容易过简，只在不够时回退；
      // * 同一份题单内不重复同一题（history 之外再按 id 去重）。
      final preferred = rows.where((q) {
        if (subject == 'chinese') {
          return !_isWritingTask(q.stem) &&
              (q.questionType == 'single_choice' ||
                  q.questionType == 'multi_choice');
        }
        if (subject == 'english') {
          return !_isEnglishWritingTask(q.stem) &&
              (q.questionType == 'single_choice' ||
                  q.questionType == 'multi_choice');
        }
        return q.questionType == 'solution';
      }).toList();
      final ordered = <Question>[
        ...preferred,
        ...rows.where((q) => !preferred.contains(q)),
      ];
      var found = 0;
      for (final q in ordered) {
        if (history.contains(q.id)) {
          continue;
        }
        final stem = pathOf(q.id, 'stem');
        final answer = pathOf(q.id, 'answer');
        if (stem == null || answer == null) {
          continue;
        }
        final stemFile = File(p.join(support.path, stem));
        final answerFile = File(p.join(support.path, answer));
        if (!await stemFile.exists() || !await answerFile.exists()) {
          continue;
        }
        picks.add(PaperQuestionPick(
            question: q, stemPath: stemFile.path, answerPath: answerFile.path));
        found++;
        if (found >= perSubject) {
          break;
        }
      }
    }
    return picks;
  }

  Future<Map<String, Object?>> _askForQuestion(
    PaperQuestionPick pick,
    Directory support,
    void Function(String message)? onProgress,
  ) async {
    final stemBytes = await File(pick.stemPath).readAsBytes();
    final answerBytes = await File(pick.answerPath).readAsBytes();
    final images = <ChatImagePart>[];
    for (final bytes in <Uint8List>[stemBytes, answerBytes]) {
      final encoded = await _encoder.encode(bytes);
      if (encoded is VisionImageReady) {
        images.add(encoded.toPart());
      }
    }
    if (images.isEmpty) {
      throw PaperGenerationException('题目图片无法读取：' + pick.question.id);
    }
    final system = _systemPrompt();
    final baseUser = _userPrompt(pick);
    Map<String, Object?>? data;
    for (var attempt = 0; attempt < 4; attempt++) {
      final suffix = attempt == 0
          ? ''
          : '\n\n上一次输出不是合法 JSON。请缩短每段文字、保证 JSON 完整；'
              '只输出一个合法 JSON 对象，不要解释、不要 Markdown 代码围栏。';
      final text = await _run(system, baseUser + suffix, images);
      data = _tryParse(text);
      if (data != null) {
        return data;
      }
      onProgress?.call('模型返回格式不对，重试第 ' + (attempt + 2).toString() + '/4 次…');
    }
    throw PaperGenerationException(
        '模型连续 4 次没有返回可解析的 JSON（题 ' + pick.question.id + '）。');
  }

  Future<String> _run(
      String system, String user, List<ChatImagePart> images) async {
    final messages = <ChatMessage>[
      ChatMessage.system(system),
      ChatMessage.user(user, images: images),
    ];
    final buffer = StringBuffer();
    try {
      final stream =
          _adapter.runTurn(messages: messages, tools: const <ModelToolSpec>[]);
      await for (final event in stream.timeout(const Duration(minutes: 4))) {
        if (event is ModelTextDelta) {
          buffer.write(event.text);
        } else if (event is ModelFailure) {
          throw PaperGenerationException(event.message);
        } else if (event is ModelTurnCancelled) {
          throw PaperGenerationException('模型调用被取消。');
        }
      }
    } on TimeoutException {
      throw PaperGenerationException('模型响应超时。');
    }
    return buffer.toString();
  }

  Map<String, Object?>? _tryParse(String raw) {
    var text = raw.trim();
    if (text.startsWith('```')) {
      text = text.replaceAll('```', '').trim();
    }
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start < 0 || end <= start) {
      return null;
    }
    try {
      final decoded = jsonDecode(text.substring(start, end + 1));
      if (decoded is Map) {
        return decoded.cast<String, Object?>();
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  String _section({
    required int index,
    required String subject,
    required PaperQuestionPick pick,
    required Map<String, Object?> json,
    required List<String> treeNames,
  }) {
    final buffer = StringBuffer();
    final title = (json['title'] as String?)?.trim();
    final source = pick.question.sourceLabel;
    buffer.writeln('## 题' +
        index.toString() +
        ' ' +
        (title == null || title.isEmpty ? '综合题' : title) +
        ' · ' +
        source);
    buffer.writeln();
    buffer.writeln('### 题目');
    buffer.writeln();
    final questionText = (json['questionText'] as String?)?.trim();
    buffer.writeln(questionText == null || questionText.isEmpty
        ? pick.question.stem
        : questionText);
    buffer.writeln();
    buffer.writeln('### 先做提示');
    buffer.writeln();
    _bullets(buffer, json['hint']);
    buffer.writeln('---');
    buffer.writeln();
    buffer.writeln('### 答案');
    buffer.writeln();
    final judgementRaw = json['judgement'];
    final hasJudgement = judgementRaw is List
        ? judgementRaw.isNotEmpty
        : (judgementRaw is String && judgementRaw.trim().isNotEmpty);
    if (hasJudgement) {
      buffer.writeln('**判断点**：');
      _bullets(buffer, judgementRaw);
      buffer.writeln();
    }
    buffer.writeln(((json['answer'] as String?) ?? '').trim());
    buffer.writeln();
    if (treeNames.isNotEmpty) {
      buffer.writeln('### 思维树');
      buffer.writeln();
      for (var i = 0; i < treeNames.length; i++) {
        final treeTitle = i == 0 ? '完整过程' : '第 ' + (i + 1).toString() + ' 棵';
        buffer.writeln('<img src="trees/' +
            treeNames[i] +
            '" alt="' +
            subject +
            '题' +
            index.toString() +
            '思维树' +
            treeTitle +
            '" style="zoom:33%;" />');
        buffer.writeln();
      }
    }
    final mistakes = json['mistakes'];
    final hasMistakes = mistakes is List
        ? mistakes.isNotEmpty
        : (mistakes is String && mistakes.trim().isNotEmpty);
    final perspective = (json['perspective'] as String?)?.trim();
    if (hasMistakes || (perspective != null && perspective.isNotEmpty)) {
      buffer.writeln('### 易错点');
      buffer.writeln();
      if (hasMistakes) {
        _bullets(buffer, mistakes);
        buffer.writeln();
      }
      if (perspective != null && perspective.isNotEmpty) {
        buffer.writeln('### 命题视角');
        buffer.writeln();
        buffer.writeln(perspective);
        buffer.writeln();
      }
    }
    final near = json['nearExtensions'];
    final background = json['background'];
    final hasNear = near is List
        ? near.isNotEmpty
        : (near is String && near.trim().isNotEmpty);
    final hasBackground = (background is List && background.isNotEmpty) ||
        (background is String && background.trim().isNotEmpty);
    if (hasNear || hasBackground) {
      buffer.writeln('### 扩展');
      buffer.writeln();
      if (hasNear) {
        buffer.writeln('#### 近扩展');
        buffer.writeln();
        _bullets(buffer, near);
        buffer.writeln();
      }
      if (hasBackground) {
        buffer.writeln('#### 背景补充');
        buffer.writeln();
        if (background is List) {
          for (final item in background) {
            buffer.writeln(item.toString().trim());
            buffer.writeln();
          }
        } else {
          buffer.writeln((background as String).trim());
          buffer.writeln();
        }
      }
    }
    final ability = (json['ability'] as String?)?.trim();
    if (ability != null && ability.isNotEmpty) {
      buffer.writeln('### 能力点与难度');
      buffer.writeln();
      buffer.writeln(ability);
    }
    return buffer.toString();
  }

  void _bullets(StringBuffer buffer, Object? raw) {
    if (raw is List) {
      for (final item in raw) {
        buffer.writeln('- ' + item.toString().trim());
      }
    } else if (raw is String && raw.trim().isNotEmpty) {
      buffer.writeln(raw.trim());
    }
  }

  String _systemPrompt() {
    return '你是高三内容编辑，不是排版工具。你只对内容质量负责：让学生读完能理解这道题、学到可迁移的思考方式，而不是把一份模板填满。'
        '你会收到一道题的题干截图与答案截图；请仔细读题、读答案，必要时逐字核对。'
        '只输出一个 JSON 对象（不要 Markdown 代码围栏、不要解释）：'
        '{"title":"一句话题型/主题","questionText":"题干全文（保留原题格式；公式用 \$...\$）",'
        '"hint":["提示1","提示2"],"judgement":["仅主观题需要的词语级判断点"],'
        '"answer":"答案（按答题卡口径的官方答案）","trees":[{"title":"第1问：任务","root":{"label":"审题：...","note":"依据/原句/算式/为什么","status":"step","children":[...]}}],'
        '"mistakes":["真正容易错的点"],"perspective":"命题视角（必须与解析不同）","nearExtensions":["扩展到新结构/新条件的任务"],'
        '"background":["可直接引用的原文/资料或一段讲解"],"ability":"能力点与难度"}'
        '内容规则：'
        '1) answer 必须是答案截图里的官方答案：选择题只给选项字母；主观题写答题卡上会写的那几句，简洁、完整；答案图看不清时不要编，按图里能确认的内容写并保持克制。'
        '2) 选择题/填空题不要给 judgement（给空数组）；主观题的 judgement 是词语级关键判断，不是整段解析；写作/作文题同样不要 judgement，也不要硬编“官方答案”。'
        '3) hint 只给方向或问题，用问句把思考交还学生：这是什么类型的问题？这类问题通常从哪些角度想？教材里有没有类似例子？不要提前说出答案或解析内容。'
        '4) 解析写进 trees，不要另起解析段落。每个小题单独一棵树；树的目的是让学生看懂怎么想到的。选项并列时（如 ABCD）应是同一判断节点下的并列分支，不能按做题顺序串成父子；不要看D→定D这种只有动作没有思路的链。每一步必须有依据/策略（为什么想到这一步、用了什么提示）；顺序确实非常规时，用节点 note 解释。'
        '5) 用答案截图与解析订正树：只保留真实常见的学生错误作为 wrong 分支；只有 AI 会犯、学生基本不会犯的错误不要放进树。'
        '6) mistakes 只写真正容易错的点；一眼就明白的逻辑不要凑数。'
        '7) perspective 必须提供解析以外的观察（如设题结构、干扰项设计、能力落点），不要复述解析，不要写立德树人这类空泛官方话。'
        '8) background 涉及他人评论/资料时优先直接引用原文；讲知识就讲透，不写无关历史。理科扩展要能动手推导/计算，公式要解释；不用计算器也能完成。'
        '9) 近扩展要改变题目结构或条件，而不只是改一个数字；简单题如果值得学就短而准，不值得学就不要硬写长。'
        '10) 一切以是否真的帮学生提升为准：不需要的板块就留空/短写，不要为格式完整而重复、凑数、注水。'
        '树节点 status 只能是 step（步骤）、evidence（原文/条件）、decision（关键判断）、answer（结论）、wrong（真实弯路）、fix（修正/直路）、check（检查）；label 尽量短，note 要写依据或怎么想到。';
  }

  String _userPrompt(PaperQuestionPick pick) {
    return '这道题来自题库：学科=' +
        subjectLabels[pick.question.subjectKey]! +
        '；来源=' +
        pick.question.sourceLabel +
        '；'
            '题型=' +
        pick.question.questionType +
        '。\n'
            '第 1 张图是题干，第 2 张图是答案/解析。请按 system 要求输出 JSON。\n'
            '题库里的题干原文（可能有图片占位符，请结合截图修正）：\n' +
        pick.question.stem;
  }

  Future<Set<String>> _loadHistory() async {
    try {
      final documents = await _documentsDirectory();
      final file = File(p.join(documents.path, historyFileName));
      if (!await file.exists()) {
        return <String>{};
      }
      final raw = jsonDecode(await file.readAsString());
      if (raw is List) {
        return raw.map((e) => e.toString()).toSet();
      }
      if (raw is Map) {
        return raw.keys.map((e) => e.toString()).toSet();
      }
    } catch (_) {
      // 历史文件坏了就当没有：宁可重复一题，也不能让整份题单生成失败。
    }
    return <String>{};
  }

  Future<void> _remember(List<String> ids) async {
    final documents = await _documentsDirectory();
    final file = File(p.join(documents.path, historyFileName));
    final existing = await _loadHistory();
    existing.addAll(ids);
    await file.writeAsString(jsonEncode(existing.toList()..sort()));
  }

  String _dateText(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return date.year.toString() + '-' + month + '-' + day;
  }
}
