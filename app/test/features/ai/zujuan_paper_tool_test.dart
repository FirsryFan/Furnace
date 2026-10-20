import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/repositories/ai_repository.dart';
import 'package:furnace/data/repositories/anki_repository.dart';
import 'package:furnace/data/repositories/question_repository.dart';
import 'package:furnace/data/repositories/tag_repository.dart';
import 'package:furnace/data/repositories/task_repository.dart';
import 'package:furnace/data/repositories/time_block_repository.dart';
import 'package:furnace/features/ai/domain/ai_tool.dart';
import 'package:furnace/features/ai/domain/approval_engine.dart';
import 'package:furnace/features/ai/domain/tool_registry.dart';
import 'package:furnace/features/ai/tools/zujuan_paper_tool.dart';

/// `read_zujuan_paper` 是对话里「粘贴整卷页 → 对照题库缺哪几道」的只读工具面：
///
///  1. **只读**：不写库、`ApprovalEngine` 任何权限模式都不逐条询问；
///  2. **认不出就报错**：没有组卷网链接形状的文本给 ToolArgError，不猜；
///  3. **对照口径**：整页题数、已收录/缺题计数、matched 每行 4 键、缺题链接
///     逐 id 用详情页 helper 重算（银行号缺失时 link 为 null）；
///  4. **裁剪**：`max_count`（默认 50、上限 200）同时截 matched 与 missing，
///     缺题被略去时给 `missing_omitted`；
///  5. 透传：`truncated` 与 `warnings` 原样带出，`title`/`paper_id`/`bank_id` 来自抽取层；
///  6. 注册：`ToolRegistry` 第 27 个工具，schema 只有 text / max_count。
void main() {
  late AppDatabase db;
  late QuestionRepository questions;
  late ReadZujuanPaperTool tool;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    questions = QuestionRepository(db);
    tool = ReadZujuanPaperTool(db: db);
  });

  tearDown(() async {
    await db.close();
  });

  ToolInvocation invoke(Map<String, Object?> args) => ToolInvocation(
        toolName: tool.name,
        action: tool.name,
        arguments: args,
      );

  Map<String, Object?> modelOf(ToolResult result) =>
      result.modelResult! as Map<String, Object?>;

  /// 造一段整卷页文本：[questionIds] 会变成 `/<bank>q<id>.html` 链接。
  String paperText({
    String? bankId = '10',
    String? paperId = '3076310',
    String? title = '2026 届高三上期末',
    List<String> questionIds = const <String>[],
  }) {
    final bank = bankId ?? '';
    final buffer = StringBuffer();
    if (title != null) {
      buffer.write('<title>$title</title>');
    }
    if (paperId != null) {
      buffer.write('/${bank}p$paperId.html ');
    }
    for (final id in questionIds) {
      buffer.write('/${bank}q$id.html ');
    }
    return buffer.toString();
  }

  Future<Question> seedQuestion({
    required String stem,
    String? zujuanQuestionId,
    String? sourceUrl,
  }) async {
    final ingested = await questions.ingest(
      QuestionDraft(
        stem: stem,
        zujuanQuestionId: zujuanQuestionId,
        sourceUrl: sourceUrl,
      ),
    );
    return ingested.question;
  }

  group('只读', () {
    test('ApprovalEngine 在任何权限模式下都不逐条询问', () {
      for (final mode in AiPermissionMode.values) {
        final decision =
            ApprovalEngine(mode: mode).forInvocation(tool, const {});
        expect(decision.risk, ToolRisk.write);
        expect(decision.reversible, isTrue);
        expect(
          decision.disposition,
          isNot(ToolDisposition.individualApproval),
          reason: 'mode ${mode.name} must not ask one by one for a read',
        );
      }
      expect(tool.readOnly, isTrue);
      expect(tool.riskFor(''), ToolRisk.write);
      expect(tool.reversibleFor(''), isTrue);
      expect(tool.availableOnCurrentPlatform, isTrue);
    });

    test('一次调用不改任何表', () async {
      await seedQuestion(
        stem: '已收录的一道题',
        zujuanQuestionId: '1001',
        sourceUrl: 'https://zujuan.xkw.com/10q1001.html',
      );

      Future<List<String>> snapshot() async {
        final questionRows = await db.select(db.questions).get();
        final optionRows = await db.select(db.questionOptions).get();
        final attachmentRows = await db.select(db.attachments).get();
        return [
          for (final row in questionRows)
            'q:${row.id}:${row.stem}:${row.updatedAt}',
          for (final row in optionRows) 'o:${row.id}:${row.content}',
          for (final row in attachmentRows) 'a:${row.id}:${row.relPath}',
        ];
      }

      final before = await snapshot();
      final result = await tool.run(invoke({
        'text': paperText(questionIds: ['1001'])
      }));
      expect(result.ok, isTrue);
      expect(await snapshot(), before);
    });
  });

  group('参数与识别', () {
    test('缺少 text 参数时失败', () async {
      final result = await tool.run(invoke(const {}));
      expect(result.ok, isFalse);
      expect(result.error, contains('缺少要解析的整页文本'));
    });

    test('text 是空白时按缺少参数处理', () async {
      final result = await tool.run(invoke({'text': '   '}));
      expect(result.ok, isFalse);
      expect(result.error, contains('缺少要解析的整页文本'));
    });

    test('认不出组卷网链接时失败且不猜', () async {
      final result = await tool.run(invoke({'text': '这是一段普通文本，没有组卷网链接。'}));
      expect(result.ok, isFalse);
      expect(result.error, contains('没从这段文本里认出组卷网题目链接'));
      expect(result.modelResult, isNull);
    });

    test('只有标题没有题号也按认不出处理', () async {
      final result = await tool.run(invoke({'text': '<title>空卷</title>'}));
      expect(result.ok, isFalse);
      expect(result.error, contains('没从这段文本里认出组卷网题目链接'));
    });
  });

  group('整卷对照', () {
    test('一页 3 道全缺：计数、缺题链接与标题都如实给出', () async {
      final result = await tool.run(invoke({
        'text': paperText(
          title: '2026 届高三上期末',
          questionIds: ['1001', '1002', '1003'],
        ),
      }));

      expect(result.ok, isTrue);
      final model = modelOf(result);
      expect(model['rule'], 'library_only');
      expect(model['paper_id'], '3076310');
      expect(model['bank_id'], '10');
      expect(model['title'], '2026 届高三上期末');
      expect(model['question_count'], 3);
      expect(model['matched_count'], 0);
      expect(model['missing_count'], 3);
      expect(model['matched'], isEmpty);
      expect(model['truncated'], isFalse);
      expect(model['warnings'], ['找到 3 个题目链接']);
      expect(model.containsKey('missing_omitted'), isFalse);

      final missing =
          ((model['missing']! as List).cast<Map<String, Object?>>());
      expect(missing, hasLength(3));
      expect(
        [for (final row in missing) row['zujuan_question_id']],
        ['1001', '1002', '1003'],
      );
      expect(
        [for (final row in missing) row['link']],
        [
          'https://zujuan.xkw.com/10q1001.html',
          'https://zujuan.xkw.com/10q1002.html',
          'https://zujuan.xkw.com/10q1003.html',
        ],
      );
      expect(result.summary, contains('这页试卷共 3 道题'));
      expect(result.summary, contains('题库里已有 0 道'));
      expect(result.summary, contains('缺 3 道'));
      expect(result.summary, contains('1001、1002、1003'));
      expect(result.summary, contains('不会去组卷网抓页面'));
    });

    test('部分命中：matched 给库内 id、题号与题干预览，缺题按页序', () async {
      final seeded = await seedQuestion(
        stem: '第一道题：已知函数 f(x)=x^2，求单调区间。',
        zujuanQuestionId: '1001',
        sourceUrl: 'https://zujuan.xkw.com/10q1001.html',
      );

      final result = await tool.run(invoke({
        'text': paperText(questionIds: ['1001', '1002', '1003']),
      }));

      expect(result.ok, isTrue);
      final model = modelOf(result);
      expect(model['question_count'], 3);
      expect(model['matched_count'], 1);
      expect(model['missing_count'], 2);

      final matched =
          ((model['matched']! as List).cast<Map<String, Object?>>()).single;
      expect(matched['zujuan_question_id'], '1001');
      expect(matched['question_id'], seeded.id);
      expect(matched['serial_no'], 'TR-00001');
      expect(matched['stem_preview'], '第一道题：已知函数 f(x)=x^2，求单调区间。');
      expect(matched.keys.toList(), [
        'zujuan_question_id',
        'question_id',
        'serial_no',
        'stem_preview',
      ]);
      expect(matched.containsKey('source_url'), isFalse);

      final missing =
          ((model['missing']! as List).cast<Map<String, Object?>>());
      expect(
        [for (final row in missing) row['zujuan_question_id']],
        ['1002', '1003'],
      );
    });

    test('全命中：missing 为空，summary 说题库里都有', () async {
      await seedQuestion(stem: '第一道题', zujuanQuestionId: '1001');
      await seedQuestion(stem: '第二道题', zujuanQuestionId: '1002');

      final result = await tool.run(invoke({
        'text': paperText(questionIds: ['1001', '1002']),
      }));

      expect(result.ok, isTrue);
      final model = modelOf(result);
      expect(model['matched_count'], 2);
      expect(model['missing_count'], 0);
      expect(model['missing'], isEmpty);
      expect(result.summary, contains('这页 2 道题题库里都有'));
      expect(result.summary, contains('已收录 2 道'));
    });

    test('没有 bankId 时缺题 link 全为 null，summary 提醒单独复制', () async {
      final result = await tool.run(invoke({
        'text': paperText(
          bankId: null,
          paperId: '3076310',
          title: '无 bank 的卷',
        ).replaceFirst(
            '/p3076310.html ', '/p3076310.html /q1001.html /q1002.html '),
      }));

      expect(result.ok, isTrue);
      final model = modelOf(result);
      expect(model['bank_id'], isNull);
      expect(model['missing_count'], 2);
      final missing =
          ((model['missing']! as List).cast<Map<String, Object?>>());
      expect([for (final row in missing) row['link']], [null, null]);
      expect(result.summary, contains('没带 bankId'));
      expect(result.summary, contains('缺题链接给不全'));
      expect(
        (model['warnings']! as List).join('；'),
        contains('缺少 bankId'),
      );
    });

    test('没有 title 时 title 透传 null，不猜标题', () async {
      final result = await tool.run(invoke({
        'text': paperText(title: null, questionIds: ['1001']),
      }));

      expect(result.ok, isTrue);
      expect(modelOf(result)['title'], isNull);
    });
  });

  group('max_count 裁剪', () {
    test('缺题超过 max_count 时截断并给 missing_omitted', () async {
      final result = await tool.run(invoke({
        'text': paperText(questionIds: ['1001', '1002', '1003']),
        'max_count': 1,
      }));

      expect(result.ok, isTrue);
      final model = modelOf(result);
      expect(model['missing_count'], 3);
      expect(model['missing'], hasLength(1));
      expect(model['missing_omitted'], 2);
      expect(result.summary, contains('这里只列了前 1 道'));
    });

    test('matched 也受 max_count 裁剪，但不产生 missing_omitted', () async {
      await seedQuestion(stem: '第一道题', zujuanQuestionId: '1001');
      await seedQuestion(stem: '第二道题', zujuanQuestionId: '1002');

      final result = await tool.run(invoke({
        'text': paperText(questionIds: ['1001', '1002']),
        'max_count': 1,
      }));

      expect(result.ok, isTrue);
      final model = modelOf(result);
      expect(model['matched_count'], 2);
      expect(model['matched'], hasLength(1));
      expect(model['missing_count'], 0);
      expect(model.containsKey('missing_omitted'), isFalse);
    });

    test('max_count 非正数回退默认值，过大抬到硬上限', () async {
      await seedQuestion(stem: '第一道题', zujuanQuestionId: '1001');
      await seedQuestion(stem: '第二道题', zujuanQuestionId: '1002');

      final fallback = await tool.run(invoke({
        'text': paperText(questionIds: ['1001', '1002']),
        'max_count': 0,
      }));
      final clamped = await tool.run(invoke({
        'text': paperText(questionIds: ['1001', '1002']),
        'max_count': 9999,
      }));

      expect(fallback.ok, isTrue);
      expect((modelOf(fallback)['matched']! as List), hasLength(2));
      expect(clamped.ok, isTrue);
      expect((modelOf(clamped)['matched']! as List), hasLength(2));
      expect(
        ReadZujuanPaperTool.defaultMaxCount,
        lessThanOrEqualTo(ReadZujuanPaperTool.hardMaxCount),
      );
    });
  });

  group('透传与注册', () {
    test('truncated 与 warnings 原样透传（超过 200 道只解析前 200）', () async {
      final ids = [for (var index = 1; index <= 205; index++) '$index'];
      final result = await tool.run(invoke({
        'text': paperText(questionIds: ids),
        'max_count': 2,
      }));

      expect(result.ok, isTrue);
      final model = modelOf(result);
      expect(model['truncated'], isTrue);
      expect(model['question_count'], 200);
      expect(model['missing_count'], 200);
      expect(model['missing'], hasLength(2));
      expect(model['missing_omitted'], 198);
      expect(
        (model['warnings']! as List).join('；'),
        contains('超过 200 道'),
      );
      expect(result.summary, contains('只按前 200 道对照'));
    });

    test('重复题号去重 warning 透传', () async {
      final result = await tool.run(invoke({
        'text': '/10p3076310.html /10q1001.html /10q1001.html /10q1002.html',
      }));

      expect(result.ok, isTrue);
      final model = modelOf(result);
      expect(model['question_count'], 2);
      expect(
        (model['warnings']! as List),
        contains('重复题号已去重'),
      );
    });

    test('注册后是第 27 个工具，schema 只有 text / max_count', () {
      final registry = ToolRegistry.forApp(
        db: db,
        tasks: TaskRepository(db),
        blocks: TimeBlockRepository(db),
        anki: AnkiRepository(db),
        tags: TagRepository(db),
      );

      expect(registry.byName('read_zujuan_paper'), isA<ReadZujuanPaperTool>());
      expect(registry.all, hasLength(27));
      expect(
        registry.forCurrentPlatform.map((item) => item.name),
        contains('read_zujuan_paper'),
      );

      final spec = registry.modelSpecs
          .firstWhere((item) => item.name == 'read_zujuan_paper');
      expect(spec.description, contains('只读'));
      expect(spec.parameters['type'], 'object');
      expect(spec.parameters['required'], contains('text'));
      final properties = spec.parameters['properties']! as Map<String, Object?>;
      expect(properties.keys, containsAll(['text', 'max_count']));
    });
  });
}
