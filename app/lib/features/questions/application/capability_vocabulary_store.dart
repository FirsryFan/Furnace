/// 能力动作词表（用户自定义 overlay）的本地持久化 + 只读 Provider。
///
/// 词表本身是纯逻辑（`domain/services/reasoning/capability_action_overlay.dart`），
/// 这里只负责三件事：从 `local_settings.capability_action_overlay_json`（schema
/// v25）读出 JSON、宽容解析成 [CapabilityActionOverlay]、把整份词表写回去。
///
/// 契约与其它可空偏好同源：**NULL = 用户没改过 = 空 overlay = 内置种子词表**。
/// 坏 JSON、空串、解析不出 customActions 一律读作空 overlay 而不是抛错——词表是
/// 锦上添花的东西，不能让它挡住任何一次解题（`docs/REASONING_LAYER_DESIGN.md`
/// §4）。
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/repository_providers.dart';
import '../../../data/repositories/settings_repository.dart';
import '../../../domain/services/reasoning/capability_action_overlay.dart';

/// 读/写 `local_settings.capability_action_overlay_json`。
///
/// 单行设置的读写全部走 [SettingsRepository]：这里是唯一知道"这一列存的是什么
/// 格式"的地方（`CapabilityActionOverlay.toJson` 的 JSON 原文），推理服务与将来
/// 的词表编辑界面都从这里拿数据。
class CapabilityVocabularyStore {
  CapabilityVocabularyStore(this._settings);

  final SettingsRepository _settings;

  /// 读出用户的词表；没有行 / 列为 NULL / 坏 JSON 都返回 [CapabilityActionOverlay.empty]。
  Future<CapabilityActionOverlay> load() async {
    final settings = await _settings.getSettings();
    final json = settings?.capabilityActionOverlayJson;
    if (json == null || json.trim().isEmpty) {
      return CapabilityActionOverlay.empty;
    }
    Object? decoded;
    try {
      decoded = jsonDecode(json);
    } on FormatException {
      return CapabilityActionOverlay.empty;
    }
    // fromJson 本身对结构错误宽容，永不抛异常；这里只兜住 JSON 语法错误。
    return CapabilityActionOverlay.fromJson(decoded);
  }

  /// 写入整份词表。
  ///
  /// 空 overlay 写 NULL（回到出厂词表），不写空 JSON 对象：这样数据库里"从未改过"
  /// 与"改成空的"是同一个可空状态，与 schema 的 NULL 契约一致。调用方写完后
  /// invalidate [capabilityActionOverlayProvider]，否则这次运行的推理还会吃旧词表。
  Future<void> save(CapabilityActionOverlay overlay) async {
    await _settings.ensureSettings();
    await _settings.updateCapabilityActionOverlayJson(
      overlay.isEmpty ? null : jsonEncode(overlay.toJson()),
    );
  }
}

/// 词表存储；测试可 override 成假 settings 仓储（或直接塞内存数据库）。
final capabilityVocabularyStoreProvider =
    Provider<CapabilityVocabularyStore>((ref) {
  return CapabilityVocabularyStore(ref.watch(settingsRepositoryProvider));
});

/// 当前生效的用户词表（读侧）。
///
/// 不用 autoDispose：一次运行里词表被推理服务反复读，缓存一份够了；写侧保存后
/// 显式 invalidate 才会重读。词表是纯本地数据，读一次只查一行，缓不缓存都不贵，
/// 但缓存让"保存 → 下一次解题"的语义成为"保存即生效"。
final capabilityActionOverlayProvider =
    FutureProvider<CapabilityActionOverlay>((ref) {
  return ref.watch(capabilityVocabularyStoreProvider).load();
});
