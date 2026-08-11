#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PACKAGE_DIR=${SCRIPT_DIR:h}
PROJECT_DIR=${PACKAGE_DIR:h:h}
APP_BUNDLE="$PROJECT_DIR/dist/Clearframe.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MODULE_CACHE="$PACKAGE_DIR/.build/module-cache"

mkdir -p "$MODULE_CACHE"
export CLANG_MODULE_CACHE_PATH="$MODULE_CACHE"
export SWIFTPM_MODULECACHE_OVERRIDE="$MODULE_CACHE"
swift build --disable-sandbox --package-path "$PACKAGE_DIR" -c release

mkdir -p "$CONTENTS_DIR/MacOS" "$CONTENTS_DIR/Resources"
install -m 755 "$PACKAGE_DIR/.build/release/ClearframeBrowser" "$CONTENTS_DIR/MacOS/ClearframeBrowser"
cp "$PACKAGE_DIR/App/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$PACKAGE_DIR/App/PkgInfo" "$CONTENTS_DIR/PkgInfo"
touch "$APP_BUNDLE"

plutil -lint "$CONTENTS_DIR/Info.plist"
codesign --force --deep --sign - "$APP_BUNDLE"
codesign --verify --deep --strict "$APP_BUNDLE"
echo "Built local development app (ad hoc only; not Developer ID signed): $APP_BUNDLE"
