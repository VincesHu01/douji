#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
cd "$ROOT_DIR"
mkdir -p "$ROOT_DIR/.build/module-cache" "$ROOT_DIR/.build/xdg-cache"
CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.build/module-cache" \
SWIFTPM_MODULECACHE_OVERRIDE="$ROOT_DIR/.build/module-cache" \
XDG_CACHE_HOME="$ROOT_DIR/.build/xdg-cache" \
swift build -c release --disable-sandbox --scratch-path "$ROOT_DIR/.build"

APP_DIR="$ROOT_DIR/dist/豆迹.app"
CONTENTS_DIR="$APP_DIR/Contents"
mkdir -p "$CONTENTS_DIR/MacOS"
mkdir -p "$CONTENTS_DIR/Resources"
cp "$ROOT_DIR/.build/release/DoubaoRecall" "$CONTENTS_DIR/MacOS/DoubaoRecall"
cp "$ROOT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$ROOT_DIR/Resources/AppIcon.icns" "$CONTENTS_DIR/Resources/AppIcon.icns"
codesign --force --deep --sign - "$APP_DIR"
echo "$APP_DIR"
