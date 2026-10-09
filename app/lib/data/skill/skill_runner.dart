/// The skill script container of docs/SKILL_FORMAT.md §3.
///
/// This is the only place in the app that starts a process on behalf of a
/// `.fskill`. Every rule in §3 exists to make "the AI may run a third-party
/// script" a bounded decision rather than an open shell, and each one is
/// implemented here:
///
/// | rule | implementation |
/// | --- | --- |
/// | one child per call, never resident | [run] starts, waits and returns |
/// | `cwd` is the skill's private directory | [run], `workingDirectory` |
/// | minimal environment, never the parent's | [environmentFor] |
/// | never inject the API key | the whitelist is a fixed list, not a filter |
/// | timeout | [defaultTimeoutSeconds], [maxTimeoutSeconds], [_killTree] |
/// | output cap | [outputCapBytes], [modelResultCapBytes] |
/// | audit | outside: the call goes through the agent loop's tool path |
///
/// **Windows only, by absence.** There is no platform check in this file; the
/// gate is one line earlier, in `SkillTool.availableOnCurrentPlatform`. A
/// platform that cannot run scripts therefore never sees the tool at all
/// (spec §5.5: absent, not failing at call time), and nothing here has to
/// pretend to be a runtime Android does not have.
///
/// Two limitations are stated as plainly here as the protections, because a
/// container that overstates itself is worse than one that does less:
///
///  * **The declared domains are not enforced.** `networkAllow` is what the
///    user was shown when they consented, and consent is recorded per skill in
///    `state.json`; nothing in this file stops a script from reaching another
///    host. Confinement here is *by declaration*, not by a sandbox. A real
///    boundary needs OS-level egress control (a firewall rule, a container, or
///    a proxy the script cannot bypass), which this app does not have.
///  * **The environment whitelist is not a security boundary either.** It
///    removes the app's own secrets from the child's reach (the model API key
///    lives in the database and is never placed in the environment in the first
///    place); it cannot stop a script from reading files the user's account can
///    read, which the spec's §3 "file read/write" row also leaves to the
///    skill's own honour.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
// `BytesBuilder` rather than `dart:io`'s re-export of it: the analyzer flags the
// indirect import, and the direct one is what the type actually belongs to.
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../../domain/skill/skill_manifest.dart';
import '../../features/ai/domain/ai_tool.dart';
import 'skill_store.dart';

/// What one script execution produced.
///
/// Deliberately a value rather than an exception: a script that times out, exits
/// non-zero or cannot even be started is an *outcome the model must read*, not a
/// crash in the conversation. [run] therefore never throws for a script-level
/// problem.
class SkillScriptOutcome {
  const SkillScriptOutcome({
    required this.ok,
    required this.summary,
    this.exitCode,
    this.stdout = '',
    this.stderr = '',
    this.timedOut = false,
    this.truncated = false,
    this.timeoutSeconds = 0,
  });

  final bool ok;

  /// One line for the user, in the conversation's own language.
  final String summary;

  /// `null` when the process never exited (timeout, or it could not be started).
  final int? exitCode;

  final String stdout;
  final String stderr;

  /// The process was killed by the container's own timeout.
  final bool timedOut;

  /// Combined output hit [SkillRunner.outputCapBytes] and was cut.
  final bool truncated;

  /// The timeout in force for this call, so a failure can name the number the
  /// user configured rather than a constant that may have been overridden.
  final int timeoutSeconds;

  Map<String, Object?> toJson() => {
        'ok': ok,
        'summary': summary,
        if (exitCode != null) 'exit_code': exitCode,
        'stdout': stdout,
        'stderr': stderr,
        'timed_out': timedOut,
        'truncated': truncated,
        if (!ok) 'timeout_seconds': timeoutSeconds,
      };
}

/// A skill that cannot run, and the one sentence that says why.
///
/// Returned instead of starting a process, so the caller can hand the model a
/// readable refusal. The reasons are exactly the ones the spec makes
/// non-negotiable: a host capability the container does not provide (§4) and
/// network use the user has not consented to (§3, §5.3).
class SkillRunRefusal {
  const SkillRunRefusal(this.reason);

  final String reason;

  @override
  String toString() => reason;
}

/// The script container. One instance serves every skill.
///
/// The instance carries no state about platforms or consent: those live in the
/// skill itself ([InstalledSkill.networkAllowed]) and on the tool wrapper that
/// decides whether it may be offered at all (`SkillTool`). That keeps this class
/// to one job - start a process, bound it, report what happened.
class SkillRunner {
  const SkillRunner();

  /// The executable used to run script entries.
  ///
  /// A bare name on purpose: the container does **not** resolve it itself, so
  /// `node` is found the same way every other program on the machine is found -
  /// through `PATH`. When it is missing the spawn fails and the call reports
  /// that fact (see [run]); nothing is installed or downloaded to paper over it.
  static const String nodeExecutable = 'node';

  /// The environment variables a script may see.
  ///
  /// This is a **fixed list, not a filter**: the parent environment is never
  /// copied and then pruned, because a filter has to enumerate what to remove
  /// and gets that wrong the moment a new secret is introduced. A list gets it
  /// wrong the other way - a new secret is absent by default - which is the
  /// failure mode that is safe.
  ///
  /// The entries are the minimum Windows and Node need to start at all
  /// (`PATH` to find `node` and any system DLL it loads, `SystemRoot`/`windir`
  /// for the system directory, `TEMP`/`TMP` for temp files, `PATHEXT` for
  /// executable resolution, `ComSpec` for a shell, `NUMBER_OF_PROCESSORS` for
  /// Node's thread pool sizing).
  static const List<String> environmentWhitelist = [
    'PATH',
    'SystemRoot',
    'windir',
    'TEMP',
    'TMP',
    'PATHEXT',
    'ComSpec',
    'NUMBER_OF_PROCESSORS',
  ];

  /// How long a script may run when the caller does not say otherwise.
  static const int defaultTimeoutSeconds = 60;

  /// The ceiling on any request. A caller may ask for less, never for more.
  static const int maxTimeoutSeconds = 300;

  /// Cap on *combined* stdout + stderr held in memory, 256 KB.
  static const int outputCapBytes = 256 * 1024;

  /// Cap on the text handed to the model, 8 KB. The model reads a summary of a
  /// script's output, not a data channel; anything larger has to go through a
  /// file the user asked for.
  static const int modelResultCapBytes = 8 * 1024;

  /// Host capabilities the container actually provides (spec §4).
  ///
  /// Only `filesystem_write`, and only in the spec's own sense: a script may
  /// write inside its private directory and wherever the user pointed it during
  /// that call. `browser_bridge` is deliberately **not** here - reusing the
  /// user's logged-in desktop browser is a capability this app does not offer,
  /// and a skill that asks for it is refused by name rather than run with the
  /// capability silently missing.
  static const Set<String> providedCapabilities = {'filesystem_write'};

  /// The requested capabilities that [providedCapabilities] does not cover.
  static List<String> unsupportedCapabilities(InstalledSkill skill) => [
        for (final permission in skill.manifest.permissions)
          if (!providedCapabilities.contains(permission)) permission,
      ];

  /// The environment handed to a child process: [environmentWhitelist] taken
  /// from the current process, and nothing else.
  ///
  /// `includeParentEnvironment: false` at the spawn site plus this map is the
  /// whole mechanism. There is no code path that passes the parent map through.
  static Map<String, String> environmentFor(Map<String, String> parent) {
    final env = <String, String>{};
    for (final name in environmentWhitelist) {
      final value = parent[name];
      if (value != null) {
        env[name] = value;
      }
    }
    return env;
  }

  /// Builds the command line for one call, or explains why it cannot be built.
  ///
  /// [declaredFlags] maps a **tool parameter name** to the command-line flag
  /// that carries it, e.g. `{'subject': '--subject'}`. The names on the left are
  /// the schema's property names; the flags on the right are what
  /// `manifest.json`'s `scripts[].args` declared. Which flag a parameter
  /// becomes is the package author's choice; that only declared ones may appear
  /// is the container's rule.
  ///
  /// The mapping is **two-way** (§2.1): a parameter with no declared flag is
  /// refused, and a declared flag the schema does not describe is refused too.
  /// Without the second half the container would be reading the manifest as
  /// advisory, and a package could aim a script at an argument no tool ever
  /// described.
  ///
  /// Types decide the shape:
  ///
  ///  * string / number / boolean-typed value → `--flag value`;
  ///  * boolean `true` → a bare `--flag`; boolean `false` → the flag is omitted;
  ///  * array of strings → the flag repeated once per element.
  ///
  /// Every value is appended as its **own argv element**, so a value containing
  /// spaces or quotes cannot become a second argument: there is no shell to
  /// re-split it and no string concatenation anywhere. That is the reason this
  /// returns a list rather than a command line.
  ///
  /// Throws [ToolArgError] for either refusal, so a caller that cannot present a
  /// readable reason still cannot run anything.
  static List<String> argvFor({
    required Map<String, Object?> parameters,
    required Map<String, Object?> arguments,
    required Map<String, String> declaredFlags,
  }) {
    final properties = _schemaProperties(parameters);
    final overDeclared = [
      for (final key in declaredFlags.keys)
        if (!properties.containsKey(key)) key,
    ]..sort();
    if (overDeclared.isNotEmpty) {
      throw ToolArgError(
        '脚本声明了参数 ${overDeclared.join(', ')}，但工具的 JSON Schema 里没有描述它们，已拒绝执行',
      );
    }

    final keys = [
      for (final entry in arguments.entries)
        if (entry.value != null) entry.key,
    ]..sort();

    final argv = <String>[];
    for (final key in keys) {
      final flag = declaredFlags[key];
      if (flag == null) {
        throw ToolArgError(
          '没有声明参数 `$key`，容器不会把它变成命令行参数，已拒绝执行。'
          '已声明的参数：${_declaredLabel(declaredFlags)}',
        );
      }
      final value = arguments[key];
      if (value is List) {
        for (final element in value) {
          if (element == null) {
            continue;
          }
          if (element is bool) {
            if (element) {
              argv.add(flag);
            }
            continue;
          }
          argv
            ..add(flag)
            ..add(element.toString());
        }
        continue;
      }
      final property = properties[key];
      final declaredAsBoolean = property is Map && property['type'] == 'boolean';
      if (value is bool || declaredAsBoolean) {
        if (_asBool(value)) {
          argv.add(flag);
        }
        continue;
      }
      argv
        ..add(flag)
        ..add(value.toString());
    }
    return argv;
  }

  /// The parameter a declared flag carries.
  ///
  /// `scripts[].args` declares command-line flags (`'--subject'`, the spec's own
  /// example in §2.1), while a tool's JSON Schema names parameters (`subject`).
  /// The two are tied together by stripping the leading dashes, which is the
  /// only convention the format implies and the one a package author writing
  /// `"args": ["--subject"]` next to `"properties": {"subject": ...}` is already
  /// following. When the names do not line up, the two-way check in [argvFor]
  /// fails closed: an unmatched flag is refused rather than passed or ignored.
  static String parameterNameOf(String flag) => flag.replaceFirst(
        RegExp(r'^-{1,2}'),
        '',
      );

  static Map<String, Object?> _schemaProperties(Map<String, Object?> parameters) {
    final properties = parameters['properties'];
    if (properties is! Map) {
      return const {};
    }
    return {
      for (final entry in properties.entries) entry.key.toString(): entry.value,
    };
  }

  static String _declaredLabel(Map<String, String> declaredFlags) {
    final keys = declaredFlags.keys.toList()..sort();
    return keys.isEmpty ? '（无）' : keys.join(', ');
  }

  static bool _asBool(Object? value) {
    if (value is bool) {
      return value;
    }
    final text = value?.toString().trim().toLowerCase();
    return text == 'true' || text == '1';
  }

  /// Runs [script] of [skill] with the model's [arguments].
  ///
  /// Returns a [SkillRunRefusal] instead of an outcome when the skill may not
  /// run at all - an unsupported host capability (§4) or network use the user
  /// has not allowed (§5.3). Those are policy answers, not script failures, and
  /// the distinction is what lets the caller refuse before anything is spawned.
  ///
  /// The timeout may be lowered (tests do), never raised above
  /// [maxTimeoutSeconds].
  Future<Object> run({
    required InstalledSkill skill,
    required SkillToolDeclaration declaration,
    required SkillScriptDeclaration? script,
    required Map<String, Object?> arguments,
    int timeoutSeconds = defaultTimeoutSeconds,
  }) async {
    final unsupported = unsupportedCapabilities(skill);
    if (unsupported.isNotEmpty) {
      return SkillRunRefusal(
        '这个 skill 申请了宿主能力 ${unsupported.join('、')}，容器不提供，因此拒绝运行。'
        '申请的宿主能力在 docs/SKILL_FORMAT.md §4 里有明确定义：容器没有实现的能力'
        '不会假装提供',
      );
    }

    if (script == null) {
      return SkillRunRefusal(
        '工具「${declaration.name}」在 manifest.json 的 scripts[] 里没有对应的脚本条目，'
        '没有可以执行的东西',
      );
    }

    final domains = skill.manifest.networkAllow;
    if (domains.isNotEmpty && !skill.networkAllowed) {
      return SkillRunRefusal(
        '这个 skill 声明要联网（${domains.join('、')}），但你还没有允许它使用网络。'
        '请先在「Skill 管理」里为它打开网络开关；在此之前它的脚本不会运行',
      );
    }

    final List<String> argv;
    try {
      argv = argvFor(
        parameters: declaration.parameters,
        arguments: arguments,
        declaredFlags: {
          for (final flag in script.args) parameterNameOf(flag): flag,
        },
      );
    } on ToolArgError catch (e) {
      return SkillRunRefusal(e.message);
    }

    final timeout = timeoutSeconds.clamp(1, maxTimeoutSeconds);
    try {
      return await _execute(
        skill: skill,
        script: script,
        argv: argv,
        timeoutSeconds: timeout,
      );
    } on ProcessException catch (e) {
      // `node` not on PATH is the case a user will actually meet on a machine
      // without Node, and it has to read as a sentence rather than a stack.
      return SkillScriptOutcome(
        ok: false,
        summary: '无法运行脚本：找不到 $nodeExecutable（$e）。'
            'skill 的脚本需要本机已安装 Node.js 并在 PATH 里',
        timeoutSeconds: timeout,
      );
    } on FileSystemException catch (e) {
      return SkillScriptOutcome(
        ok: false,
        summary: '无法运行脚本：读不到 skill 脚本文件（$e）',
        timeoutSeconds: timeout,
      );
    }
  }

  Future<SkillScriptOutcome> _execute({
    required InstalledSkill skill,
    required SkillScriptDeclaration script,
    required List<String> argv,
    required int timeoutSeconds,
  }) async {
    // `entry` is validated at install time to stay inside the package, so this
    // join cannot leave the skill directory; `cwd` is that directory, which is
    // what makes relative paths inside a script behave the way its author
    // expects.
    final entryPath = p.joinAll([
      skill.directory,
      ...script.entry.replaceAll('\\', '/').split('/'),
    ]);
    if (!File(entryPath).existsSync()) {
      return SkillScriptOutcome(
        ok: false,
        summary: '脚本文件不存在：${script.entry}（skill 目录里的文件被改动过？）',
        timeoutSeconds: timeoutSeconds,
      );
    }

    final process = await Process.start(
      nodeExecutable,
      [entryPath, ...argv],
      workingDirectory: skill.directory,
      environment: environmentFor(Platform.environment),
      // The one line that keeps the model's API key out of a third-party
      // script's reach: the child gets `environment` and nothing inherited.
      includeParentEnvironment: false,
      runInShell: false,
    );

    // One byte budget shared by both pipes, because the cap in §3 is on the
    // *combined* output: two independent caps would let a script put 512 KB in
    // front of the model by writing half of it to each stream.
    final budget = _OutputBudget(outputCapBytes);
    final stdoutBytes = BytesBuilder();
    final stderrBytes = BytesBuilder();

    // Read both pipes as they arrive. Draining them is not optional: a child
    // that fills a pipe buffer blocks forever, and a timeout would then look
    // like a hang in the container instead of a killed process.
    final stdoutDone = process.stdout.listen((chunk) {
      budget.take(chunk, stdoutBytes);
    }).asFuture<void>();
    final stderrDone = process.stderr.listen((chunk) {
      budget.take(chunk, stderrBytes);
    }).asFuture<void>();

    var timedOut = false;
    final timer = Timer(Duration(seconds: timeoutSeconds), () async {
      timedOut = true;
      // §3: kill the process *tree*. Killing the wrapper alone can leave the
      // real work running, holding the skill directory and the network.
      await _killTree(process.pid);
    });

    int? exitCode;
    try {
      exitCode = await process.exitCode;
    } finally {
      timer.cancel();
      // Both streams reach EOF once the process is gone; waiting here is what
      // makes the bytes below complete rather than "whatever arrived first".
      await Future.wait([stdoutDone, stderrDone]);
    }

    final stdoutText = utf8.decode(stdoutBytes.toBytes(), allowMalformed: true);
    final stderrText = utf8.decode(stderrBytes.toBytes(), allowMalformed: true);

    return SkillScriptOutcome(
      ok: !timedOut && exitCode == 0,
      summary: _summary(
        skill,
        script,
        timedOut: timedOut,
        exitCode: timedOut ? null : exitCode,
        stdout: stdoutText,
        timeoutSeconds: timeoutSeconds,
      ),
      exitCode: timedOut ? null : exitCode,
      stdout: stdoutText,
      stderr: stderrText,
      timedOut: timedOut,
      truncated: budget.truncated,
      timeoutSeconds: timeoutSeconds,
    );
  }

  /// Kills a process and everything it started.
  ///
  /// Windows has no process group to signal, and `Process.kill` reaches only the
  /// process it was given - for `node` that is the real process, but a script
  /// that spawns a browser or a helper leaves those behind. `taskkill /T` walks
  /// the tree, which is the only thing that makes the timeout a real bound.
  /// Other platforms are handled by `Process.kill` for completeness; script
  /// execution is gated to Windows anyway.
  Future<void> _killTree(int pid) async {
    if (Platform.isWindows) {
      try {
        await Process.run(
          'taskkill',
          ['/f', '/t', '/pid', '$pid'],
          runInShell: false,
        );
        return;
      } on ProcessException {
        // Fall through to the direct kill: `taskkill` missing is not a reason
        // to leave the process running.
      }
    }
    Process.killPid(pid);
  }

  static String _summary(
    InstalledSkill skill,
    SkillScriptDeclaration script, {
    required bool timedOut,
    required int? exitCode,
    required String stdout,
    required int timeoutSeconds,
  }) {
    if (timedOut) {
      return 'skill「${skill.name}」的脚本 ${script.entry} 超过 '
          '$timeoutSeconds 秒未结束，已连同子进程一起终止';
    }
    if (exitCode != 0) {
      return 'skill「${skill.name}」的脚本 ${script.entry} 退出码 '
          '$exitCode，执行失败';
    }
    final firstLine = stdout
        .split('\n')
        .map((line) => line.trim())
        .firstWhere((line) => line.isNotEmpty, orElse: () => '');
    final head = firstLine.length > 120 ? '${firstLine.substring(0, 120)}…' : firstLine;
    return head.isEmpty
        ? 'skill「${skill.name}」的 ${script.name} 已执行（没有输出）'
        : 'skill「${skill.name}」的 ${script.name} 已执行：$head';
  }
}

/// The one byte allowance both output pipes draw from.
///
/// §3 caps the output of a call; a per-stream cap would quietly double it, so
/// the two streams share one budget. Anything past the budget is dropped, and
/// [truncated] is how the caller learns that it was.
class _OutputBudget {
  _OutputBudget(this.limit);

  final int limit;
  int _taken = 0;
  int _offered = 0;

  /// Appends as much of [chunk] as the budget still allows to [sink].
  void take(List<int> chunk, BytesBuilder sink) {
    _offered += chunk.length;
    final remaining = limit - _taken;
    if (remaining <= 0) {
      return;
    }
    final keep = chunk.length <= remaining ? chunk.length : remaining;
    _taken += keep;
    sink.add(chunk.length <= remaining ? chunk : chunk.sublist(0, keep));
  }

  /// True when more was offered than the budget held.
  bool get truncated => _offered > limit;
}
