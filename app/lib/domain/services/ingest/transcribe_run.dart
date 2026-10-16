/// 转写规程（照片 → `mindnet.run/1`）在应用侧的**确定性那一半**（`docs/archive/TRANSCRIBE.md`）。
///
/// 规程本身分两半：**上游 AI 看图写字**（这份文档 §6 的提示词就是给它的），
/// 和**确定性代码**（校验、说人话、把"它会做什么"预告出来）。这里做的是后者 ——
/// 与 `docs/INGEST.md` 的"三步法"同一条分界：AI 只产出字段，代码负责判定。
///
/// 三层，越往下越"我们说了算"：
///  1. [decodeRunRequest]：对象或 JSON 文本 → [MaterialRunRequest]（人话错误）；
///  2. [reviewTranscribedRun]：`io_check` 类自检 —— 硬错（整份拒绝的）与建议（不拦的）分开，
///     并把每条动作的机制路径预告出来（`review` 的 `wrong + reviewed_solution` 照实写成
///     学习路径）；
///  3. [buildTranscribePrompt]：把 §6 的提示词连【图清单】一起生成出来 —— 图清单是
///     "不许发明节点 id"这条约束的**唯一**依据，所以它必须来自真实数据，不能靠 AI 猜。
///
/// 刻意不做的事：不调 AI、不读写库、不跑引擎。这一层只回答两个问题：
/// "这份请求合法吗"与"它会做什么"。
library;

import 'dart:convert';

import 'material_ingest.dart';

/// 图清单的一行：MindNet 节点 id → 人话名字（提示词里就写这个）。
typedef TranscribeInventoryEntry = ({String id, String name});

/// 转写请求的解码（与材料信封的解码同一套人话错误）。
///
/// 接受对象或 JSON 文本：AI 常常把 JSON 包在代码围栏里贴过来，所以文本入口是常态。
MaterialRunRequest decodeRunRequest(Object? raw) {
  if (raw is String) {
    final text = raw.trim();
    if (text.isEmpty) {
      throw const FormatException('请求是空的：把 AI 产出的 mindnet.run/1 贴进来');
    }
    Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException catch (error) {
      throw FormatException('请求不是合法的 JSON 文本（${error.message}）');
    }
    return decodeRunRequest(decoded);
  }
  if (raw is Map) {
    return MaterialRunRequest.fromJson(raw.cast<String, Object?>());
  }
  throw const FormatException('请求必须是对象或 JSON 文本');
}

/// 一次转写自检的结果：`io_check` 的输出 + TRANSCRIBE 自己的建议。
class TranscribeReport {
  const TranscribeReport({
    required this.runId,
    required this.ok,
    required this.errors,
    required this.previews,
    required this.warnings,
    required this.evidenceCount,
    required this.actionCount,
  });

  final String runId;

  /// 结构上合法（硬错为空）。建议（[warnings]）不影响它 —— 规程说"建议全带"，
  /// 但缺一条 `confidence` 不该让整份请求作废。
  final bool ok;
  final List<String> errors;

  /// 每条动作"会落到哪条机制路径"（人话）。
  final List<String> previews;

  /// TRANSCRIBE §3/§6 的建议：不拦，但值得让用户看见。
  final List<String> warnings;

  final int evidenceCount;
  final int actionCount;

  /// 人话多行（对齐 `tools/io_check.js` 的打印）。
  String get text {
    final buffer = StringBuffer();
    if (ok) {
      buffer.writeln('✓ 请求合法：$runId · $actionCount 条动作');
    } else {
      buffer.writeln('✗ 请求不合法：${errors.join('；')}');
    }
    for (final preview in previews) {
      buffer.writeln('  $preview');
    }
    if (ok) {
      buffer.writeln('  出处：$evidenceCount/$actionCount 条带 evidence'
          '（建议全带 —— 出问题时才查得回去）');
    }
    if (warnings.isNotEmpty) {
      buffer.writeln('  建议（不拦）：');
      for (final warning in warnings) {
        buffer.writeln('    · $warning');
      }
    }
    return buffer.toString().trimRight();
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'ok': ok,
        'run_id': runId,
        'actions': actionCount,
        'errors': errors,
        'previews': previews,
        'warnings': warnings,
        'evidence_count': evidenceCount,
      };
}

/// 自检一份（AI 从照片产出的）`mindnet.run/1` 请求：**只校验、不执行**。
///
/// [existingNodeIds] 是图里已有的节点 id —— `review` / `exposure` / `goal` 的目标都必须在里面
/// （"不许发明节点 id"，TRANSCRIBE §1 第 2 条）。
TranscribeReport reviewTranscribedRun(
  MaterialRunRequest request, {
  Set<String> existingNodeIds = const <String>{},
  Set<String> existingEdgeIds = const <String>{},
}) {
  final check = MaterialIngest.checkRunRequest(
    request,
    existingNodeIds: existingNodeIds,
    existingEdgeIds: existingEdgeIds,
  );

  final warnings = <String>[];
  for (var i = 0; i < request.actions.length; i += 1) {
    final action = request.actions[i];
    final at = '第 ${i + 1} 条（${action.kind}）';

    final evidence = action.evidence;
    if (evidence == null) {
      warnings.add('$at：没有 evidence（出问题时查不回去，§3 建议每条都带）');
    } else {
      final quote = evidence['quote'];
      if (action.kind == 'review' &&
          (quote is! String || quote.trim().isEmpty)) {
        warnings.add('$at：是 review 但 evidence.quote 是空的'
            '（review 必须有可核对的痕迹，§1 第 3 条）');
      }
    }

    final confidence = action.confidence;
    if (confidence == null) {
      warnings.add('$at：没写 confidence（把握有多大要留下来，§3）');
    } else if (!confidence.isFinite || confidence < 0 || confidence > 1) {
      warnings.add('$at：confidence 必须是 0–1，实际 $confidence');
    }

    if (action.kind == 'review' &&
        action.reviewedSolution == true &&
        action.outcome != 'wrong') {
      warnings.add('$at：写了 reviewed_solution 但 outcome 是 ${action.outcome}'
          '（"看到订正"只对 wrong 有意义，写错会让模型学反，§2）');
    }
  }

  return TranscribeReport(
    runId: request.runId,
    ok: check.ok,
    errors: check.errors,
    previews: check.previews,
    warnings: warnings,
    evidenceCount: check.evidenceCount,
    actionCount: request.actions.length,
  );
}

/// §6 的提示词（整段可复制给任何有视觉能力的模型），**把【图清单】填进去**。
///
/// [inventory] 为空是正常情况（图里还没有节点）：提示词会明说"清单是空的，
/// 新知识点先走 `knowledge`"，而不是让 AI 去猜 id。
String buildTranscribePrompt({
  required List<TranscribeInventoryEntry> inventory,
  String? graphName,
  String? note,
}) {
  final graph = StringBuffer();
  if (graphName != null && graphName.trim().isNotEmpty) {
    graph.writeln('图：${graphName.trim()}');
  }
  if (inventory.isEmpty) {
    graph.write('（清单是空的：图里还没有节点。新知识点先写 knowledge 动作建出来，'
        '再用它的 id。）');
  } else {
    for (final entry in inventory) {
      graph.writeln('${entry.id} → ${entry.name}');
    }
  }
  final extra =
      note == null || note.trim().isEmpty ? '' : '\n\n【补充说明】\n${note.trim()}';

  return '''
你是 MindNet 的"转写员"。MindNet 是一个确定性的认知模型引擎，它不看照片、不调 AI，
只接受协议化的请求。你的唯一任务：把用户给的照片/文本，转写成一份合法的 run 请求 JSON。

【你只有五种动作，别的不许写】
- review   ：看到"做了这道题"且有对错证据。outcome = correct | wrong | blank
             若同时看到订正/抄了解析，加 "reviewed_solution": true（并可给 closeness 0–1）
- exposure ：看到"读了/抄了/整理了"，但没有测试证据
- knowledge：题目引入了图里没有的知识点（给 node），或出现了新连接（给 edge）
- goal     ：用户明确说"我要搞定 X"
- time     ：需要推进到某时刻，或记录花了多久（at 或 elapsed_hours）

【绝对不许】
1. 写 S / D / R0 / 任何模型内部量；
2. 发明节点 id —— node 必须是下面【图清单】里已有的 id（新知识点先用 knowledge 建）；
3. 把"我觉得他掌握了"写成 review —— review 必须有可核对痕迹（evidence.quote 里写他实际写了什么）；
4. 猜时间：看不出时间就问，或用 time 动作显式给出；不许省略 at，也不许写 "now"；
5. 同一节点同一时刻写两条矛盾的 outcome。

【每条动作必带】
- at：{ "model_hours": <数字> }（若知道现实时间，同时给 "wall"）
- evidence：{ "source": <文件名>, "region": <照片哪一块>, "quote": <你实际看到的原文> }
- confidence：0–1，你对这条判断的把握

【输出格式】只输出 JSON，不要解释文字，不要 markdown 代码围栏：
{
  "protocol": "mindnet.run/1",
  "run_id": "<日期-序号，例如 run-2026-09-25-0007>",
  "time": { "model_hours": <当前模型时刻>, "wall": "<ISO 时间>" },
  "actions": [ ... ]
}

【发输出前逐条自检】
□ protocol 是 "mindnet.run/1"，run_id 非空且本次唯一
□ 每条 action 的 kind 在这五种之内
□ 每条 action 都有 at（或 time 动作有 elapsed_hours）
□ 所有 node 都在【图清单】里（不在就先写 knowledge 建）
□ 每一道题都有对应的一条 review/exposure（没有遗漏、没有合并）
□ 没有写任何模型内部量（S/D/R0）
□ outcome 与"有没有看到订正"匹配（看到订正才写 reviewed_solution）
□ JSON 能被 JSON.parse 解析（无注释、无尾逗号）

【图清单】（节点 id → 名称）
$graph$extra
''';
}
