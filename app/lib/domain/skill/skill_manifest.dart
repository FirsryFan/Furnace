/// The `.fskill` skill-package model.
///
/// The format is frozen in docs/SKILL_FORMAT.md; this file is the typed form of
/// its `manifest.json` (§2.1) plus the per-tool declarations of `tools/*.json`.
///
/// **Nothing here executes anything.** Installing a skill unpacks files onto
/// disk, and an enabled skill contributes its `prompt.md` (plus its
/// `references/**`) to the model's system prompt. Running a declared script is
/// `SkillRunner`'s job (`data/skill/skill_runner.dart`, the §3 container), and it
/// only ever happens after the call has been confirmed by the user.
library;

import 'dart:io';

/// A platform a skill may declare support for (spec §5.5 / AI_DESIGN D10).
///
/// Android has no Node runtime and no desktop browser, so a script-backed skill
/// declaring `windows` is refused on Android **at install time**. That is the
/// whole point of gating declaratively: a package that cannot work here never
/// reaches the installed list, instead of appearing to work and failing later.
enum SkillPlatform {
  windows('windows'),
  macos('macos'),
  linux('linux'),
  android('android'),
  ios('ios');

  const SkillPlatform(this.id);

  /// Stable value used inside `manifest.json`. Never localised.
  final String id;

  static SkillPlatform? fromId(String id) {
    for (final platform in SkillPlatform.values) {
      if (platform.id == id) {
        return platform;
      }
    }
    return null;
  }

  /// The platform this process is running on.
  ///
  /// Only this one accessor touches `dart:io`, and callers that need a
  /// *decision* take the platform as a parameter instead (see
  /// `SkillPackage.validate` and `SkillStore`). That keeps the gating rule
  /// testable for both windows and android without a device.
  static SkillPlatform get current {
    if (Platform.isWindows) {
      return SkillPlatform.windows;
    }
    if (Platform.isMacOS) {
      return SkillPlatform.macos;
    }
    if (Platform.isLinux) {
      return SkillPlatform.linux;
    }
    if (Platform.isIOS) {
      return SkillPlatform.ios;
    }
    return SkillPlatform.android;
  }
}

/// One entry of `manifest.json`'s `scripts[]`: a declared script and the
/// arguments the container would be allowed to pass it.
///
/// Parsing these is not permission to run them. They are validated (the entry
/// must exist inside the package and must not point outside it) and listed in
/// the settings card, and that is all - see [SkillToolDeclaration].
class SkillScriptDeclaration {
  const SkillScriptDeclaration({
    required this.name,
    required this.entry,
    this.args = const [],
  });

  /// Matches one tool name in `tools/*.json`.
  final String name;

  /// Package-relative path, e.g. `scripts/find.mjs`.
  final String entry;

  /// Declarative argument names, e.g. `['--subject', '--count']`.
  final List<String> args;

  Map<String, dynamic> toJson() => {
        'name': name,
        'entry': entry,
        'args': args,
      };

  /// Throws [FormatException] when a field has the wrong shape.
  ///
  /// Shape only: whether the script actually exists, and whether `entry`
  /// stays inside the package, is decided against the archive's file list.
  factory SkillScriptDeclaration.fromJson(Map<String, dynamic> json) {
    final name = json['name'];
    if (name is! String || name.trim().isEmpty) {
      throw const FormatException('scripts[] 缺少 name');
    }
    final entry = json['entry'];
    if (entry is! String || entry.trim().isEmpty) {
      throw const FormatException('scripts[] 缺少 entry');
    }
    final rawArgs = json['args'];
    return SkillScriptDeclaration(
      name: name.trim(),
      entry: entry.trim(),
      args: [
        if (rawArgs is List)
          for (final arg in rawArgs)
            if (arg != null) arg.toString(),
      ],
    );
  }
}

/// One `tools/*.json` declaration: what the skill would expose to the model.
///
/// The shape is deliberately identical to a built-in tool's (`name` /
/// `description` / `parameters`) so that the approval engine and the audit
/// ledger need no second code path (AI_DESIGN D11). That is what lets an enabled
/// skill's declaration become a callable `SkillTool` on the turn it is enabled,
/// judged by the same engine as everything else - and it is why a declaration
/// with `risk: destructive` is refused: the container has no delete semantics to
/// hand it.
class SkillToolDeclaration {
  const SkillToolDeclaration({
    required this.name,
    required this.description,
    required this.parameters,
    required this.risk,
    required this.reversible,
    required this.source,
  });

  final String name;
  final String description;

  /// The JSON Schema object, kept as decoded JSON.
  final Map<String, Object?> parameters;

  /// `write` or `destructive`. A `destructive` declaration makes the whole
  /// package unloadable (spec §5.1), so an installed skill never carries one.
  final String risk;

  /// Whether the declaration claims the call can be undone. Defaults to false:
  /// a script may touch things outside the app, and the spec refuses to assume
  /// it can be rolled back (spec §5.1 rule 2, AI_DESIGN D13b).
  final bool reversible;

  /// File inside the package this declaration came from, so a validation error
  /// can name it.
  final String source;

  Map<String, dynamic> toJson() => {
        'name': name,
        'description': description,
        'parameters': parameters,
        'risk': risk,
        'reversible': reversible,
      };

  factory SkillToolDeclaration.fromJson(
    Map<String, dynamic> json, {
    required String source,
  }) {
    final name = json['name'];
    if (name is! String || name.trim().isEmpty) {
      throw FormatException('$source 缺少 name');
    }
    final description = json['description'];
    if (description is! String || description.trim().isEmpty) {
      throw FormatException('$source 缺少 description');
    }
    final parameters = json['parameters'];
    if (parameters is! Map) {
      throw FormatException('$source 缺少 parameters');
    }
    return SkillToolDeclaration(
      name: name.trim(),
      description: description.trim(),
      parameters: parameters.cast<String, Object?>(),
      risk: json['risk'] is String ? json['risk'] as String : 'write',
      reversible: json['reversible'] == true,
      source: source,
    );
  }
}

/// A decoded `manifest.json`.
///
/// [fromJson] is intentionally strict about the fields the security rules rest
/// on (`format`, `name`, `platforms`) and lenient about presentation-only ones
/// (`description`, `version`), because a missing description is a cosmetic
/// problem while a missing platform list would silently mean "runs anywhere".
class SkillManifest {
  const SkillManifest({
    required this.format,
    required this.name,
    required this.version,
    required this.description,
    required this.platforms,
    this.networkAllow = const [],
    this.permissions = const [],
    this.scripts = const [],
  });

  /// The protocol number. Only `fskill/1` is understood; a mismatch is a
  /// refusal, never a best-effort reinterpretation (spec §5.4).
  static const String currentFormat = 'fskill/1';

  /// Legal skill names: lower case, digits and hyphens, 1-64 characters, and
  /// never starting with a hyphen. The name becomes a directory name under the
  /// app support directory, so the pattern is also what keeps a hostile name
  /// from escaping that directory.
  static final RegExp namePattern = RegExp(r'^[a-z0-9][a-z0-9-]{0,63}$');

  /// Legal tool names.
  ///
  /// Separate from [namePattern] and slightly looser: an underscore is allowed
  /// because the spec's own example declares `find_questions` (§2.1), while the
  /// skill pattern forbids it because a skill name is also a directory name.
  /// A tool name is a protocol identifier, so what it needs is "safe as a JSON
  /// key and as a `tools/*.json` `name`", not "safe as a path segment".
  static final RegExp toolNamePattern = RegExp(r'^[a-z0-9][a-z0-9_-]{0,63}$');

  final String format;
  final String name;
  final String version;
  final String description;

  /// Non-empty by contract: a skill that declares nothing is refused, because
  /// "no platform list" would otherwise have to be read as "every platform".
  final List<SkillPlatform> platforms;

  /// Hostnames the skill's scripts are allowed to reach. Empty means no network
  /// at all (spec §2.1). The container refuses to run a networked skill until the
  /// user has allowed it ([InstalledSkill.networkAllowed]); the list is what the
  /// user was shown when they allowed it, **not** an OS-level egress rule - see
  /// the honesty note in `skill_runner.dart`.
  final List<String> networkAllow;

  /// Host capabilities requested, e.g. `browser_bridge`. Unrequested
  /// capabilities are ones the container would not hand over (spec §4).
  final List<String> permissions;

  final List<SkillScriptDeclaration> scripts;

  /// True when the skill declares support for [platform].
  bool supports(SkillPlatform platform) => platforms.contains(platform);

  Map<String, dynamic> toJson() => {
        'format': format,
        'name': name,
        'version': version,
        'description': description,
        'platforms': [for (final platform in platforms) platform.id],
        'networkAllow': networkAllow,
        'permissions': permissions,
        'scripts': [for (final script in scripts) script.toJson()],
      };

  /// Decodes a manifest.
  ///
  /// Throws [FormatException] when a required field is absent or has the wrong
  /// type. It does **not** decide whether the package may be installed - the
  /// protocol check and the platform check live in the validator, so that every
  /// refusal has one place and one message.
  factory SkillManifest.fromJson(Map<String, dynamic> json) {
    final format = json['format'];
    if (format is! String || format.trim().isEmpty) {
      throw const FormatException('manifest.json 缺少 format');
    }

    final name = json['name'];
    if (name is! String) {
      throw const FormatException('manifest.json 缺少 name');
    }

    // A missing platform list is *not* defaulted to "all platforms": that
    // default would quietly defeat the gating rule for exactly the packages
    // that forgot to declare it.
    final rawPlatforms = json['platforms'];
    if (rawPlatforms is! List || rawPlatforms.isEmpty) {
      throw const FormatException('manifest.json 的 platforms 必须是非空数组');
    }
    final platforms = <SkillPlatform>[];
    for (final raw in rawPlatforms) {
      final platform = SkillPlatform.fromId(raw.toString().trim());
      if (platform == null) {
        throw FormatException('manifest.json 里有未知平台「$raw」');
      }
      if (!platforms.contains(platform)) {
        platforms.add(platform);
      }
    }

    return SkillManifest(
      format: format.trim(),
      name: name.trim(),
      version: json['version'] is String ? (json['version'] as String).trim() : '',
      description:
          json['description'] is String ? (json['description'] as String).trim() : '',
      platforms: platforms,
      networkAllow: _stringList(json['networkAllow']),
      permissions: _stringList(json['permissions']),
      scripts: _scripts(json['scripts']),
    );
  }

  static List<String> _stringList(Object? raw) => [
        if (raw is List)
          for (final item in raw)
            if (item != null && item.toString().trim().isNotEmpty)
              item.toString().trim(),
      ];

  static List<SkillScriptDeclaration> _scripts(Object? raw) {
    if (raw == null) {
      return const [];
    }
    if (raw is! List) {
      throw const FormatException('manifest.json 的 scripts 必须是数组');
    }
    final scripts = <SkillScriptDeclaration>[];
    for (final item in raw) {
      if (item is! Map) {
        throw const FormatException('manifest.json 的 scripts[] 必须是对象');
      }
      scripts.add(SkillScriptDeclaration.fromJson(item.cast<String, dynamic>()));
    }
    return scripts;
  }
}
