# 发布与分发（Windows + Android）

> 产品名：Threadflow（工作目录沿用 `class-productivity`，Dart 包名 `knowflow`，
> Android 包名 `com.threadflow.knowflow`）
> 环境实测日期：2026-09-19（本机）；Android 从零装好并**已产出可安装的 release APK**

---

## 0. 本机 Android 开发环境（从零装好，全部用户级、无需管理员）

这台机器**原先完全没有 Android SDK，也没有 JDK**。已按以下方式装好：

| 组件 | 位置 | 说明 |
| --- | --- | --- |
| JDK 21 | `C:\Program Files\Microsoft\jdk-21.0.12.101-hotspot` | `winget install --id Microsoft.OpenJDK.21`（微软 CDN 比 GitHub 稳） |
| Android SDK | `C:\AndroidDev\sdk` | 命令行工具解包；组件用 `sdkmanager` 装 |
| 环境变量 | `ANDROID_HOME` / `ANDROID_SDK_ROOT` = `C:\AndroidDev\sdk`；`JAVA_HOME` = JDK 路径 | 已写入**用户级**环境变量 |
| Flutter 配置 | `flutter config --android-sdk C:\AndroidDev\sdk` | 已写入 |
| Gradle 发行包 | `~\.gradle\wrapper\dists\gradle-9.3.1-all\...` | 见 §1.1，官方源太慢，从腾讯镜像取并**校验过官方 sha256** |
| 仓库镜像 init script | `~\.gradle\init.d\threadflow-google-cdn.gradle` | 见 §1.1 |

已安装的 SDK 组件（对齐 Flutter 3.47 要求：compileSdk 36 / minSdk 24 / NDK 28.2.13676358）：

```
platform-tools           platforms;android-36
build-tools;36.0.0       ndk;28.2.13676358   (2172 MB, sha1 已核对官方值)
```

> ⚠️ 网络注意：`dl.google.com` 与 Maven Central 通但很慢（~60–100 KB/s），GitHub 偶发 TLS/连接重置。
> 大文件用 `curl.exe -L --retry 10 --retry-all-errors -C -`；**看起来"卡住"往往是慢而不是失败**。

---

## 1. Android 构建（已实测通过）

一键脚本（推荐，已固化下面所有环境坑）：

```powershell
cd class-productivity
powershell -ExecutionPolicy Bypass -File scripts/build_android.ps1              # release APK
powershell -ExecutionPolicy Bypass -File scripts/build_android.ps1 -Mode debug  # debug APK
powershell -ExecutionPolicy Bypass -File scripts/build_android.ps1 -Mode appbundle
```

手动等价命令（注意：**必须从纯 ASCII 路径构建**，见 §1.1）：

```powershell
$env:JAVA_HOME="C:\Program Files\Microsoft\jdk-21.0.12.101-hotspot"
$env:ANDROID_HOME="C:\AndroidDev\sdk"
cmd /c mklink /J E:\threadflow-android "<真实项目 app 路径>"
cd E:\threadflow-android
flutter build apk --release
```

产物：

```
app/build/app/outputs/flutter-apk/app-debug.apk
app/build/app/outputs/flutter-apk/app-release.apk
app/build/app/outputs/bundle/release/app-release.aab
```

安装到手机（USB 调试打开）：

```powershell
C:\AndroidDev\sdk\platform-tools\adb.exe install -r <apk 路径>
```

### 实测验证结果（用 `aapt2` / `apksigner` 读真实 APK，不是推测）

| 项 | 值 |
| --- | --- |
| 包名 / 版本 | `com.threadflow.knowflow` / 0.1.0 |
| 应用名 | Threadflow |
| compileSdk / targetSdk | 36 / 36（minSdk 24，满足"Android 8+"） |
| native | `lib/arm64-v8a`、`armeabi-v7a`、`x86_64` 三套 `libsqlite3.so` 均已打包 |
| 权限 | `POST_NOTIFICATIONS`、`RECEIVE_BOOT_COMPLETED`、`VIBRATE` |
| release 签名 | `CN=Threadflow, OU=Personal, O=Threadflow, C=CN`（不再用 debug 证书） |

> ⚠️ keystore 是本地生成的 `android/threadflow-release.jks`，口令为开发用值
> （见 `android/key.properties`；两者都在 `android/.gitignore` 里）。
> **对外发布前请重新生成并妥善保管**：换 keystore 之后已安装的用户无法覆盖升级。

---

## 1.1 这台机器上必须知道的环境事实（否则会反复踩坑）

**A. 项目路径含非 ASCII**：工作区在 `E:\FirsryOS\Memory\一THREADRIPPER一\...`，由此引发三个问题：

1. AGP 直接拒绝：`Your project path contains non-ASCII characters` → `android.overridePathCheck=true`；
2. Kotlin 增量缓存写失败：`Could not close incremental caches ... class-fq-name-to-source.tab` → `kotlin.incremental=false`；
3. **release 的 AOT 快照器读不到 `app.dill`**（debug 走 JIT 所以没事）：
   `Unable to read file ...\flutter_build\<hash>\app.dill` → `Target android_aot_release_android-arm64 failed`。
   **必须从纯 ASCII 路径构建**。`scripts/build_android.ps1` 用目录 junction 解决：
   `mklink /J E:\threadflow-android <真实路径>`，再从该路径执行 `flutter build`。

**B. 网络受限**：`maven.google.com` **不可达**（`flutter doctor` 报其超时）；
`dl.google.com` 与 Maven Central 通，但只有 **~60–100 KB/s**，会以 `Read timed out` 失败。
实测对比（同一个 AGP jar，各传 8 秒）：

| 源 | 传输量 |
| --- | --- |
| `dl.google.com/dl/android/maven2` | 501 KB |
| `maven.aliyun.com/repository/google` | **12389 KB** |

因此 `android/gradle/google-cdn.init.gradle` 把所有指向 maven.google.com /
dl.google.com / Maven Central 的仓库改写到阿里云镜像。该文件同时安装到
`~/.gradle/init.d/threadflow-google-cdn.gradle`（Gradle 自动应用于**所有**构建，包括
Flutter 插件的 included build —— 第一版只钩 root build，插件构建仍在慢源上超时）。
hosts 文件不可用：无管理员权限不可写。

其他下载参考：Gradle 发行包 224MB 从官方源约 40 分钟、从腾讯镜像数秒；NDK 713MB 从腾讯镜像
下载后**校验 size 与官方 sha1 完全一致**（`size=748118221`、
`sha1=086bba43ff2f5eb0e387b15c8278bb4e0d89ba1d`）。

### Android 相关配置改动（相对 Flutter 模板）

- `AndroidManifest.xml`：应用名 `Threadflow`；新增 `POST_NOTIFICATIONS`（Android 13+ 必需，
  否则定时提醒被静默丢弃）、`RECEIVE_BOOT_COMPLETED`、`VIBRATE`。**没有**申请精确闹钟权限，
  因为 `NotificationService` 用的是 `AndroidScheduleMode.inexactAllowWhileIdle`。
- `app/build.gradle.kts`：`isCoreLibraryDesugaringEnabled = true` +
  `coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")`
  （`flutter_local_notifications` 要求）；release 签名配置（缺 keystore 时回退 debug，保证
  全新 clone 也能构建）。
- `pubspec.yaml`：sqlite3 构建 hook **不再用 `source: system`** —— 该模式按 `name_<系统>`
  取名，只配 `name_windows` 会让 Android 去找平台自带的 `libsqlite3.so`，而 NDK 不允许应用
  链接它；改用默认预编译库，Windows/Android 都可用（Windows 侧实测产出 `sqlite3.dll` 2.16MB）。
- `file_picker` 由 8.3.7 **升到 12.3.0**：旧版插件硬编码 `compileSdk 34`，与
  `flutter_plugin_android_lifecycle` 要求的 36 冲突，构建直接失败；升级后该冲突包已不在依赖树中，
  同时按 12.x 新 API 改了 3 处调用（`FilePicker.platform.*` → 静态方法、`saveFile` 需要 bytes
  并返回 `Uri?`、`PlatformFile.bytes` → `await readAsBytes()`）。
- 顺带修掉一个真 bug：设置页"备份数据"找的是 `knowflow.db`，而实际在用的是 `threadflow.db`
  —— 旧写法在全新安装上永远报 not found。

---

## 2. Windows 构建与分发

```powershell
cd class-productivity
powershell -ExecutionPolicy Bypass -File scripts/build_windows.ps1
# 或
cd app; flutter build windows --release
```

产物：`app/build/windows/x64/runner/Release/`（`knowflow.exe`）。
把该目录压成 zip 发给同学即可；或后续用 Inno Setup / MSIX 做安装包。

---

## 3. 数据与隐私

- 本地数据库（Windows）：`%APPDATA%\com.example\knowflow\threadflow.db`
  （若存在旧文件 `knowflow.db`，首次打开会就地迁移）。
- 手机端数据库位于应用私有目录，卸载即删。
- 分享请用软件内「导出知识包（.kpak）」，不含个人事件/日程/复习进度。
- 分发安装包时**不要**附带自己的数据库文件。
- 整库备份/换机用设置页的「导出工作区（.tfpkg）」；导入前会自动在应用数据目录写一份
  `pre-import-<时间戳>.tfpkg`。

---

## 4. Windows release 也需要 ASCII 路径（2026-09-19 实测）

`flutter build windows --release` 在本工作区**会失败**，报错与 Android release 同源：

```
CUSTOMBUILD : error : Unable to read file:
E:\FirsryOS\Memory\一THREADRIPPER一\class-productivity\app\.dart_tool\flutter_build\<hash>\app.dill
error MSB8066: ... flutter_assemble.vcxproj ... 已退出，代码为 1
```

`debug` 构建走 JIT，不受影响；`release` 需要 AOT 快照器读取 `app.dill`，而该路径经
MSBuild/CMake 传递时被非 ASCII 字符破坏。

**解决办法与 Android 相同：从纯 ASCII 的 junction 路径构建。**

```powershell
cmd /c mklink /J E:\threadflow-android "<真实项目 app 路径>"
cd E:\threadflow-android
Remove-Item .dart_tool\flutter_build -Recurse -Force -ErrorAction SilentlyContinue
flutter build windows --release
```

产物在 `E:\threadflow-android\build\windows\x64\runner\Release\`（实测 **35.66 MB** 打包为 zip，
`knowflow.exe` 启动后窗口正常、占用约 255 MB）。发版时把该目录压成 zip 分发。

---

## 5. 已知限制

- **字体文件导入**尚未实现（主题里可填字体族名称，但不能导入字体文件）。
- 「正文/编辑器字体」目前与界面字体共用同一套 ThemeData 字体族；两者的**独立**生效需要在
  阅读视图里再包一层 `DefaultTextStyle`，尚未做。
- 日程块暂不支持拖拽移动或拉伸边缘改时长；改时间走对话框。
- 界面仅验证了「能编译、能启动、有窗口」，**布局与手感需要在真机上确认**。

