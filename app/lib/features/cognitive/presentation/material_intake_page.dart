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
/// 也一个字都不写库，所以与下面两张单子无关；报告里那句「试跑一遍」是只读演练
/// （`run_rehearsal.dart`）：把这份请求真的喂进引擎、看它走到哪一步，同样不写库。
/// 报告里还有一句「改一改再跑」：把这一份请求带进下面那张**可编辑**的对话框
/// （与"贴一份 `run/1`"共用同一张），改完就照改的那样重新校验、重新试跑 ——
/// 照片读回来的那一份不该是只能看不能碰的死物。
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

import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/database/app_database_provider.dart';
import '../../../data/repositories/material_intake_repository.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../domain/services/cognitive/cognitive_model.dart';
import '../../../domain/services/ingest/material_ingest.dart';
import '../../../domain/services/ingest/material_intake_plan.dart';
import '../../../domain/services/ingest/transcribe_run.dart';
import '../../../l10n/app_localizations.dart';
import '../../ai/application/ai_providers.dart';
import '../../ai/domain/vision_payload.dart';
import '../application/material_intake_reader.dart';
import '../application/photo_transcribe_service.dart';
import '../application/run_intake.dart';
import '../application/run_rehearsal.dart';

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

/// 把一份 `run/1` **试跑一遍**（`rehearseRun`：只读演练，一个字都不写库）。
typedef RunRehearsalRunner = Future<RunRehearsal> Function(
  MaterialRunRequest request,
);

/// 试跑这件事的做法本身。做成 provider 有两个理由：测试里塞一份假读数就不必
/// 造一整个知识图；"用哪个模型、哪个时钟"也收在一处，不与页面其他部分纠缠。
final runRehearsalRunnerProvider = Provider<RunRehearsalRunner>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final model = ref.watch(cognitiveModelProvider);
  return (MaterialRunRequest request) =>
      rehearseRun(request: request, db: db, model: model);
});

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

  /// 屏幕上这批被撤回过几次（撤回流水，`material_intake_undo_logs`）。
  ///
  /// 撤回把行删掉了，屏幕上只看得到"这批又回到待确认"——流水是唯一还剩的痕迹。
  List<MaterialUndoLog> _undoLogs = const <MaterialUndoLog>[];

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
      final undoLogs = await repository.undoLogs(batch.batchId);
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
        _undoLogs = undoLogs;
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
    final undoLogs = await repository.undoLogs(batch.batchId);
    if (!mounted) {
      return;
    }
    setState(() {
      _proposals = pending.proposals;
      _skipped = pending.batch.skipped;
      _batch = pending.batch;
      _knownNodes = knownNodes;
      _knownEdges = knownEdges;
      _undoLogs = undoLogs;
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
      _undoLogs = const <MaterialUndoLog>[];
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
  /// **只读**：读这一步不写库、不执行请求 —— 照片这条路上到目前为止只有"读"。
  /// 报告里可以按「试跑一遍」，那是 `rehearseRun` 的只读演练（同样一个字都不写库），
  /// 不是执行：落库执行是另一件事。
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
      _noteIntakeProblem(l10n.materialIntakePhotoPickFailed('$error'));
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
      // 报告能反出来一个字符串：那是"改一改再跑" —— 用户在这份请求上按一下就带着
      // 原文进到可编辑的那张对话框（两条路共用同一张，所以不用再写一遍编辑器）。
      final editedText = await showDialog<String>(
        context: context,
        builder: (_) => _PhotoReportDialog(
          result: result,
          onAnother: _readPhoto,
          onRehearse: ref.read(runRehearsalRunnerProvider),
          onHandOver: ref.read(runIntakeRecorderProvider),
        ),
      );
      if (editedText != null && mounted) {
        await _openRunDialog(initialText: editedText);
      }
    } catch (error) {
      _noteIntakeProblem(l10n.materialIntakePhotoReadFailed('$error'));
    }
  }

  /// 贴一份 `run/1`：先校验，再（可选）试跑一遍 —— 全在同一张对话框里。
  ///
  /// 照片那条路要一张图和会看图的模型；这一条只要剪贴板：请求可以来自任何地方
  /// （别处的模型、AI 工具 `check_transcribe_run`、手写），读回来的是同一套自检
  /// （`reviewTranscribedRun`）和同一个只读演练（`rehearseRun`）。**不写库**。
  /// 图清单与"图里已有的节点/边 id"照照片那条路从库里现读（不许模型发明 id）。
  Future<void> _pasteRun() => _openRunDialog();

  /// 打开那张可编辑的 `run/1` 对话框：剪贴板那条路空着进来，照片报告那条路带着原文进来。
  ///
  /// 两条路合到一个方法里，是因为"从哪来"只该影响框里一开始有什么字。
  Future<void> _openRunDialog({String? initialText}) async {
    final l10n = AppLocalizations.of(context);
    final graph = ref.read(knowledgeEdgeRepositoryProvider);
    setState(() {
      _busy = true;
      _error = null;
    });
    final Set<String> existingNodeIds;
    final Set<String> existingEdgeIds;
    try {
      final points = await graph.graphPoints();
      final edges = await graph.all();
      existingNodeIds = <String>{for (final point in points) point.externalId};
      existingEdgeIds = <String>{for (final edge in edges) edge.id};
    } catch (error) {
      _noteIntakeProblem(l10n.materialIntakeRunGraphFailed('$error'));
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() => _busy = false);
    await showDialog<void>(
      context: context,
      builder: (_) => _RunRequestDialog(
        existingNodeIds: existingNodeIds,
        existingEdgeIds: existingEdgeIds,
        onRehearse: ref.read(runRehearsalRunnerProvider),
        onHandOver: ref.read(runIntakeRecorderProvider),
        initialText: initialText,
      ),
    );
  }

  /// 两条只读入口（照片 / 贴 `run/1`）出问题都只改这一行提示（不动提案、不动批次）。
  void _noteIntakeProblem(String message) {
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
      _undoLogs = const <MaterialUndoLog>[];
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
    // 这一批的撤回流水：刚撤的这一笔也已经在里面了。
    final undoLogs = await repository.undoLogs(batch.batchId);
    if (!mounted) {
      return;
    }
    if (!outcome.undone) {
      // 没撤成也是"点过一次撤回"：流水跟着更新，只是库里的行一个字没动。
      setState(() {
        _busy = false;
        _undoLogs = undoLogs;
      });
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
      _undoLogs = undoLogs;
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

  /// 点开那一行：这一批每一次点撤回都在这儿 —— 撤成了的说清删了哪几行，没撤成的照原样说理由。
  ///
  /// 只读流水（`material_intake_undo_logs`），不回放也不改库：撤回删掉的行不会因为看得见就
  /// 回来（想回来得再确认一次）。
  Future<void> _showUndoLogs() async {
    final l10n = AppLocalizations.of(context);
    final logs = _undoLogs;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.materialIntakeUndoLogTitle),
        content: SizedBox(
          width: 520,
          child: ListView(
            shrinkWrap: true,
            children: <Widget>[
              _Note(text: l10n.materialIntakeUndoLogNote),
              for (final log in logs) ...<Widget>[
                const SizedBox(height: 12),
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    log.undone ? Icons.undo : Icons.block,
                    size: 18,
                  ),
                  title: Text(
                    '${_stampOf(log.requestedAt)} · '
                    '${log.undone ? l10n.materialIntakeUndoLogDone : l10n.materialIntakeUndoLogNotDone}',
                  ),
                ),
                if (log.undone) ...<Widget>[
                  _Note(
                    text: log.removedPoints.isEmpty && log.removedEdges.isEmpty
                        ? l10n.materialIntakeUndoneNothing(log.restored)
                        : l10n.materialIntakeUndone(
                            log.removedPoints.length,
                            log.removedEdges.length,
                            log.restored,
                          ),
                  ),
                  // "那次撤掉了什么"要看得见：原件都是库里当时那一行的原话。
                  for (final point in log.removedPoints)
                    _Note(text: '· ${point.title}'),
                  for (final edge in log.removedEdges)
                    _Note(text: '· ${edge.fromId} → ${edge.toId}'),
                ] else
                  _Note(
                    text: l10n.materialIntakeUndoLogBlocked(
                      log.blockedReason ?? '',
                      log.blockedCount,
                    ),
                  ),
              ],
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

  /// 流水的时刻：本地时区、`MM-dd HH:mm`（够看清"哪一次"，不引新依赖）。
  static String _stampOf(int epochMs) {
    final moment = DateTime.fromMillisecondsSinceEpoch(epochMs);
    String two(int value) => value < 10 ? '0$value' : '$value';
    return '${two(moment.month)}-${two(moment.day)} '
        '${two(moment.hour)}:${two(moment.minute)}';
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
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _busy ? null : _pasteRun,
                icon: const Icon(Icons.content_paste_go_outlined, size: 18),
                label: Text(l10n.materialIntakePasteRun),
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
            // 撤回把行删了，屏幕上只剩"又回到待确认"这一步 —— 流水是唯一的痕迹：
            // 撤过几次说清楚，"怎么又冒出来了"就不是谜。点一下看得见那几次各撤了什么。
            if (_undoLogs.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              InkWell(
                onTap: _showUndoLogs,
                child: _Note(
                  text: l10n.materialIntakeUndoLogLine(_undoLogs.length),
                ),
              ),
            ],
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
/// 但可以**原地再来一张**（[onAnother]）：读不成、或者想换一张重读，都只按一下 ——
/// 不用先关掉这一个对话框、再出去找那个按钮。
class _PhotoReportDialog extends StatefulWidget {
  const _PhotoReportDialog({
    required this.result,
    this.onAnother,
    this.onRehearse,
    this.onHandOver,
  });

  final PhotoTranscribeResult result;

  /// 再来一张：关掉本对话框后重新选照片、重新读一遍。为空就没有这个按钮
  /// （对话框只当纯报告用）。
  final VoidCallback? onAnother;

  /// 试跑一遍：把这份请求喂进引擎走一遍（`rehearseRun`，只读、不写库）。
  /// 为空就没有这个按钮。
  final RunRehearsalRunner? onRehearse;

  /// 演练完那一下"把要新建的东西交给人确认"（只落待确认提案）。为空就没有。
  final RunIntakeRecorder? onHandOver;

  @override
  State<_PhotoReportDialog> createState() => _PhotoReportDialogState();
}

class _PhotoReportDialogState extends State<_PhotoReportDialog> {
  bool _rehearsing = false;
  RunRehearsal? _rehearsal;
  String? _rehearsalProblem;

  /// 按一下「试跑一遍」：跑完把读数就摆在这个对话框里（不另开一个）。
  ///
  /// 抛了就说人话、把原话留下：演练失败不该把这个报告一起带走 ——
  /// "这份请求合不合法"和"引擎跑得完跑不完"是两件事。
  Future<void> _rehearse() async {
    final runner = widget.onRehearse;
    final request = switch (widget.result) {
      PhotoTranscribeReport(:final request) => request,
      _ => null,
    };
    if (runner == null || request == null || _rehearsing) {
      return;
    }
    setState(() {
      _rehearsing = true;
      _rehearsalProblem = null;
    });
    try {
      final rehearsal = await runner(request);
      if (!mounted) {
        return;
      }
      setState(() {
        _rehearsal = rehearsal;
        _rehearsing = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _rehearsalProblem = '$error';
        _rehearsing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // 页面其余部分照旧按 `result` / `onAnother` 读：这里只把三处状态接上。
    final result = widget.result;
    final onAnother = widget.onAnother;
    final onRehearse = widget.onRehearse;
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final report = switch (result) {
      PhotoTranscribeReport() => result,
      _ => null,
    };
    final failure = switch (result) {
      PhotoTranscribeFailure() => result,
      _ => null,
    };
    // "没配模型"这一种再来一张没有意义（按一次还是同一句话）：不摆这个按钮，
    // 免得用户按了又看到同一句 —— 那句话本身已经说了该去哪儿配。
    final canAnother = failure == null ||
        failure.problem != PhotoTranscribeProblem.notConfigured;
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
                if (_rehearsing) ...<Widget>[
                  const SizedBox(height: 12),
                  Row(
                    children: <Widget>[
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 8),
                      Text(l10n.materialPhotoReportRehearseBusy),
                    ],
                  ),
                ],
                if (_rehearsal != null)
                  _RehearsalReading(
                    rehearsal: _rehearsal!,
                    onHandOver: widget.onHandOver,
                  ),
                if (_rehearsalProblem != null) ...<Widget>[
                  const SizedBox(height: 12),
                  Text(
                    l10n.materialPhotoReportRehearseFailed,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                  const SizedBox(height: 4),
                  _Problem(text: _rehearsalProblem!),
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
              SelectableText(switch (result) {
                PhotoTranscribeReport() => result.rawText,
                PhotoTranscribeFailure() =>
                  result.rawText ?? l10n.materialPhotoReportNoRaw,
              }),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        if (report != null)
          TextButton.icon(
            onPressed: () =>
                Navigator.of(context).pop(jsonEncode(report.request.toJson())),
            icon: const Icon(Icons.edit_note_outlined, size: 18),
            label: Text(l10n.materialPhotoReportEditAndRun),
          ),
        if (onRehearse != null && report != null && report.report.ok)
          TextButton.icon(
            onPressed: _rehearsing ? null : _rehearse,
            icon: const Icon(Icons.science_outlined, size: 18),
            label: Text(l10n.materialPhotoReportRehearse),
          ),
        if (onAnother != null && canAnother)
          TextButton.icon(
            onPressed: () {
              Navigator.of(context).pop();
              onAnother.call();
            },
            icon: Icon(
              failure != null ? Icons.refresh : Icons.photo_camera_outlined,
              size: 18,
            ),
            label: Text(
              failure != null
                  ? l10n.materialPhotoReportRetry
                  : l10n.materialPhotoReportPickAnother,
            ),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonClose),
        ),
      ],
    );
  }
}

/// 贴一份 `run/1`：校验 + 试跑，和照片那条路同一套自检与同一个演练。
///
/// 两条路唯一的差别是请求从哪来：那边是照片 → 模型读回来，这边是剪贴板。
/// **只读**：这里没有"执行"按钮，试跑走的是 `rehearseRun`（一个字都不写库）。
class _RunRequestDialog extends StatefulWidget {
  const _RunRequestDialog({
    required this.existingNodeIds,
    required this.existingEdgeIds,
    this.onRehearse,
    this.onHandOver,
    this.initialText,
  });

  /// 图里已有的节点/边 id：自检拿它判断"这条动作说的 id 库里有没有"。
  final Set<String> existingNodeIds;
  final Set<String> existingEdgeIds;

  /// 试跑一遍（`rehearseRun`，只读、不写库）。为空就没有这个按钮。
  final RunRehearsalRunner? onRehearse;

  /// 演练完那一下"把要新建的东西交给人确认"（只落待确认提案）。为空就没有。
  final RunIntakeRecorder? onHandOver;

  /// 一进来框里就有的字：照片报告里「改一改再跑」把那一份请求原样带进来
  /// （剪贴板那条路留空）。带字进来就顺手校验一遍 —— 用户要看见的是"现在这份"，
  /// 不是一张空白框。
  final String? initialText;

  @override
  State<_RunRequestDialog> createState() => _RunRequestDialogState();
}

class _RunRequestDialogState extends State<_RunRequestDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialText ?? '');
  MaterialRunRequest? _request;
  TranscribeReport? _report;
  String? _problem;
  bool _rehearsing = false;
  RunRehearsal? _rehearsal;
  String? _rehearsalProblem;

  @override
  void initState() {
    super.initState();
    if (widget.initialText != null) {
      // 首帧之后再校验：`_check` 会 setState，而 `build` 期间不能改状态。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _check();
        }
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 校验这份请求：读不成（`FormatException`）就说解码器那句人话；
  /// 读得成就把自检结果摆出来（包括不合法的那一份 —— 错在哪本身是信息）。
  void _check() {
    try {
      final request = decodeRunRequest(extractJsonObject(_controller.text));
      final report = reviewTranscribedRun(
        request,
        existingNodeIds: widget.existingNodeIds,
        existingEdgeIds: widget.existingEdgeIds,
      );
      setState(() {
        _request = request;
        _report = report;
        _problem = null;
        _rehearsal = null;
        _rehearsalProblem = null;
      });
    } on FormatException catch (error) {
      setState(() {
        _request = null;
        _report = null;
        _problem = error.message;
        _rehearsal = null;
        _rehearsalProblem = null;
      });
    }
  }

  /// 按一下「试跑一遍」：跑完把读数就摆在这张对话框里。
  ///
  /// 抛了就说人话、把原话留下：演练失败不该把这份请求的校验结果一起带走 ——
  /// "这份请求合不合法"和"引擎跑得完跑不完"是两件事。
  Future<void> _rehearse() async {
    final runner = widget.onRehearse;
    final request = _request;
    if (runner == null || request == null || _rehearsing) {
      return;
    }
    setState(() {
      _rehearsing = true;
      _rehearsalProblem = null;
    });
    try {
      final rehearsal = await runner(request);
      if (!mounted) {
        return;
      }
      setState(() {
        _rehearsal = rehearsal;
        _rehearsing = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _rehearsalProblem = '$error';
        _rehearsing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final report = _report;
    return AlertDialog(
      title: Text(
        widget.initialText == null
            ? l10n.materialIntakeRunDialogTitle
            : l10n.materialIntakeRunDialogTitleEdited,
      ),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              TextField(
                controller: _controller,
                minLines: 4,
                maxLines: 10,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                decoration: InputDecoration(
                  labelText: l10n.materialIntakeRunHint,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              _Note(text: l10n.materialIntakeRunNote),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton(
                  onPressed: _rehearsing ? null : _check,
                  child: Text(l10n.materialIntakeRunCheck),
                ),
              ),
              if (_problem != null) ...<Widget>[
                const SizedBox(height: 12),
                _Problem(text: _problem!),
              ],
              if (report != null) ...<Widget>[
                const SizedBox(height: 12),
                Text(
                  report.ok
                      ? l10n.materialPhotoReportValid
                      : l10n.materialPhotoReportInvalid,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: report.ok
                        ? theme.colorScheme.primary
                        : theme.colorScheme.error,
                  ),
                ),
                const SizedBox(height: 4),
                _Note(
                  text: l10n.materialPhotoReportCounts(
                    report.actionCount,
                    report.evidenceCount,
                  ),
                ),
                if (report.errors.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 12),
                  Text(
                    l10n.materialPhotoReportErrors,
                    style: theme.textTheme.titleSmall,
                  ),
                  for (final error in report.errors)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.error_outline, size: 18),
                      title: Text(error),
                    ),
                ],
                if (report.previews.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 12),
                  Text(
                    l10n.materialPhotoReportPreviews,
                    style: theme.textTheme.titleSmall,
                  ),
                  for (final preview in report.previews)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.play_arrow_outlined, size: 18),
                      title: Text(preview),
                    ),
                ],
                if (report.warnings.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 12),
                  Text(
                    l10n.materialPhotoReportWarnings,
                    style: theme.textTheme.titleSmall,
                  ),
                  for (final warning in report.warnings)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.info_outline, size: 18),
                      title: Text(warning),
                    ),
                ],
                if (_rehearsing) ...<Widget>[
                  const SizedBox(height: 12),
                  Row(
                    children: <Widget>[
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 8),
                      Text(l10n.materialPhotoReportRehearseBusy),
                    ],
                  ),
                ],
                if (_rehearsal != null)
                  _RehearsalReading(
                    rehearsal: _rehearsal!,
                    onHandOver: widget.onHandOver,
                  ),
                if (_rehearsalProblem != null) ...<Widget>[
                  const SizedBox(height: 12),
                  Text(
                    l10n.materialPhotoReportRehearseFailed,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                  const SizedBox(height: 4),
                  _Problem(text: _rehearsalProblem!),
                ],
              ],
            ],
          ),
        ),
      ),
      actions: <Widget>[
        if (widget.onRehearse != null && report != null && report.ok)
          TextButton.icon(
            onPressed: _rehearsing ? null : _rehearse,
            icon: const Icon(Icons.science_outlined, size: 18),
            label: Text(l10n.materialPhotoReportRehearse),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonClose),
        ),
      ],
    );
  }
}

/// 演练读数：这份请求真的跑起来之后，到底走到了哪一步。
/// 一条动作一行 —— 引擎对每条动作的原话（`RunActionTrace.text`）比我在这里
/// 编的转述可信：它说的是"这一条实际做了什么/为什么停在这"。没有增量的条目
/// 也照摆（"跑过但什么都没改"本身是信息）。
class _RehearsalReading extends StatefulWidget {
  const _RehearsalReading({required this.rehearsal, this.onHandOver});

  final RunRehearsal rehearsal;

  /// 「把要新建的东西交给人确认」那一下（轮次九十一）：只落待确认提案。
  /// 不给缝（`null`）就不摆这个按钮 —— 和"试跑"一样，能注入才好测。
  final RunIntakeRecorder? onHandOver;

  @override
  State<_RehearsalReading> createState() => _RehearsalReadingState();
}

class _RehearsalReadingState extends State<_RehearsalReading> {
  bool _handingOver = false;
  MaterialIntakeBatch? _handedOver;
  String? _handOverProblem;

  /// 按一下「交给人确认」：把这一跑要新建的东西落成待确认提案。
  ///
  /// 落的只有两张清单表 —— `knowledge_points` / `knowledge_edges` 一行不动，
  /// 那是清单页上"确认"那一步的事。失败了就把人话摆在这里，演练读数留着。
  Future<void> _handOver() async {
    final recorder = widget.onHandOver;
    if (recorder == null || _handingOver) {
      return;
    }
    setState(() {
      _handingOver = true;
      _handOverProblem = null;
    });
    try {
      final batch = await recorder(widget.rehearsal.report);
      if (!mounted) {
        return;
      }
      setState(() {
        _handedOver = batch;
        _handingOver = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _handOverProblem = '$error';
        _handingOver = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final traces = widget.rehearsal.report.traces;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SizedBox(height: 12),
        Text(
          l10n.materialPhotoReportRehearseHeader,
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 4),
        Text(widget.rehearsal.text),
        const SizedBox(height: 4),
        _Note(text: l10n.materialPhotoReportRehearseNote),
        if (traces.isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            l10n.materialPhotoReportRehearseTrails,
            style: theme.textTheme.labelLarge,
          ),
          for (final trace in traces)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                trace.ok ? Icons.check_circle_outline : Icons.error_outline,
                size: 18,
                color: trace.ok ? null : theme.colorScheme.error,
              ),
              title: Text(trace.text),
            ),
        ],
        if (widget.rehearsal.nodesWithoutMs.isNotEmpty)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.help_outline, size: 18),
            title: Text(
              l10n.materialPhotoReportRehearseNoMs(
                widget.rehearsal.nodesWithoutMs.join('、'),
              ),
            ),
          ),
        if (widget.rehearsal.unknownNodeIds.isNotEmpty)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.report_gmailerrorred_outlined, size: 18),
            title: Text(
              l10n.materialPhotoReportRehearseUnknown(
                widget.rehearsal.unknownNodeIds.join('、'),
              ),
            ),
          ),
        if (widget.onHandOver != null) ...<Widget>[
          const SizedBox(height: 12),
          _Note(text: l10n.materialPhotoReportHandOverNote),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonalIcon(
              onPressed: _handingOver ? null : _handOver,
              icon: const Icon(
                Icons.playlist_add_check_circle_outlined,
                size: 18,
              ),
              label: Text(
                _handingOver
                    ? l10n.materialPhotoReportHandOverBusy
                    : l10n.materialPhotoReportHandOver,
              ),
            ),
          ),
          if (_handedOver != null)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.check_circle_outline, size: 18),
              title: Text(
                l10n.materialPhotoReportHandOverDone(_handedOver!.batchId),
              ),
            ),
          if (_handOverProblem != null)
            _Problem(
              text: l10n.materialPhotoReportHandOverFailed(_handOverProblem!),
            ),
        ],
      ],
    );
  }
}
