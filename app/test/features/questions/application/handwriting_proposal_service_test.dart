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
import 'package:furnace/data/repositories/question_repository.dart';
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
  late QuestionRepository questions;
  late Directory root;
  late FakeIntakeStore store;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    tags = TagRepository(db);
    anki = AnkiRepository(db);
    questions = QuestionRepository(db);
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
        questions: questions,
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

  group('题目（第四类产物）', () {
    Future<HandwritingProposalSet> setOf(List<String> proposals) async =>
        parseHandwritingProposals(
          reply(proposals),
          sourceRef: 'handwriting_intake/hw/1/page.png',
        );

    const questionJson = '{"kind": "question", "title": "动量守恒判断", '
        '"fields": {"stem": "下列情况中动量守恒的是？", "answer": "B"}, '
        '"options": ['
        '{"label": "A", "content": "合外力不为零"},'
        '{"label": "B", "content": "合外力为零"},'
        '{"label": "C", "content": "内力远大于外力"}'
        ']}';

    test('题目：题干、选项、答案字母与题型一起入库', () async {
      final set = await setOf(<String>[questionJson]);

      final report = await serviceWith(null).applyAll(set);

      expect(report.allOk, isTrue, reason: report.outcomes.first.failureReason);
      final question = (await db.select(db.questions).get()).single;
      expect(question.stem, '下列情况中动量守恒的是？');
      expect(question.answer, 'B');
      expect(question.questionType, 'single_choice');
      expect(question.origin, 'ai_scan');
      expect(question.state, 'structured');
      expect(question.sourceLabel, '拍照整理');
      // v24 的题号在入库事务里分配，拍出来的题也必须有号。
      expect(question.serialNo, isNotNull);
      expect(report.outcomes.single.detailZh, contains('建了题目'));

      final options = await db.select(db.questionOptions).get();
      options.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      expect(options.map((option) => option.label), ['A', 'B', 'C']);
      expect(options.map((option) => option.isCorrect), [false, true, false]);
      expect(options.map((option) => option.sortOrder), [0, 1, 2]);
      expect(options.map((option) => option.questionId).toSet(), {question.id});
    });

    test('题干为空：直接失败，不写一条空题', () async {
      const set = HandwritingProposalSet(
        sourceRef: 'handwriting_intake/hw/1/page.png',
        proposals: <HandwritingProposal>[
          HandwritingProposal(
            id: 'question-0',
            kind: HandwritingProposalKind.question,
            titleZh: '看不清的题目',
            fields: <String, String>{'answer': 'B'},
          ),
        ],
      );

      final report = await serviceWith(null).applyAll(set);

      expect(report.allOk, isFalse);
      expect(report.outcomes.single.failureReason, contains('缺少题干'));
      expect(await db.select(db.questions).get(), isEmpty);
    });

    test('同题干已经有了：不重复入库，并告诉用户是哪一道', () async {
      final set = await setOf(<String>[questionJson]);
      final service = serviceWith(null);

      final first = await service.applyAll(set);
      final second = await service.applyAll(set);

      expect(first.outcomes.single.ok, isTrue);
      expect(second.outcomes.single.ok, isTrue);
      expect(second.outcomes.single.detailZh, contains('没有重复入库'));
      expect(second.outcomes.single.detailZh, contains('TR-'));
      expect(second.outcomes.single.targetId, first.outcomes.single.targetId);
      expect(await db.select(db.questions).get(), hasLength(1));
      expect(await db.select(db.questionOptions).get(), hasLength(3));
    });

    test('题目也能挂标签：object_tags 记在题目上', () async {
      final tag = await seedTagPath('文化课/物理/力学');
      final set = await setOf(<String>[
        '{"kind": "question", "title": "动量题", '
            '"fields": {"stem": "质量为 m 的小球碰撞后……", '
            '"tag_path": "文化课/物理/力学"}}',
      ]);

      final report = await serviceWith(null).applyAll(set);

      final question = (await db.select(db.questions).get()).single;
      expect(report.outcomes.single.ok, isTrue);
      expect(report.outcomes.single.detailZh, contains('并挂到'));
      final links = await db.select(db.objectTags).get();
      expect(links, hasLength(1));
      expect(links.single.objectType, 'question');
      expect(links.single.objectId, question.id);
      expect(links.single.tagId, tag.id);
    });

    test('题目标签路径不存在：题照建，明说没挂边', () async {
      final set = await setOf(<String>[
        '{"kind": "question", "title": "动量题", '
            '"fields": {"stem": "质量为 m 的小球碰撞后……", '
            '"tag_path": "其实/没有/这个路径"}}',
      ]);

      final report = await serviceWith(null).applyAll(set);

      expect(report.outcomes.single.ok, isTrue);
      expect(report.outcomes.single.detailZh, contains('没挂边'));
      expect(await db.select(db.questions).get(), hasLength(1));
      expect(await db.select(db.objectTags).get(), isEmpty);
    });

    test('纯文字题：没有选项时按解答题入库，答案正文原样保留', () async {
      final set = await setOf(<String>[
        '{"kind": "question", "title": "动量守恒条件", '
            '"fields": {"stem": "说明动量守恒的条件。", "answer": "合外力为零。", '
            '"solution": "由动量定理……"}}',
      ]);

      final report = await serviceWith(null).applyAll(set);

      final question = (await db.select(db.questions).get()).single;
      expect(report.outcomes.single.detailZh, contains('纯文字题'));
      expect(question.questionType, 'solution');
      expect(question.answer, '合外力为零。');
      expect(question.solution, '由动量定理……');
      expect(await db.select(db.questionOptions).get(), isEmpty);
    });

    test('答案不是字母时不猜：选项照存，正确项留空', () async {
      final set = await setOf(<String>[
        '{"kind": "question", "title": "动量题", '
            '"fields": {"stem": "下列说法正确的是？", "answer": "合外力为零时动量守恒"}, '
            '"options": [{"label": "A", "content": "甲"}, '
        '{"label": "B", "content": "乙"}]}',
      ]);

      final report = await serviceWith(null).applyAll(set);

      final question = (await db.select(db.questions).get()).single;
      final options = await db.select(db.questionOptions).get();
      expect(report.outcomes.single.ok, isTrue);
      expect(question.questionType, 'single_choice');
      expect(question.answer, '合外力为零时动量守恒');
      expect(options, hasLength(2));
      expect(options.every((option) => !option.isCorrect), isTrue);
    });

    test('多选题：A、C 与 AC 都认成两个正确选项', () async {
      const optionsJson = '"options": [{"label": "A", "content": "甲"}, '
          '{"label": "B", "content": "乙"}, {"label": "C", "content": "丙"}]';
      final set = await setOf(<String>[
        '{"kind": "question", "title": "多选一", '
            '"fields": {"stem": "多选第一题", "answer": "A、C"}, $optionsJson}',
        '{"kind": "question", "title": "多选二", '
            '"fields": {"stem": "多选第二题", "answer": "AC"}, $optionsJson}',
      ]);

      final report = await serviceWith(null).applyAll(set);

      expect(report.appliedCount, 2, reason: report.outcomes.first.failureReason);
      final questions = await db.select(db.questions).get();
      expect(questions.map((question) => question.questionType).toSet(),
          {'multi_choice'});
      final correct = await (db.select(db.questionOptions)
            ..where((row) => row.isCorrect.equals(true)))
          .get();
      // 两题各 A、C 两个正确项。
      expect(correct, hasLength(4));
      expect(correct.map((option) => option.label).toSet(), {'A', 'C'});
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

      await notifier.forget(relPath);
      state = container.read(handwritingQueueProvider);
      expect(state.failures, isEmpty);
      expect(state.lastReport, isNull);
    });

    test('重启后队列还在：提案与「已确认到哪一条」都从库恢复', () async {
      final relPath = await seedPhoto();
      await seedTagPath('文化课/物理/力学');

      final before = containerWith(
        FakeModelAdapter(<List<ModelEvent>>[
          FakeModelAdapter.answer(reply(<String>[tagProposal])),
        ]),
      );
      final first = before.read(handwritingQueueProvider.notifier);
      await first.refresh();
      await first.analyze(relPath);
      await first.applyProposal(relPath, 'tag-0');
      expect(
        before.read(handwritingQueueProvider).isApplied(relPath, 'tag-0'),
        isTrue,
      );

      // 重启：新容器、同一个库与磁盘目录。
      final after = containerWith(
        FakeModelAdapter(<List<ModelEvent>>[
          FakeModelAdapter.answer(reply(<String>[tagProposal])),
        ]),
      );
      final second = after.read(handwritingQueueProvider.notifier);
      await second.refresh();

      var state = after.read(handwritingQueueProvider);
      expect(state.sets[relPath]!.proposals, hasLength(1));
      expect(state.sets[relPath]!.proposals.single.titleZh, '动量守恒');
      expect(state.isApplied(relPath, 'tag-0'), isTrue);

      // 不重启也不会重复写第二份。
      expect(await second.applyProposal(relPath, 'tag-0'), isNull);
      expect(await tags.getAllTags(), hasLength(4));
    });

    test('重新整理：内容逐字没变的保留确认状态，内容变了的清掉', () async {
      final relPath = await seedPhoto();
      await seedTagPath('文化课/物理/力学');

      final first = containerWith(
        FakeModelAdapter(<List<ModelEvent>>[
          FakeModelAdapter.answer(reply(<String>[tagProposal])),
        ]),
      );
      final notifier = first.read(handwritingQueueProvider.notifier);
      await notifier.refresh();
      await notifier.analyze(relPath);
      await notifier.applyProposal(relPath, 'tag-0');

      // 同一条提案重新整理（同样的 id、同样的字段）→ 仍视为已确认。
      final same = containerWith(
        FakeModelAdapter(<List<ModelEvent>>[
          FakeModelAdapter.answer(reply(<String>[tagProposal])),
        ]),
      );
      final sameNotifier = same.read(handwritingQueueProvider.notifier);
      await sameNotifier.refresh();
      await sameNotifier.analyze(relPath);
      expect(
        same.read(handwritingQueueProvider).isApplied(relPath, 'tag-0'),
        isTrue,
      );

      // 字段变了（换了父路径）→ 用户没确认过这个版本，确认状态清掉。
      const changed = '{"kind": "tag", "title": "动量守恒", '
          '"fields": {"parent_path": "文化课/物理/力学/动量子项"}}';
      final edited = containerWith(
        FakeModelAdapter(<List<ModelEvent>>[
          FakeModelAdapter.answer(reply(<String>[tagProposal])),
          FakeModelAdapter.answer(reply(<String>[changed])),
        ]),
      );
      final editedNotifier = edited.read(handwritingQueueProvider.notifier);
      await editedNotifier.refresh();
      await editedNotifier.analyze(relPath);
      await editedNotifier.applyProposal(relPath, 'tag-0');
      expect(
        edited.read(handwritingQueueProvider).isApplied(relPath, 'tag-0'),
        isTrue,
      );
      await editedNotifier.analyze(relPath);
      expect(
        edited.read(handwritingQueueProvider).isApplied(relPath, 'tag-0'),
        isFalse,
      );
    });

    test('forget 之后重启不会复活；照片本身留在磁盘上', () async {
      final relPath = await seedPhoto();
      final container = containerWith(
        FakeModelAdapter(<List<ModelEvent>>[
          FakeModelAdapter.answer(reply(<String>[tagProposal])),
        ]),
      );
      final notifier = container.read(handwritingQueueProvider.notifier);
      await notifier.refresh();
      await notifier.analyze(relPath);
      expect(container.read(handwritingQueueProvider).sets, isNotEmpty);

      await notifier.forget(relPath);

      final restarted = containerWith(null);
      await restarted.read(handwritingQueueProvider.notifier).refresh();
      final state = restarted.read(handwritingQueueProvider);
      expect(state.sets, isEmpty);
      expect(state.images.map((image) => image.relPath), contains(relPath));
    });

    test('照片已经不在磁盘上：refresh 顺手清掉它的整理记录', () async {
      final relPath = await seedPhoto();
      final container = containerWith(
        FakeModelAdapter(<List<ModelEvent>>[
          FakeModelAdapter.answer(reply(<String>[tagProposal])),
        ]),
      );
      final notifier = container.read(handwritingQueueProvider.notifier);
      await notifier.refresh();
      await notifier.analyze(relPath);

      // 用户在别处把照片删了（这里直接把文件与 attachments 行一起删）。
      final image = (await store.pending()).single;
      await store.delete(image);

      final restarted = containerWith(null);
      await restarted.read(handwritingQueueProvider.notifier).refresh();
      expect(restarted.read(handwritingQueueProvider).sets, isEmpty);

      // 库里的行也清掉了：换一个容器再看，还是没有。
      final again = containerWith(null);
      await again.read(handwritingQueueProvider.notifier).refresh();
      expect(again.read(handwritingQueueProvider).sets, isEmpty);
    });
  });
}
