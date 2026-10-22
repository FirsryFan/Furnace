import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/features/questions/application/question_stem_display_reader.dart';

/// 题干一行显示文本的读表（轮次一百四十四，task-141）：只锁**投影口径**，
/// 不锁像素——列表显示不读图片字节，快照判定靠 B2「1 图 + >=2 占位」数量兜底。
///
/// 这里手写 questions/attachments 行而不是走 ingest，是为了造出「role=NULL 的旧
/// 题干图」「答案截图」「其它 owner 的附件」这些收题路径一次造不全的状态。
void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> insertQuestion(String id, String stem) async {
    await db.into(db.questions).insert(
          QuestionsCompanion.insert(
            id: id,
            stem: stem,
            stemFingerprint: Value('fp-$id'),
            createdAt: 0,
            updatedAt: 0,
          ),
        );
  }

  Future<void> addAttachment({
    required String id,
    required String ownerId,
    String ownerType = 'question',
    String? role,
  }) async {
    await db.into(db.attachments).insert(
          AttachmentsCompanion.insert(
            id: id,
            ownerType: ownerType,
            ownerId: ownerId,
            relPath: 'question_images/$ownerId/$id.png',
            mime: const Value('image/png'),
            role: Value(role),
            createdAt: 0,
          ),
        );
  }

  test('空库返回空 map', () async {
    expect(await readQuestionStemDisplays(db), isEmpty);
  });

  test('普通题：没有配图，走题干预览（公式去定界符、占位归一）', () async {
    await insertQuestion('q1', r'已知 $x^2$ 与 ［图1］，求最小值。');
    final displays = await readQuestionStemDisplays(db);
    final display = displays['q1']!;
    expect(display.isSnapshot, isFalse);
    expect(display.label, isEmpty);
    expect(display.hasExcerpt, isFalse);
    expect(display.imageCount, 0);
    expect(display.text, '已知 x^2 与 ［图］，求最小值。');
  });

  test('1 图 + 2 处占位且无尺寸：按 B2 判快照，正文当摘录', () async {
    await insertQuestion('q1', '［图1］［图2］光学实验');
    await addAttachment(id: 'a1', ownerId: 'q1');
    final display = (await readQuestionStemDisplays(db))['q1']!;
    expect(display.isSnapshot, isTrue);
    expect(display.imageCount, 1);
    expect(display.placeholderCount, 2);
    expect(display.label, '整题截图 · 2 处公式/图');
    expect(display.hasExcerpt, isTrue);
    expect(display.text, '光学实验');
  });

  test('纯占位快照：没有正文摘录时用标签兜底', () async {
    await insertQuestion('q1', '［图1］［图2］');
    await addAttachment(id: 'a1', ownerId: 'q1');
    final display = (await readQuestionStemDisplays(db))['q1']!;
    expect(display.isSnapshot, isTrue);
    expect(display.hasExcerpt, isFalse);
    expect(display.text, '整题截图 · 2 处公式/图');
  });

  test('答案/解析截图不参与快照判定', () async {
    await insertQuestion('q1', '［图1］［图2］光学实验');
    await addAttachment(id: 'a1', ownerId: 'q1', role: 'answer');
    await addAttachment(id: 'a2', ownerId: 'q1', role: 'answer');
    final display = (await readQuestionStemDisplays(db))['q1']!;
    expect(display.isSnapshot, isFalse);
    expect(display.imageCount, 0);
    expect(display.text, contains('［图］'));
  });

  test('role=NULL 的旧题干图算题干图', () async {
    await insertQuestion('q1', '［图1］［图2］光学实验');
    await addAttachment(id: 'a1', ownerId: 'q1');
    final display = (await readQuestionStemDisplays(db))['q1']!;
    expect(display.isSnapshot, isTrue);
    expect(display.imageCount, 1);
  });

  test('其它 owner 类型的附件不算题干图', () async {
    await insertQuestion('q1', '［图1］［图2］光学实验');
    await addAttachment(
      id: 'a1',
      ownerId: 'q1',
      ownerType: 'ai_message',
    );
    final display = (await readQuestionStemDisplays(db))['q1']!;
    expect(display.isSnapshot, isFalse);
    expect(display.imageCount, 0);
  });

  test('questionIds 只读给定题；未知 id 忽略；空集合返回空 map', () async {
    await insertQuestion('q1', '第一道题');
    await insertQuestion('q2', '第二道题');
    await insertQuestion('q3', '第三道题');
    final only = await readQuestionStemDisplays(db,
        questionIds: {' q1 ', '', 'unknown'});
    expect(only.keys, ['q1']);
    expect(only['q1']!.text, '第一道题');
    expect(
      await readQuestionStemDisplays(db, questionIds: const <String>{}),
      isEmpty,
    );
  });

  test('maxLength 透传给显示文本', () async {
    await insertQuestion('q1', '一二三四五六七八九十');
    final display = (await readQuestionStemDisplays(db, maxLength: 4))['q1']!;
    expect(display.text, '一二三四…');
  });

  test('多道题各自解析，互不影响', () async {
    await insertQuestion('q1', r'求 $f(x)$ 的导数');
    await insertQuestion('q2', '［图1］［图2］整卡截图题');
    await addAttachment(id: 'a1', ownerId: 'q2');
    final displays = await readQuestionStemDisplays(db);
    expect(displays, hasLength(2));
    expect(displays['q1']!.isSnapshot, isFalse);
    expect(displays['q1']!.text, '求 f(x) 的导数');
    expect(displays['q2']!.isSnapshot, isTrue);
  });

  test('空题干：不抛，显示文本为空', () async {
    await insertQuestion('q1', '');
    final display = (await readQuestionStemDisplays(db))['q1']!;
    expect(display.isEmpty, isTrue);
  });
}
