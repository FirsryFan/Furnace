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

/// task-110：用 Furnace 内部 agent 为六科样例题（真实库 serial 657-662）
/// 生成成熟题单草稿（答案 + Thinking DAG + 陷阱/错因/掌握点/变式/上位知识/额外任务）。
///
/// 调用路径（内部路径，非 DSH、无 UI）：
///   AiRepository.getConfig()
///     -> AiModelAdapters.chat(config)
///     -> AgentLoop.sendUserMessage(...)   // 空 ToolRegistry，每题 1 次
///
/// 真实库只以**临时副本**打开（复制到工作区 `.work/.../db-copy-*`），
/// 所有产物写到工作区 `10-projects/agent-control-plane/six-subject-drafts/<serial>/`，
/// 不写真实库、不写任何学生测量表。
///
/// 运行：
///   flutter test test/live/agent_generate_six_drafts_live_test.dart \
///     --dart-define=RUN_LIVE_GENERATE=1
void main() {
  const workspace = r'E:\Workspaces\agent-control';
  const realDbPath = r'E:\Furnace\data\furnace.db';
  const liveFlag = String.fromEnvironment('RUN_LIVE_GENERATE');
  const work = '$workspace\\.work\\six-subject-drafts-2026-11-15';
  const outRoot =
      '$workspace\\10-projects\\agent-control-plane\\six-subject-drafts';

  test(
    '内部 agent 生成六科成熟题单草稿（serial 657-662）',
    () async {
      final bundleFile = File('$work\\source-six.json');
      expect(bundleFile.existsSync(), isTrue, reason: '输入包不存在：${bundleFile.path}');
      final bundle =
          jsonDecode(await bundleFile.readAsString()) as Map<String, Object?>;
      final items = (bundle['items'] as List).cast<Map<String, Object?>>();
      expect(items, hasLength(6));

      final realDb = File(realDbPath);
      expect(realDb.existsSync(), isTrue, reason: '真实库不存在');

      // 真实库临时副本：只读使用，用完即删。
      final copyDir = Directory(
          '$work\\db-copy-${DateTime.now().millisecondsSinceEpoch}');
      copyDir.createSync(recursive: true);
      final copyPath = '${copyDir.path}\\furnace.db';
      realDb.copySync(copyPath);
      for (final suffix in const <String>['-wal', '-shm']) {
        final side = File('${realDb.path}$suffix');
        if (side.existsSync()) {
          side.copySync('${copyDir.path}\\furnace$suffix');
        }
      }

      final results = <Map<String, Object?>>[];
      AppDatabase? db;
      try {
        db = AppDatabase.forTesting(NativeDatabase(File(copyPath)));
        final repository = AiRepository(db);
        final config = await repository.getConfig();
        final cfgLine = 'CONFIG usable=${config.isUsable} '
            'model=${config.effectiveModel} base=${config.effectiveBaseUrl} '
            'effort=${config.reasoningEffort} perm=${config.permissionMode.id} '
            'maxRounds=${config.maxRounds}';
        // ignore: avoid_print
        print(cfgLine);
        if (!config.isUsable) {
          fail('AI 配置不可用，拒绝烧 token：$cfgLine');
        }

        for (final item in items) {
          final serial = (item['serial'] as num).toInt();
          final subject = item['subject'] as String;
          final dir = Directory('$outRoot\\$serial')..createSync(recursive: true);
          final draftFile = File('${dir.path}\\draft.json');
          final mdFile = File('${dir.path}\\draft.md');
          final reportFile = File('${dir.path}\\run-report.json');
          final prompt = _buildPrompt(item);

          // --- Furnace 内部 agent：一题一次 sendUserMessage ---
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
              messages.where((m) => m.role == AiRepository.roleAssistant).toList();
          final raw = assistant.isEmpty ? '' : (assistant.last.content ?? '');

          final report = <String, Object?>{
            'serial': serial,
            'subject': subject,
            'content_id': item['content_id'],
            'call_path':
                'AiRepository.getConfig -> AiModelAdapters.chat(config) -> '
                    'AgentLoop.sendUserMessage (ToolRegistry empty, no UI)',
            'real_db_source': realDbPath,
            'real_db_copy': copyPath,
            'model': config.effectiveModel,
            'base_url': config.effectiveBaseUrl,
            'permission_mode': config.permissionMode.id,
            'max_rounds': config.maxRounds,
            'conversation_id': conversation.id,
            'rounds': usage.rounds,
            'prompt_tokens': usage.promptTokens,
            'completion_tokens': usage.completionTokens,
            'total_tokens': usage.totalTokens,
            'generation_ms': usage.generationTime.inMilliseconds,
            'elapsed_ms': watch.elapsedMilliseconds,
            'llm_error': state.error,
            'cancelled': state.cancelled,
            'assistant_text_chars': raw.length,
          };

          File('${dir.path}\\prompt.txt').writeAsStringSync(prompt);
          if (state.error != null || raw.trim().isEmpty) {
            File('${dir.path}\\draft.raw.txt').writeAsStringSync(raw);
            report['ok'] = false;
            report['error'] = 'agent failed: error=${state.error} chars=${raw.length}';
            reportFile.writeAsStringSync(
                const JsonEncoder.withIndent('  ').convert(report));
            results.add(report);
            // ignore: avoid_print
            print('FAIL $serial $subject: ${report['error']}');
            continue;
          }

          try {
            final draft = _parseDraft(raw);
            // 固定字段：不让模型改题目身份。
            draft['serial'] = serial;
            draft['question_id'] = item['content_id'];
            draft['db_question_id'] = item['question_id'];
            draft['subject'] = subject;
            draft['preset'] = 'A';
            draft['difficulty'] = 'finale';
            draft['source'] = 'gaokao';
            draft['review_status'] = 'draft_pending_review';
            draft['source_detail'] = item['source_detail'];
            draft['score'] = item['score'];
            final enforced = _enforceOfficialAnswer(draft, item);
            draft['answer_source'] = '官方答案（解析卷）';
            if (enforced.isNotEmpty) {
              draft['answer_enforced_fields'] = enforced;
            }
            final problems = _validateDraft(draft, item);
            if (problems.isNotEmpty) {
              File('${dir.path}\\draft.raw.txt').writeAsStringSync(raw);
              report['ok'] = false;
              report['error'] = 'validation: ${problems.join(' | ')}';
              reportFile.writeAsStringSync(
                  const JsonEncoder.withIndent('  ').convert(report));
              results.add(report);
              // ignore: avoid_print
              print('FAIL $serial $subject: ${report['error']}');
              continue;
            }
            draft['generation'] = {
              'call_path': report['call_path'],
              'model': report['model'],
              'rounds': report['rounds'],
              'prompt_tokens': report['prompt_tokens'],
              'completion_tokens': report['completion_tokens'],
              'total_tokens': report['total_tokens'],
              'elapsed_ms': report['elapsed_ms'],
              'draft_only': true,
              'review_status': 'draft_pending_review',
              'writes_student_measurement': false,
              'generated_at': DateTime.now().toIso8601String(),
            };
            draftFile.writeAsStringSync(
                const JsonEncoder.withIndent('  ').convert(draft));
            mdFile.writeAsStringSync(_renderMarkdown(draft, report));
            report['ok'] = true;
            report['draft_json'] = draftFile.path;
            report['draft_md'] = mdFile.path;
            report['thinking_dag_nodes'] =
                ((draft['thinking_dag'] as Map)['nodes'] as List).length;
            report['answer_enforced_fields'] = enforced;
            reportFile.writeAsStringSync(
                const JsonEncoder.withIndent('  ').convert(report));
            results.add(report);
            // ignore: avoid_print
            print('OK $serial $subject nodes=${report['thinking_dag_nodes']} '
                'completionTokens=${usage.completionTokens} '
                'elapsedMs=${watch.elapsedMilliseconds} '
                'enforced=${enforced.length}');
          } catch (e) {
            File('${dir.path}\\draft.raw.txt').writeAsStringSync(raw);
            report['ok'] = false;
            report['error'] = 'parse/render: $e';
            reportFile.writeAsStringSync(
                const JsonEncoder.withIndent('  ').convert(report));
            results.add(report);
            // ignore: avoid_print
            print('FAIL $serial $subject: $e');
          }
        }

        File('$outRoot\\run-report.json').writeAsStringSync(
            const JsonEncoder.withIndent('  ')
                .convert(<String, Object?>{'runs': results}));
      } finally {
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
    timeout: const Timeout(Duration(minutes: 90)),
    skip: liveFlag.isEmpty,
  );
}

Map<String, Object?> _parseDraft(String raw) {
  var text = raw.trim();
  if (text.startsWith('```')) {
    final firstNewline = text.indexOf('\n');
    if (firstNewline > 0) {
      text = text.substring(firstNewline + 1);
    }
  }
  final fenceEnd = text.lastIndexOf('```');
  if (fenceEnd >= 0) {
    text = text.substring(0, fenceEnd);
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

/// 官方答案固定的小题，强制把 answer.parts[].result 对齐到官方答案；
/// 记录被改写的字段，便于事后审计。
List<String> _enforceOfficialAnswer(
    Map<String, Object?> draft, Map<String, Object?> item) {
  final enforced = <String>[];
  final answer = draft['answer'];
  if (answer is! Map) {
    return enforced;
  }
  final parts = answer['parts'];
  if (parts is! List) {
    return enforced;
  }
  final mode = item['answer_mode'];
  if (mode == 'official_text') {
    // 语文：四个问句必须逐字等于《高考试题分析》参考答案。
    final official = (item['official_answer'] as String)
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .toList();
    for (var i = 0; i < parts.length && i < official.length; i++) {
      final part = parts[i];
      if (part is! Map) continue;
      final result = (part['result'] as String?)?.trim() ?? '';
      final want = official[i].trim();
      // 允许括号内的替代表述与标点差异：只比较去掉括号内容后的主干。
      if (!_containsCore(result, want)) {
        part['result'] = want;
        part['result_source'] = '《2026年版全国高考语文试题分析》参考答案';
        enforced.add('answer.parts[$i].result');
      }
    }
  } else if (mode == 'writing_reference') {
    // 英语：参考范文必须逐字使用解析卷范文（非唯一答案）。
    final official = (item['official_answer'] as String).trim();
    final blocks = official.split('\n\n');
    for (var i = 0; i < parts.length && i < blocks.length; i++) {
      final part = parts[i];
      if (part is! Map) continue;
      final block = blocks[i].trim(); // "Para 1\n..." 或 "Para 2\n..."
      final newline = block.indexOf('\n');
      final para = newline > 0 ? block.substring(newline + 1).trim() : block;
      final formal = (part['formal_solution'] as String?)?.trim() ?? '';
      final ok = formal.isNotEmpty &&
          _norm(formal).contains(_norm(para.substring(0, 40))) &&
          _norm(formal).length > _norm(para).length * 0.9;
      if (!ok) {
        part['formal_solution'] = para;
        part['formal_solution_source'] = '解析卷参考范文（非唯一答案）';
        enforced.add('answer.parts[$i].formal_solution');
      }
      part['non_unique'] = true;
      part['note'] = '参考范文，非唯一答案';
    }
  }
  return enforced;
}

String _norm(String s) =>
    s.replaceAll(RegExp(r'\s+'), '').replaceAll('，', ',').replaceAll('。', '.');

bool _containsCore(String got, String want) {
  final g = _norm(got);
  final w = _norm(want);
  if (g.contains(w)) return true;
  // 去掉括号内容后再比
  final wNoParen = w.replaceAll(RegExp(r'（[^）]*）'), '').replaceAll(RegExp(r'\([^)]*\)'), '');
  final gNoParen = g.replaceAll(RegExp(r'（[^）]*）'), '').replaceAll(RegExp(r'\([^)]*\)'), '');
  return gNoParen.contains(wNoParen);
}

List<String> _validateDraft(Map<String, Object?> draft, Map<String, Object?> item) {
  final problems = <String>[];
  if (draft['preset'] != 'A') problems.add('preset != A');
  if (draft['difficulty'] != 'finale') problems.add('difficulty != finale');
  if (draft['source'] != 'gaokao') problems.add('source != gaokao');
  final title = (draft['title'] as String?)?.trim() ?? '';
  if (title.isEmpty) problems.add('title 为空');

  final answer = draft['answer'];
  if (answer is! Map) {
    problems.add('answer 不是对象');
  } else {
    final summary = (answer['summary'] as String?)?.trim() ?? '';
    if (summary.isEmpty) problems.add('answer.summary 为空');
    final parts = answer['parts'];
    if (parts is! List || parts.isEmpty) {
      problems.add('answer.parts 为空');
    } else {
      final mode = item['answer_mode'] as String?;
      final expectParts = mode == 'official_text'
          ? 4
          : mode == 'writing_reference'
              ? 2
              : mode == 'option_judgement'
                  ? 4
                  : (item['question_type'] == 'solution'
                      ? (item['serial'] == 660 ? 4 : 3)
                      : 0);
      if (expectParts > 0 && parts.length != expectParts) {
        problems.add('parts 数量 ${parts.length} != $expectParts');
      }
      for (final part in parts) {
        if (part is! Map) {
          problems.add('parts 含非对象');
          continue;
        }
        final label = (part['label'] as String?)?.trim() ?? '';
        final result = (part['result'] as String?)?.trim() ?? '';
        final formal = (part['formal_solution'] as String?)?.trim() ?? '';
        if (result.isEmpty) problems.add('$label result 为空');
        if (formal.isEmpty) problems.add('$label formal_solution 为空');
        if (formal.contains('见解析') || formal.contains('略')) {
          problems.add('$label formal_solution 含“见解析/略”');
        }
        if (label.isEmpty) problems.add('parts 含空 label');
      }
    }
    if (item['answer_mode'] == 'option_judgement') {
      final s = summary;
      if (!s.contains('BD')) problems.add('选择题结论不含 BD');
      final labels = <String, String>{};
      for (final part in parts as List) {
        if (part is Map) {
          labels['${part['label']}'.trim()] = '${part['result']}';
        }
      }
      const want = {'A': '正确', 'B': '错误', 'C': '正确', 'D': '错误'};
      want.forEach((k, v) {
        final got = labels[k] ?? '';
        if (!got.contains(v)) problems.add('选项 $k 结论应为 $v，实际 $got');
      });
    }
  }

  final dag = draft['thinking_dag'];
  if (dag is! Map) {
    problems.add('thinking_dag 不是对象');
  } else {
    final summary = (dag['summary'] as String?)?.trim() ?? '';
    if (summary.isEmpty) problems.add('thinking_dag.summary 为空');
    final nodes = dag['nodes'];
    final edges = dag['edges'];
    if (nodes is! List || nodes.length < 6 || nodes.length > 16) {
      problems.add('thinking_dag.nodes 数量异常（${nodes is List ? nodes.length : nodes}）');
    } else {
      final ids = <String>{};
      for (final node in nodes) {
        if (node is! Map) {
          problems.add('nodes 含非对象');
          continue;
        }
        final id = '${node['id']}'.trim();
        ids.add(id);
        for (final key in const ['label', 'body', 'conclusion']) {
          if (('${node[key]}').trim().isEmpty) {
            problems.add('节点 $id 缺少 $key');
          }
        }
        if (('${node['question_part']}').trim().isEmpty) {
          problems.add('节点 $id 缺少 question_part');
        }
      }
      if (edges is! List || edges.length < nodes.length - 3) {
        problems.add('edges 过少（${edges is List ? edges.length : edges} / nodes ${nodes.length}）');
      } else {
        for (final edge in edges) {
          if (edge is! Map) continue;
          final from = '${edge['from']}';
          final to = '${edge['to']}';
          if (!ids.contains(from) || !ids.contains(to)) {
            problems.add('edge $from->$to 端点不在 nodes 中');
          }
        }
      }
    }
  }

  for (final key in const ['traps', 'error_causes', 'mastery_points']) {
    final v = draft[key];
    if (v is! List || v.length < 3) {
      problems.add('$key 少于 3 条');
    }
  }
  final variant = draft['variant'];
  if (variant is! Map ||
      (variant['stem'] as String?)?.trim().isEmpty == true ||
      (variant['answer'] as String?)?.trim().isEmpty == true) {
    problems.add('variant 不完整');
  }
  final upper = draft['upper_knowledge'];
  if (upper is! Map ||
      (upper['name'] as String?)?.trim().isEmpty == true ||
      (upper['content'] as String?)?.trim().isEmpty == true) {
    problems.add('upper_knowledge 不完整');
  }
  final extra = draft['extra_task'];
  if (extra is! Map ||
      (extra['task'] as String?)?.trim().isEmpty == true ||
      (extra['acceptance'] as String?)?.trim().isEmpty == true) {
    problems.add('extra_task 不完整');
  }
  return problems;
}

String _buildPrompt(Map<String, Object?> item) {
  final subject = item['subject'] as String;
  final serial = item['serial'];
  final stem = item['stem_md'] as String;
  final answer = item['official_answer'] as String;
  final analysis = item['official_analysis'] as String;
  final figure = (item['figure_notes'] as String?) ?? '';
  final special = (item['special'] as String?) ?? '';
  final verified = (item['verified_reference'] as String?) ?? '';
  final score = item['score'];
  final paper = (item['source_detail'] as Map)['paper'];
  final number = (item['source_detail'] as Map)['number'];
  final partLabels = switch (serial) {
    657 => 'Para 1 / Para 2',
    658 => '① / ② / ③ / ④',
    661 => 'A / B / C / D',
    _ => '(1) / (2) / (3)${serial == 660 ? ' / (4)' : ''}',
  };
  return '''
你是 Furnace 的内容生成 agent。请为下面这道高考$subject压轴题（$paper 第 $number 题，满分 $score 分）生成「A 等级学生」可用的**成熟题单草稿**。

【硬性要求】
1. 只输出一个 JSON 对象：不要 Markdown 代码围栏（不要 ```），不要任何解释、前言或后记。
2. 字符串里的 LaTeX 反斜杠必须转义成双反斜杠（例如 \\\\cos、\\\\frac、\\\\sqrt、\\\\pi），保证输出能被 JSON.parse 解析。
3. 必须显式包含："preset": "A"、"difficulty": "finale"、"source": "gaokao"（source 是字符串，不是对象）、"review_status": "draft_pending_review"。
4. answer 必须是**答题卡上会写的内容**：每一小问都要有 result 和 formal_solution；formal_solution 要完整、连续、可直接抄到答题卡（含必要公式与结论），**不能写“证明见解析”“略”“同理可得”**。
5. thinking_dag 是给 A 等级学生看的完整解析（思路结构）：nodes 6–13 个，每个节点含 id / label（短，≤14 字）/ role（setup|transform|derive|check|conclusion）/ body（1–2 句核心推理，含公式或关键量，≤90 字）/ formula（LaTeX，可空字符串）/ conclusion（一句结论）/ question_part（必须是 $partLabels 之一）/ depends_on（节点 id 数组）；edges 每个含 from / to / reason，且端点必须在 nodes 里；每个小问至少 1 个节点；跨小问引用必须在 edges 里显式写出。
6. traps（≥3 条）、error_causes（≥3 条，每条 cause/symptom/fix）、mastery_points（≥3 条）、variant（1 条：stem/answer/key_steps/why_related）、upper_knowledge（1 条：name/content/why_it_helps）、extra_task（1 条：task/acceptance）都要具体、可执行，不要空话；扩展部分不设字数上限。
7. 中文输出（英语作文的范文本身用英文）。不要写学生分数、掌握度、能力测量。
8. 官方答案与官方解析是**事实基准**：结论、数值、选项对错必须与它一致；不要自编官方没有的结论。

【本题特殊要求】
$special

【必须输出的 JSON 结构】
{
  "question_id": "${item['content_id']}",
  "title": "简短标题",
  "subject": "$subject",
  "stem_md": "原题题干（LaTeX 保留）",
  "answer": {
    "summary": "答案汇总（解答题写三问/四问结果；选择题写“故选 BD”）",
    "parts": [
      {"label": "$partLabels", "result": "这一问的答案/结论", "formal_solution": "答题卡上的完整解答", "key_steps": ["关键步骤1", "关键步骤2"]}
    ]
  },
  "source": "gaokao",
  "preset": "A",
  "difficulty": "finale",
  "review_status": "draft_pending_review",
  "thinking_dag": {
    "summary": "整题思路一句话",
    "nodes": [
      {"id": "n1", "label": "这一步在做什么", "role": "setup|transform|derive|check|conclusion", "body": "1–2 句核心推理", "formula": "LaTeX 或空字符串", "conclusion": "这一步的结论", "question_part": "(1)", "depends_on": []}
    ],
    "edges": [{"from": "n1", "to": "n2", "reason": "为什么依赖"}]
  },
  "traps": ["陷阱1（具体到这一步为什么错）"],
  "error_causes": [{"cause": "错因", "symptom": "学生具体会写成什么/算成什么", "fix": "怎么纠正"}],
  "mastery_points": ["要掌握的方法/结论"],
  "variant": {"stem": "变式题面", "answer": "答案", "key_steps": ["步骤1"], "why_related": "与本题同源点"},
  "upper_knowledge": {"name": "上位知识名称", "content": "具体可学的内容", "why_it_helps": "怎么迁移"},
  "extra_task": {"task": "一个可执行的额外任务", "acceptance": "怎么算完成"}
}

【原题题干】
$stem

【官方答案（解析卷/答案卷）】
$answer

【官方解析（事实基准；可重组为 DAG，但结论不能改）】
$analysis

【图注（图片内容的人工转写，因为你看不到图片）】
$figure

【已核对的参考解答（可作事实校验，优先保证与官方答案一致）】
$verified
''';
}

String _renderMarkdown(Map<String, Object?> draft, Map<String, Object?> report) {
  final b = StringBuffer();
  String str(Object? value) => value == null ? '' : value.toString();
  List<Object?> list(Object? value) => value is List ? value.cast<Object?>() : const <Object?>[];
  String joinList(Object? value) =>
      list(value).map(str).where((s) => s.trim().isNotEmpty).join('；');

  b.writeln('# ${str(draft['title'])}');
  b.writeln();
  b.writeln('- serial: `${str(draft['serial'])}`');
  b.writeln('- question_id: `${str(draft['question_id'])}`');
  b.writeln('- 学科: ${str(draft['subject'])}');
  b.writeln('- 预设: `${str(draft['preset'])}`（A 等级）');
  b.writeln('- 难度: `${str(draft['difficulty'])}`（压轴）');
  b.writeln('- 来源: `${str(draft['source'])}`');
  final detail = draft['source_detail'];
  if (detail is Map) {
    b.writeln('- 卷面: ${str(detail['paper'])} 第 ${str(detail['number'])} 题，'
        '${str(detail['year'])}，${str(detail['region'])}，满分 ${str(detail['score'])}');
  }
  b.writeln('- 状态: `${str(draft['review_status'])}`（草稿，待人工复核）');
  b.writeln();
  b.writeln('## 题干');
  b.writeln();
  b.writeln(str(draft['stem_md']));
  b.writeln();

  b.writeln('## 答案（答题卡写法）');
  b.writeln();
  final answer = draft['answer'];
  if (answer is Map) {
    b.writeln(str(answer['summary']));
    b.writeln();
    for (final part in list(answer['parts'])) {
      if (part is! Map) continue;
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
      }
      if (part['non_unique'] == true) {
        b.writeln('> ${str(part['note'])}');
        b.writeln();
      }
      for (final step in list(part['key_steps'])) {
        b.writeln('- $step');
      }
      b.writeln();
    }
  } else {
    b.writeln(str(answer));
    b.writeln();
  }

  b.writeln('## Thinking DAG（完整思路）');
  b.writeln();
  final dag = draft['thinking_dag'];
  if (dag is Map) {
    if (str(dag['summary']).isNotEmpty) {
      b.writeln(str(dag['summary']));
      b.writeln();
    }
    for (final node in list(dag['nodes'])) {
      if (node is! Map) continue;
      final deps = joinList(node['depends_on']);
      b.writeln('### ${str(node['id'])} · ${str(node['label'])}');
      b.writeln();
      b.writeln('- 小问: ${str(node['question_part'])}');
      b.writeln('- 角色: ${str(node['role'])}');
      b.writeln('- 说明: ${str(node['body'])}');
      if (str(node['formula']).isNotEmpty) {
        b.writeln('- 公式: `${str(node['formula'])}`');
      }
      if (str(node['conclusion']).isNotEmpty) {
        b.writeln('- 结论: ${str(node['conclusion'])}');
      }
      if (deps.isNotEmpty) b.writeln('- 依赖: $deps');
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
          b.writeln('| ${str(edge['from'])} | ${str(edge['to'])} | ${str(edge['reason'])} |');
        }
      }
      b.writeln();
    }
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
  }
  b.writeln();

  b.writeln('## 额外任务（1 个）');
  b.writeln();
  final extra = draft['extra_task'];
  if (extra is Map) {
    b.writeln(str(extra['task']));
    b.writeln();
    b.writeln('**验收标准**：${str(extra['acceptance'])}');
  }
  b.writeln();

  b.writeln('---');
  b.writeln();
  b.writeln('## 生成记录（Furnace 内部 agent，草稿不写学生测量）');
  b.writeln();
  b.writeln('- 调用路径: ${str(report['call_path'])}');
  b.writeln('- 模型: `${str(report['model'])}` @ ${str(report['base_url'])}');
  b.writeln('- 轮次: ${str(report['rounds'])}');
  b.writeln('- token: prompt=${str(report['prompt_tokens'])} '
      'completion=${str(report['completion_tokens'])} '
      'total=${str(report['total_tokens'])}');
  b.writeln('- 耗时: 生成 ${str(report['generation_ms'])} ms / 总 ${str(report['elapsed_ms'])} ms');
  return b.toString();
}

