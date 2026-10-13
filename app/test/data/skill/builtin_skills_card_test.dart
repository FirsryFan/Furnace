import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/skill/argumentative_writing_skill.dart';
import 'package:furnace/data/skill/skill_archive.dart';
import 'package:furnace/data/skill/skill_package_codec.dart';
import 'package:furnace/data/skill/skill_store.dart';
import 'package:furnace/data/skill/zujuan_finder_skill.dart';
import 'package:furnace/domain/skill/skill_manifest.dart';
import 'package:furnace/features/ai/application/ai_providers.dart';
import 'package:furnace/features/ai/presentation/ai_settings_page.dart';
import 'package:furnace/l10n/app_localizations.dart';

/// The built-in install affordance on the skills card.
///
/// A focused widget test, like `skills_settings_card_test.dart`: only the card
/// is mounted, and the store is overridden. The store answers from memory -
/// what is under test here is the wiring from "one tap on 组卷网找题" to
/// `SkillStore.install(<that package's bytes>)` and to the tile that appears
/// afterwards. That the packages really unpack into a temp support directory,
/// and appear enabled there with the manifest fields below, is covered against
/// the real store in `builtin_skills_test.dart`.
void main() {
  late Directory home;

  setUp(() {
    home = Directory.systemTemp.createTempSync('furnace_builtin_card');
  });

  tearDown(() {
    if (home.existsSync()) {
      home.deleteSync(recursive: true);
    }
  });

  Future<void> pumpCard(WidgetTester tester, _FakeSkillStore store) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          skillStoreProvider.overrideWithValue(store),
          // Re-read from the store on every invalidation, exactly as the real
          // provider does, so the post-install refresh is part of the assertion.
          installedSkillsProvider.overrideWith((ref) async => store.list()),
        ],
        child: const MaterialApp(
          locale: Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          // The card is taller than the 600 px test window, so it gets a scroll
          // view here; the real page mounts it inside a `ListView`.
          home: Scaffold(body: SingleChildScrollView(child: SkillsCard())),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Scrolls [finder] into view and taps it.
  ///
  /// The built-in row sits below the fold of the test window; without the
  /// scroll the tap would land outside the viewport.
  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Key installKeyFor(String name) => Key('builtin-skill-install-$name');

  testWidgets('the card names both built-ins before anything is installed',
      (tester) async {
    await pumpCard(tester, _FakeSkillStore());

    // One install button per built-in, labelled with the skill it installs.
    expect(find.text('安装 组卷网找题'), findsOneWidget);
    expect(find.text('安装 议论文写作'), findsOneWidget);
    expect(find.byKey(installKeyFor(ZujuanFinderSkill.name)), findsOneWidget);
    expect(
      find.byKey(installKeyFor(ArgumentativeWritingSkill.name)),
      findsOneWidget,
    );
    expect(find.textContaining('内置技能'), findsOneWidget);
    expect(find.textContaining('还没有安装任何 skill'), findsOneWidget);
    // The sample keeps its own button: the built-ins are additions, not a
    // replacement for the "does the script container work here" check.
    expect(find.text('安装示例 skill'), findsOneWidget);
  });

  testWidgets('one tap installs 组卷网找题 and the tile states what it declared',
      (tester) async {
    final store = _FakeSkillStore();
    await pumpCard(tester, store);

    await tapVisible(tester, find.byKey(installKeyFor(ZujuanFinderSkill.name)));

    // The button installed *that* package, not the other built-in and not a
    // stub. Byte equality would be the wrong check - the zip encoder stamps a
    // timestamp, so two builds differ - so what the package contains is
    // compared instead.
    expect(store.installCalls, 1);
    expect(store.lastInstalledManifestName, ZujuanFinderSkill.name);
    final entries =
        SkillPackageCodec.read(store.lastInstalledBytes!).entries;
    expect(entries.keys.toList()..sort(), ['manifest.json', 'prompt.md'],
        reason: 'a prompt-only built-in ships exactly these two files');
    expect(
      entries['prompt.md']!.text.trim(),
      ZujuanFinderSkill.prompt.trim(),
    );

    // ... and the card is now showing the tile built from what it installed.
    final state = tester.state<SkillsCardState>(find.byType(SkillsCard));
    expect(state.errorMessage, isNull,
        reason: 'the card reported a refusal: ${state.errorMessage}');
    expect(find.text('zujuan-finder  ·  v1.0.0'), findsOneWidget);
    expect(find.textContaining('windows, android'), findsOneWidget);
    expect(find.textContaining('zujuan.xkw.com'), findsWidgets);
    expect(find.textContaining('声明的工具：无'), findsOneWidget);
    // A prompt-only skill is not something the unsupported-capability warning
    // can be about: it requests no host capability at all.
    expect(find.textContaining('容器不提供'), findsNothing);
  });

  testWidgets('installing both and then removing one leaves the other installed',
      (tester) async {
    final store = _FakeSkillStore();
    await pumpCard(tester, store);

    await tapVisible(tester, find.byKey(installKeyFor(ZujuanFinderSkill.name)));
    await tapVisible(
      tester,
      find.byKey(installKeyFor(ArgumentativeWritingSkill.name)),
    );

    expect(find.text('zujuan-finder  ·  v1.0.0'), findsOneWidget);
    expect(find.text('argumentative-writing  ·  v1.0.0'), findsOneWidget);

    // The existing remove action is the undo, confirmation and all.
    await tapVisible(tester, find.text('删除').first);
    expect(find.textContaining('删除 skill'), findsOneWidget);
    expect(store.removed, isEmpty, reason: 'nothing happens before consent');
    // The confirm button lives in the dialog's overlay, which has no scrollable
    // ancestor, so it is tapped directly.
    await tester.tap(find.text('删除').last);
    await tester.pumpAndSettle();

    expect(store.removed, [ArgumentativeWritingSkill.name]);
    expect(find.text('argumentative-writing  ·  v1.0.0'), findsNothing);
    expect(find.text('zujuan-finder  ·  v1.0.0'), findsOneWidget,
        reason: 'removing one built-in must not touch the other');
    // ... and the removed one is offered again: the entry belongs to the app,
    // not to the install.
    expect(
      find.byKey(installKeyFor(ArgumentativeWritingSkill.name)),
      findsOneWidget,
    );
  });
}

/// A store that records what the card asked for and answers from memory.
///
/// The filesystem behaviour is the store's own test (`builtin_skills_test.dart`);
/// here the question is only whether the button installs the right package and
/// whether the card redraws from the store afterwards.
class _FakeSkillStore extends SkillStore {
  _FakeSkillStore() : super(supportDirectory: () async => Directory.systemTemp);

  final List<InstalledSkill> _installed = [];

  /// Every `install` call, so a test can assert one tap is one install.
  final List<Uint8List> installs = [];

  /// Names passed to [remove], in call order.
  final List<String> removed = [];

  int get installCalls => installs.length;

  Uint8List? get lastInstalledBytes =>
      installs.isEmpty ? null : installs.last;

  /// The manifest name inside the last installed package, read back out of the
  /// bytes rather than remembered from the call site.
  String? get lastInstalledManifestName {
    final bytes = lastInstalledBytes;
    if (bytes == null) {
      return null;
    }
    return SkillPackageCodec.readManifest(SkillPackageCodec.read(bytes).entries)
        ?.name;
  }

  @override
  Future<({InstalledSkill? skill, SkillValidationFailure? failure})> install(
    Uint8List bytes, {
    SkillPlatform? platform,
  }) async {
    installs.add(bytes);
    // Validate for real, so a package whose manifest or prompt is broken is
    // reported here the same way the real store reports it.
    final result = validateSkillPackage(
      SkillPackageCodec.read(bytes).entries,
      platform: platform ?? SkillPlatform.current,
    );
    final failure = result.failure;
    if (failure != null) {
      return (skill: null, failure: failure);
    }
    final package = result.requirePackage;
    final installed = InstalledSkill(
      manifest: package.manifest,
      prompt: package.prompt,
      tools: package.tools,
      enabled: true,
      installedAt: DateTime.utc(2026, 10, 2),
      directory: r'C:\appdata\skills\demo',
    );
    _installed
      ..removeWhere((skill) => skill.name == installed.name)
      ..add(installed);
    return (skill: installed, failure: null);
  }

  @override
  Future<List<InstalledSkill>> list() async =>
      // Sorted by name, like the real store: the card renders this list in
      // order, so a fake that reordered it would test a different card.
      [for (final skill in _installed) skill]
        ..sort((a, b) => a.name.compareTo(b.name));

  @override
  Future<bool> setEnabled(String name, bool enabled) async => true;

  @override
  Future<bool> setNetworkAllowed(String name, bool allowed) async => true;

  @override
  Future<bool> remove(String name) async {
    removed.add(name);
    _installed.removeWhere((skill) => skill.name == name);
    return true;
  }
}
