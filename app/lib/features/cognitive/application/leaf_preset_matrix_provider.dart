import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/services/cognitive/leaf_preset_matrix.dart';

/// 读取 `assets/leaf-preset-matrix.json` 的只读 provider。
final leafPresetMatrixProvider =
    FutureProvider<LeafPresetMatrixSeed>((ref) async {
  final raw = await rootBundle.loadString('assets/leaf-preset-matrix.json');
  final decoded = jsonDecode(raw);
  if (decoded is! Map) {
    throw const FormatException('leaf-preset-matrix.json 顶层不是对象');
  }
  return LeafPresetMatrixSeed.fromJson(decoded.cast<String, Object?>());
});
