/// 题干「一行显示文本」的数据入口：数据版本变化后重读一次，页面各自取 map。
///
/// 读表本身在 `question_stem_display_reader.dart`（纯函数，AI 工具/页面都能直接用）；
/// 这里只是 Riverpod 的「数据版本 + 调它」，与 `paper_plan_provider.dart` 的
/// `questionStemsProvider` 同一写法。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/state/data_revision.dart';
import '../../../data/database/app_database_provider.dart';
import '../../../domain/services/questions/question_stem_display.dart';
import 'question_stem_display_reader.dart';

export 'question_stem_display_reader.dart' show readQuestionStemDisplays;
export '../../../domain/services/questions/question_stem_display.dart'
    show QuestionStemDisplay, resolveQuestionStemDisplay;

/// 题目 id → 列表用题干显示文本。一次读全表（列表/候选区本来就要全覆盖）；
/// 只想读少量题时直接调 [readQuestionStemDisplays] 并传 `questionIds`。
final questionStemDisplayProvider =
    FutureProvider.autoDispose<Map<String, QuestionStemDisplay>>((ref) async {
  ref.watchDatabaseRevision();
  return readQuestionStemDisplays(ref.watch(appDatabaseProvider));
});
