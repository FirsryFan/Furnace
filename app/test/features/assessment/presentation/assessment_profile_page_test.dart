import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/features/assessment/application/assessment_providers.dart';
import 'package:furnace/features/assessment/domain/assessment_models.dart';
import 'package:furnace/features/assessment/presentation/assessment_profile_page.dart';
import 'package:furnace/l10n/app_localizations.dart';

void main() {
  late AppLocalizations zh;

  setUpAll(() async {
    zh = await AppLocalizations.delegate.load(const Locale('zh'));
  });

  AbilityEstimate ability(
    String abilityId, {
    double mean = 0.0,
    int nMeasurements = 2,
    String source = EstimateSources.assessment,
    bool stale = false,
  }) =>
      AbilityEstimate(
        abilityId: abilityId,
        mean: mean,
        uncertainty: 0.5,
        nMeasurements: nMeasurements,
        source: source,
        stale: stale,
      );

  ParamEstimate param(
    String paramId, {
    double value = 0.5,
    String source = EstimateSources.derived,
  }) =>
      ParamEstimate(
        paramId: paramId,
        value: value,
        uncertainty: 0.6,
        source: source,
      );

  AssessmentSessionSummary session(
    String sessionId, {
    String taskId = 'go_nogo',
    String status = 'completed',
    DateTime? completedAt,
  }) =>
      AssessmentSessionSummary(
        sessionId: sessionId,
        taskId: taskId,
        designVersion: kAssessmentDesignVersion,
        device: AssessmentDevices.windowsMouse,
        startedAt: DateTime(2026, 10, 1, 9),
        completedAt: completedAt ?? DateTime(2026, 10, 1, 9, 5),
        status: status,
      );

  AssessmentProfileSnapshot snapshot({
    List<AbilityEstimate> abilities = const [],
    List<ParamEstimate> params = const [],
    List<AssessmentSessionSummary> sessions = const [],
  }) =>
      AssessmentProfileSnapshot(
        abilities: abilities,
        params: params,
        sessions: sessions,
      );

  Future<void> settle(WidgetTester tester, {int rounds = 40}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  Future<void> pumpProfile(
    WidgetTester tester, {
    required Future<AssessmentProfileSnapshot> Function() load,
    required _FakeAssessmentStore store,
  }) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          assessmentProfileProvider.overrideWith((ref) => load()),
          assessmentStoreProvider.overrideWithValue(store),
        ],
        child: const MaterialApp(
          locale: Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: AssessmentProfilePage(),
        ),
      ),
    );
    await settle(tester);
  }

  testWidgets('能力、参数与历史一起上屏，含不确定性、次数与来源', (tester) async {
    final store = _FakeAssessmentStore();
    await pumpProfile(
      tester,
      store: store,
      load: () async => snapshot(
        abilities: [
          ability(AbilityIds.processingSpeed, mean: 0.25, nMeasurements: 3),
          ability(AbilityIds.inhibitoryControl,
              mean: -0.5, source: EstimateSources.defaultPrior),
          ability(AbilityIds.distractionResistance,
              source: EstimateSources.userOverride, stale: true),
        ],
        params: [
          param(CognitiveParamIds.switchPenalty, value: 0.4),
          param(CognitiveParamIds.expectedPressure,
              value: 0.6, source: EstimateSources.userOverride),
        ],
        sessions: [
          session('s1'),
          session('s2', taskId: 'n_back_2', status: 'aborted'),
        ],
      ),
    );

    expect(find.text(zh.assessmentProfileTitle), findsOneWidget);
    expect(find.text(zh.assessmentProfileAbilitiesTitle), findsOneWidget);
    expect(find.text(zh.assessmentProfileParamsTitle), findsOneWidget);
    expect(find.text(zh.assessmentProfileHistoryTitle), findsOneWidget);

    expect(
      find.byKey(assessmentProfileAbilityRowKey(AbilityIds.processingSpeed)),
      findsOneWidget,
    );
    expect(find.text(zh.abilityProcessingSpeed), findsOneWidget);
    expect(find.text('0.25'), findsOneWidget);
    expect(
      find.text(zh.assessmentProfileUncertaintyRow('0.50')),
      findsWidgets,
    );
    expect(
      find.text(zh.assessmentProfileMeasurementsCount(3)),
      findsOneWidget,
    );
    expect(
      find.text(zh.assessmentProfileSourceAssessment),
      findsOneWidget,
    );
    expect(find.text(zh.assessmentProfileSourceDefault), findsOneWidget);
    expect(find.text(zh.assessmentProfileSourceOverride), findsWidgets);
    expect(find.text(zh.assessmentProfileStale), findsOneWidget);

    expect(
      find.byKey(assessmentProfileParamRowKey(CognitiveParamIds.switchPenalty)),
      findsOneWidget,
    );
    expect(find.text(zh.paramSwitchPenalty), findsOneWidget);

    expect(
      find.byKey(assessmentProfileHistoryRowKey('s1')),
      findsOneWidget,
    );
    expect(
      find.text(zh.assessmentProfileHistoryRow(
        zh.taskGoNogo,
        '2026-10-01 09:05',
        'completed',
      )),
      findsOneWidget,
    );
    expect(
      find.text(zh.assessmentProfileHistoryRow(
        zh.taskNBack2,
        '2026-10-01 09:05',
        'aborted',
      )),
      findsOneWidget,
    );
  });

  testWidgets('能力按固定能力顺序排列，未知 id 排最后', (tester) async {
    final store = _FakeAssessmentStore();
    await pumpProfile(
      tester,
      store: store,
      load: () async => snapshot(
        abilities: [
          ability('unknown_ability'),
          ability(AbilityIds.inhibitoryControl),
          ability(AbilityIds.processingSpeed),
        ],
      ),
    );

    final processing = tester.getTopLeft(
      find.byKey(assessmentProfileAbilityRowKey(AbilityIds.processingSpeed)),
    );
    final inhibitory = tester.getTopLeft(
      find.byKey(assessmentProfileAbilityRowKey(AbilityIds.inhibitoryControl)),
    );
    final unknown = tester.getTopLeft(
      find.byKey(assessmentProfileAbilityRowKey('unknown_ability')),
    );

    expect(processing.dy, lessThan(inhibitory.dy));
    expect(inhibitory.dy, lessThan(unknown.dy));
  });

  testWidgets('没有历史记录时显示空态，不渲染历史行', (tester) async {
    final store = _FakeAssessmentStore();
    await pumpProfile(
      tester,
      store: store,
      load: () async => snapshot(
        abilities: [ability(AbilityIds.processingSpeed)],
      ),
    );

    expect(
      find.byKey(assessmentProfileHistoryEmptyKey),
      findsOneWidget,
    );
    expect(
      find.text(zh.assessmentProfileHistoryEmpty),
      findsOneWidget,
    );
    expect(find.byKey(assessmentProfileHistoryKey), findsNothing);
  });

  testWidgets('手动覆盖能力：对话框校验通过后写库并刷新', (tester) async {
    final store = _FakeAssessmentStore();
    await pumpProfile(
      tester,
      store: store,
      load: () async => snapshot(
        abilities: [
          ability(
            AbilityIds.processingSpeed,
            mean: store.abilityOverrides[AbilityIds.processingSpeed] ?? 0.0,
          ),
        ],
      ),
    );

    await tester.tap(
      find.byKey(
        assessmentProfileAbilityOverrideKey(AbilityIds.processingSpeed),
      ),
    );
    await settle(tester);

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(
      find.text(zh.assessmentProfileOverrideTitle(zh.abilityProcessingSpeed)),
      findsOneWidget,
    );
    expect(find.text(zh.assessmentProfileOverrideHint), findsOneWidget);

    await tester.enterText(find.byType(TextField), '0.35');
    await tester.tap(find.text(zh.commonSave));
    await settle(tester);

    expect(
      store.abilityOverrides[AbilityIds.processingSpeed],
      closeTo(0.35, 1e-9),
    );
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('0.35'), findsOneWidget);
  });

  testWidgets('能力覆盖超出 z-score 范围时报错，不写库', (tester) async {
    final store = _FakeAssessmentStore();
    await pumpProfile(
      tester,
      store: store,
      load: () async => snapshot(
        abilities: [ability(AbilityIds.processingSpeed)],
      ),
    );

    await tester.tap(
      find.byKey(
        assessmentProfileAbilityOverrideKey(AbilityIds.processingSpeed),
      ),
    );
    await settle(tester);

    await tester.enterText(find.byType(TextField), '9');
    await tester.tap(find.text(zh.commonSave));
    await settle(tester);

    expect(
      find.text(zh.assessmentProfileOverrideInvalidZScore),
      findsOneWidget,
    );
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(store.abilityOverrides, isEmpty);
  });

  testWidgets('参数覆盖限制 0 到 1，通过后写库', (tester) async {
    final store = _FakeAssessmentStore();
    await pumpProfile(
      tester,
      store: store,
      load: () async => snapshot(
        params: [param(CognitiveParamIds.switchPenalty)],
      ),
    );

    await tester.tap(
      find.byKey(
        assessmentProfileParamOverrideKey(CognitiveParamIds.switchPenalty),
      ),
    );
    await settle(tester);

    await tester.enterText(find.byType(TextField), '2');
    await tester.tap(find.text(zh.commonSave));
    await settle(tester);

    expect(
      find.text(zh.assessmentProfileOverrideInvalid),
      findsOneWidget,
    );
    expect(store.paramOverrides, isEmpty);

    await tester.enterText(find.byType(TextField), '0.4');
    await tester.tap(find.text(zh.commonSave));
    await settle(tester);

    expect(
      store.paramOverrides[CognitiveParamIds.switchPenalty],
      closeTo(0.4, 1e-9),
    );
  });

  testWidgets('恢复自动更新按钮清掉手动覆盖', (tester) async {
    final store = _FakeAssessmentStore();
    await pumpProfile(
      tester,
      store: store,
      load: () async => snapshot(
        abilities: [
          ability(
            AbilityIds.processingSpeed,
            source: EstimateSources.userOverride,
          ),
        ],
      ),
    );

    expect(
      find.byKey(
        assessmentProfileAbilityClearKey(AbilityIds.processingSpeed),
      ),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(
        assessmentProfileAbilityClearKey(AbilityIds.processingSpeed),
      ),
    );
    await settle(tester);

    expect(
      store.clearedAbilities,
      contains(AbilityIds.processingSpeed),
    );
  });

  testWidgets('档案读取失败显示错误并可重试', (tester) async {
    final store = _FakeAssessmentStore();
    var calls = 0;
    await pumpProfile(
      tester,
      store: store,
      load: () async {
        calls++;
        if (calls == 1) throw Exception('boom');
        return snapshot(
          abilities: [ability(AbilityIds.processingSpeed)],
        );
      },
    );

    expect(
      find.text(zh.assessmentProfileLoadFailed('Exception: boom')),
      findsOneWidget,
    );
    expect(find.byKey(assessmentProfileRetryKey), findsOneWidget);

    await tester.tap(find.byKey(assessmentProfileRetryKey));
    await settle(tester);

    expect(find.text(zh.abilityProcessingSpeed), findsOneWidget);
    expect(find.byKey(assessmentProfileRetryKey), findsNothing);
  });

  testWidgets('覆盖写库失败时用 SnackBar 报错', (tester) async {
    final store = _FakeAssessmentStore()..failWrites = true;
    await pumpProfile(
      tester,
      store: store,
      load: () async => snapshot(
        abilities: [ability(AbilityIds.processingSpeed)],
      ),
    );

    await tester.tap(
      find.byKey(
        assessmentProfileAbilityOverrideKey(AbilityIds.processingSpeed),
      ),
    );
    await settle(tester);
    await tester.enterText(find.byType(TextField), '0.2');
    await tester.tap(find.text(zh.commonSave));
    await settle(tester);
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.text(zh.assessmentRunSaveFailed('Bad state: 写库失败')),
      findsOneWidget,
    );
  });
}

class _FakeAssessmentStore implements AssessmentStore {
  final Map<String, double> abilityOverrides = <String, double>{};
  final Map<String, double> paramOverrides = <String, double>{};
  final List<String> clearedAbilities = <String>[];
  final List<String> clearedParams = <String>[];
  bool failWrites = false;

  @override
  Future<void> ensureSeeded({DateTime? now}) async {}

  @override
  Future<List<AssessmentTaskConfig>> listTasks(
      {bool enabledOnly = true}) async {
    return const <AssessmentTaskConfig>[];
  }

  @override
  Future<String> recordSession({
    required String taskId,
    required String designVersion,
    required String device,
    required DateTime startedAt,
    required DateTime completedAt,
    required String status,
    required List<TrialResult> trials,
    required List<MetricSample> metrics,
    List<String> qualityFlags = const <String>[],
  }) async {
    return 'session-recorded';
  }

  @override
  Future<List<AbilityEstimate>> readAbilities() async {
    return const <AbilityEstimate>[];
  }

  @override
  Future<List<ParamEstimate>> readCognitiveParams() async {
    return const <ParamEstimate>[];
  }

  @override
  Future<void> writeEstimates({
    List<AbilityEstimate> abilities = const <AbilityEstimate>[],
    List<ParamEstimate> params = const <ParamEstimate>[],
  }) async {}

  @override
  Future<List<TaskAbilityMapping>> readTaskAbilityMappings({
    bool enabledOnly = true,
  }) async {
    return const <TaskAbilityMapping>[];
  }

  @override
  Future<List<AbilityParamMapping>> readAbilityParamMappings({
    bool enabledOnly = true,
  }) async {
    return const <AbilityParamMapping>[];
  }

  @override
  Future<List<AssessmentSessionSummary>> readSessions({int limit = 20}) async {
    return const <AssessmentSessionSummary>[];
  }

  @override
  Future<AssessmentSessionSummary?> readSession(String sessionId) async {
    return null;
  }

  @override
  Future<void> setAbilityUserOverride({
    required String abilityId,
    required double mean,
  }) async {
    if (failWrites) throw StateError('写库失败');
    abilityOverrides[abilityId] = mean;
  }

  @override
  Future<void> setParamUserOverride({
    required String paramId,
    required double value,
  }) async {
    if (failWrites) throw StateError('写库失败');
    paramOverrides[paramId] = value;
  }

  @override
  Future<void> clearAbilityUserOverride({required String abilityId}) async {
    if (failWrites) throw StateError('写库失败');
    clearedAbilities.add(abilityId);
  }

  @override
  Future<void> clearParamUserOverride({required String paramId}) async {
    if (failWrites) throw StateError('写库失败');
    clearedParams.add(paramId);
  }
}
