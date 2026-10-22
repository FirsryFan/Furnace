import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:furnace/data/package/question_pack_codec.dart';
import 'package:furnace/domain/services/package/question_pack_record.dart';
import 'package:furnace/domain/services/zujuan/zujuan_link.dart';

/// 题库包（.tqb）体检探针：解码 → 统计 → 再编码往返，不碰数据库。
///
/// 用法：dart run tool/question_pack_probe.dart <file.tqb> [report.json]
/// 只读文件，不修改原包；报告是 JSON，便于外部抓题 agent 对照。
final RegExp _placeholder = RegExp(r'[［\[【]\s*图\s*([0-9０-９]{1,3})\s*[］\]】]');
final RegExp _answerLetter = RegExp(r'^[A-Z]{1,3}$');

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln(
      'usage: dart run tool/question_pack_probe.dart <file.tqb> [report.json]',
    );
    exitCode = 64;
    return;
  }
  final File file = File(args[0]);
  if (!file.existsSync()) {
    stderr.writeln('找不到文件：${args[0]}');
    exitCode = 66;
    return;
  }
  final Stopwatch stopwatch = Stopwatch()..start();
  late final QuestionPackArchive archive;
  try {
    archive = decodeQuestionPackArchive(file.readAsBytesSync());
  } on Object catch (error) {
    stdout.writeln('DECODE_FAILED: $error');
    exitCode = 1;
    return;
  }
  stopwatch.stop();

  final Map<String, Object?> report = <String, Object?>{};
  report['file'] = file.path;
  report['file_bytes'] = file.lengthSync();
  report['decode_ms'] = stopwatch.elapsedMilliseconds;
  report['format'] = archive.manifest.format;
  report['version'] = archive.manifest.version;
  report['app_version'] = archive.manifest.appVersion;
  report['exported_at'] = archive.manifest.exportedAt.toIso8601String();
  report['generated_by'] = archive.manifest.generatedBy;
  report['manifest_question_count'] = archive.manifest.questionCount;
  report['actual_question_count'] = archive.records.length;
  report['manifest_media_count'] = archive.manifest.mediaCount;
  report['actual_media_count'] = archive.mediaBytes.length;

  final Map<String, int> subjects = <String, int>{};
  final Map<String, int> sourceLevels = <String, int>{};
  final Map<String, int> questionTypes = <String, int>{};
  final Map<String, int> origins = <String, int>{};
  final Map<String, int> states = <String, int>{};
  final Map<String, int> roles = <String, int>{};
  final Map<String, int> mimes = <String, int>{};
  final Map<String, int> tagCounts = <String, int>{};
  final Map<String, int> stemFingerprints = <String, int>{};
  final List<int> stemLengths = <int>[];
  final List<String> alerts = <String>[];
  int withSerial = 0;
  int withSourceUrl = 0;
  int withZujuanQuestionId = 0;
  int withZujuanBankId = 0;
  int withYear = 0;
  int withRegion = 0;
  int withDifficulty = 0;
  int withAnswerText = 0;
  int withSolutionText = 0;
  int withTrapNote = 0;
  int answerLetterOnly = 0;
  int optionsZero = 0;
  int options1to3 = 0;
  int options4 = 0;
  int optionsMoreThan4 = 0;
  int optionsCorrectFlagged = 0;
  int stemImageTotal = 0;
  int answerImageTotal = 0;
  int solutionImageTotal = 0;
  int placeholdersTotal = 0;
  int unbalancedDollar = 0;
  int recordsWithPlaceholderOverflow = 0;
  int recordsSnapshotLike = 0;
  int recordsWithUnreferencedStemImages = 0;
  int mediaBytesTotal = 0;
  int badImageSignature = 0;
  int linkMismatch = 0;
  final List<String> answerImageMimeSamples = <String>[];

  for (int i = 0; i < archive.records.length; i++) {
    final QuestionPackRecord r = archive.records[i];
    _bump(subjects, r.subjectKey);
    _bump(sourceLevels, r.sourceLevel);
    _bump(questionTypes, r.questionType);
    _bump(origins, r.origin);
    _bump(states, r.state);
    if (r.serialNo != null) {
      withSerial++;
    }
    if ((r.sourceUrl ?? '').trim().isNotEmpty) {
      withSourceUrl++;
    }
    if ((r.zujuanQuestionId ?? '').trim().isNotEmpty) {
      withZujuanQuestionId++;
    }
    if ((r.zujuanBankId ?? '').trim().isNotEmpty) {
      withZujuanBankId++;
    }
    if (r.year != null) {
      withYear++;
    }
    if ((r.region ?? '').trim().isNotEmpty) {
      withRegion++;
    }
    if (r.difficulty != null) {
      withDifficulty++;
    }
    if ((r.answer ?? '').trim().isNotEmpty) {
      withAnswerText++;
      if (_answerLetter.hasMatch((r.answer ?? '').trim())) {
        answerLetterOnly++;
      }
    }
    if ((r.solution ?? '').trim().isNotEmpty) {
      withSolutionText++;
    }
    if ((r.trapNote ?? '').trim().isNotEmpty) {
      withTrapNote++;
    }
    final int optionCount = r.options.length;
    if (optionCount == 0) {
      optionsZero++;
    } else if (optionCount <= 3) {
      options1to3++;
    } else if (optionCount == 4) {
      options4++;
    } else {
      optionsMoreThan4++;
    }
    if (r.options.any((QuestionPackOption o) => o.isCorrect)) {
      optionsCorrectFlagged++;
    }
    final String stem = r.stem;
    stemLengths.add(stem.length);
    final String fingerprint = stem.replaceAll(RegExp(r'\s+'), ' ').trim();
    stemFingerprints[fingerprint] = (stemFingerprints[fingerprint] ?? 0) + 1;
    final int dollarCount = stem.split(r'$').length - 1;
    if (dollarCount.isOdd) {
      unbalancedDollar++;
    }
    final int placeholderCount = _placeholder.allMatches(stem).length;
    placeholdersTotal += placeholderCount;
    int stemImages = 0;
    for (final QuestionPackMedia m in r.media) {
      _bump(roles, m.role);
      if ((m.mime ?? '').trim().isNotEmpty) {
        _bump(mimes, m.mime!.trim());
      }
      final List<int> bytes = archive.mediaBytes[m.packPath] ?? const <int>[];
      mediaBytesTotal += bytes.length;
      if (m.role == 'stem') {
        stemImages++;
      }
      if (m.role == 'answer') {
        answerImageTotal++;
        if (answerImageMimeSamples.length < 5) {
          answerImageMimeSamples.add(m.mime ?? 'null');
        }
      }
      if (m.role == 'solution') {
        solutionImageTotal++;
      }
      if (bytes.isNotEmpty && !_looksLikeImage(bytes)) {
        badImageSignature++;
      }
    }
    stemImageTotal += stemImages;
    if (placeholderCount > 0 && placeholderCount > stemImages) {
      recordsWithPlaceholderOverflow++;
    }
    if (placeholderCount > 1 && stemImages == 1) {
      recordsSnapshotLike++;
    }
    if (stemImages > 0 && placeholderCount == 0) {
      recordsWithUnreferencedStemImages++;
    }
    for (final String tag in r.tagPaths) {
      _bump(tagCounts, tag);
    }
    final String? qid = r.zujuanQuestionId;
    final String? bankId = r.zujuanBankId;
    if (qid != null &&
        qid.trim().isNotEmpty &&
        (r.sourceUrl ?? '').trim().isNotEmpty) {
      final String? rebuilt =
          zujuanQuestionDetailUrl(bankId: bankId, questionId: qid);
      if (rebuilt != null && rebuilt != r.sourceUrl!.trim()) {
        linkMismatch++;
      }
    }
  }

  report['subjects'] = _sortedCounts(subjects);
  report['source_levels'] = _sortedCounts(sourceLevels);
  report['question_types'] = _sortedCounts(questionTypes);
  report['origins'] = _sortedCounts(origins);
  report['states'] = _sortedCounts(states);
  report['media_roles'] = _sortedCounts(roles);
  report['media_mimes'] = _sortedCounts(mimes);
  report['tag_paths'] = _sortedCounts(tagCounts);
  report['with_serial_no'] = withSerial;
  report['with_source_url'] = withSourceUrl;
  report['with_zujuan_question_id'] = withZujuanQuestionId;
  report['with_zujuan_bank_id'] = withZujuanBankId;
  report['with_year'] = withYear;
  report['with_region'] = withRegion;
  report['with_difficulty'] = withDifficulty;
  report['with_answer_text'] = withAnswerText;
  report['with_solution_text'] = withSolutionText;
  report['with_trap_note'] = withTrapNote;
  report['answer_letter_only'] = answerLetterOnly;
  report['options_zero'] = optionsZero;
  report['options_1_to_3'] = options1to3;
  report['options_4'] = options4;
  report['options_more_than_4'] = optionsMoreThan4;
  report['options_with_correct_flag'] = optionsCorrectFlagged;
  report['stem_min_length'] = stemLengths.isEmpty
      ? 0
      : stemLengths.reduce((int a, int b) => a < b ? a : b);
  report['stem_max_length'] = stemLengths.isEmpty
      ? 0
      : stemLengths.reduce((int a, int b) => a > b ? a : b);
  report['stem_avg_length'] = stemLengths.isEmpty
      ? 0
      : (stemLengths.reduce((int a, int b) => a + b) / stemLengths.length)
          .round();
  report['stem_dollar_unbalanced'] = unbalancedDollar;
  report['stem_placeholders_total'] = placeholdersTotal;
  report['stem_images_total'] = stemImageTotal;
  report['records_with_placeholder_overflow'] = recordsWithPlaceholderOverflow;
  report['records_snapshot_like'] = recordsSnapshotLike;
  report['records_with_unreferenced_stem_images'] =
      recordsWithUnreferencedStemImages;
  report['answer_images_total'] = answerImageTotal;
  report['solution_images_total'] = solutionImageTotal;
  report['answer_image_mime_samples'] = answerImageMimeSamples;
  report['media_bytes_total'] = mediaBytesTotal;
  report['bad_image_signature'] = badImageSignature;
  report['duplicate_stem_groups'] =
      stemFingerprints.values.where((int c) => c > 1).length;
  report['duplicate_stem_records'] = stemFingerprints.values
      .where((int c) => c > 1)
      .fold<int>(0, (int a, int b) => a + b);
  report['zujuan_link_mismatch'] = linkMismatch;

  if (archive.manifest.questionCount != archive.records.length) {
    alerts.add(
      'manifest question_count=${archive.manifest.questionCount} '
      '与实际 ${archive.records.length} 不一致',
    );
  }
  if (archive.manifest.mediaCount != archive.mediaBytes.length) {
    alerts.add(
      'manifest media_count=${archive.manifest.mediaCount} '
      '与实际 ${archive.mediaBytes.length} 不一致',
    );
  }
  if (unbalancedDollar > 0) {
    alerts.add('$unbalancedDollar 道题的题干美元符数量是奇数（可能公式未闭合）');
  }
  if (recordsSnapshotLike > 0) {
    alerts.add(
      '$recordsSnapshotLike 道题只有 1 张题干图却有多个「［图N］」占位：'
      '这是整卡快照包，详情页应把这张图当「原题整图」，不要内联',
    );
  }
  if (recordsWithPlaceholderOverflow > recordsSnapshotLike) {
    alerts.add(
      '${recordsWithPlaceholderOverflow - recordsSnapshotLike} 道题的「［图N］」'
      '序号超过题干图片数（不是单图快照，可能是缺图）',
    );
  }
  if (recordsWithUnreferencedStemImages > 0) {
    alerts.add(
      '$recordsWithUnreferencedStemImages 道题有题干图片但题干里没有「［图N］」占位',
    );
  }
  if (withAnswerText == 0 && answerImageTotal > 0) {
    alerts.add('答案都是截图（$answerImageTotal 张），没有文字答案');
  }
  if (optionsZero > 0 && questionTypes.containsKey('single_choice')) {
    alerts.add('$optionsZero 道题没有选项');
  }
  if (linkMismatch > 0) {
    alerts.add('$linkMismatch 道题的 source_url 与按 id 重建的详情链接不一致');
  }
  report['alerts'] = alerts;

  final Uint8List encoded = encodeQuestionPackArchive(
    manifest: archive.manifest,
    records: archive.records,
    mediaBytes: archive.mediaBytes,
  );
  final QuestionPackArchive again = decodeQuestionPackArchive(encoded);
  report['reencode_bytes'] = encoded.length;
  report['reencode_record_equal'] =
      _recordsEqual(archive.records, again.records);
  report['reencode_media_equal'] =
      _sameKeys(archive.mediaBytes.keys, again.mediaBytes.keys);

  final String pretty = const JsonEncoder.withIndent('  ').convert(report);
  if (args.length > 1) {
    File(args[1]).writeAsStringSync(pretty);
    stdout.writeln('报告已写入 ${args[1]}');
  }
  stdout.writeln(pretty);
}

void _bump(Map<String, int> map, String key) {
  final String normalized = key.trim().isEmpty ? '(空)' : key.trim();
  map[normalized] = (map[normalized] ?? 0) + 1;
}

Map<String, int> _sortedCounts(Map<String, int> input) {
  final List<MapEntry<String, int>> entries = input.entries.toList()
    ..sort(
      (MapEntry<String, int> a, MapEntry<String, int> b) =>
          b.value.compareTo(a.value),
    );
  return <String, int>{
    for (final MapEntry<String, int> e in entries) e.key: e.value,
  };
}

bool _looksLikeImage(List<int> bytes) {
  if (bytes.length >= 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47) {
    return true;
  }
  if (bytes.length >= 3 &&
      bytes[0] == 0xFF &&
      bytes[1] == 0xD8 &&
      bytes[2] == 0xFF) {
    return true;
  }
  if (bytes.length >= 6 &&
      bytes[0] == 0x47 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46) {
    return true;
  }
  if (bytes.length >= 12 &&
      bytes[0] == 0x52 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x46) {
    return true;
  }
  if (bytes.length >= 2 && bytes[0] == 0x42 && bytes[1] == 0x4D) {
    return true;
  }
  return false;
}

bool _recordsEqual(List<QuestionPackRecord> a, List<QuestionPackRecord> b) {
  if (a.length != b.length) {
    return false;
  }
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}

bool _sameKeys(Iterable<String> a, Iterable<String> b) {
  final Set<String> left = a.toSet();
  final Set<String> right = b.toSet();
  return left.length == right.length && left.containsAll(right);
}
