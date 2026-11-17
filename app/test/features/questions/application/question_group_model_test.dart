@Tags(<String>['question-group-blocked'])
library;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart' show NativeDatabase;
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/features/questions/application/question_library_reader.dart';
import 'package:furnace/features/questions/application/question_corpus_reader.dart';

/// **故意失败**的题组模型测试（2026-11-17）。
///
/// 用户口径：英语阅读 A 篇、语文现代文阅读 II 这种「一篇文章 + 若干小问」必须是
/// **一道题**（题组），组卷的 3 精研 / 6 速刷按**合题**计数，不是按小问计数。
///
/// 现状（证据：真实库 `E:\Furnace\data\furnace.db`，schema v47）：
///  * `questions` 表（`tables.dart:1292-1419`）没有题组/材料/父题列；唯一像父题的是
///    `extension_of`，语义是「扩展题挂靠的组卷网母题号」，不是「这篇阅读的小问」；
///  * 整卷导入把材料内联进**每道小问**的 stem（`【材料 S1-M1】\n…`），
///    两道小问 = 两行题 → 主题库/组卷都按小问计数。
///
/// 所以本轮**不硬拆**：模型缺失时不能靠 UI 拼字符串假装成题组。这个文件是
/// **失败测试**（红），用来钉住「必须实现什么才算修好」，实现模型后应转绿。
///
/// 最小 schema + 迁移方案（未落地，因为 `database.dart/tables.dart` 正被
/// `tag-tree-collapse` 与 `question-detail` 同时改，schema 锁冲突；落地时按此做）：
///
/// ```text
/// -- 迁移 v49（在 v48 之后追加，AddColumn 可空、不回填老数据）
/// ALTER TABLE questions ADD COLUMN group_id TEXT;        -- NULL = 独立题
/// ALTER TABLE questions ADD COLUMN group_order INTEGER;  -- 小问在该组内的顺序
/// CREATE TABLE question_groups (
///   id TEXT NOT NULL PRIMARY KEY,
///   kind TEXT NOT NULL DEFAULT 'reading',  -- reading | cloze | material
///   material_md TEXT NOT NULL,             -- 文章/材料原文（Markdown）
///   material_ids TEXT,                     -- 语文 material_ids JSON 数组
///   source_label TEXT NOT NULL DEFAULT '',
///   created_at INTEGER NOT NULL,
///   updated_at INTEGER NOT NULL
/// );
/// -- 迁移只用 m.addColumn + m.createTable，不回填；
/// -- 回填脚本（一次性 tool）按「source_label + 相同材料前缀」把现有小问归组，
/// -- 并把材料从 stem 里剥到 question_groups.material_md。
/// ```
///
/// 读侧改动：
///  * `readQuestionLibrary` 按 `group_id` 聚合成一个 `QuestionGroupEntry`（材料 + 小问），
///    列表/组卷计数 = 题组数；小问仍可单独打开；
///  * `readPaperCorpus` / `PaperComposer` 的候选单位改成题组，`PaperPlan.items`
///    计一道题组（3 精研 / 6 速刷按合题）。
///
/// 运行方式：
///  * 默认 `flutter test test/features/questions` **会跑这个文件并失败**（这是刻意的
///    证据，不是回归）；
///  * 想跑绿其余测试：`flutter test test/features/questions --exclude-tags
///    question-group-blocked`。
///
/// 下面两个测试用现有 API 断言「现在是 2 行 = 拆开的状态」，期望值是**修好后的
/// 1 个题组**，所以现在会失败；实现题组模型后改成 `findsOneGroup` 的 API 即可转绿。
void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });
  tearDown(() async {
    await db.close();
  });

  Future<void> seedSubQuestion(
    String id, {
    required String material,
    required String stem,
    required int order,
    String subject = 'chinese',
  }) {
    return db.into(db.questions).insert(
          QuestionsCompanion.insert(
            id: id,
            // 现状：整卷导入把材料内联进每道小问的 stem。
            stem: '$material\n\n$stem',
            subjectKey: Value(subject),
            sourceLabel: const Value('2025 全国 I 卷'),
            createdAt: 1700000000000,
            updatedAt: 1700000000000,
            answer: const Value('参考答案'),
            solution: const Value('解析'),
            serialNo: Value(order),
          ),
        );
  }

  test('语文现代文阅读 II：材料 + 2 个小问应读成 1 道题（题组）', () async {
    const material = '【材料 S1-M1】\n种植入门问答 凡种植…';
    await seedSubQuestion(
      'q-modern-1',
      material: material,
      stem: '（1）下列对材料相关内容的理解，正确的一项是（ ）',
      order: 1,
    );
    await seedSubQuestion(
      'q-modern-2',
      material: material,
      stem: '（2）请结合材料谈谈你的看法。',
      order: 2,
    );

    final snapshot = await readQuestionLibrary(db);

    // 现状：2 条独立题（被拆成小问）。
    // 期望：1 个题组（文章 + 2 小问 = 一道题），组内小问数 2。
    expect(
      snapshot.entries.length,
      1,
      reason: '期望 1 个题组；现状是 ${snapshot.entries.length} 行小问。'
          '题组模型缺失：questions 表没有 group_id，见本文件顶部的 schema 方案。',
    );
  });

  test('组卷候选按「合题」计数：同材料 2 个小问只占 1 个题额', () async {
    const material = '【材料 S1-M1】\n阅读下面的文字，完成下列小题。';
    await seedSubQuestion(
      'q-c-1',
      material: material,
      stem: '（1）对文中画线句理解最恰当的一项是（ ）',
      order: 1,
    );
    await seedSubQuestion(
      'q-c-2',
      material: material,
      stem: '（2）文章结尾有何作用？',
      order: 2,
    );

    final corpus = await readPaperCorpus(db);

    // 现状：candidates 是 2（按小问计数），组卷凑 3 精研 / 6 速刷会多算题。
    // 期望：候选单位是题组，2 个小问共享 1 个题组 id → 1 个候选。
    expect(
      corpus.candidates.length,
      1,
      reason: '期望卷子按合题计数（1 个题组）；现状候选数 '
          '${corpus.candidates.length}，因为 readPaperCorpus 按 questions 行计数。',
    );
  });
}
