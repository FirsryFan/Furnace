# Threadflow — Flutter 应用

这是 [Furnace](../README.md) 仓库里的 Flutter 应用本身。产品定位、模块说明、
当前状态与已知未完成项，请看**仓库根目录的 [README](../README.md)**。

## 快速开始

```powershell
flutter pub get
flutter test                  # 172 项，应全绿
dart analyze                  # 应为 0 error
flutter run -d windows        # Windows 桌面
```

Android 构建请用仓库脚本，并**先读 [../docs/DEPLOY.md](../docs/DEPLOY.md)**：

```powershell
powershell -ExecutionPolicy Bypass -File ..\scripts\build_android.ps1
```

原因：开发机项目路径含非 ASCII 字符，会让 release 的 AOT 编译失败（脚本用目录 junction 绕开）；
仓库镜像、`file_picker` 版本等 6 个坑也都记录在 DEPLOY.md 里。

## 代码生成

两处生成物**已经提交进版本控制**，正常开发不需要跑生成器：

- `lib/data/database/database.g.dart` —— Drift schema（改动 `tables.dart` 后需重新生成）
- `lib/l10n/app_localizations*.dart` —— 由 ARB 生成（改动 `lib/l10n/app_*.arb` 后重新生成）

要重新生成时：

```powershell
dart run build_runner build --delete-conflicting-outputs --force-jit
flutter gen-l10n
```

> `--force-jit` 不是可选项：本机沙箱会拦截 build_runner 的 AOT 快照写盘。

## 目录（与 `lib/` 对应）

```
lib/app/          入口、外壳、设置控制器
lib/core/         主题模型、通知
lib/data/         Drift 数据库与仓库、.kpak/.tfpkg 编解码、ID 生成
lib/domain/       纯 Dart 算法：ThreadRanker、FSRS、挖空、扩散、时间窗口
lib/features/     thread / timeboard / anki(Knowledge) / tags / settings / packages
test/             与 lib 结构对应的测试
```

设计依据见 [../docs/DESIGN_BLUEPRINT.md](../docs/DESIGN_BLUEPRINT.md)（已按用户批注修订），
产品权威规范见 [../docs/THREADFLOW_SPEC.md](../docs/THREADFLOW_SPEC.md)。
