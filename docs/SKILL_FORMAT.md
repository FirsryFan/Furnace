# `.fskill` 规范（skill 包格式）

> 状态：**规范已定，执行容器尚未实现**。本文档先固定格式与安全边界，
> 因为格式一旦被第三方 skill 采用就很难改；容器实现排在 AI 对话闭环之后
> （见 [AI_DESIGN.md](AI_DESIGN.md) §12 的 A7 阶段）。

---

## 1. 为什么是"包"，而不是"提示词"

用户的原始要求是"skill 主要是提示词包"，但真实例子证明不够。实测
`zujuan-finder` skill 的实际结构：

```
SKILL.md            21 KB   提示词/方法论
references/*.md     6 份    领域知识（URL 语法、原子格式、坑）
scripts/*.mjs       10 个   真正干活的 Node 脚本（含 25 KB 的 bridge.mjs）
extension/          MV3 浏览器扩展
node_modules/playwright-core
```

提示词只占一小部分，主体是**配套脚本 + 宿主能力**。所以 `.fskill` 必须能装下
这三样东西，否则"添加 skill 来扩展能力"就只是"改提示词"。

## 2. 包结构

`.fskill` 是一个 zip（与 `.kpak` / `.tfpkg` 同样的做法）。根目录固定：

```
manifest.json        必需
prompt.md            必需
tools/*.json         可选（该 skill 暴露给 AI 的粗粒度工具声明）
scripts/**           可选（Windows 上才执行）
references/**        可选（提示词引用的资料）
```

### 2.1 `manifest.json`

```jsonc
{
  "format": "fskill/1",              // 协议号。不匹配就拒绝载入，不做兼容猜测
  "name": "zujuan-finder",           // 唯一标识，小写与连字符
  "version": "1.0.0",
  "description": "到组卷网按条件找题并落盘",
  "platforms": ["windows"],          // 只声明支持的平台；Android 不会看到它
  "networkAllow": ["zujuan.xkw.com"],// 允许联网的域名。默认空 = 不允许联网
  "permissions": ["browser_bridge"], // 请求的宿主能力，见 §4
  "scripts": [
    {
      "name": "find_questions",      // 对应 tools/*.json 里的一个工具
      "entry": "scripts/find.mjs",
      "args": ["--subject", "--count"]   // 声明式参数，容器据此校验后再传
    }
  ]
}
```

`tools/*.json` 的每个文件是**一个工具的 JSON Schema 声明**，形状与内置工具相同
（`name` / `description` / `parameters`），这样审批引擎、风险分级、审计台账
对内置工具和 skill 工具完全一致（AI_DESIGN D11）。风险等级由 manifest 指定：

```jsonc
{
  "name": "find_questions",
  "description": "到组卷网按条件检索题目",
  "risk": "write",          // 只允许 write；destructive 一律拒绝（见 §5）
  "reversible": false,      // 跑脚本多半有外部副作用，必须逐条确认
  "parameters": { "type": "object", "properties": { /* ... */ } }
}
```

## 3. 执行模型

容器（`SkillContainer`）在 Windows 上执行脚本，规则如下。每条都是为了把
"给 AI 开 shell"的风险压回可控范围：

| 项 | 规则 |
| --- | --- |
| 进程 | 一次调用一个子进程；不常驻 |
| 工作目录 | 该 skill 的**私有目录**（`<appdata>/skills/<name>/`），不是用户目录 |
| 环境变量 | 最小化。**绝不注入 API key** —— 这条是硬要求，skill 无权拿到用户的模型凭证 |
| 文件读写 | 只允许 skill 私有目录 + 用户在每次调用时显式指定的输出目录 |
| 联网 | 默认拒绝。manifest 的 `networkAllow` 声明后，**首次运行由用户确认一次** |
| 超时 | 有上限；超时即杀进程并记为 failed |
| 输出 | 有大小上限；超限截断并标注 |
| 审计 | 每次执行写入 `ai_actions` 台账（工具名、参数、结果、耗时） |

**AI 永远不直接接触 shell 或文件系统**：它只能调用 skill 声明的粗粒度工具
（例如 `find_questions`），参数是领域概念，不是命令行。这样审批清单里出现的是
"找 10 道力学题"这种人话，而不是一串命令。

## 4. 宿主能力（permissions）

| 能力 | 含义 | 平台 |
| --- | --- | --- |
| `browser_bridge` | 复用用户**已登录**的桌面浏览器标签页 | 仅 Windows |
| `filesystem_write` | 写用户显式指定的输出目录 | Windows / Android 都不给 AI 直接权限，只给 skill 声明的脚本 |

未在 `permissions` 里申请的能力，容器不会提供。

## 5. 安全边界（不可协商的部分）

1. **`destructive` 的 skill 工具一律拒绝载入**。skill 不能声明删除类工具 —— 删除
   必须走内置工具，那里有 before 快照和逐条确认（AI_DESIGN D7 / D13b）。
2. **`reversible` 默认为 `false`**。skill 脚本可能有外部副作用，因此默认走
   "逐条确认"，与权限模式无关。想标 `true` 的 skill 必须能证明可撤回，目前
   没有这样的例子，所以实际上一律 false。
3. **不注入 API key**（§3）。skill 要联网就用自己的域名白名单，不能借用模型凭证。
4. **协议号不匹配就拒绝**。不做"尽力而为"的兼容 —— 静默按旧格式解释新包，
   是安全边界最容易破的地方。
5. **平台门控是声明式的**。Android 上没有 Node 运行时和桌面浏览器，所以
   `platforms` 里没有 `android` 的 skill 在手机上根本不出现在列表里，
   而不是运行时报错（AI_DESIGN D10）。

## 6. 与内置工具的关系

skill 工具与内置工具**同构**：同一个注册表、同一套风险分级、同一个审批引擎、
同一份审计台账。skill 只是"额外追加一批工具 + 一段提示词"。这样审批和审计
不需要两套逻辑，也不会出现"内置的会被审、skill 的不会"这种漏洞。

## 7. 分发

待定（尚未实现）。已知约束：

- skill 会随 `.tfpkg` 一起被带走吗？—— **不会**。`.tfpkg` 只转储数据库表；
  skill 是磁盘上的文件，需要单独分发。
- 是否要做导入界面？—— 需要，但排在容器实现之后。
