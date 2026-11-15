import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/ai_repository.dart';
import 'package:furnace/features/ai/application/ai_providers.dart';
import 'package:furnace/features/ai/domain/agent_run.dart';
import 'package:furnace/features/ai/domain/model_adapter.dart';
import 'package:furnace/features/ai/domain/vision_payload.dart';
import 'package:furnace/features/ai/infrastructure/agent_run_store.dart';
import 'package:furnace/features/ai/infrastructure/ai_attachment_store.dart';
import 'package:furnace/features/ai/infrastructure/fake_model_adapter.dart';
import 'package:furnace/features/ai/presentation/ai_chat_page.dart';
import 'package:furnace/features/ai/presentation/widgets/turn_metrics_bar.dart';
import 'package:furnace/features/questions/presentation/drop_intake_filter.dart';
import 'package:furnace/features/questions/presentation/drop_intake_reader.dart';
import 'package:furnace/l10n/app_localizations.dart';

/// AI 对话页 2026-11-15 重构的验收点（用户列出的 10 条）。
///
/// 每条都落在真实 widget 树上，而不是检查私有方法：没有顶栏、折叠按钮在左栏
/// 边缘、新对话在右上、左栏逐条删除且没有对话 icon、标题自动取、拖拽图片（没有
/// 相册图标）、拖动条偏左且没有换行提示、提交旁 effort、底部真实指标。
///
/// 页面用内存数据库 + 脚本化模型，不碰网络；拖拽的读盘/解码/落盘分别换成假实现
/// （真实现分别在 drop_intake_reader_test / ai_attachment_store_test 里覆盖），
/// 这里验的是页面接线。
void main() {
  late AppDatabase db;
  late AiRepository repository;
  late Directory tempDir;
  late ModelAdapter adapter;
  late String stagedFilePath;

  /// 2×2 合法 PNG：让暂存缩略图的 Image.file 真的有一张可解码的图。
  final Uint8List tinyPng = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAEklEQVR4nGO8pKHBwMDAxAAGAA5sASaNUVj9AAAAAElFTkSuQmCC',
  );

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repository = AiRepository(db);
    tempDir = Directory.systemTemp.createTempSync('furnace_ai_chat_redesign');
    stagedFilePath = '${tempDir.path}${Platform.pathSeparator}staged.png';
    File(stagedFilePath).writeAsBytesSync(tinyPng);
    adapter = FakeModelAdapter([FakeModelAdapter.answer('好的')]);
    await repository.saveConfig(
      const AiConfig(enabled: true, apiKey: 'sk-test'),
      fallbackLanguage: 'zh',
    );
  });

  tearDown(() async {
    await db.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  Future<void> pumpPage(
    WidgetTester tester, {
    Size size = const Size(1400, 900),
    List<Override> overrides = const <Override>[],
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          modelAdapterProvider.overrideWithValue(adapter),
          ...overrides,
        ],
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const AiChatPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  AppLocalizations l10nOf(WidgetTester tester) =>
      AppLocalizations.of(tester.element(find.byType(AiChatPage)));

  String textOf(WidgetTester tester, Key key) =>
      tester.widget<Text>(find.byKey(key)).data!;

  DropDoneDetails doneDetails(List<DropItem> files) => DropDoneDetails(
        files: files,
        localPosition: Offset.zero,
        globalPosition: Offset.zero,
      );

  DropEventDetails eventDetails() =>
      DropEventDetails(localPosition: Offset.zero, globalPosition: Offset.zero);

  group('layout', () {
    testWidgets('没有顶栏，新对话在右上角', (tester) async {
      await repository.createConversation();
      await pumpPage(tester);

      expect(find.byType(AppBar), findsNothing,
          reason: '用户 2026-11-15 第 1 点：AI 页不要顶栏');

      final newChat = find.byKey(AiChatPage.newConversationKey);
      expect(newChat, findsOneWidget);
      final center = tester.getCenter(newChat);
      expect(center.dx, greaterThan(900),
          reason: '用户第 3 点：新对话在右上角，不是左上');
      expect(center.dy, lessThan(80), reason: '它贴着页顶，不是浮在对话里');
    });

    testWidgets('折叠按钮在左栏边缘，图标随状态切换', (tester) async {
      await repository.createConversation(title: '第一个对话');
      await pumpPage(tester);

      final toggle = find.byKey(AiChatPage.sidebarToggleKey);
      expect(toggle, findsOneWidget);
      // 左栏宽 240，按钮宽 22：中心应该在 251 附近，而不是页面中间。
      final openCenter = tester.getCenter(toggle);
      expect(openCenter.dx, greaterThan(220));
      expect(openCenter.dx, lessThan(300));
      expect(find.byIcon(Icons.chevron_left), findsOneWidget,
          reason: '展开时显示 `<`（收起）');
      expect(find.byKey(AiChatPage.sidebarKey), findsOneWidget);

      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(find.byKey(AiChatPage.sidebarKey), findsNothing);
      expect(find.byIcon(Icons.chevron_right), findsOneWidget,
          reason: '收起后显示 `>`（展开）');
      final closedCenter =
          tester.getCenter(find.byKey(AiChatPage.sidebarToggleKey));
      expect(closedCenter.dx, lessThan(60), reason: '收起后按钮贴在窗口左缘');

      await tester.tap(find.byKey(AiChatPage.sidebarToggleKey));
      await tester.pumpAndSettle();
      expect(find.byKey(AiChatPage.sidebarKey), findsOneWidget);
    });

    testWidgets('拖动条偏左，换行提示与相册图标都不再出现', (tester) async {
      await repository.createConversation();
      await pumpPage(tester);
      final l10n = l10nOf(tester);

      final handle =
          tester.getCenter(find.byKey(AiChatPage.inputResizeHandleKey));
      expect(handle.dx, lessThan(420), reason: '用户第 8 点：上下拖动条中心偏左');
      expect(find.text(l10n.aiInputKeyHint), findsNothing,
          reason: '用户第 8 点：换行提示不要出现');
      expect(find.byIcon(Icons.add_photo_alternate_outlined), findsNothing,
          reason: '用户第 7 点：去掉相册图标');
    });
  });

  group('左栏', () {
    testWidgets('条目没有对话 icon，每条都有删除按钮', (tester) async {
      final a = await repository.createConversation(title: '对话 A');
      final b = await repository.createConversation(title: '对话 B');
      await pumpPage(tester);

      expect(find.byIcon(Icons.chat_bubble_outline), findsNothing,
          reason: '用户第 6 点：左栏不需要对话型 icon');
      expect(find.byKey(AiChatPage.conversationDeleteKey(a.id)),
          findsOneWidget);
      expect(find.byKey(AiChatPage.conversationDeleteKey(b.id)),
          findsOneWidget);
    });

    testWidgets('删除非当前对话不会切走当前对话', (tester) async {
      final a = await repository.createConversation(title: '对话 A');
      await repository.addMessage(
        conversationId: a.id,
        role: AiRepository.roleUser,
        content: '消息A',
      );
      final b = await repository.createConversation(title: '对话 B');
      await repository.addMessage(
        conversationId: b.id,
        role: AiRepository.roleUser,
        content: '消息B',
      );
      await pumpPage(tester);

      final showingA = find.text('消息A').evaluate().isNotEmpty;
      final showingB = find.text('消息B').evaluate().isNotEmpty;
      expect(showingA || showingB, isTrue, reason: '页面必须已绑定一条对话');
      final deleteId = showingA ? b.id : a.id;
      final visibleText = showingA ? '消息A' : '消息B';

      await tester.tap(find.byKey(AiChatPage.conversationDeleteKey(deleteId)));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10nOf(tester).commonDelete));
      await tester.pumpAndSettle();

      expect(find.text(visibleText), findsOneWidget,
          reason: '删的是另一条，当前对话不该被切走');
      expect(await repository.listConversations(), hasLength(1));
    });

    testWidgets('删除当前对话后回到空状态，列表也空了', (tester) async {
      final conversation = await repository.createConversation();
      await repository.addMessage(
        conversationId: conversation.id,
        role: AiRepository.roleUser,
        content: '唯一消息',
      );
      await pumpPage(tester);
      expect(find.text('唯一消息'), findsOneWidget);

      await tester
          .tap(find.byKey(AiChatPage.conversationDeleteKey(conversation.id)));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10nOf(tester).commonDelete));
      await tester.pumpAndSettle();

      expect(await repository.listConversations(), isEmpty);
      expect(find.text('唯一消息'), findsNothing);
      expect(find.text(l10nOf(tester).aiEmptyHint), findsWidgets);
    });
  });

  group('自动标题', () {
    testWidgets('第一条消息决定左栏标题', (tester) async {
      final conversation = await repository.createConversation();
      await pumpPage(tester);

      await tester.enterText(find.byType(TextField), '帮我建一个任务：界面链路测试');
      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();

      final reloaded = await repository.getConversation(conversation.id);
      expect(reloaded!.title, '帮我建一个任务：界面链路测试',
          reason: '用户第 5 点：标题自动取，不再停在「对话 MM-DD HH:mm」');
      // 左栏条目用的是这条标题；消息气泡里也有同样一段文字，所以要限定在左栏里找。
      expect(
        find.descendant(
          of: find.byKey(AiChatPage.sidebarKey),
          matching: find.text('帮我建一个任务：界面链路测试'),
        ),
        findsOneWidget,
        reason: '左栏应当显示新标题',
      );
    });
  });

  group('拖拽图片', () {
    List<Override> dropOverrides({DropIntakePlan? plan, Uint8List? bytes}) {
      final imagePlan = plan ??
          planDropIntake(<DropIntakeCandidate>[
            const DropIntakeCandidate(path: '/in/a.png', fileName: 'a.png'),
          ]);
      final batch = DropIntakeBatch(
        plan: imagePlan,
        bytes: <String, Uint8List>{
          for (final decision in imagePlan.images)
            decision.path: bytes ?? tinyPng,
        },
      );
      return <Override>[
        dropIntakeReaderProvider.overrideWithValue(_FakeDropReader(batch)),
        visionImageEncoderProvider.overrideWithValue(_FakeEncoder()),
        aiAttachmentStoreProvider.overrideWithValue(_FakeAttachmentStore(
          repository: repository,
          stagedPath: stagedFilePath,
        )),
      ];
    }

    testWidgets('拖进图片会暂存，悬停时出现提示', (tester) async {
      await repository.createConversation();
      await pumpPage(tester, overrides: dropOverrides());

      final target = find.byType(DropTarget);
      expect(target, findsOneWidget);
      tester.widget<DropTarget>(target).onDragEntered!(eventDetails());
      await tester.pump();
      expect(find.byKey(AiChatPage.dropHintKey), findsOneWidget);
      expect(find.text(l10nOf(tester).aiDropImageHint), findsOneWidget);

      tester.widget<DropTarget>(target).onDragExited!(eventDetails());
      await tester.pump();
      expect(find.byKey(AiChatPage.dropHintKey), findsNothing);

      tester
          .widget<DropTarget>(target)
          .onDragDone!(doneDetails(<DropItem>[DropItemFile('/in/a.png')]));
      await tester.pumpAndSettle();

      expect(find.byKey(AiChatPage.stagedImageKey(0)), findsOneWidget,
          reason: '用户第 7 点：拖拽上传走同一条 attachment 管线');
    });

    testWidgets('拖进非图片只提示跳过，不产生暂存图', (tester) async {
      await repository.createConversation();
      final plan = planDropIntake(<DropIntakeCandidate>[
        const DropIntakeCandidate(
            path: '/in/readme.txt', fileName: 'readme.txt'),
      ]);
      await pumpPage(tester, overrides: dropOverrides(plan: plan));

      tester.widget<DropTarget>(find.byType(DropTarget)).onDragDone!(
        doneDetails(<DropItem>[DropItemFile('/in/readme.txt')]),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(AiChatPage.stagedImageKey(0)), findsNothing);
      expect(find.text(l10nOf(tester).aiDropImageSkipped(1)), findsOneWidget);
    });
  });

  group('effort', () {
    testWidgets('提交按钮旁的选择会写进配置并立即生效', (tester) async {
      await repository.createConversation();
      await pumpPage(tester);
      final l10n = l10nOf(tester);
      expect((await repository.getConfig()).reasoningEffort, isNull);
      expect(find.text(l10n.aiEffortDefault), findsOneWidget);

      await tester.tap(find.byKey(AiChatPage.effortButtonKey));
      await tester.pumpAndSettle();
      await tester.tap(
          find.byKey(AiChatPage.effortOptionKey(ReasoningEffort.high)));
      await tester.pumpAndSettle();

      expect((await repository.getConfig()).reasoningEffort,
          ReasoningEffort.high,
          reason: '用户第 9 点：effort 是真实配置，不是装饰');
      expect(find.text(l10n.aiEffortHigh), findsOneWidget,
          reason: '选择器要把当前等级显示出来');
    });
  });

  group('底部指标', () {
    testWidgets('没有运行记录时全部是 —，不是 0', (tester) async {
      await repository.createConversation();
      await pumpPage(tester);

      expect(find.byKey(TurnMetricsBar.barKey), findsOneWidget);
      for (final key in const <Key>[
        TurnMetricsBar.roundsKey,
        TurnMetricsBar.stepsKey,
        TurnMetricsBar.totalTokensKey,
        TurnMetricsBar.cacheKey,
        TurnMetricsBar.contextKey,
      ]) {
        expect(textOf(tester, key), '—');
      }
    });

    testWidgets('一轮结束后显示真实的轮/步/token/缓存/上下文', (tester) async {
      adapter = _UsageAdapter();
      await repository.createConversation();
      await pumpPage(tester);

      await tester.enterText(find.byType(TextField), '算一下');
      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();

      expect(textOf(tester, TurnMetricsBar.roundsKey), '1/200');
      expect(textOf(tester, TurnMetricsBar.stepsKey), '0');
      expect(textOf(tester, TurnMetricsBar.totalTokensKey), '120',
          reason: '100 prompt + 20 completion，来自 adapter 报告的真实用量');
      expect(textOf(tester, TurnMetricsBar.cacheKey), '60.0%',
          reason: '60 命中 / 100 prompt');
      expect(textOf(tester, TurnMetricsBar.contextKey), '0.2%',
          reason: '最后一次 prompt 100 token / 65536 窗口');
    });

    testWidgets('重开页面时用已落库的运行记录显示轮数与 token', (tester) async {
      // 没有内存态（重开页面）时，轮数/token 来自 agent_runs 这条真实审计记录；
      // 缓存与上下文没有持久化列，所以仍然是 —，不编。
      final conversation = await repository.createConversation();
      final run = AgentRunState.start(
        id: 'run-recorded',
        conversationId: conversation.id,
        presetId: 'assistant',
        mode: AgentMode.chat,
        startedAt: 1,
      )
        ..steps = 2
        ..promptTokens = 300
        ..completionTokens = 100
        ..finish(AgentRunStatus.answered, nowMs: 2);
      await AgentRunStore(db).saveRun(run);

      await pumpPage(tester);

      expect(textOf(tester, TurnMetricsBar.roundsKey), '2',
          reason: 'agent_runs.steps 是已记录的模型回合数');
      expect(textOf(tester, TurnMetricsBar.totalTokensKey), '400',
          reason: '300 prompt + 100 completion');
      expect(textOf(tester, TurnMetricsBar.stepsKey), '—');
      expect(textOf(tester, TurnMetricsBar.cacheKey), '—');
      expect(textOf(tester, TurnMetricsBar.contextKey), '—');
    });
  });
}

/// 只报告用量的模型：让底部指标拿到真实的、adapter 报上来的数字。
class _UsageAdapter implements ModelAdapter {
  @override
  Stream<ModelEvent> runTurn({
    required List<ChatMessage> messages,
    required List<ModelToolSpec> tools,
  }) async* {
    yield const ModelTextDelta('答案');
    yield const ModelTurnDone(
      finishReason: 'stop',
      promptTokens: 100,
      completionTokens: 20,
      cacheHitPromptTokens: 60,
      cacheMissPromptTokens: 40,
    );
  }
}

class _FakeDropReader implements DropIntakeReader {
  _FakeDropReader(this.batch);

  final DropIntakeBatch batch;

  @override
  Future<DropIntakeBatch> examine(List<DropItem> items) async => batch;
}

class _FakeEncoder implements VisionImageEncoder {
  @override
  int get longSide => VisionImageEncoder.defaultLongSide;

  @override
  int get maxBytes => VisionImageEncoder.defaultMaxBytes;

  @override
  Future<VisionImageResult> encode(Uint8List raw) async =>
      VisionImageReady(bytes: raw, width: 2, height: 2);
}

class _FakeAttachmentStore extends AiAttachmentStore {
  _FakeAttachmentStore({
    required AiRepository repository,
    required this.stagedPath,
  }) : super(
          repository: repository,
          supportDirectory: () async => Directory.systemTemp,
        );

  /// 页面把暂存缩略图画出来的真实文件；字段名不能叫 `absolutePath`，那是
  /// [AiAttachmentStore] 自己的方法。
  final String stagedPath;

  @override
  Future<PendingImage> save(VisionImageReady image) async => PendingImage(
        relPath: 'ai_attachments/fake.png',
        absolutePath: stagedPath,
        mime: image.mime,
        width: image.width,
        height: image.height,
      );

  @override
  Future<void> deleteFiles(Iterable<String> relPaths) async {}
}
