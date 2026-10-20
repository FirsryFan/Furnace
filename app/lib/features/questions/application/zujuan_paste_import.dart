import 'package:furnace/data/repositories/question_repository.dart';
import 'package:furnace/domain/services/zujuan/zujuan_link.dart';
import 'package:furnace/domain/services/zujuan/zujuan_paste.dart';

/// 粘贴组卷网题面 → 题库草稿的装配层（轮次一百二十七，定点组卷网找题）。
///
/// 解析归 [parseZujuanPaste]（纯文本、永不抛），这里只负责把一条
/// [ZujuanPastedQuestion] 翻译成 [QuestionDraft]：**不改写题干、不补答案、不猜
/// 选项对错**，只把已识别到的字段搬过去，并把来源信息落进 v26 的三个来源列。
///
/// 口径：
///  * 入库状态是 `raw`——粘贴来的题没经过人确认加工，不该装成 `structured`；
///  * 来源 `origin` 是 `zujuan`（历史上只有 manual / ai_scan / furnace 三种）；
///  * 只要拿到了 questionid 与 bankid，即使粘贴文本里没有完整链接，也用
///    [zujuanQuestionDetailUrl] 补一条详情页链接（url-grammar.md 的
///    `<bankid>q<id>.html` 形），链接可重建、可回溯；
///  * 知识点列表只用于预览：questions 表没有"考点"列，挂知识点要走标签树
///    （`object_tags`），这是确认入库之后另一件事，装草稿时不猜标签；
///  * 答案/解析为空串一律存 null（NULL = 没拿到，与空字符串区分）。
///
/// 选项的 `isCorrect` 一律 false：答案文本可能是 `A`，也可能是
/// `（1）A（2）B` 这种分小问写法，自动标"正确选项"很容易错标，留给确认环节。
QuestionDraft zujuanDraftFromPasted(
  ZujuanPastedQuestion pasted, {
  required String subjectKey,
  String? stemOverride,
  String defaultSourceLevel = 'school',
}) {
  final stem = (stemOverride ?? pasted.stem).trim();
  if (stem.isEmpty) {
    throw ArgumentError.value(stem, 'stem', '题干为空，不能作为题目入库');
  }

  final options = <QuestionOptionDraft>[];
  for (var i = 0; i < pasted.options.length; i++) {
    final option = pasted.options[i];
    options.add(
      QuestionOptionDraft(
        label: option.label,
        content: option.content,
        sortOrder: i,
      ),
    );
  }

  final questionId = _trimToNull(pasted.zujuanQuestionId);
  final bankId = _trimToNull(pasted.zujuanBankId);
  final pastedUrl = _trimToNull(pasted.sourceUrl);
  final sourceUrl = pastedUrl ??
      zujuanQuestionDetailUrl(bankId: bankId, questionId: questionId);

  return QuestionDraft(
    stem: stem,
    answer: _trimToNull(pasted.answer),
    solution: _trimToNull(pasted.solution),
    subjectKey: subjectKey,
    sourceLevel: defaultSourceLevel,
    sourceLabel: pasted.sourceLabel?.trim() ?? '',
    year: pasted.year,
    region: _trimToNull(pasted.region),
    sourceUrl: sourceUrl,
    zujuanQuestionId: questionId,
    zujuanBankId: bankId,
    origin: 'zujuan',
    state: 'raw',
    options: List<QuestionOptionDraft>.unmodifiable(options),
  );
}

/// 把一段粘贴文本解析成多条待入库草稿（批量版）。
///
/// 与单条版同一口径；**题干为空的草稿直接跳过**（解析器在结构识别失败时会返回
/// 空题干的兜底草稿，那种东西不该写进题库），不因一条坏草稿中断整批。返回值
/// 顺序与解析顺序一致。
List<QuestionDraft> zujuanDraftsFromPaste(
  String raw, {
  required String subjectKey,
  String defaultSourceLevel = 'school',
}) {
  final drafts = <QuestionDraft>[];
  for (final pasted in parseZujuanPaste(raw)) {
    if (pasted.stem.trim().isEmpty) continue;
    drafts.add(
      zujuanDraftFromPasted(
        pasted,
        subjectKey: subjectKey,
        defaultSourceLevel: defaultSourceLevel,
      ),
    );
  }
  return List<QuestionDraft>.unmodifiable(drafts);
}

String? _trimToNull(String? raw) {
  final trimmed = raw?.trim() ?? '';
  return trimmed.isEmpty ? null : trimmed;
}
