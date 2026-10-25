import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/state/data_revision.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../domain/services/cognitive/user_persona.dart';

/// 用户自我描述（schema v35，轮次一百七十二）。
///
/// 读到的永远是**归一化后**的文本或 `null`：
/// - `null` = 用户没写过（不是空字符串），AI 提示不带任何 persona 段落；
/// - 空串同理翻成 `null`，保证「没写」只有一种表示。
///
/// `watchDatabaseRevision()`：保存/清除之后自动重读，页面不必手动 invalidate。
/// AI 那一侧在 `AgentLoop._turnTools` 里直接读库（同一份归一化口径）。
final userPersonaProvider = FutureProvider.autoDispose<String?>((ref) async {
  ref.watchDatabaseRevision();
  final raw = await ref.watch(settingsRepositoryProvider).getUserPersona();
  if (raw == null) {
    return null;
  }
  final normalized = normalizeUserPersona(raw);
  return normalized.isEmpty ? null : normalized;
});
