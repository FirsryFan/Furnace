import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 守卫：到期日只有一个权威（FSRS）。
///
/// `docs/GAP_ANALYSIS.md` 的 D9 与 `docs/MILESTONES.md` 都把 SM-2 定成"模块保留为存档
/// 文件、不再被调用"：`lib/domain/services/srs/sm2_scheduler.dart` 留在仓库里（算法与它的
/// 单测照常跑），但 `lib/` 里不许再有第二个调用点 —— 否则 `card_states.due_at` 就有了第二个
/// 写者，而"一张表的一列只有一个写者"是 `docs/MINDNET_ROADMAP.md` 第 3 节末尾列出的纪律。
///
/// 轮次六十七把最后一个调用点删掉了（`features/anki/application/anki_service.dart`，以及只被
/// 它用到的 `features/anki/presentation/anki_page.dart` —— 那两个文件都没有任何入口，
/// 旧复习流早已被 `features/anki/presentation/review_page.dart` + `review_service.dart` 取代）。
/// 这个测试保证它不会悄悄回来。
void main() {
  test('lib/ 里除了存档文件本身，没有任何代码提到 Sm2Scheduler', () {
    final lib = Directory('lib');
    expect(
      lib.existsSync(),
      isTrue,
      reason: 'flutter test 的工作目录应当是 app/（找不到 lib/）',
    );

    const archive = 'lib/domain/services/srs/sm2_scheduler.dart';
    expect(
      File(archive).existsSync(),
      isTrue,
      reason: '存档文件被删了？D9 要的是"保留但不调用"，删它得先改文档',
    );

    final offenders = <String>[];
    for (final entity in lib.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) {
        continue;
      }
      final path = entity.path.replaceAll(r'\', '/');
      if (path == archive) {
        continue;
      }
      if (entity.readAsStringSync().contains('Sm2Scheduler')) {
        offenders.add(path);
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: '这些文件还在调用存档的 SM-2：$offenders',
    );
  });
}
