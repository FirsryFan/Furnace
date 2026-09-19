# Build the KnowFlow Windows release.
# Usage: powershell -ExecutionPolicy Bypass -File scripts/build_windows.ps1

$ErrorActionPreference = "Stop"
$AppDir = Join-Path $PSScriptRoot "..\app"

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

    Write-Host "==> Building Windows release ..."
    flutter build windows --release
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Flutter Windows build failed. Run 'flutter doctor' for toolchain details."
        exit $LASTEXITCODE
    }

    Write-Host "==> Build complete."
    Write-Host "Output: build\windows\x64\runner\Release\"
}
finally {
    Pop-Location
}
