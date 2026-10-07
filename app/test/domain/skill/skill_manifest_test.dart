import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/skill/skill_manifest.dart';

import '../../data/skill/skill_fixture.dart';

/// The manifest model: what it accepts, what shape it insists on, and which
/// fields the security rules depend on.
void main() {
  group('SkillPlatform', () {
    test('maps the manifest strings to platforms', () {
      expect(SkillPlatform.fromId('windows'), SkillPlatform.windows);
      expect(SkillPlatform.fromId('android'), SkillPlatform.android);
      // An unknown value is null rather than a silent fallback: the platform
      // list is what the install gate reads, so a typo has to be visible.
      expect(SkillPlatform.fromId('win32'), isNull);
      expect(SkillPlatform.fromId(''), isNull);
    });
  });

  group('SkillManifest', () {
    test('round-trips every field through JSON', () {
      final original = SkillManifest.fromJson(skillManifestJson(
        name: 'zujuan-finder',
        version: '1.2.3',
        description: '到组卷网找题',
        platforms: const ['windows'],
        networkAllow: const ['zujuan.xkw.com'],
        permissions: const ['browser_bridge'],
        scripts: const [
          {
            'name': 'find_questions',
            'entry': 'scripts/find.mjs',
            'args': ['--subject', '--count'],
          },
        ],
      ));

      final decoded = SkillManifest.fromJson(original.toJson());

      expect(decoded.format, 'fskill/1');
      expect(decoded.name, 'zujuan-finder');
      expect(decoded.version, '1.2.3');
      expect(decoded.description, '到组卷网找题');
      expect(decoded.platforms, [SkillPlatform.windows]);
      expect(decoded.networkAllow, ['zujuan.xkw.com']);
      expect(decoded.permissions, ['browser_bridge']);
      expect(decoded.scripts.single.entry, 'scripts/find.mjs');
      expect(decoded.scripts.single.args, ['--subject', '--count']);
    });

    test('deduplicates declared platforms', () {
      final manifest = SkillManifest.fromJson(
        skillManifestJson(platforms: const ['windows', 'windows', 'android']),
      );
      expect(manifest.platforms, [SkillPlatform.windows, SkillPlatform.android]);
    });

    test('refuses a missing or empty platform list', () {
      // Defaulting this to "all platforms" would silently disable the gate for
      // exactly the packages that forgot to declare it.
      expect(
        () => SkillManifest.fromJson(skillManifestJson(platforms: const [])),
        throwsA(isA<FormatException>()),
      );
      final withoutPlatforms = skillManifestJson()..remove('platforms');
      expect(
        () => SkillManifest.fromJson(withoutPlatforms),
        throwsA(isA<FormatException>()),
      );
    });

    test('refuses an unknown platform name', () {
      expect(
        () => SkillManifest.fromJson(
          skillManifestJson(platforms: const ['windows', 'win32']),
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('refuses a missing format or name', () {
      final withoutFormat = skillManifestJson()..remove('format');
      expect(
        () => SkillManifest.fromJson(withoutFormat),
        throwsA(isA<FormatException>()),
      );
      final withoutName = skillManifestJson()..remove('name');
      expect(
        () => SkillManifest.fromJson(withoutName),
        throwsA(isA<FormatException>()),
      );
    });

    test('defaults the presentation-only fields instead of failing', () {
      // A missing description is cosmetic; refusing it would reject packages
      // that are otherwise perfectly usable.
      final manifest = SkillManifest.fromJson({
        'format': 'fskill/1',
        'name': 'minimal',
        'platforms': ['windows'],
      });
      expect(manifest.version, isEmpty);
      expect(manifest.description, isEmpty);
      expect(manifest.networkAllow, isEmpty);
      expect(manifest.permissions, isEmpty);
      expect(manifest.scripts, isEmpty);
    });

    test('a missing risk defaults to write, and reversible to false', () {
      final tool = SkillToolDeclaration.fromJson(
        {'name': 'x', 'description': 'y', 'parameters': {'type': 'object'}},
        source: 'tools/x.json',
      );
      expect(tool.risk, 'write');
      expect(tool.reversible, isFalse);
    });

    test('refuses a script declaration with no entry', () {
      expect(
        () => SkillManifest.fromJson(skillManifestJson(scripts: const [
          {'name': 'find_questions'},
        ])),
        throwsA(isA<FormatException>()),
      );
    });

    test('the name pattern is what keeps a name usable as a directory', () {
      expect(SkillManifest.namePattern.hasMatch('zujuan-finder'), isTrue);
      expect(SkillManifest.namePattern.hasMatch('a'), isTrue);
      expect(SkillManifest.namePattern.hasMatch('a1-b2'), isTrue);
      expect(SkillManifest.namePattern.hasMatch('Zujuan'), isFalse);
      expect(SkillManifest.namePattern.hasMatch('-leading'), isFalse);
      expect(SkillManifest.namePattern.hasMatch('../escape'), isFalse);
      expect(SkillManifest.namePattern.hasMatch('a/b'), isFalse);
      expect(SkillManifest.namePattern.hasMatch('a'.padRight(65, 'a')), isFalse);
      expect(SkillManifest.namePattern.hasMatch('a'.padRight(64, 'a')), isTrue);
    });

    test('the tool name pattern allows the spec example but not a path', () {
      // The spec declares `find_questions` (§2.1), so an underscore has to be
      // legal here even though a skill *name* may not contain one.
      expect(SkillManifest.toolNamePattern.hasMatch('find_questions'), isTrue);
      expect(SkillManifest.toolNamePattern.hasMatch('find-questions'), isTrue);
      expect(SkillManifest.toolNamePattern.hasMatch('Find'), isFalse);
      expect(SkillManifest.toolNamePattern.hasMatch('_leading'), isFalse);
      expect(SkillManifest.toolNamePattern.hasMatch('../x'), isFalse);
    });
  });
}
