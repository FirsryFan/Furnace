# 平台能力矩阵（Android / Windows）

> 状态：v1，2026-11-01（task-11）。所有具体结论都标注 `文件:行号`（相对 `E:/Projects/Furnace`；工作区文件用绝对路径）。**候选 ≠ 已实现**：凡写"候选"的条目都没有门控代码。
> 本轮代码改动：`app/lib/features/ai/domain/ai_tool.dart`（平台枚举 + 工具级声明）、`app/lib/features/ai/domain/tool_registry.dart`（统一过滤 + 能力描述导出）、测试 `app/test/features/ai/tool_platform_capability_test.dart`。

## 0. 一句话

Furnace 只发 **Windows 10/11 桌面 + Android 8+** 两个目标（`docs/FURNACE_SPEC.md:14`）。平台隔离的口径是：**能力按轻/重分级，重活在 Windows，手机只保留录入/复习/查进度；不可用的任务在工具清单与 UI 上直接不存在，而不是调用时才失败**。本轮把这句话落成代码基础：工具可声明 `supportedPlatforms`（默认两端），注册表统一按当前平台过滤并导出可序列化的能力描述；**现有 29 个内置工具全部默认两端，行为不变**。

## 1. 事实基线（代码与文档实测）

### 1.1 平台与工具装配

- 双端目标：`docs/FURNACE_SPEC.md:14`（Windows 10/11 及 Android 8+）；Android 端同一代码（`docs/ARCHITECTURE.md:135`）。
- 工具清单是**静态常量**（`docs/AI_DESIGN.md:410` C2 "工具清单是代码里的静态常量"；`app/lib/features/ai/domain/tool_registry.dart:35-45`）；当前 **29 个**（`docs/HANDOFF.md:34`、`:264-266` 注册顺序；`ToolRegistry.forApp` 列表 `tool_registry.dart:55-201` 实测 29 条，测试断言通过）。
- 旧平台门槛 `availableOnCurrentPlatform`：`app/lib/features/ai/tools/` 下 30 处实现全部是 `=> true`（grep 实测）；唯一例外是 `SkillTool`（`app/lib/domain/skill/skill_tool.dart:126`）。
- 本轮之前，`ToolRegistry` 只按 `availableOnCurrentPlatform` 过滤（历史形态）；现在改为"声明 + 兼容位"两层（§1.2）。
- 唯一**已实现**的 Windows-only 门控是 skill 脚本：`SkillTool.availableOnCurrentPlatform => platform == SkillPlatform.windows && skill.manifest.supports(platform)`（`skill_tool.dart:126`）；`SkillPlatform` 枚举 5 值（`app/lib/domain/skill/skill_manifest.dart:21-31`）；agent loop 对内置工具与 skill 工具都按这一位过滤（`app/lib/features/ai/domain/agent_loop.dart:1885`、`:1892`，注释 `:1908`）。
- 既有设计口径 **D10**（`docs/AI_DESIGN.md:275-288`）：内置工具两端、prompt 型 skill 两端、**脚本型 skill 仅 Windows**、**浏览器扩展桥仅 Windows**、shell/进程两端都不给；理由"Android 上没有 Node 运行时、没有桌面浏览器、装不了扩展"（`:287`）；并规定设置页要"明确显示差异，不假装两边一样"（`:277`）。
- 文档漂移（以代码为准）：`docs/AI_DESIGN.md:281` 写"内置工具当前 21 个"、`:172` 写"27 个"，实际 29 个（`docs/HANDOFF.md:34` + 注册列表实测）。

### 1.2 本轮新增的代码基础

- `AiToolPlatform` 枚举：两值、稳定 id（`android`/`windows`）、`fromId` 反查、`all` 常量（`ai_tool.dart:254-277`）。
- `AiTool.supportedPlatforms`：默认两端 `AiToolPlatform.all`（`ai_tool.dart:306`）；`availableOnCurrentPlatform` 保留为"运行时进程"兼容位（`:315`，语义注释 `:308-314`）。
- `ToolRegistry.currentPlatform`：Android → `android`，其余主机（含运行纯测试的 Linux/macOS）→ `windows`（`tool_registry.dart:216-217`，只发这两个目标）。
- 统一过滤：`isOfferedOn`（`tool_registry.dart:228-235`）、`forPlatform`（`:239-243`）、`forCurrentPlatform`（`:245`）、`unavailableHere`（`:248-252`）；`modelSpecs`（`:287-293`）与 `isEmptyHere`（`:298`）自动跟随。
- 能力描述导出：`describePlatformCapabilities()`（`tool_registry.dart:260-273`），每条含 `tool` / `supported_platforms` / `restricted_by_platform` / `offered_here`，纯数据、稳定 id、无 l10n、注册顺序固定。

### 1.3 本轮验收（真实命令，2026-11-01 本机）

- `dart format lib/features/ai/domain/ai_tool.dart lib/features/ai/domain/tool_registry.dart test/features/ai/tool_platform_capability_test.dart` → `Formatted 3 files (1 changed) in 0.08 seconds.`（changed = 新建的测试文件）
- `dart analyze <同上三个文件>` → `No issues found!`
- `flutter test test/features/ai/tool_platform_capability_test.dart` → `+9: All tests passed!`
  覆盖：枚举 id 往返 / 默认两端 / Windows-only 工具在 Windows 可见、Android 隐藏 / `forCurrentPlatform` 镜像当前平台 / 旧门槛在当前平台仍生效 / 旧门槛不套到其他平台 / 能力描述导出稳定 id 与限制标记 / 真注册表 29 个工具双端全部可用 / `modelSpecs` 与过滤后列表一致。

## 2. 任务三档矩阵

> 分档依据是既有产品口径（`docs/AI_DESIGN.md:287`："手机端该做的事（录入、复习、查进度）内置工具就够了；'找题 + 判质量 + 生成文档'这种重活在 Windows 上做"），不是性能猜测。**A/B 档当前都双端可调用**，只有 C 档需要 `supportedPlatforms` 声明。

| 档 | 任务 | 现状（代码/文档） | 门控建议 | 依据 |
|---|---|---|---|---|
| A 轻任务（双端必须） | 对话、任务/日程/标签、复习与知识点、题库浏览/检索、组卷预览（`compose_paper` 只读生成 PaperPlan，不落库）、拍照收题 | 29 个工具中的只读/轻写工具全部双端可调 | 保持默认两端 | `tool_registry.dart:55-201`；`docs/AI_DESIGN.md:287` |
| A 轻任务（双端必须） | 小 `.tqb` 导入（工作区实测 30~36 题、4.6~28 MB）、导入预检、写库前自动备份 | 有预检 + 备份 + 按题号更新，无平台限制（`docs/HANDOFF.md:163`） | 保持两端 | `FURNACE-PIPELINE-SPEC-v1.md:261-278`（工作区） |
| B 重任务（双端可跑，桌面优先/可降级） | Word 导出（纯 Dart OOXML、公式 OMML、整卷在内存里构建） | 代码平台无关（`docs/DOCX_EXPORT_DESIGN.md:15`"纯 Dart、离线"），当前无门控 | 暂默认两端；真机卡顿再声明 windows，或提示"推荐桌面" | `docs/DOCX_EXPORT_DESIGN.md:22-32`、`:243-255` |
| B 重任务 | 批量组卷 + 质量报告（题量大时贪心计算 + 理由句） | 纯逻辑、无 AI 调用、不落库（`PaperPlan`） | 同上 | `app/lib/domain/services/paper/paper_composer.dart:365-420` |
| B 重任务 | 大 `.tqb` 导入（上限 5000 条） | 超限整包拒绝（`docs/PIPELINE_SPEC` 工作区 `FURNACE-PIPELINE-SPEC-v1.md:238`）；5000 题内存/耗时**未测**（`docs/QUESTION_BANK_DESIGN.md:821`） | 先实测再定；若要限，只限桌面 | 同左 |
| B 重任务 | 整卡大图渲染（1640 px 宽、30 题 60 媒体） | 现状双端渲染；命名/尺寸约定见 `FURNACE-PIPELINE-SPEC-v1.md:252-257` | 真机实测后决定 | 同左 |
| C Windows-only 候选（**已真实门控**） | skill 脚本（Node 脚本，`.fskill`） | `SkillTool` 只看 Windows + 包声明；Android 上工具**缺席**而非调用失败 | 保持；新工具用 `supportedPlatforms` 对齐 | `docs/AI_DESIGN.md:283`、`:287`；`skill_tool.dart:126`；`agent_loop.dart:1908` |
| C Windows-only 候选（**App 外**） | 组卷网采集管线（Node + Edge 扩展 + Playwright 渲染 + Python 校验） | 不属 App：采集层是外部 CLI（`FURNACE-PIPELINE-SPEC-v1.md:16-33`），运行环境全是桌面路径（`:65-76`） | 不需要 App 门控；文案说"在电脑上采" | 同左 |
| C Windows-only 候选（**App 外**） | 六科学习材料生产（题目/解析/扩展三份 md + 题卡） | 外部目录产物（`FURNACE-PIPELINE-SPEC-v1.md:332-349`）；App 侧材料容器 M2-c/M2-d **未做**（`docs/HANDOFF_PIPELINE.md:17-18`） | 未来接入时按"桌面生产、两端消费"设计 | 同左 |
| C Windows-only 候选（**未来**） | DSH 类重任务（多 agent/长任务/本地工具链） | **产品仓库无对应实现**；`grep DSH docs/*.md` 只在 PROGRESS 命中，未形成设计 | 立项时再定 | 未确认（§6） |

## 3. 呈现原则：不可用任务不给入口

1. **工具层**：不可用 = 不在 `forCurrentPlatform` 里（`tool_registry.dart:245`），模型连工具声明都看不到（`modelSpecs` `:287-293`）。这是 `docs/AI_DESIGN.md:277`"能力分两档且明确显示"的执行方式。
2. **调用层**：能力缺失表现为"工具不存在"，不是"调用时报错"（`tool_registry.dart:44-45`；`agent_loop.dart:1908` 的 skill 门控注释："tools are **absent from the list**, not present and failing when called"）。skill 工具是唯一沿旧位过滤的动态工具。
3. **UI 层**：入口只读 `forCurrentPlatform` / `unavailableHere`（`tool_registry.dart:245-252`），不要自己写 `Platform.isAndroid` 再判断一遍（会与注册表漂移）。D10 要求设置页明确显示差异（`docs/AI_DESIGN.md:277`）；**本轮不接 UI**（`settings_page.dart` 属 Lead 作用域），该显示尚未接线。
4. **产物层**：另一端不可消费的产物不生成、不宣称可用。目前 §4 的格式都是标准文件，两端都能消费；但**没有任何一种在 Android 真机实测过**（§6）。
5. **未门控要说明**：B 档这类"双端能跑但推荐桌面"的任务，在文案里写清"推荐桌面"，不要假装手机适合。
6. **禁止**：不把"平台"写进 l10n 文案（能力描述用稳定 id，可导出）；不在多个文件各写一套平台判断。

## 4. 跨端文件传递（唯一通道是文件，不传数据库/状态）

| 产物 | 格式与内容 | 生产 → 消费 | 证据 |
|---|---|---|---|
| `.tqb` | zip：`manifest.json` + `questions.json` 裸数组 + `media/`；version=1；上限 5000 条 | Windows 采集/导出 → 两端导入（导入前自动备份、按组卷网题号更新） | `docs/HANDOFF.md:163`、`:296`；`FURNACE-PIPELINE-SPEC-v1.md:189-211`、`:261-278` |
| `.tfpkg` | 整个工作区备份，replace 语义 | 本机导出/导入（同一 App） | `docs/QUESTION_BANK_DESIGN.md:752`；`docs/HANDOFF.md:165` |
| `.docx` | 题目卷（纯 Dart OOXML、公式 OMML、图片 inline） | 两端导出 → Word/WPS 打开；当前不产 PDF | `docs/DOCX_EXPORT_DESIGN.md:10-20`、`:251` |
| `.kpak` | 知识包（zip + manifest.json） | 两端导入（知识库） | `app/lib/data/package/knowledge_package_codec.dart:8-9` |
| `.cogprofile` | JSON：format_version 1.0 + 10 能力 + 9 参数 | 两端导出，只作档案 | `docs/HANDOFF.md:309` |

原则：文件格式是**跨端契约**——包内不使用本机 id/绝对路径（`.tqb` 的 `pack_path` 必须相对 POSIX 路径，`FURNACE-PIPELINE-SPEC-v1.md:244`；认题键是组卷网题号，`:230-233`）。因此手机端不会因为"库在 Windows 上"而不可用：把包拷过去导入即可。

## 5. 新增工具/能力时的门控清单（可执行）

1. 先判断是否依赖桌面独有能力（Node/Edge/Word/大内存/窗口）：**否 → 什么都不声明**（默认两端）。
2. **是 → 工具类里 `Set<AiToolPlatform> get supportedPlatforms => {AiToolPlatform.windows};`**，并补测试（`forPlatform(windows)` 有、`forPlatform(android)` 无）。
3. UI 入口读 `ToolRegistry.forCurrentPlatform` / `unavailableHere`，不自己判平台。
4. 产物登记到 §4；若另一端不能消费，先补消费端或不要生成。
5. 矩阵变更同步本文件；机器可读版是 `describePlatformCapabilities()`（`tool_registry.dart:260-273`），两者必须一致。

## 6. 未确认 / 风险

- **Android 真机没有逐屏手测**：`docs/HANDOFF.md:471` 把"双端真机逐屏手测"列为未做第一项，因此 A/B 档的实际性能结论都**未验证**。
- **Word 导出没有 Android 实测**，代码本身平台无关（`docs/DOCX_EXPORT_DESIGN.md:15`），故只列为 B 档候选，不是现状限制。
- **大 `.tqb`（近 5000 题）内存/耗时未测**（`docs/QUESTION_BANK_DESIGN.md:821`），B 档上限来自规范而非实测。
- **DSH 类重任务在产品仓库无实现**：`grep -l DSH docs/*.md` 只命中 `PROGRESS.md`，没有设计文档；列候选，不声称已支持。
- **文档漂移**：AI_DESIGN 的工具数（21/27）与实现（29）不一致（§1.1），本文件以代码为准。
- **本轮未接 UI**：工具层门控已生效，但设置页尚未展示"此平台不可用"的差异（`docs/AI_DESIGN.md:277` 的要求待接线）。
- **两套平台判断并存**：`ToolRegistry.isDesktop`（Windows/Linux/macOS，`tool_registry.dart:300`）与新的 `currentPlatform`（windows/android，`:216-217`）。本轮未动 `isDesktop` 以免影响既有调用，属于待统一的小债。
- 本轮测试只覆盖枚举/过滤/导出与"29 个内置工具双端不变"，**未做 Android 构建或真机测试**（不做构建是本次纪律）。
