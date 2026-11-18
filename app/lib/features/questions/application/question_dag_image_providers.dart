/// 详情页「思维 DAG 图片」的 provider：一个渲染器 + 一个落盘 store。
///
/// 目录走 `AppStorage.supportDirectory`（Windows 落 `E:\Furnace\data`，其它平台
/// 走 path_provider）。测试 override [questionDagImageSupportDirectoryProvider]
/// 指到临时目录，不去碰真实数据目录。
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/storage/app_storage.dart';
import '../data/dag_image_store.dart';
import 'dag_image_renderer.dart';

/// app support 目录（与题库配图同一个口径，单独成 provider 才能替换）。
final questionDagImageSupportDirectoryProvider =
    Provider<Future<Directory> Function()>((ref) {
  return AppStorage.supportDirectory;
});

/// 思维链 → PNG 的渲染器。
final dagImageRendererProvider = Provider<DagImageRenderer>((ref) {
  return DagImageRenderer();
});

/// 图片落盘 store（缓存 + 写文件）。
final questionDagImageStoreProvider = Provider<DagImageStore>((ref) {
  return DagImageStore(
    renderer: ref.watch(dagImageRendererProvider),
    supportDirectory: ref.watch(questionDagImageSupportDirectoryProvider),
  );
});
