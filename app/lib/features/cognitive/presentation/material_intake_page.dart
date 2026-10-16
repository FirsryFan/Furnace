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
/// 入口有三个：**贴信封**（上面两步）、**从待确认清单恢复**、以及**选一张照片** ——
/// 后者走 `photo_transcribe_service.dart`：照片与【图清单】一起发给有视觉能力的模型，
/// 回话读成一份 `mindnet.run/1` 并自检（§2-C ③ 的"照片本身"）。它**只校验、不执行**，
/// 也一个字都不写库，所以与下面两张单子无关。
///
/// 页面上下两张单子用的是同一份批次读数（`unapplied_count`）：**还没点头的**在"待确认清单"
/// （关掉页面也还在，接着确认），**已经点头的**在"已经确认完的"（只读，回答"我上次到底建了什么"）。
/// 一批只会出现在其中一张上 —— 还留着一条落不了的连接就不叫确认完。
///
/// 纪律：确认前不写知识点；"待确认清单"落库（`applied_at` NULL），所以关掉页面不会丢。
///
/// 本页不做 AI 提取（那是模型侧的活，工具 `ingest_material` 已在），也不做卡片的
/// 呈现层（INGEST §4 的可选产物，本层不产出）。
library;

import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/material_intake_repository.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../domain/services/ingest/material_ingest.dart';
import '../../../domain/services/ingest/material_intake_plan.dart';
import '../../../domain/services/ingest/transcribe_run.dart';
import '../../../l10n/app_localizations.dart';
import '../../ai/application/ai_providers.dart';
import '../../ai/domain/vision_payload.dart';
import '../application/material_intake_reader.dart';
import '../application/photo_transcribe_service.dart';

/// "选一张照片"这一步：返回照片字节，用户取消就是 `null`。
///
/// 做成 provider 是为了**测试**：widget 测试里换成假的，既不弹系统对话框，
/// 也不碰真实文件系统（真实现只有 `pickPhotoBytes`）。
typedef PhotoPicker = Future<Uint8List?> Function();

final photoPickerProvider = Provider<PhotoPicker>((ref) => pickPhotoBytes);

/// 压图/重编码（`vision_payload.dart`）。做成 provider 是为了 **widget 测试**：
/// 那个假时钟下 `dart:ui` 的解码走不完，测试里换成不会真的解码的编码器。
final visionEncoderProvider = Provider<VisionImageEncoder>(
  (ref) => const VisionImageEncoder(),
);

/// 系统选图（`file_picker`）：只要图片扩展名，取第一张。
Future<Uint8List?> pickPhotoBytes() async {
  final picked = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: const <String>[
      'png',
      'jpg',
      'jpeg',
      'webp',
      'heic',
      'bmp',
    ],
  );
  if (picked.isEmpty) {
    return null;
  }
  return picked.first.readAsBytes();
}

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

  /// 已经确认完的批次（同一张单子的另一半：做过什么，看这里）。
  List<MaterialIntakeBatch> _doneBatches = const <MaterialIntakeBatch>[];

  MaterialApplyOutcome? _outcome;

  /// 上一次撤回的结果：删了什么、退回了多少条（撤回是写，成绩单要留下来）。
  MaterialUndoOutcome? _undoOutcome;

  /// 这批里哪几条连接现在落不了（提案 id → 缺哪一端的那句话）。
  ///
  /// 屏幕上每块一摆好就算一次（`_missingNow`），勾选框一变就重算：它是"库里现在的样子 ×
  /// 现在勾着的这些"的函数，不落库 —— 所以缺的那一端补进图里、或把勾去掉之后，这句话
  /// 会自己变得不该出现。
  MaterialIntakeMissingEndpoints _missing = const <String, String>{};

  /// 算这句话要看的两份库读数（屏幕上摆着的这批里，库那边现在有什么）。
  Set<String> _knownNodes = const <String>{};
  Set<String> _knownEdges = const <String>{};

  Set<String> _selected = <String>{};
  String? _error;
  bool _busy = false;
  bool _includeTopicHubs = false;

  @override
  void initState() {
    super.initState();
    _refreshBatches();
  }

  @override
  void dispose() {
    _envelopeController.dispose();
    super.dispose();
  }

  /// 重新读两张单子：还没点头的（待确认）与已经写下去的（已确认完）。
  ///
  /// 两张单子用的是同一份批次读数（`unapplied_count`），所以一批只会在其中一张上出现：
  /// 看提案/恢复/确认/清空之后都要刷，免得一批同时挂在两边。
  Future<void> _refreshBatches() async {
    final repository = ref.read(materialIntakeRepositoryProvider);
    final pending = await readPendingBatches(repository: repository);
    final done = await readAppliedBatches(repository: repository);
    if (!mounted) {
      return;
    }
    setState(() {
      _pendingBatches = pending;
      _doneBatches = done;
    });
  }

  /// 按"现在勾着的这些 + 库里现在有什么"算一遍：哪几条连接会落不了。
  ///
  /// 只看**勾着的**提案，是因为 `apply` 也只收到勾着的那些：勾掉一个知识点，连着的边
  /// 当场就该喊"缺这一端"，而不是等确认完之后才在成绩单上看到。
  MaterialIntakeMissingEndpoints _missingNow() => pendingMissingEndpointsOf(
        proposals: <MaterialIntakeProposal>[
          for (final proposal in _proposals)
            if (_selected.contains(proposal.id)) proposal,
        ],
        knownNodeIds: _knownNodes,
        knownEdgeIds: _knownEdges,
      );

  /// 看提案：推导一遍，并把这份提案登记成"待确认"（幂等）。
  Future<void> _preview() async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _error = null;
      _outcome = null;
      _undoOutcome = null;
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
      final done = await readAppliedBatches(repository: repository);
      final knownNodes = await repository.knownExternalNodeIds();
      final knownEdges = await repository.knownEdgeIds();
      if (!mounted) {
        return;
      }
      setState(() {
        _proposals = draft.plan.proposals;
        _skipped = draft.plan.skipped;
        _batch = batch;
        _pendingBatches = pending;
        _doneBatches = done;
        _knownNodes = knownNodes;
        _knownEdges = knownEdges;
        _selected = <String>{
          for (final proposal in draft.plan.proposals) proposal.id,
        };
        _missing = _missingNow();
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
      _undoOutcome = null;
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
      // 库里没有这一批（或它已经被写下去了）：别让一张过期的单子留在屏幕上。
      setState(() => _busy = false);
      await _refreshBatches();
      return;
    }
    final knownNodes = await repository.knownExternalNodeIds();
    final knownEdges = await repository.knownEdgeIds();
    if (!mounted) {
      return;
    }
    setState(() {
      _proposals = pending.proposals;
      _skipped = pending.batch.skipped;
      _batch = pending.batch;
      _knownNodes = knownNodes;
      _knownEdges = knownEdges;
      _selected = <String>{
        for (final proposal in pending.proposals) proposal.id,
      };
      _missing = _missingNow();
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
      _missing = const <String, String>{};
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
      final done = await readAppliedBatches(repository: repository);
      // 刚才写下去的知识点现在在库里了，所以"哪几条连接还落不了"要重算一遍：
      // 落下去的那些不再算缺端点，剩下的照旧。
      final knownNodes = await repository.knownExternalNodeIds();
      final knownEdges = await repository.knownEdgeIds();
      if (!mounted) {
        return;
      }
      setState(() {
        _outcome = outcome;
        _batch = fresh ?? _batch;
        _pendingBatches = pending;
        _doneBatches = done;
        _knownNodes = knownNodes;
        _knownEdges = knownEdges;
        _missing = _missingNow();
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

  /// 选一张照片：发出去、读回一份 `run/1`、把自检结果原样摆出来。
  ///
  /// **只读**：不写库、不执行请求 —— 照片这条路上到目前为止只有"读"，执行是另一件事。
  /// 图清单与"图里已有的节点/边 id"都从库里现读（不许模型发明 id，`transcribe_run.dart`）。
  /// 读失败不清空已经贴好的信封：两件事互不相干。
  Future<void> _readPhoto() async {
    final l10n = AppLocalizations.of(context);
    final graph = ref.read(knowledgeEdgeRepositoryProvider);
    final adapter = ref.read(modelAdapterProvider);
    final pick = ref.read(photoPickerProvider);
    Uint8List? bytes;
    try {
      bytes = await pick();
    } catch (error) {
      _notePhotoProblem(l10n.materialIntakePhotoPickFailed('$error'));
      return;
    }
    if (bytes == null || !mounted) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      // 清单与 id 白名单都来自库：模型看到的 id 是这一份，写回来的也只能是这一份。
      final points = await graph.graphPoints();
      final edges = await graph.all();
      final result = await transcribePhoto(
        adapter: adapter,
        image: bytes,
        encoder: ref.read(visionEncoderProvider),
        inventory: <TranscribeInventoryEntry>[
          for (final point in points) (id: point.externalId, name: point.title),
        ],
        existingNodeIds: <String>{for (final point in points) point.externalId},
        existingEdgeIds: <String>{for (final edge in edges) edge.id},
      );
      if (!mounted) {
        return;
      }
      setState(() => _busy = false);
      await showDialog<void>(
        context: context,
        builder: (_) => _PhotoReportDialog(result: result),
      );
    } catch (error) {
      _notePhotoProblem(l10n.materialIntakePhotoReadFailed('$error'));
    }
  }

  /// 照片这条路出问题只改这一行提示（不动提案、不动批次）。
  void _notePhotoProblem(String message) {
    if (!mounted) {
      return;
    }
    setState(() {
      _busy = false;
      _error = message;
    });
  }

  void _clear() {
    _envelopeController.clear();
    setState(() {
      _proposals = const <MaterialIntakeProposal>[];
      _skipped = const <MaterialIntakeSkip>[];
      _batch = null;
      _outcome = null;
      _undoOutcome = null;
      _selected = <String>{};
      _error = null;
    });
  }

  /// 看这批当初确认了什么：读**已经写下去**的提案（不是打算建的那份）。
  ///
  /// 只读，不给勾选框：这几条已经在库里了，要改得去它们落地的地方（知识点在管理页，
  /// 线索边在知识点详情里）—— 这里再造一个"改"的入口就是第三处写者。**撤回**不是第三处
  /// 写者：它走的就是确认那一层的 `undoBatch`（同一处写者、同一份判断），所以这个入口
  /// 开在这儿而不是知识点管理页。
  Future<void> _openApplied(MaterialIntakeBatch batch) async {
    final l10n = AppLocalizations.of(context);
    final applied = await readAppliedBatch(
      repository: ref.read(materialIntakeRepositoryProvider),
      batchId: batch.batchId,
    );
    if (!mounted) {
      return;
    }
    if (applied == null) {
      await _refreshBatches();
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.materialIntakeDoneDialogTitle(batch.batchId)),
        content: SizedBox(
          width: 480,
          child: applied.proposals.isEmpty
              ? Text(l10n.materialIntakeNothingToDo)
              : ListView(
                  shrinkWrap: true,
                  children: <Widget>[
                    for (final applied in applied.proposals)
                      _AppliedTile(applied: applied),
                    const SizedBox(height: 8),
                    _Note(text: l10n.materialIntakeDoneNote),
                  ],
                ),
        ),
        actions: <Widget>[
          if (applied.proposals.isNotEmpty)
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                _undo(batch);
              },
              child: Text(l10n.materialIntakeUndo),
            ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(l10n.commonClose),
          ),
        ],
      ),
    );
  }

  /// 撤回这一批：先问一句，再让仓储层动手。
  ///
  /// 撤回是**删**，所以必须先问；撤不了（有卡片/标签/别的边）时一条也不删，
  /// 理由逐条照说 —— 界面不替用户"猜"哪条能撤。
  Future<void> _undo(MaterialIntakeBatch batch) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.materialIntakeUndoTitle),
        content: SizedBox(
          width: 420,
          child: Text(l10n.materialIntakeUndoBody),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l10n.materialIntakeUndoConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _outcome = null;
      _undoOutcome = null;
    });
    final repository = ref.read(materialIntakeRepositoryProvider);
    late final MaterialUndoOutcome outcome;
    try {
      outcome = await repository.undoBatch(batch.batchId);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _busy = false);
      _fail(l10n.materialIntakeBadEnvelope('$error'));
      return;
    }
    // 撤掉的那一批可能正是屏幕上开着的那批：读数要重新取，提案回到待确认。
    final fresh = _batch?.batchId == batch.batchId
        ? await readPendingBatch(repository: repository, batchId: batch.batchId)
        : null;
    final pending = await readPendingBatches(repository: repository);
    final done = await readAppliedBatches(repository: repository);
    // 撤回删掉了行，所以"库里现在有什么"要重新取（不然清单上的说法会停在撤回之前）。
    final knownNodes = await repository.knownExternalNodeIds();
    final knownEdges = await repository.knownEdgeIds();
    if (!mounted) {
      return;
    }
    if (!outcome.undone) {
      setState(() => _busy = false);
      await _showUndoBlocked(outcome);
      return;
    }
    setState(() {
      _busy = false;
      _undoOutcome = outcome;
      _pendingBatches = pending;
      _doneBatches = done;
      _knownNodes = knownNodes;
      _knownEdges = knownEdges;
      if (fresh != null) {
        _proposals = fresh.proposals;
        _skipped = fresh.batch.skipped;
        _batch = fresh.batch;
        _selected = <String>{
          for (final proposal in fresh.proposals) proposal.id,
        };
      }
      _missing = _missingNow();
    });
  }

  /// 撤不了：整批没动，把每条原因照原样摆出来（不给"那就撤一半吧"的选项）。
  Future<void> _showUndoBlocked(MaterialUndoOutcome outcome) async {
    final l10n = AppLocalizations.of(context);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.materialIntakeUndoBlockedTitle),
        content: SizedBox(
          width: 480,
          child: ListView(
            shrinkWrap: true,
            children: <Widget>[
              _Note(text: l10n.materialIntakeUndoBlockedNote),
              for (final block in outcome.blocked)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.block, size: 18),
                  title: Text(l10n.materialIntakeUndoBlockedRow(
                    block.title,
                    block.reason,
                  )),
                ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(l10n.commonClose),
          ),
        ],
      ),
    );
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
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              OutlinedButton.icon(
                onPressed: _busy ? null : _readPhoto,
                icon: const Icon(Icons.photo_camera_outlined, size: 18),
                label: Text(l10n.materialIntakePickPhoto),
              ),
            ],
          ),
          _Note(text: l10n.materialIntakePhotoHint),
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
          if (_doneBatches.isNotEmpty) ...<Widget>[
            const SizedBox(height: 16),
            Text(
              l10n.materialIntakeDoneTitle(_doneBatches.length),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            _Note(text: l10n.materialIntakeDoneHint),
            for (final batch in _doneBatches)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.check_circle_outline, size: 18),
                title: Text(
                  l10n.materialIntakeDoneBatch(
                    batch.appliedCount,
                    batch.batchId,
                  ),
                ),
                subtitle: Text(batch.summaryText),
                trailing: TextButton(
                  onPressed: _busy ? null : () => _openApplied(batch),
                  child: Text(l10n.materialIntakeDoneOpen),
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
          if (_undoOutcome != null) ...<Widget>[
            const SizedBox(height: 12),
            _Success(
              text: _undoOutcome!.removedPoints.isEmpty &&
                      _undoOutcome!.removedEdges.isEmpty
                  ? l10n.materialIntakeUndoneNothing(_undoOutcome!.restored)
                  : l10n.materialIntakeUndone(
                      _undoOutcome!.removedPoints.length,
                      _undoOutcome!.removedEdges.length,
                      _undoOutcome!.restored,
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
                  missing: _missing[proposal.id],
                  selected: _selected.contains(proposal.id),
                  onChanged: _busy
                      ? null
                      : (bool? value) => setState(() {
                            if (value ?? false) {
                              _selected.add(proposal.id);
                            } else {
                              _selected.remove(proposal.id);
                            }
                            // 勾选变了，"哪几条连接落不了"就变了（勾掉一端，边当场喊缺）。
                            _missing = _missingNow();
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
    this.missing,
    required this.selected,
    required this.onChanged,
  });

  final MaterialIntakeProposal proposal;

  /// 这条连接现在落不了的话，缺哪一端（能落 = null）。
  final String? missing;

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
                  // 还没点头就先说清"这条落不了、缺的是哪一端"：等确认之后再知道，
                  // 用户已经白点了一次（说法与确认时的成绩单共用一处）。
                  if (missing != null) ...<Widget>[
                    const SizedBox(height: 4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Icon(
                          Icons.link_off,
                          size: 14,
                          color: theme.colorScheme.error,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            l10n.materialIntakeCantLand(missing!),
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: theme.colorScheme.error),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 一条**已经确认**的提案（历史只读）：没有勾选框 —— 它已经写进库里了。
///
/// 每行还带一句"这次新建的 / 本来就有的（没重复建）"：成绩单只活在那一次调用里，
/// 所以这句话是确认时落在提案行上的（`already_existed`，轮次七十五）。
class _AppliedTile extends StatelessWidget {
  const _AppliedTile({required this.applied});

  final MaterialAppliedProposal applied;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final proposal = applied.proposal;
    final isPoint = proposal.kind == MaterialIntakeKind.knowledgePoint;
    final evidence = proposal.evidence;
    final source = evidence.source?.trim();
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        isPoint ? Icons.school_outlined : Icons.hub_outlined,
        size: 18,
      ),
      title: Text(proposal.title),
      subtitle: Text(
        <String>[
          isPoint
              ? l10n.materialIntakeKindPoint
              : l10n.materialIntakeKindConnection,
          if (!isPoint) l10n.materialIntakeConnectionClue,
          if (applied.alreadyExisted) l10n.materialIntakeExisting,
          l10n.materialIntakeFrom(
            (source == null || source.isEmpty)
                ? l10n.materialIntakeNoSource
                : source,
            evidence.region,
          ),
        ].join(' · '),
        style: theme.textTheme.bodySmall,
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

/// 照片读出来的东西：自检结果 + 会做什么 + 建议 + 模型原话。
///
/// 只读 —— 这里没有"执行"按钮：照片这条路目前只回答"读成了什么"，
/// 要执行得先把这份请求拿去走 `run/1`（那是下一件事）。
class _PhotoReportDialog extends StatelessWidget {
  const _PhotoReportDialog({required this.result});

  final PhotoTranscribeResult result;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final report = switch (result) {
      PhotoTranscribeReport() => result as PhotoTranscribeReport,
      _ => null,
    };
    final failure = switch (result) {
      PhotoTranscribeFailure() => result as PhotoTranscribeFailure,
      _ => null,
    };
    return AlertDialog(
      title: Text(l10n.materialPhotoReportTitle),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (report != null) ...<Widget>[
                Text(
                  report.report.ok
                      ? l10n.materialPhotoReportValid
                      : l10n.materialPhotoReportInvalid,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: report.report.ok
                        ? theme.colorScheme.primary
                        : theme.colorScheme.error,
                  ),
                ),
                const SizedBox(height: 4),
                _Note(
                  text: <String>[
                    l10n.materialPhotoReportSize(report.width, report.height),
                    l10n.materialPhotoReportCounts(
                      report.report.actionCount,
                      report.report.evidenceCount,
                    ),
                  ].join(' · '),
                ),
                if (report.report.errors.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 12),
                  Text(
                    l10n.materialPhotoReportErrors,
                    style: theme.textTheme.titleSmall,
                  ),
                  for (final error in report.report.errors)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.error_outline, size: 18),
                      title: Text(error),
                    ),
                ],
                if (report.report.previews.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 12),
                  Text(
                    l10n.materialPhotoReportPreviews,
                    style: theme.textTheme.titleSmall,
                  ),
                  for (final preview in report.report.previews)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.play_arrow_outlined, size: 18),
                      title: Text(preview),
                    ),
                ],
                if (report.report.warnings.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 12),
                  Text(
                    l10n.materialPhotoReportWarnings,
                    style: theme.textTheme.titleSmall,
                  ),
                  for (final warning in report.report.warnings)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.info_outline, size: 18),
                      title: Text(warning),
                    ),
                ],
              ],
              if (failure != null) ...<Widget>[
                Text(
                  l10n.materialPhotoReportFailed,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
                const SizedBox(height: 4),
                _Problem(text: failure.message),
              ],
              const SizedBox(height: 12),
              Text(
                l10n.materialPhotoReportRaw,
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              SelectableText(result is PhotoTranscribeReport
                  ? (result as PhotoTranscribeReport).rawText
                  : ((result as PhotoTranscribeFailure).rawText ??
                      l10n.materialPhotoReportNoRaw)),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonClose),
        ),
      ],
    );
  }
}
