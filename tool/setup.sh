#!/usr/bin/env bash
# BankSheet Pro — one command to make a checkout buildable. macOS and Linux.
#
#     ./tool/setup.sh
#
# Run this after `git clone`, after `git pull`, and any time the app comes up
# with the Flutter logo instead of its own icon.
#
# WHY IT IS NEEDED EVERY TIME
# ---------------------------
# `android/` and `ios/` are in .gitignore — they are regenerated per machine and
# per Flutter version. `flutter create` fills them with FLUTTER's defaults:
# Flutter's icon, Flutter's splash screen, an applicationId derived from the
# project name, no PDF intent filters, and — on iOS — no camera usage
# description, which terminates the app the first time the scanner is opened.
# `apply.py` puts this app's identity back on top.
#
# Missing this step does not fail the build. It ships the wrong app. So the
# script ends by verifying, and exits non-zero if anything did not land.
set -euo pipefail

cd "$(dirname "$0")/.."
echo "BankSheet Pro setup in $(pwd)"

step() {
    echo
    echo "== $1"
    shift
    "$@"
}

PY="${PYTHON:-python3}"

step "flutter pub get" flutter pub get

step "flutter create (regenerates android/ and ios/)" \
    flutter create . --platforms=android,ios --org pro.banksheet --project-name banksheet_mobile

step "make_icons.py (icon + launch screen assets)" \
    "$PY" tool/native/make_icons.py

step "apply.py (identity, icons, launch screen, intent filters, signing)" \
    "$PY" tool/native/apply.py

# CocoaPods, but only on a Mac with the iOS tree present.
if [[ "$(uname)" == "Darwin" && -d ios && -n "$(ls -A ios 2>/dev/null)" ]]; then
    if command -v pod >/dev/null 2>&1; then
        step "pod install" bash -c 'cd ios && pod install'
    else
        echo
        echo "!! CocoaPods not installed — run 'sudo gem install cocoapods',"
        echo "   then 'cd ios && pod install' before building for iOS."
    fi
fi

step "verify.py" "$PY" tool/native/verify.py

cat <<'EOF'

Ready. Next:
    flutter run                     # simulator or device
    flutter build ipa --release     # App Store
    flutter build appbundle --release   # Play

On iOS you still need to set your Team in Xcode and add the In-App Purchase
capability:  open ios/Runner.xcworkspace
EOF
