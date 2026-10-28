import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/features/assessment/application/assessment_providers.dart';
import 'package:furnace/features/assessment/domain/assessment_cog_profile.dart';
import 'package:furnace/features/assessment/domain/assessment_models.dart';
import 'package:furnace/features/assessment/presentation/assessment_cog_profile_export.dart';
import 'package:furnace/features/assessment/presentation/assessment_profile_page.dart';
import 'package:furnace/l10n/app_localizations.dart';

void main() {
  late AppLocalizations zh;

  setUpAll(() async {
    zh = await AppLocalizations.delegate.load(const Locale('zh'));
  });

  AbilityEstimate ability(String abilityId) => AbilityEstimate(
        abilityId: abilityId,
        mean: 0.2,
        uncertainty: 0.5,
        nMeasurements: 2,
        source: EstimateSources.assessment,
      );

  ParamEstimate param(String paramId) => ParamEstimate(
        paramId: paramId,
        value: 0.5,
        uncertainty: 0.6,
        source: EstimateSources.derived,
      );

  /// 十项能力 + 九项参数都齐的画像，用来核对导出 JSON 的长度。
  AssessmentProfileSnapshot featuredSnapshot() => AssessmentProfileSnapshot(
        abilities: [for (final id in AbilityIds.all) ability(id)],
        params: [for (final id in CognitiveParamIds.all) param(id)],
        sessions: const <AssessmentSessionSummary>[],
      );

  Future<void> settle(WidgetTester tester, {int rounds = 40}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  Future<void> pumpProfile(
    WidgetTester tester, {
    required Future<AssessmentProfileSnapshot> Function() load,
    required _RecordingCogProfileSaver saver,
  }) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          assessmentProfileProvider.overrideWith((ref) => load()),
          assessmentStoreProvider.overrideWithValue(_FakeAssessmentStore()),
          cogProfileFileSaverProvider.overrideWithValue(saver.call),
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

  testWidgets('导出按钮生成 .cogprofile 字节并提示文件名', (tester) async {
    final saver = _RecordingCogProfileSaver();
    await pumpProfile(
      tester,
      load: () async => featuredSnapshot(),
      saver: saver,
    );

    await tester.tap(find.byKey(assessmentProfileExportKey));
    await settle(tester);
    await tester.pump(const Duration(milliseconds: 300));

    expect(saver.calls, 1);
    expect(saver.fileName, isNotNull);
    expect(
      saver.fileName!,
      matches(RegExp(r'^furnace-cogprofile-\d{8}-\d{4}\.cogprofile$')),
    );

    final decoded =
        jsonDecode(utf8.decode(saver.bytes!)) as Map<String, Object?>;
    expect(decoded['format_version'], kCogProfileFormatVersion);
    expect(decoded['abilities']! as List<Object?>, hasLength(10));
    expect(decoded['cognitive_params']! as List<Object?>, hasLength(9));
    expect(decoded['exported_at'], isA<String>());

    expect(
      find.text(zh.assessmentProfileExportSuccess(saver.fileName!)),
      findsOneWidget,
    );
  });

  testWidgets('用户取消保存时不给提示', (tester) async {
    final saver = _RecordingCogProfileSaver()..result = null;
    await pumpProfile(
      tester,
      load: () async => featuredSnapshot(),
      saver: saver,
    );

    await tester.tap(find.byKey(assessmentProfileExportKey));
    await settle(tester);
    await tester.pump(const Duration(milliseconds: 300));

    expect(saver.calls, 1);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('保存失败时提示错误原文', (tester) async {
    final saver = _RecordingCogProfileSaver()..error = Exception('磁盘满了');
    await pumpProfile(
      tester,
      load: () async => featuredSnapshot(),
      saver: saver,
    );

    await tester.tap(find.byKey(assessmentProfileExportKey));
    await settle(tester);
    await tester.pump(const Duration(milliseconds: 300));

    expect(saver.calls, 1);
    expect(
      find.text(zh.assessmentProfileExportFailed('Exception: 磁盘满了')),
      findsOneWidget,
    );
  });

  testWidgets('档案加载中导出按钮禁用', (tester) async {
    final saver = _RecordingCogProfileSaver();
    final pending = Completer<AssessmentProfileSnapshot>();
    await pumpProfile(tester, load: () => pending.future, saver: saver);

    final button = tester.widget<IconButton>(
      find.byKey(assessmentProfileExportKey),
    );
    expect(button.onPressed, isNull);
    expect(saver.calls, 0);
  });

  testWidgets('档案加载失败时导出按钮禁用并显示错误', (tester) async {
    final saver = _RecordingCogProfileSaver();
    await pumpProfile(
      tester,
      load: () async => throw Exception('boom'),
      saver: saver,
    );

    expect(
      find.text(zh.assessmentProfileLoadFailed('Exception: boom')),
      findsOneWidget,
    );
    final button = tester.widget<IconButton>(
      find.byKey(assessmentProfileExportKey),
    );
    expect(button.onPressed, isNull);
    expect(saver.calls, 0);
  });

  test('文件名按本地时间补零', () {
    expect(
      cogProfileFileName(DateTime(2026, 1, 2, 3, 4)),
      'furnace-cogprofile-20260102-0304.cogprofile',
    );
    expect(
      cogProfileFileName(DateTime(2026, 12, 31, 23, 59)),
      'furnace-cogprofile-20261231-2359.cogprofile',
    );
    expect(
      cogProfileFileName(DateTime(2026, 6, 7, 8, 9)),
      matches(RegExp(r'^furnace-cogprofile-\d{8}-\d{4}\.cogprofile$')),
    );
  });

  test('导出字节是可解码的 JSON，空画像也合法', () async {
    final bytes = await buildCogProfileBytes(
      abilities: const <AbilityEstimate>[],
      cognitiveParams: const <ParamEstimate>[],
      exportedAt: DateTime.utc(2026, 10, 29, 1),
    );
    final decoded = jsonDecode(utf8.decode(bytes)) as Map<String, Object?>;

    expect(decoded['format_version'], kCogProfileFormatVersion);
    expect(decoded['exported_at'], '2026-10-29T01:00:00.000Z');
    expect(decoded['abilities'], isEmpty);
    expect(decoded['cognitive_params'], isEmpty);
    expect(decoded['privacy']! as String, isNotEmpty);
  });
}

/// 记录保存参数的替身：[result] 为 null 模拟用户取消，[error] 非空模拟写盘失败。
class _RecordingCogProfileSaver {
  int calls = 0;
  String? fileName;
  List<int>? bytes;
  Uri? result = Uri.file('C:/tmp/furnace-cogprofile-test.cogprofile');
  Object? error;

  Future<Uri?> call({
    required String fileName,
    required List<int> bytes,
  }) async {
    calls++;
    this.fileName = fileName;
    this.bytes = bytes;
    if (error != null) throw error!;
    return result;
  }
}

class _FakeAssessmentStore implements AssessmentStore {
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
  }) async {}

  @override
  Future<void> setParamUserOverride({
    required String paramId,
    required double value,
  }) async {}

  @override
  Future<void> clearAbilityUserOverride({required String abilityId}) async {}

  @override
  Future<void> clearParamUserOverride({required String paramId}) async {}
}
