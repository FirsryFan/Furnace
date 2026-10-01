# 交接文档（给下一个 Agent）

> 写给接手的人（或 agent）。目标：**不读完整个对话也能安全接上**。
> 本文只写**本会话实际做过并验证过**的事；没验证的一律标注。
> 撰写时的仓库状态：`c354dc4`，工作区干净，与 `origin/main` 一致。

---

## 0. 三十秒速览

**项目**：Furnace —— 本地优先的生产力套件（Flutter，Windows + Android）。
仓库 `https://github.com/FirsryFan/Furnace`，本机路径
`E:\FirsryOS\Memory\一THREADRIPPER一\class-productivity`。

**当前状态**：`flutter test` **360/360 通过**，`dart analyze lib test` **0 error / 0 warning**
（87 条 info 全是既有风格项），Windows release 可构建可运行，Android 未重构建（用户说先不急）。
schema 已到 **v6**，31 张表。

**本会话做完的三块**：
1. 全局改名 → **Furnace**（并修掉改名引发的**数据目录漂移**，会静默丢用户数据）
2. **AI 集成闭环**（对话页 + agent loop + 工具层 + 审批引擎，真实 API 实测过）
3. **MindNet 认知模型 tierA 移植**（43/43 对拍通过）+ 界面几个"假控件"修复

**最重要的三份文档**（按需读，不必全读）：
| 文档 | 什么时候读 |
| --- | --- |
| `docs/OPEN_DECISIONS.md` | **先读这个**：我做的决定 + 需要用户定夺的问题 |
| `docs/AI_DESIGN.md` | 碰 AI 部分前必读（20 条决策与依据） |
| `docs/PROGRESS.md` | 想知道"某件事为什么是这样"时查（985 行，按轮次倒序） |

---

## 1. 硬约束（**不要违反**）

| 约束 | 说明 |
| --- | --- |
| **`E:\Document\MindNet` 只读** | 用户明确要求。绝不在其中创建/修改/删除任何文件。需要它提供什么，走 `docs/MINDNET_CONTRACT.md` 的文件契约 |
| **未填 API key 时不得有任何网络请求** | 这是产品承诺。`aiEnabledProvider` 为假时对话入口根本不存在，这条有测试守着 |
| **删除类操作永远逐条确认** | 用户明确要求，任何权限模式下都不例外。`ApprovalEngine` 有穷举测试 |
| **撤不回来的操作也强制逐条确认** | 我加的约束（`docs/AI_DESIGN.md` D13b）：能自动执行的前提是能撤回 |
| **不引入第二份数据真相** | 认知模型的状态存在**已存在**的列上，不加影子表/影子列（见 §4） |
| **`database.g.dart` 要提交** | 它是生成代码但被刻意纳入版本控制，改动 schema 后必须跑 `build_runner` 并提交 |

---

## 2. 环境（这台机器特有，踩过的坑）

| 项 | 值 |
| --- | --- |
| Flutter / Dart | `D:\flutter\flutter`（3.47.2 / Dart 3.13.2） |
| Android SDK | `E:\Document\AndroidDev\sdk`，Gradle home `E:\Document\AndroidDev\gradle-home` |
| JDK | `C:\Program Files\Microsoft\jdk-21.0.12.101-hotspot`（机器级，移不走） |
| **构建必须走 ASCII 路径** | junction `E:\Document\furnace-build` → 真实 app 目录。工作区路径含中文，release 的 AOT 会读不到 `app.dill` |
| 构建脚本 | `scripts/build_android.ps1` / `build_windows.ps1`（含工具链自动探测） |
| 含中文的 `.ps1` **必须带 UTF-8 BOM** | 否则 PowerShell 5.1 按 ANSI 解码，中文注释会吞掉引号导致语法错误（已踩过） |
| Git 推送 | 全局配了代理 `http://127.0.0.1:7890`，对 github.com **时通时不通**。稳的做法：`git -c http.proxy= -c https.proxy= -c http.sslVerify=false push origin main`，失败就重试几次 |
| GitHub API | 需要 `curl --ssl-no-revoke`（Schannel 吊销检查离线） |

---

## 3. 已实现并验证的东西

### 3.1 全局改名 → Furnace（提交 `90a6be2`、`389b9fb`）

Dart 包名 `knowflow`→`furnace`；Android `com.furnace.app`；Windows `furnace.exe`；
定稿文档 `THREADFLOW_SPEC.md`→`FURNACE_SPEC.md`。

**顺带修掉一个会丢数据的真 bug**：`getApplicationSupportDirectory()` 的路径来自 exe
元数据 / applicationId，改名把两者都改了 → 旧数据留在旧目录，新安装会新建空库。
实测：新库只有 4 行种子数据，而用户真实录入的 3 个日程块在旧库无人读取。
修复见 `database.dart` 的 `_adoptLegacyDatabase`（跨目录查找并**复制**旧库，不移动；
复制失败则继续用原文件）。回归测试 `test/data/database/legacy_database_adoption_test.dart`。

**保留的旧名（故意不改）**：数据库回退链 `threadflow.db`/`knowflow.db`、
`FURNACE_SPEC.md` 顶部的改名说明、`database.dart` 里记录历史名的注释。

### 3.2 AI 集成（提交 `1a383c0`、`a84cade`、`847ef0d`）

**分层**（`app/lib/features/ai/`）：

```
domain/          agent_loop.dart(744) · approval_engine.dart(115) · ai_tool.dart(285)
                 model_adapter.dart(178) · tool_registry.dart(60)
infrastructure/  openai_compat_adapter.dart(185) · sse_assembler.dart(159)
                 fake_model_adapter.dart
tools/           task_tools.dart(469) · schedule_tools.dart(307)
application/     ai_providers.dart(94)
presentation/    ai_chat_page.dart(680) · ai_settings_page.dart(240)
```

**关键设计**（细节与依据见 `docs/AI_DESIGN.md`）：

- **工具是现有 Repository 的薄包装，不写 SQL** → AI 改数据后主界面经 Riverpod
  自己刷新，不需要任何刷新代码；业务规则只有一份实现
- **工具按模块聚合**（`manage_task` 带 `action` 参数），不把 60+ 个仓库方法铺成 60+ 个工具
  ——选择太多模型会选错
- **权限两档**（`plan` 默认 / `auto`）+ 风险两级（`write` / `destructive`）
- **`TurnGroup`：一轮输出是原子单元**（见下）

**真实 API 实测抓到的严重 bug**（`a84cade`）：我原本在模型返回工具调用时就写 assistant
消息，而工具回应要等批准 → 历史里出现"有 tool_call 却无回应"的悬空状态，provider 在
**下一次请求**时返回 400，**整个对话从此报废**。
修复：`TurnGroup` 把"assistant 消息 + 每个调用一条回应"作为整体，全部齐了才写库。
同一根因的第二条路径（`rejectPending` 写回应却不写 assistant → 孤儿 tool 消息）也已修。

**为什么单测没抓到**：`FakeModelAdapter` 不校验历史结构，真实 provider 校验。
**教训（已写进 PROGRESS.md）：客户端生成、服务端校验的结构（消息顺序、字段配对），
必须有至少一次真实调用或一个显式模拟该约束的守卫。**

**两层验证**：
- 单测 **120 项**（假模型驱动）：`agent_loop_test` 29 · `task_tools_test` 28 ·
  `sse_assembler_test` 23 · `ai_repository_test` 18 · `approval_engine_test` 11 ·
  `v6_migration_test` 8 · `ai_chat_ui_test` 3
- **真实 API harness** `app/live/agent_loop_live_test.dart`：需 `FURNACE_LIVE_AI=1` 才跑，
  从真实库**只读**取 key，用内存库跑真实 loop/工具/审批。实测：只读查询、建任务、
  **撤销真的回滚**、删除停在 `individualApproval`、拒绝无副作用、每步存储历史结构有效。

### 3.3 MindNet 认知模型 tierA（提交 `31ef312`）

- **移植**：`app/lib/domain/services/srs/dsr_memory.dart`(527) 是 `mechanisms/memory.dsr.js`
  tierA 的纯 Dart 移植（无数据库/时钟/Flutter，`nowHours` 显式传入）
- **放在 `domain/services/srs/`** 而不是 `features/ai/`：它是复习调度算法，与
  `fsrs_scheduler.dart` 并列；耦合进 AI 模块会让两边都更难改
- **对拍**：`test/fixtures/mindnet_vectors.json`（从 MindNet 拷入，冻结在 `c624884`）
  + `test/domain/services/srs/mindnet_dsr_conformance_test.dart`
  → **43/43 个公开值在 `rel ≤ 1e-12` 内复现**（round6 后逐位相等）
- **桥接**：`app/lib/domain/services/srs/dsr_card_state.dart`(218)

### 3.4 界面修复（提交 `ac3a9a4`、`31ef312`、`c354dc4`）

三个字段曾是**"假控件"**——能点、能填、能保存，但**什么都不发生**（比没做更糟，
用户会以为设置生效了）：背景色、背景透明度、正文字体。已修。

**背景图 bug 的真正原因**（用户实测"就是加载不出来"）：
`_AppearanceScope` 是 `MaterialApp` 的 builder，包住的是 Navigator→Scaffold；
我把背景色设成 `scaffoldBackgroundColor = 图色 alpha 0.9`，而 **Scaffold 在图片上面**，
0.9 的近乎不透明把图整个盖住了。图片本身没问题（实测文件存在且可解码，3000×2083）。

修法：有背景图时 Scaffold 完全透明；背景色改为画在图片**之上**的半透明纱罩
（`app/lib/app/background_layer.dart` 的 `Backdrop`）。

另修：`.tfpkg` 导出可**排除 API key**（导出前询问），只清空敏感列、同行的模型名/
权限模式/语言全部保留。测试 `test/data/package/tfpkg_secrets_test.dart` 含一条守卫：
`TfpkgService.sensitiveColumns` 里的列名必须真实存在于 schema，否则脱敏会静默失效。

---

## 4. 数据统一：为什么认知模型不会造成两份数据

**一张卡只有一条记忆状态。** `R0 / S / Σ / D` 恰好落在**已经存在**的四个列上：

| 模型字段 | 存储列 | 单位换算 |
| --- | --- | --- |
| `R0` 编码强度 | `card_states.encoding_strength` | — |
| `S` 稳定度 | `card_states.stability` | **天 → 小时 ×24**（唯一换算点：`DsrCardState.hoursPerDay`） |
| `Σ` 储蓄效应 | `card_states.savings` | — |
| `D` 难度 | `card_states.difficulty` | — |

所以接入认知模型**不需要新表、新列或迁移**；两边读写同一行，**结构上不可能不同步**
——不是靠约定，是靠没有第二份数据。

**两个容易"顺手改错"的读法**（都有测试钉住）：

1. **没记录的 `R0` 读作 1.0，不是 0.8**。FSRS 曲线无上限；`R0 = 1` 时两条曲线完全相同
   （已验证 `t = S` 都精确给 0.9）。读成 0.8 会让记得很牢的条目在模型眼里变成半生不熟。
2. **`lapses` 不转成模型的 `F`**。前者是终身计数，后者是**会衰减的证据**；
   从计数反推衰减历史等于编造数据。模型的失败证据从真实失败重新积累。

**本会话最值得记住的一个 bug**：我原本把"没有复习记录"读作 `lastReview = 当前时间`。
看着合理，实际让 `dt` 恒为 0、`R` 恒为 1、稳定度增益恒为 1.0 —— **模型完全不工作
且不报错**。真实语义：MindNet 时钟是**纪元起算小时数**，`ensureState` 里
`lastReview: node.last_review_time || now` 的 `now` 默认 **0**，所以"没有复习记录"
= 从纪元开始就在遗忘。

**更值得记的是：我把这个 bug 写进了测试**——当时断言"没复习过的卡应该 R=1"，
它**通过了**，因为实现和断言犯了同一个错误。**测试通过不等于行为正确。**

---

## 5. 我的疑问 / 需要定夺的（**最重要的一节**）

完整版在 `docs/OPEN_DECISIONS.md`，这里给结论式摘要：

### 5.1 最需要定的一条：认知模型在复习流程里的角色

现在是一套**经过对拍验证、且能与现有数据互读**的实现，但**复习界面还没调用它**。

| 方案 | 含义 | 代价 |
| --- | --- | --- |
| **(a) 顾问**（我倾向） | FSRS 继续决定到期时间，模型只用于**排序**与"发展区/死角"判断 | 数据零风险；模型的调度能力没用上 |
| (b) 调度器 | 模型直接决定间隔 | 用上全部能力，但要定"默认用哪个"并处理老数据 |
| (c) 可选 | 设置里二选一 | 最灵活，但多一个概念、两条路径都要维护 |

我倾向 (a) 起步：立刻改善体验（先复习快忘的），且不碰到期时间的权威来源。

### 5.2 新卡在模型眼里是"遗忘已久"

这是 §4 那个语义的直接后果：`lastReview = 0` → `R` 趋近 0。
对**排序**恰好合理（没复习过的先看）；但按"增益最大"排序会让所有新卡挤最前面。
要么接受，要么给新卡显式 `lastReviewedAt = 现在`（**改了就不是 MindNet 的语义了**）。

### 5.3 Thread 事件流永不自动刷新（**已确认为真问题**）

全仓只有**一处** `invalidate(threadFeedProvider)`，在"载入示例数据"里。
任何建/改/删任务或日程都不会刷新它 → **新任务在你重新点排序前完全不可见**。
而蓝图 Q2.7 承诺的"未参与排序"标记**代码里一个字都没有**。

根因是刻意设计（`docs/DESIGN_BLUEPRINT.md` L125「触发方式只有手动点排序」）+
未兑现的承诺。我建议的规则：数据变化→自动更新列表内容；精力/目标变化→只标记"需要重排"
（否则调精力时列表会在手底下乱跳）；权重变化→自动重排。**已列入待议，未动手。**

### 5.4 界面个性化剩余项（详见 `docs/APPEARANCE_DESIGN.md`）

| 项 | 状态 |
| --- | --- |
| 字体 | 用户已定方向：**安卓留空=系统字体；桌面给带预览的菜单**（Word 式）。**未实现** |
| 图标 | 导航图标写死，无法更换。**未实现**。方案：按语义槽位（约 10 个）+ 内置分组图标网格 |
| 主题色 | 只有 primary 走 seed 派生；`secondary` 解析了没用；`surface` 只能手改 JSON。**未扩展** |
| 字体文件导入 | 未做。有 `system_fonts` 包但**未认证发布者、两年未更新、周下载 2.8k**；直接读 Windows 注册表会拿到 225 项里大半是样式变体（Arial Bold/Italic 各占一项），做成菜单是垃圾堆 |

### 5.5 我明确没做的

| 项 | 说明 |
| --- | --- |
| **`Backdrop` 的视觉确认** | 装饰部分是结构性测试（7 项），**渲染部分没有像素级验证**：像素测试会死锁（`Image.file` 需要真实异步解码，widget 测试跑在 fake-async 里，`runAsync` 也没解决）；窗口截屏在本会话拿到全黑。**需要人眼确认** |
| **Android 重构建** | 用户说先不急。Dart 层改动与平台无关，但未实测 |
| **tierB 快层** | 约 400–600 行（驱动/激活/容量/点火/目标偏置/诊断）。契约建议 tierA 稳了再上；对"间隔准不准"无贡献 |
| **图投影（标签树 → 认知图）** | 用途 1（判题目质量）的胶水，未开始。契约明确说 `ls` 边权**无标定来源**，只给了量级建议（父子 0.6–0.8、兄弟 0.3–0.5），需标注为未标定 |
| **`.fskill` 执行容器** | 格式已定稿（`docs/SKILL_FORMAT.md`），容器未实现 |

---

## 6. 怎么验证（照做即可）

```powershell
cd E:\FirsryOS\Memory\一THREADRIPPER一\class-productivity\app

# 全量测试（约 1 分钟）。末尾应显示 "All tests passed!"
# 注：文件里声明的 test 是 361 条，执行计数为 360 —— 差额来自
# mindnet_dsr_conformance_test 里那条"文件缺失就 fail"的守卫，
# 它在文件存在时走 skip 分支。数字对不上是正常的，不要以为漏跑。
flutter test --concurrency=1

# 静态分析（应为 0 error / 0 warning；87 条 info 全是既有风格项，无 warning）
dart analyze lib test

# 改了 schema 后必须重新生成并提交生成代码
cd E:\Document\furnace-build
dart run build_runner build --delete-conflicting-outputs

# 构建（必须走 ASCII junction）
flutter build windows --release
powershell -ExecutionPolicy Bypass -File scripts\build_android.ps1 -Mode release

# 真实 API harness（花钱，需真实库里有 key，默认会跳过）
$env:FURNACE_LIVE_AI='1'; flutter test live\agent_loop_live_test.dart
```

**验证纪律建议**（本会话踩过坑）：
- **别用"能渲染"证明"能用"**：我曾在主题编辑器里断言按钮存在就下结论，
  而用户实测图片根本不显示。**要看最终效果，不是中间件存在。**
- **别把 bug 写进测试**：实现和断言犯同一个错误时，绿灯毫无意义（§4 的时钟 bug 就是）。
- **改代码前确认你跑的是新构建**：本会话两次启动旧 exe，白测一轮。
  Windows 看 `build\windows\x64\runner\Release\data\app.so` 的时间戳，不是 `furnace.exe`
  （那 91 KB 只是壳）。
- **AOT 产物里搜中文找不到是正常的**：本地化在 `flutter_assets`，且多为 UTF-16。

---

## 7. 提交历史（本会话相关）

```
c354dc4 refactor(appearance): 背景层抽成可测的 Backdrop，并记录待议清单
31ef312 feat(mindnet): 接入认知模型 tierA，并修掉背景图被遮挡的根因
673b6cb docs(appearance): 界面个性化设计 v1（现状核对 + 图标/主题色/字体方案）
ac3a9a4 fix(appearance): 修掉三个"假控件"，并给导出加敏感配置开关
847ef0d test(ai): 补界面层验证 —— 真实控件驱动的对话链路
a84cade fix(ai): 真实 API 实测抓到的 400 —— turn 必须是原子单元
2c6d7b8 docs(readme): 状态更新为 schema v6 / 308 项测试 / AI 闭环已实现
1a383c0 feat(ai): AI 集成最小闭环 —— 对话页 + agent loop + 工具层 + 审批引擎
90a6be2 feat!: 全局改名 Furnace，并修复改名导致的数据目录漂移
389b9fb fix(windows): 窗口标题硬编码为 knowflow，改名为 Furnace 并出 0.2.1
```

Release：`v0.1.0`（Threadflow）、`v0.2.0`、**`v0.2.1`（最新，Furnace 品牌）**。

---

## 8. 用户的工作方式（照做能省很多来回）

- 用户会**直接、具体地指出问题**，包括"你自己忽略了问题"——**这种时候先去取证，
  不要辩解**。本会话两次因为我的验证方式有漏洞而被指出，两次都是我的错。
- 用户说"**这些设计我可能没你专业，你代替我完成决定**"，标准是：
  **① 可行性+安全性 → ② 效果最大化 → ③ 方案最简**（冲突时按此优先级压）。
- 用户明确表示过**不要拿琐碎问题问他**；有值得商讨的**列出来他后续一起看**。
- 用户的使用场景以 **Android 手机**为主，Windows 为辅。
- 用户希望"**先讨论好，再直接做**"，而不是每步都确认。
