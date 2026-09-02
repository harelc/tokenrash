#!/bin/zsh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

pkill -f "/Tokenrash.app/Contents/MacOS/Tokenrash" 2>/dev/null || true
sleep 0.2

"$ROOT/scripts/build.sh"

DEST="/Applications/Tokenrash.app"
rm -rf "$DEST"
ditto "$ROOT/dist/Tokenrash.app" "$DEST"
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true
open "$DEST"
echo "Installed $DEST"
