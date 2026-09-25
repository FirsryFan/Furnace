# 开发环境设置

> 项目：Furnace
> 技术栈：Flutter（Windows 优先）

---

## 1. 安装 Flutter

1. 前往 <https://docs.flutter.dev/get-started/install/windows> 下载 Flutter SDK。
2. 解压到例如 `C:\src\flutter`。
3. 把 `C:\src\flutter\bin` 加入系统 PATH。
4. 打开 PowerShell 验证：

```powershell
flutter --version
```

5. 运行 `flutter doctor`，确保 Windows 桌面开发工具可用：

```powershell
flutter doctor
```

需要时安装 Visual Studio 2022 的“使用 C++ 的桌面开发”工作负载。

---

## 2. 初始化本项目

项目源码在 `class-productivity/app`。由于当前仓库只提交了 Dart 源码和配置，第一次需要在有 Flutter 的机器上生成平台目录：

```powershell
cd class-productivity/app

# 生成 Windows 平台目录（以及其他缺失平台文件）
flutter create --platforms=windows .

# 安装依赖
flutter pub get

# 生成本地化文件（构建时也会自动生成，这里显式执行一次便于 IDE 识别）
flutter gen-l10n

# 生成 Drift 数据库代码（表结构变更后也需要重新执行）
# 使用 --force-jit 可避免部分 Windows 路径下 AOT 写入失败的问题
dart run build_runner build --force-jit
```

---

## 3. 运行

```powershell
flutter run -d windows
```

---

## 4. 数据库代码生成

数据层使用 Drift，表结构改动后需要重新生成代码：

```powershell
dart run build_runner build --delete-conflicting-outputs
```

---

## 5. 测试

```powershell
flutter test
```

---

## 6. 目录约定

```
lib/
  app/          # 应用壳、路由、主题、设置状态
  core/         # 通用组件与工具
  features/     # 各功能模块（mindmap/tasks/timeboard/anki/packages/settings）
  data/         # Drift 数据库、Repository 实现
  domain/       # 实体与算法服务（SRS、任务调度、挖空）
```
