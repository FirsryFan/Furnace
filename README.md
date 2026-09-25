# Furnace

**Furnace** 的代码仓库 —— 面向高密度信息工作者的**本地优先**生产力工具。

四大核心模块：

| 模块 | 作用 |
| --- | --- |
| **Thread** | 动态优先级事件流：加权综合排序（紧急度 / 目标匹配 / 状态适配 / 期望压力 / 同类疲劳惩罚），全部参数对用户公开可编辑 |
| **Time** | 日程与时间轴：日/周/月 + 可自定义长度的多年时间轴（缩放 / 折叠），支持日模板与周模板一键排课 |
| **Knowledge** | 间隔重复记忆：FSRS-6 调度、自由挖空、错题强制绑定、按天复习复盘 |
| **标签（原 Mindnet）** | 树形标签体系，同时承担目标匹配与图谱扩散的“图” |

> 核心原则：**本地优先**（不联网、无账号、无遥测）· **文件化传输**（`.tfpkg` 全量打包 / `.kpak` 班级分享）· **高自定义**。
> 目标平台：**Windows 10/11** 与 **Android 8+**（同一套 Flutter 代码）。

## 当前状态

| 能力 | 状态 |
| --- | --- |
| 数据层（Drift SQLite，schema v5，26+ 表，v1→v5 幂等迁移 + 缺失列自愈） | ✅ |
| Thread 排序引擎（权重归一化、deadline 硬约束、期望时刻黄标提权） | ✅ |
| Knowledge 复习引擎（FSRS-6、自由挖空、错题绑定、严格判分、标签树扩散、按天台账） | ✅ |
| 界面（Thread / Time 日历 / Knowledge 复习 / 标签树 / 设置 / 使用文档） | ✅ |
| `.tfpkg` 全量打包编解码 + 覆盖/追加合并 | ✅ 库层 + **设置页已接入** |
| 主题 JSON（颜色/背景/字体/缩放/动画）+ 外观设置页 | ✅ **已接入设置页并在全局生效** |
| Windows 构建 | ✅ 实测可运行（`furnace.exe`） |
| Android 构建 | ✅ 实测产出已签名 release APK（61.7 MB） |
| 自动化测试 | **190 项全绿**；`dart analyze` **0 error / 0 warning** |

**尚未实现**：字体文件导入、正文与界面分开的字体、日程块的拖拽移动/拉伸改时长、真机（Android 手机）运行验证。

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
  test/                  190 项测试，与 lib 结构对应
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
flutter test                 # 172 项
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
| [docs/DESIGN_BLUEPRINT.md](docs/DESIGN_BLUEPRINT.md) | 设计蓝图 v2（已按用户批注修订，当前开发依据） |
| [docs/FURNACE_SPEC.md](docs/FURNACE_SPEC.md) | 产品权威规范（定稿） |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) · [docs/DATA_MODEL.md](docs/DATA_MODEL.md) | 技术架构与数据模型 |
| [docs/DEPLOY.md](docs/DEPLOY.md) | 构建、环境事实与踩坑记录 |
| [docs/PROGRESS.md](docs/PROGRESS.md) | 逐轮开发进展（长期记忆） |
| [docs/GAP_ANALYSIS.md](docs/GAP_ANALYSIS.md) · [docs/FEATURE_MATRIX.md](docs/FEATURE_MATRIX.md) | 差距分析与功能矩阵 |

## 许可

MIT，见 [LICENSE](LICENSE)。
