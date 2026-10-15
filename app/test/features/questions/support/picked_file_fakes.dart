/// 收题页测试用的替身：`PlatformFile` / `FilePickerPlatform`，和一个不做真实
/// 异步文件 I/O 的 `HandwritingIntakeStore`。
///
/// 为什么需要它们：
///
///  * `PlatformFile` 是 `abstract base class`，插件只给平台实现，没有可实例化的
///    公开子类；`FilePicker.pickFiles` 走 `FilePickerPlatform.instance`，桌面/移动
///    端在单元测试里都没有可用实现（调用直接 `UnimplementedError`）。所以两边都
///    要替身，收题页的"选图"这条通路才测得到。
///  * 真 store 用 `dart:io` 的**异步**文件 API，而 `testWidgets` 跑在假时钟里：
///    真实 I/O 的回调等不到。这个坑仓库里已经踩过并记在
///    `test/app/background_layer_test.dart:14-19`（"`runAsync` did not resolve it
///    either"）。所以页面级测试里把 store 换成下面这个假 store；真 store 的文件
///    语义（复制而非移动、字节原样、删除清干净）由
///    `test/features/questions/data/handwriting_intake_store_test.dart` 用普通
///    `test()` 在真实时钟下覆盖。
///
/// 假 store 保留真 store 的**数据库契约**（`attachments` 一行、`owner_type`、
/// 相对路径的形状），因为页面依赖的正是这部分；文件落盘改成同步写。
library;

import 'dart:io';

// ignore: depend_on_referenced_packages
import 'package:cross_file/cross_file.dart';
import 'package:drift/drift.dart';
import 'package:file_picker/file_picker.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/ids.dart';
import 'package:furnace/features/questions/data/handwriting_intake_store.dart';
import 'package:path/path.dart' as p;

/// 内存里的一个"用户选中的文件"：`readAsBytes()` 不碰磁盘。
///
/// 不碰磁盘是刻意的——碰了就回到假时钟等不到真实 I/O 的问题。
final class FakePickedFile extends PlatformFile {
  FakePickedFile(this.name, this.bytes);

  @override
  final String name;

  final Uint8List bytes;

  @override
  Uri get uri => Uri.file('/fake/${p.basename(name)}');

  @override
  XFile get xFile => XFile.fromData(bytes, name: name);

  @override
  int? lengthSync() => bytes.length;

  @override
  Future<int> length() async => bytes.length;

  @override
  Future<Uint8List> readAsBytes() async => bytes;

  @override
  Stream<Uint8List> readAsByteStream() async* {
    yield bytes;
  }
}

/// 只回答"用户选了这些文件"的选择器替身。
///
/// 收题页只调 `pickFiles`，所以只覆盖它；`pickFile` 保持基类的
/// `UnimplementedError`，这样误用了单文件 API 会立刻炸而不是静默通过。
final class FakeFilePicker extends FilePickerPlatform {
  FakeFilePicker(this.files);

  final List<PlatformFile> files;

  /// 每次调用带上的扩展名白名单，用来断言"只让用户选图片"。
  final List<List<String>?> allowedExtensionsCalls = <List<String>?>[];

  @override
  Future<List<PlatformFile>> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    allowedExtensionsCalls.add(allowedExtensions);
    return files;
  }
}

/// 真 store 的替身：同样的 `attachments` 行，同步写文件。
final class FakeIntakeStore extends HandwritingIntakeStore {
  FakeIntakeStore({required this.database, required this.root})
      : super(database: database, supportDirectory: () async => root);

  final AppDatabase database;

  /// 假装成 app support 目录的临时目录。
  final Directory root;

  @override
  Future<PendingHandwritingImage> save(PlatformFile picked) async {
    final name = p.basename(picked.name);
    final relPath =
        '${HandwritingIntakeStore.directoryName}/${Ids.next('hw')}/$name';
    final file = File(p.joinAll([root.path, ...relPath.split('/')]));
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(await picked.readAsBytes(), flush: true);

    final now = DateTime.now();
    final mime = HandwritingIntakeStore.mimeForName(name);
    await database.into(database.attachments).insert(
          AttachmentsCompanion.insert(
            id: Ids.next('att'),
            ownerType: HandwritingIntakeStore.ownerType,
            ownerId: '',
            relPath: relPath,
            mime: Value(mime),
            createdAt: now.millisecondsSinceEpoch,
          ),
        );
    return PendingHandwritingImage(
      relPath: relPath,
      absolutePath: file.path,
      fileName: name,
      mime: mime,
      createdAt: now,
    );
  }

  /// 同步读回字节：真 store 的 `readBytes` 是 `await file.readAsBytes()`，
  /// 页面级测试跑在假时钟里等不到那个回调（见文件头注释）。
  @override
  Future<Uint8List?> readBytes(String relPath) async {
    final file = File(p.joinAll([root.path, ...relPath.split('/')]));
    if (!file.existsSync()) {
      return null;
    }
    return file.readAsBytesSync();
  }

  @override
  Future<void> delete(PendingHandwritingImage image) async {
    await (database.delete(database.attachments)
          ..where((t) =>
              t.ownerType.equals(HandwritingIntakeStore.ownerType) &
              t.relPath.equals(image.relPath)))
        .go();
    final file = File(image.absolutePath);
    if (file.existsSync()) {
      file.deleteSync();
    }
    final parent = file.parent;
    if (p.isWithin(root.path, parent.path) &&
        parent.existsSync() &&
        parent.listSync().isEmpty) {
      parent.deleteSync();
    }
  }
}
