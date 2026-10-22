import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/features/questions/application/question_library_reader.dart';

/// 题库总览读表（轮次一百三十九，task-120）：只锁**投影口径**，不锁像素。
///
/// 这里用手写的 questions/attachments/object_tags 行而不是 `ingest`，是为了能造出
/// 「未编号」「题名空白」「role=NULL 的旧图」这些真实数据里存在、但收题路径不会
/// 一次造全的状态。
void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> insertQuestion({
    required String id,
    required String stem,
    int? serialNo,
    String? title,
    String subjectKey = '',
    String questionType = 'solution',
    double? difficulty,
    int? year,
    String? region,
    int updatedAt = 0,
  }) async {
    await db.into(db.questions).insert(
          QuestionsCompanion.insert(
            id: id,
            stem: stem,
            serialNo: Value(serialNo),
            title: Value(title),
            subjectKey: Value(subjectKey),
            questionType: Value(questionType),
            difficulty: Value(difficulty),
            year: Value(year),
            region: Value(region),
            stemFingerprint: Value('fp-$id'),
            createdAt: updatedAt,
            updatedAt: updatedAt,
          ),
        );
  }

  Future<void> addAttachment({
    required String id,
    required String questionId,
    String ownerType = 'question',
    String? role,
    int sortOrder = 0,
    String? mime = 'image/png',
  }) async {
    await db.into(db.attachments).insert(
          AttachmentsCompanion.insert(
            id: id,
            ownerType: ownerType,
            ownerId: questionId,
            relPath: 'question_images/$questionId/$id.png',
            mime: Value(mime),
            sortOrder: Value(sortOrder),
            role: Value(role),
            createdAt: 0,
          ),
        );
  }

  Future<void> addTagLink({
    required String tagId,
    required String path,
    required String questionId,
    String objectType = 'question',
  }) async {
    await db.into(db.tags).insert(
          TagsCompanion.insert(
            id: tagId,
            name: path.split('/').last,
            path: Value(path),
            createdAt: 0,
            updatedAt: 0,
          ),
        );
    await db.into(db.objectTags).insert(
          ObjectTagsCompanion.insert(
            id: 'ot-$tagId-$questionId',
            tagId: tagId,
            objectType: objectType,
            objectId: questionId,
            createdAt: 0,
          ),
        );
  }

  test('空库：空快照，不查崩', () async {
    final snapshot = await readQuestionLibrary(db);
    expect(snapshot.isEmpty, isTrue);
    expect(snapshot.totalCount, 0);
    expect(snapshot.truncated, isFalse);
    expect(snapshot.untitledCount, 0);
    expect(snapshot.subjectKeys, isEmpty);
    expect(snapshot.tagPaths, isEmpty);
  });

  test('排序：updatedAt 降序，同刻按 id 升序', () async {
    await insertQuestion(id: 'q-b', stem: 'b', updatedAt: 100);
    await insertQuestion(id: 'q-a', stem: 'a', updatedAt: 100);
    await insertQuestion(id: 'q-c', stem: 'c', updatedAt: 300);
    await insertQuestion(id: 'q-d', stem: 'd', updatedAt: 200);

    final snapshot = await readQuestionLibrary(db);
    expect(
      snapshot.entries.map((entry) => entry.questionId).toList(),
      <String>['q-c', 'q-d', 'q-a', 'q-b'],
    );
  });

  test('limit 截断：多读一行判 truncated，limit<=0 不限', () async {
    for (var i = 0; i < 3; i++) {
      await insertQuestion(id: 'q-$i', stem: '题$i', updatedAt: i);
    }

    final truncated = await readQuestionLibrary(db, limit: 2);
    expect(truncated.entries.length, 2);
    expect(truncated.totalCount, 2);
    expect(truncated.truncated, isTrue);

    final all = await readQuestionLibrary(db, limit: 3);
    expect(all.entries.length, 3);
    expect(all.truncated, isFalse);

    final unlimited = await readQuestionLibrary(db, limit: 0);
    expect(unlimited.entries.length, 3);
    expect(unlimited.truncated, isFalse);
  });

  test('题号：有编号显示 TR-xxxxx，NULL 显示「未编号」', () async {
    await insertQuestion(id: 'q-1', stem: '有编号', serialNo: 42, updatedAt: 2);
    await insertQuestion(id: 'q-2', stem: '没编号', updatedAt: 1);

    final entries = (await readQuestionLibrary(db)).entries;
    expect(entries[0].serialLabel, 'TR-00042');
    expect(entries[1].serialLabel, '未编号');
  });

  test('题名：有名字用名字；空白题名回落题干摘要；空题干兜底', () async {
    await insertQuestion(
        id: 'q-1', stem: '题干很长也无关', title: '  传送带模型  ', updatedAt: 3);
    await insertQuestion(
        id: 'q-2', stem: '  已知函数  f(x) 的单调区间。  ', title: '   ', updatedAt: 2);
    await insertQuestion(id: 'q-3', stem: '   ', updatedAt: 1);

    final entries = (await readQuestionLibrary(db)).entries;
    expect(entries[0].displayTitle, '传送带模型');
    expect(entries[0].hasTitle, isTrue);
    expect(entries[1].hasTitle, isFalse);
    expect(entries[1].displayTitle, '已知函数 f(x) 的单调区间。');
    expect(entries[2].displayTitle, '（无题干）');
  });

  test('题干摘要：压空白并截断 60 字加省略号', () async {
    final long = '甲' * 70;
    await insertQuestion(id: 'q-1', stem: '  第一行\n\n第二行\t尾巴 ');
    await insertQuestion(id: 'q-2', stem: long);

    final entries = (await readQuestionLibrary(db)).entries;
    expect(entries[0].stemPreview, '第一行 第二行 尾巴');
    expect(entries[1].stemPreview.length, 61);
    expect(entries[1].stemPreview.startsWith('甲' * 60), isTrue);
    expect(entries[1].stemPreview.endsWith('…'), isTrue);
  });

  test('题干摘要：公式去定界符、图片占位收成 [图]', () async {
    await insertQuestion(
      id: 'q-1',
      stem: r'已知 $f(x)=x^2$，图象如图［图1］所示。',
      updatedAt: 2,
    );
    await insertQuestion(
      id: 'q-2',
      stem: r'求 $$\frac{a}{b}$$ 的值',
      updatedAt: 1,
    );

    final entries = (await readQuestionLibrary(db)).entries;
    expect(
      entries[0].stemPreview,
      '已知 f(x)=x^2，图象如图［图］所示。',
    );
    expect(entries[0].displayTitle, '已知 f(x)=x^2，图象如图［图］所示。');
    expect(entries[1].stemPreview, r'求 \frac{a}{b} 的值');
  });

  test('标签：只认 objectType=question，路径去重排序', () async {
    await insertQuestion(id: 'q-1', stem: '挂了两个标签', updatedAt: 1);
    await addTagLink(tagId: 't-b', path: '文化课/生物/基因工程', questionId: 'q-1');
    await addTagLink(tagId: 't-a', path: '文化课/生物/遗传', questionId: 'q-1');
    await addTagLink(
      tagId: 't-c',
      path: '文化课/生物/不算',
      questionId: 'q-1',
      objectType: 'knowledge_point',
    );

    final entry = (await readQuestionLibrary(db)).entries.single;
    expect(entry.tagPaths, <String>['文化课/生物/基因工程', '文化课/生物/遗传']);
  });

  test('图片：按 role 分组，组内 sortOrder 再 attachmentId 排序，NULL 当题干图', () async {
    await insertQuestion(id: 'q-1', stem: '三道图', updatedAt: 1);
    await addAttachment(
        id: 'a-3', questionId: 'q-1', role: 'stem', sortOrder: 2);
    await addAttachment(id: 'a-1', questionId: 'q-1', role: null, sortOrder: 0);
    await addAttachment(
        id: 'a-2', questionId: 'q-1', role: 'stem', sortOrder: 0);
    await addAttachment(
        id: 'a-4', questionId: 'q-1', role: 'answer', sortOrder: 0);
    await addAttachment(
        id: 'a-5', questionId: 'q-1', role: 'solution', sortOrder: 0);
    await addAttachment(
      id: 'a-6',
      questionId: 'q-1',
      ownerType: 'ai_message',
      role: 'stem',
    );

    final entry = (await readQuestionLibrary(db)).entries.single;
    expect(
      entry.stemImages.map((image) => image.attachmentId).toList(),
      <String>['a-1', 'a-2', 'a-3'],
    );
    expect(entry.stemImages.every((image) => image.isStem), isTrue);
    expect(entry.stemImages.first.role, kQuestionLibraryStemRole);
    expect(entry.stemImages.first.mime, 'image/png');
    expect(entry.answerImages.single.attachmentId, 'a-4');
    expect(entry.answerImages.single.isAnswer, isTrue);
    expect(entry.solutionImages.single.attachmentId, 'a-5');
    expect(entry.imageCount, 5);
  });

  test('封面图：题干图优先，其次答案图，再解析图，无图 null', () async {
    await insertQuestion(id: 'q-1', stem: '只有答案图', updatedAt: 3);
    await addAttachment(id: 'a-1', questionId: 'q-1', role: 'answer');
    await insertQuestion(id: 'q-2', stem: '只有解析图', updatedAt: 2);
    await addAttachment(id: 'a-2', questionId: 'q-2', role: 'solution');
    await insertQuestion(id: 'q-3', stem: '题干图+答案图', updatedAt: 1);
    await addAttachment(id: 'a-3', questionId: 'q-3', role: 'answer');
    await addAttachment(id: 'a-4', questionId: 'q-3', role: 'stem');
    await insertQuestion(id: 'q-4', stem: '没图', updatedAt: 0);

    final entries = (await readQuestionLibrary(db)).entries;
    expect(entries[0].coverImage!.attachmentId, 'a-1');
    expect(entries[1].coverImage!.attachmentId, 'a-2');
    expect(entries[2].coverImage!.attachmentId, 'a-4');
    expect(entries[3].coverImage, isNull);
  });

  test('统计：未命名数、学科键去重排序并排除空学科', () async {
    await insertQuestion(
        id: 'q-1', stem: 'a', title: '有名', subjectKey: 'physics', updatedAt: 4);
    await insertQuestion(
        id: 'q-2', stem: 'b', subjectKey: 'biology', updatedAt: 3);
    await insertQuestion(id: 'q-3', stem: 'c', subjectKey: '', updatedAt: 2);
    await insertQuestion(
        id: 'q-4', stem: 'd', subjectKey: 'biology', title: ' ', updatedAt: 1);

    final snapshot = await readQuestionLibrary(db);
    expect(snapshot.untitledCount, 3);
    expect(snapshot.subjectKeys, <String>['biology', 'physics']);
  });

  test('字段透传：题型/难度/年份/地区/全量题干', () async {
    await insertQuestion(
      id: 'q-1',
      stem: '全量题干 ${'长' * 200}',
      subjectKey: 'math',
      questionType: 'single_choice',
      difficulty: 7.5,
      year: 2026,
      region: '江苏',
      updatedAt: 9,
    );

    final entry = (await readQuestionLibrary(db)).entries.single;
    expect(entry.subjectKey, 'math');
    expect(entry.questionType, 'single_choice');
    expect(entry.difficulty, 7.5);
    expect(entry.year, 2026);
    expect(entry.region, '江苏');
    expect(entry.stem.length, 205);
    expect(entry.updatedAt, 9);
  });

  test('标签路径并集：快照级去重排序', () async {
    await insertQuestion(id: 'q-1', stem: 'a', updatedAt: 2);
    await insertQuestion(id: 'q-2', stem: 'b', updatedAt: 1);
    await addTagLink(tagId: 't-1', path: '文化课/生物/基因工程', questionId: 'q-1');
    await addTagLink(tagId: 't-2', path: '文化课/生物/遗传', questionId: 'q-2');

    final snapshot = await readQuestionLibrary(db);
    expect(
      snapshot.tagPaths,
      <String>['文化课/生物/基因工程', '文化课/生物/遗传'],
    );
  });
}
