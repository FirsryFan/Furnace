/// 题库排序偏好的读写（schema v34，轮次一百六十八）。
///
/// 偏好落盘的唯一理由：用户选过「按题号」之后，重启不该回到「最新在前」
/// （`docs/QUESTION_BANK_DESIGN.md` §42.3 的边界）。读侧把 NULL / 未知 code
/// 统一翻成出厂档位（[questionLibrarySortFromStorage]）；写侧由页面在用户
/// 切换排序时调用 [SettingsRepository.updateQuestionLibrarySortMode]。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/state/data_revision.dart';
import '../../../data/repositories/repository_providers.dart';
import 'question_library_sort.dart';

/// 已落盘的题库排序偏好；没存过就是出厂「最新在前」。
///
/// `watchDatabaseRevision()`：写库之后（包括用户自己切排序）自动重读，
/// 页面不必手动 invalidate。
final questionLibrarySortPreferenceProvider =
    FutureProvider.autoDispose<QuestionLibrarySort>((ref) async {
  ref.watchDatabaseRevision();
  final repository = ref.watch(settingsRepositoryProvider);
  return questionLibrarySortFromStorage(
    await repository.getQuestionLibrarySortMode(),
  );
});
