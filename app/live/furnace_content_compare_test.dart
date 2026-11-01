// LIVE harness: Furnace 内部 AI 产出对比实验 — NOT part of the normal suite.
//
// 为什么放在 live/ 而不是 test/：它要真实 API key、会花额度，且必须显式运行：
//
//   cd E:/Projects/Furnace/app
//   FURNACE_LIVE_AI=1 flutter test live/furnace_content_compare_test.dart
//
// 它做四件事：
//  1. 从真实 app 数据库（%APPDATA%\FirsryFan\Furnace\furnace.db）**只读**读出
//     AI 配置；key 只用于请求头，绝不写进日志或输出（只打印长度不打印值）。
//  2. 用内存库 + 真实 AgentLoop / ApprovalEngine / CreateDocumentTool 跑一轮。
//  3. 把模型通过 create_document 写出的文档拷贝到
//     E:/Workspaces/Furnace/00-inbox/ai-compare/furnace/。
//  4. 把耗时 / token / 工具调用序列 / 审批路径写成 run.json 与 run.log，
//     供 COMPARISON.md 引用。
//
// 未接真实库的写入：所有工具调用都落在内存库与临时目录里，用户真实库一行不改。
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/ai_repository.dart';
import 'package:furnace/features/ai/domain/agent_loop.dart';
import 'package:furnace/features/ai/domain/approval_engine.dart';
import 'package:furnace/features/ai/domain/tool_registry.dart';
import 'package:furnace/features/ai/infrastructure/openai_compat_adapter.dart';
import 'package:furnace/features/ai/tools/document_tools.dart';
import 'package:sqlite3/sqlite3.dart' as sql;

const String _liveFlag = 'FURNACE_LIVE_AI';

/// 产物目录（工作区，允许写）。
const String _outRoot = r'E:\Workspaces\Furnace\00-inbox\ai-compare\furnace';

/// 两道真实高考题的题面。语文题取自组卷网抓取原文
/// （10-projects/zujuan-harvest/harvest/state/candidates-round2.json 的 text 字段）；
/// 数学题的公式在原站是图片，题面依据工作区 chain 文档的解析整理为等价表述。
const String _questions = r'''
## 语文题（2025·全国二卷·古代诗歌阅读，组卷网 10-27475362）

7. 阅读下面两首唐诗，完成下面小题。

咏省壁①画鹤
宋之问
粉壁图仙鹤，昂藏真气多。
鶱飞②竟不去，当是恋恩波③。

咏主人壁上画鹤寄乔主簿崔著作
陈子昂
古壁仙人画，丹青尚有文。
独舞纷如雪，孤飞暧似云。
自矜彩色重，宁忆故池群。
江海联翩翼，长鸣谁复闻。

【注】①省壁：中央官署的墙壁。②鶱飞：飞腾。③恩波：帝王的恩泽。

1．下列对这两首诗的理解和赏析，不正确的一项是（ ）
A．宋、陈这两首诗的题材相同，都是以墙壁上的画鹤作为吟咏对象。
B．在两首诗歌的后半部分，两位诗人都发挥主观想象，以表达情感。
C．宋之问诗的第二句从外在形态与内在气质两方面展现仙鹤的形象。
D．陈子昂诗用"古壁"一词强调墙壁的古旧，以衬托画鹤色彩鲜艳。

2．两首诗各自展现出了什么样的思想境界？请简要分析。

## 数学题（2024·新课标Ⅰ卷·解答题，组卷网 11-23121844）

说明：原题公式在组卷网是图片；以下题面依据工作区 chain 文档的解析整理为等价表述。

已知函数 $f(x)=\ln x-\ln(2-x)+ax+b(x-1)^3$。

(1) 若 $b=0$，且 $f'(x)\ge 0$ 对定义域内任意 $x$ 成立，求 $a$ 的最小值；

(2) 证明：曲线 $y=f(x)$ 是中心对称图形；

(3) 若 $f(x)>-2$ 当且仅当 $1<x<2$，求 $b$ 的取值范围。
''';

/// 给 Furnace 内部 AI 的真实任务：与 DSH 已产出的「六科训练材料」同构。
const String _prompt = r'''
你是 Furnace 的内置学习助手。下面有两道真实高考题（语文、数学各一道）。请把这两道题整理成一份可打印的《训练材料》Markdown 文档，用 create_document 工具保存（一份即可；如果内容太长，可以拆成两份，但不要超过两份）。

格式要求（与用户现有的六科训练材料一致）：
1. 文档分「第一部分 题目」与「第二部分 解析」；第一部分只放题目原文，不放答案。
2. 每题解析按顺序写：答案 → 可核对解析（按「定位 → 有效链 → 断点/剪枝 → 收束」四段展开，每一步回引原文或公式，不许跳步）→ 易错点 → 扩展（1-2 道变式题，附参考要点）。
3. 答案必须来自你自己的推导或题面；不确定的地方明确写「不确定」，不要编造解析。
4. 数学公式用 LaTeX（行内 $...$、行间 $$...$$）；语文引诗用原句，并注明是哪一首。
5. 全文用中文；标题自拟，例如「训练材料·语文诗歌比较 + 数学导数」。
6. 写完把 create_document 返回的文件路径原样告诉我，并用一句话说明这份材料最值得人工复核的地方。

下面是两道题的题面：

''' +
    _questions;

void main() {
  test(
      'live content compare: two real questions -> training material documents',
      () async {
    final enabled = Platform.environment[_liveFlag] == '1';
    if (!enabled) {
      // ignore: avoid_print
      print(
          'skipped: set $_liveFlag=1 to run the live content-compare harness');
      return;
    }

    // ---- 1. 从真实库只读读取 AI 配置（不打印 key） -----------------------
    final appData = Platform.environment['APPDATA']!;
    final livePath = '$appData\\FirsryFan\\Furnace\\furnace.db';
    final live = sql.sqlite3.open(livePath, mode: sql.OpenMode.readOnly);
    final row = live
        .select(
          'SELECT ai_api_key, ai_base_url, ai_model, ai_permission_mode, '
          'ai_max_rounds FROM local_settings',
        )
        .first;
    live.dispose();

    final key = row['ai_api_key'] as String?;
    expect(key, isNotNull,
        reason: 'real app database has no AI key configured');
    final baseUrl = (row['ai_base_url'] as String?) ?? AiConfig.defaultBaseUrl;
    final model = (row['ai_model'] as String?) ?? AiConfig.defaultModel;
    final mode = AiPermissionMode.fromId(row['ai_permission_mode'] as String?);
    final maxRounds = AiConfig.resolveMaxRounds(row['ai_max_rounds'] as int?);

    // ignore: avoid_print
    void say(Object? message) => print(message);

    say('LIVE mode=${mode.id} base=$baseUrl model=$model '
        'keyLen=${key!.length} maxRounds=$maxRounds dbReadOnly=ok');

    // ---- 2. 内存库 + 真实 loop -------------------------------------------
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final repository = AiRepository(db);
    await repository.saveConfig(
      AiConfig(
        enabled: true,
        apiKey: key,
        baseUrl: baseUrl,
        model: model,
        permissionMode: mode,
        maxRounds: maxRounds,
      ),
      fallbackLanguage: 'zh',
    );

    final supportDir =
        await Directory.systemTemp.createTemp('furnace_live_compare_');
    final documentTool = CreateDocumentTool(
      supportDirectory: () async => supportDir,
    );
    final adapter = OpenAiCompatAdapter(
      apiKey: key,
      baseUrl: baseUrl,
      model: model,
      temperature: 0.2,
    );
    final loop = AgentLoop(
      adapter: adapter,
      registry: ToolRegistry([documentTool]),
      approval: ApprovalEngine(mode: mode),
      repository: repository,
      db: db,
      maxRounds: maxRounds,
    );

    // 观测到的审批事件（真实运行时；auto 模式下应为空）。
    final pendingObserved = <Map<String, Object?>>[];
    final pendingCounts = <int>[];
    final sub = loop.states.listen((state) {
      if (state.pending.isNotEmpty) {
        pendingCounts.add(state.pending.length);
        for (final item in state.pending) {
          pendingObserved.add(<String, Object?>{
            'tool': item.tool.name,
            'title': item.title,
            'disposition': item.decision.disposition.name,
            'reason': item.decision.reason,
          });
        }
      }
    });

    final conversation = await repository.createConversation(
      title: 'live content compare 2026-11-01',
    );

    // ---- 3. 跑一轮，记录真实耗时与 token ---------------------------------
    final stopwatch = Stopwatch()..start();
    var approvalRounds = 0;
    try {
      await loop.sendUserMessage(
        conversationId: conversation.id,
        text: _prompt,
      );
      while (loop.state.hasPending && approvalRounds < 6) {
        approvalRounds += 1;
        await loop.approvePending(conversation.id);
        await Future<void>.delayed(Duration.zero);
      }
    } finally {
      stopwatch.stop();
    }
    await Future<void>.delayed(Duration.zero);

    final state = loop.state;
    final usage = state.usage;
    final actions = await repository.listCommittedActions(conversation.id);
    final messages = await repository.listMessages(conversation.id);

    // ---- 4. 收集产物文档：从临时 support 目录拷到工作区 ------------------
    final documentsDir = Directory(
      '${supportDir.path}${Platform.pathSeparator}'
      '${CreateDocumentTool.directoryName}',
    );
    final copied = <String>[];
    final produced = <Map<String, Object?>>[];
    if (documentsDir.existsSync()) {
      final outDir = Directory(_outRoot);
      if (!outDir.existsSync()) {
        await outDir.create(recursive: true);
      }
      final files = documentsDir
          .listSync(recursive: true)
          .whereType<File>()
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
      for (final file in files) {
        final name = file.uri.pathSegments.last;
        final target = File(
          '${outDir.path}${Platform.pathSeparator}$name',
        );
        await file.copy(target.path);
        copied.add(target.path);
        produced.add(<String, Object?>{
          'file': target.path,
          'bytes': target.lengthSync(),
          'source': file.path,
        });
      }
    }

    // ---- 5. 审批路径：记录实际裁决 + plan 模式的反事实裁决 --------------
    final approvalTrail = <Map<String, Object?>>[];
    final createDocumentActions = actions
        .where((a) => a.toolName == CreateDocumentTool.toolName)
        .toList();
    for (final action in createDocumentActions) {
      Map<String, Object?> args = const <String, Object?>{};
      try {
        args = (jsonDecode(action.argsJson ?? '{}') as Map)
            .cast<String, Object?>();
      } on FormatException {
        // malformed args are recorded as-is below
      }
      final actualDecision =
          ApprovalEngine(mode: mode).forInvocation(documentTool, args);
      final planDecision = const ApprovalEngine(mode: AiPermissionMode.plan)
          .forInvocation(documentTool, args);
      approvalTrail.add(<String, Object?>{
        'tool': action.toolName,
        'risk': action.risk,
        'status': action.status,
        'title': args['title'],
        'actualModeDisposition': actualDecision.disposition.name,
        'actualModeReason': actualDecision.reason,
        'planModeDisposition': planDecision.disposition.name,
        'planModeReason': planDecision.reason,
      });
    }

    // ---- 6. 写 run.json / run.log / prompt.md ----------------------------
    final steps = <Map<String, Object?>>[
      for (final step in state.steps)
        <String, Object?>{
          'id': step.id,
          'kind': step.kind.name,
          'round': step.round,
          'tool': step.toolName,
          'title': step.title,
          'status': step.status.name,
          'ok': step.ok,
          'summary': step.summary,
          'elapsedMs': step.elapsed?.inMilliseconds,
        },
    ];
    final run = <String, Object?>{
      'startedAt': DateTime.now().toIso8601String(),
      'model': model,
      'baseUrl': baseUrl,
      'permissionMode': mode.id,
      'maxRounds': maxRounds,
      'toolRegistry': ['create_document'],
      'wallMs': stopwatch.elapsedMilliseconds,
      'observedApproval': <String, Object?>{
        'pendingEvents': pendingCounts,
        'pendingCalls': pendingObserved,
        'approvePendingCalls': approvalRounds,
        'note': 'auto 模式下 write+reversible 的调用直接执行，不会出现 pending',
      },
      'usage': <String, Object?>{
        'rounds': usage.rounds,
        'roundsWithUsage': usage.roundsWithUsage,
        'promptTokens': usage.promptTokens,
        'completionTokens': usage.completionTokens,
        'totalTokens': usage.totalTokens,
        'cacheHitPromptTokens': usage.cacheHitPromptTokens,
        'cacheMissPromptTokens': usage.cacheMissPromptTokens,
        'generationMs': usage.generationTime.inMilliseconds,
        'tokensPerSecond': usage.tokensPerSecond,
        'lastPromptTokens': usage.lastPromptTokens,
        'contextWindowTokens': usage.contextWindowTokens,
      },
      'steps': steps,
      'actions': <Map<String, Object?>>[
        for (final action in actions)
          <String, Object?>{
            'tool': action.toolName,
            'risk': action.risk,
            'status': action.status,
            'messageId': action.messageId,
            'title': () {
              try {
                return (jsonDecode(action.argsJson ?? '{}') as Map)['title'];
              } catch (_) {
                return null;
              }
            }(),
            'result': action.resultJson,
          },
      ],
      'approvalTrail': approvalTrail,
      'messages': <Map<String, Object?>>[
        for (final m in messages)
          <String, Object?>{
            'role': m.role,
            'chars': (m.content ?? '').length,
            'content': m.content,
          },
      ],
      'producedDocuments': produced,
      'finalError': state.error,
      'finalAssistantText': state.streamingText,
      'promptChars': _prompt.length,
    };

    final jsonFile = File('$_outRoot\\run.json');
    await jsonFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(run),
      encoding: utf8,
    );
    await File('$_outRoot\\prompt.md').writeAsString(_prompt, encoding: utf8);

    final log = StringBuffer()
      ..writeln('# Furnace 内部 AI · live content compare')
      ..writeln()
      ..writeln('- 模型: $model')
      ..writeln('- 模式: ${mode.id}，maxRounds=$maxRounds')
      ..writeln('- 墙钟耗时: ${stopwatch.elapsedMilliseconds} ms')
      ..writeln('- 轮次: ${usage.rounds}，token: prompt ${usage.promptTokens} + '
          'completion ${usage.completionTokens} = ${usage.totalTokens}')
      ..writeln('- 生成耗时: ${usage.generationTime.inMilliseconds} ms，'
          'tokens/s: ${usage.tokensPerSecond}')
      ..writeln('- 观测到的 pending 事件: $pendingCounts，'
          'approvePending 次数: $approvalRounds')
      ..writeln('- 最终 error: ${state.error}')
      ..writeln()
      ..writeln('## 步骤时间线');
    for (final step in steps) {
      final tool = step['tool'];
      final summary = step['summary'];
      final elapsed = step['elapsedMs'];
      log.writeln(
        '- round ${step['round']} ${step['kind']}'
        '${tool == null ? '' : ' / $tool'}'
        ' / ${step['status']}'
        '${elapsed == null ? '' : ' / ${elapsed}ms'}'
        '${summary == null ? '' : ' — $summary'}',
      );
    }
    log
      ..writeln()
      ..writeln('## 工具动作');
    for (final action in actions) {
      log.writeln('- ${action.toolName} risk=${action.risk} '
          'status=${action.status}');
    }
    log
      ..writeln()
      ..writeln('## 审批路径');
    for (final entry in approvalTrail) {
      log.writeln('- ${entry['tool']}: 实际模式 → '
          '${entry['actualModeDisposition']}；plan 模式 → '
          '${entry['planModeDisposition']}');
    }
    log
      ..writeln()
      ..writeln('## 产物文档');
    for (final doc in produced) {
      log.writeln('- ${doc['file']} (${doc['bytes']} bytes)');
    }
    final logFile = File('$_outRoot\\run.log');
    await logFile.writeAsString(log.toString(), encoding: utf8);

    // ---- 7. 打印 + 断言（真实输出，不伪造） ------------------------------
    say('=== 结果 ===');
    say('wall=${stopwatch.elapsedMilliseconds}ms rounds=${usage.rounds} '
        'tokens=${usage.totalTokens} error=${state.error}');
    say('documents=${produced.map((d) => d['file']).toList()}');
    say('run.json=${jsonFile.path} run.log=${logFile.path}');

    sub.cancel();
    loop.dispose();
    adapter.close();
    await db.close();
    try {
      await supportDir.delete(recursive: true);
    } on FileSystemException {
      // temp dir cleanup is best-effort; the copies in the workspace are what matter
    }

    expect(state.error, isNull, reason: 'live turn failed');
    expect(
      createDocumentActions,
      isNotEmpty,
      reason: 'model did not call create_document; see run.json/run.log',
    );
    expect(produced, isNotEmpty, reason: 'no document file was produced');
    for (final doc in produced) {
      expect(File(doc['file'] as String).existsSync(), isTrue);
    }
  }, timeout: const Timeout(Duration(minutes: 10)));
}
