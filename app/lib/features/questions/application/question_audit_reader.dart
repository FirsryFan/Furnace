/// 题库体检的**读表函数**（纯 Dart，不依赖 Riverpod）+ 两个 provider。
///
/// 为什么单独一个文件：判据/阈值/排序全在
/// `domain/services/questions/question_intake_audit.dart`（纯逻辑，不碰 drift），
/// 这里只负责「把 DB 里的行拼成体检输入」。分工与 `question_corpus_reader.dart` 一致：
/// 题目 → 覆盖知识点一律走 `TaskKnowledgePointResolver`，不在本文件重写规则；
/// 图片数一律数 `attachments` 行（题干 Markdown 内嵌图不算，那正是
/// `h1_figure_missing` 要抓的「文字说如图、库里却没有图」）。
///
/// 全量读取：审计要算跨行重复（H4），`QuestionRepository.all()` 带默认 200 条上限，
/// 用它会漏掉老题、重复也算不出来。题库是本地 SQLite、行数万级以内，一次读完可接受。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/app_database_provider.dart';
import '../../../data/database/database.dart';
import '../../../domain/services/questions/question_intake_audit.dart';
import '../../../domain/services/scheduling/thread_balance_inputs.dart';

/// 一次体检读取快照：体检输入行 + 题库里出现过的学科键。
///
/// [knownSubjectKeys] 用来喂 `subject_unknown` 判据：题库里已有的学科不算未知，
/// 只有「库里别处没出现过、也不是内置学科」的 key 才提示。空集时该判据自动跳过。
class QuestionAuditCorpus {
  const QuestionAuditCorpus({
    required this.rows,
    required this.knownSubjectKeys,
  });

  /// 全部题目（含题干为空的题：空题干本身就是 H1 硬伤，不能在读表时滤掉）。
  final List<QuestionAuditRow> rows;

  /// 题库里出现过的学科 key（去空、去重、排序）。
  final Set<String> knownSubjectKeys;

  bool get isEmpty => rows.isEmpty;
}

/// 读一次全库，拼出体检输入行。
///
/// 顺序按题目 id 稳定排序，体检结论只取决于行内容、不取决于读表顺序。
Future<QuestionAuditCorpus> readQuestionAuditCorpus(AppDatabase db) async {
  final questionRows = await db.select(db.questions).get();
  final optionRows = await db.select(db.questionOptions).get();
  final linkRows = await db.select(db.objectTags).get();
  final attachmentRows = await db.select(db.attachments).get();

  // 题目 → 覆盖知识点：同一标签既挂题目、又挂知识点 → 这道题覆盖那个知识点。
  // 规则只写在这一处（`TaskKnowledgePointResolver`），组卷/相似题/体检共用。
  final pointsByQuestion = TaskKnowledgePointResolver.resolveFromTagLinks(
    <ObjectTagLink>[
      for (final row in linkRows)
        ObjectTagLink(
          tagId: row.tagId,
          objectType: row.objectType,
          objectId: row.objectId,
        ),
    ],
    sourceObjectType: kQuestionObjectType,
  );

  final optionsByQuestion = <String, List<QuestionOption>>{};
  for (final row in optionRows) {
    (optionsByQuestion[row.questionId] ??= <QuestionOption>[]).add(row);
  }
  // 与 `QuestionRepository.optionsOf` 同一口径：sortOrder 升序，平手比 label。
  for (final list in optionsByQuestion.values) {
    list.sort((a, b) {
      final byOrder = a.sortOrder.compareTo(b.sortOrder);
      if (byOrder != 0) return byOrder;
      return a.label.compareTo(b.label);
    });
  }

  final imageCountByQuestion = <String, int>{};
  for (final row in attachmentRows) {
    if (row.ownerType != 'question') continue;
    imageCountByQuestion[row.ownerId] =
        (imageCountByQuestion[row.ownerId] ?? 0) + 1;
  }

  final subjects = <String>{
    for (final row in questionRows)
      if (row.subjectKey.trim().isNotEmpty) row.subjectKey.trim(),
  }.toList()
    ..sort();

  final sortedQuestions = <Question>[...questionRows]
    ..sort((a, b) => a.id.compareTo(b.id));

  return QuestionAuditCorpus(
    rows: <QuestionAuditRow>[
      for (final row in sortedQuestions)
        QuestionAuditRow(
          questionId: row.id,
          serialNo: row.serialNo,
          stem: row.stem,
          answer: row.answer,
          solution: row.solution,
          questionType: row.questionType,
          subjectKey: row.subjectKey,
          sourceLevel: row.sourceLevel,
          sourceLabel: row.sourceLabel,
          year: row.year,
          region: row.region,
          difficulty: row.difficulty,
          aiQuality: row.aiQuality,
          // 空指纹交给体检层：那边会回退到归一化题干比较（H4）。
          stemFingerprint:
              row.stemFingerprint.trim().isEmpty ? null : row.stemFingerprint,
          options: <QuestionAuditOption>[
            for (final option
                in optionsByQuestion[row.id] ?? const <QuestionOption>[])
              QuestionAuditOption(
                label: option.label,
                content: option.content,
                isCorrect: option.isCorrect,
              ),
          ],
          knowledgePointIds: pointsByQuestion[row.id] ?? const <String>[],
          imageCount: imageCountByQuestion[row.id] ?? 0,
          state: row.state,
        ),
    ],
    knownSubjectKeys: <String>{...subjects},
  );
}

/// 体检输入行（题库列表徽标、题目详情页展开证据都从这里取）。
final questionAuditCorpusProvider = FutureProvider<QuestionAuditCorpus>((ref) {
  return readQuestionAuditCorpus(ref.watch(appDatabaseProvider));
});

/// 整库体检报告。`currentYear` 取系统年份（年份越界判据要它），
/// 已知学科取题库自身出现过的 key。
final questionAuditReportProvider = FutureProvider<QuestionAuditReport>((
  ref,
) async {
  final corpus = await ref.watch(questionAuditCorpusProvider.future);
  return QuestionIntakeAudit(
    currentYear: DateTime.now().year,
    knownSubjectKeys: corpus.knownSubjectKeys,
    knownSourceLevels: kQuestionAuditKnownSourceLevels,
  ).audit(corpus.rows);
});
