import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/skill/skill_package_codec.dart';

import 'skill_fixture.dart';

/// The zip container rules: what can be read out of a `.fskill`, and which
/// archive shapes are refused before anything is extracted.
void main() {
  group('reading a well-formed package', () {
    test('exposes the manifest, the prompt and every file', () {
      final bytes = buildSkillArchive(
        manifestJson: skillManifestJson(name: 'demo-skill'),
        prompt: '# 标题\n正文\n',
        tools: {'search.json': skillToolJson()},
        scripts: {'scripts/find.mjs': 'console.log(1)\n'},
      );

      final read = SkillPackageCodec.read(bytes);

      expect(read.entries.keys.toSet(), {
        'manifest.json',
        'prompt.md',
        'tools/search.json',
        'scripts/find.mjs',
      });
      final manifest = SkillPackageCodec.readManifest(read.entries)!;
      expect(manifest.name, 'demo-skill');
      expect(SkillPackageCodec.readPrompt(read.entries), '# 标题\n正文\n');
      expect(
        SkillPackageCodec.readToolDeclarations(read.entries).keys.toList(),
        ['tools/search.json'],
      );
    });

    test('a missing manifest reads as null, not as an exception', () {
      final bytes = buildSkillArchive(
        omit: const ['manifest.json'],
      );
      final read = SkillPackageCodec.read(bytes);
      expect(SkillPackageCodec.readManifest(read.entries), isNull);
    });

    test('a malformed manifest.json is a named refusal', () {
      final bytes = buildSkillArchive();
      final read = SkillPackageCodec.read(bytes);
      read.entries['manifest.json'] = SkillArchiveEntry(
        path: 'manifest.json',
        bytes: Uint8List.fromList(utf8.encode('{ not json')),
      );

      expect(
        () => SkillPackageCodec.readManifest(read.entries),
        throwsA(isA<SkillArchiveException>()
            .having((e) => e.code, 'code', 'invalidManifestJson')),
      );
    });
  });

  group('refusing hostile archives', () {
    test('bytes that are not a zip at all', () {
      final notZip = Uint8List.fromList(List<int>.filled(64, 7));
      expect(
        () => SkillPackageCodec.read(notZip),
        throwsA(isA<SkillArchiveException>()
            .having((e) => e.code, 'code', 'notZip')),
      );
    });

    test('an archive with too many entries', () {
      // One entry over the cap (the manifest and the prompt are two of them).
      // The check runs from the directory listing, so nothing is decompressed
      // to find this out.
      final bytes = buildSkillArchive(
        extraFiles: {
          for (var index = 0; index < SkillArchiveLimits.maxEntries - 1; index++)
            'references/$index.md': const [1, 2, 3],
        },
      );

      expect(
        () => SkillPackageCodec.read(bytes),
        throwsA(isA<SkillArchiveException>()
            .having((e) => e.code, 'code', 'tooManyEntries')),
      );
    });

    test('an absolute entry path', () {
      final bytes = craftedZip(nameFor: (_) => '/etc/passwd');
      expect(
        () => SkillPackageCodec.read(bytes),
        throwsA(isA<SkillArchiveException>()
            .having((e) => e.code, 'code', 'unsafeEntryPath')),
      );
    });

    test('a dot-dot entry path', () {
      final bytes = craftedZip(nameFor: (_) => '../../evil.txt');
      expect(
        () => SkillPackageCodec.read(bytes),
        throwsA(isA<SkillArchiveException>()
            .having((e) => e.code, 'code', 'unsafeEntryPath')),
      );
    });

    test('a backslash-separated traversal', () {
      // The `archive` package normalises `\` to `/` when it builds an entry
      // name, so this arrives as `../../evil.txt` - which is exactly why the
      // check has to be on the normalised path and not only on the raw bytes.
      final bytes = craftedZip(nameFor: (_) => r'..\..\evil.txt');
      expect(
        () => SkillPackageCodec.read(bytes),
        throwsA(isA<SkillArchiveException>()
            .having((e) => e.code, 'code', 'unsafeEntryPath')),
      );
    });

    test('a Windows drive-relative entry path', () {
      final bytes = craftedZip(nameFor: (_) => 'C:evil.txt');
      expect(
        () => SkillPackageCodec.read(bytes),
        throwsA(isA<SkillArchiveException>()
            .having((e) => e.code, 'code', 'unsafeEntryPath')),
      );
    });

    test('a single entry whose declared size exceeds the cap', () {
      // The header claims 33 MB while 64 bytes are stored: the rejection must
      // come from the declared number, before inflation, or the cap would be
      // enforced only after the memory was already spent.
      final bytes = craftedZip(
        declaredUncompressedSize: 33 * 1024 * 1024,
        payloadLength: 64,
      );

      expect(
        () => SkillPackageCodec.read(bytes),
        throwsA(isA<SkillArchiveException>()
            .having((e) => e.code, 'code', 'entryTooLarge')),
      );
    });
  });
}
