#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PACKAGE_DIR=${SCRIPT_DIR:h}
PROJECT_DIR=${PACKAGE_DIR:h:h}
APP_BUNDLE="$PROJECT_DIR/dist/Limeghost.app"
MODULE_CACHE="$PACKAGE_DIR/.build/module-cache"
ICONSET_DIR="$PACKAGE_DIR/.build/Limeghost.iconset"
ICON_FILE="$PACKAGE_DIR/.build/Limeghost.icns"
SIGNING_IDENTITY=${LIMEGHOST_SIGNING_IDENTITY:--}

mkdir -p "$MODULE_CACHE"
STAGING_ROOT=$(mktemp -d "$PACKAGE_DIR/.build/limeghost-app-stage.XXXXXX")
STAGED_APP="$STAGING_ROOT/Limeghost.app"
CONTENTS_DIR="$STAGED_APP/Contents"
cleanup() { rm -rf "$STAGING_ROOT"; }
trap cleanup EXIT

export CLANG_MODULE_CACHE_PATH="$MODULE_CACHE"
export SWIFTPM_MODULECACHE_OVERRIDE="$MODULE_CACHE"
swift build --disable-sandbox --package-path "$PACKAGE_DIR" -c release
BUILD_DIR=$(swift build --show-bin-path --package-path "$PACKAGE_DIR" -c release)

swift "$SCRIPT_DIR/generate-app-icon.swift" "$ICONSET_DIR" "$ICON_FILE"

mkdir -p "$CONTENTS_DIR/MacOS" "$CONTENTS_DIR/Resources"
install -m 755 "$BUILD_DIR/LimeghostBrowser" "$CONTENTS_DIR/MacOS/LimeghostBrowser"
cp "$PACKAGE_DIR/App/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$PACKAGE_DIR/App/PkgInfo" "$CONTENTS_DIR/PkgInfo"
cp "$PACKAGE_DIR/App/PrivacyInfo.xcprivacy" "$CONTENTS_DIR/Resources/PrivacyInfo.xcprivacy"
cp "$ICON_FILE" "$CONTENTS_DIR/Resources/Limeghost.icns"
touch "$STAGED_APP"

plutil -lint "$CONTENTS_DIR/Info.plist"
plutil -lint "$CONTENTS_DIR/Resources/PrivacyInfo.xcprivacy"
plutil -lint "$PACKAGE_DIR/App/Limeghost.entitlements"
if [[ "$SIGNING_IDENTITY" == "-" ]]; then
    codesign --force --options runtime \
        --entitlements "$PACKAGE_DIR/App/Limeghost.entitlements" \
        --sign - "$STAGED_APP"
else
    codesign --force --options runtime --timestamp \
        --entitlements "$PACKAGE_DIR/App/Limeghost.entitlements" \
        --sign "$SIGNING_IDENTITY" "$STAGED_APP"
fi
codesign --verify --deep --strict "$STAGED_APP"
mkdir -p "$PROJECT_DIR/dist"
if [[ -L "$APP_BUNDLE" ]]; then
    echo "Refusing to replace a symlinked app bundle: $APP_BUNDLE" >&2
    exit 1
fi
PREVIOUS_APP="$STAGING_ROOT/Previous-Limeghost.app"
HAD_PREVIOUS_APP=false
if [[ -e "$APP_BUNDLE" ]]; then
    mv "$APP_BUNDLE" "$PREVIOUS_APP"
    HAD_PREVIOUS_APP=true
fi
if ! mv "$STAGED_APP" "$APP_BUNDLE"; then
    if [[ "$HAD_PREVIOUS_APP" == true ]]; then mv "$PREVIOUS_APP" "$APP_BUNDLE"; fi
    exit 1
fi
codesign --verify --deep --strict "$APP_BUNDLE"
if [[ "$SIGNING_IDENTITY" == "-" ]]; then
    echo "Built local development app (hardened runtime, ad hoc identity; not notarized): $APP_BUNDLE"
else
    echo "Built Developer ID-signed app. Notarization is a separate credentialed release step: $APP_BUNDLE"
fi
