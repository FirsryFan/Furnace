/// One declared skill tool, as a real [AiTool].
///
/// docs/SKILL_FORMAT.md §6 is the rule this file exists to satisfy: a skill tool
/// is **isomorphic** to a built-in tool - same registry shape, same risk levels,
/// same approval engine, same audit ledger. It is therefore an ordinary
/// [AiTool]; the only thing that makes it a "skill" tool is that its `run` hands
/// the call to the script container instead of to a repository.
///
/// Two properties are fixed rather than read from the declaration:
///
///  * [riskFor] is always [ToolRisk.write]. A `destructive` declaration makes
///    the whole package uninstallable (spec §5.1 rule 1), and a skill may not
///    quietly act as one.
///  * [reversibleFor] is always `false`. A script may have touched something
///    outside the app, so there is no before-snapshot that could undo it. That
///    pairing - write + not reversible - is what routes every call through the
///    approval engine's `individualApproval` in both permission modes, without
///    a second gate of our own (spec §5.1 rule 2, §6).
library;

import '../../data/skill/skill_runner.dart';
import '../../data/skill/skill_store.dart';
import '../../features/ai/domain/ai_tool.dart';
import 'skill_manifest.dart';

/// The provider-facing name of one skill tool: `<skill-name>_<tool-name>`.
///
/// The provider sees one flat namespace, so the skill has to be part of the
/// name or two skills declaring `find_questions` would collide. Every character
/// outside `[a-zA-Z0-9_-]` is replaced rather than rejected: the input patterns
/// already forbid anything else (skill names are `^[a-z0-9][a-z0-9-]{0,63}$`,
/// tool names are the stricter of the two), so this is a belt-and-braces
/// normalisation for names that reach the model through an older package, not a
/// licence to accept a hostile one.
///
/// The result is also the name recorded in `ai_actions.tool_name`, which is what
/// makes the ledger's answer to "which skill did the model run?" a lookup rather
/// than a guess: the same `skill_tool` pair is recoverable from the name because
/// both halves come from patterns that cannot contain an underscore-free
/// ambiguity (the skill name has no underscore at all).
String skillToolName(String skillName, String toolName) {
  final raw = '${skillName}_$toolName';
  return raw.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
}

/// One tool a skill declares, wired to the container.
///
/// The [script] may be `null` when the skill declares a tool but no matching
/// `scripts[]` entry. The declaration survives (the card still lists it) and
/// [availableOnCurrentPlatform] is unchanged, because absence of a script is not
/// a statement about platforms; the call itself is refused with a readable
/// reason instead. That is the same treatment a missing `node` gets: a script
/// that cannot run is reported, never silently ignored.
class SkillTool extends AiTool {
  SkillTool({
    required this.skill,
    required this.declaration,
    required this.script,
    this.runner = const SkillRunner(),
    SkillPlatform? platform,
  }) : platform = platform ?? SkillPlatform.current;

  /// The installed skill this tool belongs to, as it was read this turn. A
  /// fresh copy per turn is what makes disabling a skill take effect on the very
  /// next message: the old object is never reused.
  final InstalledSkill skill;

  /// The `tools/*.json` declaration, whose `description` and `parameters` are
  /// passed to the provider untouched.
  final SkillToolDeclaration declaration;

  /// The `manifest.json` `scripts[]` entry whose name matches
  /// [SkillToolDeclaration.name], or `null` when there is none.
  final SkillScriptDeclaration? script;

  final SkillRunner runner;

  /// The platform this tool is being offered on.
  ///
  /// Injected rather than read from `dart:io` at each use, for the same reason
  /// `SkillPlatform.current` is the only accessor that touches the platform:
  /// gating has to be testable for Android without an Android device.
  final SkillPlatform platform;

  @override
  String get name => skillToolName(skill.name, declaration.name);

  /// The declared description, plus one line naming the container's own
  /// limits.
  ///
  /// The addition is the "stable mapping back to the script" the model needs
  /// (spec §3): it says which skill and script a call will run, and that the
  /// process is one-shot, so a model does not try to use it as a shell.
  @override
  String get description {
    final entry = script?.entry;
    final target = entry == null
        ? '这个工具没有对应的 scripts[] 条目，调用会被拒绝'
        : '调用会在 skill「${skill.name}」的私有目录里运行一次 $entry'
            '（一次性子进程：没有 shell、不能持续交互、不接受未声明的参数）';
    return '${declaration.description}\n$target';
  }

  @override
  Map<String, Object?> get parameters => declaration.parameters;

  /// A skill tool is a change to the world outside the app, never a read.
  @override
  ToolRisk riskFor(String action) => ToolRisk.write;

  /// Never reversible: a script's side effects are outside the app's control,
  /// so there is no snapshot to restore (spec §5.1 rule 2).
  @override
  bool reversibleFor(String action) => false;

  /// Permission to run scripts at all, plus the package's own platform
  /// declaration.
  ///
  /// Two independent answers have to agree: this process must be Windows (there
  /// is no Node runtime on Android) and the package must have declared
  /// `windows`. The install-time check already refused a package that does not
  /// declare this platform, so the second half is a re-check against a package
  /// that may have been edited on disk since - and it is stated here rather than
  /// assumed, because "the tool is absent" is the entire §5.5 defence.
  @override
  bool get availableOnCurrentPlatform =>
      platform == SkillPlatform.windows && skill.manifest.supports(platform);

  /// A skill tool has no `action` dimension; the risk is per tool.
  @override
  String actionOf(Map<String, Object?> arguments) => declaration.name;

  @override
  Future<ToolResult> run(ToolInvocation invocation) async {
    final outcome = await runner.run(
      skill: skill,
      declaration: declaration,
      script: script,
      arguments: invocation.arguments,
    );

    if (outcome is SkillRunRefusal) {
      // A refusal is a normal tool failure with a reason the model can read and
      // act on (turn on the switch, stop asking for a capability this app does
      // not have). It is deliberately not an exception: the conversation must
      // continue.
      return ToolResult.failure(outcome.reason);
    }
    final executed = outcome as SkillScriptOutcome;
    if (!executed.ok) {
      return ToolResult.failure(executed.summary);
    }
    return ToolResult(
      ok: true,
      summary: executed.summary,
      modelResult: _modelPayload(executed),
    );
  }

  /// The structured facts the model needs, with the text capped.
  ///
  /// Two separate bounds, on purpose:
  ///
  ///  * the process output is capped by the container at
  ///    [SkillRunner.outputCapBytes]; whatever survives is what this sees;
  ///  * the text handed to the model is capped again here at
  ///    [SkillRunner.modelResultCapBytes], with an explicit marker.
  ///
  /// [SkillScriptOutcome.stdout]/`stderr` carry the full (container-capped)
  /// text so the ledger and the UI can show it; `result.stdout`/`result.stderr`
  /// carry what the model reads. The flags the model needs - exit code, whether
  /// it was truncated, whether it timed out - sit at the top level rather than
  /// having to be inferred from the text.
  Object _modelPayload(SkillScriptOutcome outcome) {
    return {
      'skill': skill.name,
      'script': script?.entry,
      'exit_code': outcome.exitCode,
      'timed_out': outcome.timedOut,
      'truncated': outcome.truncated,
      'stdout': _capForModel(outcome.stdout),
      'stderr': _capForModel(outcome.stderr),
    };
  }

  /// Truncates [text] to [SkillRunner.modelResultCapBytes] and says so.
  ///
  /// The marker is a suffix rather than a replacement: a model that sees the
  /// beginning of a valid JSON document *and* a note that it was cut knows to
  /// ask for less next time, while a model that sees only "truncated" cannot
  /// tell whether the call did anything.
  static String _capForModel(String text) {
    if (text.length <= SkillRunner.modelResultCapBytes) {
      return text;
    }
    return '${text.substring(0, SkillRunner.modelResultCapBytes)}'
        '…[output truncated at ${SkillRunner.modelResultCapBytes} characters]';
  }
}
