import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/skill/sample_skill.dart';
import 'package:furnace/data/skill/skill_archive.dart';
import 'package:furnace/data/skill/skill_package_codec.dart';
import 'package:furnace/data/skill/skill_store.dart';
import 'package:furnace/domain/skill/skill_manifest.dart';
import 'package:furnace/domain/skill/skill_tool.dart';
import 'package:furnace/features/ai/domain/ai_tool.dart';

/// The skill that ships with the app.
///
/// It exists so the container can be tried without writing a package first, so
/// the test that matters is "does it actually run": a sample that fails to
/// install, or whose script cannot execute, would be worse than no sample at all.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final nodeAvailable =
      Process.runSync('where.exe', ['node'], runInShell: false).exitCode == 0;

  late Directory home;
  late SkillStore store;

  setUp(() {
    home = Directory.systemTemp.createTempSync('furnace_sample_skill');
    store = SkillStore(supportDirectory: () async => home);
  });

  tearDown(() {
    if (home.existsSync()) {
      home.deleteSync(recursive: true);
    }
  });

  test('the packaged sample passes the same validation as any other skill', () {
    final bytes = SampleSkill.build();

    final entries = SkillPackageCodec.read(bytes).entries;
    final result = validateSkillPackage(entries, platform: SkillPlatform.windows);

    expect(result.failure, isNull, reason: result.failure?.message ?? '');
    expect(result.requirePackage.manifest.name, SampleSkill.name);
    expect(
      result.requirePackage.manifest.scripts.single.name,
      SampleSkill.toolName,
    );
    expect(result.requirePackage.tools.single.name, SampleSkill.toolName);
  });

  test('installing it produces an enabled skill with one runnable tool',
      () async {
    final outcome = await store.install(SampleSkill.build());

    expect(outcome.failure, isNull, reason: outcome.failure?.message ?? '');
    final installed = (await store.list()).single;
    expect(installed.name, SampleSkill.name);
    expect(installed.enabled, isTrue, reason: 'a fresh install is on');
    expect(installed.tools.single.name, 'run_echo');
    expect(
      File('${installed.directory}/scripts/echo.mjs').existsSync(),
      isTrue,
      reason: 'the script is unpacked where the container will run it from',
    );
  });

  test('its tool reports itself runnable only on Windows', () async {
    await store.install(SampleSkill.build());
    final installed = (await store.list()).single;
    final declaration = installed.tools.single;
    final script = installed.manifest.scripts.single;

    final onWindows = SkillTool(
      skill: installed,
      declaration: declaration,
      script: script,
      platform: SkillPlatform.windows,
    );
    final onAndroid = SkillTool(
      skill: installed,
      declaration: declaration,
      script: script,
      platform: SkillPlatform.android,
    );

    expect(onWindows.availableOnCurrentPlatform, isTrue);
    expect(onAndroid.availableOnCurrentPlatform, isFalse);
    expect(
      onWindows.reversibleFor('run_echo'),
      isFalse,
      reason: 'a skill script is never assumed to be undoable (spec §5.1)',
    );
    expect(onWindows.riskFor('run_echo'), ToolRisk.write);
  });

  test('the sample script really runs and reports what it was given', () async {
    if (!nodeAvailable) {
      // Same rule as the container's own tests: no Node means no process test,
      // and that is a platform fact rather than a failure.
      // ignore: avoid_print
      print('skipped: no node on PATH');
      return;
    }
    await store.install(SampleSkill.build());
    final installed = (await store.list()).single;
    final tool = SkillTool(
      skill: installed,
      declaration: installed.tools.single,
      script: installed.manifest.scripts.single,
      platform: SkillPlatform.windows,
    );

    final result = await tool.run(const ToolInvocation(
      toolName: SampleSkill.toolName,
      action: 'run_echo',
      arguments: {'message': '你好 skill'},
    ));

    expect(result.ok, isTrue, reason: result.error ?? '');
    final text = '${result.modelResult}';
    expect(text, contains('你好 skill'), reason: 'the value reached the script');
    expect(text, contains('argv'));
    expect(
      text,
      isNot(contains('FURNACE_')),
      reason: 'the child environment is a fixed whitelist, not the parent one',
    );
  });
}
