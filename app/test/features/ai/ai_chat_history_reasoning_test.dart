import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/ai_repository.dart';
import 'package:furnace/features/ai/application/ai_providers.dart';
import 'package:furnace/features/ai/infrastructure/fake_model_adapter.dart';
import 'package:furnace/features/ai/presentation/ai_chat_page.dart';
import 'package:furnace/l10n/app_localizations.dart';

/// 历史消息里的思考过程（schema v39 落库后的 UI）。
///
/// AgentLoop 把思考文本随助手消息写进 `ai_messages.reasoning`，但页面重新
/// 打开后只渲染了正文。这里钉四件事：
///  1. 有 reasoning 的历史助手消息出现一个折叠块，默认收起（正文留视觉重心）；
///  2. 点开能看到完整思考文本，再点收起；
///  3. NULL / 空串 / 空白 reasoning 不出现任何占位；
///  4. 每条消息各自记住展开状态，展开一条不会把另一条也打开。
///
/// 流式生成中的 [_ReasoningPanel] 由 ai_chat_page_test.dart 覆盖，本文件只用
/// 已落库的历史行，不发送任何消息。
void main() {
  late AppDatabase db;
  late AiRepository repository;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repository = AiRepository(db);
    // 页面在配置不可用时会渲染「未设置」屏，而不是聊天；历史断言就落空了。
    await repository.saveConfig(
      const AiConfig(enabled: true, apiKey: 'sk-test'),
      fallbackLanguage: 'zh',
    );
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> pumpPage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          modelAdapterProvider.overrideWithValue(
            FakeModelAdapter([FakeModelAdapter.answer('好的')]),
          ),
        ],
        child: const MaterialApp(
          locale: Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: AiChatPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  AppLocalizations l10nOf(WidgetTester tester) =>
      AppLocalizations.of(tester.element(find.byType(AiChatPage)));

  /// 造一段历史对话：用户提问 + 助手回答（可带思考文本）。
  /// 返回助手消息 id（折叠块 key 需要它）与会话 id（追加下一段时用）。
  Future<({String conversationId, String messageId})> seedExchange({
    String question = '动量守恒的条件是什么？',
    String answer = '系统所受合外力为零。',
    String? reasoning,
    String? conversationId,
  }) async {
    final id = conversationId ?? (await repository.createConversation()).id;
    await repository.addMessage(
      conversationId: id,
      role: AiRepository.roleUser,
      content: question,
    );
    final assistant = await repository.addMessage(
      conversationId: id,
      role: AiRepository.roleAssistant,
      content: answer,
      reasoning: reasoning,
    );
    return (conversationId: id, messageId: assistant.id);
  }

  testWidgets('有 reasoning 的历史助手消息出现默认收起的折叠块', (tester) async {
    const reasoning = '先选系统，再看合外力是否为零。';
    final seeded = await seedExchange(reasoning: reasoning);
    await pumpPage(tester);

    final header = find.byKey(aiHistoryReasoningKey(seeded.messageId));
    expect(header, findsOneWidget);
    expect(find.text(l10nOf(tester).aiReasoningTitle), findsOneWidget);
    // 默认收起：思考文本不渲染，正文照常显示。
    expect(find.text(reasoning), findsNothing);
    expect(find.text('系统所受合外力为零。'), findsOneWidget);
    // 位置：思考块在它所生成的正文上方。
    expect(
      tester.getTopLeft(header).dy,
      lessThan(tester.getTopLeft(find.text('系统所受合外力为零。')).dy),
    );
  });

  testWidgets('点击折叠块展开思考文本，再点收起', (tester) async {
    const reasoning = '第一步：确定研究对象；第二步：受力分析。';
    final seeded = await seedExchange(reasoning: reasoning);
    await pumpPage(tester);

    final header = find.byKey(aiHistoryReasoningKey(seeded.messageId));
    await tester.tap(header);
    await tester.pumpAndSettle();
    expect(find.text(reasoning), findsOneWidget);

    await tester.tap(header);
    await tester.pumpAndSettle();
    expect(find.text(reasoning), findsNothing);
    expect(header, findsOneWidget);
  });

  testWidgets('reasoning 为 null / 空串 / 空白的历史消息都不显示折叠块', (tester) async {
    final first = await seedExchange(question: '问题一', answer: '答案一');
    final second = await seedExchange(
      conversationId: first.conversationId,
      question: '问题二',
      answer: '答案二',
      reasoning: '',
    );
    final third = await seedExchange(
      conversationId: first.conversationId,
      question: '问题三',
      answer: '答案三',
      reasoning: '   ',
    );
    await pumpPage(tester);

    expect(find.text(l10nOf(tester).aiReasoningTitle), findsNothing);
    expect(find.byKey(aiHistoryReasoningKey(first.messageId)), findsNothing);
    expect(find.byKey(aiHistoryReasoningKey(second.messageId)), findsNothing);
    expect(find.byKey(aiHistoryReasoningKey(third.messageId)), findsNothing);
    expect(find.text('答案二'), findsOneWidget);
  });

  testWidgets('每条消息的展开状态互不影响', (tester) async {
    const firstReasoning = '第一段思考：先看合外力。';
    const secondReasoning = '第二段思考：区分内力与外力。';
    final first = await seedExchange(
      reasoning: firstReasoning,
      question: '外力呢？',
      answer: '外力为零才守恒。',
    );
    final second = await seedExchange(
      conversationId: first.conversationId,
      question: '那内力呢？',
      answer: '内力不改变总动量。',
      reasoning: secondReasoning,
    );
    await pumpPage(tester);

    expect(find.text(l10nOf(tester).aiReasoningTitle), findsNWidgets(2));
    await tester.tap(find.byKey(aiHistoryReasoningKey(first.messageId)));
    await tester.pumpAndSettle();
    expect(find.text(firstReasoning), findsOneWidget);
    expect(find.text(secondReasoning), findsNothing);
    expect(find.byKey(aiHistoryReasoningKey(second.messageId)), findsOneWidget);
  });
}
