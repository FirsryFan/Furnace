/// 设置页共享的读侧 provider。
///
/// 2026-11-15 设置页重构时从 `settings_page.dart` 拆出来：档案卡、数据区
/// 都要读/刷新同一个 profile，页面本身不再负责提供它，避免
/// `data_section -> settings_page` 这种为了一个 provider 的反向依赖。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/state/data_revision.dart';
import '../../../data/database/database.dart';
import '../../../data/repositories/repository_providers.dart';

/// 本机档案（`profiles` 单行）。null = 还没有档案行。
final currentProfileProvider = FutureProvider<Profile?>((ref) {
  ref.watchDatabaseRevision();
  return ref.watch(settingsRepositoryProvider).getProfile();
});
