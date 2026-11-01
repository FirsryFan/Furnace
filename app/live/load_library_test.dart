// LIVE harness — 把本地题库包全部导入用户真实 Furnace 库，并清空重建标签系统。
//
// 它不在 test/ 下，永远不会进常规套件。显式运行：
//
//   cd E:/Projects/Furnace/app
//   FURNACE_LIVE_LIBRARY=dry flutter test live/load_library_test.dart   # 只备份+迁移演练+统计，不写真实库
//   FURNACE_LIVE_LIBRARY=1   flutter test live/load_library_test.dart   # 正式导入+重建标签
//
// 纪律（用户真实数据，写坏不可逆）：
//  1) 先复制真实库到 00-inbox/backup-20261102/，复本大小不一致就直接中止；
//  2) 先在"真实库的临时副本"上跑一遍 v35 -> v43 迁移，核对迁移前后行数，再碰真实库；
//  3) 只写 questions/question_options/attachments/object_tags/tags/review_group_plans；
//     knowledge_points / card_states / review_logs / 其它表只读不写；
//  4) 全程不联网；
//  5) 报告写到 00-inbox/load-library-report-<stamp>.md 与 .json。
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/data/database/database.dart';
import 'package:furnace/data/package/question_pack_codec.dart';
import 'package:furnace/data/repositories/question_repository.dart';
import 'package:furnace/data/repositories/tag_repository.dart';
import 'package:furnace/domain/services/package/question_pack_plan.dart';
import 'package:furnace/domain/services/package/question_pack_record.dart';
import 'package:furnace/domain/services/scheduling/thread_balance_inputs.dart'
    show kKnowledgePointObjectType, kQuestionObjectType;
import 'package:furnace/features/questions/data/question_media_store.dart';
import 'package:sqlite3/sqlite3.dart' as sql;

const String _liveFlag = 'FURNACE_LIVE_LIBRARY';
const String _workspaceRoot = r'E:\Workspaces\Furnace';
const String _packsDirPath =
    r'E:\Workspaces\Furnace\10-projects\zujuan-harvest\harvest\out';
const String _processedPackPath =
    r'E:\Workspaces\Furnace\00-inbox\prelim-process\furnace-zujuan-2026-10-27T16-09-44.processed.tqb';
const String _backupDirPath = r'E:\Workspaces\Furnace\00-inbox\backup-20261102';
const String _reportDirPath = r'E:\Workspaces\Furnace\00-inbox';

/// 新标签树：每行一条路径，父级自动创建。
const List<String> _tagSpec = <String>[
  '语文/现代文阅读',
  '语文/古诗文/诗歌鉴赏',
  '语文/古诗文/文言文',
  '语文/语言文字运用',
  '语文/写作',
  '数学/函数与导数',
  '数学/解析几何',
  '数学/数列与不等式',
  '数学/创新与竞赛',
  '数学/概率统计',
  '英语/词汇',
  '英语/语法',
  '英语/阅读',
  '英语/写作',
  '物理/力学',
  '物理/电磁学',
  '物理/热学',
  '物理/光学',
  '物理/近代物理',
  '物理/实验与创新',
  '化学/无机与元素',
  '化学/有机化学',
  '化学/反应原理',
  '化学/实验与探究',
  '化学/结构与性质',
  '生物/细胞与代谢',
  '生物/遗传与进化',
  '生物/稳态与调节',
  '生物/生态',
  '能力/语言解码A1',
  '能力/信息定位A2',
  '能力/逻辑论证A3',
  '能力/结构化建模A4',
  '能力/计算估算A5',
  '能力/图表图像A6',
  '能力/转化等价A7',
  '能力/实验设计A8',
  '能力/表达压缩A9',
  '能力/自我监控A10',
];

const Map<String, String> _subjectTagPath = <String, String>{
  'chinese': '语文',
  'math': '数学',
  'english': '英语',
  'physics': '物理',
  'chemistry': '化学',
  'biology': '生物',
};

const Map<String, String> _capabilityTagPath = <String, String>{
  'A1': '能力/语言解码A1',
  'A2': '能力/信息定位A2',
  'A3': '能力/逻辑论证A3',
  'A4': '能力/结构化建模A4',
  'A5': '能力/计算估算A5',
  'A6': '能力/图表图像A6',
  'A7': '能力/转化等价A7',
  'A8': '能力/实验设计A8',
  'A9': '能力/表达压缩A9',
  'A10': '能力/自我监控A10',
};

/// 强关键词（权重 3）：学科特有术语，用来压过通用词。
const Map<String, List<String>> _strongKeywords = <String, List<String>>{
  'chinese': <String>[
    '文言文',
    '古诗',
    '诗歌',
    '现代文',
    '文学类',
    '信息类',
    '语言文字运用',
    '成语',
    '病句',
    '修辞',
    '标点',
    '默写',
    '作文',
    '写作',
    '阅读',
  ],
  'math': <String>[
    '函数',
    '导数',
    '数列',
    '不等式',
    '解析几何',
    '椭圆',
    '双曲线',
    '抛物线',
    '向量',
    '复数',
    '概率',
    '统计',
    '三角函数',
    '立体几何',
    '集合',
    '排列组合',
    '二项式',
    '极限',
    '积分',
    '对数',
  ],
  'english': <String>[
    '英语',
    '词汇',
    '语法',
    '完形',
    '七选五',
    '续写',
    '应用文',
    '听力',
    '从句',
    '时态',
    '语态',
  ],
  'physics': <String>[
    '牛顿',
    '匀变速',
    '抛体',
    '圆周运动',
    '动量',
    '电磁感应',
    '洛伦兹',
    '安培',
    '电场',
    '磁场',
    '电势',
    '电路',
    '交变电流',
    '热力学',
    '理想气体',
    '光电效应',
    '原子核',
    '机械波',
    '干涉',
    '衍射',
    '折射',
    '浮力',
    '摩擦力',
    '运动',
  ],
  'chemistry': <String>[
    '化学',
    '有机',
    '无机',
    '化学平衡',
    '氧化还原',
    '电解',
    '离子反应',
    '摩尔',
    '热化学',
    '晶体结构',
    '官能团',
    '同分异构',
    '元素周期律',
    '溶液',
    '反应原理',
  ],
  'biology': <String>[
    '细胞',
    '遗传',
    '基因',
    'DNA',
    'RNA',
    '蛋白质',
    '酶',
    'ATP',
    '光合',
    '呼吸',
    '生态',
    '种群',
    '群落',
    '免疫',
    '激素',
    '神经',
    '染色体',
    '减数',
    '有丝',
    '变异',
    '进化',
    '育种',
    '发酵',
    '培养基',
    '基因工程',
    '细胞工程',
    '组织培养',
    '克隆',
    '胚胎',
    '稳态',
    '内环境',
    '物质循环',
    '能量流动',
    '凋亡',
    '衰老',
    '癌',
    '病毒',
    '细菌',
    '真菌',
    '代谢',
    '细胞器',
    '核酸',
    '糖类',
    '脂质',
    '脂肪',
    '固醇',
    '胆固醇',
    '磷脂',
    '氨基酸',
    '中心法则',
    '转录',
    '翻译',
    '复制',
    '分离定律',
    '自由组合',
    '伴性',
    '突变',
    '物种',
    '隔离',
    '多样性',
    '演替',
    '食物链',
    '食物网',
    '营养级',
    '细胞膜',
    '细胞核',
    '线粒体',
    '内质网',
    '高尔基体',
    '溶酶体',
    '核糖体',
    '中心体',
    '液泡',
    '细胞骨架',
    '染色质',
    '核仁',
    '核孔',
    '糖被',
    '渗透',
    '无机盐',
    '活化能',
    '转化',
    '适应',
    '抗原',
    '抗体',
    '淋巴',
    '血浆',
    '组织液',
    '血糖',
    '体温',
    '水盐',
    '反射',
    '突触',
    '神经元',
    '干细胞',
    '原癌基因',
    '抑癌基因',
    '表观遗传',
    'PCR',
    '噬菌体',
    '肺炎链球菌',
    '艾弗里',
    '赫尔希',
    '萨顿',
    '摩尔根',
    '格里菲思',
    '限制酶',
    '载体',
    '标记基因',
    '脱分化',
    '再分化',
    '全能性',
    '生物膜',
    '分泌蛋白',
    '生态系统',
    '生态工程',
    '生态位',
    '生态足迹',
    '群落演替',
    '种群密度',
    '基因频率',
    '基因型',
    '表型',
    '纯合子',
    '杂合子',
    '自由扩散',
    '协助扩散',
    '主动运输',
    '胞吞',
    '胞吐',
    '光合作用',
    '细胞呼吸',
  ],
};

/// 弱关键词（权重 1）：通用词，只在没有强关键词时起作用。
const Map<String, List<String>> _weakKeywords = <String, List<String>>{
  'chinese': <String>[
    '文言',
    '古诗',
    '诗歌',
    '现代文',
    '文学类',
    '信息类',
    '语言文字',
    '语用',
    '成语',
    '病句',
    '修辞',
    '标点',
    '默写',
    '作文',
    '写作',
    '阅读',
  ],
  'math': <String>[
    '函数',
    '导数',
    '几何',
    '数列',
    '不等式',
    '概率',
    '统计',
    '向量',
    '复数',
    '三角',
    '方程',
    '曲线',
    '椭圆',
    '双曲线',
    '抛物线',
    '集合',
    '排列',
    '组合',
    '极限',
    '积分',
  ],
  'english': <String>[
    '英语',
    '词汇',
    '语法',
    '完形',
    '七选五',
    '续写',
    '应用文',
    '听力',
    '翻译',
    '从句',
    '时态',
    '语态',
  ],
  'physics': <String>[
    '运动',
    '牛顿',
    '受力',
    '电场',
    '磁场',
    '电路',
    '电流',
    '功',
    '动能',
    '势能',
    '动量',
    '热力学',
    '温度',
    '光',
    '折射',
    '原子',
    '核反应',
    '振动',
    '波',
    '压强',
    '浮力',
    '电场',
    '电磁',
  ],
  'chemistry': <String>[
    '化学',
    '元素',
    '反应',
    '有机',
    '无机',
    '平衡',
    '溶液',
    '氧化',
    '还原',
    '电解',
    '酸',
    '碱',
    '盐',
    '分子',
    '晶体',
    '实验',
    '离子',
    '摩尔',
    '热化学',
  ],
  'biology': <String>[
    '细胞',
    '遗传',
    '基因',
    'DNA',
    'RNA',
    '蛋白质',
    '酶',
    'ATP',
    '光合',
    '呼吸',
    '生态',
    '种群',
    '群落',
    '免疫',
    '激素',
    '神经',
    '染色体',
    '减数',
    '有丝',
    '变异',
    '进化',
    '育种',
    '发酵',
    '培养基',
    '工程',
    '组织培养',
    '克隆',
    '胚胎',
    '稳态',
    '内环境',
    '物质循环',
    '能量流动',
    '凋亡',
    '衰老',
    '癌',
    '病毒',
    '细菌',
    '真菌',
    '代谢',
    '细胞器',
    '核酸',
    '糖类',
    '脂质',
    '氨基酸',
    '中心法则',
    '转录',
    '翻译',
    '复制',
    '分离定律',
    '自由组合',
    '伴性',
    '突变',
    '物种',
    '隔离',
    '多样性',
    '演替',
    '食物链',
    '食物网',
    '营养级',
    '光合作用',
  ],
};

String _two(int value) => value.toString().padLeft(2, '0');

String _stampOf(DateTime time) =>
    time.year.toString() +
    _two(time.month) +
    _two(time.day) +
    '-' +
    _two(time.hour) +
    _two(time.minute) +
    _two(time.second);

String? _nullIfBlank(String? raw) {
  final trimmed = raw?.trim() ?? '';
  return trimmed.isEmpty ? null : trimmed;
}

/// 用只读 sqlite3 读真实库现状（不经过 drift，避免触发迁移）。
Map<String, Object?> readCounts(String dbPath) {
  final db = sql.sqlite3.open(dbPath, mode: sql.OpenMode.readOnly);
  try {
    final counts = <String, Object?>{};
    const tables = <String>[
      'questions',
      'question_options',
      'tags',
      'object_tags',
      'knowledge_points',
      'card_states',
      'review_logs',
      'review_group_plans',
      'attachments',
      'knowledge_packages',
      'mind_nodes',
    ];
    for (final table in tables) {
      try {
        counts[table] =
            db.select('SELECT COUNT(*) AS c FROM ' + table).first['c'];
      } catch (error) {
        counts[table] = -1;
      }
    }
    counts['user_version'] =
        db.select('PRAGMA user_version').first['user_version'];
    final bySubject = <String, int>{};
    for (final row in db.select(
        'SELECT subject_key, COUNT(*) AS c FROM questions GROUP BY subject_key')) {
      bySubject[(row['subject_key'] as String?) ?? ''] = row['c'] as int;
    }
    counts['questions_by_subject'] = bySubject;
    return counts;
  } finally {
    db.dispose();
  }
}

Future<Set<String>> _existingFingerprints(AppDatabase db) async {
  final query = db.selectOnly(db.questions)
    ..addColumns([db.questions.stemFingerprint]);
  final rows = await query.get();
  final result = <String>{};
  for (final row in rows) {
    final value = row.read(db.questions.stemFingerprint);
    if (value == null || value.trim().isEmpty) {
      continue;
    }
    result.add(value);
  }
  return result;
}

Future<Map<String, Object?>> migrationProbe({
  required File liveDb,
  required Directory tmpDir,
}) async {
  await tmpDir.create(recursive: true);
  final probe = File(tmpDir.path + Platform.pathSeparator + 'migrate_probe.db');
  if (await probe.exists()) {
    await probe.delete();
  }
  await liveDb.copy(probe.path);
  final before = readCounts(probe.path);
  final db = AppDatabase.forTesting(NativeDatabase(probe));
  try {
    final after = <String, Object?>{};
    after['user_version'] =
        (await db.customSelect('PRAGMA user_version').getSingle())
            .data
            .values
            .first;
    after['questions'] = (await db.select(db.questions).get()).length;
    after['question_options'] =
        (await db.select(db.questionOptions).get()).length;
    after['tags'] = (await db.select(db.tags).get()).length;
    after['object_tags'] = (await db.select(db.objectTags).get()).length;
    after['knowledge_points'] =
        (await db.select(db.knowledgePoints).get()).length;
    after['card_states'] = (await db.select(db.cardStates).get()).length;
    after['review_logs'] = (await db.select(db.reviewLogs).get()).length;
    after['review_group_plans'] =
        (await db.select(db.reviewGroupPlans).get()).length;
    after['attachments'] = (await db.select(db.attachments).get()).length;
    after['integrity_check'] =
        (await db.customSelect('PRAGMA integrity_check').getSingle())
            .data
            .values
            .first;
    return <String, Object?>{
      'before': before,
      'after': after,
      'same_questions': before['questions'] == after['questions'],
      'same_knowledge_points':
          before['knowledge_points'] == after['knowledge_points'],
      'same_card_states': before['card_states'] == after['card_states'],
      'same_review_logs': before['review_logs'] == after['review_logs'],
    };
  } finally {
    await db.close();
    // 演练副本里是用户数据，用完立刻删，别在 00-inbox 里留一份库。
    try {
      if (await probe.exists()) {
        await probe.delete();
      }
    } on Object catch (_) {
      // 删不掉也不影响演练结果；报告里不引用这个文件。
    }
  }
}

Future<File> backupLiveDb(File liveDb) async {
  final backupDir = Directory(_backupDirPath);
  await backupDir.create(recursive: true);
  final target = File(
    backupDir.path +
        Platform.pathSeparator +
        'furnace-before-import-' +
        _stampOf(DateTime.now()) +
        '.db',
  );
  await liveDb.copy(target.path);
  final sourceLength = await liveDb.length();
  final targetLength = await target.length();
  if (sourceLength != targetLength) {
    throw StateError('备份大小不一致：source=' +
        sourceLength.toString() +
        ' backup=' +
        targetLength.toString());
  }
  return target;
}

Future<int> saveMediaFor({
  required QuestionPackRecord record,
  required String questionId,
  required Map<String, Uint8List> mediaBytes,
  required QuestionMediaStore mediaStore,
  required List<String> warnings,
  required DateTime now,
}) async {
  var saved = 0;
  for (final media in record.media) {
    final bytes = mediaBytes[media.packPath];
    if (bytes == null) {
      warnings.add('配图在包里找不到：' + media.packPath);
      continue;
    }
    final recorded = media.fileName?.trim() ?? '';
    final fileName =
        recorded.isNotEmpty ? recorded : media.packPath.split('/').last;
    try {
      await mediaStore.save(
        questionId: questionId,
        fileName: fileName,
        bytes: bytes,
        mime: media.mime,
        sortOrder: media.sortOrder,
        role: media.role,
        now: now,
      );
      saved += 1;
    } on Object catch (error) {
      warnings.add('配图没存进题库目录：' + fileName + '：' + error.toString());
    }
  }
  return saved;
}

QuestionDraft draftOf(QuestionPackRecord record,
    {required Set<String> tagIds}) {
  final questionType = record.questionType.trim();
  final sourceLevel = record.sourceLevel.trim();
  final origin = record.origin.trim();
  final state = record.state.trim();
  return QuestionDraft(
    stem: record.stem,
    answer: _nullIfBlank(record.answer),
    solution: _nullIfBlank(record.solution),
    subjectKey: record.subjectKey.trim(),
    questionType: questionType.isEmpty ? 'solution' : questionType,
    sourceLevel: sourceLevel.isEmpty ? 'unknown' : sourceLevel,
    sourceLabel: record.sourceLabel.trim(),
    year: record.year,
    region: _nullIfBlank(record.region),
    sourceUrl: _nullIfBlank(record.sourceUrl),
    zujuanQuestionId: _nullIfBlank(record.zujuanQuestionId),
    zujuanBankId: _nullIfBlank(record.zujuanBankId),
    textFormat: record.textFormat,
    extensionOf: _nullIfBlank(record.extensionOf),
    capability: record.capability,
    difficulty: record.difficulty,
    difficultySource: _nullIfBlank(record.difficultySource),
    trapNote: _nullIfBlank(record.trapNote),
    origin: origin.isEmpty ? 'manual' : origin,
    state: state.isEmpty ? 'structured' : state,
    options: <QuestionOptionDraft>[
      for (final option in record.options)
        QuestionOptionDraft(
          label: option.label,
          content: option.content,
          isCorrect: option.isCorrect,
          sortOrder: option.sortOrder,
        ),
    ],
    tagIds: tagIds,
  );
}

Future<Map<String, Object?>> importPackFile({
  required File file,
  required AppDatabase db,
  required QuestionRepository questions,
  required QuestionMediaStore mediaStore,
  required Map<String, Tag> tagByPath,
}) async {
  final bytes = await file.readAsBytes();
  final archive = decodeQuestionPackArchive(bytes);
  final plan = planQuestionPackImport(
    records: archive.records,
    fingerprintOf: stemFingerprint,
    existingFingerprints: await _existingFingerprints(db),
    existingTagPaths: tagByPath.keys.toSet(),
    existingQuestionIdByZujuanQuestionId:
        await questions.questionIdsByZujuanQuestionId(),
  );
  final warnings = <String>[...plan.warnings];
  final failures = <String>[];
  final now = DateTime.now();
  var created = 0;
  var updated = 0;
  var skipped = 0;
  var mediaSaved = 0;
  for (final decision in plan.decisions) {
    final record = archive.records[decision.index];
    final human = decision.index + 1;
    final tagIds = <String>{};
    for (final raw in record.tagPaths) {
      final tag = tagByPath[raw.trim()];
      if (tag != null) {
        tagIds.add(tag.id);
      }
    }
    if (decision.action == QuestionPackAction.update) {
      final existingId = decision.existingQuestionId?.trim() ?? '';
      if (existingId.isEmpty) {
        failures.add('第 ' + human.toString() + ' 道题计划更新但没有题目 id');
        continue;
      }
      try {
        final changed = await questions.updateFromPack(
          questionId: existingId,
          stem: record.stem,
          answer: _nullIfBlank(record.answer),
          solution: _nullIfBlank(record.solution),
          subjectKey: _nullIfBlank(record.subjectKey),
          questionType: _nullIfBlank(record.questionType),
          sourceLevel: _nullIfBlank(record.sourceLevel),
          sourceLabel: _nullIfBlank(record.sourceLabel),
          year: record.year,
          region: _nullIfBlank(record.region),
          sourceUrl: _nullIfBlank(record.sourceUrl),
          zujuanQuestionId: _nullIfBlank(record.zujuanQuestionId),
          zujuanBankId: _nullIfBlank(record.zujuanBankId),
          textFormat: record.textFormat == 'markdown' ? 'markdown' : null,
          extensionOf: _nullIfBlank(record.extensionOf),
          capability: record.capability.isEmpty ? null : record.capability,
          difficulty: record.difficulty,
          difficultySource: _nullIfBlank(record.difficultySource),
          trapNote: _nullIfBlank(record.trapNote),
          origin: _nullIfBlank(record.origin),
          state: _nullIfBlank(record.state),
          options: <QuestionOptionDraft>[
            for (final option in record.options)
              QuestionOptionDraft(
                label: option.label,
                content: option.content,
                isCorrect: option.isCorrect,
                sortOrder: option.sortOrder,
              ),
          ],
          additionalTagIds: tagIds,
          now: now,
        );
        if (changed == 0) {
          failures.add(
              '第 ' + human.toString() + ' 道题要更新的原题（' + existingId + '）已不在题库');
          continue;
        }
        final roles = <String>{
          for (final media in record.media)
            if (media.role.trim().isNotEmpty) media.role.trim(),
        };
        if (roles.isNotEmpty) {
          await mediaStore.deleteForQuestion(existingId, roles: roles);
        }
        updated += 1;
        mediaSaved += await saveMediaFor(
          record: record,
          questionId: existingId,
          mediaBytes: archive.mediaBytes,
          mediaStore: mediaStore,
          warnings: warnings,
          now: now,
        );
      } on Object catch (error) {
        failures.add('第 ' + human.toString() + ' 道题没更新：' + error.toString());
      }
      continue;
    }
    if (decision.action != QuestionPackAction.create) {
      skipped += 1;
      continue;
    }
    try {
      final result = await questions.ingest(
        draftOf(record, tagIds: tagIds),
        now: now,
      );
      if (!result.created) {
        skipped += 1;
        continue;
      }
      created += 1;
      mediaSaved += await saveMediaFor(
        record: record,
        questionId: result.question.id,
        mediaBytes: archive.mediaBytes,
        mediaStore: mediaStore,
        warnings: warnings,
        now: now,
      );
    } on Object catch (error) {
      failures.add('第 ' + human.toString() + ' 道题没导入：' + error.toString());
    }
  }
  return <String, Object?>{
    'file': file.path.split(Platform.pathSeparator).last,
    'records': archive.records.length,
    'manifest_question_count': archive.manifest.questionCount,
    'media_in_pack': archive.mediaBytes.length,
    'created': created,
    'updated': updated,
    'skipped': skipped,
    'media_saved': mediaSaved,
    'warnings': warnings.length,
    'failures': failures.length,
    'failure_samples': failures.take(10).toList(),
  };
}

Future<String> ensureTagPath(
  TagRepository tags,
  String path,
  Map<String, String> cache,
) async {
  final cached = cache[path];
  if (cached != null) {
    return cached;
  }
  final existing = await tags.getTagByPath(path);
  if (existing != null) {
    cache[path] = existing.id;
    return existing.id;
  }
  final segments = path.split('/');
  String? parentId;
  var current = '';
  for (final segment in segments) {
    current = current.isEmpty ? segment : current + '/' + segment;
    final known = cache[current];
    if (known != null) {
      parentId = known;
      continue;
    }
    final found = await tags.getTagByPath(current);
    if (found != null) {
      cache[current] = found.id;
      parentId = found.id;
      continue;
    }
    final createdTag = await tags.createTag(name: segment, parentId: parentId);
    cache[current] = createdTag.id;
    parentId = createdTag.id;
  }
  return parentId!;
}

Future<Map<String, Object?>> rebuildTags(
  AppDatabase db,
  TagRepository tags,
) async {
  final beforeTags = (await db.select(db.tags).get()).length;
  final beforeLinks = (await db.select(db.objectTags).get()).length;
  final beforePlans = (await db.select(db.reviewGroupPlans).get()).length;
  await db.transaction(() async {
    await db.delete(db.objectTags).go();
    await db.delete(db.reviewGroupPlans).go();
    await db.delete(db.tags).go();
  });
  final cache = <String, String>{};
  for (final path in _tagSpec) {
    await ensureTagPath(tags, path, cache);
  }
  final all = await tags.getAllTags();
  final byRoot = <String, int>{};
  for (final tag in all) {
    final path = tag.path ?? '';
    final root = path.split('/').first;
    byRoot[root] = (byRoot[root] ?? 0) + 1;
  }
  return <String, Object?>{
    'deleted_tags': beforeTags,
    'deleted_object_tags': beforeLinks,
    'deleted_review_group_plans': beforePlans,
    'created_tags': all.length,
    'created_leaf_paths': _tagSpec.length,
    'tags_by_root': byRoot,
  };
}

String? classifySubject(String title) {
  var best = '';
  var bestScore = 0;
  var tied = false;
  for (final entry in _weakKeywords.entries) {
    var score = 0;
    for (final keyword in entry.value) {
      if (title.contains(keyword)) {
        score += 1;
      }
    }
    for (final keyword in _strongKeywords[entry.key] ?? const <String>[]) {
      if (title.contains(keyword)) {
        score += 3;
      }
    }
    if (score > bestScore) {
      best = entry.key;
      bestScore = score;
      tied = false;
    } else if (score == bestScore && score > 0) {
      tied = true;
    }
  }
  if (bestScore == 0 || tied) {
    return null;
  }
  return best;
}

Future<Map<String, Object?>> attachQuestionTags(
  AppDatabase db,
  TagRepository tags,
  Map<String, String> subjectTagId,
) async {
  final rows = await db.select(db.questions).get();
  final bySubject = <String, List<String>>{};
  final untagged = <String>[];
  for (final row in rows) {
    final subject = row.subjectKey.trim();
    final tagId = subjectTagId[subject];
    if (tagId == null || subject.isEmpty) {
      untagged.add(row.id);
      continue;
    }
    bySubject.putIfAbsent(subject, () => <String>[]).add(row.id);
  }
  var attached = 0;
  for (final entry in bySubject.entries) {
    attached += await tags.addTagToObjects(
      tagId: subjectTagId[entry.key]!,
      objectIds: entry.value,
      objectType: kQuestionObjectType,
    );
  }
  return <String, Object?>{
    'questions_total': rows.length,
    'questions_with_subject_tag': attached,
    'questions_without_known_subject': untagged.length,
  };
}

Future<Map<String, Object?>> attachKnowledgePointTags(
  AppDatabase db,
  TagRepository tags,
  Map<String, String> subjectTagId,
) async {
  final rows = await db.select(db.knowledgePoints).get();
  final bySubject = <String, List<String>>{};
  final unmapped = <String>[];
  for (final row in rows) {
    final subject = classifySubject(row.title);
    final tagId = subject == null ? null : subjectTagId[subject];
    if (subject == null || tagId == null) {
      unmapped.add(row.title);
      continue;
    }
    bySubject.putIfAbsent(subject, () => <String>[]).add(row.id);
  }
  var attached = 0;
  for (final entry in bySubject.entries) {
    attached += await tags.addTagToObjects(
      tagId: subjectTagId[entry.key]!,
      objectIds: entry.value,
      objectType: kKnowledgePointObjectType,
    );
  }
  return <String, Object?>{
    'knowledge_points_total': rows.length,
    'knowledge_points_tagged': attached,
    'knowledge_points_unmapped': unmapped.length,
    'unmapped_samples': unmapped.take(20).toList(),
  };
}

Future<Map<String, Object?>> attachCapabilityTags(
  AppDatabase db,
  TagRepository tags,
  Map<String, String> capabilityTagId,
) async {
  final rows = await db.select(db.questions).get();
  final byCode = <String, List<String>>{};
  for (final row in rows) {
    final codes = decodeQuestionCapability(row.capability);
    for (final code in codes) {
      if (capabilityTagId.containsKey(code)) {
        byCode.putIfAbsent(code, () => <String>[]).add(row.id);
      }
    }
  }
  var attached = 0;
  for (final entry in byCode.entries) {
    attached += await tags.addTagToObjects(
      tagId: capabilityTagId[entry.key]!,
      objectIds: entry.value,
      objectType: kQuestionObjectType,
    );
  }
  return <String, Object?>{
    'questions_with_capability_tags': attached,
    'capability_codes_used': byCode.keys.toList(),
  };
}

Future<Map<String, Object?>> driftCounts(AppDatabase db) async {
  final questions = await db.select(db.questions).get();
  final bySubject = <String, int>{};
  for (final row in questions) {
    final subject = row.subjectKey.trim();
    bySubject[subject] = (bySubject[subject] ?? 0) + 1;
  }
  final links = await db.select(db.objectTags).get();
  final byObjectType = <String, int>{};
  for (final row in links) {
    byObjectType[row.objectType] = (byObjectType[row.objectType] ?? 0) + 1;
  }
  return <String, Object?>{
    'questions': questions.length,
    'questions_by_subject': bySubject,
    'question_options': (await db.select(db.questionOptions).get()).length,
    'tags': (await db.select(db.tags).get()).length,
    'object_tags': links.length,
    'object_tags_by_type': byObjectType,
    'knowledge_points': (await db.select(db.knowledgePoints).get()).length,
    'card_states': (await db.select(db.cardStates).get()).length,
    'review_logs': (await db.select(db.reviewLogs).get()).length,
    'review_group_plans': (await db.select(db.reviewGroupPlans).get()).length,
    'attachments': (await db.select(db.attachments).get()).length,
    'question_serial_counters':
        (await db.select(db.questionSerialCounters).get()).length,
  };
}

void writeReport({
  required File jsonFile,
  required File mdFile,
  required Map<String, Object?> report,
}) {
  jsonFile.writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(report),
    encoding: utf8,
  );
  final buffer = StringBuffer()
    ..writeln('# 真实库导入 + 标签重建报告')
    ..writeln()
    ..writeln('- 生成时间：' + (report['generated_at'] as String? ?? ''))
    ..writeln('- 模式：' + (report['mode'] as String? ?? ''))
    ..writeln('- 真实库：' + (report['live_db'] as String? ?? ''))
    ..writeln('- 备份：' + (report['backup'] as String? ?? '（未创建）'))
    ..writeln('- 迁移演练：' + (report['migration_probe_ok'] == true ? '通过' : '失败'))
    ..writeln()
    ..writeln('## 1. 导入前后')
    ..writeln()
    ..writeln('| 项 | 导入前 | 导入后/最终 |')
    ..writeln('|---|---|---|');
  final before =
      (report['before'] as Map<String, Object?>?) ?? <String, Object?>{};
  final finalCounts =
      (report['final_counts'] as Map<String, Object?>?) ?? <String, Object?>{};
  final afterImport =
      (report['after_import_counts'] as Map<String, Object?>?) ??
          <String, Object?>{};
  for (final key in <String>[
    'questions',
    'question_options',
    'tags',
    'object_tags',
    'knowledge_points',
    'card_states',
    'review_logs',
    'review_group_plans',
    'attachments',
    'user_version',
  ]) {
    buffer.writeln('| ' +
        key +
        ' | ' +
        (before[key]?.toString() ?? '-') +
        ' | ' +
        ((finalCounts[key] ?? afterImport[key])?.toString() ?? '-') +
        ' |');
  }
  buffer
    ..writeln()
    ..writeln('分科题目数（最终）：' +
        jsonEncode(report['final_questions_by_subject'] ?? <String, Object?>{}))
    ..writeln()
    ..writeln('## 2. 逐包导入')
    ..writeln()
    ..writeln('| 包 | 记录 | created | updated | skipped | media | failures |')
    ..writeln('|---|---|---|---|---|---|---|');
  final packages = (report['packages'] as List<Object?>?) ?? <Object?>[];
  for (final raw in packages) {
    final row = raw as Map<String, Object?>;
    buffer.writeln('| ' +
        (row['file']?.toString() ?? '') +
        ' | ' +
        (row['records']?.toString() ?? '') +
        ' | ' +
        (row['created']?.toString() ?? '') +
        ' | ' +
        (row['updated']?.toString() ?? '') +
        ' | ' +
        (row['skipped']?.toString() ?? '') +
        ' | ' +
        (row['media_saved']?.toString() ?? '') +
        ' | ' +
        (row['failures']?.toString() ?? '') +
        ' |');
  }
  buffer
    ..writeln()
    ..writeln('## 3. 标签重建')
    ..writeln()
    ..writeln(jsonEncode(report['tag_rebuild'] ?? <String, Object?>{}))
    ..writeln()
    ..writeln('## 4. 挂标签')
    ..writeln()
    ..writeln(
        '- 题目：' + jsonEncode(report['question_tags'] ?? <String, Object?>{}))
    ..writeln('- 知识点：' +
        jsonEncode(report['knowledge_point_tags'] ?? <String, Object?>{}))
    ..writeln(
        '- 能力点：' + jsonEncode(report['capability_tags'] ?? <String, Object?>{}))
    ..writeln()
    ..writeln('## 5. 失败 / 跳过原因')
    ..writeln()
    ..writeln('- 导入失败样本：' +
        jsonEncode(report['import_failure_samples'] ?? <Object?>[]))
    ..writeln('- 跳过总数：' + (report['skipped_total']?.toString() ?? '0'))
    ..writeln()
    ..writeln('## 6. 完整性')
    ..writeln()
    ..writeln('- user_version（最终）：' +
        (report['user_version_after']?.toString() ?? ''))
    ..writeln(
        '- integrity_check：' + (report['integrity_check']?.toString() ?? ''))
    ..writeln('- 注意：knowledge_points / card_states / review_logs 未写入。');
  mdFile.writeAsStringSync(buffer.toString(), encoding: utf8);
}

void main() {
  final mode = Platform.environment[_liveFlag];
  final enabled = mode == '1' || mode == 'dry';

  test(
    'live load local question packs into the real database and rebuild tags',
    () async {
      if (!enabled) {
        // ignore: avoid_print
        print('skipped: set ' +
            _liveFlag +
            '=dry (rehearsal) or =1 (real writes) to run');
        return;
      }
      final dryRun = mode == 'dry';
      void say(Object? message) => print(message); // ignore: avoid_print

      final appData = Platform.environment['APPDATA'];
      if (appData == null || appData.isEmpty) {
        fail('APPDATA 不存在，无法定位真实库');
      }
      final liveDb = File(appData + r'\FirsryFan\Furnace\furnace.db');
      if (!liveDb.existsSync()) {
        fail('真实库不存在：' + liveDb.path);
      }
      final packsDir = Directory(_packsDirPath);
      if (!packsDir.existsSync()) {
        fail('题库包目录不存在：' + packsDir.path);
      }
      final processedPack = File(_processedPackPath);
      if (!processedPack.existsSync()) {
        fail('processed 包不存在：' + processedPack.path);
      }

      final startedAt = DateTime.now();
      say('LIVE mode=' + (dryRun ? 'dry' : 'real') + ' db=' + liveDb.path);

      // 1) 备份（写真实库之前必须成功）。
      final backup = await backupLiveDb(liveDb);
      say('BACKUP ' + backup.path + ' bytes=' + backup.lengthSync().toString());

      // 2) 迁移演练：只碰副本。
      final tmpDir = Directory(_workspaceRoot + r'\00-inbox\_tmp');
      final probe = await migrationProbe(liveDb: liveDb, tmpDir: tmpDir);
      final probeOk = probe['same_questions'] == true &&
          probe['same_knowledge_points'] == true &&
          probe['same_card_states'] == true &&
          probe['same_review_logs'] == true;
      say('MIGRATION_PROBE ok=' +
          probeOk.toString() +
          ' before_version=' +
          ((probe['before'] as Map<String, Object?>)['user_version']
                  ?.toString() ??
              '?') +
          ' after_version=' +
          ((probe['after'] as Map<String, Object?>)['user_version']
                  ?.toString() ??
              '?'));
      expect(probeOk, isTrue, reason: '迁移演练行数不一致，停止');

      final report = <String, Object?>{
        'generated_at': DateTime.now().toIso8601String(),
        'mode': dryRun ? 'dry' : 'real',
        'live_db': liveDb.path,
        'backup': backup.path,
        'migration_probe': probe,
        'migration_probe_ok': probeOk,
        'started_at': startedAt.toIso8601String(),
        'before': readCounts(liveDb.path),
      };

      if (dryRun) {
        report['final_counts'] = report['before'];
        report['note'] = 'dry-run：只备份+迁移演练+统计，没有写真实库';
        final jsonFile = File(_reportDirPath +
            r'\load-library-report-' +
            _stampOf(startedAt) +
            '-dryrun.json');
        final mdFile = File(_reportDirPath +
            r'\load-library-report-' +
            _stampOf(startedAt) +
            '-dryrun.md');
        writeReport(jsonFile: jsonFile, mdFile: mdFile, report: report);
        say('REPORT ' + mdFile.path);
        return;
      }

      // 3) 打开真实库（触发 v35 -> v43 迁移）。
      final realSupportDir = Directory(appData + r'\FirsryFan\Furnace');
      final db = AppDatabase.forTesting(NativeDatabase(liveDb));
      try {
        final versionAfterOpen =
            (await db.customSelect('PRAGMA user_version').getSingle())
                .data
                .values
                .first;
        say('REAL_DB_OPENED user_version=' + versionAfterOpen.toString());
        expect(versionAfterOpen, 43, reason: '真实库没有迁移到 v43');

        final questions = QuestionRepository(db);
        final mediaStore = QuestionMediaStore(
          database: db,
          supportDirectory: () async => realSupportDir,
        );
        final tags = TagRepository(db);

        final tagByPath = <String, Tag>{};
        for (final tag in await tags.getAllTags()) {
          final path = tag.path?.trim() ?? '';
          if (path.isNotEmpty) {
            tagByPath[path] = tag;
          }
        }

        // 4) 导入：散包按文件名时间序，processed 包最后（它是最新的清洗版）。
        final files = packsDir
            .listSync()
            .whereType<File>()
            .where((file) => file.path.toLowerCase().endsWith('.tqb'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
        files.add(processedPack);
        final packageResults = <Map<String, Object?>>[];
        for (final file in files) {
          final result = await importPackFile(
            file: file,
            db: db,
            questions: questions,
            mediaStore: mediaStore,
            tagByPath: tagByPath,
          );
          packageResults.add(result);
          say('PACK ' +
              (result['file']?.toString() ?? '') +
              ' created=' +
              result['created'].toString() +
              ' updated=' +
              result['updated'].toString() +
              ' skipped=' +
              result['skipped'].toString() +
              ' media=' +
              result['media_saved'].toString() +
              ' failures=' +
              result['failures'].toString());
        }
        report['packages'] = packageResults;
        report['after_import_counts'] = await driftCounts(db);

        // 5) 清空并重建标签树。
        final tagRebuild = await rebuildTags(db, tags);
        report['tag_rebuild'] = tagRebuild;
        say('TAGS rebuilt created=' +
            tagRebuild['created_tags'].toString() +
            ' deleted_old=' +
            tagRebuild['deleted_tags'].toString());

        final subjectTagId = <String, String>{};
        final capabilityTagId = <String, String>{};
        for (final entry in _subjectTagPath.entries) {
          final tag = await tags.getTagByPath(entry.value);
          if (tag != null) {
            subjectTagId[entry.key] = tag.id;
          }
        }
        for (final entry in _capabilityTagPath.entries) {
          final tag = await tags.getTagByPath(entry.value);
          if (tag != null) {
            capabilityTagId[entry.key] = tag.id;
          }
        }

        // 6) 挂标签：题目按学科；知识点按标题关键词（安全规则，判断不了不挂）。
        report['question_tags'] = await attachQuestionTags(
          db,
          tags,
          subjectTagId,
        );
        report['knowledge_point_tags'] = await attachKnowledgePointTags(
          db,
          tags,
          subjectTagId,
        );
        report['capability_tags'] = await attachCapabilityTags(
          db,
          tags,
          capabilityTagId,
        );

        // 7) 最终统计与完整性。
        final finalCounts = await driftCounts(db);
        report['final_counts'] = finalCounts;
        report['final_questions_by_subject'] =
            finalCounts['questions_by_subject'];
        report['skipped_total'] = packageResults.fold<int>(
          0,
          (sum, row) => sum + ((row['skipped'] as int?) ?? 0),
        );
        report['import_failure_samples'] = <Object?>[
          for (final row in packageResults)
            for (final sample in (row['failure_samples'] as List<Object?>? ??
                const <Object?>[]))
              sample,
        ];
        report['user_version_after'] = versionAfterOpen;
        report['integrity_check'] =
            (await db.customSelect('PRAGMA integrity_check').getSingle())
                .data
                .values
                .first;
      } finally {
        await db.close();
      }

      final jsonFile = File(_reportDirPath +
          r'\load-library-report-' +
          _stampOf(startedAt) +
          '.json');
      final mdFile = File(_reportDirPath +
          r'\load-library-report-' +
          _stampOf(startedAt) +
          '.md');
      writeReport(jsonFile: jsonFile, mdFile: mdFile, report: report);
      say('REPORT ' + mdFile.path);
      say('SUMMARY ' +
          jsonEncode(<String, Object?>{
            'questions_before':
                (report['before'] as Map<String, Object?>)['questions'],
            'questions_after':
                (report['final_counts'] as Map<String, Object?>)['questions'],
            'tags_after':
                (report['final_counts'] as Map<String, Object?>)['tags'],
            'object_tags_after':
                (report['final_counts'] as Map<String, Object?>)['object_tags'],
            'integrity': report['integrity_check'],
          }));
    },
    timeout: const Timeout(Duration(minutes: 15)),
  );
}
