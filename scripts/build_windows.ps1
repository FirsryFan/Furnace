# Build the Furnace Windows release.
# Usage: powershell -ExecutionPolicy Bypass -File scripts/build_windows.ps1
#
# Why this script may build through an ASCII junction
# ------------------------------------------------
# HISTORY: this checkout used to live under a non-ASCII path
# (E:\FirsryOS\Memory\一THREADRIPPER一\Furnace). The release build's
# kernel-snapshot step could not read its own output when the path contained
# non-ASCII characters (measured 2026-10-02): error MSB8066, "Unable to read
# file ...\flutter_build\<hash>\app.dill".
#
# FIX: on 2026-11-01 the repository was moved to the pure-ASCII path
# E:\Projects\Furnace, so the in-place release build now works.
# The junction option is retained for compatibility (E:\Document\furnace-build
# is still redirected to the new app path); use -AsciiPath to build through it.
# Everything else - `flutter create`, `pub get`, `gen-l10n`, `build_runner` -
# has always been happy in the real directory.
#
# Output: <junction>\build\windows\x64\runner\Release\ - the same files as
# app\build\windows\x64\runner\Release\, because a junction is not a copy.

param(
    [string]$AsciiPath = 'E:\Document\furnace-build'
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$AppDir = Join-Path $ProjectRoot "app"

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    Write-Error "Flutter is not installed or not on PATH. See docs/DEV_SETUP.md"
    exit 1
}

Push-Location $AppDir
try {
    # Only scaffold when the Windows runner is missing: an unconditional
    # `flutter create` rewrites version-control-adjacent metadata (e.g. app/.metadata)
    # and turns a release build into a diff.
    if (-not (Test-Path (Join-Path $AppDir 'windows\CMakeLists.txt'))) {
        Write-Host "==> Ensuring platform directories ..."
        flutter create --platforms=windows .
    }

    Write-Host "==> Installing dependencies ..."
    flutter pub get

    Write-Host "==> Generating localizations ..."
    flutter gen-l10n

    Write-Host "==> Generating Drift database code ..."
    # --force-jit avoids an AOT compiler write issue in some Windows paths.
    dart run build_runner build --force-jit
}
finally {
    Pop-Location
}

# --- ASCII build path (junction to the real directory) ----------------------
$legacyAscii = 'E:\Document\threadflow-build'
$resolved = $null
foreach ($cand in @($AsciiPath, $legacyAscii)) {
    if (-not $cand) { continue }
    if (Test-Path (Join-Path $cand 'pubspec.yaml')) { $resolved = $cand; break }
}
if ($resolved) {
    if ($resolved -ne $AsciiPath) {
        Write-Host "[build_windows] reusing existing ASCII build path: $resolved"
    }
    $AsciiPath = $resolved
} else {
    Write-Host "[build_windows] creating junction: $AsciiPath -> $AppDir"
    cmd /c mklink /J "$AsciiPath" "$AppDir" | Out-Null
}
if (-not (Test-Path (Join-Path $AsciiPath 'pubspec.yaml'))) {
    throw "junction unusable: no pubspec.yaml under $AsciiPath"
}

# A cached build tree may carry absolute paths from the non-ASCII location.
Remove-Item (Join-Path $AsciiPath '.dart_tool\flutter_build') -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "==> Building Windows release (from $AsciiPath) ..."
Push-Location $AsciiPath
try {
    flutter build windows --release
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Flutter Windows build failed. Run 'flutter doctor' for toolchain details."
        exit $LASTEXITCODE
    }

    Write-Host "==> Build complete."
    # The shell exe stays small and keeps its old timestamp by design; the Dart
    # code lives in app.so, so that file's timestamp is what proves the build is
    # actually new.
    $release = 'build\windows\x64\runner\Release'
    Get-Item (Join-Path $release 'data\app.so') -ErrorAction SilentlyContinue |
        Select-Object FullName, @{ n = 'MB'; e = { [math]::Round($_.Length / 1MB, 2) } }, LastWriteTime |
        Format-List
    Write-Host "Output: $AsciiPath\build\windows\x64\runner\Release\"
}
finally {
    Pop-Location
}
