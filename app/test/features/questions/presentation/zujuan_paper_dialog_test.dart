/// 整卷对照对话框：粘贴组卷网试卷页 → 已收录 / 缺题清单、缺题链接复制。
///
/// 对照口径来自应用层 `loadZujuanPaperProgress`（只读、空抽取不查库）；这里验证
/// 界面把「没认出 / 已收录 / 缺题」三种结果分开显示，以及复制缺题链接的动作。
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/question_repository.dart';
import 'package:furnace/data/repositories/repository_providers.dart';
import 'package:furnace/domain/services/zujuan/zujuan_link.dart';
import 'package:furnace/domain/services/zujuan/zujuan_paper_extract.dart';
import 'package:furnace/features/questions/application/zujuan_paper_progress.dart';
import 'package:furnace/features/questions/presentation/zujuan_paper_dialog.dart';
import 'package:furnace/l10n/app_localizations.dart';

/// 带 bankId 的整卷页：试卷页 URL + 三道题链接（10 = 高中物理）。
const String _paperText = '''
<title>2024届高三物理周测</title>
https://zujuan.xkw.com/10p3076310.html
https://zujuan.xkw.com/10q35583902.html
https://zujuan.xkw.com/10q35583903.html
https://zujuan.xkw.com/10q35583904.html
''';

/// 同一张卷但链接里都没有 bank 段：拿不到缺题链接。
const String _noBankPaperText = '''
https://zujuan.xkw.com/p3076310.html
https://zujuan.xkw.com/q35583902.html
https://zujuan.xkw.com/q35583903.html
https://zujuan.xkw.com/q35583904.html
''';

/// 只有一道题、且没有标题（结果区要走「未命名试卷」）。
const String _noTitlePaperText = '''
https://zujuan.xkw.com/10p3076310.html
https://zujuan.xkw.com/10q35583902.html
''';

const String _garbageText = '这里没有任何题目链接。';

void main() {
  late AppDatabase db;
  late AppLocalizations zh;

  setUpAll(() async {
    zh = await AppLocalizations.delegate.load(const Locale('zh'));
  });

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test('缺题有没有链接，看整卷页的 bankId', () {
    final withBank = parseZujuanPaperText(_paperText);
    expect(withBank.bankId, '10');
    expect(
      zujuanPaperHasQuestionLink(
        ZujuanPaperProgress(extract: withBank),
        '35583902',
      ),
      isTrue,
    );

    final withoutBank = parseZujuanPaperText(_noBankPaperText);
    expect(withoutBank.bankId, isNull);
    expect(
      zujuanPaperHasQuestionLink(
        ZujuanPaperProgress(extract: withoutBank),
        '35583902',
      ),
      isFalse,
    );
    // 题号不是纯数字时链接本来就生成不出来。
    expect(
      zujuanPaperHasQuestionLink(
        ZujuanPaperProgress(extract: withBank),
        'not-a-number',
      ),
      isFalse,
    );
  });

  testWidgets('空白输入：空态文案，一次库都不查', (tester) async {
    final repository = _CountingRepository(db);
    await _pumpDialog(tester, database: db, repository: repository);

    await _parse(tester, '   ');

    expect(find.byKey(zujuanPaperEmptyKey), findsOneWidget);
    expect(find.text(zh.zujuanPaperParseEmpty), findsOneWidget);
    expect(find.byKey(zujuanPaperCopyKey), findsNothing);
    expect(repository.lookupCalls, 0);
  });

  testWidgets('认不出题目：空态文案，不查库', (tester) async {
    final repository = _CountingRepository(db);
    await _pumpDialog(tester, database: db, repository: repository);

    await _parse(tester, _garbageText);

    expect(find.byKey(zujuanPaperEmptyKey), findsOneWidget);
    expect(find.text(zh.zujuanPaperParseEmpty), findsOneWidget);
    expect(repository.lookupCalls, 0);
  });

  testWidgets('整卷三道全缺：统计行、三行带链接的缺题、复制可用', (tester) async {
    await _pumpDialog(tester, database: db);

    await _parse(tester, _paperText);

    expect(find.text(zh.zujuanPaperHeader(3, 0, 3)), findsOneWidget);
    for (final id in <String>['35583902', '35583903', '35583904']) {
      expect(find.text(zh.zujuanPaperMissingWithLink(id)), findsOneWidget);
    }
    expect(find.text(zh.zujuanPaperMatchedSection), findsNothing);
    final copy = tester.widget<FilledButton>(
      find.byKey(zujuanPaperCopyKey),
    );
    expect(copy.onPressed, isNotNull);
  });

  testWidgets('部分命中：已收录行带题号与题干预览，缺题只列没收录的', (tester) async {
    await QuestionRepository(db).ingest(
      const QuestionDraft(
        stem: '已经收录的题',
        zujuanQuestionId: '35583902',
        zujuanBankId: '10',
      ),
    );
    await _pumpDialog(tester, database: db);

    await _parse(tester, _paperText);

    expect(find.text(zh.zujuanPaperHeader(3, 1, 2)), findsOneWidget);
    expect(find.text(zh.zujuanPaperMatchedSection), findsOneWidget);
    expect(
      find.text(zh.zujuanPaperMatchedItem('TR-00001', '已经收录的题')),
      findsOneWidget,
    );
    expect(find.text(zh.zujuanPaperMissingWithLink('35583902')), findsNothing);
    expect(
        find.text(zh.zujuanPaperMissingWithLink('35583903')), findsOneWidget);
    expect(
        find.text(zh.zujuanPaperMissingWithLink('35583904')), findsOneWidget);
  });

  testWidgets('复制缺题链接：三条链接换行拼接进剪贴板，并提示已复制', (tester) async {
    final platformCalls = _mockClipboard(tester);
    await _pumpDialog(tester, database: db);
    await _parse(tester, _paperText);

    await tester.tap(find.byKey(zujuanPaperCopyKey));
    await tester.pumpAndSettle();

    final expected = <String>[
      zujuanQuestionDetailUrl(bankId: '10', questionId: '35583902')!,
      zujuanQuestionDetailUrl(bankId: '10', questionId: '35583903')!,
      zujuanQuestionDetailUrl(bankId: '10', questionId: '35583904')!,
    ].join('\n');
    expect(_copiedText(platformCalls), expected);
    expect(find.text(zh.zujuanPaperCopied), findsOneWidget);
    // 复制只剪贴板，不关对话框：用户可以继续看清单。
    expect(find.byKey(zujuanPaperDialogKey), findsOneWidget);
  });

  testWidgets('整卷页没带 bankId：缺题标「无链接」并说明原因，复制禁用', (tester) async {
    await _pumpDialog(tester, database: db);

    await _parse(tester, _noBankPaperText);

    expect(find.text(zh.zujuanPaperHeader(3, 0, 3)), findsOneWidget);
    for (final id in <String>['35583902', '35583903', '35583904']) {
      expect(find.text(zh.zujuanPaperMissingNoLink(id)), findsOneWidget);
    }
    expect(find.text(zh.zujuanPaperNoBank), findsOneWidget);
    final copy = tester.widget<FilledButton>(
      find.byKey(zujuanPaperCopyKey),
    );
    expect(copy.onPressed, isNull);
  });

  testWidgets('结果区显示整卷标题；没有标题时用「未命名试卷」', (tester) async {
    await _pumpDialog(tester, database: db);
    await _parse(tester, _paperText);
    expect(find.text('2024届高三物理周测'), findsOneWidget);

    await _parse(tester, _noTitlePaperText);
    expect(find.text(zh.zujuanPaperUntitled), findsOneWidget);
  });

  testWidgets('先解析有结果、再解析空白：结果清掉，复制按钮消失', (tester) async {
    await _pumpDialog(tester, database: db);
    await _parse(tester, _paperText);
    expect(find.byKey(zujuanPaperCopyKey), findsOneWidget);

    await _parse(tester, '   ');

    expect(find.byKey(zujuanPaperEmptyKey), findsOneWidget);
    expect(find.byKey(zujuanPaperCopyKey), findsNothing);
  });

  testWidgets('全部已收录：没有缺题，复制按钮禁用', (tester) async {
    await QuestionRepository(db).ingest(
      const QuestionDraft(
        stem: '唯一一道题',
        zujuanQuestionId: '35583902',
        zujuanBankId: '10',
      ),
    );
    await _pumpDialog(tester, database: db);

    await _parse(tester, _noTitlePaperText);

    expect(find.text(zh.zujuanPaperHeader(1, 1, 0)), findsOneWidget);
    expect(
      find.text(zh.zujuanPaperMatchedItem('TR-00001', '唯一一道题')),
      findsOneWidget,
    );
    expect(find.text(zh.zujuanPaperMissingSection), findsNothing);
    final copy = tester.widget<FilledButton>(
      find.byKey(zujuanPaperCopyKey),
    );
    expect(copy.onPressed, isNull);
  });

  testWidgets('关闭按钮：对话框消失', (tester) async {
    await _pumpDialog(tester, database: db);

    await tester.tap(find.byTooltip(zh.zujuanPaperClose));
    await tester.pumpAndSettle();

    expect(find.byKey(zujuanPaperDialogKey), findsNothing);
  });
}

Future<void> _parse(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(zujuanPaperInputKey), text);
  await tester.pump();
  await tester.tap(find.byKey(zujuanPaperParseKey));
  // 查库的 future 不排帧，等结果区出现再收尾（空态 / 复制按钮任一出现即算完）。
  for (var i = 0; i < 60; i++) {
    await tester.pump(const Duration(milliseconds: 20));
    final done = find.byKey(zujuanPaperEmptyKey).evaluate().isNotEmpty ||
        find.byKey(zujuanPaperCopyKey).evaluate().isNotEmpty;
    if (done) break;
  }
  await tester.pumpAndSettle();
}

Future<void> _pumpDialog(
  WidgetTester tester, {
  required AppDatabase database,
  QuestionRepository? repository,
}) async {
  tester.view.physicalSize = const Size(1200, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        appDatabaseProvider.overrideWithValue(database),
        if (repository != null)
          questionRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                key: const Key('open-paper'),
                onPressed: () async {
                  await showZujuanPaperDialog(
                    context,
                    l10n: AppLocalizations.of(context),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const Key('open-paper')));
  await tester.pumpAndSettle();
}

/// 拦下 `Clipboard.setData` 的平台通道调用（不真的写系统剪贴板）。
List<MethodCall> _mockClipboard(WidgetTester tester) {
  final calls = <MethodCall>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      calls.add(call);
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  return calls;
}

String? _copiedText(List<MethodCall> calls) {
  for (final call in calls.reversed) {
    if (call.method != 'Clipboard.setData') continue;
    final arguments = call.arguments;
    if (arguments is Map && arguments['text'] is String) {
      return arguments['text'] as String;
    }
  }
  return null;
}

/// 数对照查库次数：验证「没认出题号」这条路径零数据库开销。
class _CountingRepository extends QuestionRepository {
  _CountingRepository(super.db);

  int lookupCalls = 0;

  @override
  Future<Map<String, List<Question>>> byZujuanQuestionIds(
    Set<String> zujuanQuestionIds,
  ) {
    lookupCalls++;
    return super.byZujuanQuestionIds(zujuanQuestionIds);
  }
}
