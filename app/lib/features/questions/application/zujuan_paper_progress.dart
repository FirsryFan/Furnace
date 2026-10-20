/// 整卷页对照：把用户从组卷网试卷页粘来的整卷清单，对照本地题库，
/// 算出"已经收录哪几道、还缺哪几道"。
///
/// 这一层是**纯读**：不联网、不抓页面、不写库。试卷页 → 题号清单的抽取在
/// lib/domain/services/zujuan/zujuan_paper_extract.dart（粘贴的
/// URL/HTML/纯文本 → paperId/bankId/title/questionIds/questionLinks），本文件只负责
/// 把题号清单和题库对上，并把缺题链接补齐，供收题页对话框与 AI 工具共用。
///
/// 为什么不放在 UI 里：对照结果要同时给界面（"缺哪几道、去复制链接"）和模型
/// （read_zujuan_paper 工具的只读结果），两处口径必须一致；UI 只负责排版。
library;

import '../../../data/repositories/question_repository.dart';
import '../../../domain/services/questions/question_number.dart'
    show questionSerialLabel;
import '../../../domain/services/zujuan/zujuan_link.dart'
    show zujuanQuestionDetailUrl;
import '../../../domain/services/zujuan/zujuan_paper_extract.dart';

/// 题干预览最多保留的字符数（按 Unicode 码点算，中文一字一个）。
const int kZujuanPaperStemPreviewLength = 60;

/// 整卷里的一道题在题库里找到的那一行（同一组卷网 id 多行时只给最新一行）。
class ZujuanPaperMatchedQuestion {
  const ZujuanPaperMatchedQuestion({
    required this.zujuanQuestionId,
    required this.questionId,
    required this.serialLabel,
    required this.stemPreview,
    this.sourceUrl,
  });

  /// 组卷网 questionid（纯数字字符串，与题库 zujuan_question_id 同口径）。
  final String zujuanQuestionId;

  /// 题库主键 questions.id。
  final String questionId;

  /// 界面显示用的题号：有号 TR-00001，没号 TR-未编号。
  final String serialLabel;

  /// 题干压空白后的前 kZujuanPaperStemPreviewLength 个字符，截断时末尾带省略号。
  final String stemPreview;

  /// 题库里存的题源链接（可能为 null）。
  final String? sourceUrl;

  Map<String, Object?> toJson() => <String, Object?>{
        'zujuan_question_id': zujuanQuestionId,
        'question_id': questionId,
        'serial_no': serialLabel,
        'stem_preview': stemPreview,
        'source_url': sourceUrl,
      };

  @override
  bool operator ==(Object other) =>
      other is ZujuanPaperMatchedQuestion &&
      other.zujuanQuestionId == zujuanQuestionId &&
      other.questionId == questionId &&
      other.serialLabel == serialLabel &&
      other.stemPreview == stemPreview &&
      other.sourceUrl == sourceUrl;

  @override
  int get hashCode => Object.hash(
        zujuanQuestionId,
        questionId,
        serialLabel,
        stemPreview,
        sourceUrl,
      );

  @override
  String toString() => 'ZujuanPaperMatchedQuestion(zujuanQuestionId: '
      '$zujuanQuestionId, questionId: $questionId, serialLabel: $serialLabel, '
      'stemPreview: $stemPreview, sourceUrl: $sourceUrl)';
}

/// 整卷页对照结果：抽取本身 + 命中 / 缺题 / 缺题链接。
///
/// 顺序全部按试卷页里题目的出现顺序（ZujuanPaperExtract.questionIds），
/// 同一输入永远同一结果；不排序、不去重（去重已在抽取层做过）。
class ZujuanPaperProgress {
  const ZujuanPaperProgress({
    required this.extract,
    this.matched = const [],
    this.missingQuestionIds = const [],
    this.missingLinks = const [],
  });

  /// 试卷页抽取结果（标题、bankId、题号清单、warnings、truncated）。
  final ZujuanPaperExtract extract;

  /// 题库已收录的题，顺序同试卷页。
  final List<ZujuanPaperMatchedQuestion> matched;

  /// 题库里没有的组卷网 questionid（纯数字字符串），顺序同试卷页。
  final List<String> missingQuestionIds;

  /// 缺题的详情页链接，与 missingQuestionIds 同序但有过滤：拿不到链接
  /// （没有 bankId）或生成不出的题号跳过，所以长度可能小于缺题数。
  final List<String> missingLinks;

  /// 试卷页一共几道题。
  int get questionCount => extract.questionCount;

  /// 题库已收录几道。
  int get matchedCount => matched.length;

  /// 缺几道。
  int get missingCount => missingQuestionIds.length;

  /// 什么也没抽到（没有试卷编号、没有标题、没有题号）。
  bool get isEmpty => extract.isEmpty;

  /// 缺题链接是否给全（没 bankId 时缺题链接为空，界面要提示用户单独复制）。
  bool get hasMissingLinks => missingLinks.isNotEmpty;

  /// 试卷标题（可能为 null）。
  String? get title => extract.title;

  /// 试卷所属 bank 数字 id（可能为 null）。
  String? get bankId => extract.bankId;

  /// 抽取层的中文提示，原样透传（"重复题号已去重""超过 200 道只取前 200"等）。
  List<String> get warnings => extract.warnings;

  /// 题数超过抽取上限被截断。
  bool get truncated => extract.truncated;

  /// 缺题链接一行一个（复制到剪贴板就是这个形态）；为空返回空串。
  String get missingLinksText => missingLinks.join('\n');

  Map<String, Object?> toJson() => <String, Object?>{
        'extract': extract.toJson(),
        'matched': [for (final item in matched) item.toJson()],
        'missing_question_ids': missingQuestionIds,
        'missing_links': missingLinks,
        'question_count': questionCount,
        'matched_count': matchedCount,
        'missing_count': missingCount,
        'is_empty': isEmpty,
      };

  @override
  String toString() => 'ZujuanPaperProgress(questionCount: $questionCount, '
      'matchedCount: $matchedCount, missingCount: $missingCount, '
      'missingQuestionIds: $missingQuestionIds, missingLinks: $missingLinks)';
}

/// 读库做一次整卷对照；只读，不改任何行。
///
/// extract 为空（一个题号都没抽到）时直接返回空结果，**不查库**——这让
/// "粘贴了认不出的文本"这条路径零数据库开销，也方便界面区分"没认出"与
/// "认出了但全缺"。
///
/// 匹配口径：组卷网 id trim 后精确相等（数据层 QuestionRepository.byZujuanQuestionIds
/// 负责）；同一 id 多行取 updatedAt 最新那行（行内顺序已由数据层排好）。
Future<ZujuanPaperProgress> loadZujuanPaperProgress({
  required QuestionRepository repository,
  required ZujuanPaperExtract extract,
}) async {
  if (extract.isEmpty || extract.questionIds.isEmpty) {
    return ZujuanPaperProgress(extract: extract);
  }

  final ids = <String>{for (final id in extract.questionIds) '$id'};
  final rowsByZujuanId = await repository.byZujuanQuestionIds(ids);

  final matched = <ZujuanPaperMatchedQuestion>[];
  final missingIds = <String>[];
  for (final id in extract.questionIds) {
    final key = '$id';
    final rows = rowsByZujuanId[key];
    final question = (rows == null || rows.isEmpty) ? null : rows.first;
    if (question == null) {
      missingIds.add(key);
      continue;
    }
    matched.add(ZujuanPaperMatchedQuestion(
      zujuanQuestionId: key,
      questionId: question.id,
      serialLabel: questionSerialLabel(question.serialNo),
      stemPreview: _stemPreview(question.stem),
      sourceUrl: _blankToNull(question.sourceUrl),
    ));
  }

  final missingLinks = <String>[];
  for (final id in missingIds) {
    final link = zujuanQuestionDetailUrl(
      bankId: extract.bankId,
      questionId: id,
    );
    if (link != null) {
      missingLinks.add(link);
    }
  }

  return ZujuanPaperProgress(
    extract: extract,
    matched: List<ZujuanPaperMatchedQuestion>.unmodifiable(matched),
    missingQuestionIds: List<String>.unmodifiable(missingIds),
    missingLinks: List<String>.unmodifiable(missingLinks),
  );
}

/// 题干压空白 → 截断到 kZujuanPaperStemPreviewLength 个码点（中文一字一个）。
String _stemPreview(String stem,
    {int maxLength = kZujuanPaperStemPreviewLength}) {
  final collapsed = stem.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (collapsed.isEmpty) {
    return '';
  }
  final runes = collapsed.runes.toList();
  if (runes.length <= maxLength) {
    return collapsed;
  }
  return '${String.fromCharCodes(runes.take(maxLength))}…';
}

String? _blankToNull(String? raw) {
  final trimmed = raw?.trim();
  return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
}
