#!/bin/zsh
# The live end-to-end pass: serve the fixtures, point the suite at them, run it.
#
# The suite itself lives in the ordinary test target
# (Tests/BrowserBehaviorTests/BrowserE2ESmokeTests.swift), so every
# `swift test` compiles it and nothing here lists source files. This script
# exists only to provide the two things a bare `swift test` cannot: a fixture
# server, and the CLEARFRAME_SMOKE_BASE_URL that unlocks the live checks.
# It needs a logged-in desktop session — the suite opens a real window and
# asserts keyboard focus, which a headless machine will fail, not skip.
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PACKAGE_DIR=${SCRIPT_DIR:h}
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

swift test --package-path "$PACKAGE_DIR" --filter BrowserE2ESmokeTests
