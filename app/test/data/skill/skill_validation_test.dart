import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/skill/skill_archive.dart';
import 'package:furnace/data/skill/skill_package_codec.dart';
import 'package:furnace/domain/skill/skill_manifest.dart';

import 'skill_fixture.dart';

/// One case per refusal reason, each asserting the *reason* rather than "it
/// threw". The distinction matters: a package with a destructive tool and a
/// package with a bad protocol number are both "refused", but only one of them
/// is something the author can fix by editing the manifest.
void main() {
  /// Validates [bytes] for the given platform.
  SkillValidationResult validate(
    Uint8List bytes, {
    SkillPlatform platform = SkillPlatform.windows,
  }) =>
      validateSkillPackage(
        SkillPackageCodec.read(bytes).entries,
        platform: platform,
      );

  /// Asserts the refusal code of [bytes].
  void expectRefusal(
    Uint8List bytes,
    String code, {
    SkillPlatform platform = SkillPlatform.windows,
  }) {
    final result = validate(bytes, platform: platform);
    expect(result.isValid, isFalse);
    expect(result.failure!.code, code);
    // A refusal the user cannot read is a refusal they cannot act on.
    expect(result.failure!.message, isNotEmpty);
  }

  group('accepting', () {
    test('a complete package', () {
      final result = validate(buildSkillArchive(
        manifestJson: skillManifestJson(
          name: 'zujuan-finder',
          platforms: const ['windows', 'android'],
          scripts: const [
            {
              'name': 'find_questions',
              'entry': 'scripts/find.mjs',
              'args': ['--subject'],
            },
          ],
        ),
        tools: {'find.json': skillToolJson()},
        scripts: {'scripts/find.mjs': 'console.log(1)\n'},
      ));

      expect(result.isValid, isTrue);
      final package = result.requirePackage;
      expect(package.manifest.name, 'zujuan-finder');
      expect(package.prompt, isNotEmpty);
      expect(package.tools.single.name, 'find_questions');
      // `reversible` is preserved as declared, and defaults to false: a script
      // may have side effects outside the app that cannot be undone.
      expect(package.tools.single.reversible, isFalse);
      expect(package.tools.single.risk, 'write');
    });

    test('a prompt-only package with no tools and no scripts', () {
      final result = validate(buildSkillArchive(
        manifestJson: skillManifestJson(scripts: const []),
      ));
      expect(result.isValid, isTrue);
      expect(result.requirePackage.tools, isEmpty);
    });
  });

  group('refusing the manifest', () {
    test('no manifest.json', () {
      expectRefusal(
        buildSkillArchive(omit: const ['manifest.json']),
        'missingManifest',
      );
    });

    test('manifest.json that is not JSON', () {
      expectRefusal(
        buildSkillArchive(extraFiles: {
          'manifest.json': Uint8List.fromList([123, 125, 123]),
        }),
        'invalidManifestJson',
      );
    });

    test('a format other than fskill/1', () {
      final result = validate(
        buildSkillArchive(manifestJson: skillManifestJson(format: 'fskill/2')),
        platform: SkillPlatform.windows,
      );
      expect(result.failure!.code, 'formatMismatch');
      // No best-effort compatibility: the message has to say which protocol
      // was found and which one is understood.
      expect(result.failure!.message, contains('fskill/2'));
      expect(result.failure!.message, contains('fskill/1'));
    });

    test('a name that is not [a-z0-9][a-z0-9-]{0,63}', () {
      for (final name in const [
        'Zujuan-Finder',
        '-leading',
        'with_underscore',
        '../escape',
        '',
      ]) {
        expectRefusal(
          buildSkillArchive(manifestJson: skillManifestJson(name: name)),
          'invalidName',
        );
      }
      // 65 characters: one over the limit.
      expectRefusal(
        buildSkillArchive(
          manifestJson: skillManifestJson(name: 'a'.padRight(65, 'a')),
        ),
        'invalidName',
      );
    });

    test('a missing prompt.md', () {
      expectRefusal(
        buildSkillArchive(omit: const ['prompt.md']),
        'missingPrompt',
      );
    });
  });

  group('refusing the platform gate', () {
    test('a windows-only package on android', () {
      final result = validate(
        buildSkillArchive(
          manifestJson: skillManifestJson(platforms: const ['windows']),
        ),
        platform: SkillPlatform.android,
      );
      expect(result.failure!.code, 'platformMismatch');
      // The reason has to name both sides: "refused" without "because it is
      // windows-only" is not something a user can act on.
      expect(result.failure!.message, contains('windows'));
      expect(result.failure!.message, contains('android'));
    });

    test('an android-only package on windows', () {
      expectRefusal(
        buildSkillArchive(
          manifestJson: skillManifestJson(platforms: const ['android']),
        ),
        'platformMismatch',
        platform: SkillPlatform.windows,
      );
    });

    test('a windows-only package on windows', () {
      expect(
        validate(
          buildSkillArchive(
            manifestJson: skillManifestJson(platforms: const ['windows']),
          ),
          platform: SkillPlatform.windows,
        ).isValid,
        isTrue,
      );
    });
  });

  group('refusing scripts', () {
    test('an entry that is absent from the archive', () {
      final result = validate(buildSkillArchive(
        manifestJson: skillManifestJson(scripts: const [
          {'name': 'find_questions', 'entry': 'scripts/missing.mjs'},
        ]),
      ));
      expect(result.failure!.code, 'missingScriptEntry');
      expect(result.failure!.message, contains('scripts/missing.mjs'));
    });

    test('an entry that escapes the package root', () {
      final result = validate(buildSkillArchive(
        manifestJson: skillManifestJson(scripts: const [
          {'name': 'find_questions', 'entry': '../../outside.mjs'},
        ]),
        scripts: {'outside.mjs': 'x'},
      ));
      expect(result.failure!.code, 'scriptEscapesPackage');
      expect(result.failure!.message, contains('../../outside.mjs'));
    });
  });

  group('refusing tools', () {
    test('a destructive tool', () {
      final result = validate(buildSkillArchive(
        tools: {'wipe.json': skillToolJson(name: 'wipe_all', risk: 'destructive')},
      ));
      expect(result.failure!.code, 'destructiveToolRefused');
      expect(result.failure!.message, contains('wipe_all'));
      // §5.1: deletion goes through the built-in tools, which have a
      // before-snapshot and a per-call confirmation.
      expect(result.failure!.message, contains('destructive'));
    });

    test('an unknown risk label', () {
      expectRefusal(
        buildSkillArchive(
          tools: {'r.json': skillToolJson(name: 'do_it', risk: 'readonly')},
        ),
        'unsafeToolRisk',
      );
    });

    test('a tool with no name', () {
      final declaration = skillToolJson()..remove('name');
      expectRefusal(
        buildSkillArchive(tools: {'n.json': declaration}),
        'invalidToolDeclaration',
      );
    });

    test('a tool with no description', () {
      final declaration = skillToolJson()..remove('description');
      expectRefusal(
        buildSkillArchive(tools: {'d.json': declaration}),
        'invalidToolDeclaration',
      );
    });

    test('a tool with no parameters', () {
      final declaration = skillToolJson()..remove('parameters');
      final result = validate(buildSkillArchive(tools: {'p.json': declaration}));
      expect(result.failure!.code, 'invalidToolDeclaration');
      expect(result.failure!.message, contains('tools/p.json'));
    });

    test('a tools file that is not a JSON object', () {
      expectRefusal(
        buildSkillArchive(extraFiles: {
          'tools/bad.json': Uint8List.fromList([91, 93]),
        }),
        'invalidToolDeclaration',
      );
    });

    test('a tool name that would not be safe to register', () {
      // Underscores are legal in a tool name (the spec's own example is
      // `find_questions`), so what is refused here is the shape that would
      // break the declaration: a space, or a leading separator.
      for (final name in const ['Find Questions', '_leading', 'with.dot']) {
        expectRefusal(
          buildSkillArchive(tools: {'x.json': skillToolJson(name: name)}),
          'invalidToolName',
        );
      }
      // The spec's example has to be accepted, or the rule contradicts §2.1.
      expect(
        validate(
          buildSkillArchive(tools: {'x.json': skillToolJson(name: 'find_questions')}),
        ).isValid,
        isTrue,
      );
    });

    test('the same tool name declared twice', () {
      final result = validate(buildSkillArchive(tools: {
        'a.json': skillToolJson(name: 'find_questions'),
        'b.json': skillToolJson(name: 'find_questions'),
      }));
      expect(result.failure!.code, 'duplicateToolName');
      expect(result.failure!.message, contains('find_questions'));
    });

    test('a reversible declaration is kept as declared', () {
      final result = validate(buildSkillArchive(
        tools: {'r.json': skillToolJson(reversible: true)},
      ));
      expect(result.isValid, isTrue);
      expect(result.requirePackage.tools.single.reversible, isTrue);
    });
  });

  group('refusing oversized packages', () {
    test('files whose total size exceeds the cap', () {
      // Each file is under the per-entry cap, so only the sum can catch this -
      // which is why both checks exist.
      const half = SkillArchiveLimits.maxTotalUncompressedBytes ~/ 2 + 1024;      final result = validate(buildSkillArchive(extraFiles: {
        'references/a.bin': List<int>.filled(half, 1),
        'references/b.bin': List<int>.filled(half, 2),
      }));
      expect(result.failure!.code, 'packageTooLarge');
      expect(
        result.failure!.message,
        // The label the message promises, as a literal: reading it from the
        // constant would make the test agree with any value, including a wrong
        // one.
        contains('32 MB'),
      );
    });
  });
}
