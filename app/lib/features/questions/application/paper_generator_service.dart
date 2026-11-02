// ignore_for_file: prefer_interpolation_to_compose_strings
import 'dart:async';
import 'dart:convert';
import 'dart:io';
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

  static const List<String> subjects = <String>['chinese', 'math', 'physics'];
  static const Map<String, String> subjectLabels = <String, String>{
    'chinese': '语文',
    'math': '数学',
    'physics': '物理',
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
      throw PaperGenerationException('题库里可用的题不足：需要 3 科 × ' +
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
        '> 由 Furnace 内置 AI 生成；先做题，再看答案。每题：题目 → 先做提示 → 判断点 → 完整答案（对照用）→ 思维树 → 易错点与命题视角 → 扩展 → 能力点与难度。');
    markdown.writeln();

    var treeIndex = 0;
    var done = 0;
    for (final subject in subjects) {
      markdown.writeln('# ' + subjectLabels[subject]!);
      markdown.writeln();
      final subjectPicks =
          picks.where((pick) => pick.question.subjectKey == subject).toList();
      for (var i = 0; i < subjectPicks.length; i++) {
        final pick = subjectPicks[i];
        done++;
        onProgress?.call('正在生成 ' +
            subjectLabels[subject]! +
            ' 第 ' +
            (i + 1).toString() +
            ' 题（' +
            done.toString() +
            '/' +
            picks.length.toString() +
            '）…');
        final json = await _askForQuestion(pick, support, onProgress);
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

      var found = 0;
      for (final q in rows) {
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
    final user = _userPrompt(pick);
    var text = await _run(system, user, images);
    var data = _tryParse(text);
    if (data == null) {
      onProgress?.call('模型返回格式不对，要求它重新输出 JSON…');
      text = await _run(
          system, user + '\n\n只输出一个合法 JSON 对象，不要解释、不要 Markdown 代码围栏。', images);
      data = _tryParse(text);
    }
    if (data == null) {
      throw PaperGenerationException(
          '模型没有返回可解析的 JSON（题 ' + pick.question.id + '）。');
    }
    return data;
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
    buffer.writeln('### 判断点');
    buffer.writeln();
    _bullets(buffer, json['judgement']);
    buffer.writeln('### 完整答案（对照用）');
    buffer.writeln();
    buffer.writeln(((json['answer'] as String?) ?? '').trim());
    buffer.writeln();
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
    buffer.writeln('### 易错点与命题视角');
    buffer.writeln();
    _bullets(buffer, json['mistakes']);
    final perspective = (json['perspective'] as String?)?.trim();
    if (perspective != null && perspective.isNotEmpty) {
      buffer.writeln('**命题视角**：' + perspective);
      buffer.writeln();
    }
    buffer.writeln('### 扩展');
    buffer.writeln();
    buffer.writeln('#### 近扩展');
    buffer.writeln();
    _bullets(buffer, json['nearExtensions']);
    buffer.writeln('#### 背景补充');
    buffer.writeln();
    final background = json['background'];
    if (background is List) {
      for (final item in background) {
        buffer.writeln((item as String).trim());
        buffer.writeln();
      }
    }
    buffer.writeln('### 能力点与难度');
    buffer.writeln();
    buffer.writeln(((json['ability'] as String?) ?? '').trim());
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
    return '你是高三题单编辑。你会收到一道题的题干截图与答案截图；请理解题目、核对答案，'
        '输出一个 JSON 对象，字段如下：'
        '{"title":"一句话题型/主题","questionText":"题干全文（可读文本，公式用 \$...\$）",'
        '"hint":["先做提示，2-4 条"],"judgement":["判断点：选择题逐项，或大题分点给分/关键判断"],'
        '"answer":"完整、组织好的答案，供学生对照","trees":[{"title":"第1问：任务","root":{"label":"审题：...","note":"依据/原句/算式（不超过40字）","status":"step","children":[...]}}],'
        '"mistakes":["易错点/命题视角要点"],"perspective":"命题视角一段","nearExtensions":["近扩展，可判定"],'
        '"background":["背景补充，每段150-300字，按内容重要性给篇幅"],"ability":"能力点与难度一句话"}'
        '。要求：每个小题单独一棵树，顺序是审题→定原文/条件→判断→形成观点/建模→组织答案→检查；'
        '树节点 status 只能是 step（普通步骤）、evidence（原文/条件）、decision（关键判断）、answer（结论/成文）、wrong（真实弯路）、fix（修正/直路）、check（检查）；'
        'label 不超过12字，note 不超过40字但有依据/原句/算式；不要图例、不要“对照”段、不要 Markdown 代码围栏、不要解释。';
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
