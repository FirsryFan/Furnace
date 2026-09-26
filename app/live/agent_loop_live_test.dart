// LIVE API harness for the agent loop — NOT part of the normal suite.
//
// It lives outside `test/` on purpose: it needs a real API key, spends credit,
// and must never run in CI. Run it explicitly with:
//
//   FURNACE_LIVE_AI=1 flutter test live/agent_loop_live_test.dart
//
// It reads the key from the real app database (read-only) and uses an IN-MEMORY
// database, so the real loop, tools and approvals run end to end without
// touching the user's data.
//
// Each step resolves its turn completely before the next one starts, which is
// what the app's UI enforces (its input is disabled while a turn awaits
// approval).
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/ai_repository.dart';
import 'package:furnace/data/repositories/task_repository.dart';
import 'package:furnace/data/repositories/time_block_repository.dart';
import 'package:furnace/features/ai/domain/agent_loop.dart';
import 'package:furnace/features/ai/domain/approval_engine.dart';
import 'package:furnace/features/ai/domain/tool_registry.dart';
import 'package:furnace/features/ai/infrastructure/openai_compat_adapter.dart';
import 'package:furnace/features/ai/tools/schedule_tools.dart';
import 'package:furnace/features/ai/tools/task_tools.dart';
import 'package:sqlite3/sqlite3.dart' as sql;

const _liveFlag = 'FURNACE_LIVE_AI';

void main() {
  final enabled = Platform.environment[_liveFlag] == '1';

  test('live agent loop', () async {
    if (!enabled) {
      // ignore: avoid_print
      print('skipped: set $_liveFlag=1 to run the live API harness');
      return;
    }

    final appData = Platform.environment['APPDATA']!;
    final live = sql.sqlite3.open('$appData\\FirsryFan\\Furnace\\furnace.db',
        mode: sql.OpenMode.readOnly);
    final row = live
        .select('SELECT ai_api_key, ai_base_url, ai_model, ai_permission_mode '
            'FROM local_settings')
        .first;
    live.dispose();

    final key = row['ai_api_key'] as String?;
    expect(key, isNotNull, reason: 'no API key configured');
    final baseUrl =
        (row['ai_base_url'] as String?) ?? 'https://api.deepseek.com';
    final model = (row['ai_model'] as String?) ?? 'deepseek-chat';
    final mode = AiPermissionMode.fromId(row['ai_permission_mode'] as String?);

    void say(Object? message) => print(message); // ignore: avoid_print

    say('LIVE mode=${mode.id} base=$baseUrl model=$model keyLen=${key!.length}');

    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final tasks = TaskRepository(db);
    final blocks = TimeBlockRepository(db);
    final repository = AiRepository(db);
    await repository.saveConfig(
      AiConfig(
        enabled: true,
        apiKey: key,
        baseUrl: baseUrl,
        model: model,
        permissionMode: mode,
      ),
      fallbackLanguage: 'zh',
    );

    final adapter = OpenAiCompatAdapter(
        apiKey: key, baseUrl: baseUrl, model: model, temperature: 0.2);
    final loop = AgentLoop(
      adapter: adapter,
      registry: ToolRegistry([
        QueryTasksTool(tasks, db),
        ManageTaskTool(tasks, db),
        QueryScheduleTool(blocks),
        ManageTimeBlockTool(blocks, db),
      ]),
      approval: ApprovalEngine(mode: mode),
      repository: repository,
      db: db,
    );

    final conversation = await repository.createConversation(title: 'live');
    final states = <AgentTurnState>[];
    final sub = loop.states.listen(states.add);

    AgentTurnState latest() => states.isEmpty ? loop.state : states.last;

    /// Validates the invariant the provider enforces: every assistant message
    /// that carries tool calls must be answered immediately by one tool message
    /// per call. Checked against what is STORED, which is what matters.
    Future<void> checkHistory(String label) async {
      final rows = await repository.listMessages(conversation.id);
      final actions = await repository.listCommittedActions(conversation.id);
      final byMessage = <String, List<String>>{};
      for (final a in actions) {
        if (a.messageId == null || a.toolCallId == null) continue;
        byMessage.putIfAbsent(a.messageId!, () => []).add(a.toolCallId!);
      }
      final problems = <String>[];
      for (final entry in byMessage.entries) {
        final assistant =
            rows.where((r) => r.id == entry.key).toList();
        if (assistant.isEmpty) {
          problems.add('action points at missing message ${entry.key}');
          continue;
        }
        for (final id in entry.value) {
          final answered = rows.any(
              (r) => r.role == AiRepository.roleTool && r.toolCallId == id);
          if (!answered) problems.add('tool call $id has no stored reply');
        }
      }
      final committed = byMessage.values.expand((e) => e).toSet();
      for (final r in rows.where((r) => r.role == AiRepository.roleTool)) {
        if (!committed.contains(r.toolCallId)) {
          problems.add('orphan tool reply ${r.toolCallId}');
        }
      }
      say(problems.isEmpty
          ? '   [$label] 历史结构有效 ✔'
          : '   [$label] ✗ $problems');
      expect(problems, isEmpty, reason: '$label: stored history is invalid');
    }

    void dump(String label) {
      final s = latest();
      say('[$label] generating=${s.generating} pending=${s.pending.length} '
          'executed=${s.executed.length} error=${s.error}');
      for (final p in s.pending) {
        say('    pending: ${p.tool.name} / ${p.title} / '
            '${p.decision.disposition.name} — ${p.decision.reason}');
      }
      for (final e in s.executed) {
        say('    executed: ${e.summary} (undoable=${e.result.isUndoable})');
      }
      states.clear();
    }

    /// Runs a user message and resolves whatever it proposes, the way the UI
    /// does: approve everything, repeatedly, until the turn settles.
    Future<void> sayAndResolve(String text, {int maxApprovals = 4}) async {
      await loop.sendUserMessage(conversationId: conversation.id, text: text);
      await Future<void>.delayed(Duration.zero);
      var approvals = 0;
      while (loop.state.hasPending && approvals < maxApprovals) {
        approvals++;
        await loop.approvePending(conversation.id);
        await Future<void>.delayed(Duration.zero);
      }
    }

    // ---------------------------------------------------------- 1. read only
    say('\n=== 1) 只读查询 ===');
    await tasks.createTask(title: '已有任务A', priority: 3);
    await tasks.createTask(title: '已有任务B', priority: 1);
    await sayAndResolve('我现在有哪些任务？');
    dump('1');
    await checkHistory('1');

    // ------------------------------------------------------------- 2. create
    say('\n=== 2) 建任务 ===');
    await sayAndResolve('帮我建一个任务：真实链路测试');
    dump('2');
    final created = await tasks.getTasks();
    say('   库里的任务 = ${created.map((t) => t.title).toList()}');
    await checkHistory('2');

    // --------------------------------------------------------------- 3. undo
    final executed = latest().executed;
    if (executed.isNotEmpty) {
      final target = executed.firstWhere(
        (e) => e.result.isUndoable,
        orElse: () => executed.first,
      );
      say('\n=== 3) 撤销「${target.summary}」 ===');
      await loop.undoExecuted(conversation.id, target.actionId);
      await Future<void>.delayed(Duration.zero);
      say('   撤销后库里的任务 = '
          '${(await tasks.getTasks()).map((t) => t.title).toList()}');
    }

    // ----------------------------------------------------------- 4. deletion
    say('\n=== 4) 删除（任何模式都必须停下确认）===');
    final victim = (await tasks.getTasks()).first;
    await loop.sendUserMessage(
        conversationId: conversation.id, text: '把「${victim.title}」删掉');
    await Future<void>.delayed(Duration.zero);
    dump('4a');
    final stillThere = (await tasks.getTasks()).any((t) => t.id == victim.id);
    say('   目标任务还在 = $stillThere （应为 true）');
    await checkHistory('4a');

    if (loop.state.hasPending) {
      say('\n=== 5) 拒绝删除 ===');
      await loop.rejectPending(conversation.id);
      await Future<void>.delayed(Duration.zero);
      say('   拒绝后任务数 = ${(await tasks.getTasks()).length}');
      final msgs = await repository.listMessages(conversation.id);
      final toolMsgs = msgs.where((m) => m.role == AiRepository.roleTool).toList();
      if (toolMsgs.isNotEmpty) {
        say('   最后回灌给模型 = ${toolMsgs.last.content}');
      }
      await checkHistory('5');
    }

    await sub.cancel();
    loop.dispose();
    adapter.close();
    await db.close();
    say('\n=== 完成（内存库，未触碰真实数据）===');
  }, timeout: const Timeout(Duration(minutes: 8)));
}
