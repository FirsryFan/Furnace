/// 题库列表两档数据源的读表契约：未筛选只读前 500 题，筛选生效读全库。
///
/// 背景：筛选曾经只作用于前 500 题（`readQuestionLibrary` 的默认上限），题库
/// 大了以后第 500 题之后的题永远筛不到。两档来源在
/// `question_library_provider.dart`，页面按「筛选是否生效」换档。
library;

import 'package:drift/native.dart' show NativeDatabase;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/features/questions/application/question_library_filter.dart';
import 'package:furnace/features/questions/application/question_library_provider.dart';

const int _ts = 1700000000000;

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  group('questionLibraryReadLimit', () {
    test('不筛选时读前 500 题', () {
      expect(kQuestionLibraryOverviewLimit, 500);
      expect(questionLibraryReadLimit(filterActive: false), 500);
    });

    test('筛选生效时读全库（limit 0 = 不限）', () {
      expect(questionLibraryReadLimit(filterActive: true), 0);
    });
  });

  group('questionLibraryOverviewProvider（未筛选档）', () {
    test('只读前 500 题，并标记 truncated', () async {
      await _seedQuestions(db, count: 501);
      final container = _container(db);

      final snapshot = await _read(container, questionLibraryOverviewProvider);

      expect(snapshot.entries, hasLength(500));
      expect(snapshot.totalCount, 500);
      expect(snapshot.truncated, isTrue);
      expect(
        snapshot.entries.map((entry) => entry.questionId),
        isNot(contains('q-0501')),
      );
    });

    test('空库时返回空快照且不 truncated', () async {
      final container = _container(db);

      final snapshot = await _read(container, questionLibraryOverviewProvider);

      expect(snapshot.isEmpty, isTrue);
      expect(snapshot.truncated, isFalse);
    });
  });

  group('questionLibraryFullProvider（筛选档）', () {
    test('读全库：第 501 题也在快照里且不 truncated', () async {
      await _seedQuestions(db, count: 501);
      final container = _container(db);

      final snapshot = await _read(container, questionLibraryFullProvider);

      expect(snapshot.entries, hasLength(501));
      expect(snapshot.totalCount, 501);
      expect(snapshot.truncated, isFalse);
      expect(
        snapshot.entries.map((entry) => entry.questionId),
        contains('q-0501'),
      );
    });

    test('筛第 501 题：500 档筛不到，全库档筛得到', () async {
      await _seedQuestions(db, count: 501);
      final container = _container(db);
      final overview = await _read(container, questionLibraryOverviewProvider);
      final full = await _read(container, questionLibraryFullProvider);
      const filter = QuestionLibraryFilter(text: '第501题');

      expect(filterQuestionLibraryEntries(overview.entries, filter), isEmpty);
      final hits = filterQuestionLibraryEntries(full.entries, filter);
      expect(hits, hasLength(1));
      expect(hits.single.questionId, 'q-0501');
    });
  });

  group('questionLibrarySnapshotProvider（换档）', () {
    test('filterActive=false 走 500 档', () async {
      await _seedQuestions(db, count: 501);
      final container = _container(db);

      final snapshot =
          await _read(container, questionLibrarySnapshotProvider(false));

      expect(snapshot.entries, hasLength(500));
      expect(snapshot.truncated, isTrue);
    });

    test('filterActive=true 走全库档', () async {
      await _seedQuestions(db, count: 501);
      final container = _container(db);

      final snapshot =
          await _read(container, questionLibrarySnapshotProvider(true));

      expect(snapshot.entries, hasLength(501));
      expect(snapshot.truncated, isFalse);
    });
  });
}

ProviderContainer _container(AppDatabase db) {
  final container = ProviderContainer(
    overrides: [appDatabaseProvider.overrideWithValue(db)],
  );
  addTearDown(container.dispose);
  return container;
}

/// 读一档快照；先 `listen` 让 autoDispose provider 在 await 期间不被回收。
Future<QuestionLibrarySnapshot> _read(
  ProviderContainer container,
  AutoDisposeFutureProvider<QuestionLibrarySnapshot> provider,
) async {
  final subscription = container.listen(provider, (_, __) {});
  addTearDown(subscription.close);
  return container.read(provider.future);
}

Future<void> _seedQuestions(AppDatabase db, {required int count}) {
  return db.batch((batch) {
    batch.insertAll(db.questions, [
      for (var index = 1; index <= count; index++)
        QuestionsCompanion.insert(
          id: 'q-${index.toString().padLeft(4, '0')}',
          stem: '第$index题：求函数最小值',
          createdAt: _ts,
          updatedAt: _ts,
        ),
    ]);
  });
}
