/// 拍照整理的应用层验收：`docs/QUESTION_BANK_DESIGN.md` §7.3–§7.4。
///
/// 这一组测试盯着的核心口径是「**确认前不写库**」：
///
///  1. 整理（`proposeFor`）只出网点，一个字都不写库——失败四态（文件不在 /
///     格式认不出 / 离线没模型 / 回复不合契约）全部返回结果对象，不抛异常；
///  2. 写库只在确认之后发生，且三样东西各按既有规矩写：标签挂**已有**父路径、
///     知识点进 `knowledge_points`、闪存卡建模板后**必须**建卡状态；
///  3. 一条失败不影响其它条；已经确认过的提案不会被点第二次写出第二份。
///
/// 照片用 `FakeIntakeStore`（同步落盘 + 真 `attachments` 行，见
/// `../support/picked_file_fakes.dart`），模型用 `FakeModelAdapter`——不需要网络，
/// 也不需要真实的 app support 目录。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/app_database_provider.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/anki_repository.dart';
import 'package:furnace/data/repositories/tag_repository.dart';
import 'package:furnace/domain/services/intake/handwriting_proposals.dart';
import 'package:furnace/features/ai/domain/model_adapter.dart';
import 'package:furnace/features/ai/infrastructure/fake_model_adapter.dart';
import 'package:furnace/features/questions/application/handwriting_proposal_service.dart';

import '../support/picked_file_fakes.dart';

void main() {
  late AppDatabase db;
  late TagRepository tags;
  late AnkiRepository anki;
  late Directory root;
  late FakeIntakeStore store;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    tags = TagRepository(db);
    anki = AnkiRepository(db);
    root = Directory.systemTemp.createTempSync('furnace_intake_proposal_');
    store = FakeIntakeStore(database: db, root: root);
  });

  tearDown(() async {
    await db.close();
    if (root.existsSync()) {
      root.deleteSync(recursive: true);
    }
  });

  HandwritingProposalService serviceWith(ModelAdapter? adapter) =>
      HandwritingProposalService(
        store: store,
        tags: tags,
        anki: anki,
        adapter: adapter,
      );

  /// 落一张假照片，返回它的相对路径。
  Future<String> seedPhoto([String name = 'page.png']) async {
    final image = await store.save(
      FakePickedFile(name, Uint8List.fromList(<int>[1, 2, 3, 4])),
    );
    return image.relPath;
  }

  /// 逐层建出一条标签路径（路径是由父节点推出来的）。
  Future<Tag> seedTagPath(String path) async {
    Tag? parent;
    for (final segment in path.split('/')) {
      parent = parent == null
          ? await tags.createTag(name: segment)
          : await tags.createTag(name: segment, parentId: parent.id);
    }
    return parent!;
  }

  String reply(List<String> proposals) =>
      '{"proposals": [${proposals.join(',')}]}';

  const tagProposal = '{"kind": "tag", "title": "动量守恒", '
      '"fields": {"parent_path": "文化课/物理/力学"}}';

  group('整理（proposeFor）', () {
    test('照片不在了：如实说照片不在了，不编造提案', () async {
      final service = serviceWith(
        FakeModelAdapter(<List<ModelEvent>>[FakeModelAdapter.answer('{}')]),
      );
      final run = await service.proposeFor('handwriting_intake/gone/page.png');

      expect(run.ok, isFalse);
      expect(run.failureReason, contains('照片不在了'));
      expect(run.set, isNull);
    });

    test('认不出格式：不把 pdf 当成图送去"看"', () async {
      final relPath = await seedPhoto('notes.pdf');
      final service = serviceWith(
        FakeModelAdapter(<List<ModelEvent>>[FakeModelAdapter.answer('{}')]),
      );
      final run = await service.proposeFor(relPath);

      expect(run.ok, isFalse);
      expect(run.failureReason, contains('认不出'));
      expect(run.failureReason, contains('notes.pdf'));
    });

    test('离线：没有适配器时明说没模型可用，不假装整理过', () async {
      final relPath = await seedPhoto();
      final run = await serviceWith(null).proposeFor(relPath);

      expect(run.ok, isFalse);
      expect(run.failureReason, contains('没有可用的模型适配器'));
    });

    test('成功：拿到提案，提示词里带上"现在有什么"和照片本体', () async {
      final relPath = await seedPhoto('hw-1.png');
      await seedTagPath('文化课/物理/力学');
      await anki.createKnowledgePoint(title: '动量守恒的条件', content: '已有内容');

      final adapter = FakeModelAdapter(<List<ModelEvent>>[
        FakeModelAdapter.answer(reply(<String>[tagProposal])),
      ]);
      final run = await serviceWith(adapter).proposeFor(relPath);

      expect(run.ok, isTrue, reason: run.failureReason);
      expect(run.set!.proposals, hasLength(1));
      expect(run.set!.sourceRef, relPath);

      final request = adapter.requests.single;
      expect(request.tools, isEmpty);
      final system = request.messages.first.content ?? '';
      expect(system, contains('文化课/物理/力学'));
      expect(system, contains('动量守恒的条件'));
      final user = request.messages.last;
      expect(user.images, hasLength(1));
      expect(user.images.single.mime, 'image/png');
      expect(user.images.single.base64, base64Encode(<int>[1, 2, 3, 4]));
    });

    test('模型报错：返回失败并带上已经收到的原文', () async {
      final relPath = await seedPhoto();
      final adapter = FakeModelAdapter(<List<ModelEvent>>[
        <ModelEvent>[
          const ModelTextDelta('我看到'),
          const ModelFailure('502 Bad Gateway'),
        ],
      ]);
      final run = await serviceWith(adapter).proposeFor(relPath);

      expect(run.ok, isFalse);
      expect(run.failureReason, contains('模型调用失败'));
      expect(run.failureReason, contains('502'));
      expect(run.rawReply, '我看到');
    });

    test('回复不合契约：报"不符合契约"并把原文留着排查', () async {
      final relPath = await seedPhoto();
      final adapter = FakeModelAdapter(<List<ModelEvent>>[
        FakeModelAdapter.answer('这一页看起来是物理笔记。'),
      ]);
      final run = await serviceWith(adapter).proposeFor(relPath);

      expect(run.ok, isFalse);
      expect(run.failureReason, contains('不符合契约'));
      expect(run.rawReply, contains('物理笔记'));
    });
  });

  group('写库（applyAll）', () {
    Future<HandwritingProposalSet> setOf(List<String> proposals) async =>
        parseHandwritingProposals(
          reply(proposals),
          sourceRef: 'handwriting_intake/hw/1/page.png',
        );

    test('标签挂到已有父路径下', () async {
      final parent = await seedTagPath('文化课/物理/力学');
      final set = await setOf(<String>[tagProposal]);

      final report = await serviceWith(null).applyAll(set);

      expect(report.allOk, isTrue, reason: report.outcomes.first.failureReason);
      expect(report.appliedCount, 1);
      final created = await tags.getTagByPath('文化课/物理/力学/动量守恒');
      expect(created, isNotNull);
      expect(created!.parentId, parent.id);
      expect(report.outcomes.single.targetId, created.id);
    });

    test('标签父路径不存在：只报这一条，绝不凭空造一棵树', () async {
      final set = await setOf(<String>[
        '{"kind": "tag", "title": "动量守恒", '
            '"fields": {"parent_path": "不存在的/路径"}}',
      ]);

      final report = await serviceWith(null).applyAll(set);

      expect(report.allOk, isFalse);
      expect(report.outcomes.single.failureReason, contains('标签树里没有'));
      expect(await tags.getAllTags(), isEmpty);
    });

    test('标签已存在：采用既有的，不建重复', () async {
      final existing = await seedTagPath('文化课/物理/力学/动量守恒');
      final set = await setOf(<String>[tagProposal]);

      final report = await serviceWith(null).applyAll(set);

      expect(report.allOk, isTrue);
      expect(report.outcomes.single.targetId, existing.id);
      // 只有种子那四层，没有多出第五个。
      expect(await tags.getAllTags(), hasLength(4));
    });

    test('知识点：建点并挂到已有标签', () async {
      final tag = await seedTagPath('文化课/物理/力学');
      final set = await setOf(<String>[
        '{"kind": "knowledge_point", "title": "动量守恒的条件", '
            '"fields": {"content": "合外力为零", "tag_path": "文化课/物理/力学"}}',
      ]);

      final report = await serviceWith(null).applyAll(set);

      expect(report.allOk, isTrue, reason: report.outcomes.first.failureReason);
      final points = await anki.getKnowledgePoints();
      expect(points, hasLength(1));
      expect(points.single.title, '动量守恒的条件');
      expect(points.single.content, '合外力为零');
      expect(points.single.source, 'handwriting_intake');

      final links = await db.select(db.objectTags).get();
      expect(links, hasLength(1));
      expect(links.single.objectType, 'knowledge_point');
      expect(links.single.objectId, points.single.id);
      expect(links.single.tagId, tag.id);
    });

    test('知识点：标签路径不存在时，点照建——只是没挂边', () async {
      final set = await setOf(<String>[
        '{"kind": "knowledge_point", "title": "动量守恒的条件", '
            '"fields": {"content": "合外力为零", "tag_path": "其实/没有/这个路径"}}',
      ]);

      final report = await serviceWith(null).applyAll(set);

      expect(report.allOk, isTrue);
      expect(report.outcomes.single.detailZh, contains('没挂边'));
      expect(await anki.getKnowledgePoints(), hasLength(1));
      expect(await db.select(db.objectTags).get(), isEmpty);
    });

    test('闪存卡：建知识点 + 每张卡 + 每张卡的复习状态', () async {
      final set = await setOf(<String>[
        '{"kind": "flashcard", "title": "动量守恒", '
            '"fields": {"content": "正文"}, '
            '"cards": ['
            '{"question": "条件是什么？", "answer": "合外力为零。"},'
            '{"question": "公式？", "answer": "m1v1 + m2v2 = 常量", "type": "fill_blank"}'
            ']}',
      ]);

      final report = await serviceWith(null).applyAll(set);

      expect(report.allOk, isTrue, reason: report.outcomes.first.failureReason);
      expect(report.outcomes.single.detailZh, contains('2 张卡片'));

      final points = await anki.getKnowledgePoints();
      expect(points, hasLength(1));
      final templates =
          await anki.getTemplatesForKnowledgePoint(points.single.id);
      expect(templates, hasLength(2));
      expect(
        templates.map((template) => template.type),
        ['essay', 'fill_blank'],
      );

      // 没有卡状态的卡片进不了复习队列——建卡的全部意义就在这里。
      final states = await db.select(db.cardStates).get();
      expect(states, hasLength(2));
      expect(
        states.map((state) => state.cardTemplateId).toSet(),
        templates.map((template) => template.id).toSet(),
      );
    });

    test('只写被确认的那一条（onlyIds）', () async {
      final set = await setOf(<String>[
        tagProposal,
        '{"kind": "knowledge_point", "title": "动量守恒的条件", '
            '"fields": {"content": "合外力为零"}}',
      ]);
      await seedTagPath('文化课/物理/力学');

      final report =
          await serviceWith(null).applyAll(set, onlyIds: <String>{'tag-0'});

      expect(report.outcomes, hasLength(1));
      expect(report.outcomes.single.proposalId, 'tag-0');
      expect(await anki.getKnowledgePoints(), isEmpty);
      expect(await tags.getTagByPath('文化课/物理/力学/动量守恒'), isNotNull);
    });
  });

  group('内存队列（handwritingQueueProvider）', () {
    ProviderContainer containerWith(ModelAdapter? adapter) {
      final container = ProviderContainer(
        overrides: <Override>[
          appDatabaseProvider.overrideWithValue(db),
          handwritingIntakeStoreProvider.overrideWithValue(store),
          handwritingProposalServiceProvider.overrideWithValue(
            serviceWith(adapter),
          ),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('refresh → analyze → 逐条确认；重复确认不再写第二份', () async {
      final relPath = await seedPhoto();
      await seedTagPath('文化课/物理/力学');

      final container = containerWith(
        FakeModelAdapter(<List<ModelEvent>>[
          FakeModelAdapter.answer(reply(<String>[tagProposal])),
        ]),
      );
      final notifier = container.read(handwritingQueueProvider.notifier);

      await notifier.refresh();
      expect(container.read(handwritingQueueProvider).images, hasLength(1));

      final run = await notifier.analyze(relPath);
      expect(run.ok, isTrue);
      var state = container.read(handwritingQueueProvider);
      expect(state.sets[relPath]!.proposals, hasLength(1));
      expect(state.failures, isEmpty);
      expect(state.analyzing, isEmpty);

      final report = await notifier.applyProposal(relPath, 'tag-0');
      expect(report!.allOk, isTrue);
      state = container.read(handwritingQueueProvider);
      expect(state.isApplied(relPath, 'tag-0'), isTrue);
      expect(state.applying, isEmpty);
      expect(await tags.getAllTags(), hasLength(4));

      // 再点一次：什么都不写（写库是新建，点两次就会有两份）。
      expect(await notifier.applyProposal(relPath, 'tag-0'), isNull);
      expect(await tags.getAllTags(), hasLength(4));
      // 没有剩余提案可确认。
      expect(await notifier.applyAll(relPath), isNull);
    });

    test('整理失败：失败原因进 state，不留下旧提案；forget 可以清掉', () async {
      final relPath = await seedPhoto();
      final container = containerWith(
        FakeModelAdapter(<List<ModelEvent>>[
          FakeModelAdapter.failure('网络断了'),
        ]),
      );
      final notifier = container.read(handwritingQueueProvider.notifier);

      final run = await notifier.analyze(relPath);
      expect(run.ok, isFalse);

      var state = container.read(handwritingQueueProvider);
      expect(state.sets, isEmpty);
      expect(state.failures[relPath], contains('网络断了'));
      expect(state.analyzing, isEmpty);

      notifier.forget(relPath);
      state = container.read(handwritingQueueProvider);
      expect(state.failures, isEmpty);
      expect(state.lastReport, isNull);
    });
  });
}
