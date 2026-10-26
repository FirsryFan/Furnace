/// 标签用途边界的共享 helper：过滤口径、继承、保序与界面文案。
///
/// 这里钉的是「某个域的选择器该看到哪些标签」这一层的规则；解析器自己的
/// 继承/环保护已经有 domain 层测试，本文件只覆盖过滤与文案。
library;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/domain/services/tags/tag_usage.dart';
import 'package:furnace/features/tags/application/tag_usage_scope.dart';
import 'package:furnace/l10n/app_localizations_zh.dart';

Tag _tag(String id, {String? parentId, String? usageCodes, String? path}) {
  return Tag(
    id: id,
    parentId: parentId,
    name: id,
    path: path ?? id,
    usageCodes: usageCodes,
    createdAt: 1,
    updatedAt: 1,
  );
}

/// 与 `TagRepository.resolverFor` 同一套接线：只把「本级声明」交给解析器。
TagUsageResolver _resolver(Iterable<Tag> tags) => TagUsageResolver([
      for (final tag in tags)
        TagUsageNode(
          id: tag.id,
          parentId: tag.parentId,
          declaredUsages: decodeTagUsageCodes(tag.usageCodes),
        ),
    ]);

Iterable<String> _ids(TagUsageScope scope) =>
    scope.visibleTags.map((tag) => tag.id);

/// 探针：在真实 provider 环境里跑一次 [loadTagUsageScope]，把结果落到界面上。
class _ScopeProbe extends ConsumerStatefulWidget {
  const _ScopeProbe({required this.usage});

  final TagUsage usage;

  @override
  ConsumerState<_ScopeProbe> createState() => _ScopeProbeState();
}

class _ScopeProbeState extends ConsumerState<_ScopeProbe> {
  TagUsageScope? _scope;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final scope = await loadTagUsageScope(ref, widget.usage);
      if (!mounted) return;
      setState(() => _scope = scope);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    if (error != null) {
      return Text('error: $error');
    }
    final scope = _scope;
    if (scope == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final names = scope.visibleTags.map((tag) => tag.name).join('|');
    return Text('$names declared=${scope.hasAnyDeclaration}');
  }
}

Future<AppDatabase> _openDatabase() async {
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  addTearDown(db.close);
  return db;
}

Future<void> _seedTag(
  AppDatabase db, {
  required String id,
  required String name,
  String? parentId,
  String? usageCodes,
}) async {
  await db.into(db.tags).insert(TagsCompanion.insert(
        id: id,
        name: name,
        parentId: parentId == null ? const Value.absent() : Value(parentId),
        usageCodes:
            usageCodes == null ? const Value.absent() : Value(usageCodes),
        createdAt: 1,
        updatedAt: 1,
      ));
}

Future<void> _pumpProbe(
  WidgetTester tester,
  AppDatabase db,
  TagUsage usage,
) async {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
      child: MaterialApp(
        home: Scaffold(body: _ScopeProbe(usage: usage)),
      ),
    ),
  );
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 20));
    if (find.byType(CircularProgressIndicator).evaluate().isEmpty) {
      return;
    }
  }
  fail('probe still loading after 40 pumps');
}

void main() {
  group('buildTagUsageScope', () {
    test('只留下本用途可见的标签，并保持读取顺序', () {
      final tags = [
        _tag('q-root', usageCodes: 'question'),
        _tag('f-root', usageCodes: 'flashcard'),
        _tag('undeclared'),
        _tag('q-child', parentId: 'q-root'),
      ];
      final scope = buildTagUsageScope(
        usage: TagUsage.question,
        tags: tags,
        resolver: _resolver(tags),
      );

      expect(_ids(scope), ['q-root', 'undeclared', 'q-child']);
      expect(scope.tags, hasLength(4));
      expect(scope.hasAnyDeclaration, isTrue);
      expect(scope.isEmpty, isFalse);
    });

    test('父标签的声明被子标签继承', () {
      final tags = [
        _tag('root', usageCodes: 'knowledge'),
        _tag('child', parentId: 'root'),
        _tag('grandchild', parentId: 'child'),
      ];
      final resolver = _resolver(tags);

      expect(
        _ids(buildTagUsageScope(
          usage: TagUsage.knowledge,
          tags: tags,
          resolver: resolver,
        )),
        ['root', 'child', 'grandchild'],
      );
      expect(
        _ids(buildTagUsageScope(
          usage: TagUsage.question,
          tags: tags,
          resolver: resolver,
        )),
        isEmpty,
      );
    });

    test('整棵树都没有声明用途时全部可见', () {
      final tags = [_tag('a'), _tag('b')];
      final scope = buildTagUsageScope(
        usage: TagUsage.task,
        tags: tags,
        resolver: _resolver(tags),
      );

      expect(_ids(scope), ['a', 'b']);
      expect(scope.hasAnyDeclaration, isFalse);
      expect(scope.isEmpty, isFalse);
    });

    test('整棵树只声明了别的用途时本域为空', () {
      final tags = [
        _tag('a', usageCodes: 'flashcard'),
        _tag('b', usageCodes: 'time,flashcard'),
      ];
      final scope = buildTagUsageScope(
        usage: TagUsage.question,
        tags: tags,
        resolver: _resolver(tags),
      );

      expect(scope.visibleTags, isEmpty);
      expect(scope.isEmpty, isTrue);
      expect(scope.hasAnyDeclaration, isTrue);
    });
  });

  group('文案', () {
    final l10n = AppLocalizationsZh();

    test('三个域的名字', () {
      expect(tagUsageLabel(l10n, TagUsage.question), l10n.tagUsageQuestion);
      expect(tagUsageLabel(l10n, TagUsage.task), l10n.tagUsageTask);
      expect(tagUsageLabel(l10n, TagUsage.knowledge), l10n.tagUsageKnowledge);
    });

    test('没有界面名字的用途直接抛，不静默回落', () {
      expect(
        () => tagUsageLabel(l10n, TagUsage.time),
        throwsArgumentError,
      );
      expect(
        () => tagUsageLabel(l10n, TagUsage.flashcard),
        throwsArgumentError,
      );
    });

    test('声明过用途时提示本域过滤，没声明时提示默认全列', () {
      const declared = TagUsageScope(
        usage: TagUsage.question,
        tags: [],
        visibleTags: [],
        hasAnyDeclaration: true,
      );
      const undeclared = TagUsageScope(
        usage: TagUsage.question,
        tags: [],
        visibleTags: [],
        hasAnyDeclaration: false,
      );

      expect(
        tagUsageScopeHint(l10n, declared),
        l10n.tagUsageScopeHintNamed(l10n.tagUsageQuestion),
      );
      expect(
          tagUsageScopeHint(l10n, undeclared), l10n.tagUsageScopeDefaultHint);
      expect(
        tagUsageScopeEmptyText(l10n, declared),
        l10n.tagUsageScopeEmptyNamed(l10n.tagUsageQuestion),
      );
    });
  });

  testWidgets('loadTagUsageScope 读库并让继承生效', (tester) async {
    final db = await _openDatabase();
    await _seedTag(db, id: 't-bio', name: '生物', usageCodes: 'question');
    await _seedTag(db, id: 't-cell', name: '细胞', parentId: 't-bio');
    await _seedTag(db, id: 't-word', name: '单词', usageCodes: 'flashcard');

    await _pumpProbe(tester, db, TagUsage.question);

    expect(find.text('生物|细胞 declared=true'), findsOneWidget);
    expect(find.textContaining('单词'), findsNothing);
  });
}
