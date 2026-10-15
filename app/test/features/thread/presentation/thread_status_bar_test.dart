import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/anki_repository.dart';
import 'package:furnace/data/repositories/settings_repository.dart';
import 'package:furnace/features/thread/presentation/widgets/thread_status_bar.dart';
import 'package:furnace/l10n/app_localizations.dart';

/// Q25：读数要真的出现在线程页顶部，而不是只活在 `StudyRhythm` 的单元测试里
/// （`docs/MINDNET_ROADMAP.md` §3 第 4 行的验收口径）。
///
/// 这里钉四件事：日志里有坐段就报数、没有坐段就说"还没有足够记录"（不编数）、
/// 隐藏按钮把开关落库并且读数立刻消失、折叠后读数让位（折叠态只有一行）。
void main() {
  late AppDatabase db;
  late AnkiRepository anki;
  late SettingsRepository settings;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    anki = AnkiRepository(db);
    settings = SettingsRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  /// 写一条真实的复习日志（`review_logs.card_template_id` 有外键，所以先建模板）。
  Future<void> logReview(DateTime when) async {
    final point = await anki.createKnowledgePoint(
      title: '光合作用',
      content: '场所是叶绿体',
    );
    final template = await anki.createTemplate(
      knowledgePointId: point.id,
      type: 'fill_blank',
      question: '光合作用的场所是？',
      answer: '叶绿体',
    );
    final state = await anki.getOrCreateCardState(template.id);
    await anki.addReviewLog(
      cardStateId: state.id,
      cardTemplateId: template.id,
      rating: 3,
      reviewedAt: when.millisecondsSinceEpoch,
    );
  }

  Future<AppLocalizations> pumpBar(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: ThreadStatusBar(onOpenProperties: () {})),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return AppLocalizations.of(tester.element(find.byType(ThreadStatusBar)));
  }

  testWidgets('日志里有坐段 ⇒ 顶部给出可用性读数与建议', (tester) async {
    await settings.ensureSettings();
    await logReview(DateTime.now().subtract(const Duration(minutes: 6)));

    final l10n = await pumpBar(tester);

    // 6 分钟前坐下：vig = exp(-6/20) ≈ 74%，落在"做难"档。
    expect(find.textContaining(l10n.threadRhythmAdviceHard), findsOneWidget);
    expect(find.byTooltip(l10n.threadRhythmHide), findsOneWidget);
  });

  testWidgets('没有坐段 ⇒ 明说还没有足够记录，不编一个可用性', (tester) async {
    await settings.ensureSettings();

    final l10n = await pumpBar(tester);

    expect(find.text(l10n.threadRhythmEmpty), findsOneWidget);
    expect(find.byTooltip(l10n.threadRhythmHide), findsNothing);
  });

  testWidgets('点隐藏 ⇒ 开关落库且读数立刻消失（下次进页面也不显示）', (tester) async {
    await settings.ensureSettings();
    await logReview(DateTime.now().subtract(const Duration(minutes: 6)));

    final l10n = await pumpBar(tester);
    expect(find.textContaining(l10n.threadRhythmAdviceHard), findsOneWidget);

    await tester.tap(find.byTooltip(l10n.threadRhythmHide));
    await tester.pumpAndSettle();

    final stored = await settings.getSettings();
    expect(stored!.rhythmHintsEnabled, isFalse);
    expect(find.textContaining(l10n.threadRhythmAdviceHard), findsNothing);
    // 连"没有读数"那句也不显示：开关关掉是整个提示消失，不是换成空态。
    expect(find.text(l10n.threadRhythmEmpty), findsNothing);

    await pumpBar(tester);
    expect(find.textContaining(l10n.threadRhythmAdviceHard), findsNothing);
  });

  testWidgets('折叠状态条 ⇒ 读数让位（折叠态只有一行）', (tester) async {
    await settings.ensureSettings();
    await logReview(DateTime.now().subtract(const Duration(minutes: 6)));

    final l10n = await pumpBar(tester);
    expect(find.textContaining(l10n.threadRhythmAdviceHard), findsOneWidget);

    await tester.tap(find.byTooltip(l10n.threadCollapse));
    await tester.pumpAndSettle();

    expect(find.textContaining(l10n.threadRhythmAdviceHard), findsNothing);
  });
}
