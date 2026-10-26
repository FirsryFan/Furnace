import 'dart:math';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/ability_score_repository.dart';
import 'package:furnace/data/repositories/repository_providers.dart';
import 'package:furnace/domain/services/cognitive/ability_assessment.dart';
import 'package:furnace/features/cognitive/presentation/ability_assessment_page.dart';
import 'package:furnace/l10n/app_localizations.dart';

/// 能力测评页的端到端测试：真内存库 + 种子随机源。
///
/// 钉四类事：
///  1. 流程：介绍 → 逐项说明 → 小测 → 单项得分 → 汇总 → 保存；
///  2. 各项小测的读数路径真的走完（5 / 5 / 10 / 30 次），且分数交给领域层
///     换算——页面只显示 `AbilityScore` 算出来的整数分；
///  3. 保存是四项各写一行、失败只提示不退出、返回即放弃不写库；
///  4. 计时器在单项结算与离页时被取消（否则 testWidgets 会因 pending timer 挂）。
///
/// 不断言反应速度 / 模式识别的具体分数：Stopwatch 走真实时间，测试只要求
/// 落在 0–100；工作记忆（全对 / 全错）与注意稳定性（20 命中 + 10 错报）的
/// 分数在领域层是确定的，所以精确断言 83 / 0 / 50（工作记忆最长跨度 8 → 83 分）。
const Key launchKey = Key('ability-launch');

/// 先渲染一个能 pop 回去的宿主页，再 push 测评页：保存成功会 Navigator.pop，
/// 直接拿测评页当 home 会弹出唯一路由，测起来不真实。
class _LaunchHarness extends StatelessWidget {
  const _LaunchHarness({required this.random});

  final Random random;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Builder(
          builder: (context) => FilledButton(
            key: launchKey,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => AbilityAssessmentPage(random: random),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
  }
}

/// 只用来钉「保存失败不退出」：写库必抛。
class _ThrowingAbilityScoreRepository extends AbilityScoreRepository {
  _ThrowingAbilityScoreRepository(super._db);

  @override
  Future<String> record({
    required AbilityKey key,
    required double score,
    Map<String, Object?> metrics = const <String, Object?>{},
    DateTime? now,
  }) async {
    throw StateError('磁盘已满');
  }
}

/// 把正确数字串的末位改掉，保证「必然答错」。
String _wrongAnswer(String digits) {
  final last = digits.codeUnitAt(digits.length - 1);
  final replacement = last == 0x39 ? '0' : String.fromCharCode(last + 1);
  return digits.substring(0, digits.length - 1) + replacement;
}

void main() {
  late AppDatabase db;
  late AbilityScoreRepository repository;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repository = AbilityScoreRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<AppLocalizations> pumpPage(
    WidgetTester tester, {
    List<Override> overrides = const <Override>[],
    int seed = 7,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          appDatabaseProvider.overrideWithValue(db),
          ...overrides,
        ],
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: _LaunchHarness(random: Random(seed)),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(launchKey));
    await tester.pumpAndSettle();
    return AppLocalizations.of(
      tester.element(find.byType(AbilityAssessmentPage)),
    );
  }

  int readScore(WidgetTester tester, AbilityKey key) {
    final text =
        tester.widget<Text>(find.byKey(abilityItemScoreKey(key))).data!;
    return int.parse(text.replaceAll(RegExp(r'[^0-9]'), ''));
  }

  Future<void> startAssessment(WidgetTester tester) async {
    await tester.tap(find.byKey(abilityStartKey));
    await tester.pump();
  }

  Future<void> startItem(WidgetTester tester) async {
    await tester.tap(find.byKey(abilityStartItemKey));
    await tester.pump();
  }

  Future<void> nextItem(WidgetTester tester) async {
    await tester.tap(find.byKey(abilityNextKey));
    await tester.pump();
  }

  /// 反应速度：每轮把等待时间推过上限（2s），再点出现的目标。
  Future<void> playReaction(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 2100));
      await tester.tap(find.byKey(abilityReactionTargetKey));
      await tester.pump();
    }
  }

  /// 工作记忆：读出屏幕上的数字串，等它隐藏后填答案；
  /// [correct] 为 false 时必然答错，五项跨度都走完。
  Future<void> playWorkingMemory(
    WidgetTester tester, {
    required bool correct,
  }) async {
    for (var i = 0; i < 5; i++) {
      await tester.pump();
      final digits =
          tester.widget<Text>(find.byKey(abilityMemoryDigitsKey)).data!;
      await tester.pump(const Duration(milliseconds: 1300));
      await tester.enterText(
        find.byKey(abilityMemoryInputKey),
        correct ? digits : _wrongAnswer(digits),
      );
      await tester.tap(find.byKey(abilityMemorySubmitKey));
      await tester.pump();
    }
  }

  /// 模式识别：A 展示 900ms，推 1s 后 B 出现，交替点相同 / 不同。
  Future<void> playPattern(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 1000));
      await tester.tap(
        find.byKey(
            i.isEven ? abilityPatternSameKey : abilityPatternDifferentKey),
      );
      await tester.pump();
    }
  }

  /// 注意稳定性：字母（目标）点「是」，数字（非目标）点「否」——后者算错报。
  Future<void> playAttention(WidgetTester tester) async {
    final targetPattern = RegExp(r'^[A-Z]$');
    for (var i = 0; i < 30; i++) {
      await tester.pump();
      final text =
          tester.widget<Text>(find.byKey(abilityAttentionStimulusKey)).data!;
      await tester.tap(
        find.byKey(
          targetPattern.hasMatch(text)
              ? abilityAttentionYesKey
              : abilityAttentionNoKey,
        ),
      );
      await tester.pump();
    }
  }

  Future<void> reachWorkingMemoryItem(WidgetTester tester) async {
    await startAssessment(tester);
    await startItem(tester);
    await playReaction(tester);
    await nextItem(tester);
  }

  Future<void> reachPatternItem(WidgetTester tester) async {
    await reachWorkingMemoryItem(tester);
    await startItem(tester);
    await playWorkingMemory(tester, correct: true);
    await nextItem(tester);
  }

  Future<void> reachAttentionItem(WidgetTester tester) async {
    await reachPatternItem(tester);
    await startItem(tester);
    await playPattern(tester);
    await nextItem(tester);
  }

  /// 四项全部走完，停在汇总页。
  Future<void> playAllItems(WidgetTester tester) async {
    await reachAttentionItem(tester);
    await startItem(tester);
    await playAttention(tester);
    await nextItem(tester);
  }

  testWidgets('介绍页展示标题、说明与开始按钮', (tester) async {
    final l10n = await pumpPage(tester);
    expect(find.text(l10n.abilityAssessmentTitle), findsOneWidget);
    expect(find.text(l10n.abilityAssessmentIntro), findsOneWidget);
    expect(find.byKey(abilityStartKey), findsOneWidget);
    expect(find.byKey(abilityStartItemKey), findsNothing);
  });

  testWidgets('点开始进入反应速度项的说明页', (tester) async {
    final l10n = await pumpPage(tester);
    await startAssessment(tester);
    expect(find.text(l10n.abilityReactionTitle), findsOneWidget);
    expect(find.text(l10n.abilityReactionHint), findsOneWidget);
    expect(find.byKey(abilityStartItemKey), findsOneWidget);
    expect(find.byKey(abilityStartKey), findsNothing);
  });

  testWidgets('反应速度 5 次点击后出现 0–100 的单项得分', (tester) async {
    await pumpPage(tester);
    await startAssessment(tester);
    await startItem(tester);
    expect(find.byKey(abilityReactionWaitKey), findsOneWidget);
    await playReaction(tester);
    expect(
      find.byKey(abilityItemScoreKey(AbilityKey.reactionSpeed)),
      findsOneWidget,
    );
    expect(
        readScore(tester, AbilityKey.reactionSpeed), inInclusiveRange(0, 100));
    expect(find.byKey(abilityRetryKey), findsOneWidget);
    expect(find.byKey(abilityNextKey), findsOneWidget);
  });

  testWidgets('工作记忆全对记 83 分并进入下一项', (tester) async {
    final l10n = await pumpPage(tester);
    await reachWorkingMemoryItem(tester);
    await startItem(tester);
    await playWorkingMemory(tester, correct: true);
    // 跨度序列 4–8 全对，最长跨度为 8：领域层跨度 3 以下 0 分、9 才 100 分，
    // 所以 8 → 83 分。这里钉的是「读数算对了、页面照抄领域层的分」。
    expect(readScore(tester, AbilityKey.workingMemory), 83);
    expect(find.text(l10n.abilityScoreLabel(83)), findsOneWidget);
    await nextItem(tester);
    expect(find.text(l10n.abilityPatternTitle), findsOneWidget);
    expect(find.byKey(abilityStartItemKey), findsOneWidget);
  });

  testWidgets('工作记忆全错记 0 分', (tester) async {
    final l10n = await pumpPage(tester);
    await reachWorkingMemoryItem(tester);
    await startItem(tester);
    await playWorkingMemory(tester, correct: false);
    expect(readScore(tester, AbilityKey.workingMemory), 0);
    expect(find.text(l10n.abilityScoreLabel(0)), findsOneWidget);
  });

  testWidgets('模式识别 10 试次后出现 0–100 的单项得分', (tester) async {
    await pumpPage(tester);
    await reachPatternItem(tester);
    await startItem(tester);
    await playPattern(tester);
    expect(
      find.byKey(abilityItemScoreKey(AbilityKey.patternRecognition)),
      findsOneWidget,
    );
    expect(
      readScore(tester, AbilityKey.patternRecognition),
      inInclusiveRange(0, 100),
    );
  });

  testWidgets('注意稳定性 20 命中 + 10 错报记 50 分', (tester) async {
    await pumpPage(tester);
    await reachAttentionItem(tester);
    await startItem(tester);
    await playAttention(tester);
    expect(readScore(tester, AbilityKey.attentionStability), 50);
  });

  testWidgets('四项完成后汇总四行，保存写 4 行并退出页面', (tester) async {
    final l10n = await pumpPage(tester);
    await playAllItems(tester);
    expect(find.text(l10n.abilitySummaryTitle), findsOneWidget);
    for (final key in AbilityKey.values) {
      expect(find.byKey(abilitySummaryRowKey(key)), findsOneWidget);
    }
    expect(await repository.countAll(), 0);

    await tester.tap(find.byKey(abilityFinishKey));
    await tester.pumpAndSettle();

    expect(find.text(l10n.abilityScoresSaved), findsOneWidget);
    expect(await repository.countAll(), 4);
    for (final key in AbilityKey.values) {
      expect(await repository.countFor(key), 1);
    }
    final latest = await repository.latestByAbility();
    expect(latest.keys.toSet(), AbilityKey.values.toSet());
    for (final entry in latest.values) {
      expect(entry.score, inInclusiveRange(0, 100));
      expect(entry.metrics, isNotEmpty);
    }
    expect(find.byType(AbilityAssessmentPage), findsNothing);
  });

  testWidgets('保存失败只提示、留在汇总页且不写库', (tester) async {
    await pumpPage(
      tester,
      overrides: <Override>[
        abilityScoreRepositoryProvider.overrideWithValue(
          _ThrowingAbilityScoreRepository(db),
        ),
      ],
    );
    await playAllItems(tester);
    await tester.tap(find.byKey(abilityFinishKey));
    await tester.pumpAndSettle();

    expect(find.textContaining('保存失败'), findsOneWidget);
    expect(find.byKey(abilityFinishKey), findsOneWidget);
    expect(find.textContaining('保存失败：'), findsOneWidget);
    expect(await repository.countAll(), 0);
  });

  testWidgets('单项得分页可以重测当前项', (tester) async {
    await pumpPage(tester);
    await startAssessment(tester);
    await startItem(tester);
    await playReaction(tester);
    expect(
      find.byKey(abilityItemScoreKey(AbilityKey.reactionSpeed)),
      findsOneWidget,
    );

    await tester.tap(find.byKey(abilityRetryKey));
    await tester.pump();
    expect(
      find.byKey(abilityItemScoreKey(AbilityKey.reactionSpeed)),
      findsNothing,
    );
    expect(find.byKey(abilityReactionWaitKey), findsOneWidget);

    await playReaction(tester);
    expect(
      find.byKey(abilityItemScoreKey(AbilityKey.reactionSpeed)),
      findsOneWidget,
    );
  });

  testWidgets('返回即放弃，不写库', (tester) async {
    await pumpPage(tester);
    await startAssessment(tester);
    await startItem(tester);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(AbilityAssessmentPage), findsNothing);
    expect(await repository.countAll(), 0);
  });
}
