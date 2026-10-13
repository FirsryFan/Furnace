/// The shape of a skill that ships *inside* the app, and the builder for one.
///
/// `sample_skill.dart` is the precedent: the package is assembled from Dart
/// strings rather than committed as a `.fskill` blob, because a zip in the
/// repository is unreviewable - a `git diff` cannot tell you what changed
/// inside it. This file generalises that idea to the skills the app ships for
/// real work, so each of them is a readable prompt in the diff.
///
/// Both built-ins are **prompt-only**: no `tools/*.json`, no `scripts/**`. That
/// is a deliberate limit rather than an omission -
///
///  * nothing in the app can drive a browser, so a `zujuan-finder` that needs a
///    logged-in session cannot be scripted here (see the prompt itself, which
///    says so to the model);
///  * the writing coach needs no tool at all: it is methodology plus judgement.
///
/// What they add over the built-in tools is *how* to do the job: which URLs to
/// fetch, which quality criteria are falsifiable, and which claims the model is
/// not allowed to make (invented answers, an AI draft presented as the standard).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../../domain/skill/skill_manifest.dart';

/// One built-in skill, as the settings card offers it.
///
/// The card needs a label *before* anything is installed, when there is no
/// manifest on disk to read, so the display text lives here rather than being
/// read back from the package.
class BuiltinSkill {
  const BuiltinSkill({
    required this.name,
    required this.title,
    required this.summary,
    required this.build,
  });

  /// The `manifest.json` name, which is also the directory under
  /// `<appSupport>/skills/`. Shown on the card because installing creates that
  /// directory and the user should see which one.
  final String name;

  /// Display name. Chinese, like the prompts themselves: the material these
  /// skills work on (组卷网试题、中文议论文) is Chinese.
  final String title;

  /// One line for the card: what installing this actually gets the user.
  final String summary;

  /// Builds the `.fskill` bytes. Same contract as `SampleSkill.build`.
  final Uint8List Function() build;
}

/// Builds a prompt-only `.fskill` from Dart strings.
///
/// Only `manifest.json` and `prompt.md` are written. The manifest is emitted
/// with every array field present (`networkAllow`, `permissions`, `scripts`),
/// including the empty ones, so the package states "no scripts" rather than
/// leaving the reader to infer it from an absent key.
Uint8List buildPromptOnlySkill({
  required String name,
  required String version,
  required String description,
  required List<SkillPlatform> platforms,
  List<String> networkAllow = const [],
  required String prompt,
}) {
  final manifest = jsonEncode({
    'format': SkillManifest.currentFormat,
    'name': name,
    'version': version,
    'description': description,
    'platforms': [for (final platform in platforms) platform.id],
    'networkAllow': networkAllow,
    'permissions': const <String>[],
    'scripts': const <Object>[],
  });

  final archive = Archive();
  void add(String path, String text) {
    final bytes = utf8.encode(text);
    archive.addFile(ArchiveFile(path, bytes.length, bytes));
  }

  add('manifest.json', manifest);
  add('prompt.md', prompt.trim());
  return Uint8List.fromList(ZipEncoder().encode(archive)!);
}
