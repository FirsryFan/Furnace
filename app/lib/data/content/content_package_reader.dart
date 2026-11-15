/// 内容包读目录（工作区 `content-store/<subject>/Q-…/`）。
///
/// 位置在 `data/` 而不是 domain：`lib/domain/**` 的既有约定是不碰 `dart:io`
/// （唯一例外是 `domain/services/web/web_http.dart`），而读内容包必须碰文件。
/// 解析口径不在这里——`ContentPackage.fromJson` 是纯函数，本类只负责「找到哪两
/// 个文件、读成什么 JSON」。
///
/// 输入形态：
/// ```
/// <dir>/question.json
/// <dir>/boards/<subject>-board.json
/// ```
/// board 缺失不是致命错误：内容包可以只有 L1（没有 DAG/错因，卡片生成时这批
/// 节点就是空的），导入服务会把它记成 `board_missing` 的跳过项。
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../domain/services/content/content_package.dart';

/// 一次目录读取的结果：内容包 + 读取过程中的非致命事实。
class ContentPackageReadResult {
  const ContentPackageReadResult({
    required this.package,
    required this.questionPath,
    this.boardPath,
    this.warnings = const <String>[],
  });

  final ContentPackage package;
  final String questionPath;
  final String? boardPath;

  /// 非致命问题（board 缺失、board 路径指向不存在的文件等）。
  final List<String> warnings;
}

/// 内容包目录读取器（同步、只读、不写盘）。
class ContentPackageReader {
  const ContentPackageReader();

  /// 读 [directory] 下的 `question.json` 与（若存在的）学科板。
  ///
  /// 目录 / `question.json` 不存在、JSON 坏掉、契约字段不合法都抛
  /// [FormatException] 或 [FileSystemException]：调用方应当先确认包存在，
  /// 再决定要不要进入导入事务。
  ContentPackageReadResult readDirectory(String directory) {
    final root = Directory(directory);
    final questionFile = File(p.join(root.path, 'question.json'));
    if (!questionFile.existsSync()) {
      throw FileSystemException('内容包缺少 question.json', questionFile.path);
    }
    final question = _decode(questionFile);
    final subject = question['subject']?.toString().trim() ?? '';
    final warnings = <String>[];

    Map<String, Object?>? board;
    String? boardPath;
    final localBoard = File(
      p.join(root.path, 'boards', '$subject-board.json'),
    );
    if (subject.isNotEmpty && localBoard.existsSync()) {
      board = _decode(localBoard);
      boardPath = localBoard.path;
    } else {
      // 工作区里的 `panels.board_refs.<subject>.path` 是仓库相对 POSIX 路径，
      // 只有在「当前目录就是工作区根」时才能直接读到；读不到就如实告警，
      // 不猜别的包。
      final candidate = _boardPathFromQuestion(question, subject);
      if (candidate != null) {
        final file = File(candidate);
        if (file.existsSync()) {
          board = _decode(file);
          boardPath = file.path;
        } else {
          warnings.add('board 缺失：$candidate');
        }
      } else {
        warnings.add('board 缺失：boards/$subject-board.json');
      }
    }

    return ContentPackageReadResult(
      package: ContentPackage.fromJson(question, board: board),
      questionPath: questionFile.path,
      boardPath: boardPath,
      warnings: warnings,
    );
  }

  /// [readDirectory] 的容错版：目录不存在 / 读不了时返回 null（批量扫描用）。
  ContentPackageReadResult? readDirectoryOrNull(String directory) {
    try {
      return readDirectory(directory);
    } on FileSystemException {
      return null;
    } on FormatException {
      return null;
    }
  }

  static Map<String, Object?> _decode(File file) {
    final Object? decoded;
    try {
      decoded = jsonDecode(file.readAsStringSync());
    } on FormatException catch (error) {
      throw FormatException('${file.path} 不是合法 JSON：${error.message}');
    }
    if (decoded is! Map) {
      throw FormatException('${file.path} 顶层应为 JSON 对象');
    }
    return decoded.cast<String, Object?>();
  }

  static String? _boardPathFromQuestion(
    Map<String, Object?> question,
    String subject,
  ) {
    final panels = question['panels'];
    if (panels is! Map) {
      return null;
    }
    final boardRefs = panels['board_refs'];
    if (boardRefs is! Map) {
      return null;
    }
    final boardRef = boardRefs[subject];
    if (boardRef is! Map) {
      return null;
    }
    final raw = boardRef['path']?.toString().trim() ?? '';
    return raw.isEmpty ? null : raw.replaceAll('/', Platform.pathSeparator);
  }
}
