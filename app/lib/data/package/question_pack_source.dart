/// 题库包（.tqb）导出：把题库读成一组 [QuestionPackRecord] 加媒体字节（数据层）。
///
/// 导出只读：题目行、选项行、标签行、标签边、`attachments` 行各读一次，媒体字节
/// 交给调用方注入的读取函数（真实环境是 `QuestionMediaStore.readBytes`）。这样
/// 本文件不 import dart:io、不依赖 Riverpod：测试给一个内存函数就能跑。
///
/// 排序口径：题目按题号升序，**没有题号的排最后**，同组按 id 升序。这个次序是
/// 包内媒体路径 `media/q<题序>/<图序>.<ext>` 里「题序」的唯一来源——导出与导入
/// 都按同一份记录顺序看包，顺序必须确定性。
///
/// 不静默丢内容：扩展名不认识、媒体文件读不到的配图会记进 [QuestionPackSourceSnapshot.warnings]
/// 并计入 [QuestionPackSourceSnapshot.skippedMedia]，不会让整包失败。
library;

import 'dart:typed_data';

import '../../domain/services/package/question_pack_plan.dart';
import '../../domain/services/package/question_pack_record.dart';
import '../../domain/services/package/question_pack_selection.dart';
import '../database/database.dart';
import '../repositories/question_repository.dart';

/// 读取一个相对路径的媒体字节；文件不在了返回 null。
typedef QuestionPackMediaBytesReader = Future<Uint8List?> Function(
  String relPath,
);

/// 题库包里允许的图片扩展名（与 domain 层规范路径的白名单一致）。
const Set<String> kQuestionPackMediaExtensions = <String>{
  'png',
  'jpg',
  'jpeg',
  'gif',
  'webp',
  'bmp',
  'heic',
};

/// 一次导出的快照。
class QuestionPackSourceSnapshot {
  const QuestionPackSourceSnapshot({
    required this.records,
    required this.mediaBytes,
    required this.skippedMedia,
    required this.warnings,
  });

  /// 题目记录（题号升序、无号最后）。
  final List<QuestionPackRecord> records;

  /// 包内媒体路径 → 字节；键就是 [QuestionPackMedia.packPath]。
  final Map<String, Uint8List> mediaBytes;

  /// 想导出但没导出的配图张数（扩展名不认识 / 读不到字节）。
  final int skippedMedia;

  /// 人读的告警，顺序与题目顺序一致。
  final List<String> warnings;

  bool get isEmpty => records.isEmpty;

  int get questionCount => records.length;

  int get mediaCount => mediaBytes.length;

  bool get hasWarnings => warnings.isNotEmpty;
}

/// 从题库读出（可按 [selection] 与 [questionIds] 筛选的）题目与它们的配图字节。
///
/// 筛选在解码配图字节**之前**做：没选中的题不会读磁盘上的图片文件。
/// 包内题号按筛选后的顺序从 1 重新编号——包只是一次导出的子集，不是题库快照。
///
/// [questionIds] 是界面「多选后导出选中」用的显式集合：非空时只保留这些题目，
/// 集合里的未知 id 直接忽略；空集合表示不按 id 约束（与 [selection] 取交集）。
Future<QuestionPackSourceSnapshot> readQuestionPackSource({
  required AppDatabase database,
  required QuestionPackMediaBytesReader readMedia,
  QuestionPackSelection selection = const QuestionPackSelection(),
  Set<String> questionIds = const <String>{},
}) async {
  final questionRows = await database.select(database.questions).get();
  final optionRows = await database.select(database.questionOptions).get();
  final tagRows = await database.select(database.tags).get();
  final linkRows = await database.select(database.objectTags).get();
  final attachmentRows = await database.select(database.attachments).get();

  final optionsByQuestion = <String, List<QuestionPackOption>>{};
  for (final row in optionRows) {
    (optionsByQuestion[row.questionId] ??= <QuestionPackOption>[]).add(
      QuestionPackOption(
        label: row.label.trim().toUpperCase(),
        content: row.content,
        isCorrect: row.isCorrect,
        sortOrder: row.sortOrder,
      ),
    );
  }
  for (final list in optionsByQuestion.values) {
    list.sort((a, b) {
      final byOrder = a.sortOrder.compareTo(b.sortOrder);
      return byOrder != 0 ? byOrder : a.label.compareTo(b.label);
    });
  }

  final pathByTagId = <String, String>{};
  for (final row in tagRows) {
    final path = row.path?.trim() ?? '';
    if (path.isEmpty) continue;
    pathByTagId[row.id] = path;
  }

  final tagIdsByQuestion = <String, Set<String>>{};
  for (final row in linkRows) {
    if (row.objectType != 'question') continue;
    (tagIdsByQuestion[row.objectId] ??= <String>{}).add(row.tagId);
  }

  final attachmentsByQuestion = <String, List<Attachment>>{};
  for (final row in attachmentRows) {
    if (row.ownerType != 'question') continue;
    (attachmentsByQuestion[row.ownerId] ??= <Attachment>[]).add(row);
  }
  for (final list in attachmentsByQuestion.values) {
    list.sort((a, b) {
      final byOrder = a.sortOrder.compareTo(b.sortOrder);
      if (byOrder != 0) return byOrder;
      final byCreated = a.createdAt.compareTo(b.createdAt);
      return byCreated != 0 ? byCreated : a.id.compareTo(b.id);
    });
  }

  final wantedIds = <String>{
    for (final id in questionIds)
      if (id.trim() case final String trimmed when trimmed.isNotEmpty) trimmed,
  };

  final ordered = <Question>[
    for (final question
        in (List<Question>.of(questionRows)..sort(_compareQuestions)))
      if ((wantedIds.isEmpty || wantedIds.contains(question.id)) &&
          questionPackFieldsMatchSelection(
            subjectKey: question.subjectKey,
            sourceLevel: question.sourceLevel,
            serialNo: question.serialNo,
            tagPaths: <String>[
              for (final tagId
                  in tagIdsByQuestion[question.id] ?? const <String>{})
                if (pathByTagId[tagId] case final String path) path,
            ],
            selection: selection,
          ))
        question,
  ];

  final records = <QuestionPackRecord>[];
  final mediaBytes = <String, Uint8List>{};
  final warnings = <String>[];
  var skippedMedia = 0;

  for (var index = 0; index < ordered.length; index++) {
    final question = ordered[index];
    final recordNumber = index + 1;
    final label = question.serialNo == null
        ? '第 $recordNumber 道题'
        : '第 $recordNumber 道题（TR-${question.serialNo.toString().padLeft(5, '0')}）';

    final tagPaths = <String>[
      for (final tagId in tagIdsByQuestion[question.id] ?? const <String>{})
        if (pathByTagId[tagId] case final String path) path,
    ]..sort();

    final media = <QuestionPackMedia>[];
    final attachments =
        attachmentsByQuestion[question.id] ?? const <Attachment>[];
    for (final attachment in attachments) {
      final extension = _mediaExtensionOf(attachment.relPath);
      if (extension == null) {
        skippedMedia++;
        warnings.add('$label 的配图 ${attachment.relPath} 扩展名不认识，没有导出');
        continue;
      }
      final bytes = await readMedia(attachment.relPath);
      if (bytes == null || bytes.isEmpty) {
        skippedMedia++;
        warnings.add('$label 的配图 ${attachment.relPath} 读不到字节，没有导出');
        continue;
      }
      final packPath = questionPackMediaPath(
        questionIndex: recordNumber,
        mediaIndex: media.length,
        extension: extension,
      );
      media.add(QuestionPackMedia(
        packPath: packPath,
        fileName: _fileNameOf(attachment.relPath),
        mime: attachment.mime,
        role: _mediaRoleOf(attachment.role),
        sortOrder: attachment.sortOrder,
      ));
      mediaBytes[packPath] = bytes;
    }

    records.add(QuestionPackRecord(
      stem: question.stem,
      answer: question.answer,
      solution: question.solution,
      subjectKey: question.subjectKey,
      questionType: question.questionType,
      sourceLevel: question.sourceLevel,
      sourceLabel: question.sourceLabel,
      year: question.year,
      region: question.region,
      difficulty: question.difficulty,
      difficultySource: question.difficultySource,
      trapNote: question.trapNote,
      origin: question.origin,
      state: question.state,
      serialNo: question.serialNo,
      sourceUrl: question.sourceUrl,
      zujuanQuestionId: question.zujuanQuestionId,
      zujuanBankId: question.zujuanBankId,
      // 库里 NULL 的 textFormat 语义就是 plain，导出时写成显式 'plain' 便于
      // 包自己说清楚排版方式（toJson 里 plain 不落键，历史包逐字节仍不变）。
      textFormat: question.textFormat ?? 'plain',
      extensionOf: question.extensionOf,
      capability: decodeQuestionCapability(question.capability),
      options: optionsByQuestion[question.id] ?? const <QuestionPackOption>[],
      tagPaths: tagPaths,
      media: media,
    ));
  }

  return QuestionPackSourceSnapshot(
    records: List<QuestionPackRecord>.unmodifiable(records),
    mediaBytes: Map<String, Uint8List>.unmodifiable(mediaBytes),
    skippedMedia: skippedMedia,
    warnings: List<String>.unmodifiable(warnings),
  );
}

/// 题号有号在前、无号在后；同组按 id（稳定顺序，不依赖时间）。
int _compareQuestions(Question a, Question b) {
  final aSerial = a.serialNo;
  final bSerial = b.serialNo;
  if (aSerial != null && bSerial != null) {
    final bySerial = aSerial.compareTo(bSerial);
    if (bySerial != 0) return bySerial;
  } else if (aSerial != null) {
    return -1;
  } else if (bSerial != null) {
    return 1;
  }
  return a.id.compareTo(b.id);
}

String _fileNameOf(String relPath) {
  final slash = relPath.lastIndexOf('/');
  return slash < 0 ? relPath : relPath.substring(slash + 1);
}

String? _mediaExtensionOf(String relPath) {
  final name = _fileNameOf(relPath);
  final dot = name.lastIndexOf('.');
  if (dot < 0 || dot == name.length - 1) return null;
  final extension = name.substring(dot + 1).trim().toLowerCase();
  return kQuestionPackMediaExtensions.contains(extension) ? extension : null;
}

/// 库里存过的未知角色一律按题干配图处理：包格式只认 stem/answer/solution，
/// 不认识的写进去会让导入侧整包拒绝。
String _mediaRoleOf(String? stored) {
  final role = stored?.trim() ?? '';
  switch (role) {
    case 'stem':
    case 'answer':
    case 'solution':
      return role;
    default:
      return 'stem';
  }
}
