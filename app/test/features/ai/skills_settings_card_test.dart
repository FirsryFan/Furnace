import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/skill/skill_archive.dart';
import 'package:furnace/data/skill/skill_store.dart';
import 'package:furnace/domain/skill/skill_manifest.dart';
import 'package:furnace/features/ai/application/ai_providers.dart';
import 'package:furnace/features/ai/presentation/ai_settings_page.dart';
import 'package:furnace/l10n/app_localizations.dart';

/// The skills card.
///
/// This is a focused widget test, not a view-model test: the card owns its
/// localised strings and its own layout, and those are what a user sees. Only
/// the card is mounted - the whole `AiSettingsPage` would additionally need the
/// AI settings table and the tool registry, neither of which the card touches -
/// and the provider that supplies the install list is overridden, so no real
/// directory is read.
void main() {
  InstalledSkill skill({
    String name = 'demo-skill',
    String version = '1.0.0',
    bool enabled = true,
    bool networkAllowed = false,
    List<String> platforms = const ['windows'],
    List<String> networkAllow = const ['example.com'],
    List<String> permissions = const ['browser_bridge'],
    List<SkillToolDeclaration> tools = const [],
  }) =>
      InstalledSkill(
        manifest: SkillManifest(
          format: 'fskill/1',
          name: name,
          version: version,
          description: '演示用的 skill',
          platforms: [
            for (final id in platforms) SkillPlatform.fromId(id)!,
          ],
          networkAllow: networkAllow,
          permissions: permissions,
        ),
        prompt: '# 方法论\n',
        tools: tools,
        enabled: enabled,
        networkAllowed: networkAllowed,
        installedAt: DateTime.utc(2026, 10, 1),
        directory: r'C:\appdata\skills\demo-skill',
      );

  SkillToolDeclaration tool(String name) => SkillToolDeclaration(
        name: name,
        description: '按条件检索题目',
        parameters: const {'type': 'object'},
        risk: 'write',
        reversible: false,
        source: 'tools/find.json',
      );

  /// Mounts the skills card with [skills] as the store's answer.
  Future<void> pumpCard(
    WidgetTester tester,
    List<InstalledSkill> skills, {
    SkillStore? store,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          installedSkillsProvider.overrideWith((ref) async => skills),
          if (store != null) skillStoreProvider.overrideWithValue(store),
        ],
        child: const MaterialApp(
          locale: Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: SkillsCard()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('an installed skill is listed with its name and declared facts',
      (tester) async {
    await pumpCard(tester, [
      skill(version: '2.1.0', tools: [tool('find_questions')]),
    ]);

    expect(find.textContaining('demo-skill'), findsWidgets);
    expect(find.textContaining('v2.1.0'), findsOneWidget);
    expect(find.textContaining('演示用的 skill'), findsOneWidget);
    // The declared facts the spec requires to be shown, not just the name.
    expect(find.textContaining('windows'), findsOneWidget);
    expect(find.textContaining('example.com'), findsWidgets);
    // `browser_bridge` appears twice on purpose: once as a declared fact and
    // once as the warning that the container does not provide it.
    expect(find.textContaining('browser_bridge'), findsNWidgets(2));
    expect(find.textContaining('容器不提供'), findsOneWidget);
    expect(find.textContaining('find_questions'), findsOneWidget);
  });

  testWidgets('the card states whether scripts can run on this platform',
      (tester) async {
    await pumpCard(tester, [skill()]);

    if (Platform.isWindows) {
      // The container is implemented, so the old "not enabled" note must be
      // gone: leaving it would be a false statement about this build.
      expect(find.textContaining('容器已启用'), findsOneWidget);
      expect(find.textContaining('容器未启用'), findsNothing);
      expect(find.textContaining('本机可以运行'), findsOneWidget);
    } else {
      expect(find.textContaining('脚本执行只支持 Windows'), findsOneWidget);
    }
  });

  testWidgets('a skill this machine cannot run says so instead of pretending',
      (tester) async {
    await pumpCard(tester, [
      skill(platforms: const ['linux']),
    ]);

    // Whatever the host platform is, a package declaring `linux` only cannot
    // have its scripts run here.
    expect(find.textContaining('本机不能运行'), findsOneWidget);
    expect(find.textContaining('linux'), findsWidgets);
  });

  testWidgets('an empty install list says so and does not claim a container',
      (tester) async {
    await pumpCard(tester, const []);

    expect(find.textContaining('还没有安装任何 skill'), findsOneWidget);
    expect(find.textContaining('容器已启用'), findsNothing,
        reason: 'the container note belongs to an installed skill, not a header');
    expect(find.textContaining('脚本执行只支持 Windows'), findsNothing);
  });

  testWidgets('the network switch is labelled with the declared domains and '
      'reaches the store', (tester) async {
    final store = _FakeSkillStore();
    await pumpCard(
      tester,
      [skill(networkAllow: const ['zujuan.xkw.com'], networkAllowed: false)],
      store: store,
    );

    // The domains are on the consent control itself, because "allow network"
    // without them would be consent to nothing in particular.
    final consentSwitch = find.widgetWithText(
      SwitchListTile,
      '允许联网（zujuan.xkw.com）',
    );
    expect(consentSwitch, findsOneWidget);
    expect(tester.widget<SwitchListTile>(consentSwitch).value, isFalse);
    expect(find.textContaining('未允许联网（zujuan.xkw.com）'), findsOneWidget);

    await tester.tap(consentSwitch);
    await tester.pumpAndSettle();

    expect(store.networkToggled, [('demo-skill', true)]);
  });

  testWidgets('a skill that declares no network gets no consent control',
      (tester) async {
    await pumpCard(tester, [skill(networkAllow: const [])]);

    expect(find.byType(SwitchListTile), findsNothing);
    expect(find.textContaining('没有声明要联网'), findsOneWidget);
  });

  testWidgets('an invalid package shows the specific refusal reason',
      (tester) async {
    final store = _FakeSkillStore();
    await pumpCard(tester, const [], store: store);

    // Exactly what the install button does with a picked file, minus the
    // platform-channel file dialog: bytes that are not a zip at all.
    final state = tester.state<SkillsCardState>(find.byType(SkillsCard));
    final outcome = await state.installBytes(
      Uint8List.fromList([1, 2, 3, 4]),
    );

    expect(outcome.installed, isNull);
    expect(outcome.error, isNotNull);
    expect(outcome.error, contains('不是有效的 .fskill'),
        reason: 'the reason is the only part of a refusal the user can act on');

    state.showErrorForTest(outcome.error!);
    await tester.pump();
    expect(find.textContaining('不是有效的 .fskill'), findsOneWidget);
  });

  testWidgets('a refusal produced by validation is shown verbatim',
      (tester) async {
    final store = _FakeSkillStore()
      ..installFailure = const SkillValidationFailure(
        'formatMismatch',
        '协议号是「fskill/2」，本应用只支持 「fskill/1」。不做兼容猜测，已拒绝',
      );
    await pumpCard(tester, const [], store: store);

    final state = tester.state<SkillsCardState>(find.byType(SkillsCard));
    final outcome = await state.installBytes(Uint8List.fromList([1, 2, 3, 4]));
    state.showErrorForTest(outcome.error!);
    await tester.pump();

    expect(find.textContaining('fskill/2'), findsOneWidget);
    expect(find.textContaining('不做兼容猜测'), findsOneWidget);
  });

  testWidgets('the enable switch reflects the skill and reaches the store',
      (tester) async {
    final store = _FakeSkillStore();
    await pumpCard(tester, [skill(enabled: true)], store: store);

    // The tile now holds two switches (enable, then network consent), and the
    // enable one is built first, so `first` is unambiguous here.
    final enableSwitch = find.byType(Switch).first;
    expect(tester.widget<Switch>(enableSwitch).value, isTrue);

    await tester.tap(enableSwitch);
    await tester.pumpAndSettle();

    expect(store.toggled, [('demo-skill', false)],
        reason: 'tapping an enabled switch asks the store to disable it');
  });

  testWidgets('remove asks for confirmation, names the skill, and waits',
      (tester) async {
    final store = _FakeSkillStore();
    await pumpCard(tester, [skill()], store: store);

    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();

    expect(find.textContaining('删除 skill'), findsOneWidget);
    expect(
      find.textContaining('确认把这个 skill 的文件从磁盘上删掉'),
      findsOneWidget,
      reason: 'the confirmation must say the files are deleted from disk',
    );
    expect(find.textContaining('demo-skill：'), findsOneWidget,
        reason: 'the confirmation names the skill being deleted');
    expect(store.removed, isEmpty, reason: 'nothing happens before consent');

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(store.removed, isEmpty);
  });

  testWidgets('confirming the dialog removes the skill', (tester) async {
    final store = _FakeSkillStore();
    await pumpCard(tester, [skill()], store: store);

    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    // The confirm button carries the same label as the row action, so the one
    // inside the dialog is the last match.
    await tester.tap(find.text('删除').last);
    await tester.pumpAndSettle();

    expect(store.removed, ['demo-skill']);
  });
}

/// A store whose only job is to record what the card asked for.
///
/// It answers from memory rather than from disk because the filesystem
/// behaviour is covered by the store's own tests; what is under test here is
/// the wiring between the card and the store.
class _FakeSkillStore extends SkillStore {
  /// Names passed to [setEnabled], in call order.
  final List<(String, bool)> toggled = [];

  /// Names and values passed to [setNetworkAllowed], in call order.
  final List<(String, bool)> networkToggled = [];

  /// Names passed to [remove].
  final List<String> removed = [];

  /// When set, [install] reports this refusal instead of reading a package.
  SkillValidationFailure? installFailure;

  @override
  Future<({InstalledSkill? skill, SkillValidationFailure? failure})> install(
    Uint8List bytes, {
    SkillPlatform? platform,
  }) async {
    final failure = installFailure;
    if (failure != null) {
      return (skill: null, failure: failure);
    }
    // No canned answer: fall through to the real validation, which is what
    // produces the "not a zip" refusal the other test asserts on.
    return super.install(bytes, platform: platform);
  }

  @override
  Future<bool> setEnabled(String name, bool enabled) async {
    toggled.add((name, enabled));
    return true;
  }

  @override
  Future<bool> setNetworkAllowed(String name, bool allowed) async {
    networkToggled.add((name, allowed));
    return true;
  }

  @override
  Future<bool> remove(String name) async {
    removed.add(name);
    return true;
  }
}
