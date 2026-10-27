/// The AI's write path into the question bank.
///
/// 用户取消了拍照 / 文字手动入口，改为把题直接发给内置 agent（用户 2026-10-27 口径）；
/// 没有这个工具，agent 只能看图说话，题进不了库，后续做题 / 复习 / 统计都无源可依。
/// 本工具只做「把用户给的题誊写进库」，不做 AI 出题——出题被用户明令禁止。
///
/// 与 [QuestionRepository.ingest] 的关系：本工具只负责把模型给的 JSON 映射成
/// `QuestionDraft`；字段补全、去重（题干指纹）、题号分配都由 repository 负责。
/// 标签用 [resolveTagForTool] 解析，解析失败只记录不阻断入库（题先存下来更要紧）。
library;

import 'dart:convert';

import '../../../data/database/database.dart';
import '../../../data/repositories/question_repository.dart';
import '../../../data/repositories/tag_repository.dart';
import '../domain/ai_tool.dart';
import 'card_group_tools.dart' show resolveTagForTool;

/// 把用户发来的题目誊写进题库的写工具。
class CreateQuestionsTool extends AiTool {
  CreateQuestionsTool({
    required AppDatabase db,
    required TagRepository tags,
  })  : _db = db,
        _tags = tags;

  final AppDatabase _db;
  final TagRepository _tags;

  /// The name the provider sees and the agent loop recognises for undo.
  static const String toolName = 'create_questions';

  /// 一次调用最多录多少道题：一页纸 / 一张照片通常 1–20 道，留到 100 防跑偏。
  static const int maxQuestionsPerCall = 100;

  /// 模型省略 `subject_key` 时的兜底（用户口径：未知时用 other）。
  static const String fallbackSubjectKey = 'other';

  @override
  String get name => toolName;

  @override
  String get description => '把用户发来的题目（照片或粘贴的文字）逐字誊写进题库。'
      '用户说「把这道题存下来」「拍下来的题」时用它；它不是出题工具。'
      '纪律：① 逐字誊写，不改编、不补全、不自己创作；'
      '② 题面没给答案 / 解析就留空，不要自己算一个填进去；'
      '③ 一张照片 / 一页纸有多道题就逐道拆成 questions 的多个元素；'
      '④ 数学公式用 LaTeX（行内 \$...\$、行间 \$\$...\$\$）并把 text_format 传 markdown，'
      '纯文字用 plain；'
      '⑤ 不确定学科时 subject_key 用 other；'
      '⑥ 标签先用 query_content(kind: tag) 查已有路径，不要凭印象造标签，解析失败会被忽略；'
      '⑦ 同题干重复提交不算错，会返回已有题（created=false）。';

  @override
  Map<String, Object?> get parameters => {
        'type': 'object',
        'properties': {
          'questions': {
            'type': 'array',
            'description': '要录入的题目列表，一题一个元素，逐题誊写；一次最多 '
                '$maxQuestionsPerCall 道',
            'items': {
              'type': 'object',
              'properties': {
                'stem': {
                  'type': 'string',
                  'description': '题干原文（含小问），必填',
                },
                'answer': {
                  'type': 'string',
                  'description': '答案；题面没给就省略或留空，不要自己算',
                },
                'solution': {
                  'type': 'string',
                  'description': '解析 / 过程；题面没给就省略或留空',
                },
                'options': {
                  'type': 'array',
                  'description': '选择题选项；非选择题省略',
                  'items': {
                    'type': 'object',
                    'properties': {
                      'label': {'type': 'string', 'description': '选项字母，如 A'},
                      'content': {'type': 'string', 'description': '选项内容'},
                      'is_correct': {
                        'type': 'boolean',
                        'description': '是否正确答案（答案明确时填，可省略）',
                      },
                    },
                    'required': <String>['label', 'content'],
                  },
                },
                'subject_key': {
                  'type': 'string',
                  'description':
                      '学科 key：math/physics/chemistry/biology/chinese/english/history/geography/politics，不确定用 other',
                },
                'question_type': {
                  'type': 'string',
                  'enum': <String>[
                    'single_choice',
                    'multi_choice',
                    'fill_blank',
                    'solution',
                    'open',
                  ],
                  'description': '题型；不确定用 solution',
                },
                'source_level': {
                  'type': 'string',
                  'description': '来源层级（如 高中 / 初中 / 竞赛），不确定省略',
                },
                'source_label': {
                  'type': 'string',
                  'description': '来源描述，如「2023 湖南高考」',
                },
                'year': {'type': 'integer', 'description': '年份'},
                'region': {'type': 'string', 'description': '地区'},
                'difficulty': {
                  'type': 'number',
                  'description': '难度 0–1（0 最易）；不确定省略',
                },
                'trap_note': {
                  'type': 'string',
                  'description': '易错点 / 陷阱说明（可选）',
                },
                'text_format': {
                  'type': 'string',
                  'enum': <String>['plain', 'markdown'],
                  'description':
                      '题干 / 答案 / 解析的文本格式，默认 plain；有 LaTeX 用 markdown',
                },
                'tags': {
                  'type': 'array',
                  'description': '标签 id 或完整路径（先 query_content(kind: tag) 查）',
                  'items': {'type': 'string'},
                },
              },
              'required': <String>['stem'],
            },
          },
        },
        'required': <String>['questions'],
      };

  /// 可撤销的写操作：撤销时按 afterJson 的 created_ids 删掉这次新建的题。
  @override
  ToolRisk riskFor(String action) => ToolRisk.write;

  @override
  bool reversibleFor(String action) => true;

  @override
  bool get availableOnCurrentPlatform => true;

  @override
  Future<ToolResult> run(ToolInvocation invocation) async {
    final args = ToolArgs(invocation.arguments);
    try {
      final rawQuestions = args.raw['questions'];
      if (rawQuestions is! List || rawQuestions.isEmpty) {
        throw ToolArgError(
          '缺少 `questions`（要录入的题目数组，一题一个元素，不能为空）',
        );
      }
      if (rawQuestions.length > maxQuestionsPerCall) {
        throw ToolArgError(
          '一次最多录 $maxQuestionsPerCall 道题，请分成多次调用',
        );
      }

      // 先把整批草稿都校验完再写库：有一题不合法就整批不录，
      // 避免模型拿到「录了一半」的结果却不知道从哪继续。
      final unresolvedTags = <String>[];
      final drafts = <QuestionDraft>[];
      for (var i = 0; i < rawQuestions.length; i++) {
        final item = rawQuestions[i];
        if (item is! Map) {
          throw ToolArgError('第 ${i + 1} 个元素不是题目对象，请照 schema 传');
        }
        drafts.add(
          await _draftOf(item.cast<String, Object?>(), i + 1, unresolvedTags),
        );
      }

      final repo = QuestionRepository(_db);
      final results = <Map<String, Object?>>[];
      final questionIds = <String>[];
      final createdIds = <String>[];
      for (var i = 0; i < drafts.length; i++) {
        final ingested = await repo.ingest(drafts[i]);
        final question = ingested.question;
        questionIds.add(question.id);
        if (ingested.created) createdIds.add(question.id);
        results.add(<String, Object?>{
          'index': i,
          'question_id': question.id,
          'serial_no': question.serialNo,
          'created': ingested.created,
        });
      }

      final existingCount = results.length - createdIds.length;
      return ToolResult(
        ok: true,
        summary: '已录入 ${results.length} 道题（其中 $existingCount 道题库已有）',
        modelResult: <String, Object?>{
          'created': createdIds.length,
          'existing': existingCount,
          'questions': results,
          if (unresolvedTags.isNotEmpty) 'ignored_tags': unresolvedTags,
        },
        // created_ids 是撤销用的：只删这次新建的题，重题本来就在库里，不能删。
        afterJson: jsonEncode(<String, Object?>{
          'question_ids': questionIds,
          'created_ids': createdIds,
        }),
      );
    } on ToolArgError catch (e) {
      return ToolResult.failure(e.message);
    }
  }

  Future<QuestionDraft> _draftOf(
    Map<String, Object?> raw,
    int number,
    List<String> unresolvedTags,
  ) async {
    final stem = _optText(raw['stem']);
    if (stem == null) {
      throw ToolArgError('第 $number 道题缺少题干 `stem`');
    }
    return QuestionDraft(
      stem: stem,
      answer: _optText(raw['answer']),
      solution: _optText(raw['solution']),
      subjectKey: _optText(raw['subject_key']) ?? fallbackSubjectKey,
      questionType: _optText(raw['question_type']) ?? 'solution',
      sourceLevel: _optText(raw['source_level']) ?? 'unknown',
      sourceLabel: _optText(raw['source_label']) ?? '',
      year: _optInt(raw['year']),
      region: _optText(raw['region']),
      textFormat: _optText(raw['text_format'])?.toLowerCase() == 'markdown'
          ? 'markdown'
          : 'plain',
      difficulty: _optDouble(raw['difficulty']),
      trapNote: _optText(raw['trap_note']),
      options: _optionsOf(raw['options'], number),
      tagIds: await _tagIdsOf(raw['tags'], number, unresolvedTags),
    );
  }

  List<QuestionOptionDraft> _optionsOf(Object? value, int number) {
    if (value == null) return const <QuestionOptionDraft>[];
    if (value is! List) {
      throw ToolArgError('第 $number 道题的 `options` 应是数组');
    }
    final options = <QuestionOptionDraft>[];
    for (var i = 0; i < value.length; i++) {
      final item = value[i];
      if (item is! Map) {
        throw ToolArgError('第 $number 道题的第 ${i + 1} 个选项不是对象');
      }
      final map = item.cast<String, Object?>();
      final label = _optText(map['label']);
      final content = _optText(map['content']);
      if (label == null || content == null) {
        throw ToolArgError(
          '第 $number 道题的第 ${i + 1} 个选项缺少 label / content',
        );
      }
      options.add(
        QuestionOptionDraft(
          label: label,
          content: content,
          isCorrect: _optBool(map['is_correct']),
          sortOrder: i,
        ),
      );
    }
    return options;
  }

  /// 解析标签；解析失败的只记进 [unresolvedTags]，不阻断入库。
  Future<Set<String>> _tagIdsOf(
    Object? value,
    int number,
    List<String> unresolvedTags,
  ) async {
    if (value == null) return const <String>{};
    final rawTags = <String>[];
    if (value is List) {
      for (final item in value) {
        final text = _optText(item);
        if (text != null) rawTags.add(text);
      }
    } else {
      final text = _optText(value);
      if (text == null) {
        throw ToolArgError('第 $number 道题的 `tags` 应是字符串数组');
      }
      rawTags.add(text);
    }
    final ids = <String>{};
    for (final rawTag in rawTags) {
      try {
        final tag = await resolveTagForTool(_tags, rawTag);
        ids.add(tag.id);
      } on ToolArgError {
        // 标签是锦上添花：模型看错路径不该让整道题丢掉，题先入库、标签后补。
        unresolvedTags.add(rawTag);
      }
    }
    return ids;
  }
}

String? _optText(Object? value) {
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

int? _optInt(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString().trim());
}

double? _optDouble(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString().trim());
}

bool _optBool(Object? value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final text = value.trim().toLowerCase();
    return text == 'true' || text == '1' || text == 'yes' || text == '是';
  }
  return false;
}
