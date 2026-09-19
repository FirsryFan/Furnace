# Android 构建脚本（本机环境已实测通过）
#
# 为什么需要这个脚本
# ------------------
# 本机（2026-09 实测）从零装好了 Android 工具链，并且踩到了 5 个与"项目路径含中文"
# 及"网络受限"相关的坑。这些都不是代码问题，而是环境问题；脚本把它们固化下来，
# 免得每次构建重新踩一遍。详见 docs/DEPLOY.md。
#
#   1) 项目路径含非 ASCII（E:\FirsryOS\Memory\一THREADRIPPER一\...）：
#      - AGP 拒绝构建 -> gradle.properties 里 android.overridePathCheck=true
#      - Kotlin 增量缓存写失败 -> kotlin.incremental=false
#      - release 的 AOT 快照器读不到 app.dill（debug 走 JIT 所以没事）
#        -> 必须从一条纯 ASCII 路径构建，脚本用 junction 解决
#   2) maven.google.com 不可达、dl.google.com 与 Maven Central 只有 ~60KB/s
#      -> google-cdn.init.gradle 把所有仓库改写到阿里云镜像
#
# 用法
# ----
#   powershell -ExecutionPolicy Bypass -File scripts/build_android.ps1
#   powershell -ExecutionPolicy Bypass -File scripts/build_android.ps1 -Mode debug
#   powershell -ExecutionPolicy Bypass -File scripts/build_android.ps1 -Mode appbundle
#
# 产物
# ----
#   build\app\outputs\flutter-apk\app-release.apk
#   build\app\outputs\flutter-apk\app-debug.apk
#   build\app\outputs\bundle\release\app-release.aab

param(
    [ValidateSet('release', 'debug', 'appbundle')]
    [string]$Mode = 'release',
    [string]$AsciiPath = 'E:\threadflow-android'
)

$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$AppDir = Join-Path $ProjectRoot 'app'

# --- 1. 工具链环境（本机实测路径）-------------------------------------------
$JdkHome = 'C:\Program Files\Microsoft\jdk-21.0.12.101-hotspot'
$AndroidSdk = 'C:\AndroidDev\sdk'

if (-not (Test-Path $JdkHome)) {
    throw "找不到 JDK：$JdkHome。安装：winget install --id Microsoft.OpenJDK.21"
}
if (-not (Test-Path $AndroidSdk)) {
    throw "找不到 Android SDK：$AndroidSdk。见 docs/DEPLOY.md 第 0 节的安装步骤。"
}

$env:JAVA_HOME = $JdkHome
$env:ANDROID_HOME = $AndroidSdk
$env:ANDROID_SDK_ROOT = $AndroidSdk
$env:PATH = "$JdkHome\bin;$AndroidSdk\platform-tools;$env:PATH"

# --- 2. 仓库镜像 init script（幂等安装）-------------------------------------
$initSource = Join-Path $AppDir 'android\gradle\google-cdn.init.gradle'
$initDir = Join-Path $env:USERPROFILE '.gradle\init.d'
$initTarget = Join-Path $initDir 'threadflow-google-cdn.gradle'
New-Item -ItemType Directory -Force -Path $initDir | Out-Null
Copy-Item $initSource $initTarget -Force
Write-Host "[build_android] 仓库镜像已安装到 $initTarget"

# --- 3. 纯 ASCII 构建路径（junction 到真实目录）-----------------------------
# release 的 AOT 编译要求 ASCII 路径；debug 不要求，但统一走同一条路径更省心。
if (-not (Test-Path $AsciiPath)) {
    Write-Host "[build_android] 创建 junction: $AsciiPath -> $AppDir"
    cmd /c mklink /J "$AsciiPath" "$AppDir" | Out-Null
}
if (-not (Test-Path (Join-Path $AsciiPath 'pubspec.yaml'))) {
    throw "junction 不可用：$AsciiPath 下没有 pubspec.yaml"
}

# build/ 里可能残留含中文绝对路径的缓存，release AOT 会读不到 app.dill
if ($Mode -ne 'debug') {
    Remove-Item (Join-Path $AsciiPath '.dart_tool\flutter_build') -Recurse -Force -ErrorAction SilentlyContinue
}

# --- 4. 构建 ----------------------------------------------------------------
Push-Location $AsciiPath
try {
    Write-Host "[build_android] flutter build apk --$Mode   (from $AsciiPath)"
    switch ($Mode) {
        'appbundle' { flutter build appbundle --release }
        'debug' { flutter build apk --debug }
        default { flutter build apk --release }
    }
    if ($LASTEXITCODE -ne 0) {
        throw "flutter build 失败，退出码 $LASTEXITCODE"
    }

    Write-Host ''
    Write-Host '[build_android] 产物：'
    Get-ChildItem 'build\app\outputs\flutter-apk' -ErrorAction SilentlyContinue |
        Select-Object Name, @{ n = 'MB'; e = { [math]::Round($_.Length / 1MB, 2) } } |
        Format-Table -AutoSize
    Get-ChildItem 'build\app\outputs\bundle\release' -ErrorAction SilentlyContinue |
        Select-Object Name, @{ n = 'MB'; e = { [math]::Round($_.Length / 1MB, 2) } } |
        Format-Table -AutoSize

    # 签名与清单校验：不是"应该没问题"，而是读出真实值。
    $apk = 'build\app\outputs\flutter-apk\app-release.apk'
    if ($Mode -eq 'release' -and (Test-Path $apk)) {
        Write-Host '[build_android] 签名：'
        & "$AndroidSdk\build-tools\36.0.0\apksigner.bat" verify --print-certs $apk |
            Select-Object -First 2
    }
}
finally {
    Pop-Location
}
