import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/repository_providers.dart';
import 'package:furnace/data/repositories/settings_repository.dart';
import 'package:furnace/domain/services/reasoning/capability_action.dart';
import 'package:furnace/domain/services/reasoning/capability_action_overlay.dart';
import 'package:furnace/domain/services/reasoning/capability_action_overlay_editor.dart';
import 'package:furnace/features/questions/application/capability_vocabulary_editor_provider.dart';
import 'package:furnace/features/questions/application/capability_vocabulary_store.dart';

/// 词表编辑的 application 层：载入 → 编辑 → dirty → 保存 / 放弃。
///
/// 这里只测接线与状态机，编辑规则本身（校验、失败不改数据）由
/// capability_action_overlay_editor_test.dart 钉住；两边重复的断言只挑
/// 「界面能看到的」那部分。
class _FailingSaveSettings extends SettingsRepository {
  _FailingSaveSettings(super.db);

  @override
  Future<void> updateCapabilityActionOverlayJson(String? json) async {
    throw StateError('磁盘满了（测试夹具）');
  }
}

void main() {
  late AppDatabase db;
  late SettingsRepository settings;
  late CapabilityVocabularyStore store;
  late ProviderContainer container;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    settings = SettingsRepository(db);
    store = CapabilityVocabularyStore(settings);
    container = ProviderContainer(
      overrides: <Override>[
        settingsRepositoryProvider.overrideWithValue(settings),
      ],
    );
    addTearDown(container.dispose);
  });

  tearDown(() async {
    await db.close();
  });

  CapabilityActionOverlay overlayWith(List<CustomCapabilityAction> actions) =>
      CapabilityActionOverlay(customActions: actions);

  CustomCapabilityAction action(
    String key,
    String labelZh, {
    String labelEn = '',
    String descriptionZh = '',
    List<String> subjectHints = const <String>['physics'],
  }) =>
      CustomCapabilityAction(
        key: key,
        labelZh: labelZh,
        labelEn: labelEn,
        descriptionZh: descriptionZh,
        subjectHints: subjectHints,
      );

  Future<CapabilityVocabularyEditorState> loadEditor() =>
      container.read(capabilityVocabularyEditorProvider.future);

  CapabilityVocabularyEditorState readEditor() {
    final async = container.read(capabilityVocabularyEditorProvider);
    final value = async.valueOrNull;
    expect(value, isNotNull, reason: '编辑控制器应已载入完成');
    return value!;
  }

  CapabilityVocabularyEditor controller() =>
      container.read(capabilityVocabularyEditorProvider.notifier);

  test('空库：载入出厂词表，不 dirty、没有自定义条目', () async {
    final state = await loadEditor();
    expect(state.overlay.isEmpty, isTrue);
    expect(state.overlay.catalog.actions,
        hasLength(CapabilityAction.catalog.length));
    expect(state.isDirty, isFalse);
    expect(state.customActionCount, 0);
    expect(state.issues, isEmpty);
    expect(state.isSaving, isFalse);
  });

  test('已有两条用户条目：载入后不 dirty', () async {
    await store.save(overlayWith(<CustomCapabilityAction>[
      action('force_diagram_analysis', '受力图分析'),
      action('balance_equations', '配平',
          subjectHints: const <String>['chemistry']),
    ]));
    final state = await loadEditor();
    expect(state.customActionCount, 2);
    expect(state.savedOverlay.customActions, hasLength(2));
    expect(state.isDirty, isFalse);
  });

  test('add：合法条目进 overlay，dirty，合并词表认得它', () async {
    await loadEditor();
    controller().add(action('force_diagram_analysis', '受力图分析'));
    final state = readEditor();
    expect(state.customActionCount, 1);
    expect(state.isDirty, isTrue);
    expect(state.issues, isEmpty);
    expect(state.overlay.catalog.isCustomKey('force_diagram_analysis'), isTrue);
    expect(state.overlay.catalog.byKey('force_diagram_analysis')!.labelZh,
        '受力图分析');
  });

  test('add：内置 key 被拒（keyReserved），overlay 不变、不 dirty', () async {
    final initial = await loadEditor();
    controller().add(action('first_principles', '从定义出发'));
    final state = readEditor();
    expect(state.issues.single.reason,
        CapabilityActionOverlayIssueReason.keyReserved);
    expect(state.overlay, same(initial.overlay));
    expect(state.isDirty, isFalse);
  });

  test('add：非法 key → keyNotSnakeCase；缺中文名 → missingLabelZh', () async {
    await loadEditor();
    controller().add(action('Bad Key', '不合法'));
    expect(readEditor().issues.single.reason,
        CapabilityActionOverlayIssueReason.keyNotSnakeCase);
    controller().add(action('force_diagram_analysis', '   '));
    expect(readEditor().issues.single.reason,
        CapabilityActionOverlayIssueReason.missingLabelZh);
    expect(readEditor().customActionCount, 0);
  });

  test('add：重复 key → duplicateKey，先到先得', () async {
    await loadEditor();
    controller().add(action('limit_process', '取极限'));
    controller().add(action('limit_process', '取极限（重复）'));
    final state = readEditor();
    expect(state.customActionCount, 1);
    expect(state.issues.single.reason,
        CapabilityActionOverlayIssueReason.duplicateKey);
    expect(state.overlay.customActions.single.labelZh, '取极限');
  });

  test('add：达到 100 条上限 → customActionLimitExceeded', () async {
    final many = <CustomCapabilityAction>[
      for (var index = 0;
          index < CapabilityActionOverlayEditor.maxCustomActions;
          index++)
        action('custom_move_$index', '自定义动作$index'),
    ];
    await store.save(overlayWith(many));
    await loadEditor();
    controller().add(action('one_more', '再来一条'));
    final state = readEditor();
    expect(state.customActionCount,
        CapabilityActionOverlayEditor.maxCustomActions);
    expect(state.issues.single.reason,
        CapabilityActionOverlayIssueReason.customActionLimitExceeded);
    expect(state.isDirty, isFalse);
  });

  test('update：只换 label，其它字段保持原值（null = 保留）', () async {
    await store.save(overlayWith(<CustomCapabilityAction>[
      action('limit_process', '取极限',
          labelEn: 'take limit', subjectHints: const <String>['math']),
    ]));
    await loadEditor();
    controller().updateAction('limit_process', labelZh: '求极限');
    var state = readEditor();
    expect(state.isDirty, isTrue);
    expect(state.overlay.customActions.single.labelZh, '求极限');
    expect(state.overlay.customActions.single.labelEn, 'take limit');
    expect(state.overlay.customActions.single.subjectHints, <String>['math']);
    controller().updateAction('limit_process', labelEn: '');
    state = readEditor();
    expect(state.overlay.customActions.single.labelEn, '');
  });

  test('update：空中文名被拒；不存在的 key → keyNotFound', () async {
    await store.save(
        overlayWith(<CustomCapabilityAction>[action('limit_process', '取极限')]));
    await loadEditor();
    controller().updateAction('limit_process', labelZh: '   ');
    expect(readEditor().issues.single.reason,
        CapabilityActionOverlayIssueReason.missingLabelZh);
    controller().updateAction('no_such_action', labelZh: '没有这条');
    expect(readEditor().issues.single.reason,
        CapabilityActionOverlayIssueReason.keyNotFound);
    expect(readEditor().overlay.customActions.single.labelZh, '取极限');
  });

  test('remove：删掉并 dirty；不存在 → keyNotFound', () async {
    await store.save(overlayWith(<CustomCapabilityAction>[
      action('limit_process', '取极限'),
      action('balance_equations', '配平'),
    ]));
    await loadEditor();
    controller().remove('limit_process');
    var state = readEditor();
    expect(state.customActionCount, 1);
    expect(state.overlay.customActions.single.key, 'balance_equations');
    expect(state.isDirty, isTrue);
    controller().remove('limit_process');
    state = readEditor();
    expect(state.issues.single.reason,
        CapabilityActionOverlayIssueReason.keyNotFound);
    expect(state.customActionCount, 1);
  });

  test('reorder：换顺序并 dirty；原位 changed=false；越界 indexOutOfRange', () async {
    await store.save(overlayWith(<CustomCapabilityAction>[
      action('aaa_first', '第一'),
      action('bbb_second', '第二'),
    ]));
    await loadEditor();
    controller().reorder('aaa_first', 1);
    var state = readEditor();
    expect(state.overlay.customActions.map((item) => item.key).toList(),
        <String>['bbb_second', 'aaa_first']);
    expect(state.isDirty, isTrue);
    // 移回原位：数据与保存时一致，dirty 回到 false。
    controller().reorder('aaa_first', 0);
    state = readEditor();
    expect(state.overlay.customActions.map((item) => item.key).toList(),
        <String>['aaa_first', 'bbb_second']);
    expect(state.isDirty, isFalse);
    // 移到当前所在位置是空操作：changed=false、没有 issue。
    controller().reorder('bbb_second', 1);
    state = readEditor();
    expect(state.issues, isEmpty);
    expect(state.overlay.customActions.map((item) => item.key).toList(),
        <String>['aaa_first', 'bbb_second']);
    controller().reorder('bbb_second', 9);
    expect(readEditor().issues.single.reason,
        CapabilityActionOverlayIssueReason.indexOutOfRange);
  });

  test('importJson：合法条目追加、重复跳过并留 issue', () async {
    await store.save(
        overlayWith(<CustomCapabilityAction>[action('limit_process', '取极限')]));
    await loadEditor();
    controller().importJson(<String, Object?>{
      'version': 1,
      'customActions': <Object?>[
        <String, Object?>{'key': 'limit_process', 'labelZh': '取极限（导入）'},
        <String, Object?>{
          'key': 'force_diagram_analysis',
          'labelZh': '受力图分析',
          'subjectHints': <Object?>['physics']
        },
        <String, Object?>{'key': 'Bad Key', 'labelZh': '不合法'},
      ],
    });
    final state = readEditor();
    expect(state.customActionCount, 2);
    expect(state.overlay.customActions.last.key, 'force_diagram_analysis');
    expect(state.issues, hasLength(2));
    expect(
        state.issues.map((item) => item.reason).toList(),
        <CapabilityActionOverlayIssueReason>[
          CapabilityActionOverlayIssueReason.duplicateKey,
          CapabilityActionOverlayIssueReason.keyNotSnakeCase,
        ]);
    expect(state.isDirty, isTrue);
  });

  test('importJson：不是可识别形状 → importNotRecognized，overlay 不动', () async {
    final initial = await loadEditor();
    controller().importJson('这不是 overlay');
    final state = readEditor();
    expect(state.issues.single.reason,
        CapabilityActionOverlayIssueReason.importNotRecognized);
    expect(state.overlay, same(initial.overlay));
    expect(state.isDirty, isFalse);
  });

  test('成功的编辑会清掉上一次的 issue', () async {
    await loadEditor();
    controller().add(action('Bad Key', '不合法'));
    expect(readEditor().hasIssues, isTrue);
    controller().add(action('limit_process', '取极限'));
    expect(readEditor().hasIssues, isFalse);
    expect(readEditor().customActionCount, 1);
  });

  test('clearIssues 只清提示，不动数据', () async {
    await loadEditor();
    controller().add(action('Bad Key', '不合法'));
    expect(readEditor().hasIssues, isTrue);
    controller().clearIssues();
    expect(readEditor().hasIssues, isFalse);
    expect(readEditor().customActionCount, 0);
  });

  test('save：写库、dirty 变 false、推理链路读到的词表随 invalidate 更新', () async {
    expect(
        (await container.read(capabilityActionOverlayProvider.future)).isEmpty,
        isTrue);
    await loadEditor();
    controller().add(action('force_diagram_analysis', '受力图分析'));
    expect(readEditor().isDirty, isTrue);

    await controller().save();
    final state = readEditor();
    expect(state.isDirty, isFalse);
    expect(state.isSaving, isFalse);
    expect((await store.load()).customActions.single.key,
        'force_diagram_analysis');
    final refreshed =
        await container.read(capabilityActionOverlayProvider.future);
    expect(refreshed.customActions.single.key, 'force_diagram_analysis');
  });

  test('save：删光后保存写回 NULL（回到出厂词表）', () async {
    await store.save(
        overlayWith(<CustomCapabilityAction>[action('limit_process', '取极限')]));
    await loadEditor();
    controller().remove('limit_process');
    await controller().save();
    expect(readEditor().isDirty, isFalse);
    expect((await settings.getSettings())!.capabilityActionOverlayJson, isNull);
  });

  test('save：没有改动时直接返回，不建库行', () async {
    await loadEditor();
    await controller().save();
    expect(await settings.getSettings(), isNull);
    expect(readEditor().isDirty, isFalse);
  });

  test('revert：放弃未保存的改动，回到上次保存的词表', () async {
    await store.save(
        overlayWith(<CustomCapabilityAction>[action('limit_process', '取极限')]));
    await loadEditor();
    controller().add(action('force_diagram_analysis', '受力图分析'));
    controller().remove('limit_process');
    expect(readEditor().customActionCount, 1);
    expect(readEditor().isDirty, isTrue);

    controller().revert();
    final state = readEditor();
    expect(state.isDirty, isFalse);
    expect(state.overlay.customActions.single.key, 'limit_process');
    expect(state.hasIssues, isFalse);
  });

  test('save 失败：isSaving 复位、草稿保留、异常照抛', () async {
    final failing = _FailingSaveSettings(db);
    final failingContainer = ProviderContainer(
      overrides: <Override>[
        settingsRepositoryProvider.overrideWithValue(failing),
      ],
    );
    addTearDown(failingContainer.dispose);
    await failingContainer.read(capabilityVocabularyEditorProvider.future);
    failingContainer.read(capabilityVocabularyEditorProvider.notifier).add(
          action('force_diagram_analysis', '受力图分析'),
        );
    await expectLater(
      failingContainer.read(capabilityVocabularyEditorProvider.notifier).save(),
      throwsA(isA<StateError>()),
    );
    final state =
        failingContainer.read(capabilityVocabularyEditorProvider).valueOrNull!;
    expect(state.isSaving, isFalse);
    expect(state.isDirty, isTrue);
    expect(state.customActionCount, 1);
  });
}
