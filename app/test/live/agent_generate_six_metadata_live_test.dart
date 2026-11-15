import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/ai_repository.dart';
import 'package:furnace/data/repositories/content_ref_repository.dart';
import 'package:furnace/data/repositories/question_repository.dart';
import 'package:furnace/domain/services/content/content_ref_vocab.dart';
import 'package:furnace/features/ai/application/ai_model_adapters.dart';
import 'package:furnace/features/ai/domain/agent_loop.dart';
import 'package:furnace/features/ai/domain/approval_engine.dart';
import 'package:furnace/features/ai/domain/tool_registry.dart';

/// task-109：用 Furnace 内部 agent 给六科各 1 道压轴题生成「A 预设」元数据草稿。
///
/// 调用路径（内部路径，非 DSH、无 UI）：
///   AiRepository.getConfig()
///     -> AiModelAdapters.chat(config)
///     -> AgentLoop.sendUserMessage(...)   // 空 ToolRegistry
///
/// 只读真实库的**临时副本**（`--dart-define=DB_COPY=<copy>`）；不写真实库、
/// 不写学生模型测量、不建 KP/能力/标签；草稿只落工作区 `.work/.../ability-drafts/`。
///
/// 运行：
///   flutter test test/live/agent_generate_six_metadata_live_test.dart \
///     --dart-define=RUN_LIVE_GENERATE=1 \
///     --dart-define=DB_COPY=E:\Workspaces\agent-control\.work\six-subject-import-2026-11-15\after\furnace.db
void main() {
  const workspace = r'E:\Workspaces\agent-control';
  const work = '$workspace\\.work\\six-subject-import-2026-11-15';
  const liveFlag = String.fromEnvironment('RUN_LIVE_GENERATE');
  const dbCopy = String.fromEnvironment('DB_COPY');

  final items = <Map<String, String>>[
    {'subject': '数学', 'contentId': 'six-sample-2025-math-national1-q19#Q19'},
    {'subject': '语文', 'contentId': 'six-sample-2025-chinese-national1-q22#Q22'},
    {'subject': '英语', 'contentId': 'six-sample-2024-english-n1-q67#Q67'},
    {'subject': '物理', 'contentId': 'six-sample-2026-physics-guangdong-q15#Q15'},
    {'subject': '化学', 'contentId': 'six-sample-2026-chem-shandong-q15#Q15'},
    {'subject': '生物', 'contentId': 'six-sample-2026-bio-shandong-q25#Q25'},
  ];

  test(
    '内部 agent 为六科样例题生成 A 预设能力元数据草稿',
    () async {
      expect(dbCopy.isNotEmpty, isTrue, reason: '缺少 --dart-define=DB_COPY');
      expect(File(dbCopy).existsSync(), isTrue, reason: 'DB 副本不存在：$dbCopy');
      final outDir = Directory('$work\\ability-drafts')
        ..createSync(recursive: true);

      AppDatabase? db;
      db = AppDatabase.forTesting(NativeDatabase(File(dbCopy)));
      try {
        final repository = AiRepository(db);
        final config = await repository.getConfig();
        // ignore: avoid_print
        print('CONFIG usable=${config.isUsable} model=${config.effectiveModel} '
            'base=${config.effectiveBaseUrl} effort=${config.reasoningEffort}');
        if (!config.isUsable) {
          fail('AI 配置不可用（enabled/apiKey），拒绝生成：'
              'enabled=${config.enabled} model=${config.effectiveModel}');
        }

        final contentRefs = ContentRefRepository(db);
        final questions = QuestionRepository(db);
        final results = <Map<String, Object?>>[];

        for (final item in items) {
          final refs = await contentRefs.listByContentId(item['contentId']!);
          final ref = refs.where((row) =>
              row.objectType == ContentObjectType.question &&
              row.role == ContentRefRole.sourcePackage);
          if (ref.isEmpty) {
            fail('找不到 content_ref：${item['contentId']!}');
          }
          final question = await questions.byId(ref.first.objectId);
          if (question == null) {
            fail('找不到题目：${item['contentId']!}');
          }
          final prompt = _buildPrompt(
            subject: item['subject']!,
            contentId: item['contentId']!,
            stem: question.stem,
            answer: question.answer ?? '',
          );

          final adapter = AiModelAdapters.chat(config);
          final loop = AgentLoop(
            adapter: adapter,
            registry: ToolRegistry(const []),
            approval: ApprovalEngine(mode: config.permissionMode),
            repository: repository,
            db: db,
            maxRounds: config.maxRounds,
            echoReasoning: config.reasoningEffort != null,
          );
          final conversation = await repository.createConversation();
          final watch = Stopwatch()..start();
          await loop.sendUserMessage(
            conversationId: conversation.id,
            text: prompt,
          );
          watch.stop();

          final state = loop.state;
          final usage = state.usage;
          final messages = await repository.listMessages(conversation.id);
          final assistant =
              messages.where((m) => m.role == AiRepository.roleAssistant);
          final raw = assistant.isEmpty ? '' : (assistant.last.content ?? '');
          if (state.error != null || raw.trim().isEmpty) {
            fail('内部 agent 调用失败（${item['subject']!}）：error=${state.error} '
                'chars=${raw.length}');
          }
          final draft = _parseJson(raw);
          _validateDraft(draft, item['subject']!);
          draft['source_question'] = {
            'content_id': item['contentId']!,
            'question_type': question.questionType,
            'answer_len': (question.answer ?? '').length,
          };
          draft['generation'] = {
            'call_path':
                'AiRepository.getConfig -> AiModelAdapters.chat(config) -> '
                    'AgentLoop.sendUserMessage (ToolRegistry empty, no UI)',
            'model': config.effectiveModel,
            'rounds': usage.rounds,
            'prompt_tokens': usage.promptTokens,
            'completion_tokens': usage.completionTokens,
            'total_tokens': usage.totalTokens,
            'elapsed_ms': watch.elapsedMilliseconds,
            'draft_only': true,
            'review_status': 'draft_pending_review',
            'writes_student_measurement': false,
          };
          final file = File('${outDir.path}\\${_slug(item['subject']!)}.json');
          file.writeAsStringSync(
              const JsonEncoder.withIndent('  ').convert(draft));
          results.add(<String, Object?>{
            'subject': item['subject']!,
            'content_id': item['contentId']!,
            'file': file.path,
            'abilities': draft['ability_demands'],
            'kp_count': (draft['knowledge_point_candidates'] as List).length,
            'rounds': usage.rounds,
            'total_tokens': usage.totalTokens,
            'elapsed_ms': watch.elapsedMilliseconds,
          });
          // ignore: avoid_print
          print('DRAFT ${item['subject']!} -> ${file.path} '
              'kp=${(draft['knowledge_point_candidates'] as List).length} '
              'abilities=${(draft['ability_demands'] as List).length} '
              'tokens=${usage.totalTokens} elapsed=${watch.elapsedMilliseconds}ms');
        }

        File('$work\\ability-drafts\\ability-drafts.json').writeAsStringSync(
            const JsonEncoder.withIndent('  ')
                .convert(<String, Object?>{'drafts': results}));
        expect(results, hasLength(6));
      } finally {
        await db.close();
      }
    },
    timeout: const Timeout(Duration(minutes: 30)),
    skip: liveFlag.isEmpty || dbCopy.isEmpty,
  );
}

const _abilities = <String, String>{
  'A1': '语言解码：词汇 / 句法 / 术语 / 文本结构',
  'A2': '信息定位与提取：从材料找证据句 / 图表数据',
  'A3': '逻辑与论证：因果、充分必要、反例、归谬、削弱加强',
  'A4': '结构化建模：情境→方程 / 图式 / 模型',
  'A5': '计算与估算：运算、量纲、有效数字、近似',
  'A6': '图表与图像：读图、图像→代数、趋势判断',
  'A7': '转化与等价：同义改写、换元、数形结合、选项↔原文',
  'A8': '实验与证据设计：变量控制、对照、误差、方案评价',
  'A9': '表达与压缩：概括、翻译、写作、讲清楚',
  'A10': '自我监控：检查、时间分配、边界条件',
};

String _buildPrompt({
  required String subject,
  required String contentId,
  required String stem,
  required String answer,
}) {
  final abilityTable = _abilities.entries
      .map((entry) => '- ${entry.key} ${entry.value}')
      .join('\n');
  return '''
你是 Furnace 的内容标注 agent。请为下面这道高考压轴题生成「A 等级学生」的**元数据草稿**（只做标注，不写学生测量、不改题目）。

【硬性要求】
1. 只输出一个 JSON 对象；不要 Markdown 代码围栏，不要任何解释或前后缀。
2. 必须显式包含：`"preset": "A"`、`"difficulty": "finale"`、`"review_status": "draft_pending_review"`。
3. `knowledge_point_candidates` 是候选项（不是定论），每项含 name / confidence（0–1）/ evidence；不要编造教材版本或考纲编号。
4. `ability_demands` 只从下面 A1–A10 词表里选本题真正需要的（2–5 个），每项含 code / reason；code 必须在词表内。
5. `mastery_points` 写学生要掌握的可执行方法（3–6 条），不写"提高能力"这类空话。
6. 不要输出学生分数、掌握度概率、能力测量值、做题记录；不要写 Thinking DAG / 变式题 / 解析正文。
7. 中文输出，总长度控制在 1200 字以内。

【A1–A10 能力词表】
$abilityTable

【必须输出的 JSON 结构】
{
  "question_id": "$contentId",
  "subject": "$subject",
  "preset": "A",
  "difficulty": "finale",
  "knowledge_point_candidates": [
    {"name": "候选知识点", "confidence": 0.8, "evidence": "题目中的哪一步/哪句话"}
  ],
  "ability_demands": [
    {"code": "A4", "reason": "为什么本题需要结构化建模"}
  ],
  "mastery_points": ["学生要掌握的具体方法/结论"],
  "review_status": "draft_pending_review"
}

【题目】
$stem

【参考答案】
$answer
''';
}

Map<String, Object?> _parseJson(String raw) {
  var text = raw.trim();
  if (text.startsWith('```')) {
    final first = text.indexOf('\n');
    if (first > 0) text = text.substring(first + 1);
    final end = text.lastIndexOf('```');
    if (end >= 0) text = text.substring(0, end);
  }
  final start = text.indexOf('{');
  final end = text.lastIndexOf('}');
  if (start < 0 || end <= start) {
    throw const FormatException('模型输出不含 JSON 对象');
  }
  final decoded = jsonDecode(text.substring(start, end + 1));
  if (decoded is! Map) {
    throw const FormatException('模型输出 JSON 不是对象');
  }
  return decoded.map((key, value) => MapEntry(key.toString(), value));
}

void _validateDraft(Map<String, Object?> draft, String subject) {
  if (draft['preset'] != 'A') {
    fail('$subject: preset 应为 A，实际 ${draft['preset']}');
  }
  if (draft['difficulty'] != 'finale') {
    fail('$subject: difficulty 应为 finale，实际 ${draft['difficulty']}');
  }
  if (draft['review_status'] != 'draft_pending_review') {
    fail('$subject: review_status 应为 draft_pending_review，'
        '实际 ${draft['review_status']}');
  }
  final kps = draft['knowledge_point_candidates'];
  if (kps is! List || kps.isEmpty) {
    fail('$subject: knowledge_point_candidates 为空');
  }
  final abilities = draft['ability_demands'];
  if (abilities is! List || abilities.length < 2 || abilities.length > 5) {
    fail('$subject: ability_demands 数量异常（${abilities is List ? abilities.length : abilities}）');
  }
  const valid = <String>{'A1', 'A2', 'A3', 'A4', 'A5', 'A6', 'A7', 'A8', 'A9', 'A10'};
  for (final entry in abilities) {
    final code = entry is Map ? entry['code'] : null;
    if (code is! String || !valid.contains(code)) {
      fail('$subject: ability code 非法或不在 A1–A10：$code');
    }
  }
  final mastery = draft['mastery_points'];
  if (mastery is! List || mastery.isEmpty) {
    fail('$subject: mastery_points 为空');
  }
}

String _slug(String subject) => switch (subject) {
      '数学' => 'math',
      '语文' => 'chinese',
      '英语' => 'english',
      '物理' => 'physics',
      '化学' => 'chemistry',
      '生物' => 'biology',
      _ => subject,
    };
