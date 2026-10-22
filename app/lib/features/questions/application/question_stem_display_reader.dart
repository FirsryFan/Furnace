/// 题干「一行显示文本」的读表函数（纯读表，不依赖 Riverpod，不碰 dart:io）。
///
/// 组卷候选、相似题、能力动作题、收题页列表这些地方只有题干字符串，没有题名/图片
/// 元数据；整卡快照包的题干是「1 张大图 + 若干［图N］占位」，直接显示原文就是
/// 「…… ［图12］ ……」。这里一次读题目 + 题干图张数，投影成
/// [QuestionStemDisplay]（列表文本由 `question_stem_display.dart` 的纯函数决定）。
///
/// 为什么不在 UI 里各自读：attachments 的计数是同一份口径（ownerType='question'，
/// role 为 NULL 或 'stem'），散落四五个页面必然分叉；provider 只负责「数据版本 + 调它」。
/// 刻意不读图片字节、不拿像素尺寸：列表显示只需要 B2（1 图 + 占位≥2），判 B1 要读
/// 每张图——列表不值得为判定去读几十 MB。
library;

import 'package:drift/drift.dart';

import '../../../data/database/database.dart';
import '../../../domain/services/questions/question_stem_display.dart';

/// 题目 id → 列表用题干显示文本。只查题干与题干图张数，不读图片字节。
///
/// [questionIds] 非空时只读这些题（trim、去空、忽略未知 id）；空集合返回空 map，
/// 不传（null）读全表。[maxLength] 透传给显示文本的截断规则。
Future<Map<String, QuestionStemDisplay>> readQuestionStemDisplays(
  AppDatabase db, {
  Set<String>? questionIds,
  int maxLength = 60,
}) async {
  final wanted = questionIds == null
      ? null
      : <String>{
          for (final id in questionIds)
            if (id.trim().isNotEmpty) id.trim(),
        };
  if (wanted != null && wanted.isEmpty) {
    return const <String, QuestionStemDisplay>{};
  }

  final query = db.select(db.questions);
  if (wanted != null) {
    query.where((t) => t.id.isIn(wanted));
  }
  final rows = await query.get();
  if (rows.isEmpty) return const <String, QuestionStemDisplay>{};

  final counts = await _stemImageCountsOf(db, wanted);
  return <String, QuestionStemDisplay>{
    for (final row in rows)
      row.id: resolveQuestionStemDisplay(
        stem: row.stem,
        imageCount: counts[row.id] ?? 0,
        maxLength: maxLength,
      ),
  };
}

/// 题干图张数：ownerType='question'，role 为 NULL（v27 前旧行）或 'stem' 才算。
/// 答案/解析截图不参与快照判定；[wanted] 非空时只统计这些题。
Future<Map<String, int>> _stemImageCountsOf(
  AppDatabase db,
  Set<String>? wanted,
) async {
  final count = db.attachments.id.count();
  final query = db.selectOnly(db.attachments)
    ..addColumns([db.attachments.ownerId, count])
    ..groupBy([db.attachments.ownerId])
    ..where(db.attachments.ownerType.equals('question') &
        (db.attachments.role.isNull() | db.attachments.role.equals('stem')));
  if (wanted != null) {
    query.where(db.attachments.ownerId.isIn(wanted));
  }
  final rows = await query.get();
  return <String, int>{
    for (final row in rows)
      if ((row.read(count) ?? 0) > 0)
        row.read(db.attachments.ownerId)!: row.read(count) ?? 0,
  };
}
