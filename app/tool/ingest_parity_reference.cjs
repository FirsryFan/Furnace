// INGEST 对拍第 1 步（参考实现侧）：把同一份材料信封跑成 MindNet JS 的产物。
//
// 用法（在 app 目录下）：
//   node tool/ingest_parity_reference.cjs [fixture.json] [js-out.json]
//
// 需要外部只读的 MindNet 检出（默认 E:/Document/MindNet，可用 MINDNET_SRC 覆盖）
// 与本机 node。对拍三步：本脚本 → `dart run tool/ingest_dump.dart` → 本目录的
// `ingest_parity_compare.cjs`。参考实现在 src/ingest.js 里自己写了"Dart 那边照抄 5 行"，
// 这个脚本就是那 5 行（以及整条流水线）的裁判。
const fs = require('fs');

const mindnet = process.env.MINDNET_SRC || 'E:/Document/MindNet';
const ingest = require(`${mindnet}/src/ingest.js`);

const fixture = process.argv[2] || 'E:/dsh-tmp-aot/mindnet-material-fixture.json';
const out = process.argv[3] || 'E:/dsh-tmp-aot/js-out.json';
const nowHours = Number(process.env.NOW_HOURS || 497321.25);

const env = JSON.parse(fs.readFileSync(fixture, 'utf8'));
const result = ingest.convert(env, { now_hours: nowHours });
fs.writeFileSync(out, JSON.stringify(result, null, 2));
console.log(`参考实现（${mindnet}）→ ${out}`);
