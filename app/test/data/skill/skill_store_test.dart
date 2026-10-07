import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/skill/skill_store.dart';
import 'package:furnace/domain/skill/skill_manifest.dart';
import 'package:path/path.dart' as p;

import 'skill_fixture.dart';

/// The store, against a real temporary directory.
///
/// Faking the filesystem here would test nothing: the whole point of the store
/// is what ends up on disk, what a refused install leaves behind, and whether a
/// restart can read it back. The tests therefore create real files and read
/// them back the way the app does on launch.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory supportDir;
  late SkillStore store;

  setUp(() {
    supportDir = Directory.systemTemp.createTempSync('furnace_skill_store');
    store = SkillStore(supportDirectory: () async => supportDir);
  });

  tearDown(() {
    if (supportDir.existsSync()) {
      supportDir.deleteSync(recursive: true);
    }
  });

  Directory skillDir(String name) =>
      Directory(p.join(supportDir.path, SkillStore.directoryName, name));

  /// Staging directories left in the skills folder.
  ///
  /// There is one assertion behind this: whatever an install does, it must not
  /// leave a `.staging` directory behind - a leftover would be an orphaned copy
  /// of the package the user has no way to see or remove.
  List<String> stagingLeftovers() {
    final root = Directory(p.join(supportDir.path, SkillStore.directoryName));
    if (!root.existsSync()) {
      return const [];
    }
    return [
      for (final entity in root.listSync())
        if (entity is Directory &&
            p.basename(entity.path).endsWith(SkillStore.stagingSuffix))
          entity.path,
    ];
  }

  /// A store built on the same directory, as a restart would be.
  SkillStore restarted() => SkillStore(supportDirectory: () async => supportDir);

  group('install', () {
    test('extracts the package under <support>/skills/<name>/', () async {
      final result = await store.install(buildSkillArchive(
        manifestJson: skillManifestJson(name: 'demo-skill', version: '2.0.0'),
        prompt: '# 方法论\n正文\n',
        tools: {'find.json': skillToolJson()},
        scripts: {'scripts/find.mjs': 'console.log(1)\n'},
      ));

      expect(result.failure, isNull);
      final skill = result.skill!;
      expect(skill.name, 'demo-skill');
      expect(skill.manifest.version, '2.0.0');
      expect(skill.enabled, isTrue);

      // The files are really there, byte for byte: this is the contract the
      // script container would later rely on (cwd = the skill's own directory).
      expect(
        File(p.join(skillDir('demo-skill').path, 'prompt.md')).readAsStringSync(),
        '# 方法论\n正文\n',
      );
      expect(
        File(p.join(skillDir('demo-skill').path, 'scripts', 'find.mjs'))
            .readAsStringSync(),
        'console.log(1)\n',
      );
      expect(skillDir('demo-skill').path, skill.directory);
    });

    test('writes state.json inside the skill directory', () async {
      await store.install(buildSkillArchive());

      final stateFile = File(p.join(skillDir('demo-skill').path, 'state.json'));
      expect(stateFile.existsSync(), isTrue);
      final state = jsonDecode(stateFile.readAsStringSync()) as Map;
      expect(state['enabled'], isTrue);
      expect(DateTime.tryParse(state['installedAt'] as String), isNotNull);
    });

    test('a refusal leaves no directory and no staging directory behind',
        () async {
      final result = await store.install(buildSkillArchive(
        manifestJson: skillManifestJson(scripts: const [
          {'name': 'x', 'entry': 'scripts/missing.mjs'},
        ]),
      ));

      expect(result.skill, isNull);
      expect(result.failure!.code, 'missingScriptEntry');
      expect(skillDir('demo-skill').existsSync(), isFalse);
      expect(stagingLeftovers(), isEmpty);
    });

    test('a destructive tool is refused and writes nothing', () async {
      final result = await store.install(buildSkillArchive(
        tools: {'wipe.json': skillToolJson(name: 'wipe_all', risk: 'destructive')},
      ));
      expect(result.failure!.code, 'destructiveToolRefused');
      expect(skillDir('demo-skill').existsSync(), isFalse);
    });

    test('installing the same name again replaces the previous copy', () async {
      await store.install(buildSkillArchive(
        prompt: '第一版\n',
        scripts: {'scripts/find.mjs': 'v1\n'},
      ));

      final second = await store.install(buildSkillArchive(
        manifestJson: skillManifestJson(version: '2.0.0'),
        prompt: '第二版\n',
        scripts: {'scripts/find.mjs': 'v2\n'},
      ));

      expect(second.failure, isNull);
      final files = (await store.list());
      expect(files, hasLength(1), reason: 'a replace is not a second install');
      expect(files.single.manifest.version, '2.0.0');
      expect(
        File(p.join(skillDir('demo-skill').path, 'prompt.md')).readAsStringSync(),
        '第二版\n',
      );
      expect(
        File(p.join(skillDir('demo-skill').path, 'scripts', 'find.mjs'))
            .readAsStringSync(),
        'v2\n',
      );
      expect(stagingLeftovers(), isEmpty);
    });

    test('a failed validation leaves the previously installed copy intact',
        () async {
      await store.install(buildSkillArchive(prompt: '第一版\n'));

      // Same name, but the declared script is not in the archive - so this must
      // be refused before anything on disk is touched.
      final result = await store.install(buildSkillArchive(
        prompt: '第二版\n',
        manifestJson: skillManifestJson(scripts: const [
          {'name': 'x', 'entry': 'scripts/missing.mjs'},
        ]),
      ));

      expect(result.failure!.code, 'missingScriptEntry');
      final files = await store.list();
      expect(files, hasLength(1));
      expect(
        File(p.join(skillDir('demo-skill').path, 'prompt.md')).readAsStringSync(),
        '第一版\n',
        reason: 'a refused upgrade must not damage the working install',
      );
      expect(stagingLeftovers(), isEmpty);
    });

    test('a wrong-protocol package is refused with that reason', () async {
      final result = await store.install(
        buildSkillArchive(manifestJson: skillManifestJson(format: 'fskill/9')),
      );
      expect(result.failure!.code, 'formatMismatch');
      expect(skillDir('demo-skill').existsSync(), isFalse);
    });
  });

  group('list / enable / disable / remove', () {
    test('round trip', () async {
      await store.install(buildSkillArchive(
        tools: {'find.json': skillToolJson()},
      ));

      var listed = await store.list();
      expect(listed, hasLength(1));
      expect(listed.single.enabled, isTrue);
      expect(listed.single.manifest.platforms, [SkillPlatform.windows]);
      expect(listed.single.manifest.networkAllow, ['example.com']);
      expect(listed.single.tools.single.name, 'find_questions');
      expect(await store.enabled(), hasLength(1));

      expect(await store.setEnabled('demo-skill', false), isTrue);
      listed = await store.list();
      expect(listed.single.enabled, isFalse);
      expect(await store.enabled(), isEmpty,
          reason: 'a disabled skill must contribute nothing to the prompt');

      expect(await store.setEnabled('demo-skill', true), isTrue);
      expect((await store.list()).single.enabled, isTrue);
      expect(await store.enabled(), hasLength(1));

      expect(await store.remove('demo-skill'), isTrue);
      expect(await store.list(), isEmpty);
      expect(skillDir('demo-skill').existsSync(), isFalse);
    });

    test('the enabled flag survives a restart', () async {
      await store.install(buildSkillArchive());
      await store.setEnabled('demo-skill', false);

      // A restart is a new store over the same directory and nothing in memory.
      final reread = await restarted().list();
      expect(reread.single.enabled, isFalse);
    });

    test('listing is sorted by name, so the prompt order is stable', () async {
      await store.install(buildSkillArchive(
        manifestJson: skillManifestJson(name: 'zulu'),
      ));
      await store.install(buildSkillArchive(
        manifestJson: skillManifestJson(name: 'alpha'),
      ));

      expect([for (final skill in await store.list()) skill.name],
          ['alpha', 'zulu']);
    });

    test('enabling or removing an unknown skill reports false', () async {
      expect(await store.setEnabled('never-installed', true), isFalse);
      expect(await store.remove('never-installed'), isFalse);
    });

    test('removing really deletes the files from disk', () async {
      await store.install(buildSkillArchive(
        scripts: {'scripts/find.mjs': 'x\n'},
      ));
      final directory = skillDir('demo-skill');
      expect(directory.existsSync(), isTrue);

      await store.remove('demo-skill');

      expect(directory.existsSync(), isFalse);
      expect(await restarted().list(), isEmpty);
    });

    test('a foreign directory in the skills folder is skipped, not listed',
        () async {
      await store.install(buildSkillArchive());
      Directory(p.join(supportDir.path, SkillStore.directoryName, 'not-a-skill'))
          .createSync(recursive: true);

      final listed = await store.list();
      expect(listed, hasLength(1));
      expect(listed.single.name, 'demo-skill');
    });
  });

  group('platform gating at install time', () {
    test('windows-only installs on windows and is refused on android',
        () async {
      final bytes = buildSkillArchive(
        manifestJson: skillManifestJson(platforms: const ['windows']),
      );

      final onWindows = await store.install(bytes, platform: SkillPlatform.windows);
      expect(onWindows.failure, isNull);
      expect(onWindows.skill!.name, 'demo-skill');
      await store.remove('demo-skill');

      final onAndroid = await store.install(bytes, platform: SkillPlatform.android);
      expect(onAndroid.skill, isNull);
      expect(onAndroid.failure!.code, 'platformMismatch');
      expect(skillDir('demo-skill').existsSync(), isFalse);
    });

    test('android-only installs on android and is refused on windows',
        () async {
      final bytes = buildSkillArchive(
        manifestJson: skillManifestJson(platforms: const ['android']),
      );

      final onAndroid = await store.install(bytes, platform: SkillPlatform.android);
      expect(onAndroid.failure, isNull);
      await store.remove('demo-skill');

      final onWindows = await store.install(bytes, platform: SkillPlatform.windows);
      expect(onWindows.failure!.code, 'platformMismatch');
      expect(skillDir('demo-skill').existsSync(), isFalse);
    });

    test('a package declaring both platforms installs on either', () async {
      final bytes = buildSkillArchive(
        manifestJson: skillManifestJson(platforms: const ['windows', 'android']),
      );
      expect((await store.install(bytes, platform: SkillPlatform.windows)).failure,
          isNull);
      expect((await store.install(bytes, platform: SkillPlatform.android)).failure,
          isNull);
    });
  });
}
