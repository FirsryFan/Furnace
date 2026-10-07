# Build the Furnace Windows release.
# Usage: powershell -ExecutionPolicy Bypass -File scripts/build_windows.ps1
#
# Why this script builds from an ASCII path
# -----------------------------------------
# This checkout lives under `E:\FirsryOS\Memory\一THREADRIPPER一\...`, and the
# release build's kernel-snapshot step cannot read its own output when that path
# contains non-ASCII characters. Measured 2026-10-02, building in place:
#
#   CUSTOMBUILD : error : Unable to read file:
#     ...\app\.dart_tool\flutter_build\<hash>\app.dill
#   error MSB8066: ... flutter_assemble.vcxproj ... exited with code 1.
#
# `scripts/build_android.ps1` hit the same class of problem and solved it the same
# way (§3 there): build through a junction whose path is pure ASCII. Everything
# else - `flutter create`, `pub get`, `gen-l10n`, `build_runner` - is happy in the
# real directory; only the release build itself runs from the junction.
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
    Write-Host "==> Ensuring platform directories ..."
    flutter create --platforms=windows .

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
