/// 题目配图：把图片放进 app support 下按题目分目录的位置，并在 `attachments`
/// 表里记一行（`ownerType = 'question'`、`ownerId = <questionId>`）。
///
/// 为什么不复用 `HandwritingIntakeStore`：那个 store 的主人是"还没确认的收题页"
/// （`ownerType = 'handwriting_intake'`、`ownerId` 空），图片要在题目存在之前就
/// 落盘（等 OCR 之后再结构化成题干）；这里的图片属于一道**已经入库**的题，按
/// 题目分目录、按 `sortOrder` 排队、题目删了要能一起清。两者都写 `attachments`，
/// 但目录与 owner 的语义不同——混用会让"题目没确认时临时图片"出现在某道题的
/// 配图里。
///
/// 两件事必须同步：磁盘上的文件，和指向它的 `attachments` 行。数据库存的是
/// **相对** app support 目录的 POSIX 路径（Windows 上 app 目录会随安装位置或
/// 改名而移动），把相对路径还原成绝对路径只有这个类知道——所以写和读关在
/// 一个类里是唯一能让它们不分家的办法。
library;

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../data/database/database.dart';
import '../../../data/ids.dart';
import '../../../data/media/image_mime.dart';

/// 一道题下的一张已经落盘的配图。
class QuestionImage {
  const QuestionImage({
    required this.attachmentId,
    required this.relPath,
    required this.absolutePath,
    required this.fileName,
    required this.sortOrder,
    this.mime,
    this.createdAt,
  });

  /// `attachments.id`。删图时用它定位那一行。
  final String attachmentId;

  /// 相对 app support 目录、POSIX 分隔的路径。入库的就是它。
  final String relPath;

  /// 绝对路径，给 `Image.file` 用。
  final String absolutePath;

  /// 用户添加时的文件名，界面上认得出是哪张图。
  final String fileName;

  /// 同一道题内的显示顺序（0 起）；新建时接在已有图片后面。
  final int sortOrder;

  /// 从扩展名推出来的 MIME；认不出来时为 null。
  final String? mime;

  /// 落盘时间；刚保存时是本地时间。
  final DateTime? createdAt;

  String get extension => p.extension(fileName).replaceFirst('.', '');
}

/// 管着 `question_images` 目录和指向它的那些 `attachments` 行。
class QuestionMediaStore {
  QuestionMediaStore({
    required AppDatabase database,
    Future<Directory> Function()? supportDirectory,
  })  : _db = database,
        _supportDirectory = supportDirectory ?? getApplicationSupportDirectory;

  final AppDatabase _db;

  /// 测试注入用：测试不能碰真实的 app 数据目录。
  final Future<Directory> Function() _supportDirectory;

  /// app support 目录下的子目录名。`attachments` 表是全 app 共用的，所以除了
  /// `owner_type` 之外再用文件夹分一次家。
  static const String directoryName = 'question_images';

  /// `attachments.owner_type`：这里的附件属于一道题。
  static const String ownerType = 'question';

  /// 给 [questionId] 加一张图：磁盘上写 `<questionId>/<attId>/<原文件名>`，
  /// `attachments` 记一行。
  ///
  /// 只复制字节、不重编码：题目图片常常是整页印刷题或手写答案，重编码会把小字
  /// 压没（拍照整理那条通路也是这个口径）。
  ///
  /// [sortOrder] 不传就接在这道题现有图片的后面（0 起）。[mime] 不传就按扩展名
  /// 推，推不出来落 NULL。
  Future<QuestionImage> save({
    required String questionId,
    required String fileName,
    required Uint8List bytes,
    String? mime,
    int? sortOrder,
    DateTime? now,
  }) async {
    final id = questionId.trim();
    if (id.isEmpty) {
      throw ArgumentError.value(questionId, 'questionId', '题目 id 不能为空');
    }
    final safeName = p.basename(fileName.trim());
    if (safeName.isEmpty || safeName == '.' || safeName == '..') {
      throw ArgumentError.value(fileName, 'fileName', '文件名不能为空');
    }
    final resolvedMime = mime ?? imageMimeForName(safeName);
    final attachmentId = Ids.next('att');
    final relPath = '$directoryName/$id/$attachmentId/$safeName';
    final absolute = await absolutePath(relPath);
    final file = File(absolute);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);

    final ms = (now ?? DateTime.now()).millisecondsSinceEpoch;
    final order = sortOrder ?? await _nextSortOrder(id);
    await _db.into(_db.attachments).insert(
          AttachmentsCompanion.insert(
            id: attachmentId,
            ownerType: ownerType,
            ownerId: id,
            relPath: relPath,
            mime: Value(resolvedMime),
            sortOrder: Value(order),
            createdAt: ms,
          ),
        );
    return QuestionImage(
      attachmentId: attachmentId,
      relPath: relPath,
      absolutePath: absolute,
      fileName: safeName,
      sortOrder: order,
      mime: resolvedMime,
      createdAt: DateTime.fromMillisecondsSinceEpoch(ms).toLocal(),
    );
  }

  /// 一道题的配图，按 `sortOrder` 排（同序按写入时间、id 兜底，绝不依赖毫秒
  /// 撞不撞）。
  Future<List<QuestionImage>> list(String questionId) async {
    final rows = await (_db.select(_db.attachments)
          ..where((t) =>
              t.ownerType.equals(ownerType) & t.ownerId.equals(questionId.trim()))
          ..orderBy([
            (t) => OrderingTerm.asc(t.sortOrder),
            (t) => OrderingTerm.asc(t.createdAt),
            (t) => OrderingTerm.asc(t.id),
          ]))
        .get();
    final result = <QuestionImage>[];
    for (final row in rows) {
      result.add(QuestionImage(
        attachmentId: row.id,
        relPath: row.relPath,
        absolutePath: await absolutePath(row.relPath),
        fileName: p.basename(row.relPath),
        sortOrder: row.sortOrder,
        mime: row.mime,
        createdAt: DateTime.fromMillisecondsSinceEpoch(row.createdAt).toLocal(),
      ));
    }
    return result;
  }

  /// [relPath] 的绝对路径。
  Future<String> absolutePath(String relPath) async {
    final root = await _supportDirectory();
    return p.joinAll([root.path, ...relPath.split('/')]);
  }

  /// [relPath] 的字节；文件不在了返回 null。
  ///
  /// 文件丢失不算错误：用户清过 app 文件之后，题目详情仍然要能打开，只是少几张
  /// 图。和 `HandwritingIntakeStore.readBytes` / `AiAttachmentStore.readBytes`
  /// 同一个口径。
  Future<Uint8List?> readBytes(String relPath) async {
    try {
      final file = File(await absolutePath(relPath));
      if (!file.existsSync()) {
        return null;
      }
      return await file.readAsBytes();
    } on FileSystemException {
      return null;
    }
  }

  /// 删一张图：行和文件一起删，空目录顺手收掉。
  ///
  /// 顺序是"先删行再删文件"：行是索引，索引没了文件就是孤儿；反过来文件先没了、
  /// 行还指着它，界面会反复读到 null。
  Future<void> delete(QuestionImage image) async {
    await (_db.delete(_db.attachments)
          ..where((t) => t.id.equals(image.attachmentId)))
        .go();
    await _deleteFile(image.relPath);
  }

  /// 删掉一道题的所有图（行 + 文件），返回删了几张。
  ///
  /// 题目删除时由界面层在 `deleteQuestion` 前后调用；仓储不碰文件系统，所以
  /// 文件清理只能落在这里。
  Future<int> deleteForQuestion(String questionId) async {
    final images = await list(questionId);
    for (final image in images) {
      await delete(image);
    }
    return images.length;
  }

  Future<int> _nextSortOrder(String questionId) async {
    final maxOrder = _db.attachments.sortOrder.max();
    final query = _db.selectOnly(_db.attachments)
      ..addColumns([maxOrder])
      ..where(_db.attachments.ownerType.equals(ownerType) &
          _db.attachments.ownerId.equals(questionId));
    final row = await query.getSingleOrNull();
    final current = row?.read(maxOrder);
    return current == null ? 0 : current + 1;
  }

  Future<void> _deleteFile(String relPath) async {
    try {
      final file = File(await absolutePath(relPath));
      if (file.existsSync()) {
        await file.delete();
      }
      // 空的 `<attId>` 子目录，和空了之后的 `<questionId>` 目录，顺手收掉。
      // 只在确实位于本 store 根目录之下时做，免得一条畸形的 `rel_path` 把 app
      // support 目录本身删了。
      final root = await _imagesRoot();
      final attachmentDirectory = file.parent;
      if (p.isWithin(root.path, attachmentDirectory.path) &&
          attachmentDirectory.existsSync() &&
          attachmentDirectory.listSync().isEmpty) {
        attachmentDirectory.deleteSync();
      }
      final questionDirectory = attachmentDirectory.parent;
      if (questionDirectory.path != root.path &&
          p.isWithin(root.path, questionDirectory.path) &&
          questionDirectory.existsSync() &&
          questionDirectory.listSync().isEmpty) {
        questionDirectory.deleteSync();
      }
    } on FileSystemException {
      // 一个删不掉的文件不值得让"删掉这张图"整件事失败。
    }
  }

  Future<Directory> _imagesRoot() async {
    final root = await _supportDirectory();
    final directory = Directory(p.join(root.path, directoryName));
    if (!directory.existsSync()) {
      directory.createSync(recursive: true);
    }
    return directory;
  }
}
