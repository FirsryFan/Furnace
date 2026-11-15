import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/ai_repository.dart';
import 'package:furnace/features/ai/domain/conversation_title.dart';

/// 对话自动取名（用户 2026-11-15 第 5 点）。
///
/// 两半分开测：纯函数钉「从文本取什么名字」，仓储测试钉「什么时候允许改名」——
/// 占位符可以换，用户/调用方给的名字必须保留（已有则复用）。
void main() {
  group('autoConversationTitle', () {
    test('以第一行非空文本为标题', () {
      expect(
        autoConversationTitle('帮我建一个任务：界面链路测试'),
        '帮我建一个任务：界面链路测试',
      );
      expect(
        autoConversationTitle('\n\n第一行是主题\n第二行是要求'),
        '第一行是主题',
      );
    });

    test('去掉行首 markdown 装饰并折叠空白', () {
      expect(autoConversationTitle('##   复习计划'), '复习计划');
      expect(autoConversationTitle('> 引用一句'), '引用一句');
      expect(autoConversationTitle('- 列表项'), '列表项');
      expect(autoConversationTitle('1. 第一步'), '第一步');
      expect(autoConversationTitle('  多个   空格   '), '多个 空格');
    });

    test('超长标题按 rune 截断并标记省略', () {
      final long = '一' * 40;
      final title = autoConversationTitle(long, maxLength: 10)!;
      expect(title, '${'一' * 10}…');
      expect(title.runes.length, 11);
    });

    test('空白文本没有标题', () {
      expect(autoConversationTitle(''), isNull);
      expect(autoConversationTitle('   \n\t  '), isNull);
      expect(autoConversationTitle('###'), isNull);
    });

    test('emoji 不会被切成半个 surrogate pair', () {
      final title = autoConversationTitle('😀😀😀😀', maxLength: 2)!;
      expect(title, '😀😀…');
    });
  });

  group('AiRepository.autoTitleFromFirstMessage', () {
    late AppDatabase db;
    late AiRepository repository;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repository = AiRepository(db);
    });

    tearDown(() => db.close());

    test('占位标题会被第一条用户消息替换', () async {
      final conversation = await repository.createConversation();
      expect(conversation.title, startsWith('对话 '));

      final renamed = await repository.autoTitleFromFirstMessage(
        conversationId: conversation.id,
        text: '把下周的复习计划排进日程',
      );

      expect(renamed, isTrue);
      final reloaded = await repository.getConversation(conversation.id);
      expect(reloaded!.title, '把下周的复习计划排进日程');
    });

    test('用户自己起的标题不会被覆盖', () async {
      final conversation = await repository.createConversation(title: '我的对话');

      final renamed = await repository.autoTitleFromFirstMessage(
        conversationId: conversation.id,
        text: '把下周的复习计划排进日程',
      );

      expect(renamed, isFalse);
      final reloaded = await repository.getConversation(conversation.id);
      expect(reloaded!.title, '我的对话');
    });

    test('空白消息不改名，未知会话返回 false', () async {
      final conversation = await repository.createConversation();

      expect(
        await repository.autoTitleFromFirstMessage(
          conversationId: conversation.id,
          text: '   ',
        ),
        isFalse,
      );
      expect(
        await repository.autoTitleFromFirstMessage(
          conversationId: 'conv-missing',
          text: '随便',
        ),
        isFalse,
      );
      final reloaded = await repository.getConversation(conversation.id);
      expect(reloaded!.title, startsWith('对话 '));
    });
  });
}
