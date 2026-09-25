# Furnace AI 集成设计（v1，待批注）

> 状态：**待用户批注**。本文件是讨论结论的落地版，用户可直接在文中修改。
> 决策标准（用户给定，冲突时按此优先级压）：
> **① 可行性 + 安全性 → ② 使用效果最大化 → ③ 方案最简。**
>
> 本文中每个决策都标注了依据，凡是"我替你拍的"都写明理由，你觉得不对可以直接划掉。

---

## 0. 用户已明确的要求（不再是待议项）

| # | 要求 | 出处 |
| --- | --- | --- |
| 1 | 单独的对话界面 + 单独的对话存储；输入框**不**加 AI 整理 | 用户 2026-09-25 |
| 2 | AI 深度集成到软件各部分，能代替用户做繁琐操作；批量处理要容易 | 同上 |
| 3 | 模型走 **API**（不做 Ollama） | 同上 |
| 4 | AI **能改数据**，但要有 approve；且有用户可选的**权限模式** | 同上 |
| 5 | 上下文走 **agent loop**（具体设计暂缓，见 §10） | 同上 |
| 6 | **不做插件化**；用户扩展能力的唯一途径是 **skill**；skill 本质是提示词包，但要配上标准 agent 能力 | 同上 |
| 7 | API key **明文存**（个人自用，图方便） | 同上 |
| 8 | AI **默认关闭**；设置里填好 key 完成接入后才出现对话界面（作为独立界面） | 同上 |

---

## 1. 安全与可行性：先摆清楚这个 app 现在是什么

**实测事实**（aapt2 读已构建 APK，非推测）：

```
uses-permission: POST_NOTIFICATIONS / RECEIVE_BOOT_COMPLETED / VIBRATE
→ 没有 INTERNET 权限
```

也就是说，"默认不联网"目前是**操作系统强制的**，不是靠应用自觉。`pubspec.yaml` 也确实零网络依赖。

**接入 AI 必须新增 `INTERNET` 权限**，这会：
- 让 Android 安装时的权限列表出现"网络访问"；
- 把"默认不联网"从**系统强制**降级为**应用自觉**；
- 使 `docs/PRIVACY.md` 的四条承诺（无遥测 / 默认不联网 / 无网络权限）**必须改写**。

**决策 D1**：接受这个降级，但用三条硬约束把它兜住：
1. **默认关闭**：没填 key 时，应用的行为与现在**完全一致**（代码路径不触发任何网络调用）。
2. **出网只有一处**：整个代码库里只有模型适配器一个地方能发起网络请求；工具层、skill 脚本默认**不联网**（例外见 §5 的域名白名单）。
3. **可核查**：设置页明确显示"AI 已开启，会向 api.deepseek.com 发送你输入的内容与工具调用所需的本地数据摘要"，不藏。

> 依据：用户选①优先级。全应用只有一个出网点，是让"AI 关掉 = 回到原状"这句话真正成立的最小结构。

---

## 2. 总体结构

```
┌─ 对话界面（独立页面 + 导航入口，仅在 AI 已接入时出现） ──────────┐
│  消息流 · 工具调用卡片 · 审批清单 · 执行结果                      │
└───────────────────────────┬─────────────────────────────────────┘
                            │
                 ┌──────────▼───────────┐
                 │   Agent Loop（暂缓    │  §10 只列约束，不做详细设计
                 │   详细设计）          │
                 └──────────┬───────────┘
        ┌───────────────────┼───────────────────┐
        │                   │                   │
┌───────▼────────┐ ┌────────▼────────┐ ┌────────▼─────────┐
│ 模型适配器      │ │ 工具注册表       │ │ 审批 / 权限引擎   │
│ ModelAdapter    │ │ ToolRegistry    │ │ ApprovalEngine   │
│ （唯一出网点）   │ │ （静态清单）      │ │                  │
└────────────────┘ └────────┬────────┘ └──────────────────┘
                            │  薄适配器，不写 SQL
                 ┌──────────▼───────────────────────────────┐
                 │ 现有 Repository 层（13 个，已测试）         │
                 │ + 能力容器 SkillContainer（§5）            │
                 └──────────┬───────────────────────────────┘
                            │ Riverpod provider
                 ┌──────────▼───────────┐
                 │ 主界面自动刷新         │  ← 不需要额外写刷新代码
                 └──────────────────────┘
```

**决策 D2（用户已确认）**：所有工具都是现有 `Repository` 的**薄包装**，不自己写 SQL。
两个好处（前者是"深度集成"能否成立的关键）：
- 所有仓库都经 Riverpod provider 装配，AI 与 UI 用同一批实例 → **AI 在对话页建了任务，Thread 页自己就变了**；
- 硬约束、权重归一化、FSRS 调度等业务规则只有一份实现，AI 改数据时自动继承，不会分叉出第二套逻辑。

---

## 3. 模型适配器（唯一出网点）

**决策 D3**：`ModelAdapter` 抽象接口 + 两个实现。

```dart
abstract class ModelAdapter {
  Stream<ModelEvent> runTurn({
    required List<ChatMessage> messages,
    required List<ToolSpec> tools,
  });
}
```

| 实现 | 用途 |
| --- | --- |
| `OpenAiCompatAdapter` | 真实调用。DeepSeek 官方 `https://api.deepseek.com`，协议是 OpenAI 兼容（已核实官方文档） |
| `FakeModelAdapter` | 测试用。脚本化返回固定的工具调用序列 |

**为什么用 OpenAI 兼容格式**：DeepSeek 官方就是这套（`tools:[{type:"function",function:{name,description,parameters}}]`，返回 `message.tool_calls[]`，回灌 `{role:"tool",tool_call_id,content}`）。附带好处：将来想换任何 OpenAI 兼容端点只改 `base_url`。

**决策 D4**：**不开 `strict` 模式**。它的约束是"每个 object 的所有属性都必须列为 required，且 `additionalProperties:false`" —— 我们的操作参数天然是"一部分必填、一部分可选"，为了 strict 去改造成 `anyOf` 会让 schema 更难懂。改为：**在 Dart 侧做参数校验**，校验失败时把错误作为工具结果回灌给模型让它重试。更简单，也更好测（依据③）。

**决策 D5**：不用 `deepseek-reasoner`（思维链模型）作为默认。
理由：工具调用场景下，思维链模型的输出更容易偏离工具格式，且更贵更慢。默认 `deepseek-chat`，模型名做成设置项。
—— 这条标注为**待实测**：等实现完我会实际跑一次对比，如果 reasoner 效果明显更好再改默认值。

---

## 4. 工具层

### 4.1 结构

```dart
/// 只有两类（见 §6.1 D12 v2）。原先的 lowRisk / highRisk 已合并。
enum ToolRisk { write, destructive }

class ToolSpec {
  final String name;
  final String description;          // 给模型看的，要写清楚何时用
  final Map<String, Object?> schema; // JSON Schema
  final ToolRisk risk;
  /// 能否可靠保存变更前快照并撤回。false 的工具一律逐条确认（见 D13b）。
  final bool reversible;
  final Set<Platform> platforms;     // 平台门控
  final Future<ToolResult> Function(Map<String, Object?> args, ToolContext ctx) run;
}
```

**决策 D6**：工具按**模块聚合**，不按单个 Repository 方法铺开。
仓库层有 60+ 个方法，全铺成工具会让模型在选工具这一步就开始犯错（选择过多）。改为每个模块 1–2 个工具，动作用 `action` 参数区分，且**每个 action 的必需参数在 description 里写清楚**。

预计 **15 个工具**：

| 模块 | 工具 | 风险 | reversible |
| --- | --- | --- | --- |
| 任务 | `query_tasks` / `manage_task`（create·update·delete·complete·start·add_dependency） | 增改=`write`；**删除=`destructive`** | create/complete/start ✅；update ✅（存旧值）；delete ✅（存整行）；add_dependency ✅ |
| 日程 | `query_schedule` / `manage_time_block`（create·update·delete） | 同上 | 同上 |
| 模板 | `manage_time_template`（create·apply） | `write` | ✅（apply 记录生成的行） |
| 标签 | `query_tags` / `manage_tag`（create·rename·move·delete·attach·detach） | **删除=`destructive`** | ✅ |
| 复习 | `query_review` / `submit_review` | `write` | ✅ |
| 知识点 | `manage_knowledge_point`（create·update·delete） | **删除=`destructive`** | ✅ |
| 工作区 | `export_workspace`（导出 `.tfpkg`） | `write` | ✅（删掉产出文件即可） |
| 统计 | `get_stats`（进度、完成率、排序结果解释） | 只读 | — |
| skill | `run_skill` / `list_skills` | 见 §5 | ⚠️ 见下 |

> **skill 的 reversible 是特例**：skill 脚本可能产生**外部副作用**（例如在组卷网上留下访问记录、
> 或写出用户目录之外的文件），无法可靠撤回。因此 `run_skill` 的 `reversible = false`，
> **在两种模式下都逐条确认**（依 D13b）。这不是保守，是能力边界：能撤回的才敢自动。

**决策 D7**：`destructive` 类工具**永远不进入自动执行**，无论用户选了哪个权限模式。删除必须逐条确认。
> 依据①：模型判断错一次，数据就没了。这条没有权衡余地。

### 4.2 只读工具的范围

**决策 D8**：`query_*` 这类只读工具默认返回**摘要而非全量**（例如任务列表默认最多 20 条、字段裁剪）。原因：全量数据塞进上下文会挤掉对话历史，而且费 token。需要更多时让模型带分页/筛选参数再查（这也正是用工具而不是"把数据塞进 prompt"的价值所在）。

---

## 5. skill 与能力容器

### 5.1 为什么需要"容器"而不是"给 AI 开 shell"

用户的例子（组卷网找题 → 认知模型判质量 → 生成题文 → 加入计划）里，**组卷网那部分真实存在**。我实测了 `zujuan-finder` skill 的实际结构：

```
SKILL.md            21 KB   提示词/方法论
references/*.md     6 份    领域知识（URL 语法、原子格式、坑）
scripts/*.mjs       10 个   真正干活的 Node 脚本（含 25 KB 的 bridge.mjs）
extension/          MV3 浏览器扩展（background / content / popup）
node_modules/playwright-core
```

所以它**不是提示词包**：提示词只占一小部分，主体是配套脚本 + 浏览器扩展 + 本地桥。

**决策 D9**：skill 打包成 `.fskill`（zip），结构固定：

```
manifest.json      name / version / description / platforms
                   scripts[]         入口脚本 + 参数说明
                   networkAllow[]    允许访问的域名（默认空 = 不联网）
                   permissions[]     请求的宿主能力
prompt.md          系统提示词片段（skill 的"方法论"）
tools/*.json       该 skill 暴露给 AI 的工具声明（粗粒度动作）
scripts/**         配套脚本
```

应用提供 `SkillContainer` 负责执行（**仅 Windows 启用**）：

- 子进程执行，**cwd = 该 skill 的私有目录**，环境变量最小化（**不注入 API key** —— 这条是硬要求）
- 联网：默认拒绝；脚本要联网必须由 `networkAllow` 声明，且**首次运行时由用户确认一次**
- 文件：只能读写 skill 私有目录 + 用户显式指定的输出目录
- 超时与输出上限；每次执行写审计日志

**AI 永远不直接摸 shell 和文件系统**：它只能调 skill 暴露出来的粗粒度工具（例如 `find_questions`）。
> 依据①：不给通用 shell 权限，风险面小一个数量级；approve 清单里出现的也是"找 10 道力学题"这种人话，不是一堆命令行。依据③：skill 自带脚本比自己写代码调外部工具更可控、可复现。

### 5.2 平台门控（这条我替你拍，因为它直接决定 Android 能不能用）

**决策 D10**：能力分两档，且在设置页**明确显示**差异，不假装两边一样。

| 能力 | Windows | Android |
| --- | --- | --- |
| 内置工具（15 个） | ✅ | ✅ |
| 提示词型 skill（只有 `prompt.md`） | ✅ | ✅ |
| 脚本型 skill（`.fskill` 带脚本） | ✅ | ❌ |
| 浏览器扩展桥（复用已登录标签页） | ✅ | ❌ |
| shell / 进程 | ❌（不给 AI） | ❌ |

理由：Android 上没有 Node 运行时、没有桌面浏览器、装不了扩展，而引入一个 JS 引擎或 Termux 是**另一个量级的工程**，违背③。手机端该做的事（录入、复习、查进度）内置工具就够了；"找题 + 判质量 + 生成文档"这种重活在 Windows 上做。
> 关于用户提到的 Termux：**我决定不做**。理由：它等于把"给 AI 开 shell"从后门放回来，与 D9 直接冲突，且 Android 上 Termux 需要用户额外装应用、配置环境，可行性本身就差。若将来确实需要，再单独立项。

### 5.3 与内置工具相同的装配方式

**决策 D11**：skill 提供的工具与内置工具**同一种数据结构、同一个注册表、同一套审批**。skill 只是"额外追加一批工具 + 一段提示词"。这样审批引擎、审计、权限模式对两者一视同仁，不需要两套逻辑（依据③）。

---

## 6. 权限模式与审批

### 6.1 权限模式（v2：用户 2026-09-25 修订）

用户明确表态：**"除了删除，我认为都可以全自动"**。据此把风险层级**压成两级**，模式压成两档。

**决策 D12（v2）**：风险只分两类 —— `destructive`（删除类）与 `write`（其它一切写入）。

| 模式 | 只读查询 | write（增 / 改 / 完成 / 替换 / 导出） | destructive（删除类） |
| --- | --- | --- | --- |
| **按计划** | 自动 | 整轮清单确认一次 | **逐条确认** |
| **自动**（默认） | 自动 | **自动执行** | **逐条确认** |

- **不再有第三档**：原先设计的"只读模式"被删掉 —— 默认 AI 已开启意味着用户就是要它干活，再提供一个"只能读"的模式属于多余选项（依据③）。
- **`全自动` 依然不提供**：它唯一的差别就是"删除也自动"，而这条被永久排除。

**默认 = 自动**（依用户明确表态；新用户第一次进对话页时会在顶部显示一条持久提示"当前为自动执行模式，除删除外无需逐条确认"，并给出切换到"按计划"的按钮）。

**决策 D13（v2）**：自动执行的操作**全部落台账**，在对话页显示为"已自动执行"，并提供一键撤销。
撤销依赖 `ai_actions.before_json` / `after_json` 快照（见 §8）。

**决策 D13b（新增，重要约束）**：**凡是无法可靠保存 before 快照的工具，一律降级为逐条确认**，不允许进入自动执行。
理由：用户接受自动执行的前提是"出事能撤回"。如果某个操作撤不回来，那它就不该被自动执行——这条把"自动"从一个承诺变成了可验证的性质，而不是靠人记得小心。
实现上：`ToolSpec` 增加 `reversible: bool`，引擎对 `reversible == false` 的工具强制逐条确认，与模式无关。

### 6.2 审批粒度（用户已确认 BC 组合）

| 模式 | query（只读） | write（增改） | destructive（删除） |
| --- | --- | --- | --- |
| **按计划** | 自动 | 整轮清单确认一次 | 逐条确认 |
| **自动**（默认） | 自动 | 自动执行 | 逐条确认 |
| ~~全自动~~ | — | — | **不提供** |

**决策 D14**：
- **按计划**模式下，一次用户消息触发的全部工具调用打包成一张清单，看完点一次"全部执行"；清单内可单独取消某几条。
- **自动**模式下 `write` 类直接执行并落台账（可撤销）；只有 `destructive` 逐条确认。
- `reversible == false` 的工具（见 D13b）任何模式下都逐条确认。

---

## 7. 对话界面

**决策 D15**：结构

- **入口**：底部导航新增一项"对话"（与 Thread / Time / Knowledge / 标签 / 设置 同级）。**仅在 AI 已接入时出现**（满足要求 8）。
- **消息流**：用户消息 / 模型回复 / **工具调用卡片**（可折叠，展开看参数与结果）/ **审批清单卡片**（执行 / 逐条取消）/ 自动执行记录（带撤销）。
- **不需要**：多会话列表之外的花哨东西。会话列表 + 单个会话页即可。

**决策 D16**：不做"输入框旁加 AI 按钮"的分散入口（用户明确否掉）。AI 只通过对话页触达，避免同一能力有两个入口、两套状态。

---

## 8. 数据层（schema v5 → v6）

新增 3 张表 + `LocalSettings` 增列。**API key 存 `LocalSettings`**（沿用"单行本地设置"的既有模式，不新建表）。

| 表 | 用途 | 关键列 |
| --- | --- | --- |
| `ai_conversations` | 会话 | `id`, `title`, `created_at`, `updated_at` |
| `ai_messages` | 消息 | `id`, `conversation_id`, `role`, `content`, `created_at` |
| `ai_actions` | 工具调用与审批台账 | `id`, `message_id`, `tool_name`, `args_json`, `risk`, `status`(pending/approved/rejected/executed/failed), `before_json`, `after_json`, `error`, `created_at` |

`LocalSettings` 增列（全部 nullable，默认即"AI 关闭"）：
`ai_enabled` / `ai_api_key` / `ai_base_url` / `ai_model` / `ai_permission_mode`

**决策 D17**：`ai_actions.before_json` 存变更前快照，是为了 §6.1 的撤销能力。代价是存储略增，但换来"自动模式敢开"。
—— 迁移照既有约定：幂等 `_upgradeV5ToV6` + `beforeOpen` 自愈补列，与 v1→v5 一致。

**决策 D18**：**对话与会话都是普通用户表** → `.tfpkg` 导出会自动包含它们（现有实现是对 `sqlite_master` 做全表转储），不需要额外工作。
**API key 会随之被导出**。这是要求 7（明文图方便）的必然结果，我会在 `PRIVACY.md` 和导出界面上**明确提示**：`.tfpkg` 含 API key，别随便分享。

---

## 9. 隐私文档必须改写的内容

`docs/PRIVACY.md` 现有承诺与 AI 功能的冲突点，逐条改写方案：

| 现有承诺 | 改写为 |
| --- | --- |
| "默认无网络权限" | "不开启 AI 时无任何网络访问；开启 AI 后仅与所配置的模型服务通信" |
| "应用默认不联网、不上传任何使用数据" | 补充："开启 AI 后，你输入的内容与工具调用所需的本地数据摘要会发送至模型服务商" |
| "软件自动上传数据：默认无网络权限" | 改为区分开关状态说明 |
| Windows 版不需要网络权限 | 改为"不开启 AI 时不需要" |

---

## 10. agent loop（暂缓，仅记录已定约束）

用户明确要求**先不要做详细设计**。此处只固化已经确定的约束，供后续设计遵守：

- **C1**：单 agent，不做多 agent 编排。
- **C2**：不采用 cordis —— 无插件注册表、无运行时扩展点、无依赖注入容器。工具清单是代码里的静态常量。
- **C3**：必须有**轮次上限**（防止模型反复调工具烧钱），达到上限时把已有结果整理成回复，而不是静默截断。
- **C4**：上下文需可截断 —— 长对话要有压缩/丢弃策略，具体策略留待详细设计。
- **C5**：工具结果回灌时必须带 `tool_call_id`，且**只追加到末尾**（DeepSeek 的 Chat Completion API 不支持在对话中段插入工具调用，这是官方文档明确说明的限制）。
- **C6**：模型返回的工具调用要**全部**回灌结果，哪怕其中某条被用户拒绝（拒绝也要作为结果告知模型，否则它会重复提议）。

---

## 11. MindNet 接入（待协商，先留接口）

用户提到有另一个 agent 在开发 MindNet 相关内容，需要协商。我的处理：

**决策 D19**：把 MindNet 设计成**一个可替换接口**，先不写死实现。

```dart
abstract class CognitiveModel {
  Future<QuestionQuality> judge(QuestionDraft draft);
  Future<NodeActivation> diffuse({required String startNode});
}
```

- 接口定义在 Furnace 侧（我可以自由改）；
- 实现先留空（抛 `UnimplementedError`）或接一个简单启发式，**不阻塞其它部分**；
- 等协商结论出来再决定实现是"移植到 Dart"还是"Windows 上起 Node 子进程"。

**我对协商的提议**（等用户确认，见 §13）：不走 AgentTeams，用**文件契约**更简单 —— 我在 Furnace 仓库写 `docs/MINDNET_CONTRACT.md`（写清：Furnace 需要 MindNet 提供什么、以什么格式、边界在哪），用户转给对方；对方把回应写进 MindNet 仓库或直接回复，用户带回来。来回超过两轮、出现需要共同维护的接口时，再升级成 AgentTeams。

---

## 12. 实施顺序（每步都可独立验证）

| 阶段 | 内容 | 验证方式 |
| --- | --- | --- |
| A1 | schema v6 迁移 + `AiRepository`（会话/消息/台账） | `flutter test`，仿 v5 迁移测试写 v6 |
| A2 | `ModelAdapter` 抽象 + `FakeModelAdapter` + `OpenAiCompatAdapter` | Fake 驱动单测；真实调用手测一次并记录实际响应 |
| A3 | `ToolRegistry` + 任务/日程两组工具 | 单测：工具调用 → 落库 → 断言通过 Repository 可读到 |
| A4 | `ApprovalEngine` + 四种权限模式 | 单测：每种模式下各风险的裁决结果 |
| A5 | 对话界面 + 导航门控 | Windows 手测整条链路；确认主界面自动刷新 |
| A6 | 其余工具补齐 + 统计/解释类工具 | 单测 |
| A7 | `SkillContainer` + `.fskill` 规范 + 至少一个自带示例 skill | Windows 手测；含超时/拒绝联网/无 key 注入的测试 |
| A8 | 隐私文档改写 + Android `INTERNET` 权限 + 实机验证 | 真机跑到对话功能 |

**决策 D20**：A1–A5 是**最小可用闭环**（能对话、能审批、能改数据、主界面跟着变）。先把这五步走完再谈 skill。理由：如果闭环不成立，skill 做得再花也没用（依据①③）。

---

## 13. 当前状态

**用户 2026-09-25 已对以下两条拍板，不再是待议项：**

1. ✅ **权限模式**：只保留 `按计划` 与 `自动`（默认 `自动`）；除删除外全部允许自动执行；
   删除**永远逐条确认**；`reversible == false` 的工具一律逐条确认（§6.1 D12 v2 / D13b）。
2. ✅ **协商方式**：不建 AgentTeams，走文件契约 —— 已产出 `docs/MINDNET_CONTRACT.md`，
   由用户转交 MindNet 侧。

**仍未获用户明确回应的一条（唯一一条）：**

3. ⏳ **Android 上脚本型 skill 与浏览器扩展能力不提供**（§5.2 D10）。
   这条会让"组卷网找题"类 skill 在手机上不可用，所以我把它单独列出来，不替用户默默拍掉。
   在你回应之前，我按"不提供"推进（因为它是可行性决定的，不是偏好问题）。

---

## 14. 我替你拍板、但你可能想改的地方（列出来供你划）

| # | 决定 | 我的理由 | 你想改的话 |
| --- | --- | --- | --- |
| D4 | 不开 strict 模式，改在 Dart 侧校验 | 简单、好测 | 若你更信服务端强约束，可开 |
| D5 | 默认 `deepseek-chat` 而非 reasoner | 工具调用更稳、更便宜 | 待实现后实测对比再定 |
| D8 | 只读工具返回摘要而非全量 | 省上下文 | 可分页参数细调 |
| **D10** | **Android 只给内置工具 + 提示词 skill** | 可行性 | **唯一还没得到你回应的一条，见 §13** |
| D11 | skill 工具与内置工具同构 | 只有一套审批/审计 | — |
| D13/D13b | 自动执行配"台账 + 可撤销"；撤不回来的操作强制逐条确认 | 你要求除删除外全自动，而"敢自动"的前提是能撤回 | 已按你的表态定稿 |
| D16 | 不做分散入口，AI 只在对话页 | 满足你的要求 1 | — |
| D18 | API key 随 `.tfpkg` 导出，界面明确提示 | 你选了明文图方便 | 若不想带出，可加"排除敏感配置"开关 |
| D20 | 先做 A1–A5 闭环，再谈 skill | 闭环不成立则 skill 无意义 | — |
