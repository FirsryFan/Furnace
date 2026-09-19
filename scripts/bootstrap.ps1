# Bootstrap the KnowFlow Flutter app on a machine with Flutter installed.
# Usage: powershell -ExecutionPolicy Bypass -File scripts/bootstrap.ps1

$ErrorActionPreference = "Stop"
$AppDir = Join-Path $PSScriptRoot "..\app"

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    Write-Error "Flutter is not installed or not on PATH. See docs/DEV_SETUP.md"
    exit 1
}

Push-Location $AppDir
try {
    Write-Host "==> Generating platform directories (Windows) ..."
    flutter create --platforms=windows .

    Write-Host "==> Installing dependencies ..."
    flutter pub get

    Write-Host "==> Generating localizations ..."
    flutter gen-l10n

    Write-Host "==> Generating Drift database code ..."
    # --force-jit avoids an AOT compiler write issue in some Windows paths.
    dart run build_runner build --force-jit

    Write-Host "==> Done. Run 'flutter run -d windows' to start."
}
finally {
    Pop-Location
}
