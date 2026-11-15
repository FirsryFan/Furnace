import 'package:flutter/services.dart' show rootBundle;

import '../domain/preset_scoring.dart';

/// 预设卡数据的来源（接口很小，widget 测试可以注入 fixture，不碰 asset bundle）。
abstract class PresetScoringSource {
  Future<PresetScoringData> load();
}

/// 读取随包发布的精简 JSON asset。
///
/// asset 由工作区脚本 `.work/preset-ui/build_preset_asset.py` 从
/// `PRESET-SCORING-2026-11-15.json` 生成；静态只读，不联网、不写库。
class AssetPresetScoringSource implements PresetScoringSource {
  const AssetPresetScoringSource({this.assetPath = defaultAssetPath});

  static const String defaultAssetPath = 'assets/preset_scoring.json';

  final String assetPath;

  @override
  Future<PresetScoringData> load() async {
    final raw = await rootBundle.loadString(assetPath);
    return PresetScoringData.decode(raw);
  }
}
