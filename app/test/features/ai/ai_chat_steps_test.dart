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
import 'package:furnace/features/ai/presentation/widgets/run_timeline.dart';
import 'package:furnace/l10n/app_localizations.dart';

/// 本轮运行时间线在真实页面 + 真实 AgentLoop 上的接线。
///
/// run_timeline_test.dart 只验证「把状态画成什么样」，agent_loop_steps_test.dart
/// 只验证「状态里出现了哪些步骤」；这里补的是中间那段：一条脚本化的工具调用
/// 走完真实循环（审批引擎、工具执行、写库）时，聊天页是否真的在运行中显示步骤行、
/// 结束后折叠成摘要。模型是 FakeModelAdapter，数据库在内存里，不碰网络和文件系统。
void main() {
  late AppDatabase db;
  late FakeModelAdapter adapter;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    // 两轮：先调用真正的 create_questions 把题写进题库，再收尾回答。
    adapter = FakeModelAdapter([
      FakeModelAdapter.callTool('create_questions', {
        'questions': [
          {'stem': '页面级集成测试题：已知 x+1=2，求 x 的值。'},
        ],
      }),
      FakeModelAdapter.answer('已经誊写进题库了。'),
    ]);
    // 自动模式：create_questions 是可撤销的写操作，会直接执行而不是等确认。
    await AiRepository(db).saveConfig(
      const AiConfig(
        enabled: true,
        apiKey: 'sk-test',
        permissionMode: AiPermissionMode.auto,
      ),
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
          modelAdapterProvider.overrideWithValue(adapter),
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

  /// 推进固定帧数。生成中页面有无限进度条，不能用 pumpAndSettle。
  Future<void> pumpFrames(WidgetTester tester, [int frames = 10]) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  /// 轮询等待条件成立。预算按模拟时间算：本轮工具调用要走两轮模型，
  /// 每轮都要等技能目录读取那条 2 秒上限，所以留足 12 秒。
  Future<void> waitFor(
    WidgetTester tester,
    bool Function() condition, {
    required String reason,
  }) async {
    for (var i = 0; i < 600; i++) {
      if (condition()) {
        return;
      }
      await tester.pump(const Duration(milliseconds: 20));
    }
    fail('$reason 在 12 秒模拟时间内未满足');
  }

  testWidgets('一轮脚本化工具调用：运行中出现时间线，结束后折叠成摘要', (tester) async {
    final conversation = await AiRepository(db).createConversation();
    await pumpPage(tester);
    final l10n = l10nOf(tester);

    await tester.enterText(find.byType(TextField), '把这道题存下来。');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.send));

    // 逐帧观测，模拟一个真实用户在一轮进行中看到的内容：时间线先展开，
    // 工具调用出现后仍然可见，整轮结束后才折叠。不依赖具体秒数。
    var sawExpandedTimeline = false;
    var sawRound = false;
    var sawToolCall = false;
    for (var i = 0; i < 600; i++) {
      await tester.pump(const Duration(milliseconds: 20));
      if (find.byKey(runTimelineSummaryKey).evaluate().isNotEmpty) {
        break;
      }
      if (find.byKey(runTimelineKey).evaluate().isNotEmpty) {
        sawExpandedTimeline = true;
        if (find.textContaining(l10n.aiStepRound(1)).evaluate().isNotEmpty) {
          sawRound = true;
        }
        if (find
            .textContaining(l10n.aiStepCalling('create_questions'))
            .evaluate()
            .isNotEmpty) {
          sawToolCall = true;
        }
      }
    }

    expect(sawExpandedTimeline, isTrue, reason: '一轮进行中应出现本轮运行时间线');
    expect(sawRound, isTrue, reason: '时间线里应显示「第 1 轮」');
    expect(sawToolCall, isTrue, reason: '时间线里应显示正在调用的工具名');

    // 等页面把落库后的历史行全部加载回来，界面稳定后再断言与交互。
    await waitFor(
      tester,
      () => find.text('已经誊写进题库了。').evaluate().isNotEmpty,
      reason: '收尾回答未上屏',
    );
    await pumpFrames(tester);

    // 结束后：摘要行出现，步骤行收起。
    expect(find.byKey(runTimelineSummaryKey), findsOneWidget);
    final summary =
        tester.widget<Text>(find.byKey(runTimelineSummaryKey)).data ?? '';
    expect(summary, contains('本轮'));
    expect(summary, contains('步'));
    expect(find.textContaining(l10n.aiStepRound(1)), findsNothing,
        reason: '折叠后不应再显示步骤行');
    expect(find.textContaining(l10n.aiStepCalling('create_questions')),
        findsNothing);

    // 折叠是交互可逆的：点开摘要能重新看到步骤。
    await tester.tap(find.byKey(runTimelineHeaderKey));
    await tester.pump();
    expect(find.textContaining(l10n.aiStepRound(1)), findsOneWidget);
    expect(find.byKey(runTimelineStepKey(0)), findsOneWidget);
    await tester.tap(find.byKey(runTimelineHeaderKey));
    await tester.pump();
    expect(find.textContaining(l10n.aiStepRound(1)), findsNothing);

    // 工具真的写了库：不是只画了一行字。
    final questions = await db.select(db.questions).get();
    expect(questions, hasLength(1));
    expect(questions.single.stem, contains('页面级集成测试题'));
    final messages = await AiRepository(db).listMessages(conversation.id);
    expect(messages.map((m) => m.content), contains('已经誊写进题库了。'));
  });

  testWidgets('没有工具调用的一轮只有 1 步，没有调用工具行', (tester) async {
    adapter = FakeModelAdapter([FakeModelAdapter.answer('这道题我直接回答。')]);
    await AiRepository(db).createConversation();
    await pumpPage(tester);
    final l10n = l10nOf(tester);

    await tester.enterText(find.byType(TextField), '直接回答我。');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.send));
    await waitFor(
      tester,
      () => find.text('这道题我直接回答。').evaluate().isNotEmpty,
      reason: '回答未上屏',
    );
    await pumpFrames(tester);

    // 没有工具调用的一轮也有时间线：循环每轮都会追加一条模型步骤。
    // 区别在于没有「调用工具」行，整轮只有 1 步。
    expect(find.byKey(runTimelineKey), findsOneWidget);
    expect(find.byKey(runTimelineSummaryKey), findsOneWidget);
    expect(find.textContaining(l10n.aiStepCalling('create_questions')),
        findsNothing);
    expect(find.text(l10n.aiStepsSummary(1)), findsOneWidget);
  });
}
