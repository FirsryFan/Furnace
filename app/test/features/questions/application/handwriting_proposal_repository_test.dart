/// 拍照整理提案的持久化验收（schema v13，`docs/HANDWRITING_INTAKE_DESIGN.md` §4）。
///
/// 这一层要证明的口径只有三条：
///
///  1. 存进去什么，读回来还是什么（顺序、三类产物、逐字内容）；
///  2. **"用户已经确认过"不能被重新整理冲掉**——逐字没变的提案保留确认时间，
///     内容变了的清成未确认（那一条是新版本，用户没确认过它）；
///  3. 一张照片只有一条 run：重复整理是覆盖，不是追加。
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/handwriting_proposal_repository.dart';
import 'package:furnace/domain/services/intake/handwriting_proposals.dart';

void main() {
  late AppDatabase db;
  late HandwritingProposalRepository repository;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repository = HandwritingProposalRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  HandwritingProposalSet setOf(List<HandwritingProposal> proposals) =>
      HandwritingProposalSet(
        sourceRef: 'handwriting_intake/hw-1/page.png',
        proposals: proposals,
      );

  const tag = HandwritingProposal(
    id: 'tag-0',
    kind: HandwritingProposalKind.tag,
    titleZh: '动量守恒',
    rationaleZh: '照片里反复出现',
    confidence: 0.8,
    fields: <String, String>{'parent_path': '文化课/物理/力学'},
  );

  const point = HandwritingProposal(
    id: 'knowledge_point-1',
    kind: HandwritingProposalKind.knowledgePoint,
    titleZh: '动量守恒的条件',
    fields: <String, String>{'content': '合外力为零'},
  );

  const card = HandwritingProposal(
    id: 'flashcard-2',
    kind: HandwritingProposalKind.flashcard,
    titleZh: '动量守恒',
    fields: <String, String>{'content': '正文'},
    cards: <HandwritingCardDraft>[
      HandwritingCardDraft(question: '条件是什么？', answer: '合外力为零。'),
    ],
  );

  test('saveRun → runs/runOf：三类产物顺序与逐字内容都在', () async {
    final analyzedAt = DateTime(2026, 10, 16, 9, 30);
    await repository.saveRun(
      set: setOf(<HandwritingProposal>[tag, point, card]),
      analyzedAt: analyzedAt,
      rawReply: '模型原话',
    );

    final runs = await repository.runs();
    expect(runs, hasLength(1));
    final run = runs.single;
    expect(run.sourceRef, 'handwriting_intake/hw-1/page.png');
    expect(run.analyzedAt, analyzedAt);
    expect(run.rawReply, '模型原话');
    expect(
      run.proposals.map((stored) => stored.proposal.id),
      <String>['tag-0', 'knowledge_point-1', 'flashcard-2'],
    );
    expect(run.appliedProposalIds, isEmpty);
    // 逐字往返（id/kind/字段/卡片/置信度）。唯一被覆写的是 `source_ref`：
    // 从库里读回来的提案永远知道自己来自哪张照片。
    expect(run.proposalSet.sourceRef, 'handwriting_intake/hw-1/page.png');
    for (var i = 0; i < run.proposals.length; i++) {
      expect(
        run.proposalSet.proposals[i].toJson(),
        <String, Object?>{
          ...<HandwritingProposal>[tag, point, card][i].toJson(),
          'source_ref': run.sourceRef,
        },
      );
    }
    expect(run.proposalSet.proposals[2].cards.single.answer, '合外力为零。');

    final one = await repository.runOf('handwriting_intake/hw-1/page.png');
    expect(one!.proposalSet.proposals, hasLength(3));
    expect(await repository.runOf('handwriting_intake/hw-9/gone.png'), isNull);
  });

  test('零提案也是一次整理：run 行留着，proposals 为空', () async {
    await repository.saveRun(
      set: setOf(<HandwritingProposal>[]),
      analyzedAt: DateTime(2026, 10, 16, 10),
    );

    final run = (await repository.runs()).single;
    expect(run.proposals, isEmpty);
    expect(run.proposalSet.isEmpty, isTrue);
    expect(run.rawReply, isNull);
  });

  test('重复整理是覆盖：行数不翻倍，逐字没变的保留确认时间', () async {
    final first = DateTime(2026, 10, 16, 11);
    await repository.saveRun(
      set: setOf(<HandwritingProposal>[tag, point]),
      analyzedAt: first,
    );
    await repository.markApplied(
      sourceRef: 'handwriting_intake/hw-1/page.png',
      proposalId: 'tag-0',
      appliedAt: DateTime(2026, 10, 16, 11, 5),
    );

    // 第二次整理：tag 逐字没变、point 内容变了。
    const editedPoint = HandwritingProposal(
      id: 'knowledge_point-1',
      kind: HandwritingProposalKind.knowledgePoint,
      titleZh: '动量守恒的条件',
      fields: <String, String>{'content': '合外力为零（改过）'},
    );
    final second = DateTime(2026, 10, 16, 12);
    await repository.saveRun(
      set: setOf(<HandwritingProposal>[tag, editedPoint]),
      analyzedAt: second,
    );

    final run = (await repository.runs()).single;
    expect(run.proposals, hasLength(2));
    expect(run.analyzedAt, second);
    final storedTag = run.proposals.firstWhere(
      (stored) => stored.proposal.id == 'tag-0',
    );
    final storedPoint = run.proposals.firstWhere(
      (stored) => stored.proposal.id == 'knowledge_point-1',
    );
    // 用户确认过的那条（逐字相同）不该被当成"没确认过"。
    expect(storedTag.isApplied, isTrue);
    expect(storedTag.appliedAt, DateTime(2026, 10, 16, 11, 5));
    // 内容变了 = 新版本，确认状态清掉。
    expect(storedPoint.isApplied, isFalse);
    expect(run.appliedProposalIds, <String>{'tag-0'});
  });

  test('markApplied：只标记点名的那条，且标记过的时间不被覆盖', () async {
    final appliedAt = DateTime(2026, 10, 16, 13);
    await repository.saveRun(
      set: setOf(<HandwritingProposal>[tag, point]),
      analyzedAt: DateTime(2026, 10, 16, 12),
    );
    await repository.markApplied(
      sourceRef: 'handwriting_intake/hw-1/page.png',
      proposalId: 'point-0-nope',
      appliedAt: appliedAt,
    );
    // 点了一条不存在的提案：什么都不该变。
    var run = (await repository.runs()).single;
    expect(run.appliedProposalIds, isEmpty);

    await repository.markApplied(
      sourceRef: 'handwriting_intake/hw-1/page.png',
      proposalId: 'point-1',
      appliedAt: DateTime(2026, 10, 16, 12, 30),
    );
    await repository.markApplied(
      sourceRef: 'handwriting_intake/hw-1/page.png',
      proposalId: 'knowledge_point-1',
      appliedAt: appliedAt,
    );
    // 再点一次（用户手滑）：第一次确认的时间不该被改写。
    await repository.markApplied(
      sourceRef: 'handwriting_intake/hw-1/page.png',
      proposalId: 'knowledge_point-1',
      appliedAt: DateTime(2026, 10, 16, 23),
    );

    run = (await repository.runs()).single;
    expect(run.appliedProposalIds, <String>{'knowledge_point-1'});
    expect(
      run.proposals
          .firstWhere((stored) => stored.proposal.id == 'knowledge_point-1')
          .appliedAt,
      appliedAt,
    );
  });

  test('deleteRun 只删这一张照片；deleteAll 清空', () async {
    await repository.saveRun(
      set: setOf(<HandwritingProposal>[tag]),
      analyzedAt: DateTime(2026, 10, 16, 14),
    );
    await repository.saveRun(
      set: const HandwritingProposalSet(
        sourceRef: 'handwriting_intake/hw-2/page.png',
        proposals: <HandwritingProposal>[point],
      ),
      analyzedAt: DateTime(2026, 10, 16, 15),
    );
    expect(await repository.runs(), hasLength(2));

    await repository.deleteRun('handwriting_intake/hw-1/page.png');
    var runs = await repository.runs();
    expect(runs, hasLength(1));
    expect(runs.single.sourceRef, 'handwriting_intake/hw-2/page.png');
    expect(await repository.runOf('handwriting_intake/hw-1/page.png'), isNull);

    await repository.deleteAll();
    expect(await repository.runs(), isEmpty);
  });
}
