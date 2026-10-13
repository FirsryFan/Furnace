import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/skill/argumentative_writing_skill.dart';
import 'package:furnace/data/skill/builtin_skill.dart';
import 'package:furnace/data/skill/builtin_skills.dart';
import 'package:furnace/data/skill/skill_archive.dart';
import 'package:furnace/data/skill/skill_package_codec.dart';
import 'package:furnace/data/skill/skill_store.dart';
import 'package:furnace/data/skill/zujuan_finder_skill.dart';
import 'package:furnace/domain/skill/skill_manifest.dart';

/// The skills that ship inside the app.
///
/// Two things are under test, and they are different claims:
///
///  * the packages are *real* packages - built in memory from Dart strings,
///    validated by the same `validateSkillPackage` a picked `.fskill` goes
///    through, installed by the same `SkillStore`, and removable the same way.
///    A built-in that skipped validation would be a second, unaudited install
///    path;
///  * the prompts say what they must say. The one failure mode that matters
///    here is a prompt that lets the model invent an answer it cannot see, or
///    hand back an AI-written essay as the standard - so those sentences are
///    asserted on rather than trusted to survive editing.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory home;
  late SkillStore store;

  setUp(() {
    home = Directory.systemTemp.createTempSync('furnace_builtin_skill');
    store = SkillStore(supportDirectory: () async => home);
  });

  tearDown(() {
    if (home.existsSync()) {
      home.deleteSync(recursive: true);
    }
  });

  Map<String, SkillArchiveEntry> entriesOf(BuiltinSkill skill) =>
      SkillPackageCodec.read(skill.build()).entries;

  String promptOf(BuiltinSkill skill) =>
      SkillPackageCodec.readPrompt(entriesOf(skill))!;

  test('the catalog offers both jobs, and each package is named after its entry',
      () {
    expect(
      [for (final skill in BuiltinSkills.cardEntries) skill.name],
      [ZujuanFinderSkill.name, ArgumentativeWritingSkill.name],
    );

    for (final skill in BuiltinSkills.all) {
      final manifest = SkillPackageCodec.readManifest(entriesOf(skill))!;
      expect(manifest.name, skill.name,
          reason: 'the card label and the installed directory must be the same name');
      expect(manifest.format, SkillManifest.currentFormat);
    }
  });

  test('both packages validate for windows and android', () {
    for (final skill in BuiltinSkills.cardEntries) {
      final entries = entriesOf(skill);
      for (final platform in [SkillPlatform.windows, SkillPlatform.android]) {
        final result = validateSkillPackage(entries, platform: platform);
        expect(
          result.failure,
          isNull,
          reason: '${skill.name} on ${platform.id}: ${result.failure?.message ?? ''}',
        );
      }
    }
  });

  test('a platform neither package declares is refused, not silently accepted',
      () {
    for (final skill in BuiltinSkills.cardEntries) {
      final result = validateSkillPackage(
        entriesOf(skill),
        platform: SkillPlatform.macos,
      );
      expect(result.failure?.code, 'platformMismatch', reason: skill.name);
    }
  });

  test('组卷网找题 installs enabled, with the platforms and domain it declares',
      () async {
    final outcome = await store.install(ZujuanFinderSkill.build());
    expect(outcome.failure, isNull, reason: outcome.failure?.message ?? '');

    final installed = (await store.list()).single;
    expect(installed.name, 'zujuan-finder');
    expect(installed.enabled, isTrue, reason: 'a fresh install is on');
    expect(
      installed.manifest.platforms,
      [SkillPlatform.windows, SkillPlatform.android],
    );
    expect(installed.manifest.networkAllow, ['zujuan.xkw.com']);
    expect(installed.manifest.permissions, isEmpty);
    expect(
      installed.manifest.scripts,
      isEmpty,
      reason: 'prompt-only: nothing in the app can drive a browser',
    );
    expect(installed.tools, isEmpty);
    expect(
      installed.networkAllowed,
      isFalse,
      reason: 'a fresh install records a question, not consent to use the network',
    );
    // The prompt really reached the disk, and no script directory did.
    expect(installed.prompt, contains('fetch_page'));
    expect(File('${installed.directory}/prompt.md').existsSync(), isTrue);
    expect(Directory('${installed.directory}/scripts').existsSync(), isFalse);
  });

  test('议论文写作 installs enabled, prompt-only and offline', () async {
    final outcome = await store.install(ArgumentativeWritingSkill.build());
    expect(outcome.failure, isNull, reason: outcome.failure?.message ?? '');

    final installed = (await store.list()).single;
    expect(installed.name, 'argumentative-writing');
    expect(installed.enabled, isTrue);
    expect(
      installed.manifest.platforms,
      [SkillPlatform.windows, SkillPlatform.android],
    );
    expect(installed.manifest.networkAllow, isEmpty,
        reason: 'an empty allow-list is the claim "this needs no network"');
    expect(installed.manifest.scripts, isEmpty);
    expect(installed.tools, isEmpty);
    expect(installed.prompt, contains('AI 参考稿'));
  });

  test('both installed packages reach the model through enabled()', () async {
    await store.install(ZujuanFinderSkill.build());
    await store.install(ArgumentativeWritingSkill.build());

    // `SkillPrompt.build` consumes exactly this list, so being in it is what
    // "the prompt is in the system prompt" means.
    expect(
      [for (final skill in await store.enabled()) skill.name],
      ['argumentative-writing', 'zujuan-finder'],
    );
  });

  test('removing a built-in undoes the install completely', () async {
    await store.install(ZujuanFinderSkill.build());
    final directory = Directory(
      '${home.path}/${SkillStore.directoryName}/${ZujuanFinderSkill.name}',
    );
    expect(directory.existsSync(), isTrue);

    expect(await store.remove(ZujuanFinderSkill.name), isTrue);

    expect(await store.list(), isEmpty);
    expect(await store.enabled(), isEmpty);
    expect(directory.existsSync(), isFalse,
        reason: 'the existing remove action is the undo, and it deletes the directory');
  });

  test('the 组卷网 prompt tells the model what an anonymous fetch cannot do', () {
    const prompt = ZujuanFinderSkill.prompt;

    // What it works with, and where.
    expect(prompt, contains('fetch_page'));
    expect(prompt, contains('zujuan.xkw.com'));
    expect(prompt, contains('base64'));

    // The limits, stated rather than implied: answers need a login, so the
    // model must say so and must not fill the gap from memory.
    expect(prompt, contains('答案与解析需要登录'));
    expect(prompt, contains('默认拿不到'));
    expect(prompt, contains('不许'));
    expect(prompt, contains('绝不编造'));
    expect(prompt, contains('页面未提供'));

    // The four falsifiable defect classes the skill is for.
    for (final criterion in ['H1', 'H2', 'H3', 'H4']) {
      expect(prompt, contains(criterion), reason: criterion);
    }
    expect(prompt, contains('先怀疑自己'));
    expect(prompt, contains('样本 <5 道'));
  });

  test('the writing prompt forbids passing an AI draft off as the answer', () {
    const prompt = ArgumentativeWritingSkill.prompt;

    for (final method in ['逻辑先行', '比较阅读', '高阶纠错', '长时训练', 'AI 腔']) {
      expect(prompt, contains(method), reason: method);
    }

    // The teaching order, and the label that keeps a model-written essay from
    // becoming the thing the student submits.
    expect(prompt, contains('用户先发现'));
    expect(prompt, contains('AI 参考稿'));
    expect(prompt, contains('绝不作为标准答案'));
    expect(prompt, contains('不要调用联网工具'));
  });

  test('both prompts stay a prompt rather than a dump', () {
    for (final skill in BuiltinSkills.cardEntries) {
      final bytes = utf8.encode(promptOf(skill));
      // This text travels in *every* request of every turn (SkillPrompt caps
      // the whole skill section at 64 KB), so it is an index into the
      // methodology, not the methodology manual.
      expect(
        bytes.length,
        lessThan(6 * 1024),
        reason: '${skill.name} ships ${bytes.length} bytes of prompt',
      );
    }
  });
}
