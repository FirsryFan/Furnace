/// DAG 图片落盘 store 的单元测试（2026-11-19）。
///
/// 钉住四件事：
///  1. 第一次真的生成并写进磁盘；第二次直接读缓存，不再渲染；
///  2. 缓存键：入库链用链 id；未入库的链按内容哈希，同内容同键、不同内容不同键；
///  3. 坏掉的缓存文件会被重画，不会长期占着键；
///  4. 目录不可用 / 空链时失败会带原因抛出，界面才能显示"失败 + 原因 + 重试"。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:furnace/domain/services/reasoning/capability_action.dart';
import 'package:furnace/domain/services/reasoning/reasoning_prompt.dart';
import 'package:furnace/features/questions/application/dag_image_renderer.dart';
import 'package:furnace/features/questions/data/dag_image_store.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('第一次生成并落盘；第二次直接读缓存（不再渲染）', () async {
    final root = _tempRoot();
    final renderer = _CountingRenderer();
    final store = DagImageStore(
      renderer: renderer,
      supportDirectory: () async => root,
    );

    final first = await store.ensure(
      cacheKey: 'rc-test-1',
      chain: _chain(),
      title: '思维 DAG',
    );
    expect(first.fromCache, isFalse);
    expect(first.isPng, isTrue);
    final file = File(p.join(
      root.path,
      DagImageStore.directoryName,
      'rc-test-1.png',
    ));
    expect(file.existsSync(), isTrue);
    expect(file.readAsBytesSync(), orderedEquals(first.bytes));
    expect(renderer.renders, 1);

    final second = await store.ensure(
      cacheKey: 'rc-test-1',
      chain: _chain(),
      title: '思维 DAG',
    );
    expect(second.fromCache, isTrue);
    expect(second.bytes, orderedEquals(first.bytes));
    expect(second.width, first.width);
    expect(second.height, first.height);
    expect(renderer.renders, 1, reason: '缓存命中时不应重新渲染');
  });

  test('缓存键：入库链用链 id；未入库链按内容哈希，同内容同键', () {
    final chain = _chain();
    expect(DagImageStore.cacheKeyOf('rc-123', chain), 'rc-123');
    expect(
      DagImageStore.cacheKeyOf(null, chain),
      DagImageStore.cacheKeyOf('  ', chain),
    );
    expect(
      DagImageStore.cacheKeyOf('', chain),
      startsWith('runtime-'),
    );

    final other = _chain(goalSuffix: '（换一条）');
    expect(
      DagImageStore.cacheKeyOf(null, chain),
      isNot(DagImageStore.cacheKeyOf(null, other)),
    );
  });

  test('坏掉的缓存文件会被删掉重画', () async {
    final root = _tempRoot();
    final renderer = _CountingRenderer();
    final store = DagImageStore(
      renderer: renderer,
      supportDirectory: () async => root,
    );
    final file = File(p.join(
      root.path,
      DagImageStore.directoryName,
      'rc-broken.png',
    ));
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(<int>[1, 2, 3, 4]); // 不是 PNG

    final result = await store.ensure(
      cacheKey: 'rc-broken',
      chain: _chain(),
      title: '思维 DAG',
    );

    expect(renderer.renders, 1);
    expect(result.fromCache, isFalse);
    expect(result.isPng, isTrue);
    expect(file.readAsBytesSync(), orderedEquals(result.bytes));
  });

  test('数据目录不可用：抛"读不到本机数据目录 + 原因"', () async {
    final store = DagImageStore(
      renderer: _CountingRenderer(),
      supportDirectory: () async =>
          throw const FileSystemException('模拟：数据盘不可写'),
    );

    await expectLater(
      store.ensure(cacheKey: 'rc-x', chain: _chain()),
      throwsA(
        isA<DagImageStoreException>().having(
          (error) => error.message,
          'message',
          allOf(contains('读不到本机数据目录'), contains('模拟：数据盘不可写')),
        ),
      ),
    );
  });

  test('空链：渲染异常原样抛出（带可读原因），不写文件', () async {
    final root = _tempRoot();
    final store = DagImageStore(
      renderer: DagImageRenderer(),
      supportDirectory: () async => root,
    );

    await expectLater(
      store.ensure(
        cacheKey: 'rc-empty',
        chain: const ParsedChain(summary: '', steps: []),
      ),
      throwsA(isA<DagImageRenderException>()),
    );
    final file = File(p.join(
      root.path,
      DagImageStore.directoryName,
      'rc-empty.png',
    ));
    expect(file.existsSync(), isFalse);
  });

  test('同一条链被同时要两次：只渲染一次', () async {
    final root = _tempRoot();
    final renderer = _CountingRenderer();
    final store = DagImageStore(
      renderer: renderer,
      supportDirectory: () async => root,
    );

    final results = await Future.wait(<Future<DagImageFile>>[
      store.ensure(cacheKey: 'rc-concurrent', chain: _chain()),
      store.ensure(cacheKey: 'rc-concurrent', chain: _chain()),
    ]);

    expect(renderer.renders, 1);
    expect(results[0].bytes, orderedEquals(results[1].bytes));
  });
}

// ---------------------------------------------------------------------------
// 测试夹具
// ---------------------------------------------------------------------------

Directory _tempRoot() {
  final root = Directory.systemTemp.createTempSync('furnace_dag_store_');
  addTearDown(() {
    if (root.existsSync()) {
      root.deleteSync(recursive: true);
    }
  });
  return root;
}

class _CountingRenderer extends DagImageRenderer {
  int renders = 0;

  @override
  Future<DagImageRenderResult> render(
    ParsedChain chain, {
    String title = '思维 DAG',
  }) {
    renders++;
    return super.render(chain, title: title);
  }
}

ParsedChain _chain({String goalSuffix = ''}) {
  return ParsedChain(
    summary: '先看清条件，再用韦达定理，最后回代检验。',
    steps: <ParsedStep>[
      ParsedStep(
        index: 1,
        goal: '看清方程系数$goalSuffix',
        actionType: 'first_principles',
        action: CapabilityAction.byKey('first_principles'),
        justification: '',
        checkMethod: '',
        stuckRisk: 0.3,
        knowledgeHints: const <String>[],
      ),
      ParsedStep(
        index: 2,
        goal: '用韦达定理求两根之和$goalSuffix',
        actionType: 'sanity_check',
        action: CapabilityAction.byKey('sanity_check'),
        justification: '',
        checkMethod: '',
        stuckRisk: 0.7,
        knowledgeHints: const <String>[],
      ),
    ],
  );
}
