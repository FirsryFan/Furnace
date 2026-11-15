import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/ai_repository.dart';
import 'package:furnace/features/ai/application/ai_model_adapters.dart';
import 'package:furnace/features/ai/domain/agent_loop.dart';
import 'package:furnace/features/ai/domain/approval_engine.dart';
import 'package:furnace/features/ai/domain/tool_registry.dart';

/// Furnace 内部 agent 生成内容草稿（host/test，无 UI、无业务工具）。
///
/// 调用路径（严格按任务要求的内部路径，不绕过）：
///   AiRepository.getConfig()
///     -> AiModelAdapters.chat(config)          // 内部模型适配器
///     -> AgentLoop.sendUserMessage(...)        // 内部 agent loop，空 ToolRegistry
///
/// 真实库只以**临时副本**打开：复制 `E:\Furnace\data\furnace.db`（含 -wal/-shm）
/// 到工作区 `.work/agent-generate/db-copy-*`，所有写入只落在副本上，真实库不碰。
///
/// 运行（只在显式开启时跑，避免进入常规测试集、避免无谓 token）：
///   flutter test test/live/agent_generate_q19_live_test.dart --dart-define=RUN_LIVE_GENERATE=1
///   仅预检配置：  ... --dart-define=RUN_LIVE_GENERATE=probe
///
/// 输出（工作区，不在 Furnace 仓库）：
///   .work/agent-generate/draft-q19.json
///   .work/agent-generate/draft-q19.md
///   .work/agent-generate/draft-q19.run-report.json
void main() {
  const workspace = r'E:\Workspaces\agent-control';
  const realDbPath = r'E:\Furnace\data\furnace.db';
  const liveFlag = String.fromEnvironment('RUN_LIVE_GENERATE');

  test(
    '内部 agent 生成 2025 数学全国 I 卷 Q19 压轴题草稿',
    () async {
      final outDir = Directory('$workspace\\.work\\agent-generate');
      expect(outDir.existsSync(), isTrue, reason: '工作区输出目录不存在');
      final sourceFile = File('${outDir.path}\\source-q19.json');
      expect(sourceFile.existsSync(), isTrue, reason: '源题文件不存在');
      final realDb = File(realDbPath);
      expect(realDb.existsSync(), isTrue, reason: '真实库不存在');

      // --- 1. 真实库临时副本（db + WAL + SHM，保持一致快照） ---------------
      final copyDir = Directory(
          '${outDir.path}\\db-copy-${DateTime.now().millisecondsSinceEpoch}');
      copyDir.createSync(recursive: true);
      final copyPath = '${copyDir.path}\\furnace.db';
      realDb.copySync(copyPath);
      for (final suffix in const <String>['-wal', '-shm']) {
        final side = File('${realDb.path}$suffix');
        if (side.existsSync()) {
          side.copySync('${copyDir.path}\\furnace$suffix');
        }
      }

      AppDatabase? db;
      try {
        db = AppDatabase.forTesting(NativeDatabase(File(copyPath)));
        final repository = AiRepository(db);
        final config = await repository.getConfig();
        final cfgLine = 'CONFIG enabled=${config.enabled} '
            'usable=${config.isUsable} '
            'model=${config.effectiveModel} '
            'base=${config.effectiveBaseUrl} '
            'effort=${config.reasoningEffort} '
            'perm=${config.permissionMode.id} '
            'maxRounds=${config.maxRounds} '
            'keyPresent=${config.apiKey?.trim().isNotEmpty ?? false}';
        // ignore: avoid_print
        print(cfgLine);

        const probeOnly = liveFlag == 'probe';
        if (probeOnly) {
          // ignore: avoid_print
          print('PROBE ONLY: realDbCopy=$copyPath '
              'dbBytes=${File(copyPath).lengthSync()}');
          return;
        }
        if (!config.isUsable) {
          fail('AI 配置不可用（enabled / apiKey 缺失），拒绝烧 token：$cfgLine');
        }

        // --- 2. 源题 -> 内部 agent 提示词 ---------------------------------
        final source =
            jsonDecode(await sourceFile.readAsString()) as Map<String, Object?>;
        final prompt = _buildPrompt(source);

        // --- 3. Furnace 内部 agent 路径 -----------------------------------
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
        final assistant = messages
            .where((m) => m.role == AiRepository.roleAssistant)
            .toList();
        final raw = assistant.isEmpty ? '' : (assistant.last.content ?? '');

        final report = <String, Object?>{
          'call_path':
              'AiRepository.getConfig -> AiModelAdapters.chat(config) -> '
                  'AgentLoop.sendUserMessage (ToolRegistry empty, no UI)',
          'real_db_source': realDbPath,
          'real_db_copy': copyPath,
          'model': config.effectiveModel,
          'base_url': config.effectiveBaseUrl,
          'reasoning_effort': config.reasoningEffort?.toString(),
          'permission_mode': config.permissionMode.id,
          'max_rounds': config.maxRounds,
          'conversation_id': conversation.id,
          'rounds': usage.rounds,
          'rounds_with_usage': usage.roundsWithUsage,
          'prompt_tokens': usage.promptTokens,
          'completion_tokens': usage.completionTokens,
          'total_tokens': usage.totalTokens,
          'cache_hit_prompt_tokens': usage.cacheHitPromptTokens,
          'cache_miss_prompt_tokens': usage.cacheMissPromptTokens,
          'last_prompt_tokens': usage.lastPromptTokens,
          'generation_ms': usage.generationTime.inMilliseconds,
          'elapsed_ms': watch.elapsedMilliseconds,
          'llm_error': state.error,
          'cancelled': state.cancelled,
          'assistant_text_chars': raw.length,
          'assistant_reasoning_chars': state.reasoningText.length,
        };

        // --- 4. 落盘并校验 ------------------------------------------------
        final reportFile = File('${outDir.path}\\draft-q19.run-report.json');
        reportFile.writeAsStringSync(
            const JsonEncoder.withIndent('  ').convert(report));

        if (state.error != null || raw.trim().isEmpty) {
          File('${outDir.path}\\draft-q19.raw.txt').writeAsStringSync(raw);
          fail('内部 agent 调用失败：error=${state.error} '
              'cancelled=${state.cancelled} chars=${raw.length} '
              '（raw 已存 draft-q19.raw.txt）');
        }

        final draft = _parseDraft(raw);
        final missing = _requiredKeys
            .where((k) => !draft.containsKey(k) || draft[k] == null)
            .toList();
        if (missing.isNotEmpty) {
          File('${outDir.path}\\draft-q19.raw.txt').writeAsStringSync(raw);
          fail('模型输出 JSON 缺少字段：$missing（raw 已存 draft-q19.raw.txt）');
        }
        _assertField(draft, 'preset', 'A');
        _assertField(draft, 'difficulty', 'finale');
        _assertField(draft, 'source', 'gaokao');
        // 答案必须是答题卡写法：每一问都有 formal_solution，且不能是“见解析”。
        final answer = draft['answer'];
        final answerParts = answer is Map ? answer['parts'] : null;
        if (answerParts is! List || answerParts.isEmpty) {
          fail('answer.parts 为空：解答题必须给答题卡上的完整解答');
        }
        for (final part in answerParts) {
          if (part is! Map) {
            fail('answer.parts 含非对象项');
          }
          final formal = (part['formal_solution'] as String?)?.trim() ?? '';
          if (formal.isEmpty) {
            fail('${part['label']} 缺少 formal_solution：答案必须是答题卡写法，不是只给结果');
          }
          if (formal.contains('见解析') || formal.contains('略')) {
            fail('${part['label']} 的 formal_solution 含“见解析/略”，不是可抄到答题卡的完整答案');
          }
        }
        final dag = draft['thinking_dag'];
        final nodes = dag is Map ? dag['nodes'] : null;
        final nodeCount = nodes is List ? nodes.length : 0;
        if (nodeCount < 6) {
          File('${outDir.path}\\draft-q19.raw.txt').writeAsStringSync(raw);
          fail('Thinking DAG 节点过少（$nodeCount < 6），不是完整解析');
        }

        final draftFile = File('${outDir.path}\\draft-q19.json');
        draftFile.writeAsStringSync(
            const JsonEncoder.withIndent('  ').convert(draft));
        final mdFile = File('${outDir.path}\\draft-q19.md');
        mdFile.writeAsStringSync(_renderMarkdown(draft, report));

        report['draft_json'] = draftFile.path;
        report['draft_md'] = mdFile.path;
        report['thinking_dag_nodes'] = nodeCount;
        report['validated'] = true;
        reportFile.writeAsStringSync(
            const JsonEncoder.withIndent('  ').convert(report));

        // ignore: avoid_print
        print('GENERATED draft=${draftFile.path} md=${mdFile.path} '
            'nodes=$nodeCount rounds=${usage.rounds} '
            'promptTokens=${usage.promptTokens} '
            'completionTokens=${usage.completionTokens} '
            'elapsedMs=${watch.elapsedMilliseconds}');
        expect(draftFile.existsSync(), isTrue);
      } finally {
        // 副本用完即删：真实库从未被打开，工作区不留数据库副本。
        try {
          await db?.close();
        } catch (_) {}
        try {
          if (copyDir.existsSync()) {
            copyDir.deleteSync(recursive: true);
          }
        } catch (_) {}
      }
    },
    timeout: const Timeout(Duration(minutes: 25)),
    skip: liveFlag.isEmpty,
  );
}

const _requiredKeys = <String>[
  'question_id',
  'title',
  'subject',
  'stem_md',
  'answer',
  'source',
  'preset',
  'difficulty',
  'thinking_dag',
  'traps',
  'error_causes',
  'mastery_points',
  'variant',
  'upper_knowledge',
  'extra_task',
];

void _assertField(Map<String, Object?> draft, String key, String expected) {
  final value = draft[key];
  if (value != expected) {
    fail('字段 $key 应为 "$expected"，实际为 "$value"');
  }
}

Map<String, Object?> _parseDraft(String raw) {
  var text = raw.trim();
  if (text.startsWith('```')) {
    final firstNewline = text.indexOf('\n');
    if (firstNewline > 0) {
      text = text.substring(firstNewline + 1);
    }
    final fenceEnd = text.lastIndexOf('```');
    if (fenceEnd >= 0) {
      text = text.substring(0, fenceEnd);
    }
  }
  final start = text.indexOf('{');
  final end = text.lastIndexOf('}');
  if (start < 0 || end <= start) {
    throw const FormatException('模型输出不含 JSON 对象');
  }
  final decoded = jsonDecode(text.substring(start, end + 1));
  if (decoded is! Map) {
    throw const FormatException('模型输出的 JSON 不是对象');
  }
  return decoded.map((key, value) => MapEntry(key.toString(), value));
}

String _buildPrompt(Map<String, Object?> source) {
  final stem = (source['stem_md'] as String?) ?? '';
  final answer = source['answer'];
  final answerSummary =
      answer is Map ? (answer['summary_md'] as String?) ?? '' : '';
  final analysis = source['analysis'];
  final groups = analysis is Map ? analysis['groups'] : null;
  final overview = StringBuffer();
  final detail = StringBuffer();
  if (groups is List) {
    for (final group in groups) {
      if (group is! Map || group['text'] is! String) {
        continue;
      }
      final label = (group['label'] as String?) ?? '';
      final text = group['text'] as String;
      if (label.contains('详解')) {
        detail.writeln(text);
      } else {
        overview.writeln(text);
      }
    }
  }
  final overviewText = overview.toString().trim();
  final detailText = detail.toString().trim();
  final score = source['score'];
  return '''
你是 Furnace 的内容生成 agent。请为下面这道 2025 年高考数学全国 I 卷第 19 题（压轴题，满分 $score 分）生成「A 等级学生」可用的完整内容草稿。

【硬性要求】
1. 只输出一个 JSON 对象：不要 Markdown 代码围栏（不要 ```），不要任何解释、前言或后记。
2. 字符串里的 LaTeX 反斜杠必须转义成双反斜杠（例如 \\\\cos、\\\\frac、\\\\sqrt、\\\\pi），保证输出能被 JSON.parse 解析。
3. 必须显式包含："preset": "A"、"difficulty": "finale"、"source": "gaokao"（source 是字符串，不是对象）。
4. thinking_dag 是给 A 等级学生看的**完整解析**，不是短标签：每个节点写清这一步的公式 / 关键量 / 结论，node.depends_on 表示依赖；覆盖题目 (1)(2)(3) 三个小问；nodes 至少 8 个、最多 14 个，edges 与 nodes 对应。
5. 答案必须是**答题卡上会写的内容**，不是“结果 + 见解析”：解答题每一问都要给 formal_solution（完整、连续、可直接抄到答题卡的推导/证明，含必要公式与结论）；不要写“证明见解析”“略”“同理可得”。(1) 与 (3) 最终结果都是 3\\sqrt{3}；(2) 是完整证明。
6. 内容要具体、可学、可执行；不要空话；DAG 是思路结构，不能代替答题卡答案。
7. 中文输出；不要约束总字数。扩展部分（变式/上位知识/额外任务）不设字数上限，尽量写透；DAG 节点正文要短（1–2 句核心推理+公式/关键量+结论），完整逻辑由节点和边承担，不要把整段解析塞进单个节点。

【必须输出的 JSON 结构】
{
  "question_id": "q-2025-math-national1-19",
  "title": "简短标题",
  "subject": "数学",
  "stem_md": "原题三问（LaTeX 保留）",
  "answer": {
    "summary": "三问答案汇总",
    "parts": [
      {"label": "(1)", "result": "3\\\\sqrt{3}", "formal_solution": "答题卡上的完整推导（含求导、符号、最大值）", "key_steps": ["关键步骤1", "关键步骤2"]},
      {"label": "(2)", "result": "证明成立", "formal_solution": "答题卡上的完整证明（反证：解集/补集、连通性、矛盾）", "key_steps": ["关键步骤1", "关键步骤2"]},
      {"label": "(3)", "result": "3\\\\sqrt{3}", "formal_solution": "答题卡上的完整推导（周期性/端点/中间 φ 下界/可达性）", "key_steps": ["关键步骤1", "关键步骤2"]}
    ]
  },
  "source": "gaokao",
  "source_detail": {"paper": "2025年普通高等学校招生全国统一考试（全国 I 卷）数学", "number": 19, "year": 2025, "region": "全国 I 卷", "score": $score},
  "preset": "A",
  "difficulty": "finale",
  "thinking_dag": {
    "summary": "整题思路一句话",
    "nodes": [
      {"id": "n1", "label": "这一步在做什么", "role": "setup|transform|derive|check|conclusion", "body": "完整说明（含公式与关键量）", "formula": "LaTeX（可空字符串）", "conclusion": "这一步的结论", "depends_on": ["n0"], "question_part": "(1)"}
    ],
    "edges": [{"from": "n1", "to": "n2", "reason": "为什么依赖"}]
  },
  "traps": ["陷阱1（具体到这一步为什么错）"],
  "error_causes": [{"cause": "错因", "symptom": "学生具体会写成什么/算成什么", "fix": "怎么纠正"}],
  "mastery_points": ["要掌握的能力/方法"],
  "variant": {"stem": "变式题面", "answer": "答案", "key_steps": ["步骤1", "步骤2"], "why_related": "与本题同源点"},
  "upper_knowledge": {"name": "上位知识名称", "content": "具体可学的内容（不是只提名词）", "why_it_helps": "如何迁移到本题/同类题"},
  "extra_task": {"task": "一个可执行的额外任务", "acceptance": "怎么算完成"}
}

【源题】
题干：
$stem

参考答案：
$answerSummary

知识点与分析：
$overviewText

参考解析（只作事实校验与步骤参考，请重组成完整 DAG，不要整段照抄）：
$detailText
''';
}

String _renderMarkdown(Map<String, Object?> draft, Map<String, Object?> report) {
  final b = StringBuffer();
  String str(Object? value) => value == null ? '' : value.toString();
  List<Object?> list(Object? value) =>
      value is List ? value.cast<Object?>() : const <Object?>[];
  String joinList(Object? value) =>
      list(value).map(str).where((s) => s.trim().isNotEmpty).join('；');

  b.writeln('# ${str(draft['title'])}');
  b.writeln();
  b.writeln('- question_id: `${str(draft['question_id'])}`');
  b.writeln('- 学科: ${str(draft['subject'])}');
  b.writeln('- 预设: `${str(draft['preset'])}`（A 等级）');
  b.writeln('- 难度: `${str(draft['difficulty'])}`（压轴）');
  b.writeln('- 来源: `${str(draft['source'])}`');
  final detail = draft['source_detail'];
  if (detail is Map) {
    b.writeln(
        '- 卷面: ${str(detail['paper'])} 第 ${str(detail['number'])} 题，'
        '${str(detail['year'])}，${str(detail['region'])}，满分 ${str(detail['score'])}');
  }
  b.writeln();
  b.writeln('## 题干');
  b.writeln();
  b.writeln(str(draft['stem_md']));
  b.writeln();

  b.writeln('## 答案');
  b.writeln();
  final answer = draft['answer'];
  if (answer is Map) {
    b.writeln(str(answer['summary']));
    b.writeln();
    for (final part in list(answer['parts'])) {
      if (part is! Map) {
        continue;
      }
      b.writeln('### ${str(part['label'])}');
      b.writeln();
      b.writeln('**结果**：${str(part['result'])}');
      b.writeln();
      final formal = str(part['formal_solution']).trim();
      if (formal.isNotEmpty) {
        b.writeln('**答题卡答案**：');
        b.writeln();
        b.writeln(formal);
        b.writeln();
      } else {
        for (final step in list(part['key_steps'])) {
          b.writeln('- $step');
        }
        b.writeln();
      }
    }
  } else {
    b.writeln(str(answer));
    b.writeln();
  }

  b.writeln('## Thinking DAG（完整解析）');
  b.writeln();
  final dag = draft['thinking_dag'];
  if (dag is Map) {
    if (str(dag['summary']).isNotEmpty) {
      b.writeln(str(dag['summary']));
      b.writeln();
    }
    for (final node in list(dag['nodes'])) {
      if (node is! Map) {
        continue;
      }
      final deps = joinList(node['depends_on']);
      b.writeln('### ${str(node['id'])} · ${str(node['label'])}');
      b.writeln();
      if (str(node['question_part']).isNotEmpty) {
        b.writeln('- 小问: ${str(node['question_part'])}');
      }
      b.writeln('- 角色: ${str(node['role'])}');
      b.writeln('- 说明: ${str(node['body'])}');
      if (str(node['formula']).isNotEmpty) {
        b.writeln('- 公式: `${str(node['formula'])}`');
      }
      if (str(node['conclusion']).isNotEmpty) {
        b.writeln('- 结论: ${str(node['conclusion'])}');
      }
      if (deps.isNotEmpty) {
        b.writeln('- 依赖: $deps');
      }
      b.writeln();
    }
    final edges = list(dag['edges']);
    if (edges.isNotEmpty) {
      b.writeln('### 依赖边');
      b.writeln();
      b.writeln('| from | to | reason |');
      b.writeln('| --- | --- | --- |');
      for (final edge in edges) {
        if (edge is Map) {
          b.writeln(
              '| ${str(edge['from'])} | ${str(edge['to'])} | ${str(edge['reason'])} |');
        }
      }
      b.writeln();
    }
  } else {
    b.writeln(str(dag));
    b.writeln();
  }

  b.writeln('## 陷阱');
  b.writeln();
  for (final trap in list(draft['traps'])) {
    b.writeln('- $trap');
  }
  b.writeln();

  b.writeln('## 错因');
  b.writeln();
  for (final cause in list(draft['error_causes'])) {
    if (cause is Map) {
      b.writeln('- **错因**：${str(cause['cause'])}');
      b.writeln('  - 表现：${str(cause['symptom'])}');
      b.writeln('  - 纠正：${str(cause['fix'])}');
    } else {
      b.writeln('- $cause');
    }
  }
  b.writeln();

  b.writeln('## 要掌握的点');
  b.writeln();
  for (final point in list(draft['mastery_points'])) {
    b.writeln('- $point');
  }
  b.writeln();

  b.writeln('## 变式（1 条）');
  b.writeln();
  final variant = draft['variant'];
  if (variant is Map) {
    b.writeln(str(variant['stem']));
    b.writeln();
    b.writeln('**答案**：${str(variant['answer'])}');
    b.writeln();
    for (final step in list(variant['key_steps'])) {
      b.writeln('- $step');
    }
    b.writeln();
    b.writeln('**同源点**：${str(variant['why_related'])}');
  } else {
    b.writeln(str(variant));
  }
  b.writeln();

  b.writeln('## 上位知识（1 条）');
  b.writeln();
  final upper = draft['upper_knowledge'];
  if (upper is Map) {
    b.writeln('**${str(upper['name'])}**');
    b.writeln();
    b.writeln(str(upper['content']));
    b.writeln();
    b.writeln('**迁移价值**：${str(upper['why_it_helps'])}');
  } else {
    b.writeln(str(upper));
  }
  b.writeln();

  b.writeln('## 额外任务（1 个）');
  b.writeln();
  final extra = draft['extra_task'];
  if (extra is Map) {
    b.writeln(str(extra['task']));
    b.writeln();
    b.writeln('**验收标准**：${str(extra['acceptance'])}');
  } else {
    b.writeln(str(extra));
  }
  b.writeln();

  b.writeln('---');
  b.writeln();
  b.writeln('## 生成记录（Furnace 内部 agent）');
  b.writeln();
  b.writeln('- 调用路径: ${str(report['call_path'])}');
  b.writeln('- 模型: `${str(report['model'])}` @ ${str(report['base_url'])}');
  b.writeln('- 轮次: ${str(report['rounds'])}');
  b.writeln('- token: prompt=${str(report['prompt_tokens'])} '
      'completion=${str(report['completion_tokens'])} '
      'total=${str(report['total_tokens'])}');
  b.writeln('- 耗时: 生成 ${str(report['generation_ms'])} ms / '
      '总 ${str(report['elapsed_ms'])} ms');
  return b.toString();
}
