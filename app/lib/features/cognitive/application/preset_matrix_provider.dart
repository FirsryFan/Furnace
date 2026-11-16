import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/services/cognitive/preset_matrix.dart';

/// 读取 `assets/preset-ability-matrix.json` 的只读 provider。
///
/// 这是 seed 读取层，不是“矩阵已完成”的声明：没有 measured 的 KP 仍是
/// unknown，preset_global 仍是全局先验。
final presetMatrixSeedProvider =
    FutureProvider<PresetMatrixSeed>((ref) async {
  final raw = await rootBundle.loadString('assets/preset-ability-matrix.json');
  final decoded = jsonDecode(raw);
  if (decoded is! Map) {
    throw const FormatException('preset-ability-matrix.json 顶层不是对象');
  }
  return PresetMatrixSeed.fromJson(decoded.cast<String, Object?>());
});
