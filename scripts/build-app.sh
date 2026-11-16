#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

make --no-print-directory release

BIN="$ROOT/.build/StudyFullTime"
APP="$ROOT/.build/StudyFullTime.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"

if [[ ! -x "$BIN" ]]; then
    echo "error: expected executable at $BIN" >&2
    exit 1
fi

rm -rf "$APP"
mkdir -p "$MACOS" "$CONTENTS/Resources"

cp "$BIN" "$MACOS/StudyFullTime"

cat > "$CONTENTS/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>StudyFullTime</string>
    <key>CFBundleExecutable</key>
    <string>StudyFullTime</string>
    <key>CFBundleIdentifier</key>
    <string>local.studyfulltime</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>StudyFullTime</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>11.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

printf 'APPL????' > "$CONTENTS/PkgInfo"

if command -v codesign >/dev/null 2>&1; then
    codesign --force --sign - --timestamp=none "$APP" >/dev/null 2>&1 || \
        echo "warning: ad-hoc code signing failed; the app may still run"
fi

echo "Built $APP"
