/// 材料入库页（`docs/MINDNET_ROADMAP.md` §2-C ① 的界面入口）。
///
/// 材料的三步走：**记号**（人在纸上写）→ **AI 提取**（读成一份 `mindnet.material/1`
/// 信封）→ **确定性转化**（`app/lib/domain/services/ingest/material_ingest.dart`）。
/// 本页只做第三步之后的两件事：
///
///  1. 贴信封 → **看提案**：会建哪些知识点、哪些连接，每条出自哪一页哪一行；
///     同名知识点标"已存在"（不重复建），不进图的角色留在清单外并写原因。
///  2. 勾选 → **确认入库**：写 `knowledge_points`（`external_id` = 材料决定的内容 id，
///     用户改过标题也认它）与 `knowledge_edges`（连接是线索边，两端都在才落，§2-C ④）。
///
/// 两个入口做的是同一件事：**贴信封**（现算现登记）与**从待确认清单恢复**
/// （把当初登记的那批读回来，不重算）。纪律：确认前不写知识点；"待确认清单"落库
/// （`applied_at` NULL），所以关掉页面不会丢，再打开时清单里还等着。
///
/// 本页不做 AI 提取（那是模型侧的活，工具 `ingest_material` 已在），也不做卡片的
/// 呈现层（INGEST §4 的可选产物，本层不产出）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/material_intake_repository.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../domain/services/ingest/material_ingest.dart';
import '../../../domain/services/ingest/material_intake_plan.dart';
import '../../../l10n/app_localizations.dart';
import '../application/material_intake_reader.dart';

/// 材料入库页。
class MaterialIntakePage extends ConsumerStatefulWidget {
  const MaterialIntakePage({super.key});

  @override
  ConsumerState<MaterialIntakePage> createState() => _MaterialIntakePageState();
}

class _MaterialIntakePageState extends ConsumerState<MaterialIntakePage> {
  final TextEditingController _envelopeController = TextEditingController();

  /// 屏幕上正在看的那批提案（贴信封算出来的，或从清单恢复回来的）。
  List<MaterialIntakeProposal> _proposals = const <MaterialIntakeProposal>[];
  List<MaterialIntakeSkip> _skipped = const <MaterialIntakeSkip>[];
  MaterialIntakeBatch? _batch;

  /// 还没有欠账的批次（关掉页面之后回来的入口）。
  List<MaterialIntakeBatch> _pendingBatches = const <MaterialIntakeBatch>[];

  MaterialApplyOutcome? _outcome;
  Set<String> _selected = <String>{};
  String? _error;
  bool _busy = false;
  bool _includeTopicHubs = false;

  @override
  void initState() {
    super.initState();
    _refreshPendingBatches();
  }

  @override
  void dispose() {
    _envelopeController.dispose();
    super.dispose();
  }

  /// 重新读一遍"待确认清单"（看提案/确认/清空之后都要刷）。
  Future<void> _refreshPendingBatches() async {
    final batches = await readPendingBatches(
      repository: ref.read(materialIntakeRepositoryProvider),
    );
    if (!mounted) {
      return;
    }
    setState(() => _pendingBatches = batches);
  }

  /// 看提案：推导一遍，并把这份提案登记成"待确认"（幂等）。
  Future<void> _preview() async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _error = null;
      _outcome = null;
    });
    final moment = DateTime.now();
    final repository = ref.read(materialIntakeRepositoryProvider);
    try {
      final draft = await readMaterialPlan(
        repository: repository,
        raw: _envelopeController.text,
        moment: moment,
        includeTopicHubs: _includeTopicHubs,
      );
      final batch = await recordMaterialPlan(
        repository: repository,
        draft: draft,
        moment: moment,
      );
      final pending = await readPendingBatches(repository: repository);
      if (!mounted) {
        return;
      }
      setState(() {
        _proposals = draft.plan.proposals;
        _skipped = draft.plan.skipped;
        _batch = batch;
        _pendingBatches = pending;
        _selected = <String>{
          for (final proposal in draft.plan.proposals) proposal.id,
        };
        _busy = false;
      });
    } on FormatException catch (error) {
      _fail(l10n.materialIntakeBadEnvelope(error.message));
    } on MaterialIngestException catch (error) {
      _fail(l10n.materialIntakeBadEnvelope(error.message));
    }
  }

  /// 从清单恢复：把那批还没确认的提案读回来接着看/接着确认（不重算）。
  Future<void> _restore(MaterialIntakeBatch batch) async {
    setState(() {
      _busy = true;
      _error = null;
      _outcome = null;
    });
    final repository = ref.read(materialIntakeRepositoryProvider);
    final pending = await readPendingBatch(
      repository: repository,
      batchId: batch.batchId,
    );
    if (!mounted) {
      return;
    }
    if (pending == null) {
      setState(() {
        _busy = false;
        _pendingBatches = <MaterialIntakeBatch>[
          for (final item in _pendingBatches)
            if (item.batchId != batch.batchId) item,
        ];
      });
      return;
    }
    setState(() {
      _proposals = pending.proposals;
      _skipped = pending.batch.skipped;
      _batch = pending.batch;
      _selected = <String>{
        for (final proposal in pending.proposals) proposal.id,
      };
      _busy = false;
    });
  }

  void _fail(String message) {
    if (!mounted) {
      return;
    }
    setState(() {
      _error = message;
      _proposals = const <MaterialIntakeProposal>[];
      _skipped = const <MaterialIntakeSkip>[];
      _batch = null;
      _selected = <String>{};
      _busy = false;
    });
  }

  /// 确认入库：知识点进 `knowledge_points`，连接落成 `knowledge_edges` 的线索边。
  ///
  /// 落不了的连接（有一端还不在库里）由 `apply` 如实报成 `deferred`，留在待办里。
  Future<void> _apply() async {
    final batch = _batch;
    if (batch == null) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final repository = ref.read(materialIntakeRepositoryProvider);
    try {
      final outcome = await repository.apply(
        batchId: batch.batchId,
        proposalIds: _selected.toList()..sort(),
        appliedAt: DateTime.now(),
      );
      // 确认之后的读数要取"现在"的：落不了的连接照旧没确认，所以 `unapplied_count`
      // 必须和成绩单上的"还剩"是同一个数（否则同一页上两个数字会互相打脸）。
      final fresh = await repository.batch(batch.batchId);
      final pending = await readPendingBatches(repository: repository);
      if (!mounted) {
        return;
      }
      setState(() {
        _outcome = outcome;
        _batch = fresh ?? _batch;
        _pendingBatches = pending;
        _busy = false;
      });
    } on MaterialApplyException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.message;
        _busy = false;
      });
    }
  }

  void _clear() {
    _envelopeController.clear();
    setState(() {
      _proposals = const <MaterialIntakeProposal>[];
      _skipped = const <MaterialIntakeSkip>[];
      _batch = null;
      _outcome = null;
      _selected = <String>{};
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.materialIntakeTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          _Note(text: l10n.materialIntakeIntro),
          const SizedBox(height: 12),
          TextField(
            controller: _envelopeController,
            minLines: 4,
            maxLines: 10,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            decoration: InputDecoration(
              labelText: l10n.materialIntakeEnvelopeLabel,
              hintText: l10n.materialIntakeEnvelopeHint,
              border: const OutlineInputBorder(),
            ),
          ),
          CheckboxListTile(
            value: _includeTopicHubs,
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.materialIntakeTopicHubs),
            onChanged: _busy
                ? null
                : (bool? value) =>
                    setState(() => _includeTopicHubs = value ?? false),
          ),
          Row(
            children: <Widget>[
              FilledButton(
                onPressed: _busy ? null : _preview,
                child: Text(l10n.materialIntakePreview),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: _busy ? null : _clear,
                child: Text(l10n.materialIntakeClear),
              ),
            ],
          ),
          if (_pendingBatches.isNotEmpty) ...<Widget>[
            const SizedBox(height: 16),
            Text(
              l10n.materialIntakePendingTitle(_pendingBatches.length),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            _Note(text: l10n.materialIntakePendingHint),
            for (final batch in _pendingBatches)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.hourglass_empty, size: 18),
                title: Text(
                  l10n.materialIntakePendingBatch(
                    batch.unappliedCount,
                    batch.batchId,
                  ),
                ),
                subtitle: Text(batch.summaryText),
                trailing: TextButton(
                  onPressed: _busy ? null : () => _restore(batch),
                  child: Text(l10n.materialIntakeRestore),
                ),
              ),
          ],
          if (_error != null) ...<Widget>[
            const SizedBox(height: 12),
            _Problem(text: _error!),
          ],
          if (_outcome != null) ...<Widget>[
            const SizedBox(height: 12),
            _Success(
              text: l10n.materialIntakeApplied(
                _outcome!.created.length + _outcome!.createdEdges.length,
                _outcome!.existing.length + _outcome!.existingEdges.length,
                _outcome!.deferred.length,
                _outcome!.remaining,
              ),
            ),
          ],
          if (_batch != null) ...<Widget>[
            const SizedBox(height: 12),
            _Note(
              text: <String>[
                l10n.materialIntakeProposals(_proposals.length),
                if (_skipped.isNotEmpty)
                  l10n.materialIntakeSkipped(_skipped.length),
                // 都确认完了就不再念"待确认 0 条"：欠账还清这件事由成绩单说。
                if (_batch!.unappliedCount > 0)
                  l10n.materialIntakePending(_batch!.unappliedCount),
              ].join(' · '),
            ),
            if (_proposals.isEmpty) ...<Widget>[
              const SizedBox(height: 12),
              _Note(text: l10n.materialIntakeNothingToDo),
            ] else ...<Widget>[
              const SizedBox(height: 8),
              for (final proposal in _proposals)
                _ProposalTile(
                  proposal: proposal,
                  selected: _selected.contains(proposal.id),
                  onChanged: _busy
                      ? null
                      : (bool? value) => setState(() {
                            if (value ?? false) {
                              _selected.add(proposal.id);
                            } else {
                              _selected.remove(proposal.id);
                            }
                          }),
                ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: _busy || _selected.isEmpty ? null : _apply,
                child: Text(l10n.materialIntakeConfirm(_selected.length)),
              ),
            ],
            if (_skipped.isNotEmpty) ...<Widget>[
              const SizedBox(height: 16),
              Text(
                l10n.materialIntakeSkipped(_skipped.length),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              for (final skip in _skipped)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.remove_circle_outline, size: 18),
                  title: Text(skip.ref),
                  subtitle: Text(skip.reason),
                ),
            ],
          ],
        ],
      ),
    );
  }
}

/// 一条待确认提案：勾选、类型、出处、为什么。
class _ProposalTile extends StatelessWidget {
  const _ProposalTile({
    required this.proposal,
    required this.selected,
    required this.onChanged,
  });

  final MaterialIntakeProposal proposal;
  final bool selected;
  final ValueChanged<bool?>? onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isPoint = proposal.kind == MaterialIntakeKind.knowledgePoint;
    final evidence = proposal.evidence;
    final source = evidence.source?.trim();
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 12, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Checkbox(
              value: selected,
              onChanged: onChanged,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const SizedBox(height: 10),
                  Text(
                    proposal.title,
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    <String>[
                      isPoint
                          ? l10n.materialIntakeKindPoint
                          : l10n.materialIntakeKindConnection,
                      if (!isPoint) l10n.materialIntakeConnectionClue,
                      if (proposal.exists) l10n.materialIntakeExisting,
                    ].join(' · '),
                    style: theme.textTheme.labelSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.materialIntakeFrom(
                      (source == null || source.isEmpty)
                          ? l10n.materialIntakeNoSource
                          : source,
                      evidence.region,
                    ),
                    style: theme.textTheme.bodySmall,
                  ),
                  if (evidence.quote != null) ...<Widget>[
                    const SizedBox(height: 2),
                    Text(
                      l10n.materialIntakeQuote(evidence.quote!),
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(proposal.why, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text, style: Theme.of(context).textTheme.bodySmall);
  }
}

class _Problem extends StatelessWidget {
  const _Problem({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          text,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onErrorContainer,
          ),
        ),
      ),
    );
  }
}

class _Success extends StatelessWidget {
  const _Success({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          text,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSecondaryContainer,
          ),
        ),
      ),
    );
  }
}
