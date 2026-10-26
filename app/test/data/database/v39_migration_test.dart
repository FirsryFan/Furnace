import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/ai_repository.dart';
import 'package:sqlite3/sqlite3.dart' as sql;

/// v38 -> v39：AI 助手消息加 `reasoning`（思考过程）列（轮次一百七十八，
/// docs/REVIEW_FEEDBACK.md §4a）。
///
/// 列可空、NULL 代表「这条消息没有思考文本」，老库没有任何一行要回填。
/// 要锁的四件事：
///
///  1. 真实 v38 文件（库里已有对话与消息、只是没有这一列）升级后列就补上，
///     老消息读出来 reasoning 是 null，不会抛 no such column；
///  2. 升级后立刻能写思考文本、重开还在（历史消息折叠块读到的就是它）；
///  3. 被盖成 v39 却缺列的文件靠 beforeOpen 自愈；
///  4. 没传 reasoning 写 NULL，不是空字符串（UI 用 null 判断「没有思考过程」）。
void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('furnace_mig39_');
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// 用当前 schema 建库、写一条 v38 时代的对话与助手消息，再把 reasoning 列
  /// DROP 掉、把 user_version 压回 [userVersion]。
  Future<File> buildDb({
    required int userVersion,
    required String name,
    bool dropColumn = true,
  }) async {
    final dbFile = File('${tempDir.path}/$name.db');
    final fresh = AppDatabase.forTesting(NativeDatabase(dbFile));
    final repository = AiRepository(fresh);
    final conversation = await repository.createConversation(title: '旧对话');
    await repository.addMessage(
      conversationId: conversation.id,
      role: AiRepository.roleUser,
      content: '在吗',
    );
    await repository.addMessage(
      conversationId: conversation.id,
      role: AiRepository.roleAssistant,
      content: '在',
    );
    final conversationId = conversation.id;
    await fresh.close();

    final raw = sql.sqlite3.open(dbFile.path);
    if (dropColumn) {
      raw.execute('ALTER TABLE ai_messages DROP COLUMN reasoning');
    }
    raw.execute('PRAGMA user_version = $userVersion');
    raw.dispose();
    fileConversationId = conversationId;
    return dbFile;
  }

  test('真实 v38 文件升级后：老消息 reasoning 为 null，新消息能写思考、重开还在', () async {
    final file = await buildDb(userVersion: 38, name: 'v38');
    var db = AppDatabase.forTesting(NativeDatabase(file));
    var repository = AiRepository(db);

    var messages = await repository.listMessages(fileConversationId);
    expect(messages.length, 2, reason: '升级不动已有消息');
    expect(messages.map((m) => m.reasoning), everyElement(isNull),
        reason: '老消息没有思考文本 = NULL，不是空字符串');

    final written = await repository.addMessage(
      conversationId: fileConversationId,
      role: AiRepository.roleAssistant,
      content: '答案在这里',
      reasoning: '先化简，再代入。',
    );
    expect(written.reasoning, '先化简，再代入。');
    await db.close();

    // 已经是 v39，重开不再迁移；思考文本必须原样还在。
    db = AppDatabase.forTesting(NativeDatabase(file));
    repository = AiRepository(db);
    messages = await repository.listMessages(fileConversationId);
    expect(messages.length, 3);
    expect(messages.last.reasoning, '先化简，再代入。');
    expect(messages.first.reasoning, isNull);
    await db.close();
  });

  test('没传 reasoning 写 NULL（不是空字符串）', () async {
    final file = await buildDb(userVersion: 38, name: 'null');
    final db = AppDatabase.forTesting(NativeDatabase(file));
    final repository = AiRepository(db);

    final row = await repository.addMessage(
      conversationId: fileConversationId,
      role: AiRepository.roleAssistant,
      content: '普通回答',
    );
    expect(row.reasoning, isNull);
    await db.close();
  });

  test('被盖成 v39 却缺列的文件，靠自愈补列', () async {
    final file = await buildDb(userVersion: 39, name: 'fake39');
    final db = AppDatabase.forTesting(NativeDatabase(file));
    final repository = AiRepository(db);

    // 没有自愈的话，这里就 no such column 抛异常。
    final messages = await repository.listMessages(fileConversationId);
    expect(messages.length, 2);
    final row = await repository.addMessage(
      conversationId: fileConversationId,
      role: AiRepository.roleAssistant,
      content: '自愈之后',
      reasoning: '先看看列在不在',
    );
    expect(row.reasoning, '先看看列在不在');
    await db.close();
  });
}

/// [buildDb] 里新建的对话 id，供各用例读取历史消息。
late String fileConversationId;
