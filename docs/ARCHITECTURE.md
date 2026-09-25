# 架构设计（Furnace 对齐版）

> 产品：Furnace（前身：知序 Furnace）
> 更新：2026-09-07，对齐 [FURNACE_SPEC.md](FURNACE_SPEC.md) 定稿；决策编号见 [GAP_ANALYSIS.md](GAP_ANALYSIS.md)（D1–D13）
> 技术栈：Flutter（Windows 优先，Android 8+）/ Riverpod / Drift
> 架构风格：本地优先 + 单机关系库 + 纯 Dart 算法层 + Feature-first UI

---

## 1. 技术选型（v2 增补）

| 领域 | 选型 | 说明 |
| --- | --- | --- |
| 跨平台 UI | Flutter 3.47+ | Windows 10/11 + Android 8+ |
| 状态管理 | Riverpod | 沿用 |
| 本地数据库 | Drift（SQLite） | schema v2，迁移策略见 DATA_MODEL.md §7 |
| 本地通知 | flutter_local_notifications | 任务提醒（保留能力） |
| zip | archive | .kpak / .tfpkg |
| 加密（可选） | cryptography（AES-GCM） | .tfpkg 密码加密；网络受限则先留接口（GAP O1） |
| 富文本 | Markdown 结构化正文（自实现最小渲染/编辑）；flutter_quill 视 O1 引入 | 词条正文 + 图片附件 |
| Markdown 导入导出 | 自实现轻量转换（词条级） | 定稿 1.3.1 |
| 思维导图 | 树形自绘组件（既有） | 拖拽 re-parent R6 打磨 |
| 日历视图 | 自绘日/周/月网格（table_calendar 视 O1） | Time 模块 R5 |
| 国际化 | ARB zh/en | 词表按 Furnace 更新 |

沿用不表：uuid、path_provider、file_picker、timezone、intl。

## 2. 命名映射（D2，写一次、处处读）

| 用户可见 | 内部 | 说明 |
| --- | --- | --- |
| Thread | `features/tasks`、`Tasks`/`TaskItem` | 事件流。新算法/状态用新名：`ThreadRanker`、`ThreadState`、`CompletionLog` |
| Time | `features/timeboard`、`TimeBlocks` | 日程；语义重定义 D6（false=忙碌硬块） |
| Knowledge | `features/anki` | 词条/复习。调度单元 `CardState(unit_key)`；`FsrsScheduler`、`ClozeEngine`、`DiffusionBoost` |
| Mindnet | `features/mindmap` | 导图 |

模块四个主导航 = Mindnet / Thread / Time / Knowledge；.kpak 知识库与设置降为次级入口（D4）。

## 3. 分层（v2）

```
┌ UI 层：Mindnet / Thread(顶栏+列表) / Time(日历) / Knowledge(复习) / 次级页 ┐
├ 应用层（Riverpod Notifier + UseCase 服务）：                           │
│   ThreadSortController / ReviewSessionController / ImportExportCtrl …   │
├ 领域层（纯 Dart，可单测）：                                             │
│   ThreadRanker(排序) · FsrsScheduler · ClozeEngine(自由挖空/出题)       │
│   DiffusionBoost(图谱扩散) · TimeWindowEngine(占用/空闲) ·              │
│   TagTreeService · TemplateService · BatchEditService                  │
├ 数据层：Drift v2 / Repositories / TfPkgCodec+Merge / ThemeStore /      │
│          FileStore(附件/背景图)                                        │
└ 基础设施：通知 / 文件对话框 / 本地化 / 外观(主题+缩放+字体)            ┘
```

规则沿用：UI 不写 SQL；业务规则在 domain/services 纯 Dart；数据经 Repository。

## 4. 核心流程（v2 闭环）

### 4.1 Thread 手动排序（定稿 1.1.3，取代自动重排）

```
用户改顶栏状态(精力/目标) → ThreadStates 持久化
点“更新与排序” → 若 updated_at 距今 >2h 先弹确认/修改窗
→ 引擎输入：待办事件集(tags/estimate/expected/due/energy) + 状态 + Time 占用/空闲窗口
→ ThreadRanker：
   ① 硬性约束过滤：estimate > (deadline-now)-区间忙碌时长 → 标红置底(时间不足 X/Y)
   ② 其余按 0.4紧急 + 0.3目标匹配 + 0.2状态适配 − 0.1疲劳 排序（常量表 GAP §4.1）
→ 呈现排序列表 + 每事件分解得分（可解释 UI）
禁止自动轮询/自动重排（D8）；完成事件写 CompletionLogs 供下次惩罚计算
```

### 4.2 Knowledge 复习闭环（定稿 1.3）

```
进入复习 → 到期单元(FSRS due) + 强制队列(10min 短间隔) 合并
抽卡：
  ① 图谱扩散：当前轮若存在 BoostEntry 按 factor 加权(×1.8/×1.3，remaining-1)
  ② 自由挖空：到期词条按概率(0.5)尝试新槽位(历史未用)；无新位→exhausted 标记，从历史槽位抽
  ③ 呈现形式：槽位→随机派生 单选/多选/有序多选/填空；预设卡按 type；词条整测→简答
判分：严格(auto 逐字符) / 非严格(self)（填空/简答），多选顺序全对才对（O5）
答错 → 即时重做一次 + forced=1 → 10min 后重出现 → 连续两次正确解除(forced_streak≥2)
FSRS 调度(忘记/模糊/记得→Again/Hard/Good) → 写 ReviewLogs
答错 → DiffusionBoost 写 BoostEntries(距1:×1.8 / 距2:×1.3, 3 周期)
用户可点“生成任务”→ 建 Thread 事件(标题=词条标题，标签随词条)
```

### 4.3 Mindnet 与 Thread 接口（定稿 1.4.3）

```
节点 → “导入为系”：子树逐节点建/关联树形标签（path 级联）→ 可打标签
节点 → “设为当前目标”：写 ThreadStates(goal_node_id/goal_path) → 目标匹配度按子树提升
节点 → 转任务（既有，保留）
导图导入导出：.mm / OPML 编解码（xml 轻量解析）
```

### 4.4 打包双轨（定稿 §3 / D4）

```
.kpak（班级分享子集，既有）：知识内容 only，不含个人数据
.tfpkg（全量工作区）：
  导出 = 逻辑全量转储 manifest.json + attachments/ + themes/ → zip(可选 AES-GCM 密码)
  导入 = 覆盖(先自动备份现库)/追加(按稳定 id 合并；知识类按 external/package id 升级去重)
```

### 4.5 主题与外观（定稿 §4 / D13）

```
Themes(payload JSON) + LocalSettings.active_theme_id
设置项：UI/编辑字体、缩放 0.8–1.5、语言、主/辅色、背景色/透明度/背景图(复制进内部目录)、动画开关
主题 JSON 导入导出；内置 light/dark
```

## 5. 状态管理（沿用 + 增补）

- Riverpod Notifier 各模块；Drift watch 流驱动 UI。
- 全局：语言、active theme、Thread 顶栏状态（ThreadStates 单行 watch）。
- 复习会话：`ReviewSessionController` 维护当前单元/强制队列/提权计数（会话内状态不落库的仅内存）。

## 6. 常量收口（D10）

算法缺省常量集中在 `domain/services/config/furnace_defaults.dart`（GAP §4.1–4.3 全表）。
FSRS 默认权重常量随实现锁版本（注明 ts-fsrs 对应版本）。UI 一律经 provider 读取，禁止散落硬编码。

## 7. 测试策略（v2）

| 层级 | 内容 |
| --- | --- |
| 单元测试 | ThreadRanker（权重/硬约束/疲劳衰减向量）、FSRS（官方默认权重样本对照）、ClozeEngine（新槽位概率/exhausted/强制绑定状态机）、DiffusionBoost（距离 BFS/衰减）、TimeWindowEngine（重复规则展开/占用/空闲窗口）、TagTree（path 级联）、TfPkgCodec（往返/合并/加密可选）、schema 迁移（v1→v2 数据保真） |
| Widget | 模块页渲染、顶栏、日历冒烟 |
| 手工 | Windows 实机离线闭环 |

## 8. 扩展点（沿用 + 修订）

- FSRS 权重后续可在设置页开放“排序规则/复习参数深度自定义”（定稿核心原则 3）。
- .tfpkg 增量备份、主题商店式分享（未来）。
- Android 端同一代码。
- 不再计划：云同步/账号（本地优先）；插件系统（不做）。

## 9. 安全与隐私要点（详见 PRIVACY.md）

- 默认无网络权限；.kpak 白名单不含个人数据；.tfpkg 全量含个人数据 → 导出前强提醒 + 可选密码；覆盖导入前自动备份。
