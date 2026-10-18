/// `QuestionSerialBadgeById` 的验收点：题号是异步按 id 读的。
///
///  * 读到号：显示 `TR-xxxxx`；
///  * 没号（老题未回填）：显示「未编号」占位；
///  * 读失败 / 还在读：整块不渲染（列表行里不摆空框，也不崩）。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/features/questions/presentation/question_media_view.dart';
import 'package:furnace/l10n/app_localizations.dart';

void main() {
  late AppLocalizations zh;

  setUpAll(() async {
    zh = await AppLocalizations.delegate.load(const Locale('zh'));
  });

  Future<void> pumpBadge(
    WidgetTester tester, {
    required Override serialOverride,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[serialOverride],
        child: const MaterialApp(
          locale: Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Center(
              child: QuestionSerialBadgeById(questionId: 'q-serial'),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('读到编号：显示 TR-xxxxx', (tester) async {
    await pumpBadge(
      tester,
      serialOverride: questionSerialProvider.overrideWith(
        (ref, questionId) async => 12,
      ),
    );
    await tester.pump();

    expect(find.text('TR-00012'), findsOneWidget);
  });

  testWidgets('没有编号：显示「未编号」占位，不摆空框', (tester) async {
    await pumpBadge(
      tester,
      serialOverride: questionSerialProvider.overrideWith(
        (ref, questionId) async => null,
      ),
    );
    await tester.pump();

    expect(find.text(zh.questionSerialUnnumbered), findsOneWidget);
  });

  testWidgets('读号失败：整块不渲染，不崩', (tester) async {
    await pumpBadge(
      tester,
      serialOverride: questionSerialProvider.overrideWith(
        (ref, questionId) => Future<int?>.error(StateError('db down')),
      ),
    );
    await tester.pump();

    expect(find.textContaining('TR-'), findsNothing);
    expect(find.text(zh.questionSerialUnnumbered), findsNothing);
  });

  testWidgets('还在读：先不占位，读到后补上', (tester) async {
    final pending = Completer<int?>();
    await pumpBadge(
      tester,
      serialOverride: questionSerialProvider.overrideWith(
        (ref, questionId) => pending.future,
      ),
    );

    expect(find.text(zh.questionSerialUnnumbered), findsNothing);
    pending.complete(7);
    await tester.pump();
    await tester.pump();

    expect(find.text('TR-00007'), findsOneWidget);
  });
}
