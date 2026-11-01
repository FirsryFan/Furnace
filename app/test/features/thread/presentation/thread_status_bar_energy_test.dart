import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/anki_repository.dart';
import 'package:furnace/data/repositories/settings_repository.dart';
import 'package:furnace/data/repositories/thread_state_repository.dart';
import 'package:furnace/features/thread/application/energy_prediction_provider.dart';
import 'package:furnace/features/thread/presentation/widgets/energy_bar.dart';
import 'package:furnace/features/thread/presentation/widgets/thread_status_bar.dart';
import 'package:furnace/l10n/app_localizations.dart';

/// D13：预测值要真的出现在 Thread 顶栏，并且"用预测值"与手动编辑都是落库操作。
///
/// 钉四件事：有历史就有预测行（含来源提示）、没有数据时不提供"用预测值"、
/// 点"用预测值"写的就是预测的档位、手动编辑后换"手动"徽标；折叠态预测行让位。
void main() {
  late AppDatabase db;
  late AnkiRepository anki;
  late SettingsRepository settings;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    anki = AnkiRepository(db);
    settings = SettingsRepository(db);
    // 顶栏还挂着注意力读数；先建好设置行，免得多余的异步错误。
    await settings.ensureSettings();
  });

  tearDown(() async {
    await db.close();
  });

  /// 写一条真实复习日志（`review_logs.card_template_id` 有外键，所以先建模板）。
  /// 一条**已知结果**的复习 = 1 条可用证据，置信度 > 0 ⇒ 出现"用预测值"。
  /// 注意 v1 `rating` 只有 0/1/2 会被预测器识别成结果（2 = remembered），
  /// 其它值按 unknown 处理、不贡献置信度。
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
      rating: 2,
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

  testWidgets('有历史记录 ⇒ 出现预测行（置信与来源提示），未手填时无徽标', (tester) async {
    await logReview(DateTime.now().subtract(const Duration(minutes: 6)));

    final l10n = await pumpBar(tester);

    expect(find.byKey(const Key('threadEnergyPredictionRow')), findsOneWidget);
    // 中文文案：预测精力 {level}（置信 {confidence}%）。
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Text &&
            RegExp(r'^预测精力 \d+（置信 \d+%）$').hasMatch(widget.data ?? ''),
      ),
      findsOneWidget,
    );
    // "来源"在提示里：预测说明 + 预测器自己的依据行。
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Tooltip &&
            (widget.message ?? '').contains(l10n.threadEnergyPredictedNote),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('threadEnergyManualBadge')), findsNothing);
    expect(find.byKey(const Key('threadEnergyUsePrediction')), findsOneWidget);
  });

  testWidgets('没有数据 ⇒ 预测行仍显示但置信 0%，不提供"用预测值"', (tester) async {
    final l10n = await pumpBar(tester);

    expect(find.byKey(const Key('threadEnergyPredictionRow')), findsOneWidget);
    expect(find.text(l10n.threadEnergyPredicted(5, '0%')), findsOneWidget);
    expect(find.byKey(const Key('threadEnergyUsePrediction')), findsNothing);
    expect(find.byKey(const Key('threadEnergyManualBadge')), findsNothing);
  });

  testWidgets('点"用预测值" ⇒ 预测档位写进 thread_states.energy，并转为手动徽标', (tester) async {
    await logReview(DateTime.now().subtract(const Duration(minutes: 6)));
    final l10n = await pumpBar(tester);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ThreadStatusBar)),
      listen: false,
    );
    final before = await container.read(energyPredictionProvider.future);
    expect(find.byKey(const Key('threadEnergyUsePrediction')), findsOneWidget);

    await tester.tap(find.byKey(const Key('threadEnergyUsePrediction')));
    await tester.pumpAndSettle();

    final stored = await ThreadStateRepository(db).getState();
    expect(stored?.energy, before.prediction.level);

    final after = await container.read(energyPredictionProvider.future);
    expect(after.manualOverrideActive, isTrue);
    expect(find.byKey(const Key('threadEnergyManualBadge')), findsOneWidget);
    expect(find.byKey(const Key('threadEnergyUsePrediction')), findsNothing);
    expect(find.text(l10n.threadEnergyManualBadge), findsOneWidget);
  });

  testWidgets('手动编辑精力 ⇒ 落库并显示"手动"徽标，"用预测值"让位', (tester) async {
    await logReview(DateTime.now().subtract(const Duration(minutes: 6)));
    final l10n = await pumpBar(tester);

    await tester.tap(find.byType(EnergyBar));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(l10n.commonConfirm));
    await tester.pumpAndSettle();

    final stored = await ThreadStateRepository(db).getState();
    expect(stored?.energy, isNotNull);
    expect(find.byKey(const Key('threadEnergyManualBadge')), findsOneWidget);
    expect(find.byKey(const Key('threadEnergyUsePrediction')), findsNothing);
  });

  testWidgets('折叠状态条 ⇒ 预测行让位（折叠态只有主行）', (tester) async {
    await logReview(DateTime.now().subtract(const Duration(minutes: 6)));
    final l10n = await pumpBar(tester);
    expect(find.byKey(const Key('threadEnergyPredictionRow')), findsOneWidget);

    await tester.tap(find.byTooltip(l10n.threadCollapse));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('threadEnergyPredictionRow')), findsNothing);
  });
}
