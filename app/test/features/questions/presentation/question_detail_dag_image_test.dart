/// 详情页「思维 DAG 图片」的界面级测试（2026-11-19）。
///
/// 产品口径（当前版本）：
///  1. 有步骤时，DAG 区域的主视图是一张**真实生成的 PNG**，不再直接摊开文字
///     步骤链；文字明细默认收起、可展开。
///  2. 没有步骤时是明确空态（标题 + 一句「暂无」），不出现空白卡片、也不生成
///     任何图片文件。
///  3. 生成失败时显示「失败 + 原因 + 重试」，重试成功后图片出现。
///
/// 图片生成走真实 `dart:ui` 绘制 + 真实落盘（临时目录），不 mock 渲染器。
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/question_repository.dart';
import 'package:furnace/features/ai/application/ai_providers.dart';
import 'package:furnace/features/questions/application/question_dag_image_providers.dart';
import 'package:furnace/features/questions/application/question_media_providers.dart';
import 'package:furnace/features/questions/data/dag_image_store.dart';
import 'package:furnace/features/questions/presentation/question_detail_page.dart';
import 'package:furnace/l10n/app_localizations.dart';
import 'package:path/path.dart' as p;

import 'support/question_media_fakes.dart';

const String _stem = '已知 x^2-5x+6=0，求两根之和。';
const String _summary = '看清系数 → 韦达定理 → 回代检验。';

late AppLocalizations _zh;

void main() {
  setUpAll(() async {
    _zh = await AppLocalizations.delegate.load(const Locale('zh'));
  });

  testWidgets('有 steps：DAG 区出现真实生成的 PNG，图片也真的落盘', (WidgetTester tester) async {
    final database = _newDatabase();
    final roots = _tempRoot();
    final question = await _seedQuestion(database);
    await _seedChain(database, question.id);

    await _pumpDetail(
      tester,
      database,
      question.id,
      supportDirectory: () async => roots.root,
    );
    await _pumpUntil(
      tester,
      () => find.byKey(questionDetailDagImageKey).evaluate().isNotEmpty,
    );

    final imageFinder = find.byKey(questionDetailDagImageKey);
    expect(imageFinder, findsOneWidget, reason: 'DAG 区应该出现图片');

    final widget = tester.widget<Image>(imageFinder);
    final provider = widget.image;
    expect(provider, isA<MemoryImage>(),
        reason: '图片应该由生成器产出的 PNG 字节直接显示');
    final bytes = (provider as MemoryImage).bytes;
    expect(_isPng(bytes), isTrue, reason: '显示的内容必须是 PNG');
    expect(bytes.length, greaterThan(8 * 1024),
        reason: '节点/箭头/文字都画出来的 PNG 不会只有几十字节');

    // 文件真的写进了（临时的）app support 目录，且显示字节 === 落盘字节。
    final chains = await QuestionRepository(database).chainsOf(question.id);
    final file = File(p.join(
      roots.root.path,
      DagImageStore.directoryName,
      '${chains.single.id}.png',
    ));
    expect(file.existsSync(), isTrue, reason: 'DAG 图片必须真实落盘：${file.path}');
    expect(file.readAsBytesSync(), orderedEquals(bytes));

    // 图片说明在；文字步骤明细默认收起，展开后才出现。
    expect(find.text(_zh.questionDetailDagImageCaption), findsOneWidget);
    // 让 `Image.memory` 的解码真正完成：解码是 real-async 的，留在用例结束时
    // 未完成会给后续用例留下挂起的引擎回调（后续 DAG 图片就再也画不出来）。
    await tester.runAsync(
      () => precacheImage(provider, tester.element(imageFinder)),
    );
    expect(find.text(_zh.questionDetailStepTitle(1)), findsNothing);
    await tester.ensureVisible(find.byKey(questionDetailDagTextToggleKey));
    await tester.pump();
    await tester.tap(find.byKey(questionDetailDagTextToggleKey));
    await _pumpUntil(
      tester,
      () => find.text(_zh.questionDetailStepTitle(1)).evaluate().isNotEmpty,
    );
    expect(find.text(_zh.questionDetailStepTitle(1)), findsOneWidget);
  });

  testWidgets('没有 steps：明确空态，不生成任何图片文件', (WidgetTester tester) async {
    final database = _newDatabase();
    final roots = _tempRoot();
    final question = await _seedQuestion(database);

    await _pumpDetail(
      tester,
      database,
      question.id,
      supportDirectory: () async => roots.root,
    );
    await _pumpUntil(
      tester,
      () => find.text(_zh.questionDetailNoChainYet).evaluate().isNotEmpty,
    );

    expect(find.text(_zh.questionDetailNoChainYet), findsOneWidget);
    expect(find.byKey(questionDetailDagImageKey), findsNothing);
    expect(find.byKey(questionDetailDagImageLoadingKey), findsNothing);
    expect(find.byKey(questionDetailDagImageFailureKey), findsNothing);
    final imageDir =
        Directory(p.join(roots.root.path, DagImageStore.directoryName));
    expect(imageDir.existsSync(), isFalse,
        reason: '没有步骤就不该创建 DAG 图片目录 / 文件');
  });

  testWidgets('生成失败：显示失败原因 + 重试，重试成功后图片出现', (WidgetTester tester) async {
    final database = _newDatabase();
    final roots = _tempRoot();
    final question = await _seedQuestion(database);
    await _seedChain(database, question.id);

    var directoryCalls = 0;
    Future<Directory> flakyDirectory() async {
      directoryCalls++;
      if (directoryCalls == 1) {
        throw const FileSystemException('模拟：数据盘不可写');
      }
      return roots.root;
    }

    await _pumpDetail(
      tester,
      database,
      question.id,
      supportDirectory: flakyDirectory,
    );
    await _pumpUntil(
      tester,
      () =>
          find.byKey(questionDetailDagImageFailureKey).evaluate().isNotEmpty,
    );

    expect(find.byKey(questionDetailDagImageFailureKey), findsOneWidget);
    expect(find.text(_zh.questionDetailDagImageFailed), findsOneWidget);
    expect(find.textContaining('模拟：数据盘不可写'), findsOneWidget);
    expect(find.byKey(questionDetailDagImageRetryKey), findsOneWidget);
    expect(find.byKey(questionDetailDagImageKey), findsNothing);

    await tester.ensureVisible(find.byKey(questionDetailDagImageRetryKey));
    await tester.pump();
    await tester.tap(find.byKey(questionDetailDagImageRetryKey));
    await _pumpUntil(
      tester,
      () => find.byKey(questionDetailDagImageKey).evaluate().isNotEmpty,
    );

    expect(find.byKey(questionDetailDagImageKey), findsOneWidget);
    expect(find.byKey(questionDetailDagImageFailureKey), findsNothing);
    expect(directoryCalls, greaterThanOrEqualTo(2));
    final files = Directory(p.join(roots.root.path, DagImageStore.directoryName))
        .listSync()
        .whereType<File>()
        .toList();
    expect(files, isNotEmpty, reason: '重试成功也必须真实落盘');
  });
}

// ---------------------------------------------------------------------------
// 测试夹具
// ---------------------------------------------------------------------------

class _TempRoot {
  _TempRoot(this.root);
  final Directory root;
}

_TempRoot _tempRoot() {
  final root = Directory.systemTemp.createTempSync('furnace_dag_ui_');
  addTearDown(() {
    if (root.existsSync()) {
      root.deleteSync(recursive: true);
    }
  });
  return _TempRoot(root);
}

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
      questionType: 'solution',
    ),
  );
  return result.question;
}

Future<void> _seedChain(AppDatabase database, String questionId) async {
  await QuestionRepository(database).saveChain(
    questionId,
    const ReasoningChainDraft(
      summary: _summary,
      steps: <ReasoningStepDraft>[
        ReasoningStepDraft(
          goal: '看清方程的系数 a=1、b=-5、c=6。',
          actionType: 'first_principles',
          justification: '先确认标准形式',
          checkMethod: '',
          stuckRisk: 0.4,
        ),
        ReasoningStepDraft(
          goal: '用韦达定理求两根之和：x1+x2 = -b/a = 5。',
          actionType: 'sanity_check',
          justification: '',
          checkMethod: '回代检验',
          stuckRisk: 0.8,
        ),
      ],
    ),
  );
}

Future<void> _pumpDetail(
  WidgetTester tester,
  AppDatabase database,
  String questionId, {
  required Future<Directory> Function() supportDirectory,
}) async {
  tester.view.physicalSize = const Size(1200, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        appDatabaseProvider.overrideWithValue(database),
        modelAdapterProvider.overrideWithValue(null),
        questionMediaStoreProvider.overrideWithValue(
          FakeQuestionMediaStore(database: database),
        ),
        questionDagImageSupportDirectoryProvider
            .overrideWithValue(supportDirectory),
      ],
      child: MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: QuestionDetailPage(questionId: questionId),
      ),
    ),
  );
  // 首帧 + 各 FutureProvider 读库；不做图片断言前先让非图片通路走完。
  await _pumpUntil(
    tester,
    () => find.byKey(questionDetailDagSectionKey).evaluate().isNotEmpty,
  );
}

/// 轮询直到 [done] 为真。
///
/// 图片生成走 `dart:ui` 的异步 `Picture.toImage`：在 `testWidgets` 的
/// fake-async 环境里它只有在 `tester.runAsync` 打开 real-async 窗口时才会完成，
/// 所以每轮都先给真实事件循环一点时间，再推进一帧。
Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() done, {
  int rounds = 300,
}) async {
  for (var i = 0; i < rounds; i++) {
    if (done()) {
      return;
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
  if (!done()) {
    fail('轮询超时：界面上没有等到期望的内容');
  }
}

bool _isPng(List<int> bytes) =>
    bytes.length >= 8 &&
    bytes[0] == 0x89 &&
    bytes[1] == 0x50 &&
    bytes[2] == 0x4E &&
    bytes[3] == 0x47 &&
    bytes[4] == 0x0D &&
    bytes[5] == 0x0A &&
    bytes[6] == 0x1A &&
    bytes[7] == 0x0A;
