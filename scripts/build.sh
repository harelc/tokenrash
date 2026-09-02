#!/bin/zsh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SDK="$(xcrun --show-sdk-path)"
APP="$ROOT/dist/Tokenrash.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -parse-as-library \
  -O \
  -o "$APP/Contents/MacOS/Tokenrash" \
  -sdk "$SDK" \
  -target arm64-apple-macos14.0 \
  -framework SwiftUI -framework AppKit -framework WebKit -framework ServiceManagement \
  "$ROOT"/Sources/Tokenrash/*.swift

cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
chmod +x "$APP/Contents/MacOS/Tokenrash"
codesign --force --deep -s - "$APP" >/dev/null 2>&1 || true
echo "Built $APP"
