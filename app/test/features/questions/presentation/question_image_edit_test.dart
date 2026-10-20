/// 题目详情页配图的增删入口：空清单的一行入口、添加成功刷新、跳过非图片与
/// HEIC、0 字节与读不出来的文件、删除确认。
///
/// 页面级测试统一用内存 store 替身（`support/question_media_fakes.dart`），
/// 选择器用 `../support/picked_file_fakes.dart`：真 store 走异步文件 I/O，在
/// `testWidgets` 的假时钟里等不到回调。
library;

import 'dart:io';
import 'dart:typed_data';

// ignore: depend_on_referenced_packages
import 'package:cross_file/cross_file.dart';
import 'package:drift/native.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/question_repository.dart';
import 'package:furnace/domain/services/media/thumbnail_spec.dart';
import 'package:furnace/features/ai/application/ai_providers.dart';
import 'package:furnace/features/questions/application/question_media_providers.dart';
import 'package:furnace/features/questions/presentation/question_detail_page.dart';
import 'package:furnace/features/questions/presentation/question_media_view.dart';
import 'package:furnace/l10n/app_localizations.dart';

import '../support/picked_file_fakes.dart';
import 'support/question_media_fakes.dart';

const String _stem = '已知 x^2-5x+6=0，求两根之和。';

late AppLocalizations _zh;

void main() {
  setUpAll(() async {
    _zh = await AppLocalizations.delegate.load(const Locale('zh'));
  });

  testWidgets('空清单：编辑模式只留一行添加入口，不摆空相框', (tester) async {
    final database = _newDatabase();
    final question = await _seedQuestion(database);

    await _pumpDetail(tester, database, question.id);
    await _waitForText(tester, _stem);

    expect(find.byKey(questionImageAddButtonKey), findsOneWidget);
    expect(find.text(_zh.questionImageEmptyHint), findsOneWidget);
    expect(find.text(_zh.questionDetailImagesSection), findsNothing);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('添加：多选图片落盘，清单刷新并提示张数', (tester) async {
    final database = _newDatabase();
    final question = await _seedQuestion(database);
    final mediaStore = FakeQuestionMediaStore(database: database);
    final picker = _installPicker(<PlatformFile>[
      FakePickedFile('front.png', tinyPngBytes),
      FakePickedFile('side.jpg', tinyPngBytes),
    ]);

    await _pumpDetail(tester, database, question.id, mediaStore: mediaStore);
    await _waitForText(tester, _stem);

    await tester.tap(find.byKey(questionImageAddButtonKey));
    await _waitForText(tester, _zh.questionImageAddDone(2));
    await _waitForText(tester, _zh.questionImageCount(2));
    await _waitForType(tester, Image);

    // 只让用户选图片：白名单里有常见图片扩展名，且不包含 HEIC。
    expect(picker.allowedExtensionsCalls, hasLength(1));
    expect(picker.allowedExtensionsCalls.single, contains('png'));
    expect(picker.allowedExtensionsCalls.single, isNot(contains('heic')));

    final images = await mediaStore.list(question.id);
    expect(images.map((image) => image.fileName), <String>[
      'front.png',
      'side.jpg',
    ]);
    expect(find.byType(Image), findsNWidgets(2));
  });

  testWidgets('添加：非图片与 HEIC 跳过，好的照收，提示分开说', (tester) async {
    final database = _newDatabase();
    final question = await _seedQuestion(database);
    final mediaStore = FakeQuestionMediaStore(database: database);
    _installPicker(<PlatformFile>[
      FakePickedFile('note.txt', Uint8List.fromList(<int>[1, 2, 3])),
      FakePickedFile('photo.heic', Uint8List.fromList(<int>[1, 2, 3])),
      FakePickedFile('ok.png', tinyPngBytes),
    ]);

    await _pumpDetail(tester, database, question.id, mediaStore: mediaStore);
    await _waitForText(tester, _stem);

    await tester.tap(find.byKey(questionImageAddButtonKey));
    await _waitForTextContaining(tester, _zh.questionImageAddDone(1));

    expect(find.textContaining(_zh.questionImageAddSkipped(1)), findsOneWidget);
    expect(
      find.textContaining(_zh.questionImageHeicUnsupported),
      findsOneWidget,
    );
    final images = await mediaStore.list(question.id);
    expect(images.single.fileName, 'ok.png');
  });

  testWidgets('添加：0 字节文件不落盘，只提示跳过', (tester) async {
    final database = _newDatabase();
    final question = await _seedQuestion(database);
    final mediaStore = FakeQuestionMediaStore(database: database);
    _installPicker(<PlatformFile>[FakePickedFile('empty.png', Uint8List(0))]);

    await _pumpDetail(tester, database, question.id, mediaStore: mediaStore);
    await _waitForText(tester, _stem);

    await tester.tap(find.byKey(questionImageAddButtonKey));
    await _waitForText(tester, _zh.questionImageAddSkipped(1));

    expect(await mediaStore.list(question.id), isEmpty);
    expect(find.text(_zh.questionImageAddDone(1)), findsNothing);
  });

  testWidgets('添加：单个文件读不出来不整批失败', (tester) async {
    final database = _newDatabase();
    final question = await _seedQuestion(database);
    final mediaStore = FakeQuestionMediaStore(database: database);
    _installPicker(<PlatformFile>[
      _UnreadablePickedFile('broken.png'),
      FakePickedFile('ok.png', tinyPngBytes),
    ]);

    await _pumpDetail(tester, database, question.id, mediaStore: mediaStore);
    await _waitForText(tester, _stem);

    await tester.tap(find.byKey(questionImageAddButtonKey));
    await _waitForTextContaining(tester, _zh.questionImageAddDone(1));
    expect(find.textContaining(_zh.questionImageAddSkipped(1)), findsOneWidget);
    expect((await mediaStore.list(question.id)).single.fileName, 'ok.png');
  });

  testWidgets('删除：先确认再删，删完清单清空并提示', (tester) async {
    final database = _newDatabase();
    final question = await _seedQuestion(database);
    final mediaStore = FakeQuestionMediaStore(database: database)
      ..seed(
        questionId: question.id,
        fileName: 'page-1.png',
        bytes: tinyPngBytes,
      );

    await _pumpDetail(tester, database, question.id, mediaStore: mediaStore);
    await _waitForText(tester, _zh.questionImageCount(1));
    await _waitForType(tester, Image);

    // 取消：什么都不删。
    await tester.tap(find.byKey(questionImageDeleteButtonKey(
      (await mediaStore.list(question.id)).single.attachmentId,
    )));
    await tester.pumpAndSettle();
    expect(find.text(_zh.questionImageDeleteTitle), findsOneWidget);
    expect(
      find.text(_zh.questionImageDeleteConfirm('page-1.png')),
      findsOneWidget,
    );
    await tester.tap(find.text(_zh.commonClose));
    await tester.pumpAndSettle();
    expect(await mediaStore.list(question.id), hasLength(1));

    // 确认：删掉并刷新成空清单。
    final attachmentId =
        (await mediaStore.list(question.id)).single.attachmentId;
    await tester.tap(find.byKey(questionImageDeleteButtonKey(attachmentId)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(questionImageDeleteConfirmButtonKey));
    await _waitForText(tester, _zh.questionImageEmptyHint);

    expect(await mediaStore.list(question.id), isEmpty);
    expect(find.text(_zh.questionImageDeleted), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('配图：缩略图按显示尺寸与设备像素比限制解码尺寸', (tester) async {
    final database = _newDatabase();
    final question = await _seedQuestion(database);
    final mediaStore = FakeQuestionMediaStore(database: database)
      ..seed(
        questionId: question.id,
        fileName: 'page-1.png',
        bytes: tinyPngBytes,
      );

    await _pumpDetail(tester, database, question.id, mediaStore: mediaStore);
    await _waitForText(tester, _zh.questionImageCount(1));
    await _waitForType(tester, Image);

    // 详情页缩略图默认 size=96；测试视口 DPR=1.0。
    final expected = thumbnailDecodeSpec(
      logicalWidth: 96,
      logicalHeight: 96,
      devicePixelRatio: tester.view.devicePixelRatio,
    );
    expect(expected.isEmpty, isFalse);

    // Image.memory(cacheWidth:) 把它包成 ResizeImage：断言在 provider 上。
    final image = tester.widget<Image>(find.byType(Image));
    final provider = image.image;
    expect(provider, isA<ResizeImage>());
    final resize = provider as ResizeImage;
    expect(resize.width, expected.cacheWidth);
    expect(resize.height, expected.cacheHeight);
  });

  testWidgets('配图：点开的大图不限制解码尺寸', (tester) async {
    final database = _newDatabase();
    final question = await _seedQuestion(database);
    final mediaStore = FakeQuestionMediaStore(database: database)
      ..seed(
        questionId: question.id,
        fileName: 'page-1.png',
        bytes: tinyPngBytes,
      );

    await _pumpDetail(tester, database, question.id, mediaStore: mediaStore);
    await _waitForText(tester, _zh.questionImageCount(1));
    await _waitForType(tester, Image);

    await tester.tap(find.byType(Image));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);

    final dialogImage = tester.widget<Image>(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.byType(Image),
      ),
    );
    // 大图不传 cacheWidth/cacheHeight：provider 不是 ResizeImage。
    expect(dialogImage.image, isNot(isA<ResizeImage>()));
  });
}

/// 一个干净的内存库；每个用例自己关。
AppDatabase _newDatabase() {
  final database = AppDatabase.forTesting(NativeDatabase.memory());
  addTearDown(database.close);
  return database;
}

Future<Question> _seedQuestion(AppDatabase database) async {
  final result = await QuestionRepository(database).ingest(
    const QuestionDraft(
      stem: _stem,
      answer: '5',
      solution: '韦达定理：两根之和等于 -b/a。',
      subjectKey: 'math',
      questionType: 'single_choice',
      sourceLevel: 'gaokao',
      year: 2024,
      region: '江苏',
      difficulty: 4,
    ),
  );
  return result.question;
}

/// 一次「用户选了这些文件」的替身；用例结束时还原平台实例。
FakeFilePicker _installPicker(List<PlatformFile> files) {
  final picker = FakeFilePicker(files);
  final previous = FilePickerPlatform.instance;
  FilePickerPlatform.instance = picker;
  addTearDown(() => FilePickerPlatform.instance = previous);
  return picker;
}

Future<void> _pumpDetail(
  WidgetTester tester,
  AppDatabase database,
  String questionId, {
  FakeQuestionMediaStore? mediaStore,
}) async {
  _bigSurface(tester);
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        appDatabaseProvider.overrideWithValue(database),
        modelAdapterProvider.overrideWithValue(null),
        questionMediaStoreProvider.overrideWithValue(
          mediaStore ?? FakeQuestionMediaStore(database: database),
        ),
      ],
      child: MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: QuestionDetailPage(questionId: questionId),
      ),
    ),
  );
  await _settle(tester);
}

/// 页面很长，默认 800×600 视口里 `ListView` 只建可见的那几行。
void _bigSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _settle(WidgetTester tester, {int rounds = 40}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.pump(const Duration(milliseconds: 20));
    final spinning =
        find.byType(LinearProgressIndicator).evaluate().isNotEmpty ||
            find.byType(CircularProgressIndicator).evaluate().isNotEmpty;
    if (!spinning) {
      return;
    }
  }
}

Future<void> _waitForText(
  WidgetTester tester,
  String text, {
  int rounds = 120,
}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (find.text(text).evaluate().isNotEmpty) {
      return;
    }
  }
  fail('等了 12 秒也没等到这段文字：\$text');
}

Future<void> _waitForTextContaining(
  WidgetTester tester,
  String text, {
  int rounds = 120,
}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (find.textContaining(text).evaluate().isNotEmpty) {
      return;
    }
  }
  fail('等了 12 秒也没等到包含这段文字的控件：\$text');
}

Future<void> _waitForType(WidgetTester tester, Type type,
    {int rounds = 120}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (find.byType(type).evaluate().isNotEmpty) {
      return;
    }
  }
  fail('等了 12 秒也没等到这个控件：\$type');
}

/// 读字节直接抛异常的选中文件：模拟磁盘读不出来，验证「单个失败不整批失败」。
final class _UnreadablePickedFile extends PlatformFile {
  _UnreadablePickedFile(this.name);

  @override
  final String name;

  @override
  Uri get uri => Uri.file('/fake/\$name');

  @override
  XFile get xFile => XFile.fromData(Uint8List(0), name: name);

  @override
  int? lengthSync() => null;

  @override
  Future<int> length() async => 0;

  @override
  Future<Uint8List> readAsBytes() async =>
      throw const FileSystemException('读不出来');

  @override
  Stream<Uint8List> readAsByteStream() async* {
    throw const FileSystemException('读不出来');
  }
}
