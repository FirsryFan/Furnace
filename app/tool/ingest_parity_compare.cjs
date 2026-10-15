// INGEST 对拍第 3 步（裁判）：逐字段比较 JS 参考实现与本仓库 Dart 端口的产物。
//
// 用法（在 app 目录下）：
//   node tool/ingest_parity_compare.cjs [js-out.json] [dart-out.json]
//
// 比较前先把 Dart 输出规约回 JS 形态 —— 只规约**有意差异**，别的差异一律报出来并 exit 1：
//   1. 节点 meta 多一个 margin_note（JS 的 meta 没有这个键；Node.from_object 会忽略未知键）
//   2. evidence.quote 用真的页边那一行（JS 恒为 null）
//   3. hub 的 region 写 `第 ? 页`（JS 插值出 `第 undefined 页`）
//   4. 汇总里不报"几张卡"（cards 是 INGEST §4 的可选呈现层，本层不做）
//   5. 不做 NFC 归一化（pubspec 里没有 Unicode 归一化依赖；输入已是 NFC 时逐字节一致）
const fs = require('fs');

const jsPath = process.argv[2] || 'E:/dsh-tmp-aot/js-out.json';
const dartPath = process.argv[3] || 'E:/dsh-tmp-aot/dart-out.json';
const js = JSON.parse(fs.readFileSync(jsPath, 'utf8'));
const dart = JSON.parse(fs.readFileSync(dartPath, 'utf8'));

for (const node of dart.graph_patch.nodes) {
  if (node.meta) delete node.meta.margin_note; // 差异 1
}
for (const action of dart.run_request.actions) {
  if (action.node && action.evidence) {
    action.evidence.quote = null; // 差异 2
    if (action.evidence.region === '第 ? 页') action.evidence.region = '第 undefined 页'; // 差异 3
  }
}
const jsSummary = js.summary.text.replace(/ \/ \d+ 张卡/, ''); // 差异 4

const differences = [];
function walk(a, b, path) {
  if (differences.length >= 40 || a === b) return;
  const ta = a === null ? 'null' : Array.isArray(a) ? 'array' : typeof a;
  const tb = b === null ? 'null' : Array.isArray(b) ? 'array' : typeof b;
  if (ta !== tb) {
    differences.push(`${path}: JS ${ta} vs Dart ${tb}`);
    return;
  }
  if (ta === 'array') {
    if (a.length !== b.length) {
      differences.push(`${path}: JS 长度 ${a.length} vs Dart ${b.length}`);
    }
    for (let i = 0; i < Math.max(a.length, b.length); i += 1) {
      walk(a[i], b[i], `${path}[${i}]`);
    }
    return;
  }
  if (ta === 'object') {
    for (const key of new Set([...Object.keys(a), ...Object.keys(b)])) {
      walk(a[key], b[key], `${path}.${key}`);
    }
    return;
  }
  differences.push(`${path}: JS ${JSON.stringify(a)} vs Dart ${JSON.stringify(b)}`);
}

walk(js.items, dart.items, 'items');
walk(js.graph_patch, dart.graph_patch, 'graph_patch');
walk(js.run_request, dart.run_request, 'run_request');
walk(jsSummary, dart.summary, 'summary');

console.log(
  `节点 ${dart.graph_patch.nodes.length} / 边 ${dart.graph_patch.edges.length} / ` +
    `动作 ${dart.run_request.actions.length} / 标准条目 ${dart.items.length}`,
);
if (differences.length === 0) {
  console.log('PARITY OK：五处有意差异之外，逐字段相同');
  process.exit(0);
}
console.log(`差异 ${differences.length} 处：`);
for (const line of differences) console.log('  ' + line);
process.exit(1);
