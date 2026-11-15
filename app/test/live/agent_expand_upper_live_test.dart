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

/// task-110 补充（lead 2026-11-15 口径）：把六份草稿的「上位知识」从一段概述
/// 扩写成深讲笔记（七个部分：前置知识 / 解决什么问题 / 动机与来历 / 推导主线 /
/// 适用边界 / 在本题哪一步用 / 还能用在哪些题），不设字数上限。
///
/// 仍是 Furnace 内部 agent 路径（非 DSH、无 UI）：
///   AiRepository.getConfig() -> AiModelAdapters.chat(config) -> AgentLoop.sendUserMessage
/// 每题 1 次；结果只写工作区 `.work/.../upper/<serial>.json`，不写真实库。
///
///   flutter test test/live/agent_expand_upper_live_test.dart \
///     --dart-define=RUN_LIVE_EXPAND=1
void main() {
  const workspace = r'E:\Workspaces\agent-control';
  const realDbPath = r'E:\Furnace\data\furnace.db';
  const flag = String.fromEnvironment('RUN_LIVE_EXPAND');
  const work = '$workspace\\.work\\six-subject-drafts-2026-11-15';
  const drafts =
      '$workspace\\10-projects\\agent-control-plane\\six-subject-drafts';

  test(
    '内部 agent 扩写六份草稿的上位知识',
    () async {
      final outDir = Directory('$work\\upper')..createSync(recursive: true);
      final realDb = File(realDbPath);
      expect(realDb.existsSync(), isTrue);
      final copyDir = Directory(
          '$work\\db-copy-upper-${DateTime.now().millisecondsSinceEpoch}');
      copyDir.createSync(recursive: true);
      final copyPath = '${copyDir.path}\\furnace.db';
      realDb.copySync(copyPath);

      AppDatabase? db;
      final results = <Map<String, Object?>>[];
      try {
        db = AppDatabase.forTesting(NativeDatabase(File(copyPath)));
        final repository = AiRepository(db);
        final config = await repository.getConfig();
        if (!config.isUsable) {
          fail('AI 配置不可用');
        }
        const only = String.fromEnvironment('EXPAND_SERIALS');
        final serials = only.isEmpty
            ? const [657, 658, 659, 660, 661, 662]
            : only.split(',').map((s) => int.parse(s.trim())).toList();
        for (final serial in serials) {
          final draftFile = File('$drafts\\$serial\\draft.json');
          if (!draftFile.existsSync()) {
            results.add({'serial': serial, 'ok': false, 'error': 'draft.json 不存在'});
            continue;
          }
          final draft = jsonDecode(await draftFile.readAsString())
              as Map<String, Object?>;
          final prompt = _buildPrompt(draft);
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
          await loop.sendUserMessage(conversationId: conversation.id, text: prompt);
          watch.stop();
          final usage = loop.state.usage;
          final messages = await repository.listMessages(conversation.id);
          final assistant =
              messages.where((m) => m.role == AiRepository.roleAssistant).toList();
          final raw = assistant.isEmpty ? '' : (assistant.last.content ?? '');
          final report = <String, Object?>{
            'serial': serial,
            'call_path':
                'AiRepository.getConfig -> AiModelAdapters.chat(config) -> '
                    'AgentLoop.sendUserMessage (ToolRegistry empty, no UI)',
            'model': config.effectiveModel,
            'prompt_tokens': usage.promptTokens,
            'completion_tokens': usage.completionTokens,
            'elapsed_ms': watch.elapsedMilliseconds,
          };
          try {
            final parsed = _parseJson(raw);
            final upper = parsed['upper_knowledge'];
            if (upper is! Map) {
              throw const FormatException('缺少 upper_knowledge');
            }
            final content = (upper['content'] as String?)?.trim() ?? '';
            if (content.length < 1200) {
              throw FormatException('content 过短（${content.length} 字）');
            }
            for (final marker in const ['一、', '二、', '三、', '四、', '五、', '六、', '七、']) {
              if (!content.contains(marker)) {
                throw FormatException('缺少小节 $marker');
              }
            }
            final outFile = File('${outDir.path}\\$serial.json');
            outFile.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(
                <String, Object?>{
                  'serial': serial,
                  'upper_knowledge': upper,
                  'generation': report,
                }));
            report['ok'] = true;
            report['chars'] = content.length;
            report['file'] = outFile.path;
            // ignore: avoid_print
            print('OK $serial upper chars=${content.length} '
                'tokens=${usage.completionTokens} ms=${watch.elapsedMilliseconds}');
          } catch (e) {
            File('${outDir.path}\\$serial.raw.txt').writeAsStringSync(raw);
            report['ok'] = false;
            report['error'] = '$e';
            // ignore: avoid_print
            print('FAIL $serial: $e');
          }
          results.add(report);
        }
        File('${outDir.path}\\upper-expanded.json').writeAsStringSync(
            const JsonEncoder.withIndent('  ')
                .convert(<String, Object?>{'runs': results}));
      } finally {
        try {
          await db?.close();
        } catch (_) {}
        try {
          if (copyDir.existsSync()) copyDir.deleteSync(recursive: true);
        } catch (_) {}
      }
    },
    timeout: const Timeout(Duration(minutes: 60)),
    skip: flag.isEmpty,
  );
}

Map<String, Object?> _parseJson(String raw) {
  var text = raw.trim();
  if (text.startsWith('```')) {
    final nl = text.indexOf('\n');
    if (nl > 0) text = text.substring(nl + 1);
    final end = text.lastIndexOf('```');
    if (end >= 0) text = text.substring(0, end);
  }
  final start = text.indexOf('{');
  final end = text.lastIndexOf('}');
  if (start < 0 || end <= start) {
    throw const FormatException('模型输出不含 JSON 对象');
  }
  var body = text.substring(start, end + 1);
  // 模型偶尔把 LaTeX 反斜杠写成单个（\c、\s…），先补成合法 JSON 转义。
  body = body.replaceAllMapped(
      RegExp(r'\\(?!["\\/bfnrtu])'), (m) => r'\\');
  final decoded = jsonDecode(body);
  if (decoded is! Map) throw const FormatException('JSON 不是对象');
  return decoded.map((k, v) => MapEntry(k.toString(), v));
}

String _buildPrompt(Map<String, Object?> draft) {
  final subject = '${draft['subject']}';
  final stem = '${draft['stem_md']}';
  final answer = '${(draft['answer'] as Map?)?['summary']}';
  final dag = draft['thinking_dag'] as Map?;
  final nodes = (dag?['nodes'] as List?) ?? const [];
  final dagLines = nodes
      .map((n) => n is Map
          ? '- ${n['question_part']} ${n['id']} ${n['label']}：${n['conclusion']}'
          : '')
      .where((s) => s.isNotEmpty)
      .join('\n');
  final current = draft['upper_knowledge'];
  final currentText = current is Map
      ? '名称：${current['name']}\n内容：${current['content']}\n迁移价值：${current['why_it_helps']}'
      : '$current';
  return '''
你是 Furnace 的内容生成 agent。下面是一道高考$subject压轴题草稿（题干、答题卡答案、Thinking DAG 摘要、当前「上位知识」草稿）。请把「上位知识」扩写成一份可直接给学生看的深讲笔记。

【硬性要求】
1. 只输出一个 JSON 对象：不要 Markdown 代码围栏，不要任何解释或前后缀。
2. 结构固定为：{"upper_knowledge": {"name": "上位知识名称", "content": "深讲正文", "why_it_helps": "迁移价值"}}。
3. content 必须按七个小节展开，每节单独成段并以这些标签开头（标签必须原样出现）：
   一、前置知识
   二、它解决什么问题
   三、动机与来历
   四、推导主线
   五、适用边界与后果
   六、在本题哪一步用
   七、还能用在哪些题
4. 每一节都要写透：前置知识写出具体公式/结论；动机写清为什么要造这个工具；推导主线要一步步推（不能只贴结论）；边界要写成立条件与失效情形；第六节要指出对应的 DAG 节点（用 nX 编号）与代入了什么；第七节至少 3 个具体迁移场景，每个写一句怎么用。
5. 不设字数上限，宁可长而实，不要空话。公式用 LaTeX，反斜杠在 JSON 里写成双反斜杠（例如 \\\\sqrt、\\\\frac、\\\\cos）。
6. why_it_helps 写 2-4 句，说明这份知识如何改变做题动作，不要复述正文。
7. 中文输出；不要写学生分数、掌握度、能力测量。

【题干】
$stem

【答案】
$answer

【Thinking DAG 摘要】
$dagLines

【当前上位知识草稿（需要扩写，不要照抄）】
$currentText
''';
}
