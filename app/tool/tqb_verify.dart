import 'dart:io';

import 'package:furnace/data/package/question_pack_codec.dart';

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('usage: dart <this> <file.tqb>');
    exit(2);
  }
  final archive = decodeQuestionPackArchive(File(args.first).readAsBytesSync());
  final manifest = archive.manifest;
  stdout.writeln(
      'manifest format=${manifest.toJson()["format"]} version=1 questions=${manifest.questionCount} media=${manifest.mediaCount} app=${manifest.appVersion}');
  stdout.writeln(
      'decoded records=${archive.records.length} mediaBytes=${archive.mediaBytes.length}');
  var i = 0;
  for (final r in archive.records) {
    i += 1;
    final mediaPaths = r.media.map((m) => '${m.role}:${m.packPath}').join(', ');
    stdout.writeln(
        '[$i] ${r.subjectKey} ${r.questionType} options=${r.options.length} media=[${mediaPaths}] stem=${r.stem.replaceAll('\n', ' ').substring(0, r.stem.length < 40 ? r.stem.length : 40)}');
  }
  stdout.writeln('OK');
}
