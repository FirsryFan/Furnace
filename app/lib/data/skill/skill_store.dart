/// The installed-skill registry, which is a directory tree, not a table.
///
/// docs/SKILL_FORMAT.md §7 is explicit that a skill is *files on disk*: a skill
/// carries scripts, references and a prompt, none of which fit database rows,
/// and it must be separable from the database (`.tfpkg` dumps tables only, so a
/// skill has to travel on its own). This store therefore keeps the install
/// directory as the single source of truth:
///
/// ```
/// <appSupport>/skills/<name>/          the extracted package, untouched
/// <appSupport>/skills/<name>/state.json  {"enabled": true, "installedAt": ...}
/// ```
///
/// `state.json` lives *inside* the skill directory rather than beside it, so
/// deleting the directory removes the skill completely and there is nothing to
/// keep in step. The enable flag defaults to `false` when the file is missing,
/// which is the safe reading: an unreadable state is not consent to feed a
/// skill's instructions to the model.
///
/// **Installing runs nothing.** It validates, unpacks, and records a flag.
/// Nothing in a `.fskill` is executed by this class or by anything it calls,
/// and the script container of spec §3 does not exist yet (see
/// `SkillToolDeclaration`). There is also no signature or hash verification:
/// the integrity story is "you trust the file you installed", and this code
/// does not imply otherwise.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../domain/skill/skill_manifest.dart';
import 'skill_archive.dart';
import 'skill_package_codec.dart';

/// One installed skill, as the settings screen shows it.
class InstalledSkill {
  const InstalledSkill({
    required this.manifest,
    required this.prompt,
    required this.tools,
    required this.enabled,
    required this.installedAt,
    required this.directory,
  });

  final SkillManifest manifest;

  /// `prompt.md` as installed. Held so the settings and the agent loop do not
  /// each have to re-read the disk.
  final String prompt;

  /// Declared tools. Displayed, never registered into `ToolRegistry`.
  final List<SkillToolDeclaration> tools;

  final bool enabled;

  final DateTime installedAt;

  /// The skill's private directory, shown so the user can find the files.
  final String directory;

  String get name => manifest.name;

  InstalledSkill copyWith({bool? enabled}) => InstalledSkill(
        manifest: manifest,
        prompt: prompt,
        tools: tools,
        enabled: enabled ?? this.enabled,
        installedAt: installedAt,
        directory: directory,
      );
}

/// Installs, lists, enables and removes `.fskill` packages.
class SkillStore {
  SkillStore({Future<Directory> Function()? supportDirectory})
      : _supportDirectory = supportDirectory ?? getApplicationSupportDirectory;

  /// Injected in tests, which must not touch the real app data directory.
  final Future<Directory> Function() _supportDirectory;

  /// Subdirectory of the app support directory. Named for the format so the
  /// user can find and inspect what they installed.
  static const String directoryName = 'skills';

  static const String stateFileName = 'state.json';

  /// Suffix of the staging directory used to build a new install.
  ///
  /// The leading dot keeps it out of the way, and the suffix guarantees it can
  /// never collide with a real skill name (the name pattern forbids dots).
  static const String stagingSuffix = '.staging';

  /// Validates [bytes] and extracts them under `<skills>/<name>/`.
  ///
  /// Validation happens entirely in memory before anything is written, and the
  /// extraction goes to a staging directory that is swapped into place at the
  /// end. Two failure modes follow from that: a refused package leaves the disk
  /// untouched, and installing over an existing skill of the same name either
  /// replaces it whole or leaves the previous copy intact - never a half-written
  /// directory.
  ///
  /// [platform] defaults to the running platform and exists so tests can ask
  /// the gating question for both Windows and Android.
  Future<({InstalledSkill? skill, SkillValidationFailure? failure})> install(
    Uint8List bytes, {
    SkillPlatform? platform,
  }) async {
    final Map<String, SkillArchiveEntry> entries;
    try {
      entries = SkillPackageCodec.read(bytes).entries;
    } on SkillArchiveException catch (e) {
      return (skill: null, failure: SkillValidationFailure(e.code, e.message));
    }

    final result = validateSkillPackage(
      entries,
      platform: platform ?? SkillPlatform.current,
    );
    final failure = result.failure;
    if (failure != null) {
      return (skill: null, failure: failure);
    }
    final package = result.requirePackage;

    final installed = await _extract(package);
    return (skill: installed, failure: null);
  }

  /// Every installed skill, sorted by name.
  ///
  /// A directory that is not a skill (an interrupted install, or a file the
  /// user dropped in) is skipped rather than reported: it cannot be enabled,
  /// and it has no name to enable.
  Future<List<InstalledSkill>> list() async {
    final root = await _root();
    if (!root.existsSync()) {
      return const [];
    }
    final skills = <InstalledSkill>[];
    for (final entity in root.listSync()) {
      if (entity is! Directory) {
        continue;
      }
      if (p.basename(entity.path).endsWith(stagingSuffix)) {
        continue;
      }
      final skill = _readInstalled(entity);
      if (skill != null) {
        skills.add(skill);
      }
    }
    skills.sort((a, b) => a.name.compareTo(b.name));
    return skills;
  }

  /// The enabled skills, sorted by name.
  ///
  /// This is the list whose prompts reach the model, so it is deliberately
  /// derived from disk on every turn: a skill disabled a second ago must not
  /// still be speaking to the model on the next message.
  Future<List<InstalledSkill>> enabled() async =>
      [for (final skill in await list()) if (skill.enabled) skill];

  /// Turns one skill on or off. Returns false when it is not installed.
  Future<bool> setEnabled(String name, bool enabled) async {
    final directory = await _skillDirectory(name);
    if (!directory.existsSync()) {
      return false;
    }
    final state = await _readState(directory);
    await _writeState(directory, {
      'enabled': enabled,
      // Keep the original install time when only the flag changes.
      'installedAt': (state['installedAt'] as String?) ??
          DateTime.now().toUtc().toIso8601String(),
    });
    return true;
  }

  /// Deletes the skill directory, files and all.
  ///
  /// The caller confirms first, because this is the one operation here that
  /// destroys something the user cannot get back from inside the app.
  Future<bool> remove(String name) async {
    final directory = await _skillDirectory(name);
    if (!directory.existsSync()) {
      return false;
    }
    await directory.delete(recursive: true);
    return true;
  }

  // --- disk ----------------------------------------------------------------

  /// Writes [package] to a staging directory and swaps it into place.
  Future<InstalledSkill> _extract(SkillPackage package) async {
    final name = package.manifest.name;
    final root = await _root();
    final target = Directory(p.join(root.path, name));
    final staging = Directory(p.join(root.path, '$name$stagingSuffix'));
    if (staging.existsSync()) {
      await staging.delete(recursive: true);
    }
    await staging.create(recursive: true);

    try {
      for (final path in package.entries.keys.toList()..sort()) {
        final file = File(p.joinAll([staging.path, ...path.split('/')]));
        await file.parent.create(recursive: true);
        await file.writeAsBytes(package.entries[path]!.bytes, flush: true);
      }

      final installedAt = DateTime.now().toUtc();
      // `state.json` sits inside the skill directory so deleting the directory
      // deletes the skill completely; there is no second place to keep in step.
      // The flag starts `true` because installing *is* the user's decision to
      // use the skill.
      final stateFile = File(p.join(staging.path, stateFileName));
      await stateFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert({
          'enabled': true,
          'installedAt': installedAt.toIso8601String(),
          'tools': decodeToolDeclarations(package.tools),
        }),
        flush: true,
      );

      await _swap(staging, target);

      return InstalledSkill(
        manifest: package.manifest,
        prompt: package.prompt,
        tools: package.tools,
        enabled: true,
        installedAt: installedAt,
        directory: target.path,
      );
    } finally {
      // Reached on success too, where the directory no longer exists.
      if (staging.existsSync()) {
        await staging.delete(recursive: true);
      }
    }
  }

  /// Moves [staging] onto [target], keeping the previous copy until the move
  /// has succeeded.
  ///
  /// `Directory.rename` cannot overwrite an existing directory, so the old one
  /// steps aside first. If the final move fails, the old copy is moved back:
  /// the point of the whole staging dance is that a failed install never
  /// destroys a working one.
  Future<void> _swap(Directory staging, Directory target) async {
    final backup = Directory('${target.path}.replaced');
    if (backup.existsSync()) {
      await backup.delete(recursive: true);
    }
    final hadPrevious = target.existsSync();
    if (hadPrevious) {
      await target.rename(backup.path);
    }
    try {
      await staging.rename(target.path);
    } catch (_) {
      if (hadPrevious && backup.existsSync() && !target.existsSync()) {
        await backup.rename(target.path);
      }
      rethrow;
    }
    if (backup.existsSync()) {
      await backup.delete(recursive: true);
    }
  }

  /// Reads one installed skill directory, or null when it is not a skill.
  InstalledSkill? _readInstalled(Directory directory) {
    final manifestFile =
        File(p.join(directory.path, SkillPackageCodec.manifestFileName));
    if (!manifestFile.existsSync()) {
      return null;
    }

    final SkillManifest manifest;
    final String prompt;
    final List<SkillToolDeclaration> tools;
    try {
      final entries = _readEntries(directory);
      final decoded = SkillPackageCodec.readManifest(entries);
      if (decoded == null) {
        return null;
      }
      manifest = decoded;
      prompt = SkillPackageCodec.readPrompt(entries) ?? '';
      // Read back from the installed files rather than from `state.json`, so
      // the displayed tool list describes what is actually on disk.
      tools = declaredToolsForDisplay(entries);
    } on SkillArchiveException {
      return null;
    } on FileSystemException {
      return null;
    } on FormatException {
      return null;
    }

    final state = _readStateSync(directory);
    return InstalledSkill(
      manifest: manifest,
      prompt: prompt,
      tools: tools,
      // Absent state means "not enabled": an unreadable state file must not be
      // read as permission to feed this skill's instructions to the model.
      enabled: state['enabled'] == true,
      installedAt:
          DateTime.tryParse(state['installedAt']?.toString() ?? '')?.toLocal() ??
              directory.statSync().modified,
      directory: directory.path,
    );
  }

  /// Reads an installed directory back into the codec's entry shape.
  ///
  /// The files on disk are the source of truth, so this is a real read rather
  /// than a cached copy: a package edited after install is reported as it is.
  Map<String, SkillArchiveEntry> _readEntries(Directory directory) {
    final entries = <String, SkillArchiveEntry>{};
    for (final entity in directory.listSync(recursive: true)) {
      if (entity is! File) {
        continue;
      }
      final relative = p.relative(entity.path, from: directory.path);
      final segments = p.split(relative);
      if (segments.isNotEmpty && segments.first.endsWith(stagingSuffix)) {
        continue;
      }
      final path = segments.join('/');
      if (path == stateFileName) {
        continue;
      }
      entries[path] = SkillArchiveEntry(
        path: path,
        bytes: entity.readAsBytesSync(),
      );
    }
    return entries;
  }

  Map<String, Object?> _readStateSync(Directory directory) {
    final file = File(p.join(directory.path, stateFileName));
    if (!file.existsSync()) {
      return const {};
    }
    try {
      final decoded = jsonDecode(file.readAsStringSync());
      return decoded is Map ? decoded.cast<String, Object?>() : const {};
    } on FormatException {
      return const {};
    } on FileSystemException {
      return const {};
    }
  }

  Future<Map<String, Object?>> _readState(Directory directory) async {
    final file = File(p.join(directory.path, stateFileName));
    if (!file.existsSync()) {
      return const {};
    }
    try {
      final decoded = jsonDecode(await file.readAsString());
      return decoded is Map ? decoded.cast<String, Object?>() : const {};
    } on FormatException {
      return const {};
    } on FileSystemException {
      return const {};
    }
  }

  Future<void> _writeState(
    Directory directory,
    Map<String, Object?> state,
  ) async {
    final file = File(p.join(directory.path, stateFileName));
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(state),
      flush: true,
    );
  }

  Future<Directory> _root() async {
    final support = await _supportDirectory();
    final root = Directory(p.join(support.path, directoryName));
    if (!root.existsSync()) {
      root.createSync(recursive: true);
    }
    return root;
  }

  Future<Directory> _skillDirectory(String name) async {
    final root = await _root();
    return Directory(p.join(root.path, name));
  }
}
