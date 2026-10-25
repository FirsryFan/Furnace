import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/tags/tag_usage.dart';

TagUsageNode node(
  String id, {
  String? parentId,
  Set<TagUsage>? declared,
}) =>
    TagUsageNode(id: id, parentId: parentId, declaredUsages: declared);

void main() {
  group('编码/解码', () {
    test('空集合编码成 null（这一级没有声明）', () {
      expect(encodeTagUsageCodes(const []), isNull);
      expect(encodeTagUsageCodes(const {}), isNull);
    });

    test('单个/多个用途编码成稳定 code，顺序与输入无关', () {
      expect(encodeTagUsageCodes({TagUsage.time}), 'time');
      expect(
        encodeTagUsageCodes({TagUsage.time, TagUsage.question}),
        'time,question',
      );
      expect(
        encodeTagUsageCodes({TagUsage.question, TagUsage.time}),
        'time,question',
        reason: '输出顺序固定为枚举声明顺序',
      );
    });

    test('编码去重', () {
      // Set.of 会在运行时去重（字面量里重复元素会被 analyzer 拦下）。
      final duplicates = Set<TagUsage>.of([
        TagUsage.task,
        TagUsage.task,
        TagUsage.flashcard,
      ]);
      expect(encodeTagUsageCodes(duplicates), 'task,flashcard');
    });

    test('null / 空串 / 全是分隔符解码成 null', () {
      expect(decodeTagUsageCodes(null), isNull);
      expect(decodeTagUsageCodes(''), isNull);
      expect(decodeTagUsageCodes(' , ,, '), isNull);
    });

    test('认不出的 code 被忽略，全认不出 = null', () {
      expect(decodeTagUsageCodes('bogus,other'), isNull);
      expect(decodeTagUsageCodes('time,bogus'), {TagUsage.time});
      expect(decodeTagUsageCodes('Time'), isNull, reason: 'code 区分大小写');
    });

    test('容忍空格', () {
      expect(
        decodeTagUsageCodes(' time , question '),
        {TagUsage.time, TagUsage.question},
      );
    });

    test('编码后解码回到同一集合', () {
      final usages = {
        TagUsage.time,
        TagUsage.knowledge,
        TagUsage.flashcard,
      };
      expect(decodeTagUsageCodes(encodeTagUsageCodes(usages)), usages);
    });

    test('fromCode 认 code，认不出返回 null', () {
      expect(TagUsage.fromCode('question'), TagUsage.question);
      expect(TagUsage.fromCode('QUESTION'), isNull);
      expect(TagUsage.fromCode(''), isNull);
    });
  });

  group('继承解析', () {
    test('整棵树都没声明 = 不限制：effective 为 null、任何用途都可见', () {
      final resolver = TagUsageResolver([
        node('root'),
        node('child', parentId: 'root'),
      ]);
      expect(resolver.effectiveFor('child'), isNull);
      expect(resolver.isVisibleFor('child', TagUsage.time), isTrue);
      expect(resolver.isVisibleFor('child', TagUsage.question), isTrue);
      expect(resolver.hasAnyDeclaration, isFalse);
    });

    test('自己声明了就用自己的', () {
      final resolver = TagUsageResolver([
        node('t', declared: {TagUsage.time}),
      ]);
      expect(resolver.declaredFor('t'), {TagUsage.time});
      expect(resolver.effectiveFor('t'), {TagUsage.time});
      expect(resolver.effectiveSourceTagId('t'), 't');
      expect(resolver.isVisibleFor('t', TagUsage.time), isTrue);
      expect(resolver.isVisibleFor('t', TagUsage.question), isFalse);
    });

    test('没声明的子标签继承父标签', () {
      final resolver = TagUsageResolver([
        node('parent', declared: {TagUsage.time}),
        node('child', parentId: 'parent'),
        node('grandchild', parentId: 'child'),
      ]);
      expect(resolver.declaredFor('child'), isNull);
      expect(resolver.effectiveFor('child'), {TagUsage.time});
      expect(resolver.effectiveFor('grandchild'), {TagUsage.time});
      expect(resolver.effectiveSourceTagId('grandchild'), 'parent');
    });

    test('最近一个声明了的祖先优先，不会一路合并', () {
      final resolver = TagUsageResolver([
        node('grand', declared: {TagUsage.time}),
        node('parent', parentId: 'grand', declared: {TagUsage.question}),
        node('child', parentId: 'parent'),
      ]);
      expect(resolver.effectiveFor('child'), {TagUsage.question},
          reason: '继承取最近一层声明，不做并集');
      expect(resolver.effectiveSourceTagId('child'), 'parent');
    });

    test('兄弟分支互不影响', () {
      final resolver = TagUsageResolver([
        node('root'),
        node('a', parentId: 'root', declared: {TagUsage.time}),
        node('a1', parentId: 'a'),
        node('b', parentId: 'root'),
      ]);
      expect(resolver.isVisibleFor('a1', TagUsage.time), isTrue);
      expect(resolver.isVisibleFor('b', TagUsage.question), isTrue,
          reason: 'b 这条链没声明 = 不限制');
      expect(resolver.isVisibleFor('b', TagUsage.time), isTrue);
    });

    test('子标签的声明覆盖祖先声明（不是并集）', () {
      final resolver = TagUsageResolver([
        node('root', declared: {TagUsage.time, TagUsage.question}),
        node('child', parentId: 'root', declared: {TagUsage.task}),
      ]);
      expect(resolver.effectiveFor('child'), {TagUsage.task});
      expect(resolver.isVisibleFor('child', TagUsage.time), isFalse);
      expect(resolver.isVisibleFor('child', TagUsage.task), isTrue);
    });

    test('未知标签 id 安全：不抛、不限制', () {
      final resolver = TagUsageResolver([
        node('t', declared: {TagUsage.time})
      ]);
      expect(resolver.nodeOf('nope'), isNull);
      expect(resolver.declaredFor('nope'), isNull);
      expect(resolver.effectiveFor('nope'), isNull);
      expect(resolver.effectiveSourceTagId('nope'), isNull);
      expect(resolver.isVisibleFor('nope', TagUsage.flashcard), isTrue);
    });

    test('坏数据成环不会死循环', () {
      final resolver = TagUsageResolver([
        node('a', parentId: 'b'),
        node('b', parentId: 'a'),
      ]);
      expect(resolver.effectiveFor('a'), isNull);
      expect(resolver.effectiveSourceTagId('b'), isNull);
    });

    test('空声明集合按「没有声明」处理：继承照常走，但计入声明数', () {
      final resolver = TagUsageResolver([
        node('root', declared: {TagUsage.time}),
        node('child', parentId: 'root', declared: const {}),
      ]);
      expect(resolver.effectiveFor('child'), {TagUsage.time},
          reason: '空集不会截断继承链（编码器写空集合时返回 null）');
      expect(resolver.isVisibleFor('child', TagUsage.question), isFalse);
      expect(resolver.hasAnyDeclaration, isTrue);
      expect(resolver.declaredTagCount, 2);
    });

    test('declaredTagCount 只数有声明值的行', () {
      final resolver = TagUsageResolver([
        node('a', declared: {TagUsage.time}),
        node('b'),
        node('c', declared: const {}),
      ]);
      expect(resolver.declaredTagCount, 2);
      expect(resolver.hasAnyDeclaration, isTrue);
    });
  });

  group('按用途过滤标签', () {
    test('visibleTagIdsFor 只留有声明链的标签', () {
      final resolver = TagUsageResolver([
        node('root', declared: {TagUsage.time}),
        node('root.child', parentId: 'root'),
        node('free'),
        node('other', declared: {TagUsage.question}),
      ]);
      expect(
        resolver.visibleTagIdsFor(TagUsage.time),
        {'root', 'root.child', 'free'},
        reason: 'free 没声明 = 不限制所以可见；other 声明了 question 所以不可见',
      );
    });

    test('visibleOf 保持输入顺序', () {
      final resolver = TagUsageResolver([
        node('a', declared: {TagUsage.time}),
        node('b', declared: {TagUsage.question}),
        node('c'),
      ]);
      expect(
        resolver.visibleOf(['c', 'b', 'a'], TagUsage.time),
        ['c', 'a'],
      );
    });
  });
}
