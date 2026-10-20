/// The tag tree page: ordering is no longer `name.compareTo` hard-coded, and
/// the tree must stay usable while the object counts are still loading.
///
/// What is pinned here:
///  * the three ordering modes reorder every level (roots and children);
///  * the object-count badge only exists in "by object count" mode;
///  * the expansion state survives a re-sort and a mode switch;
///  * an empty database and a pending count query both render the page without
///    a spinner or an exception (counts fall back to 0);
///  * the mode choice lives in a provider, i.e. it survives page rebuilds
///    within the session.
library;

import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/domain/services/tags/tag_tree_sort.dart';
import 'package:furnace/features/tags/presentation/tag_tree_page.dart';
import 'package:furnace/l10n/app_localizations.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  /// One tags row with an explicit id and creation time.
  ///
  /// The repository stamps `DateTime.now()`, which makes the "by created at"
  /// order impossible to pin down (two rows created in the same millisecond
  /// fall back to the name tie-break), so the fixtures write the rows directly.
  Future<void> seedTag(
    String id,
    String name, {
    String? parentId,
    required int createdAt,
  }) async {
    await db.into(db.tags).insert(TagsCompanion.insert(
          id: id,
          parentId: Value(parentId),
          name: name,
          createdAt: createdAt,
          updatedAt: createdAt,
        ));
  }

  /// Attaches [count] knowledge-point links to [tagId].
  ///
  /// object_tags only has a foreign key on tag_id, not on object_id, so
  /// synthetic ids are enough here: the page only reads the COUNT.
  Future<void> attach(String tagId, int count) async {
    for (var index = 0; index < count; index++) {
      final objectId = 'obj-$tagId-$index';
      await db.into(db.objectTags).insert(ObjectTagsCompanion.insert(
            id: objectId,
            tagId: tagId,
            objectType: 'knowledge_point',
            objectId: objectId,
            createdAt: 0,
          ));
    }
  }

  /// Names, creation times and content counts all disagree, so each of the
  /// three modes produces a different order. Two children of `alpha` make the
  /// per-level ordering observable, not just the roots.
  ///
  /// alphabetical : alpha, beta, gamma           | alpha-a, alpha-b
  /// by object    : alpha(2), gamma(1), beta(0)  | alpha-a(1), alpha-b(0)
  /// by created at: gamma, alpha, beta           | alpha-b(4000), alpha-a(5000)
  Future<void> seedFixture() async {
    await seedTag('t-beta', 'beta', createdAt: 3000);
    await seedTag('t-alpha', 'alpha', createdAt: 2000);
    await seedTag('t-gamma', 'gamma', createdAt: 1000);
    await seedTag('t-alpha-b', 'alpha-b', parentId: 't-alpha', createdAt: 4000);
    await seedTag('t-alpha-a', 'alpha-a', parentId: 't-alpha', createdAt: 5000);
    await attach('t-alpha', 2);
    await attach('t-gamma', 1);
    await attach('t-alpha-a', 1);
  }

  Future<void> settle(WidgetTester tester) async {
    for (var index = 0; index < 40; index++) {
      await tester.pump(const Duration(milliseconds: 20));
      if (find.byType(CircularProgressIndicator).evaluate().isEmpty) {
        return;
      }
    }
    fail('the tag tree is still loading after 40 pumps');
  }

  Future<void> pumpPage(
    WidgetTester tester, {
    List<Override> overrides = const <Override>[],
  }) async {
    tester.view.physicalSize = const Size(1000, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          appDatabaseProvider.overrideWithValue(db),
          ...overrides,
        ],
        child: const MaterialApp(
          locale: Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: TagTreePage(),
        ),
      ),
    );
    await settle(tester);
  }

  /// The names on the visible rows, in render order (the ListView children are
  /// in tree order, so this is exactly what the user sees top to bottom).
  List<String> tileTitles(WidgetTester tester) => <String>[
        for (final tile in tester.widgetList<ListTile>(find.byType(ListTile)))
          (tile.title! as Text).data!,
      ];

  Future<void> toggle(WidgetTester tester, String name) async {
    await tester.tap(find.text(name));
    await tester.pumpAndSettle();
  }

  /// Taps the menu item itself (not its label Text) so the test does not
  /// depend on how deep the popup wraps the label.
  Future<void> selectMode(WidgetTester tester, String label) async {
    await tester.tap(find.byIcon(Icons.sort));
    await tester.pumpAndSettle();
    await tester.tap(find.ancestor(
      of: find.text(label),
      matching: find.byType(CheckedPopupMenuItem<TagTreeSortMode>),
    ));
    await tester.pumpAndSettle();
  }

  final countBadge = find.byWidgetPredicate((widget) {
    final key = widget.key;
    return key is ValueKey<String> && key.value.startsWith('tag-object-count-');
  });

  testWidgets('默认字典序：与旧的 name.compareTo 一致，且不显示内容量角标', (tester) async {
    await seedFixture();
    await pumpPage(tester);

    expect(tileTitles(tester), ['alpha', 'beta', 'gamma']);
    expect(countBadge, findsNothing);
    expect(
      ProviderScope.containerOf(tester.element(find.byType(TagTreePage)))
          .read(tagTreeSortModeProvider),
      TagTreeSortMode.alphabetical,
    );
  });

  testWidgets('切到「按内容量」：每层按内容量重排，并出现角标', (tester) async {
    await seedFixture();
    await pumpPage(tester);
    await toggle(tester, 'alpha');

    await selectMode(tester, '按内容量');

    expect(
        tileTitles(tester), ['alpha', 'alpha-a', 'alpha-b', 'gamma', 'beta']);
    expect(countBadge, findsNWidgets(5));
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('tag-object-count-t-alpha')),
        matching: find.text('2'),
      ),
      findsOneWidget,
    );
    expect(
      ProviderScope.containerOf(tester.element(find.byType(TagTreePage)))
          .read(tagTreeSortModeProvider),
      TagTreeSortMode.byObjectCount,
    );
  });

  testWidgets('切到「按添加时间」：先加的在前（含子层）', (tester) async {
    await seedFixture();
    await pumpPage(tester);
    await toggle(tester, 'alpha');

    await selectMode(tester, '按添加时间');

    expect(
        tileTitles(tester), ['gamma', 'alpha', 'alpha-b', 'alpha-a', 'beta']);
    expect(countBadge, findsNothing);
  });

  testWidgets('展开状态跨重排保留：已展开的子层不因换排序而收起', (tester) async {
    await seedFixture();
    await pumpPage(tester);
    await toggle(tester, 'alpha');
    expect(find.text('alpha-a'), findsOneWidget);

    await selectMode(tester, '按添加时间');
    expect(find.text('alpha-a'), findsOneWidget);
    expect(find.text('alpha-b'), findsOneWidget);

    // Collapsing still works after the re-sort, and the state is per tag id,
    // so switching modes again does not re-open it.
    await toggle(tester, 'alpha');
    await selectMode(tester, '按内容量');
    expect(find.text('alpha-a'), findsNothing);
    expect(tileTitles(tester), ['alpha', 'gamma', 'beta']);
  });

  testWidgets('从「按内容量」切回字典序：角标消失、顺序复原', (tester) async {
    await seedFixture();
    await pumpPage(tester);

    await selectMode(tester, '按内容量');
    expect(tileTitles(tester), ['alpha', 'gamma', 'beta']);
    expect(countBadge, findsNWidgets(3));

    await selectMode(tester, '字典序');
    expect(tileTitles(tester), ['alpha', 'beta', 'gamma']);
    expect(countBadge, findsNothing);
  });

  testWidgets('空库：显示空状态而不是加载圈', (tester) async {
    await pumpPage(tester);

    final l10n = await AppLocalizations.delegate.load(const Locale('zh'));
    expect(find.text(l10n.tagsEmpty), findsOneWidget);
    expect(find.byType(ListTile), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('计数未返回时不阻塞树：按 0 处理，模式仍然生效', (tester) async {
    await seedFixture();
    final pending = Completer<Map<String, int>>();

    await pumpPage(
      tester,
      overrides: <Override>[
        tagObjectCountsProvider.overrideWith((ref) => pending.future),
        tagTreeSortModeProvider
            .overrideWith((ref) => TagTreeSortMode.byObjectCount),
      ],
    );

    // The tags are already on screen while the count query is still pending;
    // every count reads 0, so the tie-break falls back to the name.
    expect(tileTitles(tester), ['alpha', 'beta', 'gamma']);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(countBadge, findsNWidgets(3));
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('tag-object-count-t-alpha')),
        matching: find.text('0'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('排序选择器：三档中文名，当前档打勾，切换立即重排', (tester) async {
    await seedFixture();
    await pumpPage(tester);

    await tester.tap(find.byIcon(Icons.sort));
    await tester.pumpAndSettle();
    expect(find.text('字典序'), findsOneWidget);
    expect(find.text('按内容量'), findsOneWidget);
    expect(find.text('按添加时间'), findsOneWidget);
    var items = tester.widgetList<CheckedPopupMenuItem<TagTreeSortMode>>(
      find.byType(CheckedPopupMenuItem<TagTreeSortMode>),
    );
    expect(
      items.where((item) => item.checked).map((item) => item.value).toList(),
      [TagTreeSortMode.alphabetical],
    );

    await tester.tap(find.ancestor(
      of: find.text('按内容量'),
      matching: find.byType(CheckedPopupMenuItem<TagTreeSortMode>),
    ));
    await tester.pumpAndSettle();
    expect(tileTitles(tester), ['alpha', 'gamma', 'beta']);

    await tester.tap(find.byIcon(Icons.sort));
    await tester.pumpAndSettle();
    items = tester.widgetList<CheckedPopupMenuItem<TagTreeSortMode>>(
      find.byType(CheckedPopupMenuItem<TagTreeSortMode>),
    );
    expect(
      items.where((item) => item.checked).map((item) => item.value).toList(),
      [TagTreeSortMode.byObjectCount],
    );
  });
}
