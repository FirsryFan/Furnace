/// Where a photo of a handwritten page lives once the user has picked it
/// (`docs/QUESTION_BANK_DESIGN.md` §6 步骤 1、§7 步骤 1).
///
/// 收题的第一条通路是"拍照 → 手写整理"：图片先进 `attachments`
/// （`ownerType = 'handwriting_intake'`），题目本身还只有 `state='raw'`，等
/// 视觉模型 OCR 之后再结构化成题干/选项/答案。所以图片必须在**确认之前**就落
/// 盘：用户翻到这一页时看到的待整理清单，就是磁盘上的文件 + 这一张表两样东西。
///
/// 与 `features/ai/infrastructure/ai_attachment_store.dart` 的分工是刻意的：
/// 那个 store 的图片属于**某条消息**（`AI` 会话里的 `image_url`），`owner_id`
/// 要等消息发出去才存在；这里的主人是"收题"这件事本身，没有消息、没有
/// `VisionImageEncoder`（手写照片要保留原始分辨率给 OCR，不做 1280 长边压缩，
/// 压缩反而会毁掉笔迹）。所以不是复用，是各自管各自的目录。
///
/// 两件事必须同步：磁盘上的文件，和指向它的 `attachments` 行。把它们关在一个类
/// 里是唯一能让它们不分家的办法——数据库存的是**相对** app support 目录的
/// POSIX 路径（目录在 Windows 上会随 app 改名而移动），而把相对路径还原成字节
/// 只有这个类知道怎么做。
library;

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../data/database/database.dart';
import '../../../data/ids.dart';
import '../../../data/media/image_mime.dart';

/// 一张已经落盘的待整理图片。
class PendingHandwritingImage {
  const PendingHandwritingImage({
    required this.relPath,
    required this.absolutePath,
    required this.fileName,
    this.mime,
    this.createdAt,
  });

  /// 相对 app support 目录、POSIX 分隔的路径。入库的就是它。
  final String relPath;

  /// 绝对路径，给缩略图用。
  final String absolutePath;

  /// 用户选中时的文件名，界面上认得出是哪张照片。
  final String fileName;

  /// 从扩展名推出来的 MIME；扩展名认不出来时为 null。
  final String? mime;

  /// 落盘时间；从数据库列里读出来的是 `DateTime`，刚保存时还没有。
  final DateTime? createdAt;

  String get extension => p.extension(fileName).replaceFirst('.', '');
}

/// 管着 `handwriting_intake` 目录和指向它的那些行。
class HandwritingIntakeStore {
  HandwritingIntakeStore({
    required AppDatabase database,
    Future<Directory> Function()? supportDirectory,
  })  : _db = database,
        _supportDirectory = supportDirectory ?? getApplicationSupportDirectory;

  final AppDatabase _db;

  /// 测试注入用：测试不能碰真实的 app 数据目录。
  final Future<Directory> Function() _supportDirectory;

  /// app support 目录下的子目录名。`attachments` 表是全 app 共用的，所以除了
  /// `owner_type` 之外再用文件夹分一次家。
  static const String directoryName = 'handwriting_intake';

  /// `attachments.owner_type`。设计文档 §6 写的是 `question_intake`，§7 写的是
  /// `handwriting_intake`；本页只做"拍照存附件"，按 §7 取值。
  static const String ownerType = 'handwriting_intake';

  /// 把选中的图片复制进内部目录，并记一行 `attachments`。
  ///
  /// 只复制、不重编码：OCR 要的是原始笔迹，`VisionImageEncoder` 的 1280 长边
  /// 压缩是为"发给模型看"服务的，在这里会把小字压没。
  Future<PendingHandwritingImage> save(PlatformFile picked) async {
    // 复制而不是移动：用户选中的原图留在原地，App 只拿一份自己的副本，这样
    // "从相册删掉"和"从收题清单删掉"是两件互不牵连的事。
    //
    // 一个 id 一个子目录，原文件名原样放进去：`attachments` 表没有"文件名"这一
    // 列，界面上显示的名字只能从 `rel_path` 推出来，而把唯一 id 拼在文件名前面
    // （`hw-ab12page.png`）会让用户看到一串自己没起过的名字。
    final id = Ids.next('hw');
    final fileName = p.basename(picked.name);
    final relPath = '$directoryName/$id/$fileName';
    final mime = mimeForName(picked.name);
    final directory = await _directoryFor(id);
    final file = File(p.join(directory.path, fileName));
    await file.writeAsBytes(await picked.readAsBytes(), flush: true);

    final now = DateTime.now();
    await _db.into(_db.attachments).insert(
          AttachmentsCompanion.insert(
            id: Ids.next('att'),
            ownerType: ownerType,
            ownerId: '',
            relPath: relPath,
            mime: Value(mime),
            createdAt: now.millisecondsSinceEpoch,
          ),
        );
    return PendingHandwritingImage(
      relPath: relPath,
      absolutePath: file.path,
      fileName: fileName,
      mime: mime,
      createdAt: now,
    );
  }

  /// 待整理清单，新收的在前。
  Future<List<PendingHandwritingImage>> pending() async {
    final rows = await (_db.select(_db.attachments)
          ..where((t) => t.ownerType.equals(ownerType))
          ..orderBy([
            (t) => OrderingTerm.desc(t.createdAt),
            (t) => OrderingTerm.desc(t.id),
          ]))
        .get();
    final result = <PendingHandwritingImage>[];
    for (final row in rows) {
      result.add(PendingHandwritingImage(
        relPath: row.relPath,
        absolutePath: await absolutePath(row.relPath),
        fileName: p.basename(row.relPath),
        mime: row.mime,
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(row.createdAt).toLocal(),
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
  /// 文件丢失不算错误：用户清过 app 文件之后，这一页仍然要能打开，只是少几张
  /// 图。和 `AiAttachmentStore.readBytes` 同一个口径。
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

  /// 用户把一条待整理记录丢掉：文件 + 行一起删，尽量删干净。
  ///
  /// 顺序是"先读路径再删行"：行删了，路径就不知道去哪儿找了。
  Future<void> delete(PendingHandwritingImage image) async {
    await (_db.delete(_db.attachments)
          ..where(
              (t) => t.ownerType.equals(ownerType) & t.relPath.equals(image.relPath)))
        .go();
    await _deleteFile(image.relPath);
  }

  Future<void> _deleteFile(String relPath) async {
    try {
      final file = File(await absolutePath(relPath));
      if (file.existsSync()) {
        await file.delete();
      }
      // 空的 `<id>` 子目录顺手收掉。只在真正位于本 store 根目录下的子目录上做，
      // 免得一条畸形的 `rel_path` 把 app support 目录本身删了。
      final root = await _intakeRoot();
      final parent = file.parent;
      if (p.isWithin(root.path, parent.path) &&
          parent.existsSync() &&
          parent.listSync().isEmpty) {
        parent.deleteSync();
      }
    } on FileSystemException {
      // 一个删不掉的文件不值得让"从清单里移除"整件事失败。
    }
  }

  /// 从文件名推 MIME。认不出来的扩展名返回 null——`attachments.mime` 可空，
  /// 存 null 比存一个猜的要诚实。
  ///
  /// 实现在 `data/media/image_mime.dart`：题库配图（`QuestionMediaStore`）和
  /// 拖拽收题共用同一份，以后加 `avif` 之类只改一处。
  static String? mimeForName(String name) => imageMimeForName(name);

  Future<Directory> _directoryFor(String id) async {
    final directory = Directory(p.join((await _intakeRoot()).path, id));
    if (!directory.existsSync()) {
      directory.createSync(recursive: true);
    }
    return directory;
  }

  /// `<app support>/handwriting_intake`：本 store 独占的根目录。
  Future<Directory> _intakeRoot() async {
    final root = await _supportDirectory();
    final directory = Directory(p.join(root.path, directoryName));
    if (!directory.existsSync()) {
      directory.createSync(recursive: true);
    }
    return directory;
  }
}
