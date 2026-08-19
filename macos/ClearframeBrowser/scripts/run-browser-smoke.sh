#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PACKAGE_DIR=${SCRIPT_DIR:h}
MODULE_CACHE="$PACKAGE_DIR/.build/module-cache"
TEMP_DIR=$(mktemp -d /private/tmp/clearframe-browser-smoke.XXXXXX)
SERVER_LOG="$TEMP_DIR/server.log"
PORT_FILE="$TEMP_DIR/server.port"

cleanup() {
    local smoke_status=$?
    if [[ -n "${SERVER_PID:-}" ]]; then kill "$SERVER_PID" 2>/dev/null || true; fi
    if (( smoke_status != 0 )) && [[ -s "$SERVER_LOG" ]]; then
        echo "Fixture server log:" >&2
        sed -n '1,120p' "$SERVER_LOG" >&2
    fi
    rm -rf "$TEMP_DIR"
    return "$smoke_status"
}
trap cleanup EXIT

mkdir -p "$MODULE_CACHE"
export CLANG_MODULE_CACHE_PATH="$MODULE_CACHE"
export SWIFTPM_MODULECACHE_OVERRIDE="$MODULE_CACHE"
swift build --disable-sandbox --package-path "$PACKAGE_DIR"
BUILD_DIR=$(swift build --show-bin-path --package-path "$PACKAGE_DIR")
python3 "$SCRIPT_DIR/fixture-server.py" \
    --directory "$PACKAGE_DIR/Tests/Fixtures" \
    --port-file "$PORT_FILE" \
    >"$SERVER_LOG" 2>&1 &
SERVER_PID=$!

for attempt in {1..50}; do
    if [[ -s "$PORT_FILE" ]]; then break; fi
    if ! kill -0 "$SERVER_PID" 2>/dev/null; then
        echo "Fixture server exited before publishing a port." >&2
        exit 1
    fi
    sleep 0.1
done

if [[ ! -s "$PORT_FILE" ]]; then
    echo "Fixture server did not publish a port." >&2
    exit 1
fi

SMOKE_PORT=$(<"$PORT_FILE")
if [[ ! "$SMOKE_PORT" =~ ^[0-9]+$ ]]; then
    echo "Fixture server published an invalid port: $SMOKE_PORT" >&2
    exit 1
fi
export CLEARFRAME_SMOKE_BASE_URL="http://127.0.0.1:$SMOKE_PORT/"
curl -fsS --retry 20 --retry-delay 0 --retry-connrefused "$CLEARFRAME_SMOKE_BASE_URL" >/dev/null

swiftc \
    -parse-as-library \
    -module-name ClearframeE2ESmoke \
    -I "$BUILD_DIR/Modules" \
    "$PACKAGE_DIR/Sources/ClearframeBrowser/AIConfigurationStore.swift" \
    "$PACKAGE_DIR/Sources/ClearframeBrowser/AIToolStartPage.swift" \
    "$PACKAGE_DIR/Sources/ClearframeBrowser/BrowserApplicationLifecycle.swift" \
    "$PACKAGE_DIR/Sources/ClearframeBrowser/BrowserDataStore.swift" \
    "$PACKAGE_DIR/Sources/ClearframeBrowser/ClearframeTheme.swift" \
    "$PACKAGE_DIR/Sources/ClearframeBrowser/IdentityColor.swift" \
    "$PACKAGE_DIR/Sources/ClearframeBrowser/FaviconStore.swift" \
    "$PACKAGE_DIR/Sources/ClearframeBrowser/ClearframeIconView.swift" \
    "$PACKAGE_DIR/Sources/ClearframeBrowser/WindowChromeSupport.swift" \
    "$PACKAGE_DIR/Sources/ClearframeBrowser/DownloadCenter.swift" \
    "$PACKAGE_DIR/Sources/ClearframeBrowser/OnboardingController.swift" \
    "$PACKAGE_DIR/Sources/ClearframeBrowser/BrowserSession.swift" \
    "$PACKAGE_DIR/Sources/ClearframeBrowser/PageAssistantModel.swift" \
    "$PACKAGE_DIR/Sources/ClearframeBrowser/SearchSettingsStore.swift" \
    "$PACKAGE_DIR/Sources/ClearframeBrowser/ContentBlockingSettingsStore.swift" \
    "$PACKAGE_DIR/Sources/ClearframeBrowser/ContentRuleListProvider.swift" \
    "$PACKAGE_DIR/Sources/ClearframeBrowser/VoiceInputController.swift" \
    "$PACKAGE_DIR/Sources/ClearframeBrowser/BrowserWorkspace.swift" \
    "$PACKAGE_DIR/Sources/ClearframeBrowser/WebView.swift" \
    "$PACKAGE_DIR/Sources/ClearframeBrowser/AssistantPanel.swift" \
    "$PACKAGE_DIR/Sources/ClearframeBrowser/BookmarkActions.swift" \
    "$PACKAGE_DIR/Sources/ClearframeBrowser/BookmarkBarViews.swift" \
    "$PACKAGE_DIR/Sources/ClearframeBrowser/BookmarkLibraryViews.swift" \
    "$PACKAGE_DIR/Sources/ClearframeBrowser/BookmarksHomePage.swift" \
    "$PACKAGE_DIR/Sources/ClearframeBrowser/DownloadViews.swift" \
    "$PACKAGE_DIR/Sources/ClearframeBrowser/ContentBlockingViews.swift" \
    "$PACKAGE_DIR/Sources/ClearframeBrowser/TabGroupPalette.swift" \
    "$PACKAGE_DIR/Sources/ClearframeBrowser/TabStripLayout.swift" \
    "$PACKAGE_DIR/Sources/ClearframeBrowser/TabStripViews.swift" \
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
