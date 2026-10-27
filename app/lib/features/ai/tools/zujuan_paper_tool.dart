/// 只读 AI 工具 `read_zujuan_paper`：把用户粘来的组卷网试卷页（URL / 整页保存的
/// HTML / 整页纯文本）解析成题目清单，再对照本地题库说清「这页共几道、题库已收录
/// 几道、缺哪几道」。
///
/// 分工：试卷页 → 题号清单在 `domain/services/zujuan/zujuan_paper_extract.dart`
/// （规则、去重、200 道上限都在那里）；题号清单 → 命中/缺题/缺题链接在
/// `features/questions/application/zujuan_paper_progress.dart`（与收题页对话框同一
/// 口径，界面与模型不会各说一套）。本文件只做工具面：参数校验、裁剪清单长度、
/// 说人话的 summary。
///
/// 只读、不联网、不抓页面、不凭空出题：库里没有的题如实报缺，绝不生成题干。
library;

import '../../../data/database/database.dart';
import '../../../data/repositories/question_repository.dart';
import '../../../domain/services/zujuan/zujuan_link.dart'
    show zujuanQuestionDetailUrl;
import '../../../domain/services/zujuan/zujuan_paper_extract.dart';
import '../../questions/application/zujuan_paper_progress.dart';
import '../domain/ai_tool.dart';

class ReadZujuanPaperTool extends AiTool {
  ReadZujuanPaperTool({required AppDatabase db}) : _db = db;

  final AppDatabase _db;

  /// 匹配 / 缺题清单默认各返回多少条。
  static const int defaultMaxCount = 50;

  /// 两条清单的硬上限（与解析层的 200 道题上限同量级，避免一次铺满上下文）。
  static const int hardMaxCount = 200;

  @override
  String get name => 'read_zujuan_paper';

  @override
  String get description => '把用户粘来的组卷网试卷页（试卷页 URL / 整页保存的 HTML /'
      '整页纯文本）解析出这一页的题目清单，再对照题库说明这页共几道、题库已收录哪几道、'
      '缺哪几道（缺题尽量给试卷页详情链接）。用在用户说「这整页卷子我录了几道」「还缺'
      '哪几道题」时。**只读**：不联网、不抓页面、不写库、不凭空出题——库里没有的题如实报缺。';

  @override
  Map<String, Object?> get parameters => {
        'type': 'object',
        'properties': {
          'text': {
            'type': 'string',
            'description': '粘进来的组卷网试卷页内容：试卷页 URL、整页保存的 HTML，或整页'
                '复制的纯文本（里面要有 /<bank>p<paper>.html 或 q<id>.html 形状的链接）。',
          },
          'max_count': {
            'type': 'integer',
            'description': '匹配清单与缺题清单各最多返回多少条（默认 $defaultMaxCount，'
                '上限 $hardMaxCount）；解析上限仍由域层 200 道控制。',
          },
        },
        'required': <String>['text'],
      };

  /// 只读、无 action：与 `read_question` / `read_questions_by_serials` 同一中性组合
  /// （`write` + 可逆），让 `ApprovalEngine` 在任何权限模式下都不逐条询问。
  @override
  ToolRisk riskFor(String action) => ToolRisk.write; // unused: no actions

  @override
  bool reversibleFor(String action) => true;

  @override
  bool get readOnly => true;

  @override
  bool get availableOnCurrentPlatform => true;

  @override
  Future<ToolResult> run(ToolInvocation invocation) async {
    try {
      final args = ToolArgs(invocation.arguments);
      final text = args.optString('text');
      if (text == null) {
        throw ToolArgError(
          '缺少要解析的整页文本：给 `text`，可以是组卷网试卷页 URL、整页保存的'
          ' HTML，或整页复制的纯文本',
        );
      }

      final requestedMax = args.optInt('max_count') ?? defaultMaxCount;
      final maxCount = requestedMax <= 0
          ? defaultMaxCount
          : (requestedMax < hardMaxCount ? requestedMax : hardMaxCount);

      final extract = parseZujuanPaperText(text);
      if (extract.questionIds.isEmpty) {
        throw ToolArgError(
          '没从这段文本里认出组卷网题目链接（需要 /<bank>p<paper>.html 或 q<id>.html'
          ' 形状）：可以把试卷页整页复制，或单独贴题目页链接',
        );
      }

      final progress = await loadZujuanPaperProgress(
        repository: QuestionRepository(_db),
        extract: extract,
      );

      // matched 只保留 4 个键：源链接（source_url）不进模型上下文——模型要的是
      // 「哪几道已经在库里」，不是又一份外部 URL；缺题链接另在 missing 里给。
      final matchedRows = <Map<String, Object?>>[
        for (final item in progress.matched.take(maxCount))
          {
            'zujuan_question_id': item.zujuanQuestionId,
            'question_id': item.questionId,
            'serial_no': item.serialLabel,
            'stem_preview': item.stemPreview,
          },
      ];

      // 缺题链接逐 id 现算（与对照层同一 helper、同一 bankId）：
      // progress.missingLinks 是过滤后的列表，长度可能小于缺题数，不能按位反推。
      final missingRows = <Map<String, Object?>>[
        for (final id in progress.missingQuestionIds.take(maxCount))
          {
            'zujuan_question_id': id,
            'link': zujuanQuestionDetailUrl(
              bankId: progress.extract.bankId,
              questionId: id,
            ),
          },
      ];
      final missingOmitted = progress.missingCount - missingRows.length;

      return ToolResult(
        ok: true,
        summary: _summaryOf(progress, maxCount: maxCount),
        modelResult: {
          'rule': 'library_only',
          'paper_id': progress.extract.paperId,
          'bank_id': progress.extract.bankId,
          'title': progress.extract.title,
          'question_count': progress.questionCount,
          'matched_count': progress.matchedCount,
          'missing_count': progress.missingCount,
          'truncated': progress.truncated,
          'warnings': List<String>.unmodifiable(progress.warnings),
          'matched': matchedRows,
          'missing': missingRows,
          if (missingOmitted > 0) 'missing_omitted': missingOmitted,
        },
      );
    } on ToolArgError catch (e) {
      // 模型给错了参数：变成它能读、能改的结果，而不是异常。
      return ToolResult.failure(e.message);
    }
  }

  /// 说人话的摘要：题数、已收录、缺几道（最多列前 3 个组卷网题号），
  /// 再看要不要提醒 bankId 缺失与 200 道截断。
  String _summaryOf(ZujuanPaperProgress progress, {required int maxCount}) {
    final count = progress.questionCount;
    final matchedCount = progress.matchedCount;
    final missingCount = progress.missingCount;
    final buffer = StringBuffer();
    if (missingCount == 0) {
      buffer.write('这页 $count 道题题库里都有（已收录 $matchedCount 道）。');
    } else {
      final shown = progress.missingQuestionIds.take(3).join('、');
      final missingPart = missingCount > 3 ? '$shown 等' : shown;
      buffer.write('这页试卷共 $count 道题：题库里已有 $matchedCount 道，'
          '缺 $missingCount 道（前几个题号：$missingPart）');
      if (missingCount > maxCount) {
        buffer.write('，这里只列了前 $maxCount 道');
      }
      buffer.write('。');
    }
    buffer.write('我只读题库，不会去组卷网抓页面');
    if (progress.extract.bankId == null) {
      buffer.write('；这页没带 bankId，缺题链接给不全，可以单独复制题目页链接');
    }
    buffer.write('。');
    if (progress.truncated) {
      buffer.write('这页题号超过 200 道，只按前 200 道对照。');
    }
    return buffer.toString();
  }
}
