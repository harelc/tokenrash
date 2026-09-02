#!/bin/zsh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

pkill -f "/Tokenrash.app/Contents/MacOS/Tokenrash" 2>/dev/null || true
sleep 0.2

SDK="$(xcrun --show-sdk-path)"
APP="$ROOT/dist/Tokenrash.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -parse-as-library \
  -O \
  -o "$APP/Contents/MacOS/Tokenrash" \
  -sdk "$SDK" \
  -target arm64-apple-macos14.0 \
  -framework SwiftUI -framework AppKit -framework WebKit \
  "$ROOT"/Sources/Tokenrash/*.swift

cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
chmod +x "$APP/Contents/MacOS/Tokenrash"
codesign --force --deep -s - "$APP" >/dev/null 2>&1 || true
open "$APP"
echo "Launched $APP"
