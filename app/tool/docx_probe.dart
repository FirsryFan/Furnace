/// 一次性探针：把「组卷 → .docx」装配层用真实文件跑一遍，产出样张给 Word 验收。
///
/// 不属于单测：它依赖本机外部目录（图片素材、输出目录），且验收靠 Word COM。
/// 验收流程与结论见 docs/DOCX_EXPORT_DESIGN.md「Word 真测」一节。
///
/// 用法（在 app 目录）：
///   dart run tool/docx_probe.dart <素材目录> <输出文件> [--no-math]
library;

import 'dart:io';

import 'package:furnace/data/media/image_size.dart';
import 'package:furnace/domain/services/export/omml/omml.dart';
import 'package:furnace/domain/services/export/paper_docx.dart';
import 'package:furnace/domain/services/paper/paper_composer.dart';

/// 把 LaTeX 编成 OMML；编不动就退回原文并打印原因（与生产接线同口径）。
String Function(String tex, {int? sizeHalfPt}) _mathCompiler(
    List<String> failures) {
  return (String tex, {int? sizeHalfPt}) {
    try {
      return compileLatexToOmml(tex, sizeHalfPt: sizeHalfPt);
    } on LatexError catch (error) {
      failures.add('$tex → ${error.message}');
      return tex;
    }
  };
}

Future<PaperDocxImage?> _loadImage(String path) async {
  final file = File(path);
  if (!file.existsSync()) {
    stderr.writeln('配图缺失：$path');
    return null;
  }
  final bytes = await file.readAsBytes();
  final info = readImageInfo(bytes);
  if (info == null) {
    stderr.writeln('认不出图片格式：$path');
    return null;
  }
  return PaperDocxImage(
    bytes: bytes,
    extension: info.format.extension,
    pixelWidth: info.size.width,
    pixelHeight: info.size.height,
    fileName: path.split(Platform.pathSeparator).last,
  );
}

PaperItem _item(String id, {String kp = 'kp1', String reason = '危险区，优先补'}) {
  return PaperItem(
    questionId: id,
    subjectKey: 'math',
    sourceLevel: 'gaokao',
    questionType: 'solution',
    knowledgePointId: kp,
    matchedKnowledgePointIds: <String>[kp],
    zone: PaperZone.danger,
    need: 0.9,
    quality: 0.72,
    score: 0.81,
    reasonZh: reason,
    improvementNote: '先把定义域与单调性的判据写完整',
    backgroundZh: '文化课 / 数学 / 函数与导数',
  );
}

Future<void> main(List<String> args) async {
  if (args.length < 2) {
    stderr
        .writeln('用法：dart run tool/docx_probe.dart <素材目录> <输出文件> [--no-math]');
    exitCode = 64;
    return;
  }
  final materialDir = args[0];
  final outputPath = args[1];
  final useMath = !args.contains('--no-math');

  final figure = await _loadImage(
    '$materialDir${Platform.pathSeparator}figure-640x360.png',
  );
  final tall = await _loadImage(
    '$materialDir${Platform.pathSeparator}tall-300x900.png',
  );
  // 答案截图（v27 role=answer）：有素材才嵌，没有就当这题没有答案图。
  final answerShot = await _loadImage(
    '$materialDir${Platform.pathSeparator}answer-620x860.png',
  );

  final failures = <String>[];
  final plan = PaperPlan(
    items: <PaperItem>[
      _item('q-formula'),
      _item('q-tall', kp: 'kp2', reason: '发展区，练精度'),
      _item('q-plain', kp: 'kp3', reason: '健康区，保持手感'),
    ],
    uncoveredKnowledgePointIds: const <String>['kp9'],
    deferredKnowledgePointIds: const <String>['kp8'],
    byKnowledgePoint: const <String, int>{'kp1': 1, 'kp2': 1, 'kp3': 1},
    candidateCount: 12,
    requestedCount: 3,
    overallNeed: 0.86,
    weights: const PaperWeights(),
  );

  final questions = <String, PaperDocxQuestion>{
    'q-formula': PaperDocxQuestion(
      questionId: 'q-formula',
      serialNo: 'TR-00001',
      stem: r'已知函数 $f(x)=x^{2}-2x+3$，求其单调区间，并说明 $f(x)$ 在 $[0,3]$ 上的最值。',
      subjectKey: 'math',
      sourceLevel: 'gaokao',
      sourceLabel: '2026 届高三上期末',
      year: 2026,
      region: '江苏',
      questionType: 'solution',
      options: const <PaperDocxOption>[
        PaperDocxOption(label: 'A', content: r'在 $(-\infty,1)$ 上单调递减'),
        PaperDocxOption(
          label: 'B',
          content: r'在 $(1,+\infty)$ 上单调递增',
          isCorrect: true,
        ),
      ],
      answer: r'$f(x)$ 在 $(-\infty,1]$ 上递减、在 $[1,+\infty)$ 上递增；'
          r'$[0,3]$ 上最小值为 $2$、最大值为 $6$。',
      solution: r'配方得 $f(x)=(x-1)^{2}+2$，对称轴 $x=1$；'
          r'区间端点与顶点比较得最值。',
      images: <PaperDocxImage>[if (figure != null) figure],
      answerImages: <PaperDocxImage>[if (answerShot != null) answerShot],
    ),
    'q-tall': PaperDocxQuestion(
      questionId: 'q-tall',
      serialNo: 'TR-00002',
      stem: r'如图，在四棱锥 $P-ABCD$ 中，底面 $ABCD$ 是边长为 2 的正方形，'
          r'且 $PA\perp$ 底面，求二面角 $P-BC-A$ 的余弦值。',
      subjectKey: 'math',
      sourceLevel: 'provincial_diagnostic',
      sourceLabel: '2026 届南京二模',
      year: 2026,
      region: '南京',
      questionType: 'solution',
      answer: r'二面角的余弦值为 $\frac{\sqrt{3}}{3}$。',
      solution: r'以 $A$ 为原点建系，面 $PBC$ 与面 $ABC$ 的法向量分别为 '
          r'$\vec{n}_{1}=(0,1,1)$、$\vec{n}_{2}=(0,0,1)$，再按二面角为锐角取正值。',
      images: <PaperDocxImage>[if (tall != null) tall],
    ),
    'q-plain': const PaperDocxQuestion(
      questionId: 'q-plain',
      stem: r'设数列 $\{a_{n}\}$ 满足 $a_{1}=1$，$a_{n+1}=2a_{n}+1$，求通项公式。',
      subjectKey: 'math',
      sourceLevel: 'elite_school',
      sourceLabel: '2026 届苏州中学周测',
      questionType: 'solution',
      answer: r'$a_{n}=2^{n}-1$。',
      solution: r'两边加 1 得 $a_{n+1}+1=2(a_{n}+1)$，故 $\{a_{n}+1\}$ '
          r'是首项 2、公比 2 的等比数列。',
    ),
  };

  final knowledgePointNames = <String, String>{
    'kp1': '二次函数与单调性',
    'kp2': '立体几何·二面角',
    'kp3': '数列递推',
    'kp8': '导数与不等式',
    'kp9': '概率统计',
  };

  final result = buildPaperDocx(
    plan: plan,
    questions: questions,
    knowledgePointNames: knowledgePointNames,
    mathCompiler: useMath ? _mathCompiler(failures) : null,
    footerText: 'Furnace · 2026-10-19',
    generatedAt: DateTime(2026, 10, 19, 5, 0),
    title: '高三数学·函数与立体几何专项卷',
  );

  final outFile = File(outputPath);
  await outFile.parent.create(recursive: true);
  await outFile.writeAsBytes(result.bytes, flush: true);

  stdout
    ..writeln('输出：${outFile.absolute.path}')
    ..writeln('大小：${result.bytes.length} 字节')
    ..writeln('题目：${result.questionCount} 道，段落 ${result.paragraphCount}，'
        '配图 ${result.imageCount} + 答案截图 ${result.answerImageCount}'
        '（跳过 ${result.imageSkippedCount}）')
    ..writeln('公式：${result.formulaCount} 处，失败 ${result.formulaFailureCount}')
    ..writeln(
        '缺失：题 ${result.missingQuestionCount} / 题干 ${result.missingStemCount} / '
        '答案 ${result.missingAnswerCount} / 解析 ${result.missingSolutionCount}')
    ..writeln('告警：${result.hasWarnings ? '有' : '无'}');
  for (final note in result.imageSkippedNotes) {
    stdout.writeln('  跳图：$note');
  }
  for (final failure in result.formulaFailures) {
    stdout.writeln('  公式失败：$failure');
  }
  for (final failure in failures) {
    stdout.writeln('  编译器报错：$failure');
  }
}
