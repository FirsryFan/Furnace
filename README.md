# Furnace

**Furnace** 的代码仓库 —— 面向高密度信息工作者的**本地优先**生产力工具。

四大核心模块：

| 模块 | 作用 |
| --- | --- |
| **Thread** | 动态优先级事件流：加权综合排序（紧急度 / 目标匹配 / 状态适配 / 期望压力 / 同类疲劳惩罚），全部参数对用户公开可编辑 |
| **Time** | 日程与时间轴：日/周/月 + 可自定义长度的多年时间轴（缩放 / 折叠），支持日模板与周模板一键排课 |
| **Knowledge** | 间隔重复记忆：FSRS-6 调度、自由挖空、错题强制绑定、按天复习复盘 |
| **标签** | 树形标签体系：组织、筛选与用途边界（卡组 = 标签） |
| **MindNet** | 用户模型引擎：记忆/思维/判断建模，驱动个性化找题、排序、复习推送与精力预测（顶层模块，见 docs/DECISIONS-2026-11.md D03） |

> 核心原则：**本地优先**（不联网、无账号、无遥测）· **文件化传输**（`.tfpkg` 全量打包 / `.kpak` 班级分享）· **高自定义**。
> 目标平台：**Windows 10/11** 与 **Android 8+**（同一套 Flutter 代码）。
>
> 当前版本：**0.6.12+32**（dev 测试构建；最新 tag 仍是 `v0.6.12`；main 上 schema 已到 **v42**，未发版）。除核心模块外，App 里还有：**题库**（题目/题源/组卷/Word 导出）、**内置 AI「智能化」**（一等模块：收题、找题、组卷、排计划）、**用户评测板块**（能力/认知参数，归入 MindNet 用户模型）、**知识库 `.kpak`**（已下沉设置）、**题库包 `.tqb` 与采集管线**。Windows 数据默认目录为 `E:\Furnace\data`（可用指针文件重定位）。完整接手说明见 [docs/HANDOFF.md](docs/HANDOFF.md)。

## 当前状态

| 能力 | 状态 |
| --- | --- |
| 数据层（Drift SQLite，schema **v42**，**57 表**，v1→v42 幂等迁移 + 缺失列/表自愈） | ✅ |
| MindNet 顶层模块（认知模型 / 知识网络 / 今日清单 / 机制参数 / 评测档案入口） | ✅ 入口已接；引擎实现分阶段（D03） |
| AI 一等模块（入口常驻，未配 key 时页面内配置引导；工具平台门控基础） | ✅ 基础 | 
| 知识库下沉设置（启用/禁用/卸载/导入导出） | ✅（schema v42） |
| Windows 数据目录迁 `E:\Furnace\data`（指针文件 + 一次性复制迁移 + 失败回退） | ✅ 代码与单测；真机端到端待验 |
| MindNet 精力预测（纯逻辑 22 测试 + Thread 顶栏预测值/手动覆盖/“用预测值”） | ✅ 逻辑与 UI 已接 |
| Thread 排序引擎（权重归一化、deadline 硬约束、期望时刻黄标提权） | ✅ |
| Knowledge 复习引擎（FSRS-6、自由挖空、错题绑定、严格判分、标签树扩散、按天台账） | ✅ |
| 界面（Thread / Time 日历 / Knowledge 复习 / 标签树 / 设置 / 使用文档） | ✅ |
| `.tfpkg` 全量打包编解码 + 覆盖/追加合并 | ✅ 库层 + **设置页已接入** |
| 主题 JSON（颜色/背景/字体/缩放/动画）+ 外观设置页 | ✅ **已接入设置页并在全局生效** |
| **AI「智能化」**（agent loop + 工具层 + 审批引擎 + 对话界面 + live 对比 harness） | ✅ 闭环已实现；入口常驻，未配 key 时页面内给配置引导 |
| Windows 构建 | ✅ 实测可运行（`furnace.exe`） |
| Android 构建 | ✅ 实测产出已签名 release APK（62.08 MB，`com.furnace.app`） |
| 诊断包导出（含题目与 AI 内容、绝不含 key；设置 → 数据） | ✅ 服务 + UI + 5 测试 |
| 题目详情「MindNet 认知评价」卡（题目内容 × 认知模型融合第一块界面） | ✅ provider + 详情页卡 + 17 测试；en 判词文案待 l10n |
| 每日自动化（06:00 组卷网抓题 + 题库 L2 初步加工；06:30 每日检验清单 issue） | ✅ Windows 计划任务已注册；真实批次待首跑 |
| 自动化测试 | 轮次 188 全量 **+6864 通过 / 2 跳过**（3 个旧断言更新后单跑全绿）；轮次 189 改动区域 scoped 117 例全绿；`dart analyze lib test` = **87 issues / 0 error / 0 warning** |

**尚未实现 / 待验证**：双端真机逐屏手测、采集管线 M2 剩余（材料容器与材料练习记录）、能力点录入与 T×A 报表、页面级设计 token 迁移、6:2:2 复习配额、错题按能力点自动建卡组、任务侧批量提前；云同步明确不做。详见 [docs/HANDOFF.md](docs/HANDOFF.md) 第 16 节。

## 目录结构

```
app/                     Flutter 应用
  lib/
    app/                 入口、外壳、设置控制器
    core/                主题（theme_profile.dart）、通知
    data/                Drift 数据库、仓库、.kpak/.tfpkg 编解码、ID 生成
    domain/              纯 Dart 算法：排序、FSRS、挖空、扩散、时间窗口、主题模型
    features/            thread / timeboard / anki(Knowledge) / tags / settings / packages
    l10n/                中英 ARB 与生成的本地化
  test/                  408 个测试文件，与 lib 结构对应
  android/               Android 工程 + 构建期 Gradle 修补
  windows/               Windows 工程
docs/                    设计蓝图、权威规范、差距分析、进度、部署
scripts/                 构建脚本（Windows / Android）
```

## 构建

### Windows

```powershell
cd app
flutter build windows --release
# 或
powershell -ExecutionPolicy Bypass -File scripts/build_windows.ps1
```

### Android

```powershell
powershell -ExecutionPolicy Bypass -File scripts/build_android.ps1
# 可选：-Mode debug / -Mode appbundle
```

**首次在 Android 上构建前请读 [docs/DEPLOY.md](docs/DEPLOY.md)** —— 里面记录了 6 个必须避开的坑，包括
`maven.google.com` 不可达需要用镜像、项目路径含非 ASCII 会让 release 的 AOT 编译失败（脚本已用
junction 自动处理）、以及 `file_picker` 的版本冲突。

### 测试

```powershell
cd app
flutter test                 # 308 项
dart analyze                 # 应为 0 error
```

## 签名（发布前必读）

本仓库**不包含**签名密钥 —— 它是公开仓库，密钥一旦提交即等同泄露。

- 未配置 keystore 时 `flutter build apk` **仍然可用**，只是回退用 debug 证书签名，
  可以自己装到手机上测试，但不适合分发。
- 要做可分发的构建，请先生成自己的 keystore 并写入 `app/android/key.properties`
  （两者都已被 `.gitignore` 排除），详见 [docs/DEPLOY.md](docs/DEPLOY.md)。

## 文档

| 文档 | 内容 |
| --- | --- |
| [docs/HANDOFF.md](docs/HANDOFF.md) | **接手先读**：现状、硬约束、环境坑、验证方法、未完成项 |
| [docs/DECISIONS-2026-11.md](docs/DECISIONS-2026-11.md) | **决策唯一登记处**：2026-11 用户评审后的 D01–D09（定位/平台/MindNet/AI/题库四层/全量记录/知识库/数据目录/精力预测） |
| [docs/MINDNET_FIRST_CLASS_DESIGN.md](docs/MINDNET_FIRST_CLASS_DESIGN.md) | MindNet 扶正设计：撤销"并入标签"、现状盘点、目标架构与分阶段 |
| [docs/QUESTION_MATURITY_PIPELINE.md](docs/QUESTION_MATURITY_PIPELINE.md) | 题库四层成熟度管线与 AI 自主"整"的设计 |
| [docs/PLATFORM_CAPABILITY_MATRIX.md](docs/PLATFORM_CAPABILITY_MATRIX.md) | Android/Windows 任务分级与"不可用不给入口"门控矩阵 |
| [docs/OPEN_DECISIONS.md](docs/OPEN_DECISIONS.md) | 已做的决定 + 需要用户定夺的问题 |
| [docs/DESIGN_BLUEPRINT.md](docs/DESIGN_BLUEPRINT.md) | 设计蓝图 v2（已按用户批注修订，当前开发依据） |
| [docs/FURNACE_SPEC.md](docs/FURNACE_SPEC.md) | 产品权威规范（定稿） |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) · [docs/DATA_MODEL.md](docs/DATA_MODEL.md) | 技术架构与数据模型 |
| [docs/DEPLOY.md](docs/DEPLOY.md) | 构建、环境事实与踩坑记录 |
| [docs/PROGRESS.md](docs/PROGRESS.md) | 逐轮开发进展（长期记忆） |
| [docs/AI_DESIGN.md](docs/AI_DESIGN.md) | AI 集成设计（20 条决策与依据） |
| [docs/APPEARANCE_DESIGN.md](docs/APPEARANCE_DESIGN.md) | 界面个性化设计（现状核对 + 图标/主题色/字体方案） |
| [docs/SKILL_FORMAT.md](docs/SKILL_FORMAT.md) | `.fskill` 包格式与安全边界 |
| [docs/MINDNET_CONTRACT.md](docs/MINDNET_CONTRACT.md) | 与 MindNet 的接口约定（双方回应都在里面） |
| [docs/GAP_ANALYSIS.md](docs/GAP_ANALYSIS.md) · [docs/FEATURE_MATRIX.md](docs/FEATURE_MATRIX.md) | 差距分析与功能矩阵 |
| [docs/USER_GUIDE.md](docs/USER_GUIDE.md) | **用户使用指南**：AI 能做什么、高频指令、学习闭环、考前提前复习 |
| [docs/HANDOFF_PIPELINE.md](docs/HANDOFF_PIPELINE.md) | **采集管线交接（handoff M1–M4）**：`.tqb` 新字段、Markdown 渲染、扩展题/能力标签、契约验证命令与未做项 |

## 许可

MIT，见 [LICENSE](LICENSE)。
