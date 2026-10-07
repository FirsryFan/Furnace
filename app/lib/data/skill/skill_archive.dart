/// Validation for a decoded `.fskill`.
///
/// Every rule here answers one question: *may this package be installed at
/// all?* The refusals are separated from plain decoding on purpose, because
/// "why can I not install this?" has to have exactly one answer, with its own
/// code, that the settings screen shows verbatim and the tests assert on.
///
/// The rules come from docs/SKILL_FORMAT.md §5 (non-negotiable security
/// boundary) and §2.1 (manifest shape). Two of them are worth spelling out
/// because they are the ones a user will actually meet:
///
///  * **No protocol guessing** (§5.4): a `format` other than `fskill/1` is
///    refused. Interpreting a newer package as if it were an older format is
///    precisely how a security boundary breaks quietly.
///  * **Declarative platform gating** (§5.5 / AI_DESIGN D10): a package that
///    does not declare the current platform is refused *now*. The alternative -
///    installing it and failing when a script is needed - would put a skill in
///    the list that cannot work.
library;

import 'dart:convert';

import '../../domain/skill/skill_manifest.dart';
import 'skill_package_codec.dart';

/// A package that passed every rule, ready to be written to disk.
class SkillPackage {
  const SkillPackage({
    required this.manifest,
    required this.prompt,
    required this.tools,
    required this.entries,
  });

  final SkillManifest manifest;

  /// The `prompt.md` text, which is what an enabled skill contributes to the
  /// model's system prompt.
  final String prompt;

  /// The declared tools, in `tools/*.json` path order.
  final List<SkillToolDeclaration> tools;

  /// Every file to extract, keyed by package-relative path.
  final Map<String, SkillArchiveEntry> entries;
}

/// A refusal, with a stable code and a user-facing message.
class SkillValidationFailure {
  const SkillValidationFailure(this.code, this.message);

  /// Stable identifier. Tests assert this, so a rule cannot be silently
  /// reworded into a different rule.
  final String code;

  /// Why the package was refused, addressed to the user.
  final String message;

  @override
  String toString() => '[$code] $message';
}

/// Either a package or the reason it will not be installed.
class SkillValidationResult {
  const SkillValidationResult._({this.package, this.failure});

  const SkillValidationResult.valid(SkillPackage package)
      : this._(package: package);

  const SkillValidationResult.invalid(SkillValidationFailure failure)
      : this._(failure: failure);

  final SkillPackage? package;
  final SkillValidationFailure? failure;

  bool get isValid => package != null;

  /// Throws when the package was refused. Used where a failure is a
  /// programming error rather than a user-facing outcome.
  SkillPackage get requirePackage {
    final value = package;
    if (value == null) {
      throw StateError('package was refused: $failure');
    }
    return value;
  }
}

/// Applies every rule to decoded archive [entries].
///
/// [platform] is the platform the decision is made *for*, injected rather than
/// read from `dart:io` inside the rule so that both the Windows and the Android
/// answer can be tested without either device.
SkillValidationResult validateSkillPackage(
  Map<String, SkillArchiveEntry> entries, {
  required SkillPlatform platform,
}) {
  final SkillManifest manifest;
  try {
    final decoded = SkillPackageCodec.readManifest(entries);
    if (decoded == null) {
      return const SkillValidationResult.invalid(SkillValidationFailure(
        'missingManifest',
        '缺少 manifest.json，不是 skill 包',
      ));
    }
    manifest = decoded;
  } on SkillArchiveException catch (e) {
    return SkillValidationResult.invalid(SkillValidationFailure(e.code, e.message));
  }

  final manifestFailure = _checkManifest(manifest, platform);
  if (manifestFailure != null) {
    return SkillValidationResult.invalid(manifestFailure);
  }

  final prompt = SkillPackageCodec.readPrompt(entries);
  if (prompt == null) {
    // A skill with no instructions would install and then change nothing,
    // which is indistinguishable from a broken install.
    return const SkillValidationResult.invalid(SkillValidationFailure(
      'missingPrompt',
      '缺少 prompt.md，skill 至少要有一段提示词',
    ));
  }

  final entryFailure = _checkEntries(entries);
  if (entryFailure != null) {
    return SkillValidationResult.invalid(entryFailure);
  }

  final scriptFailure = _checkScripts(manifest, entries);
  if (scriptFailure != null) {
    return SkillValidationResult.invalid(scriptFailure);
  }

  final tools = _checkTools(entries);
  if (tools is SkillValidationFailure) {
    return SkillValidationResult.invalid(tools);
  }

  return SkillValidationResult.valid(SkillPackage(
    manifest: manifest,
    prompt: prompt,
    tools: tools as List<SkillToolDeclaration>,
    entries: entries,
  ));
}

/// The manifest-level rules: protocol, name, platform.
SkillValidationFailure? _checkManifest(
  SkillManifest manifest,
  SkillPlatform platform,
) {
  if (manifest.format != SkillManifest.currentFormat) {
    return SkillValidationFailure(
      'formatMismatch',
      '协议号是「${manifest.format}」，本应用只支持 '
      '「${SkillManifest.currentFormat}」。不做兼容猜测，已拒绝',
    );
  }

  if (!SkillManifest.namePattern.hasMatch(manifest.name)) {
    return SkillValidationFailure(
      'invalidName',
      'skill 名「${manifest.name}」不合法：只能是小写字母、数字和连字符，'
      '1-64 位且不能以连字符开头（这个名字会作为磁盘目录名）',
    );
  }

  if (!manifest.supports(platform)) {
    return SkillValidationFailure(
      'platformMismatch',
      '这个 skill 只声明支持 '
      '${manifest.platforms.map((p) => p.id).join('、')}，'
      '不支持当前平台 ${platform.id}。Android 上没有 Node 运行时与桌面浏览器，'
      '脚本型 skill 只能在 Windows 上安装',
    );
  }

  return null;
}

/// Every path and the declared sizes across the whole package.
SkillValidationFailure? _checkEntries(
  Map<String, SkillArchiveEntry> entries,
) {
  var total = 0;
  final paths = entries.keys.toList()..sort();
  for (final path in paths) {
    // The codec already refused unsafe paths when it decoded the archive; this
    // repeats the check so the rule is enforced by the validator too, and so
    // its message is available in the same place as the other refusals. It
    // cannot be reached through `SkillPackageCodec.read`, which is the only
    // producer of this map.
    if (_looksUnsafe(path)) {
      return SkillValidationFailure(
        'unsafeEntryPath',
        'skill 包含跳出包目录的路径「$path」，已拒绝',
      );
    }
    total += entries[path]!.bytes.length;
    if (total > SkillArchiveLimits.maxTotalUncompressedBytes) {
      return const SkillValidationFailure(
        'packageTooLarge',
        'skill 解压后总大小超过上限 '
        '（${SkillArchiveLimits.maxTotalUncompressedLabel}），已拒绝解包',
      );
    }
  }
  return null;
}

/// Whether a path would leave the package root.
bool _looksUnsafe(String path) {
  if (path.isEmpty || path.startsWith('/')) {
    return true;
  }
  final segments = path.split('/');
  return segments.contains('..') || segments.first.contains(':');
}

/// Each declared script entry must exist and must stay inside the package.
SkillValidationFailure? _checkScripts(
  SkillManifest manifest,
  Map<String, SkillArchiveEntry> entries,
) {
  for (final script in manifest.scripts) {
    final raw = script.entry.replaceAll('\\', '/');
    if (raw.startsWith('/') || raw.split('/').contains('..')) {
      return SkillValidationFailure(
        'scriptEscapesPackage',
        '脚本「${script.name}」的 entry「${script.entry}」指向包外路径，已拒绝',
      );
    }
    if (!entries.containsKey(raw)) {
      return SkillValidationFailure(
        'missingScriptEntry',
        '脚本「${script.name}」声明的 entry「${script.entry}」在包里不存在',
      );
    }
  }
  return null;
}

/// The `tools/*.json` declarations.
///
/// The tool set is what an approval checklist and an audit ledger would act
/// on, so a half-declared tool is refused rather than guessed at.
Object _checkTools(Map<String, SkillArchiveEntry> entries) {
  final declared = SkillPackageCodec.readToolDeclarations(entries);
  final paths = declared.keys.toList()..sort();
  final tools = <SkillToolDeclaration>[];
  final names = <String, String>{};

  for (final path in paths) {
    final json = declared[path];
    if (json == null) {
      return SkillValidationFailure(
        'invalidToolDeclaration',
        '$path 不是合法的 JSON 对象',
      );
    }

    // §5.1 rule 1: a skill may not declare a deletion. Deletion has to go
    // through the built-in tools, where there is a before-snapshot and a
    // per-call confirmation (AI_DESIGN D7 / D13b); a skill script cannot offer
    // either, so the whole package is refused rather than the one tool dropped.
    if (json['risk'] == 'destructive') {
      final name = json['name']?.toString() ?? path;
      return SkillValidationFailure(
        'destructiveToolRefused',
        '$path 声明的工具「$name」风险等级是 destructive。'
        '删除类工具一律拒绝载入：删除必须走内置工具，那里有变更前快照和逐条确认',
      );
    }

    final SkillToolDeclaration tool;
    try {
      tool = SkillToolDeclaration.fromJson(json, source: path);
    } on FormatException catch (e) {
      return SkillValidationFailure('invalidToolDeclaration', e.message);
    }

    // Only `write` is allowed, and the default when `risk` is absent is
    // `write` too (`SkillToolDeclaration.fromJson`) - so this rejects an
    // unknown or misspelled label instead of letting it mean "some risk".
    if (tool.risk != 'write') {
      return SkillValidationFailure(
        'unsafeToolRisk',
        '$path 声明的工具「${tool.name}」风险等级是「${tool.risk}」，'
        '只允许 write（destructive 一律拒绝）',
      );
    }

    if (!SkillManifest.toolNamePattern.hasMatch(tool.name)) {
      return SkillValidationFailure(
        'invalidToolName',
        '$path 声明的工具名「${tool.name}」不合法：只能是小写字母、数字、下划线和连字符，'
        '1-64 位且不能以下划线或连字符开头',
      );
    }

    final previous = names[tool.name];
    if (previous != null) {
      return SkillValidationFailure(
        'duplicateToolName',
        '工具名「${tool.name}」在 $previous 和 $path 里重复声明',
      );
    }
    names[tool.name] = path;
    tools.add(tool);
  }

  return tools;
}

/// The declared tools of an already-installed package, for display.
///
/// Lenient on purpose: this runs while building the settings list, where a
/// package the user edited by hand should show what it has rather than make the
/// whole list fail. Installation uses [_checkTools], which is strict.
List<SkillToolDeclaration> declaredToolsForDisplay(
  Map<String, SkillArchiveEntry> entries,
) {
  final declared = SkillPackageCodec.readToolDeclarations(entries);
  final tools = <SkillToolDeclaration>[];
  for (final path in declared.keys.toList()..sort()) {
    final json = declared[path];
    if (json == null) {
      continue;
    }
    final parameters = json['parameters'];
    tools.add(SkillToolDeclaration(
      name: json['name']?.toString() ?? path,
      description: json['description']?.toString() ?? '',
      parameters:
          parameters is Map ? parameters.cast<String, Object?>() : const {},
      risk: json['risk']?.toString() ?? 'write',
      reversible: json['reversible'] == true,
      source: path,
    ));
  }
  return tools.isEmpty ? List<SkillToolDeclaration>.empty() : tools;
}

/// Serialises declarations for `state.json`.
///
/// The declarations are re-read from the installed package when it is listed,
/// so this is only a record of what the package declared when it was installed.
String encodeToolDeclarations(List<SkillToolDeclaration> tools) =>
    jsonEncode([for (final tool in tools) tool.toJson()]);

/// Parses what [encodeToolDeclarations] wrote.
List<SkillToolDeclaration> decodeToolDeclarations(Object? raw) {
  if (raw is! List) {
    return const [];
  }
  final tools = <SkillToolDeclaration>[];
  for (final item in raw) {
    if (item is! Map) {
      continue;
    }
    try {
      tools.add(SkillToolDeclaration.fromJson(
        item.cast<String, dynamic>(),
        source: 'state.json',
      ));
    } on FormatException {
      // A malformed cached declaration must not make the whole skill list
      // unreadable; the package's own tools/*.json is the source of truth and
      // is re-read on every list.
      continue;
    }
  }
  return tools;
}
