# BankSheet Pro — one command to make a checkout buildable.
#
#     .\tool\setup.ps1
#
# Run this after `git clone`, after `git pull`, and any time the app comes up
# with the Flutter logo instead of its own icon.
#
# WHY IT IS NEEDED EVERY TIME
# ---------------------------
# `android/` and `ios/` are in .gitignore — they are regenerated per machine and
# per Flutter version. `flutter create` fills them with FLUTTER's defaults:
# Flutter's icon, Flutter's splash screen, an applicationId derived from the
# project name, and no PDF intent filters. `apply.py` puts this app's identity
# back on top. Miss it and the build still succeeds — you just ship the wrong
# app.
#
# The script stops on the first failure and finishes by verifying the result,
# so "it printed OK" and "the phone will look right" are the same statement.

$ErrorActionPreference = 'Stop'

# Run from the project root no matter where this was invoked from.
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root
Write-Host "BankSheet Pro setup in $root" -ForegroundColor Cyan

function Invoke-Step($label, $block) {
    Write-Host ""
    Write-Host "== $label" -ForegroundColor Cyan
    & $block
    if ($LASTEXITCODE -ne 0) {
        Write-Host "   failed: $label" -ForegroundColor Red
        exit 1
    }
}

# `py` is the Windows launcher and is present on almost every Python install;
# `python` is not always on PATH. Prefer whichever exists.
$py = if (Get-Command py -ErrorAction SilentlyContinue) { 'py' } else { 'python' }

Invoke-Step "flutter pub get" { flutter pub get }

Invoke-Step "flutter create (regenerates android/ and ios/)" {
    flutter create . --platforms=android,ios --org pro.banksheet --project-name banksheet_mobile
}

Invoke-Step "make_icons.py (icon + launch screen assets)" {
    & $py tool\native\make_icons.py
}

Invoke-Step "apply.py (identity, icons, launch screen, intent filters, signing)" {
    & $py tool\native\apply.py
}

Invoke-Step "verify.py" {
    & $py tool\native\verify.py
}

Write-Host ""
Write-Host "Ready. Next:" -ForegroundColor Green
Write-Host "    flutter run --release          # on the phone"
Write-Host "    flutter build appbundle --release   # for Play"
Write-Host ""
Write-Host "If the phone still shows the old icon, the icon is baked into the" -ForegroundColor Yellow
Write-Host "installed APK: run 'flutter clean', rebuild, and if it persists" -ForegroundColor Yellow
Write-Host "uninstall the app once — some launchers cache it until reinstall." -ForegroundColor Yellow
