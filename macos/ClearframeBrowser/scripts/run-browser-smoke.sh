#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PACKAGE_DIR=${SCRIPT_DIR:h}
BUILD_DIR="$PACKAGE_DIR/.build/arm64-apple-macosx/debug"
MODULE_CACHE="$PACKAGE_DIR/.build/module-cache"
TEMP_DIR=$(mktemp -d /private/tmp/clearframe-browser-smoke.XXXXXX)
SERVER_LOG="$TEMP_DIR/server.log"

cleanup() {
    if [[ -n "${SERVER_PID:-}" ]]; then kill "$SERVER_PID" 2>/dev/null || true; fi
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

mkdir -p "$MODULE_CACHE"
export CLANG_MODULE_CACHE_PATH="$MODULE_CACHE"
export SWIFTPM_MODULECACHE_OVERRIDE="$MODULE_CACHE"
swift build --disable-sandbox --package-path "$PACKAGE_DIR"
python3 -m http.server 8765 --bind 127.0.0.1 --directory "$PACKAGE_DIR/Tests/Fixtures" >"$SERVER_LOG" 2>&1 &
SERVER_PID=$!

swiftc \
    -parse-as-library \
    -module-name ClearframeE2ESmoke \
    -I "$BUILD_DIR/Modules" \
    "$PACKAGE_DIR/Sources/ClearframeBrowser/AIConfigurationStore.swift" \
    "$PACKAGE_DIR/Sources/ClearframeBrowser/AIToolStartPage.swift" \
    "$PACKAGE_DIR/Sources/ClearframeBrowser/BrowserApplicationLifecycle.swift" \
    "$PACKAGE_DIR/Sources/ClearframeBrowser/BrowserDataStore.swift" \
    "$PACKAGE_DIR/Sources/ClearframeBrowser/DownloadCenter.swift" \
    "$PACKAGE_DIR/Sources/ClearframeBrowser/OnboardingController.swift" \
    "$PACKAGE_DIR/Sources/ClearframeBrowser/BrowserSession.swift" \
    "$PACKAGE_DIR/Sources/ClearframeBrowser/PageAssistantModel.swift" \
    "$PACKAGE_DIR/Sources/ClearframeBrowser/SearchSettingsStore.swift" \
    "$PACKAGE_DIR/Sources/ClearframeBrowser/VoiceInputController.swift" \
    "$PACKAGE_DIR/Sources/ClearframeBrowser/BrowserWorkspace.swift" \
    "$PACKAGE_DIR/Sources/ClearframeBrowser/WebView.swift" \
    "$PACKAGE_DIR/Sources/ClearframeBrowser/AssistantPanel.swift" \
    "$PACKAGE_DIR/Sources/ClearframeBrowser/BrowserView.swift" \
    "$PACKAGE_DIR/Tests/BrowserE2ESmoke.swift" \
    "$BUILD_DIR"/ClearframeCore.build/*.swift.o \
    -framework AppKit \
    -framework WebKit \
    -framework Security \
    -framework AVFoundation \
    -framework Speech \
    -o "$TEMP_DIR/clearframe-browser-e2e"

"$TEMP_DIR/clearframe-browser-e2e"
