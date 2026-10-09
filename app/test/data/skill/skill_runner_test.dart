/// The §3 script container, against real temporary skill directories and a real
/// `node`.
///
/// Nothing is mocked here. The container's whole job is bytes on a pipe, an
/// environment map and a process tree, and a fake would test the fake: these
/// tests create a skill directory, write a script into it, run it, and assert on
/// what the process actually printed. The fixture `.fskill` is built in-process
/// by `skill_fixture.dart`, so no binary is committed for any of it.
///
/// Tests whose subject is the *declarative* half of the container (argument
/// mapping) run without Node at all: `argvFor` is a pure function and is tested
/// as one. The tests that need a process are skipped, with a printed reason,
/// when `node` is not on this machine's `PATH` - a platform without Node is
/// exactly the Android case the spec gates on, so it must not look like a
/// failure of the rules that do not depend on it.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/skill/skill_runner.dart';
import 'package:furnace/data/skill/skill_store.dart';
import 'package:furnace/domain/skill/skill_manifest.dart';
import 'package:furnace/domain/skill/skill_tool.dart';
import 'package:furnace/features/ai/domain/agent_loop.dart';
import 'package:furnace/features/ai/domain/ai_tool.dart';
import 'package:path/path.dart' as p;

import 'skill_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Whether this machine can run any of the process tests.
  ///
  /// Resolved once, through the same `PATH` the container uses, so the answer
  /// here and the container's own answer are the same question.
  final nodeAvailable = Process.runSync(
    'where.exe',
    ['node'],
    runInShell: false,
  ).exitCode == 0;

  late Directory home;
  late SkillStore store;
  const runner = SkillRunner();

  setUp(() {
    home = Directory.systemTemp.createTempSync('furnace_skill_runner');
    store = SkillStore(supportDirectory: () async => home);
  });

  tearDown(() {
    if (home.existsSync()) {
      home.deleteSync(recursive: true);
    }
  });

  Directory skillDir(String name) =>
      Directory(p.join(home.path, SkillStore.directoryName, name));

  /// Writes a skill directory by hand, bypassing `install`.
  ///
  /// The runner's contract is with an [InstalledSkill] whose files are on disk,
  /// not with the installer, so the tests write the files directly and let
  /// [SkillStore.list] read them back exactly as the app would. That keeps an
  /// install-time failure from masquerading as a container failure.
  ///
  /// `state.json` is written with `networkAllowed` set to what the test asks
  /// for, which is how consent is expressed without going through the UI.
  void seedSkill({
    String name = 'demo-skill',
    List<String> platforms = const ['windows'],
    List<String> networkAllow = const [],
    List<String> permissions = const [],
    List<Map<String, dynamic>> scripts = const [],
    Map<String, Map<String, dynamic>> tools = const {},
    Map<String, String> files = const {},
    bool networkAllowed = false,
  }) {
    final dir = skillDir(name);
    dir.createSync(recursive: true);
    File(p.join(dir.path, 'manifest.json')).writeAsStringSync(jsonEncode(
      skillManifestJson(
        name: name,
        platforms: platforms,
        networkAllow: networkAllow,
        permissions: permissions,
        scripts: scripts,
      ),
    ));
    File(p.join(dir.path, 'prompt.md')).writeAsStringSync('# $name\n');
    for (final entry in tools.entries) {
      File(p.join(dir.path, 'tools', entry.key))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(jsonEncode(entry.value));
    }
    for (final entry in files.entries) {
      File(p.joinAll([dir.path, ...entry.key.split('/')]))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(entry.value);
    }    File(p.join(dir.path, SkillStore.stateFileName)).writeAsStringSync(jsonEncode({
      'enabled': true,
      'networkAllowed': networkAllowed,
      'installedAt': DateTime.utc(2026, 10, 2).toIso8601String(),
    }));
  }

  Future<InstalledSkill> installed(String name) async {
    final skills = await store.list();
    return skills.firstWhere((skill) => skill.name == name);
  }

  SkillToolDeclaration declaration(InstalledSkill skill, String toolName) =>
      skill.tools.firstWhere((tool) => tool.name == toolName);

  /// A `tools/*.json` declaration whose parameters are `subject`, `count`,
  /// `verbose` and `only`.
  Map<String, dynamic> findQuestionsTool() => skillToolJson(parameters: {
        'type': 'object',
        'properties': {
          'subject': {'type': 'string'},
          'count': {'type': 'integer'},
          'verbose': {'type': 'boolean'},
          'only': {'type': 'array', 'items': {'type': 'string'}},
        },
      });

  Map<String, dynamic> script(
    String name,
    String entry,
    List<String> args,
  ) =>
      {'name': name, 'entry': entry, 'args': args};

  group('argument mapping is declarative (spec §2.1)', () {
    /// The declaration all of these share: four parameters, four flags.
    Map<String, Object?> parameters() => {
          'type': 'object',
          'properties': {
            'subject': {'type': 'string'},
            'count': {'type': 'integer'},
            'verbose': {'type': 'boolean'},
            'only': {'type': 'array', 'items': {'type': 'string'}},
          },
        };

    /// What `manifest.json`'s `scripts[].args` would declare, keyed by the
    /// parameter each flag belongs to. Derived through the same helper the
    /// container uses, so a change to the pairing convention shows up as a test
    /// failure rather than as two independently stale assumptions.
    final declared = {
      for (final flag in const ['--subject', '--count', '--verbose', '--only'])
        SkillRunner.parameterNameOf(flag): flag,
    };

    test('strings, numbers, booleans and arrays map to their flags', () {
      final argv = SkillRunner.argvFor(
        parameters: parameters(),
        arguments: {
          'subject': '物理 力学',
          'count': 3,
          'verbose': true,
          'only': ['A B', 'C'],
        },
        declaredFlags: declared,
      );

      expect(argv, [
        '--count',
        '3',
        // The array repeats its flag once per element, in order.
        '--only',
        'A B',
        '--only',
        'C',
        '--subject',
        '物理 力学',
        // A true boolean is a bare flag, not `--verbose true`.
        '--verbose',
      ]);
      // The space inside a value is a space *inside one argv element*: there is
      // no shell to split it and no string concatenation to split it either.
      expect(argv.where((token) => token == '物理 力学'), hasLength(1));
    });

    test('a false boolean is omitted entirely', () {
      final argv = SkillRunner.argvFor(
        parameters: parameters(),
        arguments: {'verbose': false, 'subject': 'x'},
        declaredFlags: declared,
      );
      expect(argv, ['--subject', 'x']);
    });

    test('an undeclared parameter is refused, not passed', () {
      expect(
        () => SkillRunner.argvFor(
          parameters: parameters(),
          arguments: {'subject': 'x', '--danger': 'rm -rf'},
          declaredFlags: declared,
        ),
        throwsA(isA<ToolArgError>().having(
          (e) => e.message,
          'message',
          allOf(contains('--danger'), contains('已拒绝')),
        )),
      );
    });

    test('a declared flag the schema does not describe is refused too', () {
      expect(
        () => SkillRunner.argvFor(
          parameters: parameters(),
          arguments: {'subject': 'x'},
          // A manifest that declares a flag for a parameter the tool schema
          // never described: the container refuses rather than guessing which
          // parameter the flag was meant for.
          declaredFlags: {...declared, 'smuggled': '--smuggled'},
        ),
        throwsA(isA<ToolArgError>().having(
          (e) => e.message,
          'message',
          allOf(contains('smuggled'), contains('JSON Schema')),
        )),
      );
    });

    test('the manifest flag and the schema parameter are tied by name', () {
      // `scripts[].args` declares flags; the schema declares parameters. The
      // container strips the leading dashes to pair them, so this is the one
      // place that pairing is stated.
      expect(SkillRunner.parameterNameOf('--subject'), 'subject');
      expect(SkillRunner.parameterNameOf('--only'), 'only');
    });

    test('a parameter the model omits produces no flag at all', () {
      expect(
        SkillRunner.argvFor(
          parameters: parameters(),
          arguments: {'count': 1},
          declaredFlags: declared,
        ),
        ['--count', '1'],
      );
    });
  });

  group('a declared tool runs its script', () {
    test('the declared tool runs, and its JSON line comes back', () async {
      seedSkill(
        networkAllow: const [],
        tools: {'find.json': findQuestionsTool()},
        scripts: [script('find_questions', 'scripts/find.mjs', ['--subject', '--count'])],
        files: {
          'scripts/find.mjs': r'''
const argv = process.argv.slice(2);
const subject = argv[argv.indexOf('--subject') + 1];
const count = Number(argv[argv.indexOf('--count') + 1]);
console.log(JSON.stringify({questions: [{id: 'q1', subject}], count, cwd: process.cwd()}));
''',
        },
      );

      if (!nodeAvailable) {
        markTestSkipped('node is not on PATH: this machine cannot run skill scripts');
        return;
      }

      final skill = await installed('demo-skill');
      final result = await runner.run(
        skill: skill,
        declaration: declaration(skill, 'find_questions'),
        script: skill.manifest.scripts.single,
        arguments: {'subject': '物理', 'count': 2},
      );

      expect(result, isA<SkillScriptOutcome>());
      final outcome = result as SkillScriptOutcome;
      expect(outcome.ok, isTrue, reason: outcome.stderr);
      expect(outcome.exitCode, 0);
      expect(outcome.timedOut, isFalse);
      expect(outcome.truncated, isFalse);

      final decoded = jsonDecode(outcome.stdout.trim()) as Map;
      expect(decoded['count'], 2);
      expect(decoded['cwd'], skill.directory,
          reason: '§3: cwd is the skill private directory, not the user home');
      final questions = decoded['questions'] as List;
      expect((questions.single as Map)['subject'], '物理');
    });

    test('the model result is truncated when the output is huge', () async {
      seedSkill(
        tools: {'find.json': findQuestionsTool()},
        scripts: [script('find_questions', 'scripts/huge.mjs', [])],
        files: {
          // 64 KB of a single line, repeated ten times: enough to pass the
          // 8 KB model cap several times over.
          'scripts/huge.mjs':
              "const line = 'x'.repeat(64 * 1024);\nfor (let i = 0; i < 10; i++) console.log(line);\n",
        },
      );
      if (!nodeAvailable) {
        markTestSkipped('node is not on PATH: this machine cannot run skill scripts');
        return;
      }

      final skill = await installed('demo-skill');
      final outcome = await runner.run(
        skill: skill,
        declaration: declaration(skill, 'find_questions'),
        script: skill.manifest.scripts.single,
        arguments: const {},
      ) as SkillScriptOutcome;
      expect(outcome.ok, isTrue);

      // The container keeps up to 256 KB; the tool caps what the model reads at
      // 8 KB and says so.
      expect(outcome.stdout.length, greaterThan(SkillRunner.modelResultCapBytes));

      final toolResult = await skillToolFor(skill, runner)
          .run(const ToolInvocation(
        toolName: 'demo-skill_find_questions',
        action: 'find_questions',
        arguments: {},
      ));
      expect(toolResult.ok, isTrue);
      final payload = toolResult.modelResult! as Map;
      final stdout = payload['stdout']! as String;
      expect(stdout.length, lessThan(SkillRunner.modelResultCapBytes + 200));
      expect(stdout, contains('truncated'));
      expect(payload['exit_code'], 0);
      expect(payload['timed_out'], isFalse);
    });
  });

  group('the environment whitelist (spec §3)', () {
    test('a script sees exactly the whitelisted variables', () async {
      seedSkill(
        tools: {'find.json': findQuestionsTool()},
        scripts: [script('find_questions', 'scripts/env.mjs', [])],
        files: {
          'scripts/env.mjs':
              'console.log(JSON.stringify(Object.keys(process.env).map(k => k.toUpperCase()).sort()));\n',
        },
      );
      if (!nodeAvailable) {
        markTestSkipped('node is not on PATH: this machine cannot run skill scripts');
        return;
      }

      // A decoy in the parent process: the container must not pass the parent
      // environment through, and the strongest form of that claim is that a
      // variable which is present in the map handed in cannot be found in the
      // child's environment.
      const decoy = 'FURNACE_TEST_API_KEY';
      final parent = {
        ...Platform.environment,
        decoy: 'sk-must-not-leak',
        'PATH': Platform.environment['PATH'] ?? '',
      };
      final childEnv = SkillRunner.environmentFor(parent);
      expect(childEnv.containsKey(decoy), isFalse,
          reason: 'the whitelist is a fixed list, so an unlisted secret is absent');
      expect(childEnv.keys.toSet(), {
        for (final name in SkillRunner.environmentWhitelist)
          if (parent[name] != null) name,
      });

      final skill = await installed('demo-skill');
      final outcome = await runner.run(
        skill: skill,
        declaration: declaration(skill, 'find_questions'),
        script: skill.manifest.scripts.single,
        arguments: const {},
      ) as SkillScriptOutcome;

      expect(outcome.ok, isTrue, reason: outcome.stderr);
      final keys = (jsonDecode(outcome.stdout.trim()) as List).cast<String>().toSet();
      expect(keys, isNot(contains(decoy)));
      // Nothing that looks like a credential, whoever added it, on any platform.
      for (final key in keys) {
        expect(
          key.contains('KEY') || key.contains('TOKEN') || key.contains('SECRET') ||
              key.contains('PASSWORD'),
          isFalse,
          reason: 'child environment leaked $key',
        );
      }
      // The allow-list is not empty: an environment stripped of PATH could not
      // have started node in the first place, which is itself evidence.
      expect(outcome.stderr, isEmpty);
    });
  });

  group('process rules (spec §3)', () {
    test('a timeout kills the process and reports a failure', () async {
      seedSkill(
        tools: {'find.json': findQuestionsTool()},
        scripts: [script('find_questions', 'scripts/slow.mjs', [])],
        files: {
          'scripts/slow.mjs': 'setTimeout(() => {}, 60000);\n',
        },
      );
      if (!nodeAvailable) {
        markTestSkipped('node is not on PATH: this machine cannot run skill scripts');
        return;
      }

      final skill = await installed('demo-skill');
      final started = DateTime.now();
      final outcome = await runner.run(
        skill: skill,
        declaration: declaration(skill, 'find_questions'),
        script: skill.manifest.scripts.single,
        arguments: const {},
        timeoutSeconds: 1,
      ) as SkillScriptOutcome;

      expect(outcome.ok, isFalse);
      expect(outcome.timedOut, isTrue);
      expect(outcome.exitCode, isNull, reason: 'the process never exited on its own');
      expect(outcome.summary, contains('超过 1 秒'));
      expect(DateTime.now().difference(started).inSeconds, lessThan(30),
          reason: 'a 1 s timeout must not wait for the script');
    });

    test('a non-zero exit is a failure carrying stdout and stderr', () async {
      seedSkill(
        tools: {'find.json': findQuestionsTool()},
        scripts: [script('find_questions', 'scripts/fail.mjs', [])],
        files: {
          'scripts/fail.mjs':
              "console.log('部分结果');\nconsole.error('出错了：账号未登录');\nprocess.exit(3);\n",
        },
      );
      if (!nodeAvailable) {
        markTestSkipped('node is not on PATH: this machine cannot run skill scripts');
        return;
      }

      final skill = await installed('demo-skill');
      final outcome = await runner.run(
        skill: skill,
        declaration: declaration(skill, 'find_questions'),
        script: skill.manifest.scripts.single,
        arguments: const {},
      ) as SkillScriptOutcome;

      expect(outcome.ok, isFalse);
      expect(outcome.exitCode, 3);
      expect(outcome.stdout, contains('部分结果'));
      expect(outcome.stderr, contains('账号未登录'));
      expect(outcome.summary, contains('3'));
    });

    test('a value with a space arrives as one argument', () async {
      seedSkill(
        tools: {'find.json': findQuestionsTool()},
        scripts: [
          script('find_questions', 'scripts/argv.mjs', ['--subject', '--count']),
        ],
        files: {
          // `process.argv` is the only witness that can prove the boundary: a
          // value that had been re-split by a shell would show up as two
          // elements here.
          'scripts/argv.mjs':
              'console.log(JSON.stringify(process.argv.slice(2)));\n',
        },
      );
      if (!nodeAvailable) {
        markTestSkipped('node is not on PATH: this machine cannot run skill scripts');
        return;
      }

      final skill = await installed('demo-skill');
      final outcome = await runner.run(
        skill: skill,
        declaration: declaration(skill, 'find_questions'),
        script: skill.manifest.scripts.single,
        arguments: {'subject': '物理 力学 (必修一)', 'count': 5},
      ) as SkillScriptOutcome;

      expect(outcome.ok, isTrue, reason: outcome.stderr);
      // Arguments are emitted in a deterministic order (sorted by parameter
      // name), so the command line a skill receives does not depend on the
      // order the model happened to serialise its JSON object in.
      expect(jsonDecode(outcome.stdout.trim()),
          ['--count', '5', '--subject', '物理 力学 (必修一)']);
    });

    test('a missing script entry in scripts[] is refused, not run', () async {
      // The tool is declared but the manifest has no matching scripts[] entry.
      seedSkill(
        tools: {'find.json': findQuestionsTool()},
      );
      final skill = await installed('demo-skill');
      final refusal = await runner.run(
        skill: skill,
        declaration: declaration(skill, 'find_questions'),
        script: null,
        arguments: const {},
      );
      expect(refusal, isA<SkillRunRefusal>());
      expect((refusal as SkillRunRefusal).reason, contains('scripts[]'));
    });

    test('a script file that is not on disk is reported, not thrown', () async {
      // The installed file was removed or renamed by hand after install. The
      // rule this covers is "no exception escapes to the loop": the call has to
      // come back as a readable sentence either way.
      seedSkill(
        tools: {'find.json': findQuestionsTool()},
        scripts: [script('find_questions', 'scripts/deleted.mjs', [])],
      );
      final skill = await installed('demo-skill');
      final outcome = await runner.run(
        skill: skill,
        declaration: declaration(skill, 'find_questions'),
        script: skill.manifest.scripts.single,
        arguments: const {},
      ) as SkillScriptOutcome;

      expect(outcome.ok, isFalse);
      expect(outcome.summary, contains('scripts/deleted.mjs'));
      expect(outcome.summary, contains('不存在'));
    });
  });

  group('consent and host capabilities', () {
    test('a network skill is refused before consent and runs after it (real install)',
        () async {
      // A real install through the store, so the consent flag is exercised
      // against the archive format rather than a hand-written state file.
      final installedResult = await store.install(buildSkillArchive(
        manifestJson: skillManifestJson(
          name: 'net-skill',
          networkAllow: const ['zujuan.xkw.com'],
          permissions: const [],
          scripts: const [
            {'name': 'find_questions', 'entry': 'scripts/find.mjs', 'args': []},
          ],
        ),
        tools: {'find.json': findQuestionsTool()},
        scripts: {
          'scripts/find.mjs': 'console.log(JSON.stringify({ok: true}));\n',
        },
      ));
      expect(installedResult.failure, isNull);

      final beforeConsent = await installed('net-skill');
      expect(beforeConsent.networkAllowed, isFalse,
          reason: 'a fresh install has never been shown the domain list');
      expect(beforeConsent.manifest.networkAllow, ['zujuan.xkw.com']);

      final refused = await runner.run(
        skill: beforeConsent,
        declaration: declaration(beforeConsent, 'find_questions'),
        script: beforeConsent.manifest.scripts.single,
        arguments: const {},
      );
      expect(refused, isA<SkillRunRefusal>());
      expect((refused as SkillRunRefusal).reason, contains('zujuan.xkw.com'),
          reason: 'the refusal has to name what the user would be allowing');

      expect(await store.setNetworkAllowed('net-skill', true), isTrue);

      // A restart is a new store over the same directory, which is what makes
      // this "persisted" rather than "remembered in the instance".
      final restarted = SkillStore(supportDirectory: () async => home);
      final afterConsent =
          (await restarted.list()).firstWhere((s) => s.name == 'net-skill');
      expect(afterConsent.networkAllowed, isTrue);

      if (!nodeAvailable) {
        markTestSkipped('node is not on PATH: this machine cannot run skill scripts');
        return;
      }
      final outcome = await const SkillRunner().run(
        skill: afterConsent,
        declaration: declaration(afterConsent, 'find_questions'),
        script: afterConsent.manifest.scripts.single,
        arguments: const {},
      );
      expect(outcome, isA<SkillScriptOutcome>());
      expect((outcome as SkillScriptOutcome).ok, isTrue, reason: outcome.stderr);
    });

    test('the enable flag and network consent do not overwrite each other',
        () async {
      await store.install(buildSkillArchive(
        manifestJson: skillManifestJson(
          name: 'net-skill',
          networkAllow: const ['example.com'],
        ),
      ));
      await store.setNetworkAllowed('net-skill', true);
      await store.setEnabled('net-skill', false);

      final skill = (await SkillStore(supportDirectory: () async => home)
              .list())
          .single;
      expect(skill.enabled, isFalse);
      expect(skill.networkAllowed, isTrue,
          reason: 'two independent facts share one state file');
    });

    test('an older state.json without the field reads as "not allowed"', () async {
      seedSkill(name: 'old-skill', networkAllow: const ['example.com']);
      // Exactly the file a pre-consent version of the app wrote.
      File(p.join(skillDir('old-skill').path, SkillStore.stateFileName))
          .writeAsStringSync(jsonEncode({
        'enabled': true,
        'installedAt': DateTime.utc(2026, 1, 1).toIso8601String(),
      }));

      final skill = await installed('old-skill');
      expect(skill.networkAllowed, isFalse);
    });

    test('a skill with no declared domains is not asked for consent', () async {
      seedSkill(
        networkAllow: const [],
        tools: {'find.json': findQuestionsTool()},
        scripts: [
          script('find_questions', 'scripts/find.mjs', ['--subject', '--count']),
        ],
        files: {'scripts/find.mjs': "console.log('ok');\n"},
      );
      if (!nodeAvailable) {
        markTestSkipped('node is not on PATH: this machine cannot run skill scripts');
        return;
      }
      final skill = await installed('demo-skill');
      final outcome = await runner.run(
        skill: skill,
        declaration: declaration(skill, 'find_questions'),
        script: skill.manifest.scripts.single,
        arguments: const {},
      );
      expect((outcome as SkillScriptOutcome).ok, isTrue,
          reason: 'no declared network means no consent to ask for');
    });

    test('browser_bridge is refused, and the message names the capability',
        () async {
      seedSkill(
        permissions: const ['browser_bridge'],
        tools: {'find.json': findQuestionsTool()},
        scripts: [script('find_questions', 'scripts/find.mjs', [])],
        files: {'scripts/find.mjs': "console.log('never runs');\n"},
      );

      final skill = await installed('demo-skill');
      final tool = skillToolFor(skill, runner);
      final result = await tool.run(ToolInvocation(
        toolName: tool.name,
        action: 'find_questions',
        arguments: const {},
      ));

      expect(result.ok, isFalse);
      expect(result.error, contains('browser_bridge'));
      expect(result.error, contains('不提供'));
      // Refused, not run: the script would have printed 'never runs' if the
      // container had decided to ignore the unsupported capability.
      expect(result.error, isNot(contains('never runs')));
    });

    test('a provided capability is not a refusal', () async {
      seedSkill(
        permissions: const ['filesystem_write'],
        tools: {'find.json': findQuestionsTool()},
        scripts: [script('find_questions', 'scripts/find.mjs', [])],
        files: {'scripts/find.mjs': "console.log('ok');\n"},
      );
      final skill = await installed('demo-skill');
      expect(SkillRunner.unsupportedCapabilities(skill), isEmpty);
    });
  });

  group('what the model is handed', () {
    test('a refusal is a readable failure, not a thrown exception', () async {
      seedSkill(
        tools: {'find.json': findQuestionsTool()},
        scripts: [
          script('find_questions', 'scripts/find.mjs', ['--subject', '--count']),
        ],
        files: {'scripts/find.mjs': "console.log('ok');\n"},
      );
      final skill = await installed('demo-skill');
      final tool = skillToolFor(skill, runner);

      final result = await tool.run(const ToolInvocation(
        toolName: 'demo-skill_find_questions',
        action: 'find_questions',
        arguments: {'undeclared': 'x'},
      ));

      // The container refuses a parameter no flag was declared for, and the
      // model is told which one - actionable, and without a process ever
      // starting.
      expect(result.ok, isFalse);
      expect(result.error, contains('undeclared'));
      expect(result.error, contains('已拒绝'));
    });
  });
}

/// The runtime tool for one declaration, built the way the agent loop builds it.
///
/// Imported from the app rather than re-implemented: if the loop's construction
/// and the tests' construction could differ, the tests would be proving
/// something about a tool nobody runs.
SkillTool skillToolFor(InstalledSkill skill, SkillRunner runner) =>
    declareSkillTools(
      skill: skill,
      runner: runner,
      platform: SkillPlatform.windows,
    ).single;
