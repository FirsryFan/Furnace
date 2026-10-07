/// Builds `.fskill` archives in memory.
///
/// There is no committed binary fixture on purpose: a `.fskill` is a zip, so
/// building one in the test is both shorter than checking in a blob and better
/// evidence - the test states the exact package it is refusing, instead of
/// pointing at an opaque file whose contents nobody can read in review.
///
/// Two builders exist because they test different things:
///
///  * [buildSkillArchive] uses the `archive` package, which is what the app
///    itself uses, so it produces the archives a real user would install;
///  * [craftedZip] writes the zip bytes by hand. It exists because a declared
///    uncompressed size larger than the data cannot be produced with the normal
///    encoder (it would have to allocate that much memory to inflate), and a
///    zip bomb is exactly the case where the declared size is a lie.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// A manifest document with the fields a test cares about, and valid defaults
/// for the rest.
Map<String, dynamic> skillManifestJson({
  String format = 'fskill/1',
  String name = 'demo-skill',
  String version = '1.0.0',
  String description = '演示用的 skill',
  List<String> platforms = const ['windows'],
  List<String> networkAllow = const ['example.com'],
  List<String> permissions = const ['browser_bridge'],
  List<Map<String, dynamic>> scripts = const [],
}) =>
    {
      'format': format,
      'name': name,
      'version': version,
      'description': description,
      'platforms': platforms,
      'networkAllow': networkAllow,
      'permissions': permissions,
      'scripts': scripts,
    };

/// A `tools/*.json` declaration document.
Map<String, dynamic> skillToolJson({
  String name = 'find_questions',
  String description = '按条件检索题目',
  String risk = 'write',
  bool reversible = false,
  Object? parameters,
}) =>
    {
      'name': name,
      'description': description,
      'risk': risk,
      'reversible': reversible,
      'parameters': parameters ??
          {
            'type': 'object',
            'properties': {
              'subject': {'type': 'string'},
            },
          },
    };

/// Builds a `.fskill` whose `manifest.json` is [manifestJson].
///
/// Omitting `prompt.md` or any `tools/` file is meaningful: those absences are
/// what several of the refusals are about.
Uint8List buildSkillArchive({
  Map<String, dynamic>? manifestJson,
  String? prompt,
  Map<String, Map<String, dynamic>> tools = const {},
  Map<String, String> scripts = const {},
  Map<String, List<int>> extraFiles = const {},
  List<String> omit = const [],
}) {
  final archive = Archive();
  void add(String path, List<int> bytes) {
    if (omit.contains(path)) {
      return;
    }
    archive.addFile(ArchiveFile(path, bytes.length, bytes));
  }

  final manifest = manifestJson ?? skillManifestJson();
  add('manifest.json', utf8.encode(jsonEncode(manifest)));
  add('prompt.md', utf8.encode(prompt ?? '# 演示 skill\n\n这是一段方法论文本。\n'));
  for (final entry in tools.entries) {
    add('tools/${entry.key}', utf8.encode(jsonEncode(entry.value)));
  }
  for (final entry in scripts.entries) {
    add(entry.key, utf8.encode(entry.value));
  }
  for (final entry in extraFiles.entries) {
    add(entry.key, entry.value);
  }
  return Uint8List.fromList(ZipEncoder().encode(archive)!);
}

/// Builds a zip with one or more entries whose *declared* uncompressed size is
/// [declaredUncompressedSize] while the stored data stays tiny.
///
/// The declared number is the one an extractor would trust, so this is how a
/// "the header claims 33 MB, the payload is 64 bytes" bomb looks on the wire;
/// the caps have to be enforced against it rather than against the payload.
Uint8List craftedZip({
  int declaredUncompressedSize = 64,
  int payloadLength = 64,
  int count = 1,
  String Function(int index)? nameFor,
}) {
  String nameAt(int index) => nameFor?.call(index) ?? 'filler.txt';
  final writer = _ByteWriter();
  final localOffsets = <int>[];
  final crc = getCrc32(List<int>.filled(payloadLength, 65));

  for (var index = 0; index < count; index++) {
    localOffsets.add(writer.length);
    final payload = List<int>.filled(payloadLength, 65);
    final name = nameAt(index);
    writer
      ..u32(0x04034b50)
      ..u16(20)
      ..u16(0)
      ..u16(ZipFile.zipCompressionStore)
      ..u16(0)
      ..u16(0)
      ..u32(crc)
      ..u32(payload.length)
      ..u32(declaredUncompressedSize);
    writer
      ..u16(name.length)
      ..u16(0)
      ..ascii(name)
      ..bytes(payload);
  }

  final directoryOffset = writer.length;
  for (var index = 0; index < count; index++) {
    final name = nameAt(index);
    writer
      ..u32(0x02014b50)
      ..u16(20)
      ..u16(20)
      ..u16(0)
      ..u16(ZipFile.zipCompressionStore)
      ..u16(0)
      ..u16(0)
      ..u32(crc)
      ..u32(payloadLength)
      ..u32(declaredUncompressedSize);
    writer
      ..u16(name.length)
      ..u16(0)
      ..u16(0)
      ..u16(0)
      ..u16(0)
      ..u32(0)
      ..u32(localOffsets[index])
      ..ascii(name);
  }
  final directorySize = writer.length - directoryOffset;

  writer
    ..u32(0x06054b50)
    ..u16(0)
    ..u16(0)
    ..u16(count)
    ..u16(count)
    ..u32(directorySize)
    ..u32(directoryOffset)
    ..u16(0);

  return writer.toBytes();
}

/// Minimal little-endian byte writer for [craftedZip].
class _ByteWriter {
  final BytesBuilder _builder = BytesBuilder();

  int get length => _builder.length;

  void u16(int value) {
    final data = ByteData(2)..setUint16(0, value, Endian.little);
    _builder.add(data.buffer.asUint8List());
  }

  void u32(int value) {
    final data = ByteData(4)..setUint32(0, value, Endian.little);
    _builder.add(data.buffer.asUint8List());
  }

  void ascii(String value) => _builder.add(asciiEncode(value));

  void bytes(List<int> value) => _builder.add(value);

  Uint8List toBytes() => _builder.toBytes();
}

/// ASCII bytes, used because every path in these fixtures is ASCII and a
/// filename encoded as UTF-8 would need the language flag set to be read back.
List<int> asciiEncode(String value) =>
    [for (final unit in value.codeUnits) unit & 0xff];
