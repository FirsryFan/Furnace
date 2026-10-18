/// 题库配图的 provider：唯一一个 `QuestionMediaStore` 实例。
///
/// 页面写、详情读、删题清图都走同一个实例——多个实例就是多套"文件在哪儿"的
/// 想法。测试通过 override `appDatabaseProvider` 与
/// `questionMediaSupportDirectoryProvider` 指到临时目录。
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../data/database/app_database_provider.dart';
import '../data/question_media_store.dart';

/// app support 目录。单独成一个 provider，测试才能把它指到临时目录，不去碰
/// 真实的 app 数据目录（与拍照整理那条通路的
/// `questionIntakeSupportDirectoryProvider` 同一个口径）。
final questionMediaSupportDirectoryProvider =
    Provider<Future<Directory> Function()>((ref) {
  return getApplicationSupportDirectory;
});

/// 题目配图的 store。
final questionMediaStoreProvider = Provider<QuestionMediaStore>((ref) {
  return QuestionMediaStore(
    database: ref.watch(appDatabaseProvider),
    supportDirectory: ref.watch(questionMediaSupportDirectoryProvider),
  );
});
